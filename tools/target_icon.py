"""Draws Media/FocusTarget.tga: a target (ring, centre dot and four ticks) in the same flat, white-with-alpha style as the
other header icons (the game tints it gold). Used by the Quests bar's focus mode button and the Extras page."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from img import render, seg_dist, write_tga  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..", "Media")

# Everything is in a 0..1 square: ring radius and thickness, the centre dot, and the four round-capped ticks.
CX = CY = 0.5
RING_R, RING_W = 0.317, 0.09
DOT_R = 0.108
TICK_W = 0.09
TICKS = (
    ((0.5, 0.085), (0.5, 0.255)),
    ((0.5, 0.745), (0.5, 0.915)),
    ((0.085, 0.5), (0.255, 0.5)),
    ((0.745, 0.5), (0.915, 0.5)),
)


def inside(x, y):
    d = math.hypot(x - CX, y - CY)
    if abs(d - RING_R) <= RING_W / 2 or d <= DOT_R:
        return True
    return any(seg_dist(x, y, ax, ay, bx, by) <= TICK_W / 2 for (ax, ay), (bx, by) in TICKS)


if __name__ == "__main__":
    write_tga(os.path.join(ROOT, "FocusTarget.tga"), render(inside, 64, 4))
