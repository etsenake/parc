import AppKit

/// Full, selectable persistence feedback for the bounded routing footer.
@MainActor
enum LinkRoutingErrorDetails {
    static func present(_ message: String?, in window: NSWindow?) {
        guard let message, !message.isEmpty, let window, window.isKeyWindow,
              window.attachedSheet == nil else { return }
        var content = PArcDialog.Content(title: "Air Traffic Control Details", confirm: "Done")
        content.details = message
        PArcDialog.inform(in: window, content)
    }
}
