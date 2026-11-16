import AppKit

@MainActor private final class ProbeWindow: NSWindow {
    var shown = true, key = true, minimized = false
    var testSheet: NSWindow?
    override var isVisible: Bool { shown }
    override var isKeyWindow: Bool { key }
    override var isMiniaturized: Bool { minimized }
    override var attachedSheet: NSWindow? { testSheet }
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
    }
}
@MainActor private final class MarkedText: NSTextView {
    var composing = true
    override func hasMarkedText() -> Bool { composing }
}
@MainActor private final class ClearTarget: NSObject, NSMenuItemValidation {
    var available = true
    var requests = 0
    func validateMenuItem(_ item: NSMenuItem) -> Bool { available }
    @objc func clearToday(_ sender: NSMenuItem) { requests += 1 }
    @objc func custom(_ sender: NSMenuItem) {}
}
@main @MainActor struct ClearTodayCommandTests {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let window = ProbeWindow(), other = ProbeWindow()
        var owner = true, requests = 0
        func request(_ prepare: @escaping () -> Void = {}) -> BrowserClearTodayCommand {
            BrowserClearTodayCommand(window: window, ownerIsAvailable: { owner },
                prepare: prepare, clear: { requests += 1 })
        }
        let first = request()
        expect(first.isAvailable && first.perform() && requests == 1, "Original context receives one request")
        expect(!first.isAvailable && !first.perform() && requests == 1, "Original menu receipt cannot replay")
        var reentrant: BrowserClearTodayCommand!
        reentrant = request { expect(!reentrant.perform(), "Dismissal cannot reenter the consumed receipt") }
        expect(reentrant.perform() && requests == 2, "Reentry leaves one original request")
        window.shown = false; expect(!request().perform(), "Hidden owner refused"); window.shown = true
        window.minimized = true; expect(!request().perform(), "Minimized owner refused"); window.minimized = false
        window.testSheet = other; expect(!request().perform(), "Original sheet owns input"); window.testSheet = nil
        owner = false; expect(!request().perform(), "Changed Space/Profile/native owner refused"); owner = true
        window.key = false
        expect(request().isAvailable && !request().perform(), "Prospective panel command cannot mutate behind other key window")
        expect(request { window.key = true }.perform(), "Owned panel dismissal can restore original key window")
        expect(!request { owner = false }.perform(), "Owner is rechecked after synchronous dismissal")
        owner = true
        expect(!request { window.key = false }.perform(), "Focus loss during preparation cancels")
        window.key = true
        expect(!request { window.testSheet = other }.perform(), "A new original sheet cancels execution")
        window.testSheet = nil
        let text = MarkedText(frame: window.contentView!.bounds)
        window.contentView!.addSubview(text); _ = window.makeFirstResponder(text)
        expect(window.firstResponder === text, "Actual native editor is first responder")
        expect(!request().isAvailable && !request().perform(), "Native marked text retains ownership")
        text.composing = false
        expect(request().perform(), "Native editor after composition admits modified application command")
        _ = window.makeFirstResponder(nil); text.removeFromSuperview()
        expect(requests == 4, "Refused contexts never dispatch a retirement request")
        weak var retired: ProbeWindow?
        var expired: BrowserClearTodayCommand!
        autoreleasepool {
            let temporary = ProbeWindow(); retired = temporary
            expired = BrowserClearTodayCommand(window: temporary, ownerIsAvailable: { true }, clear: { requests += 100 })
            temporary.close()
        }
        expect(retired == nil && !expired.isAvailable && !expired.perform(), "Receipt does not retain a retired physical window")

        let target = ClearTarget(), file = root.appendingPathComponent("keyboard-shortcuts.json")
        let chord = KeyboardShortcut(key: "k", flags: [.command, .shift])
        func register(_ registry: KeyboardShortcuts) -> NSMenuItem {
            let main = NSMenu(), parent = NSMenuItem(title: "Tabs", action: nil, keyEquivalent: "")
            let menu = NSMenu(title: "Tabs"); parent.submenu = menu; main.addItem(parent); NSApp.mainMenu = main
            let item = NSMenuItem(title: "Clear Today", action: #selector(ClearTarget.clearToday), keyEquivalent: "k")
            item.keyEquivalentModifierMask = [.command, .shift]; item.target = target; menu.addItem(item)
            registry.register(item, group: "Tabs")
            let custom = NSMenuItem(title: "Custom", action: #selector(ClearTarget.custom), keyEquivalent: "")
            custom.target = target; menu.addItem(custom); registry.register(custom, group: "Tabs")
            return item
        }
        func event(_ repeating: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 1,
                windowNumber: 0, context: nil, characters: "K", charactersIgnoringModifiers: "K", isARepeat: repeating, keyCode: 40)!
        }
        let registry = KeyboardShortcuts(); registry.configure(directory: root); let item = register(registry)
        expect(registry.shortcut(for: "clearToday:") == chord, "Recovered physical Command-Shift-K default")
        expect(item.keyEquivalent == "k" && item.keyEquivalentModifierMask == chord.flags, "Visible actual menu chord")
        expect(registry.priority(for: "clearToday:") == .preferWebsites, "Absent original priority override retains existing fallback")
        let native = registry.nativeCommand(for: event(), editable: false)
        expect(native?.item === item && native?.priority == .preferWebsites, "Existing native command priority route")
        expect(registry.nativeCommand(for: event(), editable: true)?.item === item, "Modified application command is not native text alias")
        expect(registry.nativeCommand(for: event(true), editable: false) == nil, "Held repeat does not issue duplicate retirement")
        target.available = false
        expect(registry.nativeCommand(for: event(), editable: false) == nil, "Unavailable original action cannot dispatch")
        target.available = true
        let actions = registry.menuCommands(in: other).filter { $0.id == "clearToday:" }
        expect(actions.count == 1 && actions[0].title == "Clear Today" && actions[0].shortcut == chord,
               "One command-search row uses live registered binding")
        expect(registry.commands.contains { $0.id == "clearToday:" && $0.group == "Tabs" }, "Existing Settings has real registered command")
        func encoded(_ chord: KeyboardShortcut?) -> [String: Any] {
            chord.map { ["shortcut": ["key": $0.key, "modifiers": $0.modifiers]] } ?? [:]
        }
        for version in 1...3 {
            let document: [String: Any] = ["version": version, "developerDefaults": 1,
                "selectionCommandDefaults": 1, "menuPriorityDefaults": 1, "creationShortcutDefaults": 1,
                "alternateShortcutDefaults": 1, "closeWindowShortcutDefaults": 1, "fullscreenShortcutDefaults": 1,
                "exitShortcutDefaults": 1, "findShortcutDefaults": 1,
                "overrides": ["custom:": encoded(chord)], "priorities": ["custom:": "useBoth"]]
            try JSONSerialization.data(withJSONObject: document).write(to: file)
            let old = KeyboardShortcuts(); old.configure(directory: root); let oldItem = register(old)
            expect(old.loadError == nil && old.shortcut(for: "custom:") == chord, "Saved custom chord preserved")
            expect(old.shortcut(for: "clearToday:") == nil && oldItem.keyEquivalent.isEmpty, "New command never steals an explicit saved chord")
            expect(old.priority(for: "custom:") == .useBoth, "Saved custom priority remains intact")
            let data = try Data(contentsOf: file)
            let saved = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            expect(saved["clearTodayShortcutDefaults"] as? Int == 1, "Additive migration marker is durable")
            old.configure(directory: root)
            let repeated = try Data(contentsOf: file)
            expect(repeated == data, "Migration is byte-idempotent")
            try old.reset("clearToday:")
            expect(old.isConflicting("clearToday:") && old.activeShortcut(for: "clearToday:") == nil,
                   "Explicit Reset retains visible conflict with neither owner dispatchable")
            try old.set(nil, for: "custom:"); try old.reset("clearToday:")
            expect(old.activeShortcut(for: "clearToday:") == chord, "Clearing conflict and Reset restores recovered default")
            try old.setPriority(.useBoth, for: "clearToday:"); try old.set(nil, for: "clearToday:")
            old.configure(directory: root)
            expect(old.shortcut(for: "clearToday:") == nil && old.priority(for: "clearToday:") == .useBoth,
                   "Explicit disabled command and priority survive reload")
            try old.resetAll()
            expect(old.shortcut(for: "clearToday:") == chord && old.priority(for: "clearToday:") == .preferWebsites,
                   "Reset All intentionally adopts current defaults")
        }
        try JSONSerialization.data(withJSONObject: ["version": 3, "overrides": [:]]).write(to: file)
        let absent = KeyboardShortcuts(); absent.configure(directory: root); _ = register(absent)
        expect(absent.shortcut(for: "clearToday:") == chord, "Unassigned legacy files receive the added command")
        let customChord = KeyboardShortcut(key: "k", flags: [.command, .control])
        try JSONSerialization.data(withJSONObject: ["version": 3, "overrides": ["clearToday:": encoded(customChord)],
            "priorities": ["clearToday:": "useBoth"]]).write(to: file)
        let explicit = KeyboardShortcuts(); explicit.configure(directory: root); _ = register(explicit)
        expect(explicit.shortcut(for: "clearToday:") == customChord && explicit.priority(for: "clearToday:") == .useBoth,
               "Forward-compatible explicit command choices survive migration")
        let corrupt = Data("bad shortcuts".utf8); try corrupt.write(to: file)
        explicit.configure(directory: root)
        let unchanged = try Data(contentsOf: file)
        expect(explicit.loadError != nil && unchanged == corrupt, "Malformed settings are preserved verbatim")
        print("PASS: \(count) Clear Today owner/menu/migration assertions")
    }
}
