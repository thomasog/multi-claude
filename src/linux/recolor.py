#!/usr/bin/env python3
"""Recolor Claude's icon to a target color, using only the standard library.

    python3 recolor.py <source.png> <output.png> <RRGGBB>

Every colored pixel takes the target hue; saturation and brightness are scaled so the logo's own
brand color lands exactly on the target, while near-white pixels (the glyph) stay light. Same
algorithm as src/windows/MultiClaude.cs. Reads non-interlaced 8-bit RGB/RGBA PNGs and palette PNGs.
"""

import colorsys
import struct
import sys
import zlib

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def read_png(path):
    """Return (width, height, rows); rows are lists of (r, g, b, a) tuples."""
    with open(path, "rb") as file:
        data = file.read()
    if not data.startswith(PNG_SIGNATURE):
        sys.exit(f"{path}: not a PNG file")

    pos, compressed, palette, alpha = len(PNG_SIGNATURE), b"", [], b""
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", body)
            supported = depth == 8 if color_type in (2, 6) else color_type == 3 and depth in (1, 2, 4, 8)
            if not supported or interlace:
                sys.exit(f"{path}: need a non-interlaced 8-bit RGB or RGBA PNG, or a palette PNG")
            channels = {2: 3, 3: 1, 6: 4}[color_type]
        elif kind == b"PLTE":
            palette = [tuple(body[i:i + 3]) for i in range(0, len(body) - 2, 3)]
        elif kind == b"tRNS":
            alpha = body
        elif kind == b"IDAT":
            compressed += body
    if color_type == 3 and not palette:
        sys.exit(f"{path}: palette PNG without a palette")

    # Filters work on bytes; bpp is the byte distance to the previous pixel (at least 1).
    raw, bpp, stride = zlib.decompress(compressed), max(1, channels * depth // 8), (width * channels * depth + 7) // 8
    rows, previous = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        for i in range(stride):
            left = line[i - bpp] if i >= bpp else 0
            up = previous[i]
            up_left = previous[i - bpp] if i >= bpp else 0
            if kind == 1:
                line[i] = (line[i] + left) & 255
            elif kind == 2:
                line[i] = (line[i] + up) & 255
            elif kind == 3:
                line[i] = (line[i] + (left + up) // 2) & 255
            elif kind == 4:
                line[i] = (line[i] + _paeth(left, up, up_left)) & 255
        if color_type == 3:
            per_byte, mask = 8 // depth, (1 << depth) - 1
            indexes = [line[x // per_byte] >> (8 - depth * (x % per_byte + 1)) & mask for x in range(width)]
            rows.append([palette[i] + (alpha[i] if i < len(alpha) else 255,) for i in indexes])
        else:
            opaque = (255,) if channels == 3 else ()
            rows.append([tuple(line[x:x + channels]) + opaque for x in range(0, stride, channels)])
        previous = line
    return width, height, rows


def write_png(path, width, height, rows):
    """Write RGBA rows as a PNG."""
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    raw = b"".join(b"\x00" + bytes(value for pixel in row for value in pixel) for row in rows)
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    with open(path, "wb") as file:
        file.write(PNG_SIGNATURE + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def recolor(rows, hex_color):
    """Return new rows recolored toward hex_color (RRGGBB)."""
    value = int(hex_color, 16)
    hue, sat, val = colorsys.rgb_to_hsv((value >> 16 & 255) / 255, (value >> 8 & 255) / 255, (value & 255) / 255)

    # The logo's brand color: mean saturation and brightness of clearly colored, opaque pixels.
    sample = [colorsys.rgb_to_hsv(r / 255, g / 255, b / 255) for row in rows[::2] for r, g, b, a in row[::2] if a >= 200]
    brand = [(s, v) for _, s, v in sample if s >= 0.3]
    brand_sat = sum(s for s, _ in brand) / len(brand) if brand else 0.6
    brand_val = sum(v for _, v in brand) / len(brand) if brand else 0.85

    result = []
    for row in rows:
        new_row = []
        for r, g, b, a in row:
            if a:
                _, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
                colored = min(1.0, s / brand_sat)
                rgb = colorsys.hsv_to_rgb(hue, min(1.0, s * sat / brand_sat), min(1.0, v * (1 - colored + colored * val / brand_val)))
                r, g, b = (round(channel * 255) for channel in rgb)
            new_row.append((r, g, b, a))
        result.append(new_row)
    return result


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    source, output, color = sys.argv[1:]
    width, height, pixels = read_png(source)
    write_png(output, width, height, recolor(pixels, color.lstrip("#")))
