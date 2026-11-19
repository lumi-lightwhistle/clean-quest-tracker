"""Draws the icon tiles used in the CurseForge description (docs/icons/tile-*.png).

Each tile is the whole thing: the gold rim, the dark fill and a full-colour icon centred inside it with the same space on
every side. CurseForge strips padding, margins and heights from description HTML and sizes emoji its own way, so a tile
built from boxes and text never comes out the same twice; a fixed-size picture does. The page shows each tile at 44px;
the files are drawn at twice that so they stay sharp on high-density screens.

Icons are laid out on a 32-unit grid and placed in the tile's centre. Unlike the add-on's own textures (white with alpha,
tinted in game), these are finished colour images.

Run from the repository root:  python tools/card_icons.py
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from img import render, seg_dist, write_png  # noqa: E402

SIZE = 88  # pixels; shown at 44px
TILE = 44.0  # tile units (CSS pixels on the page)
RIM, RADIUS = 2.0, 8.0  # a 2px gold rim and 8px corners
ICON = 26.0  # the icon's square, centred: (44 - 26) / 2 = 9 units of space on every side
GRID = 32.0  # icon drawing units
RIM_COLOUR, FILL_COLOUR = "c9922d", "2a2015"


def hexrgb(value):
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


# Icon shapes take a point in icon units (0-32 across the icon's square).
def circle(cx, cy, r):
    return lambda px, py: math.hypot(px - cx, py - cy) <= r


def dome(cx, base, rx, ry):
    """The top half of an ellipse standing on `base`: a figure's shoulders."""
    return lambda px, py: py <= base and ((px - cx) / rx) ** 2 + ((py - base) / ry) ** 2 <= 1


def bowl(cx, top, rx, ry):
    """The bottom half of an ellipse hanging from `top`: the point of a shield."""
    return lambda px, py: py >= top and ((px - cx) / rx) ** 2 + ((py - top) / ry) ** 2 <= 1


def rounded(x0, y0, w, h, r):
    def inside(px, py):
        cx = min(max(px, x0 + r), x0 + w - r)
        cy = min(max(py, y0 + r), y0 + h - r)
        return math.hypot(px - cx, py - cy) <= r
    return inside


def polygon(points):
    def inside(px, py):
        hit = False
        for (ax, ay), (bx, by) in zip(points, points[1:] + points[:1]):
            if (ay > py) != (by > py) and px < ax + (py - ay) * (bx - ax) / (by - ay):
                hit = not hit
        return hit
    return inside


def stroke(points, width):
    def inside(px, py):
        return any(seg_dist(px, py, ax, ay, bx, by) <= width / 2 for (ax, ay), (bx, by) in zip(points, points[1:]))
    return inside


def link(ax, ay, bx, by, r_out, r_in):
    """A chain link: the outline of a capsule from a to b."""
    def inside(px, py):
        d = seg_dist(px, py, ax, ay, bx, by)
        return r_in <= d <= r_out
    return inside


def union(*shapes):
    return lambda px, py: any(shape(px, py) for shape in shapes)


def minus(shape, cut):
    return lambda px, py: shape(px, py) and not cut(px, py)


def where(shape, test):
    return lambda px, py: shape(px, py) and test(px, py)


def tile_rect(inset, radius):
    """The tile's own rounded square, in tile units."""
    def inside(tx, ty):
        lo, hi = inset + radius, TILE - inset - radius
        cx, cy = min(max(tx, lo), hi), min(max(ty, lo), hi)
        return math.hypot(tx - cx, ty - cy) <= radius
    return inside


def compose(path, icon_layers):
    """The rim, the fill, then the icon's (shape, colour) layers, bottom to top, written as a PNG."""
    offset, scale = (TILE - ICON) / 2, ICON / GRID

    def frame(shape):
        return lambda x, y: shape(x * TILE, y * TILE)

    def icon(shape):
        return lambda x, y: shape((x * TILE - offset) / scale, (y * TILE - offset) / scale)

    layers = [(frame(tile_rect(0, RADIUS)), RIM_COLOUR), (frame(tile_rect(RIM, RADIUS - RIM)), FILL_COLOUR)]
    layers += [(icon(shape), colour) for shape, colour in icon_layers]
    rgba = [[(0.0, 0.0, 0.0, 0.0)] * SIZE for _ in range(SIZE)]
    for shape, colour in layers:
        cover = render(shape, SIZE)
        r, g, b = (c / 255.0 for c in hexrgb(colour))
        for y in range(SIZE):
            for x in range(SIZE):
                a = cover[y][x]
                if a <= 0:
                    continue
                dr, dg, db, da = rgba[y][x]
                out = a + da * (1 - a)
                rgba[y][x] = (
                    (r * a + dr * da * (1 - a)) / out,
                    (g * a + dg * da * (1 - a)) / out,
                    (b * a + db * da * (1 - a)) / out,
                    out,
                )
    write_png(path, [[tuple(int(round(c * 255)) for c in px) for px in row] for row in rgba])


GOLD, PALE, CREAM, INK = "f2c868", "bfd0d8", "f3ead6", FILL_COLOUR

LINK_A = link(7.5, 24.5, 15, 17, 5.6, 3.0)
SHIELD = union(rounded(4, 3, 24, 13, 3.5), bowl(16, 15, 12, 14.5))

TILES = {
    # Quests by zone: a folded map with a green patch and a route.
    "zones": [
        (polygon([(3, 7), (12, 9), (12, 27), (3, 25)]), "e6d3a3"),
        (polygon([(12, 9), (21, 7), (21, 25), (12, 27)]), "c9ad73"),
        (polygon([(21, 7), (30, 9), (30, 27), (21, 25)]), "e6d3a3"),
        (where(circle(15, 15, 4.2), lambda px, py: 12 <= px <= 21), "5fb35a"),
        (stroke([(6, 21), (11, 18), (17, 21), (23, 15), (27, 13)], 1.5), "d9534f"),
    ],
    # Search: a magnifying glass.
    "search": [
        (stroke([(19.5, 19.5), (27.5, 27.5)], 5), "8a5a3c"),
        (circle(13, 13, 9.5), GOLD),
        (circle(13, 13, 7), "8fd3f4"),
        (where(circle(13, 13, 7), lambda px, py: px + py < 21), "c4ecfb"),
    ],
    # Party questing: a pale figure behind a gold one, outlined in the tile's dark brown so they read apart.
    "party": [
        (union(circle(21.4, 9.45, 4.6), dome(21.4, 25.45, 8.4, 8.9)), PALE),
        (union(circle(12.4, 10.95, 6.1), dome(12.4, 27.15, 10.2, 10.8)), INK),
        (union(circle(12.4, 10.95, 5.3), dome(12.4, 27.15, 9.4, 10)), GOLD),
    ],
    # Objective progress: a finished green bar with a tick over a blue bar part-way full, close to the tracker's colours.
    "progress": [
        (rounded(3, 6.5, 26, 7.5, 3.75), "36e04a"),
        (stroke([(11.5, 10.2), (14.5, 12.8), (20.3, 7.4)], 2.0), "0f2a12"),
        (rounded(3, 18, 26, 7.5, 3.75), "5d6f80"),
        (rounded(3.6, 18.6, 24.8, 6.3, 3.15), "14202c"),
        (rounded(3.6, 18.6, 15, 6.3, 3.15), "2f9cff"),
    ],
    # Yours to arrange: a painter's palette.
    "arrange": [
        (minus(union(circle(16, 16, 12.5), circle(22, 23, 6)), circle(11.5, 21.5, 3)), "d9b48a"),
        (circle(10, 11.5, 2.6), "e05a4f"),
        (circle(16.5, 8.5, 2.6), "f2c868"),
        (circle(23, 11, 2.6), "5fb35a"),
        (circle(24, 18, 2.6), "4c8fdc"),
    ],
    # Getting started: a compass.
    "start": [
        (circle(16, 16, 13), GOLD),
        (circle(16, 16, 10.6), CREAM),
        (polygon([(16, 6.5), (19.3, 16), (12.7, 16)]), "e05a4f"),
        (polygon([(12.7, 16), (19.3, 16), (16, 25.5)]), "5b6670"),
        (circle(16, 16, 1.8), INK),
    ],
    # Works with: two linked chain links.
    "works": [
        (LINK_A, GOLD),
        (link(17, 15, 24.5, 7.5, 5.6, 3.0), PALE),
        (where(LINK_A, lambda px, py: px + py > 33), GOLD),
    ],
    # Behaves like the original: a shield.
    "original": [
        (SHIELD, "3f7fcf"),
        (where(SHIELD, lambda px, py: px > 16), "6ea3e6"),
    ],
    # Help and source: a speech bubble.
    "help": [
        (union(rounded(3, 6, 26, 16.5, 6), polygon([(8, 20), (8, 27.5), (15, 21)])), CREAM),
        (circle(10.5, 14.25, 1.9), INK),
        (circle(16, 14.25, 1.9), INK),
        (circle(21.5, 14.25, 1.9), INK),
    ],
}


def main():
    out = os.path.join(os.path.dirname(__file__), "..", "docs", "icons")
    os.makedirs(out, exist_ok=True)
    for name, layers in TILES.items():
        compose(os.path.join(out, "tile-%s.png" % name), layers)
    print("Wrote %d tiles to docs/icons" % len(TILES))


if __name__ == "__main__":
    main()
