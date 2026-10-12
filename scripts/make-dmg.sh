#!/bin/bash
# The disk image people open to install Perch: build/Perch.dmg. Its window shows the Perch icon, an arrow and the Applications
# folder, on the picture in Resources/dmg (drawn from ui/install/background.html, see scripts/render-dmg-background.mjs).
# Needs build/Perch.app (./scripts/package.sh makes it) and a logged-in desktop: Finder lays the window out, which takes a few seconds.
# Not a Sparkle update: updates come from the zip. The release carries both (scripts/release.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Perch.app OUT=build/Perch.dmg NAME=Perch
[ -d "$APP" ] || { echo "No $APP: run ./scripts/package.sh first"; exit 1; }
W=660 H=400                      # the picture's size in points: the window's inside
STAGE=$(mktemp -d) RW=$(mktemp -u).dmg
trap 'rm -rf "$STAGE" "$RW"' EXIT
# the folder the image is made from: the app, a way to Applications, the picture (hidden), the volume's icon
mkdir "$STAGE/.background"
ditto "$APP" "$STAGE/Perch.app"
ln -s /Applications "$STAGE/Applications"
tiffutil -cathidpicheck Resources/dmg/background.png Resources/dmg/background@2x.png -out "$STAGE/.background/plain.tiff"
tiffutil -lzw "$STAGE/.background/plain.tiff" -out "$STAGE/.background/background.tiff" && rm "$STAGE/.background/plain.tiff"   # smaller, so Finder has the picture sooner
cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"
# a volume of the right size, plus room for Finder's own files
SIZE=$(( $(du -sm "$STAGE" | cut -f1) + 20 ))
# an image of this name may still be mounted from an earlier try
hdiutil detach "/Volumes/$NAME" -quiet 2>/dev/null || true
hdiutil create -quiet -srcfolder "$STAGE" -volname "$NAME" -fs HFS+ -format UDRW -size ${SIZE}m "$RW"
DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk '/^\/dev\/disk/ {print $1; exit}')
VOL="/Volumes/$NAME"
command -v SetFile >/dev/null && SetFile -a C "$VOL" || echo "No SetFile (Xcode command line tools): the disk will have a plain icon."
# Finder lays the window out: no toolbar or sidebar, icons of 112 at the two places the picture leaves for them.
# A window's bounds count its title bar, which is why the bottom edge is a little further down than the picture's height.
osascript <<OSA
tell application "Finder"
  tell disk "$NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 140, 200 + $W, 140 + $H + 28}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 12
    set background picture of opts to file ".background:background.tiff"
    set position of item "Perch.app" of container window to {175, 180}
    set position of item "Applications" of container window to {485, 180}
    update without registering applications
    delay 3
    close
    open
    delay 2
    close
  end tell
end tell
OSA
# Finder writes the window's layout to .DS_Store a moment after it closes; an image detached before that opens as a plain
# Finder window that then rearranges itself. Wait for the file to be there, and quiet.
for i in $(seq 1 20); do [ -f "$VOL/.DS_Store" ] && break; sleep 1; done
[ -f "$VOL/.DS_Store" ] || echo "Finder wrote no .DS_Store: the window will open plain. Run it again."
sleep 3
sync
for i in 1 2 3 4 5; do hdiutil detach "$DEV" -quiet && break; sleep 2; done
rm -f "$OUT"
hdiutil convert "$RW" -quiet -format UDZO -imagekey zlib-level=9 -o "$OUT"
echo "Disk image: $(pwd)/$OUT ($(du -h "$OUT" | cut -f1))"
