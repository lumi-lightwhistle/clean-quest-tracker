"""Draws Media/Tick.tga: a round-capped tick in the flat, white-with-alpha style the game tints. The settings
window draws it on the colour in use in each palette (Colours page cards, Search page row), dark on pale colours and
white on dark ones."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from img import polyline, render, write_tga  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..", "Media")

# In a 0..1 square, top to bottom: the short stroke down to the corner, then the long stroke up to the right.
POINTS = ((0.2, 0.54), (0.4, 0.73), (0.8, 0.29))
WIDTH = 0.15


if __name__ == "__main__":
    write_tga(os.path.join(ROOT, "Tick.tga"), render(polyline(POINTS, WIDTH), 32, 4))
