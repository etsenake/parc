import AppKit

/// A menu invocation retains the original physical window, not the next front
/// browser. Closing still belongs to NSWindow's existing asynchronous delegate.
@MainActor final class BrowserWindowCloseCommand {
    private weak var window: NSWindow?
    private let ownerIsAvailable: () -> Bool
    private let prepare: () -> Void
    private var consumed = false

    init(window: NSWindow, ownerIsAvailable: @escaping () -> Bool,
         prepare: @escaping () -> Void = {}) {
        self.window = window; self.ownerIsAvailable = ownerIsAvailable; self.prepare = prepare
    }

    private var availableWindow: NSWindow? {
        guard let window, window.isVisible, !window.isMiniaturized,
              window.styleMask.contains(.closable), window.attachedSheet == nil,
              ownerIsAvailable() else { return nil }
        return window
    }
    var isAvailable: Bool { !consumed && availableWindow != nil }

    @discardableResult
    func perform(_ sender: Any?) -> Bool {
        guard !consumed, let original = availableWindow else { return false }
        consumed = true
        // The owned command panel may need to return focus first. Revalidate
        // after dismissal; never activate or substitute a different window.
        prepare()
        guard availableWindow === original, original.isKeyWindow else { return false }
        original.performClose(sender)
        // This means requested, not closed: the delegate may refuse or await
        // native beforeunload. A new invocation is needed after a refusal.
        return true
    }
}
