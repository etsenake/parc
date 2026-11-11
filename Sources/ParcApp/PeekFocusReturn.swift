import AppKit

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
                if let current = window.firstResponder,
                   current !== window, current !== self.responder {
                    self.invalidated = true
                }
            }
        }
    }

    func cancel() { consumed = true; observation = nil }

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
