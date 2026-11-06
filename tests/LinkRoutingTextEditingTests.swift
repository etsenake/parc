import AppKit

@main
struct LinkRoutingTextEditingTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        var ended = false
        editor.setMarkedText("候", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        precondition(editor.hasMarkedText())
        precondition(!LinkRoutingTextEditing.handle(#selector(NSResponder.insertNewline(_:)), in: editor) { ended = true })
        precondition(!ended)
        editor.unmarkText()
        precondition(LinkRoutingTextEditing.handle(#selector(NSResponder.insertNewline(_:)), in: editor) { ended = true })
        precondition(ended)
        ended = false
        precondition(!LinkRoutingTextEditing.handle(#selector(NSResponder.cancelOperation(_:)), in: editor) { ended = true })
        precondition(!ended)
        print("Link routing marked-text submission passed")
    }
}
