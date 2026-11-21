import AppKit
import Testing
@testable import Parc

struct LiveBindingTests {
    @MainActor private final class Fixture {
        let menu = NSMenu(title: "View")
        let registry: KeyboardShortcuts
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let copyDefault = KeyboardShortcut(key: "c", flags: [.command, .shift])

        init() throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let root = menu
            registry = KeyboardShortcuts(mainMenu: { root }, observesKeyboardLayout: false)
            register("toggleSidebar:", chord: KeyboardShortcut(key: "s", flags: .command))
            register("copyCurrentURL:", chord: copyDefault)
            registry.configure(directory: directory)
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func register(_ id: String, chord: KeyboardShortcut) {
            let item = NSMenuItem(title: id, action: NSSelectorFromString(id), keyEquivalent: chord.key)
            item.keyEquivalentModifierMask = chord.flags
            menu.addItem(item)
            registry.register(item, group: "View")
        }

        func copyItem() -> NSMenuItem {
            let item = NSMenuItem(title: "Copy URL", action: nil, keyEquivalent: "")
            registry.showBinding(on: item, for: "copyCurrentURL:")
            return item
        }
    }

    @Test @MainActor func accessibilityHelpUsesTheLatestTitleAndSpokenKey() throws {
        let fixture = try Fixture()
        let toggle = NSButton()
        fixture.registry.bindHelp(toggle, title: "Hide sidebar", commandID: "toggleSidebar:")
        fixture.registry.bindHelp(toggle, title: "Lock sidebar", commandID: "toggleSidebar:")
        try fixture.registry.set(KeyboardShortcut(key: " ", flags: [.control, .command]), for: "toggleSidebar:")
        #expect(toggle.accessibilityHelp() == "Lock sidebar ⌃⌘Space")
        #expect(toggle.cell?.accessibilityHelp() == toggle.accessibilityHelp())
        #expect(toggle.toolTip == nil)
    }

    @Test(arguments: [false, true])
    @MainActor func disabledHelpIsShownOnlyWhenItDoesNotRequireABinding(requiresBinding: Bool) throws {
        let fixture = try Fixture()
        let button = NSButton()
        fixture.registry.bindHelp(button, title: "Copy URL", commandID: "copyCurrentURL:", requiresBinding: requiresBinding)
        try fixture.registry.set(nil, for: "copyCurrentURL:")
        #expect(button.accessibilityHelp() == (requiresBinding ? nil : "Copy URL"))
    }

    @Test @MainActor func retainedMenuItemsRemoveConflictsAndRestoreTheBinding() throws {
        let fixture = try Fixture()
        let item = fixture.copyItem()
        try fixture.registry.set(fixture.copyDefault, for: "toggleSidebar:")
        #expect(item.keyEquivalent.isEmpty)
        try fixture.registry.reset("toggleSidebar:")
        #expect(item.keyEquivalent == fixture.copyDefault.key)
    }

    @Test @MainActor func theDiscoveryCallbackSeesTheCommittedMenuBinding() throws {
        let fixture = try Fixture()
        let item = fixture.copyItem()
        var discovered: String?
        fixture.registry.onDiscoveryChange = { discovered = item.keyEquivalent }
        try fixture.registry.set(KeyboardShortcut(key: "y", flags: [.command, .shift]), for: "copyCurrentURL:")
        #expect(discovered == "y")
    }

    @Test @MainActor func bindingHelpDoesNotRetainItsMenuItem() throws {
        let fixture = try Fixture()
        weak var released: NSMenuItem?
        do {
            let item = fixture.copyItem()
            released = item
            #expect(item.keyEquivalent == fixture.copyDefault.key)
        }
        #expect(released == nil)
    }

    @Test @MainActor func aRetiredCommandKeepsItsSavedChordUntilReregistered() throws {
        let fixture = try Fixture()
        let item = fixture.copyItem()
        let chord = KeyboardShortcut(key: "y", flags: [.command, .shift])
        try fixture.registry.set(chord, for: "copyCurrentURL:")
        fixture.registry.retireCommands(["copyCurrentURL:"])
        #expect(fixture.registry.shortcut(for: "copyCurrentURL:") == chord)
        #expect(item.keyEquivalent.isEmpty)
        fixture.register("copyCurrentURL:", chord: fixture.copyDefault)
        #expect(item.keyEquivalent == chord.key)
    }
}
