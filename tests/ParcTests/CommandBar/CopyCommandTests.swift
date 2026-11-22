import AppKit
import Testing
@testable import Parc
@testable import ParcKit

struct CopyCommandTests {
    private static let ids = ["copyCurrentURL:", "copyCurrentURLAsMarkdown:", "copyCurrentURLAsQuote:"]
    private static let flags: [NSEvent.ModifierFlags] = [[.command, .shift], [.command, .shift, .option], [.command, .shift, .control]]

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let menu = NSMenu(title: "Edit")
        let registry: KeyboardShortcuts
        var file: URL { directory.appendingPathComponent("keyboard-shortcuts.json") }

        init(document: [String: Any]? = nil) throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let document { try JSONSerialization.data(withJSONObject: document).write(to: directory.appendingPathComponent("keyboard-shortcuts.json")) }
            let menu = menu
            registry = KeyboardShortcuts(mainMenu: { menu }, observesKeyboardLayout: false)
            for (index, id) in CopyCommandTests.ids.enumerated() {
                add(id, key: "c", flags: CopyCommandTests.flags[index], group: "Edit")
            }
            add("closeTab:", key: "w", flags: .command, group: "File")
            add("selectAll:", key: "a", flags: .command, group: "Edit")
            registry.configure(directory: directory)
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        private func add(_ id: String, key: String, flags: NSEvent.ModifierFlags, group: String) {
            let item = NSMenuItem(title: id, action: NSSelectorFromString(id), keyEquivalent: key)
            item.keyEquivalentModifierMask = flags
            menu.addItem(item)
            registry.register(item, group: group)
        }

        func reload() { registry.configure(directory: directory) }

        func savedData() throws -> Data { try Data(contentsOf: file) }
    }

    private static func legacy() -> [String: Any] {
        ["version": 2, "overrides": [
            ids[0]: ["shortcut": ["key": "j", "modifiers": NSEvent.ModifierFlags.command.rawValue]],
            "anotherAction:": ["shortcut": ["key": "c", "modifiers": flags[1].rawValue]]],
         "priorities": [:]]
    }

    @Test @MainActor func closeTabKeepsItsOriginalBindingAndBrowserPriority() throws {
        let fixture = try Fixture()
        #expect(fixture.registry.shortcut(for: "closeTab:") == KeyboardShortcut(key: "w", flags: .command))
        #expect(fixture.registry.priority(for: "closeTab:") == .preferParc)
    }

    @Test @MainActor func selectAllKeepsNativeCommandAAndStaysOutOfSettings() throws {
        let fixture = try Fixture()
        #expect(fixture.registry.shortcut(for: "selectAll:") == KeyboardShortcut(key: "a", flags: .command))
        #expect(!fixture.registry.commands.contains { $0.id == "selectAll:" })
    }

    @Test @MainActor func aWebsiteFirstChoiceSurvivesReload() throws {
        let fixture = try Fixture()
        try fixture.registry.setPriority(.preferWebsites, for: Self.ids[0])
        fixture.reload()
        #expect(fixture.registry.priority(for: Self.ids[0]) == .preferWebsites)
    }

    @Test @MainActor func aUseBothChoiceSurvivesReload() throws {
        let fixture = try Fixture()
        try fixture.registry.setPriority(.useBoth, for: Self.ids[1])
        fixture.reload()
        #expect(fixture.registry.priority(for: Self.ids[1]) == .useBoth)
    }

    @Test @MainActor func aDisabledQuoteStaysDisabledInTheMenu() throws {
        let fixture = try Fixture()
        try fixture.registry.set(nil, for: Self.ids[2])
        fixture.reload()
        #expect(fixture.registry.shortcut(for: Self.ids[2]) == nil)
        #expect(fixture.menu.items[2].keyEquivalent.isEmpty)
    }

    @Test @MainActor func resetAdoptsTheRecoveredPriorityAndChord() throws {
        let fixture = try Fixture()
        try fixture.registry.setPriority(.preferWebsites, for: Self.ids[0])
        try fixture.registry.set(nil, for: Self.ids[2])
        try fixture.registry.reset(Self.ids[0])
        try fixture.registry.reset(Self.ids[2])
        #expect(fixture.registry.priority(for: Self.ids[0]) == .preferParc)
        #expect(fixture.registry.shortcut(for: Self.ids[2])?.flags == Self.flags[2])
    }

    @Test @MainActor func anOldCustomURLChordFollowsTheSameSelector() throws {
        let fixture = try Fixture(document: Self.legacy())
        #expect(fixture.registry.shortcut(for: Self.ids[0])?.key == "j")
        #expect(fixture.registry.priority(for: Self.ids[0]) == .preferWebsites)
    }

    @Test @MainActor func aNewMarkdownCommandGetsTheRecoveredPriority() throws {
        let fixture = try Fixture(document: Self.legacy())
        #expect(fixture.registry.priority(for: Self.ids[1]) == .preferParc)
    }

    @Test @MainActor func anImplicitOldCloseTabPriorityStaysWebsiteFirst() throws {
        let fixture = try Fixture(document: Self.legacy())
        #expect(fixture.registry.priority(for: "closeTab:") == .preferWebsites)
    }

    @Test @MainActor func anExplicitCloseTabPrioritySurvivesRepeatedConfiguration() throws {
        let fixture = try Fixture(document: Self.legacy())
        try fixture.registry.setPriority(.useBoth, for: "closeTab:")
        fixture.reload()
        #expect(fixture.registry.priority(for: "closeTab:") == .useBoth)
    }

    @Test @MainActor func aDisabledCloseTabBindingStaysDisabled() throws {
        let fixture = try Fixture(document: Self.legacy())
        try fixture.registry.set(nil, for: "closeTab:")
        fixture.reload()
        #expect(fixture.registry.shortcut(for: "closeTab:") == nil)
    }

    @Test @MainActor func thePriorityMigrationIsIdempotent() throws {
        let fixture = try Fixture(document: Self.legacy())
        try fixture.registry.set(nil, for: "closeTab:")
        let migrated = try fixture.savedData()
        fixture.reload()
        #expect(try fixture.savedData() == migrated)
    }

    @Test @MainActor func resetAllAppliesTheActualDefaults() throws {
        let fixture = try Fixture(document: Self.legacy())
        try fixture.registry.resetAll()
        #expect(Self.ids.allSatisfy { fixture.registry.priority(for: $0) == .preferParc })
        #expect(fixture.registry.priority(for: "closeTab:") == .preferParc)
    }
}
