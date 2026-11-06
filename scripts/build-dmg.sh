#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Blox.app
"$(dirname "$0")/build-app.sh"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/Blox.app"
ln -s /Applications "$STAGE/Applications"

DMG="build/Blox-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Blox $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "--- dmg: $DMG ---"
