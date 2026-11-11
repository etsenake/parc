#!/usr/bin/env python3
"""Enforce the 500-line ceiling for every repository Markdown document.

Changelogs are excluded by user direction. The default checks tracked files and new,
unignored files in the working tree; --ref checks the actual committed tree.
Git-ignored local output is excluded only when it is not tracked.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys

MAX_LINES = 500
REPO = Path(__file__).resolve().parents[1]


def git(repo: Path, *args: str, data: bytes | None = None) -> bytes:
    return subprocess.run(["git", *args], cwd=repo, input=data,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout


def markdown(path: str) -> bool:
    document = Path(path)
    return (document.suffix.lower() in {".md", ".mdc", ".markdown"}
            and document.stem.lower() != "changelog")


def working_documents(repo: Path) -> dict[str, bytes]:
    paths = git(repo, "ls-files", "--cached", "--others", "--exclude-standard", "-z")
    documents = {}
    for raw in sorted(set(paths.split(b"\0")) - {b""}):
        name = os.fsdecode(raw)
        if not markdown(name):
            continue
        path = repo / name
        if path.is_symlink():
            raise ValueError(f"{name}: Markdown documents must be regular files, not symlinks")
        try:
            documents[name] = path.read_bytes()
        except FileNotFoundError:
            pass
    return documents


def committed_documents(repo: Path, ref: str) -> dict[str, bytes]:
    tree = git(repo, "rev-parse", "--verify", "--end-of-options", f"{ref}^{{tree}}").strip()
    entries = git(repo, "ls-tree", "-rz", "--full-tree", tree.decode("ascii"))
    blobs = {}
    for record in filter(None, entries.split(b"\0")):
        header, raw_name = record.split(b"\t", 1)
        mode, kind, oid = header.split()
        name = os.fsdecode(raw_name)
        if not markdown(name):
            continue
        if kind != b"blob" or mode not in {b"100644", b"100755"}:
            raise ValueError(f"{name}: Markdown documents must be regular files")
        blobs[name] = oid
    if not blobs:
        return {}
    data = git(repo, "cat-file", "--batch", data=b"\n".join(blobs.values()) + b"\n")
    documents = {}
    offset = 0
    for name, expected in blobs.items():
        end = data.index(b"\n", offset)
        oid, kind, size = data[offset:end].split()
        if oid != expected or kind != b"blob":
            raise ValueError(f"{name}: could not read the committed document")
        offset = end + 1
        length = int(size)
        documents[name] = data[offset:offset + length]
        offset += length + 1
    return documents


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=REPO, help="Repository root (default: this checkout)")
    parser.add_argument("--ref", help="Check this Git commit, tag or tree instead of working files")
    args = parser.parse_args(argv)
    try:
        repo = args.repo.expanduser().resolve()
        root = Path(os.fsdecode(git(repo, "rev-parse", "--show-toplevel")).rstrip("\n")).resolve()
        if root != repo:
            raise ValueError(f"--repo must be the repository root: {root}")
        documents = committed_documents(repo, args.ref) if args.ref else working_documents(repo)
        oversized = []
        for name, content in documents.items():
            lines = len(content.decode("utf-8").splitlines())
            if lines > MAX_LINES:
                oversized.append(f"  {name}: {lines} lines (maximum {MAX_LINES})")
        if oversized:
            print("Documentation check failed:\n" + "\n".join(oversized), file=sys.stderr)
            print("Condense current guidance; keep history in Git and link focused guides.", file=sys.stderr)
            return 1
    except (OSError, UnicodeError, ValueError, subprocess.CalledProcessError) as error:
        detail = error.stderr.decode("utf-8", errors="replace").strip() if isinstance(error, subprocess.CalledProcessError) else str(error)
        print(f"Documentation check failed: {detail}", file=sys.stderr)
        return 1
    scope = f" at {args.ref}" if args.ref else " in the working tree"
    print(f"Documentation check passed: {len(documents)} Markdown files{scope}; maximum {MAX_LINES} lines.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
