import AppKit

@MainActor private final class InventoryTarget: NSObject, NSMenuItemValidation {
    var enabled = true
    func validateMenuItem(_ item: NSMenuItem) -> Bool { enabled }
    @objc func nextTab(_ sender: NSMenuItem) {}
    @objc func previousTab(_ sender: NSMenuItem) {}
    @objc func newBlankWindow(_ sender: NSMenuItem) {}
    @objc func viewLibrary(_ sender: NSMenuItem) {}
    @objc func custom(_ sender: NSMenuItem) {}
}

@main @MainActor struct InventoryCommandTests {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = InventoryTarget()
        func register(_ registry: KeyboardShortcuts) -> [String: NSMenuItem] {
            let rootMenu = NSMenu(), parent = NSMenuItem(title: "Tabs", action: nil, keyEquivalent: "")
            let menu = NSMenu(title: "Tabs"); parent.submenu = menu; rootMenu.addItem(parent); NSApp.mainMenu = rootMenu
            var items: [String: NSMenuItem] = [:]
            for (id, key, flags) in [
                ("nextTab:", "\u{f701}", NSEvent.ModifierFlags([.command, .option])), ("previousTab:", "\u{f700}", [.command, .option]),
                ("newBlankWindow:", "n", [.command, .control]), ("viewLibrary:", "l", [.command, .shift]), ("custom:", "", [])] {
                let item = NSMenuItem(title: id, action: NSSelectorFromString(id), keyEquivalent: key)
                item.keyEquivalentModifierMask = flags; item.target = target; menu.addItem(item)
                registry.register(item, group: "Tabs"); items[id] = item
            }
            for (id, action, key) in [("nextTab", "nextTab:", "}"), ("previousTab", "previousTab:", "{")] {
                let item = NSMenuItem(title: id, action: NSSelectorFromString(action), keyEquivalent: key)
                item.keyEquivalentModifierMask = .command; item.target = target
                item.isHidden = true; item.allowsKeyEquivalentWhenHidden = true; menu.addItem(item)
                registry.register(item, group: "Tabs", bindingID: id, discoverable: false); items[id] = item
            }
            return items
        }
        func event(_ code: UInt16, _ key: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 1,
                             windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key,
                             isARepeat: false, keyCode: code)!
        }
        let registry = KeyboardShortcuts(); registry.configure(directory: root); let items = register(registry)
        expect(registry.shortcut(for: "newBlankWindow:") == .init(key: "n", flags: [.command, .control]), "Blank Window default")
        expect(registry.shortcut(for: "viewLibrary:") == .init(key: "l", flags: [.command, .shift]), "View Library default")
        expect(registry.shortcut(for: "nextTab") == .init(key: "}", flags: .command), "Hidden Next Tab binding")
        expect(registry.shortcut(for: "previousTab") == .init(key: "{", flags: .command), "Hidden Previous Tab binding")
        for id in ["newBlankWindow:", "viewLibrary:", "nextTab", "previousTab"] {
            expect(registry.priority(for: id) == .preferWebsites, "No shipped priority attribute for \(id)")
        }
        expect(registry.priority(for: "nextTab:") == .preferParc, "Menu Next Tab keeps its own priority")
        expect(items["nextTab"]!.keyEquivalent == "}" && items["nextTab"]!.keyEquivalentModifierMask == .command, "Symbolic menu chord")
        let shiftedNext = event(30, "}", [.command, .shift])
        expect(registry.nativeCommand(for: shiftedNext, editable: false)?.item === items["nextTab"], "Symbolic Command-} dispatches the hidden Next Tab owner")
        expect(registry.nativeCommand(for: event(33, "{", [.command, .shift]), editable: false)?.item === items["previousTab"], "Symbolic Command-{ dispatches Previous Tab")
        target.enabled = false
        expect(registry.nativeCommand(for: shiftedNext, editable: false) == nil, "Unavailable positional target is not dispatched")
        target.enabled = true
        let physical = KeyboardShortcut(key: "]", flags: [.command, .shift])
        if KeyboardShortcut.physicalKeys(producingShifted: "}").contains("]") {
            try registry.set(physical, for: "custom:")
            expect(registry.nativeCommand(for: shiftedNext, editable: false)?.item === items["custom:"], "Physical saved chord wins")
            expect(items["nextTab"]!.keyEquivalent == "", "Symbolic equivalent suppressed for the physical owner")
            try registry.set(nil, for: "custom:")
            expect(items["nextTab"]!.keyEquivalent == "}", "Clearing the physical owner restores the symbolic equivalent")
        }
        try registry.set(.init(key: "j", flags: [.command, .option, .control]), for: "nextTab")
        expect(registry.nativeCommand(for: shiftedNext, editable: false) == nil, "Customized binding drops the symbolic route")
        expect(registry.shortcut(for: "nextTab:") == .init(key: "\u{f701}", flags: [.command, .option]), "Independent identities")
        try registry.resetAll()

        let file = root.appendingPathComponent("keyboard-shortcuts.json")
        let legacy = """
        {"version":3,"overrides":{"custom:":{"shortcut":{"key":"l","modifiers":\(NSEvent.ModifierFlags([.command, .shift]).rawValue)}}},
         "priorities":{},"developerDefaults":1,"selectionCommandDefaults":1,"menuPriorityDefaults":1,
         "creationShortcutDefaults":1,"alternateShortcutDefaults":1,"closeWindowShortcutDefaults":1,
         "fullscreenShortcutDefaults":1,"exitShortcutDefaults":1,"findShortcutDefaults":1,
         "clearTodayShortcutDefaults":1,"pasteStyleShortcutDefaults":1}
        """
        try Data(legacy.utf8).write(to: file)
        let old = KeyboardShortcuts(); old.configure(directory: root); _ = register(old)
        expect(old.loadError == nil, "Migration saved")
        expect(old.shortcut(for: "viewLibrary:") == nil, "New View Library default does not steal a saved custom chord")
        expect(old.shortcut(for: "custom:") == .init(key: "l", flags: [.command, .shift]), "Saved chord preserved")
        expect(old.shortcut(for: "newBlankWindow:") == .init(key: "n", flags: [.command, .control]), "Untouched new default adopted")
        let saved = try String(contentsOf: file, encoding: .utf8)
        expect(saved.contains("inventoryShortcutDefaults"), "Additive marker persisted")
        print("PASS: \(count) KB03 inventory default/symbolic/migration assertions")
    }
}
