#!/usr/bin/env python3
from functools import lru_cache
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"

CONTROLS = "NSButton|NSPopUpButton|NSSwitch|NSSegmentedControl|NSColorWell"
KEEP_CURSOR = {
    "CommandBarScopeHint": "a hint with no action",
    "FavoriteTile": "a tab, which keeps the arrow like the sidebar's rows",
    "PictureInPictureBarControl": "its own cursor rect: the PiP panel is rarely key",
    "SidebarPlusRowButton": "a menu row",
    "ThemeIconButton": "the hand, enabled or not",
    "ThemeAppearanceButton": "the hand, enabled or not",
    "UpdateBannerKeyStop": "its own cursor rect over the SwiftUI control it stands in for",
}
PLAIN_BUTTON_FILES = {"OnboardingImportBookmarksPicker.swift": "the bookmark list in setup keeps the arrow"}
STYLES_SHOWN_BY_KEY_STOPS = {
    ("UpdateReadyCard.swift", "Bare"): "the banner's key-stop modifier gives the hand",
    ("UpdateReadyCard.swift", "Style"): "the banner's key-stop modifier gives the hand",
}
TAPS_KEEPING_THE_ARROW = {
    ("OnboardingPasswordHelp.swift", "onTapGesture(perform: dismiss)"): "the dimmed backdrop around the help card",
    ("RecentTabSwitcherView.swift", "onTapGesture { choose(item.id) }"): "a tab card, which keeps the arrow like the sidebar's rows",
}
WIRING = "func pointingHandCursor() -> some View { modifier(PointingHandCursor()) }"
BLOCKS = {
    "PointingHandCursor": (r"^struct PointingHandCursor: ViewModifier \{$", [
        "@Environment(\\.isEnabled) private var isEnabled",
        "let marked = content.background(PointingHandCursorArea())",
        "if #available(macOS 15, *) { marked.pointerStyle(isEnabled ? .link : nil) } else { marked }",
    ]),
    "PointingHandCursorArea": (r"^private struct PointingHandCursorArea: NSViewRepresentable \{$", [
        "func updateNSView(_ view: AreaView, context: Context) { view.enabled = context.environment.isEnabled }",
        "var enabled = true { didSet { if enabled != oldValue { window?.invalidateCursorRects(for: self) } } }",
        "override func hitTest(_ point: NSPoint) -> NSView? { nil }",
        "if enabled { addCursorRect(visibleRect, cursor: .pointingHand) }",
    ]),
}
GESTURE_CALL = re.compile(r"\.(?:gesture|simultaneousGesture|highPriorityGesture)\(\s*(\w*)")
CLICK_GESTURE = re.compile(r"\b(?:Spatial)?TapGesture\b|\bLongPressGesture\b")
NON_CLICK_GESTURES = {"DragGesture", "MagnifyGesture", "MagnificationGesture", "RotateGesture", "RotationGesture"}


def helper_problems(text):
    failures = [] if WIRING in text else ["PointingHand.swift: pointingHandCursor() should apply PointingHandCursor"]
    for name, (start, needed) in BLOCKS.items():
        match = re.search(start, text, re.M)
        end = text.find("\n}", match.end()) if match else -1
        body = {line.strip() for line in text[match.end():end].splitlines()} if match else set()
        failures += [f"PointingHand.swift: {name} should contain the line {line}" for line in needed if line not in body]
    return failures


def bracket_depths(text):
    depths, strings, depth, quoted, hashes, resume, index = [0] * len(text), [False] * len(text), 0, False, "", [], 0
    while index < len(text):
        char = text[index]
        if quoted:
            strings[index], depths[index] = True, depth
            escape = "\\" + hashes
            if text.startswith(escape, index) and index + len(escape) < len(text):
                for offset in range(len(escape) + 1):
                    strings[index + offset], depths[index + offset] = True, depth
                if text[index + len(escape)] == "(":
                    resume.append((depth, hashes))
                    depth, quoted = depth + 1, False
                index += len(escape) + 1
                continue
            if char == '"' and text.startswith(hashes, index + 1):
                for offset in range(len(hashes) + 1):
                    strings[index + offset], depths[index + offset] = True, depth
                quoted = False
                index += len(hashes) + 1
                continue
        elif char == '"':
            hashes = re.search(r"#*$", text[:index]).group(0)
            quoted, strings[index], depths[index] = True, True, depth
        elif char in "([{":
            depths[index] = depth
            depth += 1
        elif char in ")]}":
            depth -= 1
            depths[index] = depth
            if char == ")" and resume and depth == resume[-1][0]:
                hashes = resume.pop()[1]
                quoted, strings[index] = True, True
        else:
            depths[index] = depth
        index += 1
    return depths, strings


def continues_chain(text, newline):
    return text[newline + 1:].lstrip(" \t").startswith(".")


def chain(text, depths, strings, position):
    level = depths[position]
    start = position
    while start > 0 and depths[start - 1] >= level:
        if text[start - 1] == "\n" and depths[start - 1] == level and not continues_chain(text, start - 1):
            break
        start -= 1
    end = position
    while end < len(text) and depths[end] >= level:
        if text[end] == "\n" and depths[end] == level and not continues_chain(text, end):
            break
        end += 1
    return "".join(char for index, char in enumerate(text[start:end], start)
                   if depths[index] == level and not strings[index])


def argument(text, depths, opening):
    end = opening + 1
    while end < len(text) and depths[end] > depths[opening]:
        end += 1
    return text[opening + 1:end]


def clickable_positions(text, depths):
    for match in re.finditer(r"\.onTapGesture\b|\.onLongPressGesture\b", text):
        yield match.start()
    for match in GESTURE_CALL.finditer(text):
        opening = text.index("(", match.start())
        if match.group(1) not in NON_CLICK_GESTURES or CLICK_GESTURE.search(argument(text, depths, opening)):
            yield match.start()


def problems(files):
    return [failure for name, text in sorted(files.items()) for failure in file_problems(name, text)]


@lru_cache(maxsize=None)
def file_problems(name, text):
    failures = []
    if name == "PointingHand.swift":
        return tuple(helper_problems(text))
    lines = text.splitlines()
    for match in re.finditer(rf"class (\w+): ({CONTROLS})\b", text):
        if match.group(1) not in KEEP_CURSOR:
            failures.append(f"{name}: {match.group(1)} should subclass PointingHand{match.group(2)[2:]}")
    for match in re.finditer(rf"(?<![\w.])({CONTROLS})\(", text):
        line = text.count("\n", 0, match.start()) + 1
        failures.append(f"{name}:{line}: use PointingHand{match.group(1)[2:]} instead of {match.group(1)}")
    if name not in PLAIN_BUTTON_FILES:
        for index, line in enumerate(lines):
            if re.search(r"\.buttonStyle\(\.\w+\)", line):
                around = "\n".join(lines[max(0, index - 20):index + 6])
                if "pointingHandCursor()" not in around and "updateBannerKeyStop(" not in around:
                    failures.append(f"{name}:{index + 1}: give this button .pointingHandCursor()")
    depths, strings = bracket_depths(text)
    for position in clickable_positions(text, depths):
        line = text.count("\n", 0, position)
        if any(name == file and snippet in lines[line] for file, snippet in TAPS_KEEPING_THE_ARROW):
            continue
        if ".pointingHandCursor()" not in chain(text, depths, strings, position):
            failures.append(f"{name}:{line + 1}: give this clickable view .pointingHandCursor()")
    for match in re.finditer(r"^( *)(?:@MainActor )?(?:private |fileprivate )?struct (\w+): [^{]*\bButtonStyle\b[^{]*\{$", text, re.M):
        indent, style = match.groups()
        end = text.find(f"\n{indent}}}", match.end())
        if (name, style) not in STYLES_SHOWN_BY_KEY_STOPS and "pointingHandCursor()" not in text[match.end():end]:
            failures.append(f"{name}: {style} should end its body with .pointingHandCursor()")
    return tuple(failures)


def probe(body):
    return "import SwiftUI\n\nstruct Probe: View {\n    var body: some View {\n" + body + "    }\n}\n"


files = {path.name: path.read_text() for path in sorted(app.glob("*.swift"))}
failures = problems(files)

helper = files.get("PointingHand.swift", "")
style_line = "if #available(macOS 15, *) { marked.pointerStyle(isEnabled ? .link : nil) } else { marked }"
broken = {
    "a helper with only the cursor rectangle": ("PointingHand.swift", helper.replace(style_line, "marked"),
                                                "should contain the line if #available"),
    "a helper whose pointer style is never applied": ("PointingHand.swift", helper.replace(
        style_line, "if #available(macOS 15, *) { _ = marked.pointerStyle(isEnabled ? .link : nil); marked } else { marked }"),
        "should contain the line if #available"),
    "a helper that ignores the enabled state": ("PointingHand.swift", helper.replace(
        ".pointerStyle(isEnabled ? .link : nil)", ".pointerStyle(.link)"), "should contain the line if #available"),
    "a helper without its cursor rectangle": ("PointingHand.swift", helper.replace(
        "let marked = content.background(PointingHandCursorArea())", "let marked = content"), "should contain the line let marked"),
    "a cursor rectangle that is never added": ("PointingHand.swift", helper.replace(
        "if enabled { addCursorRect(visibleRect, cursor: .pointingHand) }", ""), "should contain the line if enabled { addCursorRect"),
    "a cursor rectangle that ignores the enabled state": ("PointingHand.swift", helper.replace(
        "{ view.enabled = context.environment.isEnabled }", "{}"), "should contain the line func updateNSView"),
    "a cursor rectangle that never refreshes": ("PointingHand.swift", helper.replace(
        "var enabled = true { didSet { if enabled != oldValue { window?.invalidateCursorRects(for: self) } } }",
        "var enabled = true"), "should contain the line var enabled"),
    "a helper that isn't wired to the modifier": ("PointingHand.swift", helper.replace(WIRING,
        "func pointingHandCursor() -> some View { self }"), "should apply PointingHandCursor"),
    "a tapped view whose neighbour has the hand": ("PointingHandProbe.swift", probe(
        "        VStack {\n            Text(\"Hint\").pointingHandCursor()\n            Text(\"Go\")\n"
        "                .padding()\n                .onTapGesture {}\n        }\n"), "give this clickable view"),
    "a tapped view whose overlay has the hand": ("PointingHandProbe.swift", probe(
        "        Color.clear\n            .overlay(Text(\"x\").pointingHandCursor())\n            .onTapGesture {}\n"),
        "give this clickable view"),
    "a tap gesture written across lines": ("PointingHandProbe.swift", probe(
        "        Text(\"Go\")\n            .gesture(\n                SpatialTapGesture().onEnded { _ in }\n            )\n"),
        "give this clickable view"),
    "a gesture held in a variable": ("PointingHandProbe.swift", probe(
        "        Text(\"Go\").gesture(tap)\n"), "give this clickable view"),
    "a tap combined with a drag": ("PointingHandProbe.swift", probe(
        "        Text(\"Go\")\n            .gesture(DragGesture(minimumDistance: 0).simultaneously(with: TapGesture().onEnded {}))\n"),
        "give this clickable view"),
    "a plain button without the hand": ("PointingHandProbe.swift", probe(
        "        Button(\"Go\") {}\n            .buttonStyle(.plain)\n"), "give this button"),
}
for label, (name, text, expected) in broken.items():
    variant = {**files, name: text}
    found = problems(variant)
    if variant == files or not any(expected in failure for failure in found):
        failures.append(f"negative control not caught as expected: {label}")

accepted = {
    "the hand before a multi-line modifier": probe(
        "        Text(\"Go\")\n            .pointingHandCursor()\n            .background {\n                Color.red\n"
        "            }\n            .onTapGesture {}\n"),
    "the hand after a multi-line tap": probe(
        "        Text(\"Go\")\n            .onTapGesture {\n                print(\"(\")\n            }\n"
        "            .pointingHandCursor()\n"),
    "a drag gesture": probe("        Text(\"Go\")\n            .simultaneousGesture(DragGesture().onChanged { _ in })\n"),
    "a drag beside a tapped view with the hand": probe(
        "        VStack {\n            Text(\"Drag\").simultaneousGesture(DragGesture().onChanged { _ in })\n"
        "            Text(\"Go\").gesture(TapGesture().onEnded {}).pointingHandCursor()\n        }\n"),
    "a bracket inside a raw string": probe(
        "        Text(\"Go\")\n            .pointingHandCursor()\n            .help(#\"\\(\"#)\n            .onTapGesture {}\n"),
    "a bracket inside an interpolated string": probe(
        "        Text(\"Go\")\n            .pointingHandCursor()\n            .help(\"\\(open ? \"(\" : \"\")Go\")\n"
        "            .onTapGesture {}\n"),
}
for label, text in accepted.items():
    found = [failure for failure in problems({**files, "PointingHandProbe.swift": text}) if failure.startswith("PointingHandProbe")]
    if found:
        failures.append(f"positive control rejected: {label}: {found}")

if failures:
    sys.exit("Pointing hand:\n  " + "\n  ".join(failures))
print(f"PASS: every Parc button shows the pointing hand; {len(broken)} negative controls fail and "
      f"{len(accepted)} positive controls pass as they should")
