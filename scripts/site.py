#!/usr/bin/env python3
"""Build parcbrowser.com from site/, filling its release slots and adding the site's What's New page."""
import argparse
from html import escape
import importlib.util
from pathlib import Path
import shutil
import sys

whats_new_spec = importlib.util.spec_from_file_location("parc_whats_new", Path(__file__).with_name("whats_new.py"))
whats_new = importlib.util.module_from_spec(whats_new_spec)
whats_new_spec.loader.exec_module(whats_new)

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "site"
DOWNLOAD = "https://github.com/etsenake/parc-releases/releases/latest/download/Parc-arm64.dmg"
BUILD_MARK = ".parc-site-build"

FRESH_SLOT = '<section id="fresh" class="fresh sec" data-fill="latest-release" hidden></section>'
VERSION_SLOT = '<span data-fill="version"></span>'
ARROW = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14"/><path d="M13 6l6 6-6 6"/></svg>'
OLD_LEAD = "Thanks for using Parc! Here’s what’s new in this version."
NEW_LEAD = "Every Parc release, in plain words. Here’s the newest one."
WHATS_NEW_DESCRIPTION = "Every Parc release, in plain words: what’s new, what’s fixed and what got faster."
WHATS_NEW_URL = "https://parcbrowser.com/whats-new/"
SHARE_IMAGE = "https://parcbrowser.com/assets/og.png"

SITE_HEAD = (
    f'\n<meta name="description" content="{WHATS_NEW_DESCRIPTION}">'
    f'\n<link rel="canonical" href="{WHATS_NEW_URL}">'
    '\n<meta property="og:type" content="website">'
    '\n<meta property="og:site_name" content="Parc">'
    '\n<meta property="og:title" content="What’s New in Parc">'
    f'\n<meta property="og:description" content="{WHATS_NEW_DESCRIPTION}">'
    f'\n<meta property="og:url" content="{WHATS_NEW_URL}">'
    f'\n<meta property="og:image" content="{SHARE_IMAGE}">'
    '\n<meta name="twitter:card" content="summary_large_image">'
)
SITE_NAV = (f'<nav class="site-nav" aria-label="Site"><a class="home" href="../"><span class="mark" aria-hidden="true">'
            f'</span>Parc</a><a class="get" href="{DOWNLOAD}">Download</a></nav>')
SITE_FOOT = (
    '<footer class="site-foot"><div class="squiggle"></div><h2>Not on Parc yet?</h2>'
    '<p>Free and open source, for Apple Silicon Macs on macOS 13 or later. It updates itself, and every update shows up here.</p>'
    f'<p class="site-cta"><a class="get" href="{DOWNLOAD}">Download Parc</a><code>brew install --cask etsenake/tap/parc</code></p>'
    '<p class="site-links"><a href="../">parcbrowser.com</a><a href="https://github.com/etsenake/parc">Source on GitHub</a></p>'
    '</footer>\n'
)
SITE_STYLE = """
.banner.site{position:relative;padding-top:120px}
.site-nav{position:absolute;top:0;left:0;right:0;display:flex;align-items:center;justify-content:space-between;gap:16px;max-width:1120px;margin:0 auto;padding:24px 32px}
.site-nav a{color:#FFFCEC;text-decoration:none}
.home{display:inline-flex;align-items:center;gap:10px;font:italic 600 30px/1 var(--display)}
.home .mark{width:17px;height:25px;margin:0}
.get{display:inline-flex;align-items:center;padding:11px 20px;border-radius:999px;background:#FFFCEC;font:600 15px/1 var(--body);text-decoration:none;transition:transform .3s cubic-bezier(.3,1.6,.5,1)}
.site-nav .get{color:#3139FB}
.get:hover{transform:translateY(-1px) scale(1.03)}
.site-foot{padding:0 0 96px;text-align:center}
.site-foot .squiggle{margin:0 0 56px}
.site-foot h2{font:italic 600 46px/1 var(--display);letter-spacing:-.01em;color:var(--ink)}
.site-foot p{max-width:440px;margin:16px auto 0;font-size:16px}
.site-foot .site-cta{display:flex;flex-wrap:wrap;align-items:center;justify-content:center;gap:12px 18px;max-width:none;margin-top:28px}
.site-foot .get{background:var(--new);color:#FFFCEC}
.site-cta code{font:13px var(--mono);color:var(--muted)}
.site-foot .site-links{display:flex;justify-content:center;gap:22px;margin-top:36px;font-size:14px}
.site-links a{color:var(--muted)}
.site-links a:hover{color:var(--new)}
@media (max-width:640px){.banner.site{padding-top:104px}.site-nav{padding:18px 24px}.home{font-size:26px}}
"""

def releases() -> list:
    return whats_new.read_releases(ROOT / "release-notes.json")


def replace_once(text: str, anchor: str, replacement: str, where: str) -> str:
    count = text.count(anchor)
    if count != 1:
        raise SystemExit(f"{where}: expected exactly one {anchor!r}, found {count}")
    return text.replace(anchor, replacement)


def scope_label(scope) -> str:
    return scope.replace("-", " ").capitalize() if scope else ""


def fresh_section(release) -> str:
    if release is None:
        return ""
    notable = [change for change in release["changes"]
               if not change["breaking"] and change["type"] in ("feat", "fix", "perf")]
    picks = [change for change in notable if change["type"] == "feat"][:3] or notable[:3]
    items = []
    for change in picks:
        label = scope_label(change["scope"])
        chip = f"<span>{escape(label, quote=False)}</span>" if label else ""
        items.append(f"<li>{chip}{escape(whats_new.release_notes.display(change['summary']), quote=False)}</li>")
    glance = whats_new.glance(release["changes"])
    meta = escape(whats_new.long_date(release["date"])) + (f" · {escape(glance)}" if glance else "")
    return ('<section id="fresh" class="fresh sec" aria-labelledby="fresh-title"><div class="wrap fresh-panel"><div>'
            '<p class="eyebrow">Fresh paint</p>'
            f'<h2 class="h2" id="fresh-title">Parc {escape(release["version"])} is out.</h2>'
            f'<p class="fresh-meta">{meta}</p>'
            f'<a class="btn-ink fresh-btn" href="whats-new/">Read what’s new{ARROW}</a></div>'
            f'<ul class="fresh-list">{"".join(items)}</ul></div></section>')


def fill_index(text: str, history: list) -> str:
    latest = history[0] if history else None
    text = replace_once(text, FRESH_SLOT, fresh_section(latest), "index.html")
    version = f'<span data-fill="version">Parc {escape(latest["version"])} · </span>' if latest else ""
    return replace_once(text, VERSION_SLOT, version, "index.html")


def site_whats_new(page: str) -> str:
    page = replace_once(page, "<title>What’s New in Parc</title>", "<title>What’s New in Parc</title>" + SITE_HEAD,
                        "What's New")
    page = replace_once(page, '<header class="banner">', '<header class="banner site">\n' + SITE_NAV, "What's New")
    if OLD_LEAD in page:
        page = replace_once(page, OLD_LEAD, NEW_LEAD, "What's New")
    page = replace_once(page, "</main>", SITE_FOOT + "</main>", "What's New")
    return replace_once(page, "</style>", SITE_STYLE + "</style>", "What's New")


def build(arguments) -> None:
    out = Path(arguments.out).resolve()
    if out == ROOT or out.is_relative_to(SITE) or SITE.is_relative_to(out):
        raise SystemExit(f"{out} overlaps the site's sources in {SITE}; pick a folder outside them")
    if out.exists() and not out.is_dir():
        raise SystemExit(f"{out} is a file, not a folder; pick a folder for the site")
    if out.exists() and any(out.iterdir()):
        if not (out / BUILD_MARK).is_file():
            raise SystemExit(f"{out} isn't empty and isn't an earlier site build; pick another folder")
        shutil.rmtree(out)
    elif out.exists():
        out.rmdir()
    shutil.copytree(SITE, out)
    (out / BUILD_MARK).write_text("Built by scripts/site.py; a later build may replace this folder.\n", encoding="utf-8")
    history = releases()
    index = out / "index.html"
    index.write_text(fill_index(index.read_text(encoding="utf-8"), history), encoding="utf-8")
    page = out / "whats-new" / "index.html"
    page.parent.mkdir(parents=True, exist_ok=True)
    page.write_text(site_whats_new(whats_new.render(ROOT / "release-notes.json")), encoding="utf-8")
    print(f"Built the site in {out}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    built = commands.add_parser("build", help="build the site into a folder")
    built.add_argument("out", nargs="?", default=str(ROOT / "build/site"))
    built.set_defaults(run=build)
    arguments = parser.parse_args()
    arguments.run(arguments)


if __name__ == "__main__":
    sys.exit(main())
