import AppKit

@MainActor final class BrowserExitCommand {
    private weak var window: NSWindow?
    private let targetIsAvailable: () -> Bool
    private let prepare: () -> Void
    private let execute: () -> Bool
    private var consumed = false

    init(window: NSWindow, targetIsAvailable: @escaping () -> Bool,
         prepare: @escaping () -> Void = {}, execute: @escaping () -> Bool) {
        self.window = window; self.targetIsAvailable = targetIsAvailable
        self.prepare = prepare; self.execute = execute
    }
    private var availableWindow: NSWindow? {
        guard let window, window.isVisible, !window.isMiniaturized,
              window.attachedSheet == nil, targetIsAvailable() else { return nil }
        if let input = window.firstResponder as? NSTextInputClient, input.hasMarkedText() { return nil }
        return window
    }
    var isAvailable: Bool { !consumed && availableWindow != nil }
    @discardableResult func perform() -> Bool {
        guard isAvailable, let original = availableWindow else { return false }
        consumed = true
        prepare()
        guard availableWindow === original, original.isKeyWindow else { return false }
        return execute()
    }
}
