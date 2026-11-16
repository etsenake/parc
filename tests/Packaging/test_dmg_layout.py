import hashlib
import importlib.util
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import patch
import zipfile

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("parc_dmg_layout", REPO / "scripts/dmg_layout.py")
layout = importlib.util.module_from_spec(spec)
spec.loader.exec_module(layout)
SHIPPED_2_7_0 = Path(__file__).with_name("fixtures") / "ds-store-2.7.0.bin"
ICON = b"fixture icon"


def tiff(sizes):
    data = bytearray(b"MM\x00\x2a" + struct.pack(">I", 8))
    for index, (width, height) in enumerate(sizes):
        offset = len(data)
        following = offset + 30 if index + 1 < len(sizes) else 0
        data += struct.pack(">H", 2) + struct.pack(">HHII", 256, 4, 1, width)
        data += struct.pack(">HHIHH", 257, 3, 1, height, 0) + struct.pack(">I", following)
    return bytes(data)


class FetchTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="parc-dmgbuild-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.cache = self.root / "cache"
        self.wheels = []
        for name in ("alpha", "beta"):
            wheel = self.root / f"{name}-1.0-py3-none-any.whl"
            with zipfile.ZipFile(wheel, "w") as archive:
                archive.writestr(f"{name}/__init__.py", "VALUE = 1\n")
                archive.writestr(f"{name}-1.0.dist-info/METADATA", "Name: " + name)
            self.wheels.append((name, "1.0", wheel.as_uri(), hashlib.sha256(wheel.read_bytes()).hexdigest()))

    def test_pinned_wheels_unpack_once_into_one_cached_folder(self):
        with patch.object(layout, "WHEELS", tuple(self.wheels)):
            site = layout.fetch(self.cache)
            self.assertEqual(site, layout.directory(self.cache))
            self.assertEqual(sorted(path.name for path in site.iterdir()), ["alpha", "beta"])
            for wheel in self.root.glob("*.whl"):
                wheel.unlink()
            self.assertEqual(layout.fetch(self.cache), site)
        self.assertEqual([path.name for path in self.cache.iterdir()], [site.name])

    def test_mismatched_wheel_is_refused_and_not_cached(self):
        wheels = (self.wheels[0], (*self.wheels[1][:3], "0" * 64))
        with (patch.object(layout, "WHEELS", wheels),
              self.assertRaisesRegex(layout.LayoutError, "beta 1.0 does not match its pinned SHA-256")):
            layout.fetch(self.cache)
        self.assertEqual(list(self.cache.iterdir()), [])


class LoadTests(unittest.TestCase):
    def test_a_library_loaded_from_elsewhere_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            site = Path(temporary).resolve() / "site"
            pinned = {}
            for name in ("ds_store", "mac_alias"):
                pinned[name] = types.ModuleType(name)
                pinned[name].__file__ = str(site / name / "__init__.py")
            elsewhere = types.ModuleType("dmgbuild")
            elsewhere.__file__ = str(Path(temporary) / "other/dmgbuild/__init__.py")
            for module in (elsewhere, types.ModuleType("dmgbuild")):
                with (self.subTest(file=getattr(module, "__file__", None)),
                      patch.object(layout, "fetch", return_value=site), patch.object(sys, "path", list(sys.path)),
                      patch.dict(sys.modules, pinned | {"dmgbuild": module}),
                      self.assertRaisesRegex(layout.LayoutError, "^dmgbuild was loaded from outside its pinned copy")):
                    layout.load()

    def test_libraries_that_cannot_be_fetched_refuse_the_layout(self):
        failure = subprocess.CalledProcessError(6, ["curl"])
        with (patch.object(layout, "load", side_effect=failure),
              self.assertRaisesRegex(layout.LayoutError, "pinned dmgbuild libraries could not be loaded")):
            layout.verify(Path("/nonexistent"), bytes(32), ICON)


class SettingsTests(unittest.TestCase):
    def test_dmgbuild_gets_the_install_window_settings(self):
        self.assertEqual(layout.settings(Path("/stage/Parc.app")), {
            "files": ["/stage/Parc.app"], "symlinks": {"Applications": "/Applications"},
            "icon": "/stage/Parc.app/Contents/Resources/Parc.icns",
            "background": str(REPO / "Sources/DiskImage/background.png"), "format": "UDZO",
            "window_rect": ((200, 120), (640, 400)), "default_view": "icon-view", "show_status_bar": False,
            "show_tab_view": False, "show_toolbar": False, "show_pathbar": False, "show_sidebar": False,
            "icon_size": 128, "text_size": 13, "icon_locations": {"Parc.app": (160, 190), "Applications": (480, 190)}})


class ImageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temporary = tempfile.TemporaryDirectory(prefix="parc-dmg-image-")
        cls.addClassCleanup(temporary.cleanup)
        cls.root = Path(temporary.name).resolve()
        app = cls.root / "stage/Parc.app"
        (app / "Contents/Resources").mkdir(parents=True)
        (app / "Contents/Resources/Parc.icns").write_bytes(ICON)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "org.parc.Browser"}))
        cls.image = cls.root / "Parc-arm64.dmg"
        layout.build(app, cls.image, cls.root / "dmgbuild.log")

    def mount(self, writable=False):
        mount = Path(tempfile.mkdtemp(prefix="mount-", dir=self.root))
        options = ["-shadow", str(mount) + ".shadow"] if writable else ["-readonly"]
        subprocess.run(["hdiutil", "attach", str(self.image), "-nobrowse", "-noautoopen", *options,
                        "-mountpoint", str(mount)], check=True, capture_output=True)
        self.addCleanup(subprocess.run, ["hdiutil", "detach", "-force", str(mount)], capture_output=True)
        return mount

    def check(self, volume, finder_info=None):
        if finder_info is None:
            result = subprocess.run(["xattr", "-px", "com.apple.FinderInfo", str(volume)], capture_output=True,
                                    text=True)
            finder_info = b"" if result.returncode else bytes.fromhex("".join(result.stdout.split()))
        layout.verify(volume, finder_info, ICON)

    def test_dmgbuild_image_passes_with_exactly_dmgbuilds_records(self):
        volume = self.mount()
        self.check(volume)
        self.assertEqual(sorted(path.name for path in volume.iterdir()),
                         [".DS_Store", ".VolumeIcon.icns", ".background.tiff", "Applications", "Parc.app"])
        records = layout.records((volume / ".DS_Store").read_bytes())
        self.assertEqual(sorted(records), [(".", "bwsp"), (".", "icvl"), (".", "icvp"), (".", "vSrn"),
                                           ("Applications", "Iloc"), ("Parc.app", "Iloc")])
        self.assertEqual((records[(".", "icvl")], records[(".", "vSrn")]), (b"icnv", 1))
        self.assertEqual({name: records[(name, "Iloc")] for name in layout.POSITIONS}, layout.POSITIONS)
        view = records[(".", "icvp")]
        self.assertEqual((view["backgroundType"], view["iconSize"], view["textSize"]), (2, 128.0, 13.0))
        self.assertEqual(records[(".", "bwsp")]["WindowBounds"], "{{200, 120}, {640, 400}}")
        self.assertEqual(layout.tiff_sizes((volume / ".background.tiff").read_bytes()), layout.BACKGROUND_SIZES)

    def test_the_shipped_2_7_0_layout_is_refused(self):
        volume = self.mount(writable=True)
        (volume / ".DS_Store").write_bytes(SHIPPED_2_7_0.read_bytes())
        with self.assertRaisesRegex(layout.LayoutError, "differs from what dmgbuild writes for this window: "
                                                        r"\. icvl, \. vstl$"):
            self.check(volume)

    def test_tampered_images_are_refused(self):
        shipped_alias = layout.records(SHIPPED_2_7_0.read_bytes())[(".", "icvp")]["backgroundImageAlias"]

        def moved(volume):
            alias = layout.records((volume / ".DS_Store").read_bytes())[(".", "icvp")]["backgroundImageAlias"]
            with patch.dict(layout.POSITIONS, {"Applications": (480, 320)}):
                (volume / ".DS_Store").write_bytes(layout.written_store(alias))

        def replaced(volume):
            picture = volume / layout.BACKGROUND
            data = picture.read_bytes()
            picture.unlink()
            picture.write_bytes(data)

        def single(volume):
            with (volume / layout.BACKGROUND).open("r+b") as stream:
                stream.truncate(0)
                stream.write(tiff([layout.WINDOW]))

        cases = {"no layout file": (lambda volume: (volume / ".DS_Store").unlink(), "missing or unreadable"),
                 "moved icon": (moved, r"window: Applications Iloc$"),
                 "another image's picture": (lambda volume: (volume / ".DS_Store").write_bytes(
                     layout.written_store(shipped_alias)), "does not point at this volume's picture"),
                 "replaced picture": (replaced, "does not point at this volume's picture"),
                 "single-size picture": (single, "lacks its 1x and 2x images"),
                 "different volume icon": (lambda volume: (volume / layout.VOLUME_ICON).write_bytes(b"other"),
                                           "does not carry Parc's icon")}
        for name, (tamper, message) in cases.items():
            with self.subTest(name):
                volume = self.mount(writable=True)
                tamper(volume)
                with self.assertRaisesRegex(layout.LayoutError, message):
                    self.check(volume)
        with self.assertRaisesRegex(layout.LayoutError, "does not carry Parc's icon"):
            self.check(self.mount(), finder_info=bytes(32))


class ArtworkTests(unittest.TestCase):
    def test_tiff_sizes_reads_every_representation(self):
        self.assertEqual(layout.tiff_sizes(tiff([(640, 400), (1280, 800)])), [(640, 400), (1280, 800)])
        with self.assertRaises(layout.LayoutError):
            layout.tiff_sizes(b"\x89PNG\r\n\x1a\n")
        sizeless = bytearray(tiff([(640, 400)]))
        struct.pack_into(">H", sizeless, 10, 999)
        with self.assertRaises(layout.LayoutError):
            layout.tiff_sizes(bytes(sizeless))

    def test_checked_in_art_matches_the_window_at_1x_and_2x(self):
        sizes = []
        for name in layout.ARTWORK:
            data = (layout.ART / name).read_bytes()
            self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
            sizes.append(struct.unpack(">II", data[16:24]))
        self.assertEqual(sizes, layout.BACKGROUND_SIZES)
        self.assertFalse(layout.ART.is_relative_to(layout.ART.parents[1] / "Resources"))
        self.assertEqual(sorted(path.name for path in layout.ART.iterdir() if path.suffix == ".png"),
                         sorted(layout.ARTWORK))


if __name__ == "__main__":
    unittest.main()
