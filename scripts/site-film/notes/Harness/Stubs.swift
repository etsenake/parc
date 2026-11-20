import AppKit

extension BrowserWindowController {
    func showToast(_ content: ParcToastContent) {}
}

@MainActor protocol EmbeddedPageSurface: NSView {}

@MainActor final class NoteEmbedBlockView: NoteBlockView {
    override func measureHeight(width: CGFloat) -> CGFloat { CGFloat(NoteEmbedSizing.height(of: block.props)) + 38 }
}
