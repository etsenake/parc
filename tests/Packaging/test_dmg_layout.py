import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import stat
import struct
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("parc_dmg_layout", Path(__file__).resolve().parents[2] / "scripts/dmg_layout.py")
layout = importlib.util.module_from_spec(spec)
spec.loader.exec_module(layout)
VOLUME_CREATED = 3846000000.5
FILE_CREATED = 3846000001.25


def fixture_alias():
    return layout.alias_record("Parc", VOLUME_CREATED, ".background", 23, "background.tiff", 24, FILE_CREATED)


def tiff(sizes):
    data = bytearray(b"MM\x00\x2a" + struct.pack(">I", 8))
    for index, (width, height) in enumerate(sizes):
        offset = len(data)
        following = offset + 30 if index + 1 < len(sizes) else 0
        data += struct.pack(">H", 2) + struct.pack(">HHII", 256, 4, 1, width)
        data += struct.pack(">HHIHH", 257, 3, 1, height, 0) + struct.pack(">I", following)
    return bytes(data)


class LayoutRecordTests(unittest.TestCase):
    def test_alias_has_fixed_bytes_and_reads_back(self):
        alias = fixture_alias()
        self.assertEqual(hashlib.sha256(alias).hexdigest(),
                         "eac4b526fe2aa69c581b644885a5625dac94186bfd4082902d8d823e9090c81a")
        self.assertEqual(layout.read_alias(alias), {
            "kind": 0, "volume": "Parc", "volume_created": 3846000000, "filesystem": b"H+", "folder_id": 23,
            "name": "background.tiff", "file_id": 24, "file_created": 3846000001,
            "path": "/.background/background.tiff", "folder": ".background",
            "carbon_path": "Parc:.background:\0background.tiff"})

    def test_store_has_fixed_bytes_and_round_trips(self):
        data = layout.store(layout.layout_entries(fixture_alias()))
        self.assertEqual(len(data), 4 + 2 * layout.PAGE)
        self.assertEqual(hashlib.sha256(data).hexdigest(),
                         "bbb0c553595bb8cb63c9fd0e95f688aacd20020ee71e23a3fbc9cb1abaab6f7d")
        entries = layout.read_store(data)
        self.assertEqual(list(entries), [(".", "bwsp"), (".", "icvp"), (".", "vSrn"), (".", "vstl"),
                                         ("Applications", "Iloc"), ("Parc.app", "Iloc")])
        self.assertEqual(entries[("Parc.app", "Iloc")], ("blob", struct.pack(">IIII", 160, 204, 0xFFFFFFFF, 0xFFFF0000)))
        self.assertEqual(entries[("Applications", "Iloc")], ("blob", struct.pack(">IIII", 480, 204, 0xFFFFFFFF, 0xFFFF0000)))
        self.assertEqual(entries[(".", "vstl")], ("type", b"icnv"))
        view = plistlib.loads(entries[(".", "icvp")][1])
        self.assertEqual(view.pop("backgroundImageAlias"), fixture_alias())
        self.assertEqual(view, layout.icon_view_options())
        self.assertEqual(view["backgroundType"], 2)
        self.assertEqual((view["iconSize"], view["textSize"]), (128.0, 13.0))
        window = plistlib.loads(entries[(".", "bwsp")][1])
        self.assertEqual(window["WindowBounds"], "{{200, 120}, {640, 400}}")
        self.assertFalse(window["ShowToolbar"] or window["ShowSidebar"] or window["ShowStatusBar"])

    def test_reader_follows_internal_nodes(self):
        entries = [("a", "Iloc", "blob", layout.icon_location(1, 2)), ("b", "vSrn", "long", 1),
                   ("c", "Iloc", "blob", layout.icon_location(3, 4))]
        leaf = lambda chosen: struct.pack(">II", 0, len(chosen)) + b"".join(layout.encode_entry(*e) for e in chosen)
        data = bytearray(layout.store(entries))
        root = struct.pack(">III", 3, 1, 2) + layout.encode_entry(*entries[1])
        info = layout.INFO_ADDRESS + 4
        struct.pack_into(">I", data, info, 4)
        struct.pack_into(">II", data, info + 8 + 8, 0x2000 | 12, 0x3000 | 12)
        data += bytes(0x4000 - (len(data) - 4))
        for address, body in ((layout.NODE_ADDRESS, root), (0x2000, leaf(entries[:1])), (0x3000, leaf(entries[2:]))):
            data[address + 4:address + 4 + layout.PAGE] = body + bytes(layout.PAGE - len(body))
        self.assertEqual(set(layout.read_store(bytes(data))), {("a", "Iloc"), ("b", "vSrn"), ("c", "Iloc")})

    def test_garbage_and_truncated_stores_are_rejected(self):
        data = layout.store(layout.layout_entries(fixture_alias()))
        for broken in (b"", b"not a store", data[:2052], data[:4] + b"Bud2" + data[8:]):
            with self.subTest(length=len(broken)), self.assertRaises((ValueError, struct.error)):
                layout.read_store(broken)
        with self.assertRaises(layout.LayoutError):
            layout.read_alias(fixture_alias()[:40])


    def test_hostile_alias_lengths_and_shared_tree_nodes_are_refused(self):
        alias = bytearray(fixture_alias())
        first_tag = 8 + struct.calcsize(layout.ALIAS_FIXED)
        for length in (-4, -100, 30000):
            struct.pack_into(">h", alias, first_tag + 2, length)
            with self.subTest(length=length), self.assertRaises(layout.LayoutError):
                layout.read_alias(bytes(alias))
        entries = [("a", "vSrn", "long", 1)]
        data = bytearray(layout.store(entries))
        root = struct.pack(">III", 1, 1, 1) + layout.encode_entry(*entries[0])
        data[layout.NODE_ADDRESS + 4:layout.NODE_ADDRESS + 4 + len(root)] = root
        with self.assertRaises(layout.LayoutError):
            layout.read_store(bytes(data))


class VolumeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.volume = Path(temporary.name)
        background = self.volume / layout.BACKGROUND
        background.parent.mkdir()
        background.write_bytes(tiff(layout.BACKGROUND_SIZES))
        os.chflags(background.parent, stat.UF_HIDDEN)
        (self.volume / layout.VOLUME_ICON).write_bytes(b"icon")
        layout.write(self.volume)

    def rewrite(self, code, kind, value):
        entries = [entry if entry[1] != code else (entry[0], code, kind, value)
                   for entry in layout.layout_entries(layout.background_alias(self.volume))]
        (self.volume / ".DS_Store").write_bytes(layout.store(entries))

    def test_written_volume_verifies(self):
        layout.verify(self.volume, layout.CUSTOM_ICON, b"icon")

    def test_wrong_kinds_and_loose_types_are_refused(self):
        view = layout.icon_view_options() | {"backgroundImageAlias": layout.background_alias(self.volume)}
        cases = {"icon view as a number": ("icvp", "long", 7),
                 "icon view as a list": ("icvp", "blob", plistlib.dumps([1])),
                 "broken XML": ("icvp", "blob", b"<?xml version='1.0'?><plist><dict>"),
                 "alias as text": ("icvp", "blob", plistlib.dumps(view | {"backgroundImageAlias": "alias"})),
                 "integer for a bool": ("icvp", "blob", plistlib.dumps(view | {"labelOnBottom": 1})),
                 "integer for a float": ("icvp", "blob", plistlib.dumps(view | {"iconSize": 128})),
                 "non-text key": ("icvp", "blob", bytes.fromhex("62706c6973743030d1010210011002080b0d0000000000"
                                                                "0001010000000000000003000000000000000000000000"
                                                                "000000000f"))}
        for name, record in cases.items():
            with self.subTest(name):
                self.rewrite(*record)
                with self.assertRaises(layout.LayoutError):
                    layout.verify(self.volume, layout.CUSTOM_ICON, b"icon")

    def test_alias_fields_must_all_match_the_picture(self):
        root, folder = self.volume.stat(), (self.volume / ".background").stat()
        image = (self.volume / layout.BACKGROUND).stat()
        alias = layout.alias_record(layout.VOLUME, layout.mac_time(root.st_birthtime), ".background", folder.st_ino,
                                    "other.tiff", image.st_ino, layout.mac_time(image.st_birthtime))
        view = layout.icon_view_options() | {"backgroundImageAlias": alias}
        self.rewrite("icvp", "blob", plistlib.dumps(view, fmt=plistlib.FMT_BINARY))
        with self.assertRaisesRegex(layout.LayoutError, "does not point"):
            layout.verify(self.volume, layout.CUSTOM_ICON, b"icon")


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


if __name__ == "__main__":
    unittest.main()
