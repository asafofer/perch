#!/bin/bash
# Films the notch at 60 fps and makes the X cuts from it.
#
#   ./scripts/record-notch.sh capture [seconds] [out.mov]   # the built-in screen, 60 fps, no cursor (default 16 s, build/notch-take.mov)
#   ./scripts/record-notch.sh film "<scenario>" [seconds]   # the design page's scenario, frame by frame on a virtual clock, 1920 x 1440 (build/design-film.mov)
#       then: SRC_W=1920 SRC_H=1440 KEYS=... KEYS45=... ./scripts/record-notch.sh export build/design-film.mov <start> <length>
#   ./scripts/record-notch.sh export <in.mov> [start] [length]   # build/notch-16x9.mp4 and build/notch-4x5.mp4 (default from 0 s, 10 s)
#   ZOOM_AT=2.2 ./scripts/record-notch.sh export <in.mov> 1.4 10.5  # the same, with the camera pushing in as the notch opens
#   KEYS="0:1800:0 2.2:1800:0 3.2:1040:0 8.2:760:-140 8.9:1040:0" ./scripts/record-notch.sh export <in.mov> 1.4 10.5
#
# The crop is centred on the notch, from the top of the screen. Without ZOOM_AT or KEYS it holds still: 16:9 takes
# 1200 x 675 px of the screen (600 x 337 pt), 4:5 takes 960 x 1200 px (the panel's 480 pt, so the open row fits); CROP_W=<px>
# changes the 16:9 width (smaller is closer; under 940 cuts the open row).
# A camera move: KEYS is a list of time:width:offset, seconds into the cut, how many screen pixels wide the 16:9 frame is,
# and how far its middle sits from the notch's (screen pixels, minus is left), and optionally how it comes into that key
# (:out for a push that starts fast and settles, with the notch's spring; :in; in and out by default). It never jumps. ZOOM_AT=<s> is the short form: wide (WIDE, 1800 px) until the notch opens at that time, then in to the
# open row (TIGHT, 1040 px) over ZOOM_S seconds (0.9). The 4:5 cut follows the same keys, its widths times 0.8 (KEYS45 sets
# its own). The move is drawn at twice the output size with ffmpeg's perspective filter, which places the frame between
# pixels, so it glides instead of stepping a pixel at a time.
# Encoded H.264 High, 4:2:0, CRF 16, 60 fps, faststart, no audio: X plays it without re-timing. The notch is drawn at 2x,
# so a close-up of 760 px is scaled up 2.5x and still reads on mobile.
set -euo pipefail
cd "$(dirname "$0")/.."

SCREEN="${SCREEN:-$(ffmpeg -f avfoundation -list_devices true -i '' 2>&1 | sed -n 's/.*\[\([0-9]*\)\] Capture screen 0.*/\1/p' | head -1 || true)}"
# the built-in screen in pixels: its middle is the notch's
read -r SW SH < <(system_profiler SPDisplaysDataType 2>/dev/null | awk '/Resolution:/ { print $2, $4; exit }')
# a film of the design page (film-design.swift) is its own size: SRC_W and SRC_H say it
SW="${SRC_W:-$SW}"; SH="${SRC_H:-$SH}"
ENC=(-c:v libx264 -preset slow -crf 16 -profile:v high -pix_fmt yuv420p -r 60 -movflags +faststart -an)

case "${1:-}" in
  capture)
    secs="${2:-16}"; out="${3:-build/notch-take.mov}"; mkdir -p "$(dirname "$out")"
    ffmpeg -y -loglevel error -f avfoundation -capture_cursor 0 -framerate 60 -pixel_format nv12 -i "$SCREEN:none" -t "$secs" \
      -c:v libx264 -preset ultrafast -crf 8 -pix_fmt yuv420p "$out"
    echo "record-notch: $out"
    ;;
  film)
    # the design page in film mode (one scenario, no captions, the notch without its pink edge), every frame exact
    name="$2"; secs="${3:-11.5}"; frames=$(mktemp -d)
    ( cd ui && npm run build --silent >/dev/null 2>&1 )
    port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
    python3 -m http.server "$port" --directory ui >/dev/null 2>&1 & srv=$!
    trap 'kill $srv 2>/dev/null || true; rm -rf "$frames"' EXIT
    sleep .6
    q=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$name")
    swift scripts/film-design.swift "http://localhost:$port/design.html?record&film=$q" "$frames" "$secs" 960 720
    mkdir -p build
    ffmpeg -y -loglevel error -framerate 60 -i "$frames/f%05d.png" -c:v libx264 -preset slow -crf 6 -pix_fmt yuv444p build/design-film.mov
    echo "record-notch: build/design-film.mov (1920 x 1440)"
    ;;
  export)
    in="$2"; start="${3:-0}"; len="${4:-10}"
    # still <out> <out w> <out h> <px>: the crop from the top centre, held
    still() {
      local h=$(( $4 * $3 / $2 ))
      ffmpeg -y -loglevel error -ss "$start" -t "$len" -i "$in" -vf "crop=$4:$h:$(( SW / 2 - $4 / 2 )):0,scale=$2:$3:flags=lanczos,setsar=1" "${ENC[@]}" "$1"
    }
    # move <out> <out w> <out h> <keys>: the camera through the keys (time:width:offset in screen pixels)
    move() {
      local out=$1 ow=$2 oh=$3 keys=$4
      local vf; vf=$(python3 - "$ow" "$oh" "$SW" "$SH" $keys <<'PY'
import sys
ow, oh, sw, sh = map(int, sys.argv[1:5])
# time:width:offset[:ease]; the ease is how the camera comes into that key: io (in and out, the default), out (fast, then
# settling: a push with the notch's own spring), in
keys, eases = [], []
for k in sys.argv[5:]:
    f = k.split(':'); keys.append(tuple(float(v) for v in f[:3])); eases.append(f[3] if len(f) > 3 else 'io')
# the source region holds every frame the keys ask for; it is drawn at twice the output size
wmax = max(w + 2 * abs(o) for _, w, o in keys)
wmax = min(int(wmax) // 2 * 2, sw); hmax = int(wmax * oh / ow) // 2 * 2
if hmax > sh: sys.exit(f'record-notch: these keys need {wmax} x {hmax} px and the film is {sw} x {sh}: film it taller or narrow the keys')
s2w, s2h = ow * 2, oh * 2; k = s2w / wmax
T = 'in/60'
def ease(a, b, kind):
    p = f'clip(({T}-{a})/{b - a},0,1)'
    if kind == 'out': return f'(1-pow(1-{p},4))'
    if kind == 'in': return f'pow({p},3)'
    return f'if(lt({p},0.5),4*pow({p},3),1-pow(2-2*{p},3)/2)'
def track(val):
    # piecewise: before the first key its value, between keys an eased blend, after the last its value
    e = f'{val(keys[-1])}'
    for i in reversed(range(len(keys) - 1)):
        (t0, *a), (t1, *b) = keys[i], keys[i + 1]
        v0, v1 = val((t0, *a)), val((t1, *b))
        e = f'if(lt({T},{t1}),{v0}+({v1}-({v0}))*{ease(t0, t1, eases[i + 1])},{e})'
    return f'if(lt({T},{keys[0][0]}),{val(keys[0])},{e})'
W = track(lambda kk: round(kk[1] * k, 3))
C = track(lambda kk: round(s2w / 2 + kk[2] * k, 3))
X0 = f'(({C})-({W})/2)'; X1 = f'(({C})+({W})/2)'; H = f'(({W})*{oh}/{ow})'
print(f"crop={wmax}:{hmax}:{sw // 2 - wmax // 2}:0,scale={s2w}:{s2h}:flags=lanczos,fps=60,"
      f"perspective=x0='{X0}':y0=0:x1='{X1}':y1=0:x2='{X0}':y2='{H}':x3='{X1}':y3='{H}':interpolation=cubic:eval=frame,"
      f"scale={ow}:{oh}:flags=lanczos,setsar=1")
PY
)
      ffmpeg -y -loglevel error -ss "$start" -t "$len" -i "$in" -vf "$vf" "${ENC[@]}" "$out"
    }
    if [ -n "${ZOOM_AT:-}" ] && [ -z "${KEYS:-}" ]; then
      e=$(python3 -c "print(round($ZOOM_AT + ${ZOOM_S:-0.9}, 3))")
      KEYS="0:${WIDE:-1800}:0 $ZOOM_AT:${WIDE:-1800}:0 $e:${TIGHT:-1040}:0"
    fi
    if [ -n "${KEYS:-}" ]; then
      move build/notch-16x9.mp4 1920 1080 "$KEYS"
      move build/notch-4x5.mp4 1080 1350 "${KEYS45:-$(python3 -c "import sys; print(' '.join(':'.join([f[0], str(round(float(f[1])*.8))] + f[2:]) for f in (k.split(':') for k in sys.argv[1].split())))" "$KEYS")}"
    else
      w="${CROP_W:-1200}"; still build/notch-16x9.mp4 1920 1080 $(( w / 16 * 16 ))
      still build/notch-4x5.mp4 1080 1350 960
    fi
    echo "record-notch: build/notch-16x9.mp4, build/notch-4x5.mp4"
    ;;
  *) sed -n '2,22p' "$0"; exit 1 ;;
esac
