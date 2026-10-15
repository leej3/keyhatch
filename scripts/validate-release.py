#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Fail closed on incomplete/mismatched release packages. Does not install or upload."""
import argparse
import datetime
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile


def command(*args):
    return subprocess.run([str(arg) for arg in args], check=True, capture_output=True)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_plist(path):
    with path.open("rb") as stream:
        return plistlib.load(stream)


def inspect(path):
    command("codesign", "--verify", "--strict", "--all-architectures", "--deep", path)
    detail = command("codesign", "-d", "--verbose=4", path).stderr.decode()
    flags = re.search(r"flags=0x([0-9a-fA-F]+)", detail)
    require(flags is not None and int(flags[1], 16) & 0x10000, "Hardened Runtime missing: " + path.name)
    result = command("codesign", "-d", "--entitlements", "-", path)
    entitlements = plistlib.loads(result.stdout) if result.stdout.strip() else {}
    forbidden = {"com.apple.security.get-task-allow", "com.apple.security.inherit",
                 "com.apple.security.cs.disable-library-validation",
                 "com.apple.security.cs.allow-jit", "com.apple.security.cs.allow-unsigned-executable-memory",
                 "com.apple.security.cs.allow-dyld-environment-variables"}
    require(not any(entitlements.get(key) for key in forbidden), "Unsafe signing entitlement")
    return detail, entitlements


def profile_matches(app, bundle_id, team, group):
    profile = app / "Contents/embedded.provisionprofile"
    require(profile.is_file(), "Missing embedded distribution provisioning profile: " + app.name)
    data = plistlib.loads(command("security", "cms", "-D", "-i", profile).stdout)
    require(team in data.get("TeamIdentifier", []), "Provisioning team mismatch")
    require("OSX" in data.get("Platform", []), "Expected a macOS provisioning profile")
    require(not data.get("ProvisionedDevices") and not data.get("ProvisionsAllDevices"),
            "Expected an App Store distribution profile")
    expiry = data.get("ExpirationDate")
    require(isinstance(expiry, datetime.datetime) and expiry > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
            "Provisioning profile expired")
    entitlements = data.get("Entitlements", {})
    require(entitlements.get("com.apple.application-identifier") == team + "." + bundle_id,
            "Provisioning application identifier mismatch")
    require(group in entitlements.get("com.apple.security.application-groups", []), "Group not provisioned")
    require(not entitlements.get("get-task-allow", False) and
            not entitlements.get("com.apple.security.get-task-allow", False), "Development profile in release")
    with tempfile.TemporaryDirectory(prefix="keyhatch-cert-check-") as directory:
        prefix = Path(directory) / "signer"
        command("codesign", "-d", "--extract-certificates", prefix, app)
        leaf = Path(str(prefix) + "0").read_bytes()
        require(leaf in data.get("DeveloperCertificates", []), "Signer is not authorized by profile")


def validate(app, channel):
    require(app.is_dir() and app.suffix == ".app", "Expected an app bundle")
    info = read_plist(app / "Contents/Info.plist")
    require(info.get("KeyhatchDistribution") == channel, "Distribution mismatch")
    bundle_id = info.get("CFBundleIdentifier", "")
    require(re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle_id), "Invalid bundle identifier")
    resources = app / "Contents/Resources"
    require((resources / "Privacy.md").is_file() and (resources / "LICENSE").is_file(),
            "Missing privacy policy or license")
    privacy = read_plist(resources / "PrivacyInfo.xcprivacy")
    require(privacy.get("NSPrivacyTracking") is False and privacy.get("NSPrivacyCollectedDataTypes") == [],
            "Unexpected privacy declaration")
    client_app = app / "Contents/Helpers/KeyhatchClient.app"
    client = (client_app / "Contents/MacOS/keyhatch" if channel == "app-store"
              else app / "Contents/MacOS/KeyhatchCLI")
    require(client.is_file() and not client.is_symlink(), "Missing embedded client")
    items = [(app, bundle_id, "broker"), (client_app if channel == "app-store" else client,
                                         bundle_id + ".client", "client")]
    if channel != "app-store":
        importer = app / "Contents/MacOS/KeyhatchImport"
        require(importer.is_file(), "Missing direct importer")
        items.append((importer, bundle_id + ".import", "importer"))
    else:
        require(not (app / "Contents/MacOS/KeyhatchImport").exists(), "Legacy importer in Store package")
        require(not (app / "Contents/MacOS/KeyhatchCLI").exists(), "Unsandboxed client in Store package")
    team = info.get("KeyhatchTeamIdentifier", "")
    if channel != "development":
        require(re.fullmatch(r"[A-Z0-9]{10}", team), "Missing developer team")
        require(not bundle_id.startswith(("local.", "com.example.")), "Placeholder bundle identifier")
    for path, identifier, role in items:
        detail, entitlements = inspect(path)
        require("Identifier=" + identifier + "\n" in detail, "Code identifier mismatch: " + role)
        if channel == "development":
            require("Signature=adhoc" in detail and not entitlements, "Development signing mismatch")
            continue
        require("TeamIdentifier=" + team + "\n" in detail, "Code team mismatch: " + role)
        requirement = "anchor apple generic"
        if channel == "direct":
            requirement += (' and certificate leaf[subject.OU] = "' + team +
                            '" and certificate 1[field.1.2.840.113635.100.6.2.6] exists'
                            ' and certificate leaf[field.1.2.840.113635.100.6.1.13] exists')
            require("Timestamp=" in detail, "Missing secure signing timestamp")
            require(not entitlements, "Unexpected direct-channel entitlement")
        else:
            require(any("Authority=" + prefix in detail for prefix in
                        ("Apple Distribution:", "3rd Party Mac Developer Application:", "Mac App Distribution:")),
                    "Expected a Mac App Store distribution signing identity")
            group = info.get("KeyhatchAppGroup", "")
            require(bool(group) and "$" not in group, "Unresolved App Group")
            require(entitlements.get("com.apple.security.app-sandbox") is True, "Sandbox missing")
            require(entitlements.get("com.apple.security.application-groups") == [group], "Group mismatch")
            allowed = {"com.apple.security.app-sandbox", "com.apple.security.application-groups",
                       "com.apple.application-identifier", "com.apple.developer.team-identifier"}
            if role == "broker":
                allowed.add("com.apple.security.network.client")
                require(entitlements.get("com.apple.security.network.client") is True, "HTTPS entitlement missing")
            require(set(entitlements) <= allowed, "Unexpected Store entitlement: " + role)
            profile_matches(path, identifier, team, group)
        command("codesign", "--verify", "--strict", "--all-architectures", "-R=" + requirement, path)
    # This command validates the executing client's relationship to its sealed
    # containing app. It never connects to the broker or reads credentials.
    command(client, "verify-installation")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--channel", required=True, choices=("development", "direct", "app-store"))
    args = parser.parse_args()
    try:
        validate(args.app.resolve(), args.channel)
    except (ValueError, OSError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        # No credentials or profile contents belong in release diagnostics.
        parser.exit(1, "Release validation failed: " + (str(error) if isinstance(error, ValueError)
                                                       else type(error).__name__) + "\n")
    print("PASS: signed package, identity, entitlements, privacy and embedded client validation")


if __name__ == "__main__":
    main()
