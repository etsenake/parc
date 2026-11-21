import Foundation
import Testing
@testable import ParcCore

struct EaselSnapFeedbackTests {
    private static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

    @Test func aNewGuideStartsTransparentAndIsFullyInAfterEightyMilliseconds() {
        #expect(Self.near(EaselFeedbackCurve.guideOpacity(0), 0))
        #expect(Self.near(EaselFeedbackCurve.guideOpacity(0.08), 1))
    }

    @Test func aGuideFadesInOnAnEaseOut() {
        #expect(EaselFeedbackCurve.guideOpacity(0.04) > 0.5)
    }

    @Test func endMarksStartSmallOvershootAndRestAtFullSize() {
        #expect(Self.near(EaselFeedbackCurve.markScale(0, reduced: false), EaselFeedbackCurve.markFrom))
        let peak = stride(from: 0.0, to: EaselFeedbackCurve.markPop, by: 0.005).map { EaselFeedbackCurve.markScale($0, reduced: false) }.max() ?? 0
        #expect(peak > 1)
        #expect(Self.near(EaselFeedbackCurve.markScale(1, reduced: false), 1))
    }

    @Test func reduceMotionKeepsEndMarksStill() {
        #expect(Self.near(EaselFeedbackCurve.markScale(0, reduced: true), 1))
    }

    @Test func theSameGuideKeepsOneKeyWhileHeld() {
        #expect(EaselGuideSnapKey(anchor: .left, coordinate: 120.001) == EaselGuideSnapKey(anchor: .left, coordinate: 120.002))
    }

    @Test func differentAnchorsAreDifferentEngagements() {
        #expect(EaselGuideSnapKey(anchor: .left, coordinate: 120.001) != EaselGuideSnapKey(anchor: .centerX, coordinate: 120))
    }

    private static let pieces: [[EaselConnectorRoute.Segment]] = [[.line(.init(x: 0, y: 0), .init(x: 100, y: 0)),
                                                                   .line(.init(x: 100, y: 0), .init(x: 100, y: 100))]]

    @Test func pieceLengthSumsSegments() {
        #expect(Self.near(EaselConnectorReveal.length(of: Self.pieces), 200))
    }

    @Test func halfARouteStopsAtTheCorner() {
        let half = EaselConnectorReveal.trimmed(Self.pieces, fraction: 0.5)
        #expect(half.count == 1 && half.first?.count == 1)
        #expect(half.first?.first?.end == EaselPoint(x: 100, y: 0))
    }

    @Test func aPartialSegmentIsCutAtItsArcLength() throws {
        let partial = EaselConnectorReveal.trimmed(Self.pieces, fraction: 0.75)
        let segments = try #require(partial.first)
        try #require(segments.count == 2)
        #expect(Self.near(segments[1].end.y, 50))
    }

    @Test func aFinishedRevealDrawsTheWholeRoute() {
        #expect(EaselConnectorReveal.trimmed(Self.pieces, fraction: 1) == Self.pieces)
    }

    @Test func aRevealStartsEmpty() {
        #expect(EaselConnectorReveal.trimmed(Self.pieces, fraction: 0).isEmpty)
    }

    @Test func aCurveRevealsByArcLength() {
        let curve: [[EaselConnectorRoute.Segment]] = [[.cubic(.init(x: 0, y: 0), .init(x: 0, y: 50), .init(x: 100, y: 50), .init(x: 100, y: 0))]]
        #expect(EaselConnectorReveal.tip(curve, fraction: 0.5).map { Self.near($0.x, 50, 2) } == true)
    }

    @Test func drawingStartsAtTheStartAndFinishesInAQuarterSecond() {
        #expect(Self.near(EaselFeedbackCurve.revealFraction(0, reduced: false), 0))
        #expect(Self.near(EaselFeedbackCurve.revealFraction(0.25, reduced: false), 1))
    }

    @Test func reduceMotionDrawsTheWholeConnectorAtOnce() {
        #expect(Self.near(EaselFeedbackCurve.revealFraction(0, reduced: true), 1))
    }

    @Test func anArrowheadPopsFromNothingOvershootsAndRestsAtFullSize() {
        #expect(Self.near(EaselFeedbackCurve.headScale(0, reduced: false), 0))
        let peak = stride(from: 0.0, to: EaselFeedbackCurve.headPop, by: 0.005).map { EaselFeedbackCurve.headScale($0, reduced: false) }.max() ?? 0
        #expect(peak > 1.02)
        #expect(Self.near(EaselFeedbackCurve.headScale(1, reduced: false), 1))
    }

    @Test func theHeadPopsAfterTheLineAndThenTheRevealEnds() {
        #expect(!EaselFeedbackCurve.revealFinished(0.3, reduced: false, drawsLine: true))
        #expect(EaselFeedbackCurve.revealFinished(0.7, reduced: false, drawsLine: true))
    }

    @Test func theReducedFadeIsShort() {
        #expect(EaselFeedbackCurve.revealFinished(0.16, reduced: true, drawsLine: true))
    }

    @Test func anAnchorDotGrowsFromItsSizeToItsTarget() {
        #expect(Self.near(EaselFeedbackCurve.highlighted(0, from: 4, to: 5.5), 4))
        #expect(Self.near(EaselFeedbackCurve.highlighted(1, from: 4, to: 5.5), 5.5))
    }

    @Test func aTrayBrightensInATenthOfASecond() {
        #expect(Self.near(EaselFeedbackCurve.trayLevel(0.1, from: 0, rising: true), 1))
    }

    @Test func aTrayDimsFromWhereItIs() {
        #expect(Self.near(EaselFeedbackCurve.trayLevel(0.1, from: 0.6, rising: false), 0))
    }

    @Test func aFlashPeaksQuicklyAndEnds() {
        #expect(Self.near(EaselFeedbackCurve.flashLevel(EaselFeedbackCurve.flashRise), 1))
        #expect(Self.near(EaselFeedbackCurve.flashLevel(EaselFeedbackCurve.flash), 0))
    }

    @Test func stickyGrowthRunsFromTheOldHeightToTheNewOne() {
        #expect(Self.near(EaselFeedbackCurve.grownValue(0, from: 220, to: 260), 220))
        #expect(Self.near(EaselFeedbackCurve.grownValue(1, from: 220, to: 260), 260))
    }

    @Test func tableSlidesRunFromZeroToOne() {
        #expect(Self.near(EaselFeedbackCurve.tableSlideProgress(0), 0))
        #expect(Self.near(EaselFeedbackCurve.tableSlideProgress(1), 1))
    }

    @Test(arguments: [(0.0, 0), (15, 1), (360, 0), (-15, 23)])
    func rotationSnapsInFifteenDegreeStepsThatWrapAroundTheCircle(degrees: Double, step: Int) {
        #expect(EaselRotationSnap.step(degrees) == step)
    }

    @Test func invalidAnglesHaveNoStep() {
        #expect(EaselRotationSnap.step(.nan) == nil)
    }

    private static func box(_ kind: EaselItemKind, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> EaselItem {
        EaselItem(kind: kind, frame: EaselRect(x: x, y: y, width: w, height: h), zIndex: 0)
    }

    private static let outer = box(.section, 0, 0, 800, 600)
    private static let inner = box(.section, 50, 50, 300, 300)
    private static let sticky = box(.sticky, 900, 900, 100, 100)

    private static func dropTarget(x: Double) -> UUID? {
        var moving = sticky
        moving.frame.x = x
        moving.frame.y = 100
        return EaselSectionDrop.target(moving: [moving], original: [sticky], in: [outer, inner, sticky])
    }

    @Test func theInnermostTrayLightsUp() {
        #expect(Self.dropTarget(x: 100) == Self.inner.id)
    }

    @Test func anOuterTrayLightsUpOutsideTheInnerOne() {
        #expect(Self.dropTarget(x: 500) == Self.outer.id)
    }

    @Test func halfInDoesNotCount() {
        #expect(Self.dropTarget(x: 760) == nil)
    }

    @Test func movingWithinATrayDoesNotLightIt() {
        let start = Self.box(.sticky, 400, 400, 50, 50)
        var inside = start
        inside.frame.x = 420
        #expect(EaselSectionDrop.target(moving: [inside], original: [start], in: [Self.outer, start]) == nil)
    }

    @Test func aFoldStartsWhereTheBranchIs() {
        #expect(EaselFeedbackCurve.foldPresentation(0, toward: EaselPoint(x: -100, y: 0), reduced: false).isIdentity)
    }

    @Test func aFoldEndsInTheParentTransparent() {
        let end = EaselFeedbackCurve.foldPresentation(EaselFeedbackCurve.fold, toward: EaselPoint(x: -100, y: 0), reduced: false)
        #expect(Self.near(end.opacity, 0) && Self.near(end.offset.x, -100))
    }

    @Test func reduceMotionFoldsByFadingOnly() {
        let reduced = EaselFeedbackCurve.foldPresentation(0.05, toward: EaselPoint(x: -100, y: 0), reduced: true)
        #expect(Self.near(reduced.offset.x, 0) && Self.near(reduced.scale, 1))
        #expect(reduced.opacity < 1)
    }

    @Test func deeperTopicsUnfoldLaterWithinAShortSpread() throws {
        let delays = EaselFeedbackCurve.unfoldDelays(depths: [1, 2, 2, 3])
        try #require(delays.count == 4)
        #expect(delays[0] == 0 && delays[1] == delays[2] && delays[3] > delays[1])
        #expect((delays.max() ?? 0) <= EaselFeedbackCurve.unfoldSpread + 1e-9)
    }

    @Test func oneLevelUnfoldsTogether() {
        #expect(EaselFeedbackCurve.unfoldDelays(depths: [2, 2]) == [0, 0])
    }

    private static let other = box(.rectangle, 400, 0, 200, 120)

    private static func snap(_ item: EaselItem, _ handle: EaselResizeHandle, scale: Double = 1, lockedX: Bool = false) -> (item: EaselItem, matches: [EaselSizeMatch]) {
        EaselEqualSize.snap(item, handle: handle, centered: false, candidates: [other], scale: scale, lockedX: lockedX, lockedY: false)
    }

    @Test func aRightEdgeResizeSnapsToAnEqualWidthAndReportsTheMatch() {
        let snapped = Self.snap(Self.box(.rectangle, 0, 0, 196, 80), .right)
        #expect(Self.near(snapped.item.frame.width, 200) && Self.near(snapped.item.frame.x, 0))
        #expect(snapped.matches == [EaselSizeMatch(other: Self.other.id, horizontal: true)])
    }

    @Test func aLeftEdgeResizeKeepsTheRightEdge() {
        let left = Self.snap(Self.box(.rectangle, 100, 0, 196, 80), .left)
        #expect(Self.near(left.item.frame.x + left.item.frame.width, 296) && Self.near(left.item.frame.width, 200))
    }

    @Test func anEngagedGuideWinsOverEqualSize() {
        #expect(Self.near(Self.snap(Self.box(.rectangle, 0, 0, 196, 80), .right, lockedX: true).item.frame.width, 196))
    }

    @Test func theEqualSizeToleranceIsMeasuredOnScreen() {
        #expect(Self.near(Self.snap(Self.box(.rectangle, 0, 0, 196, 80), .right, scale: 2).item.frame.width, 196))
    }

    @Test func aCornerSnapsBothSizesAndDrawsADimensionPairForEach() {
        let corner = Self.snap(Self.box(.rectangle, 0, 0, 196, 117), .bottomRight)
        #expect(Self.near(corner.item.frame.width, 200) && Self.near(corner.item.frame.height, 120))
        #expect(corner.matches.count == 2)
        #expect(EaselEqualSize.lines(corner.item, matches: corner.matches, in: [Self.other], scale: 1).count == 2)
    }

    @Test(arguments: [EaselItemKind.sticky, .text])
    func stickiesAndTextKeepTheirOwnSizing(kind: EaselItemKind) {
        #expect(!EaselEqualSize.resizes(kind))
    }
}
