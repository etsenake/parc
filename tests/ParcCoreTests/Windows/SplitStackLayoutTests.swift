import Foundation
import Testing
@testable import ParcCore

struct SplitStackLayoutTests {
    private static func close(_ left: [Double], _ right: [Double], _ tolerance: Double = 1e-9) -> Bool {
        left.count == right.count && zip(left, right).allSatisfy { abs($0 - $1) < tolerance }
    }

    private static func stacks(_ sizes: [Int], _ slots: [Double], _ inner: [[Double]]) -> BrowserSplitStacks {
        BrowserSplitStacks(slotSizes: sizes, slotFactors: slots, stackFactors: inner)
    }

    private static func frames(_ value: BrowserSplitStacks, _ orientation: SplitOrientation = .horizontal,
                               size: CGSize = CGSize(width: 1010, height: 710), scale: CGFloat = 2) -> [CGRect] {
        SplitStackGeometry.paneFrames(size: size, orientation: orientation, stacks: value,
                                      thickness: 10, minimum: 220, scale: scale)
    }

    private static func dividers(_ value: BrowserSplitStacks, _ orientation: SplitOrientation = .horizontal,
                                 size: CGSize = CGSize(width: 1010, height: 710)) -> [SplitStackGeometry.Divider] {
        SplitStackGeometry.dividers(paneFrames: frames(value, orientation, size: size), size: size,
                                    orientation: orientation, stacks: value, thickness: 10)
    }

    private static func flat(_ factors: [Double], _ orientation: SplitOrientation, _ size: CGSize) -> [CGRect] {
        SplitStackGeometry.flatFrames(size: size, orientation: orientation, factors: factors, thickness: 10, minimum: 220, scale: 2)
    }

    private static func fits(_ frames: [CGRect], _ size: CGSize) -> Bool {
        frames.allSatisfy { CGRect(origin: .zero, size: size).contains($0) }
    }

    private static let columnStacks = stacks([2, 1], [0.5, 0.5], [[0.5, 0.5], [1]])
    private static let roomy = CGSize(width: 1010, height: 710)
    private static let page = CGSize(width: 500, height: 520)

    @Test func aSideBySideSplitRunsItsSlotsAcrossAndStacksTheFirstColumnWithATenPointGap() {
        #expect(Self.frames(Self.columnStacks) == [CGRect(x: 0, y: 0, width: 500, height: 350), CGRect(x: 0, y: 360, width: 500, height: 350),
                                                   CGRect(x: 510, y: 0, width: 500, height: 710)])
    }

    @Test func aTopAndBottomSplitRunsItsRowsDownAndDividesTheFirstRow() {
        #expect(Self.frames(Self.columnStacks, .vertical) == [CGRect(x: 0, y: 0, width: 500, height: 350), CGRect(x: 510, y: 0, width: 500, height: 350),
                                                              CGRect(x: 0, y: 360, width: 1010, height: 350)])
    }

    @Test func aStackedPaneKeepsTheMinimumOnTheCrossAxisAndItsNeighbourGivesUpTheDeficit() {
        let squeezed = Self.frames(Self.stacks([2, 1], [0.5, 0.5], [[0.95, 0.05], [1]]))
        #expect(squeezed[1].height == 220)
        #expect(squeezed[0].height == 480)
        #expect(squeezed[1].minY == 490)
    }

    @Test func aSlotKeepsTheMinimumOnTheMainAxisAndBothStackPanesShareItsWidth() {
        let squeezed = Self.frames(Self.stacks([2, 1], [0.9, 0.1], [[0.5, 0.5], [1]]))
        #expect(squeezed[2].width == 220)
        #expect(squeezed[0].width == 780)
        #expect(squeezed[1].width == 780)
    }

    @Test func severalSqueezedStackPanesEachKeepTheMinimumAndTheRestRedistributes() {
        let three = Self.frames(Self.stacks([1, 3], [0.5, 0.5], [[1], [0.9, 0.05, 0.05]]))
        #expect(three[2].height == 220)
        #expect(three[3].height == 220)
        #expect(three[1].height == 250)
    }

    @Test func paneEdgesStayOnWholePointsAfterBackingScaleRounding() {
        let odd = Self.frames(Self.columnStacks, size: CGSize(width: 1001, height: 701), scale: 2)
        #expect(odd.allSatisfy { [$0.minX, $0.minY, $0.maxX, $0.maxY].allSatisfy { $0 == $0.rounded() } })
    }

    @Test func panesInOneStackShareTheSlotsEdgesExactly() {
        let odd = Self.frames(Self.columnStacks, size: CGSize(width: 1001, height: 701), scale: 2)
        #expect(odd[0].minX == odd[1].minX)
        #expect(odd[0].maxX == odd[1].maxX)
    }

    @Test func theLastSlotAndLastStackedPaneReachTheFarEdges() {
        let odd = Self.frames(Self.columnStacks, size: CGSize(width: 1001, height: 701), scale: 2)
        #expect(odd[2].maxX == 1001)
        #expect(odd[1].maxY == 701)
    }

    @Test func theDeficitLoopMatchesTheFlatSplitsRedistribution() {
        let lengths = SplitStackGeometry.lengths([0.7, 0.2, 0.1], available: 1000, minimum: 220)
        #expect(lengths.map { Double($0) } == [560, 220, 220])
    }

    @Test func dividersFollowReadingOrder() {
        let column = Self.dividers(Self.columnStacks)
        #expect(column.map(\.id) == [SplitStackDivider(slot: 0, index: 0), SplitStackDivider(slot: nil, index: 0)])
    }

    @Test func aStackDividerSpansOnlyItsColumn() {
        let divider = Self.dividers(Self.columnStacks)[0]
        #expect(divider.rect == CGRect(x: 0, y: 350, width: 500, height: 10))
        #expect(!divider.isVerticalBar)
    }

    @Test func theStackedDividersEightPointEndInsetAppliesWithinItsColumn() {
        #expect(Self.dividers(Self.columnStacks)[0].region == CGRect(x: 8, y: 350, width: 484, height: 10))
    }

    @Test func aMainRowDividerSpansTheWholeSplit() {
        let divider = Self.dividers(Self.columnStacks)[1]
        #expect(divider.rect == CGRect(x: 500, y: 0, width: 10, height: 710))
        #expect(divider.isVerticalBar)
    }

    @Test func theMainRowSideBySideDividerKeepsTheTopBarClear() {
        #expect(Self.dividers(Self.columnStacks)[1].region == CGRect(x: 500, y: 53, width: 10, height: 657))
    }

    @Test func aTopAndBottomSplitListsTheMainRowDividerBeforeTheLowerRowsDivider() {
        let rows = Self.dividers(Self.stacks([1, 2], [0.5, 0.5], [[1], [0.5, 0.5]]), .vertical)
        #expect(rows.map(\.id) == [SplitStackDivider(slot: nil, index: 0), SplitStackDivider(slot: 1, index: 0)])
    }

    @Test func theMainRowDividerInATopAndBottomSplitSpansTheWidthWithTheEndInset() {
        let rows = Self.dividers(Self.stacks([1, 2], [0.5, 0.5], [[1], [0.5, 0.5]]), .vertical)
        #expect(rows[0].rect == CGRect(x: 0, y: 350, width: 1010, height: 10))
        #expect(rows[0].region == CGRect(x: 8, y: 350, width: 994, height: 10))
    }

    @Test func aDividerInsideTheLowerRowSpansOnlyThatRow() {
        let rows = Self.dividers(Self.stacks([1, 2], [0.5, 0.5], [[1], [0.5, 0.5]]), .vertical)
        #expect(rows[1].rect == CGRect(x: 500, y: 360, width: 10, height: 350))
        #expect(rows[1].isVerticalBar)
    }

    @Test func aDividerBetweenTwoLowerPanesStaysClearOfTheirHeaders() {
        let rows = Self.dividers(Self.stacks([1, 2], [0.5, 0.5], [[1], [0.5, 0.5]]), .vertical)
        #expect(rows[1].region == CGRect(x: 500, y: 413, width: 10, height: 297))
    }

    @Test(arguments: [(0, SplitStackDivider(slot: 0, index: 0)), (1, SplitStackDivider(slot: nil, index: 0)), (2, SplitStackDivider(slot: 1, index: 0))])
    func fourPanesInTwoStacksGiveASplitterBetweenEachReadingOrderPair(_ pane: Int, _ expected: SplitStackDivider) {
        let four = Self.stacks([2, 2], [0.5, 0.5], [[0.5, 0.5], [0.5, 0.5]])
        #expect(four.divider(after: pane) == expected)
    }

    @Test func thereIsNoSplitterAfterTheLastPane() {
        let four = Self.stacks([2, 2], [0.5, 0.5], [[0.5, 0.5], [0.5, 0.5]])
        #expect(four.divider(after: 3) == nil)
    }

    @Test func theSecondDividerInAThreePaneStackIsThatStacksSecondDivider() {
        #expect(Self.stacks([3, 1], [0.5, 0.5], [[1, 1, 1], [1]]).divider(after: 1) == SplitStackDivider(slot: 0, index: 1))
    }

    @Test func framesThatDoNotMatchTheStackGiveNoDividers() {
        let four = Self.stacks([2, 2], [0.5, 0.5], [[0.5, 0.5], [0.5, 0.5]])
        #expect(SplitStackGeometry.dividers(paneFrames: [.zero, .zero], size: .zero, orientation: .horizontal, stacks: four, thickness: 10).isEmpty)
    }

    @Test func withRoomEveryPaneKeepsTheMinimumAndTheDeficitRedistributes() {
        #expect(SplitStackGeometry.fittedLengths([0.7, 0.2, 0.1], available: 1000, minimum: 220, scale: 2) == [560, 220, 220])
        #expect(SplitStackGeometry.fittedLengths([0.6, 0.2, 0.2], available: 660, minimum: 220, scale: 2) == [220, 220, 220])
    }

    @Test func aRoomyFlatSplitKeepsItsWeightsWithTheMinimumOnTheAxisItRuns() {
        #expect(Self.flat([0.25, 0.75], .horizontal, Self.roomy) == [CGRect(x: 0, y: 0, width: 250, height: 710), CGRect(x: 260, y: 0, width: 750, height: 710)])
        #expect(Self.flat([0.3, 0.7], .vertical, Self.roomy) == [CGRect(x: 0, y: 0, width: 1010, height: 220), CGRect(x: 0, y: 230, width: 1010, height: 480)])
    }

    @Test func aSinglePageFillsItsPageAreaWithNoSplitMinimum() {
        #expect(Self.flat([1], .horizontal, CGSize(width: 180, height: 140)) == [CGRect(x: 0, y: 0, width: 180, height: 140)])
    }

    @Test func shortOfRoomForEveryMinimumThePanesShareWhatThereIsEvenly() {
        #expect(SplitStackGeometry.fittedLengths([0.6, 0.2, 0.2], available: 480, minimum: 220, scale: 2) == [160, 160, 160])
    }

    @Test func evenSharesRoundDownAtTheWindowsScaleSoTheyNeverExceedTheRoom() {
        let odd = SplitStackGeometry.fittedLengths([1, 1, 1], available: 500, minimum: 220, scale: 1)
        #expect(odd == [166, 166, 166])
        #expect(odd.reduce(0, +) <= 500)
    }

    @Test func threeSideBySidePanesInANarrowPageAreaShareItInsteadOfSpillingPastItsEdge() {
        #expect(Self.flat([0.6, 0.2, 0.2], .horizontal, Self.page) == [CGRect(x: 0, y: 0, width: 160, height: 520),
                                                                    CGRect(x: 170, y: 0, width: 160, height: 520),
                                                                    CGRect(x: 340, y: 0, width: 160, height: 520)])
    }

    @Test func threeTopAndBottomPanesInAShortPageAreaShareItsHeight() {
        #expect(Self.flat([1, 1, 1], .vertical, Self.page) == [CGRect(x: 0, y: 0, width: 500, height: 167),
                                                             CGRect(x: 0, y: 177, width: 500, height: 166),
                                                             CGRect(x: 0, y: 353, width: 500, height: 167)])
    }

    @Test func aTopAndBottomSplitPutsNoWidthMinimumOnANarrowPageArea() {
        #expect(Self.flat([1, 1, 1], .vertical, CGSize(width: 300, height: 860)) == [CGRect(x: 0, y: 0, width: 300, height: 280),
                                                                                   CGRect(x: 0, y: 290, width: 300, height: 280),
                                                                                   CGRect(x: 0, y: 580, width: 300, height: 280)])
    }

    @Test func aSideBySideSplitFillsAPageAreaShorterThanTheOldFloor() {
        #expect(Self.flat([0.5, 0.5], .horizontal, CGSize(width: 600, height: 300)).allSatisfy { $0.height == 300 })
    }

    @Test func aThreePaneStackInAShortPageAreaSharesTheColumnWhileTheMainRowKeepsItsRoom() {
        let wide = CGSize(width: 1000, height: 520)
        let committed = Self.frames(Self.stacks([3, 1], [0.5, 0.5], [[1, 1, 1], [1]]), size: wide)
        #expect(Self.fits(committed, wide))
        #expect(committed[0...2].allSatisfy { $0.width == 495 && abs($0.height - 500.0 / 3) < 1 })
        #expect(committed[3] == CGRect(x: 505, y: 0, width: 495, height: 520))
    }

    @Test func fourSlotsInANarrowPageAreaShareItsWidth() {
        let size = CGSize(width: 700, height: 520)
        let fourSlots = Self.frames(BrowserSplitStacks.flat([0.4, 0.2, 0.2, 0.2]), size: size)
        #expect(Self.fits(fourSlots, size))
        #expect(fourSlots.allSatisfy { abs($0.width - 167.5) <= 0.5 })
    }

    @Test func aStackDropPreviewInAShortPageAreaFitsAndShowsTheFramesTheDropCommits() throws {
        let wide = CGSize(width: 1000, height: 520)
        let reserved = try #require(Self.columnStacks.reservingStack(besidePane: 1, after: true)).stacks
        let grown = try #require(BrowserSplitLayout(id: UUID(), spaceID: UUID(), tabIDs: [UUID(), UUID(), UUID()], orientation: .horizontal,
                                                    widthFactors: Self.columnStacks.flattenedFactors, stacks: Self.columnStacks)
            .insertingIntoStack(UUID(), besidePaneAt: 1, after: true))
        #expect(Self.fits(Self.frames(reserved, size: wide), wide))
        #expect(Self.frames(reserved, size: wide) == Self.frames(try #require(grown.stacks), size: wide))
    }

    @Test func startingAStackInAShortFlatSplitPreviewsInsideThePageArea() throws {
        let lone = try #require(BrowserSplitStacks.flat([0.5, 0.5]).reservingStack(besidePane: 0, after: true)).stacks
        let size = CGSize(width: 1000, height: 400)
        #expect(Self.fits(Self.frames(lone, size: size), size))
    }

    @Test func aMainRowDropPreviewInANarrowPageAreaFitsAndMatchesTheDroppedSplit() throws {
        let ids = [UUID(), UUID()], space = UUID()
        let pair = BrowserSplitLayout(id: UUID(), spaceID: space, tabIDs: ids, orientation: .horizontal, widthFactors: [0.75, 0.25], stacks: nil)
        let dropped = try #require(SplitDropTransaction.make(source: UUID(), selection: ids, layout: pair, target: .insert(1),
                                                             orientation: .horizontal, spaceID: space))
        let preview = BrowserSplitStacks.flat(pair.widthFactors).reservingSlot(at: 1).slotFactors
        #expect(Self.flat(preview, .horizontal, Self.page) == Self.flat(dropped.widthFactors, .horizontal, Self.page))
        #expect(Self.fits(Self.flat(preview, .horizontal, Self.page), Self.page))
    }

    @Test(arguments: [(3, 1000.0, 220.0), (3, 480.0, 160.0), (1, 100.0, 220.0)])
    func dividersAndStepsUseTheMinimumTheLayoutCanActuallyGive(_ count: Int, _ available: CGFloat, _ expected: CGFloat) {
        #expect(SplitStackGeometry.fittedMinimum(count: count, available: available, minimum: 220) == expected)
    }

    struct SqueezedCase: Sendable, CustomTestStringConvertible {
        let saved: [Double]
        let available: CGFloat
        let scale: CGFloat
        var testDescription: String { "saved \(saved) in \(available) points" }
        static let all = [SqueezedCase(saved: [1.0 / 3, 1.0 / 3, 1.0 / 3], available: 480, scale: 2),
                          SqueezedCase(saved: [0.6, 0.2, 0.2], available: 500, scale: 1),
                          SqueezedCase(saved: [0.6, 0.2, 0.2], available: 481, scale: 2)]

        func squeezed() -> (shares: [Double], minimum: Double) {
            let shown = SplitStackGeometry.fittedLengths(saved, available: available, minimum: 220, scale: scale).map { Double($0) }
            let minimum = SplitStackGeometry.fittedMinimum(count: 3, available: available, minimum: 220)
            let result = SplitStackGeometry.adjustableShares(saved: saved, shown: shown, available: Double(available), minimum: Double(minimum))!
            return (result.shares, result.minimum)
        }
    }

    @Test(arguments: SqueezedCase.all)
    func squeezedPanesCannotGrowFromTheFirst(_ c: SqueezedCase) {
        let s = c.squeezed()
        #expect(SplitPaneResize.resizingPane(0, in: s.shares, growing: true, minimum: s.minimum) == nil)
    }

    @Test(arguments: SqueezedCase.all)
    func squeezedPanesCannotShrinkTheSecond(_ c: SqueezedCase) {
        let s = c.squeezed()
        #expect(SplitPaneResize.resizingPane(1, in: s.shares, growing: false, minimum: s.minimum) == nil)
    }

    @Test(arguments: SqueezedCase.all)
    func squeezedPanesCannotMoveADividerForward(_ c: SqueezedCase) {
        let s = c.squeezed()
        #expect(SplitPaneResize.movingDivider(0, in: s.shares, forward: true, minimum: s.minimum) == nil)
    }

    @Test(arguments: SqueezedCase.all)
    func squeezedSplitterLimitsMeetAtTheirValue(_ c: SqueezedCase) {
        let s = c.squeezed()
        let positions = (0..<2).compactMap { SplitStackGeometry.splitterPosition(shares: s.shares, index: $0, minimum: s.minimum) }
        #expect(positions.count == 2)
        #expect(positions.allSatisfy { abs($0.minimum - $0.value) < 1e-9 && abs($0.maximum - $0.value) < 1e-9 })
    }

    @Test func aSplittersLimitsNeverCrossItsValue() throws {
        let crossing = try #require(SplitStackGeometry.splitterPosition(shares: [0.3, 0.3, 0.4], index: 0, minimum: 0.31))
        #expect(crossing.minimum <= crossing.value)
        #expect(crossing.maximum >= crossing.value)
    }

    private struct SnapStep { let distance: Double; let x: CGFloat; let y: CGFloat }

    private static func run(_ steps: [SnapStep], horizontal: Bool = false) -> (state: SplitDividerSnapState, haptics: [Bool]) {
        var state = SplitDividerSnapState()
        let haptics = steps.map { step in
            state.update(distance: step.distance,
                         velocity: SplitDividerSnapState.velocity(CGPoint(x: step.x, y: step.y), movingHorizontally: horizontal))
        }
        return (state, haptics)
    }

    @Test func aSideBySideDividerReadsSidewaysSpeedAndAnUpAndDownDividerReadsVerticalSpeed() {
        #expect(SplitDividerSnapState.velocity(CGPoint(x: -80, y: 500), movingHorizontally: true) == -80)
        #expect(SplitDividerSnapState.velocity(CGPoint(x: -80, y: 500), movingHorizontally: false) == 500)
    }

    @Test func anUpAndDownDividerEasedDownOntoTheCentreSnapsWithOneHaptic() {
        let fromAbove = Self.run([SnapStep(distance: -30, x: 2, y: 400), SnapStep(distance: -6, x: -1, y: 80)])
        #expect(fromAbove.state.isSnapped)
        #expect(fromAbove.haptics == [false, true])
    }

    @Test func easedUpOntoTheCentreFromBelowItSnapsToo() {
        let fromBelow = Self.run([SnapStep(distance: 30, x: -2, y: -400), SnapStep(distance: 6, x: 3, y: -80)])
        #expect(fromBelow.state.isSnapped)
        #expect(fromBelow.haptics == [false, true])
    }

    @Test(arguments: [true, false])
    func oneTwentyPointsPerSecondAlongTheDividersOwnAxisStillSnaps(_ fromBelow: Bool) {
        let steps = fromBelow ? [SnapStep(distance: 30, x: 0, y: -400), SnapStep(distance: 6, x: 0, y: -120)]
                              : [SnapStep(distance: -30, x: 0, y: 400), SnapStep(distance: -6, x: 0, y: 120)]
        #expect(Self.run(steps).state.isSnapped)
    }

    @Test(arguments: [true, false])
    func aQuickDragThroughTheCentrePassesStraightThrough(_ fromBelow: Bool) {
        let steps = fromBelow ? [SnapStep(distance: 30, x: 0, y: -400), SnapStep(distance: 6, x: 0, y: -121)]
                              : [SnapStep(distance: -30, x: 0, y: 400), SnapStep(distance: -6, x: 0, y: 121)]
        let result = Self.run(steps)
        #expect(!result.state.isSnapped)
        #expect(result.haptics == [false, false])
    }

    @Test(arguments: [true, false])
    func easingAwayFromTheCentreNeverSnaps(_ up: Bool) {
        let steps = up ? [SnapStep(distance: -30, x: 0, y: 900), SnapStep(distance: -4, x: 0, y: 900), SnapStep(distance: -6, x: 0, y: -50)]
                       : [SnapStep(distance: 30, x: 0, y: -900), SnapStep(distance: 4, x: 0, y: -900), SnapStep(distance: 6, x: 0, y: 50)]
        let result = Self.run(steps)
        #expect(!result.state.isSnapped)
        #expect(result.haptics == [false, false, false])
    }

    @Test func snappingWaitsUntilTheDividerHasMovedFourteenPointsAway() {
        #expect(!Self.run([SnapStep(distance: -6, x: 0, y: 30)]).state.isSnapped)
    }

    @Test func aSnappedDividerHoldsInsideTheBandThenReleasesWithOneHapticAsItLeaves() {
        var held = Self.run([SnapStep(distance: 30, x: -2, y: -400), SnapStep(distance: 6, x: 3, y: -80)]).state
        let velocity = SplitDividerSnapState.velocity(CGPoint(x: 0, y: -900), movingHorizontally: false)
        let stay = held.update(distance: -10, velocity: velocity)
        let release = held.update(distance: -14, velocity: velocity)
        let beyond = held.update(distance: -40, velocity: velocity)
        #expect(!stay)
        #expect(release)
        #expect(!beyond)
        #expect(!held.isSnapped)
    }

    @Test func aSideBySideDividerSnapsOnItsSidewaysSpeedAlone() {
        let sideways = Self.run([SnapStep(distance: 30, x: -400, y: 0), SnapStep(distance: 6, x: -80, y: 900)], horizontal: true)
        #expect(sideways.state.isSnapped)
        #expect(sideways.haptics == [false, true])
    }

    @Test func aSideBySideDividerEasingAwayDoesNotSnap() {
        let away = Self.run([SnapStep(distance: -30, x: 900, y: 0), SnapStep(distance: -4, x: 900, y: 0), SnapStep(distance: -6, x: -50, y: 900)], horizontal: true)
        #expect(!away.state.isSnapped)
    }

    @Test(arguments: [(0, 2, 0 as Int?, "Split View Divider 1, inside column 1", SplitOrientation.horizontal),
                      (1, 3, 0, "Split View Divider 2, inside column 1", .horizontal),
                      (1, 2, 1, "Split View Divider 2, inside row 2", .vertical),
                      (1, 2, nil, "Split View Divider 2", .horizontal),
                      (0, 1, nil, "Split View Divider", .horizontal)])
    func splittersAreLabelledWithTheirReadingOrderNumberAndContainer(_ index: Int, _ count: Int, _ slot: Int?, _ label: String, _ orientation: SplitOrientation) {
        #expect(SplitStackGeometry.splitterLabel(index: index, count: count, slot: slot, orientation: orientation) == label)
    }

    @Test func aStackSplitterReportsItsShareWithinItsSlotBoundedByTheMinimumOnEachSide() throws {
        let pair = try #require(SplitStackGeometry.splitterPosition(shares: [0.25, 0.75], index: 0, minimum: 0.2))
        #expect(Self.close([pair.value, pair.minimum, pair.maximum], [0.25, 0.2, 0.8]))
    }

    @Test func aLaterSplitterCountsThePanesBeforeIt() throws {
        let middle = try #require(SplitStackGeometry.splitterPosition(shares: [0.25, 0.25, 0.5], index: 1, minimum: 0.2))
        #expect(Self.close([middle.value, middle.minimum, middle.maximum], [0.5, 0.45, 0.8]))
    }

    @Test func aSplitterPastTheLastPairHasNoValue() {
        #expect(SplitStackGeometry.splitterPosition(shares: [0.5, 0.5], index: 1, minimum: 0.2) == nil)
    }

    @Test func validSavedStackSharesMeasureAgainstTheSlotsOwnLength() throws {
        let saved = try #require(SplitStackGeometry.adjustableShares(saved: [0.5, 0.5], shown: [350, 350], available: 700, minimum: 220))
        #expect(Self.close(saved.shares, [0.5, 0.5]))
        #expect(abs(saved.minimum - 220.0 / 700) < 1e-12)
    }

    @Test func sharesSqueezedBelowTheMinimumFallBackToWhatIsShown() throws {
        let shown = try #require(SplitStackGeometry.adjustableShares(saved: [0.95, 0.05], shown: [480, 220], available: 700, minimum: 220))
        #expect(Self.close(shown.shares, [480.0 / 700, 220.0 / 700]))
    }

    @Test func aRoomyPairDragsFromItsSavedShares() throws {
        let factors = try #require(SplitStackGeometry.resizableFactors(saved: [0.5, 0.5], shown: [350, 350], divider: 0, available: 700, minimum: 220))
        #expect(Self.close(factors, [0.5, 0.5]))
    }

    private static let commandValue = stacks([2, 1], [0.6, 0.4], [[0.3, 0.7], [1]])
    private static let commandIDs = [UUID(), UUID(), UUID()]
    private static func commandLayout() -> BrowserSplitLayout {
        BrowserSplitLayout(id: UUID(), spaceID: UUID(), tabIDs: commandIDs, orientation: .horizontal,
                           widthFactors: commandValue.flattenedFactors, stacks: commandValue)
    }

    @Test func expandGivesTheFocusedPaneTheLargestShareOnBothLevels() throws {
        let layout = Self.commandLayout()
        let expanded = try #require(layout.expanded(focusing: layout.tabIDs[1])?.stacks)
        #expect(expanded.slotFactors[0] > 0.999)
        #expect(expanded.stackFactors[0][1] > 0.999)
    }

    @Test func anExpandedStackedPaneLeavesItsNeighboursAtTheMinimumOnBothAxes() throws {
        let layout = Self.commandLayout()
        let expanded = try #require(layout.expanded(focusing: layout.tabIDs[1])?.stacks)
        let expandedFrames = Self.frames(expanded)
        #expect(expandedFrames[2].width == 220)
        #expect(expandedFrames[0].height == 220)
        #expect(expandedFrames[1].height == 480)
    }

    @Test func makeAllEqualEvensTheSlotsThenEachStack() throws {
        let equal = try #require(Self.commandLayout().resized(by: .equal)?.stacks)
        #expect(equal.slotFactors == [0.5, 0.5])
        #expect(equal.stackFactors == [[0.5, 0.5], [1]])
        #expect(equal.isEven)
    }

    @Test func evennessChecksBothLevels() {
        #expect(!Self.commandValue.isEven)
        #expect(Self.stacks([2, 2], [1, 1], [[2, 2], [3, 3]]).isEven)
    }

    @Test func widenStepsTheFocusedPanesSlotAlongTheMainRowOnly() throws {
        let widened = try #require(SplitPaneResize.resizingPane(0, in: Self.commandValue.slotFactors, growing: true, minimum: 0.22))
        let wide = try #require(Self.commandLayout().resized(by: .slots(widened))?.stacks)
        #expect(Self.close(wide.slotFactors, [0.7, 0.3]))
        #expect(wide.stackFactors == Self.commandValue.stackFactors)
    }

    @Test func narrowStepsTheSlotBackTowardEvenAndLeavesTheStackAlone() throws {
        let narrowed = try #require(SplitPaneResize.resizingPane(0, in: Self.commandValue.slotFactors, growing: false, minimum: 0.22))
        let narrow = try #require(Self.commandLayout().resized(by: .slots(narrowed))?.stacks)
        #expect(Self.close(narrow.slotFactors, [0.5, 0.5]))
        #expect(narrow.stackFactors == Self.commandValue.stackFactors)
    }

    @Test func eveningAStackDividerMovesOnlyItsTwoPanes() throws {
        let divider = try #require(Self.commandLayout().resized(by: .divider(0, slot: 0, leadingShare: 0.5))?.stacks)
        #expect(Self.close(divider.stackFactors[0], [0.5, 0.5]))
        #expect(Self.close(divider.slotFactors, Self.commandValue.slotFactors))
    }

    @Test func aMainRowDividerMovesOnlyItsTwoSlots() throws {
        let divider = try #require(Self.commandLayout().resized(by: .divider(0, slot: nil, leadingShare: 0.25))?.stacks)
        #expect(Self.close(divider.slotFactors, [0.25, 0.75]))
        #expect(divider.stackFactors == Self.commandValue.stackFactors)
    }

    @Test func aKeyboardStepOnAStackDividerUsesTheSlotsOwnShares() throws {
        let stepped = try #require(SplitPaneResize.movingDivider(0, in: [0.3, 0.7], forward: true, minimum: 0.3))
        #expect(Self.close(stepped, [0.4, 0.6]))
    }

    @Test func aDividerOutsideTheStackIsRefused() {
        #expect(Self.commandLayout().resized(by: .divider(1, slot: 0, leadingShare: 0.5)) == nil)
    }

    @Test func aPairSqueezedBelowTheMinimumDragsFromWhatIsShown() throws {
        let squeezed = try #require(SplitStackGeometry.resizableFactors(saved: [0.05, 0.24, 0.71], shown: [220, 318, 942], divider: 0, available: 1480, minimum: 220))
        #expect(Self.close(squeezed, [220.0 / 1480, 318.0 / 1480, 942.0 / 1480]))
    }

    @Test func aSqueezedDragSavesItsWholeLevelAsPreviewedSoTheOtherSlotKeepsItsSize() throws {
        let three = Self.stacks([1, 1, 2], [0.05, 0.24, 0.71], [[1], [1], [0.5, 0.5]])
        let trio = BrowserSplitLayout(id: UUID(), spaceID: UUID(), tabIDs: [UUID(), UUID(), UUID(), UUID()], orientation: .horizontal,
                                      widthFactors: three.flattenedFactors, stacks: three)
        let whole = try #require(trio.resized(by: .level(slot: nil, factors: [269.0 / 1480, 269.0 / 1480, 942.0 / 1480]))?.stacks)
        #expect(Self.close(whole.slotFactors, [269.0 / 1480, 269.0 / 1480, 942.0 / 1480]))
        #expect(whole.stackFactors == three.stackFactors)
    }

    @Test func aWholeLevelSaveInsideAStackChangesOnlyThatStack() throws {
        let inner = try #require(Self.commandLayout().resized(by: .level(slot: 0, factors: [0.2, 0.8]))?.stacks)
        #expect(Self.close(inner.stackFactors[0], [0.2, 0.8]))
        #expect(Self.close(inner.slotFactors, Self.commandValue.slotFactors))
    }

    @Test func aLiveDragReplacesOnlyItsOwnLevel() {
        #expect(Self.commandValue.replacing([0.2, 0.8], inSlot: 0).stackFactors[0] == [0.2, 0.8])
        #expect(Self.commandValue.replacing([0.1, 0.9], inSlot: nil).slotFactors == [0.1, 0.9])
    }

    @Test func aMainRowDropReservationMakesAWholeNewSlot() {
        let reserved = Self.commandValue.reservingSlot(at: 1)
        #expect(reserved.slotSizes == [2, 1, 1])
        #expect(Self.close(reserved.slotFactors, [0.4, 1.0 / 3, 0.4 * 2 / 3]))
        #expect(reserved.stackFactors == [[0.3, 0.7], [1], [1]])
    }

    private static func committed(_ value: BrowserSplitStacks, _ orientation: SplitOrientation = .horizontal, pane: Int, after: Bool) -> BrowserSplitStacks? {
        let layout = BrowserSplitLayout(id: UUID(), spaceID: UUID(), tabIDs: (0..<value.paneCount).map { _ in UUID() },
                                        orientation: orientation, widthFactors: value.flattenedFactors,
                                        stacks: value.slotSizes.contains { $0 > 1 } ? value : nil)
        return layout.insertingIntoStack(UUID(), besidePaneAt: pane, after: after)?.stacks
    }

    private static func matches(_ left: BrowserSplitStacks, _ right: BrowserSplitStacks?) -> Bool {
        guard let right else { return false }
        return left.slotSizes == right.slotSizes && close(left.slotFactors, right.slotFactors)
            && left.stackFactors.count == right.stackFactors.count
            && zip(left.stackFactors, right.stackFactors).allSatisfy { close($0, $1) }
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
        let belowFrames = Self.frames(below.stacks)
        #expect(Self.inside(belowFrames[1], slotOf: belowFrames[0]))
        #expect(belowFrames[1].minY == belowFrames[0].maxY + 10)
        #expect(belowFrames[2].height == 710)
    }

    @Test func stackingAboveTheSecondPaneMakesTheRegionFirstInItsColumn() throws {
        let above = try #require(BrowserSplitStacks.flat([0.6, 0.4]).reservingStack(besidePane: 1, after: false))
        let aboveFrames = Self.frames(above.stacks)
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
        let middleFrames = Self.frames(middle.stacks)
        #expect(Self.inside(middleFrames[1], slotOf: middleFrames[2]))
        #expect(middleFrames[1].minY == 0)
        #expect(middleFrames[0].height == 710)
        #expect(middleFrames[3].height == 710)
    }

    @Test func aStackOfTwoGrowsToThreeWithTheNewcomerTakingAnAverageShareBeforeRenormalising() throws {
        let column = Self.stacks([2, 1], [0.6, 0.4], [[0.3, 0.7], [1]])
        let grown = try #require(column.reservingStack(besidePane: 0, after: true))
        #expect(grown.region == 1)
        #expect(grown.stacks.slotSizes == [3, 1])
        #expect(grown.stacks.slotFactors == [0.6, 0.4])
        #expect(Self.close(grown.stacks.stackFactors[0], [0.2, 1.0 / 3, 0.7 / 1.5]))
        #expect(grown.stacks.stackFactors[1] == [1])
    }

    @Test func theGrownStackMatchesTheStoresInsertion() throws {
        let column = Self.stacks([2, 1], [0.6, 0.4], [[0.3, 0.7], [1]])
        let grown = try #require(column.reservingStack(besidePane: 0, after: true))
        #expect(Self.matches(grown.stacks, Self.committed(column, pane: 0, after: true)))
    }

    @Test func theRegionSitsBetweenTheStackedPanesInsideTheirColumn() throws {
        let column = Self.stacks([2, 1], [0.6, 0.4], [[0.3, 0.7], [1]])
        let grownFrames = Self.frames(try #require(column.reservingStack(besidePane: 0, after: true)).stacks)
        #expect(Self.inside(grownFrames[1], slotOf: grownFrames[0]))
        #expect(grownFrames[1].minY == grownFrames[0].maxY + 10)
        #expect(grownFrames[2].minY == grownFrames[1].maxY + 10)
    }

    @Test func stackingTheLoneColumnLeavesTheOtherStackAlone() throws {
        let column = Self.stacks([2, 1], [0.6, 0.4], [[0.3, 0.7], [1]])
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
        let rowFrames = Self.frames(right.stacks, .vertical)
        #expect(Self.inside(rowFrames[2], slotOf: rowFrames[1], .vertical))
        #expect(rowFrames[2].minX == rowFrames[1].maxX + 10)
        #expect(rowFrames[0].width == 1010)
    }

    @Test func aPaneOutsideTheSplitReservesNothing() {
        #expect(Self.stacks([2, 1], [0.6, 0.4], [[0.3, 0.7], [1]]).reservingStack(besidePane: 3, after: false) == nil)
    }

    @Test func aMalformedStackReservesNothing() {
        #expect(Self.stacks([2, 1], [0.5, 0.5], [[1], [1]]).reservingStack(besidePane: 0, after: true) == nil)
    }

    private struct Pending {
        let ids = [UUID(), UUID(), UUID()]
        let stacked: BrowserState
        let flat: BrowserState

        init() {
            let profile = BrowserProfile(id: UUID(), name: "Profile")
            let space = BrowserSpace(id: UUID(), name: "Home", symbol: "circle", color: "000000", profileID: profile.id)
            func state(_ layout: BrowserSplitLayout) -> BrowserState {
                var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
                state.tabs = layout.tabIDs.enumerated().map { index, id in
                    BrowserTab(id: id, spaceID: space.id, profileID: profile.id, url: "https://\(index).test/", title: "T\(index)",
                               kind: .today, createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10),
                               savedURL: "https://\(index).test/", savedTitle: "T\(index)")
                }
                state.splitLayouts = [layout]
                state.selectedTabIDs = layout.tabIDs
                return state
            }
            let ids = ids
            let value = SplitStackLayoutTests.stacks([2, 1], [0.5, 0.5], [[0.5, 0.5], [1]])
            stacked = state(BrowserSplitLayout(id: UUID(), spaceID: space.id, tabIDs: ids, orientation: .horizontal,
                                               widthFactors: value.flattenedFactors, stacks: value))
            flat = state(BrowserSplitLayout(spaceID: space.id, tabIDs: [ids[0], ids[1]], orientation: .horizontal, widthFactors: [0.5, 0.5]))
        }
    }

    @Test func aPendingPaneBelowTheLoneColumnRendersInsideThatColumnAfterItsPane() throws {
        let p = Pending()
        let below = try #require(SplitPaneInsertion(paneID: p.ids[2], stackingAfter: true, state: p.stacked))
        #expect(below.index == 3)
        #expect(below.previewLayout?.stacks?.slotSizes == [2, 2])
        #expect(below.previewLayout?.orientation == .horizontal)
    }

    @Test func thePendingStackedPreviewKeepsAValidFlatRow() throws {
        let p = Pending()
        let below = try #require(SplitPaneInsertion(paneID: p.ids[2], stackingAfter: true, state: p.stacked))
        #expect(below.previewFactors.count == 4)
        #expect(abs(below.previewFactors.reduce(0, +) - 1) < 1e-9)
    }

    @Test func aPendingPaneAboveTheTopLeftPaneJoinsItsStackAtTheTop() throws {
        let p = Pending()
        let above = try #require(SplitPaneInsertion(paneID: p.ids[0], stackingAfter: false, state: p.stacked))
        #expect(above.index == 0)
        #expect(above.previewLayout?.stacks?.slotSizes == [3, 1])
    }

    @Test func aPendingMainRowPaneBesideAStackRendersAsItsOwnFullLengthSlot() throws {
        let p = Pending()
        let mainRow = try #require(SplitPaneInsertion(paneID: p.ids[1], operation: .addAfter, state: p.stacked))
        #expect(mainRow.index == 2)
        #expect(mainRow.previewLayout?.stacks?.slotSizes == [2, 1, 1])
    }

    @Test func anAddThatWouldChangeAStackedSplitsDirectionNeverOpensAPendingPane() {
        let p = Pending()
        #expect(SplitPaneInsertion(paneID: p.ids[0], operation: .addBelow, state: p.stacked) == nil)
    }

    @Test func aFlatSplitsPendingPaneKeepsTodaysFlatPreview() throws {
        let p = Pending()
        let flatAdd = try #require(SplitPaneInsertion(paneID: p.ids[1], operation: .addAfter, state: p.flat))
        #expect(flatAdd.previewLayout == nil)
        #expect(Self.close(flatAdd.previewFactors, [1.0 / 3, 1.0 / 3, 1.0 / 3]))
    }

    @Test func stackingAPaneInAFlatSplitPreviewsTheNewStack() throws {
        let p = Pending()
        let flatStack = try #require(SplitPaneInsertion(paneID: p.ids[0], stackingAfter: true, state: p.flat))
        #expect(flatStack.index == 1)
        #expect(flatStack.previewLayout?.stacks?.slotSizes == [2, 1])
    }

    private struct Pictures {
        let items: [RecentTabOrder.Item]
        let ids: [UUID]

        init() {
            var order = RecentTabOrder()
            let profile = BrowserProfile(id: UUID(), name: "Profile")
            let space = BrowserSpace(id: UUID(), name: "Home", symbol: "circle", color: "000000", profileID: profile.id)
            let ids = [UUID(), UUID(), UUID(), UUID()]
            var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
            state.tabs = ids.enumerated().map { index, id in
                BrowserTab(id: id, spaceID: space.id, profileID: profile.id, url: "https://\(index).test/", title: "T\(index)",
                           kind: .today, createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10),
                           savedURL: "https://\(index).test/", savedTitle: "T\(index)")
            }
            let value = SplitStackLayoutTests.stacks([1, 2], [0.5, 0.5], [[1], [0.5, 0.5]])
            state.splitLayouts = [BrowserSplitLayout(id: UUID(), spaceID: space.id, tabIDs: Array(ids.prefix(3)), orientation: .vertical,
                                                     widthFactors: value.flattenedFactors, stacks: value)]
            items = order.items(state: state, selected: [ids[3]], currentSpace: space.id) { _ in true }
            self.ids = ids
        }
    }

    @Test func theTabSwitcherLearnsTheSplitsRealStackedShape() {
        let p = Pictures()
        let split = p.items.first { $0.tabIDs.count == 3 }
        #expect(split?.slotSizes == [1, 2])
        #expect(split?.orientation == .vertical)
    }

    @Test func aSinglePageHasNoStackedShape() {
        let p = Pictures()
        #expect(p.items.first { $0.tabIDs == [p.ids[3]] }?.slotSizes == nil)
    }
}
