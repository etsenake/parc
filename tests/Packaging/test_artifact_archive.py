"""Archive transport tests use tiny synthetic trees; no engine or browser runs."""
import gzip
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import tarfile
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("artifact_archive", Path(__file__).resolve().parents[2] / "scripts/artifact_archive.py")
archive = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(archive)


class ArtifactArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.output = self.root / "assets"
        self.source.mkdir()
        self.output.mkdir()
        self.destination = self.root / "restored"

    def tearDown(self):
        archive._cleanup(self.root)
        self.temporary.cleanup()

    def create(self, **kwargs):
        manifest = archive.create_archive(self.source, self.output, "fixture", **kwargs)
        return self.output / "fixture.manifest.json", manifest

    def raw_artifact(self, records, headers=None, payload=b"", trailer=b""):
        inventory = b"".join(archive._json(record) for record in records)
        (self.output / "fixture.inventory.jsonl").write_bytes(inventory)
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode="w", format=tarfile.PAX_FORMAT) as tar:
            for record in (records if headers is None else headers):
                header = tarfile.TarInfo(record["path"])
                header.mode = record["mode"]
                header.pax_headers = {"PARC.mtime_ns": str(record["mtime_ns"])}
                kind = record["type"]
                header.type = {"directory": tarfile.DIRTYPE, "symlink": tarfile.SYMTYPE,
                               "fifo": tarfile.FIFOTYPE, "file": tarfile.REGTYPE}[kind]
                header.size = record.get("size", 0)
                header.linkname = record.get("target", "")
                tar.addfile(header, io.BytesIO(payload) if kind == "file" else None)
        (self.output / "fixture.part000001.tar.gz").write_bytes(gzip.compress(buffer.getvalue() + trailer))
        manifest = {"format": archive.FORMAT, "compression": "gzip", "archive": "tar",
                    "root": {"mode": 0o755, "mtime_ns": 13},
                    "inventory": {**archive._digest(self.output / "fixture.inventory.jsonl"), "entries": len(records)},
                    "parts": [archive._digest(self.output / "fixture.part000001.tar.gz")]}
        path = self.output / "fixture.manifest.json"
        path.write_bytes(archive._json(manifest))
        return path

    def record(self, path="file", kind="file", **kwargs):
        result = {"path": path, "type": kind, "mode": 0o755, "mtime_ns": 1_701_234_567_987_654_321}
        if kind == "file":
            result.update(size=0, sha256=hashlib.sha256(b"").hexdigest())
        result.update(kwargs)
        return result

    def assert_refused(self, manifest):
        with self.assertRaises((archive.ArchiveError, OSError, tarfile.TarError)):
            archive.extract_archive(manifest, self.destination)
        self.assertFalse(os.path.lexists(self.destination))
        self.assertFalse(list(self.root.glob(".restored-*")))

    def test_round_trip_preserves_contents_modes_and_exact_nanoseconds(self):
        directory = self.source / "directory"
        directory.mkdir()
        file = directory / "executable"
        file.write_bytes(b"example\0data")
        file.chmod(0o751)
        (directory / "link").symlink_to("executable")
        if os.chmod in os.supports_follow_symlinks:
            os.chmod(directory / "link", 0o700, follow_symlinks=False)
        for index, path in enumerate((file, directory / "link", directory, self.source)):
            instant = 1_701_234_567_987_654_321 + index
            os.utime(path, ns=(instant, instant), follow_symlinks=False)
        manifest, description = self.create()
        archive.verify_archive(manifest)
        archive.extract_archive(manifest, self.destination)
        for relative in (".", "directory", "directory/executable", "directory/link"):
            expected, actual = (self.source / relative).lstat(), (self.destination / relative).lstat()
            self.assertEqual(expected.st_mtime_ns, actual.st_mtime_ns)
            self.assertEqual(stat.S_IMODE(expected.st_mode), stat.S_IMODE(actual.st_mode))
        self.assertEqual((self.destination / "directory/executable").read_bytes(), b"example\0data")
        self.assertEqual(os.readlink(self.destination / "directory/link"), "executable")
        self.assertEqual(description["inventory"]["entries"], 3)

    def test_split_boundaries_and_empty_source(self):
        manifest, description = self.create(part_size=17)
        self.assertGreater(len(description["parts"]), 1)
        self.assertTrue(all(part["size"] == 17 for part in description["parts"][:-1]))
        self.assertLessEqual(description["parts"][-1]["size"], 17)
        archive.extract_archive(manifest, self.destination)
        self.assertEqual(list(self.destination.iterdir()), [])

    def test_selection_exclusion_extras_and_relocated_symlinks(self):
        (self.source / "keep").mkdir()
        (self.source / "keep/data").write_bytes(b"included")
        (self.source / "keep/omit").symlink_to("/external")
        (self.source / "ignore").write_bytes(b"excluded")
        (self.source / "keep/absolute").symlink_to(str(self.source / "keep/data"))
        manifest, _ = self.create(includes=["keep"], excludes=["keep/omit"],
                                  extra_files={"metadata/sdk.json": b"{}"},
                                  symlink_rewrites={"keep/absolute": "data"})
        archive.extract_archive(manifest, self.destination)
        self.assertFalse((self.destination / "ignore").exists())
        self.assertFalse(os.path.lexists(self.destination / "keep/omit"))
        self.assertEqual((self.destination / "keep/absolute").read_bytes(), b"included")
        self.assertEqual((self.destination / "metadata/sdk.json").read_bytes(), b"{}")

    def test_hash_tampering_does_not_publish(self):
        (self.source / "file").write_bytes(os.urandom(4096))
        manifest, description = self.create(part_size=100)
        part = self.output / description["parts"][-1]["name"]
        data = bytearray(part.read_bytes())
        data[-1] ^= 1
        part.write_bytes(data)
        self.assert_refused(manifest)

    def test_inventory_tampering_does_not_publish(self):
        manifest, description = self.create()
        (self.output / description["inventory"]["name"]).write_bytes(b"{}\n")
        self.assert_refused(manifest)

    def test_file_content_mismatch_even_with_valid_part_hash(self):
        record = self.record(size=3, sha256=hashlib.sha256(b"yes").hexdigest())
        self.assert_refused(self.raw_artifact([record], payload=b"bad"))

    def test_absolute_parent_duplicate_and_missing_parent_paths(self):
        for records in ([self.record("/escape")], [self.record("../escape")],
                        [self.record("same"), self.record("same")], [self.record("missing/file")]):
            with self.subTest(records=records):
                self.assert_refused(self.raw_artifact(records))

    def test_symlink_ancestor_and_indirect_escape_are_rejected(self):
        cases = [
            [self.record("a", "symlink", target="."), self.record("a/file")],
            [self.record("a", "symlink", target="."), self.record("b", "symlink", target="a/../escape")],
            [self.record("a", "symlink", target="b"), self.record("b", "symlink", target="a")],
            [self.record("a", "symlink", target="/outside")],
        ]
        for records in cases:
            with self.subTest(records=records):
                self.assert_refused(self.raw_artifact(records))

    def test_destination_filesystem_case_alias_cannot_escape(self):
        probe = self.root / "CASE_PROBE"
        probe.touch()
        if not (self.root / "case_probe").exists():
            self.skipTest("destination filesystem is case-sensitive")
        records = [self.record("A", "symlink", target="."),
                   self.record("b", "symlink", target="a/../outside")]
        self.assert_refused(self.raw_artifact(records))

    def test_destination_filesystem_unicode_alias_cannot_escape(self):
        probe = self.root / "caf\u00e9"
        probe.touch()
        if not (self.root / "cafe\u0301").exists():
            self.skipTest("destination filesystem distinguishes Unicode normalization")
        records = [self.record("b", "symlink", target="cafe\u0301/../outside"),
                   self.record("caf\u00e9", "symlink", target=".")]
        self.assert_refused(self.raw_artifact(records))

    def test_internal_symlink_chain_and_parent_target_work(self):
        records = [self.record("a", "directory"), self.record("a/link", "symlink", target="../b"),
                   self.record("b", "symlink", target="c"), self.record("c")]
        manifest = self.raw_artifact(records)
        archive.extract_archive(manifest, self.destination)
        self.assertEqual((self.destination / "a/link").read_bytes(), b"")

    def test_special_unlisted_and_trailing_tar_entries_rejected(self):
        good = self.record()
        for headers, trailer in (([self.record(kind="fifo")], b""),
                                 ([good, self.record("extra")], b""), ([good], b"hidden data")):
            with self.subTest(headers=headers, trailer=trailer):
                self.assert_refused(self.raw_artifact([good], headers=headers, trailer=trailer))

    def test_existing_and_concurrently_created_destination_never_clobbered(self):
        manifest, _ = self.create()
        self.destination.mkdir()
        sentinel = self.destination / "existing"
        sentinel.write_bytes(b"safe")
        with self.assertRaises(FileExistsError):
            archive.extract_archive(manifest, self.destination)
        self.assertEqual(sentinel.read_bytes(), b"safe")
        sentinel.unlink()
        self.destination.rmdir()
        def raced(stage, final):
            final.mkdir()
        with self.assertRaises(FileExistsError):
            archive.extract_archive(manifest, self.destination, post_extract=raced)
        self.assertTrue(self.destination.is_dir())
        self.assertEqual(list(self.destination.iterdir()), [])

    def test_callback_runs_before_publication_and_failure_cleans_stage(self):
        manifest, _ = self.create()
        def failing(stage, final):
            self.assertFalse(final.exists())
            (stage / "adopted").write_text("yes")
            raise RuntimeError("adoption failed")
        with self.assertRaisesRegex(RuntimeError, "adoption failed"):
            archive.extract_archive(manifest, self.destination, post_extract=failing)
        self.assertFalse(self.destination.exists())
        self.assertFalse(list(self.root.glob(".restored-*")))
        archive.extract_archive(manifest, self.destination,
                                post_extract=lambda stage, final: (stage / "adopted").write_text(str(final)))
        self.assertEqual((self.destination / "adopted").read_text(), str(self.destination.resolve()))

    def test_creation_collision_and_unsafe_source_do_not_publish(self):
        (self.source / "outside").symlink_to("/outside")
        with self.assertRaises(archive.ArchiveError):
            self.create()
        self.assertEqual(list(self.output.iterdir()), [])
        (self.source / "outside").unlink()
        (self.output / "fixture.manifest.json").write_bytes(b"existing")
        with self.assertRaises(FileExistsError):
            self.create()
        self.assertEqual([path.name for path in self.output.iterdir()], ["fixture.manifest.json"])
        self.assertEqual((self.output / "fixture.manifest.json").read_bytes(), b"existing")

    def test_source_mutation_rejected(self):
        path = self.source / "data"
        path.write_bytes(b"first")
        original = archive._HashReader.read
        def mutate(reader, size):
            result = original(reader, size)
            path.write_bytes(b"other")
            return result
        with patch.object(archive._HashReader, "read", mutate):
            with self.assertRaisesRegex(archive.ArchiveError, "changed during export"):
                self.create()
        self.assertEqual(list(self.output.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
