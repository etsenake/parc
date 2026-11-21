import AppKit
import ParcCore

@MainActor
protocol HistorySwipeScrollRoomProvider: AnyObject {
    var historySwipeScrollRoom: HistorySwipeTargets.ScrollRoom? { get }
}

@MainActor
final class HistorySwipeNoteSource: NSObject, @preconcurrency HistorySwipeTarget, @preconcurrency HistorySwipePresenter {
    static let shared = HistorySwipeNoteSource()

    private let clock = HistorySwipeSystemClock()
    private lazy var driver = HistorySwipeDriver(target: self, presenter: self, clock: clock)
    private var monitor: Any?
    private var buttonMonitor: Any?
    private weak var controller: BrowserWindowController?
    private var tabID: UUID?
    private weak var peek: DocumentPeekController?
    private var dismissing = false
    private var overlay: HistorySwipeOverlayView?
    private var reducesMotion = false

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated { HistorySwipeNoteSource.shared.receive(event) } ? nil : event
        }
        buttonMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .otherMouseUp]) { event in
            MainActor.assumeIsolated { HistorySwipeNoteSource.shared.historyButton(event) } ? nil : event
        }
    }

    private func historyButton(_ event: NSEvent) -> Bool {
        guard event.buttonNumber == 3 || event.buttonNumber == 4, let window = event.window,
              let controller = window.windowController as? BrowserWindowController, let content = window.contentView,
              let hit = content.hitTest(content.convert(event.locationInWindow, from: nil)) else { return false }
        let forward = event.buttonNumber == 4
        guard let id = controller.noteVisitTarget(forward ? .forward : .back),
              let view = controller.browsers[id] ?? noteView(controller, id),
              hit === view || hit.isDescendant(of: view) else { return false }
        if event.type == .otherMouseUp { controller.stepNoteVisit(id, forward: forward) }
        return true
    }

    private func receive(_ event: NSEvent) -> Bool {
        if event.phase == .began {
            if driver.isActive { driver.cancel() }
            resolveTarget(event)
            guard tabID != nil || peek != nil else { return false }
            driver.receive(.pageScroll(.began(synthetic: false, momentum: false)))
            driver.receive(.pageScroll(.updated(consumed: Self.scrollsHorizontally(event))))
            driver.receive(.overscroll(propagatesX: true))
        }
        guard tabID != nil || peek != nil else { return false }
        let step = driver.receive(HistorySwipeEvents.scroll(
            phase: event.phase, momentumPhase: event.momentumPhase, deltaX: Double(event.scrollingDeltaX),
            deltaY: Double(event.scrollingDeltaY), directionInverted: event.isDirectionInvertedFromDevice))
        if let request = step.startsTracking { track(event, request) }
        if event.momentumPhase == .ended || event.momentumPhase == .cancelled, !driver.isActive {
            tabID = nil; peek = nil; dismissing = false
        }
        return step.consumesEvent
    }

    private func resolveTarget(_ event: NSEvent) {
        controller = nil
        tabID = nil
        peek = nil
        dismissing = false
        guard let window = event.window, let controller = window.windowController as? BrowserWindowController,
              let content = window.contentView,
              let hit = content.hitTest(content.convert(event.locationInWindow, from: nil)) else { return }
        if let card = controller.activePeek as? DocumentPeekController, card.holdsDocument,
           hit === card.document || hit.isDescendant(of: card.document) {
            self.controller = controller
            peek = card
            return
        }
        guard let id = controller.noteVisitTarget(.back), let view = noteView(controller, id),
              hit === view || hit.isDescendant(of: view) else { return }
        self.controller = controller
        tabID = id
    }

    private func noteView(_ controller: BrowserWindowController, _ id: UUID) -> NSView? {
        let editor: NSViewController? = controller.noteEditors[id]?.editor ?? controller.easelEditors[id]?.editor
        guard let editor, editor.isViewLoaded else { return nil }
        let view = editor.view
        return view.window == nil || view.isHiddenOrHasHiddenAncestor ? nil : view
    }

    private static func scrollsHorizontally(_ event: NSEvent) -> Bool {
        guard let content = event.window?.contentView,
              let hit = content.hitTest(content.convert(event.locationInWindow, from: nil)) else { return false }
        let rooms = sequence(first: hit, next: \.superview).compactMap { view -> HistorySwipeTargets.ScrollRoom? in
            if let provider = view as? HistorySwipeScrollRoomProvider { return provider.historySwipeScrollRoom }
            guard let scroll = view as? NSScrollView, let document = scroll.documentView else { return nil }
            return HistorySwipeTargets.ScrollRoom(content: Double(document.frame.width),
                                                  visible: Double(scroll.contentView.bounds.width))
        }
        return HistorySwipeTargets.scrollsHorizontally(rooms)
    }

    private var visit: TabNoteVisit? {
        guard let controller, let tabID, controller.noteVisitTarget(.back) == tabID else { return nil }
        return controller.store.state.tab(tabID)?.noteVisit
    }

    var swipesBetweenPages: Bool { NSEvent.isSwipeTrackingFromScrollEventsEnabled }
    var allowsHistorySwipe: Bool {
        if let peek { return peek.canSwipeDismiss || dismissing }
        return visit?.showsNote == true && controller?.navigationHistory == nil
    }

    func historyEntries(toward direction: HistorySwipeDirection) -> Int {
        guard peek == nil else { return 0 }
        return HistorySwipeNoteStep.entries(toward: direction, visit: visit, pageEntries: 0)
    }

    func dismisses(toward direction: HistorySwipeDirection) -> Bool {
        direction == .back && peek?.canSwipeDismiss == true
    }

    func beginSwipe(_ direction: HistorySwipeDirection) -> Bool {
        peek == nil && allowsHistorySwipe && historyEntries(toward: direction) > 0
    }

    func beginDismissal() -> Bool {
        guard let peek, peek.canSwipeDismiss, peek.beginSwipeDismissal() else { return false }
        dismissing = true
        return true
    }

    func navigate(_ commit: HistorySwipeCommit) -> Bool {
        if peek != nil {
            guard case .dismiss = commit, dismissing else { return false }
            return peek?.commitSwipeDismissal() ?? false
        }
        guard let controller, let tabID, let visit else { return false }
        let direction: HistorySwipeDirection, distance: Int
        switch commit {
        case let .adjacent(toward): direction = toward; distance = 1
        case let .entry(toward, steps): direction = toward; distance = steps
        case .dismiss: return false
        }
        switch HistorySwipeNoteStep.step(toward: direction, distance: distance, visit: visit, pageEntries: 0) {
        case .visit?:
            return controller.stepNoteVisit(tabID, by: HistorySwipeNoteStep.visitOffset(toward: direction, distance: distance))
        case .page?, nil:
            return false
        }
    }

    func endSwipe() {}

    func preloadBack() {}

    func present(_ output: HistorySwipeOutput) {
        if dismissing, let peek {
            switch output {
            case .commit:
                dismissing = false; self.peek = nil
            case .cancel:
                dismissing = false; self.peek = nil
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
            tabID = nil
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
        guard let controller, let tabID, let visit, let container = noteView(controller, tabID)?.superview else { return }
        let frame = noteView(controller, tabID)?.frame ?? container.bounds
        let view = HistorySwipeOverlayView(frame: frame)
        view.autoresizingMask = [.width, .height]
        view.palette = controller.historySwipePalette
        let page = controller.nativePage(forTabID: tabID)
        let rows = { (forward: Bool) in
            controller.noteVisitRows(visit, forward: forward, page: page).map { HistorySwipeOverlayRow(title: $0.title, favicon: $0.icon) }
        }
        let shown = visit.current.map { HistorySwipeOverlayRow(title: $0.title, favicon: BrowserWindowController.noteVisitIcon($0, profile: controller.activeProfileID)) }
            ?? HistorySwipeOverlayRow(title: visit.page.title, favicon: page?.favicon)
        view.setRows(current: shown, back: rows(false), forward: rows(true))
        container.addSubview(view, positioned: .above, relativeTo: noteView(controller, tabID))
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
}
