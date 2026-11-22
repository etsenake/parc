import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct InventoryCommandTests {
    @Test(arguments: [
        ("newBlankWindow:", "n", NSEvent.ModifierFlags([.command, .control]), false),
        ("viewLibrary:", "l", NSEvent.ModifierFlags([.command, .shift]), false),
        ("nextTab", "}", NSEvent.ModifierFlags.command, false),
        ("previousTab", "{", NSEvent.ModifierFlags.command, false),
        ("nextTab:", "\u{f701}", NSEvent.ModifierFlags([.command, .option]), true),
    ])
    @MainActor func theMenuInventoryKeepsSeparateDefaults(id: String, key: String, flags: NSEvent.ModifierFlags,
                                                           prefersParc: Bool) {
        _ = NSApplication.shared
        var root: NSMenu?
        let registry = KeyboardShortcuts(mainMenu: { root }, observesKeyboardLayout: false)
        let delegate = AppDelegate()
        root = delegate.buildMenus(shortcuts: registry, install: false, initialSpaces: BrowserState.initial().spaces)
        #expect(registry.shortcut(for: id) == KeyboardShortcut(key: key, flags: flags))
        #expect(registry.priority(for: id) == (prefersParc ? .preferParc : .preferWebsites))
    }

    @MainActor private final class Target: NSObject, NSMenuItemValidation {
        var enabled = true
        func validateMenuItem(_ item: NSMenuItem) -> Bool { enabled }
        @objc func nextTab(_ sender: NSMenuItem) {}
        @objc func previousTab(_ sender: NSMenuItem) {}
        @objc func newBlankWindow(_ sender: NSMenuItem) {}
        @objc func viewLibrary(_ sender: NSMenuItem) {}
        @objc func custom(_ sender: NSMenuItem) {}
    }

    @MainActor private final class Bench {
        let directory: URL
        let file: URL
        let target = Target()
        let menu = NSMenu(title: "Tabs")
        var items: [String: NSMenuItem] = [:]

        init() throws {
            _ = NSApplication.shared
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            file = directory.appendingPathComponent("keyboard-shortcuts.json")
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func registry() -> KeyboardShortcuts {
            let registry = KeyboardShortcuts(mainMenu: { [menu] in menu }, observesKeyboardLayout: false)
            registry.configure(directory: directory)
            menu.removeAllItems()
            items = [:]
            let rows: [(String, String, NSEvent.ModifierFlags)] = [
                ("nextTab:", "\u{f701}", [.command, .option]), ("previousTab:", "\u{f700}", [.command, .option]),
                ("newBlankWindow:", "n", [.command, .control]), ("viewLibrary:", "l", [.command, .shift]), ("custom:", "", []),
            ]
            for (id, key, flags) in rows {
                let item = NSMenuItem(title: id, action: NSSelectorFromString(id), keyEquivalent: key)
                item.keyEquivalentModifierMask = flags
                item.target = target
                menu.addItem(item)
                registry.register(item, group: "Tabs")
                items[id] = item
            }
            for (id, action, key) in [("nextTab", "nextTab:", "}"), ("previousTab", "previousTab:", "{")] {
                let item = NSMenuItem(title: id, action: NSSelectorFromString(action), keyEquivalent: key)
                item.keyEquivalentModifierMask = .command
                item.target = target
                item.isHidden = true
                item.allowsKeyEquivalentWhenHidden = true
                menu.addItem(item)
                registry.register(item, group: "Tabs", bindingID: id, discoverable: false)
                items[id] = item
            }
            return registry
        }

        func event(_ code: UInt16, _ key: String, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 1,
                windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key,
                isARepeat: false, keyCode: code))
        }
    }

    @Test @MainActor func theSymbolicBraceChordsDispatchTheirHiddenOwners() throws {
        let bench = try Bench()
        let registry = bench.registry()
        #expect(bench.items["nextTab"]?.keyEquivalent == "}")
        #expect(bench.items["nextTab"]?.keyEquivalentModifierMask == .command)
        #expect(registry.priority(for: "nextTab:") == .preferParc)
        #expect(registry.nativeCommand(for: try bench.event(30, "}", [.command, .shift]), editable: false)?.item === bench.items["nextTab"])
        #expect(registry.nativeCommand(for: try bench.event(33, "{", [.command, .shift]), editable: false)?.item === bench.items["previousTab"])
    }

    @Test @MainActor func anUnavailableTargetIsNotDispatched() throws {
        let bench = try Bench()
        let registry = bench.registry()
        bench.target.enabled = false
        #expect(registry.nativeCommand(for: try bench.event(30, "}", [.command, .shift]), editable: false) == nil)
    }

    @Test @MainActor func aPhysicalSavedChordWinsAndClearingItRestoresTheSymbolicEquivalent() throws {
        try #require(KeyboardShortcut.physicalKeys(producingShifted: "}").contains("]"))
        let bench = try Bench()
        let registry = bench.registry()
        try registry.set(KeyboardShortcut(key: "]", flags: [.command, .shift]), for: "custom:")
        #expect(registry.nativeCommand(for: try bench.event(30, "}", [.command, .shift]), editable: false)?.item === bench.items["custom:"])
        #expect(bench.items["nextTab"]?.keyEquivalent == "")
        try registry.set(nil, for: "custom:")
        #expect(bench.items["nextTab"]?.keyEquivalent == "}")
    }

    @Test @MainActor func customizingTheHiddenBindingDropsItsSymbolicRouteAndKeepsIdentitiesIndependent() throws {
        let bench = try Bench()
        let registry = bench.registry()
        try registry.set(.init(key: "j", flags: [.command, .option, .control]), for: "nextTab")
        #expect(registry.nativeCommand(for: try bench.event(30, "}", [.command, .shift]), editable: false) == nil)
        #expect(registry.shortcut(for: "nextTab:") == .init(key: "\u{f701}", flags: [.command, .option]))
        try registry.resetAll()
    }

    @Test @MainActor func oldSettingsKeepTheirChordAndAdoptUntouchedNewDefaults() throws {
        let bench = try Bench()
        let legacy = """
        {"version":3,"overrides":{"custom:":{"shortcut":{"key":"l","modifiers":\(NSEvent.ModifierFlags([.command, .shift]).rawValue)}}},
         "priorities":{},"developerDefaults":1,"selectionCommandDefaults":1,"menuPriorityDefaults":1,
         "creationShortcutDefaults":1,"alternateShortcutDefaults":1,"closeWindowShortcutDefaults":1,
         "fullscreenShortcutDefaults":1,"exitShortcutDefaults":1,"findShortcutDefaults":1,
         "clearTodayShortcutDefaults":1,"pasteStyleShortcutDefaults":1}
        """
        try Data(legacy.utf8).write(to: bench.file)
        let registry = bench.registry()
        #expect(registry.loadError == nil)
        #expect(registry.shortcut(for: "viewLibrary:") == nil)
        #expect(registry.shortcut(for: "custom:") == .init(key: "l", flags: [.command, .shift]))
        #expect(registry.shortcut(for: "newBlankWindow:") == .init(key: "n", flags: [.command, .control]))
        #expect(try String(contentsOf: bench.file, encoding: .utf8).contains("inventoryShortcutDefaults"))
    }
}
