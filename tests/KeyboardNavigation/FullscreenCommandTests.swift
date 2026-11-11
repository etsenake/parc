import AppKit

@MainActor private class InertWindow: NSWindow {
    var shown = true
    var key = true
    var minimized = false
    var testSheet: NSWindow?
    var requests = 0
    override var isVisible: Bool { shown }
    override var isKeyWindow: Bool { key }
    override var isMainWindow: Bool { true }
    override var isMiniaturized: Bool { minimized }
    override var attachedSheet: NSWindow? { testSheet }
    override func toggleFullScreen(_ sender: Any?) { requests += 1 }
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                   styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        collectionBehavior = .fullScreenPrimary
    }
}
@MainActor private final class PhaseWindow: InertWindow {
    var inFullscreen = false
    var available = true
    var validations = 0
    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        validations += 1
        item.title = inFullscreen ? "Exit Full Screen" : "Enter Full Screen"
        return available
    }
}
@MainActor private final class MenuTarget: NSObject, NSMenuItemValidation {
    var available = true
    var inFullscreen = false
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleFullScreen) {
            item.title = inFullscreen ? "Exit Full Screen" : "Enter Full Screen"
        }
        return available
    }
    @objc func toggleFullScreen(_ sender: NSMenuItem) {}
    @objc func custom(_ sender: NSMenuItem) {}
}
@main @MainActor struct FullscreenCommandTests {
    static var count = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(condition(), message)
    }
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = InertWindow(), other = InertWindow()
        defer { original.close(); other.close() }
        let item = NSMenuItem(title: "Enter/Exit Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        item.keyEquivalentModifierMask = [.command, .control]
        var ownerValid = true
        func request(_ prepare: @escaping () -> Void = {}) -> BrowserWindowFullscreenCommand {
            BrowserWindowFullscreenCommand(window: original, ownerIsAvailable: { ownerValid }, prepare: prepare)
        }
        let command = request()
        expect(command.validate(item), "Actual AppKit native validation accepts eligible inert window")
        expect(item.title == "Enter Full Screen", "AppKit supplies actual Enter title")
        expect(item.keyEquivalent == "f" && item.keyEquivalentModifierMask == [.command, .control], "Validation preserves saved menu key equivalent")
        expect(command.perform(nil) && original.requests == 1 && other.requests == 0, "Exact original native action dispatched without a transition or fallback")
        expect(!command.validate(item) && !command.perform(nil), "Original invocation cannot replay")
        expect(!original.styleMask.contains(.fullScreen), "Dispatch does not synthesize completion")
        original.collectionBehavior = .fullScreenNone
        expect(!request().validate(item) && !request().perform(nil), "Real native capability validation rejects forbidden fullscreen")
        original.collectionBehavior = .fullScreenPrimary
        original.shown = false; expect(!request().validate(item), "Hidden original rejected"); original.shown = true
        original.minimized = true; expect(!request().perform(nil), "Minimized original rejected"); original.minimized = false
        original.testSheet = other; expect(!request().perform(nil), "Sheet retains modal ownership"); original.testSheet = nil
        ownerValid = false; expect(!request().perform(nil), "Retired native owner rejected"); ownerValid = true
        original.key = false
        expect(request().validate(item), "Native capability remains queryable for the original main window behind its owned command panel")
        expect(!request().perform(nil), "Original cannot act behind another key window"); original.key = true
        expect(!request({ original.key = false }).perform(nil), "Focus loss during command-panel dismissal cancels")
        original.key = true
        expect(!request({ ownerValid = false }).perform(nil), "Owner loss during dismissal cancels"); ownerValid = true
        expect(!request({ original.collectionBehavior = .fullScreenNone }).perform(nil), "Native capability is revalidated after dismissal")
        original.collectionBehavior = .fullScreenPrimary
        var reentrant: BrowserWindowFullscreenCommand!
        var nested = true
        reentrant = request { nested = reentrant.perform(nil) }
        expect(reentrant.perform(nil) && !nested && original.requests == 2, "Request consumed before dismissal reentrancy")
        let wrongItem = NSMenuItem(title: "Other", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "")
        expect(!request().validate(wrongItem), "A different selector cannot borrow the owner")
        var expired: BrowserWindowFullscreenCommand!
        weak var retired: InertWindow?
        autoreleasepool {
            let temporary = InertWindow(); retired = temporary
            expired = BrowserWindowFullscreenCommand(window: temporary, ownerIsAvailable: { true })
            temporary.close()
        }
        expect(retired == nil && !expired.validate(item) && !expired.perform(nil), "Weak invocation never keeps retired window alive")
        let phase = PhaseWindow(); defer { phase.close() }
        let phaseRequest = BrowserWindowFullscreenCommand(window: phase, ownerIsAvailable: { true })
        phase.inFullscreen = true
        expect(phaseRequest.validate(item) && item.title == "Exit Full Screen", "Menu keeps actual native validator's dynamic title")
        phase.available = false
        expect(!phaseRequest.perform(nil) && phase.requests == 0, "Native transition refusal remains authoritative")

        let registry = KeyboardShortcuts(), file = root.appendingPathComponent("keyboard-shortcuts.json"), target = MenuTarget()
        let chord = KeyboardShortcut(key: "f", flags: [.command, .control])
        func register(_ value: KeyboardShortcuts) -> NSMenuItem {
            let menu = NSMenu(), parent = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
            let child = NSMenu(title: "View"); parent.submenu = child; menu.addItem(parent); NSApp.mainMenu = menu
            let item = NSMenuItem(title: "Enter Full Screen", action: #selector(MenuTarget.toggleFullScreen), keyEquivalent: "f")
            item.keyEquivalentModifierMask = [.command, .control]; item.target = target
            child.addItem(item); value.register(item, group: "View")
            let custom = NSMenuItem(title: "Custom", action: #selector(MenuTarget.custom), keyEquivalent: "")
            custom.target = target; child.addItem(custom); value.register(custom, group: "View")
            return item
        }
        func event(repeating: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .control], timestamp: 1,
                windowNumber: 0, context: nil, characters: "f", charactersIgnoringModifiers: "f", isARepeat: repeating, keyCode: 3)!
        }
        registry.configure(directory: root); let registered = register(registry)
        expect(registry.shortcut(for: "toggleFullScreen:") == chord, "Recovered Cmd-Control-F default")
        expect(registry.priority(for: "toggleFullScreen:") == .useBoth, "Recovered promptAfterConsumedByWebView policy")
        let native = registry.nativeCommand(for: event(), editable: false)
        expect(native?.item === registered && native?.priority == .useBoth, "Existing native acknowledgment route receives original item and Use Both")
        expect(registry.nativeCommand(for: event(), editable: true)?.item === registered, "Modified native command remains distinct from text editing")
        expect(registry.nativeCommand(for: event(repeating: true), editable: false) == nil, "Held repeat cannot issue toggle requests")
        target.available = false
        expect(registry.nativeCommand(for: event(), editable: false) == nil, "Native query respects unavailable original owner")
        target.available = true; target.inFullscreen = true
        let results = registry.menuCommands(in: other).filter { $0.id == "toggleFullScreen:" }
        expect(results.count == 1 && results[0].title == "Exit Full Screen" && results[0].shortcut == chord, "One live dynamic Actions row retains original keycap")
        expect(registry.commands.contains { $0.id == "toggleFullScreen:" && $0.group == "View" }, "Actual editable Shortcuts entry")
        target.inFullscreen = false
        func encoded(_ shortcut: KeyboardShortcut?) -> [String: Any] {
            shortcut.map { ["shortcut": ["key": $0.key, "modifiers": $0.modifiers]] } ?? [:]
        }
        for version in 1...3 {
            let document: [String: Any] = ["version": version, "developerDefaults": 1,
                "selectionCommandDefaults": 1, "menuPriorityDefaults": 1, "creationShortcutDefaults": 1,
                "alternateShortcutDefaults": 1, "closeWindowShortcutDefaults": 1,
                "overrides": ["custom:": encoded(chord)], "priorities": ["custom:": "preferWebsites"]]
            try JSONSerialization.data(withJSONObject: document).write(to: file)
            let old = KeyboardShortcuts(); old.configure(directory: root); let oldItem = register(old)
            expect(old.loadError == nil && old.shortcut(for: "custom:") == chord, "Saved chord keeps its existing owner")
            expect(old.shortcut(for: "toggleFullScreen:") == nil && oldItem.keyEquivalent.isEmpty, "New command cannot take saved custom chord")
            expect(old.priority(for: "toggleFullScreen:") == .useBoth && old.priority(for: "custom:") == .preferWebsites, "New policy and explicit existing choice preserved")
            let saved = try Data(contentsOf: file)
            let value = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
            expect(value["fullscreenShortcutDefaults"] as? Int == 1, "Additive migration marker persists")
            old.configure(directory: root)
            let repeated = try Data(contentsOf: file); expect(repeated == saved, "Migration byte-idempotent")
            try old.reset("toggleFullScreen:")
            expect(old.isConflicting("toggleFullScreen:") && old.activeShortcut(for: "toggleFullScreen:") == nil, "Explicit Reset saves a visible conflict without stealing the original chord")
            try old.set(nil, for: "custom:"); try old.reset("toggleFullScreen:")
            expect(old.shortcut(for: "toggleFullScreen:") == chord, "Reset after clearing conflict restores recovered chord")
            try old.setPriority(.preferWebsites, for: "toggleFullScreen:"); try old.set(nil, for: "toggleFullScreen:")
            old.configure(directory: root)
            expect(old.shortcut(for: "toggleFullScreen:") == nil && old.priority(for: "toggleFullScreen:") == .preferWebsites, "Explicit disabled and priority choice survives reload")
            try old.resetAll()
            expect(old.shortcut(for: "toggleFullScreen:") == chord && old.priority(for: "toggleFullScreen:") == .useBoth, "Reset All deliberately adopts reference defaults")
        }
        try JSONSerialization.data(withJSONObject: ["version": 3, "overrides": [:]]).write(to: file)
        let absent = KeyboardShortcuts(); absent.configure(directory: root); _ = register(absent)
        expect(absent.shortcut(for: "toggleFullScreen:") == chord && absent.priority(for: "toggleFullScreen:") == .useBoth, "Unassigned legacy installs receive new command")
        let customChord = KeyboardShortcut(key: "k", flags: [.command, .control])
        try JSONSerialization.data(withJSONObject: ["version": 3, "overrides": ["toggleFullScreen:": encoded(customChord)],
            "priorities": ["toggleFullScreen:": "preferParc"]]).write(to: file)
        let explicit = KeyboardShortcuts(); explicit.configure(directory: root); _ = register(explicit)
        expect(explicit.shortcut(for: "toggleFullScreen:") == customChord && explicit.priority(for: "toggleFullScreen:") == .preferParc, "Forward-compatible explicit preferences preserved")
        let corrupt = Data("bad shortcuts".utf8); try corrupt.write(to: file)
        explicit.configure(directory: root)
        let remains = try Data(contentsOf: file)
        expect(explicit.loadError != nil && remains == corrupt, "Malformed file never overwritten")
        print("PASS: \(count) Full Screen owner/menu/migration assertions")
    }
}
