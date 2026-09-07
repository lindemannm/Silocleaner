#!/bin/bash
# Verifies the signed, exported direct-distribution bundle before and after
# notarization.  This deliberately checks every executable separately instead
# of relying on codesign --deep, which can hide a bad nested signature.

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
finder_extension="$app_path/Contents/PlugIns/FinderOpen.appex"
finder_executable="$finder_extension/Contents/MacOS/FinderOpen"
helper_plist="$app_path/Contents/Library/LaunchDaemons/com.lindemannm.Silocleaner.SilocleanerHelper.plist"
helper_executable="$app_path/Contents/MacOS/SilocleanerHelper"
sentinel_plist="$app_path/Contents/Library/LaunchAgents/com.lindemannm.SilocleanerSentinel.plist"
sentinel_executable="$app_path/Contents/MacOS/SilocleanerSentinel"

require_path() {
    if [[ ! -e "$1" ]]; then
        echo "Required release component is missing: $1" >&2
        exit 65
    fi
}

require_value() {
    local actual="$1"
    local expected="$2"
    local label="$3"
    if [[ "$actual" != "$expected" ]]; then
        echo "$label is '$actual'; expected '$expected'" >&2
        exit 65
    fi
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

check_signature() {
    local component="$1"
    echo "Checking signature: $component"
    /usr/bin/codesign --verify --strict --verbose=4 "$component"
}

team_identifier() {
    /usr/bin/codesign -dvv "$1" 2>&1 | /usr/bin/awk -F= '/^TeamIdentifier=/{ print $2; exit }'
}

check_entitlements() {
    local component="$1"
    local expected="$2"
    local raw_entitlements entitlement_file normalized_expected normalized_actual
    raw_entitlements="$(mktemp "${TMPDIR:-/tmp}/silocleaner-entitlements-raw.XXXXXX")"
    entitlement_file="$(mktemp "${TMPDIR:-/tmp}/silocleaner-entitlements.XXXXXX")"
    normalized_expected="$(mktemp "${TMPDIR:-/tmp}/silocleaner-entitlements-expected.XXXXXX")"
    normalized_actual="$(mktemp "${TMPDIR:-/tmp}/silocleaner-entitlements-actual.XXXXXX")"
    /usr/bin/codesign -d --entitlements :- "$component" > "$entitlement_file" 2> "$raw_entitlements"
    if ! /usr/bin/plutil -lint "$entitlement_file" >/dev/null; then
        echo "Could not read entitlements for $component" >&2
        rm -f "$raw_entitlements" "$entitlement_file" "$normalized_expected" "$normalized_actual"
        exit 65
    fi
    /usr/bin/plutil -convert binary1 -o "$normalized_expected" "$expected"
    /usr/bin/plutil -convert binary1 -o "$normalized_actual" "$entitlement_file"
    if ! /usr/bin/cmp -s "$normalized_expected" "$normalized_actual"; then
        /usr/bin/plutil -p "$expected"
        /usr/bin/plutil -p "$entitlement_file"
        echo "Entitlements differ from the reviewed release policy: $component" >&2
        rm -f "$raw_entitlements" "$entitlement_file" "$normalized_expected" "$normalized_actual"
        exit 65
    fi
    rm -f "$raw_entitlements" "$entitlement_file" "$normalized_expected" "$normalized_actual"
}

for component in "$app_path" "$app_executable" "$finder_extension" "$finder_executable" "$helper_executable" "$sentinel_executable" "$helper_plist" "$sentinel_plist"; do
    require_path "$component"
done

require_value "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")" \
    "com.lindemannm.Silocleaner" "Main app bundle identifier"
require_value "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$finder_extension/Contents/Info.plist")" \
    "com.lindemannm.Silocleaner.FinderOpen" "Finder extension bundle identifier"
require_value "$(plist_value "$helper_plist" Label)" \
    "com.lindemannm.Silocleaner.SilocleanerHelper" "Helper launchd label"
require_value "$(plist_value "$helper_plist" AssociatedBundleIdentifiers:0)" \
    "com.lindemannm.Silocleaner" "Helper associated bundle identifier"
require_value "$(plist_value "$sentinel_plist" Label)" \
    "com.lindemannm.SilocleanerSentinel" "Sentinel launchd label"
require_value "$(plist_value "$sentinel_plist" AssociatedBundleIdentifiers:0)" \
    "com.lindemannm.Silocleaner" "Sentinel associated bundle identifier"

for component in "$app_path" "$app_executable" "$finder_extension" "$finder_executable" "$helper_executable" "$sentinel_executable"; do
    check_signature "$component"
done

release_team="$(team_identifier "$app_executable")"
if [[ -z "$release_team" || "$release_team" == "not set" ]]; then
    echo "Main app is not signed by an Apple Developer team" >&2
    exit 65
fi
for component in "$finder_executable" "$helper_executable" "$sentinel_executable"; do
    require_value "$(team_identifier "$component")" "$release_team" "Signing team for $component"
done

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
check_entitlements "$app_executable" "$repo_root/Silocleaner/Resources/Silocleaner.entitlements"
check_entitlements "$finder_executable" "$repo_root/FinderOpen/FinderOpen.entitlements"

# The helper and Sentinel intentionally have no entitlements.  codesign emits
# an empty plist for both, which is checked explicitly to catch a future broad
# exception or accidental application-group grant.
check_entitlements "$helper_executable" "$repo_root/Silocleaner/Config/NoEntitlements.entitlements"
check_entitlements "$sentinel_executable" "$repo_root/Silocleaner/Config/NoEntitlements.entitlements"

echo "Release bundle verification passed: $app_path"
