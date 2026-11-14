import Foundation

final class Page: HistorySwipeEnvironment {
    var swipesBetweenPages = true
    var allowsHistorySwipe = true
    var back: Int
    var forward: Int

    init(back: Int = 3, forward: Int = 2) {
        self.back = back
        self.forward = forward
    }

    func historyEntries(toward direction: HistorySwipeDirection) -> Int {
        direction == .back ? back : forward
    }
}

final class Shell: HistorySwipeShell {
    var outputs: [HistorySwipeOutput] = []
    func historySwipe(_ output: HistorySwipeOutput) { outputs.append(output) }
}

struct Trace {
    var inputs: [HistorySwipeInput] = []
    var time = 100.0
    var natural = true
    var x = 0.5
    var y = 0.5

    var fingers: [HistorySwipePoint] {
        [HistorySwipePoint(x: x - 0.06, y: y), HistorySwipePoint(x: x + 0.06, y: y)]
    }

    mutating func land(_ x: Double, _ y: Double = 0.5) {
        self.x = x
        self.y = y
        inputs.append(.touches(.began, fingers, time: time))
    }

    mutating func move(_ x: Double, _ y: Double? = nil, after delay: Double = 0.008) {
        time += delay
        self.x = x
        if let y { self.y = y }
        inputs.append(.touches(.moved, fingers, time: time))
    }

    mutating func lift() {
        time += 0.008
        inputs.append(.touches(.ended, fingers, time: time))
    }

    mutating func scroll(_ phase: HistorySwipeEventPhase, dx: Double = 0, dy: Double = 0,
                         momentum: HistorySwipeEventPhase = .none) {
        inputs.append(.scroll(HistorySwipeScroll(phase: phase, momentumPhase: momentum, deltaX: dx, deltaY: dy,
                                                 directionInverted: natural)))
    }

    mutating func pageAnswers(consumed: Bool = false, propagatesX: Bool? = true) {
        inputs.append(.pageScroll(.began(synthetic: false, momentum: false)))
        if let propagatesX { inputs.append(.overscroll(propagatesX: propagatesX)) }
        inputs.append(.pageScroll(.updated(consumed: consumed)))
    }

    mutating func tracked(_ amount: Double, _ phase: HistorySwipeEventPhase, generation: Int = 1,
                          complete: Bool = false) {
        inputs.append(.trackedSwipe(HistorySwipeTrackedUpdate(generation: generation, amount: amount, phase: phase,
                                                              isComplete: complete)))
    }

    mutating func clock(_ time: Double) {
        inputs.append(.clock(time))
    }

    static func opening(from x: Double, toward sign: Double, natural: Bool = true, consumed: Bool = false,
                        propagatesX: Bool? = true) -> Trace {
        var trace = Trace(natural: natural)
        let content = natural ? sign : -sign
        trace.land(x)
        trace.scroll(.mayBegin)
        trace.move(x + sign * 0.002)
        trace.scroll(.began, dx: content * 2)
        trace.pageAnswers(consumed: consumed, propagatesX: propagatesX)
        trace.move(x + sign * 0.005)
        trace.scroll(.changed, dx: content * 3)
        return trace
    }

    static func wheel(natural: Bool = true, dx: Double, dy: Double = 0, consumed: Bool = false) -> Trace {
        var trace = Trace(natural: natural)
        trace.scroll(.mayBegin)
        trace.scroll(.began, dx: dx / 2, dy: dy / 2)
        trace.pageAnswers(consumed: consumed)
        trace.scroll(.changed, dx: dx, dy: dy)
        return trace
    }
}

struct Run {
    var recognizer: HistorySwipeRecognizer
    var steps: [HistorySwipeStep] = []
    var inputs: [HistorySwipeInput] = []

    init(_ trace: Trace, _ page: Page = Page(), parameters: HistorySwipeParameters = .chromium) {
        recognizer = HistorySwipeRecognizer(parameters: parameters)
        play(trace.inputs, page)
    }

    mutating func play(_ more: [HistorySwipeInput], _ page: Page) {
        for input in more {
            steps.append(recognizer.receive(input, in: page))
            inputs.append(input)
        }
    }

    var outputs: [HistorySwipeOutput] { steps.flatMap(\.outputs) }

    var gestures: [HistorySwipeOutput] {
        outputs.filter { if case .progress = $0 { false } else { true } }
    }

    var fractions: [Double] {
        outputs.compactMap { if case let .progress(value) = $0 { value.fraction } else { nil } }
    }

    var stretches: [Double] {
        outputs.compactMap { if case let .progress(value) = $0 { value.stretch } else { nil } }
    }

    var scrollConsumes: [Bool] {
        zip(inputs, steps).compactMap { input, step in
            if case .scroll = input { step.consumesEvent } else { nil }
        }
    }

    func steps(after count: Int) -> [HistorySwipeStep] { Array(steps.dropFirst(count)) }
}

@main struct HistorySwipeRecognizerTests {
    static var count = 0

    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("HistorySwipeRecognizer: \(message)") }
    }

    static func near(_ values: [Double], _ expected: [Double]) -> Bool {
        values.count == expected.count && zip(values, expected).allSatisfy { abs($0 - $1) < 1e-9 }
    }

    static func main() {
        chromiumValues()
        trackpadBack()
        trackpadForward()
        naturalScrollingDirections()
        unavailableHistoryAndSettings()
        magicMouse()
        magicMouseCancelsAndStaleTracking()
        pageConsumesFirstScroll()
        overscrollBehaviorNone()
        verticalCancel()
        reversalBelowCommitPoint()
        holdSelectionAndDetents()
        holdEdges()
        backgroundWindow()
        interruptions()
        injectedParameters()
        controller()
        print("HistorySwipeRecognizer: \(count) checks passed")
    }

    static func chromiumValues() {
        let p = HistorySwipeParameters.chromium
        check(p.commitDistance == 0.08 && p.consumeDistance == 0.01 && p.directionDistance == 0.001,
              "Chromium's commit, consume and direction distances")
        check(p.verticalCancelDistance == 0.24 && p.verticalDriftDistance == 0.01
              && p.verticalDominance == 2 && p.verticalExcess == 1.3, "Chromium's vertical cancel rules")
        check(p.trackedArmAmount == 0.3 && p.rubberBand == 0, "Chromium's tracked-swipe arm point and hard clamp")
        check(p.holdDelay == 0.5 && p.rowStep == 0.05, "the starting hold delay and row step")
    }

    static func trackpadBack() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        let opened = trace.inputs.count
        trace.move(0.315)
        trace.scroll(.changed, dx: 4)
        trace.move(0.35)
        trace.scroll(.changed, dx: 6)
        trace.move(0.40)
        trace.scroll(.changed, dx: 8)
        trace.move(0.41)
        trace.lift()
        trace.scroll(.ended)
        trace.scroll(.none, dx: 5, momentum: .began)
        trace.scroll(.none, dx: 4, momentum: .changed)
        trace.scroll(.none, momentum: .ended)
        let run = Run(trace)
        check(run.gestures == [.begin(.back), .armed(true), .commit(.adjacent(.back))],
              "a natural rightward two-finger swipe arms and commits Back")
        check(near(run.fractions, [0.1875, 0.625, 1]), "progress is finger travel over the commit distance, clamped")
        check(run.stretches.last == 1, "Chromium's progress stops at the commit point without a rubber band")
        check(run.scrollConsumes == [false, false, true, true, true, true, false, false, true, false],
              "the page keeps events until the swipe is possible, then momentum after the lift is swallowed")
        check(run.steps[opened].preloadsBack && run.steps.filter(\.preloadsBack).count == 1,
              "tracking a Back swipe hints a likely back navigation once")
        check(run.recognizer.state == .completed, "lifting armed completes the gesture")
    }

    static func trackpadForward() {
        var trace = Trace.opening(from: 0.60, toward: -1)
        trace.move(0.585)
        trace.scroll(.changed, dx: -4)
        trace.move(0.55)
        trace.move(0.50)
        trace.lift()
        let run = Run(trace)
        check(run.gestures == [.begin(.forward), .armed(true), .commit(.adjacent(.forward))],
              "a natural leftward two-finger swipe arms and commits Forward")
        check(near(run.fractions, [0.1875, 0.625, 1]), "Forward progress grows as the fingers travel left")
        check(!run.steps.contains(where: \.preloadsBack), "Forward never hints a back navigation")
    }

    static func naturalScrollingDirections() {
        var right = Trace.opening(from: 0.30, toward: 1, natural: false)
        right.move(0.40)
        right.lift()
        check(Run(right).gestures == [.begin(.forward), .armed(true), .commit(.adjacent(.forward))],
              "without natural scrolling a rightward swipe goes Forward")
        var left = Trace.opening(from: 0.60, toward: -1, natural: false)
        left.move(0.50)
        left.lift()
        check(Run(left).gestures == [.begin(.back), .armed(true), .commit(.adjacent(.back))],
              "without natural scrolling a leftward swipe goes Back")
        var still = Trace(natural: true)
        still.land(0.30)
        still.scroll(.began, dx: 1)
        still.pageAnswers()
        still.move(0.3005)
        still.scroll(.changed, dx: 1)
        check(Run(still).gestures.isEmpty, "a swipe needs Chromium's minimum horizontal travel to choose a direction")
    }

    static func unavailableHistoryAndSettings() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.40)
        trace.scroll(.changed, dx: 8)
        trace.lift()
        let noBack = Run(trace, Page(back: 0))
        check(noBack.outputs.isEmpty && !noBack.scrollConsumes.contains(true),
              "a page with nothing Back keeps every event")
        let off = Page()
        off.swipesBetweenPages = false
        let disabled = Run(trace, off)
        check(disabled.outputs.isEmpty && !disabled.scrollConsumes.contains(true),
              "the system swipe-between-pages setting turns the gesture off")
        let covered = Page()
        covered.allowsHistorySwipe = false
        check(Run(trace, covered).outputs.isEmpty, "a covered window never begins a swipe")
    }

    static func magicMouse() {
        var trace = Trace.wheel(dx: 4, dy: 1)
        trace.tracked(0, .began)
        trace.tracked(0.12, .changed)
        trace.tracked(0.36, .changed)
        trace.clock(500)
        trace.tracked(0.4, .ended)
        trace.tracked(0.7, .ended)
        trace.tracked(1, .ended, complete: true)
        trace.tracked(1, .ended)
        let run = Run(trace)
        let request = run.steps.compactMap(\.startsTracking)
        check(request == [HistorySwipeTrackingRequest(direction: .back, generation: 1)],
              "a Magic Mouse swipe asks AppKit to track it once, Back for natural rightward travel")
        check(run.scrollConsumes == [false, false, true], "the swipe takes the event that starts AppKit tracking")
        check(run.gestures == [.begin(.back), .armed(true), .commit(.adjacent(.back))],
              "AppKit's tracked progress arms and commits the adjacent page")
        check(near(run.fractions, [0.4, 1]), "tracked progress is the gesture amount over Chromium's 0.3")
        check(run.steps.contains { $0.clockDeadline != nil } == false, "a tracked swipe never schedules the list")
        check(!run.outputs.contains(.hold), "without finger positions there is no hold list")
        check(run.steps.dropLast().allSatisfy { !$0.stopsTracking } && run.steps.last?.stopsTracking == true,
              "AppKit's settle animation runs out, and a callback after completion stops")

        let forward = Run(Trace.wheel(dx: -4, dy: 1))
        check(forward.steps.compactMap(\.startsTracking).map(\.direction) == [.forward],
              "natural leftward Magic Mouse travel goes Forward")
        let vertical = Run(Trace.wheel(dx: 1, dy: 4))
        check(vertical.steps.allSatisfy { $0.startsTracking == nil && !$0.consumesEvent },
              "a mostly vertical Magic Mouse scroll stays with the page")
        let consumed = Run(Trace.wheel(dx: 4, consumed: true))
        check(consumed.steps.allSatisfy { $0.startsTracking == nil }, "a page that takes the scroll keeps the Magic Mouse")

        var repeated = Trace.wheel(dx: 4)
        repeated.scroll(.changed, dx: 5)
        repeated.scroll(.changed, dx: 6)
        repeated.tracked(0, .began)
        repeated.scroll(.changed, dx: 4)
        let once = Run(repeated)
        check(once.steps.compactMap(\.startsTracking).count == 1 && once.scrollConsumes.suffix(3) == [true, true, true],
              "later scroll events in the same gesture never ask AppKit to track again")

        var short = Trace.wheel(dx: 4)
        short.tracked(0, .began)
        short.tracked(0.1, .changed)
        short.tracked(0.12, .ended)
        check(Run(short).gestures == [.begin(.back), .commit(.adjacent(.back))],
              "AppKit's ended phase decides a tracked commit; the arm amount only moves the armed look")

        var next = Trace.wheel(dx: 4)
        next.tracked(0, .began)
        next.tracked(0.4, .ended, complete: true)
        next.scroll(.began, dx: 2)
        next.scroll(.changed, dx: 4)
        next.scroll(.changed, dx: 4)
        check(Run(next).steps.compactMap(\.startsTracking).count == 1,
              "a new Magic Mouse gesture waits for the page's own answer instead of reusing the last one")
    }

    static func magicMouseCancelsAndStaleTracking() {
        var released = Trace.wheel(dx: 4)
        released.tracked(0, .began)
        released.tracked(0.1, .changed)
        released.tracked(0.08, .cancelled)
        released.tracked(0.03, .cancelled)
        released.tracked(0, .cancelled, complete: true)
        let early = Run(released)
        check(early.gestures == [.begin(.back), .cancel], "releasing a Magic Mouse swipe early cancels")
        check(early.steps.allSatisfy { !$0.stopsTracking }, "AppKit's own cancel animation is not interrupted")

        var interrupted = Trace.wheel(dx: 4)
        interrupted.tracked(0, .began)
        interrupted.tracked(0.2, .changed)
        interrupted.scroll(.began, dx: 1)
        let late = interrupted.inputs.count
        interrupted.tracked(0.25, .changed)
        interrupted.pageAnswers()
        interrupted.scroll(.changed, dx: 3)
        interrupted.tracked(0.1, .changed, generation: 2)
        let stale = Run(interrupted)
        check(stale.gestures == [.begin(.back), .cancel, .begin(.back)],
              "a new gesture cancels the old tracked swipe and starts its own")
        check(stale.steps[late].stopsTracking && stale.steps[late].outputs.isEmpty, "a late callback from the old tracking stops it")
        check(stale.steps.compactMap(\.startsTracking).map(\.generation) == [1, 2], "each tracking gets a new generation")

        let page = Page()
        var covered = Run(Trace.wheel(dx: 4), page)
        covered.play([.trackedSwipe(HistorySwipeTrackedUpdate(generation: 1, amount: 0, phase: .began))], page)
        page.allowsHistorySwipe = false
        covered.play([.trackedSwipe(HistorySwipeTrackedUpdate(generation: 1, amount: 0.2, phase: .changed))], page)
        check(covered.gestures == [.begin(.back), .cancel] && covered.steps.last?.stopsTracking == true,
              "a sheet arriving mid-swipe cancels and stops AppKit tracking")
    }

    static func pageConsumesFirstScroll() {
        var trace = Trace.opening(from: 0.30, toward: 1, consumed: true)
        trace.move(0.35)
        trace.scroll(.changed, dx: 6)
        trace.move(0.42)
        trace.scroll(.changed, dx: 8)
        trace.lift()
        let run = Run(trace)
        check(run.outputs.isEmpty && !run.scrollConsumes.contains(true),
              "a carousel that takes the first scroll keeps the whole gesture")

        var late = Trace(natural: true)
        late.land(0.30)
        late.move(0.302)
        late.scroll(.began, dx: 2)
        late.move(0.305)
        late.scroll(.changed, dx: 3)
        late.pageAnswers()
        late.move(0.31)
        late.scroll(.changed, dx: 3)
        let waiting = Run(late)
        check(waiting.scrollConsumes == [false, false, true] && waiting.gestures == [.begin(.back)],
              "the swipe waits for the page's answer before it can begin")

        var synthetic = Trace(natural: true)
        synthetic.land(0.30)
        synthetic.move(0.302)
        synthetic.scroll(.began, dx: 2)
        synthetic.inputs += [.pageScroll(.began(synthetic: true, momentum: false)), .overscroll(propagatesX: true),
                             .pageScroll(.updated(consumed: false))]
        synthetic.move(0.305)
        synthetic.scroll(.changed, dx: 3)
        synthetic.inputs += [.pageScroll(.began(synthetic: false, momentum: true)), .pageScroll(.updated(consumed: false))]
        synthetic.move(0.31)
        synthetic.scroll(.changed, dx: 3)
        check(Run(synthetic).outputs.isEmpty, "synthetic and momentum scroll starts are not the page's answer")

        var stale = Trace.opening(from: 0.30, toward: 1)
        stale.lift()
        stale.land(0.30)
        stale.move(0.302)
        stale.scroll(.began, dx: 2)
        stale.move(0.31)
        stale.scroll(.changed, dx: 3)
        check(Run(stale).gestures == [.begin(.back), .cancel],
              "an earlier gesture's answer never lets the next one start before the page replies")
    }

    static func overscrollBehaviorNone() {
        var none = Trace.opening(from: 0.30, toward: 1, propagatesX: false)
        none.move(0.42)
        none.scroll(.changed, dx: 8)
        none.lift()
        let blocked = Run(none)
        check(blocked.outputs.isEmpty && !blocked.scrollConsumes.contains(true),
              "overscroll-behavior: none keeps the swipe off the page")
        var silent = Trace.opening(from: 0.30, toward: 1, propagatesX: nil)
        silent.move(0.42)
        silent.scroll(.changed, dx: 8)
        check(Run(silent).outputs.isEmpty, "a page that never overscrolls horizontally keeps the gesture")
    }

    static func verticalCancel() {
        var drift = Trace.opening(from: 0.30, toward: 1)
        drift.move(0.31, 0.53)
        drift.scroll(.changed, dx: 2, dy: 6)
        drift.move(0.40, 0.53)
        drift.scroll(.changed, dx: 8)
        drift.lift()
        let run = Run(drift)
        check(run.gestures == [.begin(.back), .cancel], "more vertical than horizontal travel cancels")
        check(run.scrollConsumes.suffix(2) == [false, false], "a cancelled swipe hands the events back to the page")

        var early = Trace(natural: true)
        early.land(0.30)
        early.move(0.302, 0.52)
        early.scroll(.began, dx: 2)
        early.pageAnswers()
        early.move(0.31, 0.52)
        early.scroll(.changed, dx: 3)
        check(Run(early).outputs.isEmpty, "a vertical start never shows a swipe")

        var long = Trace.opening(from: 0.30, toward: 1)
        long.move(0.65)
        long.move(0.65, 0.40)
        long.move(0.65, 0.25)
        let far = Run(long)
        check(far.gestures == [.begin(.back), .armed(true), .cancel],
              "Chromium's large vertical travel cancels even an armed swipe before the hold")
    }

    static func reversalBelowCommitPoint() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.315)
        trace.move(0.40)
        trace.move(0.36)
        trace.scroll(.changed, dx: -3)
        trace.lift()
        trace.scroll(.none, dx: -3, momentum: .changed)
        let run = Run(trace)
        check(run.gestures == [.begin(.back), .armed(true), .armed(false), .cancel],
              "backing off below the commit point disarms, and lifting there cancels")
        check(run.scrollConsumes.suffix(2) == [true, true], "a disarmed swipe still owns its events and momentum")
        check(run.recognizer.state == .completed, "the lift finishes the gesture without navigating")

        var again = Trace.opening(from: 0.30, toward: 1)
        again.move(0.40)
        again.move(0.36)
        again.move(0.42)
        again.lift()
        check(Run(again).gestures == [.begin(.back), .armed(true), .armed(false), .armed(true), .commit(.adjacent(.back))],
              "rearming after a reversal commits")
    }

    static func holdSelectionAndDetents() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.315)
        trace.move(0.40)
        let armedAt = trace.time
        let armedIndex = trace.inputs.count - 1
        trace.clock(armedAt + 0.49)
        trace.clock(armedAt + 0.5)
        trace.scroll(.changed, dx: 1)
        trace.move(0.40, 0.56)
        trace.move(0.40, 0.62)
        trace.move(0.40, 0.75)
        trace.move(0.40, 0.69)
        trace.move(0.40, 0.58)
        trace.move(0.40, 0.40)
        trace.lift()
        let run = Run(trace)
        check(run.steps[armedIndex].clockDeadline == armedAt + 0.5, "arming schedules the hold after the delay")
        check(run.steps[armedIndex + 1].outputs.isEmpty, "the list waits for the full delay")
        check(run.gestures == [.begin(.back), .armed(true), .hold, .selection(1),
                               .selection(2), .detent, .selection(3), .detent,
                               .selection(2), .detent, .selection(1), .detent, .selection(0), .detent, .cancel],
              "vertical travel steps one row at a time with a detent each, clamps at the ends, and lifting on the current page cancels")
        check(run.scrollConsumes.last == true, "the hold owns its events")

        var pick = Trace.opening(from: 0.30, toward: 1)
        pick.move(0.40)
        pick.clock(pick.time + 0.5)
        pick.move(0.40, 0.56)
        pick.lift()
        check(Run(pick).gestures == [.begin(.back), .armed(true), .hold, .selection(1), .selection(2), .detent,
                                     .commit(.entry(.back, distance: 2))],
              "lifting on a row commits that history entry")

        var forward = Trace.opening(from: 0.60, toward: -1)
        forward.move(0.50)
        forward.clock(forward.time + 0.5)
        forward.move(0.50, 0.66)
        forward.lift()
        check(Run(forward).gestures == [.begin(.forward), .armed(true), .hold, .selection(1), .selection(2), .detent,
                                        .commit(.entry(.forward, distance: 2))],
              "Forward holds too, and stops at the last Forward entry")

        var jump = Trace.opening(from: 0.30, toward: 1)
        jump.move(0.40)
        jump.clock(jump.time + 0.5)
        jump.move(0.40, 0.66)
        check(Run(jump, Page(back: 5)).gestures.suffix(6) == [.selection(2), .detent, .selection(3), .detent,
                                                              .selection(4), .detent],
              "a fast vertical sweep still steps and ticks every row")
    }

    static func holdEdges() {
        var dwell = Trace.opening(from: 0.30, toward: 1)
        dwell.move(0.40)
        dwell.move(0.41, after: 0.6)
        check(Run(dwell).gestures == [.begin(.back), .armed(true), .hold, .selection(1)],
              "a finger movement after the delay opens the list without waiting for the clock")

        var reset = Trace.opening(from: 0.30, toward: 1)
        reset.move(0.40)
        let armedAt = reset.time
        reset.move(0.36, after: 0.3)
        reset.move(0.40, after: 0.1)
        reset.clock(armedAt + 0.6)
        reset.clock(armedAt + 0.9)
        check(Run(reset).gestures == [.begin(.back), .armed(true), .armed(false), .armed(true), .hold, .selection(1)],
              "disarming restarts the dwell")

        var out = Trace.opening(from: 0.30, toward: 1)
        out.move(0.40)
        out.clock(out.time + 0.5)
        out.move(0.33)
        out.scroll(.changed, dx: -3)
        out.move(0.29)
        out.scroll(.changed, dx: -3)
        out.lift()
        let slid = Run(out)
        check(slid.gestures == [.begin(.back), .armed(true), .hold, .selection(1), .cancel],
              "sliding back out past the edge cancels the list, and moving inside it does not")
        check(slid.scrollConsumes.suffix(2) == [true, false], "the page gets its events back after sliding out")

        var lifted = Trace.opening(from: 0.30, toward: 1)
        lifted.move(0.40)
        lifted.time += 0.6
        lifted.lift()
        check(Run(lifted).gestures == [.begin(.back), .armed(true), .commit(.adjacent(.back))],
              "lifting before the list opens commits the adjacent page even after the delay")

        var tremor = Trace.opening(from: 0.30, toward: 1)
        tremor.move(0.39)
        let restAt = tremor.time
        for index in 0..<70 { tremor.move(0.39, index.isMultiple(of: 2) ? 0.501 : 0.5, after: 0.007) }
        tremor.clock(restAt + 0.5)
        check(Run(tremor).gestures == [.begin(.back), .armed(true), .hold, .selection(1)],
              "resting fingers that tremble while the list waits still open it")

        var slide = Trace.opening(from: 0.30, toward: 1)
        slide.move(0.39)
        slide.move(0.39, 0.6, after: 0.1)
        check(Run(slide).gestures == [.begin(.back), .armed(true), .cancel],
              "a real vertical slide while the list waits still cancels")
    }

    static func backgroundWindow() {
        let background = Page(back: 3, forward: 0)
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.40)
        trace.clock(trace.time + 0.5)
        trace.move(0.40, 0.56)
        trace.lift()
        check(Run(trace, background).gestures == [.begin(.back), .armed(true), .hold, .selection(1),
                                                  .selection(2), .detent, .commit(.entry(.back, distance: 2))],
              "a swipe and hold need nothing from the page beyond coverage and history")

        var untouched = Trace.wheel(dx: 4)
        untouched.tracked(0, .began)
        untouched.tracked(0.35, .changed)
        untouched.tracked(0.4, .ended)
        check(Run(untouched, background).gestures == [.begin(.back), .armed(true), .commit(.adjacent(.back))],
              "a background trackpad swipe that arrives without touches still goes Back through tracked progress")

        let sheet = Page()
        var covered = Run(Trace.opening(from: 0.30, toward: 1), sheet)
        sheet.allowsHistorySwipe = false
        var rest = Trace()
        rest.x = 0.30
        rest.move(0.40)
        rest.scroll(.changed, dx: 8)
        covered.play(rest.inputs, sheet)
        check(covered.gestures == [.begin(.back), .cancel] && covered.scrollConsumes.last == false,
              "covering the page cancels the swipe and hands its events back")
    }

    static func interruptions() {
        let page = Page()
        var lifecycle = Run(Trace.opening(from: 0.30, toward: 1), page)
        lifecycle.play([.cancel], page)
        var rest = Trace()
        rest.x = 0.30
        rest.move(0.40)
        rest.scroll(.changed, dx: 8)
        rest.lift()
        lifecycle.play(rest.inputs, page)
        check(lifecycle.gestures == [.begin(.back), .cancel] && lifecycle.scrollConsumes.last == false,
              "a navigation or page change cancels the swipe")

        var committed = Trace.opening(from: 0.30, toward: 1)
        committed.move(0.40)
        committed.lift()
        committed.inputs.append(.cancel)
        committed.scroll(.none, dx: 4, momentum: .changed)
        let after = Run(committed)
        check(after.gestures == [.begin(.back), .armed(true), .commit(.adjacent(.back))]
              && after.scrollConsumes.last == true, "the navigation a commit starts does not undo the finished swipe")

        var touch = Trace.opening(from: 0.30, toward: 1)
        touch.move(0.40)
        touch.land(0.5)
        check(Run(touch).gestures == [.begin(.back), .armed(true), .cancel], "a new touch cancels the live swipe")

        var scroll = Trace.opening(from: 0.30, toward: 1)
        scroll.move(0.35)
        scroll.scroll(.began, dx: 1)
        check(Run(scroll).gestures == [.begin(.back), .cancel], "a new scroll gesture cancels the live swipe")

        var vertical = Trace.opening(from: 0.30, toward: 1)
        vertical.scroll(.changed, dx: 3, dy: 1)
        check(Run(vertical).scrollConsumes.suffix(2) == [true, false],
              "while the swipe is only possible, events with vertical travel still reach the page")

        var cancelled = Trace.opening(from: 0.30, toward: 1)
        cancelled.move(0.40)
        cancelled.inputs.append(.touches(.cancelled, cancelled.fingers, time: cancelled.time))
        check(Run(cancelled).gestures == [.begin(.back), .armed(true), .cancel], "cancelled touches cancel the swipe")
    }

    static func injectedParameters() {
        var tuned = HistorySwipeParameters.chromium
        tuned.commitDistance = 0.1
        tuned.rubberBand = 0.5
        tuned.holdDelay = 1
        tuned.rowStep = 0.1
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.315)
        trace.move(0.39)
        trace.move(0.45)
        let armedAt = trace.time
        trace.move(0.60)
        trace.clock(armedAt + 0.5)
        trace.clock(armedAt + 1)
        trace.move(0.60, 0.56)
        trace.move(0.60, 0.61)
        let run = Run(trace, parameters: tuned)
        check(near(run.fractions, [0.15, 0.9, 1, 1]), "the commit distance is injectable")
        check(near(run.stretches, [0.15, 0.9, 1.25, 1.4]), "the rubber band resists travel past the commit point")
        check(run.gestures == [.begin(.back), .armed(true), .hold, .selection(1), .selection(2), .detent],
              "the hold delay and row step are injectable")

        var off = HistorySwipeParameters.chromium
        off.holdDelay = .infinity
        var never = Trace.opening(from: 0.30, toward: 1)
        never.move(0.40)
        never.clock(1e9)
        never.lift()
        check(Run(never, parameters: off).gestures == [.begin(.back), .armed(true), .commit(.adjacent(.back))],
              "an infinite hold delay turns the list off")
    }

    static func controller() {
        let page = Page()
        let shell = Shell()
        let controller = HistorySwipeController(shell: shell)
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.40)
        trace.lift()
        var direct = HistorySwipeRecognizer()
        var consumed: [Bool] = []
        for input in trace.inputs {
            let step = controller.receive(input, in: page)
            check(step == direct.receive(input, in: page), "the controller returns the recognizer's step")
            consumed.append(step.consumesEvent)
        }
        check(shell.outputs.filter { if case .progress = $0 { false } else { true } }
              == [.begin(.back), .armed(true), .commit(.adjacent(.back))], "the shell receives every output in order")
        check(consumed.contains(true) && controller.recognizer.state == .completed, "the forwarder gets consume answers")

        weak var released: Shell?
        var orphan: HistorySwipeController?
        do {
            let gone = Shell()
            released = gone
            orphan = HistorySwipeController(shell: gone)
        }
        check(released == nil, "the controller does not keep its shell alive")
        var later: [HistorySwipeStep] = []
        for input in trace.inputs { later.append(orphan!.receive(input, in: page)) }
        check(later.flatMap(\.outputs).contains(.commit(.adjacent(.back))), "a controller without a shell still recognizes")
    }
}
