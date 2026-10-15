#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
# Local archive only: does not upload, register identifiers, or fetch profiles.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${KEYHATCH_TEAM:?Set your Apple Developer team ID}"
: "${KEYHATCH_BUNDLE_ID:?Set your registered broker bundle ID}"
: "${KEYHATCH_APP_GROUP:?Set the group authorized in BOTH provisioning profiles}"
: "${KEYHATCH_BROKER_PROFILE:?Set broker distribution profile specifier}"
: "${KEYHATCH_CLIENT_PROFILE:?Set client distribution profile specifier}"
[[ "$KEYHATCH_TEAM" =~ ^[A-Z0-9]{10}$ ]] || { echo 'Invalid team ID' >&2; exit 2; }
[[ "$KEYHATCH_BUNDLE_ID" != com.example.* && "$KEYHATCH_BUNDLE_ID" != local.* ]] || { echo 'Use registered identifiers' >&2; exit 2; }
xcrun --find xcodebuild >/dev/null || { echo 'Full Xcode is required; Command Line Tools cannot archive a Store app.' >&2; exit 1; }
python3 scripts/generate-xcode-project.py
mkdir -p .build/store-archives
keyhatch_archive_dir="$(mktemp -d "$PWD/.build/store-archives/build.XXXXXX")"
xcodebuild -project Keyhatch.xcodeproj -scheme 'Keyhatch Store' -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$keyhatch_archive_dir/Keyhatch.xcarchive" \
    DEVELOPMENT_TEAM="$KEYHATCH_TEAM" KEYHATCH_BUNDLE_ID="$KEYHATCH_BUNDLE_ID" \
    KEYHATCH_APP_GROUP="$KEYHATCH_APP_GROUP" KEYHATCH_BROKER_PROFILE="$KEYHATCH_BROKER_PROFILE" \
    KEYHATCH_CLIENT_PROFILE="$KEYHATCH_CLIENT_PROFILE" archive
python3 scripts/validate-release.py "$keyhatch_archive_dir/Keyhatch.xcarchive/Products/Applications/Keyhatch.app" --channel app-store
printf 'Local archive: %s\nReview/export with Xcode Organizer; no submission performed.\n' "$keyhatch_archive_dir/Keyhatch.xcarchive"
