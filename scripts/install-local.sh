#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
bash scripts/build-preview.sh
keyhatch_build="$(swift build --scratch-path .build/keyhatch --show-bin-path)"
keyhatch_root="$HOME/.local/share/keyhatch"
keyhatch_bin="$HOME/.local/bin/keyhatch"
mkdir -p "$keyhatch_root/releases" "$HOME/.local/bin"
if [[ -e "$keyhatch_bin" || -L "$keyhatch_bin" ]]; then
    [[ -L "$keyhatch_bin" && "$(readlink "$keyhatch_bin")" == "$keyhatch_root/current/keyhatch" ]] || {
        echo 'Refusing to replace an unrelated keyhatch command.' >&2; exit 1;
    }
fi
if [[ -e "$keyhatch_root/current" || -L "$keyhatch_root/current" ]]; then
    [[ -L "$keyhatch_root/current" ]] || { echo 'Current deployment is not a symlink.' >&2; exit 1; }
    printf 'Previous deployment retained: %s\n' "$(readlink "$keyhatch_root/current")"
fi
keyhatch_release="$(mktemp -d "$keyhatch_root/releases/build.XXXXXX")"
ditto '.build/Keyhatch Preview.app' "$keyhatch_release/Keyhatch.app"
cp "$keyhatch_build/KeyhatchCLI" "$keyhatch_release/keyhatch"
cp "$keyhatch_build/deployment.json" "$keyhatch_release/deployment.json"
plutil -convert xml1 "$keyhatch_release/deployment.json"
plutil -replace appPath -string "$keyhatch_release/Keyhatch.app" "$keyhatch_release/deployment.json"
plutil -convert json "$keyhatch_release/deployment.json"
chmod 700 "$keyhatch_release/keyhatch"
chmod 600 "$keyhatch_release/deployment.json"
codesign --verify --strict "$keyhatch_release/keyhatch"
codesign --verify --strict "$keyhatch_release/Keyhatch.app"
ln -s "$keyhatch_release" "$keyhatch_release/current.next"
mv -fh "$keyhatch_release/current.next" "$keyhatch_root/current"
if [[ ! -L "$keyhatch_bin" ]]; then ln -s "$keyhatch_root/current/keyhatch" "$keyhatch_bin"; fi
printf 'Installed locally: %s\nOpen: %s\n' "$keyhatch_bin" "$keyhatch_release/Keyhatch.app"
echo 'Existing Agent Vault and Git helpers are unchanged. Restart the app after updates; code pins intentionally reject mixed versions.'
