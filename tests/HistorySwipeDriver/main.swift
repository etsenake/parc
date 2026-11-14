import AppKit

final class Page: HistorySwipeTarget, HistorySwipePresenter, HistorySwipeClock {
    var swipesBetweenPages = true
    var allowsHistorySwipe = true
    var back = 3
    var forward = 2
    var opens = true
    var lands = true
    var begun: [HistorySwipeDirection] = []
    var commits: [HistorySwipeCommit] = []
    var ends = 0
    var preloads = 0
    var shown: [HistorySwipeOutput] = []
    var now: TimeInterval = 100
    var ticks: [(deadline: TimeInterval, tick: () -> Void)] = []
    var duringNavigation: (() -> Void)?

    func historyEntries(toward direction: HistorySwipeDirection) -> Int { direction == .back ? back : forward }
    func beginSwipe(_ direction: HistorySwipeDirection) -> Bool {
        begun.append(direction)
        return opens
    }
    func navigate(_ commit: HistorySwipeCommit) -> Bool {
        commits.append(commit)
        duringNavigation?()
        return lands
    }
    func endSwipe() { ends += 1 }
    func preloadBack() { preloads += 1 }
    func present(_ output: HistorySwipeOutput) { shown.append(output) }
    func schedule(at deadline: TimeInterval, _ tick: @escaping () -> Void) { ticks.append((deadline, tick)) }

    var gestures: [HistorySwipeOutput] { shown.filter { if case .progress = $0 { false } else { true } } }
}

let p = HistorySwipeParameters()
var checks = 0
func expect(_ value: Bool, _ message: String) {
    checks += 1
    precondition(value, "HistorySwipeDriver: \(message)")
}

struct Hand {
    let driver: HistorySwipeDriver
    let page: Page
    var time = 100.0
    var x = 0.5
    var y = 0.5
    var steps: [HistorySwipeStep] = []

    init(_ page: Page) {
        self.page = page
        driver = HistorySwipeDriver(target: page, presenter: page, clock: page)
    }

    var fingers: [HistorySwipePoint] {
        HistorySwipeEvents.points([CGPoint(x: x - 0.06, y: y), CGPoint(x: x + 0.06, y: y)])
    }

    mutating func send(_ input: HistorySwipeInput) { steps.append(driver.receive(input)) }

    mutating func scroll(_ phase: NSEvent.Phase, dx: Double = 0, dy: Double = 0) {
        send(HistorySwipeEvents.scroll(phase: phase, momentumPhase: [], deltaX: dx, deltaY: dy,
                                       directionInverted: true))
    }

    mutating func touch(_ phase: HistorySwipeTouchPhase, x: Double? = nil, y: Double? = nil) {
        time += 0.008
        page.now = time
        if let x { self.x = x }
        if let y { self.y = y }
        send(.touches(phase, fingers, time: time))
    }

    mutating func pageAnswers(consumed: Bool = false) {
        send(.pageScroll(.began(synthetic: false, momentum: false)))
        send(.overscroll(propagatesX: true))
        send(.pageScroll(.updated(consumed: consumed)))
    }

    mutating func openBack() {
        touch(.began)
        scroll(.mayBegin)
        touch(.moved, x: x + 0.002)
        scroll(.began, dx: 2)
        pageAnswers()
        touch(.moved, x: x + 0.003)
        scroll(.changed, dx: 3)
    }

    mutating func tick() {
        guard let due = page.ticks.last else { return }
        time = max(time, due.deadline)
        page.now = time
        due.tick()
    }
}

do {
    let page = Page()
    var hand = Hand(page)
    hand.openBack()
    expect(page.begun == [.back] && page.gestures == [.begin(.back)], "a swipe opens a session before the indicator")
    expect(hand.steps.last?.consumesEvent == true, "the opening scroll belongs to the swipe")
    hand.touch(.moved, x: 0.5 + p.consumeDistance * 2)
    expect(page.preloads == 1, "a likely Back navigation warms the page once")
    hand.touch(.moved, x: 0.5 + p.commitDistance * 1.1)
    hand.touch(.ended)
    expect(page.commits == [.adjacent(.back)], "lifting past the commit point moves Back once")
    expect(page.gestures == [.begin(.back), .armed(true), .commit(.adjacent(.back))], "the indicator sees the commit")
    expect(page.ends == 1 && !hand.driver.isActive, "the session ends with the swipe")
}

do {
    let page = Page()
    page.opens = false
    var hand = Hand(page)
    hand.openBack()
    expect(page.begun == [.back] && page.shown.isEmpty, "a refused session shows nothing")
    expect(hand.steps.last?.stopsTracking == true, "a refused session stops any tracking")
    hand.touch(.moved, x: 0.5 + p.commitDistance * 1.5)
    hand.touch(.ended)
    expect(page.commits.isEmpty && page.shown.isEmpty, "a refused session never navigates")
}

do {
    let page = Page()
    var hand = Hand(page)
    hand.openBack()
    hand.touch(.moved, x: 0.5 + p.commitDistance * 1.2)
    hand.driver.cancel()
    expect(page.gestures.last == .cancel && page.ends == 1, "a page or window change cancels the indicator")
    hand.touch(.ended)
    expect(page.commits.isEmpty, "a cancelled swipe never navigates late")
    hand.driver.cancel()
    expect(page.gestures.filter { $0 == .cancel }.count == 1, "a second cancel is ignored")
}

do {
    let page = Page()
    page.lands = false
    var hand = Hand(page)
    hand.openBack()
    hand.touch(.moved, x: 0.5 + p.commitDistance * 1.2)
    hand.touch(.ended)
    expect(page.commits == [.adjacent(.back)] && page.gestures.last == .cancel,
           "a commit the page refuses shows a cancel instead")
}

do {
    let page = Page()
    var hand = Hand(page)
    page.duringNavigation = { [driver = hand.driver] in driver.cancel() }
    hand.openBack()
    hand.touch(.moved, x: 0.5 + p.commitDistance * 1.2)
    hand.touch(.ended)
    expect(page.gestures.last == .commit(.adjacent(.back)) && page.gestures.filter { $0 == .cancel }.isEmpty,
           "the navigation's own start doesn't cancel the commit it caused")
}

do {
    let page = Page()
    var hand = Hand(page)
    hand.openBack()
    hand.touch(.moved, x: 0.5 + p.commitDistance * 1.2)
    let armedAt = hand.time
    expect(page.ticks.count == 1 && abs(page.ticks[0].deadline - (armedAt + p.holdDelay)) < 1e-9,
           "arming schedules the hold for the hold delay")
    hand.touch(.moved, x: 0.5 + p.commitDistance * 1.25)
    expect(page.ticks.count == 1, "an unchanged deadline is not scheduled twice")
    hand.tick()
    expect(page.gestures.suffix(2) == [.hold, .selection(1)], "the scheduled tick opens the list")
    hand.touch(.moved, y: 0.5 + p.rowStep * 1.1)
    hand.touch(.ended)
    expect(page.commits == [.entry(.back, distance: 2)], "lifting on a row navigates that many entries back")
}

do {
    let page = Page()
    var hand = Hand(page)
    hand.openBack()
    hand.touch(.moved, x: 0.5 + p.commitDistance * 1.2)
    let stale = page.ticks[0]
    hand.touch(.moved, x: 0.5 + p.commitDistance * 0.5)
    hand.touch(.moved, x: 0.5 + p.commitDistance * 1.2)
    expect(page.ticks.count == 2, "re-arming schedules a new hold")
    hand.time = stale.deadline
    page.now = stale.deadline
    stale.tick()
    expect(!page.gestures.contains(.hold), "a superseded tick does nothing")
}

do {
    let page = Page()
    var hand = Hand(page)
    hand.scroll(.mayBegin)
    hand.scroll(.began, dx: 1)
    hand.pageAnswers()
    hand.scroll(.changed, dx: 4)
    guard let request = hand.steps.last?.startsTracking else { fatalError("HistorySwipeDriver: no tracking request") }
    expect(request.direction == .back && hand.steps.last?.consumesEvent == true,
           "a swipe without touches asks AppKit to track it")
    func update(_ amount: Double, _ phase: NSEvent.Phase, complete: Bool = false, generation: Int? = nil) -> Bool {
        hand.driver.tracked(HistorySwipeTrackedUpdate(generation: generation ?? request.generation, amount: amount,
                                                      phase: HistorySwipeEvents.phase(phase), isComplete: complete))
    }
    expect(update(0, .began), "tracking begins")
    expect(page.begun == [.back] && page.gestures == [.begin(.back)], "the tracked swipe opens its session")
    expect(update(0.35, .changed) && page.gestures.contains(.armed(true)), "AppKit's amount arms the swipe")
    expect(update(0.6, .ended) && page.commits == [.adjacent(.back)], "AppKit's end commits")
    expect(update(1, .changed, complete: true), "the finishing animation runs out")
    expect(!update(0.2, .changed, generation: request.generation + 1), "a stale tracker is stopped")
}

do {
    let page = Page()
    var hand = Hand(page)
    hand.scroll(.mayBegin)
    hand.scroll(.began, dx: 1)
    hand.pageAnswers()
    hand.scroll(.changed, dx: 4)
    let generation = hand.steps.last?.startsTracking?.generation ?? 0
    _ = hand.driver.tracked(HistorySwipeTrackedUpdate(generation: generation, amount: 0, phase: .began))
    hand.driver.cancel()
    let keeps = hand.driver.tracked(HistorySwipeTrackedUpdate(generation: generation, amount: 0.5, phase: .ended))
    expect(!keeps && page.commits.isEmpty, "AppKit's late end after a cancel stops tracking and never navigates")
}

do {
    let page = Page()
    var hand = Hand(page)
    hand.openBack()
    page.allowsHistorySwipe = false
    hand.touch(.moved, x: 0.5 + p.commitDistance * 1.2)
    expect(page.gestures.last == .cancel && page.ends == 1, "losing eligibility mid-swipe cancels")
    page.allowsHistorySwipe = true
    var refused = Hand(Page())
    refused.page.allowsHistorySwipe = false
    refused.openBack()
    expect(refused.page.begun.isEmpty && refused.page.shown.isEmpty, "an ineligible page never opens a session")
    var off = Hand(Page())
    off.page.swipesBetweenPages = false
    off.openBack()
    expect(off.page.begun.isEmpty, "the system setting turns swiping off")
}

do {
    let page = Page()
    weak var gone: Page?
    var driver: HistorySwipeDriver?
    do {
        let temporary = Page()
        gone = temporary
        driver = HistorySwipeDriver(target: temporary, presenter: page, clock: page)
    }
    expect(gone == nil, "the driver doesn't keep its page alive")
    expect(driver?.receive(.cancel).stopsTracking == true, "a driver whose page is gone stops tracking")
}

expect(HistorySwipeEvents.phase(.began) == .began && HistorySwipeEvents.phase(.changed) == .changed
       && HistorySwipeEvents.phase(.mayBegin) == .mayBegin && HistorySwipeEvents.phase(.stationary) == .stationary
       && HistorySwipeEvents.phase(.ended) == .ended && HistorySwipeEvents.phase(.cancelled) == .cancelled
       && HistorySwipeEvents.phase([]) == .none && HistorySwipeEvents.phase([.began, .changed]) == .none,
       "AppKit phases map one to one, and anything else is no phase")

let rows = HistorySwipeRows(entries: ["a", "b", "c", "d", "e"], currentIndex: 3)
expect(rows.current == "d" && rows.back == ["c", "b", "a"] && rows.forward == ["e"],
       "rows list the adjacent entry first in each direction")
let edge = HistorySwipeRows(entries: ["a"], currentIndex: 0)
expect(edge.current == "a" && edge.back.isEmpty && edge.forward.isEmpty, "a single entry has no neighbours")
expect(HistorySwipeRows(entries: ["a"], currentIndex: 4).current == nil, "an out-of-range index shows no rows")

precondition(checks == 37, "HistorySwipeDriver: ran \(checks) checks")
print("HistorySwipeDriver: \(checks) checks passed")
