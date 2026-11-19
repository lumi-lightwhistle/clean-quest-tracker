"""Draws the full-colour card icons used in the CurseForge description (docs/icons/*.png).

Unlike the add-on's own textures (white with alpha, tinted in game), these are finished colour images, since a web page
shows them as they are. Shapes are laid out on a 32-unit grid and drawn with img.render's supersampling.

Run from the repository root:  python tools/card_icons.py
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from img import render, seg_dist, write_png  # noqa: E402

SIZE = 64
GRID = 32.0


def hexrgb(value):
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def circle(cx, cy, r):
    return lambda x, y: math.hypot(x * GRID - cx, y * GRID - cy) <= r


def dome(cx, base, rx, ry):
    """The top half of an ellipse standing on `base`: a figure's shoulders."""
    def inside(x, y):
        px, py = x * GRID, y * GRID
        return py <= base and ((px - cx) / rx) ** 2 + ((py - base) / ry) ** 2 <= 1
    return inside


def rounded(x0, y0, w, h, r):
    def inside(x, y):
        px, py = x * GRID, y * GRID
        cx = min(max(px, x0 + r), x0 + w - r)
        cy = min(max(py, y0 + r), y0 + h - r)
        return math.hypot(px - cx, py - cy) <= r
    return inside


def stroke(points, width):
    def inside(x, y):
        px, py = x * GRID, y * GRID
        return any(seg_dist(px, py, ax, ay, bx, by) <= width / 2 for (ax, ay), (bx, by) in zip(points, points[1:]))
    return inside


def union(*shapes):
    return lambda x, y: any(shape(x, y) for shape in shapes)


def compose(path, layers):
    """Paints (shape, colour) layers bottom to top over a transparent square and writes a PNG."""
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
                mix = lambda s, d: (s * a + d * da * (1 - a)) / out  # noqa: E731
                rgba[y][x] = (mix(r, dr), mix(g, dg), mix(b, db), out)
    rows = [[tuple(int(round(c * 255)) for c in px) for px in row] for row in rgba]
    write_png(path, rows)


def main():
    out = os.path.join(os.path.dirname(__file__), "..", "docs", "icons")
    os.makedirs(out, exist_ok=True)

    # Party: a pale figure behind a gold one, outlined in the tile's own dark brown so they read apart.
    back = union(circle(21, 10.5, 4.6), dome(21, 26.5, 8.4, 8.9))
    front_edge = union(circle(12, 12, 6.1), dome(12, 28.2, 10.2, 10.8))
    front = union(circle(12, 12, 5.3), dome(12, 28.2, 9.4, 10))
    compose(os.path.join(out, "party.png"), [(back, "bfd0d8"), (front_edge, "2a2015"), (front, "f2c868")])

    # Objective progress: a finished green bar with a tick over a blue bar part-way full, close to the tracker's own colours.
    compose(os.path.join(out, "progress.png"), [
        (rounded(3, 6.5, 26, 7.5, 3.75), "36e04a"),
        (stroke([(11.5, 10.2), (14.5, 12.8), (20.3, 7.4)], 2.0), "0f2a12"),
        (rounded(3, 18, 26, 7.5, 3.75), "5d6f80"),
        (rounded(3.6, 18.6, 24.8, 6.3, 3.15), "14202c"),
        (rounded(3.6, 18.6, 15, 6.3, 3.15), "2f9cff"),
    ])
    print("Wrote docs/icons/party.png and docs/icons/progress.png")


if __name__ == "__main__":
    main()
