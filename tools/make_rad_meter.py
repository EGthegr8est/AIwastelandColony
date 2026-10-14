"""
Pixel-art radiation survey meter button for a 2D wasteland game.

Draws every frame procedurally at native resolution (40x64) so the art can be
tweaked by changing a few numbers and re-running:

    python3 make_rad_meter.py [out_dir]

Outputs:
    rad_meter_sheet.png    sprite sheet, one animation per row
    rad_meter_frames.json  frame regions + per-frame durations (ms)
    rad_meter_preview.gif  4x preview of a full on/off cycle
"""
import json
import math
import os
import random
import sys

from PIL import Image

W, H = 40, 64

# ---------------------------------------------------------------- palette
OUT = (38, 28, 14)
YHI = (250, 222, 92)
Y = (228, 188, 40)
YMD = (206, 164, 30)
YSH = (166, 124, 24)
YDK = (108, 78, 18)
BLK = (24, 22, 26)
BLKMD = (46, 44, 50)
BLKHI = (88, 86, 96)
TICK = (58, 54, 50)
RED = (196, 44, 32)
MET = (170, 170, 162)
METHI = (236, 236, 228)
METSH = (98, 98, 94)
NEEDLE = (18, 18, 18)
RUST = (136, 84, 36)
GLINT = (255, 255, 248)
SHADOW = (0, 0, 0, 80)
HOVER = (255, 244, 170)

# Dial face: unlit cream -> radium-green glow, 4 steps (face, face-shadow)
FACE_LEVELS = [
    ((234, 228, 208), (198, 190, 168)),
    ((228, 236, 194), (190, 200, 158)),
    ((218, 242, 178), (178, 210, 146)),
    ((204, 248, 160), (160, 220, 130)),
]

# Selector knob detents (degrees, 0 = right, counter-clockwise)
KNOB = {"check": 220, "off": 180, "zero": 140, "x100": 100, "x10": 60}

# Gauge geometry
DIAL_C = (20.0, 17.0)      # dial centre (continuous coords)
PIVOT = (20.0, 23.5)       # needle pivot
ARC_R = 10.0
ANG_0, ANG_5 = 145.0, 35.0  # needle angle at 0 and at 5 r/hr
NEEDLE_LEN = 9.0
KNOB_C = (13.0, 41.0)
ZERO_C = (10.0, 52.0)


def v_to_ang(v):
    return ANG_0 + (ANG_5 - ANG_0) * (v / 5.0)


# ---------------------------------------------------------------- helpers
def blank():
    return [[None] * W for _ in range(H)]


def put(L, x, y, c):
    if 0 <= x < W and 0 <= y < H:
        L[y][x] = c


def dist(x, y, c):
    return math.hypot(x + 0.5 - c[0], y + 0.5 - c[1])


def angle(x, y, c):
    return math.degrees(math.atan2(-(y + 0.5 - c[1]), x + 0.5 - c[0])) % 360


def bresenham(x0, y0, x1, y1):
    pts = []
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        pts.append((x0, y0))
        if x0 == x1 and y0 == y1:
            return pts
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def pixel_perfect(pts):
    """Drop the corner pixel of any L-shaped step so lines stay 1px thin."""
    out = []
    for p in pts:
        if out and out[-1] == p:
            continue
        out.append(p)
    i = 1
    while i < len(out) - 1:
        a, b, c = out[i - 1], out[i], out[i + 1]
        if (a[0] == b[0] or a[1] == b[1]) and (c[0] == b[0] or c[1] == b[1]) \
                and a[0] != c[0] and a[1] != c[1]:
            del out[i]
        else:
            i += 1
    return out


def arc_pixels(r, a0, a1, c=PIVOT):
    pts, steps = [], 400
    for i in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        pts.append((math.floor(c[0] + r * math.cos(a)),
                    math.floor(c[1] - r * math.sin(a))))
    return pixel_perfect(pts)


def rrect_inside(x, y, x0, y0, x1, y1):
    if not (x0 <= x <= x1 and y0 <= y <= y1):
        return False
    return not ((x in (x0, x1)) and (y in (y0, y1)))


# ---------------------------------------------------------------- the meter
def draw_device(knob_deg, needle_v, glow):
    L = blank()

    # --- body (rounded box) ---
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
                c = YHI
            elif x == bx1 - 1 or y == by1 - 1:
                c = YSH
            else:
                c = Y
            put(L, x, y, c)

    # --- strap loop, top right ---
    for x in range(28, 35):
        put(L, x, 1, OUT)
    for x in (27, 34):
        put(L, x, 2, OUT)
    for x in range(28, 34):
        put(L, x, 2, YHI if x < 30 else Y)

    # --- bottom-left strap tab ---
    for x in range(4, 12):
        put(L, x, 61, OUT)
    put(L, 4, 60, OUT)
    put(L, 11, 60, OUT)
    for x in range(5, 11):
        put(L, x, 60, METSH if 6 <= x <= 9 else MET)

    # --- latch clip, top centre ---
    for x in range(17, 23):
        put(L, x, 0, OUT)
    for y in (1, 2):
        put(L, 16, y, OUT)
        put(L, 23, y, OUT)
        for x in range(17, 23):
            put(L, x, y, METHI if (x < 19 and y == 1) else (MET if y == 1 else METSH))

    # --- bezel + face ---
    face, face_sh = FACE_LEVELS[glow]
    for y in range(H):
        for x in range(W):
            d = dist(x, y, DIAL_C)
            a = angle(x, y, DIAL_C)
            dy = y + 0.5 - DIAL_C[1]
            dx = x + 0.5 - DIAL_C[0]
            if d <= 10.5:
                c = face
                if dy > 6.2 or (d > 9.6 and dy < -2):
                    c = face_sh
                put(L, x, y, c)
            elif d <= 13.0:
                c = BLK
                if 11.2 < d <= 12.3 and 105 <= a <= 165:
                    c = BLKHI
                elif 11.2 < d <= 12.3 and (285 <= a <= 340):
                    c = BLKMD
                put(L, x, y, c)
            elif d <= 14.0 and dx + dy > 5 and L[y][x] in (Y, YHI):
                put(L, x, y, YSH)          # bezel casts a shadow down-right

    # glass glint
    for p in ((12, 10), (13, 9), (14, 8)):
        put(L, *p, GLINT)
    put(L, 26, 25, GLINT)

    # bezel screws
    for sx in (8, 31):
        put(L, sx, 21, MET)
        put(L, sx, 22, METSH)

    # --- scale arc, ticks, red check band ---
    red_from = v_to_ang(3.8)
    for y in range(4, 24):                         # solid red "circuit check" band
        for x in range(8, 32):
            r = dist(x, y, PIVOT)
            a = angle(x, y, PIVOT)
            if ARC_R - 1.6 <= r <= ARC_R + 0.6 and ANG_5 - 3 <= a <= red_from \
                    and dist(x, y, DIAL_C) <= 10.0:
                put(L, x, y, RED)
    for (x, y) in arc_pixels(ARC_R, ANG_0, red_from + 1):
        put(L, x, y, TICK)
    for v in (1, 2, 3):                            # major ticks
        a = math.radians(v_to_ang(v))
        x = math.floor(PIVOT[0] + (ARC_R + 1.0) * math.cos(a))
        y = math.floor(PIVOT[1] - (ARC_R + 1.0) * math.sin(a))
        put(L, x, y, TICK)

    # "r/hr" suggestion
    for p in ((18, 18), (19, 18), (21, 18)):
        put(L, *p, face_sh)

    # --- needle ---
    a = math.radians(v_to_ang(needle_v))
    sx = 19 if math.cos(a) < 0 else 20
    tx = math.floor(PIVOT[0] + NEEDLE_LEN * math.cos(a))
    ty = math.floor(PIVOT[1] - NEEDLE_LEN * math.sin(a))
    for (x, y) in bresenham(sx, 23, tx, ty):
        put(L, x, y, NEEDLE)

    # pivot cap + zero-adjust mechanism
    for y in range(20, 25):
        for x in range(16, 24):
            if math.hypot(x + 0.5 - 20.0, y + 0.5 - 24.5) <= 2.6 and y <= 24:
                put(L, x, y, BLK)
    put(L, 19, 22, BLKMD)
    put(L, 19, 25, METHI)
    put(L, 20, 25, MET)
    put(L, 19, 26, MET)
    put(L, 20, 26, METSH)

    # --- lower plate ---
    px0, py0, px1, py1 = 5, 31, 34, 57
    for x in range(px0, px1 + 1):
        put(L, x, py0, YHI)
        put(L, x, py1, YSH)
        put(L, x, py1 + 1, YMD)
    for y in range(py0, py1 + 1):
        put(L, px0, y, YHI)
        put(L, px1, y, YSH)
    put(L, px1, py0, Y)
    put(L, px0, py1, Y)

    # --- selector knob ---
    for y in range(34, 49):
        for x in range(6, 21):
            d = dist(x, y, KNOB_C)
            if d <= 3.0:
                put(L, x, y, BLK)
            elif d <= 3.9:
                put(L, x, y, YDK)
    for (x, y) in ((11, 39), (12, 39)):
        put(L, x, y, BLKHI)
    for deg in KNOB.values():                      # detent ticks + label dashes
        a = math.radians(deg)
        put(L, math.floor(KNOB_C[0] + 4.8 * math.cos(a)),
            math.floor(KNOB_C[1] - 4.8 * math.sin(a)), YDK)
        if deg != 60:                              # X10 label hides behind handle
            for r in (6.4, 7.4):
                put(L, math.floor(KNOB_C[0] + r * math.cos(a)),
                    math.floor(KNOB_C[1] - r * math.sin(a)), YSH)
    a = math.radians(knob_deg)                    # chrome pointer bar
    pts = []
    for i in range(0, 36):
        r = 0.2 + i * 0.1
        pts.append((math.floor(KNOB_C[0] + r * math.cos(a)),
                    math.floor(KNOB_C[1] - r * math.sin(a))))
    for (x, y) in pixel_perfect(pts):
        put(L, x, y, METHI)
    tail = (math.floor(KNOB_C[0] - 1.6 * math.cos(a)),
            math.floor(KNOB_C[1] + 1.6 * math.sin(a)))
    put(L, *tail, METSH)

    # --- zero button ---
    for y in range(47, 57):
        for x in range(5, 15):
            d = dist(x, y, ZERO_C)
            if d <= 2.2:
                put(L, x, y, BLK)
            elif d <= 3.2:
                put(L, x, y, YDK)
    put(L, 9, 51, BLKHI)
    for x in range(8, 12):
        put(L, x, 47, YSH)

    # --- illegible maker's markings (rotated text) ---
    random.seed(3)
    for col, (y0, y1) in zip((27, 29, 31), ((40, 55), (38, 55), (36, 54))):
        y = y0
        while y <= y1:
            run = random.choice((1, 2, 2, 3))
            for k in range(run):
                if y + k <= y1:
                    put(L, col, y + k, YDK)
            y += run + 1
    for y in range(36, 43):                        # dark stamp
        put(L, 32, y, YDK)

    # --- carry handle ---
    hx0, hy0, hx1, hy1 = 17, 28, 22, 61
    for y in range(29, 60):                        # cast shadow to the right
        if L[y][23] in (Y, YHI, YMD) or L[y][23] == YSH:
            put(L, 23, y, YSH if y < 57 else YDK)
        if L[y][24] in (Y, YHI):
            put(L, 24, y, YMD)
    for y in range(hy0, hy1 + 1):
        for x in range(hx0, hx1 + 1):
            if not rrect_inside(x, y, hx0, hy0, hx1, hy1):
                continue
            edge = any(not rrect_inside(x + dx, y + dy, hx0, hy0, hx1, hy1)
                       for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if edge:
                c = OUT
            elif y == hy0 + 1:
                c = YHI
            elif y == hy1 - 1:
                c = YSH
            elif x == hx0 + 1:
                c = YHI
            elif x == hx1 - 1:
                c = YSH
            else:
                c = Y
            put(L, x, y, c)
    for y in range(31, 58, 1):                     # seam line down the grip
        if y % 7 != 3:
            put(L, 19, y, YMD)

    # --- wear & grime (same every frame) ---
    random.seed(11)
    cells = [(x, y) for y in range(H) for x in range(W) if L[y][x] == Y]
    for (x, y) in random.sample(cells, 26):
        put(L, x, y, YMD)
    for (x, y) in random.sample(cells, 8):
        put(L, x, y, YSH)
    for p in ((4, 12), (35, 47), (4, 40), (21, 58)):
        put(L, *p, RUST)
    for p in ((5, 12), (35, 48), (20, 59)):
        put(L, *p, METSH)
    return L


def mask_of(L):
    return [[L[y][x] is not None for x in range(W)] for y in range(H)]


def compose(state):
    """state: knob(deg), v(needle), glow(0-3), press(0/1) -> RGBA image."""
    dev = draw_device(state["knob"], state["v"], state["glow"])
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    m = mask_of(dev)
    px = img.load()
    for y in range(H):                             # ground shadow (fixed)
        for x in range(W):
            sx, sy = x - 1, y - 2
            if 0 <= sx < W and 0 <= sy < H and m[sy][sx]:
                px[x, y] = SHADOW
    dy = state.get("press", 0)
    for y in range(H):
        for x in range(W):
            c = dev[y][x]
            if c is not None and 0 <= y + dy < H:
                px[x, y + dy] = c + (255,)
    return img


def hover_outline():
    m = mask_of(draw_device(KNOB["off"], REST, 0))
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    for y in range(H):
        for x in range(W):
            if m[y][x]:
                continue
            if any(0 <= x + dx < W and 0 <= y + dy < H and m[y + dy][x + dx]
                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                px[x, y] = HOVER + (255,)
    return img


# ---------------------------------------------------------------- animation
REST = -0.3
K = KNOB


def S(knob, v, glow, press=0, ms=80):
    return {"knob": K[knob], "knob_name": knob, "v": v, "glow": glow,
            "press": press, "ms": ms}


ANIMS = {
    # row 0 col 0 = idle off; col 1 = hover outline overlay (not a state)
    "off": [S("off", REST, 0, ms=1000)],
    "power_on": [
        S("off", REST, 0, 1, 60),     # press
        S("zero", REST, 0, 1, 70),    # click
        S("x100", 0.3, 1, 1, 70),     # click
        S("x10", 1.6, 2, 0, 60),      # click, release
        S("x10", 3.2, 3, 0, 50),
        S("x10", 4.4, 3, 0, 50),      # swings into the red band
        S("x10", 4.95, 3, 0, 70),     # pegs
        S("x10", 4.2, 3, 0, 50),
        S("x10", 2.8, 3, 0, 50),
        S("x10", 1.6, 3, 0, 60),
        S("x10", 0.9, 3, 0, 60),
        S("x10", 1.45, 3, 0, 70),
        S("x10", 1.1, 3, 0, 80),
        S("x10", 1.25, 3, 0, 100),
    ],
    "on": [  # looping idle: needle wanders, one bulb flicker
        S("x10", 1.25, 3, ms=160),
        S("x10", 1.4, 3, ms=140),
        S("x10", 1.15, 3, ms=180),
        S("x10", 1.35, 3, ms=120),
        S("x10", 1.55, 2, ms=70),
        S("x10", 1.3, 3, ms=160),
        S("x10", 1.05, 3, ms=200),
        S("x10", 1.3, 3, ms=150),
    ],
    "power_off": [
        S("x10", 1.25, 3, 1, 60),
        S("x100", 1.0, 3, 1, 70),
        S("zero", 0.6, 2, 1, 70),
        S("off", 0.1, 1, 0, 70),
        S("off", -0.35, 0, 0, 60),    # undershoot
        S("off", 0.05, 1, 0, 60),     # dying flicker
        S("off", REST, 0, 0, 120),
    ],
}
ROWS = ["off", "power_on", "on", "power_off"]


def main(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    cols = max(len(ANIMS[a]) for a in ROWS)
    sheet = Image.new("RGBA", (cols * W, len(ROWS) * H), (0, 0, 0, 0))
    meta = {"frame_w": W, "frame_h": H, "animations": {}}
    frames_by_anim = {}
    for row, name in enumerate(ROWS):
        imgs, info = [], []
        for col, st in enumerate(ANIMS[name]):
            im = compose(st)
            sheet.paste(im, (col * W, row * H))
            imgs.append(im)
            info.append({"x": col * W, "y": row * H, "ms": st["ms"],
                         "pressed": bool(st["press"]), "needle": st["v"],
                         "knob": st["knob_name"], "glow": st["glow"]})
        frames_by_anim[name] = imgs
        meta["animations"][name] = {"row": row, "loop": name == "on",
                                    "frames": info}
    sheet.paste(hover_outline(), (W, 0))
    meta["hover_outline"] = {"x": W, "y": 0}
    sheet.save(os.path.join(out_dir, "rad_meter_sheet.png"))
    with open(os.path.join(out_dir, "rad_meter_frames.json"), "w") as f:
        json.dump(meta, f, indent=1)

    # 4x preview GIF of a full cycle on a sand background
    scale, bg = 4, (196, 164, 116, 255)
    seq = [(frames_by_anim["off"][0], 700)]
    seq += list(zip(frames_by_anim["power_on"],
                    [s["ms"] for s in ANIMS["power_on"]]))
    for _ in range(3):
        seq += list(zip(frames_by_anim["on"], [s["ms"] for s in ANIMS["on"]]))
    seq += list(zip(frames_by_anim["power_off"],
                    [s["ms"] for s in ANIMS["power_off"]]))
    seq += [(frames_by_anim["off"][0], 600)]
    pad = 6
    out = []
    for im, ms in seq:
        canvas = Image.new("RGBA", (W + pad * 2, H + pad * 2), bg)
        canvas.alpha_composite(im, (pad, pad))
        out.append(canvas.convert("RGB").resize(
            ((W + pad * 2) * scale, (H + pad * 2) * scale), Image.NEAREST))
    out[0].save(os.path.join(out_dir, "rad_meter_preview.gif"), save_all=True,
                append_images=out[1:], duration=[ms for _, ms in seq],
                loop=0, disposal=1)
    sync_gdscript(out_dir, meta)
    print("frames:", {k: len(v) for k, v in ANIMS.items()}, "sheet:", sheet.size)


def sync_gdscript(out_dir, meta):
    """Rewrite the ANIMS table inside rad_meter_button.gd so it matches the sheet."""
    gd = os.path.join(out_dir, "rad_meter_button.gd")
    if not os.path.exists(gd):
        return
    lines = ["const ANIMS := {"]
    for name in ROWS:
        a = meta["animations"][name]
        rows, prev = [], None
        for f in a["frames"]:
            detent = 1 if (prev is not None and f["knob"] != prev) else 0
            rows.append(f"[{f['x']}, {f['y']}, {f['ms']}, {detent}]")
            prev = f["knob"]
        lines.append(f'\t"{name}": {{"loop": {str(a["loop"]).lower()}, "frames": [')
        for i in range(0, len(rows), 4):
            lines.append("\t\t" + ", ".join(rows[i:i + 4]) + ",")
        lines.append("\t]},")
    lines.append("}")
    begin = "# --- FRAMES BEGIN"
    end = "# --- FRAMES END ---"
    src = open(gd).read()
    head, rest = src.split(begin, 1)
    marker_line, rest = rest.split("\n", 1)
    _, tail = rest.split(end, 1)
    open(gd, "w").write(head + begin + marker_line + "\n" + "\n".join(lines)
                        + "\n" + end + tail)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__)))
