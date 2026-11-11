import AppKit

@MainActor private final class PeekMenuTarget: NSObject, NSMenuItemValidation {
    var enabled = false
    func validateMenuItem(_ item: NSMenuItem) -> Bool { enabled }
    @objc func openInCurrentSpace(_ sender: NSMenuItem) {}
}
@MainActor private final class PeekCommandWindow: NSWindow {
    var key = true
    override var isKeyWindow: Bool { key }
}

@main struct LiveBindingTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ reason: String) { checks += 1; precondition(value(), reason) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = KeyboardShortcuts()
        let menu = NSMenu(title: "View")
        for (id, key, flags) in [("toggleSidebar:", "s", NSEvent.ModifierFlags.command), ("resetTab:", "r", [.command, .shift]),
                                 ("copyCurrentURL:", "c", [.command, .shift]), ("reload:", "r", .command)] {
            let item = NSMenuItem(title: id, action: NSSelectorFromString(id), keyEquivalent: key)
            item.keyEquivalentModifierMask = flags; menu.addItem(item); registry.register(item, group: "View")
        }
        registry.configure(directory: directory)

        expect(KeyboardShortcuts.toolTip("Hide sidebar", shortcut: KeyboardShortcut(key: "s", flags: .command)) == "Hide sidebar ⌘S", "Tooltip format")
        expect(KeyboardShortcuts.toolTip("Hide sidebar", shortcut: nil) == "Hide sidebar", "No binding, title alone")
        expect(registry.toolTip("Go back", for: "goBack:") == "Go back", "Unregistered command shows the title")

        func help(_ button: NSButton) -> String? {
            precondition(button.toolTip == nil && button.cell?.accessibilityHelp() == button.accessibilityHelp(), "help tag or cell help diverged")
            return button.accessibilityHelp()
        }
        let toggle = NSButton(), reset = NSButton(), plain = NSButton()
        registry.bindHelp(toggle, title: "Hide sidebar", commandID: "toggleSidebar:")
        registry.bindHelp(reset, title: "Reset Tab", commandID: "resetTab:", requiresBinding: true)
        registry.bindHelp(plain, title: "Site Control Center", commandID: nil)
        expect(help(toggle) == "Hide sidebar ⌘S" && help(reset) == "Reset Tab ⇧⌘R" && help(plain) == "Site Control Center", "Initial live help")

        try registry.set(KeyboardShortcut(key: "b", flags: [.command, .option]), for: "toggleSidebar:")
        expect(help(toggle) == "Hide sidebar ⌥⌘B", "Changed binding updates the help")
        try registry.set(nil, for: "resetTab:")
        expect(help(reset) == nil, "Cleared Reset Tab binding clears its binding-only help")
        try registry.reset("resetTab:")
        expect(help(reset) == "Reset Tab ⇧⌘R", "Reset restores the help")

        let proposal = KeyboardShortcut(key: "c", flags: [.command, .shift])
        try registry.set(proposal, for: "toggleSidebar:")
        expect(help(toggle) == "Hide sidebar", "Conflicting binding is not advertised")
        try registry.reset("toggleSidebar:")
        expect(help(toggle) == "Hide sidebar ⌘S", "Resolved conflict advertises again")

        registry.bindHelp(toggle, title: "Lock sidebar", commandID: "toggleSidebar:")
        try registry.set(KeyboardShortcut(key: "l", flags: [.command, .control]), for: "toggleSidebar:")
        expect(help(toggle) == "Lock sidebar ⌃⌘L", "Latest title keeps following the binding")
        try registry.set(KeyboardShortcut(key: " ", flags: [.command, .control]), for: "toggleSidebar:")
        expect(help(toggle) == "Lock sidebar ⌃⌘Space", "Spoken help says Space where the keycap shows ⎵")
        try registry.reset("toggleSidebar:")

        let copy = NSMenuItem(title: "Copy URL", action: nil, keyEquivalent: "")
        registry.showBinding(on: copy, for: "copyCurrentURL:")
        expect(copy.keyEquivalent == "c" && copy.keyEquivalentModifierMask == [.command, .shift], "Menu entry shows the binding")
        try registry.set(nil, for: "copyCurrentURL:")
        expect(copy.keyEquivalent.isEmpty && copy.keyEquivalentModifierMask.isEmpty, "Unbound menu entry shows none")
        try registry.reset("copyCurrentURL:")
        expect(copy.keyEquivalent == "c", "A retained context menu refreshes without rebuilding")
        try registry.set(proposal, for: "toggleSidebar:")
        expect(copy.keyEquivalent.isEmpty, "A conflict clears the original context menu's binding")
        try registry.reset("toggleSidebar:")
        expect(copy.keyEquivalent == "c", "Resolving a conflict restores the original context menu")
        var discovered = ""
        registry.onDiscoveryChange = { discovered = copy.keyEquivalent }
        try registry.set(KeyboardShortcut(key: "y", flags: [.command, .shift]), for: "copyCurrentURL:")
        expect(discovered == "y", "The custom presentation signal sees committed bindings and menus")
        try registry.reset("copyCurrentURL:")
        weak var releasedMenu: NSMenuItem?
        do {
            let transient = NSMenuItem(title: "Transient", action: nil, keyEquivalent: "")
            releasedMenu = transient
            registry.showBinding(on: transient, for: "copyCurrentURL:")
        }
        expect(releasedMenu == nil, "Discovery registration does not keep a context menu item alive")
        let customCopy = KeyboardShortcut(key: "y", flags: [.command, .shift])
        try registry.set(customCopy, for: "copyCurrentURL:")
        registry.retireCommands(["copyCurrentURL:"])
        expect(registry.shortcut(for: "copyCurrentURL:") == customCopy
               && registry.activeShortcut(for: "copyCurrentURL:") == nil && copy.keyEquivalent.isEmpty,
               "Retirement preserves customization but withdraws discoverable/executable bindings")
        let restoredCopy = NSMenuItem(title: "Copy URL", action: NSSelectorFromString("copyCurrentURL:"), keyEquivalent: "c")
        restoredCopy.keyEquivalentModifierMask = [.command, .shift]; menu.addItem(restoredCopy)
        registry.register(restoredCopy, group: "View")
        expect(registry.activeShortcut(for: "copyCurrentURL:") == customCopy && copy.keyEquivalent == "y",
               "Re-registering the original command restores its saved binding and retained context menu")
        try registry.reset("copyCurrentURL:")

        do {
            let transient = NSButton()
            registry.bindHelp(transient, title: "Reload this page", commandID: "reload:")
            expect(help(transient) == "Reload this page ⌘R", "Transient view bound")
        }
        try registry.set(KeyboardShortcut(key: "r", flags: [.command, .option]), for: "reload:")
        expect(help(toggle) == "Lock sidebar ⌘S", "Other bindings unaffected after a released view")

        let peekRegistry = KeyboardShortcuts(), peekMenu = NSMenu(title: "Tabs"), rootMenu = NSMenu()
        let parentItem = NSMenuItem(); parentItem.submenu = peekMenu; rootMenu.addItem(parentItem)
        NSApp.mainMenu = rootMenu
        let target = PeekMenuTarget()
        let open = NSMenuItem(title: "Open Peek in Current Space", action: #selector(PeekMenuTarget.openInCurrentSpace), keyEquivalent: "")
        open.target = target; open.isHidden = true; open.allowsKeyEquivalentWhenHidden = true; peekMenu.addItem(open)
        let peekDirectory = directory.appendingPathComponent("peek")
        try FileManager.default.createDirectory(at: peekDirectory, withIntermediateDirectories: true)
        peekRegistry.configure(directory: peekDirectory)
        peekRegistry.register(open, group: "Tabs", discoverable: false)
        let openChord = KeyboardShortcut(key: "o", flags: .command)
        expect(peekRegistry.activeShortcut(for: "openInCurrentSpace:") == openChord && open.keyEquivalent == "o", "Peek default survives an initially hidden native menu")
        expect(peekRegistry.priority(for: "openInCurrentSpace:") == .useBoth, "Peek retains the recovered consumed-website prompt priority")
        let openEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 1,
            windowNumber: 0, context: nil, characters: "o", charactersIgnoringModifiers: "o", isARepeat: false, keyCode: 31)!
        expect(peekRegistry.nativeCommand(for: openEvent, editable: false) == nil, "No modal does not intercept Command-O")
        target.enabled = true
        expect(peekRegistry.nativeCommand(for: openEvent, editable: true)?.item === open, "Hidden entry revalidates the actual newly available modal")
        let expand = NSButton()
        peekRegistry.bindHelp(expand, title: "Open Peek as Tab", commandID: "openInCurrentSpace:")
        try peekRegistry.set(nil, for: "openInCurrentSpace:")
        expect(help(expand) == "Open Peek as Tab" && open.keyEquivalent.isEmpty, "Removing Peek binding clears both native menu and Expand hint")
        try peekRegistry.reset("openInCurrentSpace:")
        expect(help(expand) == "Open Peek as Tab ⌘O", "Reset restores the original Expand binding")
        let legacy = directory.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let legacyFile = legacy.appendingPathComponent("keyboard-shortcuts.json")
        func writeLegacy(_ overrides: [String: Any]) throws {
            try JSONSerialization.data(withJSONObject: ["version": 3, "overrides": overrides]).write(to: legacyFile)
        }
        try writeLegacy(["other:": ["shortcut": ["key": "o", "modifiers": NSEvent.ModifierFlags.command.rawValue]]])
        peekRegistry.configure(directory: legacy)
        expect(peekRegistry.activeShortcut(for: "openInCurrentSpace:") == nil && peekRegistry.shortcut(for: "other:") == openChord, "New default never steals a saved Command-O")
        let migrated = try JSONSerialization.jsonObject(with: Data(contentsOf: legacyFile)) as! [String: Any]
        expect(migrated["peekOpenShortcutDefaults"] as? Int == 1, "Peek's independent migration marker persists")
        try writeLegacy(["openInCurrentSpace:": [:]])
        peekRegistry.configure(directory: legacy)
        expect(peekRegistry.activeShortcut(for: "openInCurrentSpace:") == nil, "An explicit saved disable survives introduction")
        try writeLegacy(["openInCurrentSpace:": ["shortcut": ["key": "o", "modifiers": NSEvent.ModifierFlags([.command, .shift]).rawValue]]])
        peekRegistry.configure(directory: legacy)
        expect(peekRegistry.activeShortcut(for: "openInCurrentSpace:") == .init(key: "o", flags: [.command, .shift]), "A saved custom Peek chord survives")
        try writeLegacy([:]); peekRegistry.configure(directory: legacy)
        expect(peekRegistry.activeShortcut(for: "openInCurrentSpace:") == openChord && peekRegistry.priority(for: "openInCurrentSpace:") == .useBoth, "Untouched old settings receive the recovered new default and priority")

        let originalWindow = PeekCommandWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        originalWindow.isReleasedWhenClosed = false; originalWindow.orderFront(nil)
        defer { originalWindow.orderOut(nil) }
        var originalTarget = true, promoted = 0
        let originalCommand = PeekOpenCommand(window: originalWindow, targetIsAvailable: { originalTarget }, execute: { promoted += 1 })
        expect(originalCommand.isAvailable, "Original modal target is admitted")
        originalTarget = false
        expect(!originalCommand.perform() && promoted == 0, "Changed modal/Space/Profile identity cannot retarget a tracked menu command")
        originalTarget = true; originalWindow.key = false
        expect(!originalCommand.perform() && promoted == 0, "A different key window cannot receive the original command")
        originalWindow.key = true
        expect(originalCommand.perform() && promoted == 1 && !originalCommand.perform(), "Original target promotes once and only once")

        let suite = "parc.kb38.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var upsell = SuperCopyUpsell(defaults: defaults)
        upsell.calendar = Calendar(identifier: .gregorian)
        let chord = KeyboardShortcut(key: "c", flags: [.command, .shift])
        let url = "https://example.com/a?b=1"
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        expect(upsell.message(copied: url, pageURL: url, shortcut: chord, now: now) == "Copy links faster by pressing ⇧⌘C", "First page-URL copy offers the shortcut")
        expect(upsell.message(copied: "example", pageURL: url, shortcut: chord, now: now) == nil, "Other text is not the page URL")
        expect(upsell.message(copied: url, pageURL: url, shortcut: nil, now: now) == nil, "No valid binding, no upsell")
        expect(upsell.message(copied: url, pageURL: nil, shortcut: chord, now: now) == nil, "No page, no upsell")
        upsell.recordShown(now: now)
        expect(upsell.message(copied: url, pageURL: url, shortcut: chord, now: now.addingTimeInterval(86_400)) == nil, "One day later is too soon")
        expect(upsell.message(copied: url, pageURL: url, shortcut: chord, now: now.addingTimeInterval(2 * 86_400)) != nil, "Two days later offers again")

        let window = NSWindow(contentRect: NSRect(x: -12_000, y: -12_000, width: 300, height: 200),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let anchor = NSView(frame: root.bounds)
        root.addSubview(anchor); window.contentView = root
        let toasts = PArcToastPresenter()
        let upsellToast = PArcToastContent.superCopyUpsell(shortcut: chord.display, message: "Copy links faster by pressing ⇧⌘C")
        expect(upsellToast.body == .shortcut(leading: SuperCopyUpsell.prefix, shortcut: "⇧⌘C", trailing: nil)
               && upsellToast.showsShortcut, "The upsell toast is the shortcut content with the upsell's own text")
        expect(toasts.show(upsellToast, in: window, over: anchor, theme: SpaceTheme()) == nil,
               "A hidden window cannot record a shown upsell")
        window.orderBack(nil)
        defer { toasts.dismiss(animated: false); window.orderOut(nil) }
        let responder = window.firstResponder
        expect(toasts.show(upsellToast, in: window, over: anchor, theme: SpaceTheme()) != nil
               && window.childWindows?.count == 1, "A visible window attaches the toast as its child")
        expect(window.firstResponder === responder, "The passive toast preserves the original responder")
        print("LiveBindingTests: \(checks) checks passed")
    }
}
