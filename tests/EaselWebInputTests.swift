import AppKit

@main
struct EaselWebInputTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        var submissions = 0, closes = 0
        let controller = EaselWebInput(validOwner: { false }, submit: { _, _ in submissions += 1; return true })
        controller.onClose = { closes += 1 }
        let field = controller.view.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
        let editor = NSTextView(frame: .zero)
        editor.setMarkedText("composing", selectedRange: NSRange(location: 9, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        precondition(editor.hasMarkedText())
        precondition(!controller.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        precondition(!controller.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        precondition(closes == 0 && submissions == 0)
        editor.unmarkText()
        precondition(controller.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        controller.cancel(); controller.validate()
        precondition(closes == 1 && submissions == 0)
        let unowned = NSView(frame: .zero)
        precondition(!controller.show(from: unowned))
        let stale = EaselWebInput(draft: .init(mode: .search, text: "example"), validOwner: { false }, submit: { _, _ in submissions += 1; return true })
        stale.onClose = { closes += 1 }
        precondition(stale.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        precondition(closes == 2)
        precondition(submissions == 0)
        let compact = EaselWebInput(submitTitle: "Add Link", allowsSearch: false, validOwner: { false }, submit: { _, _ in false })
        let compactField = compact.view.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
        precondition(compactField.placeholderString == "Paste a URL")
        precondition(compact.view.frame.size == NSSize(width: 368, height: 76))
        precondition(compact.view.subviews.filter { !$0.isHidden }.allSatisfy { compact.view.bounds.contains($0.frame) })
        let visible = compact.view.subviews.filter { !$0.isHidden }.map(\.frame)
        precondition(visible.enumerated().allSatisfy { i, frame in visible.dropFirst(i + 1).allSatisfy { !$0.intersects(frame) } })
        compact.cancel(restoreFocus: false)
        print("EaselWebInput: 14 assertions passed (actual native IME, cancellation, stale owner; no displayed window)")
    }
}
