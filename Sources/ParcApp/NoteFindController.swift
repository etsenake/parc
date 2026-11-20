import AppKit

@MainActor
final class NoteFindController {
    unowned let editor: NotePageEditor
    init(editor: NotePageEditor) { self.editor = editor }
    var isVisible: Bool { false }
    func show(replacing: Bool = false) {}
    func hide() {}
}
