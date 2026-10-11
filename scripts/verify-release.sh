#!/bin/bash
# Verify the artifact that will actually be packaged, not just the Xcode inputs.
set -euo pipefail
app_path=${1:?Usage: verify-release.sh /path/to/CopyShot.app [vMAJOR.MINOR]}
codesign --verify --deep --strict --verbose=2 "$app_path"
task_dir=$(mktemp -d)
trap 'rm -rf "$task_dir"' EXIT
codesign --display --entitlements - --xml "$app_path" > "$task_dir/entitlements.plist"
python3 - "$app_path" "$task_dir/entitlements.plist" "${2:-}" "$(dirname "$0")/../docs/appcast.xml" <<'PY'
import pathlib, plistlib, sys, xml.etree.ElementTree as ET
app, entitlements, tag, feed_path = sys.argv[1:]
with open(entitlements, 'rb') as f:
    privileges = plistlib.load(f)
with open(pathlib.Path(app) / 'Contents/Info.plist', 'rb') as f:
    info = plistlib.load(f)
for key in ('com.apple.security.app-sandbox', 'com.apple.security.network.client',
            'com.apple.security.files.user-selected.read-write'):
    assert privileges.get(key) is True, f'Missing required entitlement: {key}'
assert not privileges.get('com.apple.security.get-task-allow'), 'Debugging entitlement in release'
bundle_id = info['CFBundleIdentifier']
required = {bundle_id + '-spks', bundle_id + '-spki'}
assert required <= set(privileges.get('com.apple.security.temporary-exception.mach-lookup.global-name', [])), 'Missing Sparkle communication entitlements'
assert info.get('SUEnableInstallerLauncherService') is True, 'Sparkle installer service disabled'
version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
assert build.isdecimal(), 'Use a positive, monotonically increasing integer build number'
feed = pathlib.Path(feed_path)
if feed.exists():
    released = [int(node.text) for node in ET.parse(feed).iter('{http://www.andymatuschak.org/xml-namespaces/sparkle}version')]
    assert int(build) > max(released, default=0), 'Build number must exceed every published appcast build'
if tag:
    assert tag == 'v' + version, f'Tag {tag} does not match app version {version}'
for notice in ('CopyShot-LICENSE.txt', 'Sparkle-LICENSE.txt', 'ONNXRuntime-LICENSE.txt', 'ThirdPartyNotices.txt'):
    assert (pathlib.Path(app) / 'Contents/Resources' / notice).is_file(), f'Missing notice: {notice}'
print(f'Verified CopyShot {version} (build {build}): sandbox, Sparkle, notices, signature')
PY
