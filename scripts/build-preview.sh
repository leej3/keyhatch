#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --scratch-path .build/keyhatch --product Keyhatch
preview_binary_dir="$(swift build --scratch-path .build/keyhatch --show-bin-path)"
preview_bundle="$PWD/.build/Keyhatch Preview.app"
mkdir -p "$preview_bundle/Contents/MacOS"
mkdir -p "$preview_bundle/Contents/Resources"
cp "$preview_binary_dir/Keyhatch" "$preview_bundle/Contents/MacOS/Keyhatch"
cp Resources/Info.plist "$preview_bundle/Contents/Info.plist"
cp LICENSE "$preview_bundle/Contents/Resources/LICENSE"
# Development-only ad-hoc signature; NOT a provisioned or distributable app.
codesign --force --sign - "$preview_bundle"
printf 'Development preview: %s\n' "$preview_bundle"
