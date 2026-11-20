import AppKit

@MainActor
final class NoteBlockHandleController {
    unowned let editor: NotePageEditor
    init(editor: NotePageEditor) { self.editor = editor }
    func pointerMoved(to point: NSPoint) {}
    func pointerExited() {}
    func layoutDidChange() {}
    func handleKey(_ event: NSEvent) -> Bool { false }
}
