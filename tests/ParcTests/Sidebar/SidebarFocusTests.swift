import AppKit
import Testing
@testable import Parc

@MainActor
struct SidebarFocusTests {
    private let chord = KeyboardShortcut(key: " ", flags: [.control])
    private let custom = KeyboardShortcut(key: "s", flags: [.command, .option])

    @MainActor private final class Registry {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var file: URL { directory.appendingPathComponent("keyboard-shortcuts.json") }
        let registry = KeyboardShortcuts(mainMenu: { nil }, observesKeyboardLayout: false)
        let reveal = NSMenuItem(title: "Reveal Current Tab", action: NSSelectorFromString("focusSidebar:"), keyEquivalent: " ")
        let other = NSMenuItem(title: "Other", action: NSSelectorFromString("other:"), keyEquivalent: "")

        init() throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            reveal.keyEquivalentModifierMask = .control
            registry.register(reveal, group: "Tabs")
            registry.register(other, group: "Tabs")
            registry.configure(directory: directory)
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func encoded(_ chord: KeyboardShortcut?) -> [String: Any] {
            guard let chord else { return [:] }
            return ["shortcut": ["key": chord.key, "modifiers": chord.modifiers]]
        }

        func write(_ overrides: [String: Any]) throws {
            try JSONSerialization.data(withJSONObject: ["version": 2, "overrides": overrides, "priorities": ["other:": "preferParc"]]).write(to: file)
            registry.configure(directory: directory)
        }
    }

    @Test func aFreshInstallationReceivesTheRecoveredDefault() throws {
        let fixture = try Registry()
        #expect(fixture.registry.shortcut(for: "focusSidebar:") == chord)
        #expect(fixture.registry.activeShortcut(for: "focusSidebar:") == chord)
    }

    @Test func theDefaultPassesTheOriginalRegistryValidation() {
        #expect(chord.isValid)
        #expect(!chord.isReserved)
    }

    @Test func aSavedCustomChordIsReadable() throws {
        let fixture = try Registry()
        try fixture.write(["other:": fixture.encoded(chord)])
        #expect(fixture.registry.loadError == nil)
    }

    @Test func theNewDefaultDoesNotStealASavedChord() throws {
        let fixture = try Registry()
        try fixture.write(["other:": fixture.encoded(chord)])
        #expect(fixture.registry.shortcut(for: "focusSidebar:") == nil)
        #expect(fixture.registry.activeShortcut(for: "focusSidebar:") == nil)
    }

    @Test func theOriginalCustomOwnerRemains() throws {
        let fixture = try Registry()
        try fixture.write(["other:": fixture.encoded(chord)])
        #expect(fixture.registry.shortcut(for: "other:") == chord)
        #expect(fixture.registry.priority(for: "other:") == .preferParc)
    }

    @Test func theActualMenuBindingFollowsTheOriginalOwner() throws {
        let fixture = try Registry()
        try fixture.write(["other:": fixture.encoded(chord)])
        #expect(fixture.reveal.keyEquivalent.isEmpty)
        #expect(fixture.other.keyEquivalent == " ")
    }

    @Test func savedConflictProtectionIsIdempotent() throws {
        let fixture = try Registry()
        try fixture.write(["other:": fixture.encoded(chord)])
        let saved = try Data(contentsOf: fixture.file)
        fixture.registry.configure(directory: fixture.directory)
        #expect(try Data(contentsOf: fixture.file) == saved)
    }

    @Test func anExplicitResetExposesTheConflictAndSuppressesBothMenuBindings() throws {
        let fixture = try Registry()
        try fixture.write(["other:": fixture.encoded(chord)])
        try fixture.registry.reset("focusSidebar:")
        #expect(fixture.registry.isConflicting("focusSidebar:"))
        #expect(fixture.reveal.keyEquivalent.isEmpty)
        #expect(fixture.other.keyEquivalent.isEmpty)
    }

    @Test func anExplicitCustomFocusBindingSurvives() throws {
        let fixture = try Registry()
        try fixture.write(["focusSidebar:": fixture.encoded(custom), "other:": fixture.encoded(chord)])
        #expect(fixture.registry.shortcut(for: "focusSidebar:") == custom)
    }

    @Test func anExplicitlyDisabledFocusCommandSurvives() throws {
        let fixture = try Registry()
        try fixture.write(["focusSidebar:": fixture.encoded(nil)])
        #expect(fixture.registry.shortcut(for: "focusSidebar:") == nil)
    }

    @Test func anUncontestedExistingFileReceivesTheDefault() throws {
        let fixture = try Registry()
        try fixture.write([:])
        #expect(fixture.registry.shortcut(for: "focusSidebar:") == chord)
        #expect(fixture.registry.activeShortcut(for: "focusSidebar:") == chord)
    }

    @Test func explicitResetAllRestoresTheCurrentDefault() throws {
        let fixture = try Registry()
        try fixture.write(["focusSidebar:": fixture.encoded(custom)])
        try fixture.registry.resetAll()
        #expect(fixture.registry.shortcut(for: "focusSidebar:") == chord)
    }
}
