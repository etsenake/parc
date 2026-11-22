import Foundation
import Testing
@testable import ParcCore

struct SplitPaneControlsActionsTests {
    private typealias Fixture = SplitPaneControlsTestsSupport.Fixture

    @MainActor @Test func theFirstPaneCannotMoveBeforeTheStart() throws {
        let f = try Fixture()
        #expect(!f.store.moveSplitPane(f.a, offset: -1, expected: f.original))
    }

    @MainActor @Test func theLastPaneCannotMoveAfterTheEnd() throws {
        let f = try Fixture()
        #expect(!f.store.moveSplitPane(f.c, offset: 1, expected: f.original))
    }

    @MainActor @Test func anUntrustedOffsetRefusesWithoutOverflow() throws {
        let f = try Fixture()
        #expect(!f.store.moveSplitPane(f.a, offset: Int.min, expected: f.original))
    }

    @MainActor @Test func anOriginalPaneMovesDown() throws {
        let f = try Fixture()
        #expect(f.store.moveSplitPane(f.b, offset: 1, expected: f.original))
    }

    @MainActor @Test func movingKeepsTheGroupAndReordersPageIDs() throws {
        let f = try Fixture()
        let moved = f.moved()
        #expect(moved.tabIDs == [f.a, f.c, f.b])
        #expect(moved.id == f.original.id)
    }

    @MainActor @Test func paneProportionsMoveWithTheirContent() throws {
        let f = try Fixture()
        let moved = f.moved()
        #expect(moved.widthFactors == [f.original.widthFactors[0], f.original.widthFactors[2], f.original.widthFactors[1]])
    }

    @MainActor @Test func movingPreservesOrientationAndAnchor() throws {
        let f = try Fixture()
        let moved = f.moved()
        #expect(moved.orientation == .vertical)
        #expect(moved.sidebarAnchorID == f.original.sidebarAnchorID)
    }

    @MainActor @Test func movingDoesNotRecreatePagesOrCloseOriginals() throws {
        let f = try Fixture()
        _ = f.moved()
        #expect(f.store.state.tabs == f.tabs)
        #expect(f.store.state.recentlyClosedIDs == f.archive)
    }

    @MainActor @Test func orderAndWindowSelectionPublishTogether() throws {
        let f = try Fixture()
        let moved = f.moved()
        #expect(f.store.state.selectedTabIDs == moved.tabIDs)
        #expect(f.store.state.selectionBySpace[f.store.activeSpaceID.uuidString] == moved.tabIDs)
    }

    @MainActor @Test func aMoveIsDurablyRestored() throws {
        let f = try Fixture()
        let moved = f.moved()
        #expect(try BrowserStore(directory: f.root).activeSplitLayout == moved)
    }

    @MainActor @Test func aStaleMenuReceiptRefuses() throws {
        let f = try Fixture()
        _ = f.moved()
        let unchanged = f.store.state
        #expect(!f.store.moveSplitPane(f.b, offset: -1, expected: f.original))
        #expect(f.store.state == unchanged)
    }

    @MainActor @Test func theInverseMoveRestoresTheOriginalMetadataAndRatios() throws {
        let f = try Fixture()
        let moved = f.moved()
        #expect(f.store.moveSplitPane(f.b, offset: -1, expected: moved))
        #expect(f.store.activeSplitLayout == f.original)
    }

    struct DirectionCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let operation: SplitPaneOperation
        let enabled: Bool
    }

    @Test(arguments: [
        DirectionCase(testDescription: "Move previous", operation: .movePrevious, enabled: false),
        DirectionCase(testDescription: "Move next", operation: .moveNext, enabled: true),
    ])
    func theFirstPaneCanOnlyMoveTowardTheEnd(_ direction: DirectionCase) {
        #expect(direction.operation.isEnabled(index: 0, count: 3) == direction.enabled)
    }

    @Test func addIsUnavailableAtFourPanes() {
        #expect(!SplitPaneOperation.addAfter.isEnabled(index: 0, count: 4))
    }

    @Test func aSolePaneCannotBeSeparated() {
        #expect(!SplitPaneOperation.separate.isEnabled(index: 0, count: 1))
    }

    struct LinkCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let paneCount: Int
        let enabled: Bool
    }

    @Test(arguments: [
        LinkCase(testDescription: "Two panes", paneCount: 2, enabled: true),
        LinkCase(testDescription: "Single pane", paneCount: 1, enabled: false),
    ])
    func copyLinksNeedsAPopulatedSplit(_ split: LinkCase) {
        #expect(SplitPaneOperation.copyLinks.isEnabled(index: 0, count: split.paneCount) == split.enabled)
    }

    @MainActor private struct Links {
        let space: UUID, profile: UUID
        let note: UUID, easel: UUID, settings: UUID, blank: UUID

        init(_ f: Fixture) {
            space = f.store.activeSpaceID
            profile = f.store.activeSpace.profileID
            note = f.store.openResolvedURL(URL(string: InternalPage.note(URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md")).urlString)!)
            easel = f.store.openResolvedURL(URL(string: InternalPage.easel(UUID()).urlString)!)
            settings = f.store.openResolvedURL(URL(string: "parc://settings/")!)
            blank = f.store.openResolvedURL(URL(string: "about:blank")!)
        }
    }

    @MainActor @Test func copyLinksCopiesEveryPagesAddressInPaneOrder() throws {
        let f = try Fixture()
        let l = Links(f)
        #expect(FolderLinks.links(in: f.store.state, tabIDs: [f.c, f.a, f.b], spaceID: l.space, profileID: l.profile).map(\.tabID) == [f.c, f.a, f.b])
    }

    @MainActor @Test func notesCopyTheirFileWhileEaselsParcPagesAndBlankTabsAreSkippedAndPagesCopyOnce() throws {
        let f = try Fixture()
        let l = Links(f)
        let links = FolderLinks.links(in: f.store.state, tabIDs: [l.note, f.b, l.settings, l.easel, f.a, l.blank, f.b], spaceID: l.space, profileID: l.profile)
        #expect(links.map(\.tabID) == [l.note, f.b, f.a])
    }

    @MainActor @Test func aSplitWithoutAWebPageHasNothingToCopy() throws {
        let f = try Fixture()
        let l = Links(f)
        #expect(FolderLinks.links(in: f.store.state, tabIDs: [l.easel, l.settings], spaceID: l.space, profileID: l.profile).isEmpty)
    }

    @MainActor @Test func anotherProfilesPagesAreNeverCopied() throws {
        let f = try Fixture()
        let l = Links(f)
        #expect(FolderLinks.links(in: f.store.state, tabIDs: [f.a, f.b], spaceID: l.space, profileID: UUID()).isEmpty)
    }
}
