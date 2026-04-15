#!/usr/bin/env bash
# Builds SmartPrompting.ipa with a free personal team (7-day provisioning).
# Requires: you've signed into Xcode with a free Apple ID and set
# DEVELOPMENT_TEAM in the environment (visible in Xcode → Settings → Accounts).

set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="build"
mkdir -p "$BUILD_DIR"

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
    echo "error: set DEVELOPMENT_TEAM=<your-team-id>  (Xcode → Settings → Accounts)." >&2
    exit 1
fi

if [[ ! -d "Apps/SmartPromptingiOS.xcodeproj" ]]; then
    echo "error: Apps/SmartPromptingiOS.xcodeproj not found." >&2
    echo "       Create it in Xcode from Apps/SmartPromptingiOS/* sources, link" >&2
    echo "       SmartPromptingCore as a local SPM, then re-run. See docs/install.md." >&2
    exit 1
fi

echo "==> archive iOS app"
xcodebuild \
    -project Apps/SmartPromptingiOS.xcodeproj \
    -scheme SmartPromptingiOS \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$BUILD_DIR/iOS.xcarchive" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    archive

cat > "$BUILD_DIR/iOSExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>development</string>
  <key>teamID</key><string>$DEVELOPMENT_TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>compileBitcode</key><false/>
</dict>
</plist>
EOF

echo "==> export .ipa"
xcodebuild -exportArchive \
    -archivePath "$BUILD_DIR/iOS.xcarchive" \
    -exportPath "$BUILD_DIR/iOSExport" \
    -exportOptionsPlist "$BUILD_DIR/iOSExportOptions.plist" \
    -allowProvisioningUpdates

cp "$BUILD_DIR/iOSExport/SmartPrompting.ipa" "$BUILD_DIR/SmartPrompting.ipa"
echo "==> done: $BUILD_DIR/SmartPrompting.ipa"
echo "Drop into iCloud Drive → open in AltStore, or Xcode → run to install."
