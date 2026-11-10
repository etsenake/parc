#!/usr/bin/env python3
"""Render Parc's self-contained What's New page from release-notes.json."""
import argparse
import base64
import datetime
import hashlib
from html import escape
import importlib.util
import json
from pathlib import Path
from string import Template
import struct

notes_spec = importlib.util.spec_from_file_location("parc_release_notes", Path(__file__).with_name("release_notes.py"))
release_notes = importlib.util.module_from_spec(notes_spec)
notes_spec.loader.exec_module(release_notes)

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = "Sources/WhatsNew/WhatsNew.html"
SCRIPT = "Sources/WhatsNew/WhatsNew.js"
# Every line the timeline says, kept here for rewording. The page fills in
# {from} and {count} when See What's New opens it after an update.
COPY = {
    "skipped": "Straight from {from} to here? Bold. Here are the {count} releases you leapfrogged.",
    "skipped one": "Straight from {from} to here? Bold. Here’s the release you leapfrogged.",
    "catch up": "Catch me up ↓",
    "intro": "What we’ve been up to.",
    "no notes": "Tightened screws, oiled hinges, fewer crashes. Nothing flashy, just keeping the lights on.",
    "this version": "This version",
    "shown above": "Shown above",
    "new to you": "New to you",
    "previous version": "Your previous version",
}
# Breaking changes lead whatever their type; the rest group by type.
GROUPS = (("breaking", "heads-up", "Heads up"), ("feat", "new", "New"),
          ("fix", "fixed", "Fixed"), ("perf", "faster", "Faster"))


def read_releases(path: Path) -> list:
    """Releases newest first; a missing file is an empty history."""
    try:
        releases = json.loads(path.read_text(encoding="utf-8"))["releases"]
    except FileNotFoundError:
        return []
    for release in releases:
        for change in release["changes"]:
            if not change["breaking"] and change["type"] not in ("feat", "fix", "perf"):
                raise ValueError(f"{release['version']}: a non-breaking {change['type']!r} change has no group")
    versions = [tuple(int(part) for part in release["version"].split(".")) for release in releases]
    if versions != sorted(versions, reverse=True):
        raise ValueError("release-notes.json must list the newest release first")
    return releases


def members(changes: list, key: str) -> list:
    return [change for change in changes
            if (change["breaking"] and key == "breaking") or (not change["breaking"] and change["type"] == key)]


def render_groups(changes: list, heading: str, quiet: str = release_notes.QUIET) -> str:
    html = []
    for key, name, title in GROUPS:
        summaries = [change["summary"] for change in members(changes, key)]
        if summaries:
            items = "".join(f"<li>{escape(release_notes.display(summary))}</li>" for summary in summaries)
            html.append(f'<div class="group {name}"><{heading} class="label">{title}</{heading}>'
                        f"<ul>{items}</ul></div>")
    return "\n".join(html) or f'<p class="quiet">{escape(quiet)}</p>'


def glance(changes: list) -> str:
    """A closed row's summary, such as "2 new · 3 fixed"; nothing for a release without notes."""
    counts = [(key, title, len(members(changes, key))) for key, _, title in GROUPS]
    return " · ".join(title if key == "breaking" else f"{count} {title.lower()}" for key, title, count in counts if count)


def long_date(value: str) -> str:
    date = datetime.date.fromisoformat(value)
    return f"{date:%B} {date.day}, {date.year}"


def render_content(releases: list) -> str:
    if not releases:
        return ('<section class="empty"><h2>A clean slate</h2>'
                "<p>This build of Parc doesn’t have release notes yet. "
                "They’ll show up here after your next update.</p></section>")
    latest, *earlier = releases
    notes = '<p class="lead">Thanks for using Parc! Here’s what’s new in this version.</p>\n'
    if earlier:
        # Shown by WhatsNew.js when See What's New opens the page after an update that skipped releases.
        notes += f'<p class="skipped" hidden><span></span><a href="#earlier">{escape(COPY["catch up"])}</a></p>\n'
    notes += render_groups(latest["changes"], "h3", COPY["no notes"])
    html = ['<section class="latest">'
            f'<p class="eyebrow">{escape(long_date(latest["date"]))} · Build {escape(str(latest["build"]))}</p>'
            f'<h2>Parc {escape(latest["version"])}</h2>{notes}</section>']
    if earlier:
        html.append('<div class="squiggle"></div><section class="earlier" id="earlier"><h2>Earlier releases</h2>'
                    f'<p>{escape(COPY["intro"])}</p><ol class="timeline">'
                    f'<li class="step current" data-version="{escape(latest["version"])}"><div class="row">'
                    f'<span class="version">{escape(latest["version"])}</span>'
                    f'<span class="tag">{escape(COPY["this version"])}</span>'
                    f'<span class="glance">{escape(COPY["shown above"])}</span>'
                    f'<span class="date">{escape(long_date(latest["date"]))}</span></div></li>')
        for release in earlier:
            version = escape(release["version"])
            html.append(f'<li class="step" data-version="{version}"><details><summary class="row">'
                        f'<span class="version">{version}</span><span class="glance">{escape(glance(release["changes"]))}</span>'
                        f'<span class="date">{escape(long_date(release["date"]))}</span><span class="chevron"></span>'
                        f'</summary><div class="notes">{render_groups(release["changes"], "h4", COPY["no notes"])}</div></details></li>')
        html.append("</ol></section>")
    html.append('<p class="signoff">That’s everything. Happy browsing!</p>')
    return "\n".join(html)


def inline(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode()


def favicon(path: Path) -> str:
    """Chromium stores favicons as square 16 and 32 px bitmaps, which stretches any other shape."""
    width, height = struct.unpack(">II", path.read_bytes()[16:24])
    if width != height:
        raise ValueError(f"{path.name} is {width} × {height}; a favicon must be square")
    return inline(path)


def script(repo: Path) -> str:
    """WhatsNew.js after the copy it shows. "<" is escaped so no copy can close the script element."""
    words = {key: COPY[key] for key in ("skipped", "skipped one", "new to you", "previous version")}
    words = json.dumps(words, ensure_ascii=False).replace("<", "\\u003c")
    return f"const copy = {words};\n" + (repo / SCRIPT).read_text(encoding="utf-8")


def render(notes: Path, repo: Path = ROOT) -> str:
    page = Template((repo / TEMPLATE).read_text(encoding="utf-8"))
    code = script(repo)
    return page.substitute(font=inline(repo / "Sources/WhatsNew/CormorantGaramond-SemiBoldItalic.woff"),
                           mark=inline(repo / "Sources/WhatsNew/mark.png"),
                           grain=inline(repo / "Resources/ThemeTextures/grain.png"),
                           favicon=favicon(repo / "Sources/WhatsNew/favicon.png"),
                           content=render_content(read_releases(notes)), script=code,
                           script_hash=base64.b64encode(hashlib.sha256(code.encode()).digest()).decode())


def write(repo: Path, output: Path) -> None:
    """Write the bundled page from the repository's release notes."""
    output.write_text(render(repo / "release-notes.json", repo), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--notes", type=Path, default=ROOT / "release-notes.json")
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(render(arguments.notes), encoding="utf-8")


if __name__ == "__main__":
    main()
