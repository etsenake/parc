import AppKit
import Testing
@testable import Parc

struct CommandShortcutMigrationTests {
    enum Command: CaseIterable {
        case clearToday, closeWindow, fullscreen, findNext, findPrevious

        var id: String {
            switch self {
            case .clearToday: "clearToday:"
            case .closeWindow: "closeWindow:"
            case .fullscreen: "toggleFullScreen:"
            case .findNext: "findNext:"
            case .findPrevious: "findPrevious:"
            }
        }

        var chord: KeyboardShortcut {
            switch self {
            case .clearToday: .init(key: "k", flags: [.command, .shift])
            case .closeWindow: .init(key: "w", flags: [.command, .shift])
            case .fullscreen: .init(key: "f", flags: [.command, .control])
            case .findNext: .init(key: "g", flags: .command)
            case .findPrevious: .init(key: "g", flags: [.command, .shift])
            }
        }

        var marker: String {
            switch self {
            case .clearToday: "clearTodayShortcutDefaults"
            case .closeWindow: "closeWindowShortcutDefaults"
            case .fullscreen: "fullscreenShortcutDefaults"
            case .findNext, .findPrevious: "findShortcutDefaults"
            }
        }
    }

    @MainActor private final class Target: NSObject, NSMenuItemValidation {
        var available = true
        @objc func clearToday(_ sender: NSMenuItem) {}
        @objc func closeWindow(_ sender: NSMenuItem) {}
        @objc func toggleFullScreen(_ sender: NSMenuItem) {}
        @objc func findNext(_ sender: NSMenuItem) {}
        @objc func findPrevious(_ sender: NSMenuItem) {}
        @objc func custom(_ sender: NSMenuItem) {}
        func validateMenuItem(_ item: NSMenuItem) -> Bool { available }
    }

    @MainActor private final class Fixture {
        let menu = NSMenu(title: "Test Commands")
        let item: NSMenuItem
        let target = Target()
        let registry: KeyboardShortcuts
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var file: URL { directory.appendingPathComponent("keyboard-shortcuts.json") }

        init(_ command: Command) throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let root = menu
            registry = KeyboardShortcuts(mainMenu: { root }, observesKeyboardLayout: false)
            item = NSMenuItem(title: command.id, action: NSSelectorFromString(command.id), keyEquivalent: command.chord.key)
            item.keyEquivalentModifierMask = command.chord.flags
            item.target = target
            let custom = NSMenuItem(title: "Custom", action: #selector(Target.custom(_:)), keyEquivalent: "")
            custom.target = target
            menu.addItem(item)
            menu.addItem(custom)
            registry.register(item, group: menu.title)
            registry.register(custom, group: menu.title)
            registry.configure(directory: directory)
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func loadLegacy(version: Int, bindings: [String: KeyboardShortcut], priorities: [String: String] = [:]) throws {
            let overrides = bindings.mapValues { ["shortcut": ["key": $0.key, "modifiers": $0.modifiers] as [String: Any]] }
            let document: [String: Any] = ["version": version, "overrides": overrides, "priorities": priorities]
            try JSONSerialization.data(withJSONObject: document).write(to: file)
            registry.configure(directory: directory)
        }

        func event(for command: Command, repeating: Bool = false) throws -> NSEvent {
            let chord = command.chord
            let characters = chord.flags.contains(.shift) ? chord.key.uppercased() : chord.key
            let keyCodes: [String: UInt16] = ["w": 13, "f": 3, "k": 40, "g": 5]
            let keyCode = try #require(keyCodes[chord.key])
            return try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: chord.flags, timestamp: 0,
                windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: repeating, keyCode: keyCode))
        }
    }

    @Test(arguments: Command.allCases, [1, 2, 3])
    @MainActor func newDefaultsDoNotDisplaceSavedCustomChords(command: Command, version: Int) throws {
        let fixture = try Fixture(command)
        try fixture.loadLegacy(version: version, bindings: ["custom:": command.chord], priorities: ["custom:": "useBoth"])
        #expect(fixture.registry.shortcut(for: "custom:") == command.chord)
        #expect(fixture.registry.priority(for: "custom:") == .useBoth)
        #expect(fixture.registry.shortcut(for: command.id) == nil)
        #expect(fixture.item.keyEquivalent.isEmpty)
    }

    @Test(arguments: Command.allCases)
    @MainActor func readingTheMigratedDocumentAgainKeepsItsBytes(command: Command) throws {
        let fixture = try Fixture(command)
        try fixture.loadLegacy(version: 1, bindings: [:])
        let bytes = try Data(contentsOf: fixture.file)
        let document = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(document[command.marker] as? Int == 1)
        fixture.registry.configure(directory: fixture.directory)
        #expect(try Data(contentsOf: fixture.file) == bytes)
    }

    @Test(arguments: Command.allCases)
    @MainActor func aResetShowsTheConflictWithAnOccupiedDefault(command: Command) throws {
        let fixture = try Fixture(command)
        try fixture.loadLegacy(version: 3, bindings: ["custom:": command.chord])
        try fixture.registry.reset(command.id)
        #expect(fixture.registry.isConflicting(command.id))
        #expect(fixture.registry.activeShortcut(for: command.id) == nil)
    }

    @Test(arguments: Command.allCases)
    @MainActor func aResetRestoresAnUnoccupiedDefault(command: Command) throws {
        let fixture = try Fixture(command)
        try fixture.registry.set(nil, for: command.id)
        try fixture.registry.reset(command.id)
        #expect(fixture.registry.activeShortcut(for: command.id) == command.chord)
    }

    @Test(arguments: Command.allCases)
    @MainActor func disablingACommandAndChoosingAPrioritySurvivesLoad(command: Command) throws {
        let fixture = try Fixture(command)
        try fixture.registry.setPriority(.preferParc, for: command.id)
        try fixture.registry.set(nil, for: command.id)
        fixture.registry.configure(directory: fixture.directory)
        #expect(fixture.registry.shortcut(for: command.id) == nil)
        #expect(fixture.registry.priority(for: command.id) == .preferParc)
    }

    @Test(arguments: Command.allCases)
    @MainActor func legacySettingsCanAlreadyContainACustomChord(command: Command) throws {
        let fixture = try Fixture(command)
        let custom = KeyboardShortcut(key: "j", flags: [.command, .control])
        try fixture.loadLegacy(version: 3, bindings: [command.id: custom], priorities: [command.id: "useBoth"])
        #expect(fixture.registry.shortcut(for: command.id) == custom)
        #expect(fixture.registry.priority(for: command.id) == .useBoth)
    }

    @Test(arguments: Command.allCases)
    @MainActor func anUnoccupiedDefaultIsInstalledInLegacySettings(command: Command) throws {
        let fixture = try Fixture(command)
        try fixture.loadLegacy(version: 3, bindings: [:])
        #expect(fixture.registry.shortcut(for: command.id) == command.chord)
    }

    @Test(arguments: Command.allCases)
    @MainActor func aNativeChordRetainsItsOriginalMenuItem(command: Command) throws {
        let fixture = try Fixture(command)
        let event = try fixture.event(for: command)
        #expect(fixture.registry.nativeCommand(for: event, editable: true)?.item === fixture.item)
    }

    @Test(arguments: Command.allCases)
    @MainActor func repeatingACommandDoesNotIssueAnotherRequest(command: Command) throws {
        let fixture = try Fixture(command)
        let event = try fixture.event(for: command, repeating: true)
        #expect(fixture.registry.nativeCommand(for: event, editable: false) == nil)
    }

    @Test(arguments: Command.allCases)
    @MainActor func aNativeChordRefusesAnUnavailableTarget(command: Command) throws {
        let fixture = try Fixture(command)
        fixture.target.available = false
        let event = try fixture.event(for: command)
        #expect(fixture.registry.nativeCommand(for: event, editable: false) == nil)
    }

    @Test @MainActor func corruptShortcutSettingsStayOnDisk() throws {
        let fixture = try Fixture(.closeWindow)
        let corrupt = Data("bad shortcuts".utf8)
        try corrupt.write(to: fixture.file)
        fixture.registry.configure(directory: fixture.directory)
        #expect(fixture.registry.loadError != nil)
        #expect(try Data(contentsOf: fixture.file) == corrupt)
    }
}
