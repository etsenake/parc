import AppKit

@MainActor
enum EaselInsertKind: String, CaseIterable {
    case image, video, audio, file, pdf, embed, bookmark, codeBlock, equation

    @MainActor enum Group: String, CaseIterable {
        case media, web, code

        var title: String {
            switch self {
            case .media: return "Media"
            case .web: return "Web"
            case .code: return "Code"
            }
        }

        var icon: NoteIcon {
            switch self {
            case .media: return .symbol("photo")
            case .web: return .symbol("globe")
            case .code: return EaselToolPalette.icon(for: .codeBlock)
            }
        }

        var kinds: [EaselInsertKind] { EaselInsertKind.allCases.filter { $0.group == self } }
        var firstKind: EaselInsertKind { kinds[0] }
    }

    var group: Group {
        switch self {
        case .image, .video, .audio, .file, .pdf: return .media
        case .embed, .bookmark: return .web
        case .codeBlock, .equation: return .code
        }
    }

    var itemKind: EaselItemKind? {
        switch self {
        case .image: return .image
        case .video: return .video
        case .audio: return .audio
        case .file: return .file
        case .pdf: return .pdf
        case .embed: return .browser
        case .bookmark: return .link
        case .equation: return .equation
        case .codeBlock: return nil
        }
    }

    private var catalogItem: NoteCatalogItem? {
        switch self {
        case .image: return NoteBlockCatalog.item("image")
        case .video: return NoteBlockCatalog.item("video")
        case .audio: return NoteBlockCatalog.item("audio")
        case .file: return NoteBlockCatalog.item("file")
        case .pdf: return NoteBlockCatalog.item("pdf")
        case .embed: return NoteBlockCatalog.item("embed")
        case .bookmark: return NoteBlockCatalog.item("bookmark")
        case .equation: return NoteBlockCatalog.item("equation")
        case .codeBlock: return nil
        }
    }

    var title: String { catalogItem?.title ?? EaselTool.codeBlock.title }

    var summary: String? { catalogItem?.summary ?? NoteBlockCatalog.item("code")?.summary }

    var keywords: [String] {
        guard let item = catalogItem else { return ["code", "snippet", "monospace", "program"] }
        return item.aliases + item.keywords
    }

    var icon: NoteIcon {
        switch catalogItem?.icon {
        case .symbol(let name): return .symbol(name)
        case .text(let text): return .glyph(text)
        case .swatch, nil: return EaselToolPalette.icon(for: .codeBlock)
        }
    }
}
