#!/usr/bin/env python3
from pathlib import Path
import re
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source
root = Path(__file__).resolve().parents[2]
controller = browser_window_controller_source(root / "Sources/ParcApp")
delegate = (root / "Sources/ParcApp/AppDelegate.swift").read_text()
checks = 0


def body(source, signature):
    start = source.index(signature)
    depth, i = 0, source.index("{", start)
    for j in range(i, len(source)):
        depth += {"{": 1, "}": -1}.get(source[j], 0)
        if depth == 0:
            return source[start:j + 1]
    raise AssertionError(f"unterminated {signature}")


def expect(condition, message):
    global checks
    assert condition, message
    checks += 1


commands = {"widenSplitPane": ".widen", "narrowSplitPane": ".narrow", "equalizeSplitPanes": ".equalize"}
mapping = body(delegate, "private func splitCommand(for action: Selector?)")
for selector, case in commands.items():
    expect(f"case #selector({selector}): return {case}" in mapping, f"{selector} maps to its split command")
    expect(f"@objc private func {selector}(_ sender: Any?) {{ performSplitMenuCommand(sender) }}" in delegate,
           f"{selector} performs the validated split target")
menu = re.search(r"for \(title, selector\) in \[\(\"Widen Current Split\", #selector\(widenSplitPane\)\),\s*"
                 r"\(\"Narrow Current Split\", #selector\(narrowSplitPane\)\),\s*"
                 r"\(\"Make All Split Panes Equal\", #selector\(equalizeSplitPanes\)\)\] \{\s*"
                 r"item\(title, selector, in: view\)\s*hideKeepingShortcut\(view\)\s*\}", delegate)
expect(menu is not None, "the three commands are hidden View items with no default shortcut, like Collapse All Folders")
expect(delegate.index("splitCommandsMenu = view") < menu.start(), "they live in the validated split commands menu")

available = body(controller, "func splitCommandIsAvailable(_ command: SplitCommand) -> Bool")
expect("guard splitCommandsAvailable else { return false }" in available
       and "case .widen, .narrow, .equalize: return splitResizeIsAvailable(command)" in available,
       "the commands pass the shared split command gate, then their own rule")
rule = body(controller, "func splitResizeIsAvailable(_ command: SplitCommand) -> Bool")
expect("guard selectedTabIDs.count > 1, splitInsertion == nil, renderedPaneIDs == selectedTabIDs,\n              window?.isKeyWindow == true else { return false }" in rule,
       "they are unavailable outside a shown multi-pane split and while an Add pane is pending")
expect("case .widen: return focused.map { splitView.canResizePane($0, growing: true) } ?? false" in rule
       and "case .narrow: return focused.map { splitView.canResizePane($0, growing: false) } ?? false" in rule
       and "default: return splitView.canEqualizePanes" in rule,
       "they are disabled whenever the focused step or Make Equal would change nothing")
expect("(selectedTabIDs.count == 1 || activeSplitLayout != nil)" in body(controller, "var splitCommandsAvailable: Bool"),
       "several displayed panes must belong to a real split")
execute = body(controller, "func executeSplitCommand(_ command: SplitCommand, targetID: UUID)")
expect("case .widen:\n            if let pane = panes[targetID] { splitView.resizePane(pane, growing: true) }" in execute
       and "case .narrow:\n            if let pane = panes[targetID] { splitView.resizePane(pane, growing: false) }" in execute
       and "case .equalize:\n            splitView.equalizePanes()" in execute,
       "the commands resize the target window's own split view")
expect("splitView.prepareDividerResize = { [weak self] in self?.prepareSplitResize() }" in controller,
       "the split view's adjustments commit through the window's resize receipt")
expect("splitView.prepareStackedResize = { [weak self] in self?.prepareStackedSplitResize() }" in controller,
       "stacked adjustments commit through the window's stacked resize receipt")
receipt = body(controller, "private func splitResizeReceipt(stacked: Bool)")
expect("window.isKeyWindow" in receipt and "(layout.stacks != nil) == stacked" in receipt
       and "self.performWindowCommand(selectNativePage: false)" in receipt,
       "both receipts keep the per-window rules and only serve their own kind of split")
resize = body(controller, "func prepareSplitResize() -> (([Double]) -> Bool)?")
expect("splitResizeReceipt(stacked: false)" in resize
       and "store.resizeSplit(expected: layout, widthFactors: factors)" in resize,
       "a flat split saves its flat row through the store")
stacked = body(controller, "func prepareStackedSplitResize() -> ((SplitStackResize) -> BrowserSplitStacks?)?")
expect("splitResizeReceipt(stacked: true)" in stacked and "layout.resized(by: change)" in stacked
       and "store.resizeSplit(expected: layout, resized: resized)" in stacked,
       "a stacked split saves the pure stacked edit through the store")
presentation = (root / "Sources/ParcCore/CommandBarCommandPresentation.swift").read_text()
triggers = (root / "Sources/ParcCore/CommandBarMenuItemInfo.swift").read_text()
settings = (root / "Sources/ParcApp/ShortcutsSettingsView.swift").read_text()
for selector in commands:
    expect(f'"{selector}": "' in presentation, f"{selector} has a command bar symbol")
    expect(f'"{selector}:": .init(triggers: [' in triggers, f"{selector} has command bar search words")
    expect(f'"{selector}:": "' in settings, f"{selector} explains itself in Settings → Shortcuts")
print(f"PASS: {checks} split resize command wiring checks")
