"""Tiny pure-Python image helpers: read/write 32-bit TGA, write PNG, and draw anti-aliased shapes from distance
functions. Icons are white with alpha, as the add-on tints them in game."""
import math
import struct
import zlib


def read_tga(path):
    data = open(path, "rb").read()
    id_len, cmap, itype = data[0], data[1], data[2]
    w, h = struct.unpack("<HH", data[12:16])
    bpp, desc = data[16], data[17]
    assert itype == 2 and bpp == 32, (itype, bpp)
    px = data[18 + id_len:]
    top_down = bool(desc & 0x20)
    alpha = [[0.0] * w for _ in range(h)]
    for y in range(h):
        row = y if top_down else h - 1 - y
        for x in range(w):
            b, g, r, a = px[(y * w + x) * 4:(y * w + x) * 4 + 4]
            alpha[row][x] = a / 255.0
    return alpha


def write_tga(path, alpha):
    h, w = len(alpha), len(alpha[0])
    # Bottom-up rows (descriptor 8), the same layout as the add-on's existing icons.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    body = bytearray()
    for y in range(h - 1, -1, -1):
        for x in range(w):
            a = max(0, min(255, int(round(alpha[y][x] * 255))))
            body += bytes((255, 255, 255, a))
    open(path, "wb").write(header + bytes(body))


def write_png(path, rgba_rows):
    h, w = len(rgba_rows), len(rgba_rows[0])
    raw = bytearray()
    for row in rgba_rows:
        raw.append(0)
        for r, g, b, a in row:
            raw += bytes((r, g, b, a))

    def chunk(kind, payload):
        c = kind + payload
        return struct.pack(">I", len(payload)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


def render(inside, size=64, ss=4):
    """inside(x, y) -> bool in a 0..1 square; supersampled coverage."""
    out = [[0.0] * size for _ in range(size)]
    for y in range(size):
        for x in range(size):
            hit = 0
            for sy in range(ss):
                for sx in range(ss):
                    if inside((x + (sx + 0.5) / ss) / size, (y + (sy + 0.5) / ss) / size):
                        hit += 1
            out[y][x] = hit / (ss * ss)
    return out


def seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy)))
    return math.hypot(px - ax - vx * t, py - ay - vy * t)


def polyline(points, width):
    def inside(x, y):
        for (ax, ay), (bx, by) in zip(points, points[1:]):
            if seg_dist(x, y, ax, ay, bx, by) <= width / 2:
                return True
        return False
    return inside
