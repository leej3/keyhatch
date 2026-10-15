#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Check release rejection with copies of a development app; never launch its UI."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
source = Path(sys.argv[1]).resolve()


def validate(app, accepted, channel="development"):
    result = subprocess.run([sys.executable, str(root / "scripts/validate-release.py"),
                             str(app), "--channel", channel], capture_output=True, text=True, timeout=30)
    assert (result.returncode == 0) == accepted, (result.returncode, result.stdout, result.stderr)


def sign(app, options="runtime", entitlements=None):
    arguments = ["codesign", "--force", "--sign", "-", "--options", options]
    if entitlements:
        arguments += ["--entitlements", str(entitlements)]
    subprocess.run(arguments + [str(app)], check=True, capture_output=True)


validate(source, True)
validate(source, False, "direct")
with tempfile.TemporaryDirectory(prefix="keyhatch-release-checks-") as directory:
    app = Path(directory) / "Keyhatch.app"
    shutil.copytree(source, app)
    policy = app / "Contents/Resources/Privacy.md"
    original = policy.read_bytes()
    policy.write_bytes(original + b"\nAltered synthetic resource.\n")
    validate(app, False)
    policy.write_bytes(original)
    sign(app)
    validate(app, True)
    sign(app, options="0")
    validate(app, False)
    unsafe = Path(directory) / "unsafe.plist"
    unsafe.write_bytes(plistlib.dumps({"com.apple.security.get-task-allow": True}))
    sign(app, entitlements=unsafe)
    validate(app, False)
    sign(app)
    # codesign preserves entitlements when re-signing unless explicitly cleared;
    # this fixture ends here rather than treating a re-sign as an entitlement reset.
print("PASS: release rejects channel mismatch, altered resources, missing runtime and debug entitlement")
