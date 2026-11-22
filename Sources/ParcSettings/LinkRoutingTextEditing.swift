import AppKit

@MainActor
enum LinkRoutingTextEditing {
    static func handle(_ command: Selector, in textView: NSTextView, endEditing: () -> Void) -> Bool {
        guard command == #selector(NSResponder.insertNewline(_:)), !textView.hasMarkedText() else { return false }
        endEditing()
        return true
    }
}
