"""
Makes the 32 x 32 pictures of the points of interest and of the Giant Frog from their 16 x 16 originals in art/source/.

It is an algorithmic upscale (Scale2x: every pixel becomes 2 x 2, and diagonal edges are smoothed one step), not a redraw, so the
pictures have the new pixel size but no new detail; redraw them by hand to add some. Plain Python, no packages needed:

    python tools/upscale_sites.py

writes art/poi_atlas.png (10 sites, 32 x 32 each, one row), art/poi_atlas.json and the frog into art/animals.png (the deer and the
two bears stay 16 x 16 at the left; the frog is 32 x 32 at x = 48). Run `godot --headless --path . --import` afterwards.
"""
import json
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "..", "art")
SRC = os.path.join(ART, "source")


def read_png(path):
    d = open(path, "rb").read()
    pos, idat, plte, trns = 8, b"", None, None
    w = h = ct = bd = 0
    while pos < len(d):
        n, t = struct.unpack(">I4s", d[pos:pos + 8])
        body = d[pos + 8:pos + 8 + n]
        pos += 12 + n
        if t == b"IHDR":
            w, h, bd, ct = struct.unpack(">IIBB", body[:10])
        elif t == b"IDAT":
            idat += body
        elif t == b"PLTE":
            plte = body
        elif t == b"tRNS":
            trns = body
    assert bd == 8, "8-bit PNGs only"
    ch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
    raw, stride, prev, p, px = zlib.decompress(idat), w * ch, bytearray(w * ch), 0, []
    for _ in range(h):
        f, line = raw[p], bytearray(raw[p + 1:p + 1 + w * ch])
        p += 1 + stride
        for i in range(stride):
            a = line[i - ch] if i >= ch else 0
            b = prev[i]
            c = prev[i - ch] if i >= ch else 0
            if f == 1:
                line[i] = (line[i] + a) & 255
            elif f == 2:
                line[i] = (line[i] + b) & 255
            elif f == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
        for x in range(w):
            if ct == 6:
                px.append(tuple(line[x * 4:x * 4 + 4]))
            elif ct == 2:
                px.append(tuple(line[x * 3:x * 3 + 3]) + (255,))
            elif ct == 3:
                i = line[x]
                px.append(tuple(plte[i * 3:i * 3 + 3]) + (trns[i] if trns and i < len(trns) else 255,))
            elif ct == 0:
                px.append((line[x],) * 3 + (255,))
            else:
                px.append((line[x * 2],) * 3 + (line[x * 2 + 1],))
        prev = line
    return w, h, px


def write_png(path, w, h, px):
    raw = b"".join(b"\x00" + bytes(v for p in px[y * w:(y + 1) * w] for v in p) for y in range(h))

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def clear(p):
    return (0, 0, 0, 0) if p[3] == 0 else p


def scale2x(px, w, h):
    """Scale2x (AdvMAME2x): each pixel becomes 2 x 2; a corner takes a neighbour's colour where two neighbours agree and the others do not."""
    def at(x, y):
        return clear(px[min(max(y, 0), h - 1) * w + min(max(x, 0), w - 1)])
    out = [None] * (w * 2 * h * 2)
    for y in range(h):
        for x in range(w):
            p, a, b, c, d = at(x, y), at(x, y - 1), at(x + 1, y), at(x - 1, y), at(x, y + 1)
            e0 = a if (c == a and c != d and a != b) else p
            e1 = b if (a == b and a != c and b != d) else p
            e2 = c if (d == c and d != b and c != a) else p
            e3 = d if (b == d and b != a and d != c) else p
            i = (y * 2) * (w * 2) + x * 2
            out[i], out[i + 1], out[i + w * 2], out[i + w * 2 + 1] = e0, e1, e2, e3
    return out, w * 2, h * 2


def crop(px, w, x0, y0, cw, ch):
    return [px[(y0 + y) * w + x0 + x] for y in range(ch) for x in range(cw)]


def paste(dst, dw, src, sw, sh, ox, oy):
    for y in range(sh):
        for x in range(sw):
            dst[(oy + y) * dw + ox + x] = src[y * sw + x]


def main():
    # the sites: one row of 16 x 16 pictures becomes one row of 32 x 32
    w, h, px = read_png(os.path.join(SRC, "poi_atlas_16.png"))
    s, sw, sh = scale2x(px, w, h)
    write_png(os.path.join(ART, "poi_atlas.png"), sw, sh, s)
    meta = json.load(open(os.path.join(SRC, "poi_atlas_16.json")))
    meta["sprite_size_px"] = 32
    for e in meta["sprites"].values():
        for k in ("x", "y", "w", "h"):
            e[k] = int(e[k]) * 2
    json.dump(meta, open(os.path.join(ART, "poi_atlas.json"), "w"), indent=2, sort_keys=True)
    # the animals: the deer and bears as they were, the frog (the fourth) at 32 x 32
    w, h, px = read_png(os.path.join(SRC, "animals_16.png"))
    out = [(0, 0, 0, 0)] * (80 * 32)
    paste(out, 80, crop(px, w, 0, 0, 48, 16), 48, 16, 0, 0)
    frog, fw, fh = scale2x(crop(px, w, 48, 0, 16, 16), 16, 16)
    paste(out, 80, frog, fw, fh, 48, 0)
    write_png(os.path.join(ART, "animals.png"), 80, 32, out)
    print("wrote art/poi_atlas.png", (sw, sh), "and art/animals.png (80, 32)")


if __name__ == "__main__":
    sys.exit(main())
