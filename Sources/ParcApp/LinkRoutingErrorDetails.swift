import AppKit

@MainActor
enum LinkRoutingErrorDetails {
    static func present(_ message: String?, in window: NSWindow?) {
        guard let message, !message.isEmpty, let window, window.isKeyWindow,
              window.attachedSheet == nil else { return }
        var content = ParcDialog.Content(title: "Air Traffic Control Details", confirm: "Done")
        content.details = message
        ParcDialog.inform(in: window, content)
    }
}
