"""Rounded-rectangle images for the party badge containers. White with alpha (tinted in game), 32x32, meant to be
nine-sliced: the corners keep their shape at any badge width.

  BadgeRound / BadgeRoundEdge   corner radius 5  (slice margin 6)  - chips
  BadgePill / BadgePillEdge     corner radius 8.5 (slice margin 9) - fully rounded ends at 18px tall
"""
import math
import sys

sys.path.insert(0, ".")
from img import render, write_tga  # noqa: E402

SIZE = 32


def rounded(radius, inset=0.0):
    """Inside test for a rounded square filling the image, shrunk by `inset` pixels."""
    lo, hi = inset, SIZE - inset
    r = max(0.0, radius - inset)

    def inside(x, y):
        px, py = x * SIZE, y * SIZE
        if px < lo or px > hi or py < lo or py > hi:
            return False
        cx = min(max(px, lo + r), hi - r)
        cy = min(max(py, lo + r), hi - r)
        return math.hypot(px - cx, py - cy) <= r
    return inside


def ring(radius, width=1.0):
    outer, inner = rounded(radius), rounded(radius, width)
    return lambda x, y: outer(x, y) and not inner(x, y)


out = sys.argv[1]
for name, radius in (("BadgeRound", 5.0), ("BadgePill", 8.5)):
    write_tga(out + name + ".tga", render(rounded(radius), SIZE, 6))
    write_tga(out + name + "Edge.tga", render(ring(radius, 1.0), SIZE, 6))
print("done")
