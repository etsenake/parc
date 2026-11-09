#!/usr/bin/env python3
"""ContentFocusRequest: focus following an explicit content selection.

Off-screen windows that report key without being shown; no browser, input,
preferences or Parc binary. Runs the main run loop briefly for the idle retry.
"""
from pathlib import Path
import re
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
controller = (root / "Sources/ParcApp/BrowserWindowController.swift").read_text()
# BrowserWindowController is not compiled here: its wiring is asserted in source.
for use, count in (("let request = ContentFocusRequest(window: window, content: pageHost)", 1),
                   ("focusedTabID = id; updateNavigation(); requestNativeSelection(); focusSelectedContent(); return true", 1),
                   ("updateNavigation(); requestNativeSelection(); focusSelectedContent()\n", 1),
                   ("        requestNativeSelection()\n        focusSelectedContent()\n        if previousProfile", 1),
                   ("            requestNativeSelection()\n            focusSelectedContent()\n        case .move", 1),
                   ("        guard restoreFocus else { return }\n        requestNativeSelection()\n", 1),
                   ("if let editor = findField.currentEditor(), window?.firstResponder === editor { return }\n            if window?.makeFirstResponder(findField) == true { return }\n        }\n        focusSelectedContent()\n", 1),
                   ("reclaimFocusAfterSplitPresentation()", 4),
                   ("guard let window, ContentFocusRequest.lostByPresentation(window.firstResponder, window: window) else { return }\n        focusSelectedContent()", 1),
                   ("self.window?.makeFirstResponder(self.findField) == true { return }", 1)):
    assert controller.count(use) == count, f"content focus wiring changed: {use}"
assert controller.count("ContentFocusRequest.returnsToSaved(view, find: find,") == 1, "command-bar close target wiring changed"
# A blank tab gives focus to the window: the request ends, the local fallback
# and the command-bar close do the same, and every pane surface keeps the flag.
assert controller.count("if self.panes[id]?.showsBlank == true { window.makeFirstResponder(nil); return .focused }") == 1
assert controller.count("else if panes[id]?.showsBlank == true { window.makeFirstResponder(nil) }") == 1
assert controller.count("else if self.panes[id]?.showsBlank == true { self.window?.makeFirstResponder(nil) }") == 1
pane = controller[controller.index("private final class BrowserPane: NSView {"):]
pane = pane[:pane.index("\n}\n")]
def switches(text):
    return len(re.findall(r"(?<!var )\bsurface = ", text))


surfaces = {re.match(r"\s*(?:\w+\s+)*func (\w+)", member).group(1): member
            for member in re.split(r"\n(?=    (?:(?:private|fileprivate|override)\s+)*func )", pane)[1:] if switches(member)}
assert {"showBlank", "showBrowser", "showError"} <= surfaces.keys(), f"the pane's surfaces moved: {sorted(surfaces)}"
assert sum(map(switches, surfaces.values())) == switches(pane), "BrowserPane switches surface outside its show functions"
for name, member in surfaces.items():
    assert member.count("showsBlank = ") == switches(member), f"BrowserPane.{name} switches surface without setting showsBlank"
    assert ("showsBlank = true" in member) == (name == "showBlank"), f"BrowserPane.{name} sets showsBlank wrongly"
assert controller.count("showsBlank = true") == 1, "showsBlank is set outside the blank surface"
attempt = controller.index("if self.panes[id]?.showsBlank == true { window.makeFirstResponder(nil); return .focused }")
assert attempt < controller.index("self.focusSelectedLocalContent()\n            return paneHoldsFocus() ? .focused : .waiting"), \
    "a blank tab no longer ends the request before the waiting fallback"
command = (root / "Sources/ParcApp/CommandBar.swift").read_text()
assert "mayRestoreOriginal?(view) ?? true,\n               SavedFocus.mayReturn(to: view, in: parent)" in command, "command-bar close order changed"
peek = (root / "Sources/ParcApp/PeekController.swift").read_text()
assert "window.selectKeyView(following: entry)" in peek and "window.selectKeyView(preceding: exit)" in peek
with tempfile.TemporaryDirectory(prefix="parc-content-focus-") as directory:
    executable = Path(directory) / "checks"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcApp/ContentFocusRequest.swift"), str(root / "Sources/ParcApp/SavedFocus.swift"),
                    str(Path(__file__).with_name("ContentFocusRequestTests.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
