import Foundation
import Testing
@testable import ParcCore

struct SplitStackLayoutMinimumsTests {
    struct LengthCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let weights: [Double]
        let available: CGFloat
        let expected: [CGFloat]
    }

    @Test(arguments: [
        LengthCase(testDescription: "Room beyond the minimum", weights: [0.7, 0.2, 0.1], available: 1000, expected: [560, 220, 220]),
        LengthCase(testDescription: "Just enough room for the minimums", weights: [0.6, 0.2, 0.2], available: 660, expected: [220, 220, 220]),
    ])
    func panesKeepTheirMinimumAndRedistributeTheDeficit(_ layout: LengthCase) {
        #expect(SplitStackGeometry.fittedLengths(layout.weights, available: layout.available, minimum: 220, scale: 2) == layout.expected)
    }

    enum FlatAxis: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case horizontal = "Side by side"
        case vertical = "Top and bottom"

        var testDescription: String { rawValue }
        var orientation: SplitOrientation { self == .horizontal ? .horizontal : .vertical }
        var factors: [Double] { self == .horizontal ? [0.25, 0.75] : [0.3, 0.7] }
        var frames: [CGRect] {
            switch self {
            case .horizontal:
                [CGRect(x: 0, y: 0, width: 250, height: 710), CGRect(x: 260, y: 0, width: 750, height: 710)]
            case .vertical:
                [CGRect(x: 0, y: 0, width: 1010, height: 220), CGRect(x: 0, y: 230, width: 1010, height: 480)]
            }
        }
    }

    @Test(arguments: FlatAxis.allCases)
    func aRoomyFlatSplitKeepsItsWeightsSubjectToTheMinimumOnItsAxis(_ axis: FlatAxis) {
        #expect(SplitStackLayoutTestsSupport.flat(axis.factors, axis.orientation, SplitStackLayoutTestsSupport.roomy) == axis.frames)
    }

    @Test func aSinglePageFillsItsPageAreaWithNoSplitMinimum() {
        #expect(SplitStackLayoutTestsSupport.flat([1], .horizontal, CGSize(width: 180, height: 140)) == [CGRect(x: 0, y: 0, width: 180, height: 140)])
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
        #expect(SplitStackLayoutTestsSupport.flat([0.6, 0.2, 0.2], .horizontal, SplitStackLayoutTestsSupport.page) == [CGRect(x: 0, y: 0, width: 160, height: 520),
                                                                    CGRect(x: 170, y: 0, width: 160, height: 520),
                                                                    CGRect(x: 340, y: 0, width: 160, height: 520)])
    }

    @Test func threeTopAndBottomPanesInAShortPageAreaShareItsHeight() {
        #expect(SplitStackLayoutTestsSupport.flat([1, 1, 1], .vertical, SplitStackLayoutTestsSupport.page) == [CGRect(x: 0, y: 0, width: 500, height: 167),
                                                             CGRect(x: 0, y: 177, width: 500, height: 166),
                                                             CGRect(x: 0, y: 353, width: 500, height: 167)])
    }

    @Test func aTopAndBottomSplitPutsNoWidthMinimumOnANarrowPageArea() {
        #expect(SplitStackLayoutTestsSupport.flat([1, 1, 1], .vertical, CGSize(width: 300, height: 860)) == [CGRect(x: 0, y: 0, width: 300, height: 280),
                                                                                   CGRect(x: 0, y: 290, width: 300, height: 280),
                                                                                   CGRect(x: 0, y: 580, width: 300, height: 280)])
    }

    @Test func aSideBySideSplitFillsAPageAreaShorterThanTheOldFloor() {
        #expect(SplitStackLayoutTestsSupport.flat([0.5, 0.5], .horizontal, CGSize(width: 600, height: 300)).allSatisfy { $0.height == 300 })
    }

    @Test func aThreePaneStackInAShortPageAreaSharesTheColumnWhileTheMainRowKeepsItsRoom() {
        let wide = CGSize(width: 1000, height: 520)
        let committed = SplitStackLayoutTestsSupport.frames(SplitStackLayoutTestsSupport.stacks([3, 1], [0.5, 0.5], [[1, 1, 1], [1]]), size: wide)
        #expect(SplitStackLayoutTestsSupport.fits(committed, wide))
        #expect(committed[0...2].allSatisfy { $0.width == 495 && abs($0.height - 500.0 / 3) < 1 })
        #expect(committed[3] == CGRect(x: 505, y: 0, width: 495, height: 520))
    }

    @Test func fourSlotsInANarrowPageAreaShareItsWidth() {
        let size = CGSize(width: 700, height: 520)
        let fourSlots = SplitStackLayoutTestsSupport.frames(BrowserSplitStacks.flat([0.4, 0.2, 0.2, 0.2]), size: size)
        #expect(SplitStackLayoutTestsSupport.fits(fourSlots, size))
        #expect(fourSlots.allSatisfy { abs($0.width - 167.5) <= 0.5 })
    }

    @Test func aStackDropPreviewInAShortPageAreaFitsAndShowsTheFramesTheDropCommits() throws {
        let wide = CGSize(width: 1000, height: 520)
        let reserved = try #require(SplitStackLayoutTestsSupport.columnStacks.reservingStack(besidePane: 1, after: true)).stacks
        let grown = try #require(BrowserSplitLayout(id: UUID(), spaceID: UUID(), tabIDs: [UUID(), UUID(), UUID()], orientation: .horizontal,
                                                    widthFactors: SplitStackLayoutTestsSupport.columnStacks.flattenedFactors, stacks: SplitStackLayoutTestsSupport.columnStacks)
            .insertingIntoStack(UUID(), besidePaneAt: 1, after: true))
        #expect(SplitStackLayoutTestsSupport.fits(SplitStackLayoutTestsSupport.frames(reserved, size: wide), wide))
        #expect(SplitStackLayoutTestsSupport.frames(reserved, size: wide) == SplitStackLayoutTestsSupport.frames(try #require(grown.stacks), size: wide))
    }

    @Test func startingAStackInAShortFlatSplitPreviewsInsideThePageArea() throws {
        let lone = try #require(BrowserSplitStacks.flat([0.5, 0.5]).reservingStack(besidePane: 0, after: true)).stacks
        let size = CGSize(width: 1000, height: 400)
        #expect(SplitStackLayoutTestsSupport.fits(SplitStackLayoutTestsSupport.frames(lone, size: size), size))
    }

    @Test func aMainRowDropPreviewInANarrowPageAreaFitsAndMatchesTheDroppedSplit() throws {
        let ids = [UUID(), UUID()], space = UUID()
        let pair = BrowserSplitLayout(id: UUID(), spaceID: space, tabIDs: ids, orientation: .horizontal, widthFactors: [0.75, 0.25], stacks: nil)
        let dropped = try #require(SplitDropTransaction.make(source: UUID(), selection: ids, layout: pair, target: .insert(1),
                                                             orientation: .horizontal, spaceID: space))
        let preview = BrowserSplitStacks.flat(pair.widthFactors).reservingSlot(at: 1).slotFactors
        #expect(SplitStackLayoutTestsSupport.flat(preview, .horizontal, SplitStackLayoutTestsSupport.page) == SplitStackLayoutTestsSupport.flat(dropped.widthFactors, .horizontal, SplitStackLayoutTestsSupport.page))
        #expect(SplitStackLayoutTestsSupport.fits(SplitStackLayoutTestsSupport.flat(preview, .horizontal, SplitStackLayoutTestsSupport.page), SplitStackLayoutTestsSupport.page))
    }

    struct MinimumCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let count: Int
        let available: CGFloat
        let expected: CGFloat
    }

    @Test(arguments: [
        MinimumCase(testDescription: "Roomy split", count: 3, available: 1000, expected: 220),
        MinimumCase(testDescription: "Squeezed split", count: 3, available: 480, expected: 160),
        MinimumCase(testDescription: "Single pane", count: 1, available: 100, expected: 220),
    ])
    func dividersAndStepsUseTheMinimumTheLayoutCanActuallyGive(_ layout: MinimumCase) {
        #expect(SplitStackGeometry.fittedMinimum(count: layout.count, available: layout.available, minimum: 220) == layout.expected)
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
}
