import Foundation
import Testing
@testable import ParcCore

struct EaselControlMotionTests {
    private static func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-9 }

    @Test func controlsRestAtFullSize() {
        #expect(EaselControlMotion.scale(hovered: false, pressed: false) == 1)
    }

    @Test func hoveredControlsGrow() {
        #expect(EaselControlMotion.scale(hovered: true, pressed: false) == EaselControlMotion.hoverScale)
    }

    @Test(arguments: [true, false])
    func pressedControlsShrinkWhetherHoveredOrNot(hovered: Bool) {
        #expect(EaselControlMotion.scale(hovered: hovered, pressed: true) == EaselControlMotion.pressedScale)
    }

    @Test func cardsUseTheirOwnHoverAndPressScales() {
        #expect(EaselControlMotion.scale(hovered: true, pressed: false, hover: 1.03, press: 0.98) == 1.03)
        #expect(EaselControlMotion.scale(hovered: false, pressed: true, hover: 1.03, press: 0.98) == 0.98)
    }

    @Test func restingControlsCastNoShadow() {
        #expect(EaselControlMotion.shadowOpacity(hovered: false, pressed: false, dark: false) == 0)
    }

    @Test func hoveredControlsCastTheShadowForTheirAppearance() {
        #expect(EaselControlMotion.shadowOpacity(hovered: true, pressed: false, dark: false) == EaselControlMotion.hoverShadowOpacity)
        #expect(EaselControlMotion.shadowOpacity(hovered: true, pressed: false, dark: true) == EaselControlMotion.darkHoverShadowOpacity)
    }

    @Test func pressedControlsSitFlat() {
        #expect(EaselControlMotion.shadowOpacity(hovered: true, pressed: true, dark: false) == 0)
    }

    @Test(arguments: [("04:59", "04:58", EaselDigitRoll.Direction.down), ("04:59", "05:59", .up), ("05:00", "05:00", .up)])
    func digitsRollTheWayTheCountMoves(from: String, to: String, direction: EaselDigitRoll.Direction) {
        #expect(EaselDigitRoll.direction(from: from, to: to) == direction)
    }

    @Test(arguments: [("04:59", "04:58", [4]), ("05:00", "04:59", [1, 3, 4]), ("05:00", "05:00", [])])
    func onlyChangedDigitsRoll(from: String, to: String, columns: [Int]) {
        #expect(EaselDigitRoll.changedColumns(from: from, to: to) == columns)
    }

    @Test func aNewLeadingDigitRollsUpFromNothing() throws {
        let columns = EaselDigitRoll.columns(from: "9:59", to: "10:00")
        try #require(columns.count == 5)
        #expect(columns[0].old == nil && columns[0].new == "1")
        #expect(columns[0].direction == .up)
    }

    @Test func aDroppedDigitRollsDownAndLeaves() throws {
        let leaving = EaselDigitRoll.columns(from: "10:00", to: "9:59")
        try #require(!leaving.isEmpty)
        #expect(leaving[0].old == "1" && leaving[0].new == nil)
        #expect(leaving[0].direction == .down)
    }

    @Test(arguments: [(EaselDigitRoll.Direction.up, true, 1.0), (.up, false, -1), (.down, true, -1), (.down, false, 1)])
    func digitsEnterAndExitOnTheSideTheyRollFrom(direction: EaselDigitRoll.Direction, entering: Bool, sign: Double) {
        let travel = 20 * EaselDigitRoll.rollDistance
        #expect(Self.near(EaselDigitRoll.offsetBelowIsPositive(of: direction, height: 20, entering: entering), sign * travel))
    }

    @Test func thePulseTrainHasOneValuePerKeyTimeForThreePulses() {
        #expect(EaselPulseTrain.keyTimes.count == EaselPulseTrain.values.count)
        #expect(EaselPulseTrain.keyTimes.count == 1 + 2 * EaselPulseTrain.count)
    }

    @Test func pulseKeyTimesSpanTheAnimationInIncreasingOrder() {
        let times = EaselPulseTrain.keyTimes
        #expect(times.first == 0 && Self.near(times.last ?? 0, 1))
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func theGlowStartsAndEndsDark() {
        #expect(EaselPulseTrain.values.first == 0 && EaselPulseTrain.values.last == 0)
    }

    @Test func eachPulseIsSofterThanTheLastButStillVisible() {
        let values = EaselPulseTrain.values
        let peaks = stride(from: 1, to: values.count, by: 2).map { values[$0] }
        #expect(zip(peaks, peaks.dropFirst()).allSatisfy { $0 > $1 })
        #expect(peaks.allSatisfy { $0 > 0 && $0 <= 1 })
    }
}
