import AppKit
@testable import ParcCore
import QuartzCore
import Testing
@testable import Parc

@MainActor
struct SplitDropReservationIntentTests {
    @MainActor private final class IntentRig {
        let scene = SplitDropReservationSupport.Scene()
        let lease: ParcSplitView.DropReservation
        var now: TimeInterval = 100
        var due = 0
        let seat: NSPoint

        init() {
            scene.addColumn()
            lease = scene.split.prepareDropReservation(in: scene.host, contents: scene.panes.map(\.body))!
            lease.setInsertionColor { [ink = scene.ink] in ink }
            seat = NSPoint(x: scene.columnFrames[2].midX, y: scene.columnFrames[2].maxY - 10)
            lease.clock = { [weak self] in self?.now ?? 0 }
            lease.onIntentDue = { [weak self] in self?.due += 1 }
        }

        func sweep(from start: NSPoint, to end: NSPoint, steps: Int = 40, each: (SplitDropGeometry.Proposal?) -> Void = { _ in }) {
            for step in 1...steps {
                let progress = CGFloat(step) / CGFloat(steps)
                now += 0.008
                each(lease.proposal(at: NSPoint(x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress),
                                    canPropose: scene.allowAll))
            }
        }

        func settleOnSeat() -> SplitDropGeometry.Proposal? {
            sweep(from: NSPoint(x: 1, y: 200), to: seat)
            now += 0.05
            return lease.proposal(at: seat, canPropose: scene.allowAll)
        }
    }

    @Test func aFastSweepToTheLoneColumnsBottomBandOpensNothingAndMovesNoPane() {
        let rig = IntentRig()
        var opened = false
        rig.sweep(from: NSPoint(x: 1, y: 200), to: rig.seat) { _ in
            opened = opened || rig.lease.shownTarget != nil || rig.lease.appeared
                || rig.scene.split.arrangedSubviews.map(\.frame) != rig.scene.columnFrames
        }
        #expect(!opened)
        #expect(rig.scene.split.subviews.count == 3)
    }

    @Test func theSeatUnderThePointerWaitsDueOneSampleWindowAfterTheLastMovement() {
        let rig = IntentRig()
        rig.sweep(from: NSPoint(x: 1, y: 200), to: rig.seat)
        #expect(rig.lease.hoverIntent.isPending)
        #expect(rig.lease.hoverIntent.deadline == rig.now + 0.05)
    }

    @Test func externalDropIntentWaitsForTheStationaryPointerDeadline() throws {
        let scene = SplitDropReservationSupport.Scene()
        let lease = try #require(scene.split.prepareDropReservation(in: scene.host, contents: scene.panes.map(\.body)))
        let edge = scene.host.convert(NSPoint(x: 1, y: 200), to: nil)
        let drag = SplitDropDragInfo(window: scene.window, location: edge)
        drag.writeURL("https://intent.invalid")
        let now: TimeInterval = 100
        var timers: [Timer] = []
        lease.clock = { now }
        lease.intentFireDate = { Date(timeIntervalSinceReferenceDate: now + $0) }
        lease.scheduleIntentTimer = { timers.append($0) }
        let session = try #require(ExternalSplitDropSession(host: scene.host, info: drag, frames: scene.originalFrames,
            orientation: .horizontal, reservation: lease, validate: { lease.isCurrent }, insertionColor: { .black },
            canPropose: scene.allowAll, commit: { _, _ in false }))
        session.targets.performFeedback = {}
        var targets: [SplitDropTarget?] = []
        session.targets.onChange = { targets.append($0) }

        #expect(session.update(drag) == .copy)
        #expect(targets.isEmpty)
        let deadline = now + 0.05
        let timer = try #require(timers.first)
        #expect(timer.fireDate == Date(timeIntervalSinceReferenceDate: deadline))
    }

    @Test func externalDropIntentRechecksTheStationaryPointerAtItsDeadline() throws {
        let scene = SplitDropReservationSupport.Scene()
        let lease = try #require(scene.split.prepareDropReservation(in: scene.host, contents: scene.panes.map(\.body)))
        let edge = scene.host.convert(NSPoint(x: 1, y: 200), to: nil)
        let drag = SplitDropDragInfo(window: scene.window, location: edge)
        drag.writeURL("https://intent.invalid")
        var now: TimeInterval = 100
        var timers: [Timer] = []
        lease.clock = { now }
        lease.intentFireDate = { Date(timeIntervalSinceReferenceDate: now + $0) }
        lease.scheduleIntentTimer = { timers.append($0) }
        let session = try #require(ExternalSplitDropSession(host: scene.host, info: drag, frames: scene.originalFrames,
            orientation: .horizontal, reservation: lease, validate: { lease.isCurrent }, insertionColor: { .black },
            canPropose: scene.allowAll, commit: { _, _ in false }))
        session.targets.performFeedback = {}
        var targets: [SplitDropTarget?] = []
        session.targets.onChange = { targets.append($0) }
        _ = session.update(drag)
        let deadline = now + 0.05
        let timer = try #require(timers.first)

        now = deadline
        timer.fire()

        #expect(targets == [.insert(0)])
        #expect(timers.count == 1)
        #expect(!timer.isValid)
    }

    @Test func aReleaseBeforeTheSeatAppearsDropsIntoTheSeatAndMovesNothingFirst() {
        let rig = IntentRig()
        rig.sweep(from: NSPoint(x: 1, y: 200), to: rig.seat)
        let early = rig.lease.proposal(at: rig.seat, canPropose: rig.scene.allowAll, presenting: false)
        #expect(early?.0 == .stack(2, after: true))
        #expect(early?.1 == .horizontal)
        #expect(rig.scene.split.arrangedSubviews.map(\.frame) == rig.scene.columnFrames)
    }

    @Test func onceThePointerSettlesTheSeatOpensAndAsksForItsHaptic() {
        let rig = IntentRig()
        let settled = rig.settleOnSeat()
        #expect(settled?.0 == .stack(2, after: true))
        #expect(rig.lease.shownTarget == .stack(2, after: true))
        #expect(rig.lease.appeared)
        #expect(rig.scene.split.arrangedSubviews.map(\.frame) != rig.scene.columnFrames)
    }

    @Test func sweepingOnTowardTheLeftEdgeKeepsTheOpenSeatWithNoCollapse() throws {
        let rig = IntentRig()
        _ = rig.settleOnSeat()
        let seatFrames = rig.scene.split.arrangedSubviews.map(\.frame)
        let region = try #require(rig.scene.region())
        var collapsed = false
        rig.sweep(from: rig.seat, to: NSPoint(x: 1, y: 200)) { proposal in
            collapsed = collapsed || rig.lease.shownTarget != .stack(2, after: true) || rig.lease.appeared
                || rig.scene.split.arrangedSubviews.map(\.frame) != seatFrames || region.superview !== rig.scene.split
                || region.layer?.opacity != 1 || proposal == nil
        }
        #expect(!collapsed)
    }

    @Test func settlingOnTheLeftEdgeMovesTheSameRegionStraightFromTheSeat() throws {
        let rig = IntentRig()
        let seatRect = try #require(rig.settleOnSeat()).2
        let region = try #require(rig.scene.region())
        rig.sweep(from: rig.seat, to: NSPoint(x: 1, y: 200))
        rig.now += 0.05
        let edge = rig.lease.proposal(at: NSPoint(x: 1, y: 200), canPropose: rig.scene.allowAll)
        let move = region.layer?.animation(forKey: "Split drop region") as? CAAnimationGroup
        let bounds = move?.animations?.compactMap { $0 as? CABasicAnimation }.first { $0.keyPath == "bounds" }
        #expect(edge?.0 == .insert(0))
        #expect(rig.lease.shownTarget == .insert(0))
        #expect(rig.lease.appeared)
        #expect(region.superview === rig.scene.split)
        #expect(region.layer?.opacity == 1)
        #expect((bounds?.fromValue as? NSValue)?.rectValue.size == seatRect.size)
    }

    @Test func leavingTheSplitClearsThePreviewAtOnce() {
        let rig = IntentRig()
        _ = rig.settleOnSeat()
        #expect(rig.lease.proposal(at: NSPoint(x: -20, y: -20), canPropose: rig.scene.allowAll) == nil)
        #expect(rig.lease.shownTarget == nil)
        #expect(rig.scene.split.arrangedSubviews.map(\.frame) == rig.scene.columnFrames)
    }

    @Test func endingTheIntentLeaseRestoresTheStackedFramesAndForgetsTheIntent() {
        let rig = IntentRig()
        _ = rig.settleOnSeat()
        rig.lease.end()
        #expect(rig.scene.split.arrangedSubviews.map(\.frame) == rig.scene.columnFrames)
        #expect(rig.scene.split.subviews.count == 3)
        #expect(!rig.lease.hoverIntent.isPending)
    }
}
