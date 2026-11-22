import AppKit
import ParcCore

@MainActor final class PeekOpenCommand {
    private weak var window: NSWindow?
    private let targetIsAvailable: () -> Bool
    private let execute: () -> Void
    private var consumed = false

    static func applyDestination(_ space: BrowserSpace, to item: NSMenuItem) {
        item.title = "Open in " + space.name
        let icon = (space.customIcon?.image(size: 12)
            ?? NSImage(systemSymbolName: space.symbol, accessibilityDescription: nil))?.copy() as? NSImage
        icon?.size = NSSize(width: 12, height: 12)
        item.showImage(icon)
    }

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
