#!/bin/bash
# Build Perch (web UI + Swift), wrap it in a signed .app bundle, and launch it.
# Flags: --demo plays the flow once. --snapshot <dir> writes PNGs of each state and quits.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG=${CONFIG:-debug}
( cd ui && npm run build --silent )
swift build -c "$CONFIG"
APP=build/Perch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/ui"
cp ".build/$CONFIG/Perch" "$APP/Contents/MacOS/Perch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp ui/index.html ui/app.js "$APP/Contents/Resources/ui/"
cp -R ui/dist "$APP/Contents/Resources/ui/dist"
codesign --force --sign - "$APP" >/dev/null 2>&1
pkill -x Perch 2>/dev/null || true
case "${1:-}" in
  --demo) open -n "$APP" --args --demo ;;
  --snapshot) "$APP/Contents/MacOS/Perch" --snapshot "${2:-build/snapshots}" ;;
  *) open "$APP" ;;
esac
