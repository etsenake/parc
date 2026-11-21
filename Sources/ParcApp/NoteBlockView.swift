import AppKit
import ParcCore

@MainActor
protocol NoteTextHost: AnyObject {
    var blockID: NoteBlockID { get }
    var field: NoteTextField { get }
    var textView: NoteTextView { get }
}

@MainActor
class NoteBlockView: NSView {
    let blockID: NoteBlockID
    weak var editor: NotePageEditor?
    private(set) var block: NoteBlock
    private(set) var isBlockSelected = false
    var isReadOnly = false { didSet { if oldValue != isReadOnly { readOnlyDidChange() } } }

    init(block: NoteBlock, editor: NotePageEditor?) {
        blockID = block.id
        self.block = block
        self.editor = editor
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func update(_ block: NoteBlock) {
        self.block = block
        needsLayout = true
        needsDisplay = true
    }

    func measureHeight(width: CGFloat) -> CGFloat { 28 }

    var textHosts: [NoteTextHost] { [] }

    func textHost(for field: NoteTextField) -> NoteTextHost? {
        textHosts.first { $0.field == field }
    }

    var handleAnchorY: CGFloat { 14 }

    var contentLeadingInset: CGFloat { 0 }

    func setBlockSelected(_ selected: Bool, animated: Bool) {
        isBlockSelected = selected
    }

    func readOnlyDidChange() {}

    func themeDidChange() { needsDisplay = true }

    func focus(at offset: Int?, field: NoteTextField = .body) -> Bool {
        guard let host = textHost(for: field) ?? textHosts.first else { return false }
        let view = host.textView
        guard let window = view.window else { return false }
        if let offset { view.selectedOffsets = offset..<offset }
        return window.makeFirstResponder(view)
    }
}

@MainActor
final class NotePlaceholderBlockView: NoteBlockView {
    override func measureHeight(width: CGFloat) -> CGFloat { 30 }
}
