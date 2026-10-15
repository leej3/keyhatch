#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
# Explicit release operation only. Uses a preconfigured Keychain notary profile.
set -euo pipefail
[[ $# == 2 ]] || { echo 'Usage: notarize-direct.sh APP_PATH KEYCHAIN_PROFILE' >&2; exit 2; }
keyhatch_app="$1"
keyhatch_profile="$2"
keyhatch_scripts="$(cd "$(dirname "$0")" && pwd)"
python3 "$keyhatch_scripts/validate-release.py" "$keyhatch_app" --channel direct
keyhatch_notary_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyhatch-notary.XXXXXX")"
printf 'Notary evidence directory: %s\n' "$keyhatch_notary_dir"
ditto -c -k --keepParent "$keyhatch_app" "$keyhatch_notary_dir/submission.zip"
# Retain the result and submission identifier, including failures, for review.
xcrun notarytool submit "$keyhatch_notary_dir/submission.zip" \
    --keychain-profile "$keyhatch_profile" --wait --output-format json > "$keyhatch_notary_dir/result.json"
python3 - "$keyhatch_notary_dir/result.json" <<'PY'
import json, sys
with open(sys.argv[1]) as stream:
    result = json.load(stream)
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization not accepted; inspect retained result and request the notary log.')
PY
xcrun stapler staple "$keyhatch_app"
xcrun stapler validate "$keyhatch_app"
spctl --assess --type execute --verbose=2 "$keyhatch_app"
printf 'Accepted and stapled. Notary evidence retained: %s\n' "$keyhatch_notary_dir"
