import AppKit

/// Full, selectable persistence feedback for the bounded routing footer.
@MainActor
enum LinkRoutingErrorDetails {
    static func present(_ message: String?, in window: NSWindow?) {
        guard let message, !message.isEmpty, let window, window.isKeyWindow,
              window.attachedSheet == nil else { return }

        let alert = NSAlert()
        alert.messageText = "Air Traffic Control Details"
        alert.addButton(withTitle: "Done")

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        text.string = message
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.font = .systemFont(ofSize: 13)
        text.textContainerInset = NSSize(width: 4, height: 4)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.containerSize = NSSize(width: 360, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.setAccessibilityLabel("Routing error details")
        scroll.documentView = text
        alert.accessoryView = scroll
        alert.beginSheetModal(for: window)
    }
}
