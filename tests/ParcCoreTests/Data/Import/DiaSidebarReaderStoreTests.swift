import Foundation
import Testing
@testable import ParcCore

struct DiaSidebarReaderStoreTests {
    private typealias Fixture = DiaSidebarReaderFixture

    private struct Imported {
        let state: BrowserState
        let standardID: UUID
        let work: BrowserSpace
        let play: BrowserSpace
    }

    @MainActor private func withImport(_ body: (Imported) throws -> Void) throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let importedAt = Date(timeIntervalSince1970: 1_793_000_000)
            let sidebar = try Fixture.read(in: directory.appendingPathComponent("dia", isDirectory: true))
            let store = try BrowserStore(directory: directory.appendingPathComponent("store", isDirectory: true),
                                         now: { importedAt })
            let standardID = store.state.profiles[0].id
            let before = store.state.spaces.count
            _ = try store.importSidebar(sidebar, profiles: [(.standard, "Default")], standardProfileID: standardID)
            let created = Array(store.state.spaces.dropFirst(before))
            try #require(created.count == 2)
            try body(Imported(state: store.state, standardID: standardID, work: created[0], play: created[1]))
        }
    }

    @MainActor @Test func theTwoSpacesAreCreatedForTheStandardProfile() throws {
        try withImport { imported in
            #expect(imported.work.title == "Work" && imported.play.title == "Play")
            #expect(imported.work.profileID == imported.standardID && imported.play.profileID == imported.standardID)
        }
    }

    @MainActor @Test func nestedFoldersKeepTheirNamesAndParents() throws {
        try withImport { imported in
            let folders = imported.state.folders.filter { $0.spaceID == imported.work.id }
            let docs = try #require(folders.first { $0.name == "Docs" })
            let specs = try #require(folders.first { $0.name == "Specs" })
            #expect(docs.parentID == nil && specs.parentID == docs.id)
            #expect(docs.isExpanded && specs.isExpanded)
            let spec = try #require(imported.state.tabs.first { $0.savedURL == "https://spec.example.com/" })
            #expect(spec.folderID == specs.id && spec.kind == .pinned && spec.customTitle == "My Spec")
        }
    }

    @MainActor @Test func theSplitKeepsItsPanesAndWidthsAndPinnedOrderIsDias() throws {
        try withImport { imported in
            let state = imported.state
            let docs = try #require(state.folders.first { $0.spaceID == imported.work.id && $0.name == "Docs" })
            let groups = SidebarSplitItems.groups(in: state, spaceID: imported.work.id)
            let split = try #require(groups.first)
            #expect(groups.count == 1 && split.orientation == .horizontal && split.tabIDs.count == 2)
            #expect(zip(split.widthFactors, [0.35, 0.65]).allSatisfy { abs($0 - $1) < 1e-9 })
            let urls = split.tabIDs.compactMap { id in state.tabs.first { $0.id == id }?.savedURL }
            #expect(urls == ["https://a.example.com/", "https://b.example.com/"])
            let root = SidebarHierarchy.children(in: .init(spaceID: imported.work.id, folderID: nil, section: .pinned), state: state)
            #expect(root == [.folder(docs.id), .split(split.id)])
        }
    }

    @MainActor @Test func favoritesAndOpenTabsLandWhereDiaHadThem() throws {
        try withImport { imported in
            let state = imported.state
            let location = SidebarContainerLocation(spaceID: imported.work.id, folderID: nil, section: .favorite,
                                                    profileID: imported.standardID)
            let favorites = SidebarHierarchy.children(in: location, state: state)
            let mailTab = state.tabs.first(where: { $0.savedURL == "https://mail.example.com/" })
            let mail = try #require(mailTab)
            #expect(favorites == [.tab(mail.id)] && mail.kind == .favorite)
            let today = state.tabs.filter { $0.spaceID == imported.work.id && $0.kind == .today }
            #expect(today.map(\.savedURL) == ["https://today.example.com/"])
            let play = state.tabs.filter { $0.spaceID == imported.play.id }
            #expect(play.map(\.savedURL) == ["https://play.example.com/"] && play.first?.kind == .pinned)
        }
    }

    @MainActor @Test func closedWindowsAndDeletedTabsNeverReachTheStore() throws {
        try withImport { imported in
            let urls = imported.state.tabs.map(\.savedURL)
            #expect(!urls.contains("https://closed-window.example.com/"))
            #expect(!urls.contains { $0.contains("deleted") })
        }
    }
}
