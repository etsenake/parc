import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
SAMPLE = REPO / "tests/Packaging/fixtures/release-notes-sample.json"
spec = importlib.util.spec_from_file_location("parc_whats_new", REPO / "scripts/whats_new.py")
whats_new = importlib.util.module_from_spec(spec)
spec.loader.exec_module(whats_new)


def change(kind, summary, breaking=False):
    return {"type": kind, "scope": None, "summary": summary, "breaking": breaking}


def release(version, *changes):
    return {"version": version, "build": 1, "date": "2026-11-10", "changes": list(changes)}


class WhatsNewTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.notes = Path(self.temporary.name) / "release-notes.json"

    def render(self, *releases):
        self.notes.write_text(json.dumps({"releases": list(releases)}))
        return whats_new.render(self.notes)

    def test_missing_file_renders_the_empty_state(self):
        self.assertEqual(whats_new.read_releases(self.notes), [])
        page = whats_new.render(self.notes)
        self.assertIn("A clean slate", page)
        self.assertNotIn("Happy browsing", page)
        self.assertEqual(self.render(), page)

    def test_all_release_text_is_escaped(self):
        page = self.render(release("1.0.0", change("feat", '<img src=x onerror="alert(1)"> & <b>bold</b>')))
        self.assertIn("&lt;img src=x onerror=&quot;alert(1)&quot;&gt; &amp; &lt;b&gt;bold&lt;/b&gt;", page)
        self.assertNotIn("<img", page)
        self.assertNotIn("<b>", page)

    def test_summaries_render_with_a_capital_first_letter_only(self):
        page = self.render(release("1.0.1", change("fix", "correct browser chrome in iCloud tabs")))
        self.assertIn("<li>Correct browser chrome in iCloud tabs</li>", page)

    def test_groups_follow_heads_up_new_fixed_faster(self):
        page = self.render(release("2.0.0", change("perf", "Faster thing"), change("fix", "Fixed thing"),
                                   change("feat", "Breaking thing", breaking=True), change("feat", "New thing"),
                                   change("fix", "Breaking fix", breaking=True)))
        labels = re.findall(r'class="label">([^<]+)<', page)
        self.assertEqual(labels, ["Heads up", "New", "Fixed", "Faster"])
        groups = dict(re.findall(r'<div class="group ([a-z-]+)">(.*?)</div>', page))
        self.assertEqual(re.findall(r"<li>(.*?)</li>", groups["heads-up"]), ["Breaking thing", "Breaking fix"])
        self.assertEqual(re.findall(r"<li>(.*?)</li>", groups["new"]), ["New thing"])

    def test_breaking_changes_of_any_type_are_heads_up(self):
        page = self.render(release("2.0.0", change("refactor", "Require macOS 14", breaking=True)))
        self.assertIn('<div class="group heads-up"><h3 class="label">Heads up</h3><ul><li>Require macOS 14</li>', page)

    def test_newest_release_leads_and_the_rest_keep_their_order(self):
        page = whats_new.render(SAMPLE)
        self.assertIn("<h2>Parc 1.9.0</h2>", page)
        self.assertIn("November 10, 2026 · Build 23", page)
        self.assertEqual(re.findall(r'<span class="version">([^<]+)</span>', page),
                         ["1.9.0", "1.8.2", "1.8.1", "1.8.0", "1.7.0"])
        self.assertEqual(re.findall(r'<li class="step" data-version="([^"]+)"><details>', page),
                         ["1.8.2", "1.8.1", "1.8.0", "1.7.0"])
        self.assertIn('<li class="step current" data-version="1.9.0"><div class="row"><span class="version">1.9.0</span>', page)
        self.assertIn('<p class="skipped" hidden><span></span><a href="#earlier">Catch me up ↓</a></p>', page)
        page = self.render(release("1.9.0", change("fix", "Only fix")))
        self.assertNotIn("Earlier releases", page)
        self.assertNotIn('class="skipped"', page)
        self.assertNotIn('class="label">New', page)

    def test_releases_without_user_facing_changes_say_so(self):
        page = self.render(release("1.9.1"), release("1.9.0"))
        self.assertIn("Thanks for using Parc! Here’s what’s new in this version.", page)
        self.assertEqual(page.count(f'<p class="quiet">{whats_new.COPY["no notes"]}</p>'), 2)

    def test_closed_rows_count_each_group_and_rows_without_notes_count_nothing(self):
        page = self.render(release("2.0.0"),
                           release("1.9.0", change("fix", "A"), change("feat", "B"), change("fix", "C"),
                                   change("fix", "D", breaking=True), change("perf", "E")),
                           release("1.8.2"))
        self.assertEqual(re.findall(r'<span class="glance">([^<]*)</span>', page),
                         ["Shown above", "Heads up · 1 new · 2 fixed · 1 faster", ""])

    def test_out_of_order_or_unknown_changes_are_refused(self):
        with self.assertRaisesRegex(ValueError, "newest release first"):
            self.render(release("1.9.0"), release("1.10.0"))
        with self.assertRaisesRegex(ValueError, "non-breaking 'docs' change"):
            self.render(release("1.9.0", change("docs", "Reword the README")))

    def test_page_loads_nothing_from_outside_itself(self):
        page = whats_new.render(SAMPLE)
        self.assertIn("default-src 'none'", page)
        self.assertEqual(re.findall(r'(?:src|href)="(?!data:|#earlier")', page), [])
        self.assertEqual(re.findall(r"url\((?![\"']?data:|%23)", page), [])
        self.assertEqual(re.findall(r"\$\{?[a-z_]", page), [])

    def test_the_only_script_is_the_inline_one_its_policy_names(self):
        page = whats_new.render(SAMPLE)
        [code] = re.findall(r"<script>(.*?)</script>", page, re.S)
        self.assertEqual(page.count("<script"), 1)
        digest = base64.b64encode(hashlib.sha256(code.encode()).digest()).decode()
        self.assertEqual(re.search(r'script-src ([^;"]+)"', page)[1], f"'sha256-{digest}'")
        self.assertIn('"skipped one": "Straight from {from} to here? Bold.', code)

    def test_copy_cannot_close_the_script(self):
        words = dict(whats_new.COPY)
        self.addCleanup(whats_new.COPY.update, words)
        whats_new.COPY["skipped"] = "</script><b>"
        page = whats_new.render(SAMPLE)
        self.assertEqual(page.count("</script>"), 1)
        self.assertIn('"skipped": "\\u003c/script>\\u003cb>"', page)

    def test_each_inlined_asset_appears_once(self):
        page = whats_new.render(SAMPLE)
        for asset in ("Sources/WhatsNew/CormorantGaramond-SemiBoldItalic.woff",
                      "Sources/WhatsNew/mark.png", "Resources/ThemeTextures/grain.png"):
            self.assertEqual(page.count(whats_new.inline(REPO / asset)), 1, asset)

    def test_page_stays_small(self):
        self.assertLess(len(whats_new.render(REPO / "release-notes.json").encode()), 300_000)

    def test_favicon_is_square_so_it_is_not_stretched(self):
        page = whats_new.render(SAMPLE)
        icon = base64.b64decode(re.search(r'rel="icon" href="data:image/png;base64,([^"]+)"', page)[1])
        self.assertEqual(struct.unpack(">II", icon[16:24]), (32, 32))
        tall = Path(self.temporary.name) / "favicon.png"
        tall.write_bytes(icon[:16] + struct.pack(">II", 43, 64) + icon[24:])
        with self.assertRaises(ValueError):
            whats_new.favicon(tall)


if __name__ == "__main__":
    unittest.main()
