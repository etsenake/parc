import AppKit
import ParcCore

@MainActor
public protocol NoteTextHost: AnyObject {
    var blockID: NoteBlockID { get }
    var field: NoteTextField { get }
    var textView: NoteTextView { get }
}

@MainActor
open class NoteBlockView: NSView, Sendable {
    package let blockID: NoteBlockID
    package weak var editor: NotePageEditor?
    package private(set) var block: NoteBlock
    private(set) var isBlockSelected = false
    var isReadOnly = false { didSet { if oldValue != isReadOnly { readOnlyDidChange() } } }

    public init(block: NoteBlock, editor: NotePageEditor?) {
        blockID = block.id
        self.block = block
        self.editor = editor
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }

    open func update(_ block: NoteBlock) {
        self.block = block
        needsLayout = true
        needsDisplay = true
    }

    open func measureHeight(width: CGFloat) -> CGFloat { 28 }

    var textHosts: [NoteTextHost] { [] }

    func textHost(for field: NoteTextField) -> NoteTextHost? {
        textHosts.first { $0.field == field }
    }

    open var handleAnchorY: CGFloat { 14 }

    var contentLeadingInset: CGFloat { 0 }

    open func setBlockSelected(_ selected: Bool, animated: Bool) {
        isBlockSelected = selected
    }

    open func readOnlyDidChange() {}

    func themeDidChange() { needsDisplay = true }

    open func focus(at offset: Int?, field: NoteTextField = .body) -> Bool {
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
