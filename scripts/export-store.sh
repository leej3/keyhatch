#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
# Local export only. Never uploads or changes developer account provisioning.
set -euo pipefail
[[ $# == 1 ]] || { echo 'Usage: export-store.sh ARCHIVE_PATH' >&2; exit 2; }
: "${KEYHATCH_TEAM:?Set your Apple Developer team ID}"
: "${KEYHATCH_BUNDLE_ID:?Set your registered broker bundle ID}"
: "${KEYHATCH_BROKER_PROFILE:?Set broker distribution profile specifier}"
: "${KEYHATCH_CLIENT_PROFILE:?Set client distribution profile specifier}"
: "${KEYHATCH_INSTALLER_IDENTITY:?Set the Mac Installer Distribution certificate common name}"
keyhatch_archive="$1"
keyhatch_scripts="$(cd "$(dirname "$0")" && pwd)"
keyhatch_root="$(dirname "$keyhatch_scripts")"
[[ -d "$keyhatch_archive/Products/Applications/Keyhatch.app" ]] || { echo 'Missing archived app' >&2; exit 2; }
mkdir -p "$keyhatch_root/.build/store-exports"
keyhatch_export="$(mktemp -d "$keyhatch_root/.build/store-exports/export.XXXXXX")"
python3 - "$keyhatch_export/options.plist" <<'PY'
import os, plistlib, sys
with open(sys.argv[1], 'wb') as stream:
    plistlib.dump({
        'method': 'app-store-connect', 'destination': 'export',
        'teamID': os.environ['KEYHATCH_TEAM'], 'signingStyle': 'manual',
        'signingCertificate': 'Apple Distribution',
        'installerSigningCertificate': os.environ['KEYHATCH_INSTALLER_IDENTITY'],
        'manageAppVersionAndBuildNumber': False, 'uploadSymbols': False,
        'provisioningProfiles': {
            os.environ['KEYHATCH_BUNDLE_ID']: os.environ['KEYHATCH_BROKER_PROFILE'],
            os.environ['KEYHATCH_BUNDLE_ID'] + '.client': os.environ['KEYHATCH_CLIENT_PROFILE']
        }
    }, stream)
PY
xcodebuild -exportArchive -archivePath "$keyhatch_archive" \
    -exportPath "$keyhatch_export/package" -exportOptionsPlist "$keyhatch_export/options.plist"
pkgutil --check-signature "$keyhatch_export/package/Keyhatch.pkg"
pkgutil --expand-full "$keyhatch_export/package/Keyhatch.pkg" "$keyhatch_export/expanded"
python3 "$keyhatch_scripts/validate-release.py" \
    "$keyhatch_export/expanded/$KEYHATCH_BUNDLE_ID.pkg/Payload/Keyhatch.app" \
    --channel app-store --static-only
shasum -a 256 "$keyhatch_export/package/Keyhatch.pkg" > "$keyhatch_export/SHA256SUMS"
printf 'Validated local installer: %s/package/Keyhatch.pkg\nNo upload or installation performed.\n' "$keyhatch_export"
