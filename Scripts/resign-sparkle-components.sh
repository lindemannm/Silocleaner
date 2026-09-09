#!/bin/bash
# Sparkle distributes nested executables with its own signatures. A direct
# Developer ID release must re-sign each one with this product's identity and
# a secure timestamp, then re-seal the outer app.

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /absolute/path/to/Silocleaner.app" >&2
    exit 64
fi

app_path="$1"
if [[ ! -d "$app_path" ]]; then
    echo "Not an application bundle: $app_path" >&2
    exit 66
fi
app_path="$(cd "$app_path" && pwd -P)"
app_executable="$app_path/Contents/MacOS/Silocleaner"
identity="$(/usr/bin/codesign -dvv "$app_executable" 2>&1 | /usr/bin/awk -F= '/^Authority=Developer ID Application:/{ print $2; exit }')"
framework_root="$app_path/Contents/Frameworks/Sparkle.framework"

if [[ -z "$identity" ]]; then
    echo "App is not signed with a Developer ID Application identity." >&2
    exit 1
fi
if [[ ! -d "$framework_root" ]]; then
    echo "Embedded Sparkle framework is missing: $framework_root" >&2
    exit 1
fi

sign() {
    /usr/bin/codesign --force --sign "$identity" --options runtime --timestamp "$1"
}

version_root="$framework_root/Versions/B"
sign "$version_root/Autoupdate"
sign "$version_root/Updater.app"
sign "$version_root/XPCServices/Downloader.xpc"
sign "$version_root/XPCServices/Installer.xpc"
sign "$framework_root"

app_entitlements="$(mktemp "${TMPDIR:-/tmp}/silocleaner-app-entitlements.XXXXXX")"
trap 'rm -f "$app_entitlements"' EXIT
/usr/bin/codesign -d --entitlements :- "$app_executable" > "$app_entitlements" 2>/dev/null
/usr/bin/codesign --force --sign "$identity" --options runtime --timestamp --entitlements "$app_entitlements" "$app_path"
