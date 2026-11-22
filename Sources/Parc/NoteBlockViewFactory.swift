import AppKit
import ParcCore

@MainActor
protocol NoteBoardProviding {
    func makeBlock(_ block: NoteBlock, editor: NotePageEditor) -> NoteBlockView
    func host(for editor: NotePageEditor) -> NoteBoardHost?
    func pages(for editor: NotePageEditor) -> NoteBoardPages?
}

@MainActor
protocol NoteBoardHost: AnyObject {
    var directory: URL { get }
    func canOpen(_ id: UUID) -> Bool
    func snapshot(_ block: NoteBlock) -> Data?
    func adopt(for editor: NotePageEditor)
}

@MainActor
protocol NoteBoardPages: AnyObject {
    func wants(_ key: UUID, url: String, variant: EmbeddedPageFingerprint?) -> Bool?
    func fingerprint(_ key: UUID) -> String?
    func block(for key: UUID) -> NoteBlockID?
    func recordNavigation(_ url: URL, for key: UUID, expectedURL: String) throws
}

protocol NoteBoardSurface: AnyObject {}

@MainActor
enum NoteBlockViewFactory {
    static var boards: NoteBoardProviding?

    static func make(_ block: NoteBlock, editor: NotePageEditor) -> NoteBlockView {
        switch block.kind {
        case .paragraph, .heading, .bulletedItem, .numberedItem, .todo, .toggle, .quote, .callout:
            return NoteTextBlockView(block: block, editor: editor)
        case .code: return NoteCodeBlockView(block: block, editor: editor)
        case .equation: return NoteEquationBlockView(block: block, editor: editor)
        case .divider: return NoteDividerBlockView(block: block, editor: editor)
        case .tableOfContents: return NoteTOCBlockView(block: block, editor: editor)
        case .breadcrumb: return NoteBreadcrumbBlockView(block: block, editor: editor)
        case .html, .raw: return NoteRawBlockView(block: block, editor: editor)
        case .table: return NoteTableBlockView(block: block, editor: editor)
        case .image, .video, .audio, .file, .pdf: return NoteMediaBlockView(block: block, editor: editor)
        case .bookmark: return NoteBookmarkBlockView(block: block, editor: editor)
        case .embed: return NoteEmbedBlockView(block: block, editor: editor)
        case .easel:
            guard let boards else { preconditionFailure("A board provider is required to render an Easel block") }
            return boards.makeBlock(block, editor: editor)
        case .pageLink: return NotePageLinkBlockView(block: block, editor: editor)
        case .columns, .column: return NoteColumnsBlockView(block: block, editor: editor)
        case .synced: return NoteSyncedBlockView(block: block, editor: editor)
        case .button: return NoteButtonBlockView(block: block, editor: editor)
        }
    }
}
