#!/bin/bash
# Runs a built Perch on this Mac and keeps what it saw, so a macOS version can be compared with another (the "macOS versions" workflow).
# check.sh <Perch.app> <out dir>. Leaves its results in <out>: shots of the real screen, the app's own snapshots, the design page
# filmed in this Mac's WebKit, and log.txt.
set -uo pipefail
cd "$(dirname "$0")/../.."
APP=$1 OUT=$2 BIN="$1/Contents/MacOS/Perch"
mkdir -p "$OUT"/screen "$OUT"/app "$OUT"/design
exec > >(tee "$OUT/log.txt") 2>&1
say() { echo; echo "== $*"; }
shot() { screencapture -x "$OUT/screen/$1.png" && echo "shot $1" || echo "shot $1 failed"; }
alive() { pgrep -x Perch >/dev/null && echo "Perch is running" || echo "Perch is NOT running"; }
quit() { pkill -x Perch; for _ in $(seq 50); do pgrep -x Perch >/dev/null || break; sleep 0.1; done; }

say System
sw_vers; uname -m
system_profiler SPDisplaysDataType | grep -E "Resolution|Display Type|Main Display" || true
echo "WebKit: $(defaults read /System/Library/Frameworks/WebKit.framework/Resources/Info.plist CFBundleVersion 2>/dev/null)"
echo "Safari: $(defaults read /Applications/Safari.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null)"
vtool -show-build "$BIN" | grep -E "minos|sdk"

say A Claude Code session to show
python3 -I scripts/compat/fake-session.py "$HOME/PerchTest/settings-speed" 5f0c2d1e-1111-4a6b-9c1d-000000000001

say Scan
"$BIN" --dump 2>&1 | head -60

say The app draws each state with sample data
"$BIN" --snapshot "$OUT/app" --wallpaper ui/wallpapers/blue-distortion-1.webp; echo "exit $?"; ls "$OUT/app"

say First run: onboarding
defaults delete app.perch.mac 2>/dev/null
open "$APP"; sleep 6; alive; shot onboarding-hello
osascript -e 'tell application "System Events" to key code 36' 2>&1; sleep 2; shot onboarding-next
quit

say Hooks and a permission asked through the socket
defaults write app.perch.mac onboarded -bool true
"$BIN" --install-hooks
ls -la ~/.config/perch; grep -c perch ~/.claude/settings.json
open "$APP" --args --show; sleep 6; alive; shot card-show
osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1; sleep 2; shot after-escape
echo '{"session_id":"5f0c2d1e-1111-4a6b-9c1d-000000000001","cwd":"'"$HOME"'/PerchTest/settings-speed","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"npm run build"}}' \
  | ~/.config/perch/hook claude PermissionRequest > "$OUT/hook-answer.txt" 2>&1 &
HOOK=$!
sleep 4; shot permission-asked
ls -la ~/.config/perch/perch.sock
osascript -e 'tell application "System Events" to key code 36' >/dev/null 2>&1; sleep 3
kill $HOOK 2>/dev/null; echo "hook answered: $(cat "$OUT/hook-answer.txt")"
shot after-permission
osascript -e 'tell application "System Events" to tell process "Perch" to get name of menu bar items of menu bar 1' 2>&1
quit

say Updates: an older version looks for one
OLD=$(dirname "$APP")/PerchOld.app; rm -rf "$OLD"; ditto "$APP" "$OLD"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.4.0" "$OLD/Contents/Info.plist"
codesign --force --deep --sign - "$OLD" >/dev/null 2>&1
defaults write app.perch.mac SULastCheckTime -date "2020-01-01 00:00:00 +0000"
open "$OLD"; sleep 20; alive; shot update-scheduled
defaults read app.perch.mac SULastCheckTime 2>&1
osascript -e 'tell application "System Events" to tell process "Perch" to click menu bar item 1 of menu bar 1' -e 'delay 1' \
  -e 'tell application "System Events" to tell process "Perch" to click menu item "Check for updates…" of menu 1 of menu bar item 1 of menu bar 1' 2>&1
sleep 8; shot update-asked
quit

say The design page in this WebKit
python3 -m http.server 8799 --directory ui >/dev/null 2>&1 & SERVER=$!
sleep 1
swift scripts/compat/shoot.swift http://127.0.0.1:8799 "$OUT/design" \
  "Onboarding/Hello" "Onboarding/1. Make me yours" "Onboarding/3. Your shortcut" "Onboarding/6. All set" \
  "Coming back/Needs your OK" "Coming back/Asked you something" "Coming back/Finished" "Coming back/Working" \
  "Acting on it/All sessions" "Replying/Reply: typed" "Reply formatting/Reply: a table" \
  "Settings/Settings" "Settings/Settings: Notifications" "Settings/Settings: General" "Settings/Change character" \
  "Motion/A card’s status changes" "Motion/Reply opens and closes" "Motion/Settings pages and switches" "Motion/The list sorts itself again" \
  "Character/Switching shapes" "External display/Resting" "External display/Opened by the hotkey" "External display/Live activity" \
  "Updates/Update available" "New session/The prompt, typed"
kill $SERVER
echo done
