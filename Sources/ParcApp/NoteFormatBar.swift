import AppKit

@MainActor
final class NoteFormatBarController {
    unowned let editor: NotePageEditor
    init(editor: NotePageEditor) { self.editor = editor }
    var isVisible: Bool { false }
    func selectionDidChange() {}
    func dismiss(animated: Bool = true) {}
    func handleKey(_ event: NSEvent) -> Bool { false }
}
