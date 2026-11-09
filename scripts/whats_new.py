#!/usr/bin/env python3
"""Render Parc's self-contained What's New page from release-notes.json."""
import argparse
import base64
import datetime
from html import escape
import json
from pathlib import Path
from string import Template

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = "Sources/WhatsNew/WhatsNew.html"
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


def render_groups(changes: list, heading: str) -> str:
    html = []
    for key, name, title in GROUPS:
        summaries = [change["summary"] for change in changes
                     if (change["breaking"] and key == "breaking")
                     or (not change["breaking"] and change["type"] == key)]
        if summaries:
            items = "".join(f"<li>{escape(summary)}</li>" for summary in summaries)
            html.append(f'<div class="group {name}"><{heading} class="label">{title}</{heading}>'
                        f"<ul>{items}</ul></div>")
    return "\n".join(html) or '<p class="quiet">Behind-the-scenes work only.</p>'


def long_date(value: str) -> str:
    date = datetime.date.fromisoformat(value)
    return f"{date:%B} {date.day}, {date.year}"


def render_content(releases: list) -> str:
    if not releases:
        return ('<section class="empty"><h2>A clean slate</h2>'
                "<p>This build of Parc doesn’t have release notes yet. "
                "They’ll show up here after your next update.</p></section>")
    latest, *earlier = releases
    if latest["changes"]:
        notes = ('<p class="lead">Thanks for using Parc! Here’s what’s new in this version.</p>\n'
                 + render_groups(latest["changes"], "h3"))
    else:
        notes = '<p class="lead">Thanks for using Parc! This version is all behind-the-scenes work.</p>'
    html = ['<section class="latest">'
            f'<p class="eyebrow">{escape(long_date(latest["date"]))} · Build {escape(str(latest["build"]))}</p>'
            f'<h2>Parc {escape(latest["version"])}</h2>{notes}</section>']
    if earlier:
        html.append('<div class="squiggle"></div><section class="earlier"><h2>Earlier releases</h2>')
        for release in earlier:
            html.append(f'<article class="release"><header><h3>{escape(release["version"])}</h3>'
                        f'<p class="date">{escape(long_date(release["date"]))}</p></header>'
                        f'<div>{render_groups(release["changes"], "h4")}</div></article>')
        html.append("</section>")
    html.append('<p class="signoff">That’s everything. Happy browsing!</p>')
    return "\n".join(html)


def inline(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode()


def render(notes: Path, repo: Path = ROOT) -> str:
    page = Template((repo / TEMPLATE).read_text(encoding="utf-8"))
    return page.substitute(font=inline(repo / "Resources/Onboarding/MarlinSoftSQ-ExtraBold.otf"),
                           mark=inline(repo / "Resources/AppIcons/Marks/Monochrome.png"),
                           favicon=inline(repo / "Sources/WhatsNew/favicon.png"),
                           content=render_content(read_releases(notes)))


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
