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
}
