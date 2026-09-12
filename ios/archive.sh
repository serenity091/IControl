#!/bin/bash
# Archive only: this script never runs tests or uploads to App Store Connect.
set -euo pipefail
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Developer Program team ID}"
: "${ICONTROL_BUNDLE_ID:?Set ICONTROL_BUNDLE_ID to the identifier registered in App Store Connect}"
: "${BUILD_NUMBER:?Set BUILD_NUMBER to an unused App Store Connect build number}"
: "${PHONE_CONTROLLER_PRIVACY_URL:?Set the public HTTPS privacy policy URL}"
: "${PHONE_CONTROLLER_SUPPORT_URL:?Set the public HTTPS support URL}"
for release_url in "$PHONE_CONTROLLER_PRIVACY_URL" "$PHONE_CONTROLLER_SUPPORT_URL"; do
    case "$release_url" in https://?*) ;; *) echo 'Release URLs must use HTTPS.' >&2; exit 1 ;; esac
done
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
archive_path="${ARCHIVE_PATH:-$project_dir/../build/Phone Controller.xcarchive}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
exec xcodebuild -project "$project_dir/IControl.xcodeproj" -scheme IControl \
    -configuration Release -destination 'generic/platform=iOS' \
    -archivePath "$archive_path" DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    ICONTROL_BUNDLE_ID="$ICONTROL_BUNDLE_ID" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    MARKETING_VERSION="${MARKETING_VERSION:-1.0}" \
    PHONE_CONTROLLER_PRIVACY_URL="$PHONE_CONTROLLER_PRIVACY_URL" \
    PHONE_CONTROLLER_SUPPORT_URL="$PHONE_CONTROLLER_SUPPORT_URL" \
    -allowProvisioningUpdates archive
