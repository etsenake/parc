import AppKit

@MainActor
final class NoteSlashMenuController {
    unowned let editor: NotePageEditor
    init(editor: NotePageEditor) { self.editor = editor }
    var isOpen: Bool { false }
    func open(_ trigger: NoteSlashTrigger) {}
    func textDidChange(in host: NoteTextHost) {}
    func handleKey(_ event: NSEvent) -> Bool { false }
    func dismiss(animated: Bool = true) {}
}
