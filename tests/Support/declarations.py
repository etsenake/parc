#!/usr/bin/env python3
"""declarations.py <output .swift> <name>...

Writes the top-level declaration of each name (a class, struct or enum, or
the extension declaring a member of that name), cut whole with its file's
imports from the one Sources/ParcApp file that holds it, so a check can
compile a small type that lives inside a file it can't compile without
depending on where in that file it sits. Braces are counted as written, so a
cut declaration must not hold an unbalanced brace in a string or comment.
Prints the output path."""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parents[2]
MODIFIERS = r"(?:(?:final|private|fileprivate|internal|public|open|nonisolated)\s+)*"
TOP_LEVEL = re.compile(rf"^(?:@\w+(?:\([^)]*\))?\s+)*{MODIFIERS}(class|struct|enum|extension)\s+(\w+)", re.M)


def blocks(text):
    for match in TOP_LEVEL.finditer(text):
        depth = 0
        for end in range(text.index("{", match.end()), len(text)):
            depth += {"{": 1, "}": -1}.get(text[end], 0)
            if depth == 0:
                yield match, text[match.start():end + 1]
                break


def declaration(name):
    member = re.compile(rf"^    (?:@\w+\s+)*{MODIFIERS}(?:static\s+)?(?:let|var|func)\s+{name}\b", re.M)
    found = []
    for path in sorted((root / "Sources/ParcApp").glob("*.swift")):
        text = path.read_text()
        for match, block in blocks(text):
            kind, declared = match.groups()
            if (kind != "extension" and declared == name) or (kind == "extension" and member.search(block)):
                found.append((path.name, re.findall(r"^import \w+$", text, re.M), block))
    if len(found) != 1:
        raise SystemExit(f"tests/Support/declarations.py: {len(found)} top-level Sources/ParcApp declarations of {name}: "
                         + ", ".join(name for name, _, _ in found))
    return found[0][1:]


if __name__ == "__main__":
    output = pathlib.Path(sys.argv[1])
    found = [declaration(name) for name in sys.argv[2:]]
    imports = sorted({line for lines, _ in found for line in lines})
    output.write_text("\n".join(imports) + "\n\n" + "\n\n".join(block for _, block in found) + "\n")
    print(output)
