"""
Pixel-art END SEASON button: a salvaged window (64x40, the other buttons turned on
their side) looking out over the wasteland. Clicking it plays a sunset, the moon rises
and stars come out; after a short night, dawn brings the day back.

    python3 make_end_season.py [out_dir]

Outputs:
    end_season_sheet.png    sprite sheet, one animation per row (hover outline at row 0, col 1)
    end_season_frames.json  frame regions, per-frame durations (ms), time-of-day labels
    end_season_preview.gif  4x preview of a full cycle
and refreshes the frame table inside end_season_button.gd if it is next to this script.
"""
import json
import math
import os
import random
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_rad_meter import SHADOW, HOVER  # noqa: E402

W, H = 64, 40

# ---------------------------------------------------------------- helpers
def blank():
    return [[None] * W for _ in range(H)]


def put(L, x, y, c):
    if 0 <= x < W and 0 <= y < H:
        L[y][x] = c


def mask_of(L):
    return [[L[y][x] is not None for x in range(W)] for y in range(H)]


def lerp(a, b, u):
    return tuple(int(round(a[i] + (b[i] - a[i]) * u)) for i in range(3))


def lighten(c, k):
    return lerp(c, (255, 255, 255), k)


# ---------------------------------------------------------------- wood + label palette
OUT = (40, 28, 20)
WHI = (190, 164, 126)
WD = (154, 126, 94)
WMD = (128, 102, 76)
WSH = (98, 76, 58)
WDK = (66, 50, 38)
PAINT, PAINT_DK = (112, 142, 136), (86, 112, 108)
MET, METSH = (150, 150, 146), (92, 92, 90)
LABEL, LABEL_SH = (240, 230, 204), (58, 42, 32)

# ---------------------------------------------------------------- time of day
KEYS = {
    "day": dict(sky0=(110, 158, 196), sky1=(152, 190, 208), sky2=(212, 210, 182),
                mesa=(178, 148, 126), mesa_hi=(200, 172, 144), ruin=(120, 108, 106),
                sand_hi=(238, 208, 148), sand=(214, 176, 116), sand_dk=(178, 138, 88),
                rock=(134, 102, 74), tree=(98, 80, 68),
                cur=(158, 76, 60), cur_dk=(116, 54, 46), cur_hi=(192, 110, 84), glare=0.24),
    "golden": dict(sky0=(104, 134, 180), sky1=(204, 168, 140), sky2=(250, 192, 112),
                   mesa=(180, 120, 96), mesa_hi=(218, 150, 106), ruin=(108, 82, 84),
                   sand_hi=(248, 188, 110), sand=(222, 152, 92), sand_dk=(172, 106, 72),
                   rock=(122, 78, 60), tree=(86, 62, 58),
                   cur=(178, 82, 58), cur_dk=(128, 58, 46), cur_hi=(216, 120, 80), glare=0.2),
    "dusk": dict(sky0=(64, 68, 128), sky1=(172, 92, 112), sky2=(246, 128, 70),
                 mesa=(104, 62, 82), mesa_hi=(142, 80, 88), ruin=(58, 38, 58),
                 sand_hi=(172, 106, 88), sand=(138, 80, 76), sand_dk=(98, 58, 64),
                 rock=(74, 44, 52), tree=(50, 32, 48),
                 cur=(120, 54, 52), cur_dk=(86, 38, 42), cur_hi=(150, 70, 62), glare=0.14),
    "twilight": dict(sky0=(30, 32, 78), sky1=(64, 50, 104), sky2=(120, 66, 98),
                     mesa=(48, 38, 70), mesa_hi=(62, 48, 82), ruin=(30, 24, 46),
                     sand_hi=(92, 78, 104), sand=(70, 60, 90), sand_dk=(50, 44, 70),
                     rock=(40, 34, 58), tree=(28, 22, 40),
                     cur=(70, 38, 50), cur_dk=(50, 28, 38), cur_hi=(86, 48, 60), glare=0.1),
    "night": dict(sky0=(10, 12, 34), sky1=(18, 24, 58), sky2=(34, 44, 84),
                  mesa=(22, 26, 50), mesa_hi=(32, 38, 66), ruin=(14, 14, 30),
                  sand_hi=(76, 86, 120), sand=(52, 60, 92), sand_dk=(36, 42, 70),
                  rock=(26, 30, 52), tree=(14, 14, 28),
                  cur=(48, 30, 42), cur_dk=(34, 22, 32), cur_hi=(60, 40, 52), glare=0.08),
    "dawn": dict(sky0=(58, 72, 130), sky1=(158, 128, 156), sky2=(248, 178, 136),
                 mesa=(112, 90, 110), mesa_hi=(152, 112, 118), ruin=(70, 58, 76),
                 sand_hi=(206, 162, 132), sand=(172, 128, 112), sand_dk=(128, 94, 92),
                 rock=(92, 70, 74), tree=(62, 48, 62),
                 cur=(140, 70, 62), cur_dk=(100, 50, 48), cur_hi=(172, 92, 78), glare=0.16),
}
# tod 0 day -> 1 golden -> 2 dusk -> 3 twilight -> 4 night -> 5 dawn -> 6 day
TRACK = ["day", "golden", "dusk", "twilight", "night", "dawn", "day"]

SUN_COLS = {  # core, rim, glow
    "day": ((255, 252, 220), (255, 232, 150), (255, 246, 206)),
    "golden": ((255, 228, 140), (252, 178, 72), (255, 204, 120)),
    "dusk": ((255, 172, 96), (238, 102, 60), (252, 132, 80)),
    "dawn": ((255, 214, 150), (250, 150, 100), (255, 186, 142)),
}
SUN_TRACK = ["day", "golden", "dusk", "dusk", "dusk", "dawn", "day"]


def on_track(track, table, tod):
    i = min(int(tod), len(track) - 2)
    u = tod - i
    a, b = table[track[i]], table[track[i + 1]]
    if isinstance(a, dict):
        return {k: (a[k] + (b[k] - a[k]) * u if isinstance(a[k], float) else lerp(a[k], b[k], u))
                for k in a}
    return tuple(lerp(a[j], b[j], u) for j in range(len(a)))


def star_level(tod):
    if tod <= 2.2:
        return 0.0
    if tod <= 4:
        return min(1.0, (tod - 2.2) / 1.6)
    return max(0.0, 1 - (tod - 4) / 1.1)


# ---------------------------------------------------------------- the view
GX0, GY0, GW, GH = 7, 5, 50, 19        # glass: x 7..56, y 5..23
HZ = 13                                # horizon row (scene coords)
MULL = (24, 25)                        # mullion columns (scene coords)

MESA = {}
for gx, top in enumerate([12, 12, 11, 11, 12, 12, 11, 12, 12, 12, 12, 11]):
    MESA[gx] = top                     # low hills in the east
for gx in range(12, 20):
    MESA[gx] = 9                       # flat-topped mesa
MESA.update({11: 11, 19: 10, 20: 11, 21: 11, 22: 12, 23: 12})
RUINS = {31: 8, 32: 6, 33: 6, 34: 7, 35: 9, 36: 12, 37: 11, 38: 11, 39: 12, 41: 12,
         44: 12, 45: 9, 46: 8, 47: 8, 48: 10, 49: 7}
HOLES = {(32, 8), (33, 10), (46, 10), (47, 12), (32, 11)}
TREE = [(28, 17), (28, 16), (28, 15), (28, 14), (27, 13), (29, 13), (26, 12), (30, 12), (30, 11)]
ROCKS = [(4, 17), (5, 17), (15, 16), (36, 17), (37, 17), (44, 15), (21, 18)]
FIRE = (9, 16)


def ridge(gx):
    return 15 + int(round(1.0 * math.sin(gx / 5.0 + 0.5)))


def classify():
    cls = [["sky"] * GW for _ in range(GH)]
    for gy in range(GH):
        for gx in range(GW):
            if gy >= HZ:
                r = ridge(gx)
                if gy == r:
                    c = "sand_hi"
                elif gy > r and (gy == GH - 1 and (gx * 7 + gy) % 3 == 0):
                    c = "sand_dk"
                elif gy == HZ:
                    c = "far"
                else:
                    c = "sand"
                cls[gy][gx] = c
            elif gx in MESA and gy >= MESA[gx]:
                cls[gy][gx] = "mesa_hi" if gy == MESA[gx] else "mesa"
            elif gx in RUINS and gy >= RUINS[gx] and (gx, gy) not in HOLES:
                cls[gy][gx] = "ruin"
    for (x, y) in ROCKS:
        cls[y][x] = "rock"
    for (x, y) in TREE:
        cls[y][x] = "tree"
    return cls


CLS = classify()
rs = random.Random(9)
STARS = []
while len(STARS) < 16:
    p = (rs.randrange(5, GW), rs.randrange(0, 10))
    if CLS[p[1]][p[0]] == "sky" and p[0] not in MULL and all(
            abs(p[0] - q[0]) + abs(p[1] - q[1]) > 3 for q in STARS):
        STARS.append(p)


SKY_BAND = [0, 0, 0, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4]   # row -> band, 5 clean bands


def sky_color(pal, gx, gy):
    a, b, c = pal["sky0"], pal["sky1"], pal["sky2"]
    return (a, lerp(a, b, 0.5), b, lerp(b, c, 0.5), c)[SKY_BAND[min(gy, len(SKY_BAND) - 1)]]


def sun_set_pos(s):
    return (int(round(30 + 15 * s)), int(round(3 + 11 * s ** 1.5)))


def sun_rise_pos(r):
    return (int(round(5 + 25 * r)), int(round(14 - 11 * (1 - (1 - r) ** 1.5))))


def moon_pos(m):
    return (int(round(5 + 11 * m)), int(round(14 - 11 * (1 - (1 - m) ** 1.8))))


CRESCENT = [(0, -1), (1, -1), (-1, 0), (0, 0), (-1, 1), (0, 1), (0, 2), (1, 2)]


def scene(tod, sun=None, glow=1.0, moon=None, moon_fade=1.0, twinkle=None, fire=None):
    pal = on_track(TRACK, KEYS, tod)
    pal["far"] = lerp(pal["sand"], pal["sky2"], 0.35)     # hazy far ground at the horizon
    img = [[sky_color(pal, gx, gy) for gx in range(GW)] for gy in range(GH)]

    def is_sky(x, y):
        return 0 <= x < GW and 0 <= y < GH and CLS[y][x] == "sky"

    # stars
    lvl = star_level(tod)
    for i, (x, y) in enumerate(STARS):
        if i / len(STARS) >= lvl:
            continue
        bright = 1.0 if twinkle is None else (1.0 if (i * 5 + twinkle) % 4 else 0.45)
        img[y][x] = lerp(img[y][x], (232, 234, 255), min(1.0, lvl * 1.3) * bright)

    # sun glow + disc
    if sun is not None:
        sx, sy = sun
        core, rim, gc = on_track(SUN_TRACK, SUN_COLS, tod)
        low = min(1.0, max(0.0, sy / HZ))
        R = 4.0 + 5.0 * low ** 2
        for y in range(GH):
            for x in range(GW):
                d = math.hypot(x - sx, y - sy)
                k = max(0.0, 1 - d / R) * 0.6 * glow
                k = math.floor(k * 5) / 5            # banded halo
                if k > 0:
                    img[y][x] = lerp(img[y][x], gc, k)
        if glow >= 1.0:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    if 0 <= sx + dx < GW and 0 <= sy + dy < GH:
                        img[sy + dy][sx + dx] = rim if dx and dy else core

    # moon
    if moon is not None and moon_fade > 0:
        mx, my = moon
        for y in range(GH):
            for x in range(GW):
                d = math.hypot(x - mx - 0.3, y - my - 0.5)
                if d < 4.0:
                    k = math.floor((1 - d / 4.0) * 0.3 * moon_fade * 4) / 4
                    img[y][x] = lerp(img[y][x], (170, 190, 226), k)
        for dx, dy in CRESCENT:
            x, y = mx + dx, my + dy
            if 0 <= x < GW and 0 <= y < GH:
                img[y][x] = lerp(img[y][x], (240, 240, 222), moon_fade)

    # land on top (hides whatever has set behind it)
    for y in range(GH):
        for x in range(GW):
            c = CLS[y][x]
            if c != "sky":
                img[y][x] = pal[c]

    # campfire at night
    if fire is not None:
        fx, fy = FIRE
        flame = [(255, 210, 110), (255, 160, 60), (255, 236, 160)][fire % 3]
        img[fy][fx] = flame
        if fire % 3 != 1:
            img[fy - 1][fx] = lerp(img[fy - 1][fx], (255, 140, 50), 0.7)
        for q in ((fx - 1, fy), (fx + 1, fy), (fx, fy + 1)):
            img[q[1]][q[0]] = lerp(img[q[1]][q[0]], (255, 140, 60), 0.35)

    # glass: frame shadow, glare streaks, crack
    for x in range(GW):
        img[0][x] = lerp(img[0][x], (0, 0, 0), 0.25)
    for y in range(GH):
        img[y][26] = lerp(img[y][26], (0, 0, 0), 0.15)
    g = pal["glare"]
    for (x0, y0, n) in ((8, 11, 7), (11, 11, 4), (41, 17, 6), (44, 17, 3)):
        for i in range(n):
            x, y = x0 + i, y0 - i
            if 0 <= x < GW and 0 <= y < GH:
                img[y][x] = lighten(img[y][x], g)
    for (x, y) in ((47, 2), (46, 1), (45, 0), (48, 3), (49, 4), (46, 3), (45, 4), (48, 1)):
        img[y][x] = lighten(img[y][x], g * 2)

    # tattered curtain hanging inside the left edge
    drop = [12, 14, 10, 7]
    for gx, n in enumerate(drop):
        for gy in range(n):
            c = (pal["cur_dk"], pal["cur"], pal["cur_hi"], pal["cur"])[gx]
            if gy == n - 1 or (gx, gy) == (1, 6):
                c = pal["cur_dk"]
            img[gy][gx] = c
    return img


# ---------------------------------------------------------------- the window
FONT = {
    "E": ["1111", "1000", "1110", "1000", "1111"],
    "N": ["1001", "1101", "1011", "1001", "1001"],
    "D": ["1110", "1001", "1001", "1001", "1110"],
    "S": ["0111", "1000", "0110", "0001", "1110"],
    "A": ["0110", "1001", "1111", "1001", "1001"],
    "O": ["0110", "1001", "1001", "1001", "0110"],
}


def text_pixels(text, x0, y0):
    pts, x = [], x0
    for ch in text:
        if ch == " ":
            x += 3
            continue
        for r, row in enumerate(FONT[ch]):
            for c, bit in enumerate(row):
                if bit == "1":
                    pts.append((x + c, y0 + r))
        x += 5
    return pts


LABEL_TEXT = "END SEASON"
_tw = sum(3 if ch == " " else 5 for ch in LABEL_TEXT) - 1
LABEL_PTS = text_pixels(LABEL_TEXT, (W - _tw) // 2, 31)


def draw_device(view):
    L = blank()
    # sill (wider than the frame, rounded ends)
    sx0, sy0, sx1, sy1 = 1, 27, 62, 37
    for y in range(sy0, sy1 + 1):
        for x in range(sx0, sx1 + 1):
            if (x in (sx0, sx1)) and (y in (sy0, sy1)):
                continue
            edge = x in (sx0, sx1) or y in (sy0, sy1) or \
                ((x in (sx0 + 1, sx1 - 1)) and (y in (sy0, sy1)))
            if edge:
                c = OUT
            elif y == 28:
                c = WHI
            elif y == 29:
                c = WD
            elif y == 36:
                c = WSH
            else:
                c = WMD
            put(L, x, y, c)
    for x in range(sx0 + 1, sx1):
        if L[30][x] == WMD:
            put(L, x, 30, WSH)               # lip shadow under the sill top

    # frame
    fx0, fy0, fx1, fy1 = 3, 1, 60, 26
    for y in range(fy0, fy1 + 1):
        for x in range(fx0, fx1 + 1):
            if x in (fx0, fx1) or y == fy0:
                c = OUT
            elif y == 2 or x == 4:
                c = WHI
            elif y == 4 or x == 6:
                c = WMD
            elif y == 24 or x == 57:
                c = WHI
            elif y == 26 or x == 59:
                c = WSH
            else:
                c = WD
            put(L, x, y, c)
    put(L, fx0, fy0, None)
    put(L, fx1, fy0, None)

    # the view through the glass, then the mullion over it
    for y in range(GH):
        for x in range(GW):
            put(L, GX0 + x, GY0 + y, view[y][x])
    for y in range(GY0, GY0 + GH):
        put(L, GX0 + MULL[0], y, WHI)
        put(L, GX0 + MULL[1], y, WMD)
    put(L, 31, 14, MET)
    put(L, 32, 14, METSH)
    put(L, 31, 15, METSH)

    # hinges on the left stile
    for hy in (7, 20):
        put(L, 4, hy, MET)
        put(L, 5, hy, METSH)
        put(L, 4, hy + 1, METSH)
        put(L, 5, hy + 1, METSH)

    # weathering: grain, old flaking paint, nails
    rnd = random.Random(4)
    for _ in range(26):
        x, y = rnd.randrange(4, 60), rnd.choice([3, 25] + list(range(31, 36)))
        n = rnd.randrange(2, 5)
        for i in range(n):
            c = L[y][x + i] if x + i < W else None
            if c == WD:
                put(L, x + i, y, WMD)
            elif c == WMD:
                put(L, x + i, y, WSH)
    for _ in range(8):
        x, y = rnd.randrange(5, 6), rnd.randrange(6, 23)
        put(L, x, y, WMD)
        x, y = rnd.randrange(58, 59), rnd.randrange(6, 23)
        put(L, x, y, WMD)
    for (x, y) in ((9, 3), (10, 3), (11, 2), (44, 3), (45, 3), (58, 12), (58, 13), (5, 16),
                   (21, 25), (22, 25)):
        put(L, x, y, PAINT if (x + y) % 2 else PAINT_DK)
    for (x, y) in ((3 + 2, 33), (60 - 1, 33)):
        put(L, x, y, METSH)

    # painted label with a hard drop shadow
    for (x, y) in LABEL_PTS:
        put(L, x + 1, y + 1, LABEL_SH)
    for (x, y) in LABEL_PTS:
        put(L, x, y, LABEL)
    return L


def compose(view, press):
    dev = draw_device(view)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    m = mask_of(dev)
    px = img.load()
    for y in range(H):
        for x in range(W):
            sx, sy = x - 1, y - 2
            if 0 <= sx < W and 0 <= sy < H and m[sy][sx]:
                px[x, y] = SHADOW
    for y in range(H):
        for x in range(W):
            c = dev[y][x]
            if c is not None and 0 <= y + press < H:
                px[x, y + press] = c + (255,)
    return img


def hover_outline(view):
    m = mask_of(draw_device(view))
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    for y in range(H):
        for x in range(W):
            if not m[y][x] and any(0 <= x + dx < W and 0 <= y + dy < H and m[y + dy][x + dx]
                                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                px[x, y] = HOVER + (255,)
    return img


# ---------------------------------------------------------------- animation
def F(ms, tod, time, sky, press=0, sun_s=None, sun_r=None, glow=1.0, moon=None, fade=1.0,
      twinkle=None, fire=None):
    sun = sun_set_pos(sun_s) if sun_s is not None else (
        sun_rise_pos(sun_r) if sun_r is not None else None)
    view = scene(tod, sun=sun, glow=glow, moon=moon_pos(moon) if moon is not None else None,
                 moon_fade=fade, twinkle=twinkle, fire=fire)
    return {"view": view, "ms": ms, "press": press, "time": time, "sky": sky}


ANIMS = {
    "day": [F(1000, 0, "Midday", "Sun high", sun_s=0)],
    "end_season": [
        F(60, 0, "Midday", "Sun high", press=1, sun_s=0),
        F(70, 0.15, "Afternoon", "Sun lowering", sun_s=0.12),
        F(70, 0.35, "Afternoon", "Sun lowering", sun_s=0.25),
        F(70, 0.55, "Late afternoon", "Sun lowering", sun_s=0.38),
        F(70, 0.8, "Golden hour", "Sun low", sun_s=0.5),
        F(70, 1.05, "Golden hour", "Sun low", sun_s=0.62),
        F(80, 1.35, "Sunset", "Sun at the ruins", sun_s=0.74),
        F(90, 1.7, "Sunset", "Sun on the horizon", sun_s=0.84),
        F(90, 2.0, "Sunset", "Last of the sun", sun_s=0.92),
        F(90, 2.3, "Dusk", "Sun down", sun_s=1.0, glow=0.7),
        F(90, 2.7, "Dusk", "First stars", sun_s=1.0, glow=0.35, fire=0),
        F(90, 3.1, "Twilight", "Moon rising", moon=0.1, fire=1),
        F(80, 3.4, "Twilight", "Moon rising", moon=0.3, fire=2),
        F(80, 3.65, "Night", "Moon rising", moon=0.5, fire=0),
        F(80, 3.85, "Night", "Moon rising", moon=0.7, fire=1),
        F(90, 3.95, "Night", "Moon up", moon=0.85, fire=2),
        F(120, 4.0, "Night", "Moon up", moon=1.0, fire=0),
    ],
    "night": [F(150, 4.0, "Night", "Moon up", moon=1.0, twinkle=k, fire=k) for k in range(6)],
    "new_day": [
        F(90, 4.25, "Before dawn", "Moon fading", moon=1.0, fade=0.8, fire=1),
        F(90, 4.5, "Before dawn", "Moon fading", moon=1.0, fade=0.55, fire=2),
        F(90, 4.8, "Dawn", "Sun rising", sun_r=0.06, moon=1.0, fade=0.3),
        F(80, 5.0, "Dawn", "Sun rising", sun_r=0.16, moon=1.0, fade=0.12),
        F(80, 5.2, "Sunrise", "Sun rising", sun_r=0.3),
        F(70, 5.45, "Morning", "Sun climbing", sun_r=0.45),
        F(70, 5.65, "Morning", "Sun climbing", sun_r=0.6),
        F(70, 5.8, "Morning", "Sun climbing", sun_r=0.7),     # steps over the window bar
        F(80, 5.92, "Late morning", "Sun climbing", sun_r=0.87),
        F(100, 6.0, "Midday", "Sun high", sun_r=1.0),
    ],
}
ROWS = ["day", "end_season", "night", "new_day"]


def sync_gdscript(path, meta):
    if not os.path.exists(path):
        return
    lines = ["const ANIMS := {"]
    for name in ROWS:
        a = meta["animations"][name]
        rows = [f"[{f['x']}, {f['y']}, {f['ms']}]" for f in a["frames"]]
        lines.append(f'\t"{name}": {{"loop": {str(a["loop"]).lower()}, "frames": [')
        for i in range(0, len(rows), 4):
            lines.append("\t\t" + ", ".join(rows[i:i + 4]) + ",")
        lines.append("\t]},")
    lines.append("}")
    begin, end = "# --- FRAMES BEGIN", "# --- FRAMES END ---"
    src = open(path).read()
    head, rest = src.split(begin, 1)
    marker_line, rest = rest.split("\n", 1)
    _, tail = rest.split(end, 1)
    open(path, "w").write(head + begin + marker_line + "\n" + "\n".join(lines) + "\n" + end + tail)


def main(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    cols = max(len(ANIMS[a]) for a in ROWS)
    sheet = Image.new("RGBA", (cols * W, len(ROWS) * H), (0, 0, 0, 0))
    meta = {"frame_w": W, "frame_h": H, "animations": {}}
    imgs = {}
    for row, name in enumerate(ROWS):
        info, imgs[name] = [], []
        for col, f in enumerate(ANIMS[name]):
            im = compose(f["view"], f["press"])
            sheet.paste(im, (col * W, row * H))
            imgs[name].append(im)
            info.append({"x": col * W, "y": row * H, "ms": f["ms"], "pressed": bool(f["press"]),
                         "time": f["time"], "sky": f["sky"]})
        meta["animations"][name] = {"row": row, "loop": name == "night", "frames": info}
    sheet.paste(hover_outline(ANIMS["day"][0]["view"]), (W, 0))
    meta["hover_outline"] = {"x": W, "y": 0}
    sheet.save(os.path.join(out_dir, "end_season_sheet.png"))
    with open(os.path.join(out_dir, "end_season_frames.json"), "w") as fh:
        json.dump(meta, fh, indent=1)

    scale, bg, pad = 4, (196, 164, 116, 255), 6
    seq = [(imgs["day"][0], 700)]
    seq += [(im, f["ms"]) for im, f in zip(imgs["end_season"], ANIMS["end_season"])]
    for _ in range(2):
        seq += [(im, f["ms"]) for im, f in zip(imgs["night"], ANIMS["night"])]
    seq += [(im, f["ms"]) for im, f in zip(imgs["new_day"], ANIMS["new_day"])]
    seq += [(imgs["day"][0], 600)]
    frames = []
    for im, _ in seq:
        c = Image.new("RGBA", (W + pad * 2, H + pad * 2), bg)
        c.alpha_composite(im, (pad, pad))
        frames.append(c.convert("RGB").resize(((W + pad * 2) * scale, (H + pad * 2) * scale),
                                              Image.NEAREST))
    frames[0].save(os.path.join(out_dir, "end_season_preview.gif"), save_all=True,
                   append_images=frames[1:], duration=[ms for _, ms in seq], loop=0, disposal=1)

    sync_gdscript(os.path.join(out_dir, "end_season_button.gd"), meta)
    print("frames:", {k: len(v) for k, v in ANIMS.items()}, "sheet:", sheet.size)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__)))
