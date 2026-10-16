#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Run opt-in signed sandbox probes without replacing or starting the original app.

Start a disposable signed Store development app under /Applications and keep its
broker locked, then run:
  python3 Tests/test-store-sandbox.py --app /Applications/TEST/Keyhatch.app \
    --identity 'Apple Development: NAME (ID)' --team TEAMID \
    --allow-disposable-applications-copy

For private storage coverage, add --synthetic-private-file ABSOLUTE_PATH and
--confirm-existing-synthetic-private-file. The file must already exist under the
broker's container. The caller must establish this using the broker; this test
does not create/read private files or bypass container protection. Omission is
reported as SKIP, never as verified isolation.

The probe tests this Mac/build: denied loopback connect, App Group scratch access,
optional denied private-file open, and rejection of a correctly signed but
different client executable. It does not test App Store re-signing, every network
path, other OS versions, biometric lifecycle, or hostile code with other grants.
"""
import argparse
import os
from pathlib import Path
import plistlib
import re
import shutil
import socket
import subprocess
import tempfile


def run(arguments, timeout=60):
    result = subprocess.run(arguments, capture_output=True, timeout=timeout)
    if result.returncode:
        # Do not dump arbitrary tool/process output (including filesystem paths).
        raise RuntimeError(f"{Path(arguments[0]).name} failed (exit {result.returncode})")
    return result


def entitlements(app):
    return plistlib.loads(run(["codesign", "-d", "--entitlements", "-", "--xml", str(app)]).stdout)


def cdhash(app):
    result = run(["codesign", "-d", "--verbose=4", str(app)])
    match = re.search(rb"^CDHash=([0-9a-f]{40})$", result.stderr, re.MULTILINE)
    if not match:
        raise RuntimeError("Cannot determine native code hash")
    return match[1].decode("ascii")


def locked_status(client):
    result = run([str(client), "status"], timeout=15)
    if result.stdout.strip() != b"locked":
        raise RuntimeError("Original broker must report exactly locked")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--identity", required=True)
    parser.add_argument("--team", required=True)
    parser.add_argument("--allow-disposable-applications-copy", action="store_true", required=True)
    parser.add_argument("--synthetic-private-file", type=Path)
    parser.add_argument("--confirm-existing-synthetic-private-file", action="store_true")
    args = parser.parse_args()
    if not args.identity.startswith("Apple Development: ") or not re.fullmatch(r"[A-Z0-9]{10}", args.team):
        parser.error("Use an explicit Apple Development identity and ten-character team ID")
    app = args.app.resolve(strict=True)
    if not app.is_relative_to(Path("/Applications")) or app.suffix != ".app":
        parser.error("The original test app must be under /Applications")
    # Re-signing writes into bundle metadata. Refuse any symlink that could
    # redirect those writes from the disposable copy into another installation.
    for directory, subdirectories, files in os.walk(app, followlinks=False):
        if any((Path(directory) / name).is_symlink() for name in subdirectories + files):
            parser.error("This narrow test requires a source bundle without symlinks")
    helper_relative = Path("Contents/Helpers/KeyhatchClient.app")
    helper = app / helper_relative
    executable_relative = Path("Contents/MacOS/keyhatch")
    client = helper / executable_relative
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("KeyhatchDistribution") != "app-store" or info.get("KeyhatchTeamIdentifier") != args.team:
        parser.error("Expected a Store-channel app signed by the supplied team")
    bundle_id = info.get("CFBundleIdentifier", "")
    group = info.get("KeyhatchAppGroup", "")
    identifier_pattern = r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+"
    if (not isinstance(bundle_id, str) or not isinstance(group, str) or
            not re.fullmatch(identifier_pattern, bundle_id) or
            not re.fullmatch(identifier_pattern, group)):
        parser.error("Expected valid sealed bundle and App Group identifiers")
    original_entitlements = entitlements(app)
    client_entitlements = entitlements(helper)
    for values, identifier in ((original_entitlements, bundle_id), (client_entitlements, bundle_id + ".client")):
        if (values.get("com.apple.security.app-sandbox") is not True or
                values.get("com.apple.developer.team-identifier") != args.team or
                values.get("com.apple.application-identifier") != args.team + "." + identifier or
                values.get("com.apple.security.application-groups") != [group]):
            parser.error("Signed sandbox, team, application identifier, or App Group mismatch")
    for target in (app, helper):
        profile = plistlib.loads(run(["security", "cms", "-D", "-i",
                                     str(target / "Contents/embedded.provisionprofile")]).stdout)
        if not profile.get("ProvisionedDevices") or profile.get("TeamIdentifier") != [args.team]:
            parser.error("Use development profiles for the supplied team and this registered Mac")
    allowed_client_keys = {"com.apple.security.app-sandbox", "com.apple.security.application-groups",
                           "com.apple.developer.team-identifier", "com.apple.application-identifier"}
    if set(client_entitlements) - allowed_client_keys:
        parser.error("Client has unexpected entitlements; refuse an ambiguous sandbox test")
    private = args.synthetic_private_file
    if bool(private) != args.confirm_existing_synthetic_private_file:
        parser.error("Private-file test requires both an explicit path and existing-synthetic-file confirmation")
    if private:
        # Avoid resolving/stat-ing protected containers from the unsandboxed
        # harness; caller establishes existence. Lexically constrain the target.
        private = Path(os.path.abspath(private))
        container = Path.home() / "Library/Containers" / bundle_id / "Data"
        if not private.is_relative_to(container) or private == container:
            parser.error("Synthetic file must be inside the original broker's private Data container")
    run(["codesign", "--verify", "--strict", "--deep", "--all-architectures", str(app)])
    run([str(client), "verify-installation"], timeout=30)
    locked_status(client)
    broker_hash = cdhash(app)
    original_hash = cdhash(helper)
    source = Path(__file__).with_name("StoreSandboxProbe.swift")
    # TemporaryDirectory owns exactly this fresh directory. No caller-selected
    # destination or broad cleanup path is accepted; the original is read-only.
    with tempfile.TemporaryDirectory(prefix="KeyhatchSandboxProbe-", dir="/Applications") as generated:
        directory = Path(generated)
        probe_app = directory / "Keyhatch.app"
        shutil.copytree(app, probe_app, symlinks=True)
        probe_helper = probe_app / helper_relative
        executable = probe_helper / executable_relative
        executable.unlink()  # break any copied hard-link before compiling
        run(["xcrun", "swiftc", "-parse-as-library", "-O", str(source), "-o", str(executable)], timeout=180)
        for target, values in ((probe_helper, client_entitlements), (probe_app, original_entitlements)):
            declaration = directory / ("client.plist" if target == probe_helper else "broker.plist")
            declaration.write_bytes(plistlib.dumps(values))
            run(["codesign", "--force", "--sign", args.identity, "--options", "runtime",
                 "--timestamp=none", "--entitlements", str(declaration), str(target)])
        run(["codesign", "--verify", "--strict", "--deep", "--all-architectures", str(probe_app)])
        if cdhash(probe_helper) == original_hash or entitlements(probe_helper) != client_entitlements:
            raise RuntimeError("Probe must have a distinct hash and unchanged sandbox entitlements")
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen(2)
            listener.settimeout(3)
            port = listener.getsockname()[1]
            with socket.create_connection(("127.0.0.1", port), timeout=3):
                positive, _ = listener.accept()
                positive.close()
            print("PASS: unsandboxed loopback positive control")
            command = [str(executable), group, str(port), broker_hash]
            if private:
                command.append(str(private))
            result = subprocess.run(command, capture_output=True, timeout=20)
            # Only our fixed diagnostic messages are allowed through. Never
            # print dynamic system errors or unexpected response data.
            for line in (result.stdout + result.stderr).decode("utf-8", errors="replace").splitlines():
                if re.fullmatch(r"(?:PASS|SKIP|FAIL): [A-Za-z0-9 ()/-]+", line):
                    print(line)
            if result.returncode:
                raise RuntimeError("Signed sandbox probe failed")
        locked_status(client)
        if cdhash(app) != broker_hash or cdhash(helper) != original_hash:
            raise RuntimeError("Original bundle changed during test")
    print("PASS: original locked broker remains responsive; disposable copy removed")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.TimeoutExpired, plistlib.InvalidFileException) as error:
        if isinstance(error, RuntimeError):
            print("FAIL:", error)
        else:
            print("FAIL: test setup or execution failed (no private data logged)")
        raise SystemExit(1)
