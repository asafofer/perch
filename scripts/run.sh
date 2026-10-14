#!/bin/bash
# Build Perch (web UI + Swift), wrap it in a signed .app bundle, and launch it.
# Flags: --update-demo plays an update over the real notch (nothing is downloaded). --simulate plays "away, then back" with your real projects. --show opens the card right away with your real sessions. --demo plays the flow once. --idle <seconds> shows it after that much idle time (default 1200). --snapshot <dir> writes PNGs of each state and quits.
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
# A build that is not a release says so (menu bar, Settings): which branch and commit this running copy came from.
if [ "$CONFIG" != "release" ]; then
  LABEL="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ?) @ $(git rev-parse --short HEAD 2>/dev/null || echo ?)$(git diff --quiet HEAD 2>/dev/null || echo +)"
  /usr/libexec/PlistBuddy -c "Add :PerchTestBuild string $LABEL" "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Sparkle (the updater) travels inside the app. Its sandbox helpers are not needed by an app that is not sandboxed.
mkdir -p "$APP/Contents/Frameworks"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Perch"
cp ui/index.html ui/app.js ui/orbs.js "$APP/Contents/Resources/ui/"
cp -R ui/dist "$APP/Contents/Resources/ui/dist"
# What each release says about itself, for the What's new card on the first start after an update.
cp -R release-notes "$APP/Contents/Resources/release-notes"
# A release build is signed with the Developer ID certificate when this Mac has one.
# Anything else uses the stable local "Perch Dev" certificate, so macOS remembers privacy permissions across rebuilds.
# (An ad-hoc signature changes on every build, which makes macOS ask for permission again each time.)
DEVID=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
if [ "$CONFIG" = release ] && [ -n "$DEVID" ]; then SIGN="$DEVID"
elif security find-identity -p codesigning 2>/dev/null | grep -q '"Perch Dev"'; then SIGN="Perch Dev"; else SIGN=-; fi
# A Developer ID build runs with the hardened runtime and a timestamp, as notarization needs. A "Perch Dev" build cannot:
# its certificate has no team, and the hardened runtime then refuses to load Sparkle ("different Team IDs").
FLAGS=(); [ "$SIGN" = "$DEVID" ] && FLAGS=(--options runtime --timestamp)
# Inside out: Sparkle's helpers, then its framework, then the app. If "Perch Dev" refuses, fall back to ad hoc; a Developer ID signature never does.
sign() {
  if [ "$SIGN" = "$DEVID" ]; then codesign --force --sign "$SIGN" ${FLAGS[@]+"${FLAGS[@]}"} "$@"
  else codesign --force --sign "$SIGN" ${FLAGS[@]+"${FLAGS[@]}"} "$@" >/dev/null 2>&1 || codesign --force --sign - "$@" >/dev/null 2>&1; fi
}
SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPK/Autoupdate"; sign "$SPK/Updater.app"; sign "$APP/Contents/Frameworks/Sparkle.framework"
sign --entitlements Resources/Perch.entitlements "$APP"
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
  --onboarding) open -n "$APP" --args --onboarding ;;
  --hello) open -n "$APP" --args --hello ;;
  --activity) open -n "$APP" --args --activity ;;
  --update-demo) open -n "$APP" --args --update-demo ;;
  --idle) open -n "$APP" --args --idle "${2:-15}" ;;
  --snapshot) PERCH_CHARACTER="${PERCH_CHARACTER:-octo,#B9A2F5}" "$APP/Contents/MacOS/Perch" --snapshot "${2:-build/snapshots}" "${@:3}" ;;
  *) open "$APP" ;;
esac
