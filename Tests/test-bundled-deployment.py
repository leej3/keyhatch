#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Exercise sealed deployment trust with temporary, synthetic ad hoc apps.

Usage: python3 Tests/test-bundled-deployment.py CLI_BINARY [IPC_FIXTURE_BINARY]
Never opens the GUI, creates/connects to a broker socket, or reads credential storage.
"""
import json
import pathlib
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile


cli = pathlib.Path(sys.argv[1]).resolve()
fixture = pathlib.Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else None


def sign(path, identifier):
    subprocess.run(
        ["/usr/bin/codesign", "--force", "--sign", "-", "--identifier", identifier, str(path)],
        check=True, capture_output=True,
    )


def verify(tool, accepted):
    result = subprocess.run([str(tool), "verify-installation"], capture_output=True, text=True, timeout=20)
    assert (result.returncode == 0) == accepted, (result.returncode, result.stdout, result.stderr)


def code_hash(tool):
    result = subprocess.run(["/usr/bin/codesign", "--display", "--verbose=4", str(tool)],
                            capture_output=True, text=True, check=True)
    return re.search(r"^CDHash=([a-f0-9]{40})$", result.stderr, re.MULTILINE).group(1)


def verify_broker(broker, tool, accepted):
    if fixture is None:
        return
    result = subprocess.run([str(broker), "bundle-pin"], capture_output=True, text=True, timeout=20)
    assert (result.returncode == 0) == accepted, (result.returncode, result.stdout, result.stderr)
    if accepted:
        assert result.stdout.strip() == code_hash(tool), result.stdout


with tempfile.TemporaryDirectory(prefix="keyhatch-deployment-checks-") as directory:
    root = pathlib.Path(directory)
    app = root / "Keyhatch.app"
    binaries = app / "Contents/MacOS"
    binaries.mkdir(parents=True)
    # The optional fixture exercises broker trust without launching the real app.
    broker = binaries / "Keyhatch"
    shutil.copy(fixture if fixture else "/usr/bin/true", broker)
    tool = binaries / "KeyhatchCLI"
    shutil.copy(cli, tool)
    info = app / "Contents/Info.plist"
    metadata = {
        "CFBundleIdentifier": "org.keyhatch.synthetic",
        "CFBundleExecutable": "Keyhatch",
        "CFBundlePackageType": "APPL",
        "KeyhatchDistribution": "development",
    }
    info.write_bytes(plistlib.dumps(metadata))
    sign(tool, "org.keyhatch.synthetic.client")
    sign(app, "org.keyhatch.synthetic")
    verify(tool, True)
    verify_broker(broker, tool, True)

    # Replacing a nested signature breaks the containing bundle's seal.
    original_pin = code_hash(tool)
    sign(tool, "org.keyhatch.synthetic.replacement")
    assert code_hash(tool) != original_pin
    verify(tool, False)
    verify_broker(broker, tool, False)
    # Re-sealing the outer app establishes the changed client build's actual pin.
    sign(app, "org.keyhatch.synthetic")
    verify(tool, True)
    verify_broker(broker, tool, True)
    sign(tool, "org.keyhatch.synthetic.client")
    sign(app, "org.keyhatch.synthetic")
    verify(tool, True)

    # A sealed resource alteration is rejected before any IPC access.
    info.write_bytes(info.read_bytes() + b"\n<!-- altered -->")
    verify(tool, False)
    verify_broker(broker, tool, False)
    info.write_bytes(plistlib.dumps(metadata))
    sign(app, "org.keyhatch.synthetic")
    verify(tool, True)

    # A development signature must not be accepted as a production identity.
    metadata["KeyhatchDistribution"] = "direct"
    metadata["KeyhatchTeamIdentifier"] = "ABCDEFGHIJ"
    info.write_bytes(plistlib.dumps(metadata))
    sign(app, "org.keyhatch.synthetic")
    verify(tool, False)
    verify_broker(broker, tool, False)

    # Missing channel metadata is not an invitation to use deployment.json.
    del metadata["KeyhatchDistribution"]
    info.write_bytes(plistlib.dumps(metadata))
    sign(app, "org.keyhatch.synthetic")
    legacy = binaries / "deployment.json"
    legacy.write_text(json.dumps({"serverHash": "a" * 40, "clientHash": code_hash(tool), "appPath": str(app)}))
    legacy.chmod(0o600)
    verify(tool, False)
    legacy.unlink()

    # Standalone preview compatibility uses a bounded private file.
    standalone = root / "standalone"
    standalone.mkdir()
    copied = standalone / "keyhatch"
    shutil.copy(cli, copied)
    sign(copied, "org.keyhatch.synthetic.client")
    client_hash = code_hash(copied)
    deployment = standalone / "deployment.json"
    deployment.write_text(json.dumps({"serverHash": "a" * 40, "clientHash": client_hash, "appPath": str(app)}))
    deployment.chmod(0o600)
    verify(copied, True)
    deployment.write_bytes(b" " * 8193)
    verify(copied, False)

print("PASS: sealed bundled CLI; tamper and ad hoc production rejection; no legacy fallback; bounded standalone preview")
if fixture:
    print("PASS: broker derives actual nested client hash; rejects tampering; adopts re-signed client only after outer re-sealing")
