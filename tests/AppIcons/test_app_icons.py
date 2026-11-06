"""Exercise real export of every catalog variant without a browser engine.

Independent debug/release bundle integration is covered by tests/Packaging.
"""
import importlib.util
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("parc_app_icons", ROOT / "scripts/app_icons.py")
icons = importlib.util.module_from_spec(spec)
spec.loader.exec_module(icons)


def rgba_png(path):
    """Read ImageIO's noninterlaced 8-bit RGBA output without extra packages."""
    data = path.read_bytes()
    width, height, depth, color, compression, filtering, interlace = struct.unpack(
        ">IIBBBBB", data[16:29])
    if (depth, color, compression, filtering, interlace) != (8, 6, 0, 0, 0):
        raise AssertionError("Expected a noninterlaced RGBA8 export")
    chunks = []
    offset = 8
    while offset < len(data):
        count = struct.unpack(">I", data[offset:offset + 4])[0]
        if data[offset + 4:offset + 8] == b"IDAT":
            chunks.append(data[offset + 8:offset + 8 + count])
        offset += count + 12
    raw = zlib.decompress(b"".join(chunks))
    stride = width * 4
    rows = []
    previous = bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind = raw[start]
        row = bytearray(raw[start + 1:start + 1 + stride])
        for x in range(stride):
            left = row[x - 4] if x >= 4 else 0
            above = previous[x]
            upper_left = previous[x - 4] if x >= 4 else 0
            if kind == 0:
                prediction = 0
            elif kind == 1:
                prediction = left
            elif kind == 2:
                prediction = above
            elif kind == 3:
                prediction = (left + above) // 2
            elif kind == 4:
                p = left + above - upper_left
                distances = [abs(p - left), abs(p - above), abs(p - upper_left)]
                prediction = [left, above, upper_left][distances.index(min(distances))]
            else:
                raise AssertionError("Unknown PNG row filter")
            row[x] = (row[x] + prediction) & 255
        rows.append(row)
        previous = row
    return width, height, rows


def alpha_bounds(rows, threshold=128):
    left, top, right, bottom = len(rows[0]) // 4, len(rows), 0, 0
    for y, row in enumerate(rows):
        for x in range(0, len(row), 4):
            if row[x + 3] >= threshold:
                left = min(left, x // 4); top = min(top, y)
                right = max(right, x // 4 + 1); bottom = max(bottom, y + 1)
    if right <= left:
        return None
    return left, top, right, bottom


class AppIconTests(unittest.TestCase):
    def test_catalog_uses_original_instead_of_development_mascot(self):
        icons = ROOT / "Resources/AppIcons"
        catalog = json.loads((icons / "catalog.json").read_text())
        self.assertEqual(catalog["default"], "Original")
        self.assertEqual(set(catalog["variants"]), {
            "Original", "Candy", "Colorful", "FlutedGlass", "Hologram",
            "Neon", "Schoolbook", "EarlyBirds", "Canary", "Dev",
        })
        self.assertEqual(len(catalog["variants"]), 10)
        for name in catalog["variants"]:
            with self.subTest(name=name):
                data = (icons / (name + ".png")).read_bytes()
                self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
                width, height = struct.unpack(">II", data[16:24])
                self.assertEqual(width, height)
                self.assertGreaterEqual(width, 1024)
                self.assertEqual(data[25], 6, "Artwork must retain RGBA transparency")

    def test_all_variants_export_native_sizes_and_original_is_shared_default(self):
        with tempfile.TemporaryDirectory(prefix="parc-icon-test-") as temporary:
            resources = Path(temporary) / "Resources"
            shutil.copytree(ROOT / "Resources/AppIcons", resources / "AppIcons")
            filename = icons.package_app_icons(resources)
            self.assertEqual(filename, "Parc.icns")
            data = (resources / filename).read_bytes()
            self.assertEqual(data[:4], b"icns")
            self.assertEqual(struct.unpack(">I", data[4:8])[0], len(data))
            catalog = json.loads((resources / "AppIcons/catalog.json").read_text())
            family = {}
            for name in catalog["variants"]:
                with self.subTest(variant=name):
                    native = resources / "AppIcons" / (name + ".icns")
                    native_bytes = native.read_bytes()
                    self.assertEqual(native_bytes[:4], b"icns")
                    self.assertEqual(struct.unpack(">I", native_bytes[4:8])[0], len(native_bytes))
                    family[name] = native_bytes
                    decoded = Path(temporary) / (name + ".iconset")
                    subprocess.run(["/usr/bin/iconutil", "--convert", "iconset", "--output",
                                    str(decoded), str(native)], check=True)
                    expected = {}
                    for points in (16, 32, 128, 256, 512):
                        for scale in (1, 2):
                            suffix = "@2x" if scale == 2 else ""
                            expected[f"icon_{points}x{points}{suffix}.png"] = (points * scale, points * scale)
                    self.assertEqual({path.name for path in decoded.iterdir()}, set(expected))
                    for representation, dimensions in expected.items():
                        path = decoded / representation
                        self.assertEqual(struct.unpack(">II", path.read_bytes()[16:24]), dimensions)
                        width, height, rows = rgba_png(path)
                        bounds = alpha_bounds(rows)
                        self.assertIsNotNone(bounds)
                        left, top, right, bottom = bounds
                        extent = max(right - left, bottom - top)
                        target = round(width * (204 / 256 if name == "Dev" else 824 / 1024))
                        # Raster edge coverage can move the >=50% boundary one
                        # pixel. This rejects the old 83-89% inconsistent framing.
                        self.assertLessEqual(abs(extent - target), 1, (name, representation, bounds))
                        self.assertLessEqual(abs((left + right) / 2 - width / 2), 1)
                        target_y = height * (130 / 256 if name == "Dev" else 0.5)
                        self.assertLessEqual(abs((top + bottom) / 2 - target_y), 1)
                        # Every variant keeps a transparent outer pixel ring;
                        # colored full-canvas mattes and clipping are regressions.
                        perimeter = [rows[0], rows[-1]]
                        self.assertTrue(all(row[x] == 0 for row in perimeter
                                            for x in range(3, len(row), 4)))
                        self.assertTrue(all(row[3] == 0 and row[-1] == 0 for row in rows))
                    self.assertEqual((resources / "AppIcons" / (name + ".png")).read_bytes(),
                                     (ROOT / "Resources/AppIcons" / (name + ".png")).read_bytes())
            self.assertEqual(data, family["Original"])
            self.assertEqual(len(set(family.values())), len(catalog["variants"]))


if __name__ == "__main__":
    unittest.main()
