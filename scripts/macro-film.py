#!/usr/bin/env python3
# The notch clip as a macro shot: frames of the design page filmed flat (film-design.swift, the notch alone on #111, many
# frames a second) are seen by a virtual camera tilted over them, with a shallow depth of field, motion blur from the
# frames between, and a slow drift that ends where it began, so the clip loops.
#
#   macro-film.py <frames dir> <out.mp4> [--ppt 8] [--fps-in 240] [--seconds 8]
#
# The frames are of the page's top, the notch's middle across their middle, <ppt> pixels to a point. Needs numpy and opencv.
import argparse, glob, math, os, subprocess, sys
import numpy as np
import cv2

ap = argparse.ArgumentParser()
ap.add_argument('frames'); ap.add_argument('out')
ap.add_argument('--ppt', type=float, default=8); ap.add_argument('--fps-in', type=int, default=240)
ap.add_argument('--seconds', type=float, default=8.5); ap.add_argument('--size', default='1080x1350')
ap.add_argument('--only', default='', help='times to write as stills instead, e.g. 0.5,3,5,6.8')
a = ap.parse_args()
W, H = map(int, a.size.split('x'))
FPS = 60
SUB = a.fps_in // FPS                    # frames filmed per frame shown
SHUT = max(1, round(SUB * .5))           # a 180 degree shutter: the first half of them make the blur
files = sorted(glob.glob(os.path.join(a.frames, 'f*.png')))
BG = 0.0   # above the screen's top edge: the bezel

def ease_io(p): return p * p * (3 - 2 * p) if p < 1 else 1.0
def ease_out(p): return 1 - (1 - p) ** 3
def ease_soft(p): return 0.5 - 0.5 * math.cos(math.pi * p)

# the camera, in the page's points from the notch's top middle (y down): where it looks, how wide it sees there, what is in focus
KEYS = [  # t, look x, look y, width, focus x, focus y, ease into this key
    (0.0, -40, 34, 240, -40, 20, None),
    (0.8, -44, 34, 234, -40, 20, ease_soft),       # barely moving on the closed notch
    (1.5, -150, 44, 250, -205, 15, ease_io),       # eases back as the notch springs open; focus settles on the character
    (2.5, -158, 44, 200, -205, 15, ease_soft),     # drifting in, toward the character
    (5.6, -168.5, 44, 110, -205, 15, ease_io),       # the push in, side-eye to glare
    (7.5, -168.5, 44, 107, -205, 15, ease_soft),     # held on the glare
    (8.1, -40, 34, 240, -40, 20, ease_io),         # back out as the notch closes
    (8.5, -40, 34, 240, -40, 20, ease_soft),       # resting closed, where the clip began, so it loops
]

def camera(t):
    t = t % a.seconds
    for i in range(len(KEYS) - 1):
        k0, k1 = KEYS[i], KEYS[i + 1]
        if t <= k1[0]:
            p = k1[6]((t - k0[0]) / (k1[0] - k0[0]))
            w = k0[3] * (k1[3] / k0[3]) ** p                       # zoom on a log scale
            u = p if k0[3] == k1[3] else (k0[3] - w) / (k0[3] - k1[3])
            lx, ly = k0[1] + (k1[1] - k0[1]) * u, k0[2] + (k1[2] - k0[2]) * u
            fx, fy = k0[4] + (k1[4] - k0[4]) * p, k0[5] + (k1[5] - k0[5]) * p
            break
    ph = 2 * math.pi * t / a.seconds   # the drift: one slow loop over the clip
    pitch = math.radians(9 + 0.6 * math.sin(ph))
    yaw = math.radians(-6 + 0.8 * math.sin(ph + 1.1))
    roll = math.radians(-1 + 0.3 * math.sin(ph + 2.3))
    return lx, ly, w, fx, fy, pitch, yaw, roll

FOV = math.radians(26)
F = W / (2 * math.tan(FOV / 2))
K = np.array([[F, 0, W / 2], [0, F, H / 2], [0, 0, 1]])

def rot(pitch, yaw, roll):
    cx, sx, cy, sy, cz, sz = math.cos(pitch), math.sin(pitch), math.cos(yaw), math.sin(yaw), math.cos(roll), math.sin(roll)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Rz @ Rx @ Ry

def plane_to_image(t):
    lx, ly, w, fx, fy, pitch, yaw, roll = camera(t)
    R = rot(pitch, yaw, roll); D = F * w / W
    tvec = -R @ np.array([lx, ly, 0.0]) + np.array([0, 0, D])
    Hm = K @ np.column_stack([R[:, 0], R[:, 1], tvec])
    return Hm, R, tvec, (fx, fy)

# the frames, smaller copies for a far camera, so a warp never skips pixels
cache = {}
def source(k, level):
    key = (k, level)
    if key in cache: return cache[key]
    if len(cache) > 3 * SUB: cache.clear()
    im = cv2.imread(files[min(k, len(files) - 1)], cv2.IMREAD_COLOR).astype(np.float32) / 255.0
    for _ in range(level): im = cv2.pyrDown(im)
    cache[key] = im
    return im

def warp(k, t):
    Hm, *_ = plane_to_image(t)
    w = camera(t)[2]; shown = W / w   # pixels a point at the centre
    level, ppt = 0, a.ppt
    while ppt / 2 >= shown * 1.15 and level < 3: level += 1; ppt /= 2
    im = source(k, level)
    cx = im.shape[1] / 2
    S = np.array([[1 / ppt, 0, -cx / ppt], [0, 1 / ppt, 0], [0, 0, 1]])
    return cv2.warpPerspective(im, Hm @ S, (W, H), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_CONSTANT, borderValue=(BG, BG, BG))

LEVELS = [0, 1.2, 2.4, 4.0, 6.0, 8.5, 12.0, 16.0]
APERTURE = 30.0   # how fast things leave focus, in pixels of blur for a depth a whole camera distance off

def depth_blur(img, t):
    Hm, R, tvec, (fx, fy) = plane_to_image(t)
    Hi = np.linalg.inv(Hm)
    gs = 8
    us, vs = np.meshgrid(np.arange(0, W, gs) + gs / 2, np.arange(0, H, gs) + gs / 2)
    pts = Hi @ np.stack([us.ravel(), vs.ravel(), np.ones(us.size)])
    px, py = pts[0] / pts[2], pts[1] / pts[2]
    Z = R[2, 0] * px + R[2, 1] * py + tvec[2]
    Zf = R[2, 0] * fx + R[2, 1] * fy + tvec[2]
    coc = np.clip(APERTURE * np.abs(Z - Zf) / Z, 0, LEVELS[-1]).reshape(us.shape).astype(np.float32)
    coc = cv2.resize(coc, (W, H), interpolation=cv2.INTER_LINEAR)
    st = np.stack([img] + [cv2.GaussianBlur(img, (0, 0), s) for s in LEVELS[1:]])
    idx = np.interp(coc, LEVELS, np.arange(len(LEVELS))).astype(np.float32)
    lo = np.floor(idx).astype(np.int64); hi = np.minimum(lo + 1, len(LEVELS) - 1); f = (idx - lo)[..., None]
    pick = lambda j: np.take_along_axis(st, j[None, ..., None].repeat(3, -1), 0)[0]
    return pick(lo) * (1 - f) + pick(hi) * f

def frame(i):
    # the shutter is open for the first half of the frame: the filmed frames in that time, each seen by the camera of its moment
    ts = [(i + .5 * j / SHUT) / FPS for j in range(SHUT)]
    acc = np.zeros((H, W, 3), np.float32)
    for t in ts:
        acc += warp(int(round(t * a.fps_in)), t)
    return depth_blur(acc / SHUT, sum(ts) / len(ts))

n = int(round(a.seconds * FPS))
if a.only:
    for s in a.only.split(','):
        i = int(round(float(s) * FPS))
        cv2.imwrite(os.path.splitext(a.out)[0] + f'-{s}.png', np.clip(frame(i) * 255 + .5, 0, 255).astype(np.uint8))
    sys.exit(0)
enc = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'bgr24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-',
                        '-vf', 'scale=out_color_matrix=bt709:out_range=tv', '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709',
                        '-c:v', 'libx264', '-preset', 'slow', '-crf', '15', '-profile:v', 'high', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-an', a.out],
                       stdin=subprocess.PIPE)
for i in range(n):
    # a little grain-free dither so the near-black never bands
    img = frame(i) * 255 + np.random.uniform(-.5, .5, (H, W, 1)).astype(np.float32)
    enc.stdin.write(np.clip(img + .5, 0, 255).astype(np.uint8).tobytes())
    if i % 60 == 0: print(f'macro-film: {i}/{n}', file=sys.stderr)
enc.stdin.close(); enc.wait()
print(f'macro-film: {a.out}')
