import Foundation
import Testing
@testable import ParcCore

@MainActor
struct SpaceManagementTests {
    @MainActor final class Fixture {
        let directory: URL
        let store: BrowserStore
        let original: BrowserSpace

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-space-management-\(UUID())")
            store = try BrowserStore(directory: directory)
            original = store.activeSpace
        }

        deinit { try? FileManager.default.removeItem(at: directory) }
    }

    @Test func aFreshSpaceIsUntitled() throws {
        let f = try Fixture()
        #expect(f.original.title == nil)
        #expect(f.original.name == "Space 1")
    }

    @Test func emptyCreationUsesThePosition() throws {
        let f = try Fixture()
        let secondID = f.store.createSpace(name: "")
        #expect(f.store.activeSpace.id == secondID)
        #expect(f.store.activeSpace.title == nil)
        #expect(f.store.activeSpace.name == "Space 2")
    }

    @Test func legacyPositionalNamesMigrateOnceAndAnUntitledSpaceFollowsItsReorderedPosition() throws {
        let f = try Fixture()
        _ = f.store.createSpace(name: "")
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(f.store.state)) as? [String: Any])
        var spaces = try #require(legacy["spaces"] as? [[String: Any]])
        for index in spaces.indices { spaces[index].removeValue(forKey: "title") }
        legacy["spaces"] = spaces
        let migrated = try JSONDecoder().decode(BrowserState.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(migrated.spaces.allSatisfy { $0.title == nil })
        var shifted = migrated.spaces[1]
        shifted.updateDisplayName(position: 0)
        #expect(shifted.title == nil)
        #expect(shifted.name == "Space 1")
    }

    @Test func aLiteralPlaceholderRemainsAnAuthoredTitleAndSurvivesPersistence() throws {
        let f = try Fixture()
        try f.store.saveSpaceTitle(f.original, title: "Space 1")
        #expect(f.store.state.spaces[0].title == "Space 1")
        let reloaded = try BrowserStore(directory: f.directory)
        #expect(reloaded.state.spaces[0].title == "Space 1")
    }

    @Test func aStaleTitleLeaseFailsAndPreservesTheCompetingTitle() throws {
        let f = try Fixture()
        try f.store.saveSpaceTitle(f.original, title: "Space 1")
        #expect(throws: (any Error).self) { try f.store.saveSpaceTitle(f.original, title: "Overwritten") }
        #expect(f.store.state.spaces[0].title == "Space 1")
    }

    @Test func renamePreservesAnIndependentlyEditedThemeAndAnEmptyRenameRestoresThePlaceholder() throws {
        let f = try Fixture()
        try f.store.saveSpaceTitle(f.original, title: "Space 1")
        let explicit = f.store.state.spaces[0]
        var theme = explicit.theme
        theme.noise = 0.35
        _ = f.store.setSpaceTheme(explicit.id, theme: theme)
        try f.store.saveSpaceTitle(explicit, title: "Work")
        #expect(f.store.state.spaces[0].title == "Work")
        #expect(f.store.state.spaces[0].theme == theme)
        let work = f.store.state.spaces[0]
        try f.store.saveSpaceTitle(work, title: "")
        #expect(f.store.state.spaces[0].title == nil)
        #expect(f.store.state.spaces[0].name == "Space 1")
    }

    @Test func iconMutationsApplyAStaleLeaseFailsAndRemoveResetsTheCustomIcon() throws {
        let f = try Fixture()
        let untitled = f.store.state.spaces[0]
        try f.store.saveSpaceIcon(untitled, icon: .emoji("🌿"))
        #expect(f.store.state.spaces[0].customIcon == .emoji("🌿"))
        #expect(throws: (any Error).self) { try f.store.saveSpaceIcon(untitled, icon: .emoji("🌊")) }
        let iconSpace = f.store.state.spaces[0]
        try f.store.saveSpaceIcon(iconSpace, icon: nil)
        #expect(f.store.state.spaces[0].customIcon == nil)
    }

    @Test func aReassignedProfileRefusesARetainedRename() throws {
        let f = try Fixture()
        var alien = f.store.state.spaces[0]
        alien.profileID = UUID()
        #expect(throws: (any Error).self) { try f.store.saveSpaceTitle(alien, title: "Foreign") }
    }

    @Test func aDiskFailureThrowsAndPublishesNoPartialState() throws {
        let f = try Fixture()
        let snapshot = f.store.state
        try FileManager.default.removeItem(at: f.directory)
        try Data().write(to: f.directory)
        #expect(throws: (any Error).self) { try f.store.saveSpaceTitle(snapshot.spaces[0], title: "Not saved") }
        #expect(f.store.state == snapshot)
        try FileManager.default.removeItem(at: f.directory)
    }
}
