import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit

struct CreationDefaultTests {
    @MainActor private final class Fixture {
        let registry: KeyboardShortcuts
        let menu: NSMenu
        let delegate = AppDelegate()

        init() {
            _ = NSApplication.shared
            var root: NSMenu?
            let registry = KeyboardShortcuts(mainMenu: { root }, observesKeyboardLayout: false)
            self.registry = registry
            menu = delegate.buildMenus(shortcuts: registry, install: false, initialSpaces: BrowserState.initial().spaces)
            root = menu
        }
    }

    @Test(arguments: [
        ("createNote:", "N", NSEvent.ModifierFlags.control, true),
        ("createNoteInSplit:", "n", NSEvent.ModifierFlags([.control, .option]), true),
        ("createEasel:", "E", NSEvent.ModifierFlags.control, false),
        ("capturePage:", "2", NSEvent.ModifierFlags([.command, .shift]), false),
    ])
    @MainActor func aCreationCommandHasItsOriginalDefault(id: String, key: String, flags: NSEvent.ModifierFlags,
                                                          offersBoth: Bool) {
        let fixture = Fixture()
        let chord = KeyboardShortcut(key: key, flags: flags)
        #expect(fixture.registry.shortcut(for: id) == chord)
        #expect(fixture.registry.commands.first { $0.id == id }?.defaultShortcut == chord)
        #expect(fixture.registry.priority(for: id) == (offersBoth ? .useBoth : .preferWebsites))
        #expect(fixture.registry.supportsPriority(id))
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func loadingOldSettingsKeepsExplicitCreationChoices(version: Int) throws {
        let fixture = Fixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let chord = KeyboardShortcut(key: "k", flags: [.command, .control])
        let overrides: [String: [String: Any]] = [
            "createNote:": ["shortcut": ["key": chord.key, "modifiers": chord.modifiers]],
            "createEasel:": [:],
        ]
        let file = directory.appendingPathComponent("keyboard-shortcuts.json")
        let legacy: [String: Any] = ["version": version, "overrides": overrides,
                                     "priorities": ["createNote:": "preferParc"]]
        try JSONSerialization.data(withJSONObject: legacy).write(to: file)
        fixture.registry.configure(directory: directory)
        #expect(fixture.registry.loadError == nil)
        #expect(fixture.registry.shortcut(for: "createNote:") == chord)
        #expect(fixture.registry.shortcut(for: "createEasel:") == nil)
        #expect(fixture.registry.shortcut(for: "capturePage:") == nil)
        #expect(fixture.registry.priority(for: "createNote:") == .preferParc)
    }

    @MainActor private final class Target: NSObject, NSMenuItemValidation {
        func validateMenuItem(_ item: NSMenuItem) -> Bool { true }
        @objc func createNote(_ sender: Any?) {}
        @objc func createNoteInSplit(_ sender: Any?) {}
        @objc func createEasel(_ sender: Any?) {}
        @objc func capturePage(_ sender: Any?) {}
        @objc func unrelated(_ sender: Any?) {}
    }

    @MainActor private final class Bench {
        static let rows: [(String, String, KeyboardShortcut)] = [
            ("createNote:", "New Note", .init(key: "N", flags: .control)),
            ("createNoteInSplit:", "New Note in Split View", .init(key: "n", flags: [.control, .option])),
            ("createEasel:", "New Easel", .init(key: "E", flags: .control)),
            ("capturePage:", "Capture Portion…", .init(key: "2", flags: [.command, .shift])),
        ]
        let directory: URL
        let file: URL
        let target = Target()
        let menu = NSMenu(title: "File")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [], backing: .buffered, defer: false)
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
            for (id, title, _) in Self.rows {
                let item = NSMenuItem(title: title, action: NSSelectorFromString(id), keyEquivalent: "")
                item.target = target
                menu.addItem(item)
                items[id] = item
                registry.register(item, group: "File")
            }
            return registry
        }

        func write(version: Int, custom: KeyboardShortcut) throws {
            let legacy: [String: Any] = ["version": version, "developerDefaults": 1,
                "selectionCommandDefaults": 1, "menuPriorityDefaults": 1,
                "overrides": ["createNote:": ["shortcut": ["key": custom.key, "modifiers": custom.modifiers]],
                              "createEasel:": [:],
                              "unrelated:": ["shortcut": ["key": "2", "modifiers": KeyboardShortcut(key: "2", flags: [.command, .shift]).modifiers]]],
                "priorities": ["createNote:": "preferParc", "createEasel:": "useBoth", "unrelated:": "useBoth"]]
            try JSONSerialization.data(withJSONObject: legacy).write(to: file)
        }
    }

    private static let custom = KeyboardShortcut(key: "k", flags: [.command, .control])

    @Test(arguments: [0, 1, 2, 3])
    @MainActor func aFreshRegistryPutsEachOriginalChordOnItsRealMenuItem(index: Int) throws {
        let bench = try Bench()
        let registry = bench.registry()
        let (id, _, chord) = Bench.rows[index]
        #expect(bench.items[id]?.keyEquivalent == chord.key)
        #expect(bench.items[id]?.keyEquivalentModifierMask == chord.flags)
        #expect(registry.menuCommands(in: bench.window).first { $0.id == id }?.shortcut == chord)
    }

    @Test @MainActor func readingFreshDefaultsNeverWritesTheSettingsFile() throws {
        let bench = try Bench()
        let registry = bench.registry()
        _ = registry.menuCommands(in: bench.window)
        _ = registry.commands
        #expect(!FileManager.default.fileExists(atPath: bench.file.path))
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func migratingOldSettingsLeavesAmbiguousCreationCommandsUnboundAndKeepsExplicitPriorities(version: Int) throws {
        let bench = try Bench()
        try bench.write(version: version, custom: Self.custom)
        let registry = bench.registry()
        #expect(registry.shortcut(for: "createNoteInSplit:") == nil)
        #expect(registry.shortcut(for: "capturePage:") == nil)
        #expect(bench.items["capturePage:"]?.keyEquivalent.isEmpty == true)
        #expect(registry.priority(for: "createEasel:") == .useBoth)
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func migrationPersistsItsMarkerKeepsUnknownOverridesAndIsByteIdempotent(version: Int) throws {
        let bench = try Bench()
        try bench.write(version: version, custom: Self.custom)
        let registry = bench.registry()
        let migrated = try Data(contentsOf: bench.file)
        let value = try #require(JSONSerialization.jsonObject(with: migrated) as? [String: Any])
        #expect(value["creationShortcutDefaults"] as? Int == 1)
        let saved = try #require(value["overrides"] as? [String: Any])
        #expect(saved["unrelated:"] != nil)
        registry.configure(directory: bench.directory)
        #expect(try Data(contentsOf: bench.file) == migrated)
    }

    @Test(arguments: [1, 2, 3])
    @MainActor func resettingAfterMigrationAdoptsOriginalChordsAndRecoveredPriority(version: Int) throws {
        let bench = try Bench()
        try bench.write(version: version, custom: Self.custom)
        let registry = bench.registry()
        let other = NSMenuItem(title: "Unrelated", action: NSSelectorFromString("unrelated:"), keyEquivalent: "")
        other.target = bench.target
        registry.register(other, group: "Other")
        try registry.reset("capturePage:")
        #expect(registry.isConflicting("capturePage:"))
        #expect(registry.activeShortcut(for: "capturePage:") == nil)
        try registry.reset("createNoteInSplit:")
        #expect(registry.shortcut(for: "createNoteInSplit:") == Bench.rows[1].2)
        registry.configure(directory: bench.directory)
        #expect(registry.shortcut(for: "createNoteInSplit:") == Bench.rows[1].2)
        try registry.resetAll()
        for (id, _, chord) in Bench.rows { #expect(registry.shortcut(for: id) == chord) }
        #expect(registry.priority(for: "createNote:") == .useBoth)
    }

    @Test @MainActor func anExplicitClearPersistsAfterDefaultsExist() throws {
        let bench = try Bench()
        let registry = bench.registry()
        try registry.set(nil, for: "createNote:")
        registry.configure(directory: bench.directory)
        #expect(registry.shortcut(for: "createNote:") == nil)
    }

    @Test @MainActor func aCustomChordAndPrioritySurviveReload() throws {
        let bench = try Bench()
        let registry = bench.registry()
        try registry.set(Self.custom, for: "createEasel:")
        try registry.setPriority(.preferParc, for: "createEasel:")
        registry.configure(directory: bench.directory)
        #expect(registry.shortcut(for: "createEasel:") == Self.custom)
        #expect(registry.priority(for: "createEasel:") == .preferParc)
    }

    @Test @MainActor func malformedSettingsAreReportedAndNeverReplaced() throws {
        let bench = try Bench()
        let registry = bench.registry()
        let corrupt = Data("broken shortcuts".utf8)
        try corrupt.write(to: bench.file)
        registry.configure(directory: bench.directory)
        #expect(registry.loadError != nil)
        #expect(try Data(contentsOf: bench.file) == corrupt)
    }
}
