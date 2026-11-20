import Foundation

struct NoteBlockStyle: Hashable {
    var kind: NoteBlockKind
    var level = 1
    var toggleable = false

    init(_ kind: NoteBlockKind, level: Int = 1, toggleable: Bool = false) {
        self.kind = kind
        self.level = level
        self.toggleable = toggleable
    }

    init(of block: NoteBlock) {
        kind = block.kind
        level = block.kind == .heading ? block.props.level : 1
        toggleable = block.kind == .heading && block.props.toggleable
    }

    func configure(_ props: inout NoteBlockProps) {
        guard kind == .heading else { return }
        props.level = level
        props.toggleable = toggleable
    }
}

enum NoteActionIcon: Hashable {
    case symbol(String)
    case glyph(String)
    case textColor(NoteColor?)
    case backgroundColor(NoteColor?)
}

enum NoteBlockAction: Hashable {
    case delete
    case duplicate
    case turnInto(NoteBlockStyle)
    case turnIntoColumns(Int)
    case color(NoteColorStyle?)
    case copyLink
    case moveTo
    case moveToNote(URL)
    case language(String)
    case wrapCode
    case diagramMode(NoteDiagramMode)
    case align(NoteAlignment)
    case download
    case viewOriginal
    case fullScreen
    case copyOriginalLink
    case tableItem(String)
}

struct NoteBlockMenuEntry: Hashable {
    var id: String
    var title: String
    var icon: NoteActionIcon?
    var shortcut: String?
    var subtitle: String?
    var keywords: [String] = []
    var group = 0
    var section: String?
    var isChecked = false
    var isEnabled = true
    var isDestructive = false
    var action: NoteBlockAction?
    var children: [NoteBlockMenuEntry] = []

    var hasSubmenu: Bool { !children.isEmpty || action == .moveTo }
}

struct NoteBlockMenuContext {
    var blocks: [NoteBlock]
    var isReadOnly = false
    var canMoveToNotes = false
    var supportsBlockLinks = false
    var tableEntries: [NoteBlockMenuEntry] = []
    var columnLimit = 0
}

enum NoteBlockMenuModel {
    static let searchPlaceholder = "Search actions…"
    static let moveSearchPlaceholder = "Move to which note?"
    static let turnIntoTitle = "Turn Into"
    static let colorTitle = "Color"
    static let languageTitle = "Language"
    static let diagramViewTitle = "View"
    static let alignmentTitle = "Alignment"
    static let moveTitle = "Move to"

    static let turnIntoStyles: [(style: NoteBlockStyle, title: String, icon: NoteActionIcon, keywords: [String])] = [
        (NoteBlockStyle(.paragraph), "Text", .symbol("textformat"), ["paragraph", "plain"]),
        (NoteBlockStyle(.heading, level: 1), "Heading 1", .glyph("H1"), ["h1", "title", "big"]),
        (NoteBlockStyle(.heading, level: 2), "Heading 2", .glyph("H2"), ["h2", "subtitle"]),
        (NoteBlockStyle(.heading, level: 3), "Heading 3", .glyph("H3"), ["h3"]),
        (NoteBlockStyle(.heading, level: 4), "Heading 4", .glyph("H4"), ["h4"]),
        (NoteBlockStyle(.bulletedItem), "Bulleted List", .symbol("list.bullet"), ["bullet", "unordered", "ul"]),
        (NoteBlockStyle(.numberedItem), "Numbered List", .symbol("list.number"), ["ordered", "ol", "number"]),
        (NoteBlockStyle(.todo), "To-do List", .symbol("checkmark.square"), ["todo", "checkbox", "task", "check"]),
        (NoteBlockStyle(.toggle), "Toggle List", .symbol("arrowtriangle.right.fill"), ["collapse", "details", "disclosure"]),
        (NoteBlockStyle(.code), "Code", .symbol("chevron.left.forwardslash.chevron.right"), ["snippet", "pre", "monospace"]),
        (NoteBlockStyle(.quote), "Quote", .symbol("text.quote"), ["blockquote", "citation"]),
        (NoteBlockStyle(.callout), "Callout", .symbol("lightbulb"), ["note", "tip", "warning", "alert", "box"]),
        (NoteBlockStyle(.equation), "Block Equation", .symbol("function"), ["math", "latex", "tex", "formula"]),
        (NoteBlockStyle(.heading, level: 1, toggleable: true), "Toggle Heading 1", .glyph("▸H1"), ["collapse", "h1"]),
        (NoteBlockStyle(.heading, level: 2, toggleable: true), "Toggle Heading 2", .glyph("▸H2"), ["collapse", "h2"]),
        (NoteBlockStyle(.heading, level: 3, toggleable: true), "Toggle Heading 3", .glyph("▸H3"), ["collapse", "h3"]),
        (NoteBlockStyle(.heading, level: 4, toggleable: true), "Toggle Heading 4", .glyph("▸H4"), ["collapse", "h4"]),
    ]

    static let languages: [(id: String, title: String)] = [
        ("", "Plain Text"), ("bash", "Bash"), ("c", "C"), ("cpp", "C++"), ("csharp", "C#"), ("css", "CSS"),
        ("diff", "Diff"), ("go", "Go"), ("graphql", "GraphQL"), ("html", "HTML"), ("java", "Java"),
        ("javascript", "JavaScript"), ("json", "JSON"), ("kotlin", "Kotlin"), ("latex", "LaTeX"), ("lua", "Lua"),
        ("markdown", "Markdown"), ("mermaid", "Mermaid"), ("objectivec", "Objective-C"), ("php", "PHP"),
        ("python", "Python"), ("r", "R"), ("ruby", "Ruby"), ("rust", "Rust"), ("shell", "Shell"), ("sql", "SQL"),
        ("swift", "Swift"), ("toml", "TOML"), ("typescript", "TypeScript"), ("xml", "XML"), ("yaml", "YAML"),
    ]

    static func turnable(_ block: NoteBlock) -> Bool {
        block.kind.hasRichText || block.kind == .code || block.kind == .equation
    }

    static func showsPDF(_ block: NoteBlock) -> Bool {
        guard block.kind == .pdf || block.kind == .file else { return false }
        guard let source = block.props.source, !source.isEmpty else { return block.kind == .pdf }
        return NoteMDMedia.pathExtension(source) == "pdf" || block.kind == .pdf
    }

    static func pdfTurnIntoEntries(for blocks: [NoteBlock]) -> [NoteBlockMenuEntry] {
        let kinds = Set(blocks.map(\.kind))
        return [
            NoteBlockMenuEntry(id: "turn.pdf", title: "PDF", icon: .symbol("doc.richtext"), keywords: ["inline", "viewer", "read"],
                               section: turnIntoTitle, isChecked: kinds == [.pdf], action: .turnInto(NoteBlockStyle(.pdf))),
            NoteBlockMenuEntry(id: "turn.file", title: "File", icon: .symbol("paperclip"), keywords: ["attachment", "row"],
                               section: turnIntoTitle, isChecked: kinds == [.file], action: .turnInto(NoteBlockStyle(.file))),
        ]
    }

    static func linkable(_ block: NoteBlock) -> Bool {
        switch block.kind {
        case .html, .raw, .column, .columns: return false
        default: return true
        }
    }

    static func colorable(_ block: NoteBlock) -> Bool {
        block.kind.hasRichText || block.kind == .tableOfContents
    }

    static func languageTitle(for id: String) -> String {
        let key = id.lowercased()
        return languages.first { $0.id == key }?.title ?? (id.isEmpty ? "Plain Text" : id)
    }

    static func entries(for context: NoteBlockMenuContext) -> [NoteBlockMenuEntry] {
        let blocks = context.blocks
        guard let first = blocks.first else { return [] }
        let sameKind = blocks.allSatisfy { $0.kind == first.kind }
        let single = blocks.count == 1
        let editable = !context.isReadOnly
        var result: [NoteBlockMenuEntry] = []
        if editable {
            result.append(NoteBlockMenuEntry(id: "delete", title: "Delete", icon: .symbol("trash"), shortcut: "⌫",
                                             keywords: ["remove", "erase", "trash"], group: 0, isDestructive: true, action: .delete))
            result.append(NoteBlockMenuEntry(id: "duplicate", title: "Duplicate", icon: .symbol("plus.square.on.square"), shortcut: "⌘D",
                                             keywords: ["copy", "clone"], group: 0, action: .duplicate))
            let restyles = blocks.allSatisfy(turnable)
            let media = !restyles && blocks.allSatisfy(showsPDF) ? pdfTurnIntoEntries(for: blocks) : []
            if restyles || !media.isEmpty || context.columnLimit >= 2 {
                result.append(NoteBlockMenuEntry(id: "turn", title: turnIntoTitle, icon: .symbol("arrow.triangle.2.circlepath"),
                                                 keywords: ["convert", "change", "type"] + (media.isEmpty ? [] : ["pdf", "file"]), group: 0,
                                                 children: media + turnIntoEntries(for: blocks, columns: context.columnLimit, restyles: restyles)))
            }
        }
        if sameKind { result += kindEntries(for: blocks, kind: first.kind, editable: editable, single: single) }
        if sameKind, first.kind == .table, editable { result += context.tableEntries.map { entry in var copy = entry; copy.group = 1; return copy } }
        if single && context.supportsBlockLinks && linkable(first) {
            result.append(NoteBlockMenuEntry(id: "link", title: "Copy Link to Block", icon: .symbol("link"), shortcut: "⌃⌘L",
                                             keywords: ["url", "anchor", "share"], group: 2, action: .copyLink))
        }
        if editable && context.canMoveToNotes {
            result.append(NoteBlockMenuEntry(id: "move", title: moveTitle, icon: .symbol("arrow.turn.up.right"), shortcut: "⇧⌘P",
                                             keywords: ["send", "transfer", "another note"], group: 3, action: .moveTo))
        }
        if editable && blocks.allSatisfy(colorable) {
            result.append(NoteBlockMenuEntry(id: "color", title: colorTitle, icon: .symbol("paintpalette"),
                                             keywords: ["colour", "highlight", "background", "paint"], group: 4,
                                             children: colorEntries(current: commonColor(of: blocks))))
        }
        return result
    }

    static func turnIntoEntries(for blocks: [NoteBlock], columns: Int = 0, restyles: Bool = true) -> [NoteBlockMenuEntry] {
        let current = Set(blocks.map(NoteBlockStyle.init(of:)))
        let styles = restyles ? turnIntoStyles.map { option in
            NoteBlockMenuEntry(id: "turn." + styleKey(option.style), title: option.title, icon: option.icon,
                               keywords: option.keywords, section: turnIntoTitle,
                               isChecked: current.count == 1 && current.contains(option.style), action: .turnInto(option.style))
        } : []
        return styles + columnEntries(limit: columns)
    }

    static func columnEntries(limit: Int) -> [NoteBlockMenuEntry] {
        guard limit >= 2 else { return [] }
        return (2...min(limit, NotePageSession.maximumColumns)).map { count in
            NoteBlockMenuEntry(id: "turn.columns\(count)", title: "\(count) Columns", icon: .symbol("rectangle.split.\(min(count, 3))x1"),
                               keywords: ["columns", "layout", "side by side", "split"], section: turnIntoTitle,
                               action: .turnIntoColumns(count))
        }
    }

    static func colorEntries(current: NoteColorStyle??) -> [NoteBlockMenuEntry] {
        let textSection = "Text Color", backgroundSection = "Background Color"
        var result = [NoteBlockMenuEntry(id: "color.text.default", title: "Default Text", icon: .textColor(nil),
                                         keywords: ["clear", "reset", "none"], section: textSection,
                                         isChecked: current == .some(nil), action: .color(nil))]
        for color in NoteColor.allCases {
            let name = color.rawValue.capitalized
            result.append(NoteBlockMenuEntry(id: "color.text." + color.rawValue, title: name + " Text", icon: .textColor(color),
                                             keywords: [color.rawValue, "ink", "font"], section: textSection,
                                             isChecked: current == .some(.text(color)), action: .color(.text(color))))
        }
        result.append(NoteBlockMenuEntry(id: "color.background.default", title: "Default Background", icon: .backgroundColor(nil),
                                         keywords: ["clear", "reset", "none"], section: backgroundSection, action: .color(nil)))
        for color in NoteColor.allCases {
            let name = color.rawValue.capitalized
            result.append(NoteBlockMenuEntry(id: "color.background." + color.rawValue, title: name + " Background",
                                             icon: .backgroundColor(color), keywords: [color.rawValue, "highlight", "fill"],
                                             section: backgroundSection, isChecked: current == .some(.background(color)),
                                             action: .color(.background(color))))
        }
        return result
    }

    static func languageEntries(current: String?) -> [NoteBlockMenuEntry] {
        languages.map { language in
            NoteBlockMenuEntry(id: "language." + (language.id.isEmpty ? "plain" : language.id), title: language.title,
                               keywords: [language.id], section: languageTitle,
                               isChecked: current.map { $0.lowercased() == language.id } ?? false, action: .language(language.id))
        }
    }

    static func diagramModeEntries(current: NoteDiagramMode?) -> [NoteBlockMenuEntry] {
        NoteDiagramMode.allCases.map { mode in
            let symbol: String
            switch mode {
            case .code: symbol = "chevron.left.forwardslash.chevron.right"
            case .preview: symbol = "eye"
            case .split: symbol = "rectangle.split.1x2"
            }
            return NoteBlockMenuEntry(id: "diagramView." + mode.rawValue, title: mode.title, icon: .symbol(symbol),
                                      keywords: ["view", "diagram", "mermaid"], section: diagramViewTitle,
                                      isChecked: current == mode, action: .diagramMode(mode))
        }
    }

    static func alignmentEntries(current: NoteAlignment?) -> [NoteBlockMenuEntry] {
        let options: [(NoteAlignment, String, String)] = [(.left, "Left", "text.alignleft"), (.center, "Center", "text.aligncenter"),
                                                         (.right, "Right", "text.alignright")]
        return options.map { alignment, title, symbol in
            NoteBlockMenuEntry(id: "align." + alignment.rawValue, title: title, icon: .symbol(symbol), keywords: ["align", "centre"],
                               section: alignmentTitle, isChecked: current == alignment, action: .align(alignment))
        }
    }

    private static func kindEntries(for blocks: [NoteBlock], kind: NoteBlockKind, editable: Bool, single: Bool) -> [NoteBlockMenuEntry] {
        var result: [NoteBlockMenuEntry] = []
        let block = blocks[0]
        switch kind {
        case .code where editable:
            let languages = Set(blocks.map { $0.props.language.lowercased() })
            let current = languages.count == 1 ? languages.first : nil
            result.append(NoteBlockMenuEntry(id: "language", title: languageTitle, icon: .symbol("curlybraces"),
                                             subtitle: current.map { languageTitle(for: $0) }, keywords: ["syntax", "highlight"],
                                             group: 1, children: languageEntries(current: current)))
            result.append(NoteBlockMenuEntry(id: "wrap", title: "Wrap Code", icon: .symbol("text.word.spacing"),
                                             keywords: ["soft wrap", "lines"], group: 1,
                                             isChecked: blocks.allSatisfy(\.props.wrap), action: .wrapCode))
            if blocks.allSatisfy(NoteMermaid.isDiagram) {
                let modes = Set(blocks.map(NoteMermaid.storedMode(of:)))
                let current = modes.count == 1 ? modes.first : nil
                result.append(NoteBlockMenuEntry(id: "diagramView", title: diagramViewTitle, icon: .symbol("rectangle.split.1x2"),
                                                 subtitle: current?.title, keywords: ["mermaid", "diagram", "preview", "split", "code"],
                                                 group: 1, children: diagramModeEntries(current: current)))
            }
        case .image, .video, .audio, .file, .pdf:
            if editable && (kind == .image || kind == .pdf) {
                let alignments = Set(blocks.map(\.props.alignment))
                result.append(NoteBlockMenuEntry(id: "align", title: alignmentTitle, icon: .symbol("text.aligncenter"),
                                                 keywords: ["left", "right", "center", "centre"], group: 1,
                                                 children: alignmentEntries(current: alignments.count == 1 ? alignments.first : nil)))
            }
            if single && block.props.source?.isEmpty == false {
                result.append(NoteBlockMenuEntry(id: "download", title: "Download", icon: .symbol("arrow.down.circle"),
                                                 keywords: ["save", "export"], group: 1, action: .download))
                result.append(NoteBlockMenuEntry(id: "original", title: "View Original", icon: .symbol("arrow.up.forward.square"),
                                                 keywords: ["open", "source", "full size"], group: 1, action: .viewOriginal))
                if kind == .pdf {
                    result.append(NoteBlockMenuEntry(id: "fullScreen", title: "Full Screen", icon: .symbol("arrow.up.left.and.arrow.down.right"),
                                                     shortcut: "⎵", keywords: ["expand", "present", "read", "big"], group: 1, action: .fullScreen))
                }
            }
        case .bookmark, .embed:
            if single && block.props.source?.isEmpty == false {
                result.append(NoteBlockMenuEntry(id: "copyOriginal", title: "Copy Link to Original", icon: .symbol("link"),
                                                 keywords: ["url", "address"], group: 1, action: .copyOriginalLink))
                result.append(NoteBlockMenuEntry(id: "original", title: "View Original", icon: .symbol("arrow.up.forward.square"),
                                                 keywords: ["open", "visit"], group: 1, action: .viewOriginal))
            }
        default:
            break
        }
        return result
    }

    static func commonColor(of blocks: [NoteBlock]) -> NoteColorStyle?? {
        guard let first = blocks.first else { return .none }
        return blocks.allSatisfy { $0.color == first.color } ? .some(first.color) : .none
    }

    static func styleKey(_ style: NoteBlockStyle) -> String {
        switch style.kind {
        case .heading: return (style.toggleable ? "toggleHeading" : "heading") + String(style.level)
        default: return style.kind.rawValue
        }
    }

    static func filter(_ entries: [NoteBlockMenuEntry], query: String) -> [NoteBlockMenuEntry] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return entries }
        var result: [NoteBlockMenuEntry] = []
        for entry in entries {
            if entry.action != nil, entry.isEnabled, matches(entry, needle) {
                var flat = entry
                flat.section = nil
                result.append(flat)
            }
        }
        for entry in entries where !entry.children.isEmpty {
            let parentMatches = matches(entry, needle)
            for child in entry.children where child.isEnabled && (parentMatches || matches(child, needle)) {
                var flat = child
                flat.section = entry.title
                result.append(flat)
            }
        }
        return result
    }

    static func matches(_ entry: NoteBlockMenuEntry, _ needle: String) -> Bool {
        let haystacks = [entry.title] + entry.keywords
        return haystacks.contains { candidate in
            let value = normalized(candidate)
            if value.hasPrefix(needle) { return true }
            return value.split(whereSeparator: { $0 == " " || $0 == "-" }).contains { $0.hasPrefix(needle) }
        }
    }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func footer(for blocks: [NoteBlock]) -> String? {
        let stats = NotePageStats(page: NotePage(blocks: blocks))
        guard stats.words > 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let count = formatter.string(from: NSNumber(value: stats.characters)) ?? String(stats.characters)
        return stats.wordLabel + " · " + (stats.characters == 1 ? "1 character" : count + " characters")
    }
}
