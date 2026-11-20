import AppKit

@MainActor
final class NotePageViewController: NSViewController {
    let file: NoteFileSession
    private(set) var editor: NotePageEditor!
    var onTitleChange: ((String) -> Void)?
    var onURLChange: ((URL) -> Void)?
    var onOpenURL: ((URL) -> Void)?
    var onOpenNote: ((URL) -> Void)?

    init(file: NoteFileSession) {
        self.file = file
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        editor = NotePageEditor(session: file.page, environment: file.environment)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = editor.canvas
        view = scroll
    }

    var canAcceptExternalDrop: Bool { !file.page.isReadOnly }

    func focusContent() {}

    func prepareToClose() -> Bool {
        do { try file.flush(); return true } catch { return false }
    }

    func inheritSpaceContentAppearance(_ appearance: NSAppearance?) {
        view.appearance = appearance
    }
}
