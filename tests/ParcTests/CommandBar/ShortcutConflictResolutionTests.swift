import AppKit
import Testing
@testable import Parc

struct ShortcutConflictResolutionTests {
    @MainActor private final class Target: NSObject, NSMenuItemValidation {
        var delivered = 0
        func validateMenuItem(_ item: NSMenuItem) -> Bool { true }
        @objc func alpha(_ sender: Any?) { delivered += 1 }
        @objc func beta(_ sender: Any?) { delivered += 1 }
        @objc func gamma(_ sender: Any?) { delivered += 1 }
        @objc func copy(_ sender: Any?) { delivered += 1 }
    }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let menu = NSMenu(title: "Test")
        let target = Target()
        let registry: KeyboardShortcuts
        var items: [NSMenuItem] = []
        var file: URL { directory.appendingPathComponent("keyboard-shortcuts.json") }
        let a = KeyboardShortcut(key: "a", flags: [.command, .option])
        let b = KeyboardShortcut(key: "b", flags: [.command, .option])
        let reserved = KeyboardShortcut(key: "c", flags: .command)

        init() throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let root = menu
            registry = KeyboardShortcuts(mainMenu: { root }, observesKeyboardLayout: false)
            registry.configure(directory: directory)
            for (id, key, flags) in [("alpha:", "a", NSEvent.ModifierFlags([.command, .option])), ("beta:", "b", [.command, .option]),
                                     ("gamma:", "b", [.command, .option]), ("copy:", "c", [.command])] {
                let item = NSMenuItem(title: id, action: NSSelectorFromString(id), keyEquivalent: key)
                item.keyEquivalentModifierMask = flags
                item.target = target
                menu.addItem(item)
                registry.register(item, group: "Test")
                items.append(item)
            }
            try registry.setPriority(.useBoth, for: "alpha:")
            try registry.setPriority(.preferParc, for: "beta:")
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        var keyEquivalents: [String] { items.map(\.keyEquivalent) }

        func bFace() throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option], timestamp: 0,
                windowNumber: 0, context: nil, characters: "b", charactersIgnoringModifiers: "b", isARepeat: false, keyCode: 11))
        }

        func blockStorage() throws {
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        }

        func restoreStorage() throws { try FileManager.default.removeItem(at: file) }
    }

    @Test @MainActor func aProposalNamesEveryEffectiveOwnerAndChangesNothing() throws {
        let fixture = try Fixture()
        let saved = try Data(contentsOf: fixture.file)
        let revision = fixture.registry.revision
        let proposal = try #require(try fixture.registry.conflictProposal(for: fixture.b, commandID: "alpha:"))
        #expect(proposal.conflicts.map(\.id) == ["beta:", "gamma:"])
        #expect(try Data(contentsOf: fixture.file) == saved)
        #expect(fixture.registry.revision == revision)
    }

    @Test @MainActor func duplicateDefaultsDisableOnlyTheConflictingMenus() throws {
        let fixture = try Fixture()
        #expect(fixture.keyEquivalents == ["a", "", "", "c"])
    }

    @Test @MainActor func resolvingAssignsTheTargetAndDisablesEveryOwnerTogether() throws {
        let fixture = try Fixture()
        let revision = fixture.registry.revision
        let proposal = try #require(try fixture.registry.conflictProposal(for: fixture.b, commandID: "alpha:"))
        try fixture.registry.resolveConflict(proposal)
        #expect(fixture.registry.shortcut(for: "alpha:") == fixture.b)
        #expect(fixture.registry.shortcut(for: "beta:") == nil)
        #expect(fixture.registry.shortcut(for: "gamma:") == nil)
        #expect(fixture.keyEquivalents == ["b", "", "", "c"])
        #expect(fixture.registry.revision == revision + 1)
        #expect(fixture.registry.priority(for: "alpha:") == .useBoth)
        #expect(fixture.registry.priority(for: "beta:") == .preferParc)
    }

    @Test @MainActor func aResolutionAndItsDisabledOwnersSurviveReload() throws {
        let fixture = try Fixture()
        try fixture.registry.resolveConflict(try #require(try fixture.registry.conflictProposal(for: fixture.b, commandID: "alpha:")))
        fixture.registry.configure(directory: fixture.directory)
        #expect(fixture.registry.shortcut(for: "alpha:") == fixture.b)
        #expect(fixture.registry.shortcut(for: "beta:") == nil)
    }

    @Test @MainActor func aStaleProposalIsRefused() throws {
        let fixture = try Fixture()
        let proposal = try #require(try fixture.registry.conflictProposal(for: fixture.b, commandID: "alpha:"))
        try fixture.registry.resolveConflict(proposal)
        #expect(throws: (any Error).self) { try fixture.registry.resolveConflict(proposal) }
    }

    @Test(arguments: [("c", "alpha:"), ("a", "copy:")])
    @MainActor func protectedEditingChordsAndTargetsAreRefused(key: String, command: String) throws {
        let fixture = try Fixture()
        let chord = key == "c" ? fixture.reserved : fixture.a
        #expect(throws: (any Error).self) { _ = try fixture.registry.conflictProposal(for: chord, commandID: command) }
    }

    @Test @MainActor func anUncontestedChordNeedsNoResolution() throws {
        let fixture = try Fixture()
        #expect(try fixture.registry.conflictProposal(for: fixture.a, commandID: "alpha:") == nil)
    }

    @Test @MainActor func aResetResolutionRestoresTheDefaultBindingAndKeepsTheDisplacedPriority() throws {
        let fixture = try Fixture()
        try fixture.registry.set(fixture.a, for: "beta:")
        let reset = try #require(try fixture.registry.conflictProposal(for: fixture.a, commandID: "alpha:", resetsPriority: true))
        try fixture.registry.resolveConflict(reset)
        #expect(fixture.registry.shortcut(for: "alpha:") == fixture.a)
        #expect(!fixture.registry.isCustomized("alpha:"))
        #expect(fixture.registry.priority(for: "beta:") == .preferParc)
    }

    @Test @MainActor func aFailedWriteLeavesEveryBindingAndTheRevisionAlone() throws {
        let fixture = try Fixture()
        let blocked = try #require(try fixture.registry.conflictProposal(for: fixture.a, commandID: "gamma:"))
        let revision = fixture.registry.revision
        try fixture.blockStorage()
        #expect(throws: (any Error).self) { try fixture.registry.resolveConflict(blocked) }
        #expect(fixture.registry.revision == revision)
        #expect(fixture.registry.shortcut(for: "alpha:") == fixture.a)
        #expect(fixture.registry.shortcut(for: "gamma:") == nil)
        #expect(fixture.keyEquivalents == ["a", "", "", "c"])
    }

    @Test @MainActor func theSameProposalRetriesAfterAStorageFailure() throws {
        let fixture = try Fixture()
        let blocked = try #require(try fixture.registry.conflictProposal(for: fixture.a, commandID: "gamma:"))
        try fixture.blockStorage()
        #expect(throws: (any Error).self) { try fixture.registry.resolveConflict(blocked) }
        try fixture.restoreStorage()
        try fixture.registry.resolveConflict(blocked)
        #expect(fixture.registry.shortcut(for: "gamma:") == fixture.a)
    }

    @Test @MainActor func resetAllRestoresShippedBindingsAndClearsEveryOverride() throws {
        let fixture = try Fixture()
        try fixture.registry.resolveConflict(try #require(try fixture.registry.conflictProposal(for: fixture.b, commandID: "alpha:")))
        try fixture.registry.resetAll()
        #expect(fixture.registry.shortcut(for: "alpha:") == fixture.a)
        #expect(fixture.registry.shortcut(for: "beta:") == fixture.b)
        #expect(!fixture.registry.hasOverrides)
    }

    @MainActor private func clashing(_ fixture: Fixture) throws -> NSMenuItem {
        try fixture.registry.set(nil, for: "gamma:")
        let prior = try #require(fixture.registry.nativeCommand(for: try fixture.bFace(), editable: false))
        try fixture.registry.set(fixture.b, for: "alpha:")
        return try #require(prior.item)
    }

    @Test @MainActor func anUncontestedBindingReachesItsNativeMenuItem() throws {
        let fixture = try Fixture()
        try fixture.registry.set(nil, for: "gamma:")
        #expect(fixture.registry.nativeCommand(for: try fixture.bFace(), editable: false)?.item === fixture.items[1])
    }

    @Test @MainActor func aSavedConflictClearsBothMenusAndMarksBothCommands() throws {
        let fixture = try Fixture()
        _ = try clashing(fixture)
        #expect(fixture.registry.isConflicting("alpha:"))
        #expect(fixture.registry.isConflicting("beta:"))
        #expect(fixture.items[0].keyEquivalent.isEmpty && fixture.items[1].keyEquivalent.isEmpty)
    }

    @Test @MainActor func aSavedConflictCannotBeBypassedByTheNativeQueryAPriorCommandOrAppKit() throws {
        let fixture = try Fixture()
        try fixture.registry.set(nil, for: "gamma:")
        let event = try fixture.bFace()
        let prior = try #require(fixture.registry.nativeCommand(for: event, editable: false))
        try fixture.registry.set(fixture.b, for: "alpha:")
        #expect(fixture.registry.nativeCommand(for: event, editable: false) == nil)
        #expect(!fixture.registry.perform(prior, event: event, editable: false))
        #expect(!fixture.menu.performKeyEquivalent(with: event))
        #expect(fixture.target.delivered == 0)
    }

    @Test @MainActor func conflictingCommandsStayDiscoverableWithoutAnActiveKeyEquivalent() throws {
        let fixture = try Fixture()
        _ = try clashing(fixture)
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let commands = fixture.registry.menuCommands(in: window).filter { ["alpha:", "beta:"].contains($0.id) }
        #expect(commands.count == 2)
        #expect(commands.allSatisfy { $0.shortcut == nil })
    }

    @Test @MainActor func aConflictPersistsAcrossConfigureWithoutBeingRewritten() throws {
        let fixture = try Fixture()
        _ = try clashing(fixture)
        let data = try Data(contentsOf: fixture.file)
        fixture.registry.configure(directory: fixture.directory)
        #expect(try Data(contentsOf: fixture.file) == data)
        #expect(fixture.registry.isConflicting("alpha:"))
        #expect(fixture.registry.isConflicting("beta:"))
    }

    @Test @MainActor func threeOwnersExposeTheExactTwoOtherAssignments() throws {
        let fixture = try Fixture()
        _ = try clashing(fixture)
        try fixture.registry.set(fixture.b, for: "gamma:")
        #expect(fixture.registry.conflictingCommands(for: "alpha:").map(\.id) == ["beta:", "gamma:"])
    }

    @Test @MainActor func aFailedDurableClearPublishesNoPartialResolution() throws {
        let fixture = try Fixture()
        _ = try clashing(fixture)
        try fixture.registry.set(fixture.b, for: "gamma:")
        let revision = fixture.registry.revision
        try fixture.blockStorage()
        #expect(throws: (any Error).self) { try fixture.registry.set(nil, for: "alpha:") }
        #expect(fixture.registry.revision == revision)
        #expect(fixture.registry.isConflicting("alpha:"))
        #expect(fixture.registry.nativeCommand(for: try fixture.bFace(), editable: false) == nil)
    }

    @Test @MainActor func clearingTheFinalConflictRestoresTheSurvivingNativeOwner() throws {
        let fixture = try Fixture()
        _ = try clashing(fixture)
        try fixture.registry.set(fixture.b, for: "gamma:")
        try fixture.registry.set(nil, for: "alpha:")
        #expect(fixture.registry.isConflicting("beta:") && fixture.registry.isConflicting("gamma:"))
        try fixture.registry.set(nil, for: "gamma:")
        #expect(!fixture.registry.isConflicting("beta:"))
        #expect(fixture.registry.nativeCommand(for: try fixture.bFace(), editable: false)?.item === fixture.items[1])
        #expect(fixture.items[1].keyEquivalent == "b")
    }

    @Test @MainActor func aLegacyCollisionWithNativeCopyStaysSavedButCannotOverrideEditing() throws {
        let fixture = try Fixture()
        let data = try Data(contentsOf: fixture.file)
        var document = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var overrides = document["overrides"] as? [String: Any] ?? [:]
        overrides["alpha:"] = ["shortcut": ["key": "c", "modifiers": NSEvent.ModifierFlags.command.rawValue]]
        document["overrides"] = overrides
        try JSONSerialization.data(withJSONObject: document).write(to: fixture.file)
        fixture.registry.configure(directory: fixture.directory)
        #expect(fixture.registry.activeShortcut(for: "alpha:") == nil)
        #expect(fixture.registry.shortcut(for: "alpha:") == fixture.reserved)
        #expect(fixture.registry.activeShortcut(for: "copy:") == fixture.reserved)
        #expect(fixture.items[3].keyEquivalent == "c")
    }
}
