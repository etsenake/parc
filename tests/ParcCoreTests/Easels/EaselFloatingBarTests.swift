import Foundation
import Testing
@testable import ParcCore

struct EaselFloatingBarTests {
    private static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

    private static func bar(width: Double = 1000, height: Double = 700) -> EaselRect {
        EaselFloatingBar.frame(containerWidth: width, containerHeight: height, preferredWidth: 600, height: 36, top: 72)
    }

    private static let placed = EaselRect(x: 200, y: 648, width: 600, height: 36)
    private static let visible = EaselRect(x: 100, y: 200, width: 400, height: 300)

    @Test func theBarIsCentredAndFloatsSixteenPointsAboveTheBottom() {
        #expect(Self.bar() == Self.placed)
    }

    @Test func aNarrowWindowClampsTheBarInsideTwelvePointSideMargins() {
        let narrow = Self.bar(width: 400)
        #expect(narrow.width == 376 && narrow.x == 12)
    }

    @Test func aVeryShortWindowKeepsTheBarUnderTheTitleRow() {
        #expect(Self.bar(height: 100).y == 72)
    }

    @Test(arguments: [Double.nan, 10])
    func invalidOrTooNarrowWindowsGiveTheBarNoWidth(width: Double) {
        #expect(Self.bar(width: width).width == 0)
    }

    @Test func theCoveredBandRunsFromTheBarsTopPlusClearanceToTheBottom() {
        #expect(EaselFloatingBar.coveredBottom(containerHeight: 700, bar: Self.placed) == 60)
    }

    @Test func anEmptyBarCoversNothing() {
        #expect(EaselFloatingBar.coveredBottom(containerHeight: 700, bar: EaselRect(x: 0, y: 0, width: 0, height: 0)) == 0)
    }

    @Test func theBarNeverClaimsMoreThanHalfOfATinyViewport() {
        #expect(EaselFloatingBar.cover(60, viewportHeight: 100) == 50)
    }

    @Test func negativeCoverIsIgnored() {
        #expect(EaselFloatingBar.cover(-5, viewportHeight: 600) == 0)
    }

    @Test func zoomedInTheCoveredBandShrinksInDocumentPoints() {
        #expect(EaselFloatingBar.uncovered(Self.visible, coveredBottom: 60, magnification: 2) == EaselRect(x: 100, y: 200, width: 400, height: 270))
    }

    @Test func zoomedOutTheCoveredBandGrowsInDocumentPoints() {
        #expect(Self.near(EaselFloatingBar.uncovered(Self.visible, coveredBottom: 60, magnification: 0.5).height, 180))
    }

    @Test(arguments: [(60.0, 0.0), (0, 1)])
    func invalidZoomOrNoBarLeavesTheViewWhole(coveredBottom: Double, magnification: Double) {
        #expect(EaselFloatingBar.uncovered(Self.visible, coveredBottom: coveredBottom, magnification: magnification) == Self.visible)
    }

    @Test func fittingUsesTheViewportAboveTheBar() {
        let room = EaselFloatingBar.viewport(width: 800, height: 600, coveredBottom: 60)
        #expect(room.width == 800 && room.height == 540)
    }

    @Test func theClipCentreDropsByHalfTheCoverSoContentCentresAboveTheBar() {
        let centre = EaselFloatingBar.clipCentre(showing: EaselPoint(x: 500, y: 400), coveredBottom: 60, viewportHeight: 600, magnification: 1)
        #expect(centre == EaselPoint(x: 500, y: 430))
        #expect(Self.near((centre.y - 300 + centre.y + 300 - 60) / 2, 400))
    }

    @Test func theCentreShiftScalesWithZoom() {
        let zoomed = EaselFloatingBar.clipCentre(showing: EaselPoint(x: 500, y: 400), coveredBottom: 60, viewportHeight: 600, magnification: 2)
        #expect(Self.near(zoomed.y, 415))
    }

    @Test func zoomToFitLeavesRoomForTheBar() {
        let content = EaselRect(x: 0, y: 0, width: 400, height: 1000)
        let room = EaselFloatingBar.viewport(width: 800, height: 600, coveredBottom: 60)
        let plain = EaselZoom.fitting(content, viewport: (800, 600), minimum: 0.25, maximum: 4) ?? 0
        let covered = EaselZoom.fitting(content, viewport: room, minimum: 0.25, maximum: 4) ?? 0
        #expect(covered < plain)
    }

    @Test func theRecenterChipFloatsTenPointsAboveTheBar() {
        let chip = EaselFloatingBar.chipFrame(width: 120, height: 28, containerWidth: 1000, bar: Self.placed, top: 64)
        #expect(chip == EaselRect(x: 440, y: 610, width: 120, height: 28))
    }

    @Test func theChipNeverRisesAboveTheCanvasTop() {
        let cramped = EaselFloatingBar.chipFrame(width: 120, height: 28, containerWidth: 1000, bar: EaselRect(x: 0, y: 70, width: 10, height: 36), top: 64)
        #expect(cramped.y == 64)
    }

    @Test func theCurrentToolPillHugsItsButton() {
        #expect(EaselFloatingBar.pillFrame(button: EaselRect(x: 40, y: 4, width: 28, height: 28), inset: 1) == EaselRect(x: 41, y: 5, width: 26, height: 26))
    }

    @Test(arguments: [
        (EaselTool.select, nil), (.sticky, .hop), (.marker, .tilt), (.highlighter, .tilt), (.eraser, .wiggle), (.stamp, .thump), (.hand, .open),
        (.rectangle, .pop), (.ellipse, .pop), (.elbowConnector, .pop), (.curvedConnector, .pop), (.straightConnector, .pop),
    ] as [(EaselTool, EaselToolFlourish?)])
    func eachToolHasItsFlourish(tool: EaselTool, flourish: EaselToolFlourish?) {
        #expect(EaselToolFlourish.flourish(for: tool) == flourish)
    }

    private static let flourishes: [EaselToolFlourish] = [.hop, .tilt, .wiggle, .thump, .pop, .open]

    @Test(arguments: flourishes)
    func aFlourishStartsAndEndsAtRestAndMovesBetween(flourish: EaselToolFlourish) {
        let frames = flourish.frames()
        #expect(frames.first?.isRest == true && frames.last?.isRest == true)
        #expect(frames.contains { !$0.isRest })
    }

    @Test(arguments: flourishes)
    func aFlourishSettlesQuickly(flourish: EaselToolFlourish) {
        #expect(flourish.duration >= 0.3 && flourish.duration <= 0.45)
    }

    @Test(arguments: flourishes)
    func aFlourishRestsOutsideItsRun(flourish: EaselToolFlourish) {
        #expect(flourish.frame(at: -1).isRest)
        #expect(flourish.frame(at: flourish.duration + 1).isRest)
    }

    @Test(arguments: flourishes)
    func aFlourishMovesSmoothlyBetweenFramesNeverJumping(flourish: EaselToolFlourish) {
        let frames = flourish.frames()
        let biggestStep = zip(frames, frames.dropFirst()).map { a, b in
            max(abs(a.dx - b.dx), abs(a.dy - b.dy), abs(a.rotation - b.rotation) / 10, abs(a.scaleX - b.scaleX) * 20, abs(a.scaleY - b.scaleY) * 20)
        }.max() ?? 0
        #expect(biggestStep < 2.5)
    }

    @Test func theStickyHopsAboutFourPointsUp() {
        #expect(Self.near(EaselToolFlourish.hop.frames().map(\.dy).min() ?? 0, -4, 0.15))
    }

    @Test func theStampSquashesFirstThenPops() {
        let thump = EaselToolFlourish.thump.frames()
        #expect((thump.first { !$0.isRest }?.scaleY ?? 1) < 1)
        #expect(thump.contains { $0.scaleY > 1 })
    }

    @Test func theEraserWigglesBackAndForth() {
        let wiggle = EaselToolFlourish.wiggle.frames().map(\.rotation).filter { abs($0) > 0.5 }
        #expect(zip(wiggle, wiggle.dropFirst()).filter { ($0 > 0) != ($1 > 0) }.count >= 2)
    }

    @Test func aKickStartsAtRest() {
        #expect(Self.near(EaselToolFlourish.kick(at: 0, response: 0.3, damping: 0.5), 0))
    }

    @Test func aKickPeaksAtItsFullAmplitude() {
        let peak = (1...400).map { EaselToolFlourish.kick(at: Double($0) / 1000, response: 0.3, damping: 0.5) }.max() ?? 0
        #expect(Self.near(peak, 1, 0.01))
    }

    @Test func overdampedKicksAreIgnored() {
        #expect(EaselToolFlourish.kick(at: 0.1, response: 0.3, damping: 1.2) == 0)
    }
}
