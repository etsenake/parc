import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("engine_artifacts", REPO / "scripts/engine-artifacts.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


class ArtifactCLITests(unittest.TestCase):
    def test_package_round_trip_and_refresh_preserve_original(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            source, cache, restored = root / "source", root / "cache", root / "restored"
            (source / "Parc.app").mkdir(parents=True)
            cache.mkdir()
            (source / "Parc.app/program").write_bytes(b"existing app")
            (source / "libcomponent.dylib").write_bytes(b"existing engine")
            (source / "package-report.json").write_text('{"executed":false}')
            with patch("builtins.print"):
                self.assertEqual(tool.main(["create-package", "--package-dir", str(source),
                    "--output", str(cache), "--name", "package", "--part-size", "512"]), 0)
            manifest = cache / "package.manifest.json"
            inventory = [json.loads(line) for line in (cache / "package.inventory.jsonl").read_text().splitlines()]
            metadata = next(item for item in inventory if item["path"] == ".parc-package-snapshot.json")
            lock = root / "lock.json"
            lock.write_text(json.dumps({"schema_version": 1, "target": "mac-arm64", "repository": "owner/repo",
                "release": "test", "artifacts": {"package": {"manifest": manifest.name,
                "manifest_sha256": tool.digest(manifest), "metadata_sha256": metadata["sha256"]}}}))
            with patch("builtins.print"):
                self.assertEqual(tool.main(["restore", "--kind", "package", "--lock", str(lock),
                    "--cache", str(cache), "--destination", str(restored)]), 0)
            self.assertEqual((restored / "libcomponent.dylib").read_bytes(), b"existing engine")
            original_metadata = (restored / ".parc-package-snapshot.json").read_bytes()
            with patch("builtins.print"):
                self.assertEqual(tool.main(["create-package", "--package-dir", str(restored),
                    "--output", str(cache), "--name", "refreshed"]), 0)
            self.assertEqual((restored / ".parc-package-snapshot.json").read_bytes(), original_metadata)
            with patch("builtins.print"):
                self.assertEqual(tool.main(["restore", "--kind", "package", "--lock", str(lock),
                    "--cache", str(cache), "--destination", str(restored)]), 1)

    def test_metadata_replacement_refuses_links(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            source = root / "source"
            source.mkdir()
            (source / "other").write_text("preserve")
            (source / "metadata").symlink_to("other")
            archive = tool.module("artifact_archive")
            with self.assertRaises(archive.ArchiveError):
                archive.create_archive(source, root / "cache", "test", extra_files={"metadata": b"new"},
                                       replace_extra_files=True)
            self.assertEqual((source / "other").read_text(), "preserve")

    def test_existing_valid_cache_needs_no_network(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "part"
            path.write_bytes(b"cached")
            with patch.object(tool.subprocess, "check_output") as network:
                tool.fetch_asset("owner/repo", {"id": 1, "size": 6}, path, tool.digest(path))
            network.assert_not_called()

    def test_complete_partial_publishes_without_range_request(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "part"
            partial = path.with_name("part.partial")
            partial.write_bytes(b"complete")
            with patch.object(tool.subprocess, "check_output") as network:
                tool.fetch_asset("owner/repo", {"id": 1, "size": 8}, path, tool.digest(partial))
            network.assert_not_called()
            self.assertEqual(path.read_bytes(), b"complete")
            self.assertFalse(partial.exists())

    def test_private_download_resumes_without_auth_in_arguments(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "part"
            partial = path.with_name("part.partial")
            partial.write_bytes(b"first")
            def complete(argv, **kwargs):
                self.assertIn("--continue-at", argv)
                self.assertNotIn("secret_token", " ".join(argv))
                self.assertIn("secret_token", kwargs["input"])
                self.assertEqual(partial.read_bytes(), b"first")
                partial.write_bytes(b"first second")
            with patch.object(tool.subprocess, "check_output", return_value="secret_token"), \
                 patch.object(tool.subprocess, "run", side_effect=complete):
                tool.fetch_asset("owner/repo", {"id": 1, "size": 12}, path,
                                 hashlib.sha256(b"first second").hexdigest())
            self.assertEqual(path.read_bytes(), b"first second")
            self.assertFalse(partial.exists())

    def test_cached_tamper_never_overwritten(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "part"
            path.write_bytes(b"wrong")
            with self.assertRaisesRegex(ValueError, "differs from its pin"):
                tool.fetch_asset("owner/repo", {}, path, "0" * 64)
            self.assertEqual(path.read_bytes(), b"wrong")


if __name__ == "__main__":
    unittest.main()
