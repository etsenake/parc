import Foundation
import Testing
@testable import ParcCore

struct SplitStackLayoutDropGeometryTests {
    private static func committed(_ value: BrowserSplitStacks, _ orientation: SplitOrientation = .horizontal, pane: Int, after: Bool) -> BrowserSplitStacks? {
        let layout = BrowserSplitLayout(id: UUID(), spaceID: UUID(), tabIDs: (0..<value.paneCount).map { _ in UUID() },
                                        orientation: orientation, widthFactors: value.flattenedFactors,
                                        stacks: value.slotSizes.contains { $0 > 1 } ? value : nil)
        return layout.insertingIntoStack(UUID(), besidePaneAt: pane, after: after)?.stacks
    }

    private static func matches(_ left: BrowserSplitStacks, _ right: BrowserSplitStacks?) -> Bool {
        guard let right else { return false }
        return left.slotSizes == right.slotSizes && SplitStackLayoutTestsSupport.close(left.slotFactors, right.slotFactors)
            && left.stackFactors.count == right.stackFactors.count
            && zip(left.stackFactors, right.stackFactors).allSatisfy { SplitStackLayoutTestsSupport.close($0, $1) }
    }

    private static func inside(_ region: CGRect, slotOf pane: CGRect, _ orientation: SplitOrientation = .horizontal) -> Bool {
        orientation == .horizontal ? region.minX == pane.minX && region.maxX == pane.maxX
                                   : region.minY == pane.minY && region.maxY == pane.maxY
    }

    @Test func aFlatSplitReadsAsOnePanePerSlot() {
        let pair = BrowserSplitStacks.flat([0.6, 0.4])
        #expect(pair.slotSizes == [1, 1])
        #expect(pair.slotFactors == [0.6, 0.4])
        #expect(pair.stackFactors == [[1], [1]])
    }

    @Test func stackingBelowTheFirstOfTwoPanesHalvesItsColumnAndKeepsTheSlotWeights() throws {
        let below = try #require(BrowserSplitStacks.flat([0.6, 0.4]).reservingStack(besidePane: 0, after: true))
        #expect(below.region == 1)
        #expect(below.stacks.slotSizes == [2, 1])
        #expect(below.stacks.slotFactors == [0.6, 0.4])
        #expect(below.stacks.stackFactors == [[0.5, 0.5], [1]])
    }

    @Test func theReservedShapeIsTheOneTheStoreCommits() throws {
        let pair = BrowserSplitStacks.flat([0.6, 0.4])
        let below = try #require(pair.reservingStack(besidePane: 0, after: true))
        #expect(Self.matches(below.stacks, Self.committed(pair, pane: 0, after: true)))
    }

    @Test func theRegionSitsUnderItsPaneWhileTheOtherColumnKeepsItsFullHeight() throws {
        let below = try #require(BrowserSplitStacks.flat([0.6, 0.4]).reservingStack(besidePane: 0, after: true))
        let belowFrames = SplitStackLayoutTestsSupport.frames(below.stacks)
        #expect(Self.inside(belowFrames[1], slotOf: belowFrames[0]))
        #expect(belowFrames[1].minY == belowFrames[0].maxY + 10)
        #expect(belowFrames[2].height == 710)
    }

    @Test func stackingAboveTheSecondPaneMakesTheRegionFirstInItsColumn() throws {
        let above = try #require(BrowserSplitStacks.flat([0.6, 0.4]).reservingStack(besidePane: 1, after: false))
        let aboveFrames = SplitStackLayoutTestsSupport.frames(above.stacks)
        #expect(above.region == 1)
        #expect(above.stacks.slotSizes == [1, 2])
        #expect(above.stacks.stackFactors == [[1], [0.5, 0.5]])
        #expect(Self.inside(aboveFrames[1], slotOf: aboveFrames[2]))
        #expect(aboveFrames[1].maxY + 10 == aboveFrames[2].minY)
    }

    @Test func threeFlatPanesStackTheMiddleOneInPlace() throws {
        let trio = BrowserSplitStacks.flat([0.5, 0.25, 0.25])
        let middle = try #require(trio.reservingStack(besidePane: 1, after: false))
        #expect(middle.region == 1)
        #expect(middle.stacks.slotSizes == [1, 2, 1])
        #expect(middle.stacks.stackFactors == [[1], [0.5, 0.5], [1]])
        #expect(Self.matches(middle.stacks, Self.committed(trio, pane: 1, after: false)))
    }

    @Test func onlyTheMiddleColumnDivides() throws {
        let middle = try #require(BrowserSplitStacks.flat([0.5, 0.25, 0.25]).reservingStack(besidePane: 1, after: false))
        let middleFrames = SplitStackLayoutTestsSupport.frames(middle.stacks)
        #expect(Self.inside(middleFrames[1], slotOf: middleFrames[2]))
        #expect(middleFrames[1].minY == 0)
        #expect(middleFrames[0].height == 710)
        #expect(middleFrames[3].height == 710)
    }

    @Test func aStackOfTwoGrowsToThreeWithTheNewcomerTakingAnAverageShareBeforeRenormalising() throws {
        let column = SplitStackLayoutTestsSupport.stacks([2, 1], [0.6, 0.4], [[0.3, 0.7], [1]])
        let grown = try #require(column.reservingStack(besidePane: 0, after: true))
        #expect(grown.region == 1)
        #expect(grown.stacks.slotSizes == [3, 1])
        #expect(grown.stacks.slotFactors == [0.6, 0.4])
        #expect(SplitStackLayoutTestsSupport.close(grown.stacks.stackFactors[0], [0.2, 1.0 / 3, 0.7 / 1.5]))
        #expect(grown.stacks.stackFactors[1] == [1])
    }

    @Test func theGrownStackMatchesTheStoresInsertion() throws {
        let column = SplitStackLayoutTestsSupport.stacks([2, 1], [0.6, 0.4], [[0.3, 0.7], [1]])
        let grown = try #require(column.reservingStack(besidePane: 0, after: true))
        #expect(Self.matches(grown.stacks, Self.committed(column, pane: 0, after: true)))
    }

    @Test func theRegionSitsBetweenTheStackedPanesInsideTheirColumn() throws {
        let column = SplitStackLayoutTestsSupport.stacks([2, 1], [0.6, 0.4], [[0.3, 0.7], [1]])
        let grownFrames = SplitStackLayoutTestsSupport.frames(try #require(column.reservingStack(besidePane: 0, after: true)).stacks)
        #expect(Self.inside(grownFrames[1], slotOf: grownFrames[0]))
        #expect(grownFrames[1].minY == grownFrames[0].maxY + 10)
        #expect(grownFrames[2].minY == grownFrames[1].maxY + 10)
    }

    @Test func stackingTheLoneColumnLeavesTheOtherStackAlone() throws {
        let column = SplitStackLayoutTestsSupport.stacks([2, 1], [0.6, 0.4], [[0.3, 0.7], [1]])
        let lone = try #require(column.reservingStack(besidePane: 2, after: true))
        #expect(lone.region == 3)
        #expect(lone.stacks.slotSizes == [2, 2])
        #expect(lone.stacks.stackFactors == [[0.3, 0.7], [0.5, 0.5]])
    }

    @Test func aTopAndBottomSplitStacksItsLowerRowLeftAndRight() throws {
        let rows = BrowserSplitStacks.flat([0.5, 0.5])
        let right = try #require(rows.reservingStack(besidePane: 1, after: true))
        #expect(right.region == 2)
        #expect(right.stacks.slotSizes == [1, 2])
        #expect(Self.matches(right.stacks, Self.committed(rows, .vertical, pane: 1, after: true)))
    }

    @Test func theRegionSitsRightOfItsPaneInsideThatRow() throws {
        let right = try #require(BrowserSplitStacks.flat([0.5, 0.5]).reservingStack(besidePane: 1, after: true))
        let rowFrames = SplitStackLayoutTestsSupport.frames(right.stacks, .vertical)
        #expect(Self.inside(rowFrames[2], slotOf: rowFrames[1], .vertical))
        #expect(rowFrames[2].minX == rowFrames[1].maxX + 10)
        #expect(rowFrames[0].width == 1010)
    }

    @Test func aPaneOutsideTheSplitReservesNothing() {
        #expect(SplitStackLayoutTestsSupport.stacks([2, 1], [0.6, 0.4], [[0.3, 0.7], [1]]).reservingStack(besidePane: 3, after: false) == nil)
    }

    @Test func aMalformedStackReservesNothing() {
        #expect(SplitStackLayoutTestsSupport.stacks([2, 1], [0.5, 0.5], [[1], [1]]).reservingStack(besidePane: 0, after: true) == nil)
    }
}
