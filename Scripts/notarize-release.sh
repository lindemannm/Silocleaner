#!/bin/bash
# Archives, verifies, notarizes, staples, and re-verifies a Developer-ID build.
# Credentials stay in a locally configured notarytool keychain profile.

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 NOTARYTOOL_KEYCHAIN_PROFILE /absolute/path/to/export-directory" >&2
    exit 64
fi

profile="$1"
export_directory="$2"
if [[ ! -d "$export_directory" ]]; then
    echo "Export directory does not exist: $export_directory" >&2
    exit 66
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
archive_path="$export_directory/Silocleaner.xcarchive"
app_path="$archive_path/Products/Applications/Silocleaner.app"
zip_path="$export_directory/Silocleaner-notarization.zip"

if [[ -e "$archive_path" || -e "$zip_path" ]]; then
    echo "Refusing to overwrite an existing archive or submission ZIP in $export_directory" >&2
    exit 73
fi

xcodebuild \
    -project "$repo_root/Silocleaner.xcodeproj" \
    -scheme 'Silocleaner Release' \
    -configuration Release \
    -archivePath "$archive_path" \
    archive

/bin/bash "$repo_root/Scripts/resign-sparkle-components.sh" "$app_path"
"$repo_root/Scripts/verify-release-bundle.sh" "$app_path"

/usr/bin/ditto -c -k --keepParent "$app_path" "$zip_path"
xcrun notarytool submit "$zip_path" --keychain-profile "$profile" --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=4 "$app_path"
"$repo_root/Scripts/verify-release-bundle.sh" "$app_path"

echo "Notarized release archive is ready: $archive_path"
