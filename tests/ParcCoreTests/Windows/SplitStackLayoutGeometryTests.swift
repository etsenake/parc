import Foundation
import Testing
@testable import ParcCore

struct SplitStackLayoutGeometryTests {
    private static func dividers(_ value: BrowserSplitStacks, _ orientation: SplitOrientation = .horizontal,
                                 size: CGSize = CGSize(width: 1010, height: 710)) -> [SplitStackGeometry.Divider] {
        SplitStackGeometry.dividers(paneFrames: SplitStackLayoutTestsSupport.frames(value, orientation, size: size), size: size,
                                    orientation: orientation, stacks: value, thickness: 10)
    }

    @Test func aSideBySideSplitRunsItsSlotsAcrossAndStacksTheFirstColumnWithATenPointGap() {
        #expect(SplitStackLayoutTestsSupport.frames(SplitStackLayoutTestsSupport.columnStacks) == [CGRect(x: 0, y: 0, width: 500, height: 350), CGRect(x: 0, y: 360, width: 500, height: 350),
                                                   CGRect(x: 510, y: 0, width: 500, height: 710)])
    }

    @Test func aTopAndBottomSplitRunsItsRowsDownAndDividesTheFirstRow() {
        #expect(SplitStackLayoutTestsSupport.frames(SplitStackLayoutTestsSupport.columnStacks, .vertical) == [CGRect(x: 0, y: 0, width: 500, height: 350), CGRect(x: 510, y: 0, width: 500, height: 350),
                                                              CGRect(x: 0, y: 360, width: 1010, height: 350)])
    }

    @Test func aStackedPaneKeepsTheMinimumOnTheCrossAxisAndItsNeighbourGivesUpTheDeficit() {
        let squeezed = SplitStackLayoutTestsSupport.frames(SplitStackLayoutTestsSupport.stacks([2, 1], [0.5, 0.5], [[0.95, 0.05], [1]]))
        #expect(squeezed[1].height == 220)
        #expect(squeezed[0].height == 480)
        #expect(squeezed[1].minY == 490)
    }

    @Test func aSlotKeepsTheMinimumOnTheMainAxisAndBothStackPanesShareItsWidth() {
        let squeezed = SplitStackLayoutTestsSupport.frames(SplitStackLayoutTestsSupport.stacks([2, 1], [0.9, 0.1], [[0.5, 0.5], [1]]))
        #expect(squeezed[2].width == 220)
        #expect(squeezed[0].width == 780)
        #expect(squeezed[1].width == 780)
    }

    @Test func severalSqueezedStackPanesEachKeepTheMinimumAndTheRestRedistributes() {
        let three = SplitStackLayoutTestsSupport.frames(SplitStackLayoutTestsSupport.stacks([1, 3], [0.5, 0.5], [[1], [0.9, 0.05, 0.05]]))
        #expect(three[2].height == 220)
        #expect(three[3].height == 220)
        #expect(three[1].height == 250)
    }

    @Test func paneEdgesStayOnWholePointsAfterBackingScaleRounding() {
        let odd = SplitStackLayoutTestsSupport.frames(SplitStackLayoutTestsSupport.columnStacks, size: CGSize(width: 1001, height: 701), scale: 2)
        #expect(odd.allSatisfy { [$0.minX, $0.minY, $0.maxX, $0.maxY].allSatisfy { $0 == $0.rounded() } })
    }

    @Test func panesInOneStackShareTheSlotsEdgesExactly() {
        let odd = SplitStackLayoutTestsSupport.frames(SplitStackLayoutTestsSupport.columnStacks, size: CGSize(width: 1001, height: 701), scale: 2)
        #expect(odd[0].minX == odd[1].minX)
        #expect(odd[0].maxX == odd[1].maxX)
    }

    @Test func theLastSlotAndLastStackedPaneReachTheFarEdges() {
        let odd = SplitStackLayoutTestsSupport.frames(SplitStackLayoutTestsSupport.columnStacks, size: CGSize(width: 1001, height: 701), scale: 2)
        #expect(odd[2].maxX == 1001)
        #expect(odd[1].maxY == 701)
    }

    @Test func theDeficitLoopMatchesTheFlatSplitsRedistribution() {
        let lengths = SplitStackGeometry.lengths([0.7, 0.2, 0.1], available: 1000, minimum: 220)
        #expect(lengths.map { Double($0) } == [560, 220, 220])
    }

    @Test func dividersFollowReadingOrder() {
        let column = Self.dividers(SplitStackLayoutTestsSupport.columnStacks)
        #expect(column.map(\.id) == [SplitStackDivider(slot: 0, index: 0), SplitStackDivider(slot: nil, index: 0)])
    }

    @Test func aStackDividerSpansOnlyItsColumn() {
        let divider = Self.dividers(SplitStackLayoutTestsSupport.columnStacks)[0]
        #expect(divider.rect == CGRect(x: 0, y: 350, width: 500, height: 10))
        #expect(!divider.isVerticalBar)
    }

    @Test func theStackedDividersEightPointEndInsetAppliesWithinItsColumn() {
        #expect(Self.dividers(SplitStackLayoutTestsSupport.columnStacks)[0].region == CGRect(x: 8, y: 350, width: 484, height: 10))
    }

    @Test func aMainRowDividerSpansTheWholeSplit() {
        let divider = Self.dividers(SplitStackLayoutTestsSupport.columnStacks)[1]
        #expect(divider.rect == CGRect(x: 500, y: 0, width: 10, height: 710))
        #expect(divider.isVerticalBar)
    }

    @Test func theMainRowSideBySideDividerKeepsTheTopBarClear() {
        #expect(Self.dividers(SplitStackLayoutTestsSupport.columnStacks)[1].region == CGRect(x: 500, y: 53, width: 10, height: 657))
    }

    @Test func aTopAndBottomSplitListsTheMainRowDividerBeforeTheLowerRowsDivider() {
        let rows = Self.dividers(SplitStackLayoutTestsSupport.stacks([1, 2], [0.5, 0.5], [[1], [0.5, 0.5]]), .vertical)
        #expect(rows.map(\.id) == [SplitStackDivider(slot: nil, index: 0), SplitStackDivider(slot: 1, index: 0)])
    }

    @Test func theMainRowDividerInATopAndBottomSplitSpansTheWidthWithTheEndInset() {
        let rows = Self.dividers(SplitStackLayoutTestsSupport.stacks([1, 2], [0.5, 0.5], [[1], [0.5, 0.5]]), .vertical)
        #expect(rows[0].rect == CGRect(x: 0, y: 350, width: 1010, height: 10))
        #expect(rows[0].region == CGRect(x: 8, y: 350, width: 994, height: 10))
    }

    @Test func aDividerInsideTheLowerRowSpansOnlyThatRow() {
        let rows = Self.dividers(SplitStackLayoutTestsSupport.stacks([1, 2], [0.5, 0.5], [[1], [0.5, 0.5]]), .vertical)
        #expect(rows[1].rect == CGRect(x: 500, y: 360, width: 10, height: 350))
        #expect(rows[1].isVerticalBar)
    }

    @Test func aDividerBetweenTwoLowerPanesStaysClearOfTheirHeaders() {
        let rows = Self.dividers(SplitStackLayoutTestsSupport.stacks([1, 2], [0.5, 0.5], [[1], [0.5, 0.5]]), .vertical)
        #expect(rows[1].region == CGRect(x: 500, y: 413, width: 10, height: 297))
    }

    struct DividerCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let pane: Int
        let slot: Int?
    }

    @Test(arguments: [
        DividerCase(testDescription: "Within the first slot", pane: 0, slot: 0),
        DividerCase(testDescription: "Between the two slots", pane: 1, slot: nil),
        DividerCase(testDescription: "Within the second slot", pane: 2, slot: 1),
    ])
    func twoStacksHaveADividerBetweenEveryReadingOrderPair(_ divider: DividerCase) {
        let four = SplitStackLayoutTestsSupport.stacks([2, 2], [0.5, 0.5], [[0.5, 0.5], [0.5, 0.5]])
        #expect(four.divider(after: divider.pane) == SplitStackDivider(slot: divider.slot, index: 0))
    }

    @Test func thereIsNoSplitterAfterTheLastPane() {
        let four = SplitStackLayoutTestsSupport.stacks([2, 2], [0.5, 0.5], [[0.5, 0.5], [0.5, 0.5]])
        #expect(four.divider(after: 3) == nil)
    }

    @Test func theSecondDividerInAThreePaneStackIsThatStacksSecondDivider() {
        #expect(SplitStackLayoutTestsSupport.stacks([3, 1], [0.5, 0.5], [[1, 1, 1], [1]]).divider(after: 1) == SplitStackDivider(slot: 0, index: 1))
    }

    @Test func framesThatDoNotMatchTheStackGiveNoDividers() {
        let four = SplitStackLayoutTestsSupport.stacks([2, 2], [0.5, 0.5], [[0.5, 0.5], [0.5, 0.5]])
        #expect(SplitStackGeometry.dividers(paneFrames: [.zero, .zero], size: .zero, orientation: .horizontal, stacks: four, thickness: 10).isEmpty)
    }
}
