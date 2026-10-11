#!/bin/bash
# Try a real update on this Mac without publishing anything: an older copy of Perch checks a feed served from this machine and
# updates itself to a newer one, through Sparkle, the notch and the restart, exactly as an installed copy would.
#   ./scripts/test-update.sh            the old copy checks by itself and updates (the way your friends get it)
#   ./scripts/test-update.sh --manual   automatic checks off: pick Check for updates in the menu and press Update yourself
#   ./scripts/test-update.sh --stop     quit the test copy and the feed, undo the test's settings, bring your Perch back
# The test copy lives in build/test-update and your installed Perch is put away while it runs (two Perch fight over the shortcut).
set -euo pipefail
cd "$(dirname "$0")/.."
DIR=build/test-update; PORT=8779; DOMAIN=app.perch.mac
stop() {
  pkill -f "$DIR/old/Perch.app" 2>/dev/null || true
  pkill -f "http.server $PORT" 2>/dev/null || true
  defaults delete $DOMAIN SUEnableAutomaticChecks 2>/dev/null || true
  defaults delete $DOMAIN SULastCheckTime 2>/dev/null || true
  defaults delete $DOMAIN lastRunBuild 2>/dev/null || true
}
if [ "${1:-}" = "--stop" ]; then stop; [ -d /Applications/Perch.app ] && open /Applications/Perch.app; echo "Stopped. Your installed Perch is back."; exit 0; fi
stop
./scripts/package.sh >/dev/null
rm -rf "$DIR"; mkdir -p "$DIR/old" "$DIR/new" "$DIR/feed"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
SIGN="Perch Dev"; security find-identity -p codesigning 2>/dev/null | grep -q '"Perch Dev"' || SIGN=-
copy() {   # folder, shown version, build number
  ditto build/Perch.app "$1/Perch.app"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $2" -c "Set :CFBundleVersion $3" -c "Set :SUFeedURL http://localhost:$PORT/appcast.xml" "$1/Perch.app/Contents/Info.plist"
  local k="$1/Perch.app/Contents/Frameworks/Sparkle.framework/Versions/B"
  for x in "$k/Autoupdate" "$k/Updater.app" "$1/Perch.app/Contents/Frameworks/Sparkle.framework" "$1/Perch.app"; do codesign --force --sign "$SIGN" "$x" >/dev/null 2>&1 || codesign --force --sign - "$x" >/dev/null 2>&1; done
}
copy "$DIR/old" "$VERSION" 1
copy "$DIR/new" "$VERSION-test" 2
cat > "$DIR/feed/Perch-$VERSION-test.md" <<'N'
A test update to try the update flow

- Nothing changed in Perch: this only checks that updating works
- The notch downloads it with a ring beside the camera, restarts and says Updated
- What's new scrolls when the list is long, and a long line like this one wraps instead of being cut off at the edge of the notch
- Line four of the test list
- Line five of the test list
- Line six of the test list
- Line seven of the test list: scroll to see it
- Line eight of the test list
N
ditto -c -k --norsrc --keepParent "$DIR/new/Perch.app" "$DIR/feed/Perch-$VERSION-test.zip"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast --embed-release-notes --download-url-prefix "http://localhost:$PORT/" "$DIR/feed" >/dev/null
( cd "$DIR/feed" && nohup python3 -m http.server $PORT >/dev/null 2>&1 & )
pkill -x Perch 2>/dev/null || true; sleep 1
defaults write $DOMAIN lastRunBuild 1
if [ "${1:-}" = "--manual" ]; then defaults write $DOMAIN SUEnableAutomaticChecks -bool false; else defaults delete $DOMAIN SUEnableAutomaticChecks 2>/dev/null || true; fi
defaults delete $DOMAIN SULastCheckTime 2>/dev/null || true
open -n "$DIR/old/Perch.app"
if [ "${1:-}" = "--manual" ]; then echo "Running Perch $VERSION (build 1). Menu bar icon, Check for updates, then Update. ./scripts/test-update.sh --stop when done."
else echo "Running Perch $VERSION (build 1): it finds $VERSION-test in a few seconds and updates itself. ./scripts/test-update.sh --stop when done."; fi
