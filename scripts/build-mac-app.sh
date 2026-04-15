#!/usr/bin/env bash
# Builds SmartPrompting.app (macOS) and wraps it in a DMG.
# Free: ad-hoc codesigning, no notarization. First launch requires right-click → Open.

set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="build"
mkdir -p "$BUILD_DIR"

if [[ ! -d "Apps/SmartPromptingMac.xcodeproj" ]]; then
    echo "error: Apps/SmartPromptingMac.xcodeproj not found." >&2
    echo "       Open Apps/SmartPromptingMac/*.swift in a new Xcode project," >&2
    echo "       link SmartPromptingCore, then re-run. See docs/install.md." >&2
    exit 1
fi

echo "==> archive macOS app"
xcodebuild \
    -project Apps/SmartPromptingMac.xcodeproj \
    -scheme SmartPromptingMac \
    -configuration Release \
    -archivePath "$BUILD_DIR/Mac.xcarchive" \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    archive

echo "==> export .app"
cat > "$BUILD_DIR/ExportOptions.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>mac-application</string>
  <key>signingStyle</key><string>manual</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$BUILD_DIR/Mac.xcarchive" \
    -exportPath "$BUILD_DIR/MacExport" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"

APP="$BUILD_DIR/MacExport/SmartPrompting.app"
codesign --force --deep --sign - "$APP"

echo "==> create DMG"
if command -v create-dmg >/dev/null 2>&1; then
    create-dmg \
        --volname "SmartPrompting" \
        --window-size 540 360 \
        --icon "SmartPrompting.app" 140 160 \
        --app-drop-link 400 160 \
        "$BUILD_DIR/SmartPrompting.dmg" "$APP"
else
    hdiutil create -volname SmartPrompting -srcfolder "$APP" -ov -format UDZO "$BUILD_DIR/SmartPrompting.dmg"
fi

echo "==> done: $BUILD_DIR/SmartPrompting.dmg"
