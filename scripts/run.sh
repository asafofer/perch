#!/bin/bash
# Build Perch, wrap it in a signed .app bundle, and launch it. Pass --demo to play the whole flow once.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG=${CONFIG:-debug}
swift build -c "$CONFIG"
APP=build/Perch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/$CONFIG/Perch" "$APP/Contents/MacOS/Perch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1
pkill -x Perch 2>/dev/null || true
if [ "${1:-}" = "--demo" ]; then
  open -n "$APP" --args --demo
else
  open "$APP"
fi
