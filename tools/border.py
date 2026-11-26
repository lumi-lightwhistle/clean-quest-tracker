"""Textures for the tracker's backdrop (UI/FrameBorder.lua): the bronze border, the skies' glow and the sample cards'
stars; and Moontide's wave on progress bars (Tracker/Progress.lua).
python tools/border.py Media

  BorderRing.tga             512x256, white with alpha (tinted in game). 32 quarter rings in 64px cells, 8 across:
                             cell i has inner radius / outer radius = i / 32, so cell 0 is a solid quarter disc. Each
                             ring fills the cell's top-left 62x62 with its arc centre at (62, 62), and runs on straight
                             for 2px past that, so texture filtering at the 62px edge samples the line rather than
                             empty space. Used for the rounded corners of the background and of each border layer.
  BorderCorner<Finish>.tga   256x256, in colour: the corner flourish (cap with stud, curls along both edges, leaves
                             and an outward finial) for the top-left corner. The other corners mirror it. It covers
                             art units -16..52 on both axes; one unit is one game pixel at 100% flourish size, and
                             (0, 0) is the corner of the border line.
  BorderCrest<Finish>.tga    256x128, in colour: the crest on the header (a diamond with a curl on each side). It
                             covers art units -32..32 across and -16..16 down, centred on (0, 0).
  BackdropGlow.tga           128x128, white with alpha: a soft glow, opaque at the centre and fading straight down to
                             nothing at an ellipse that fills the image (the Moonglow theme's moonlight, tinted in game).
  BackdropStars.tga          128x128, in colour, tiled: four one-pixel specks, two white at 30% and two pale blue at
                             22% (the Moonglow theme's stars; about the preview's one of each per 95x85 pixels).
  BarWave.tga                64x8, white with alpha, tiled across: one crest of Moontide's light on a smooth progress
                             bar (Tracker/Progress.lua). Opaque at the tile's middle, fading straight down to nothing a
                             third of the tile either side, so each crest is two thirds of TIDE_SPACING wide.

The art follows the approved design preview (not in the repo), which drew it at 2x. The flourish and
crest are coloured per finish rather than tinted, because each holds several colours (dark edge, metal gradient,
highlights). The finishes' five colours must match FINISHES in UI/FrameBorder.lua.
"""
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from img import seg_dist, write_tga, write_tga_rgba  # noqa: E402

FINISHES = {
    "Polished": ["f6e0ac", "c99456", "7b4b23", "d9a86a", "6a4120"],
    "Aged": ["dcc79b", "a7884f", "5d4a2f", "a18a5a", "463624"],
    "Dark": ["c48e5c", "80552f", "3a2412", "704828", "24160a"],
}
DARK = (28 / 255, 16 / 255, 6 / 255, 0.95)
SS = 4  # samples per pixel along each axis


def rgb(hex_colour):
    return tuple(int(hex_colour[i:i + 2], 16) / 255 for i in (0, 2, 4))


# ---------------------------------------------------------------------------------------------------------------------
# Paths: absolute M, L, H, V, C, Q and Z (Z must end its subpath), flattened to polylines
# ---------------------------------------------------------------------------------------------------------------------
def parse(d):
    tokens = re.findall(r"[MLHVCQZ]|-?(?:\d+\.?\d*|\.\d+)", d)
    subpaths, current, x, y, i, cmd = [], None, 0.0, 0.0, 0, None
    while i < len(tokens):
        if tokens[i] in "MLHVCQZ":
            cmd = tokens[i]
            i += 1
            if cmd == "Z":
                current.append(current[0])
                continue

        def num(k):
            return float(tokens[i + k])
        if cmd == "M":
            x, y = num(0), num(1)
            current = [(x, y)]
            subpaths.append(current)
            i += 2
            cmd = "L"
        elif cmd == "L":
            x, y = num(0), num(1)
            current.append((x, y))
            i += 2
        elif cmd == "H":
            x = num(0)
            current.append((x, y))
            i += 1
        elif cmd == "V":
            y = num(0)
            current.append((x, y))
            i += 1
        elif cmd == "C":
            p0, p1, p2, p3 = (x, y), (num(0), num(1)), (num(2), num(3)), (num(4), num(5))
            for step in range(1, 25):
                t = step / 24
                u = 1 - t
                current.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                                u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
            x, y = p3
            i += 6
        elif cmd == "Q":
            p0, p1, p2 = (x, y), (num(0), num(1)), (num(2), num(3))
            for step in range(1, 13):
                t = step / 12
                u = 1 - t
                current.append((u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
                                u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]))
            x, y = p2
            i += 4
    # Repeated points (a Z back onto the start, say) would make zero-length segments.
    return [[p for k, p in enumerate(sub) if k == 0 or p != sub[k - 1]] for sub in subpaths]


def circle(cx, cy, r):
    return [[(cx + r * math.cos(a * math.pi / 32), cy + r * math.sin(a * math.pi / 32)) for a in range(65)]]


def mirror(subpaths):
    """Mirrors a shape left to right. Its op is marked mirrored too, so its gradient flips with it, as under SVG's
    scale(-1 1)."""
    return [[(-px, py) for px, py in sub] for sub in subpaths]


def bbox(subpaths):
    xs = [p[0] for sub in subpaths for p in sub]
    ys = [p[1] for sub in subpaths for p in sub]
    return min(xs), min(ys), max(xs), max(ys)


def inside(subpaths, px, py):
    hit = False
    for sub in subpaths:
        for (ax, ay), (bx, by) in zip(sub, sub[1:]):
            if (ay > py) != (by > py) and px < ax + (py - ay) * (bx - ax) / (by - ay):
                hit = not hit
    return hit


def near(subpaths, px, py, half):
    for sub in subpaths:
        for (ax, ay), (bx, by) in zip(sub, sub[1:]):
            if seg_dist(px, py, ax, ay, bx, by) <= half:
                return True
    return False


# ---------------------------------------------------------------------------------------------------------------------
# Paints. Gradients use the shape's own box, as SVG's objectBoundingBox does.
# ---------------------------------------------------------------------------------------------------------------------
def ramp(stops, t):
    t = max(0.0, min(1.0, t))
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            k = 0 if t1 == t0 else (t - t0) / (t1 - t0)
            return tuple(a + (b - a) * k for a, b in zip(c0, c1))
    return stops[-1][1]


def metal(tones):
    """The flourish metal: a diagonal gradient, light at the top left of the shape."""
    colours = [rgb(tones[i]) for i in (0, 1, 3, 2, 4)]
    stops = [(i / 4, c) for i, c in enumerate(colours)]

    def paint(u, v):
        return ramp(stops, (u + v) / 2) + (1.0,)
    return paint


def gloss(tones):
    """The stud and the crest's centre: a round highlight up and left of centre."""
    stops = [(0, rgb(tones[0])), (0.45, rgb(tones[1])), (1, rgb(tones[4]))]

    def paint(u, v):
        return ramp(stops, math.hypot(u - 0.35, v - 0.3) / 0.75) + (1.0,)
    return paint


def solid(colour):
    return lambda u, v: colour


# ---------------------------------------------------------------------------------------------------------------------
# Drawing: each operation is (geometry, "fill" or a stroke width, paint name[, mirrored]). Coverage is computed once
# per operation and shared by every finish.
# ---------------------------------------------------------------------------------------------------------------------
def coverage(op, width, height, to_art):
    subpaths, kind = op[0], op[1]
    x0, y0, x1, y1 = bbox(subpaths)
    margin = 0 if kind == "fill" else kind / 2 + 0.01
    scale, ox, oy = to_art
    cols = range(max(0, int((x0 - margin - ox) * scale) - 1), min(width, int((x1 + margin - ox) * scale) + 2))
    rows = range(max(0, int((y0 - margin - oy) * scale) - 1), min(height, int((y1 + margin - oy) * scale) + 2))
    result = {}
    for py in rows:
        for px in cols:
            hits = 0
            for sy in range(SS):
                for sx in range(SS):
                    ax = ox + (px + (sx + 0.5) / SS) / scale
                    ay = oy + (py + (sy + 0.5) / SS) / scale
                    if kind == "fill" and inside(subpaths, ax, ay) or kind != "fill" and near(subpaths, ax, ay, kind / 2):
                        hits += 1
            if hits:
                result[(px, py)] = hits / (SS * SS)
    return result


def compose(ops, covers, paints, width, height, to_art):
    scale, ox, oy = to_art
    image = [[[0.0, 0.0, 0.0, 0.0] for _ in range(width)] for _ in range(height)]  # premultiplied
    for op, cover, paint in zip(ops, covers, paints):
        x0, y0, x1, y1 = bbox(op[0])
        bw, bh = max(x1 - x0, 1e-6), max(y1 - y0, 1e-6)
        for (px, py), amount in cover.items():
            ax, ay = ox + (px + 0.5) / scale, oy + (py + 0.5) / scale
            u = (ax - x0) / bw
            r, g, b, a = paint(1 - u if len(op) > 3 and op[3] else u, (ay - y0) / bh)
            k = amount * a
            pixel = image[py][px]
            pixel[0] = r * k + pixel[0] * (1 - k)
            pixel[1] = g * k + pixel[1] * (1 - k)
            pixel[2] = b * k + pixel[2] * (1 - k)
            pixel[3] = k + pixel[3] * (1 - k)
    return [[(p[0] / p[3], p[1] / p[3], p[2] / p[3], p[3]) if p[3] > 0 else (0, 0, 0, 0) for p in row]
            for row in image]


def corner_ops():
    """(geometry, kind, paint name) in the preview's order: curls, leaves, cap, highlight, stud."""
    ops = []
    for d in ("M26 -2C32 -10 42 -11 46 -5C49 -.5 44 2.5 41 -.5C39 -2.5 41.5 -5 43.5 -3.5",
              "M-2 26C-10 32 -11 42 -5 46C-.5 49 2.5 44 -.5 41C-2.5 39 -5 41.5 -3.5 43.5"):
        ops += [(parse(d), 2.9, "dark"), (parse(d), 1.7, "metal")]
    for d, edge in (("M30 -6.5C27 -13 21 -15 15 -14C19 -10 24 -7.5 30 -6.5Z", 0.6),
                    ("M-6.5 30C-13 27 -15 21 -14 15C-10 19 -7.5 24 -6.5 30Z", 0.6),
                    ("M-3 -3C-4 -9 -9 -14 -15 -15C-14 -9 -9 -4 -3 -3Z", 0.6),
                    ("M24 -.75L20 -4H-1Q-4 -4 -4 -1V20L-.75 24L2.5 20V5Q2.5 2.5 5 2.5H20Z", 0.7)):
        ops += [(parse(d), "fill", "metal"), (parse(d), edge, "dark")]
    ops.append((parse("M20 -.9H4Q-.9 -.9 -.9 4V20"), 0.55, "shine"))
    ops += [(circle(-0.6, -0.6, 3.7), "fill", "gloss"), (circle(-0.6, -0.6, 3.7), 0.7, "dark"),
            (circle(-1.7, -1.8, 1), "fill", "spark")]
    return ops


def crest_ops():
    curl = parse("M-8 -1C-13 -8 -22 -9 -26 -3.5C-28.5 0 -24.5 2.5 -22.5 .3C-21 -1.3 -22.5 -3.3 -24 -2.3")
    ops = []
    for side, flipped in ((curl, False), (mirror(curl), True)):
        ops += [(side, 2.8, "dark", flipped), (side, 1.6, "metal", flipped)]
    outer, inner = parse("M0 -9L6.5 0L0 9L-6.5 0Z"), parse("M0 -4.2L3 0L0 4.2L-3 0Z")
    ops += [(outer, "fill", "metal"), (outer, 0.7, "dark"), (inner, "fill", "gloss"), (inner, 0.5, "dark")]
    return ops


def paints_for(ops, tones):
    table = {
        "dark": solid(DARK),
        "metal": metal(tones),
        "gloss": gloss(tones),
        "shine": solid((1.0, 236 / 255, 196 / 255, 0.45)),
        "spark": solid((1.0, 244 / 255, 214 / 255, 0.85)),
    }
    return [table[op[2]] for op in ops]


def art(name, ops, width, height, to_art, out):
    covers = [coverage(op, width, height, to_art) for op in ops]
    for finish, tones in FINISHES.items():
        write_tga_rgba(f"{out}{name}{finish}.tga", compose(ops, covers, paints_for(ops, tones), width, height, to_art))


def ring_atlas(out):
    width, height, cell, region = 512, 256, 64, 62
    alpha = [[0.0] * width for _ in range(height)]
    for index in range(32):
        cx, cy = (index % 8) * cell, (index // 8) * cell
        outer, inner = float(region), region * index / 32
        for y in range(cell):
            for x in range(cell):
                hits = 0
                for sy in range(SS):
                    for sx in range(SS):
                        dx = max(region - (x + (sx + 0.5) / SS), 0.0)
                        dy = max(region - (y + (sy + 0.5) / SS), 0.0)
                        if inner <= math.hypot(dx, dy) <= outer:
                            hits += 1
                alpha[cy + y][cx + x] = hits / (SS * SS)
    write_tga(out + "BorderRing.tga", alpha)


def glow(out):
    size = 128
    alpha = [[0.0] * size for _ in range(size)]
    for y in range(size):
        for x in range(size):
            hits = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    u = (x + (sx + 0.5) / SS) / size * 2 - 1
                    v = (y + (sy + 0.5) / SS) / size * 2 - 1
                    hits += max(0.0, 1 - math.hypot(u, v))
            alpha[y][x] = hits / (SS * SS)
    write_tga(out + "BackdropGlow.tga", alpha)


def stars(out):
    size = 128
    # Empty pixels are white at no opacity, so scaling blends the specks with white, not black.
    rows = [[(1.0, 1.0, 1.0, 0.0)] * size for _ in range(size)]
    white, blue = (1.0, 1.0, 1.0, 0.30), (220 / 255, 235 / 255, 1.0, 0.22)
    for (x, y), colour in (((23, 31), white), ((97, 92), white), ((71, 62), blue), ((12, 109), blue)):
        rows[y][x] = colour
    write_tga_rgba(out + "BackdropStars.tga", rows)


def wave(out):
    width, height = 64, 8
    row = []
    for x in range(width):
        hits = 0.0
        for sx in range(SS):
            u = (x + (sx + 0.5) / SS) / width
            hits += max(0.0, 1 - abs(u - 0.5) * 3)
        row.append(hits / SS)
    write_tga(out + "BarWave.tga", [list(row) for _ in range(height)])


if __name__ == "__main__":
    target = os.path.join(sys.argv[1] if len(sys.argv) > 1 else "Media", "")
    ring_atlas(target)
    art("BorderCorner", corner_ops(), 256, 256, (256 / 68, -16.0, -16.0), target)
    art("BorderCrest", crest_ops(), 256, 128, (4.0, -32.0, -16.0), target)
    glow(target)
    stars(target)
    wave(target)
    print("done")
