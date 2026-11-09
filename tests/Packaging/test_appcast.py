"""The Sparkle appcast: escaped XML, a whole-archive signature and identical bytes on a rerun."""
import datetime
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from xml.etree import ElementTree

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("parc_appcast", REPO / "scripts/appcast.py")
appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appcast)
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
SIGNATURE = "c2lnbmF0dXJlK2J5dGVz/w=="
PUBLISHED = datetime.datetime(2026, 11, 9, 21, 14, 3, 512345, tzinfo=datetime.timezone.utc)


class RenderTests(unittest.TestCase):
    def test_url_and_notes_are_escaped_and_notes_survive_cdata(self):
        info = {"CFBundleShortVersionString": "1.9.0", "CFBundleVersion": "23", "LSMinimumSystemVersion": "13.0"}
        notes = '<ul><li>Tabs &amp; spaces</li></ul><p>a ]]> b</p>'
        url = "https://example.invalid/download?a=1&b=2"
        text = appcast.render(info, notes, url, SIGNATURE, 42, PUBLISHED)
        item = ElementTree.fromstring(text).find("channel/item")
        self.assertEqual(item.findtext("title"), "New Version Available")
        self.assertEqual(item.findtext("pubDate"), "Mon, 09 Nov 2026 21:14:03 +0000")
        self.assertEqual(item.findtext(SPARKLE + "version"), "23")
        self.assertEqual(item.findtext(SPARKLE + "shortVersionString"), "1.9.0")
        self.assertEqual(item.findtext(SPARKLE + "minimumSystemVersion"), "13.0")
        self.assertEqual(item.findtext("description"), notes)
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.attrib, {"url": url, "length": "42", "type": "application/octet-stream",
                                            SPARKLE + "edSignature": SIGNATURE})

    def test_notes_are_grouped_html_from_this_version(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "release-notes.json"
            path.write_text(json.dumps({"releases": [
                {"version": "1.9.0", "build": 23, "date": "2026-11-09", "changes": [
                    {"type": "fix", "scope": None, "summary": "Keep <b> titles", "breaking": False},
                    {"type": "feat", "scope": "updates", "summary": "Install updates", "breaking": True}]},
                {"version": "1.8.2", "build": 22, "date": "2026-11-08", "changes": [
                    {"type": "feat", "scope": None, "summary": "Older", "breaking": False}]}]}))
            html = appcast.notes(path, "1.9.0")
            self.assertLess(html.index("Heads up"), html.index("Fixed"))
            self.assertIn("<li>Keep &lt;b&gt; titles</li>", html)
            self.assertNotIn("Older", html)
            with self.assertRaisesRegex(ValueError, "no release 2.0.0"):
                appcast.notes(path, "2.0.0")


class SignatureTests(unittest.TestCase):
    def test_sign_update_output_is_parsed(self):
        self.assertEqual(appcast.parse(f'sparkle:edSignature="{SIGNATURE}" length="226564948"\n'),
                         (SIGNATURE, 226564948))
        for output in ("", "Error: no key", f'sparkle:edSignature="{SIGNATURE}"', f'edSignature="{SIGNATURE}" length="1"'):
            with self.subTest(output=output), self.assertRaises(ValueError):
                appcast.parse(output)


class WriteTests(unittest.TestCase):
    """main() against stand-in Sparkle tools that log their arguments."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="parc-appcast-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / "release-notes.json").write_text(json.dumps({"releases": [{
            "version": "1.9.0", "build": 23, "date": "2026-11-09",
            "changes": [{"type": "feat", "scope": None, "summary": "Updates", "breaking": False}]}]}))
        self.app = self.root / "Parc.app"
        (self.app / "Contents").mkdir(parents=True)
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleShortVersionString": "1.9.0", "CFBundleVersion": "23", "LSMinimumSystemVersion": "13.0",
            "SUPublicEDKey": "trusted-key"}))
        self.archive = self.root / "Parc-1.9.0-arm64.zip"
        self.archive.write_bytes(b"notarized archive bytes")
        self.output = self.root / "appcast.xml"
        self.log = self.root / "calls.jsonl"
        self.tools(length_delta=0, verify_exit=0, public_key="trusted-key")

    def tools(self, *, length_delta, verify_exit, public_key):
        folder = self.root / "Sparkle/bin"
        folder.mkdir(parents=True, exist_ok=True)
        scripts = {"sign_update": f"""
if "--verify" in args:
    sys.exit({verify_exit})
print('sparkle:edSignature="{SIGNATURE}" length="%d"' % (os.path.getsize(args[-1]) + {length_delta}))
""", "generate_keys": f"print({public_key!r})\n"}
        for name, body in scripts.items():
            (folder / name).write_text(f"#!{sys.executable}\nimport json, os, sys\nargs = sys.argv[1:]\n"
                                       f"open({str(self.log)!r}, 'a').write(json.dumps([{name!r}, *args]) + '\\n')\n{body}")
            (folder / name).chmod(0o755)

    def write(self, *key, published=PUBLISHED.isoformat()):
        argv = ["appcast.py", str(self.app), str(self.archive), str(self.output), "--published", published, *key]
        with patch.object(sys, "argv", argv), patch.object(appcast, "ROOT", self.root), \
                patch.object(appcast.sparkle, "fetch", return_value=self.root / "Sparkle"):
            appcast.main()
        return self.output.read_bytes()

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_rerun_writes_identical_bytes_after_sparkle_verifies(self):
        key = self.root / "key"
        first = self.write("--ed-key-file", str(key))
        self.assertEqual(self.write("--ed-key-file", str(key)), first)
        self.assertEqual(self.calls()[:2], [["sign_update", "--ed-key-file", str(key), str(self.archive)],
                                            ["sign_update", "--ed-key-file", str(key), "--verify", str(self.archive), SIGNATURE]])
        enclosure = ElementTree.fromstring(first).find("channel/item/enclosure")
        self.assertEqual(enclosure.get("url"),
                         "https://github.com/etsenake/parc-releases/releases/download/v1.9.0/Parc-1.9.0-arm64.zip")
        self.assertEqual(enclosure.get("length"), str(self.archive.stat().st_size))

    def test_release_signs_with_the_keychain_key_the_app_trusts(self):
        self.write()
        self.assertEqual(self.calls()[:2], [["generate_keys", "--account", "parc", "-p"],
                                            ["sign_update", "--account", "parc", str(self.archive)]])
        self.tools(length_delta=0, verify_exit=0, public_key="another-key")
        self.output.unlink(); self.log.unlink()
        with self.assertRaises(SystemExit) as refused:
            self.write()
        self.assertEqual(refused.exception.code, 1)
        self.assertEqual(self.calls(), [["generate_keys", "--account", "parc", "-p"]])
        self.assertFalse(self.output.exists())

    def test_partial_or_unverified_signature_keeps_the_existing_feed(self):
        self.output.write_bytes(b"earlier feed")
        for delta, verify, error in ((-1, 0, ValueError), (0, 1, subprocess.CalledProcessError)):
            self.tools(length_delta=delta, verify_exit=verify, public_key="trusted-key")
            with self.subTest(length_delta=delta, verify_exit=verify):
                with self.assertRaises(error) as failed:
                    self.write("--ed-key-file", str(self.root / "key"))
                if error is ValueError:
                    self.assertIn("signed 22 bytes", str(failed.exception))
                    self.assertFalse(any("--verify" in call for call in self.calls()))
                self.assertEqual(self.output.read_bytes(), b"earlier feed")
                self.assertFalse(self.output.with_suffix(".tmp").exists())

    def test_published_date_needs_an_offset(self):
        with self.assertRaises(SystemExit) as refused:
            self.write("--ed-key-file", str(self.root / "key"), published="2026-11-09T21:14:03")
        self.assertEqual(refused.exception.code, 2)
        self.assertEqual(self.calls(), [])

if __name__ == "__main__":
    unittest.main()
