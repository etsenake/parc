import Foundation

final class Page: HistorySwipeEnvironment {
    var swipesBetweenPages = true
    var allowsHistorySwipe = true
    var back: Int
    var forward: Int
    var peekFirstPage = false

    init(back: Int = 3, forward: Int = 2, peekFirstPage: Bool = false) {
        self.back = back
        self.forward = forward
        self.peekFirstPage = peekFirstPage
    }

    func historyEntries(toward direction: HistorySwipeDirection) -> Int {
        direction == .back ? back : forward
    }

    func dismisses(toward direction: HistorySwipeDirection) -> Bool {
        peekFirstPage && direction == .back
    }

    static var peek: Page { Page(back: 0, forward: 0, peekFirstPage: true) }
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

    mutating func rest(_ duration: Double = 0.2) {
        move(x + 0.0005, after: duration)
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
                        propagatesX: Bool? = true, y: Double = 0.5) -> Trace {
        var trace = Trace(natural: natural)
        let content = natural ? sign : -sign
        trace.land(x, y)
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

extension HistorySwipeStep {
    var gestures: [HistorySwipeOutput] {
        outputs.filter {
            switch $0 {
            case .progress, .rowRemainder: false
            default: true
            }
        }
    }
}

struct Run {
    var recognizer: HistorySwipeRecognizer
    var steps: [HistorySwipeStep] = []
    var inputs: [HistorySwipeInput] = []

    init(_ trace: Trace, _ page: Page = Page(), parameters: HistorySwipeParameters = .dia) {
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

    var gestures: [HistorySwipeOutput] { steps.flatMap(\.gestures) }

    var shape: [HistorySwipeOutput] {
        gestures.map { if case .release = $0 { .release(velocity: 0) } else { $0 } }
    }

    var releases: [Double] {
        outputs.compactMap { if case let .release(velocity) = $0 { velocity } else { nil } }
    }

    var remainders: [Double] {
        outputs.compactMap { if case let .rowRemainder(value) = $0 { value } else { nil } }
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

    var selections: [Int] {
        outputs.compactMap { if case let .selection(row) = $0 { row } else { nil } }
    }

    var detents: Int { outputs.filter { $0 == .detent }.count }

    mutating func tickUntilQuiet(_ page: Page, limit: Int = 200) -> [TimeInterval] {
        var deadlines: [TimeInterval] = []
        while deadlines.count < limit, let deadline = steps.last?.clockDeadline {
            deadlines.append(deadline)
            play([.clock(deadline)], page)
        }
        return deadlines
    }
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

    static func band(_ progress: Double, _ resistance: Double = 0.15) -> Double {
        let resisted = (progress - 1) * resistance
        return 1 + resisted / (resisted + 1)
    }

    static func main() {
        diaValues()
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
        holdWaitsForRest()
        holdOpensOnCurrentPage()
        listCollapsesBelowCommitPoint()
        holdEdges()
        longHistories()
        edgeBoundaryTremor()
        rowRemainders()
        openListMargins()
        backgroundWindow()
        interruptions()
        injectedParameters()
        controller()
        peekDismissalValues()
        peekDismissalTrackpad()
        peekDismissalSpringsBack()
        peekDismissalFlick()
        peekDismissalReversal()
        peekDismissalVerticalCancel()
        peekDismissalMagicMouse()
        peekDismissalNeedsFirstPage()
        peekDismissalKeepsPageRules()
        print("HistorySwipeRecognizer: \(count) checks passed")
    }

    static func diaValues() {
        let p = HistorySwipeParameters.dia
        check(p.commitDistance == 0.08 && p.consumeDistance == 0.01 && p.directionDistance == 0.001,
              "Chromium's commit, consume and direction distances, which Dia shares")
        check(p.verticalCancelDistance == 0.24 && p.verticalDriftDistance == 0.01
              && p.verticalDominance == 2 && p.verticalExcess == 1.3, "Chromium's vertical cancel rules")
        check(p.trackedArmAmount == 0.3, "Chromium's tracked-swipe arm point")
        check(p.rubberBand == 0.15 && p.holdDelay == 0.3 && p.rowStep == 0.08, "Dia's rubber band, hold delay and row step")
        check(p.edgeZone == 0.15 && p.edgeStepInterval == 0.1, "long histories keep stepping ten rows a second at the edges")
        check(p.edgeMargin == 0.03, "edge stepping needs a deliberate 3% of travel and stops 3% outside its zone")
        check(p.listCloseProgress == 0.85, "an open list closes only once the fingers slide clearly below the commit point")
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
        check(near(run.fractions, [0.1875, 0.625, 1, 1]), "progress is finger travel over the commit distance, clamped")
        check(near(run.stretches, [0.1875, 0.625, band(1.25), band(1.375)]),
              "travel past the commit point stretches with Dia's 0.15 rubber band")

        var far = Trace.opening(from: 0.30, toward: 1)
        for x in [0.46, 0.54, 0.62, 0.70] { far.move(x) }
        let stretched = Run(far).stretches.suffix(4)
        let gains = zip(stretched, stretched.dropFirst()).map { $1 - $0 }
        check(near(Array(stretched), [band(2), band(3), band(4), band(5)]) && gains == gains.sorted(by: >)
              && stretched.last! < 1.4, "each further reach past the commit point moves the indicator less")
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
        trace.clock(armedAt + 0.29)
        trace.clock(armedAt + 0.3)
        trace.scroll(.changed, dx: 1)
        trace.move(0.40, 0.59)
        trace.move(0.40, 0.67)
        trace.move(0.40, 0.84)
        trace.move(0.40, 0.75)
        trace.move(0.40, 0.66)
        trace.move(0.40, 0.40)
        trace.lift()
        let run = Run(trace)
        check(run.steps[armedIndex].clockDeadline == armedAt + 0.3, "arming schedules the hold after Dia's 0.3 s")
        check(run.steps[armedIndex + 1].outputs.isEmpty, "the list waits for the full delay")
        check(run.gestures == [.begin(.back), .armed(true), .hold, .selection(0),
                               .selection(1), .detent, .selection(2), .detent, .selection(3), .detent,
                               .selection(2), .detent, .selection(1), .detent, .selection(0), .detent, .cancel],
              "vertical travel steps one row at a time with a detent each, clamps at the ends, and lifting on the current page cancels")
        check(run.scrollConsumes.last == true, "the hold owns its events")

        var pick = Trace.opening(from: 0.30, toward: 1)
        pick.move(0.40)
        pick.clock(pick.time + 0.3)
        pick.move(0.40, 0.59)
        pick.lift()
        check(Run(pick).gestures == [.begin(.back), .armed(true), .hold, .selection(0), .selection(1), .detent,
                                     .commit(.entry(.back, distance: 1))],
              "lifting on a row commits that history entry")

        var forward = Trace.opening(from: 0.60, toward: -1)
        forward.move(0.50)
        forward.clock(forward.time + 0.3)
        forward.move(0.50, 0.41)
        forward.move(0.50, 0.25)
        forward.lift()
        check(Run(forward).gestures == [.begin(.forward), .armed(true), .hold, .selection(0), .selection(1), .detent,
                                        .selection(2), .detent, .commit(.entry(.forward, distance: 2))],
              "Forward holds too, steps as the fingers move down its top-to-bottom list, and stops at the last entry")

        var upward = Trace.opening(from: 0.60, toward: -1)
        upward.move(0.50)
        upward.clock(upward.time + 0.3)
        upward.move(0.50, 0.41)
        upward.move(0.50, 0.52)
        upward.move(0.50, 0.70)
        upward.lift()
        check(Run(upward).gestures == [.begin(.forward), .armed(true), .hold, .selection(0), .selection(1), .detent,
                                       .selection(0), .detent, .cancel],
              "moving up a Forward list heads back to the current page at its top, stops there, and lifting there cancels")

        var down = Trace.opening(from: 0.30, toward: 1)
        down.move(0.40)
        down.clock(down.time + 0.3)
        down.move(0.40, 0.59)
        down.move(0.40, 0.48)
        down.move(0.40, 0.30)
        down.lift()
        check(Run(down).gestures == [.begin(.back), .armed(true), .hold, .selection(0), .selection(1), .detent,
                                     .selection(0), .detent, .cancel],
              "moving down a Back list heads back to the current page at its bottom, stops there, and lifting there cancels")

        var short = Trace.opening(from: 0.30, toward: 1)
        short.move(0.40)
        short.clock(short.time + 0.3)
        short.move(0.40, 0.575)
        check(Run(short).gestures.suffix(1) == [.selection(0)], "travel short of 8% of the trackpad keeps the row")

        var jump = Trace.opening(from: 0.30, toward: 1)
        jump.move(0.40)
        jump.clock(jump.time + 0.3)
        jump.move(0.40, 0.75)
        check(Run(jump, Page(back: 5)).gestures.suffix(6) == [.selection(1), .detent, .selection(2), .detent,
                                                              .selection(3), .detent],
              "a fast vertical sweep still steps and ticks every row")
    }

    static func holdWaitsForRest() {
        let page = Page()
        var sliding = Trace.opening(from: 0.30, toward: 1)
        sliding.move(0.40)
        let armedAt = sliding.time
        let armedIndex = sliding.inputs.count - 1
        for x in [0.41, 0.42, 0.43, 0.44, 0.45] { sliding.move(x, after: 0.1) }
        let restAt = sliding.time
        var run = Run(sliding, page)
        check(!run.outputs.contains(.hold) && run.recognizer.state == .armed,
              "fingers still moving past the commit point keep the list closed though 0.5 s has passed since arming")
        check(run.steps[armedIndex].clockDeadline == armedAt + 0.3
              && run.steps[(armedIndex + 1)...(armedIndex + 2)].allSatisfy { $0.clockDeadline == armedAt + 0.3 },
              "movements before the first wake keep its deadline, so the clock isn't rescheduled on every movement")
        let wakes = run.tickUntilQuiet(page)
        check(abs(wakes.last! - (restAt + 0.3)) < 1e-9 && run.steps.last?.outputs == [.hold, .selection(0)],
              "the list opens 0.3 s after the last movement, once the fingers rest past the commit point")
        check(run.steps.suffix(wakes.count).dropLast().allSatisfy(\.outputs.isEmpty) && wakes == wakes.sorted(),
              "earlier wakes only reschedule the hold")

        var settled = Trace.opening(from: 0.30, toward: 1)
        settled.move(0.40)
        settled.move(0.44, after: 0.2)
        let stillAt = settled.time
        settled.clock(stillAt + 0.29)
        settled.clock(stillAt + 0.3)
        let rested = Run(settled, page)
        check(rested.steps.dropLast().allSatisfy { !$0.outputs.contains(.hold) } && rested.steps.last?.outputs == [.hold, .selection(0)],
              "a movement 0.2 s after arming pushes the list to 0.3 s after that movement")

        var held = Trace.opening(from: 0.30, toward: 1)
        held.move(0.40)
        held.clock(held.time + 0.3)
        held.move(0.42, 0.5, after: 0.05)
        held.move(0.44, 0.5, after: 0.05)
        check(Run(held, page).gestures == [.begin(.back), .armed(true), .hold, .selection(0)],
              "once the list is open, moving past the commit point doesn't close or reopen it")
    }

    static func holdOpensOnCurrentPage() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.40)
        trace.clock(trace.time + 0.3)
        let opened = Run(trace)
        check(opened.gestures == [.begin(.back), .armed(true), .hold, .selection(0)] && opened.recognizer.selection == 0,
              "the list opens with the current page selected")
        trace.lift()
        let lifted = Run(trace)
        check(lifted.gestures.last == .cancel && !lifted.gestures.contains { if case .commit = $0 { true } else { false } },
              "lifting as soon as the list opens navigates nowhere")

        var forward = Trace.opening(from: 0.60, toward: -1)
        forward.move(0.50)
        forward.clock(forward.time + 0.3)
        forward.lift()
        check(Run(forward).gestures == [.begin(.forward), .armed(true), .hold, .selection(0), .cancel],
              "a Forward list opens on the current page too")

        var older = Trace.opening(from: 0.30, toward: 1)
        older.move(0.40)
        older.clock(older.time + 0.3)
        older.move(0.40, 0.40)
        older.move(0.40, 0.49)
        older.lift()
        check(Run(older).gestures == [.begin(.back), .armed(true), .hold, .selection(0), .selection(1), .detent,
                                      .commit(.entry(.back, distance: 1))],
              "moving down a Back list stays on the current page; moving up reaches the previous page")
    }

    static func listCollapsesBelowCommitPoint() {
        let page = Page()
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.40)
        trace.clock(trace.time + 0.3)
        trace.move(0.40, 0.59)
        trace.move(0.40, 0.67)
        trace.move(0.36, 0.67)
        let belowIndex = trace.inputs.count - 1
        trace.scroll(.changed, dx: -3)
        let collapsed = Run(trace, page)
        check(collapsed.gestures == [.begin(.back), .armed(true), .hold, .selection(0), .selection(1), .detent,
                                     .selection(2), .detent, .armed(false)]
              && collapsed.steps[belowIndex].outputs.first.map { if case .progress = $0 { true } else { false } } == true,
              "sliding below the commit point disarms and closes the list, and the swipe carries on")
        check(collapsed.recognizer.state == .tracking && collapsed.recognizer.selection == nil
              && collapsed.steps.last?.clockDeadline == nil && collapsed.scrollConsumes.last == true,
              "the collapsed swipe keeps its events, drops the selection and asks for no tick")

        var lifted = trace
        lifted.lift()
        check(Run(lifted, page).gestures.last == .cancel, "lifting below the commit point after the list closed cancels")

        var vertical = trace
        vertical.move(0.365, 0.69)
        vertical.move(0.37, 0.67)
        check(Run(vertical, page).gestures.last == .armed(false),
              "vertical travel spent choosing rows doesn't count toward the vertical cancel afterwards")

        var reopened = trace
        reopened.move(0.41, 0.67)
        let rearmedAt = reopened.time
        reopened.move(0.42, 0.67, after: 0.1)
        let restAt = reopened.time
        var again = Run(reopened, page)
        check(again.gestures.suffix(2) == [.armed(false), .armed(true)] && !again.steps.suffix(2).contains { $0.outputs.contains(.hold) },
              "sliding back past the commit point rearms without reopening the list at once")
        check(again.steps.last?.clockDeadline == rearmedAt + 0.3, "rearming schedules a new hold")
        let wakes = again.tickUntilQuiet(page)
        check(abs(wakes.last! - (restAt + 0.3)) < 1e-9 && again.steps.last?.outputs == [.hold, .selection(0)],
              "resting another 0.3 s reopens the list on the current page")
        var pick = Trace()
        pick.x = 0.42; pick.y = 0.67; pick.time = restAt + 0.3
        pick.move(0.42, 0.76)
        pick.lift()
        again.play(pick.inputs, page)
        check(again.gestures.suffix(3) == [.selection(1), .detent, .commit(.entry(.back, distance: 1))],
              "the reopened list steps from the current page again")

        var commit = trace
        commit.move(0.42, 0.67)
        commit.lift()
        check(Run(commit, page).gestures.suffix(2) == [.armed(true), .commit(.adjacent(.back))],
              "lifting after rearming, before the list reopens, goes to the adjacent page")
    }

    static func holdEdges() {
        var dwell = Trace.opening(from: 0.30, toward: 1)
        dwell.move(0.40)
        dwell.move(0.41, after: 0.6)
        check(Run(dwell).gestures == [.begin(.back), .armed(true), .hold, .selection(0)],
              "fingers that already rested for the delay open the list on their next movement without waiting for the clock")

        var reset = Trace.opening(from: 0.30, toward: 1)
        reset.move(0.40)
        let armedAt = reset.time
        reset.move(0.36, after: 0.2)
        reset.move(0.40, after: 0.1)
        reset.clock(armedAt + 0.45)
        reset.clock(armedAt + 0.65)
        let restarted = Run(reset)
        check(restarted.gestures == [.begin(.back), .armed(true), .armed(false), .armed(true), .hold, .selection(0)]
              && restarted.steps.last?.outputs == [.hold, .selection(0)], "disarming restarts the dwell")

        var out = Trace.opening(from: 0.30, toward: 1)
        out.move(0.40)
        out.clock(out.time + 0.3)
        out.move(0.33)
        out.scroll(.changed, dx: -3)
        out.move(0.29)
        out.scroll(.changed, dx: -3)
        out.lift()
        let slid = Run(out)
        check(slid.gestures == [.begin(.back), .armed(true), .hold, .selection(0), .armed(false), .cancel],
              "sliding back below the commit point closes the list, and sliding on past the start cancels")
        check(slid.scrollConsumes.suffix(2) == [true, false], "the page gets its events back after sliding out")

        var jump = Trace.opening(from: 0.30, toward: 1)
        jump.move(0.40)
        jump.clock(jump.time + 0.3)
        jump.move(0.29)
        check(Run(jump).gestures == [.begin(.back), .armed(true), .hold, .selection(0), .cancel],
              "a single slide from the list past the start cancels")

        var lifted = Trace.opening(from: 0.30, toward: 1)
        lifted.move(0.40)
        lifted.time += 0.6
        lifted.lift()
        check(Run(lifted).gestures == [.begin(.back), .armed(true), .commit(.adjacent(.back))],
              "a lift never opens the list itself, so without it the swipe commits the adjacent page")

        var tremor = Trace.opening(from: 0.30, toward: 1)
        tremor.move(0.39)
        let restAt = tremor.time
        for index in 0..<70 { tremor.move(0.39, index.isMultiple(of: 2) ? 0.501 : 0.5, after: 0.007) }
        let stillAt = tremor.time
        tremor.clock(restAt + 0.5)
        let trembling = Run(tremor)
        check(trembling.gestures == [.begin(.back), .armed(true)] && trembling.recognizer.state == .armed,
              "resting fingers that tremble while the list waits never cancel, and each tremor restarts the wait")
        tremor.clock(stillAt + 0.3)
        check(Run(tremor).gestures == [.begin(.back), .armed(true), .hold, .selection(0)],
              "the list opens 0.3 s after the trembling stops")

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
        trace.clock(trace.time + 0.3)
        trace.move(0.40, 0.59)
        trace.lift()
        check(Run(trace, background).gestures == [.begin(.back), .armed(true), .hold, .selection(0),
                                                  .selection(1), .detent, .commit(.entry(.back, distance: 1))],
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
        var tuned = HistorySwipeParameters.dia
        tuned.commitDistance = 0.1
        tuned.rubberBand = 0.5
        tuned.holdDelay = 1
        tuned.rowStep = 0.1
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.315)
        trace.move(0.39)
        trace.move(0.45)
        trace.move(0.60)
        let restAt = trace.time
        trace.clock(restAt + 0.5)
        trace.clock(restAt + 1)
        trace.time = restAt + 1
        trace.move(0.60, 0.56)
        trace.move(0.60, 0.61)
        let run = Run(trace, parameters: tuned)
        check(near(run.fractions, [0.15, 0.9, 1, 1]), "the commit distance is injectable")
        check(near(run.stretches, [0.15, 0.9, 1.2, 1.5]), "the rubber band's resistance is injectable")
        check(run.gestures == [.begin(.back), .armed(true), .hold, .selection(0), .selection(1), .detent],
              "the hold delay and row step are injectable")

        var off = HistorySwipeParameters.dia
        off.holdDelay = .infinity
        var never = Trace.opening(from: 0.30, toward: 1)
        never.move(0.40)
        never.clock(1e9)
        never.lift()
        check(Run(never, parameters: off).gestures == [.begin(.back), .armed(true), .commit(.adjacent(.back))],
              "an infinite hold delay turns the list off")

        var still = HistorySwipeParameters.dia
        still.edgeZone = 0
        var edge = Trace.opening(from: 0.30, toward: 1)
        edge.move(0.40)
        edge.clock(edge.time + 0.3)
        edge.move(0.40, 0.95)
        let page = Page(back: 20)
        var fixed = Run(edge, page, parameters: still)
        check(fixed.tickUntilQuiet(page).isEmpty && fixed.selections == [0, 1, 2, 3, 4, 5],
              "an empty edge zone leaves long histories to finger travel alone")
    }

    static func longHistories() {
        let page = Page(back: 50)
        var climb = Trace.opening(from: 0.30, toward: 1)
        climb.move(0.40)
        climb.clock(climb.time + 0.3)
        climb.move(0.40, 0.70)
        climb.move(0.40, 0.88)
        let entered = climb.time
        var run = Run(climb, page)
        check(run.selections == [0, 1, 2, 3, 4] && run.steps.last?.clockDeadline == entered + 0.1,
              "fingers that reach the top edge step by travel, then ask for a clock tick")
        let deadlines = run.tickUntilQuiet(page)
        check(run.selections == Array(0...50) && run.detents == 50,
              "resting at the top edge reaches all 50 Back entries, one selection and detent per row")
        check(deadlines.count == 46 && zip(deadlines, deadlines.dropFirst()).allSatisfy { abs($1 - $0 - 0.1) < 1e-9 },
              "the edge steps one row every tenth of a second")
        check(run.steps.last?.clockDeadline == nil, "the ticks stop at the oldest entry")
        var lift = Trace()
        lift.x = 0.40; lift.y = 0.88; lift.time = deadlines.last ?? 0
        lift.lift()
        run.play(lift.inputs, page)
        check(run.gestures.last == .commit(.entry(.back, distance: 50)), "lifting there opens the oldest entry")

        var back = Trace.opening(from: 0.30, toward: 1)
        back.move(0.40)
        back.clock(back.time + 0.3)
        back.move(0.40, 0.88)
        var down = Run(back, page)
        let first = down.steps.last?.clockDeadline ?? 0
        down.play([.clock(first), .clock(first + 0.1), .clock(first + 0.2)], page)
        let high = down.selections.last ?? 0
        var leave = Trace()
        leave.x = 0.40; leave.y = 0.88; leave.time = first + 0.25
        leave.move(0.40, 0.72)
        down.play(leave.inputs, page)
        let settled = down.selections.last ?? 0
        check(high == 7 && settled == 5 && down.steps.last?.clockDeadline == nil,
              "leaving the edge stops the ticks and travel steps back from where the edge left off")
        down.play([.clock(first + 0.4)], page)
        check(down.steps.last?.outputs.isEmpty == true, "a stale tick after leaving the edge changes nothing")
        var bottom = Trace()
        bottom.x = 0.40; bottom.y = 0.72; bottom.time = first + 0.5
        bottom.move(0.40, 0.12)
        down.play(bottom.inputs, page)
        check(down.selections.last == 0, "travel alone can come back to the current page")
        check(down.steps.last?.clockDeadline == nil, "at the current page the bottom edge has nowhere left to go")

        var homeward = Trace.opening(from: 0.30, toward: 1)
        homeward.move(0.40)
        homeward.clock(homeward.time + 0.3)
        homeward.move(0.40, 0.88)
        var home = Run(homeward, page)
        _ = home.tickUntilQuiet(page, limit: 30)
        let far = home.selections.last ?? 0
        var sink = Trace()
        sink.x = 0.40; sink.y = 0.88; sink.time = (home.steps.last?.clockDeadline ?? 0) - 0.05
        sink.move(0.40, 0.14)
        home.play(sink.inputs, page)
        let afterTravel = home.selections.last ?? 0
        _ = home.tickUntilQuiet(page)
        check(far == 34 && afterTravel == 25 && home.selections.last == 0,
              "resting at the bottom edge steps a long Back list all the way back to the current page")

        let ahead = Page(back: 0, forward: 30)
        var forward = Trace.opening(from: 0.60, toward: -1)
        forward.move(0.50)
        forward.clock(forward.time + 0.3)
        forward.move(0.50, 0.10)
        var newer = Run(forward, ahead)
        _ = newer.tickUntilQuiet(ahead)
        check(newer.selections == Array(0...30) && newer.gestures.contains(.begin(.forward)),
              "a long Forward list keeps stepping at the bottom edge")

        var high0 = Trace(natural: true)
        high0.land(0.30, 0.9)
        high0.scroll(.mayBegin)
        high0.move(0.302)
        high0.scroll(.began, dx: 2)
        high0.pageAnswers()
        high0.move(0.305)
        high0.scroll(.changed, dx: 3)
        high0.move(0.40)
        high0.clock(high0.time + 0.3)
        high0.move(0.40, 0.92)
        var parked = Run(high0, page)
        check(parked.gestures == [.begin(.back), .armed(true), .hold, .selection(0)] && parked.steps.last?.clockDeadline == nil,
              "a list that opens with the fingers already at the edge waits instead of scrolling by itself")
        var again = Trace()
        again.x = 0.40; again.y = 0.92; again.time = high0.time
        again.move(0.40, 0.80)
        again.move(0.40, 0.87)
        parked.play(again.inputs, page)
        let rearmed = parked.steps.last?.clockDeadline
        _ = parked.tickUntilQuiet(page, limit: 3)
        check(rearmed != nil && parked.selections == [0, 1, 2, 3],
              "leaving the edge and coming back starts the steps")

        var late = Trace.opening(from: 0.30, toward: 1)
        late.move(0.40)
        late.clock(late.time + 0.3)
        late.move(0.40, 0.88)
        var lagging = Run(late, page)
        let due = lagging.steps.last?.clockDeadline ?? 0
        lagging.play([.clock(due + 1)], page)
        check(lagging.steps.last?.gestures == [.selection(5), .detent]
              && abs((lagging.steps.last?.clockDeadline ?? 0) - (due + 1.1)) < 1e-9,
              "a late tick steps a single row instead of jumping")

        var lifted = Trace.opening(from: 0.30, toward: 1)
        lifted.move(0.40)
        lifted.clock(lifted.time + 0.3)
        lifted.move(0.40, 0.88)
        let pending = lifted.time + 0.1
        lifted.lift()
        lifted.clock(pending)
        let gone = Run(lifted, page)
        check(gone.gestures.last == .commit(.entry(.back, distance: 4)) && gone.steps.last?.outputs.isEmpty == true,
              "lifting ends the edge steps")
        check(gone.steps.suffix(2).allSatisfy { $0.clockDeadline == nil }, "a finished swipe asks for no more ticks")
    }

    static func edgeBoundaryTremor() {
        let page = Page(back: 50)
        var inside = Trace.opening(from: 0.30, toward: 1, y: 0.851)
        inside.move(0.40)
        inside.clock(inside.time + 0.3)
        for y in [0.849, 0.851, 0.849, 0.852, 0.8505] { inside.move(0.40, y, after: 0.03) }
        var parkedInside = Run(inside, page)
        check(parkedInside.tickUntilQuiet(page).isEmpty && parkedInside.selections == [0],
              "a list that opens just inside the top zone ignores tremor across the zone's edge")
        var liftInside = Trace()
        liftInside.x = 0.40; liftInside.y = 0.8505; liftInside.time = inside.time + 1
        liftInside.lift()
        parkedInside.play(liftInside.inputs, page)
        check(parkedInside.gestures.last == .cancel, "so lifting there still goes nowhere")

        var outside = Trace.opening(from: 0.30, toward: 1, y: 0.849)
        outside.move(0.40)
        outside.clock(outside.time + 0.3)
        for y in [0.851, 0.849, 0.852, 0.8515] { outside.move(0.40, y, after: 0.03) }
        var parkedOutside = Run(outside, page)
        check(parkedOutside.tickUntilQuiet(page).isEmpty && parkedOutside.selections == [0],
              "a list that opens just outside the top zone ignores tremor into it")

        let ahead = Page(back: 0, forward: 30)
        var low = Trace.opening(from: 0.60, toward: -1, y: 0.151)
        low.move(0.50)
        low.clock(low.time + 0.3)
        for y in [0.149, 0.151, 0.148, 0.1495] { low.move(0.50, y, after: 0.03) }
        var parkedLow = Run(low, ahead)
        check(parkedLow.tickUntilQuiet(ahead).isEmpty && parkedLow.selections == [0],
              "a Forward list that opens just above the bottom zone ignores tremor into it")

        var push = Trace.opening(from: 0.30, toward: 1, y: 0.84)
        push.move(0.40)
        push.clock(push.time + 0.3)
        push.move(0.40, 0.88)
        var pushed = Run(push, page)
        check(pushed.steps.last?.clockDeadline != nil && !pushed.tickUntilQuiet(page, limit: 3).isEmpty
              && pushed.selections == [0, 1, 2, 3],
              "a deliberate push toward the edge starts the steps even from a list that opened near it")

        var engaged = Trace.opening(from: 0.30, toward: 1)
        engaged.move(0.40)
        engaged.clock(engaged.time + 0.3)
        engaged.move(0.40, 0.86)
        var stepping = Run(engaged, page)
        _ = stepping.tickUntilQuiet(page, limit: 2)
        var hand = Trace()
        hand.x = 0.40; hand.y = 0.86; hand.time = stepping.steps.last?.clockDeadline ?? 0
        var stillStepping = true
        for y in [0.849, 0.84, 0.851, 0.83] {
            hand.move(0.40, y, after: 0.001)
            stepping.play(Array(hand.inputs.suffix(1)), page)
            stillStepping = stillStepping && stepping.steps.last?.clockDeadline != nil
        }
        let before = stepping.selections.count
        _ = stepping.tickUntilQuiet(page, limit: 2)
        check(stillStepping && stepping.selections.count == before + 2,
              "once stepping, tremor back across the zone's edge doesn't stop it")
        hand.move(0.40, 0.81)
        stepping.play(Array(hand.inputs.suffix(1)), page)
        check(stepping.steps.last?.clockDeadline == nil, "moving 3% out of the zone stops it")
    }

    static func rowRemainders() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.40)
        trace.clock(trace.time + 0.3)
        let opened = trace.inputs.count
        trace.move(0.40, 0.54)
        trace.move(0.40, 0.60)
        let stepped = trace.inputs.count - 1
        trace.move(0.40, 0.46)
        trace.move(0.40, 0.40)
        let run = Run(trace)
        check(!run.steps.prefix(opened).contains { $0.outputs.contains { if case .rowRemainder = $0 { true } else { false } } },
              "nothing reports a remainder before the list opens")
        check(near(run.remainders, [0.5, 0.25, 0]),
              "between rows the recognizer reports how far the fingers are toward the next row, and nothing past the current page")
        let outputs = run.steps[stepped].outputs
        check(outputs.count == 3 && outputs[0] == .selection(1) && outputs[1] == .detent
              && { if case .rowRemainder = outputs[2] { true } else { false } }(),
              "a row step reports its selection first, then the remainder past it")

        var forward = Trace.opening(from: 0.60, toward: -1)
        forward.move(0.50)
        forward.clock(forward.time + 0.3)
        forward.move(0.50, 0.46)
        check(near(Run(forward).remainders, [0.5]), "a Forward list leans toward newer pages as the fingers move down")

        let page = Page(back: 50)
        var edge = Trace.opening(from: 0.30, toward: 1)
        edge.move(0.40)
        edge.clock(edge.time + 0.3)
        edge.move(0.40, 0.88)
        var climbing = Run(edge, page)
        let leaning = climbing.remainders.last ?? 0
        _ = climbing.tickUntilQuiet(page, limit: 1)
        check(abs(leaning - 0.75) < 1e-9 && climbing.remainders.last == 0, "an edge step lands squarely on its row")

        var collapse = Trace.opening(from: 0.30, toward: 1)
        collapse.move(0.40)
        collapse.clock(collapse.time + 0.3)
        collapse.move(0.40, 0.54)
        let held = collapse.inputs.count
        collapse.move(0.36, 0.54)
        collapse.move(0.36, 0.58)
        let closed = Run(collapse)
        check(!closed.steps.dropFirst(held).contains { $0.outputs.contains { if case .rowRemainder = $0 { true } else { false } } },
              "a closed list reports no remainder")
    }

    static func openListMargins() {
        var jitter = Trace.opening(from: 0.30, toward: 1)
        jitter.move(0.3804)
        jitter.clock(jitter.time + 0.3)
        jitter.move(0.3799, 0.665)
        jitter.lift()
        let slipped = Run(jitter)
        check(slipped.gestures.contains(.hold) && slipped.gestures.last == .commit(.entry(.back, distance: 2)),
              "a hair of drift below the commit point keeps the open list and its pick")

        var drifted = Trace.opening(from: 0.30, toward: 1)
        drifted.move(0.34, 0.52)
        drifted.move(0.38, 0.55)
        drifted.move(0.42, 0.58)
        drifted.clock(drifted.time + 0.3)
        let opened = drifted.inputs.count
        drifted.move(0.364, 0.58)
        let folded = Run(drifted)
        check(folded.steps.prefix(opened).flatMap(\.gestures).contains(.hold)
              && folded.steps.dropFirst(opened).flatMap(\.gestures) == [.armed(false)]
              && folded.recognizer.state == .tracking,
              "sliding back after earlier vertical travel folds the list and keeps the swipe going")

        var end = Trace.opening(from: 0.30, toward: 1)
        end.move(0.40)
        end.clock(end.time + 0.3)
        end.move(0.40, 0.59)
        let atEnd = end.inputs.count
        end.move(0.40, 0.63)
        let last = Run(end, Page(back: 1))
        let beyond = last.steps.dropFirst(atEnd).flatMap(\.outputs).compactMap { output -> Double? in
            if case let .rowRemainder(value) = output { value } else { nil }
        }
        check(last.recognizer.selection == 1 && beyond.allSatisfy { $0 <= 0 },
              "the last row leans toward nothing past the end of history")
    }

    static let release0 = HistorySwipeOutput.release(velocity: 0)

    static func peekDismissalValues() {
        let p = HistorySwipeParameters.dia
        check(p.dismissDistance == 0.3 && p.dismissCommitProgress == 0.5 && p.dismissDisarmProgress == 0.45,
              "a Peek card leaves over 30% of the trackpad, closes past halfway and disarms just below it")
        check(p.flickVelocity == 0.6 && p.flickProgress == 0.1 && p.velocityWindow == 0.08,
              "a flick is 60% of the trackpad a second after a tenth of the card's travel, measured over 80 ms")
    }

    static func peekDismissalTrackpad() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        for x in [0.36, 0.42, 0.47, 0.50] { trace.move(x) }
        trace.rest()
        trace.lift()
        trace.scroll(.none, dx: 4, momentum: .changed)
        let run = Run(trace, Page.peek)
        check(run.shape == [.beginDismissal, .armed(true), release0, .commit(.dismiss)],
              "on a Peek's first page a natural rightward swipe drags the card and closes it past halfway")
        check(near(run.fractions.prefix(4).map { ($0 * 1e6).rounded() / 1e6 }, [0.2, 0.4, 0.566667, 0.666667]),
              "card progress is finger travel over 30% of the trackpad")
        check(run.fractions == run.stretches, "the card follows the fingers with no rubber band")
        check(run.releases.count == 1 && abs(run.releases[0]) < 0.05, "resting before the lift releases with no speed")
        check(!run.steps.contains(where: \.preloadsBack), "a dismissal never warms a Back navigation")
        check(run.steps.allSatisfy { $0.clockDeadline == nil }, "a dismissal never schedules the history list")
        check(run.scrollConsumes.last == true, "the momentum after a dismissal stays off the page")
        check(run.recognizer.dismissing && run.recognizer.state == .completed, "the lift finishes the dismissal")

        var held = Trace.opening(from: 0.30, toward: 1)
        held.move(0.48)
        held.clock(held.time + 1)
        held.move(0.4805, after: 1)
        check(!Run(held, Page.peek).gestures.contains(.hold), "resting past halfway never opens a history list")

        var unnatural = Trace.opening(from: 0.60, toward: -1, natural: false)
        for x in [0.54, 0.48, 0.44] { unnatural.move(x) }
        unnatural.rest()
        unnatural.lift()
        check(Run(unnatural, Page.peek).shape == [.beginDismissal, .armed(true), release0, .commit(.dismiss)],
              "without natural scrolling the Back-direction swipe dismisses")
    }

    static func peekDismissalSpringsBack() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.36)
        trace.move(0.40)
        trace.rest()
        trace.lift()
        let run = Run(trace, Page.peek)
        check(run.shape == [.beginDismissal, release0, .cancel], "letting go before halfway springs the card back")
        var tiny = Trace.opening(from: 0.30, toward: 1)
        tiny.lift()
        check(Run(tiny, Page.peek).shape == [.beginDismissal, release0, .cancel],
              "lifting before the card moves never closes")
    }

    static func peekDismissalFlick() {
        var flick = Trace.opening(from: 0.30, toward: 1)
        flick.move(0.31)
        flick.move(0.34, after: 0.01)
        flick.lift()
        let fast = Run(flick, Page.peek)
        check(fast.shape == [.beginDismissal, release0, .commit(.dismiss)],
              "a quick flick closes the card even though it never reached halfway")
        check(fast.releases.first.map { $0 > 2 } == true, "the flick's speed is reported in card lengths a second")

        var short = Trace.opening(from: 0.30, toward: 1)
        short.move(0.31)
        short.move(0.325, after: 0.01)
        short.lift()
        check(Run(short, Page.peek).shape == [.beginDismissal, release0, .cancel],
              "a flick needs a tenth of the card's travel before it can close")

        var lazy = Trace.opening(from: 0.30, toward: 1)
        lazy.move(0.31)
        lazy.move(0.34, after: 0.2)
        lazy.lift()
        check(Run(lazy, Page.peek).shape == [.beginDismissal, release0, .cancel], "a slow short drag springs back")

        var stale = Trace.opening(from: 0.30, toward: 1)
        stale.move(0.31)
        stale.move(0.34, after: 0.01)
        stale.rest(0.15)
        stale.lift()
        check(Run(stale, Page.peek).shape == [.beginDismissal, release0, .cancel],
              "speed from more than 80 ms before the lift doesn't count as a flick")
    }

    static func peekDismissalReversal() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        for x in [0.40, 0.47, 0.44, 0.43, 0.38] { trace.move(x) }
        trace.rest()
        trace.lift()
        let back = Run(trace, Page.peek)
        check(back.shape == [.beginDismissal, .armed(true), .armed(false), release0, .cancel],
              "pulling back below the disarm point silently disarms and letting go springs back")
        check(back.fractions.suffix(3).allSatisfy { $0 < 0.5 }, "the card follows the fingers back")

        var tremor = Trace.opening(from: 0.30, toward: 1)
        for x in [0.46, 0.449, 0.456, 0.447, 0.455, 0.448] { tremor.move(x) }
        tremor.rest()
        tremor.lift()
        let shaky = Run(tremor, Page.peek)
        check(shaky.gestures.filter { $0 == .armed(true) }.count == 1 && !shaky.gestures.contains(.armed(false)),
              "tremor around halfway arms once, so the tap plays once")
        check(shaky.shape.last == .commit(.dismiss), "letting go while armed closes")

        var again = Trace.opening(from: 0.30, toward: 1)
        for x in [0.47, 0.42, 0.47] { again.move(x) }
        again.rest()
        again.lift()
        check(Run(again, Page.peek).shape == [.beginDismissal, .armed(true), .armed(false), .armed(true), release0,
                                               .commit(.dismiss)], "crossing halfway again taps again and closes")

        var thrown = Trace.opening(from: 0.30, toward: 1)
        for x in [0.40, 0.48, 0.52] { thrown.move(x) }
        thrown.move(0.47, after: 0.01)
        thrown.lift()
        check(Run(thrown, Page.peek).shape == [.beginDismissal, .armed(true), release0, .cancel],
              "flicking back toward the start keeps the card even past halfway")

        var behind = Trace.opening(from: 0.30, toward: 1)
        behind.move(0.36)
        behind.move(0.25)
        behind.rest()
        behind.lift()
        let past = Run(behind, Page.peek)
        check(past.fractions.last == 0 && past.shape.last == .cancel, "pulling past the start holds the card at rest")
    }

    static func peekDismissalVerticalCancel() {
        var drift = Trace.opening(from: 0.30, toward: 1)
        drift.move(0.36)
        drift.move(0.37, 0.56)
        drift.move(0.50, 0.56)
        drift.scroll(.changed, dx: 8)
        drift.lift()
        let run = Run(drift, Page.peek)
        check(run.shape == [.beginDismissal, .cancel], "drifting mostly up or down springs the card back")
        check(run.scrollConsumes.last == false, "a drift-cancelled drag hands its events back to the page")
        var long = Trace.opening(from: 0.30, toward: 1)
        long.move(0.50)
        long.move(0.50, 0.38)
        long.move(0.50, 0.24)
        check(Run(long, Page.peek).shape == [.beginDismissal, .armed(true), .cancel],
              "large vertical travel cancels even an armed dismissal")
    }

    static func peekDismissalMagicMouse() {
        var trace = Trace.wheel(dx: 4)
        trace.tracked(0, .began)
        trace.tracked(0.3, .changed)
        trace.tracked(0.55, .changed)
        trace.tracked(0.47, .changed)
        trace.tracked(0.6, .ended)
        trace.tracked(1, .ended, complete: true)
        let run = Run(trace, Page.peek)
        check(run.steps.compactMap(\.startsTracking) == [HistorySwipeTrackingRequest(direction: .back, generation: 1)],
              "a Magic Mouse swipe on a Peek's first page asks AppKit to track it")
        check(run.gestures == [.beginDismissal, .armed(true), .commit(.dismiss)],
              "AppKit's amount drags the card, arms at halfway and its end closes it")
        check(near(run.fractions, [0.3, 0.55, 0.47]), "the card follows AppKit's gesture amount")

        var early = Trace.wheel(dx: 4)
        early.tracked(0, .began)
        early.tracked(0.52, .changed)
        early.tracked(0.4, .changed)
        early.tracked(0.2, .cancelled)
        early.tracked(0, .cancelled, complete: true)
        check(Run(early, Page.peek).gestures == [.beginDismissal, .armed(true), .armed(false), .cancel],
              "AppKit's cancel springs the card back")
    }

    static func peekDismissalNeedsFirstPage() {
        var trace = Trace.opening(from: 0.30, toward: 1)
        trace.move(0.42)
        trace.lift()
        check(Run(trace, Page(back: 2, forward: 0, peekFirstPage: true)).gestures
              == [.begin(.back), .armed(true), .commit(.adjacent(.back))],
              "with pages behind it a Peek's swipe still goes Back")
        check(Run(trace, Page(back: 0)).outputs.isEmpty, "an ordinary first page keeps the gesture")

        var forward = Trace.opening(from: 0.60, toward: -1)
        forward.move(0.48)
        forward.lift()
        check(Run(forward, Page.peek).outputs.isEmpty, "swiping toward Forward never dismisses")
        check(Run(forward, Page(back: 0, forward: 1, peekFirstPage: true)).gestures
              == [.begin(.forward), .armed(true), .commit(.adjacent(.forward))],
              "a Peek with pages ahead still goes Forward")
    }

    static func peekDismissalKeepsPageRules() {
        var trace = Trace.opening(from: 0.30, toward: 1, consumed: true)
        trace.move(0.50)
        trace.lift()
        check(Run(trace, Page.peek).outputs.isEmpty, "a carousel that takes the first scroll keeps the gesture")
        var none = Trace.opening(from: 0.30, toward: 1, propagatesX: false)
        none.move(0.50)
        check(Run(none, Page.peek).outputs.isEmpty, "overscroll-behavior: none keeps the card still")
        var plain = Trace.opening(from: 0.30, toward: 1)
        plain.move(0.50)
        let off = Page.peek
        off.swipesBetweenPages = false
        check(Run(plain, off).outputs.isEmpty, "the system swipe setting turns dismissal off too")
        let page = Page.peek
        var covered = Run(Trace.opening(from: 0.30, toward: 1), page)
        page.allowsHistorySwipe = false
        var more = Trace()
        more.x = 0.305
        more.move(0.40)
        covered.play(more.inputs, page)
        check(covered.gestures == [.beginDismissal, .cancel], "losing the page mid-drag springs the card back")
        var touch = Trace.opening(from: 0.30, toward: 1)
        touch.move(0.40)
        touch.land(0.5)
        check(Run(touch, Page.peek).gestures == [.beginDismissal, .cancel], "a new touch cancels the drag")
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
