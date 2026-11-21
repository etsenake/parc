import Foundation
import Testing
@testable import ParcCore

struct FolderMoveTests {
    typealias Move = CommandBarFolderMove
    typealias Source = CommandBarFolderMoveSource

    struct Fixture {
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let foreign = BrowserProfile(id: UUID(), name: "Other")
        let origin: BrowserSpace
        let away: BrowserSpace
        let other: BrowserSpace
        let sourceFolder: BrowserFolder
        let nested: BrowserFolder
        let here: BrowserFolder
        let there: BrowserFolder
        let wrong: BrowserFolder
        let first: BrowserTab
        let last: BrowserTab
        let child: BrowserTab
        let favorite: BrowserTab
        let resident: BrowserTab
        let state: BrowserState

        init() {
            origin = BrowserSpace(id: UUID(), name: "Origin", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            away = BrowserSpace(id: UUID(), name: "Away", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            other = BrowserSpace(id: UUID(), name: "Foreign", symbol: "circle", color: "ABCDEF", profileID: foreign.id)
            sourceFolder = BrowserFolder(id: UUID(), spaceID: origin.id, name: "Source", isExpanded: false)
            nested = BrowserFolder(id: UUID(), spaceID: origin.id, name: "Nested", parentID: sourceFolder.id, isExpanded: false)
            here = BrowserFolder(id: UUID(), spaceID: origin.id, name: "Destination", isExpanded: false)
            there = BrowserFolder(id: UUID(), spaceID: away.id, name: "Destination", isExpanded: false)
            wrong = BrowserFolder(id: UUID(), spaceID: other.id, name: "Destination", isExpanded: false)
            func tab(_ title: String, kind: TabKind = .today, folder: UUID? = nil) -> BrowserTab {
                BrowserTab(id: UUID(), spaceID: origin.id, profileID: profile.id, url: "https://current.test/" + title,
                    title: title, kind: kind, folderID: folder, createdAt: Date(timeIntervalSince1970: 100),
                    lastAccessed: Date(timeIntervalSince1970: 100), savedURL: "https://home.test/" + title, savedTitle: "Home")
            }
            first = tab("First")
            last = tab("Last")
            child = tab("Child", kind: .pinned, folder: nested.id)
            favorite = tab("Favorite", kind: .favorite)
            resident = tab("Resident", kind: .pinned, folder: here.id)
            var state = BrowserState(profiles: [profile, foreign], spaces: [origin, away, other], activeSpaceID: origin.id)
            state.folders = [sourceFolder, nested, here, there, wrong]
            state.tabs = [first, child, last, favorite, resident]
            state.selectedTabIDs = [first.id]
            state.selectionBySpace = [origin.id.uuidString: [first.id]]
            self.state = state
        }

        func source(_ items: [SidebarItemReference], _ state: BrowserState? = nil) -> Source? {
            Source(items: items, spaceID: origin.id, profileID: profile.id, state: state ?? self.state)
        }

        func action(_ source: Source, _ folderID: UUID, _ state: BrowserState? = nil) -> Move? {
            Move.snapshot(source: source, state: state ?? self.state).first { $0.folder.folderID == folderID }
        }

        func toHere(_ items: [SidebarItemReference]? = nil) -> Move {
            let input = source(items ?? [.tab(first.id), .tab(last.id)])!
            return action(input, here.id)!
        }

        func toThere(_ items: [SidebarItemReference]) -> Move { action(source(items)!, there.id)! }
    }

    struct Change: Sendable, CustomTestStringConvertible {
        let name: String
        let apply: @Sendable (inout BrowserState, Fixture) -> Void
        var testDescription: String { name }
    }

    static let expiringChanges: [Change] = [
        Change(name: "the original incarnation is replaced") { $0.tabs[0].createdAt.addTimeInterval(1) },
        Change(name: "the source is archived") { $0.tabs[0].archivedAt = Date() },
        Change(name: "the destination is removed") { state, fixture in state.folders.removeAll { $0.id == fixture.here.id } },
        Change(name: "the destination moves to another space") { state, fixture in state.folders[2].spaceID = fixture.away.id },
        Change(name: "profile ownership changes") { state, fixture in state.spaces[0].profileID = fixture.foreign.id },
    ]

    @Test func theTitleIsTheRecoveredRendererLiteral() {
        #expect(Fixture().toHere().title == "Pin to")
    }

    @Test func destinationWordsMatchTheAction() {
        let move = Fixture().toHere()
        #expect(Move.matching([move], query: "move destination") == [move])
    }

    @Test func theVisibleActionTextMatches() {
        let move = Fixture().toHere()
        #expect(Move.matching([move], query: "PIN TO") == [move])
    }

    @Test func anEmptyQueryInventsNoAction() {
        #expect(Move.matching([Fixture().toHere()], query: "").isEmpty)
    }

    @Test func aFolderInAnotherProfileIsNeverOffered() {
        let fixture = Fixture()
        #expect(fixture.action(fixture.source([.tab(fixture.first.id), .tab(fixture.last.id)])!, fixture.wrong.id) == nil)
    }

    @Test func duplicateNamedDestinationsKeepTheirSpaceContext() {
        let fixture = Fixture()
        let input = fixture.source([.tab(fixture.first.id), .tab(fixture.last.id)])!
        #expect(Move.snapshot(source: input, state: fixture.state).filter { $0.folder.name == "Destination" }.count == 2)
    }

    @Test func movingKeepsTheOriginalRecordsWithoutCloning() throws {
        let fixture = Fixture()
        let moved = try #require(fixture.toHere().applying(to: fixture.state))
        #expect(moved.tabs.map(\.id) == fixture.state.tabs.map(\.id))
    }

    @Test func todayItemsBecomeFolderPins() throws {
        let fixture = Fixture()
        let moved = try #require(fixture.toHere().applying(to: fixture.state))
        let ids = [fixture.first.id, fixture.last.id]
        #expect(moved.tabs.filter { ids.contains($0.id) }.allSatisfy { $0.kind == .pinned && $0.folderID == fixture.here.id })
    }

    @Test func promotionCapturesTheActualCurrentDestination() throws {
        let fixture = Fixture()
        let moved = try #require(fixture.toHere().applying(to: fixture.state))
        #expect(moved.tabs[0].savedURL == fixture.first.url)
    }

    @Test func theCollectionAppendsAfterTheExistingChildren() throws {
        let fixture = Fixture()
        let moved = try #require(fixture.toHere().applying(to: fixture.state))
        let location = SidebarContainerLocation(spaceID: fixture.origin.id, folderID: fixture.here.id, section: .pinned)
        #expect(SidebarHierarchy.children(in: location, state: moved) == [.tab(fixture.resident.id), .tab(fixture.first.id), .tab(fixture.last.id)])
    }

    @Test func aSameSpaceMoveKeepsTheActiveOriginalPage() throws {
        let fixture = Fixture()
        let moved = try #require(fixture.toHere().applying(to: fixture.state))
        #expect(moved.selectedTabIDs == fixture.state.selectedTabIDs)
        #expect(moved.selectionBySpace == fixture.state.selectionBySpace)
    }

    @Test func movingExpandsTheTargetFolder() throws {
        let fixture = Fixture()
        let moved = try #require(fixture.toHere().applying(to: fixture.state))
        #expect(moved.folders.first { $0.id == fixture.here.id }?.isExpanded == true)
    }

    @Test func unrelatedOriginalMetadataIsUnchanged() throws {
        let fixture = Fixture()
        let moved = try #require(fixture.toHere().applying(to: fixture.state))
        #expect(moved.tabs[1] == fixture.child)
        #expect(moved.tabs[3] == fixture.favorite)
    }

    @Test func anAppliedMoveCannotBeReused() throws {
        let fixture = Fixture()
        let move = fixture.toHere()
        let moved = try #require(move.applying(to: fixture.state))
        #expect(move.applying(to: moved) == nil)
    }

    @Test func aSameParentSourceIsExcluded() {
        let fixture = Fixture()
        #expect(fixture.action(fixture.source([.tab(fixture.resident.id)])!, fixture.here.id) == nil)
    }

    @Test func aCollectionWithASameParentItemRefusesRatherThanReorders() {
        let fixture = Fixture()
        #expect(fixture.action(fixture.source([.tab(fixture.first.id), .tab(fixture.resident.id)])!, fixture.here.id) == nil)
    }

    @Test func anAncestorOwnsItsSubtreeOnce() {
        let fixture = Fixture()
        let input = fixture.source([.folder(fixture.sourceFolder.id), .tab(fixture.child.id)])!
        #expect(input.roots == [.folder(fixture.sourceFolder.id)])
    }

    @Test(arguments: [true, false])
    func selfAndDescendantCyclesAreRefused(intoSelf: Bool) {
        let fixture = Fixture()
        let input = fixture.source([.folder(fixture.sourceFolder.id), .tab(fixture.child.id)])!
        #expect(fixture.action(input, intoSelf ? fixture.sourceFolder.id : fixture.nested.id) == nil)
    }

    @Test func aWholeFolderGoesIntoTheActualDestination() throws {
        let fixture = Fixture()
        let relocated = try #require(fixture.toThere([.folder(fixture.sourceFolder.id), .tab(fixture.child.id)]).applying(to: fixture.state))
        #expect(relocated.folders.first { $0.id == fixture.sourceFolder.id }?.parentID == fixture.there.id)
    }

    @Test func aNestedTreeStaysOneSameProfileHierarchy() throws {
        let fixture = Fixture()
        let relocated = try #require(fixture.toThere([.folder(fixture.sourceFolder.id), .tab(fixture.child.id)]).applying(to: fixture.state))
        let ids = [fixture.sourceFolder.id, fixture.nested.id]
        #expect(relocated.folders.filter { ids.contains($0.id) }.allSatisfy { $0.spaceID == fixture.away.id })
    }

    @Test func aNestedItemKeepsItsHomeAndParent() throws {
        let fixture = Fixture()
        let relocated = try #require(fixture.toThere([.folder(fixture.sourceFolder.id), .tab(fixture.child.id)]).applying(to: fixture.state))
        let child = relocated.tabs.first { $0.id == fixture.child.id }
        #expect(child?.folderID == fixture.nested.id)
        #expect(child?.savedURL == fixture.child.savedURL)
    }

    @Test func aDescendantKeepsItsOriginalDisclosure() throws {
        let fixture = Fixture()
        let relocated = try #require(fixture.toThere([.folder(fixture.sourceFolder.id), .tab(fixture.child.id)]).applying(to: fixture.state))
        #expect(relocated.folders.first { $0.id == fixture.nested.id }?.isExpanded == false)
    }

    @Test func aFavoriteBecomesAFolderPinInTheSameProfile() throws {
        let fixture = Fixture()
        let moved = try #require(fixture.toThere([.tab(fixture.favorite.id)]).applying(to: fixture.state))
        let favorite = try #require(moved.tabs.first { $0.id == fixture.favorite.id })
        #expect(favorite.spaceID == fixture.away.id)
        #expect(favorite.kind == .pinned)
        #expect(favorite.folderID == fixture.there.id)
    }

    @Test func aMovedFavoriteKeepsItsHomeAndIncarnation() throws {
        let fixture = Fixture()
        let moved = try #require(fixture.toThere([.tab(fixture.favorite.id)]).applying(to: fixture.state))
        let favorite = try #require(moved.tabs.first { $0.id == fixture.favorite.id })
        #expect(favorite.savedURL == fixture.favorite.savedURL)
        #expect(favorite.createdAt == fixture.favorite.createdAt)
    }

    struct SplitFixture {
        let fixture = Fixture()
        let group: BrowserSplitLayout
        let state: BrowserState

        init() {
            group = BrowserSplitLayout(sidebarAnchorID: fixture.first.id, spaceID: fixture.origin.id,
                                       tabIDs: [fixture.first.id, fixture.last.id], orientation: .horizontal, widthFactors: [0.3, 0.7])
            var state = fixture.state
            state.splitLayouts = [group]
            self.state = state
        }

        func moved() -> BrowserState {
            let input = fixture.source([.split(group.id)], state)!
            return fixture.action(input, fixture.there.id, state)!.applying(to: state)!
        }
    }

    @Test func aPaneIsNotSilentlyExtracted() {
        let split = SplitFixture()
        #expect(split.fixture.source([.tab(split.fixture.first.id)], split.state) == nil)
    }

    @Test func aWholeSplitKeepsItsIdentityMembershipAndProportions() {
        let split = SplitFixture()
        let layout = split.moved().splitLayouts[0]
        #expect(layout.id == split.group.id)
        #expect(layout.tabIDs == split.group.tabIDs)
        #expect(layout.widthFactors == split.group.widthFactors)
    }

    @Test func aWholeSplitMovesTogether() {
        let split = SplitFixture()
        let moved = split.moved()
        #expect(moved.splitLayouts[0].spaceID == split.fixture.away.id)
        #expect(moved.tabs.filter { split.group.tabIDs.contains($0.id) }.allSatisfy { $0.folderID == split.fixture.there.id })
    }

    @Test func liveMetadataIsAllowedWithoutReplayingTheURL() {
        let fixture = Fixture()
        let move = fixture.toHere()
        var changed = fixture.state
        changed.tabs[0].url = "https://redirect.test/"
        changed.tabs[0].title = "Live"
        #expect(move.isCurrent(in: changed))
        #expect(move.applying(to: changed)?.tabs[0].savedURL == "https://redirect.test/")
    }

    @Test(arguments: expiringChanges)
    func theMoveExpiresWhen(change: Change) {
        let fixture = Fixture()
        let move = fixture.toHere()
        var changed = fixture.state
        change.apply(&changed, fixture)
        #expect(!move.isCurrent(in: changed))
    }

    @Test func anEmptySourceRefuses() {
        #expect(Fixture().source([]) == nil)
    }

    @Test func aDuplicateSourceRefuses() {
        let fixture = Fixture()
        #expect(fixture.source([.tab(fixture.first.id), .tab(fixture.first.id)]) == nil)
    }

    @Test func anEmptyFolderMovesWithoutMaterializingAPage() {
        let fixture = Fixture()
        var emptyState = fixture.state
        emptyState.tabs.removeAll { $0.id == fixture.resident.id }
        let empty = fixture.source([.folder(fixture.here.id)], emptyState)!
        let moved = fixture.action(empty, fixture.there.id, emptyState)?.applying(to: emptyState)
        #expect(empty.tabIDs.isEmpty)
        #expect(moved?.folders.first { $0.id == fixture.here.id }?.parentID == fixture.there.id)
    }

    @Test func aNonEmptyFolderKeepsOneOriginalRoot() {
        let fixture = Fixture()
        #expect(fixture.source([.folder(fixture.here.id)])?.roots == [.folder(fixture.here.id)])
    }

    @Test func theCapturedSpaceDoesNotFollowTheSharedActiveWindow() {
        let fixture = Fixture()
        var otherWindow = fixture.state
        otherWindow.activeSpaceID = fixture.other.id
        otherWindow.selectedTabIDs = []
        #expect(fixture.toHere().applying(to: otherWindow)?.tabs[0].folderID == fixture.here.id)
    }
}
