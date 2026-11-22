import AppKit

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
        prepare()
        guard availableWindow === original, original.isKeyWindow else { return false }
        original.performClose(sender)
        return true
    }
}
