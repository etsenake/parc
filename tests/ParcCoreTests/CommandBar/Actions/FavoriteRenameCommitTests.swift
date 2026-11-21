import Foundation
import Testing
@testable import ParcCore

@MainActor
struct FavoriteRenameCommitTests {
    @MainActor struct Fixture {
        let directory = CommandBarFixtures.temporaryDirectory("rename-action")
        let store: BrowserStore
        let id: UUID

        init() throws {
            store = try BrowserStore(directory: directory)
            id = store.openResolvedURL(URL(string: "https://example.test/original")!)
            store.setKind(id, .favorite)
        }

        var favorite: BrowserTab { store.state.tabs.first { $0.id == id }! }

        func prepared() throws -> CommandBarFavoriteRenameAction {
            try #require(CommandBarFavoriteRenameAction(state: store.state, spaceID: store.state.activeSpaceID,
                                                       profileID: favorite.profileID, selectedTabIDs: [id]))
        }
    }

    @Test func savingTheTitleChangesOnlyTheOriginalTitle() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let action = try fixture.prepared()
        let before = fixture.store.state
        let exact = try #require(action.currentTab(in: before, spaceID: before.activeSpaceID,
                                                   profileID: fixture.favorite.profileID, selectedTabIDs: [fixture.id]))
        _ = try fixture.store.saveFavoriteTitle(exact, title: "Research 🪐")
        var expected = before
        expected.tabs[expected.tabs.firstIndex { $0.id == fixture.id }!].customTitle = "Research 🪐"
        #expect(fixture.store.state == expected)
    }
}
