import AppKit

extension NoteTheme {
    nonisolated static let syncedPadding: CGFloat = 8
}

@MainActor
final class NoteSyncedBlockView: NoteBlockView {
    override init(block: NoteBlock, editor: NotePageEditor?) {
        super.init(block: block, editor: editor)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        refreshAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func update(_ block: NoteBlock) {
        super.update(block)
        refreshAccessibility()
    }

    private var scale: CGFloat {
        editor?.session.page.settings.smallText == true ? NoteTheme.smallBodySize / NoteTheme.bodySize : 1
    }

    override func measureHeight(width: CGFloat) -> CGFloat { NoteTheme.syncedPadding * scale }

    override var handleAnchorY: CGFloat { NoteTheme.syncedPadding * scale / 2 }

    override func mouseDown(with event: NSEvent) { NoteBlockPointer.selectBlock(self, with: event) }

    private func refreshAccessibility() {
        setAccessibilityLabel(block.isSyncedCopy ? "Synced copy" : "Synced block")
    }
}
