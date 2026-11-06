import AppKit

@MainActor
enum LinkRoutingTextEditing {
    /// Return submits the focused rule only after an input method has finished
    /// its marked-text composition. Other commands remain AppKit's to handle.
    static func handle(_ command: Selector, in textView: NSTextView, endEditing: () -> Void) -> Bool {
        guard command == #selector(NSResponder.insertNewline(_:)), !textView.hasMarkedText() else { return false }
        endEditing()
        return true
    }
}
