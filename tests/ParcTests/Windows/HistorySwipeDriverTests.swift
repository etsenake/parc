import AppKit
@testable import ParcCore
import Testing
@testable import Parc

struct HistorySwipeDriverTests {
    private let parameters = HistorySwipeParameters()

    @Test
    func openingBackPresentsTheSession() {
        var hand = Hand(Page())
        hand.openBack()
        #expect(hand.page.begun == [.back])
        #expect(hand.page.gestures == [.begin(.back)])
    }

    @Test
    func openingBackConsumesTheScroll() {
        var hand = Hand(Page())
        hand.openBack()
        #expect(hand.steps.last?.consumesEvent == true)
    }

    @Test
    func likelyBackPreloadsOnce() {
        var hand = Hand(Page())
        hand.openBack()
        hand.touch(.moved, x: 0.5 + parameters.consumeDistance * 2)
        hand.armBack()
        #expect(hand.page.preloads == 1)
    }

    @Test
    func liftingAnArmedSwipeNavigatesBackOnce() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.touch(.ended)
        #expect(hand.page.commits == [.adjacent(.back)])
    }

    @Test
    func liftingAnArmedSwipePresentsTheCommit() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.touch(.ended)
        #expect(hand.page.gestures == [.begin(.back), .armed(true), .commit(.adjacent(.back))])
    }

    @Test
    func committingEndsTheSession() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.touch(.ended)
        #expect(hand.page.ends == 1)
        #expect(!hand.driver.isActive)
    }

    @Test
    func refusingBackStopsTrackingWithoutAnIndicator() {
        var hand = Hand(Page())
        hand.page.opens = false
        hand.openBack()
        #expect(hand.page.begun == [.back])
        #expect(hand.page.shown.isEmpty)
        #expect(hand.steps.last?.stopsTracking == true)
    }

    @Test
    func liftingAfterRefusalDoesNotNavigate() {
        var hand = Hand(Page())
        hand.page.opens = false
        hand.openBack()
        hand.armBack(multiplier: 1.5)
        hand.touch(.ended)
        #expect(hand.page.commits.isEmpty)
        #expect(hand.page.shown.isEmpty)
    }

    @Test
    func cancelEndsTheSessionAndIndicator() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.driver.cancel()
        #expect(hand.page.gestures.last == .cancel)
        #expect(hand.page.ends == 1)
    }

    @Test
    func liftingAfterCancelDoesNotNavigate() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.driver.cancel()
        hand.touch(.ended)
        #expect(hand.page.commits.isEmpty)
    }

    @Test
    func cancellingTwicePresentsOneCancel() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.driver.cancel()
        hand.driver.cancel()
        #expect(hand.page.gestures.filter { $0 == .cancel }.count == 1)
    }

    @Test
    func refusedNavigationCancelsTheIndicator() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.page.lands = false
        hand.touch(.ended)
        #expect(hand.page.commits == [.adjacent(.back)])
        #expect(hand.page.gestures.last == .cancel)
    }

    @Test
    func navigationCanRequestCancellationWithoutCancellingItsOwnCommit() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.page.duringNavigation = { [weak driver = hand.driver] in driver?.cancel() }
        hand.touch(.ended)
        #expect(hand.page.gestures.last == .commit(.adjacent(.back)))
        #expect(!hand.page.gestures.contains(.cancel))
    }

    @Test
    func armingSchedulesTheHoldDelay() throws {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        let tick = try #require(hand.page.ticks.first)
        #expect(hand.page.ticks.count == 1)
        #expect(abs(tick.deadline - (hand.time + parameters.holdDelay)) < 1e-9)
    }

    @Test
    func movingWithTheSameDeadlineDoesNotScheduleAgain() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.armBack(multiplier: 1.25)
        #expect(hand.page.ticks.count == 1)
    }

    @Test
    func holdingOpensTheListOnTheCurrentPage() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.armBack(multiplier: 1.25)
        hand.tick()
        hand.tick()
        #expect(hand.page.gestures.suffix(2) == [.hold, .selection(0)])
    }

    @Test
    func liftingOnAHistoryRowNavigatesToThatEntry() {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        hand.armBack(multiplier: 1.25)
        hand.tick()
        hand.tick()
        hand.touch(.moved, y: 0.5 + parameters.rowStep * 1.1)
        hand.touch(.ended)
        #expect(hand.page.commits == [.entry(.back, distance: 1)])
    }

    @Test
    func rearmingSupersedesTheEarlierHold() throws {
        var hand = Hand(Page())
        hand.openBack()
        hand.armBack()
        let stale = try #require(hand.page.ticks.first)
        hand.armBack(multiplier: 0.5)
        hand.armBack()
        #expect(hand.page.ticks.count == 2)
        hand.page.now = stale.deadline
        stale.tick()
        #expect(!hand.page.gestures.contains(.hold))
    }

    @Test
    func aSwipeWithoutTouchesRequestsAppKitTracking() throws {
        var hand = Hand(Page())
        let generation = try hand.openTrackedBack()
        #expect(generation > 0)
        #expect(hand.steps.last?.startsTracking?.direction == .back)
        #expect(hand.steps.last?.consumesEvent == true)
    }

    @Test
    func appKitTrackingBeginsTheSession() throws {
        var hand = Hand(Page())
        let generation = try hand.openTrackedBack()
        #expect(hand.update(generation, 0, .began))
        #expect(hand.page.begun == [.back])
        #expect(hand.page.gestures == [.begin(.back)])
    }

    @Test
    func appKitAmountArmsTheSwipe() throws {
        var hand = Hand(Page())
        let generation = try hand.openTrackedBack()
        _ = hand.update(generation, 0, .began)
        #expect(hand.update(generation, 0.35, .changed))
        #expect(hand.page.gestures.contains(.armed(true)))
    }

    @Test
    func appKitEndingCommitsTheSwipe() throws {
        var hand = Hand(Page())
        let generation = try hand.openTrackedBack()
        _ = hand.update(generation, 0, .began)
        _ = hand.update(generation, 0.35, .changed)
        #expect(hand.update(generation, 0.6, .ended))
        #expect(hand.page.commits == [.adjacent(.back)])
    }

    @Test
    func appKitCanFinishItsAnimationAfterCommit() throws {
        var hand = Hand(Page())
        let generation = try hand.openTrackedBack()
        _ = hand.update(generation, 0, .began)
        _ = hand.update(generation, 0.35, .changed)
        _ = hand.update(generation, 0.6, .ended)
        #expect(hand.update(generation, 1, .changed, complete: true))
    }

    @Test
    func aStaleAppKitGenerationStopsTracking() throws {
        var hand = Hand(Page())
        let generation = try hand.openTrackedBack()
        _ = hand.update(generation, 0, .began)
        #expect(!hand.update(generation + 1, 0.2, .changed))
    }

    @Test
    func aLateAppKitEndAfterCancelStopsWithoutNavigating() throws {
        var hand = Hand(Page())
        let generation = try hand.openTrackedBack()
        _ = hand.update(generation, 0, .began)
        hand.driver.cancel()
        #expect(!hand.update(generation, 0.5, .ended))
        #expect(hand.page.commits.isEmpty)
    }

    @Test
    func losingEligibilityMidSwipeCancels() {
        var hand = Hand(Page())
        hand.openBack()
        hand.page.allowsHistorySwipe = false
        hand.armBack()
        #expect(hand.page.gestures.last == .cancel)
        #expect(hand.page.ends == 1)
    }

    @Test(arguments: [true, false])
    func aDisabledSwipeDoesNotOpenASession(systemEnabled: Bool) {
        var hand = Hand(Page())
        hand.page.swipesBetweenPages = systemEnabled
        hand.page.allowsHistorySwipe = !systemEnabled
        hand.openBack()
        #expect(hand.page.begun.isEmpty)
        #expect(hand.page.shown.isEmpty)
    }

    @Test
    func aDeallocatedPageStopsTracking() {
        let page = Page()
        weak var gone: Page?
        let driver: HistorySwipeDriver
        do {
            let temporary = Page()
            gone = temporary
            driver = HistorySwipeDriver(target: temporary, presenter: page, clock: page)
        }
        #expect(gone == nil)
        #expect(driver.receive(.cancel).stopsTracking)
    }

    @Test
    func theFirstPeekPageOpensDismissal() {
        var hand = Hand(Page.peek)
        hand.openBack()
        #expect(hand.page.begun.isEmpty)
        #expect(hand.page.dismissals == 1)
        #expect(hand.page.gestures == [.beginDismissal])
    }

    @Test
    func releasingAnArmedPeekAsksItToCloseOnce() {
        var hand = Hand(Page.peek)
        hand.openBack()
        hand.touch(.moved, x: 0.5 + parameters.dismissDistance * 0.6)
        hand.rest()
        hand.touch(.ended)
        #expect(hand.page.commits == [.dismiss])
    }

    @Test
    func thePeekReceivesArmingAndReleaseBeforeClose() {
        var hand = Hand(Page.peek)
        hand.openBack()
        hand.touch(.moved, x: 0.5 + parameters.dismissDistance * 0.3)
        hand.touch(.moved, x: 0.5 + parameters.dismissDistance * 0.6)
        hand.rest()
        hand.touch(.ended)
        #expect(hand.page.shape == [.beginDismissal, .armed(true), .release(velocity: 0), .commit(.dismiss)])
    }

    @Test
    func peekDismissalEndsWithoutPreloadingBack() {
        var hand = Hand(Page.peek)
        hand.openBack()
        hand.touch(.moved, x: 0.5 + parameters.dismissDistance * 0.6)
        hand.rest()
        hand.touch(.ended)
        #expect(hand.page.ends == 1)
        #expect(hand.page.preloads == 0)
        #expect(!hand.driver.isActive)
    }

    @Test
    func refusingPeekDismissalStopsTrackingWithoutPresentation() {
        var hand = Hand(Page.peek)
        hand.page.dismissalOpens = false
        hand.openBack()
        #expect(hand.page.dismissals == 1)
        #expect(hand.page.shown.isEmpty)
        #expect(hand.steps.last?.stopsTracking == true)
    }

    @Test
    func releasingARefusedPeekDragDoesNotClose() {
        var hand = Hand(Page.peek)
        hand.page.dismissalOpens = false
        hand.openBack()
        hand.touch(.moved, x: 0.5 + parameters.dismissDistance * 0.8)
        hand.touch(.ended)
        #expect(hand.page.commits.isEmpty)
        #expect(hand.page.shown.isEmpty)
    }

    @Test
    func aPeekThatRefusesToCloseSpringsBack() {
        var hand = Hand(Page.peek)
        hand.openBack()
        hand.touch(.moved, x: 0.5 + parameters.dismissDistance * 0.6)
        hand.page.lands = false
        hand.rest()
        hand.touch(.ended)
        #expect(hand.page.commits == [.dismiss])
        #expect(hand.page.gestures.last == .cancel)
    }

    @Test
    func cancellingAPeekDragEndsItOnceWithoutClosing() {
        var hand = Hand(Page.peek)
        hand.openBack()
        hand.touch(.moved, x: 0.5 + parameters.dismissDistance * 0.6)
        hand.driver.cancel()
        hand.touch(.ended)
        #expect(hand.page.commits.isEmpty)
        #expect(hand.page.gestures.filter { $0 == .cancel }.count == 1)
        #expect(hand.page.ends == 1)
    }

    @Test
    func appKitTrackingBeginsPeekDismissal() throws {
        var hand = Hand(Page.peek)
        let generation = try hand.openTrackedBack()
        #expect(generation > 0)
        #expect(hand.update(generation, 0, .began))
        #expect(hand.page.gestures == [.beginDismissal])
    }

    @Test
    func appKitEndingClosesThePeek() throws {
        var hand = Hand(Page.peek)
        let generation = try hand.openTrackedBack()
        _ = hand.update(generation, 0, .began)
        #expect(hand.update(generation, 0.6, .changed))
        #expect(hand.update(generation, 0.7, .ended))
        #expect(hand.page.commits == [.dismiss])
    }

    @Test
    func aPeekWithPreviousPagesOpensBackInsteadOfDismissal() {
        var hand = Hand(Page())
        hand.page.peekFirstPage = true
        hand.openBack()
        #expect(hand.page.begun == [.back])
        #expect(hand.page.dismissals == 0)
    }

    @Test(arguments: [
        (NSEvent.Phase.began.rawValue, HistorySwipeEventPhase.began),
        (NSEvent.Phase.changed.rawValue, .changed),
        (NSEvent.Phase.mayBegin.rawValue, .mayBegin),
        (NSEvent.Phase.stationary.rawValue, .stationary),
        (NSEvent.Phase.ended.rawValue, .ended),
        (NSEvent.Phase.cancelled.rawValue, .cancelled),
        (0, .none),
        (NSEvent.Phase([.began, .changed]).rawValue, .none),
    ])
    func appKitPhasesMapToSwipePhases(rawPhase: UInt, expected: HistorySwipeEventPhase) {
        #expect(HistorySwipeEvents.phase(NSEvent.Phase(rawValue: rawPhase)) == expected)
    }

    @Test
    func historyRowsStartWithTheAdjacentEntry() {
        let rows = HistorySwipeRows(entries: ["a", "b", "c", "d", "e"], currentIndex: 3)
        #expect(rows.current == "d")
        #expect(rows.back == ["c", "b", "a"])
        #expect(rows.forward == ["e"])
    }

    @Test
    func aSingleHistoryEntryHasNoNeighbours() {
        let rows = HistorySwipeRows(entries: ["a"], currentIndex: 0)
        #expect(rows.current == "a")
        #expect(rows.back.isEmpty)
        #expect(rows.forward.isEmpty)
    }

    @Test
    func anInvalidHistoryIndexHasNoRows() {
        let rows = HistorySwipeRows(entries: ["a"], currentIndex: 4)
        #expect(rows.current == nil)
        #expect(rows.back.isEmpty)
        #expect(rows.forward.isEmpty)
    }

    private final class Page: HistorySwipeTarget, HistorySwipePresenter, HistorySwipeClock {
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

    private struct Hand {
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
