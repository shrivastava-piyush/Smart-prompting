#!/usr/bin/env bash
# Builds the `sp` CLI as a universal (arm64 + x86_64) release binary.
# Free: uses ad-hoc codesign (`-`), no Developer ID needed.

set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="build"
mkdir -p "$BUILD_DIR"

echo "==> swift build (release, universal)"
swift build -c release \
    --arch arm64 --arch x86_64 \
    --product sp

# swift build output lives under .build/apple/Products/Release when universal.
SRC=".build/apple/Products/Release/sp"
if [[ ! -f "$SRC" ]]; then
    SRC=".build/release/sp"
fi

echo "==> stripping + ad-hoc signing"
strip -x "$SRC" || true
codesign --force --sign - "$SRC"

cp "$SRC" "$BUILD_DIR/sp"
echo "==> done: $BUILD_DIR/sp"
file "$BUILD_DIR/sp"
