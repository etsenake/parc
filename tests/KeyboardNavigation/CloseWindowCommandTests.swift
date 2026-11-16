import AppKit

@MainActor private final class ProbeWindow: NSWindow {
    var shown = true
    var key = true
    var minimized = false
    var testSheet: NSWindow?
    var requests = 0
    var closed = 0
    override var isVisible: Bool { shown }
    override var isKeyWindow: Bool { key }
    override var isMiniaturized: Bool { minimized }
    override var attachedSheet: NSWindow? { testSheet }
    override func performClose(_ sender: Any?) { requests += 1; super.performClose(sender) }
    override func close() { closed += 1; super.close() }
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
    }
}
@MainActor private final class CloseTarget: NSObject, NSMenuItemValidation, NSWindowDelegate {
    var available = true
    var pending = false
    var approved = false
    var delegateRequests = 0
    var command: BrowserWindowCloseCommand?
    func validateMenuItem(_ item: NSMenuItem) -> Bool { available && !pending }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        delegateRequests += 1
        if approved { return true }
        pending = true
        return false
    }
    @objc func closeWindow(_ sender: NSMenuItem) { _ = command?.perform(sender) }
    @objc func custom(_ sender: NSMenuItem) {}
}
@main @MainActor struct CloseWindowCommandTests {
    static var count = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(condition(), message)
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = CloseTarget(), original = ProbeWindow(), other = ProbeWindow()
        original.delegate = target
        let command = BrowserWindowCloseCommand(window: original, ownerIsAvailable: { !target.pending })
        expect(command.isAvailable, "Original physical window accepts a request")
        expect(command.perform(nil), "Request reaches actual performClose")
        expect(original.requests == 1 && target.delegateRequests == 1 && original.closed == 0,
               "Actual NSWindow delegate can defer the close")
        expect(!command.isAvailable && !command.perform(nil), "One token cannot replay a close")
        expect(other.requests == 0, "No different window is targeted")
        let pending = BrowserWindowCloseCommand(window: original, ownerIsAvailable: { !target.pending })
        expect(!pending.perform(nil), "A pending original close rejects duplicate invocations")
        target.pending = false
        let retry = BrowserWindowCloseCommand(window: original, ownerIsAvailable: { !target.pending })
        expect(retry.perform(nil) && target.delegateRequests == 2, "Fresh invocation after refusal reaches original delegate")
        target.approved = true
        original.performClose(nil)
        expect(original.closed == 1 && target.delegateRequests == 3, "Only original delegate approval closes the inert window")

        let window = ProbeWindow()
        var ownerValid = true
        func request(_ prepare: @escaping () -> Void = {}) -> BrowserWindowCloseCommand {
            BrowserWindowCloseCommand(window: window, ownerIsAvailable: { ownerValid }, prepare: prepare)
        }
        window.shown = false; expect(!request().isAvailable, "Hidden owner rejected"); window.shown = true
        window.minimized = true; expect(!request().isAvailable, "Minimized owner rejected"); window.minimized = false
        window.styleMask.remove(.closable); expect(!request().isAvailable, "Unclosable owner rejected"); window.styleMask.insert(.closable)
        window.testSheet = other; expect(!request().perform(nil), "Attached sheet retains its owner"); window.testSheet = nil
        window.key = false; expect(!request().perform(nil), "Non-key physical owner cannot close behind another window")
        window.key = true
        expect(!request({ ownerValid = false }).perform(nil), "Owner loss during panel dismissal cancels")
        expect(window.requests == 0, "No close dispatched by refused paths")
        ownerValid = true
        expect(!request({ window.key = false }).perform(nil), "Focus loss during panel dismissal cancels")
        window.key = true
        var expired: BrowserWindowCloseCommand!
        weak var retired: ProbeWindow?
        autoreleasepool {
            let temporary = ProbeWindow()
            retired = temporary
            expired = BrowserWindowCloseCommand(window: temporary, ownerIsAvailable: { true })
            temporary.close()
        }
        expect(retired == nil && !expired.isAvailable && !expired.perform(nil), "Menu lease does not keep closed owner alive")

        let registry = KeyboardShortcuts(), file = root.appendingPathComponent("keyboard-shortcuts.json")
        let chord = KeyboardShortcut(key: "w", flags: [.command, .shift])
        func register(_ value: KeyboardShortcuts) -> NSMenuItem {
            let menu = NSMenu(), parent = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
            let child = NSMenu(title: "File"); parent.submenu = child; menu.addItem(parent); NSApp.mainMenu = menu
            let item = NSMenuItem(title: "Close Window", action: #selector(CloseTarget.closeWindow), keyEquivalent: "w")
            item.keyEquivalentModifierMask = [.command, .shift]; item.target = target
            child.addItem(item); value.register(item, group: "File")
            let custom = NSMenuItem(title: "Custom", action: #selector(CloseTarget.custom), keyEquivalent: "")
            custom.target = target; child.addItem(custom); value.register(custom, group: "File")
            return item
        }
        func event(repeat repeating: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 1,
                windowNumber: 0, context: nil, characters: "W", charactersIgnoringModifiers: "W", isARepeat: repeating, keyCode: 13)!
        }
        target.pending = false
        registry.configure(directory: root); let item = register(registry)
        expect(registry.shortcut(for: "closeWindow:") == chord, "Recovered default chord")
        expect(item.keyEquivalent == "w" && item.keyEquivalentModifierMask == chord.flags, "Real visible menu equivalent")
        expect(registry.priority(for: "closeWindow:") == .preferParc, "Original overrideWebView priority")
        let native = registry.nativeCommand(for: event(), editable: false)
        expect(native?.item === item && native?.priority == .preferParc, "Existing native priority query owns exact menu item")
        expect(registry.nativeCommand(for: event(), editable: true)?.item === item, "Modified close is not a text editing alias")
        expect(registry.nativeCommand(for: event(repeat: true), editable: false) == nil, "Held repeat does not generate close requests")
        target.available = false
        expect(registry.nativeCommand(for: event(), editable: false) == nil, "Unavailable original command does not dispatch")
        target.available = true
        let result = registry.menuCommands(in: other).filter { $0.id == "closeWindow:" }
        expect(result.count == 1 && result[0].title == "Close Window" && result[0].shortcut == chord, "One actual Actions row with live keycap")
        expect(registry.commands.contains { $0.id == "closeWindow:" && $0.group == "File" }, "Real editable Settings entry")

        func encoded(_ shortcut: KeyboardShortcut?) -> [String: Any] {
            shortcut.map { ["shortcut": ["key": $0.key, "modifiers": $0.modifiers]] } ?? [:]
        }
        for version in 1...3 {
            let document: [String: Any] = ["version": version, "developerDefaults": 1,
                "selectionCommandDefaults": 1, "menuPriorityDefaults": 1, "creationShortcutDefaults": 1,
                "alternateShortcutDefaults": 1, "overrides": ["custom:": encoded(chord)],
                "priorities": ["custom:": "useBoth"]]
            try JSONSerialization.data(withJSONObject: document).write(to: file)
            let old = KeyboardShortcuts(); old.configure(directory: root); let oldItem = register(old)
            expect(old.loadError == nil && old.shortcut(for: "custom:") == chord, "Saved custom chord remains original")
            expect(old.shortcut(for: "closeWindow:") == nil && oldItem.keyEquivalent.isEmpty, "New Close Window never takes existing custom chord")
            expect(old.priority(for: "closeWindow:") == .preferParc && old.priority(for: "custom:") == .useBoth, "New command gets recovered policy, existing explicit policy preserved")
            let saved = try Data(contentsOf: file)
            let value = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
            expect(value["closeWindowShortcutDefaults"] as? Int == 1, "Additive migration marker saved")
            old.configure(directory: root)
            let repeated = try Data(contentsOf: file)
            expect(repeated == saved, "Migration is byte-idempotent")
            try old.reset("closeWindow:")
            expect(old.isConflicting("closeWindow:") && old.activeShortcut(for: "closeWindow:") == nil, "Explicit Reset persists visible conflict without dispatching either owner")
            try old.set(nil, for: "custom:"); try old.reset("closeWindow:")
            expect(old.shortcut(for: "closeWindow:") == chord, "Explicit reset adopts recovered default after conflict removed")
            try old.setPriority(.preferWebsites, for: "closeWindow:"); try old.set(nil, for: "closeWindow:")
            old.configure(directory: root)
            expect(old.shortcut(for: "closeWindow:") == nil && old.priority(for: "closeWindow:") == .preferWebsites, "Explicit disabled binding and priority survive reload")
            try old.resetAll()
            expect(old.shortcut(for: "closeWindow:") == chord && old.priority(for: "closeWindow:") == .preferParc, "Reset All deliberately restores defaults")
        }
        try JSONSerialization.data(withJSONObject: ["version": 3, "overrides": [:]]).write(to: file)
        let absent = KeyboardShortcuts(); absent.configure(directory: root); _ = register(absent)
        expect(absent.shortcut(for: "closeWindow:") == chord && absent.priority(for: "closeWindow:") == .preferParc, "Unassigned legacy files receive new command")
        let customChord = KeyboardShortcut(key: "k", flags: [.command, .control])
        try JSONSerialization.data(withJSONObject: ["version": 3, "overrides": ["closeWindow:": encoded(customChord)],
            "priorities": ["closeWindow:": "useBoth"]]).write(to: file)
        let explicit = KeyboardShortcuts(); explicit.configure(directory: root); _ = register(explicit)
        expect(explicit.shortcut(for: "closeWindow:") == customChord && explicit.priority(for: "closeWindow:") == .useBoth, "Forward-compatible explicit choices preserved")
        let corrupt = Data("bad shortcuts".utf8); try corrupt.write(to: file)
        explicit.configure(directory: root)
        let remains = try Data(contentsOf: file)
        expect(explicit.loadError != nil && remains == corrupt, "Malformed settings are never overwritten")
        print("PASS: \(count) Close Window owner/menu/migration assertions")
    }
}
