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
# The build number is the commit count, so a build says which commit it came from (the list shows it at its foot).
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD 2>/dev/null || echo 1)" "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp ui/index.html ui/app.js ui/orbs.js "$APP/Contents/Resources/ui/"
cp -R ui/dist "$APP/Contents/Resources/ui/dist"
# Sign with the stable local "Perch Dev" certificate when it exists, so macOS remembers privacy permissions across rebuilds.
# (An ad-hoc signature changes on every build, which makes macOS ask for permission again each time.)
if security find-identity -p codesigning 2>/dev/null | grep -q '"Perch Dev"'; then
  codesign --force --sign "Perch Dev" "$APP" >/dev/null 2>&1 || codesign --force --sign - "$APP" >/dev/null 2>&1
else
  codesign --force --sign - "$APP" >/dev/null 2>&1
fi
if [ "${1:-}" = "--package-only" ]; then exit 0; fi
# The design page's real app icons, from this Mac. Leaves a running Perch alone.
if [ "${1:-}" = "--design-icons" ]; then "$APP/Contents/MacOS/Perch" --design-icons ui/icons.local.json; exit 0; fi
pkill -x Perch 2>/dev/null || true
# Wait for the old copy to quit: opening while it is still going hands the launch to the dying process.
for _ in $(seq 50); do pgrep -x Perch >/dev/null || break; sleep 0.1; done
case "${1:-}" in
  --demo) open -n "$APP" --args --demo ;;
  --show) open -n "$APP" --args --show ;;
  --simulate) open -n "$APP" --args --simulate ;;
  --setup) open -n "$APP" --args --setup ;;
  --onboarding) open -n "$APP" --args --onboarding ;;
  --hello) open -n "$APP" --args --hello ;;
  --activity) open -n "$APP" --args --activity ;;
  --idle) open -n "$APP" --args --idle "${2:-15}" ;;
  --snapshot) PERCH_CHARACTER="${PERCH_CHARACTER:-octo,#B9A2F5}" "$APP/Contents/MacOS/Perch" --snapshot "${2:-build/snapshots}" "${@:3}" ;;
  *) open "$APP" ;;
esac
