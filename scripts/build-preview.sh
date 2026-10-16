#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --scratch-path .build/keyhatch --product Keyhatch
swift build --scratch-path .build/keyhatch --product KeyhatchCLI
preview_binary_dir="$(swift build --scratch-path .build/keyhatch --show-bin-path)"
preview_bundle="$PWD/.build/Keyhatch Preview.app"
mkdir -p "$preview_bundle/Contents/MacOS"
mkdir -p "$preview_bundle/Contents/Resources"
cp "$preview_binary_dir/Keyhatch" "$preview_bundle/Contents/MacOS/Keyhatch"
cp Resources/Info.plist "$preview_bundle/Contents/Info.plist"
cp LICENSE "$preview_bundle/Contents/Resources/LICENSE"
cp Resources/Keyhatch.icns "$preview_bundle/Contents/Resources/Keyhatch.icns"
# Hardened ad-hoc builds for a local pilot; not provisioned/notarized for distribution.
codesign --force --options runtime --sign - --identifier local.keyhatch.cli "$preview_binary_dir/KeyhatchCLI"
preview_client_hash="$(codesign -d --verbose=4 "$preview_binary_dir/KeyhatchCLI" 2>&1 | awk -F= '/^CDHash=/{print $2}')"
[[ "$preview_client_hash" =~ ^[0-9a-f]{40}$ ]]
/usr/libexec/PlistBuddy -c "Add :KeyhatchClientCDHash string $preview_client_hash" "$preview_bundle/Contents/Info.plist"
codesign --force --options runtime --sign - "$preview_bundle"
preview_server_hash="$(codesign -d --verbose=4 "$preview_bundle" 2>&1 | awk -F= '/^CDHash=/{print $2}')"
[[ "$preview_server_hash" =~ ^[0-9a-f]{40}$ ]]
plutil -create xml1 "$preview_binary_dir/deployment.json"
plutil -insert serverHash -string "$preview_server_hash" "$preview_binary_dir/deployment.json"
plutil -insert clientHash -string "$preview_client_hash" "$preview_binary_dir/deployment.json"
plutil -insert appPath -string "$preview_bundle" "$preview_binary_dir/deployment.json"
plutil -convert json "$preview_binary_dir/deployment.json"
chmod 600 "$preview_binary_dir/deployment.json"
printf 'Development preview: %s\n' "$preview_bundle"
