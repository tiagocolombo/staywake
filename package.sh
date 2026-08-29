#!/bin/bash
# Builds dist/StayWake-<version>.dmg — a drag-to-Applications disk image.
# Needs only the Command Line Tools: no Xcode, no Developer ID certificate.
set -euo pipefail

cd "$(dirname "$0")"

./build.sh

APP=dist/StayWake.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
VOLUME="StayWake $VERSION"
DMG="dist/StayWake-$VERSION.dmg"

echo
echo "==> Staging disk image contents"
STAGE=$(mktemp -d /tmp/staywake-dmg.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/StayWake.app"
# The symlink is what makes the window a drag-to-install target.
ln -s /Applications "$STAGE/Applications"
cp packaging/README-FIRST.txt "$STAGE/README FIRST.txt"

echo "==> Building $DMG"
rm -f "$DMG"
hdiutil create \
    -volname "$VOLUME" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -quiet \
    "$DMG"

SIZE=$(du -h "$DMG" | cut -f1)
echo
echo "Built $DMG ($SIZE)"
echo
echo "This app is ad-hoc signed, not notarized. On another Mac the first"
echo "launch must be right-click > Open — see 'README FIRST.txt' in the image."
