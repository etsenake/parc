import AppKit

@MainActor final class PeekOpenCommand {
    private weak var window: NSWindow?
    private let targetIsAvailable: () -> Bool
    private let execute: () -> Void
    private var consumed = false

    init(window: NSWindow, targetIsAvailable: @escaping () -> Bool, execute: @escaping () -> Void) {
        self.window = window; self.targetIsAvailable = targetIsAvailable; self.execute = execute
    }
    var isAvailable: Bool {
        guard !consumed, let window, window.isVisible, !window.isMiniaturized,
              window.attachedSheet == nil, targetIsAvailable() else { return false }
        if let input = window.firstResponder as? NSTextInputClient, input.hasMarkedText() { return false }
        return true
    }
    @discardableResult func perform() -> Bool {
        guard isAvailable, window?.isKeyWindow == true else { return false }
        consumed = true
        execute()
        return true
    }
}
