import AppKit

@MainActor private final class FindWindow: NSWindow {
    var shown = true, key = true, minimized = false
    var testSheet: NSWindow?
    override var isVisible: Bool { shown }
    override var isKeyWindow: Bool { key }
    override var isMiniaturized: Bool { minimized }
    override var attachedSheet: NSWindow? { testSheet }
    init() {
        super.init(contentRect: .init(x: 0, y: 0, width: 300, height: 200),
                   styleMask: [.titled], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
    }
}
@MainActor private final class FindText: NSTextView {
    var composing = false
    override func hasMarkedText() -> Bool { composing }
}
@MainActor private final class FindTarget: NSObject, NSMenuItemValidation {
    var available = true
    func validateMenuItem(_ item: NSMenuItem) -> Bool { available }
    @objc func find(_ sender: NSMenuItem) {}
    @objc func findNext(_ sender: NSMenuItem) {}
    @objc func findPrevious(_ sender: NSMenuItem) {}
    @objc func useSelectionForFind(_ sender: NSMenuItem) {}
    @objc func custom(_ sender: NSMenuItem) {}
}
@main @MainActor struct FindCommandTests {
    static var count = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
        count += 1; precondition(condition(), label)
    }
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let window = FindWindow(), other = FindWindow(), text = FindText(frame: .init(x: 0, y: 0, width: 200, height: 100))
        window.contentView?.addSubview(text); window.makeFirstResponder(text)
        var available = true, dispatched = 0
        func request(_ prepare: @escaping () -> Void = {}) -> BrowserFindCommand {
            BrowserFindCommand(action: .next, window: window, available: { available }, prepare: prepare) { dispatched += 1 }
        }
        let original = request()
        expect(original.isAvailable && original.perform(), "Exact original owner executes")
        expect(!original.perform() && dispatched == 1, "One menu lease cannot replay")
        text.composing = true; expect(!request().perform(), "Native marked text retains input"); text.composing = false
        window.shown = false; expect(!request().isAvailable, "Hidden owner rejected"); window.shown = true
        window.minimized = true; expect(!request().isAvailable, "Minimized owner rejected"); window.minimized = false
        window.testSheet = other; expect(!request().perform(), "Sheet ownership preserved"); window.testSheet = nil
        window.key = false; expect(!request().perform(), "No action behind another key window"); window.key = true
        expect(!request({ available = false }).perform(), "Panel dismissal revalidates original document")
        available = true
        expect(!request({ window.key = false }).perform(), "Focus loss cancels before dispatch"); window.key = true
        expect(dispatched == 1, "No replacement dispatch")
        var object: NSObject? = NSObject(), state: BrowserFindState<NSObject>!
        state = BrowserFindState(owner: object!, revision: 4); state.query = "original query"
        expect(state.matches(object, revision: 4), "Original document query matches")
        expect(!state.matches(NSObject(), revision: 4), "Same revision on different page rejected")
        expect(!state.matches(object, revision: 5), "New document revision rejected")
        object = nil; expect(state.owner == nil && !state.matches(nil, revision: 4), "Query never retains retired page")
        for (name, shift, expected) in [("insertNewline:", false, BrowserFindAction.next),
            ("insertNewline:", true, .previous), ("moveUp:", false, .previous), ("moveDown:", true, .next)] {
            expect(BrowserFindAction.fieldAction(NSSelectorFromString(name), shift: shift, composing: false) == expected, "Recovered field direction")
            expect(BrowserFindAction.fieldAction(NSSelectorFromString(name), shift: shift, composing: true) == nil, "Marked-text command not intercepted")
        }
        expect(BrowserFindAction.fieldAction(NSSelectorFromString("moveLeft:"), shift: false, composing: false) == nil, "Native caret motion preserved")
        expect(BrowserFindAction.allCases.map(\.rawValue) == [0, 1, 2, 3, 7, 12], "the six Find item tags")
        expect(BrowserFindAction.allCases.filter(\.isNativeTextOnly) == [.jumpToSelection, .replace],
               "Browser rejects only Jump to Selection and Find and Replace")
        expect(BrowserFindAction.replace.title == "Find and Replace" && BrowserFindAction.jumpToSelection.title == "Jump to Selection",
               "Shipped Find item titles")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = FindTarget(), file = root.appendingPathComponent("keyboard-shortcuts.json")
        let defaults = KeyboardShortcuts.recoveredFindShortcuts
        func register(_ registry: KeyboardShortcuts) -> [String: NSMenuItem] {
            let main = NSMenu(), edit = NSMenu(title: "Edit"), find = NSMenu(title: "Find")
            let editRow = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""), findRow = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
            editRow.submenu = edit; main.addItem(editRow); findRow.submenu = find; edit.addItem(findRow); NSApp.mainMenu = main
            var rows: [String: NSMenuItem] = [:]
            for (id, title) in [("find:", "Find…"), ("findNext:", "Find Next"), ("findPrevious:", "Find Previous"), ("useSelectionForFind:", "Use Selection to Find"), ("custom:", "Custom")] {
                let chord = id == "find:" ? KeyboardShortcut(key: "f", flags: .command) : defaults[id]
                let item = NSMenuItem(title: title, action: NSSelectorFromString(id), keyEquivalent: chord?.key ?? "")
                item.keyEquivalentModifierMask = chord?.flags ?? .command; item.target = target; find.addItem(item)
                registry.register(item, group: "Find"); rows[id] = item
            }
            return rows
        }
        let registry = KeyboardShortcuts(); registry.configure(directory: root); let rows = register(registry)
        for (id, chord) in defaults {
            expect(registry.shortcut(for: id) == chord && rows[id]?.keyEquivalent == chord.key, "Real menu default chord")
            expect(registry.priority(for: id) == .preferWebsites, "No invented override priority")
        }
        expect(registry.shortcut(for: "useSelectionForFind:") == nil, "Original unbound selection action")
        expect(registry.commands.filter { $0.group == "Find" }.count == 5, "Commands present in shortcut editor")
        expect(registry.menuCommands(in: window).contains { $0.id == "findNext:" && $0.shortcut == defaults["findNext:"] }, "Actions search uses actual menu/keycap")
        func event(_ shift: Bool, repeat repeating: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.command, .shift] : .command,
                timestamp: 1, windowNumber: 0, context: nil, characters: shift ? "G" : "g", charactersIgnoringModifiers: shift ? "G" : "g", isARepeat: repeating, keyCode: 5)!
        }
        expect(registry.nativeCommand(for: event(false), editable: false)?.item === rows["findNext:"], "Native priority query reaches exact Next item")
        expect(registry.nativeCommand(for: event(true), editable: false)?.item === rows["findPrevious:"], "Shift query reaches exact Previous item")
        target.available = false; expect(registry.nativeCommand(for: event(false), editable: false) == nil, "Unavailable owner never falls through")
        target.available = true
        func encoded(_ chord: KeyboardShortcut?) -> [String: Any] {
            chord.map { ["shortcut": ["key": $0.key, "modifiers": $0.modifiers]] } ?? [:]
        }
        for version in 1...3 {
            for (id, chord) in defaults {
                try JSONSerialization.data(withJSONObject: ["version": version, "overrides": ["custom:": encoded(chord)], "priorities": ["custom:": "useBoth"]]).write(to: file)
                let old = KeyboardShortcuts(); old.configure(directory: root); let oldRows = register(old)
                expect(old.shortcut(for: "custom:") == chord && old.shortcut(for: id) == nil && oldRows[id]?.keyEquivalent == "", "New default never steals custom binding")
                expect(old.priority(for: "custom:") == .useBoth, "Custom priority retained")
                let saved = try Data(contentsOf: file); old.configure(directory: root)
                let reloaded = try Data(contentsOf: file)
                expect(reloaded == saved, "Migration is idempotent")
                try old.reset(id)
                expect(old.isConflicting(id) && old.activeShortcut(for: id) == nil, "Explicit Reset saves a visible conflict and prevents ambiguous dispatch")
                try old.set(nil, for: "custom:"); try old.reset(id)
                expect(old.shortcut(for: id) == chord, "Explicit reset restores unoccupied default")
                try old.setPriority(.preferParc, for: id); try old.set(nil, for: id); old.configure(directory: root)
                expect(old.shortcut(for: id) == nil && old.priority(for: id) == .preferParc, "Disabled binding and explicit priority survive reload")
            }
        }
        // KB04: numbered targets and the native-text Find items never take a saved chord.
        for (id, chord) in KeyboardShortcuts.numberedTargetShortcuts {
            try JSONSerialization.data(withJSONObject: ["version": 3, "findShortcutDefaults": 1,
                "overrides": ["custom:": encoded(chord)]]).write(to: file)
            let old = KeyboardShortcuts(); old.configure(directory: root)
            expect(old.loadError == nil && old.shortcut(for: "custom:") == chord && old.shortcut(for: id) == nil,
                   "Numbered target default never steals a saved chord")
            let others = KeyboardShortcuts.numberedTargetShortcuts.keys.filter { $0 != id }
            let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            let overrides = saved["overrides"] as? [String: Any] ?? [:]
            expect(saved["numberedTargetShortcutDefaults"] as? Int == 1 && others.allSatisfy { overrides[$0] == nil },
                   "Durable marker; unoccupied numbered defaults stay untouched")
        }
        expect(KeyboardShortcuts.numberedTargetShortcuts["item1"] == .init(key: "1", flags: [.command])
               && KeyboardShortcuts.numberedTargetShortcuts["space9"] == .init(key: "9", flags: [.control])
               && KeyboardShortcuts.numberedTargetShortcuts["findAndReplace:"] == .init(key: "f", flags: [.command, .option])
               && KeyboardShortcuts.numberedTargetShortcuts["jumpToSelection:"] == .init(key: "j", flags: [.command]),
               "Recovered numbered and Find defaults")
        // Dynamic Space metadata follows its menu owner without losing saved choices.
        let dynamicDirectory = root.appendingPathComponent("dynamic")
        try FileManager.default.createDirectory(at: dynamicDirectory, withIntermediateDirectories: true)
        let dynamic = KeyboardShortcuts(); dynamic.configure(directory: dynamicDirectory)
        let space = NSMenuItem(title: "Work", action: NSSelectorFromString("selectSpace:"), keyEquivalent: "1")
        space.keyEquivalentModifierMask = .control
        dynamic.register(space, group: "Spaces", bindingID: "space1", title: "Work")
        try dynamic.set(nil, for: "space1")
        dynamic.register(space, group: "Spaces", bindingID: "space1", title: "Personal")
        expect(dynamic.commands.first { $0.id == "space1" }?.title == "Personal" && dynamic.shortcut(for: "space1") == nil,
               "Renaming a numbered Space preserves its disabled binding")
        let tenth = NSMenuItem(title: "Tenth Space", action: NSSelectorFromString("selectSpace:"), keyEquivalent: "")
        dynamic.register(tenth, group: "Spaces", bindingID: "space10", title: tenth.title)
        expect(dynamic.commands.contains { $0.id == "space10" } && dynamic.shortcut(for: "space10") == nil,
               "Spaces beyond nine remain discoverable without an invented default")
        try dynamic.set(.init(key: "0", flags: [.control]), for: "space10")
        expect(dynamic.shortcut(for: "space10") == .init(key: "0", flags: [.control]),
               "A later numbered Space accepts a real custom binding")
        dynamic.retireCommands(["space1"])
        expect(!dynamic.commands.contains { $0.id == "space1" }, "Removed numbered Space leaves discovery")
        dynamic.register(space, group: "Spaces", bindingID: "space1", title: "Restored")
        expect(dynamic.shortcut(for: "space1") == nil, "Reappearing numbered Space retains the saved user choice")
        print("PASS: \(count) Find command, owner, composition and migration assertions")
    }
}
