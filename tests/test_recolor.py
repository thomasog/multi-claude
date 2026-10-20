"""Tests for src/linux/recolor.py - standard library only. Run: python3 -m unittest discover tests"""
import colorsys
import pathlib
import struct
import sys
import tempfile
import unittest
import zlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "src" / "linux"))
import recolor

ORANGE, WHITE, CLEAR = (217, 119, 87, 255), (255, 255, 255, 255), (0, 0, 0, 0)


def synthetic_logo(size=32):
    """Orange square, white glyph in the middle, one transparent corner."""
    rows = [[ORANGE] * size for _ in range(size)]
    for y in range(12, 20):
        for x in range(12, 20):
            rows[y][x] = WHITE
    rows[0][0] = CLEAR
    return rows


def chunk_of(kind, body):
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))


def encode_png(width, height, color_type, depth, lines, extra=b"", filters=(0,)):
    """A PNG from raw scanlines (bytes, no filter byte), filtered row by row with the given types."""
    bpp = max(1, {2: 3, 3: 1, 6: 4}[color_type] * depth // 8)
    raw, previous = b"", bytes(len(lines[0]))
    for y, line in enumerate(lines):
        kind, out = filters[y % len(filters)], bytearray()
        for i, value in enumerate(line):
            left = line[i - bpp] if i >= bpp else 0
            up, up_left = previous[i], previous[i - bpp] if i >= bpp else 0
            predictor = [0, left, up, (left + up) // 2, recolor._paeth(left, up, up_left)][kind]
            out.append((value - predictor) & 255)
        raw += bytes([kind]) + bytes(out)
        previous = line
    header = struct.pack(">IIBBBBB", width, height, depth, color_type, 0, 0, 0)
    return (recolor.PNG_SIGNATURE + chunk_of(b"IHDR", header) + extra + chunk_of(b"IDAT", zlib.compress(raw))
            + chunk_of(b"IEND", b""))


def read_bytes(data):
    with tempfile.TemporaryDirectory() as d:
        path = pathlib.Path(d) / "x.png"
        path.write_bytes(data)
        return recolor.read_png(path)


class RecolorTest(unittest.TestCase):
    def test_background_takes_target_color(self):
        r, g, b, _ = recolor.recolor(synthetic_logo(), "1F4E8C")[4][4]
        h, _, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        self.assertAlmostEqual(h * 360, 214, delta=6)
        self.assertAlmostEqual(v, 0x8C / 255, delta=0.05)

    def test_glyph_stays_white(self):
        self.assertTrue(all(c > 240 for c in recolor.recolor(synthetic_logo(), "1F6F43")[16][16][:3]))

    def test_transparency_is_kept(self):
        self.assertEqual(recolor.recolor(synthetic_logo(), "1F6F43")[0][0][3], 0)

    def test_png_round_trip(self):
        rows = synthetic_logo()
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / "x.png"
            recolor.write_png(path, 32, 32, rows)
            w, h, back = recolor.read_png(path)
        self.assertEqual((w, h), (32, 32))
        self.assertEqual(back, [list(map(tuple, row)) for row in rows])

    def test_every_filter_type_is_decoded(self):
        rows = synthetic_logo()
        for y, row in enumerate(rows):             # vary the pixels so every predictor matters
            rows[y] = [(r, (g + 7 * x) & 255, (b + 13 * y) & 255, a) for x, (r, g, b, a) in enumerate(row)]
        lines = [bytes(v for pixel in row for v in pixel) for row in rows]
        for kind in range(5):
            with self.subTest(filter=kind):
                _, _, back = read_bytes(encode_png(32, 32, 6, 8, lines, filters=(kind,)))
                self.assertEqual(back, rows)
        _, _, back = read_bytes(encode_png(32, 32, 6, 8, lines, filters=(0, 1, 2, 3, 4)))
        self.assertEqual(back, rows)

    def test_rgb_without_alpha_is_opaque(self):
        lines = [bytes([217, 119, 87, 1, 2, 3]) for _ in range(2)]
        _, _, back = read_bytes(encode_png(2, 2, 2, 8, lines, filters=(4,)))
        self.assertEqual(back, [[(217, 119, 87, 255), (1, 2, 3, 255)]] * 2)

    def test_palette_png_with_transparency(self):
        plte = chunk_of(b"PLTE", bytes([217, 119, 87, 255, 255, 255, 0, 0, 0]))
        trns = chunk_of(b"tRNS", bytes([255, 255, 0]))   # entry 2 transparent; missing entries are opaque
        lines = [bytes([0, 1, 2, 0]), bytes([2, 2, 1, 1])]
        _, _, back = read_bytes(encode_png(4, 2, 3, 8, lines, plte + trns, filters=(1, 2)))
        o, w, c = (217, 119, 87, 255), (255, 255, 255, 255), (0, 0, 0, 0)
        self.assertEqual(back, [[o, w, c, o], [c, c, w, w]])

    def test_palette_png_with_low_bit_depth(self):
        plte = chunk_of(b"PLTE", bytes([217, 119, 87, 255, 255, 255, 1, 2, 3, 4, 5, 6]))
        # 4-bit: 5 pixels -> 3 bytes; 2-bit: 5 pixels -> 2 bytes; padding bits are ignored.
        for depth, line in ((4, bytes([0x01, 0x23, 0x10])), (2, bytes([0b00011011, 0b01000000]))):
            with self.subTest(depth=depth):
                _, _, back = read_bytes(encode_png(5, 1, 3, depth, [line], plte, filters=(1,)))
                colors = [(217, 119, 87), (255, 255, 255), (1, 2, 3), (4, 5, 6)]
                self.assertEqual(back, [[c + (255,) for c in colors + [colors[1]]]])


if __name__ == "__main__":
    unittest.main()
