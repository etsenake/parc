import AppKit
import Combine

enum NoteCaretDirection: Hashable { case up, down, left, right }

enum NoteSlashTrigger: Hashable {
    case slash(NotePosition)
    case plus(after: NoteBlockID)
    case turnInto([NoteBlockID])
}

@MainActor
final class NotePageEditor {
    let session: NotePageSession
    let environment: NoteEnvironment
    private(set) var canvas: NotePageCanvasView!
    private(set) var selection: NoteSelectionController!
    private(set) var formatBar: NoteFormatBarController!
    private(set) var slashMenu: NoteSlashMenuController!
    private(set) var handles: NoteBlockHandleController!
    private(set) var find: NoteFindController!
    var onOpenURL: ((URL) -> Void)?
    var onOpenNote: ((URL) -> Void)?
    var onError: ((Error) -> Void)?
    private var subscription: AnyCancellable?

    init(session: NotePageSession, environment: NoteEnvironment) {
        self.session = session
        self.environment = environment
        canvas = NotePageCanvasView(editor: self)
        selection = NoteSelectionController(editor: self)
        formatBar = NoteFormatBarController(editor: self)
        slashMenu = NoteSlashMenuController(editor: self)
        handles = NoteBlockHandleController(editor: self)
        find = NoteFindController(editor: self)
        subscription = session.changes.sink { [weak self] change in self?.sessionDidChange(change) }
        canvas.reload()
    }

    var isReadOnly: Bool { session.isReadOnly || session.page.settings.locked }

    func makeBlockView(for block: NoteBlock) -> NoteBlockView {
        let view = NoteBlockViewFactory.make(block, editor: self)
        view.isReadOnly = isReadOnly
        return view
    }

    func textDidChange(in host: NoteTextHost) {
        let view = host.textView
        let range = view.selectedOffsets
        session.setText(view.noteText, of: (host.blockID, host.field), origin: view,
                        selection: .text(anchor: NotePosition(host.blockID, range.lowerBound, field: host.field),
                                         head: NotePosition(host.blockID, range.upperBound, field: host.field)))
        slashMenu.textDidChange(in: host)
    }

    func textSelectionDidChange(in host: NoteTextHost) {
        let range = host.textView.selectedOffsets
        session.setSelection(.text(anchor: NotePosition(host.blockID, range.lowerBound, field: host.field),
                                   head: NotePosition(host.blockID, range.upperBound, field: host.field)), origin: host.textView)
        formatBar.selectionDidChange()
    }

    func handleTextCommand(_ selector: Selector, in host: NoteTextHost) -> Bool {
        false
    }

    func handleKeyDown(_ event: NSEvent, in host: NoteTextHost?) -> Bool {
        if slashMenu.handleKey(event) { return true }
        if formatBar.handleKey(event) { return true }
        if handles.handleKey(event) { return true }
        return false
    }

    func focus(_ position: NotePosition) {
        canvas.scrollBlockToVisible(position.block)
        _ = canvas.blockView(for: position.block)?.focus(at: position.offset, field: position.field)
    }

    func open(_ url: URL) {
        if url.isFileURL, NoteFileKind(url: url) != nil { onOpenNote?(url) } else { onOpenURL?(url) }
    }

    private func sessionDidChange(_ change: NotePageChange) {
        if change.kind != .selection { canvas.apply(change) }
        selection.apply(session.selection)
        formatBar.selectionDidChange()
        handles.layoutDidChange()
    }
}
