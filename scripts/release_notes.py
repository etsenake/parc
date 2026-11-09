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
GENERATED = ("Merge ", 'Revert "', 'Reapply "', "fixup! ", "squash! ", "amend! ")
UNDO = re.compile(r'(Revert|Reapply) "(.*)"')
SECTIONS = (("Heads up", None), ("New", "feat"), ("Fixed", "fix"), ("Faster", "perf"))


def parse(message):
    """The Conventional Commit in a message, or None when its subject doesn't follow the format."""
    subject, _, body = message.strip().partition("\n")
    match = SUBJECT.fullmatch(subject.strip())
    if not match or match["type"] not in TYPES:
        return None
    return {"type": match["type"], "scope": match["scope"], "summary": match["summary"].strip(),
            "breaking": bool(match["breaking"] or BREAKING.search(body))}


def changes(repo, since, until):
    """Parsed commits in since..until, oldest first, without merges or unparseable subjects.

    git's own Revert "subject" cancels that change within the range; Reapply "subject" restores it.
    """
    log = subprocess.run(["git", "log", "-z", "--no-merges", "--reverse", "--format=%B", since + ".." + until],
                         cwd=repo, capture_output=True, text=True, check=True).stdout
    found, cancelled = [], {}
    for message in log.split("\0"):
        subject = message.strip().partition("\n")[0].strip()
        undo = UNDO.fullmatch(subject)
        if undo and undo[1] == "Revert":
            reverted = [index for index, (original, _) in enumerate(found) if original == undo[2]]
            if reverted:
                cancelled[undo[2]] = found.pop(reverted[-1])[1]
            continue
        if undo:
            change = cancelled.pop(undo[2], None) or parse(undo[2])
        else:
            change = parse(message)
        if change:
            found.append((subject, change))
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


def record(notes, release):
    """Newest first; a rerun replaces its own version in place instead of appending it twice."""
    releases = notes["releases"]
    if any(item["version"] == release["version"] for item in releases):
        return {"releases": [release if item["version"] == release["version"] else item for item in releases]}
    return {"releases": [release, *releases]}


def markdown(release):
    lines = []
    for title, kind in SECTIONS:
        items = [change for change in release["changes"]
                 if (change["breaking"] if kind is None else change["type"] == kind and not change["breaking"])]
        if items:
            lines += ["", "### " + title, ""]
            lines += ["- " + (f"**{item['scope']}:** " if item["scope"] else "") + item["summary"] for item in items]
    return "\n".join(lines).strip()


def changelog(notes):
    parts = ["# Changelog"]
    for release in notes["releases"]:
        parts += [f"## {release['version']} ({release['date']})", markdown(release) or "No user-facing changes."]
    return "\n\n".join(parts) + "\n"


def write(repo, release):
    """Record one release in release-notes.json and regenerate CHANGELOG.md from it."""
    path = Path(repo) / "release-notes.json"
    notes = record(json.loads(path.read_text()), release)
    path.write_text(json.dumps(notes, indent=2) + "\n")
    (Path(repo) / "CHANGELOG.md").write_text(changelog(notes))


def check(message):
    """An error for a commit message the commit-msg hook must reject, else None."""
    subject = next((line for line in message.splitlines() if line.strip() and not line.startswith("#")), "")
    if subject.startswith(GENERATED) or parse(subject):
        return None
    return ("Commit subjects use Conventional Commits: type(scope)!: summary\n"
            "  for example: fix(sidebar): Keep pinned tabs after a restart\n"
            "  types: " + " ".join(TYPES) + "\n"
            "  feat, fix and perf subjects become Parc's release notes; write them for Parc users.\n"
            "  rejected: " + (subject or "(empty)"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("check", help="validate a commit message file").add_argument("file")
    commands.add_parser("markdown", help="print one recorded release's notes").add_argument("version")
    preview = commands.add_parser("preview", help="print the bump and notes a range would release")
    preview.add_argument("--since", help="default: the tag of app-version.json")
    preview.add_argument("--until", default="origin/main")
    args = parser.parse_args()
    if args.command == "check":
        error = check(Path(args.file).read_text())
        if error:
            sys.exit(error)
    elif args.command == "markdown":
        releases = json.loads((ROOT / "release-notes.json").read_text())["releases"]
        found = [release for release in releases if release["version"] == args.version]
        if not found:
            sys.exit("release-notes.json has no release " + args.version)
        print(markdown(found[0]))
    else:
        since = args.since or "v" + json.loads((ROOT / "app-version.json").read_text())["version"]
        found = changes(ROOT, since, args.until)
        kind = bump(found)
        print(f"{kind or 'Nothing to release'} since {since}")
        if kind:
            print(markdown(entry("next", None, None, found)))


if __name__ == "__main__":
    main()
