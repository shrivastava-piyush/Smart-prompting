#!/usr/bin/env bash
# Generates Xcode projects for both apps using XcodeGen.
# Run once after cloning, or any time you add/rename source files.
#
# Usage:
#   ./scripts/setup-xcode.sh
#
# Prerequisites:
#   brew install xcodegen

set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "XcodeGen not found. Installing via Homebrew..."
    brew install xcodegen
fi

echo "==> Generating SmartPromptingMac.xcodeproj"
cd Apps/SmartPromptingMac
xcodegen generate
cd ../..

echo "==> Generating SmartPromptingiOS.xcodeproj"
cd Apps/SmartPromptingiOS
xcodegen generate
cd ../..

echo ""
echo "Done. Open the projects:"
echo "  open Apps/SmartPromptingMac/SmartPromptingMac.xcodeproj"
echo "  open Apps/SmartPromptingiOS/SmartPromptingiOS.xcodeproj"
echo ""
echo "Both projects link SmartPromptingCore as a local Swift Package."
echo "Select your target device and press Cmd+R to build & run."
