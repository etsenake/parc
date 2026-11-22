import Foundation
import Testing
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SidebarNoteDropTests {
    @MainActor final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-sidebar-note-drop-" + UUID().uuidString)
        let plans: URL
        let ideas: URL
        let store: BrowserStore
        let profileID: UUID
        let spaceID: UUID

        init() throws {
            let notes = directory.appendingPathComponent("Notes", isDirectory: true)
            try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
            plans = notes.appendingPathComponent("Plans.md")
            ideas = notes.appendingPathComponent("Ideas.txt")
            try Data("# Plans\n".utf8).write(to: plans)
            try Data("ideas\n".utf8).write(to: ideas)
            store = try BrowserStore(directory: directory.appendingPathComponent("tabs"))
            profileID = store.activeSpace.profileID
            spaceID = store.state.activeSpaceID
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func opensNewTab(_ urls: [URL], profileID: UUID? = nil) -> Bool {
            SidebarNotePlacement.opensNewTab(urls, state: store.state, profileID: profileID ?? self.profileID)
        }
    }

    @Test func aNoteWithNoTabYetGetsAFreshTab() throws {
        let fixture = try Fixture()
        #expect(fixture.opensNewTab([fixture.plans]))
    }

    @Test func aNoteThatIsAlreadyOpenJustGetsSelected() throws {
        let fixture = try Fixture()
        _ = try #require(fixture.store.openNote(url: fixture.plans, title: "Plans"))
        #expect(!fixture.opensNewTab([fixture.plans]))
    }

    @Test func anAnchoredAddressNamesTheSameOpenNote() throws {
        let fixture = try Fixture()
        _ = try #require(fixture.store.openNote(url: fixture.plans, title: "Plans"))
        #expect(!fixture.opensNewTab([try #require(URL(string: fixture.plans.absoluteString + "#top"))]))
    }

    @Test func oneNewNoteInTheBunchIsEnoughToShowTheLine() throws {
        let fixture = try Fixture()
        _ = try #require(fixture.store.openNote(url: fixture.plans, title: "Plans"))
        #expect(fixture.opensNewTab([fixture.plans, fixture.ideas]))
    }

    @Test func anotherProfilesTabForTheFileDoesNotCount() throws {
        let fixture = try Fixture()
        _ = try #require(fixture.store.openNote(url: fixture.plans, title: "Plans"))
        #expect(fixture.opensNewTab([fixture.plans], profileID: UUID()))
    }

    @MainActor struct Drop {
        let fixture: Fixture
        let first: UUID
        let second: UUID
        let plansTab: UUID
        let ideasTab: UUID
        let location: SidebarContainerLocation
        let moved: Bool

        var order: [SidebarItemReference] { SidebarHierarchy.children(in: location, state: fixture.store.state) }
    }

    func dropIdeasAboveTheFirstTab() throws -> Drop {
        let fixture = try Fixture()
        let store = fixture.store
        let first = store.open("https://example.test/one"), second = store.open("https://example.test/two")
        let plansTab = try #require(store.openNote(url: fixture.plans, title: "Plans"))
        let location = SidebarContainerLocation(spaceID: fixture.spaceID, folderID: nil, section: .today)
        let ideasTab = try #require(store.openNote(url: fixture.ideas, title: "Ideas"))
        let expected = try #require(SidebarHierarchySnapshot(state: store.state, spaceID: fixture.spaceID,
                                                             profileID: fixture.profileID, includesFavorites: true))
        let moved = try store.moveSidebarItems([.tab(ideasTab)], to: location, before: .tab(first), expected: expected)
        return Drop(fixture: fixture, first: first, second: second, plansTab: plansTab, ideasTab: ideasTab, location: location, moved: moved)
    }

    @Test func aFreshlyOpenedNoteMovesToTheDroppedSpot() throws {
        #expect(try dropIdeasAboveTheFirstTab().moved)
    }

    @Test func theDroppedNoteLandsRightAboveTheRowTheLinePointedAt() throws {
        let drop = try dropIdeasAboveTheFirstTab()
        let ideasIndex = try #require(drop.order.firstIndex(of: .tab(drop.ideasTab)))
        let firstIndex = try #require(drop.order.firstIndex(of: .tab(drop.first)))
        #expect(ideasIndex + 1 == firstIndex)
    }

    @Test func everythingElseStaysPutWhenANoteIsDropped() throws {
        let drop = try dropIdeasAboveTheFirstTab()
        #expect(drop.order.contains(.tab(drop.second)))
        #expect(drop.order.contains(.tab(drop.plansTab)))
    }

    @Test func theDroppedNoteStaysSelectedAfterItMoves() throws {
        let drop = try dropIdeasAboveTheFirstTab()
        #expect(drop.fixture.store.state.selectedTabIDs == [drop.ideasTab])
    }
}
