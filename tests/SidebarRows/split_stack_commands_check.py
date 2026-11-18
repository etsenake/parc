#!/usr/bin/env python3
from pathlib import Path
import re
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source
root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
controller = browser_window_controller_source(app)
delegate = (app / "AppDelegate.swift").read_text()
menu_source = (app / "SplitPaneMenu.swift").read_text()
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


mapping = body(delegate, "private func splitCommand(for action: Selector?)")
expect("case #selector(splitThisPane): return .add(.stackAfter)" in mapping,
       "Split This Pane adds below or to the right of the focused pane through the validated Add command")
expect("@objc private func splitThisPane(_ sender: Any?) { performSplitMenuCommand(sender) }" in delegate,
       "the View item performs its prepared split target")
item = 'item("Split This Pane", #selector(splitThisPane), "\\\\", in: view, modifiers: [.control, .shift])'
expect(item in delegate, "Split This Pane is a visible View item defaulting to Control-Shift-Backslash")
expect(delegate.index("splitCommandsMenu = view") < delegate.index(item)
       < delegate.index('item("Close this Split Pane"'), "it sits with the split commands in the validated View menu")
chords = re.findall(r'"\\\\"[^)\n]*modifiers: \[(?:\.control, \.shift|\.shift, \.control)\]', delegate)
expect(len(chords) == 1, "no other Parc menu command claims Control-Shift-Backslash")

available = body(controller, "func splitCommandIsAvailable(_ command: SplitCommand) -> Bool")
expect(available.index("guard splitCommandsAvailable else { return false }") < available.index("case .add(let operation):"),
       "Split This Pane passes the shared gate that refuses Peek, Library and other split blockers")
expect("guard selectedTabIDs.count < 4, splitInsertion == nil else { return false }" in available
       and "guard stacking || activeSplitLayout?.stacks != nil, let focus = currentTabID else { return !stacking }" in available
       and "return SplitPaneInsertion(paneID: focus, operation: operation, state: presentedState) != nil" in available,
       "stacked adds are unavailable at four panes and while an Add is pending, and need a split to stack in")
gate = body(controller, "var splitCommandsAvailable: Bool")
expect("spaceCommandsAvailable && activePeek == nil && libraryView == nil" in gate, "the shared gate still refuses Peek and Library")
perform = body(body(controller, "@MainActor final class SplitCommandTarget"), "func perform()")
expect(perform.count("PCNativeBrowserApplication.canPresentTabSwitcher(in: window)") == 2,
       "execution still revalidates fullscreen, sheets, transfers and the switcher after dismissing surfaces")

target = body(controller, "func splitCommandTarget(_ command: SplitCommand, paneID: UUID? = nil) -> SplitCommandTarget?")
expect("guard layout.movingSlot(of: target, by: delta) != nil else { return nil }" in target
       and "guard selectedTabIDs.indices.contains(position + delta) else { return nil }" in target,
       "main-row Move needs a slot neighbour in a stacked split and keeps today's rule in a flat one")
expect("if case .moveInStack(let delta) = command, activeSplitLayout?.movingWithinStack(target, by: delta) == nil { return nil }" in target,
       "a stack move needs a neighbour in its stack")
execute = body(controller, "func executeSplitCommand(_ command: SplitCommand, targetID: UUID)")
expect("case .moveInStack(let offset):" in execute
       and "store.moveSplitPaneWithinStack(targetID, offset: offset, expected: layout)" in execute,
       "a stack move commits through the store's stack move")
expect("case .add(let operation): beginSplitInsertion(operation, paneID: targetID)" in execute,
       "stacked adds open the pending pane with the command bar like today's Add")
resolve = body(controller, "func resolvedSplitCommand(_ command: SplitCommand) -> SplitCommand")
expect("guard case .add(let operation) = command," in resolve
       and "operation.startsSplitView(paneCount: selectedTabIDs.count, isSplit: activeSplitLayout != nil) else { return command }" in resolve
       and "return .addNew" in resolve, "on a single unsplit page Split This Pane becomes Add Split View's command")
expect("switch resolvedSplitCommand(command) {" in available,
       "availability judges Split This Pane by the command it will run, behind the same shared gate")
expect(target.index("let command = resolvedSplitCommand(command)") < target.index("guard splitCommandIsAvailable(command)"),
       "the prepared target holds Add Split View's command, so it revalidates and runs exactly like Add Split View")
expect("case .addNew: toggleSplit()" in execute, "Add Split View's command opens its pending pane and command bar")
toggle = body(controller, "func toggleSplit()")
expect("guard let last = selectedTabIDs.last else { return }" in toggle
       and "beginSplitInsertion(activeSplitLayout?.orientation == .vertical ? .addBelow : .addAfter, paneID: last)" in toggle,
       "Add Split View on a single page opens its pending pane to the right of the page")
menu = body(controller, "func showSplitPaneMenu(_ paneID: UUID, from anchor: NSView)")
expect("case .stackPrevious: command = .moveInStack(-1)" in menu and "case .stackNext: command = .moveInStack(1)" in menu
       and "case .addBefore, .addAfter, .addAbove, .addBelow, .stackBefore, .stackAfter: command = .add(operation)" in menu
       and "layout: layout)" in menu, "the pane menu routes its stack rows through the window's split commands")
for title, artwork in [("Add Above This Pane", "icon-split-stack-add-top"), ("Add Below This Pane", "icon-split-stack-add-bottom"),
                       ("Add Left of This Pane", "icon-split-stack-add-left"), ("Add Right of This Pane", "icon-split-stack-add-right")]:
    expect(f'("{title}", "{artwork}", ' in menu_source, f"{title} is a pane menu row with its artwork")
    for variant in ["", "@2x", "-dark", "-dark@2x"]:
        expect((root / f"Resources/SplitPaneMenu/{artwork}{variant}.png").is_file(), f"{artwork}{variant}.png exists")

presentation = (root / "Sources/ParcCore/CommandBarCommandPresentation.swift").read_text()
triggers = (root / "Sources/ParcCore/CommandBarMenuItemInfo.swift").read_text()
settings = (app / "ShortcutsSettingsView.swift").read_text()
shortcuts = (app / "KeyboardShortcuts.swift").read_text()
expect('"splitThisPane": "' in presentation, "Split This Pane has a command bar symbol")
expect('"splitThisPane:": .init(triggers: [' in triggers, "Split This Pane has command bar search words")
expect('"splitThisPane:": "' in settings, "Split This Pane explains itself in Settings → Shortcuts")
priority = body(shortcuts, "private func defaultPriority(for id: String) -> Priority")
expect('"splitThisPane:"].contains(id) { return .useBoth }' in priority, "Split This Pane uses Add Split View's Use Both priority")
expect(shortcuts.count('key: "\\\\"') == 1
       and 'splitThisPaneShortcut = KeyboardShortcut(key: "\\\\", flags: [.control, .shift])' in shortcuts
       and 'case "splitThisPane:": windowShortcut = Self.splitThisPaneShortcut' in shortcuts,
       "the shortcut registry's only Backslash default is Split This Pane's")
migration = body(shortcuts, "if document.splitThisPaneShortcutDefaults == nil")
expect('document.overrides["splitThisPane:"] == nil' in migration
       and '$0.key != "splitThisPane:" && $0.value.shortcut == Self.splitThisPaneShortcut' in migration
       and 'document.overrides["splitThisPane:"] = Override(shortcut: nil)' in migration,
       "the new default never steals a chord someone already saved on another command")
print(f"PASS: {checks} split stack command wiring checks")
