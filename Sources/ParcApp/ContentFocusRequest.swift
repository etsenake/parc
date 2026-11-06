import AppKit

/// One explicit request to move keyboard focus to the window's selected
/// content once it can take it (docs/navigation.md, focus traversal).
///
///
///
/// selection posts `windowContent` for the selected content, for example
///
/// [D]. Parc's shell selects a page before the engine shows its renderer: the
/// engine reconciles visibility in a later task, and a hidden renderer refuses
///
/// `pendingResponder` does, no longer than its two-second freshness
///
/// wait, after the engine's queued work has run. It has no timer.
///
/// Focus follows the selection only while the content region holds it (the
/// previous page, now parked or still displayed), or nothing does: the
/// sidebar's list stop, a panel or a field outside the content keeps its focus
/// (`holdsContentFocus`). A newer request, a cancellation or focus moving
/// anywhere else ends the request without a fallback.
@MainActor
final class ContentFocusRequest {
    enum Outcome { case focused, waiting, cancelled }

    ///
    static let freshness: TimeInterval = 2

    private weak var window: NSWindow?
    private weak var content: NSView?
    private let deadline: TimeInterval
    private let attempt: () -> Outcome
    private var observer: CFRunLoopObserver?
    private var finished = false

    /// `content` is the window's content region (pages, panes, Peeks);
    /// `attempt` revalidates the original selection and focuses it.
    init(window: NSWindow, content: NSView, attempt: @escaping () -> Outcome) {
        self.window = window; self.content = content; self.attempt = attempt
        deadline = ProcessInfo.processInfo.systemUptime + Self.freshness
    }

    deinit { if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) } }

    /// Whether focus may move to the selected content: nothing holds it, or the
    /// window, a view no longer shown (a parked page) or the content region.
    static func holdsContentFocus(_ responder: NSResponder?, window: NSWindow, content: NSView) -> Bool {
        guard let responder, responder !== window else { return true }
        guard let view = responder as? NSView else { return false }
        if view.window !== window || view.isHiddenOrHasHiddenAncestor { return true }
        return view.isDescendant(of: content)
    }

    /// Whether a presentation change took focus away: nothing or the window
    /// holds it, or the view holding it left this window or is no longer shown
    ///
    ///
    static func lostByPresentation(_ responder: NSResponder?, window: NSWindow) -> Bool {
        guard let responder, responder !== window else { return true }
        guard let view = responder as? NSView else { return false }
        return !SavedFocus.mayReturn(to: view, in: window)
    }

    /// Whether a command bar's close returns focus to the responder it saved.
    ///
    ///
    /// so the saved responder returns only inside that target, keeping its
    /// caret and native selection; elsewhere the owner focuses the target.
    static func returnsToSaved(_ view: NSView, find: NSView?, content: NSView?) -> Bool {
        if let find { return view === find || view.isDescendant(of: find) }
        guard let content else { return false }
        return view.isDescendant(of: content)
    }

    /// Attempts now and, while the content is not ready, again whenever the
    /// main run loop is about to wait.
    func start() {
        guard step() == .waiting, !finished else { return }
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 0) {
            [weak self] _, _ in MainActor.assumeIsolated { _ = self?.step() }
        }
        self.observer = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    func cancel() { finish() }

    private func step() -> Outcome {
        guard !finished else { return .cancelled }
        guard let window, let content, window.isKeyWindow, window.attachedSheet == nil,
              ProcessInfo.processInfo.systemUptime < deadline,
              Self.holdsContentFocus(window.firstResponder, window: window, content: content) else {
            finish(); return .cancelled
        }
        let outcome = attempt()
        if outcome != .waiting { finish() }
        return outcome
    }

    private func finish() {
        finished = true
        if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes); self.observer = nil }
    }
}
