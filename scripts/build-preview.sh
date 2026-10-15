#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product Handrail
preview_binary_dir="$(swift build --show-bin-path)"
preview_bundle="$PWD/.build/Handrail Preview.app"
mkdir -p "$preview_bundle/Contents/MacOS"
cp "$preview_binary_dir/Handrail" "$preview_bundle/Contents/MacOS/Handrail"
cp Resources/Info.plist "$preview_bundle/Contents/Info.plist"
# Development-only ad-hoc signature; NOT a provisioned or distributable app.
codesign --force --sign - "$preview_bundle"
printf 'Development preview: %s\n' "$preview_bundle"
