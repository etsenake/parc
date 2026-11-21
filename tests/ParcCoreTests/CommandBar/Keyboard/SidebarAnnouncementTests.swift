import Foundation
import Testing
@testable import ParcCore

@MainActor
struct SidebarAnnouncementTests {
    typealias Announcement = SidebarKeyboardAnnouncement

    @MainActor final class Fixture {
        var state = BrowserState.initial()
        let space: BrowserSpace
        let profile: UUID
        let outer: BrowserFolder
        let inner: BrowserFolder
        let unnamed: BrowserFolder
        let favorite: BrowserTab
        let renamed: BrowserTab
        let blank: BrowserTab
        let right: BrowserTab
        let pair: BrowserSplitLayout
        var cursor = SidebarKeyboardCursor(highlightedID: nil)
        var requests: [String] = []
        let directory = CommandBarFixtures.temporaryDirectory("sidebar-announcement")
        let names = ["Favorite", "Outer, folder, expanded", "Inner, folder, collapsed", "Alpha, Beta, Split View",
                     "Folder, collapsed", "Research, Split View, 2 tabs", "Renamed", "New tab"]

        deinit { try? FileManager.default.removeItem(at: directory) }

        init() {
            let start = BrowserState.initial()
            state = start
            let space = start.spaces[0], profile = space.profileID
            self.space = space
            self.profile = profile
            outer = BrowserFolder(id: UUID(), spaceID: space.id, name: "Outer", parentID: nil, isExpanded: true)
            inner = BrowserFolder(id: UUID(), spaceID: space.id, name: "Inner", parentID: outer.id, isExpanded: false)
            unnamed = BrowserFolder(id: UUID(), spaceID: space.id, name: "", parentID: nil, isExpanded: false)
            func tab(_ name: String, _ kind: TabKind, _ parent: UUID? = nil) -> BrowserTab {
                .init(id: UUID(), spaceID: space.id, profileID: profile, url: "https://example.invalid/" + name,
                    title: name, kind: kind, folderID: parent, createdAt: .distantPast, lastAccessed: .distantPast,
                    savedURL: "https://example.invalid/" + name, savedTitle: name)
            }
            favorite = tab("Favorite", .favorite)
            let a = tab("Alpha", .pinned, outer.id), b = tab("Beta", .pinned, outer.id)
            let hidden = tab("Hidden", .pinned, inner.id), left = tab("Left", .today)
            right = tab("Right", .today)
            var renamedTab = tab("Original", .today)
            renamedTab.customTitle = "Renamed"
            renamed = renamedTab
            var blankTab = tab("", .today)
            blankTab.url = "about:blank"
            blankTab.savedURL = ""
            blankTab.savedTitle = ""
            blank = blankTab
            pair = BrowserSplitLayout(sidebarAnchorID: b.id, spaceID: space.id, tabIDs: [a.id, b.id],
                orientation: .vertical, widthFactors: [0.5, 0.5])
            let research = BrowserSplitLayout(sidebarAnchorID: left.id, customTitle: "Research", spaceID: space.id,
                tabIDs: [left.id, right.id], widthFactors: [0.5, 0.5])
            state.tabs = [favorite, a, b, hidden, left, right, renamed, blank]
            state.folders = [outer, inner, unnamed]
            state.splitLayouts = [pair, research]
            state.selectedTabIDs = [renamed.id]
            state.selectionBySpace[space.id.uuidString] = [renamed.id]
            state.sidebarItemOrder[SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .pinned).key] =
                [.folder(outer.id), .folder(unnamed.id)]
            state.sidebarItemOrder[SidebarContainerLocation(spaceID: space.id, folderID: outer.id, section: .pinned).key] =
                [.folder(inner.id), .split(pair.id)]
            state.sidebarItemOrder[SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .today).key] =
                [.tab(left.id), .tab(renamed.id), .tab(blank.id)]
        }

        func items(_ current: BrowserState? = nil, closed: Set<UUID> = []) -> [SidebarKeyboardNavigation.Item] {
            SidebarKeyboardNavigation.items(state: current ?? state, spaceID: space.id, selected: [renamed.id],
                focused: renamed.id, available: { !closed.contains($0) })
        }

        func enter() {
            cursor = SidebarKeyboardCursor(highlightedID: items().first { $0.selection?.tabIDs == [renamed.id] }?.id)
        }

        func press(_ delta: Int, in current: BrowserState? = nil, closed: Set<UUID> = []) {
            let target = current ?? state
            requests.append(Announcement.move(delta, cursor: &cursor, in: items(target, closed: closed), state: target))
        }

        func highlightable(_ reference: SidebarItemReference) -> SidebarKeyboardNavigation.Item? {
            items().first { $0.reference == reference }
        }
    }

    @Test func everyHighlightableItemSpeaksTheNameTheSidebarShows() {
        let f = Fixture()
        #expect(f.items().compactMap { Announcement.text($0, state: f.state) } == f.names)
    }

    @Test func aSplitShowingOnlyItsIconSpeaksWhatItsRowSaysNotItsPageTitles() {
        let f = Fixture()
        var iconOnly = f.state
        iconOnly.splitLayouts[0].customIcon = .symbol("star")
        #expect(f.items(iconOnly).first { $0.reference == .split(f.pair.id) }.flatMap { Announcement.text($0, state: iconOnly) }
                == "Split View, 2 tabs")
    }

    @Test func enteringTheModeSpeaksTheItemHighlightedAtTheStart() {
        let f = Fixture()
        f.enter()
        #expect(Announcement.highlight(f.cursor, in: f.items(), state: f.state) == "Renamed")
    }

    @Test func enteringWithoutAHighlightedItemAsksForNoAnnouncement() {
        let f = Fixture()
        #expect(Announcement.highlight(SidebarKeyboardCursor(highlightedID: nil), in: f.items(), state: f.state) == nil)
        #expect(Announcement.highlight(nil, in: f.items(), state: f.state) == nil)
    }

    @Test func downAsksForExactlyOneAnnouncementNamingTheNextItem() {
        let f = Fixture()
        f.enter()
        f.press(1)
        #expect(f.requests == ["New tab"])
    }

    @Test func steppingPastTheLastItemAsksForOneEndOfListAnnouncement() {
        let f = Fixture()
        f.enter()
        f.press(1)
        f.press(1)
        #expect(f.requests.last == Announcement.endOfList)
        #expect(f.cursor.highlightedID == nil)
        #expect(f.requests.count == 2)
    }

    @Test func downReEntersAtTheTopAndWalksEveryItemWithOneAnnouncementPerPress() {
        let f = Fixture()
        for expected in f.names {
            let before = f.requests.count
            f.press(1)
            #expect(f.requests.count == before + 1)
            #expect(f.requests.last == expected)
        }
    }

    @Test func upReEntersAtTheBottomAndWalksBackWithOneAnnouncementPerPress() {
        let f = Fixture()
        for expected in f.names.reversed() {
            let before = f.requests.count
            f.press(-1)
            #expect(f.requests.count == before + 1)
            #expect(f.requests.last == expected)
        }
    }

    @Test func steppingPastTheFirstItemAsksForOneTopOfListAnnouncement() {
        let f = Fixture()
        for _ in f.names { f.press(-1) }
        f.press(-1)
        #expect(f.requests.last == Announcement.topOfList)
        #expect(f.cursor.highlightedID == nil)
        #expect(f.requests.count == f.names.count + 1)
    }

    @Test func aLoadFinishingATitleChangeOrABackgroundTabClosingKeepsTheHighlight() {
        let f = Fixture()
        f.cursor = SidebarKeyboardCursor(highlightedID: f.highlightable(.tab(f.favorite.id))?.id)
        var refreshed = f.state
        refreshed.tabs[0].savedTitle = "Favorite, loaded"
        refreshed.tabs[0].title = "Favorite, loaded"
        f.cursor.reconcile(f.items(refreshed).map(\.id))
        f.cursor.reconcile(f.items(refreshed, closed: [f.right.id]).map(\.id))
        #expect(f.cursor.highlightedID == f.items().first?.id)
    }

    @Test func theNextArrowPressSpeaksTheRefreshedTitle() {
        let f = Fixture()
        f.cursor = SidebarKeyboardCursor(highlightedID: f.highlightable(.tab(f.favorite.id))?.id)
        var refreshed = f.state
        refreshed.tabs[0].savedTitle = "Favorite, loaded"
        refreshed.tabs[0].title = "Favorite, loaded"
        f.cursor.reconcile(f.items(refreshed).map(\.id))
        f.press(1, in: refreshed)
        f.press(-1, in: refreshed)
        #expect(f.requests.suffix(2) == ["Outer, folder, expanded", "Favorite, loaded"])
    }

    @Test func aHighlightedTabClosingInTheBackgroundClearsTheHighlight() {
        let f = Fixture()
        f.cursor = SidebarKeyboardCursor(highlightedID: f.highlightable(.tab(f.blank.id))?.id)
        var closing = f.state
        closing.tabs.removeAll { $0.id == f.blank.id }
        f.cursor.reconcile(f.items(closing).map(\.id))
        #expect(f.cursor.highlightedID == nil)
    }

    @Test func upAfterThatRemovalSpeaksTheNewLastItem() {
        let f = Fixture()
        var closing = f.state
        closing.tabs.removeAll { $0.id == f.blank.id }
        f.press(-1, in: closing)
        #expect(f.requests.last == "Renamed")
    }

    func highlightedFolder(_ f: Fixture, in store: BrowserStore) throws -> BrowserFolder {
        try #require(f.items(store.state).first { $0.id == f.cursor.highlightedID }?.folder)
    }

    func storeWithHighlightedInner(_ f: Fixture) throws -> BrowserStore {
        try FileManager.default.createDirectory(at: f.directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(f.state).write(to: f.directory.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: f.directory)
        f.cursor = SidebarKeyboardCursor(highlightedID: f.items(store.state).first { $0.reference == .folder(f.inner.id) }?.id)
        return store
    }

    @Test func afterReturnOpensAFolderItsNewStateIsSpoken() throws {
        let f = Fixture()
        let store = try storeWithHighlightedInner(f)
        let folder = try highlightedFolder(f, in: store)
        #expect(try store.setFolderExpanded(!folder.isExpanded, expected: folder, profileID: f.profile))
        f.cursor.reconcile(f.items(store.state).map(\.id))
        #expect(Announcement.highlight(f.cursor, in: f.items(store.state), state: store.state) == "Inner, folder, expanded")
    }

    @Test func afterReturnClosesAFolderItsNewStateIsSpoken() throws {
        let f = Fixture()
        let store = try storeWithHighlightedInner(f)
        let folder = try highlightedFolder(f, in: store)
        _ = try store.setFolderExpanded(!folder.isExpanded, expected: folder, profileID: f.profile)
        f.cursor.reconcile(f.items(store.state).map(\.id))
        let opened = try highlightedFolder(f, in: store)
        #expect(try store.setFolderExpanded(!opened.isExpanded, expected: opened, profileID: f.profile))
        #expect(Announcement.highlight(f.cursor, in: f.items(store.state), state: store.state) == "Inner, folder, collapsed")
    }

    @Test func arrowsInAnEmptySidebarStillAnswerOncePerPress() {
        let f = Fixture()
        var empty = SidebarKeyboardCursor(highlightedID: nil)
        #expect(Announcement.move(1, cursor: &empty, in: [], state: f.state) == Announcement.emptyList)
        #expect(Announcement.move(-1, cursor: &empty, in: [], state: f.state) == Announcement.emptyList)
    }

    @Test func aHighlightedRowWithoutAReadableNameNeverClaimsTheListEnded() {
        let f = Fixture()
        let stale = SidebarKeyboardNavigation.Item(reference: .tab(UUID()), selection: nil, folder: nil)
        var lost = SidebarKeyboardCursor(highlightedID: nil)
        #expect(Announcement.move(1, cursor: &lost, in: [stale], state: f.state) == Announcement.unnamedItem)
    }
}
