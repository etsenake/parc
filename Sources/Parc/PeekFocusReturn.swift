import AppKit

@MainActor
final class PeekFocusReturn {
    private weak var window: NSWindow?
    private weak var responder: NSResponder?
    private weak var borrower: NSResponder?
    private var observation: NSKeyValueObservation?
    private var invalidated = false
    private var consumed = false
    private var lending = false
    private var released = false

    init?(source: NSView) {
        guard let window = source.window, let responder = window.firstResponder,
              let view = responder as? NSView,
              view === source || view.isDescendant(of: source) else { return nil }
        self.window = window; self.responder = responder
        observation = window.observe(\.firstResponder, options: [.new]) { [weak self] window, _ in
            MainActor.assumeIsolated {
                guard let self, !self.lending else { return }
                if let current = window.firstResponder, current !== window,
                   current !== self.responder, current !== self.borrower {
                    self.invalidated = true
                }
            }
        }
    }

    var isActive: Bool { !consumed && !invalidated && responder != nil }

    func cancel() { consumed = true; observation = nil }

    @discardableResult
    func lend(in original: NSWindow, to target: () -> Bool) -> Bool {
        guard !consumed, !invalidated, borrower == nil, window === original, original.attachedSheet == nil,
              let responder else { return false }
        let current = original.firstResponder
        guard current === responder || (released && (current == nil || current === original)) else { return false }
        lending = true
        if !target() || original.firstResponder === responder { original.makeFirstResponder(nil); released = true }
        lending = false
        if let current = original.firstResponder, current !== original, current !== responder {
            borrower = current
        }
        return true
    }

    @discardableResult
    func perform(in original: NSWindow, ownerIsAvailable: () -> Bool,
                 action: (NSResponder?) -> Void) -> Bool {
        guard !consumed else { return false }
        consumed = true; observation = nil
        guard !invalidated, window === original, original.attachedSheet == nil,
              ownerIsAvailable() else { return false }
        let current = original.firstResponder
        guard current == nil || current === original || current === responder
                || current === borrower else { return false }
        action(responder)
        return true
    }
}
