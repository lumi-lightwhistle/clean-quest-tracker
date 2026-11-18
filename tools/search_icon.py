"""Draws Media/Search.tga: a magnifying glass in the same flat, white-with-alpha style as the other header icons
(the game tints it gold). Run with --preview <png> to also write a side-by-side check against the pin and arrows."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from img import read_tga, render, seg_dist, write_png, write_tga  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..", "CleanQuestTracker", "Media")

# Ring centre and radius, ring thickness, and the handle (a round-capped stroke out to the bottom-right).
CX, CY, R, RING = 0.42, 0.42, 0.25, 0.115
HANDLE = ((0.62, 0.62), (0.84, 0.84))
HANDLE_W = 0.15


def inside(x, y):
    d = math.hypot(x - CX, y - CY)
    if abs(d - R) <= RING / 2:
        return True
    (ax, ay), (bx, by) = HANDLE
    return seg_dist(x, y, ax, ay, bx, by) <= HANDLE_W / 2


def main():
    alpha = render(inside, 64, 4)
    write_tga(os.path.join(ROOT, "Search.tga"), alpha)
    if "--preview" in sys.argv:
        out = sys.argv[sys.argv.index("--preview") + 1]
        icons = [read_tga(os.path.join(ROOT, n + ".tga")) for n in ("FocusZone", "ExpandAll", "Settings", "Locked")]
        icons.append(alpha)
        gold, bg, scale, gap = (217, 176, 74), (14, 11, 9), 2, 16
        w = len(icons) * (64 * scale + gap) + gap
        h = 64 * scale + gap * 2
        rows = [[bg + (255,) for _ in range(w)] for _ in range(h)]
        for i, icon in enumerate(icons):
            ox = gap + i * (64 * scale + gap)
            for y in range(64 * scale):
                for x in range(64 * scale):
                    a = icon[y // scale][x // scale]
                    rows[gap + y][ox + x] = tuple(int(bg[c] + (gold[c] - bg[c]) * a) for c in range(3)) + (255,)
        write_png(out, rows)


if __name__ == "__main__":
    main()
