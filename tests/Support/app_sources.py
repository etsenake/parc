#!/usr/bin/env python3
import pathlib
import re
import subprocess
import sys

from declarations import MODIFIERS, blocks

root = pathlib.Path(__file__).resolve().parents[2]
DIRECTORIES = (root / "Sources/ParcApp", root / "Sources/ParcCore")
TOP_LEVEL = re.compile(rf"^(?:@\w+(?:\([^)]*\))?\s+)*({MODIFIERS})(?:class|struct|enum|protocol|actor|typealias|func|let|var)\s+(\w+)", re.M)
MEMBER = re.compile(rf"^    (?:@\w+\s+)*({MODIFIERS})(?:static\s+)?(?:func|var|let)\s+(\w+)", re.M)
MISSING_NAME = re.compile(r"error: cannot find (?:type )?'(\w+)' in scope")
MISSING_MEMBER = re.compile(r"error: (?:value of )?type '[^']+' has no member '(\w+)'")
LIMIT = 40


def visible(modifiers):
    return not re.search(r"\b(?:private|fileprivate)\b", modifiers)


def index():
    names, members = {}, {}
    for directory in DIRECTORIES:
        for path in sorted(directory.glob("*.swift")):
            text = path.read_text()
            for modifiers, name in TOP_LEVEL.findall(text):
                if visible(modifiers):
                    names.setdefault(name, set()).add(path)
            for match, block in blocks(text):
                if match.group(1) == "extension":
                    for modifiers, name in MEMBER.findall(block):
                        if visible(modifiers):
                            members.setdefault(name, set()).add(path)
    return names, members


def additions(errors, compiled, declared):
    names, members = declared
    found = {}
    for pattern, table in ((MISSING_NAME, names), (MISSING_MEMBER, members)):
        for name in pattern.findall(errors):
            candidates = table.get(name, set())
            if len(candidates) == 1:
                path = next(iter(candidates))
                if path.resolve() not in compiled:
                    found.setdefault(path, name)
    return found


def report(result):
    sys.stdout.write(result.stdout)
    sys.stdout.flush()
    sys.stderr.write(result.stderr)
    sys.stderr.flush()


def compile_swift(command):
    command = [str(part) for part in command]
    declared = None
    added = 0
    while True:
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode == 0:
            report(result)
            return
        declared = declared or index()
        compiled = {pathlib.Path(part).resolve() for part in command if part.endswith(".swift")}
        found = additions(result.stderr, compiled, declared)
        if not found or added + len(found) > LIMIT:
            report(result)
            raise subprocess.CalledProcessError(result.returncode, command)
        position = command.index("-o") if "-o" in command else len(command)
        for path, name in sorted(found.items()):
            sys.stderr.write(f"tests/Support/app_sources.py: added {path.relative_to(root)} for {name}\n")
            sys.stderr.flush()
            command.insert(position, str(path))
        added += len(found)


if __name__ == "__main__":
    try:
        compile_swift(sys.argv[1:])
    except subprocess.CalledProcessError as error:
        sys.exit(128 - error.returncode if error.returncode < 0 else error.returncode)
