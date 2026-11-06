#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf build
swift build -c release --product blox

APP=build/Blox.app
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/blox" "$APP/Contents/MacOS/blox"
if [ -d ".build/release/blox_blox.bundle" ]; then
    mkdir -p "$APP/Contents/Resources"
    cp -R ".build/release/blox_blox.bundle" "$APP/Contents/Resources/"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>blox</string>
    <key>CFBundleIdentifier</key><string>dev.blox.app</string>
    <key>CFBundleName</key><string>Blox</string>
    <key>CFBundleDisplayName</key><string>Blox</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.1</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>dev.blox.app</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>blox</string>
            </array>
        </dict>
    </array>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "--- bundle ok: $APP ---"

if [[ "${1:-build}" == install ]]; then
    pkill -x blox 2>/dev/null || true
    sleep 1
    rm -rf /Applications/blox.app /Applications/Blox.app
    cp -R "$APP" /Applications/Blox.app
    codesign --verify --strict /Applications/Blox.app
    echo "--- installed: /Applications/Blox.app ---"
fi
