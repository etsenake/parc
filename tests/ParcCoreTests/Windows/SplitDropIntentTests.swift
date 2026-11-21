import Foundation
import Testing
@testable import ParcCore

struct SplitDropIntentTests {
    typealias Zone = SplitDropIntent.Zone
    typealias Place = SplitDropIntent.Place
    private static let leftEdge = Zone(target: .insert(0), orientation: .horizontal)
    private static let leftCentre = Zone(target: .replace(0), orientation: .horizontal)
    private static let between = Zone(target: .insert(1), orientation: .horizontal)
    private static let rightCentre = Zone(target: .replace(1), orientation: .horizontal)
    private static let rightEdge = Zone(target: .insert(2), orientation: .horizontal)
    private static let seat = Zone(target: .stack(1, after: true), orientation: .horizontal)

    private static func place(x: Double, y: Double) -> Place {
        if x >= 700 && x < 710 { return .preview }
        let pane = x < 700 ? 0.0 : 710.0
        let local = x - pane
        if local < 80 { return .pane(pane == 0 ? leftEdge : between) }
        if local > 620 { return .pane(pane == 0 ? between : rightEdge) }
        if pane > 0 && y > 650 { return .pane(seat) }
        return .pane(pane == 0 ? leftCentre : rightCentre)
    }

    private struct Pointer {
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

    @Test func aFastSweepFromTheSidebarOverEdgeCentreBoundaryAndGapOpensNothing() {
        var pointer = Pointer(x: 0, y: 300)
        pointer.sample()
        pointer.glide(toX: 1100, y: 690, speed: 1500)
        #expect(pointer.steps.allSatisfy { !$0.step.changed })
        #expect(pointer.shown == nil)
    }

    @Test func crossingAWidePaneCentreAtABriskSpeedTakesFarLongerThanTheDwellAndOpensNothing() {
        var wide = Pointer(x: 90, y: 300)
        wide.sample()
        wide.glide(toX: 610, y: 300, speed: 600)
        #expect(wide.time - 10 > 0.12 * 5)
        #expect(wide.shown == nil)
        #expect(wide.steps.allSatisfy { !$0.step.changed })
    }

    @Test func sweepingAcrossASinglePagesWideSideBandOpensNothing() {
        var single = Pointer(x: 0, y: 300)
        single.sample(.pane(Self.leftEdge))
        for _ in 0..<60 {
            single.time += 0.008
            single.x += 12
            single.sample(.pane(single.x < 480 ? Self.leftEdge : single.x < 720 ? Self.leftCentre : Self.rightEdge))
        }
        #expect(single.shown == nil)
        #expect(single.appearances.isEmpty)
    }

    private static func arrivedAtTheSeat() -> (pointer: Pointer, entry: TimeInterval) {
        var pointer = Pointer(x: 900, y: 300)
        pointer.sample()
        pointer.glide(toX: 1000, y: 660, speed: 1500)
        return (pointer, pointer.steps.first { $0.place == .pane(seat) }?.time ?? .infinity)
    }

    @Test func arrivingFastLeavesTheSeatClosed() {
        let a = Self.arrivedAtTheSeat()
        #expect(a.pointer.shown == nil)
        #expect(a.entry <= a.pointer.time)
    }

    @Test func slowingBelowTheSettleSpeedOpensTheSeat() {
        var a = Self.arrivedAtTheSeat()
        a.pointer.glide(toX: 1010, y: 670, speed: 100)
        #expect(a.pointer.steps.first { $0.step.appeared }?.step.shown == Self.seat)
    }

    @Test func theSlowdownOpensTheSeatBeforeTheDwellWould() {
        var a = Self.arrivedAtTheSeat()
        a.pointer.glide(toX: 1010, y: 670, speed: 100)
        let opened = a.pointer.steps.first { $0.step.appeared }
        #expect((opened?.time ?? .infinity) - a.entry < 0.12)
    }

    @Test func alreadyMovingSlowlyTheCentreRingAppearsOnceItsSpeedIsKnown() {
        var aimed = Pointer(x: 300, y: 300)
        aimed.sample()
        aimed.glide(toX: 640, y: 300, speed: 120)
        #expect(aimed.appearances.first == Self.leftCentre)
    }

    @Test func easingSlowlyFromTheCentreIntoTheBoundaryOpensItOnItsFirstSampleThere() {
        var aimed = Pointer(x: 300, y: 300)
        aimed.sample()
        aimed.glide(toX: 640, y: 300, speed: 120)
        let band = aimed.steps.firstIndex { $0.place == .pane(Self.between) }
        #expect(band.map { aimed.steps[$0].step.appeared && aimed.steps[$0].step.shown == Self.between } == true)
    }

    private static func lingering() -> Pointer {
        var pointer = Pointer(x: 300, y: 300)
        pointer.sample()
        pointer.glide(toX: 400, y: 300, speed: 350)
        return pointer
    }

    @Test func aSpeedAboveTheSettleSpeedMakesTheRingWaitOutTheDwell() {
        let pointer = Self.lingering()
        #expect(pointer.steps.filter { $0.time - 10 < 0.12 }.allSatisfy { $0.step.shown == nil })
    }

    @Test func lingeringAtAModerateSpeedOpensTheZoneAfterTheDwell() {
        #expect(Self.lingering().steps.first { $0.step.appeared }?.step.shown == Self.leftCentre)
    }

    @Test func theDwellOpensItWithinOneSampleOfOneTwentyMilliseconds() {
        let opened = Self.lingering().steps.first { $0.step.appeared }
        #expect((opened?.time ?? 0) - 10 >= 0.12)
        #expect((opened?.time ?? .infinity) - 10 < 0.12 + 0.009)
    }

    private static func pendingAtTheSeat() -> Pointer {
        var pointer = Pointer(x: 900, y: 300)
        pointer.sample()
        pointer.glide(toX: 1000, y: 680, speed: 1500)
        return pointer
    }

    @Test func theSeatIsPendingWhileThePointerStillMovesFast() {
        let pointer = Self.pendingAtTheSeat()
        #expect(pointer.shown == nil)
        #expect(pointer.intent.isPending)
    }

    @Test func aPointerThatStopsIsJudgedSettledOneWindowAfterItsLastMovement() {
        let pointer = Self.pendingAtTheSeat()
        #expect(pointer.intent.deadline == pointer.time + 0.05)
    }

    @Test func theTimersSampleAtTheDeadlineOpensTheSeat() {
        var pointer = Self.pendingAtTheSeat()
        pointer.time = pointer.intent.deadline ?? pointer.time
        pointer.sample()
        #expect(pointer.shown == Self.seat)
        #expect(pointer.steps.last?.step.appeared == true)
    }

    @Test func nothingPendingLeavesNoDeadline() {
        var pointer = Self.pendingAtTheSeat()
        pointer.time = pointer.intent.deadline ?? pointer.time
        pointer.sample()
        #expect(pointer.intent.deadline == nil)
    }

    private static func columnOpen() -> Pointer {
        var pointer = Pointer(x: 640, y: 300)
        pointer.sample()
        pointer.rest(for: 0.06)
        return pointer
    }

    @Test func restingInTheBoundaryBandOpensTheColumnBetween() {
        #expect(Self.columnOpen().shown == Self.between)
    }

    @Test func crossingTheGapAndTheRightCentreKeepsTheOpenColumnWithNoCollapse() {
        var pointer = Self.columnOpen()
        let before = pointer.steps.count
        pointer.glide(toX: 1000, y: 680, speed: 1500)
        #expect(pointer.steps[before...].allSatisfy { !$0.step.changed && $0.step.shown == Self.between })
    }

    @Test func theSeatReplacesTheColumnInOneStep() {
        var pointer = Self.columnOpen()
        pointer.glide(toX: 1000, y: 680, speed: 1500)
        let before = pointer.steps.count
        pointer.rest(for: 0.06)
        let changes = pointer.steps[before...].filter { $0.step.changed }
        #expect(changes.count == 1)
        #expect(changes.first?.step.shown == Self.seat)
    }

    private static func earlyRelease() -> Pointer {
        var pointer = columnOpen()
        pointer.glide(toX: 1000, y: 680, speed: 1500)
        return pointer
    }

    @Test func theSeatHasNotAppearedYetOnAnEarlyRelease() {
        let pointer = Self.earlyRelease()
        #expect(pointer.shown == Self.between)
        #expect(pointer.intent.isPending)
    }

    @Test func anEarlyReleaseDropsIntoTheSeatUnderThePointer() {
        let pointer = Self.earlyRelease()
        #expect(pointer.intent.dropZone(at: Self.place(x: pointer.x, y: pointer.y)) == Self.seat)
    }

    @Test func aReleaseInsideTheOpenPreviewOrAGapDropsIntoTheShownPreview() {
        #expect(Self.earlyRelease().intent.dropZone(at: .preview) == Self.between)
    }

    @Test func aReleaseOverASpotOfferingNothingDropsNowhere() {
        #expect(Self.earlyRelease().intent.dropZone(at: .pane(nil)) == nil)
    }

    @Test func withNothingOpenAFastDropStillLandsAtTheEdgeUnderThePointer() {
        var fresh = Pointer(x: 0, y: 300)
        fresh.sample()
        fresh.glide(toX: 50, y: 300, speed: 1500)
        #expect(fresh.shown == nil)
        #expect(fresh.intent.dropZone(at: Self.place(x: fresh.x, y: fresh.y)) == Self.leftEdge)
    }

    private static func seatShown() -> Pointer {
        var pointer = Pointer(x: 0, y: 300)
        pointer.sample()
        pointer.glide(toX: 1000, y: 680, speed: 1500)
        return pointer
    }

    @Test func crossingZonesNeverAsksForAHaptic() {
        #expect(Self.seatShown().appearances.isEmpty)
    }

    @Test func theSeatAppearingAsksForOneHaptic() {
        var pointer = Self.seatShown()
        pointer.glide(toX: 1005, y: 685, speed: 80)
        #expect(pointer.appearances == [Self.seat])
    }

    @Test func holdingInsideTheOpenSeatAsksForNothingMore() {
        var pointer = Self.seatShown()
        pointer.glide(toX: 1005, y: 685, speed: 80)
        pointer.sample(.preview)
        pointer.time += 0.2
        pointer.sample(.preview)
        pointer.glide(toX: 1006, y: 686, speed: 50)
        #expect(pointer.appearances == [Self.seat])
    }

    @Test func leavingClearsWithoutAHaptic() {
        var pointer = Self.seatShown()
        pointer.glide(toX: 1005, y: 685, speed: 80)
        let left = pointer.intent.leave()
        #expect(left.changed)
        #expect(!left.appeared)
    }

    @Test func comingBackAndSettlingOnACentreAsksForOneMoreHaptic() {
        var pointer = Self.seatShown()
        pointer.glide(toX: 1005, y: 685, speed: 80)
        _ = pointer.intent.leave()
        pointer.time += 0.1
        pointer.x = 300
        pointer.y = 300
        pointer.sample()
        pointer.rest(for: 0.06)
        #expect(pointer.appearances == [Self.seat, Self.leftCentre])
    }

    @Test func leavingTheSplitClearsThePreviewAtOnceAndForgetsThePendingSeat() {
        var pointer = Self.earlyRelease()
        #expect(pointer.shown == Self.between)
        let left = pointer.intent.leave()
        #expect(left == SplitDropIntent.Step(shown: nil, changed: true))
        #expect(pointer.shown == nil)
        #expect(!pointer.intent.isPending)
        #expect(pointer.intent.deadline == nil)
    }

    @Test func leavingAgainChangesNothing() {
        var pointer = Self.earlyRelease()
        _ = pointer.intent.leave()
        #expect(pointer.intent.leave() == SplitDropIntent.Step(shown: nil, changed: false))
    }

    @Test func sweepingBackInFastRightBesideWhereItLeftOpensNothingSinceLeavingForgetsTheOldSamples() {
        var returning = Pointer(x: 10, y: 300)
        returning.sample()
        returning.rest(for: 0.06)
        #expect(returning.shown == Self.leftEdge)
        #expect(returning.intent.leave().changed)
        returning.time += 2
        returning.x = 0
        returning.y = 305
        returning.sample()
        returning.glide(toX: 400, y: 305, speed: 1500)
        #expect(returning.shown == nil)
        #expect(returning.appearances == [Self.leftEdge])
    }

    @Test func aClockThatRunsBackwardsStillLetsTheDwellOpenTheZone() {
        var rewound = Pointer(x: 300, y: 300)
        rewound.sample()
        rewound.glide(toX: 330, y: 300, speed: 350)
        rewound.time -= 5
        rewound.glide(toX: 400, y: 300, speed: 350)
        #expect(rewound.shown == Self.leftCentre)
    }

    @Test func escapeOrTheDragsEndResetsEverythingAtOnce() {
        var escaped = Self.columnOpen()
        escaped.intent.reset()
        #expect(escaped.shown == nil)
        #expect(!escaped.intent.isPending)
        #expect(escaped.intent.deadline == nil)
    }

    @Test func afterAResetThePointersSpeedIsMeasuredAfreshBeforeAnythingOpens() {
        var escaped = Self.columnOpen()
        escaped.intent.reset()
        escaped.time += 0.008
        escaped.sample()
        #expect(escaped.shown == nil)
        #expect(escaped.intent.deadline == escaped.time + 0.05)
    }

    private static func pastTheGap() -> Pointer {
        var pointer = columnOpen()
        pointer.glide(toX: 750, y: 300, speed: 1500)
        return pointer
    }

    @Test func thePaneBeyondTheGapOffersTheSameColumn() {
        let pointer = Self.pastTheGap()
        #expect(pointer.shown == Self.between)
        #expect(!pointer.intent.isPending)
    }

    @Test func theRightCentreIsPending() {
        var pointer = Self.pastTheGap()
        pointer.sample(.pane(Self.rightCentre))
        #expect(pointer.intent.isPending)
    }

    @Test func aGapKeepsTheOpenColumnAndCancelsAnythingPending() {
        var pointer = Self.pastTheGap()
        pointer.sample(.pane(Self.rightCentre))
        pointer.x = 705
        pointer.time += 0.008
        pointer.sample()
        #expect(pointer.steps.last?.place == .preview)
        #expect(pointer.shown == Self.between)
        #expect(!pointer.intent.isPending)
        #expect(pointer.intent.deadline == nil)
    }

    @Test func evenRestingInAGapKeepsTheColumn() {
        var pointer = Self.pastTheGap()
        pointer.x = 705
        pointer.time += 0.008
        pointer.sample()
        pointer.rest(for: 0.3)
        #expect(pointer.shown == Self.between)
        #expect(pointer.steps.suffix(30).allSatisfy { !$0.step.changed })
    }

    private static func onEmptySpot() -> Pointer {
        var pointer = pastTheGap()
        for _ in 0..<4 {
            pointer.x += 20
            pointer.time += 0.008
            pointer.sample(.pane(nil))
        }
        return pointer
    }

    @Test func aSpotOfferingNothingWaitsLikeAnyOtherZone() {
        let pointer = Self.onEmptySpot()
        #expect(pointer.shown == Self.between)
        #expect(pointer.intent.isPending)
    }

    @Test func settlingOnASpotOfferingNothingClosesTheColumnWithoutAHaptic() {
        var pointer = Self.onEmptySpot()
        pointer.time += 0.05
        pointer.sample(.pane(nil))
        #expect(pointer.shown == nil)
        #expect(pointer.steps.last?.step.changed == true)
        #expect(pointer.steps.last?.step.appeared == false)
    }

    @Test func aZeroDwellOpensEveryZoneOnEntry() {
        var pointer = Pointer(x: 0, y: 300, intent: SplitDropIntent(dwell: 0))
        pointer.sample()
        #expect(pointer.shown == Self.leftEdge)
        #expect(pointer.steps.last?.step.appeared == true)
    }

    @Test func aZeroDwellFollowsThePointerHoweverFastItMoves() {
        var pointer = Pointer(x: 0, y: 300, intent: SplitDropIntent(dwell: 0))
        pointer.sample()
        pointer.glide(toX: 300, y: 300, speed: 3000)
        #expect(pointer.shown == Self.leftCentre)
    }
}
