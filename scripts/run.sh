#!/bin/bash
# Build Perch (web UI + Swift), wrap it in a signed .app bundle, and launch it.
# Flags: --simulate plays "away, then back" with your real projects. --show opens the card right away with your real sessions. --demo plays the flow once. --idle <seconds> shows it after that much idle time (default 1200). --snapshot <dir> writes PNGs of each state and quits.
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
  --show) open -n "$APP" --args --show ;;
  --simulate) open -n "$APP" --args --simulate ;;
  --setup) open -n "$APP" --args --setup ;;
  --idle) open -n "$APP" --args --idle "${2:-15}" ;;
  --snapshot) "$APP/Contents/MacOS/Perch" --snapshot "${2:-build/snapshots}" "${@:3}" ;;
  *) open "$APP" ;;
esac
