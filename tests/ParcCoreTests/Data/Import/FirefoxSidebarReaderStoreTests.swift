import Foundation
import Testing
@testable import ParcCore

struct FirefoxSidebarReaderStoreTests {
    private typealias Fixture = FirefoxSidebarFixture

    @MainActor @Test func theFirstWindowFillsTheHomeSpaceAndTheSecondGetsItsOwn() throws {
        let sidebar = try Fixture.standard()
        try DataFixtures.withTemporaryDirectory { directory in
            let importedAt = Fixture.importedAt
            let store = try BrowserStore(directory: directory, now: { importedAt })
            let standardID = store.state.profiles[0].id
            let home = store.activeSpace.id
            let spacesBefore = store.state.spaces.count
            let result = try store.importSidebar(sidebar, profiles: [(Fixture.profileKey, "Personal")],
                standardProfileID: standardID, primary: Fixture.profileKey, into: standardID, home: home)
            let state = store.state
            #expect(result[Fixture.profileKey] == BrowserImportDestination(spaceID: home, profileID: standardID))
            #expect(state.spaces.count == spacesBefore + 1)

            func tab(_ url: String) throws -> UUID {
                let found = try #require(state.tabs.first { $0.savedURL == url && $0.archivedAt == nil })
                return found.id
            }
            let mail = try tab("https://mail.example.com/"), docB = try tab("https://docs.example.com/b")
            let docC = try tab("https://docs.example.com/c"), left = try tab("https://left.example.com/")
            let right = try tab("https://right.example.com/"), news = try tab("https://news.example.com/")
            let shop = try tab("https://shop.example.com/"), maps = try tab("https://maps.example.com/")
            let research = try #require(state.folders.first { $0.spaceID == home && $0.name == "Research" })
            let trip = try #require(state.folders.first { $0.spaceID == home && $0.name == "Trip" })
            #expect(!research.isExpanded && !trip.isExpanded)
            let pinned = SidebarHierarchy.children(in: .init(spaceID: home, folderID: nil, section: .pinned), state: state)
            #expect(pinned == [.tab(mail), .folder(research.id), .folder(trip.id)])
            let researchChildren = SidebarHierarchy.children(in: .init(spaceID: home, folderID: research.id, section: .pinned),
                                                             state: state)
            #expect(researchChildren == [.tab(docB), .tab(docC)])

            let split = try #require(state.splitLayouts.first { $0.spaceID == home })
            #expect(split.tabIDs == [left, right])
            #expect(split.orientation == .horizontal && split.widthFactors == [0.5, 0.5])
            let today = SidebarHierarchy.children(in: .init(spaceID: home, folderID: nil, section: .today), state: state)
            #expect(today == [.split(split.id), .tab(news)])

            let second = try #require(state.spaces.last)
            #expect(second.id != home && second.profileID == standardID)
            let secondToday = SidebarHierarchy.children(in: .init(spaceID: second.id, folderID: nil, section: .today), state: state)
            #expect(secondToday == [.tab(shop), .tab(maps)])

            let favorites = state.tabs.filter { $0.kind == .favorite && $0.profileID == standardID }.map(\.savedURL)
            #expect(favorites.suffix(2) == ["https://wiki.example.com/", "https://calendar.example.com/"])

            let closed = try #require(state.tabs.first { $0.savedURL == "https://closed.example.com/" })
            #expect(closed.archivedAt == Date(timeIntervalSince1970: 1_763_999_500) && closed.spaceID == home
                    && closed.archiveProvenance?.reason == .manual)
        }
    }

    @MainActor @Test func importingTheSameSessionTwiceAddsNothing() throws {
        let sidebar = try Fixture.standard()
        try DataFixtures.withTemporaryDirectory { directory in
            let importedAt = Fixture.importedAt
            let store = try BrowserStore(directory: directory, now: { importedAt })
            let standardID = store.state.profiles[0].id
            let home = store.activeSpace.id
            _ = try store.importSidebar(sidebar, profiles: [(Fixture.profileKey, "Personal")],
                standardProfileID: standardID, primary: Fixture.profileKey, into: standardID, home: home)
            let once = store.state
            _ = try store.importSidebar(sidebar, profiles: [(Fixture.profileKey, "Personal")],
                standardProfileID: standardID, primary: Fixture.profileKey, into: standardID, home: home)
            #expect(store.state.spaces.count == once.spaces.count && store.state.tabs.count == once.tabs.count)
        }
    }
}
