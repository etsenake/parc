import AppKit

@MainActor final class BrowserWindowFullscreenCommand {
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
              window.attachedSheet == nil, ownerIsAvailable() else { return nil }
        return window
    }

    func validate(_ item: NSMenuItem) -> Bool {
        guard !consumed, item.action == #selector(NSWindow.toggleFullScreen(_:)),
              let original = availableWindow else { return false }
        return original.validateMenuItem(item)
    }

    @discardableResult
    func perform(_ sender: Any?) -> Bool {
        let validation = NSMenuItem(title: "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "")
        guard let original = availableWindow, validate(validation) else { return false }
        consumed = true
        prepare()
        guard availableWindow === original, original.isKeyWindow,
              original.validateMenuItem(validation) else { return false }
        original.toggleFullScreen(sender)
        return true
    }
}
