#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Check release rejection with copies of a development app; never launch its UI."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import importlib.util
import platform

root = Path(__file__).resolve().parent.parent
source = Path(sys.argv[1]).resolve()
spec = importlib.util.spec_from_file_location("release_validator", root / "scripts/validate-release.py")
validator = importlib.util.module_from_spec(spec)
sys.dont_write_bytecode = True
spec.loader.exec_module(validator)


def validate(app, accepted, channel="development", *, static_only=False, expected_error=None):
    arguments = [sys.executable, str(root / "scripts/validate-release.py"), str(app), "--channel", channel]
    if static_only:
        arguments.append("--static-only")
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=60)
    assert (result.returncode == 0) == accepted, (result.returncode, result.stdout, result.stderr)
    if expected_error:
        assert expected_error in result.stderr, result.stderr


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
    declared = Path(directory) / "declared.plist"
    declared.write_bytes(plistlib.dumps({"com.apple.security.network.client": True}))
    sign(app, entitlements=declared)
    _, parsed = validator.inspect(app)
    assert parsed == {"com.apple.security.network.client": True}, parsed
    validate(app, False)
    unsafe = Path(directory) / "unsafe.plist"
    unsafe.write_bytes(plistlib.dumps({"com.apple.security.get-task-allow": True}))
    sign(app, entitlements=unsafe)
    validate(app, False)
    sign(app)
    # codesign preserves entitlements when re-signing unless explicitly cleared;
    # this fixture ends here rather than treating a re-sign as an entitlement reset.

# A universal helper can have individually valid signatures but different
# policies in its non-native slice. Static validation must inspect both slices.
# The tiny helper is deliberately never executed; no signing keys are needed.
with tempfile.TemporaryDirectory(prefix="keyhatch-universal-checks-") as directory:
    directory = Path(directory)
    app = directory / "Keyhatch.app"
    shutil.copytree(source, app)
    bundle_id = plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleIdentifier"]
    fixture_source = directory / "probe.c"
    fixture_source.write_text("int main(void) { return 0; }\n")
    universal = directory / "universal"
    subprocess.run(["xcrun", "clang", "-arch", "arm64", "-arch", "x86_64",
                    "-mmacosx-version-min=14.0", str(fixture_source), "-o", str(universal)],
                   check=True, capture_output=True)
    native = platform.machine()
    assert native in ("arm64", "x86_64"), native
    other = "x86_64" if native == "arm64" else "arm64"
    declared = directory / "network.plist"
    declared.write_bytes(plistlib.dumps({"com.apple.security.network.client": True}))
    client = app / "Contents/MacOS/KeyhatchCLI"

    def universal_fixture(*, unexpected_entitlement=False, missing_runtime=False, wrong_identifier=False):
        slices = []
        for architecture in (native, other):
            path = directory / architecture
            subprocess.run(["lipo", str(universal), "-thin", architecture, "-output", str(path)],
                           check=True, capture_output=True)
            identifier = bundle_id + ".client"
            if architecture == other and wrong_identifier:
                identifier += ".unexpected"
            options = "0" if architecture == other and missing_runtime else "runtime"
            arguments = ["codesign", "--force", "--sign", "-", "--options", options,
                         "--identifier", identifier]
            if architecture == other and unexpected_entitlement:
                arguments += ["--entitlements", str(declared)]
            subprocess.run(arguments + [str(path)], check=True, capture_output=True)
            slices.append(str(path))
        subprocess.run(["lipo", "-create", *slices, "-output", str(client)], check=True, capture_output=True)
        sign(app)
        subprocess.run(["codesign", "--verify", "--strict", "--deep", "--all-architectures", str(app)],
                       check=True, capture_output=True)
        _, native_entitlements = validator.inspect(client, native)
        assert native_entitlements == {}, native_entitlements

    universal_fixture()
    validate(app, True, static_only=True)
    universal_fixture(unexpected_entitlement=True)
    validate(app, False, static_only=True, expected_error="Development signing mismatch")
    universal_fixture(missing_runtime=True)
    validate(app, False, static_only=True, expected_error="Hardened Runtime missing")
    universal_fixture(wrong_identifier=True)
    validate(app, False, static_only=True, expected_error="Code identifier mismatch")
print("PASS: entitlement extraction; release rejects channel/resource/signing failures and non-native slice policy mismatches")
