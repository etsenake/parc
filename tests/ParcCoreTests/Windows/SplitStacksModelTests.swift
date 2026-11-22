import Foundation
import Testing
@testable import ParcCore

struct SplitStacksModelTests {
    private struct Model {
        let space = UUID(), a = UUID(), b = UUID(), c = UUID(), x = UUID(), y = UUID()
        var pair: BrowserSplitLayout { BrowserSplitLayout(spaceID: space, tabIDs: [a, b], widthFactors: [0.4, 0.6]) }
        var trio: BrowserSplitLayout { pair.insertingIntoStack(x, besidePaneAt: 0, after: true)! }
        var quad: BrowserSplitLayout { trio.insertingIntoStack(y, besidePaneAt: 1, after: true)! }
        var wide: BrowserSplitLayout { SplitStacksTestsSupport.stacked([a, b, c], space: space, sizes: [1, 2], slots: [0.3, 0.7], stacks: [[1], [0.25, 0.75]]) }
        var quadStack: BrowserSplitLayout { SplitStacksTestsSupport.stacked([a, x, y, b], space: space, sizes: [3, 1], slots: [0.5, 0.5], stacks: [[0.2, 0.3, 0.5], [1]]) }
    }

    @Test func addingBelowAPaneOfAFlatSplitCreatesAStackInThatPanesColumn() {
        let m = Model()
        #expect(m.trio.tabIDs == [m.a, m.x, m.b])
        #expect(m.trio.orientation == .horizontal)
        #expect(m.trio.stacks == BrowserSplitStacks(slotSizes: [2, 1], slotFactors: [0.4, 0.6], stackFactors: [[0.5, 0.5], [1]]))
    }

    @Test func addingAboveAPanePutsTheNewPaneFirstInItsStack() {
        let m = Model()
        let above = m.pair.insertingIntoStack(m.x, besidePaneAt: 1, after: false)
        #expect(above?.tabIDs == [m.a, m.x, m.b])
        #expect(above?.stacks?.slotSizes == [1, 2])
    }

    @Test func aPaneAlreadyInAStackAddsToThatSameStack() {
        let m = Model()
        #expect(m.quad.tabIDs == [m.a, m.x, m.y, m.b])
        #expect(m.quad.stacks?.slotSizes == [3, 1])
        #expect(SplitStacksTestsSupport.close(m.quad.stacks!.stackFactors[0], [1.0 / 3, 1.0 / 3, 1.0 / 3]))
    }

    @Test func noStackInsertAtFourPanes() {
        #expect(Model().quad.insertingIntoStack(UUID(), besidePaneAt: 0, after: true) == nil)
    }

    @Test func aSinglePageCannotBeStacked() {
        let m = Model()
        #expect(BrowserSplitLayout(spaceID: m.space, tabIDs: [m.a], widthFactors: [1]).insertingIntoStack(m.x, besidePaneAt: 0, after: true) == nil)
    }

    @Test func aStackedPaneHasAPositionInsideItsOwnSlot() {
        let m = Model()
        let quad = m.quad
        #expect(quad.position(of: m.y)?.slot == 0)
        #expect(quad.position(of: m.y)?.index == 2)
    }

    @Test func aSlotAndIndexIdentifyThePane() {
        let m = Model()
        let quad = m.quad
        #expect(quad.paneID(slot: 1, index: 0) == m.b)
    }

    @Test func theFirstSlotsRangeSpansAllOfItsStackedPanes() {
        let m = Model()
        let quad = m.quad
        #expect(quad.slotRange(0) == 0..<3)
    }

    @Test func theSlotBoundariesFollowReadingOrder() {
        let m = Model()
        let quad = m.quad
        #expect(quad.slotBoundaries == [0, 3, 4])
        #expect(m.pair.mainRowInsertionIndex(after: m.a) == 1)
    }

    @Test func insertingAfterAStackedPaneTargetsTheEndOfItsStack() {
        let m = Model()
        let quad = m.quad
        #expect(quad.mainRowInsertionIndex(after: m.x) == 3)
    }

    @Test func insertingAfterAFlatPaneTargetsTheNextSlot() {
        let m = Model()
        #expect(m.pair.slotBoundaries == [0, 1, 2])
    }

    @Test func aStackLeftWithOnePaneBecomesAnOrdinarySlot() {
        let m = Model()
        var collapsed = m.trio
        collapsed.removePane(at: 1)
        #expect(collapsed.tabIDs == [m.a, m.b])
        #expect(collapsed.stacks == nil)
        #expect(collapsed.widthFactors == [0.4, 0.6])
        #expect(collapsed.orientation == .horizontal)
    }

    @Test func aSplitLeftWithASingleStackedColumnBecomesFlatInTheStacksDirection() {
        let m = Model()
        var column = m.trio
        column.removePane(at: 2)
        #expect(column.tabIDs == [m.a, m.x])
        #expect(column.stacks == nil)
        #expect(column.orientation == .vertical)
        #expect(column.widthFactors == [0.5, 0.5])
    }

    @Test func removingFromAStackOfThreeKeepsAStackOfTwo() {
        let m = Model()
        var smaller = m.quad
        smaller.removePane(at: 0)
        #expect(smaller.tabIDs == [m.x, m.y, m.b])
        #expect(smaller.stacks?.slotSizes == [2, 1])
        #expect(SplitStacksTestsSupport.close(smaller.stacks!.stackFactors[0], [0.5, 0.5]))
    }

    @Test func theFocusSuccessorIsThePaneNowAtTheOldReadingOrderIndex() {
        let m = Model()
        #expect(BrowserSplitLayout.focusSuccessor([m.x, m.y, m.b], removedAt: 0) == m.x)
    }

    @Test func aFlatRemovalIsUntouched() {
        let m = Model()
        var flatRemoval = BrowserSplitLayout(spaceID: m.space, tabIDs: [m.a, m.b, m.c], widthFactors: [0.2, 0.3, 0.5])
        flatRemoval.removePane(at: 1)
        #expect(flatRemoval.tabIDs == [m.a, m.c])
        #expect(flatRemoval.widthFactors == [0.2, 0.5])
    }

    @Test func movingAlongTheMainRowMovesThePanesWholeSlot() throws {
        let m = Model()
        let slotMove = try #require(m.wide.movingSlot(of: m.b, by: -1))
        #expect(slotMove.tabIDs == [m.b, m.c, m.a])
        #expect(slotMove.stacks?.slotSizes == [2, 1])
        #expect(slotMove.stacks?.slotFactors == [0.7, 0.3])
        #expect(slotMove.stacks?.stackFactors == [[0.25, 0.75], [1]])
    }

    @Test func aPaneAloneCanMoveItsSlotForward() {
        let m = Model()
        #expect(m.wide.movingSlot(of: m.a, by: 1)?.tabIDs == [m.b, m.c, m.a])
    }

    @Test func theFirstSlotCannotMoveBackward() {
        let m = Model()
        #expect(m.wide.movingSlot(of: m.a, by: -1) == nil)
    }

    @Test func movingAcrossReordersWithinTheStack() throws {
        let m = Model()
        let inner = try #require(m.wide.movingWithinStack(m.c, by: -1))
        #expect(inner.tabIDs == [m.a, m.c, m.b])
        #expect(inner.stacks?.stackFactors == [[1], [0.75, 0.25]])
        #expect(inner.stacks?.slotFactors == [0.3, 0.7])
    }

    @Test func movingAcrossNeedsAStackNeighbour() {
        let m = Model()
        #expect(m.wide.movingWithinStack(m.a, by: 1) == nil)
        #expect(m.wide.movingWithinStack(m.b, by: -1) == nil)
    }

    @Test func convertTransposesBothLevelsAndKeepsReadingOrder() {
        let wide = Model().wide
        let turned = wide.transposed()
        #expect(turned.orientation == .vertical)
        #expect(turned.stacks == wide.stacks)
        #expect(turned.tabIDs == wide.tabIDs)
        #expect(turned.transposed() == wide)
    }

    @Test func expandGivesTheFocusedPaneTheMaximumShareOnBothLevels() throws {
        let m = Model()
        let expanded = try #require(m.wide.expanded(focusing: m.c))
        #expect(expanded.stacks!.slotFactors[1] > 0.999)
        #expect(expanded.stacks!.stackFactors[1][1] > 0.999)
        #expect(expanded.stacks!.stackFactors[0] == [1])
    }

    @Test func aFlatExpandKeepsTodaysFactors() {
        let m = Model()
        #expect(m.pair.expanded(focusing: m.a)?.widthFactors == m.pair.expandedFactors(focusing: m.a))
    }

    @Test func makeAllEqualEvensTheSlotsThenEachStack() {
        #expect(Model().wide.equalized()?.stacks == BrowserSplitStacks(slotSizes: [1, 2], slotFactors: [0.5, 0.5], stackFactors: [[1], [0.5, 0.5]]))
    }

    @Test func aFlatMakeAllEqualKeepsTodaysFactors() {
        let m = Model()
        #expect(BrowserSplitLayout(spaceID: m.space, tabIDs: [m.a, m.b, m.c], widthFactors: [0.2, 0.3, 0.5]).equalized()?.widthFactors
                == BrowserSplitLayout.normalized([1, 1, 1], count: 3))
    }

    @Test func aStackDividerResizesOnlyItsTwoNeighbours() throws {
        let resize = try #require(Model().quadStack.resizingDivider(1, inSlot: 0, leadingShare: 0.5))
        #expect(SplitStacksTestsSupport.close(resize.stacks!.stackFactors[0], [0.2, 0.4, 0.4]))
        #expect(resize.stacks!.slotFactors == [0.5, 0.5])
    }

    @Test func aMainRowDividerResizesOnlyItsTwoSlots() throws {
        let quad = Model().quadStack
        let resize = try #require(quad.resizingDivider(0, inSlot: nil, leadingShare: 0.25))
        #expect(SplitStacksTestsSupport.close(resize.stacks!.slotFactors, [0.25, 0.75]))
        #expect(resize.stacks!.stackFactors == quad.stacks!.stackFactors)
    }

    struct ResizeCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let divider: Int
        let slot: Int?
        let share: Double
    }

    @Test(arguments: [
        ResizeCase(testDescription: "Divider past the end of a stack", divider: 2, slot: 0, share: 0.5),
        ResizeCase(testDescription: "Divider in a slot with just one pane", divider: 0, slot: 1, share: 0.5),
        ResizeCase(testDescription: "Divider pushed to the far edge", divider: 0, slot: 0, share: 1.0),
    ])
    func anInvalidDividerResizeIsRefused(_ resize: ResizeCase) {
        #expect(Model().quadStack.resizingDivider(resize.divider, inSlot: resize.slot, leadingShare: resize.share) == nil)
    }

    @Test func resizingAStackNormalisesItsWeights() {
        let quad = Model().quadStack
        #expect(SplitStacksTestsSupport.close(quad.resizingStack(0, factors: [1, 1, 2])!.stacks!.stackFactors[0], [0.25, 0.25, 0.5]))
    }

    @Test func resizingTheMainSlotsNormalisesTheirWeights() {
        let quad = Model().quadStack
        #expect(quad.resizingSlots([1, 3])!.stacks!.slotFactors == [0.25, 0.75])
    }

    @Test func aProjectionKeepsASurvivingStack() {
        let m = Model()
        var subset = BrowserSplitLayout(id: m.quadStack.id, spaceID: m.space, tabIDs: [m.x, m.y, m.b], widthFactors: [0.3, 0.3, 0.4], stacks: nil)
        subset.restack(from: m.quadStack)
        #expect(subset.stacks?.slotSizes == [2, 1])
        #expect(subset.stacks?.slotFactors == [0.5, 0.5])
    }

    @Test func aReorderedProjectionThatSplitsAStackDropsToFlat() {
        let m = Model()
        var broken = BrowserSplitLayout(id: m.quadStack.id, spaceID: m.space, tabIDs: [m.a, m.b, m.y], widthFactors: [0.3, 0.3, 0.4], stacks: nil)
        broken.restack(from: m.quadStack)
        #expect(broken.stacks == nil)
        #expect(broken.tabIDs == [m.a, m.b, m.y])
        #expect(broken.widthFactors.count == 3)
    }

    @Test func restackingFromAFlatSplitChangesNothing() {
        let m = Model()
        var untouched = BrowserSplitLayout(spaceID: m.space, tabIDs: [m.b, m.a], widthFactors: [0.6, 0.4])
        untouched.restack(from: m.pair)
        #expect(untouched.widthFactors == [0.6, 0.4])
        #expect(untouched.stacks == nil)
    }
}
