#!/usr/bin/env bash
# Installs a launchd agent that keeps SmartPrompting.app running at login.
set -euo pipefail

APP="/Applications/SmartPrompting.app"
if [[ ! -d "$APP" ]]; then
    echo "error: $APP not found. Install the DMG first." >&2
    exit 1
fi

PLIST="$HOME/Library/LaunchAgents/com.smartprompting.popup.plist"
mkdir -p "$(dirname "$PLIST")"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.smartprompting.popup</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>$APP</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "Installed $PLIST"
echo "SmartPrompting will now launch at login."
