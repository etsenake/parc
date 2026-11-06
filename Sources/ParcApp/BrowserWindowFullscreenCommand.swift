import AppKit

/// The original browser window owns the native action and its later fullscreen
/// notifications. A menu request is neither a page request nor a completion.
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
        // AppKit supplies the actual Enter/Exit title, capability and native
        // transition availability. Do not infer success or maintain a second
        // fullscreen state from a menu invocation.
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
        return true // Dispatched only; actual notifications remain authoritative.
    }
}
