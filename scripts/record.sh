#!/bin/bash
# The README's GIF: plays the sample flow over a Raycast wallpaper (the app's --record), and makes docs/assets/perch.gif.
# Quits a running Perch while it records, and opens it again after.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-docs/assets/perch.gif}
WALL=${WALL:-ui/wallpapers/blue-distortion-1.webp}
./scripts/run.sh --package-only
FRAMES=$(mktemp -d)
pkill -x Perch 2>/dev/null || true
for _ in $(seq 50); do pgrep -x Perch >/dev/null || break; sleep 0.1; done
PERCH_CHARACTER="${PERCH_CHARACTER:-octo,#B9A2F5}" build/Perch.app/Contents/MacOS/Perch --record "$FRAMES" --wallpaper "$WALL"
# The frames over the wallpaper, at 720 px wide, with one palette for the whole GIF so colours hold still between frames.
ffmpeg -loglevel error -y -loop 1 -i "$FRAMES/wall.png" -framerate 20 -pattern_type glob -i "$FRAMES/f*.png" \
  -filter_complex "[0][1]overlay=shortest=1,fps=20,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" "$OUT"
echo "GIF: $OUT ($(du -h "$OUT" | cut -f1)), from $(ls "$FRAMES"/f*.png | wc -l | tr -d ' ') frames"
rm -rf "$FRAMES"
open build/Perch.app
