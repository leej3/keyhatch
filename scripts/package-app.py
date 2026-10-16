#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Build a fresh self-contained direct/development app; never install or upload it."""
import argparse
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--channel", choices=("development", "direct"), default="development")
    parser.add_argument("--identity", help="Developer ID Application identity; never a password")
    parser.add_argument("--team", help="10-character Apple Developer team ID")
    parser.add_argument("--bundle-id", default="local.keyhatch.distribution")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", args.bundle_id):
        parser.error("Invalid bundle identifier")
    if args.channel == "direct":
        if not args.identity or not re.fullmatch(r"[A-Z0-9]{10}", args.team or ""):
            parser.error("Direct signing requires --identity and --team")
        if args.bundle_id.startswith(("local.", "com.example.")):
            parser.error("Direct signing requires your registered --bundle-id")
    elif args.identity or args.team:
        parser.error("Development packages use ad-hoc signing only")

    scratch = ROOT / ".build/distribution-build"
    build = ["swift", "build", "--scratch-path", str(scratch), "--configuration", "release"]
    if args.channel == "direct":
        build += ["--arch", "arm64", "--arch", "x86_64"]
    run(*build, cwd=ROOT)
    binaries = Path(subprocess.check_output(build + ["--show-bin-path"], cwd=ROOT, text=True).strip())
    output = ROOT / ".build/packages"
    output.mkdir(parents=True, exist_ok=True)
    release = Path(tempfile.mkdtemp(prefix=args.channel + "-", dir=output))
    app = release / "Keyhatch.app"
    macos = app / "Contents/MacOS"
    resources = app / "Contents/Resources"
    macos.mkdir(parents=True)
    resources.mkdir()
    for source, name in (("Keyhatch", "Keyhatch"), ("KeyhatchCLI", "KeyhatchCLI"),
                         ("KeyhatchImport", "KeyhatchImport")):
        shutil.copy2(binaries / source, macos / name)
    for source in ("Resources/Privacy.md", "Resources/PrivacyInfo.xcprivacy", "Resources/Keyhatch.icns", "LICENSE"):
        shutil.copy2(ROOT / source, resources / Path(source).name)
    with (ROOT / "Resources/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    info.update(CFBundleIdentifier=args.bundle_id, CFBundleName="Keyhatch",
                KeyhatchDistribution=args.channel, NSHighResolutionCapable=True)
    if args.team:
        info["KeyhatchTeamIdentifier"] = args.team
    with (app / "Contents/Info.plist").open("wb") as stream:
        plistlib.dump(info, stream)
    signing = ["codesign", "--force", "--options", "runtime", "--sign", args.identity or "-"]
    if args.channel == "direct":
        signing.append("--timestamp")
    # Sign nested code first. Never use --deep to sign an unknown bundle tree.
    run(*signing, "--identifier", args.bundle_id + ".client", macos / "KeyhatchCLI")
    run(*signing, "--identifier", args.bundle_id + ".import", macos / "KeyhatchImport")
    run(*signing, app)
    run("python3", ROOT / "scripts/validate-release.py", app, "--channel", args.channel)
    print(app)
    print("Built only. Existing installation and credential routing are unchanged.")


if __name__ == "__main__":
    main()
