import Foundation
import Testing
@testable import ParcCore

struct ZenSidebarReaderStoreTests {
    private typealias Fixture = ZenSidebarFixture

    private struct Imported {
        let state: BrowserState
        let standardID: UUID
        let created: [BrowserSpace]
        let zenID: UUID
        let workID: UUID
        let clientsID: UUID
    }

    @MainActor private static func withImport(_ body: (Imported) throws -> Void) throws {
        try DataFixtures.withTemporaryDirectory { root in
            let profile = try Fixture.makeProfile(in: root.appendingPathComponent("zen", isDirectory: true))
            let zen = try ZenSidebarReader.read(profiles: [profile])
            let importedAt = Fixture.importedAt
            let store = try BrowserStore(directory: root.appendingPathComponent("store", isDirectory: true), now: { importedAt })
            let standardID = store.state.profiles[0].id
            let spacesBefore = store.state.spaces.count
            _ = try store.importSidebar(zen, profiles: [(Fixture.key, profile.name)], standardProfileID: standardID)
            let state = store.state
            func profileID(_ name: String) throws -> UUID { try #require(state.profiles.first { $0.name == name }).id }
            try body(Imported(state: state, standardID: standardID, created: Array(state.spaces.dropFirst(spacesBefore)),
                              zenID: profileID("Zen"), workID: profileID("Work"), clientsID: profileID("Clients")))
        }
    }

    @MainActor @Test func eachZenSpaceAndContainerLandsInItsOwnProfile() throws {
        try Self.withImport { imported in
            #expect(imported.created.map(\.title) == ["Personal", "Work", "Clients"])
            #expect(imported.created.map(\.profileID) == [imported.zenID, imported.workID, imported.clientsID])
            #expect(imported.created.map(\.pinnedCollapsed) == [false, true, false])
            #expect(imported.created[0].customIcon == .emoji("🏠"))
            #expect(imported.state.arcImportedSpaces["zen:\(Fixture.personal)"] == imported.created[0].id)
            #expect(imported.state.arcImportedSpaces["zen:\(Fixture.work)"] == imported.created[1].id)
        }
    }

    @MainActor @Test func foldersNestInZensOrderWithTheSplitInside() throws {
        try Self.withImport { imported in
            let state = imported.state
            let spaceID = imported.created[0].id
            let tabs = state.tabs.filter { $0.spaceID == spaceID && $0.kind == .pinned }
            func tab(_ url: String) throws -> BrowserTab { try #require(tabs.first { $0.savedURL == url }) }
            let reading = try #require(state.folders.first { $0.spaceID == spaceID && $0.name == "Reading" })
            let later = try #require(state.folders.first { $0.spaceID == spaceID && $0.name == "Later" })
            let papers = try #require(state.folders.first { $0.parentID == reading.id })
            #expect(reading.parentID == nil && reading.isExpanded && papers.name == "Papers" && !papers.isExpanded)
            #expect(!state.folders.contains { $0.name == "Feed" })
            let inbox = try tab("https://news.example.com/")
            #expect(inbox.customTitle == "Inbox" && inbox.title == "News")
            let root = SidebarHierarchy.children(in: .init(spaceID: spaceID, folderID: nil, section: .pinned), state: state)
            #expect(root == [.tab(inbox.id), .folder(reading.id), .folder(later.id)])
            let split = try #require(state.splitLayouts.first { $0.spaceID == spaceID && $0.tabIDs.count == 2 })
            let left = try tab("https://left.example/"), right = try tab("https://right.example/")
            #expect(split.tabIDs == [left.id, right.id] && split.orientation == .horizontal && split.stacks == nil)
            #expect(Fixture.close(split.widthFactors, [0.3, 0.7]))
            #expect(left.folderID == reading.id && right.folderID == reading.id)
            let blog = try tab("https://blog.example.com/"), paper = try tab("https://arxiv.org/abs/1")
            let inside = SidebarHierarchy.children(in: .init(spaceID: spaceID, folderID: reading.id, section: .pinned), state: state)
            #expect(inside == [.tab(blog.id), .split(split.id), .folder(papers.id)])
            #expect(paper.folderID == papers.id)
        }
    }

    @MainActor @Test func theStackedTodaySplitKeepsItsColumns() throws {
        try Self.withImport { imported in
            let state = imported.state
            let spaceID = imported.created[0].id
            let split = try #require(state.splitLayouts.first { $0.spaceID == spaceID && $0.tabIDs.count == 3 })
            let urls = split.tabIDs.compactMap { id in state.tabs.first { $0.id == id }?.savedURL }
            #expect(urls == ["https://a.example/", "https://b.example/", "https://c.example/"])
            #expect(split.stacks?.slotSizes == [2, 1])
            #expect(Fixture.close(split.widthFactors, [0.3, 0.3, 0.4]))
            #expect(split.tabIDs.allSatisfy { id in state.tabs.first { $0.id == id }?.kind == .today })
            let today = state.tabs.filter { $0.spaceID == spaceID && $0.kind == .today && $0.archivedAt == nil }
            #expect(today.contains { $0.savedURL == "https://d.example/2" })
            #expect(!state.tabs.contains { $0.savedURL == "https://preview.example/" || $0.savedURL == "https://feed.example/1" })
        }
    }

    @MainActor @Test func essentialsBecomeEachProfilesFavorites() throws {
        try Self.withImport { imported in
            func favorites(_ profileID: UUID) -> [String] {
                imported.state.tabs.filter { $0.kind == .favorite && $0.profileID == profileID }.map(\.savedURL)
            }
            #expect(favorites(imported.zenID) == ["https://github.com/"])
            #expect(favorites(imported.workID) == ["https://mail.example.com/"])
            #expect(favorites(imported.clientsID) == ["https://calendar.example.com/"])
            #expect(favorites(imported.standardID).isEmpty)
        }
    }

    @MainActor @Test func workTabsLandInTheWorkContainerProfile() throws {
        try Self.withImport { imported in
            let state = imported.state
            let work = imported.created[1]
            let jira = try #require(state.tabs.first { $0.savedURL == "https://jira.example.com/" })
            let wiki = try #require(state.tabs.first { $0.savedURL == "https://wiki.example.com/" })
            #expect(jira.spaceID == work.id && jira.kind == .pinned && jira.profileID == imported.workID)
            #expect(wiki.spaceID == work.id && wiki.kind == .today && wiki.profileID == imported.workID)
        }
    }
}
