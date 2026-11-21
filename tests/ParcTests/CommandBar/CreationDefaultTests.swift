import AppKit
import Testing
@testable import Parc
@testable import ParcCore

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
}
