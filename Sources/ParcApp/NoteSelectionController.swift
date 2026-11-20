import AppKit

@MainActor
final class NoteSelectionController {
    unowned let editor: NotePageEditor
    init(editor: NotePageEditor) { self.editor = editor }
    func textViewMouseDown(_ view: NoteTextView, with event: NSEvent) -> Bool { false }
    func canvasMouseDown(_ event: NSEvent) -> Bool { false }
    func apply(_ selection: NotePageSelection) {}
    var selectionBounds: NSRect? { nil }
    func moveCaret(from position: NotePosition, direction: NoteCaretDirection, extend: Bool, x: CGFloat?) -> Bool { false }
    func selectAll() {}
}
