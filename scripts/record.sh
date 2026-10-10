#!/bin/bash
# The README's GIF and stills, filmed from the design page (ui/design.html?record): the real interface with sample data
# on a Raycast wallpaper. Needs ffmpeg, and the screen unlocked (a corner panel shows while it records, ~22 s).
# Writes docs/assets/perch.gif and the stills ask.png, card.png, list.png, activity.png.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-docs/assets}
( cd ui && npm run build --silent )
PORT=8766
python3 -m http.server $PORT --directory ui >/dev/null 2>&1 & SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
sleep 0.6
FRAMES=$(mktemp -d)
swift scripts/record-design.swift "http://localhost:$PORT/design.html?record" "$FRAMES" 21 840 340
echo "$(ls "$FRAMES" | wc -l | tr -d ' ') frames"
# The GIF: 720 px wide, one palette for all of it so colours hold still between frames.
ffmpeg -loglevel error -y -framerate 20 -pattern_type glob -i "$FRAMES/f*.png" \
  -vf "fps=20,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" "$OUT/perch.gif"
# Stills: frames at moments in the flow (20 a second), the panel's 520 x 340 pt around the notch; the live activity is a strip.
# Crops are fractions of the frame (840 x 340 pt at the screen's scale), so any display gives the same picture, 1040 px wide.
still() { ffmpeg -loglevel error -y -i "$FRAMES/$(printf 'f%05d.png' "$2")" -vf "crop=iw*520/840:ih*$3/340:(iw-ow)/2:0,scale=1040:-1:flags=lanczos" "$OUT/$1.png"; }
still ask 60 340
still card 100 340
still list 210 340
still activity 310 110
echo "GIF: $OUT/perch.gif ($(du -h "$OUT/perch.gif" | cut -f1)) and stills in $OUT"
rm -rf "$FRAMES"
