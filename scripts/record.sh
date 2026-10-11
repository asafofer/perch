#!/bin/bash
# The README's GIF, filmed from the design page (ui/design.html?record): the real interface with sample data on a
# Raycast wallpaper. Needs ffmpeg. Headless: nothing shows on screen (~22 s).
# Writes docs/assets/perch.gif.
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
echo "GIF: $OUT/perch.gif ($(du -h "$OUT/perch.gif" | cut -f1))"
rm -rf "$FRAMES"
