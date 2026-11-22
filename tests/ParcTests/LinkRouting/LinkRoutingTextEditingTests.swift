import AppKit
import Testing
@testable import Parc
@testable import ParcSettings

@MainActor
struct LinkRoutingTextEditingTests {
    @Test func markedTextDefersSubmission() {
        _ = NSApplication.shared
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        var ended = false
        editor.setMarkedText("候", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        check(editor.hasMarkedText(), "editor holds marked text")
        check(!LinkRoutingTextEditing.handle(#selector(NSResponder.insertNewline(_:)), in: editor) { ended = true },
              "newline during marked text stays with the input method")
        check(!ended, "marked text does not end editing")
        editor.unmarkText()
        check(LinkRoutingTextEditing.handle(#selector(NSResponder.insertNewline(_:)), in: editor) { ended = true },
              "newline submits once text is committed")
        check(ended, "committed newline ends editing")
        ended = false
        check(!LinkRoutingTextEditing.handle(#selector(NSResponder.cancelOperation(_:)), in: editor) { ended = true },
              "cancel is not handled")
        check(!ended, "cancel does not end editing")
    }
}
