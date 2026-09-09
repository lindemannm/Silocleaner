#!/bin/bash
# Archives, verifies, notarizes, staples, and re-verifies a Developer-ID build
# and its drag-to-Applications disk image.
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
dmg_path="$export_directory/Silocleaner.dmg"

if [[ -e "$archive_path" || -e "$zip_path" || -e "$dmg_path" ]]; then
    echo "Refusing to overwrite an existing archive, submission ZIP, or DMG in $export_directory" >&2
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

app_executable="$app_path/Contents/MacOS/Silocleaner"
identity="$(/usr/bin/codesign -dvv "$app_executable" 2>&1 | /usr/bin/awk -F= '/^Authority=Developer ID Application:/{ print $2; exit }')"
if [[ -z "$identity" ]]; then
    echo "App is not signed with a Developer ID Application identity." >&2
    exit 1
fi

dmg_staging="$(mktemp -d "${TMPDIR:-/tmp}/silocleaner-dmg.XXXXXX")"
trap 'rm -rf "$dmg_staging"' EXIT
/usr/bin/ditto "$app_path" "$dmg_staging/Silocleaner.app"
/bin/ln -s /Applications "$dmg_staging/Applications"
/usr/bin/hdiutil create \
    -volname "Silocleaner" \
    -srcfolder "$dmg_staging" \
    -format UDZO \
    -ov "$dmg_path"
/usr/bin/codesign --force --sign "$identity" --timestamp \
    --identifier "com.lindemannm.Silocleaner.dmg" "$dmg_path"
xcrun notarytool submit "$dmg_path" --keychain-profile "$profile" --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg_path"

echo "Notarized release DMG is ready: $dmg_path"
