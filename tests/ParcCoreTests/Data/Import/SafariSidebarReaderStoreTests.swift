import Foundation
import Testing
@testable import ParcCore

struct SafariSidebarReaderStoreTests {
    private typealias Fixture = SafariSidebarReaderFixture

    @MainActor
    @Test func looseTabsLandInTheHomeSpaceAndEachTabGroupBecomesASpace() throws {
        try Fixture.withHome { home in
            let sidebar = try Fixture.read(home)
            try DataFixtures.withTemporaryDirectory { directory in
                let store = try BrowserStore(directory: directory, now: { Fixture.importedAt })
                let standardID = store.state.profiles[0].id
                let homeID = store.activeSpaceID
                let spacesBefore = store.state.spaces.count
                let tabsBefore = Set(store.state.tabs.map(\.id))
                let result = try store.importSidebar(sidebar, profiles: [(.standard, "Safari")], standardProfileID: standardID,
                                                     primary: .standard, into: standardID, home: homeID)
                let state = store.state
                let fresh = state.tabs.filter { !tabsBefore.contains($0.id) }
                func urls(_ space: UUID, _ kind: TabKind) -> [String] {
                    fresh.filter { $0.spaceID == space && $0.kind == kind && $0.folderID == nil }.map(\.savedURL)
                }
                #expect(urls(homeID, .today) == ["file:///Users/example/notes.html", "https://weather.example.com/"])
                #expect(urls(homeID, .pinned) == ["https://mail.example.com/", "https://cal.example.com/"])
                #expect(result[.standard] == .init(spaceID: homeID, profileID: standardID))

                let work = try #require(state.profiles.first { $0.name == "Work" })
                let created = Array(state.spaces.dropFirst(spacesBefore))
                #expect(created.map(\.title) == ["Research", "Work", "Client X"])
                #expect(created.map(\.profileID) == [standardID, work.id, work.id])
                #expect(created[1].customIcon == .symbol("briefcase"))
                #expect(result[Fixture.work] == .init(spaceID: created[1].id, profileID: work.id))

                let research = created[0]
                let paper = try #require(fresh.first { $0.spaceID == research.id && $0.kind == .pinned && $0.folderID == nil })
                #expect(paper.savedURL == "https://papers.example.org/" && paper.customTitle == "Paper index")
                let folder = try #require(state.folders.first { $0.spaceID == research.id })
                #expect(folder.name == "Favorites" && !folder.isExpanded)
                #expect(fresh.filter { $0.folderID == folder.id }.map(\.savedURL) == ["https://wiki.example.org/"])
                #expect(urls(research.id, .today) == ["https://news.example.net/a"])
                #expect(urls(created[1].id, .pinned) == ["https://chat.example.com/"])
                #expect(urls(created[1].id, .today) == ["https://docs.example.com/w"])
                #expect(urls(created[2].id, .today) == ["https://clientx.example.com/", "https://clientx.example.com/invoices"])

                let favorites = fresh.filter { $0.kind == .favorite }
                #expect(favorites.filter { $0.profileID == standardID }.map(\.savedURL)
                        == (1...12).map { "https://bar\($0).example.com/" })
                #expect(favorites.filter { $0.profileID == work.id }.map(\.savedURL)
                        == ["https://jira.example.com/", "https://wiki.work.example.com/"])
            }
        }
    }

    @MainActor
    @Test func importingSafariAgainAddsNoSecondCopy() throws {
        try Fixture.withHome { home in
            let sidebar = try Fixture.read(home)
            try DataFixtures.withTemporaryDirectory { directory in
                let store = try BrowserStore(directory: directory, now: { Fixture.importedAt })
                let standardID = store.state.profiles[0].id
                let homeID = store.activeSpaceID
                _ = try store.importSidebar(sidebar, profiles: [(.standard, "Safari")], standardProfileID: standardID,
                                            primary: .standard, into: standardID, home: homeID)
                let once = store.state
                _ = try store.importSidebar(sidebar, profiles: [(.standard, "Safari")], standardProfileID: standardID,
                                            primary: .standard, into: standardID, home: homeID)
                #expect(store.state.spaces.count == once.spaces.count && store.state.tabs.count == once.tabs.count)
                #expect(store.state.profiles.filter { $0.name == "Work" }.count == 1)
            }
        }
    }
}
