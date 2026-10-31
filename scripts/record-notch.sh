#!/bin/bash
# Films the notch at 60 fps and makes the X cuts from it.
#
#   ./scripts/record-notch.sh capture [seconds] [out.mov]   # the built-in screen, 60 fps, no cursor (default 16 s, build/notch-take.mov)
#   ./scripts/record-notch.sh export <in.mov> [start] [length]   # build/notch-16x9.mp4 and build/notch-4x5.mp4 (default from 0 s, 10 s)
#
# The crop is centred on the notch, from the top of the screen: 16:9 takes 1440 x 810 px of the screen (720 x 405 pt) and
# scales it to 1920 x 1080; 4:5 takes 864 x 1080 px and scales it to 1080 x 1350. CROP_W=<px> changes the 16:9 width
# (smaller is closer). Encoded H.264 High, 4:2:0, CRF 16, 60 fps, faststart, no audio: X plays it without re-timing, and
# mobile gets sharp edges because the notch is drawn at 2x and only scaled up 1.33x or 1.25x.
set -euo pipefail
cd "$(dirname "$0")/.."

SCREEN="${SCREEN:-$(ffmpeg -f avfoundation -list_devices true -i '' 2>&1 | sed -n 's/.*\[\([0-9]*\)\] Capture screen 0.*/\1/p' | head -1 || true)}"
# the built-in screen in pixels: its middle is the notch's
read -r SW SH < <(system_profiler SPDisplaysDataType 2>/dev/null | awk '/Resolution:/ { print $2, $4; exit }')
ENC=(-c:v libx264 -preset slow -crf 16 -profile:v high -pix_fmt yuv420p -r 60 -movflags +faststart -an)

case "${1:-}" in
  capture)
    secs="${2:-16}"; out="${3:-build/notch-take.mov}"; mkdir -p "$(dirname "$out")"
    ffmpeg -y -loglevel error -f avfoundation -capture_cursor 0 -framerate 60 -pixel_format nv12 -i "$SCREEN:none" -t "$secs" \
      -c:v libx264 -preset ultrafast -crf 8 -pix_fmt yuv420p "$out"
    echo "record-notch: $out"
    ;;
  export)
    in="$2"; start="${3:-0}"; len="${4:-10}"
    w="${CROP_W:-1440}"; w=$(( w / 16 * 16 )); h=$(( w * 9 / 16 ))
    x=$(( SW / 2 - w / 2 ))
    ffmpeg -y -loglevel error -ss "$start" -t "$len" -i "$in" -vf "crop=$w:$h:$x:0,scale=1920:1080:flags=lanczos,setsar=1" "${ENC[@]}" build/notch-16x9.mp4
    ffmpeg -y -loglevel error -ss "$start" -t "$len" -i "$in" -vf "crop=864:1080:$(( SW / 2 - 432 )):0,scale=1080:1350:flags=lanczos,setsar=1" "${ENC[@]}" build/notch-4x5.mp4
    echo "record-notch: build/notch-16x9.mp4, build/notch-4x5.mp4"
    ;;
  *) sed -n '2,10p' "$0"; exit 1 ;;
esac
