import AppKit
import Testing
@testable import Parc
@testable import ParcKit

struct ShortcutPersistSkipTests {
    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let registry = KeyboardShortcuts(mainMenu: { nil }, observesKeyboardLayout: false)
        let item = NSMenuItem(title: "Archive Tab", action: NSSelectorFromString("closeTab:"), keyEquivalent: "w")
        let original = KeyboardShortcut(key: "e", flags: [.command, .option])
        var file: URL { directory.appendingPathComponent("keyboard-shortcuts.json") }

        init() throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            registry.configure(directory: directory)
            item.keyEquivalentModifierMask = .command
            registry.register(item, group: "File")
            try registry.set(original, for: "closeTab:")
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func fileIdentity() throws -> UInt64 {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            return try #require((attributes[.systemFileNumber] as? NSNumber)?.uint64Value)
        }
    }

    @Test @MainActor func anIdenticalBindingDoesNotPublishAChange() throws {
        let fixture = try Fixture()
        let revision = fixture.registry.revision
        try fixture.registry.set(fixture.original, for: "closeTab:")
        #expect(fixture.registry.revision == revision)
    }

    @Test @MainActor func anIdenticalBindingDoesNotReplaceTheSavedFile() throws {
        let fixture = try Fixture()
        let inode = try fixture.fileIdentity()
        let saved = try Data(contentsOf: fixture.file)
        try fixture.registry.set(fixture.original, for: "closeTab:")
        #expect(try fixture.fileIdentity() == inode)
        #expect(try Data(contentsOf: fixture.file) == saved)
    }

    @Test @MainActor func aChangedBindingIsPublishedAndPersisted() throws {
        let fixture = try Fixture()
        let originalRevision = fixture.registry.revision
        let new = KeyboardShortcut(key: "r", flags: [.command, .option])
        try fixture.registry.set(new, for: "closeTab:")
        #expect(fixture.registry.revision > originalRevision)
        let saved = KeyboardShortcuts(mainMenu: { nil }, observesKeyboardLayout: false)
        saved.configure(directory: fixture.directory)
        #expect(saved.shortcut(for: "closeTab:") == new)
    }
}
