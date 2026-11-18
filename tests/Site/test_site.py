import html
from html.parser import HTMLParser
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
SITE = ROOT / "site"
SOURCES = SITE / "src"
PUBLIC = SITE / "public"
SCRIPTS = ROOT / "scripts"
PAGES = ("index.html", "404.html", "whats-new/index.html")
LINK_ATTRIBUTES = {"href", "src", "poster"}
ALLOWED_HOSTS = {"github.com", "parcbrowser.com"}
SKIPPED_SCHEMES = ("http:", "https:", "mailto:", "data:", "#")
WHATS_NEW_URL = "https://parcbrowser.com/whats-new/"
NETWORK_APIS = ("fetch", "XMLHttpRequest", "WebSocket", "EventSource", "sendBeacon")


def load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def newest_release() -> dict:
    return json.loads((ROOT / "release-notes.json").read_text(encoding="utf-8"))["releases"][0]


def text_of(fragment: str) -> str:
    return " ".join(html.unescape(re.sub(r"<[^>]+>", "", fragment)).split())


def css_urls(css: str) -> list:
    return [match.group(2).strip() for match in re.finditer(r"url\(\s*(['\"]?)(.*?)\1\s*\)", css)]


def inline_blocks(page: str, tag: str) -> list:
    return re.findall(rf"<{tag}\b[^>]*>(.*?)</{tag}\s*>", page, re.S | re.I)


def js_comments(script: str) -> list:
    return [line for line in script.splitlines() if line.lstrip().startswith("//")] + (["/*"] if "/*" in script else [])


def frontmatter(component: str) -> str:
    match = re.match(r"---\n(.*?)\n---\n", component, re.S)
    return match.group(1) if match else ""


def component_scripts(component: str) -> list:
    return [frontmatter(component), *inline_blocks(component, "script")]


class Tags(HTMLParser):
    def __init__(self, text: str):
        super().__init__(convert_charrefs=True)
        self.tags = []
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        self.tags.append((tag, {key: value or "" for key, value in attrs}))

    def links(self) -> list:
        found = []
        for _, attrs in self.tags:
            for key, value in attrs.items():
                if key in LINK_ATTRIBUTES or (key.startswith("data-") and value.startswith(("/assets/", "assets/"))):
                    found.append(value)
                elif key == "srcset":
                    found += [part.split()[0] for part in value.split(",") if part.strip()]
        return found

    def find(self, tag: str, **wanted) -> list:
        return [attrs for name, attrs in self.tags
                if name == tag and all(attrs.get(key.replace("_", "-"), "").lower() == value.lower()
                                       for key, value in wanted.items())]

    def with_class(self, tag: str, name: str) -> list:
        return [attrs for found, attrs in self.tags if found == tag and name in attrs.get("class", "").split()]


class BuiltSiteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory()
        cls.out = Path(cls.scratch.name) / "site"
        npm = shutil.which("npm")
        if not npm or not (SITE / "node_modules/astro").is_dir():
            cls.scratch.cleanup()
            raise AssertionError("the site checks need Node and the site's packages: run npm ci in site/")
        result = subprocess.run([npm, "run", "build", "--", "--outDir", str(cls.out)], cwd=SITE,
                                env={**os.environ, "PYTHON": sys.executable}, capture_output=True, text=True, timeout=300)
        if result.returncode:
            cls.scratch.cleanup()
            raise AssertionError(f"the Astro build exited {result.returncode}\n{result.stdout}{result.stderr}")

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

    def built_scripts(self) -> list:
        scripts = [(str(path.relative_to(self.out)), path.read_text(encoding="utf-8")) for path in self.out.rglob("*.js")]
        for page in ("index.html", "404.html"):
            scripts += [(f"{page} inline", block) for block in inline_blocks(self.page(page), "script") if block.strip()]
        return scripts

    def test_build_writes_every_page(self):
        for page in PAGES:
            with self.subTest(page=page):
                self.assertTrue((self.out / page).is_file(), f"{page} is missing from the build")

    def test_fresh_paint_announces_the_newest_version(self):
        title = re.search(r'<(\w+)[^>]*\bid="fresh-title"[^>]*>(.*?)</\1>', self.page("index.html"), re.S)
        self.assertIsNotNone(title, "the fresh section has no fresh-title element")
        self.assertIn(f"Parc {newest_release()['version']} is out.", text_of(title.group(2)))

    def test_fresh_paint_uses_whats_new_wording(self):
        whats_new = load("parc_whats_new_fresh_test", "whats_new.py")
        release = whats_new.read_releases(ROOT / "release-notes.json")[0]
        notable = [change for change in release["changes"]
                   if not change["breaking"] and change["type"] in ("feat", "fix", "perf")]
        picks = [change for change in notable if change["type"] == "feat"][:3] or notable[:3]
        glance = whats_new.glance(release["changes"])
        meta = whats_new.long_date(release["date"]) + (f" · {glance}" if glance else "")
        index = self.page("index.html")
        found = re.search(r'<p class="fresh-meta[^"]*"[^>]*>(.*?)</p>', index, re.S)
        self.assertIsNotNone(found, "the fresh section has no fresh-meta line")
        self.assertEqual(text_of(found.group(1)), meta)
        items = re.search(r'<ul class="fresh-list[^"]*"[^>]*>(.*?)</ul>', index, re.S)
        self.assertIsNotNone(items, "the fresh section has no fresh-list")
        expected = [(change["scope"].replace("-", " ").capitalize() if change["scope"] else "",
                     whats_new.release_notes.display(change["summary"])) for change in picks]
        found = []
        for item in inline_blocks(items.group(1), "li"):
            chip = re.match(r"\s*<span[^>]*>(.*?)</span>(.*)", item, re.S)
            found.append((text_of(chip.group(1)), text_of(chip.group(2))) if chip else ("", text_of(item)))
        self.assertEqual(found, expected)

    def test_download_line_names_the_newest_version(self):
        line = re.search(r'<p class="download-meta[^"]*"[^>]*>(.*?)</p>', self.page("index.html"), re.S)
        self.assertIsNotNone(line, "the download section has no download-meta line")
        self.assertTrue(text_of(line.group(1)).startswith(f"Parc {newest_release()['version']} · macOS 13+"))

    def test_pages_only_run_scripts_the_site_builds(self):
        for page in ("index.html", "404.html"):
            for attrs in Tags(self.page(page)).find("script"):
                with self.subTest(page=page, script=attrs.get("src", "inline")):
                    self.assertEqual(attrs.get("type"), "module")
                    if "src" in attrs:
                        self.assertTrue(attrs["src"].startswith("/assets/"), attrs["src"])

    def test_built_scripts_make_no_network_requests(self):
        scripts = self.built_scripts()
        self.assertTrue(scripts, "the home page ships no script")
        for name, script in scripts:
            for api in NETWORK_APIS:
                with self.subTest(script=name, api=api):
                    self.assertIsNone(re.search(rf"\b{api}\b", script))

    def test_global_styles_come_before_component_styles(self):
        for page in ("index.html", "404.html"):
            sheets = []
            for match in re.finditer(r'<link rel="stylesheet" href="([^"]+)"[^>]*>|<style[^>]*>(.*?)</style>', self.page(page), re.S):
                sheets.append((self.out / match.group(1).lstrip("/")).read_text(encoding="utf-8") if match.group(1) else match.group(2))
            css = "\n".join(sheets)
            with self.subTest(page=page):
                self.assertIn("color-scheme:light", css)
                self.assertIn(":where(.astro-", css)
                self.assertLess(css.index("color-scheme:light"), css.index(":where(.astro-"))

    def test_whats_new_page_wears_the_site_chrome_and_keeps_its_policy(self):
        page = self.page("whats-new/index.html")
        tags = Tags(page)
        self.assertIn('<nav class="site-nav"', page)
        self.assertIn('<footer class="site-foot">', page)
        self.assertIn("Every Parc release, in plain words. Here’s the newest one.", page)
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
            if tag == "script":
                with self.subTest(tag=tag):
                    self.assertNotIn("src", attrs)

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
        sheets = [(path.parent, path.read_text(encoding="utf-8")) for path in self.out.rglob("*.css")]
        for page in ("index.html", "404.html"):
            sheets += [(self.out, block) for block in inline_blocks(self.page(page), "style")]
        self.assertTrue(sheets)
        for folder, css in sheets:
            for link in css_urls(css):
                if link.startswith(("data:", "#")):
                    continue
                path = unquote(urlsplit(link).path)
                target = self.out / path.lstrip("/") if path.startswith("/") else folder / path
                with self.subTest(url=link):
                    self.assertTrue(target.is_file(), f"{link} is missing")

    def test_fonts_ship_with_their_licence(self):
        fonts = list(self.out.rglob("*.woff2"))
        self.assertTrue(fonts, "the build ships no fonts")
        for folder in {font.parent for font in fonts}:
            with self.subTest(folder=str(folder.relative_to(self.out))):
                self.assertTrue((folder / "OFL.txt").is_file())

    def test_icon_picker_offers_every_icon(self):
        index = self.page("index.html")
        picks = Tags(index).with_class("button", "icon-pick")
        self.assertEqual(len(picks), len(list((SOURCES / "assets/icons").glob("*.png"))))
        for attrs in picks:
            with self.subTest(icon=attrs.get("aria-label") or attrs):
                self.assertEqual(attrs.get("role"), "radio")

    def test_every_guide_card_has_a_scene(self):
        index = self.page("index.html")
        opens = sorted(int(value) for value in re.findall(r'data-open="(\d+)"', index))
        scenes = sorted(int(value) for value in re.findall(r'<template id="scene-(\d+)"', index))
        self.assertTrue(opens)
        self.assertEqual(opens, list(range(len(opens))))
        self.assertEqual(scenes, opens)

    def test_home_page_only_links_out_over_https_to_known_hosts(self):
        for page in ("index.html", "404.html"):
            attributes = re.findall(r"\b(?:href|src|poster|content|action)\s*=\s*[\"']([^\"']+)[\"']", self.page(page), re.I)
            for value in (item for item in attributes if "://" in item):
                with self.subTest(page=page, url=value):
                    parts = urlsplit(value)
                    self.assertEqual(parts.scheme, "https")
                    self.assertIn(parts.hostname, ALLOWED_HOSTS)


class SiteSourceTests(unittest.TestCase):
    def sources(self, *patterns) -> list:
        return sorted(path for pattern in patterns for path in [*SOURCES.rglob(pattern), *PUBLIC.rglob(pattern)])

    def test_site_scripts_make_no_network_requests(self):
        scripts = [(path, path.read_text(encoding="utf-8")) for path in self.sources("*.ts")]
        scripts += [(path, block) for path in self.sources("*.astro")
                    for block in inline_blocks(path.read_text(encoding="utf-8"), "script")]
        self.assertTrue(scripts)
        for path, script in scripts:
            for api in NETWORK_APIS:
                with self.subTest(file=str(path.relative_to(ROOT)), api=api):
                    self.assertIsNone(re.search(rf"\b{api}\b", script))

    def test_site_sources_carry_no_comments(self):
        for path in self.sources("*.astro", "*.html"):
            page = path.read_text(encoding="utf-8")
            with self.subTest(file=str(path.relative_to(ROOT))):
                self.assertNotIn("<!--", page)
                for style in inline_blocks(page, "style"):
                    self.assertNotIn("/*", style)
                for script in component_scripts(page):
                    self.assertFalse(js_comments(script))
        for path in self.sources("*.css"):
            with self.subTest(file=str(path.relative_to(ROOT))):
                self.assertNotIn("/*", path.read_text(encoding="utf-8"))
        for path in [*self.sources("*.ts", "*.js", "*.mjs"), SITE / "astro.config.mjs"]:
            with self.subTest(file=str(path.relative_to(ROOT))):
                self.assertFalse(js_comments(path.read_text(encoding="utf-8")))

    def test_in_app_whats_new_page_stays_free_of_site_chrome(self):
        page = load("parc_whats_new_site_test", "whats_new.py").render(ROOT / "release-notes.json")
        self.assertNotIn("site-nav", page)
        self.assertNotIn("site-foot", page)


if __name__ == "__main__":
    unittest.main()
