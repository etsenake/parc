import hashlib
import json
from pathlib import Path
import unittest

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[2] / "Resources/AppIcons"


def digest(data):
    return hashlib.sha256(data).hexdigest()


class ArtworkChecks(unittest.TestCase):
    def test_approved_master_pixels_and_export_inputs(self):
        manifest = json.loads((ROOT / "artwork-provenance.json").read_text())
        catalog = json.loads((ROOT / "catalog.json").read_text())
        self.assertEqual(set(manifest["masters"]), set(catalog["variants"]))
        for name, record in manifest["masters"].items():
            with self.subTest(variant=name):
                path = ROOT / (name + ".png")
                image = Image.open(path)
                self.assertEqual(image.mode, "RGBA")
                self.assertEqual(image.size, (1254, 1254))
                self.assertEqual(digest(path.read_bytes()), record["cleanedFileSHA256"])
                self.assertEqual(digest(image.convert("RGB").tobytes()), record["originalRGBSHA256"])
                alpha = image.getchannel("A")
                mask = alpha.point(lambda value: 255 if value >= 128 else 0)
                opaque = ImageChops.multiply(image, Image.merge("RGBA", (mask, mask, mask, mask)))
                self.assertEqual(digest(opaque.tobytes()), record["originalOpaqueSHA256"])
                x0, y0, x1, y1 = mask.getbbox()
                outside = alpha.copy()
                outside.paste(0, (x0 - 2, y0 - 2, x1 + 2, y1 + 2))
                self.assertIsNone(outside.getbbox(), "Stray alpha may not extend beyond the approved silhouette's edge band")
                self.assertGreater(record["removedAlphaPixels"], 0)
                self.assertEqual(record["opaquePixelsChanged"], 0)

    def test_derived_marks_have_one_open_silhouette(self):
        record = json.loads((ROOT / "artwork-provenance.json").read_text())["marks"]
        color = Image.open(ROOT / "Marks/Borderless.png")
        mono = Image.open(ROOT / "Marks/Monochrome.png")
        self.assertEqual(list(color.size), record["size"])
        self.assertEqual(color.size, mono.size)
        self.assertEqual(color.getchannel("A").tobytes(), mono.getchannel("A").tobytes())
        self.assertEqual(digest(color.getchannel("A").tobytes()), record["alphaSHA256"])
        self.assertEqual(set(mono.convert("RGB").getdata()), {(0, 0, 0)})
        self.assertEqual(digest((ROOT / "Marks/Borderless.png").read_bytes()), record["borderlessFileSHA256"])
        self.assertEqual(digest((ROOT / "Marks/Monochrome.png").read_bytes()), record["monochromeFileSHA256"])
        x0, y0, _, _ = record["sourceCrop"]
        alpha = color.getchannel("A")
        for x, y in [(700, 450), (650, 850), (750, 1040), (390, 400)]:
            self.assertEqual(alpha.getpixel((x - x0, y - y0)), 0, "Bowl, curl and exterior must remain open")
        original = Image.open(ROOT / "Original.png")
        for x, y in [(500, 400), (800, 500), (400, 580), (500, 800), (650, 1000), (710, 920)]:
            self.assertEqual(color.getpixel((x - x0, y - y0)), original.getpixel((x, y)),
                             "Approved colored P interior must be copied exactly")


if __name__ == "__main__":
    unittest.main()
