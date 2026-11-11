import hashlib
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("parc_sparkle_fetch", REPO / "scripts/sparkle.py")
sparkle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sparkle)


class SparkleFetchTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="parc-sparkle-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        release = self.root / "release"
        for name in ("Sparkle.framework/Versions/B/Sparkle", "bin/sign_update", "Sparkle Test App.app/Contents/Info.plist"):
            (release / name).parent.mkdir(parents=True, exist_ok=True)
            (release / name).write_text("fixture")
        self.archive = self.root / "Sparkle.tar.xz"
        subprocess.run(["/usr/bin/tar", "-cJf", str(self.archive), "-C", str(release), "."], check=True)
        self.digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.cache = self.root / "cache"

    def test_verified_release_is_extracted_once(self):
        with patch.object(sparkle, "URL", self.archive.as_uri()), patch.object(sparkle, "SHA256", self.digest):
            release = sparkle.fetch(self.cache)
            self.assertEqual(release, sparkle.directory(self.cache))
            self.assertEqual(sorted(path.name for path in release.iterdir()), ["Sparkle.framework", "bin"])
            self.archive.unlink()
            self.assertEqual(sparkle.fetch(self.cache), release)
        self.assertEqual([path.name for path in self.cache.iterdir()], [release.name])

    def test_mismatched_download_is_refused_and_not_cached(self):
        with patch.object(sparkle, "URL", self.archive.as_uri()), patch.object(sparkle, "SHA256", "0" * 64):
            with self.assertRaisesRegex(ValueError, "pinned SHA-256"):
                sparkle.fetch(self.cache)
        self.assertEqual(list(self.cache.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
