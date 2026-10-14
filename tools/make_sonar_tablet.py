"""
Pixel-art rugged field tablet button with a sonar screen, for the same UI set as the
rad meter (same 40x64 frame, same press/shadow/hover conventions).

Idle ("off"): the screen shows a color terrain map.
Switching on: the screen turns like a card and comes back as a black-and-green sonar
view, pings once, then a sweep circles and lights up contacts as it passes.

    python3 make_sonar_tablet.py [out_dir]

Outputs:
    sonar_tablet_sheet.png    sprite sheet, one animation per row (hover outline at row 0, col 1)
    sonar_tablet_frames.json  frame regions + per-frame durations (ms)
    sonar_tablet_preview.gif  4x preview of a full cycle
and refreshes the frame table inside sonar_tablet_button.gd if it is next to this script.
"""
import json
import math
import os
import random
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_rad_meter import (W, H, SHADOW, HOVER, blank, put, rrect_inside,  # noqa: E402
                            bresenham, pixel_perfect, mask_of)

# ---------------------------------------------------------------- palette
OUT = (22, 24, 26)
TH = (188, 192, 190)
T = (152, 156, 156)
TMD = (132, 136, 138)
TSH = (102, 106, 110)
TDK = (70, 74, 78)
RUB = (46, 48, 50)
RUBHI = (82, 84, 86)
BEZ = (18, 20, 22)
BEZHI = (54, 58, 62)
DUST = (178, 152, 112)
AMBER = (232, 162, 40)
AMBER_DK = (150, 98, 30)
LED_GREEN = (140, 255, 120)
LED_AMBER = (255, 176, 48)
SCREEN_DARK = (10, 12, 14)

# color map
CLAY, SAND, DUNE, ROCK = (158, 118, 80), (200, 164, 108), (222, 194, 138), (132, 112, 94)
RIVER = (84, 126, 150)
ROAD = (78, 74, 70)
CITY, CITY_DK, CRATER = (124, 118, 110), (82, 78, 72), (52, 44, 38)
FARM, FARM_HI = (98, 142, 62), (134, 174, 82)
RAIDER = (196, 52, 40)
MARK_RED = (214, 40, 40)

# sonar greens, dark -> bright
G = [(6, 14, 9), (16, 48, 24), (30, 96, 44), (58, 160, 70), (120, 230, 110), (214, 255, 204)]

# screen placement
SX0, SY0, SW, SH = 8, 8, 24, 36
CX, CY = 12, 18                       # own position, screen-local (global 20, 26)
CCX, CCY = CX + 0.5, CY + 0.5


# ---------------------------------------------------------------- map data
def value_noise(w, h, gx, gy, seed):
    r = random.Random(seed)
    grid = [[r.random() for _ in range(gx + 1)] for _ in range(gy + 1)]
    out = [[0.0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            fx, fy = x / (w - 1) * gx, y / (h - 1) * gy
            x0, y0 = min(int(fx), gx - 1), min(int(fy), gy - 1)
            tx, ty = fx - x0, fy - y0
            tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
            a = grid[y0][x0] * (1 - tx) + grid[y0][x0 + 1] * tx
            b = grid[y0 + 1][x0] * (1 - tx) + grid[y0 + 1][x0 + 1] * tx
            out[y][x] = a * (1 - ty) + b * ty
    return out


def build_map():
    n1 = value_noise(SW, SH, 4, 6, 21)
    n2 = value_noise(SW, SH, 8, 12, 22)
    hgt = [[0.65 * n1[y][x] + 0.35 * n2[y][x] for x in range(SW)] for y in range(SH)]
    vals = sorted(v for row in hgt for v in row)
    th = [vals[int(len(vals) * p)] for p in (0.25, 0.62, 0.88)]
    level = [[sum(v > t for t in th) for v in row] for row in hgt]

    feats = {}     # (x, y) -> (color, sonar level)

    river = pixel_perfect([(math.floor(5 + 2.5 * math.sin(y / 5.5 + 0.6) + y * 0.08), y)
                           for y in range(SH)])
    for p in river:
        feats[p] = (RIVER, 2)

    road = []
    pts = [(16, 7), (20, 14), (17, 24), (21, 35)]
    for a, b in zip(pts, pts[1:]):
        road += bresenham(*a, *b)
    for p in road:
        feats[p] = (ROAD, 2)

    for (bx, by) in ((9, 2), (12, 2), (15, 2), (9, 5), (12, 5), (15, 5), (10, 8), (13, 8)):
        crater = (bx, by) in ((12, 5), (15, 2))
        for dx in range(2):
            for dy in range(2):
                if crater:
                    feats[(bx + dx, by + dy)] = (CRATER, 1)
                else:
                    feats[(bx + dx, by + dy)] = (CITY if dy == 0 else CITY_DK, 3)

    for (fx, fy) in ((2, 12), (7, 27)):
        for dx in range(2):
            for dy in range(2):
                feats[(fx + dx, fy + dy)] = (FARM_HI if (dx, dy) == (0, 0) else FARM, 2)

    for p in ((19, 29), (21, 29), (20, 30), (19, 31), (21, 31)):
        feats[p] = (RAIDER, 2)

    blips = [(13, 4), (2, 12), (8, 28), (20, 30)]   # city, two colonies, raider camp
    return level, feats, blips


LEVEL, FEATS, BLIPS = build_map()


def color_map():
    pal = (CLAY, SAND, DUNE, ROCK)
    img = [[pal[LEVEL[y][x]] for x in range(SW)] for y in range(SH)]
    for (x, y), (c, _) in FEATS.items():
        if 0 <= x < SW and 0 <= y < SH:
            img[y][x] = c
    for y in range(SH):                               # faint map grid
        for x in range(SW):
            if x % 6 == 0 or y % 6 == 0:
                img[y][x] = tuple(int(v * 0.9) for v in img[y][x])
    img[CY][CX] = (255, 255, 255)                     # you-are-here marker
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        img[CY + dy][CX + dx] = MARK_RED
    return img


def sonar_features():
    f = {}
    for y in range(SH):
        for x in range(SW):
            lv = LEVEL[y][x]
            if (x + 1 < SW and LEVEL[y][x + 1] != lv) or (y + 1 < SH and LEVEL[y + 1][x] != lv):
                f[(x, y)] = 1                         # terrain contours
    for p, (_, s) in FEATS.items():
        f[p] = max(f.get(p, 0), s)
    return f


SFEAT = sonar_features()


def px_angle(x, y):
    return math.degrees(math.atan2(-(y + 0.5 - CCY), x + 0.5 - CCX)) % 360


def px_dist(x, y):
    return math.hypot(x + 0.5 - CCX, y + 0.5 - CCY)


def overlay(x, y):
    """Range rings + crosshair, dotted."""
    if (x + y) % 2:
        return 0
    if x == CX or y == CY:
        return 1
    d = px_dist(x, y)
    return 1 if any(abs(d - r) < 0.5 for r in (6, 12, 18)) else 0


def sonar(theta=None, flash=False, ping=None, dim=0):
    """theta = sweep angle (deg, 0 = east, clockwise sweep means decreasing)."""
    lv = [[0] * SW for _ in range(SH)]
    for y in range(SH):
        for x in range(SW):
            l = overlay(x, y)
            f = SFEAT.get((x, y), 0)
            if theta is not None:
                d = (px_angle(x, y) - theta) % 360    # degrees since the sweep passed
                if f:
                    l = max(l, f + 1 if d < 45 else f if d < 180 else max(1, f - 1))
                elif d < 22.5:
                    l = max(l, 1)
            elif f:
                l = max(l, f)
            if flash:
                l = min(5, l + 2) if l else 1
            if ping is not None:
                r = px_dist(x, y)
                if abs(r - ping) < 0.6:
                    l = max(l, 4)
                elif abs(r - (ping - 1.3)) < 0.6:
                    l = max(l, 2)
            lv[y][x] = max(0, l - dim) if l else 0
    if theta is not None:                              # the sweep arm
        a = math.radians(theta)
        ex = math.floor(CCX + 26 * math.cos(a))
        ey = math.floor(CCY - 26 * math.sin(a))
        for i, (x, y) in enumerate(bresenham(CX, CY, ex, ey)):
            if 0 <= x < SW and 0 <= y < SH:
                lv[y][x] = 5 if i < 3 else 4
    for (bx, by) in BLIPS:
        if theta is None:
            l = 4 if flash else 2
        else:
            d = (px_angle(bx, by) - theta) % 360
            l = 5 if d < 22.5 else 4 if d < 90 else 3 if d < 200 else 2
        l = max(1, l - dim)
        lv[by][bx] = max(lv[by][bx], l)
        if l == 5:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if 0 <= bx + dx < SW and 0 <= by + dy < SH:
                    lv[by + dy][bx + dx] = max(lv[by + dy][bx + dx], 3)
    lv[CY][CX] = max(1, 5 - dim)
    return [[G[l] for l in row] for row in lv]


def flip(content, w, side, shade=True):
    """Card turn around the vertical axis. side='out': turning away, 'in': coming back."""
    out = [[SCREEN_DARK] * SW for _ in range(SH)]
    cw = SW * w
    x0 = (SW - cw) / 2
    for y in range(SH):
        for x in range(SW):
            u = (x + 0.5 - x0) / cw
            if not 0 <= u < 1:
                continue
            far = u if side == "out" else 1 - u
            s = 1 - 0.32 * (1 - w) * far              # far edge gets shorter
            sy = (SH / 2) + (y + 0.5 - SH / 2) / s
            if not 0 <= sy < SH:
                continue
            c = content[int(sy)][min(SW - 1, int(u * SW))]
            if shade:
                k = 0.55 + 0.45 * w
                c = tuple(int(v * k) for v in c)
            out[y][x] = c
    return out


def edge_on():
    out = [[SCREEN_DARK] * SW for _ in range(SH)]
    for y in range(1, SH - 1):
        out[y][11] = out[y][12] = G[5]
        out[y][10] = out[y][13] = G[2]
    return out


# ---------------------------------------------------------------- the tablet
def emboss(L, shape, fill, hi=TH, lo=TSH):
    s = set(shape)
    for (x, y) in s:
        put(L, x, y, fill)
    for (x, y) in s:
        for dx, dy, c in ((0, -1, hi), (-1, 0, hi), (0, 1, lo), (1, 0, lo)):
            q = (x + dx, y + dy)
            if q not in s:
                put(L, *q, c)


def draw_device(screen, led):
    L = blank()
    bx0, by0, bx1, by1 = 3, 3, 36, 59
    for y in range(H):
        for x in range(W):
            if not rrect_inside(x, y, bx0, by0, bx1, by1):
                continue
            edge = any(not rrect_inside(x + dx, y + dy, bx0, by0, bx1, by1)
                       for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if edge:
                c = OUT
            elif x == bx0 + 1 or y == by0 + 1:
                c = TH
            elif x == bx1 - 1 or y == by1 - 1:
                c = TSH
            else:
                c = T
            put(L, x, y, c)

    # rubber corner bumpers
    for (cx, cy, sx, sy) in ((3, 3, 1, 1), (36, 3, -1, 1), (3, 59, 1, -1), (36, 59, -1, -1)):
        for i in range(4):
            for j in range(4):
                x, y = cx + sx * i, cy + sy * j
                if L[y][x] is None or L[y][x] == OUT:
                    continue
                put(L, x, y, RUBHI if (i, j) == (1, 1) else RUB)
        put(L, cx + sx * 4, cy + sy * 1, TSH)
        put(L, cx + sx * 1, cy + sy * 4, TSH)

    # stub antenna, top right
    for (x, y, c) in ((30, 0, OUT), (29, 1, OUT), (30, 1, RUBHI), (31, 1, OUT),
                      (29, 2, OUT), (30, 2, RUB), (31, 2, OUT)):
        put(L, x, y, c)

    # stencil label above the screen
    for x in (12, 13, 15, 16, 17, 19, 20):
        put(L, x, 4, TMD)

    # recessed screen bezel
    ex0, ey0, ex1, ey1 = 6, 6, 33, 45
    for x in range(ex0, ex1 + 1):
        put(L, x, ey0 - 1, TSH)
        put(L, x, ey1 + 1, TH)
    for y in range(ey0, ey1 + 1):
        put(L, ex0 - 1, y, TSH)
        put(L, ex1 + 1, y, TH)
    for y in range(ey0, ey1 + 1):
        for x in range(ex0, ex1 + 1):
            if rrect_inside(x, y, ex0, ey0, ex1, ey1):
                put(L, x, y, BEZ)
    for x in range(SX0, SX0 + SW):
        put(L, x, ey1 - 1, BEZHI)

    # screen content + glass glare
    for y in range(SH):
        for x in range(SW):
            put(L, SX0 + x, SY0 + y, screen[y][x])
    for (x, y) in ((1, 2), (2, 1), (3, 0), (22, 35)):
        c = screen[y][x]
        put(L, SX0 + x, SY0 + y, tuple(int(v + (255 - v) * 0.45) for v in c))

    # controls: d-pad, two keys (one amber), status LED, speaker grille, screws
    pad = [(11, 50), (11, 51), (11, 52), (11, 53), (11, 54), (9, 52), (10, 52), (12, 52), (13, 52)]
    emboss(L, pad, RUB)
    put(L, 11, 50, RUBHI)
    emboss(L, [(x, y) for x in range(16, 19) for y in (49, 50)], RUB)
    put(L, 16, 49, RUBHI)
    emboss(L, [(x, y) for x in range(16, 19) for y in (53, 54)], AMBER)
    put(L, 18, 54, AMBER_DK)
    put(L, 21, 50, LED_GREEN if led == "green" else LED_AMBER)
    put(L, 21, 49, TSH)
    if led == "green":
        for q in ((20, 50), (22, 50), (21, 51)):
            put(L, *q, (150, 196, 150))
    for y in (49, 51, 53, 55):
        for x in range(25, 32):
            put(L, x, y, TDK)
            put(L, x, y + 1, TH)
    for (x, y) in ((6, 48), (33, 48)):
        put(L, x, y, TDK)
        put(L, x + 1, y + 1, TH)

    # wear, scratches, wasteland dust (same every frame)
    rnd = random.Random(5)
    cells = [(x, y) for y in range(H) for x in range(W) if L[y][x] == T]
    for p in rnd.sample(cells, 22):
        put(L, *p, TMD)
    for p in rnd.sample(cells, 6):
        put(L, *p, TSH)
    for p in ((26, 57), (27, 57), (28, 56), (4, 30), (4, 31), (4, 33)):
        put(L, *p, TH)
    for p in ((8, 58), (9, 58), (14, 58), (22, 58), (23, 58), (35, 44), (35, 45), (4, 52)):
        put(L, *p, DUST)
    return L


def compose(screen, led, press):
    dev = draw_device(screen, led)
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


def hover_outline(screen):
    m = mask_of(draw_device(screen, "amber"))
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    for y in range(H):
        for x in range(W):
            if not m[y][x] and any(0 <= x + dx < W and 0 <= y + dy < H and m[y + dy][x + dx]
                                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                px[x, y] = HOVER + (255,)
    return img


# ---------------------------------------------------------------- animation
CMAP = color_map()
BOOT = sonar()
GLOW = sonar(flash=True)
STEPS = 16
SWEEP = [90 - k * 360 / STEPS for k in range(STEPS)]


def F(screen, ms, led="amber", press=0, label="Color map", sweep=None):
    return {"screen": screen, "ms": ms, "led": led, "press": press,
            "label": label, "sweep": None if sweep is None else (90 - sweep) % 360}


ANIMS = {
    "off": [F(CMAP, 1000)],
    "power_on": [
        F(CMAP, 60, press=1),
        F(flip(CMAP, 0.66, "out"), 45, press=1, label="Flipping"),
        F(flip(CMAP, 0.30, "out"), 45, press=1, label="Flipping"),
        F(edge_on(), 40, led="green", label="Flipping"),
        F(flip(GLOW, 0.30, "in", shade=False), 45, led="green", label="Flipping"),
        F(flip(GLOW, 0.66, "in", shade=False), 45, led="green", label="Flipping"),
        F(sonar(flash=True), 60, led="green", label="Sonar"),
        F(sonar(ping=4), 70, led="green", label="Sonar · ping"),
        F(sonar(ping=10), 70, led="green", label="Sonar · ping"),
        F(sonar(ping=16), 70, led="green", label="Sonar · ping"),
        F(sonar(ping=22), 70, led="green", label="Sonar · ping"),
    ],
    "on": [F(sonar(theta=a), 90, led="green", label="Sonar", sweep=a) for a in SWEEP],
    "power_off": [
        F(sonar(theta=SWEEP[0]), 60, led="green", press=1, label="Sonar", sweep=SWEEP[0]),
        F(sonar(dim=1), 45, led="green", press=1, label="Flipping"),
        F(flip(BOOT, 0.66, "out", shade=False), 45, led="green", press=1, label="Flipping"),
        F(flip(BOOT, 0.30, "out", shade=False), 45, led="green", label="Flipping"),
        F(edge_on(), 40, label="Flipping"),
        F(flip(CMAP, 0.30, "in"), 45, label="Flipping"),
        F(flip(CMAP, 0.66, "in"), 45, label="Flipping"),
        F(CMAP, 80),
    ],
}
ROWS = ["off", "power_on", "on", "power_off"]


def sync_gdscript(path, const_name, meta):
    if not os.path.exists(path):
        return
    lines = [f"const {const_name} := {{"]
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
            im = compose(f["screen"], f["led"], f["press"])
            sheet.paste(im, (col * W, row * H))
            imgs[name].append(im)
            info.append({"x": col * W, "y": row * H, "ms": f["ms"], "pressed": bool(f["press"]),
                         "screen": f["label"], "sweep": f["sweep"], "led": f["led"]})
        meta["animations"][name] = {"row": row, "loop": name == "on", "frames": info}
    sheet.paste(hover_outline(CMAP), (W, 0))
    meta["hover_outline"] = {"x": W, "y": 0}
    sheet.save(os.path.join(out_dir, "sonar_tablet_sheet.png"))
    with open(os.path.join(out_dir, "sonar_tablet_frames.json"), "w") as fh:
        json.dump(meta, fh, indent=1)

    scale, bg, pad = 4, (196, 164, 116, 255), 6
    seq = [(imgs["off"][0], 700)]
    seq += [(im, f["ms"]) for im, f in zip(imgs["power_on"], ANIMS["power_on"])]
    for _ in range(2):
        seq += [(im, f["ms"]) for im, f in zip(imgs["on"], ANIMS["on"])]
    seq += [(im, f["ms"]) for im, f in zip(imgs["power_off"], ANIMS["power_off"])]
    seq += [(imgs["off"][0], 600)]
    frames = []
    for im, _ in seq:
        c = Image.new("RGBA", (W + pad * 2, H + pad * 2), bg)
        c.alpha_composite(im, (pad, pad))
        frames.append(c.convert("RGB").resize(((W + pad * 2) * scale, (H + pad * 2) * scale),
                                              Image.NEAREST))
    frames[0].save(os.path.join(out_dir, "sonar_tablet_preview.gif"), save_all=True,
                   append_images=frames[1:], duration=[ms for _, ms in seq], loop=0, disposal=1)

    sync_gdscript(os.path.join(out_dir, "sonar_tablet_button.gd"), "TABLET_ANIMS", meta)
    print("frames:", {k: len(v) for k, v in ANIMS.items()}, "sheet:", sheet.size)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__)))
