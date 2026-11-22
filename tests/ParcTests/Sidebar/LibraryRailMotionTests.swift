import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcLibrary

struct LibraryRailMotionTests {
    struct Composition: Sendable, CustomTestStringConvertible {
        let name: String
        var testDescription: String { name }
    }

    static let compositions = ["screenshots", "downloads", "easels", "spaces", "archive"].map(Composition.init)

    static func animation(_ name: String) throws -> LibraryRailAnimation {
        let url = try #require(Bundle.module.url(forResource: "ChromeFixtures", withExtension: nil))
            .appendingPathComponent("Library/\(name).json")
        return try #require(LibraryRailAnimation(data: Data(contentsOf: url)))
    }

    private static func markers(_ name: String) throws -> (animation: LibraryRailAnimation, from: Double, windup: Double, end: Double) {
        let animation = try animation(name)
        return (animation, try #require(animation.frame(forMarker: "hover-start")), try #require(animation.frame(forMarker: "hover-end")),
                try #require(animation.frame(forMarker: "selection-end")))
    }

    private static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }

    private static func controlPoints(_ timing: CAMediaTimingFunction?) -> [Float] {
        guard let timing else { return [] }
        var first = [Float](repeating: 0, count: 2), second = first
        timing.getControlPoint(at: 1, values: &first)
        timing.getControlPoint(at: 2, values: &second)
        return first + second
    }

    @Test(arguments: compositions)
    func eachCompositionHopsOverALittleUnderASecondWellBehindItsOwnPace(_ composition: Composition) throws {
        let (animation, from, _, end) = try Self.markers(composition.name)
        let duration = LibraryRailMotion.playbackDuration(from: from, to: end, frameRate: animation.frameRate)
        #expect(duration >= 0.9 && duration <= 1)
        #expect(duration >= (end - from) / animation.frameRate * 1.6)
    }

    @Test(arguments: compositions)
    func eachCompositionWindsUpForAtLeastAQuarterSecond(_ composition: Composition) throws {
        let (animation, from, windup, _) = try Self.markers(composition.name)
        #expect(LibraryRailMotion.playbackDuration(from: from, to: windup, frameRate: animation.frameRate) >= 0.25)
    }

    @Test(arguments: compositions)
    func eachCompositionStartsOnHoverStart(_ composition: Composition) throws {
        let (animation, from, _, end) = try Self.markers(composition.name)
        #expect(LibraryRailMotion.playbackFrame(from: from, to: end, frameRate: animation.frameRate, elapsed: 0) == from)
        #expect(LibraryRailMotion.playbackFrame(from: from, to: end, frameRate: animation.frameRate, elapsed: -1) == from)
    }

    @Test(arguments: compositions)
    func eachCompositionIsHalfwayThroughItsFramesHalfwayThroughItsTime(_ composition: Composition) throws {
        let (animation, from, _, end) = try Self.markers(composition.name)
        let duration = LibraryRailMotion.playbackDuration(from: from, to: end, frameRate: animation.frameRate)
        #expect(Self.near(LibraryRailMotion.playbackFrame(from: from, to: end, frameRate: animation.frameRate, elapsed: duration / 2), (from + end) / 2))
    }

    @Test(arguments: compositions)
    func eachCompositionParksOnSelectionEnd(_ composition: Composition) throws {
        let (animation, from, _, end) = try Self.markers(composition.name)
        let duration = LibraryRailMotion.playbackDuration(from: from, to: end, frameRate: animation.frameRate)
        #expect(LibraryRailMotion.playbackFrame(from: from, to: end, frameRate: animation.frameRate, elapsed: duration + 1) == end)
    }

    @Test func playbackRunsAtThirtySixCompositionFramesASecond() {
        #expect(Self.near(LibraryRailMotion.playbackFrame(from: 1, to: 35, frameRate: 60, elapsed: 0.375), 14.5))
    }

    @Test func fadesTakeAThirdOfASecondInAQuarterOutAndPagesFadeInOverThreeTenths() {
        #expect(LibraryRailMotion.arrival == 0.34)
        #expect(LibraryRailMotion.departure == 0.26)
        #expect(LibraryRailMotion.pageFade == 0.3)
    }

    @Test func lightingUpUsesTheArrivalTimeAndDimmingTheDepartureTime() {
        #expect(LibraryRailMotion.fadeDuration(rising: true) == LibraryRailMotion.arrival)
        #expect(LibraryRailMotion.fadeDuration(rising: false) == LibraryRailMotion.departure)
    }

    @Test(arguments: [(0.0, 0.0), (1, 1), (-0.5, 0), (1.5, 1)])
    func theCurveIsPinnedAtBothEnds(_ progress: Double, _ value: Double) {
        #expect(LibraryRailMotion.eased(progress) == value)
    }

    @Test(arguments: 1...100)
    func theCurveNeverReverses(_ step: Int) {
        #expect(LibraryRailMotion.eased(Double(step) / 100) >= LibraryRailMotion.eased(Double(step - 1) / 100))
    }

    @Test func theCurveAnswersQuicklyAndDeceleratesIntoPlace() {
        #expect(LibraryRailMotion.eased(0.5) > 0.6 && LibraryRailMotion.eased(0.5) < 0.9)
    }

    @Test func coreAnimationFadesFollowTheSameCurveAsTheDrawnInk() {
        #expect(Self.controlPoints(LibraryRailMotion.timing) == [0.25, 0.46, 0.45, 0.94])
    }

    @Test func aNewFadeRestsOnItsValue() {
        let fade = LibraryRailMotion.Fade(0)
        #expect(fade.value(at: 0) == 0 && fade.isSettled(at: 0))
    }

    @Test func lightingUpStartsWhereTheTileIsAndEasesTowardFull() {
        var fade = LibraryRailMotion.Fade(0)
        fade.retarget(1, at: 10, animated: true)
        let half = 10 + LibraryRailMotion.arrival / 2
        #expect(fade.value(at: 10) == 0)
        #expect(!fade.isSettled(at: half))
        #expect(fade.value(at: half) > 0.5 && fade.value(at: half) < 1)
    }

    @Test func lightingUpSettlesExactlyOnFullAtTheArrivalTime() {
        var fade = LibraryRailMotion.Fade(0)
        fade.retarget(1, at: 10, animated: true)
        let arrived = 10 + LibraryRailMotion.arrival + 1e-9
        #expect(fade.value(at: arrived) == 1 && fade.isSettled(at: arrived))
    }

    @Test func aQuickClickAwayTurnsTheFadeAroundWithoutAJump() {
        var fade = LibraryRailMotion.Fade(0)
        fade.retarget(1, at: 10, animated: true)
        let turn = 10 + LibraryRailMotion.arrival / 3, reached = fade.value(at: turn)
        fade.retarget(0, at: turn, animated: true)
        #expect(Self.near(fade.value(at: turn), reached))
        #expect(fade.value(at: turn + 0.01) < reached)
    }

    @Test func askingForTheSameTargetAgainDoesNotRestartTheFade() {
        var fade = LibraryRailMotion.Fade(0)
        fade.retarget(1, at: 10, animated: true)
        let turn = 10 + LibraryRailMotion.arrival / 3
        fade.retarget(0, at: turn, animated: true)
        fade.retarget(0, at: turn + 0.1, animated: true)
        let departed = turn + LibraryRailMotion.departure + 1e-9
        #expect(fade.isSettled(at: departed) && fade.value(at: departed) == 0)
    }

    @Test func settlingARunningFadeJumpsItToItsTarget() {
        var fade = LibraryRailMotion.Fade(0)
        fade.retarget(1, at: 20, animated: true)
        fade.retarget(1, at: 20.05, animated: false)
        #expect(fade.isSettled(at: 20.05) && fade.value(at: 20.05) == 1)
    }

    @Test func withoutAWindowAChangeAppliesAtOnce() {
        var fade = LibraryRailMotion.Fade(1)
        fade.retarget(0, at: 21, animated: false)
        #expect(fade.isSettled(at: 21) && fade.value(at: 21) == 0)
    }

    @Test func theFillFadesFromWhatIsOnScreenToWhateverTheTileNowWants() {
        let fill = LibraryRailMotion.fade("backgroundColor", from: CGColor(gray: 0, alpha: 0), duration: LibraryRailMotion.arrival)
        #expect(fill.keyPath == "backgroundColor" && fill.fromValue != nil && fill.toValue == nil)
        #expect(fill.duration == LibraryRailMotion.arrival)
        #expect(Self.controlPoints(fill.timingFunction) == [0.25, 0.46, 0.45, 0.94])
    }

    @Test func aNewPageFadesUpFromClearToItsOwnOpacity() {
        let page = LibraryRailMotion.fade("opacity", from: 0, to: Float(1), duration: LibraryRailMotion.pageFade)
        #expect(page.keyPath == "opacity" && (page.fromValue as? Int) == 0 && (page.toValue as? Float) == 1 && page.duration == 0.3)
    }

    private static var spring: CASpringAnimation { LibraryRailMotion.pressSpring("bounds", from: NSValue(rect: .zero),
                                                              to: NSValue(rect: NSRect(x: 2, y: 2, width: 4, height: 4))) }

    @Test func thePressSpringHasTheRailsResponseAndDamping() {
        let spring = Self.spring
        let ratio = spring.damping / (2 * (spring.stiffness * spring.mass).squareRoot())
        let response = 2 * Double.pi / (spring.stiffness / spring.mass).squareRoot()
        #expect(Self.near(response, LibraryRailMotion.pressResponse, 1e-6))
        #expect(Self.near(ratio, LibraryRailMotion.pressDamping, 1e-6))
    }

    @Test func thePressSinksInSoftlyAndSettlesWithNoVisibleOvershoot() {
        let spring = Self.spring
        let ratio = spring.damping / (2 * (spring.stiffness * spring.mass).squareRoot())
        let overshoot = exp(-Double.pi * ratio / (1 - ratio * ratio).squareRoot())
        #expect(LibraryRailMotion.pressResponse >= 0.25 && overshoot < 0.01)
        #expect(spring.duration == spring.settlingDuration && spring.duration > 0.3 && spring.duration < 1)
    }
}
