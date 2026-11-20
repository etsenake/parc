import AppKit

@MainActor
enum NoteBlockViewFactory {
    static func make(_ block: NoteBlock, editor: NotePageEditor) -> NoteBlockView {
        switch block.kind {
        case .paragraph, .heading, .bulletedItem, .numberedItem, .todo, .toggle, .quote, .callout:
            return NoteTextBlockView(block: block, editor: editor)
        case .code: return NoteCodeBlockView(block: block, editor: editor)
        case .equation: return NoteEquationBlockView(block: block, editor: editor)
        case .divider: return NoteDividerBlockView(block: block, editor: editor)
        case .tableOfContents: return NoteTOCBlockView(block: block, editor: editor)
        case .html, .raw: return NoteRawBlockView(block: block, editor: editor)
        case .table: return NoteTableBlockView(block: block, editor: editor)
        case .image, .video, .audio, .file, .pdf: return NoteMediaBlockView(block: block, editor: editor)
        case .bookmark: return NoteBookmarkBlockView(block: block, editor: editor)
        case .embed: return NoteEmbedBlockView(block: block, editor: editor)
        case .pageLink: return NotePageLinkBlockView(block: block, editor: editor)
        case .columns, .column: return NoteColumnsBlockView(block: block, editor: editor)
        case .synced: return NoteSyncedBlockView(block: block, editor: editor)
        }
    }
}
