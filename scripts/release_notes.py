#!/usr/bin/env python3
"""Conventional Commit release bumps, release-notes.json and CHANGELOG.md."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TYPES = ("feat", "fix", "perf", "refactor", "docs", "build", "ci", "chore", "test", "style", "revert")
NOTABLE = ("feat", "fix", "perf")
SUBJECT = re.compile(r"(?P<type>[a-z]+)(?:\((?P<scope>[^()\s]+)\))?(?P<breaking>!)?: (?P<summary>\S.*)")
BREAKING = re.compile(r"^BREAKING[ -]CHANGE: ", re.MULTILINE)
UNDO = re.compile(r'(Revert|Reapply) "(.*)"')
SECTIONS = (("Heads up", None), ("New", "feat"), ("Fixed", "fix"), ("Faster", "perf"))
QUIET = "No user-facing changes."
RULE = ("Commit messages are one line, a Conventional Commit: type(scope)!: summary\n"
        "  for example: fix(sidebar): Keep pinned tabs after a restart\n"
        "  types: " + " ".join(TYPES) + "\n"
        "  feat, fix and perf subjects are Parc's release notes: write them for Parc users, starting with a capital.\n"
        "  No body or trailers such as Co-Authored-By; ! alone marks a breaking change.\n"
        '  A revert is one line too: Revert "fix(sidebar): Keep pinned tabs after a restart"')


def parse(message):
    """The Conventional Commit in a message, or None when its subject doesn't follow the format."""
    subject, _, body = message.strip().partition("\n")
    match = SUBJECT.fullmatch(subject.strip())
    if not match or match["type"] not in TYPES:
        return None
    return {"type": match["type"], "scope": match["scope"], "summary": match["summary"].strip(),
            "breaking": bool(match["breaking"] or BREAKING.search(body))}


def undone(subject):
    """("Revert" or "Reapply", the original subject) for git's own revert subjects, else (None, subject).

    Each Revert layer undoes the one inside it: git 2.43+ reverts Revert "S" as Reapply "S", older git as
    Revert "Revert "S"".
    """
    layers = []
    undo = UNDO.fullmatch(subject)
    while undo:
        layers.append(undo[1])
        subject = undo[2]
        undo = UNDO.fullmatch(subject)
    if not layers:
        return None, subject
    return ("Revert" if layers.count("Revert") % 2 else "Reapply"), subject


def last_release(repo, revision):
    """The newest release tag revision contains; a superseded run's version commit has none."""
    return subprocess.run(["git", "describe", "--tags", "--abbrev=0", "--match", "v[0-9]*.[0-9]*.[0-9]*", revision],
                          cwd=repo, capture_output=True, text=True, check=True).stdout.strip()


def changes(repo, since, until):
    """Parsed commits in since..until, oldest first, without merges or unparseable subjects.

    git's own Revert "subject" cancels that change and Reapply "subject" restores it.
    """
    log = subprocess.run(["git", "log", "-z", "--no-merges", "--reverse", "--format=%B", since + ".." + until],
                         cwd=repo, capture_output=True, text=True, check=True).stdout
    found, cancelled = [], {}
    for message in log.split("\0"):
        action, original = undone(message.strip().partition("\n")[0].strip())
        if action == "Revert":
            reverted = [index for index, (subject, _) in enumerate(found) if subject == original]
            if reverted:
                cancelled[original] = found.pop(reverted[-1])[1]
            else:
                # The change shipped before this range, so reapplying it here ships nothing new.
                cancelled.setdefault(original, None)
            continue
        if action:
            change = cancelled.pop(original) if original in cancelled else parse(original)
        else:
            change = parse(message)
        if change:
            found.append((original, change))
    return [change for _, change in found]


def bump(changes):
    if any(change["breaking"] for change in changes):
        return "major"
    if any(change["type"] == "feat" for change in changes):
        return "minor"
    if any(change["type"] in ("fix", "perf") for change in changes):
        return "patch"
    return None


def entry(version, build, date, changes):
    return {"version": version, "build": build, "date": date,
            "changes": [change for change in changes if change["type"] in NOTABLE or change["breaking"]]}


def record(notes, release, since):
    """Newest first. Entries after the published version `since` are a rerun of this release or a
    superseded run that never shipped; this release covers all of their changes, so it replaces them."""
    older = [item for item in notes["releases"] if number(item["version"]) <= number(since)]
    return {"releases": [release, *older]}


def number(version):
    return tuple(map(int, version.split(".")))


def display(summary):
    """Capitalizes an all-lowercase first word, leaving names like macOS or iCloud alone. Some subjects on main start
    lowercase, and release-notes.json keeps them as written."""
    return summary[:1].upper() + summary[1:] if summary.split(" ", 1)[0].islower() else summary


def markdown(release):
    lines = []
    for title, kind in SECTIONS:
        items = [change for change in release["changes"]
                 if (change["breaking"] if kind is None else change["type"] == kind and not change["breaking"])]
        if items:
            lines += ["", "### " + title, ""]
            lines += ["- " + (f"**{item['scope']}:** " if item["scope"] else "") + display(item["summary"])
                      for item in items]
    return "\n".join(lines).strip()


def changelog(notes):
    parts = ["# Changelog"]
    for release in notes["releases"]:
        parts += [f"## {release['version']} ({release['date']})", markdown(release) or QUIET]
    return "\n\n".join(parts) + "\n"


def files(notes, release, since):
    """release-notes.json and CHANGELOG.md after recording one release."""
    notes = record(notes, release, since)
    return {"release-notes.json": json.dumps(notes, indent=2) + "\n", "CHANGELOG.md": changelog(notes)}


def check(message, merge=False):
    """What breaks the commit rules in a stored message, else None; a merge may keep git's own body."""
    lines = [line for line in message.splitlines() if line.strip()]
    subject = lines[0] if lines else ""
    if (merge and subject.startswith("Merge ")) or (len(lines) == 1 and (UNDO.fullmatch(subject) or parse(subject))):
        return None
    return (subject or "(empty)") + (f" [{len(lines)} lines]" if len(lines) > 1 else "")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("markdown", help="print one recorded release's notes").add_argument("version")
    preview = commands.add_parser("preview", help="print the bump and notes a range would release")
    preview.add_argument("--since", help="default: the newest release tag in --until")
    preview.add_argument("--until", default="origin/main")
    args = parser.parse_args()
    if args.command == "markdown":
        releases = json.loads((ROOT / "release-notes.json").read_text())["releases"]
        found = [release for release in releases if release["version"] == args.version]
        if not found:
            sys.exit("release-notes.json has no release " + args.version)
        print(markdown(found[0]) or QUIET)
    else:
        since = args.since or last_release(ROOT, args.until)
        found = changes(ROOT, since, args.until)
        kind = bump(found)
        print(f"{kind or 'Nothing to release'} since {since}")
        if kind:
            print(markdown(entry("next", None, None, found)))


if __name__ == "__main__":
    main()
