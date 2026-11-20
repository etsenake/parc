import AppKit

@MainActor
final class HistorySwipeForwarding: NSObject, PCNativeHistorySwipeClient {
    static let shared = HistorySwipeForwarding()

    static func install() {
        if PCNativeHistorySwipeSource.client == nil { PCNativeHistorySwipeSource.client = shared }
        HistorySwipeNoteSource.shared.install()
    }

    func historySwipeHandler(for source: PCNativeHistorySwipeSource) -> any PCNativeHistorySwipeHandler {
        HistorySwipeForwarder(source: source)
    }
}

final class HistorySwipeSystemClock: HistorySwipeClock {
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
    private weak var dismissal: PeekController?
    private weak var lookedUpPeek: PeekController?
    private var peekLookedUp = false
    private var noteStep: (controller: BrowserWindowController, tabID: UUID, visit: TabNoteVisit)?
    private var engineSwipe = false

    init(source: PCNativeHistorySwipeSource) {
        self.source = source
    }

    func historySwipeSource(_ source: PCNativeHistorySwipeSource, scroll event: NSEvent) -> Bool {
        if event.phase == .began { peekLookedUp = false }
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
        EmbeddedPagePool.pageScrollBegan(momentum: momentum, from: source)
    }

    func historySwipeSource(_ source: PCNativeHistorySwipeSource, pageScrollUpdatedConsumed consumed: Bool) {
        driver.receive(.pageScroll(.updated(consumed: consumed)))
        EmbeddedPagePool.pageScrollUpdated(consumed: consumed, from: source)
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
        let pageEntries = source?.historyEntries(back: direction == .back) ?? 0
        return HistorySwipeNoteStep.entries(toward: direction, visit: noteAhead(direction)?.visit, pageEntries: pageEntries)
    }

    private func noteAhead(_ direction: HistorySwipeDirection) -> (controller: BrowserWindowController, tabID: UUID, visit: TabNoteVisit)? {
        guard direction == .forward, let browser = swipeBrowser,
              let controller = browser.window?.windowController as? BrowserWindowController,
              let id = controller.noteVisitTarget(.forward), controller.browsers[id] === browser,
              let visit = controller.store.state.tab(id)?.noteVisit, !visit.showsNote else { return nil }
        return (controller, id, visit)
    }

    private var swipeBrowser: PCBrowserView? {
        var view = source?.overlayContainer
        while let current = view, !(current is PCBrowserView) { view = current.superview }
        return view as? PCBrowserView
    }

    func dismisses(toward direction: HistorySwipeDirection) -> Bool {
        direction == .back && swipePeek?.canSwipeDismiss == true
    }

    func beginDismissal() -> Bool {
        guard let peek = swipePeek, peek.canSwipeDismiss, peek.beginSwipeDismissal() else { return false }
        dismissal = peek
        return true
    }

    private var swipePeek: PeekController? {
        if peekLookedUp { return lookedUpPeek }
        let browser = swipeBrowser
        let controller = browser?.window?.windowController as? BrowserWindowController
        let peek = browser?.nativePage.flatMap { controller?.activePeek(showing: $0) }
        lookedUpPeek = peek
        peekLookedUp = true
        return peek
    }

    func beginSwipe(_ direction: HistorySwipeDirection) -> Bool {
        noteStep = noteAhead(direction)
        let pageEntries = source?.historyEntries(back: direction == .back) ?? 0
        history = noteStep == nil || pageEntries > 0 ? source?.beginSwipe(back: direction == .back) : nil
        engineSwipe = history != nil
        return history != nil || noteStep != nil
    }

    func navigate(_ commit: HistorySwipeCommit) -> Bool {
        guard let source else { return false }
        if let noteStep {
            let distance: Int
            switch commit {
            case .adjacent: distance = 1
            case let .entry(_, steps): distance = steps
            case .dismiss: return false
            }
            switch HistorySwipeNoteStep.step(toward: .forward, distance: distance, visit: noteStep.visit,
                                             pageEntries: engineSwipe ? source.historyEntries(back: false) : 0) {
            case .note?:
                guard noteStep.controller.noteVisitTarget(.forward) == noteStep.tabID else { return false }
                return noteStep.controller.stepNoteVisit(noteStep.tabID, forward: true)
            case let .page(steps)?:
                return source.navigate(back: false, distance: steps)
            case .pageUnderNote?, nil:
                return false
            }
        }
        switch commit {
        case let .adjacent(direction): return source.navigate(back: direction == .back)
        case let .entry(direction, distance): return source.navigate(back: direction == .back, distance: distance)
        case .dismiss: return dismissal?.commitSwipeDismissal() ?? false
        }
    }

    func endSwipe() {
        noteStep = nil
        if engineSwipe { source?.endSwipe() }
        engineSwipe = false
    }

    func preloadBack() {
        source?.preloadBack()
    }

    func present(_ output: HistorySwipeOutput) {
        if let peek = dismissal {
            switch output {
            case .commit:
                dismissal = nil
            case .cancel:
                dismissal = nil
                peek.followSwipeDismissal(output)
            default:
                peek.followSwipeDismissal(output)
            }
            return
        }
        if case .beginDismissal = output { return }
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
        let rows = history.map { HistorySwipeRows(entries: $0.entries.map(Self.row), currentIndex: $0.currentIndex) }
        if let noteStep {
            let note = HistorySwipeOverlayRow(title: noteStep.visit.note.title,
                                              favicon: noteStep.visit.noteFile.flatMap { NoteTabIconArt.shared.image(forNote: $0) })
            let current = rows?.current ?? HistorySwipeOverlayRow(title: noteStep.visit.page.title, favicon: nil)
            view.setRows(current: current, back: rows?.back ?? [], forward: [note] + (rows?.forward ?? []))
        } else if let rows {
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
