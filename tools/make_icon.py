"""Turns a square icon on a black background into the add-on's list icon: the black background becomes transparent
(flood fill from the edges, so dark areas inside the artwork are kept), the result is cropped flush to the artwork,
padded to a square, scaled down with a box filter (premultiplied alpha, so edges stay clean) and written as a
32-bit bottom-up TGA, plus a PNG preview.

Usage: make_icon.py <raw.bgra> <width> <height> <out.tga> <preview.png> [size]
The raw file is width*height*4 bytes of BGRA, as exported by Windows' image decoder.
"""
import struct
import sys
import zlib
from collections import deque

raw_path, w, h, out_tga, out_png = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
size = int(sys.argv[6]) if len(sys.argv) > 6 else 64
BACKGROUND = 26  # a pixel this dark (max channel) touching the edge counts as background

data = open(raw_path, "rb").read()
assert len(data) == w * h * 4, "raw size doesn't match the dimensions"


def px(x, y):
    i = (y * w + x) * 4
    return data[i + 2], data[i + 1], data[i]  # r, g, b


# Flood fill the background from every edge pixel.
transparent = bytearray(w * h)
queue = deque()
for x in range(w):
    queue.append((x, 0))
    queue.append((x, h - 1))
for y in range(h):
    queue.append((0, y))
    queue.append((w - 1, y))
while queue:
    x, y = queue.popleft()
    k = y * w + x
    if transparent[k] or max(px(x, y)) > BACKGROUND:
        continue
    transparent[k] = 1
    if x > 0:
        queue.append((x - 1, y))
    if x < w - 1:
        queue.append((x + 1, y))
    if y > 0:
        queue.append((x, y - 1))
    if y < h - 1:
        queue.append((x, y + 1))

# Crop flush to the artwork, then pad to a square.
xs = [x for y in range(h) for x in range(w) if not transparent[y * w + x]]
left, right = min(xs), max(xs)
ys = [y for y in range(h) if any(not transparent[y * w + x] for x in range(left, right + 1))]
top, bottom = min(ys), max(ys)
side = max(right - left + 1, bottom - top + 1)
ox = left - (side - (right - left + 1)) // 2
oy = top - (side - (bottom - top + 1)) // 2
print(f"artwork box: x {left}-{right}, y {top}-{bottom}; square side {side}")

# Box-filter down to size x size with premultiplied alpha.
out = []
for ty in range(size):
    row = []
    y0, y1 = oy + ty * side / size, oy + (ty + 1) * side / size
    for tx in range(size):
        x0, x1 = ox + tx * side / size, ox + (tx + 1) * side / size
        r = g = b = a = n = 0.0
        for sy in range(int(y0), max(int(y0) + 1, int(y1))):
            for sx in range(int(x0), max(int(x0) + 1, int(x1))):
                n += 1
                if 0 <= sx < w and 0 <= sy < h and not transparent[sy * w + sx]:
                    pr, pg, pb = px(sx, sy)
                    r += pr
                    g += pg
                    b += pb
                    a += 1
        if a:
            row.append((round(r / a), round(g / a), round(b / a), round(255 * a / n)))
        else:
            row.append((0, 0, 0, 0))
    out.append(row)

# TGA: 32-bit, uncompressed, bottom-up rows (descriptor 8), like the add-on's other textures.
header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 8)
body = bytearray()
for row in reversed(out):
    for r, g, b, a in row:
        body += bytes((b, g, r, a))
open(out_tga, "wb").write(header + bytes(body))


# PNG preview at 4x, on a dark backdrop like the AddOns list.
def chunk(kind, payload):
    c = kind + payload
    return struct.pack(">I", len(payload)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)


scale, bg = 4, (24, 20, 16)
raw = bytearray()
for row in out:
    line = bytearray()
    for r, g, b, a in row:
        t = a / 255
        pix = bytes(round(bg[i] + ((r, g, b)[i] - bg[i]) * t) for i in range(3)) + b"\xff"
        line += pix * scale
    for _ in range(scale):
        raw += b"\x00" + line
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size * scale, size * scale, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
open(out_png, "wb").write(png)
print("wrote", out_tga, "and", out_png)
