import AppKit

@MainActor
final class HistorySwipeForwarding: NSObject, PCNativeHistorySwipeClient {
    static let shared = HistorySwipeForwarding()

    static func install() {
        if PCNativeHistorySwipeSource.client == nil { PCNativeHistorySwipeSource.client = shared }
    }

    func historySwipeHandler(for source: PCNativeHistorySwipeSource) -> any PCNativeHistorySwipeHandler {
        HistorySwipeForwarder(source: source)
    }
}

private final class HistorySwipeSystemClock: HistorySwipeClock {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func schedule(at deadline: TimeInterval, _ tick: @escaping () -> Void) {
        let timer = Timer(timeInterval: max(0, deadline - now), repeats: false) { _ in tick() }
        RunLoop.main.add(timer, forMode: .common)
    }
}

@MainActor
final class HistorySwipeForwarder: NSObject, PCNativeHistorySwipeHandler,
                                   @preconcurrency HistorySwipeTarget, @preconcurrency HistorySwipePresenter {
    private weak var source: PCNativeHistorySwipeSource?
    private let clock = HistorySwipeSystemClock()
    private lazy var driver = HistorySwipeDriver(target: self, presenter: self, clock: clock)
    private var history: PCNativeHistorySwipeHistory?
    private var overlay: HistorySwipeOverlayView?
    private var reducesMotion = false

    init(source: PCNativeHistorySwipeSource) {
        self.source = source
    }

    func historySwipeSource(_ source: PCNativeHistorySwipeSource, scroll event: NSEvent) -> Bool {
        let step = driver.receive(HistorySwipeEvents.scroll(
            phase: event.phase, momentumPhase: event.momentumPhase, deltaX: Double(event.scrollingDeltaX),
            deltaY: Double(event.scrollingDeltaY), directionInverted: event.isDirectionInvertedFromDevice))
        if let request = step.startsTracking { track(event, request) }
        return step.consumesEvent
    }

    func historySwipeSource(_ source: PCNativeHistorySwipeSource, touches event: NSEvent,
                            phase: PCNativeHistorySwipeTouchPhase) {
        let points = HistorySwipeEvents.points(event.touches(matching: .any, in: nil).map(\.normalizedPosition))
        driver.receive(.touches(Self.phase(phase), points, time: event.timestamp))
    }

    func historySwipeSource(_ source: PCNativeHistorySwipeSource, pageScrollBeganSynthetic synthetic: Bool,
                            momentum: Bool) {
        driver.receive(.pageScroll(.began(synthetic: synthetic, momentum: momentum)))
    }

    func historySwipeSource(_ source: PCNativeHistorySwipeSource, pageScrollUpdatedConsumed consumed: Bool) {
        driver.receive(.pageScroll(.updated(consumed: consumed)))
    }

    func historySwipeSource(_ source: PCNativeHistorySwipeSource, overscrollPropagatesX propagates: Bool) {
        driver.receive(.overscroll(propagatesX: propagates))
    }

    func historySwipeSourceDidCancel(_ source: PCNativeHistorySwipeSource) {
        driver.cancel()
    }

    var swipesBetweenPages: Bool { NSEvent.isSwipeTrackingFromScrollEventsEnabled }
    var allowsHistorySwipe: Bool { source?.allowsHistorySwipe ?? false }

    func historyEntries(toward direction: HistorySwipeDirection) -> Int {
        source?.historyEntries(back: direction == .back) ?? 0
    }

    func dismisses(toward direction: HistorySwipeDirection) -> Bool { false }

    func beginDismissal() -> Bool { false }

    func beginSwipe(_ direction: HistorySwipeDirection) -> Bool {
        history = source?.beginSwipe(back: direction == .back)
        return history != nil
    }

    func navigate(_ commit: HistorySwipeCommit) -> Bool {
        guard let source else { return false }
        switch commit {
        case let .adjacent(direction): return source.navigate(back: direction == .back)
        case let .entry(direction, distance): return source.navigate(back: direction == .back, distance: distance)
        case .dismiss: return false
        }
    }

    func endSwipe() {
        source?.endSwipe()
    }

    func preloadBack() {
        source?.preloadBack()
    }

    func present(_ output: HistorySwipeOutput) {
        if case .begin = output { showOverlay() }
        guard let overlay else { return }
        overlay.handle(output)
        switch output {
        case .commit, .cancel:
            self.overlay = nil
            history = nil
            let collapse = reducesMotion ? HistorySwipeOverlayTiming.reducedCollapse : HistorySwipeOverlayTiming.collapse
            let timer = Timer(timeInterval: collapse, repeats: false) { [weak overlay] _ in
                MainActor.assumeIsolated { overlay?.removeFromSuperview() }
            }
            RunLoop.main.add(timer, forMode: .common)
        default:
            break
        }
    }

    private func showOverlay() {
        overlay = nil
        reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard let container = source?.overlayContainer else { return }
        let view = HistorySwipeOverlayView(frame: container.bounds)
        view.autoresizingMask = [.width, .height]
        view.palette = (container.window?.windowController as? BrowserWindowController)?.historySwipePalette
        if let history {
            let rows = HistorySwipeRows(entries: history.entries.map(Self.row), currentIndex: history.currentIndex)
            view.setRows(current: rows.current ?? HistorySwipeOverlayRow(title: "", favicon: nil),
                         back: rows.back, forward: rows.forward)
        }
        container.addSubview(view)
        overlay = view
    }

    private func track(_ event: NSEvent, _ request: HistorySwipeTrackingRequest) {
        event.trackSwipeEvent(options: .lockDirection, dampenAmountThresholdMin: -1, max: 1) {
            [weak self] amount, phase, complete, stop in
            MainActor.assumeIsolated {
                let update = HistorySwipeTrackedUpdate(generation: request.generation, amount: Double(amount),
                                                       phase: HistorySwipeEvents.phase(phase), isComplete: complete)
                if self?.driver.tracked(update) != true { stop.pointee = true }
            }
        }
    }

    private static func row(_ entry: PCNativeHistorySwipeEntry) -> HistorySwipeOverlayRow {
        HistorySwipeOverlayRow(title: entry.title, favicon: entry.favicon)
    }

    private static func phase(_ phase: PCNativeHistorySwipeTouchPhase) -> HistorySwipeTouchPhase {
        switch phase {
        case .began: .began
        case .moved: .moved
        case .ended: .ended
        case .cancelled: .cancelled
        @unknown default: .cancelled
        }
    }
}
