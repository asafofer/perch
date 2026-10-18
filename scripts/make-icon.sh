#!/bin/bash
# The app icon from docs/assets/icon.svg: drawn by WebKit (the character's coat is an SVG filter), then every size macOS
# wants into Resources/AppIcon.icns, docs/assets/icon.png, and icon-256.png for the README (a browser draws the SVG's coat
# filter blurred). Needs the screen unlocked (a corner panel shows for a moment).
set -euo pipefail
cd "$(dirname "$0")/.."
T=$(mktemp -d)
swift scripts/render-svg.swift docs/assets/icon.svg "$T/icon.png" 512
sips -z 1024 1024 "$T/icon.png" --out docs/assets/icon.png >/dev/null
sips -z 256 256 docs/assets/icon.png --out docs/assets/icon-256.png >/dev/null
mkdir "$T/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s docs/assets/icon.png --out "$T/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) docs/assets/icon.png --out "$T/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$T/AppIcon.iconset" -o Resources/AppIcon.icns
rm -rf "$T"
echo "Wrote Resources/AppIcon.icns, docs/assets/icon.png and icon-256.png"
