import html
from html.parser import HTMLParser
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
SITE = ROOT / "site"
SCRIPTS = ROOT / "scripts"
PAGES = ("index.html", "404.html", "whats-new/index.html")
LINK_ATTRIBUTES = {"href", "src", "poster"}
ALLOWED_HOSTS = {"github.com", "parcbrowser.com"}
SKIPPED_SCHEMES = ("http:", "https:", "mailto:", "data:", "#")
WHATS_NEW_URL = "https://parcbrowser.com/whats-new/"


def load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def newest_version() -> str:
    return json.loads((ROOT / "release-notes.json").read_text(encoding="utf-8"))["releases"][0]["version"]


def site_js() -> str:
    return (SITE / "assets/site.js").read_text(encoding="utf-8")


def specimens(script: str) -> str:
    match = re.search(r"const SPECIMENS = \[(.*?)\n\];", script, re.S)
    if not match:
        raise AssertionError("site.js has no SPECIMENS array")
    return match.group(1)


def css_urls(css: str) -> list:
    return [match.group(2).strip() for match in re.finditer(r"url\(\s*(['\"]?)(.*?)\1\s*\)", css)]


def inline_blocks(page: str, tag: str) -> list:
    return re.findall(rf"<{tag}\b[^>]*>(.*?)</{tag}\s*>", page, re.S | re.I)


def js_comments(script: str) -> list:
    return [line for line in script.splitlines() if line.lstrip().startswith("//")] + (["/*"] if "/*" in script else [])


class Tags(HTMLParser):
    def __init__(self, text: str):
        super().__init__(convert_charrefs=True)
        self.tags = []
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        self.tags.append((tag, {key: value or "" for key, value in attrs}))

    def links(self) -> list:
        return [value for _, attrs in self.tags for key, value in attrs.items() if key in LINK_ATTRIBUTES]

    def find(self, tag: str, **wanted) -> list:
        return [attrs for name, attrs in self.tags
                if name == tag and all(attrs.get(key.replace("_", "-"), "").lower() == value.lower()
                                       for key, value in wanted.items())]


class BuiltSiteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory()
        cls.out = Path(cls.scratch.name) / "site"
        result = subprocess.run([sys.executable, str(SCRIPTS / "site.py"), "build", str(cls.out)],
                                cwd=ROOT, capture_output=True, text=True, timeout=300)
        if result.returncode:
            cls.scratch.cleanup()
            raise AssertionError(f"site.py build exited {result.returncode}\n{result.stdout}{result.stderr}")

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def page(self, name: str) -> str:
        return (self.out / name).read_text(encoding="utf-8")

    def resolve(self, page: str, link: str) -> Path:
        path = unquote(urlsplit(link).path)
        base = self.out if path.startswith("/") else (self.out / page).parent
        target = (base / path.lstrip("/")).resolve()
        return target / "index.html" if target.is_dir() or path.endswith("/") else target

    def test_build_writes_every_page(self):
        for page in PAGES:
            with self.subTest(page=page):
                self.assertTrue((self.out / page).is_file(), f"{page} is missing from the build")

    def test_latest_release_slot_announces_the_newest_version(self):
        index = self.page("index.html")
        self.assertNotIn('data-fill="latest-release"', index)
        title = re.search(r'<(\w+)[^>]*\bid="fresh-title"[^>]*>(.*?)</\1>', index, re.S)
        self.assertIsNotNone(title, "the fresh section has no fresh-title element")
        words = " ".join(html.unescape(re.sub(r"<[^>]+>", "", title.group(2))).split())
        self.assertIn(f"Parc {newest_version()} is out.", words)

    def test_download_line_names_the_newest_version(self):
        index = self.page("index.html")
        self.assertNotIn('<span data-fill="version"></span>', index)
        self.assertIn(f'<span data-fill="version">Parc {newest_version()} · </span>', index)

    def test_whats_new_page_wears_the_site_chrome_and_keeps_its_policy(self):
        page = self.page("whats-new/index.html")
        tags = Tags(page)
        self.assertIn('<nav class="site-nav"', page)
        self.assertIn('<footer class="site-foot">', page)
        self.assertEqual([WHATS_NEW_URL], [attrs.get("href") for attrs in tags.find("link", rel="canonical")])
        policies = [attrs.get("content", "") for attrs in tags.find("meta", http_equiv="Content-Security-Policy")]
        self.assertTrue(any("default-src 'none'" in policy for policy in policies), policies)

    def test_whats_new_page_only_embeds_data_urls(self):
        for tag, attrs in Tags(self.page("whats-new/index.html")).tags:
            if "src" in attrs:
                with self.subTest(tag=tag, src=attrs["src"][:80]):
                    self.assertTrue(attrs["src"].strip().lower().startswith("data:"))
            if tag == "link" and attrs.get("rel", "").strip().lower() != "canonical":
                with self.subTest(tag=tag, href=attrs.get("href", "")[:80]):
                    self.assertTrue(attrs.get("href", "").strip().lower().startswith("data:"))

    def test_every_local_link_points_at_a_built_file(self):
        for page in PAGES:
            for link in Tags(self.page(page)).links():
                if not link or link.startswith(SKIPPED_SCHEMES):
                    continue
                with self.subTest(page=page, link=link):
                    self.assertFalse(urlsplit(link).netloc, f"{link} names a host without a scheme")
                    if page == "404.html":
                        self.assertTrue(link.startswith("/"), f"{link} breaks when Pages serves the 404 page deeper down")
                    target = self.resolve(page, link)
                    self.assertTrue(target.is_relative_to(self.out.resolve()), f"{link} leaves the site")
                    self.assertTrue(target.is_file(), f"{link} is missing from the build")

    def test_parcbrowser_urls_point_at_built_files(self):
        for page in PAGES:
            for value in re.findall(r"https://parcbrowser\.com[^\s\"'<>)]*", self.page(page)):
                with self.subTest(page=page, url=value):
                    target = self.resolve(page, "/" + urlsplit(value).path.lstrip("/"))
                    self.assertTrue(target.is_file(), f"{value} is missing from the build")

    def test_every_stylesheet_url_points_at_a_built_file(self):
        assets = self.out / "assets"
        for link in css_urls((assets / "site.css").read_text(encoding="utf-8")):
            if link.startswith(("data:", "#")):
                continue
            with self.subTest(url=link):
                self.assertTrue((assets / unquote(urlsplit(link).path)).is_file(), f"{link} is missing")

    def test_every_icon_in_the_picker_is_built(self):
        line = re.search(r"const ICONS = \[(.*?)\];", site_js())
        self.assertIsNotNone(line, "site.js has no ICONS array")
        files = re.findall(r"\[\s*'([^']+)'\s*,\s*'[^']*'\s*\]", line.group(1))
        self.assertTrue(files)
        for file in files:
            with self.subTest(icon=file):
                self.assertTrue((self.out / "assets/icons" / f"{file}.png").is_file())

    def test_home_page_only_links_out_over_https_to_known_hosts(self):
        for page in ("index.html", "404.html"):
            attributes = re.findall(r"\b(?:href|src|poster|content|action)\s*=\s*[\"']([^\"']+)[\"']", self.page(page), re.I)
            for value in (item for item in attributes if "://" in item):
                with self.subTest(page=page, url=value):
                    parts = urlsplit(value)
                    self.assertEqual(parts.scheme, "https")
                    self.assertIn(parts.hostname, ALLOWED_HOSTS)


class SiteSourceTests(unittest.TestCase):
    def test_every_field_guide_clip_has_its_video_and_poster(self):
        clips = re.findall(r"\bclip:\s*'([a-z-]+)'", specimens(site_js()))
        self.assertTrue(clips)
        for clip in clips:
            for suffix in (".mp4", ".jpg"):
                with self.subTest(clip=clip, suffix=suffix):
                    self.assertTrue((SITE / "media" / "plates" / f"{clip}{suffix}").is_file())

    def test_every_guide_card_has_a_scene_and_a_specimen(self):
        index = (SITE / "index.html").read_text(encoding="utf-8")
        opens = sorted(int(value) for value in re.findall(r'data-open="(\d+)"', index))
        scenes = sorted(int(value) for value in re.findall(r'<template id="scene-(\d+)"', index))
        entries = re.findall(r"^\s*\{\s*no:", specimens(site_js()), re.M)
        self.assertEqual(opens, list(range(len(opens))))
        self.assertEqual(scenes, opens)
        self.assertEqual(len(entries), len(opens))

    def test_script_makes_no_network_requests(self):
        script = site_js()
        for api in ("fetch", "XMLHttpRequest", "WebSocket", "EventSource", "sendBeacon"):
            with self.subTest(api=api):
                self.assertIsNone(re.search(rf"\b{api}\b", script))


    def test_site_sources_carry_no_comments(self):
        for path in sorted(SITE.rglob("*.html")):
            page = path.read_text(encoding="utf-8")
            with self.subTest(file=str(path.relative_to(ROOT))):
                self.assertNotIn("<!--", page)
                for style in inline_blocks(page, "style"):
                    self.assertNotIn("/*", style)
                for script in inline_blocks(page, "script"):
                    self.assertFalse(js_comments(script))
        for path in sorted(SITE.rglob("*.css")):
            with self.subTest(file=str(path.relative_to(ROOT))):
                self.assertNotIn("/*", path.read_text(encoding="utf-8"))
        for path in sorted(SITE.rglob("*.js")):
            with self.subTest(file=str(path.relative_to(ROOT))):
                self.assertFalse(js_comments(path.read_text(encoding="utf-8")))

    def test_fonts_ship_with_their_licence(self):
        fonts = SITE / "assets/fonts"
        self.assertTrue((fonts / "OFL.txt").is_file())
        css = (SITE / "assets/site.css").read_text(encoding="utf-8")
        faces = re.findall(r"@font-face\s*\{[^}]*\}", css)
        self.assertTrue(faces)
        for link in (url for face in faces for url in css_urls(face)):
            with self.subTest(font=link):
                self.assertTrue((SITE / "assets" / unquote(urlsplit(link).path)).is_file(), f"{link} is missing")

    def test_in_app_whats_new_page_stays_free_of_site_chrome(self):
        page = load("parc_whats_new_site_test", "whats_new.py").render(ROOT / "release-notes.json")
        self.assertNotIn("site-nav", page)
        self.assertNotIn("site-foot", page)


if __name__ == "__main__":
    unittest.main()
