import AppKit

@MainActor
final class ContentFocusRequest {
    enum Outcome { case focused, waiting, cancelled }

    static let freshness: TimeInterval = 2

    private weak var window: NSWindow?
    private weak var content: NSView?
    private let deadline: TimeInterval
    private let attempt: () -> Outcome
    private var observer: CFRunLoopObserver?
    private var finished = false

    init(window: NSWindow, content: NSView, attempt: @escaping () -> Outcome) {
        self.window = window; self.content = content; self.attempt = attempt
        deadline = ProcessInfo.processInfo.systemUptime + Self.freshness
    }

    deinit { if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) } }

    static func holdsContentFocus(_ responder: NSResponder?, window: NSWindow, content: NSView) -> Bool {
        guard let responder, responder !== window else { return true }
        guard let view = responder as? NSView else { return false }
        if view.window !== window || view.isHiddenOrHasHiddenAncestor { return true }
        return view.isDescendant(of: content)
    }

    static func lostByPresentation(_ responder: NSResponder?, window: NSWindow) -> Bool {
        guard let responder, responder !== window else { return true }
        guard let view = responder as? NSView else { return false }
        return !SavedFocus.mayReturn(to: view, in: window)
    }

    static func returnsToSaved(_ view: NSView, find: NSView?, content: NSView?) -> Bool {
        if let find { return view === find || view.isDescendant(of: find) }
        guard let content else { return false }
        return view.isDescendant(of: content)
    }

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
