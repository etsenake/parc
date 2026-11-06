import AppKit

/// A one-use return from an original Peek responder. It does not choose a page,
/// capture a key, or retain a window/control after its owner has gone away.
@MainActor
final class PeekFocusReturn {
    private weak var window: NSWindow?
    private weak var responder: NSResponder?
    private var observation: NSKeyValueObservation?
    private var invalidated = false
    private var consumed = false

    init?(source: NSView) {
        guard let window = source.window, let responder = window.firstResponder,
              let view = responder as? NSView,
              view === source || view.isDescendant(of: source) else { return nil }
        self.window = window; self.responder = responder
        observation = window.observe(\.firstResponder, options: [.new]) { [weak self] window, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // AppKit can temporarily vacate a disappearing view. A new
                // concrete responder, including another Peek control or text
                // editor, owns focus even if it later moves away again.
                if let current = window.firstResponder,
                   current !== window, current !== self.responder {
                    self.invalidated = true
                }
            }
        }
    }

    func cancel() { consumed = true; observation = nil }

    /// The caller revalidates the original page/session and native key/security
    /// gate. Never activates a window, guesses a replacement, or retries later.
    @discardableResult
    func perform(in original: NSWindow, ownerIsAvailable: () -> Bool,
                 action: (NSResponder?) -> Void) -> Bool {
        guard !consumed else { return false }
        consumed = true; observation = nil
        guard !invalidated, window === original, original.attachedSheet == nil,
              ownerIsAvailable() else { return false }
        let current = original.firstResponder
        guard current == nil || current === original || current === responder else { return false }
        action(responder)
        return true
    }
}
