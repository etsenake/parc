import AppKit

@MainActor private final class InertWindow: NSWindow {
    var shown = true, key = true, minimized = false
    var testSheet: NSWindow?
    var testResponder: NSResponder?
    override var isVisible: Bool { shown }
    override var isKeyWindow: Bool { key }
    override var isMainWindow: Bool { true }
    override var isMiniaturized: Bool { minimized }
    override var attachedSheet: NSWindow? { testSheet }
    override var firstResponder: NSResponder? { testResponder ?? super.firstResponder }
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
    }
}
@MainActor private final class Composition: NSTextView {
    override func hasMarkedText() -> Bool { true }
}
@MainActor private final class MenuTarget: NSObject, NSMenuItemValidation {
    var available = true, calls = 0
    func validateMenuItem(_ item: NSMenuItem) -> Bool { available }
    @objc func exit(_ sender: NSMenuItem) { calls += 1 }
    @objc func custom(_ sender: NSMenuItem) {}
}
@main @MainActor struct ExitCommandTests {
    static var count = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(condition(), message)
    }
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = InertWindow(), other = InertWindow(); defer { original.close(); other.close() }
        var valid = true, calls = 0, actualResult = true
        func request(_ prepare: @escaping () -> Void = {}) -> BrowserExitCommand {
            BrowserExitCommand(window: original, targetIsAvailable: { valid }, prepare: prepare,
                               execute: { calls += 1; return actualResult })
        }
        let command = request()
        expect(command.isAvailable && command.perform() && calls == 1, "Exact original context executes once")
        expect(!command.isAvailable && !command.perform() && calls == 1, "Consumed invocation cannot replay")
        actualResult = false
        expect(!request().perform() && calls == 2, "Original target refusal propagates without window/page fallback")
        actualResult = true
        valid = false; expect(!request().perform() && calls == 2, "Stale target cannot execute"); valid = true
        original.shown = false; expect(!request().isAvailable, "Hidden window rejected"); original.shown = true
        original.minimized = true; expect(!request().perform(), "Minimized original rejected"); original.minimized = false
        original.testSheet = other; expect(!request().perform(), "Native sheet retains ownership"); original.testSheet = nil
        original.key = false
        expect(request().isAvailable && !request().perform(), "Prospective original panel row cannot act until original regains key")
        expect(request { original.key = true }.perform(), "Owned panel may restore original key window")
        expect(!request { valid = false }.perform(), "Target change during dismissal cancels"); valid = true
        expect(!request { original.key = false }.perform(), "Different key window never replaces original"); original.key = true
        original.testResponder = Composition()
        expect(!request().perform(), "Native marked text keeps its actual first-responder ownership")
        original.testResponder = nil
        var reentrant: BrowserExitCommand!, nested = true
        reentrant = request { nested = reentrant.perform() }
        expect(reentrant.perform() && !nested, "Token consumed before dismissal reentry")
        weak var retired: InertWindow?
        var expired: BrowserExitCommand!
        autoreleasepool {
            let w = InertWindow(); retired = w
            expired = BrowserExitCommand(window: w, targetIsAvailable: { true }, execute: { true }); w.close()
        }
        expect(retired == nil && !expired.perform(), "Invocation weakly owns retired physical window")

        let target = MenuTarget(), file = root.appendingPathComponent("keyboard-shortcuts.json")
        let escape = KeyboardShortcut(key: "\u{1b}", flags: [])
        let custom = KeyboardShortcut(key: "k", flags: [.command, .control])
        func register(_ registry: KeyboardShortcuts) -> NSMenuItem {
            let menu = NSMenu(), parent = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
            let child = NSMenu(title: "View"); parent.submenu = child; menu.addItem(parent); NSApp.mainMenu = menu
            let item = NSMenuItem(title: "Exit", action: #selector(MenuTarget.exit), keyEquivalent: "\u{1b}")
            item.target = target; item.keyEquivalentModifierMask = []; item.isHidden = true; item.allowsKeyEquivalentWhenHidden = true
            child.addItem(item); registry.register(item, group: "View")
            let extra = NSMenuItem(title: "Custom", action: #selector(MenuTarget.custom), keyEquivalent: "")
            extra.target = target; child.addItem(extra); registry.register(extra, group: "View")
            return item
        }
        func event(_ chord: KeyboardShortcut, repeatKey: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: chord.flags, timestamp: 1,
                windowNumber: 0, context: nil, characters: chord.key, charactersIgnoringModifiers: chord.key,
                isARepeat: repeatKey, keyCode: chord.key == "\u{1b}" ? 53 : 40)!
        }
        func encoded(_ shortcut: KeyboardShortcut?) -> [String: Any] {
            shortcut.map { ["shortcut": ["key": $0.key, "modifiers": $0.modifiers]] } ?? [:]
        }
        let registry = KeyboardShortcuts(); registry.configure(directory: root); let item = register(registry)
        expect(registry.shortcut(for: "exit:") == escape && escape.isValid, "Actual bare Escape default remains resettable/persistable")
        expect(registry.priority(for: "exit:") == .useBoth && registry.supportsPriority("exit:"), "Actual Use Both metadata retained")
        expect(item.keyEquivalent.isEmpty && !NSApp.mainMenu!.performKeyEquivalent(with: event(escape)), "Default never steals native Escape in pre-renderer AppKit menu dispatch")
        expect(registry.nativeCommand(for: event(escape), editable: false) == nil, "Default Escape remains on acknowledged native heuristic path")
        let results = registry.menuCommands(in: original).filter { $0.id == "exit:" }
        expect(results.count == 1 && results[0].shortcut == escape && results[0].title == "Exit", "Actions discovers one actual Exit with metadata keycap")
        try registry.setPriority(.preferWebsites, for: "exit:")
        expect(registry.nativeCommand(for: event(escape), editable: false) == nil, "Website-first does not install competing plain-Escape router")
        try registry.setPriority(.preferParc, for: "exit:")
        let preferred = registry.nativeCommand(for: event(escape), editable: false)
        expect(preferred?.item === item && preferred?.priority == .preferParc, "Explicit browser-first Exit is original native pre-renderer command")
        expect(registry.nativeCommand(for: event(escape), editable: true)?.item === item, "Explicit browser-first Exit applies in editable page content too")
        expect(preferred.map(registry.isExitCommand) == true, "Exit binding identifies the reducer's special-cased action")
        expect(registry.nativeCommand(for: event(escape, repeatKey: true), editable: false) == nil, "Repeat cannot issue explicit command")
        target.available = false
        expect(registry.nativeCommand(for: event(escape), editable: false) == nil, "Unavailable Exit is not a replacement context")
        target.available = true
        try registry.set(custom, for: "exit:"); try registry.setPriority(.useBoth, for: "exit:")
        expect(item.keyEquivalent == "k" && item.keyEquivalentModifierMask == custom.flags, "Custom chord is actual native menu equivalent")
        let actual = registry.nativeCommand(for: event(custom), editable: false)
        expect(actual?.item === item && actual?.priority == .useBoth, "Custom chord uses existing ACK/Press Again machinery")
        expect(registry.nativeCommand(for: event(escape), editable: false) == nil, "Custom command leaves physical Escape independent")
        expect(actual.map { registry.perform($0, event: event(custom), editable: false) } == true && target.calls == 1, "Original native command dispatch reaches actual sender/target")
        try registry.set(nil, for: "exit:")
        expect(item.keyEquivalent.isEmpty && registry.nativeCommand(for: event(custom), editable: false) == nil, "Disabled configurable command has no custom transport")
        expect(actual.map { registry.perform($0, event: event(custom), editable: false) } == false, "Saved revision change invalidates pending command")
        try registry.reset("exit:")
        expect(registry.shortcut(for: "exit:") == escape && registry.priority(for: "exit:") == .useBoth, "Reset restores original default/priority without preemption")
        for version in 1...3 {
            try JSONSerialization.data(withJSONObject: ["version": version,
                "overrides": ["custom:": encoded(escape)], "priorities": ["custom:": "preferParc"]]).write(to: file)
            let legacy = KeyboardShortcuts(); legacy.configure(directory: root); _ = register(legacy)
            expect(legacy.loadError == nil && legacy.shortcut(for: "custom:") == escape, "Persisted valid physical key retains owner")
            expect(legacy.shortcut(for: "exit:") == nil, "New default does not steal explicit saved owner")
            let saved = try Data(contentsOf: file)
            let value = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
            expect(value["exitShortcutDefaults"] as? Int == 1, "Additive marker is durable")
            legacy.configure(directory: root); let repeated = try Data(contentsOf: file)
            expect(saved == repeated, "Migration byte-idempotent")
            try legacy.reset("exit:")
            expect(legacy.isConflicting("exit:") && legacy.activeShortcut(for: "exit:") == nil, "Explicit Reset shows conflict without enabling ambiguous Escape dispatch")
            try legacy.set(nil, for: "custom:"); try legacy.reset("exit:")
            expect(legacy.shortcut(for: "exit:") == escape, "Explicit reset after conflict restores default")
        }
        for chord in [custom, nil] as [KeyboardShortcut?] {
            try JSONSerialization.data(withJSONObject: ["version": 3, "overrides": ["exit:": encoded(chord)],
                "priorities": ["exit:": "preferWebsites"]]).write(to: file)
            let saved = KeyboardShortcuts(); saved.configure(directory: root); _ = register(saved)
            expect(saved.shortcut(for: "exit:") == chord && saved.priority(for: "exit:") == .preferWebsites, "Explicit custom/disabled and saved priority remain authoritative")
            try saved.resetAll()
            expect(saved.shortcut(for: "exit:") == escape && saved.priority(for: "exit:") == .useBoth, "Reset All deliberately adopts defaults")
        }
        let bad = Data("broken".utf8); try bad.write(to: file)
        let failed = KeyboardShortcuts(); failed.configure(directory: root); let remaining = try Data(contentsOf: file)
        expect(failed.loadError != nil && remaining == bad, "Unreadable file never overwritten")
        print("PASS: \(count) Exit invocation/menu/priority/migration assertions")
    }
}
