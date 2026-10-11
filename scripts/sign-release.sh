#!/bin/bash
# Re-sign a built Release app inside out, retaining its sandbox privileges.
set -euo pipefail
app_path=${1:?Usage: sign-release.sh /path/to/CopyShot.app [identity]}
identity=${2:--}
signing_options=(--force --sign "$identity")
# Hardened runtime library validation requires a shared Team ID. Ad-hoc
# binaries have none, so enabling it would prevent embedded frameworks loading.
if [ "$identity" != "-" ]; then signing_options+=(--options runtime); fi
task_dir=$(mktemp -d)
trap 'rm -rf "$task_dir"' EXIT
entitlements="$task_dir/entitlements.plist"
codesign --display --entitlements - --xml "$app_path" > "$entitlements"
plutil -lint "$entitlements"
# Development build products can carry this; distribution products must not.
/usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' "$entitlements" 2>/dev/null || true

sparkle="$app_path/Contents/Frameworks/Sparkle.framework"
codesign "${signing_options[@]}" "$sparkle/Versions/B/XPCServices/Installer.xpc"
codesign "${signing_options[@]}" --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
codesign "${signing_options[@]}" "$sparkle/Versions/B/Autoupdate"
codesign "${signing_options[@]}" "$sparkle/Versions/B/Updater.app"
for framework in "$app_path"/Contents/Frameworks/*.framework; do
    codesign "${signing_options[@]}" "$framework"
done
codesign "${signing_options[@]}" --entitlements "$entitlements" "$app_path"
"$(dirname "$0")/verify-release.sh" "$app_path"
