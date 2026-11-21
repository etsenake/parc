import Foundation
import Testing
@testable import ParcCore

struct SplitDropIntentTests {
    typealias Zone = SplitDropIntent.Zone
    typealias Place = SplitDropIntent.Place
    static let leftEdge = Zone(target: .insert(0), orientation: .horizontal)
    static let leftCentre = Zone(target: .replace(0), orientation: .horizontal)
    static let between = Zone(target: .insert(1), orientation: .horizontal)
    static let rightCentre = Zone(target: .replace(1), orientation: .horizontal)
    static let rightEdge = Zone(target: .insert(2), orientation: .horizontal)
    static let seat = Zone(target: .stack(1, after: true), orientation: .horizontal)

    static func place(x: Double, y: Double) -> Place {
        if x >= 700 && x < 710 { return .preview }
        let pane = x < 700 ? 0.0 : 710.0
        let local = x - pane
        if local < 80 { return .pane(pane == 0 ? leftEdge : between) }
        if local > 620 { return .pane(pane == 0 ? between : rightEdge) }
        if pane > 0 && y > 650 { return .pane(seat) }
        return .pane(pane == 0 ? leftCentre : rightCentre)
    }

    struct Pointer {
        var intent = SplitDropIntent()
        var time: TimeInterval = 10
        var x: Double
        var y: Double
        var steps: [(time: TimeInterval, place: Place, step: SplitDropIntent.Step)] = []
        init(x: Double, y: Double, intent: SplitDropIntent = SplitDropIntent()) { self.x = x; self.y = y; self.intent = intent }

        mutating func sample(_ given: Place? = nil) {
            let place = given ?? SplitDropIntentTests.place(x: x, y: y)
            steps.append((time, place, intent.move(to: place, x: x, y: y, at: time)))
        }
        mutating func glide(toX targetX: Double, y targetY: Double, speed: Double, every interval: TimeInterval = 0.008) {
            let distance = hypot(targetX - x, targetY - y)
            let count = max(1, Int((distance / speed / interval).rounded(.up)))
            let startX = x, startY = y
            for index in 1...count {
                let progress = Double(index) / Double(count)
                time += distance / speed / Double(count)
                x = startX + (targetX - startX) * progress; y = startY + (targetY - startY) * progress
                sample()
            }
        }
        mutating func rest(for duration: TimeInterval, every interval: TimeInterval = 0.008) {
            let end = time + duration
            while time + interval <= end + 1e-9 { time += interval; sample() }
        }
        var shown: Zone? { intent.shown }
        var appearances: [Zone] { steps.compactMap { $0.step.appeared ? $0.step.shown : nil } }
    }

    @Test static func fastTraversalOpensNothing() {
        var pointer = Pointer(x: 0, y: 300)
        pointer.sample()
        pointer.glide(toX: 1100, y: 690, speed: 1500)
        #expect(pointer.steps.allSatisfy { !$0.step.changed } && pointer.shown == nil,
               "a fast sweep from the sidebar over the left edge, a centre, the boundary and a gap opens nothing")
        var wide = Pointer(x: 90, y: 300)
        wide.sample()
        wide.glide(toX: 610, y: 300, speed: 600)
        #expect(wide.time - 10 > 0.12 * 5 && wide.shown == nil && wide.steps.allSatisfy { !$0.step.changed },
               "crossing a wide pane centre at a brisk 600 points a second takes far longer than the dwell and still opens nothing")
        var single = Pointer(x: 0, y: 300)
        single.sample(.pane(leftEdge))
        for _ in 0..<60 {
            single.time += 0.008; single.x += 12
            single.sample(.pane(single.x < 480 ? leftEdge : single.x < 720 ? leftCentre : rightEdge))
        }
        #expect(single.shown == nil && single.appearances.isEmpty,
               "sweeping across a single page's wide side band at 1500 points a second opens nothing")
    }

    @Test static func slowdownOpensAtOnce() {
        var pointer = Pointer(x: 900, y: 300)
        pointer.sample()
        pointer.glide(toX: 1000, y: 660, speed: 1500)
        let entry = pointer.steps.first { $0.place == .pane(seat) }?.time ?? .infinity
        #expect(pointer.shown == nil && entry <= pointer.time, "arriving fast leaves the seat closed")
        pointer.glide(toX: 1010, y: 670, speed: 100)
        let opened = pointer.steps.first { $0.step.appeared }
        #expect(opened?.step.shown == seat, "slowing below the settle speed opens the seat")
        #expect((opened?.time ?? .infinity) - entry < 0.12, "the slowdown opens it before the dwell would")
        var aimed = Pointer(x: 300, y: 300)
        aimed.sample()
        aimed.glide(toX: 640, y: 300, speed: 120)
        #expect(aimed.appearances.first == leftCentre, "already moving slowly, the centre ring appears once its speed is known")
        let band = aimed.steps.firstIndex { $0.place == .pane(between) }
        #expect(band.map { aimed.steps[$0].step.appeared && aimed.steps[$0].step.shown == between } == true,
               "easing slowly from the centre into the boundary band opens it on its first sample there")
    }

    @Test static func dwellOpens() {
        var pointer = Pointer(x: 300, y: 300)
        pointer.sample()
        pointer.glide(toX: 400, y: 300, speed: 350)
        let entry = 10.0
        #expect(pointer.steps.filter { $0.time - entry < 0.12 }.allSatisfy { $0.step.shown == nil },
               "350 points a second is above the settle speed, so the ring waits out the dwell")
        let opened = pointer.steps.first { $0.step.appeared }
        #expect(opened?.step.shown == leftCentre, "lingering at a moderate speed opens the zone after the dwell")
        #expect((opened?.time ?? 0) - entry >= 0.12 && (opened?.time ?? .infinity) - entry < 0.12 + 0.009,
               "the dwell opens it within one sample of 120 ms")
    }

    @Test static func stoppingOpensAtTheDeadline() {
        var pointer = Pointer(x: 900, y: 300)
        pointer.sample()
        pointer.glide(toX: 1000, y: 680, speed: 1500)
        #expect(pointer.shown == nil && pointer.intent.isPending, "the seat is pending while the pointer is still moving fast")
        let deadline = pointer.intent.deadline
        #expect(deadline == pointer.time + 0.05, "a pointer that stops is judged settled one window after its last movement")
        pointer.time = deadline ?? pointer.time
        pointer.sample()
        #expect(pointer.shown == seat && pointer.steps.last?.step.appeared == true, "the timer's sample at the deadline opens the seat")
        #expect(pointer.intent.deadline == nil, "nothing pending leaves no deadline")
    }

    @Test static func openToOpenTransition() {
        var pointer = Pointer(x: 640, y: 300)
        pointer.sample()
        pointer.rest(for: 0.06)
        #expect(pointer.shown == between, "resting in the boundary band opens the column between")
        let before = pointer.steps.count
        pointer.glide(toX: 1000, y: 680, speed: 1500)
        let travel = pointer.steps[before...]
        #expect(travel.allSatisfy { !$0.step.changed && $0.step.shown == between },
               "crossing the gap and the right centre keeps the open column, with no collapse")
        pointer.rest(for: 0.06)
        let changes = pointer.steps[before...].filter { $0.step.changed }
        #expect(changes.count == 1 && changes.first?.step.shown == seat,
               "the seat replaces the column in one step, straight from one preview to the next")
    }

    @Test static func earlyReleaseDropsUnderThePointer() {
        var pointer = Pointer(x: 640, y: 300)
        pointer.sample()
        pointer.rest(for: 0.06)
        pointer.glide(toX: 1000, y: 680, speed: 1500)
        #expect(pointer.shown == between && pointer.intent.isPending, "the seat has not appeared yet")
        #expect(pointer.intent.dropZone(at: place(x: pointer.x, y: pointer.y)) == seat,
               "an early release drops into the seat under the pointer, not the column still showing")
        #expect(pointer.intent.dropZone(at: .preview) == between,
               "a release inside the open preview or a gap drops into the preview that shows")
        #expect(pointer.intent.dropZone(at: .pane(nil)) == nil, "a release over a spot offering nothing drops nowhere")
        var fresh = Pointer(x: 0, y: 300)
        fresh.sample()
        fresh.glide(toX: 50, y: 300, speed: 1500)
        #expect(fresh.shown == nil && fresh.intent.dropZone(at: place(x: fresh.x, y: fresh.y)) == leftEdge,
               "with nothing open yet, a fast drop still lands at the edge under the pointer")
    }

    @Test static func hapticsOnlyOnAppearance() {
        var pointer = Pointer(x: 0, y: 300)
        pointer.sample()
        pointer.glide(toX: 1000, y: 680, speed: 1500)
        #expect(pointer.appearances.isEmpty, "crossing zones never asks for a haptic")
        pointer.glide(toX: 1005, y: 685, speed: 80)
        #expect(pointer.appearances == [seat], "the seat appearing asks for one haptic")
        pointer.sample(.preview); pointer.time += 0.2; pointer.sample(.preview)
        pointer.glide(toX: 1006, y: 686, speed: 50)
        #expect(pointer.appearances == [seat], "holding inside the open seat asks for nothing more")
        let left = pointer.intent.leave()
        #expect(left.changed && !left.appeared, "leaving clears without a haptic")
        pointer.time += 0.1
        pointer.x = 300; pointer.y = 300
        pointer.sample()
        pointer.rest(for: 0.06)
        #expect(pointer.appearances == [seat, leftCentre], "coming back and settling on a centre asks for one more")
    }

    @Test static func leavingAndEscapeClearImmediately() {
        var pointer = Pointer(x: 640, y: 300)
        pointer.sample()
        pointer.rest(for: 0.06)
        pointer.glide(toX: 1000, y: 680, speed: 1500)
        #expect(pointer.shown == between && pointer.intent.isPending, "a column shows while the seat is pending")
        let left = pointer.intent.leave()
        #expect(left == SplitDropIntent.Step(shown: nil, changed: true) && pointer.shown == nil && !pointer.intent.isPending
               && pointer.intent.deadline == nil, "leaving the split clears the preview at once and forgets the pending seat")
        #expect(pointer.intent.leave() == SplitDropIntent.Step(shown: nil, changed: false), "leaving again changes nothing")
        var returning = Pointer(x: 10, y: 300)
        returning.sample()
        returning.rest(for: 0.06)
        #expect(returning.shown == leftEdge, "resting on the left edge opens it")
        #expect(returning.intent.leave().changed, "the drag leaves the split")
        returning.time += 2; returning.x = 0; returning.y = 305
        returning.sample()
        returning.glide(toX: 400, y: 305, speed: 1500)
        #expect(returning.shown == nil && returning.appearances == [leftEdge],
               "sweeping back in fast right beside where it left opens nothing, since leaving forgets the old samples")
        var rewound = Pointer(x: 300, y: 300)
        rewound.sample()
        rewound.glide(toX: 330, y: 300, speed: 350)
        rewound.time -= 5
        rewound.glide(toX: 400, y: 300, speed: 350)
        #expect(rewound.shown == leftCentre, "a clock that runs backwards still lets the dwell open the zone")
        var escaped = Pointer(x: 640, y: 300)
        escaped.sample()
        escaped.rest(for: 0.06)
        escaped.intent.reset()
        #expect(escaped.shown == nil && !escaped.intent.isPending && escaped.intent.deadline == nil,
               "Escape or the drag's end resets everything at once")
        escaped.time += 0.008
        escaped.sample()
        #expect(escaped.shown == nil && escaped.intent.deadline == escaped.time + 0.05,
               "after a reset the pointer's speed is measured afresh before anything opens")
    }

    @Test static func gapsAndEmptySpotsKeepTheOpenPreview() {
        var pointer = Pointer(x: 640, y: 300)
        pointer.sample()
        pointer.rest(for: 0.06)
        pointer.glide(toX: 750, y: 300, speed: 1500)
        #expect(pointer.shown == between && pointer.intent.isPending == false, "the pane beyond the gap offers the same column")
        pointer.sample(.pane(rightCentre))
        #expect(pointer.intent.isPending, "the right centre is pending")
        pointer.x = 705; pointer.time += 0.008
        pointer.sample()
        #expect(pointer.steps.last?.place == .preview && pointer.shown == between && !pointer.intent.isPending
               && pointer.intent.deadline == nil, "a gap keeps the open column and cancels anything pending")
        pointer.rest(for: 0.3)
        #expect(pointer.shown == between && pointer.steps.suffix(30).allSatisfy { !$0.step.changed },
               "even resting in a gap keeps the column")
        for _ in 0..<4 { pointer.x += 20; pointer.time += 0.008; pointer.sample(.pane(nil)) }
        #expect(pointer.shown == between && pointer.intent.isPending, "a spot offering nothing waits like any other zone")
        pointer.time += 0.05; pointer.sample(.pane(nil))
        #expect(pointer.shown == nil && pointer.steps.last?.step.changed == true && pointer.steps.last?.step.appeared == false,
               "settling on a spot offering nothing closes the column without a haptic")
    }

    @Test static func immediateIntentOpensOnEntry() {
        var pointer = Pointer(x: 0, y: 300, intent: SplitDropIntent(dwell: 0))
        pointer.sample()
        #expect(pointer.shown == leftEdge && pointer.steps.last?.step.appeared == true,
               "a zero dwell opens every zone on entry, as before hover intent")
        pointer.glide(toX: 300, y: 300, speed: 3000)
        #expect(pointer.shown == leftCentre, "and follows the pointer however fast it moves")
    }
}
