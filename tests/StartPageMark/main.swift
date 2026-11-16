import QuartzCore

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

@MainActor @main struct StartPageMarkTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("StartPageMark: \(message)") }
    }
    static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 1e-6) -> Bool { abs(a - b) <= tolerance }
    static func near(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 1e-6) -> Bool {
        near(a.x, b.x, tolerance) && near(a.y, b.y, tolerance)
    }
    static func near(_ a: CATransform3D, _ b: CATransform3D, _ tolerance: CGFloat = 1e-6) -> Bool {
        [(a.m11, b.m11), (a.m12, b.m12), (a.m21, b.m21), (a.m22, b.m22), (a.m41, b.m41), (a.m42, b.m42),
         (a.m33, b.m33), (a.m44, b.m44)].allSatisfy { near($0.0, $0.1, tolerance) }
    }
    static func apply(_ t: CATransform3D, _ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * t.m11 + p.y * t.m21 + t.m41, y: p.x * t.m12 + p.y * t.m22 + t.m42)
    }

    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        singleAndDoubleClicksAreInert()
        dragTriggersTaffy()
        holdTriggersCharge()
        holdThenMove()
        moveThenHold()
        tripleClickSwoops()
        busyGesturesAreIgnored()
        triggersDoNotStack()
        reduceMotionPerEgg()
        pauseConditions()
        poseMaths()
        stretchMaths()
        springMaths()
        swoopMaths()
        ribbonGeometry()
        chargeMaths()
        confettiMaths()
        taffyAnimator()
        stageSwoop()
        stageCharge()
        stagePauseCleanup()
        shimmer()
        fillAndTint()
        print("StartPageMark: \(count) assertions passed")
    }

    struct Pointer {
        var recognizer = StartPageMarkGestureRecognizer(clickInterval: 0.5)
        var session = StartPageMarkSession()
        var canAnimate = true
        var reduceMotion = false

        mutating func send(_ cues: [StartPageMarkCue]) -> [StartPageMarkSession.Effect] {
            var effects: [StartPageMarkSession.Effect] = []
            for cue in cues {
                let produced = session.handle(cue, canAnimate: canAnimate, reduceMotion: reduceMotion)
                if produced.contains(.reset) { recognizer.reset() }
                effects += produced
            }
            return effects
        }
        mutating func down(_ point: CGPoint, _ time: TimeInterval) -> [StartPageMarkSession.Effect] {
            send(recognizer.pointerDown(at: point, time: time, idle: session.isIdle))
        }
        mutating func drag(_ point: CGPoint, _ time: TimeInterval) -> [StartPageMarkSession.Effect] {
            send(recognizer.pointerDragged(to: point, time: time))
        }
        mutating func up(_ point: CGPoint, _ time: TimeInterval) -> [StartPageMarkSession.Effect] {
            send(recognizer.pointerUp(at: point, time: time))
        }
        mutating func hold(_ time: TimeInterval) -> [StartPageMarkSession.Effect] {
            send(recognizer.holdElapsed(at: time))
        }
        mutating func click(_ point: CGPoint, _ time: TimeInterval) -> [StartPageMarkSession.Effect] {
            down(point, time) + up(point, time + 0.08)
        }
    }

    static func singleAndDoubleClicksAreInert() {
        var recognizer = StartPageMarkGestureRecognizer(clickInterval: 0.5)
        let origin = CGPoint(x: 30, y: 40)
        check(recognizer.pointerDown(at: origin, time: 0, idle: true).isEmpty, "pressing the mark does nothing on its own")
        check(recognizer.holdDeadline == StartPageMarkGestureRecognizer.holdDelay, "a still press arms one hold deadline")
        check(recognizer.pointerUp(at: origin, time: 0.1).isEmpty, "a single click does nothing")
        check(recognizer.holdDeadline == nil, "releasing disarms the hold deadline")
        check(recognizer.clicks?.count == 1, "a quick still press counts as a click")
        var pointer = Pointer()
        check(pointer.click(origin, 0).isEmpty, "a single click does nothing")
        check(pointer.click(origin, 0.3).isEmpty, "two clicks do nothing")
        check(pointer.session.phase == .rest && pointer.session.generation == 0, "inert clicks leave the mark at rest")
        _ = pointer.down(origin, 5)
        check(pointer.drag(CGPoint(x: 33, y: 42), 5.05).isEmpty, "a jitter inside the slop does not start the stretch")
        check(pointer.drag(CGPoint(x: 34, y: 40), 5.06).isEmpty, "a drag of exactly the slop does not start the stretch")
        check(pointer.up(CGPoint(x: 33, y: 42), 5.1).isEmpty, "a click that wobbles inside the slop does nothing")
        check(pointer.drag(CGPoint(x: 90, y: 40), 5.2).isEmpty, "a drag after release without a press does nothing")
        check(pointer.up(CGPoint(x: 90, y: 40), 5.3).isEmpty, "a stray release does nothing")
        check(pointer.hold(6).isEmpty, "a stray hold deadline does nothing")
        var session = StartPageMarkSession()
        check([StartPageMarkCue.track(CGVector(dx: 5, dy: 0)), .release(CGVector(dx: 5, dy: 0)), .discharge(1), .cancel(1)]
                .flatMap { session.handle($0, canAnimate: true, reduceMotion: false) }.isEmpty,
              "follow-up cues without a trigger do nothing")
        check(session.phase == .rest && session.generation == 0, "follow-up cues leave the mark at rest")
    }

    static func dragTriggersTaffy() {
        var pointer = Pointer()
        _ = pointer.down(.zero, 0)
        let first = pointer.recognizer.pointerDragged(to: CGPoint(x: 10, y: 0), time: 0.05)
        check(first == [.begin(.taffy), .track(CGVector(dx: 6, dy: 0))], "crossing the slop before the hold triggers Taffy once")
        check(pointer.recognizer.holdDeadline == nil, "a drag disarms the hold")
        check(pointer.send(first) == [.track(CGVector(dx: 6, dy: 0))], "the trigger starts interactive stretching")
        check(pointer.session.phase == .interacting(.taffy, .motion), "the session is stretching")
        let second = pointer.recognizer.pointerDragged(to: CGPoint(x: 24, y: 7), time: 0.1)
        check(second.count == 1 && { if case .track = second[0] { return true }; return false }(), "later drags only track")
        check(pointer.recognizer.holdElapsed(at: 1).isEmpty, "a late hold deadline does not turn a drag into a charge")
        check(pointer.recognizer.pointerDragged(to: CGPoint(x: 2, y: 0), time: 1.1) == [.track(CGVector(dx: 0, dy: 0))],
              "returning inside the slop relaxes the stretch without ending it")
        let release = pointer.recognizer.pointerUp(at: CGPoint(x: 40, y: 0), time: 1.2)
        check(release == [.release(CGVector(dx: 36, dy: 0))], "releasing reports the final pull")
        check(pointer.send(release) == [.play(.snap(CGVector(dx: 36, dy: 0))), .haptic], "release snaps home once with one haptic tick")
        check(pointer.session.phase == .playing(.taffy, .motion), "the snap-home is playing")
        check(pointer.send(release).isEmpty, "a repeated release does not replay")
        check(pointer.session.land(generation: pointer.session.generation).isEmpty, "Taffy has no landing tick")
        check(TaffyStretch.pull(CGVector(dx: 0, dy: -4)) == CGVector(dx: 0, dy: 0), "the pull starts at zero at the slop")
        let pull = TaffyStretch.pull(CGVector(dx: 30, dy: 40))
        check(near(pull.dx, 30 * 46 / 50) && near(pull.dy, 40 * 46 / 50), "the pull keeps the drag's direction")
    }

    static func holdTriggersCharge() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 20, y: 30), 10)
        check(pointer.recognizer.holdDeadline == 10 + StartPageMarkGestureRecognizer.holdDelay, "the hold deadline is one bounded delay away")
        check(pointer.hold(10.2).isEmpty, "an early deadline check does not charge")
        check(pointer.drag(CGPoint(x: 22, y: 31), 10.3).isEmpty, "a still press inside the slop keeps waiting")
        check(pointer.hold(10.36) == [.charge(.motion)], "holding still past the threshold starts charging")
        check(pointer.session.phase == .interacting(.charge, .motion), "the session is charging")
        check(pointer.recognizer.holdDeadline == nil, "charging needs no further timer")
        check(pointer.hold(11).isEmpty, "a repeated deadline does not restart the charge")
        check(pointer.drag(CGPoint(x: 26, y: 34), 10.5).isEmpty, "a small wobble keeps the charge")
        let release = pointer.recognizer.pointerUp(at: CGPoint(x: 26, y: 34), time: 10.36 + StartPageMarkCharge.ramp + 0.05)
        check(release == [.discharge(1)], "releasing reports a full charge after the ramp")
        check(pointer.send(release) == [.play(.loop)], "a full charge loops the loop")
        let generation = pointer.session.generation
        check(pointer.session.landing, "the loop waits for its landing")
        check(pointer.session.land(generation: generation - 1).isEmpty, "a stale landing does not tick")
        check(pointer.session.land(generation: generation) == [.haptic], "the landing ticks")
        check(pointer.session.land(generation: generation).isEmpty, "the landing ticks once")
        pointer.session.finish(generation: generation)
        check(pointer.session.phase == .rest, "the loop finishes")
        var weak = Pointer()
        _ = weak.down(.zero, 0)
        _ = weak.hold(0.35)
        let short = weak.recognizer.pointerUp(at: .zero, time: 0.55)
        let shortLevel = StartPageMarkCharge.level(held: 0.55 - 0.35)
        check(short == [.discharge(shortLevel)] && near(shortLevel, 0.2 / StartPageMarkCharge.ramp), "a short charge reports its level")
        check(weak.send(short) == [.play(.relax(shortLevel, .motion))], "an undercharged release relaxes without a loop")
        check(!weak.session.landing && weak.session.land(generation: weak.session.generation).isEmpty, "a relax never ticks")
        check(StartPageMarkCharge.launches(StartPageMarkCharge.launchLevel) && !StartPageMarkCharge.launches(0.59),
              "the loop needs the mockup's 60% charge")
        var late = Pointer()
        _ = late.down(.zero, 0)
        let lateLevel = StartPageMarkCharge.level(held: 0.5 - StartPageMarkGestureRecognizer.holdDelay)
        check(late.up(.zero, 0.5) == [.charge(.motion), .play(.relax(lateLevel, .motion))],
              "a release after the threshold without a timer is a hold, charged from when the hold began")
        check(late.recognizer.clicks == nil, "a held press never counts as a click")
    }

    static func holdThenMove() {
        var pointer = Pointer()
        _ = pointer.down(CGPoint(x: 10, y: 10), 0)
        _ = pointer.hold(0.35)
        check(pointer.drag(CGPoint(x: 16, y: 14), 0.45).isEmpty, "moving inside the charge slop keeps charging")
        check(pointer.session.phase == .interacting(.charge, .motion), "still charging")
        let cancel = pointer.recognizer.pointerDragged(to: CGPoint(x: 19, y: 10), time: 0.55)
        check(cancel.count == 1 && { if case .cancel = cancel[0] { return true }; return false }(),
              "moving past the charge slop cancels the charge quietly")
        check(!cancel.contains(.begin(.taffy)), "a cancelled charge never turns into Taffy")
        let effects = pointer.send(cancel)
        check(effects.count == 1 && !effects.contains(.haptic) && { if case .play(.relax) = effects[0] { return true }; return false }(),
              "a cancelled charge relaxes without a tick")
        check(pointer.drag(CGPoint(x: 80, y: 10), 0.6).isEmpty, "the cancelled gesture stays inert")
        check(pointer.up(CGPoint(x: 80, y: 10), 0.7).isEmpty, "releasing a cancelled charge plays nothing")
        var late = Pointer()
        _ = late.down(.zero, 0)
        let cues = late.recognizer.pointerDragged(to: CGPoint(x: 12, y: 0), time: 0.5)
        check(cues == [.begin(.charge), .cancel(StartPageMarkCharge.level(held: 0.5 - StartPageMarkGestureRecognizer.holdDelay))],
              "movement after the hold threshold charges rather than stretching")
    }

    static func moveThenHold() {
        var pointer = Pointer()
        _ = pointer.down(.zero, 0)
        check(pointer.drag(CGPoint(x: 5, y: 0), 0.2) == [.track(CGVector(dx: 1, dy: 0))], "moving before the threshold starts Taffy")
        check(pointer.hold(0.4).isEmpty && pointer.session.phase == .interacting(.taffy, .motion),
              "holding still after a drag keeps Taffy")
        check(pointer.recognizer.clicks == nil, "a drag resets the click count")
    }

    static func tripleClickSwoops() {
        var pointer = Pointer()
        let spot = CGPoint(x: 30, y: 50)
        _ = pointer.click(spot, 0)
        _ = pointer.click(CGPoint(x: 33, y: 52), 0.2)
        check(pointer.recognizer.clicks?.count == 2, "two quick clicks are counted")
        let third = pointer.recognizer.pointerDown(at: CGPoint(x: 34, y: 47), time: 0.4, idle: true)
        check(third == [.begin(.swoop)], "the third quick click swoops")
        check(pointer.recognizer.holdDeadline == nil && pointer.recognizer.clicks == nil, "the swoop consumes the clicks and arms no hold")
        check(pointer.send(third) == [.play(.swoop)], "the swoop plays at once")
        check(pointer.session.phase == .playing(.swoop, .motion) && pointer.session.landing, "the swoop waits for its landing")
        check(pointer.drag(CGPoint(x: 80, y: 80), 0.45).isEmpty, "dragging the third press does nothing more")
        check(pointer.up(CGPoint(x: 80, y: 80), 0.5).isEmpty, "releasing the third press does nothing more")
        check(pointer.session.land(generation: pointer.session.generation) == [.haptic], "the swoop ticks on landing")
        var slow = Pointer()
        _ = slow.click(spot, 0)
        _ = slow.click(spot, 0.3)
        check(slow.down(spot, 0.38 + 0.51).isEmpty, "a slow third click does not swoop")
        check(slow.recognizer.clicks == nil, "a slow click starts a new count")
        var far = Pointer()
        _ = far.click(spot, 0)
        _ = far.click(spot, 0.2)
        check(far.down(CGPoint(x: spot.x + 9, y: spot.y), 0.4).isEmpty, "a third click away from the first does not swoop")
        var system = Pointer()
        system.recognizer.clickInterval = 1.5
        _ = system.click(spot, 0)
        _ = system.click(spot, 1)
        check(system.down(spot, 2) == [.play(.swoop)], "the click interval follows the system setting")
        var broken = Pointer()
        _ = broken.click(spot, 0)
        _ = broken.down(spot, 0.2)
        _ = broken.drag(CGPoint(x: spot.x + 20, y: spot.y), 0.25)
        _ = broken.up(CGPoint(x: spot.x + 20, y: spot.y), 0.3)
        broken.session.finish(generation: broken.session.generation)
        _ = broken.click(spot, 0.4)
        check(broken.down(spot, 0.6).isEmpty, "a drag between clicks breaks the triple-click")
    }

    static func busyGesturesAreIgnored() {
        var pointer = Pointer()
        _ = pointer.down(.zero, 0)
        _ = pointer.drag(CGPoint(x: 0, y: 20), 0.1)
        _ = pointer.up(CGPoint(x: 0, y: 20), 0.2)
        let playing = pointer.session.generation
        check(pointer.session.phase == .playing(.taffy, .motion), "the first trigger plays")
        check(pointer.recognizer.pointerDown(at: .zero, time: 0.3, idle: false).isEmpty, "a press during playback is ignored for its whole gesture")
        check(pointer.recognizer.holdDeadline == nil, "an ignored press arms no hold")
        check(pointer.drag(CGPoint(x: 20, y: 0), 0.35).isEmpty, "an ignored press never stretches")
        pointer.session.finish(generation: playing)
        check(pointer.drag(CGPoint(x: 40, y: 0), 0.45).isEmpty, "the ignored gesture stays ignored after the play ends")
        check(pointer.up(CGPoint(x: 40, y: 0), 0.5).isEmpty, "releasing the ignored gesture plays nothing")
        var clicks = Pointer()
        _ = clicks.down(.zero, 0)
        _ = clicks.hold(0.35)
        _ = clicks.up(.zero, 1.5)
        let loop = clicks.session.generation
        _ = clicks.click(.zero, 1.6)
        _ = clicks.click(.zero, 1.8)
        clicks.session.finish(generation: loop)
        check(clicks.down(.zero, 2.0).isEmpty, "clicks during playback never count toward a swoop")
        check(clicks.recognizer.clicks == nil, "the count starts fresh after playback")
        var holding = Pointer()
        _ = holding.down(.zero, 0)
        _ = holding.hold(0.35)
        _ = holding.up(.zero, 0.6)
        _ = holding.recognizer.pointerDown(at: .zero, time: 0.7, idle: holding.session.isIdle)
        check(holding.hold(1.1).isEmpty, "holding during a relax does not charge again")
    }

    static func triggersDoNotStack() {
        var session = StartPageMarkSession()
        _ = session.handle(.begin(.swoop), canAnimate: true, reduceMotion: false)
        for cue in [StartPageMarkCue.begin(.swoop), .begin(.charge), .begin(.taffy), .track(CGVector(dx: 9, dy: 0)),
                    .release(CGVector(dx: 9, dy: 0)), .discharge(1), .cancel(1)] {
            check(session.handle(cue, canAnimate: true, reduceMotion: false).isEmpty, "a trigger during playback is ignored")
        }
        check(session.phase == .playing(.swoop, .motion), "the first play keeps going")
        var stale = StartPageMarkSession()
        _ = stale.handle(.begin(.taffy), canAnimate: true, reduceMotion: false)
        _ = stale.handle(.release(.zero), canAnimate: true, reduceMotion: false)
        let old = stale.generation
        _ = stale.pause()
        _ = stale.handle(.begin(.taffy), canAnimate: true, reduceMotion: false)
        _ = stale.handle(.release(.zero), canAnimate: true, reduceMotion: false)
        stale.finish(generation: old)
        check(stale.phase == .playing(.taffy, .motion), "a stale completion cannot end a newer play")
        stale.finish(generation: stale.generation)
        check(stale.phase == .rest, "the current completion ends the play")
        var interacting = StartPageMarkSession()
        _ = interacting.handle(.begin(.charge), canAnimate: true, reduceMotion: false)
        interacting.finish(generation: interacting.generation)
        check(interacting.phase == .interacting(.charge, .motion), "a completion cannot end a charge that is still held")
        var mismatched = StartPageMarkSession()
        _ = mismatched.handle(.begin(.taffy), canAnimate: true, reduceMotion: false)
        check(mismatched.handle(.discharge(1), canAnimate: true, reduceMotion: false).isEmpty, "a charge release cannot end a stretch")
        _ = mismatched.pause()
        _ = mismatched.handle(.begin(.charge), canAnimate: true, reduceMotion: false)
        check(mismatched.handle(.release(.zero), canAnimate: true, reduceMotion: false).isEmpty, "a stretch release cannot end a charge")
    }

    static func reduceMotionPerEgg() {
        check(StartPageMarkMotionStyle(reduceMotion: true) == .shimmer, "Reduce Motion selects the shimmer")
        check(StartPageMarkMotionStyle(reduceMotion: false) == .motion, "motion is the default")
        var taffy = Pointer()
        taffy.reduceMotion = true
        _ = taffy.down(.zero, 0)
        check(taffy.drag(CGPoint(x: 20, y: 0), 0.1).isEmpty, "Reduce Motion never stretches the mark")
        check(taffy.session.phase == .interacting(.taffy, .shimmer), "the stretch is held as a shimmer")
        taffy.reduceMotion = false
        check(taffy.drag(CGPoint(x: 30, y: 9), 0.2).isEmpty, "turning Reduce Motion off mid-gesture keeps the shimmer chosen at the trigger")
        check(taffy.up(CGPoint(x: 30, y: 9), 0.3) == [.shimmer, .haptic], "Reduce Motion replaces the snap with the shimmer and its tick")
        check(taffy.session.phase == .playing(.taffy, .shimmer), "the shimmer gates further triggers")
        var swoop = Pointer()
        swoop.reduceMotion = true
        _ = swoop.click(.zero, 0)
        _ = swoop.click(.zero, 0.2)
        check(swoop.down(.zero, 0.4) == [.shimmer, .haptic], "Reduce Motion replaces the swoop with the shimmer")
        check(!swoop.session.landing && swoop.session.land(generation: swoop.session.generation).isEmpty, "a shimmer swoop never lands")
        var charge = Pointer()
        charge.reduceMotion = true
        _ = charge.down(.zero, 0)
        check(charge.hold(0.35) == [.charge(.shimmer)], "Reduce Motion charges with the glow only")
        check(charge.up(.zero, 1.2) == [.shimmer, .haptic], "Reduce Motion replaces the loop with the shimmer")
        check(!charge.session.landing, "a shimmer charge never lands")
        var weak = Pointer()
        weak.reduceMotion = true
        _ = weak.down(.zero, 0)
        _ = weak.hold(0.35)
        check(weak.up(.zero, 0.5) == [.play(.relax(StartPageMarkCharge.level(held: 0.5 - 0.35), .shimmer))],
              "an undercharged Reduce Motion release only fades the glow")
    }

    static func pauseConditions() {
        let visible = StartPageMarkActivity(windowVisible: true, occluded: false, miniaturized: false, hidden: false)
        check(visible.canAnimate, "a visible window animates")
        var occluded = visible; occluded.occluded = true
        var miniaturized = visible; miniaturized.miniaturized = true
        var hidden = visible; hidden.hidden = true
        var closed = visible; closed.windowVisible = false
        check(!occluded.canAnimate, "an occluded window pauses")
        check(!miniaturized.canAnimate, "a miniaturized window pauses")
        check(!hidden.canAnimate, "a hidden start page pauses")
        check(!closed.canAnimate, "a window that is not visible pauses")
        check(!StartPageMarkActivity.inactive.canAnimate, "a mark without a window pauses")
        for egg in [StartPageMarkEasterEgg.taffy, .swoop, .charge] {
            var session = StartPageMarkSession()
            check(session.handle(.begin(egg), canAnimate: false, reduceMotion: false).isEmpty && session.phase == .rest,
                  "a trigger in a paused window is skipped")
        }
        var session = StartPageMarkSession()
        check(session.pause().isEmpty && session.generation == 0, "pausing at rest does nothing")
        _ = session.handle(.begin(.taffy), canAnimate: true, reduceMotion: false)
        check(session.handle(.track(CGVector(dx: 9, dy: 0)), canAnimate: false, reduceMotion: false) == [.reset],
              "losing visibility mid-stretch puts the mark back at rest")
        _ = session.handle(.begin(.charge), canAnimate: true, reduceMotion: false)
        check(session.handle(.discharge(1), canAnimate: false, reduceMotion: false) == [.reset],
              "a release in a paused window neither plays nor ticks")
        _ = session.handle(.begin(.swoop), canAnimate: true, reduceMotion: false)
        let generation = session.generation
        check(session.pause() == [.reset] && session.phase == .rest, "occluding the window mid-swoop skips to rest")
        check(session.land(generation: generation).isEmpty, "the paused swoop's landing never ticks")
        session.finish(generation: generation)
        check(session.phase == .rest && session.generation == generation + 1, "the paused play's completion is stale")
        var pointer = Pointer()
        _ = pointer.down(.zero, 0)
        _ = pointer.hold(0.35)
        pointer.canAnimate = false
        check(pointer.drag(CGPoint(x: 12, y: 0), 0.4) == [.reset], "hiding the window mid-charge resets it")
        check(pointer.recognizer.press == nil && pointer.recognizer.holdDeadline == nil, "a pause ends the gesture")
    }

    static func poseMaths() {
        let size = CGSize(width: 65, height: 96)
        let down = StartPageMarkFrame(size: size, anchor: .zero, yDown: true)
        let up = StartPageMarkFrame(size: size, anchor: .zero, yDown: false)
        check(near(StartPageMarkPose.identity.transform(in: down), CATransform3DIdentity), "the resting pose is the identity")
        check(near(StartPageMarkPose.identity.transform(in: up), CATransform3DIdentity), "the resting pose is the identity in an upward space")
        let squash = StartPageMarkPose(scale: CGSize(width: 1.2, height: 0.7), origin: StartPageMarkPose.bottom)
        let downSquash = squash.transform(in: down)
        check(near(apply(downSquash, CGPoint(x: 32.5, y: 96)), CGPoint(x: 32.5, y: 96)), "a squash keeps the base in place")
        check(near(apply(downSquash, CGPoint(x: 32.5, y: 0)).y, 96 * 0.3), "a squash lowers the top")
        let upSquash = squash.transform(in: up)
        check(near(apply(upSquash, CGPoint(x: 32.5, y: 0)), CGPoint(x: 32.5, y: 0)), "an upward space keeps the base at its bottom")
        check(near(apply(upSquash, CGPoint(x: 32.5, y: 96)).y, 96 * 0.7), "an upward space lowers the top")
        let turn = StartPageMarkPose(rotation: .pi / 2).transform(in: down)
        check(near(apply(turn, CGPoint(x: 65, y: 48)), CGPoint(x: 32.5, y: 48 + 32.5)), "a positive rotation turns clockwise on screen")
        let upTurn = StartPageMarkPose(rotation: .pi / 2).transform(in: up)
        check(near(apply(upTurn, CGPoint(x: 65, y: 48)), CGPoint(x: 32.5, y: 48 - 32.5)), "an upward layer space mirrors the pose")
        let moved = StartPageMarkPose(offset: CGVector(dx: 10, dy: -20))
        check(near(apply(moved.transform(in: down), .zero), CGPoint(x: 10, y: -20)), "the offset moves the mark on screen")
        check(near(apply(moved.transform(in: up), .zero), CGPoint(x: 10, y: 20)), "the offset is up on screen in an upward space")
        let centred = StartPageMarkFrame(size: size, anchor: CGPoint(x: 0.5, y: 0.5), yDown: true)
        check(near(apply(squash.transform(in: centred), CGPoint(x: 0, y: 48)), CGPoint(x: 0, y: 48)),
              "a centred anchor keeps the base in place")
        check(near(down.scale, 96 / 65), "mark-relative motion scales from the mockup's 65 pt mark")
    }

    static func stretchMaths() {
        check(TaffyStretch.elongation(0) == 0, "no pull, no stretch")
        check(near((TaffyStretch.elongation(0.001) / 0.001), TaffyStretch.resistance, 1e-3), "the stretch starts at the rubber band's resistance")
        var previous: CGFloat = 0
        for distance in stride(from: CGFloat(5), through: 2000, by: 5) {
            let value = TaffyStretch.elongation(distance)
            check(value > previous && value < TaffyStretch.reach, "the stretch grows with the pull and never passes its reach")
            previous = value
        }
        let size = CGSize(width: 65, height: 96)
        check(near(TaffyStretch.transform(pull: .zero, size: size, anchor: .zero, yDown: true), CATransform3DIdentity),
              "a zero pull leaves the mark untouched")
        let right = TaffyStretch.transform(pull: CGVector(dx: 30, dy: 0), size: size, anchor: .zero, yDown: true)
        let e = TaffyStretch.elongation(30)
        let along = 1 + e / size.width, across = 1 / along.squareRoot()
        check(near(apply(right, CGPoint(x: 65, y: 48)), CGPoint(x: 65 + e, y: 48)), "the far edge follows the pointer by the stretch")
        check(near(apply(right, CGPoint(x: 0, y: 48)), CGPoint(x: 0, y: 48)), "the near edge stays put")
        check(near(apply(right, CGPoint(x: 32.5, y: 0)).y, 48 * (1 - across)), "the mark thins across the pull like taffy")
        check(near(right.m11 * right.m22 - right.m12 * right.m21, along * across), "taffy keeps its volume")
        check(near(TaffyStretch.transform(pull: CGVector(dx: 20, dy: 20), size: size, anchor: .zero, yDown: false),
                   TaffyStretch.transform(pull: CGVector(dx: 20, dy: -20), size: size, anchor: .zero, yDown: true)),
              "an upward layer space mirrors the pointer's vertical direction")
        let squash = TaffyStretch.blend(right, -0.3)
        check(squash.m11 < 1 && squash.m22 > 1 && apply(squash, CGPoint(x: 65, y: 48)).x < 65, "overshoot squashes the mark the other way")
    }

    static func springMaths() {
        let spring = TaffySpring.spring
        check(near(spring.stiffness, pow(2 * .pi / TaffySpring.response, 2)), "stiffness follows the sidebar spring helpers")
        check(near(spring.damping, 4 * .pi * TaffySpring.dampingRatio / TaffySpring.response), "damping follows the sidebar spring helpers")
        check(near(spring.displacement(at: 0), 1), "the spring starts at the released stretch")
        for candidate in [spring, StartPageMarkLanding.spring, StartPageMarkCharge.relaxSpring(level: 1)] {
            var x = 1.0, v = 0.0, t = 0.0
            let h = 1e-5
            for target in [0.05, 0.1, 0.2, 0.4] {
                while t < target - h / 2 {
                    v += (-candidate.stiffness * x - candidate.damping * v) * h
                    x += v * h
                    t += h
                }
                check(abs(x - candidate.displacement(at: t)) < 1e-3, "the closed form matches the spring's motion at \(target)s")
            }
        }
        let samples = spring.samples()
        check(samples.first == 1 && samples.last == 0, "the samples run from the stretch to home")
        check((samples.min() ?? 0) < -0.2, "the release wobbles past home")
        let duration = Double(samples.count - 1) / StartPageMarkSpring.sampleRate
        check(duration > 0.6 && duration < 1.2, "the snap-home is short")
        let landing = StartPageMarkLanding.poses()
        check(near(landing[0].scale.height, 1 - StartPageMarkLanding.squash) && near(landing[0].scale.width, 1 + 0.8 * StartPageMarkLanding.squash),
              "the landing starts squashed onto its base")
        check(landing.last == StartPageMarkLanding.pose(0) && landing.allSatisfy { $0.origin == StartPageMarkPose.bottom },
              "the landing squashes onto its base")
        check(landing.contains { $0.scale.height > 1.05 }, "the landing bounces past home")
        check(StartPageMarkLanding.duration > 0.6 && StartPageMarkLanding.duration < 1, "the landing settles in under a second")
    }

    static func swoopMaths() {
        check(near(StartPageMarkSwoop.reach(pageWidth: 600), 870, 1e-9) && StartPageMarkSwoop.reach(pageWidth: 2000) == 1100,
              "the swoop's reach follows the page up to the mockup's cap")
        let reach: CGFloat = 870
        check(StartPageMarkSwoop.offset(progress: 0, reach: reach) == CGVector(dx: 0, dy: 0)
              && StartPageMarkSwoop.offset(progress: 1, reach: reach) == CGVector(dx: 0, dy: 0), "the swoop leaves and lands at home")
        let top = StartPageMarkSwoop.offset(progress: 0.5, reach: reach)
        check(near(top.dx, 0) && near(top.dy, -120), "the arc peaks 120 pt above home")
        let samples = stride(from: CGFloat(0), through: 1, by: 0.01).map { StartPageMarkSwoop.offset(progress: $0, reach: reach) }
        check(samples.allSatisfy { $0.dy <= 0 }, "the arc never dips below home toward the command bar")
        check(near(samples.map(\.dx).max() ?? 0, 0.2887 * reach, 1) && near(samples.map(\.dx).min() ?? 0, -0.2887 * reach, 1),
              "the arc sweeps across the page on both sides")
        let first = StartPageMarkSwoop.pose(at: 0, reach: reach), last = StartPageMarkSwoop.pose(at: StartPageMarkSwoop.duration, reach: reach)
        check(near(first.rotation, 0) && near(last.rotation, 2 * .pi), "the mark turns once on the way")
        check(first.scale == CGSize(width: 1, height: StartPageMarkSwoop.stretch), "the flying mark stretches slightly")
        let flight = StartPageMarkSwoop.flight(reach: reach)
        check(flight.times.first == 0 && flight.times.last == StartPageMarkSwoop.duration && flight.poses.count == flight.times.count,
              "the flight is sampled across its duration")
        let p = StartPageMarkSwoop.progress(at: 0.3), h = 1e-4
        let a = StartPageMarkSwoop.offset(progress: p - h, reach: reach), b = StartPageMarkSwoop.offset(progress: p + h, reach: reach)
        let tangent = StartPageMarkSwoop.tangent(progress: p, reach: reach)
        check(near((b.dx - a.dx) / (2 * h), tangent.dx, 1e-2) && near((b.dy - a.dy) / (2 * h), tangent.dy, 1e-2), "the ribbon follows the arc's direction")
    }

    static func ribbonGeometry() {
        let home = CGPoint(x: 400, y: 300), mark = CGSize(width: 65, height: 96), reach: CGFloat = 870
        func points(_ path: CGPath) -> [CGPoint] {
            var result: [CGPoint] = []
            path.applyWithBlock { element in
                if element.pointee.type == .moveToPoint || element.pointee.type == .addLineToPoint { result.append(element.pointee.points[0]) }
            }
            return result
        }
        let start = StartPageMarkSwoop.ribbon(at: 0, home: home, reach: reach, mark: mark, width: 26, stripes: 3)
        check(start.count == 3 && start.allSatisfy { points($0).allSatisfy { $0 == home } }, "no ribbon before the mark leaves")
        let time = 0.5
        let middle = StartPageMarkSwoop.ribbon(at: time, home: home, reach: reach, mark: mark, width: 26, stripes: 3)
        let counts = Set(([start, middle].flatMap { $0 }).map { points($0).count })
        check(counts == [2 * StartPageMarkSwoop.ribbonPoints], "every ribbon frame has the same shape for smooth animation")
        let pose = StartPageMarkSwoop.pose(at: time, reach: reach)
        let center = points(middle[1])
        let n = StartPageMarkSwoop.ribbonPoints
        let spine = (0..<n).map { CGPoint(x: (center[$0].x + center[2 * n - 1 - $0].x) / 2, y: (center[$0].y + center[2 * n - 1 - $0].y) / 2) }
        check(spine.allSatisfy { !StartPageMarkSwoop.covers($0, home: home, mark: mark, pose: pose) }, "the ribbon starts behind the mark")
        let widths = (0..<n).map { hypot(center[$0].x - center[2 * n - 1 - $0].x, center[$0].y - center[2 * n - 1 - $0].y) }
        check(widths.last! > widths.first! && widths.first! < 1, "the ribbon tapers toward its tail")
        let outer = points(middle[0]), inner = points(middle[2])
        check(hypot(outer[n - 1].x - inner[n - 1].x, outer[n - 1].y - inner[n - 1].y) > widths.last!,
              "the Space's colours run side by side along the ribbon")
        check(StartPageMarkSwoop.ribbon(at: time, home: home, reach: reach, mark: mark, width: 26, stripes: 9).count == StartPageMarkSwoop.maximumStripes,
              "the ribbon has at most three stripes")
        let end = StartPageMarkSwoop.ribbon(at: StartPageMarkSwoop.ribbonDuration, home: home, reach: reach, mark: mark, width: 26, stripes: 1)
        check(points(end[0]).allSatisfy { near($0, home) }, "the ribbon is gone once its tail lands")
    }

    static func chargeMaths() {
        check(StartPageMarkCharge.level(held: 0) == 0 && StartPageMarkCharge.level(held: StartPageMarkCharge.ramp) == 1
              && StartPageMarkCharge.level(held: 5) == 1, "the charge fills over the ramp and stays full")
        check(near(StartPageMarkGestureRecognizer.holdDelay + StartPageMarkCharge.ramp, 1.0), "the charge is full one second after the press, as in the mockup")
        let full = StartPageMarkCharge.holdPose(level: 1)
        check(full.origin == StartPageMarkPose.bottom && near(full.scale.height, 1 - StartPageMarkCharge.squish)
              && near(full.scale.width, 1 + StartPageMarkCharge.spread), "a full charge squishes the mark onto its base")
        check(StartPageMarkCharge.holdPose(level: 0) == StartPageMarkPose(origin: StartPageMarkPose.bottom), "charging starts from rest")
        check(StartPageMarkCharge.glow(0, scale: 1) == (0, 0), "no charge, no glow")
        let glow = StartPageMarkCharge.glow(1, scale: 1)
        check(near(glow.radius, 8.5) && near(CGFloat(glow.opacity), 0.9), "a full charge glows at the mockup's strength")
        let radius: CGFloat = 52
        let launch = StartPageMarkCharge.loopPose(at: 0, radius: radius)
        check(launch.offset == CGVector(dx: 0, dy: 0) && near(launch.scale.width, 0.9) && near(launch.scale.height, 1.16),
              "the release launches with a stretch")
        let top = StartPageMarkCharge.loopPose(at: StartPageMarkCharge.loopDuration / 2, radius: radius)
        check(near(top.offset.dy, -2 * radius) && near(top.offset.dx, 0, 1e-4) && near(top.rotation, -.pi), "the loop reaches its top upside down")
        let quarter = StartPageMarkCharge.loopPose(at: StartPageMarkCharge.loopDuration * 0.32, radius: radius)
        check(quarter.offset.dx > 0 && quarter.offset.dy < 0, "the loop climbs to the right first")
        let end = StartPageMarkCharge.loopPose(at: StartPageMarkCharge.loopDuration, radius: radius)
        check(near(end.offset.dx, 0, 1e-4) && near(end.offset.dy, 0, 1e-4) && near(end.rotation, -2 * .pi) && end.scale == CGSize(width: 1, height: 1),
              "the loop comes home after one full turn")
        check(StartPageMarkCharge.loopGlow(at: 0) == 1 && StartPageMarkCharge.loopGlow(at: StartPageMarkCharge.loopGlowFade) == 0, "the glow fades during the loop")
        check(near(StartPageMarkCharge.relaxGlow(at: 0, level: 1), 1) && StartPageMarkCharge.relaxGlow(at: StartPageMarkCharge.relaxGlowDuration, level: 1) == 0,
              "a relax fades the glow")
        check(StartPageMarkCharge.relaxPose(StartPageMarkCharge.relaxSquish(level: 1)).scale.height == 1 - StartPageMarkCharge.squish,
              "a relax starts from the held squish")
    }

    static func confettiMaths() {
        var generator = SeededGenerator(state: 7)
        let pieces = StartPageMarkConfetti.pieces(colors: 3, using: &generator)
        check(pieces.count == StartPageMarkConfetti.count, "the burst throws the mockup's 90 pieces")
        check(pieces.enumerated().allSatisfy { $0.element.color == $0.offset % 3 }, "the pieces take turns through the theme colours")
        check(pieces.allSatisfy {
            let speed = hypot($0.velocity.dx, $0.velocity.dy)
            let angle = atan2($0.velocity.dy, $0.velocity.dx) * 180 / .pi
            return speed >= 240 - 1e-6 && speed <= 600 + 1e-6 && angle >= -170 - 1e-6 && angle <= -10 + 1e-6
        }, "the burst fans upward")
        check(pieces.allSatisfy { StartPageMarkConfetti.lives.contains($0.life) && StartPageMarkConfetti.widths.contains($0.size.width) },
              "each piece has a bounded size and life")
        var none = SeededGenerator(state: 1)
        check(StartPageMarkConfetti.pieces(colors: 0, using: &none).isEmpty, "no colours, no confetti")
        let piece = StartPageMarkConfettiPiece(velocity: CGVector(dx: 200, dy: -500), rotation: 0, spin: 4, size: CGSize(width: 6, height: 4),
                                               life: 2, color: 0)
        var x: CGFloat = 0, y: CGFloat = 0, vx: CGFloat = 200, vy: CGFloat = -500, t = 0.0
        let h = 1e-4
        while t < 1 - h / 2 {
            vx *= CGFloat(pow(0.35, h)); vy = vy * CGFloat(pow(0.35, h)) + 900 * CGFloat(h)
            x += vx * CGFloat(h); y += vy * CGFloat(h); t += h
        }
        let closed = piece.offset(at: 1)
        check(near(closed.dx, x, 0.5) && near(closed.dy, y, 0.5), "confetti follows the mockup's drag and gravity")
        check(piece.offset(at: 2).dy > piece.offset(at: 0.5).dy, "confetti falls back down")
        check(piece.opacity(at: 1.3) == 1 && near(piece.opacity(at: 1.7), 0.5) && piece.opacity(at: 2) == 0, "confetti fades over its last 30%")
        check(piece.flutter(at: 0) == (4 + 0.6) / 4 && near(piece.flutter(at: .pi / 2 / 1.7 / 4), 0.6 / 4), "confetti flutters as it spins")
        let group = StartPageMarkConfetti.animation(for: piece, from: CGPoint(x: 10, y: 10))
        check(group.duration == 2 && group.animations?.count == 3, "each piece animates once for its life")
    }

    static func stageLayers() -> (body: CALayer, shimmer: CALayer, host: CALayer, page: CALayer) {
        let page = CALayer()
        page.isGeometryFlipped = true
        page.bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let body = CALayer()
        body.bounds = CGRect(x: 0, y: 0, width: 65, height: 96)
        body.anchorPoint = .zero
        body.position = CGPoint(x: 368, y: 200)
        page.addSublayer(body)
        let host = CALayer()
        host.frame = page.bounds
        page.addSublayer(host)
        return (body, CALayer(), host, page)
    }

    static func stop(_ layer: CALayer, _ key: String) {
        guard let animation = layer.animation(forKey: key) else { return check(false, "\(key) is running") }
        animation.delegate?.animationDidStop?(animation, finished: true)
    }

    static let colors = [CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1),
                         CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)]

    static func taffyAnimator() {
        let stage = CALayer()
        stage.bounds = CGRect(x: 0, y: 0, width: 65, height: 96)
        stage.anchorPoint = .zero
        let flipped = CALayer()
        flipped.isGeometryFlipped = true
        flipped.addSublayer(stage)
        let animator = TaffyAnimator()
        let pull = CGVector(dx: 12, dy: 30)
        animator.track(pull, stage: stage)
        check(near(stage.transform, TaffyStretch.transform(pull: pull, size: stage.bounds.size, anchor: .zero, yDown: true)),
              "tracking stretches in a flipped superlayer's downward space")
        let upright = CALayer()
        upright.addSublayer(stage)
        animator.track(pull, stage: stage)
        check(near(stage.transform, TaffyStretch.transform(pull: pull, size: stage.bounds.size, anchor: .zero, yDown: false)),
              "tracking mirrors the pull in an upward superlayer")
        let stretched = stage.transform
        animator.play(from: pull, stage: stage) {}
        check(near(stage.transform, CATransform3DIdentity), "the model is home while the spring plays")
        let values = ((stage.animation(forKey: TaffyAnimator.key) as? CAKeyframeAnimation)?.values as? [NSValue])?.map(\.caTransform3DValue) ?? []
        check(values.count == TaffySpring.spring.samples().count, "the spring is sampled")
        check(values.first.map { near($0, stretched) } == true && values.last.map { near($0, CATransform3DIdentity) } == true,
              "the spring runs from the released stretch to home")
        animator.track(pull, stage: stage)
        check(stage.animation(forKey: TaffyAnimator.key) == nil, "tracking takes over from a playing spring")
        animator.reset(stage: stage)
        check(stage.animation(forKey: TaffyAnimator.key) == nil && near(stage.transform, CATransform3DIdentity), "reset puts the mark home at once")
    }

    static func stageSwoop() {
        let layers = stageLayers()
        let stage = StartPageMarkStage(body: layers.body, shimmer: layers.shimmer)
        stage.colors = colors
        var landed = 0, finished = 0
        stage.swoop(in: layers.host, home: CGPoint(x: 400, y: 248), pageWidth: 800, landed: { landed += 1 }, completion: { finished += 1 })
        check(layers.host.sublayers?.count == 1, "the ribbon lives in one effects layer")
        let ribbon = layers.host.sublayers?.first
        check(ribbon?.sublayers?.count == 3 && ribbon?.sublayers?.allSatisfy { $0 is CAShapeLayer } == true, "the ribbon is one stripe per theme colour")
        check(ribbon?.isGeometryFlipped == !layers.host.contentsAreFlipped(), "the effects layer works top-down like the page")
        let flight = layers.body.animation(forKey: StartPageMarkStage.swoopKey) as? CAKeyframeAnimation
        check(flight?.duration == StartPageMarkSwoop.duration, "the mark flies for the mockup's 1.15 s")
        let frame = StartPageMarkFrame(layer: layers.body)
        let peak = (flight?.values as? [NSValue])?.map(\.caTransform3DValue).map { apply($0, CGPoint(x: 32.5, y: 48)).y }.min() ?? 0
        check(near(peak, 48 - 120, 1), "the flight carries the mark up the arc in the page's downward space")
        check(frame.yDown, "the page layer is top-down")
        check(landed == 0, "no landing tick before the mark lands")
        stop(layers.body, StartPageMarkStage.swoopKey)
        check(landed == 1 && layers.body.animation(forKey: StartPageMarkStage.landingKey) != nil, "the mark lands with a squash and a tick")
        stop(layers.body, StartPageMarkStage.landingKey)
        check(finished == 0, "the swoop waits for its ribbon")
        if let ribbon { stop(ribbon, StartPageMarkStage.lifetimeKey) }
        check(finished == 1 && (layers.host.sublayers ?? []).isEmpty && stage.effects == nil, "the ribbon is removed when the swoop ends")
        var plain = 0
        let bare = StartPageMarkStage(body: stageLayers().body, shimmer: CALayer())
        bare.swoop(in: nil, home: .zero, pageWidth: 800, landed: {}, completion: { plain += 1 })
        stop(bare.body, StartPageMarkStage.swoopKey)
        stop(bare.body, StartPageMarkStage.landingKey)
        check(plain == 1, "a swoop without an effects host still finishes")
    }

    static func stageCharge() {
        let layers = stageLayers()
        let stage = StartPageMarkStage(body: layers.body, shimmer: layers.shimmer)
        stage.colors = colors
        stage.charge(.motion)
        check(layers.body.animation(forKey: StartPageMarkStage.holdKey) != nil && layers.body.animation(forKey: StartPageMarkStage.buzzKey) != nil,
              "charging squishes the mark and buzzes once full")
        check(layers.body.animation(forKey: StartPageMarkStage.holdKey)?.isRemovedOnCompletion == false, "the squish holds while the press does")
        check(layers.body.animation(forKey: StartPageMarkStage.glowOpacityKey) != nil
              && layers.body.animation(forKey: StartPageMarkStage.glowColorKey)?.repeatCount == .infinity, "charging glows through the theme colours")
        var landed = 0, finished = 0
        stage.loop(in: layers.host, home: CGPoint(x: 400, y: 248), landed: { landed += 1 }, completion: { finished += 1 })
        check(layers.body.animation(forKey: StartPageMarkStage.holdKey) == nil && layers.body.animation(forKey: StartPageMarkStage.buzzKey) == nil,
              "the release lets go of the squish")
        check(layers.body.animation(forKey: StartPageMarkStage.loopKey)?.duration == StartPageMarkCharge.loopDuration, "the mark loops the loop")
        let confetti = layers.host.sublayers?.first
        check(layers.host.sublayers?.count == 1 && confetti?.sublayers?.count == StartPageMarkConfetti.count, "the confetti is a bounded set of layers")
        stop(layers.body, StartPageMarkStage.glowOpacityKey)
        check(layers.body.animation(forKey: StartPageMarkStage.glowColorKey) == nil, "the glow stops cycling once it fades")
        stop(layers.body, StartPageMarkStage.loopKey)
        check(landed == 1, "the loop lands with a tick")
        stop(layers.body, StartPageMarkStage.landingKey)
        check(finished == 0, "the loop waits for its confetti")
        if let confetti { stop(confetti, StartPageMarkStage.lifetimeKey) }
        check(finished == 1 && (layers.host.sublayers ?? []).isEmpty, "the confetti is removed when it settles")
        let quiet = StartPageMarkStage(body: stageLayers().body, shimmer: CALayer())
        quiet.colors = colors
        quiet.charge(.shimmer)
        check(quiet.body.animation(forKey: StartPageMarkStage.holdKey) == nil && quiet.body.animation(forKey: StartPageMarkStage.glowOpacityKey) != nil,
              "Reduce Motion charges with the glow and no squish")
        var relaxed = 0
        let relaxing = StartPageMarkStage(body: stageLayers().body, shimmer: CALayer())
        relaxing.colors = colors
        relaxing.charge(.motion)
        relaxing.relax(level: 0.5, style: .motion) { relaxed += 1 }
        check(relaxing.body.animation(forKey: StartPageMarkStage.relaxKey) != nil && relaxing.body.animation(forKey: StartPageMarkStage.holdKey) == nil,
              "an undercharged release springs back")
        stop(relaxing.body, StartPageMarkStage.relaxKey)
        check(relaxed == 0, "the relax waits for its glow")
        stop(relaxing.body, StartPageMarkStage.glowOpacityKey)
        check(relaxed == 1 && relaxing.body.animation(forKey: StartPageMarkStage.glowColorKey) == nil, "the relax ends once settled")
    }

    static func stagePauseCleanup() {
        let layers = stageLayers()
        let stage = StartPageMarkStage(body: layers.body, shimmer: layers.shimmer)
        stage.colors = colors
        var landed = 0, finished = 0
        stage.swoop(in: layers.host, home: CGPoint(x: 400, y: 248), pageWidth: 800, landed: { landed += 1 }, completion: { finished += 1 })
        let ribbon = layers.host.sublayers?.first
        let flight = layers.body.animation(forKey: StartPageMarkStage.swoopKey)
        stage.reset()
        check((layers.host.sublayers ?? []).isEmpty && stage.effects == nil, "pausing removes the ribbon")
        check(StartPageMarkStage.bodyKeys.allSatisfy { layers.body.animation(forKey: $0) == nil } && near(layers.body.transform, CATransform3DIdentity),
              "pausing sends the mark home at once")
        if let flight { flight.delegate?.animationDidStop?(flight, finished: false) }
        if let lifetime = ribbon?.animation(forKey: StartPageMarkStage.lifetimeKey) { lifetime.delegate?.animationDidStop?(lifetime, finished: false) }
        check(landed == 0 && finished == 0 && layers.body.animation(forKey: StartPageMarkStage.landingKey) == nil,
              "a paused swoop never lands or ticks afterwards")
        stage.charge(.motion)
        stage.loop(in: layers.host, home: .zero, landed: {}, completion: {})
        check(layers.host.sublayers?.count == 1, "one effects layer at a time")
        stage.reset()
        check((layers.host.sublayers ?? []).isEmpty, "pausing removes the confetti")
        check(layers.body.shadowOpacity == 0 && layers.body.animation(forKey: StartPageMarkStage.glowColorKey) == nil, "pausing puts out the glow")
        stage.colors = []
        stage.swoop(in: layers.host, home: .zero, pageWidth: 800, landed: {}, completion: {})
        check((layers.host.sublayers ?? []).isEmpty, "no colours, no ribbon layer")
        stage.reset()
    }

    static func shimmer() {
        let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), blue = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        let sequence = StartPageMarkShimmer.sequence([red, blue])
        check(sequence.map(\.alpha) == [0, StartPageMarkShimmer.peakAlpha, StartPageMarkShimmer.peakAlpha, 0],
              "the shimmer fades in through the theme colours and out again")
        check(StartPageMarkShimmer.sequence([]).isEmpty, "no colours, no shimmer")
        var finished = false
        let layer = CALayer()
        StartPageMarkShimmer.play(on: layer, colors: []) { finished = true }
        check(finished && layer.animation(forKey: StartPageMarkShimmer.key) == nil, "an empty shimmer finishes at once")
        StartPageMarkShimmer.play(on: layer, colors: sequence) {}
        let animation = layer.animation(forKey: StartPageMarkShimmer.key) as? CAKeyframeAnimation
        check(animation?.keyPath == "backgroundColor" && animation?.values?.count == 4, "the shimmer changes colour in place without moving the mark")
        check(layer.backgroundColor == nil, "the shimmer leaves no colour behind")
        StartPageMarkShimmer.reset(layer)
        check(layer.animation(forKey: StartPageMarkShimmer.key) == nil, "reset stops the shimmer")
    }

    static func fillAndTint() {
        for incognito in [false, true] {
            for colored in [false, true] {
                check(StartPageMarkFill(colorMark: true, themeHasColor: colored, incognito: incognito) == .art, "the colour mark is its own artwork")
            }
        }
        check(StartPageMarkFill(colorMark: false, themeHasColor: true, incognito: false) == .theme, "a coloured theme fills the mark")
        check(StartPageMarkFill(colorMark: false, themeHasColor: false, incognito: false) == .ink, "a colourless theme inks the mark")
        check(StartPageMarkFill(colorMark: false, themeHasColor: true, incognito: true) == .ink, "a private window inks the mark")
        check(StartPageMarkFill(colorMark: false, themeHasColor: false, pagingHasColor: (false, true), incognito: false) == .theme,
              "a swipe toward a coloured Space shows its gradient on the mark")
        check(StartPageMarkFill(colorMark: false, themeHasColor: true, pagingHasColor: (false, false), incognito: false) == .ink,
              "a swipe between colourless Spaces inks the mark")
        check(StartPageMarkFill(colorMark: false, themeHasColor: true, pagingHasColor: (true, true), incognito: true) == .ink,
              "a private window ignores swipes")
        let tint = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.25), label = CGColor(gray: 0.5, alpha: 1)
        func components(_ color: CGColor) -> [CGFloat] {
            color.converted(to: CGColorSpace(name: CGColorSpace.extendedSRGB)!, intent: .defaultIntent, options: nil)?.components ?? []
        }
        let gray = components(label)
        check(zip(components(StartPageMarkTint.blend(tint, label, progress: 0)), components(tint)).allSatisfy { near($0, $1, 1e-4) },
              "the tint starts at the outgoing Space")
        check(zip(components(StartPageMarkTint.blend(tint, label, progress: 1)), gray).allSatisfy { near($0, $1, 1e-4) },
              "the tint ends at the incoming Space")
        let half = components(StartPageMarkTint.blend(tint, label, progress: 0.5))
        check(near(half[3], 0.625, 1e-4) && near(half[0], gray[0] / 2, 1e-4), "the tint blends through the swipe")
        check(zip(components(StartPageMarkTint.blend(tint, label, progress: 3)), gray).allSatisfy { near($0, $1, 1e-4) },
              "an overshooting swipe holds the incoming tint")
    }
}
