import Foundation

@main
struct EaselControlMotionTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }

    static func main() {
        scales()
        shadows()
        rolls()
        pulses()
        print("EaselControlMotionTests passed")
    }

    static func scales() {
        expect(EaselControlMotion.scale(hovered: false, pressed: false) == 1, "rest scale")
        expect(EaselControlMotion.scale(hovered: true, pressed: false) == EaselControlMotion.hoverScale, "hover scale")
        expect(EaselControlMotion.scale(hovered: true, pressed: true) == EaselControlMotion.pressedScale, "press beats hover")
        expect(EaselControlMotion.scale(hovered: false, pressed: true) == EaselControlMotion.pressedScale, "press without hover")
        expect(EaselControlMotion.scale(hovered: true, pressed: false, hover: 1.03, press: 0.98) == 1.03, "card hover scale")
        expect(EaselControlMotion.scale(hovered: false, pressed: true, hover: 1.03, press: 0.98) == 0.98, "card press scale")
    }

    static func shadows() {
        expect(EaselControlMotion.shadowOpacity(hovered: false, pressed: false, dark: false) == 0, "no shadow at rest")
        expect(EaselControlMotion.shadowOpacity(hovered: true, pressed: false, dark: false) == EaselControlMotion.hoverShadowOpacity,
               "light hover shadow")
        expect(EaselControlMotion.shadowOpacity(hovered: true, pressed: false, dark: true) == EaselControlMotion.darkHoverShadowOpacity,
               "dark hover shadow")
        expect(EaselControlMotion.shadowOpacity(hovered: true, pressed: true, dark: false) == 0, "pressed controls sit flat")
    }

    static func rolls() {
        expect(EaselDigitRoll.direction(from: "04:59", to: "04:58") == .down, "counting down rolls down")
        expect(EaselDigitRoll.direction(from: "04:59", to: "05:59") == .up, "adding a minute rolls up")
        expect(EaselDigitRoll.direction(from: "05:00", to: "05:00") == .up, "unchanged defaults up")
        expect(EaselDigitRoll.changedColumns(from: "04:59", to: "04:58") == [4], "one digit changes")
        expect(EaselDigitRoll.changedColumns(from: "05:00", to: "04:59") == [1, 3, 4], "borrow changes three digits")
        expect(EaselDigitRoll.changedColumns(from: "05:00", to: "05:00").isEmpty, "same text changes nothing")
        let columns = EaselDigitRoll.columns(from: "9:59", to: "10:00")
        expect(columns.count == 5, "columns align to the right")
        expect(columns[0].old == nil && columns[0].new == "1", "new leading digit enters from nothing")
        expect(columns[0].direction == .up, "growing text rolls up")
        let leaving = EaselDigitRoll.columns(from: "10:00", to: "9:59")
        expect(leaving[0].old == "1" && leaving[0].new == nil, "dropped digit leaves")
        expect(leaving[0].direction == .down, "shrinking text rolls down")
        let travel = 20 * EaselDigitRoll.rollDistance
        expect(near(EaselDigitRoll.offsetBelowIsPositive(of: .up, height: 20, entering: true), travel), "rolling up enters from below")
        expect(near(EaselDigitRoll.offsetBelowIsPositive(of: .up, height: 20, entering: false), -travel), "rolling up exits above")
        expect(near(EaselDigitRoll.offsetBelowIsPositive(of: .down, height: 20, entering: true), -travel), "rolling down enters from above")
        expect(near(EaselDigitRoll.offsetBelowIsPositive(of: .down, height: 20, entering: false), travel), "rolling down exits below")
    }

    static func pulses() {
        let times = EaselPulseTrain.keyTimes, values = EaselPulseTrain.values
        expect(times.count == values.count, "one value per key time")
        expect(times.count == 1 + 2 * EaselPulseTrain.count, "three pulses")
        expect(times.first == 0 && near(times.last ?? 0, 1), "keyframes span the whole animation")
        expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 }, "key times increase")
        expect(values.first == 0 && values.last == 0, "glow starts and ends dark")
        let peaks = stride(from: 1, to: values.count, by: 2).map { values[$0] }
        expect(zip(peaks, peaks.dropFirst()).allSatisfy { $0 > $1 }, "each pulse is softer than the last")
        expect(peaks.allSatisfy { $0 > 0 && $0 <= 1 }, "peaks stay visible but gentle")
    }
}
