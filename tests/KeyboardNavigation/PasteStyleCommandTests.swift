import AppKit

@MainActor private final class PageView: NSView {
    var mainFrame = true
    var requests = 0
    override var acceptsFirstResponder: Bool { true }
    @objc func pasteAndMatchStyle(_ sender: Any?) { requests += 1 }
    @objc func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        item.action == NSSelectorFromString("pasteAndMatchStyle:") && mainFrame
    }
}

@main @MainActor struct PasteStyleCommandTests {
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
        let file = root.appendingPathComponent("keyboard-shortcuts.json")
        let chord = KeyboardShortcut(key: "v", flags: [.command, .shift])
        let hiddenChord = KeyboardShortcut(key: "v", flags: [.command, .option, .shift])
        func register(_ registry: KeyboardShortcuts) -> (NSMenuItem, NSMenuItem) {
            let main = NSMenu(), parent = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
            let menu = NSMenu(title: "Edit"); parent.submenu = menu; main.addItem(parent); NSApp.mainMenu = main
            let item = NSMenuItem(title: "Paste and Match Style", action: WebpageEditCommands.pasteMatchingStyle, keyEquivalent: "v")
            item.keyEquivalentModifierMask = [.command, .shift]; menu.addItem(item)
            registry.register(item, group: "Edit")
            let hidden = NSMenuItem(title: "Paste and Match Style", action: WebpageEditCommands.pasteMatchingStyle, keyEquivalent: "v")
            hidden.keyEquivalentModifierMask = hiddenChord.flags; hidden.isHidden = true
            hidden.allowsKeyEquivalentWhenHidden = true; menu.addItem(hidden)
            registry.registerEquivalent(hidden, for: "pasteAsPlainText:", shortcut: hiddenChord)
            let custom = NSMenuItem(title: "Custom", action: NSSelectorFromString("custom:"), keyEquivalent: "")
            menu.addItem(custom); registry.register(custom, group: "Edit")
            return (item, hidden)
        }

        let registry = KeyboardShortcuts(); registry.configure(directory: root)
        let (item, hidden) = register(registry)
        expect(registry.shortcut(for: "pasteAsPlainText:") == chord, "Recovered Command-Shift-V default")
        expect(item.keyEquivalent == "v" && item.keyEquivalentModifierMask == chord.flags, "Visible actual menu chord")
        expect(hidden.keyEquivalent == "v" && hidden.keyEquivalentModifierMask == hiddenChord.flags,
               "Hidden Command-Option-Shift-V equivalent follows the primary")
        expect(registry.priority(for: "pasteAsPlainText:") == .preferWebsites, "No shipped priority attribute")
        expect(registry.commands.filter { $0.id == "pasteAsPlainText:" }.count == 1, "One editable Shortcuts entry")
        try registry.set(KeyboardShortcut(key: "p", flags: [.command, .option]), for: "pasteAsPlainText:")
        expect(hidden.keyEquivalent.isEmpty, "Customized primary suppresses the fixed hidden equivalent")
        try registry.resetAll()

        func encoded(_ chord: KeyboardShortcut?) -> [String: Any] {
            chord.map { ["shortcut": ["key": $0.key, "modifiers": $0.modifiers]] } ?? [:]
        }
        let document: [String: Any] = ["version": 3, "overrides": ["custom:": encoded(chord)]]
        try JSONSerialization.data(withJSONObject: document).write(to: file)
        let old = KeyboardShortcuts(); old.configure(directory: root); let (oldItem, oldHidden) = register(old)
        expect(old.loadError == nil && old.shortcut(for: "custom:") == chord, "Saved custom chord preserved")
        expect(old.shortcut(for: "pasteAsPlainText:") == nil && oldItem.keyEquivalent.isEmpty && oldHidden.keyEquivalent.isEmpty,
               "New command never steals an explicit saved chord")
        let data = try Data(contentsOf: file)
        let saved = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        expect(saved["pasteStyleShortcutDefaults"] as? Int == 1, "Additive migration marker is durable")
        old.configure(directory: root)
        let repeated = try Data(contentsOf: file)
        expect(repeated == data, "Migration is byte-idempotent")

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                               styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let page = PageView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        window.contentView!.addSubview(page)
        let probe = NSMenuItem(title: "Paste and Match Style", action: WebpageEditCommands.pasteMatchingStyle, keyEquivalent: "")
        expect(window.makeFirstResponder(page) && window.firstResponder === page, "Page view owns focus")
        expect(WebpageEditCommands.pageTarget(in: window) === page, "Engine page view is the forwarding target")
        expect(WebpageEditCommands.canPasteMatchingStyle(probe, in: window), "Main-frame page validates its own selector")
        page.mainFrame = false
        expect(!WebpageEditCommands.canPasteMatchingStyle(probe, in: window), "Engine validation stays authoritative")
        WebpageEditCommands.pasteMatchingStyle(from: probe, in: window)
        expect(page.requests == 0, "Refused validation never dispatches")
        page.mainFrame = true
        WebpageEditCommands.pasteMatchingStyle(from: probe, in: window)
        expect(page.requests == 1, "Forwarded once to the page view")
        let text = NSTextView(frame: NSRect(x: 0, y: 100, width: 100, height: 50))
        window.contentView!.addSubview(text)
        expect(window.makeFirstResponder(text), "Native text owns focus")
        expect(WebpageEditCommands.pageTarget(in: window) == nil && !WebpageEditCommands.canPasteMatchingStyle(probe, in: window),
               "Native text keeps its own pasteAsPlainText:")
        let inner = PageView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        text.addSubview(inner)
        expect(window.makeFirstResponder(inner) && WebpageEditCommands.pageTarget(in: window) === inner,
               "The focused page view answers before any text ancestor")
        window.close()
        print("PasteStyleCommandTests: \(count) checks passed")
    }
}
