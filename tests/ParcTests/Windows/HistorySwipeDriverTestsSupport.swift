import AppKit
@testable import ParcCore
import Testing
@testable import Parc

enum HistorySwipeDriverTestsSupport {
    final class Page: HistorySwipeTarget, HistorySwipePresenter, HistorySwipeClock {
        var swipesBetweenPages = true
        var allowsHistorySwipe = true
        var back = 3
        var forward = 2
        var opens = true
        var lands = true
        var peekFirstPage = false
        var dismissalOpens = true
        var dismissals = 0
        var begun: [HistorySwipeDirection] = []
        var commits: [HistorySwipeCommit] = []
        var ends = 0
        var preloads = 0
        var shown: [HistorySwipeOutput] = []
        var now: TimeInterval = 100
        var ticks: [(deadline: TimeInterval, tick: () -> Void)] = []
        var duringNavigation: (() -> Void)?

        func historyEntries(toward direction: HistorySwipeDirection) -> Int { direction == .back ? back : forward }
        func dismisses(toward direction: HistorySwipeDirection) -> Bool { peekFirstPage && direction == .back }
        func beginDismissal() -> Bool {
            dismissals += 1
            return dismissalOpens
        }
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
        var shape: [HistorySwipeOutput] { gestures.map { if case .release = $0 { .release(velocity: 0) } else { $0 } } }

        static var peek: Page {
            let page = Page()
            page.back = 0
            page.forward = 0
            page.peekFirstPage = true
            return page
        }
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

        mutating func armBack(multiplier: Double = 1.2) {
            touch(.moved, x: 0.5 + HistorySwipeParameters().commitDistance * multiplier)
        }

        mutating func openTrackedBack() throws -> Int {
            scroll(.mayBegin)
            scroll(.began, dx: 1)
            pageAnswers()
            scroll(.changed, dx: 4)
            return try #require(steps.last?.startsTracking).generation
        }

        func update(_ generation: Int, _ amount: Double, _ phase: HistorySwipeEventPhase,
                    complete: Bool = false) -> Bool {
            driver.tracked(HistorySwipeTrackedUpdate(generation: generation, amount: amount,
                                                      phase: phase, isComplete: complete))
        }

        mutating func rest() {
            time += 0.2
            touch(.moved, x: x + 0.0005)
        }

        mutating func tick() {
            guard let due = page.ticks.last else { return }
            time = max(time, due.deadline)
            page.now = time
            due.tick()
        }
    }
}
