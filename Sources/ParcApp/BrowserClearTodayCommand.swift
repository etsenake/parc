import AppKit

/// Clear belongs to the captured browser context. The existing retirement owner
/// collects Today tabs only when invoked and owns consent, persistence and Reopen Closed Tab.
@MainActor final class BrowserClearTodayCommand {
    private weak var window: NSWindow?
    private let ownerIsAvailable: () -> Bool
    private let prepare: () -> Void
    private let clear: () -> Void
    private var consumed = false

    init(window: NSWindow, ownerIsAvailable: @escaping () -> Bool,
         prepare: @escaping () -> Void = {}, clear: @escaping () -> Void) {
        self.window = window; self.ownerIsAvailable = ownerIsAvailable
        self.prepare = prepare; self.clear = clear
    }

    private var availableWindow: NSWindow? {
        guard let window, window.isVisible, !window.isMiniaturized,
              window.attachedSheet == nil,
              (window.firstResponder as? NSTextInputClient)?.hasMarkedText() != true,
              ownerIsAvailable() else { return nil }
        return window
    }
    var isAvailable: Bool { !consumed && availableWindow != nil }

    @discardableResult func perform() -> Bool {
        guard !consumed, let original = availableWindow else { return false }
        consumed = true
        prepare()
        guard availableWindow === original, original.isKeyWindow else { return false }
        clear()
        return true // Requested; native retirement can still refuse asynchronously.
    }
}
