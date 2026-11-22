import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitPaneMenuActionsTests {
    @MainActor private final class Dispatch {
        var performed: [SplitPaneOperation] = []
        var available = true
    }

    struct MenuOperationCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let position: Int
        let expected: SplitPaneOperation

        static let stack = [
            Self(testDescription: "Move Left", position: 0, expected: .movePrevious),
            Self(testDescription: "Move Up", position: 1, expected: .stackPrevious),
            Self(testDescription: "Add Above This Pane", position: 2, expected: .stackBefore),
            Self(testDescription: "Add Below This Pane", position: 3, expected: .stackAfter),
        ]
        static let sole = [
            Self(testDescription: "Add Left Split", position: 0, expected: .addBefore),
            Self(testDescription: "Add Right Split", position: 1, expected: .addAfter),
            Self(testDescription: "Add Top Split", position: 2, expected: .addAbove),
            Self(testDescription: "Add Bottom Split", position: 3, expected: .addBelow),
        ]
    }

    private static func invoke(_ item: NSMenuItem) {
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
    }

    private static func rows(_ menu: NSMenu) -> [String] { menu.items.filter { !$0.isSeparatorItem }.map(\.title) }

    private static func make(_ dispatch: Dispatch, orientation: SplitOrientation = .horizontal, index: Int = 0, count: Int = 2,
                             layout: BrowserSplitLayout? = nil, artwork: ((String) -> NSImage?)? = nil) -> NSMenu {
        SplitPaneMenu.make(orientation: orientation, index: index, count: count, layout: layout, artwork: artwork) { operation in
            { if dispatch.available { dispatch.performed.append(operation) } }
        }
    }

    private static func stackedLayout(_ orientation: SplitOrientation) -> BrowserSplitLayout {
        let shape = BrowserSplitLayout.shape(orientation: orientation, sizes: [1, 2], factors: [0.5, 0.5], stackFactors: [[1], [0.5, 0.5]])
        return BrowserSplitLayout(id: UUID(), spaceID: UUID(), tabIDs: [UUID(), UUID(), UUID()], orientation: shape.orientation,
                                  widthFactors: shape.widthFactors, stacks: shape.stacks)
    }

    @Test func theMenuOwnsExplicitAvailability() {
        let menu = Self.make(Dispatch())
        #expect(!menu.autoenablesItems)
        #expect(menu.title == "Split View Controls Menu")
    }

    @Test func aHorizontalSplitMatchesTheInstalledPaneControlList() {
        #expect(Self.rows(Self.make(Dispatch())) == ["Move Left", "Move Right", "Add Right Split", "Add Left Split", "Add Above This Pane",
                                                     "Add Below This Pane", "Separate Tab from Split", "Convert to Vertical Split View",
                                                     "Copy Links"])
    }

    @Test func aBoundaryMoveIsDisabled() {
        let menu = Self.make(Dispatch())
        #expect(menu.items[0].isEnabled == false)
        #expect(menu.items[1].isEnabled)
    }

    @Test func menuSectionsAreSeparators() {
        #expect(Self.make(Dispatch()).items.filter(\.isSeparatorItem).count == 3)
    }

    @Test func eachItemKeepsItsActionOwner() {
        let item = Self.make(Dispatch()).items[1]
        #expect(item.target != nil)
        #expect(item.representedObject != nil)
        #expect(item.action != nil)
    }

    @Test func dispatchPreservesTheExactOperation() {
        let dispatch = Dispatch()
        Self.invoke(Self.make(dispatch).items[1])
        #expect(dispatch.performed == [.moveNext])
    }

    @Test func theOwnerCanRejectAnActionAfterTheMenuWasPrepared() {
        let dispatch = Dispatch()
        let menu = Self.make(dispatch)
        dispatch.available = false
        Self.invoke(menu.items[1])
        #expect(dispatch.performed.isEmpty)
    }

    @Test func aFourPaneMenuHasNoFifthPaneAction() {
        let full = Self.make(Dispatch(), orientation: .vertical, index: 3, count: 4)
        #expect(full.items.filter { $0.title.hasPrefix("Add ") }.allSatisfy { !$0.isEnabled })
    }

    @Test func theLastVerticalPaneOnlyMovesUp() {
        let full = Self.make(Dispatch(), orientation: .vertical, index: 3, count: 4)
        #expect(full.items[0].title == "Move Up" && full.items[0].isEnabled)
        #expect(!full.items[1].isEnabled)
    }

    @Test func aTopAndBottomSplitOffersSidewaysStackedAdds() {
        #expect(Self.rows(Self.make(Dispatch(), orientation: .vertical, index: 3, count: 4))
                == ["Move Up", "Move Down", "Add Top Split", "Add Bottom Split", "Add Left of This Pane", "Add Right of This Pane",
                    "Separate Tab from Split", "Convert to Horizontal Split View", "Copy Links"])
    }

    @Test func convertSitsAboveCopyLinks() {
        let full = Self.make(Dispatch(), orientation: .vertical, index: 3, count: 4)
        #expect(full.items[9].title == "Convert to Horizontal Split View")
        #expect(full.items.last?.title == "Copy Links")
    }

    @Test func aPaneInAStackAlsoMovesWithinIt() {
        let stacked = Self.make(Dispatch(), index: 2, count: 3, layout: Self.stackedLayout(.horizontal))
        #expect(Self.rows(stacked) == ["Move Left", "Move Right", "Move Up", "Move Down", "Add Right Split", "Add Left Split",
                                       "Add Above This Pane", "Add Below This Pane", "Separate Tab from Split",
                                       "Convert to Vertical Split View", "Copy Links"])
    }

    @Test func movesNeedANeighbour() {
        let stacked = Self.make(Dispatch(), index: 2, count: 3, layout: Self.stackedLayout(.horizontal))
        #expect(stacked.items[0].isEnabled && !stacked.items[1].isEnabled)
        #expect(stacked.items[2].isEnabled && !stacked.items[3].isEnabled)
    }

    @Test func threePanesLeaveRoomForOneMore() {
        let stacked = Self.make(Dispatch(), index: 2, count: 3, layout: Self.stackedLayout(.horizontal))
        #expect(stacked.items.filter { $0.title.hasPrefix("Add ") }.allSatisfy { $0.isEnabled })
    }

    @Test(arguments: MenuOperationCase.stack)
    func stackRowsDispatchTheirExactOperations(_ sample: MenuOperationCase) throws {
        let dispatch = Dispatch()
        let stacked = Self.make(dispatch, index: 2, count: 3, layout: Self.stackedLayout(.horizontal))
        let titles = Set(MenuOperationCase.stack.map(\.testDescription))
        let items = stacked.items.filter { titles.contains($0.title) }
        #expect(items.count == MenuOperationCase.stack.count)
        let item = try #require(items.indices.contains(sample.position) ? items[sample.position] : nil)
        Self.invoke(item)
        #expect(dispatch.performed == [sample.expected])
    }

    @Test func aPaneAloneInItsSlotShowsNoStackMoves() {
        let lone = Self.make(Dispatch(), index: 0, count: 3, layout: Self.stackedLayout(.horizontal))
        #expect(!lone.items.contains { $0.title == "Move Up" || $0.title == "Move Down" })
        #expect(!lone.items[0].isEnabled && lone.items[1].isEnabled)
    }

    @Test func inATopAndBottomSplitAStackedPaneMovesLeftAndRight() {
        let sideways = Self.make(Dispatch(), orientation: .vertical, index: 1, count: 3, layout: Self.stackedLayout(.vertical))
        #expect(Self.rows(sideways).prefix(4) == ["Move Up", "Move Down", "Move Left", "Move Right"])
        #expect(sideways.items[0].isEnabled && !sideways.items[1].isEnabled)
        #expect(!sideways.items[2].isEnabled && sideways.items[3].isEnabled)
    }

    @Test func copyLinksFollowsTheOwnersLiveRefusal() {
        let dispatch = Dispatch()
        let menu = Self.make(dispatch)
        let copyLinks = menu.items.last!
        dispatch.available = false
        Self.invoke(copyLinks)
        #expect(copyLinks.isEnabled)
        #expect(dispatch.performed.isEmpty)
    }

    @Test func copyLinksDispatchesTheSplitsCopyOperation() {
        let dispatch = Dispatch()
        Self.invoke(Self.make(dispatch).items.last!)
        #expect(dispatch.performed == [.copyLinks])
    }

    @Test func withNoWebPageToCopyOnlyCopyLinksIsDisabled() {
        let linkless = SplitPaneMenu.make(orientation: .horizontal, index: 0, count: 2) { operation in
            operation == .copyLinks ? nil : {}
        }
        #expect(linkless.items.last?.title == "Copy Links")
        #expect(linkless.items.last?.isEnabled == false)
        #expect(linkless.items[1].isEnabled)
    }

    @Test func aSolePaneExposesBothOriginalOrientationSections() {
        let single = Self.make(Dispatch(), orientation: .vertical, index: 0, count: 1)
        #expect(single.items.map(\.title) == ["Add Left Split", "Add Right Split", "", "Add Top Split", "Add Bottom Split"])
        #expect(single.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.isEnabled })
    }

    @Test(arguments: MenuOperationCase.sole)
    func soleRowsDispatchTheirBeforeAfterAndOrientationIdentities(_ sample: MenuOperationCase) throws {
        let dispatch = Dispatch()
        let single = Self.make(dispatch, orientation: .vertical, index: 0, count: 1)
        let items = single.items.filter { !$0.isSeparatorItem }
        #expect(items.count == MenuOperationCase.sole.count)
        let item = try #require(items.indices.contains(sample.position) ? items[sample.position] : nil)
        Self.invoke(item)
        #expect(dispatch.performed == [sample.expected])
    }

    @Test(arguments: [0, 5])
    func noMenuMaterializesOutsideTheContentBounds(_ count: Int) {
        let invalid = SplitPaneMenu.make(orientation: .horizontal, index: 0, count: count) { _ in
            Issue.record("an invalid menu dispatched")
            return nil
        }
        #expect(invalid.items.isEmpty)
    }

    @Test func aRefusedOwnerLeavesNoEnabledAction() {
        let refused = SplitPaneMenu.make(orientation: .horizontal, index: 1, count: 3) { _ in nil }
        #expect(refused.items.allSatisfy { $0.isSeparatorItem || !$0.isEnabled })
    }
}
