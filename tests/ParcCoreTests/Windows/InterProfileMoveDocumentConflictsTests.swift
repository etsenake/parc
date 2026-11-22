import Foundation
import Testing
@testable import ParcCore

struct InterProfileMoveDocumentConflictsTests {
    private typealias Fixture = InterProfileMoveTestsSupport.Fixture

    private struct Blocks {
        let f = Fixture()
        let note = InternalPage.easel(UUID()).urlString
        let easel = InternalPage.easel(UUID()).urlString
        let research: BrowserFolder

        init() { research = BrowserFolder(id: UUID(), spaceID: f.s.id, name: "Research") }

        func set(_ id: UUID, _ url: String, title: String? = nil, in state: inout BrowserState) {
            let index = state.tabs.firstIndex { $0.id == id }!
            state.tabs[index].url = url
            state.tabs[index].savedURL = url
            if let title { state.tabs[index].title = title; state.tabs[index].savedTitle = title }
        }

        func alias(_ url: String, _ space: BrowserSpace, _ kind: TabKind, folder: UUID? = nil, archived: Bool = false) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: url, title: "Alias", kind: kind,
                       folderID: folder, createdAt: Date(timeIntervalSince1970: 3), lastAccessed: Date(timeIntervalSince1970: 4),
                       archivedAt: archived ? Date(timeIntervalSince1970: 5) : nil, savedURL: url, savedTitle: "Alias")
        }

        func block(_ items: [SidebarItemReference], _ state: BrowserState) throws -> (InterProfileDocumentBlock?, Bool) {
            let source = try #require(SidebarHierarchySnapshot(state: state, spaceID: f.s.id, profileID: f.p.id))
            let target = try #require(SidebarHierarchySnapshot(state: state, spaceID: f.d.id, profileID: f.q.id))
            let move = try #require(SidebarSpaceMove(items: items, from: source, to: target, state: state))
            let after = move.applying(to: state)
            let refused = after.map { InterProfileMove.documents(moving: Set(move.tabIDs), after: $0) == nil } ?? false
            return (InterProfileDocumentBlock(moving: Set(move.tabIDs), before: state, after: after), refused)
        }

        var clean: BrowserState {
            var state = f.state
            set(f.today.id, note, in: &state)
            return state
        }

        var duplicated: BrowserState {
            var state = clean
            state.folders = [research]
            state.tabs.append(alias(note, f.s, .pinned, folder: research.id))
            return state
        }
    }

    @Test func aBlockedDocumentMoveExplainsInsteadOfAskingForTheDataWarning() {
        let f = Fixture()
        #expect(InterProfileMoveGate.resolve(sourceProfiles: [f.p.id], destination: f.q.id, decision: nil, bypass: false, blocked: true) == .blocked)
    }

    @Test func dontAskAgainStillExplainsABlockedMove() {
        let f = Fixture()
        #expect(InterProfileMoveGate.resolve(sourceProfiles: [f.p.id], destination: f.q.id, decision: nil, bypass: true, blocked: true) == .blocked)
    }

    @Test func aSameDataMoveIsNeverGatedByTheDocumentCheck() {
        let f = Fixture()
        #expect(InterProfileMoveGate.resolve(sourceProfiles: [f.q.id], destination: f.q.id, decision: nil, bypass: false, blocked: true) == .proceed(remembersChoice: false))
    }

    @Test func anUnblockedMoveStillAsksFirst() {
        let f = Fixture()
        #expect(InterProfileMoveGate.resolve(sourceProfiles: [f.p.id], destination: f.q.id, decision: nil, bypass: false, blocked: false) == .confirm)
    }

    @Test func anEaselWithNoOtherEntriesHasNothingToExplainAndStillMoves() throws {
        let b = Blocks()
        let (none, refused) = try b.block([.tab(b.f.today.id)], b.clean)
        #expect(none == nil)
        #expect(!refused)
    }

    @Test func webPagesNeverProduceADocumentExplanation() throws {
        let b = Blocks()
        let (web, refused) = try b.block([.split(b.f.group.id)], b.f.state)
        #expect(web == nil)
        #expect(!refused)
    }

    @Test func aMoveThatNoLongerAppliesExplainsNothing() {
        let f = Fixture()
        #expect(InterProfileDocumentBlock(moving: [f.today.id], before: f.state, after: nil) == nil)
    }

    @Test func aDuplicateInAFolderBlocksTheMoveAndMatchesTheStoresRefusal() throws {
        let b = Blocks()
        let (copy, refused) = try b.block([.tab(b.f.today.id)], b.duplicated)
        #expect(copy != nil)
        #expect(refused)
    }

    @Test func theDuplicateIsPlacedInItsFolderWithTheDestinationNamedInTheTitle() throws {
        let b = Blocks()
        let folder = try #require(try b.block([.tab(b.f.today.id)], b.duplicated).0)
        #expect(folder.places == [.sidebar(.folder("Research"), split: false, otherSpace: nil)])
        #expect(folder.title == "Can’t move to Office")
        #expect(folder.message == "This Easel is still used elsewhere in Home: in the folder “Research”.")
    }

    private func archivedBlock(_ b: Blocks) throws -> (InterProfileDocumentBlock, Bool) {
        var archived = b.f.state
        b.set(b.f.today.id, b.easel, in: &archived)
        archived.tabs.append(b.alias(b.easel, b.f.s, .today, archived: true))
        let (old, refused) = try b.block([.tab(b.f.today.id)], archived)
        return (try #require(old), refused)
    }

    @Test func anArchivedEntryIsReportedAsTheArchive() throws {
        let (archive, refused) = try archivedBlock(Blocks())
        #expect(refused)
        #expect(archive.places == [.archive])
        #expect(archive.message == "This Easel is still used elsewhere in Home: in the Archive.")
    }

    private func joinedPinned(_ b: Blocks) -> BrowserState {
        var joined = b.f.state
        var pinnedNote = joined.tabs.first { $0.id == b.f.pinned.id }!
        pinnedNote.url = b.note
        pinnedNote.savedURL = b.note
        joined.tabs.append(SplitMembership.makeHome(of: pinnedNote, id: UUID(), now: Date(timeIntervalSince1970: 6), activeTabBeforeCreationID: nil))
        b.set(b.f.g1.id, b.note, title: "Plans", in: &joined)
        return joined
    }

    @Test func aPinnedTabShowingAWebPageNamesTheEaselSavedInIt() throws {
        let b = Blocks()
        var away = b.clean
        let index = away.tabs.firstIndex { $0.id == b.f.pinned.id }!
        away.tabs[index].savedURL = b.note
        away.tabs[index].savedTitle = "Plans"
        away.tabs[index].title = "Docs page"
        let (navigated, refused) = try b.block([.tab(b.f.pinned.id)], away)
        #expect(refused)
        #expect(navigated?.message == "The Easel “Plans” is still used elsewhere in Home: in Today.")
    }

    @Test func theSavedSpotAPinnedEasselLeftWhenJoiningASplitBlocksTheMove() throws {
        let b = Blocks()
        let (spot, refused) = try b.block([.split(b.f.group.id)], joinedPinned(b))
        let saved = try #require(spot)
        #expect(refused)
        #expect(saved.places == [.sidebar(.pinned, split: false, otherSpace: nil)])
        #expect(saved.message == "The Easel “Plans” is still used elsewhere in Home: in Pinned.")
    }

    @Test func aCopyInsideAPinnedSplitBlocksTheMove() throws {
        let b = Blocks()
        var pinnedSplit = b.clean
        for id in b.f.group.tabIDs { pinnedSplit.tabs[pinnedSplit.tabs.firstIndex { $0.id == id }!].kind = .pinned }
        b.set(b.f.g2.id, b.note, in: &pinnedSplit)
        let (split, refused) = try b.block([.tab(b.f.today.id)], pinnedSplit)
        let paired = try #require(split)
        #expect(refused)
        #expect(paired.places == [.sidebar(.pinned, split: true, otherSpace: nil)])
        #expect(paired.message == "This Easel is still used elsewhere in Home: in a pinned split.")
    }

    @Test func draggingAPinnedEaselIntoAnotherDatasSplitLeavesItsPinnedSpotBehind() throws {
        let b = Blocks()
        let f = b.f
        var dragged = f.state
        b.set(f.pinned.id, b.note, in: &dragged)
        let request = ForeignSplitDrop.Request(source: try #require(dragged.tab(f.pinned.id)), sourceHomeID: UUID(), spaceID: f.d.id, profileID: f.q.id,
            selection: [f.d1.id], layout: nil, target: .insert(1), orientation: .horizontal, destinationHomeIDs: [:])
        let dropped = ForeignSplitDrop.proposal(request, state: dragged, now: Date(timeIntervalSince1970: 7), creation: nil)
        let behind = try #require(InterProfileDocumentBlock(moving: [f.pinned.id], before: dragged, after: dropped))
        #expect(behind.places == [.leftBehind(.pinned, split: false)])
        #expect(behind.message == "This Easel is still used elsewhere in Home: in the pinned spot it leaves behind.")
    }

    private func spread(_ b: Blocks) -> BrowserState {
        let work = BrowserSpace(id: UUID(), name: "Work", symbol: "circle", color: "AABBCC", profileID: b.f.p.id)
        var shared = b.duplicated
        shared.spaces.append(work)
        shared.tabs.insert(contentsOf: [b.alias(b.note, work, .today), b.alias(b.note, b.f.s, .favorite)], at: shared.tabs.count - 1)
        return shared
    }

    @Test func everyDistinctPlaceIsKeptOnceInAStableOrder() throws {
        let b = Blocks()
        let (many, refused) = try b.block([.tab(b.f.today.id)], spread(b))
        let block = try #require(many)
        #expect(refused)
        #expect(block.places == [.sidebar(.today, split: false, otherSpace: "Work"), .sidebar(.favorites, split: false, otherSpace: nil),
                                 .sidebar(.folder("Research"), split: false, otherSpace: nil)])
    }

    @Test func entriesOutsideTheSourceSpaceNameTheirSpace() throws {
        let b = Blocks()
        let many = try #require(try b.block([.tab(b.f.today.id)], spread(b)).0)
        #expect(many.message == "This Easel is still used elsewhere: in Today in Work, in Favorites and in the folder “Research” in Home.")
    }

    @Test func aLongListStaysShort() throws {
        let b = Blocks()
        var shared = spread(b)
        shared.tabs.append(b.alias(b.note, b.f.s, .today, archived: true))
        #expect(try b.block([.tab(b.f.today.id)], shared).0?.message == "This Easel is still used elsewhere: in Today in Work, in Favorites and 2 more places.")
    }

    private func pairState(_ b: Blocks) -> BrowserState {
        var pair = b.duplicated
        b.set(b.f.g1.id, b.note, title: "Plans", in: &pair)
        b.set(b.f.g2.id, b.easel, title: "Board", in: &pair)
        pair.tabs.removeAll { $0.id == b.f.today.id }
        pair.tabs.append(b.alias(b.easel, b.f.s, .today, archived: true))
        return pair
    }

    @Test func aSplitWithTwoBlockedDocumentsExplainsTheFirstAndCountsTheOther() throws {
        let b = Blocks()
        let (both, refused) = try b.block([.split(b.f.group.id)], pairState(b))
        let first = try #require(both)
        #expect(refused)
        #expect(first.document == InternalPage(urlString: b.note))
        #expect(first.others == [InternalPage(urlString: b.easel)!])
        #expect(first.message == "The Easel “Plans” is still used elsewhere in Home: in the folder “Research”. 1 more Easel is too.")
    }

    @Test func aMultiItemMoveNamesTheOneItemThatBlocksIt() throws {
        let b = Blocks()
        var onlyEasel = pairState(b)
        onlyEasel.tabs.removeAll { $0.folderID == b.research.id }
        let (one, refused) = try b.block([.split(b.f.group.id)], onlyEasel)
        #expect(refused)
        #expect(one?.message == "The Easel “Board” is still used elsewhere in Home: in the Archive.")
    }

    @Test func aNewSpaceThatKeepsSeparateDataIsBlockedTheSameWay() throws {
        let b = Blocks()
        let duplicated = b.duplicated
        let snapshot = try #require(SidebarHierarchySnapshot(state: duplicated, spaceID: b.f.s.id, profileID: b.f.p.id))
        var draft = try #require(SidebarNewSpaceDraft(items: [.tab(b.f.today.id)], from: snapshot, state: duplicated))
        draft.name = "Fresh"
        draft.keepSeparate()
        let fresh = try #require(InterProfileDocumentBlock(moving: Set(draft.tabIDs), before: duplicated, after: draft.applying(to: duplicated)))
        #expect(fresh.message == "This Easel is still used elsewhere in Home: in the folder “Research”.")
    }
}
