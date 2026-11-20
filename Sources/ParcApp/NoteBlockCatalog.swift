import Foundation

enum NoteCatalogSection: String, CaseIterable, Hashable {
    case basic, media, advanced, inline, colors, actions

    var title: String {
        switch self {
        case .basic: return "Basic blocks"
        case .media: return "Media"
        case .advanced: return "Advanced blocks"
        case .inline: return "Inline"
        case .colors: return "Colors"
        case .actions: return "Actions"
        }
    }

    var needsQuery: Bool { self == .colors || self == .actions }
}

enum NoteCatalogBlock: Hashable {
    case text, heading(Int), toggleHeading(Int), bulleted, numbered, todo, toggle, quote, callout, divider
    case newNote, linkToNote, table
    case image, video, audio, file, bookmark, embed
    case tableOfContents, equation, code, columns(Int)

    static let turnIntoTargets: [NoteCatalogBlock] = [
        .text, .heading(1), .heading(2), .heading(3), .heading(4), .bulleted, .numbered, .todo, .toggle,
        .toggleHeading(1), .toggleHeading(2), .toggleHeading(3), .toggleHeading(4), .quote, .callout, .code, .equation,
    ]

    var kind: NoteBlockKind {
        switch self {
        case .text: return .paragraph
        case .heading, .toggleHeading: return .heading
        case .bulleted: return .bulletedItem
        case .numbered: return .numberedItem
        case .todo: return .todo
        case .toggle: return .toggle
        case .quote: return .quote
        case .callout: return .callout
        case .divider: return .divider
        case .newNote, .linkToNote: return .pageLink
        case .table: return .table
        case .image: return .image
        case .video: return .video
        case .audio: return .audio
        case .file: return .file
        case .bookmark: return .bookmark
        case .embed: return .embed
        case .tableOfContents: return .tableOfContents
        case .equation: return .equation
        case .code: return .code
        case .columns: return .columns
        }
    }

    var bearsText: Bool { kind.hasRichText || kind.hasPlainText }

    var canTurnInto: Bool { Self.turnIntoTargets.contains(self) }

    func configure(_ props: inout NoteBlockProps) {
        switch self {
        case .heading(let level):
            props.level = min(max(level, 1), 6)
            props.toggleable = false
        case .toggleHeading(let level):
            props.level = min(max(level, 1), 6)
            props.toggleable = true
            props.expanded = true
        default:
            break
        }
    }

    func makeBlock() -> NoteBlock {
        if case .columns(let count) = self {
            return NoteBlock(.columns, children: (0..<min(max(count, 2), 5)).map { _ in NoteBlock(.column, children: [.paragraph()]) })
        }
        return NoteBlock.paragraph().converted(to: kind, configure: configure)
    }

    func describes(_ block: NoteBlock) -> Bool {
        switch self {
        case .text: return block.kind == .paragraph
        case .heading(let level): return block.kind == .heading && !block.props.toggleable && block.props.level == level
        case .toggleHeading(let level): return block.kind == .heading && block.props.toggleable && block.props.level == level
        case .columns(let count): return block.kind == .columns && block.children.count == count
        default: return block.kind == kind
        }
    }
}

enum NoteCatalogInline: Hashable { case mention, date, emoji, equation }

enum NoteCatalogAction: Hashable { case delete, duplicate, moveUp, moveDown }

enum NoteCatalogEffect: Hashable {
    case block(NoteCatalogBlock)
    case turnInto(NoteCatalogBlock)
    case inline(NoteCatalogInline)
    case color(NoteColorStyle?)
    case action(NoteCatalogAction)
}

enum NoteCatalogIcon: Hashable {
    case symbol(String)
    case text(String)
    case swatch(NoteColorStyle?)
}

struct NoteCatalogItem: Hashable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let section: NoteCatalogSection
    let icon: NoteCatalogIcon
    let hint: String?
    let aliases: [String]
    let keywords: [String]
    let effect: NoteCatalogEffect

    var block: NoteCatalogBlock? {
        switch effect {
        case .block(let value), .turnInto(let value): return value
        default: return nil
        }
    }
}

struct NoteCatalogContext: Hashable {
    enum Mode: Hashable { case slash, plus, turnInto }
    var mode: Mode
    var allowsColumns = true
    var allowsNewNote = true
    var allowsActions = true

    static let slash = NoteCatalogContext(mode: .slash)
    static let plus = NoteCatalogContext(mode: .plus, allowsActions: false)
    static let turnInto = NoteCatalogContext(mode: .turnInto, allowsActions: false)
}

enum NoteBlockCatalog {
    static let items: [NoteCatalogItem] = buildItems()
    static let turnIntoItems: [NoteCatalogItem] = buildTurnIntoItems(prefixed: true)
    static let turnIntoMenuItems: [NoteCatalogItem] = buildTurnIntoItems(prefixed: false)
    private static let order: [String: Int] = {
        var result: [String: Int] = [:]
        for (index, item) in (items + turnIntoItems + turnIntoMenuItems).enumerated() where result[item.id] == nil { result[item.id] = index }
        return result
    }()
    private static let turnPrefixes = ["turn into", "turninto", "turn to", "turn"]

    static func item(_ id: String) -> NoteCatalogItem? {
        (items + turnIntoItems + turnIntoMenuItems).first { $0.id == id }
    }

    static func item(for block: NoteCatalogBlock) -> NoteCatalogItem? {
        items.first { $0.effect == .block(block) }
    }

    static func turnIntoMenuItems(columnLimit: Int) -> [NoteCatalogItem] {
        guard columnLimit >= 2 else { return turnIntoMenuItems }
        return turnIntoMenuItems + (2...min(columnLimit, NotePageSession.maximumColumns)).compactMap { count in
            guard let base = item(for: .columns(count)) else { return nil }
            return NoteCatalogItem(id: "into." + base.id, title: base.title, summary: "Line these blocks up side by side.", section: .actions,
                                   icon: base.icon, hint: nil, aliases: base.aliases, keywords: base.keywords + [base.title],
                                   effect: .turnInto(.columns(count)))
        }
    }

    static func results(for query: String, in context: NoteCatalogContext = .slash) -> [NoteCatalogItem] {
        let normalized = normalize(query)
        if context.mode == .turnInto { return rank(turnIntoMenuItems, normalized, keepEmpty: true) }
        let base = items.filter { item in
            switch item.effect {
            case .block(.columns): return context.allowsColumns
            case .block(.newNote): return context.allowsNewNote
            case .action: return context.allowsActions
            default: return true
            }
        }
        guard !normalized.isEmpty else { return base.filter { !$0.section.needsQuery } }
        if context.allowsActions, let remainder = turnRemainder(normalized) {
            return rank(turnIntoItems, remainder, keepEmpty: true)
        }
        return rank(base, normalized, keepEmpty: false)
    }

    static let strongMatchScore = 600

    static func score(_ item: NoteCatalogItem, query: String) -> Int? {
        let query = normalize(query)
        guard !query.isEmpty else { return 0 }
        let compactQuery = compact(query)
        let length = query.count
        var best: Int?
        func consider(_ value: Int) { best = max(best ?? Int.min, value) }
        let title = normalize(item.title)
        let compactTitle = compact(title)
        let aliases = item.aliases.map(normalize)
        let keywords = item.keywords.map(normalize)
        for alias in aliases where alias == query || (!compactQuery.isEmpty && compact(alias) == compactQuery) { consider(1000) }
        if title == query || (!compactQuery.isEmpty && compactTitle == compactQuery) { consider(950) }
        if title.hasPrefix(query) { consider(900 - min(40, title.count - length)) }
        if !compactQuery.isEmpty, compactTitle.hasPrefix(compactQuery) { consider(880 - min(40, compactTitle.count - compactQuery.count)) }
        for alias in aliases {
            if alias.hasPrefix(query) { consider(790 - min(30, alias.count - length)) }
            else if !compactQuery.isEmpty, compact(alias).hasPrefix(compactQuery) { consider(780 - min(30, alias.count - length)) }
        }
        if wordPrefixMatch(query, title) { consider(800) }
        for keyword in keywords {
            if keyword == query { consider(760) }
            else if keyword.hasPrefix(query) { consider(720) }
            else if wordPrefixMatch(query, keyword) { consider(700) }
        }
        if length >= 2, title.contains(query) { consider(600) }
        if compactQuery.count >= 2 {
            if let fuzzy = fuzzyScore(compactQuery, title) { consider(300 + fuzzy) }
            for candidate in aliases + keywords { if let fuzzy = fuzzyScore(compactQuery, candidate) { consider(200 + min(fuzzy, 99)) } }
        }
        return best
    }

    static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func compact(_ value: String) -> String {
        String(value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    static func wordPrefixMatch(_ query: String, _ target: String) -> Bool {
        let tokens = query.split(separator: " ").map(String.init)
        let words = target.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "/" }).map(String.init)
        guard !tokens.isEmpty else { return false }
        var index = 0
        for token in tokens {
            while index < words.count, !words[index].hasPrefix(token) { index += 1 }
            guard index < words.count else { return false }
            index += 1
        }
        return true
    }

    static func fuzzyScore(_ query: String, _ target: String) -> Int? {
        let needle = Array(query), haystack = Array(target)
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
        var position = 0, score = 0, previous = -2
        for (index, character) in haystack.enumerated() where position < needle.count {
            guard character == needle[position] else { continue }
            let startsWord = index == 0 || !(haystack[index - 1].isLetter || haystack[index - 1].isNumber)
            if position == 0 && !startsWord { continue }
            score += (index == previous + 1 ? 6 : 0) + (startsWord ? 4 : 0)
            previous = index
            position += 1
        }
        guard position == needle.count else { return nil }
        return min(99, score + max(0, 20 - (haystack.count - needle.count)))
    }

    private static func turnRemainder(_ query: String) -> String? {
        if query.count >= 3, "turn".hasPrefix(query) { return "" }
        for prefix in turnPrefixes where query.hasPrefix(prefix) {
            return String(query.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func rank(_ candidates: [NoteCatalogItem], _ query: String, keepEmpty: Bool) -> [NoteCatalogItem] {
        guard !query.isEmpty else { return keepEmpty ? candidates : [] }
        let scored = candidates.compactMap { item in score(item, query: query).map { (item, $0) } }
        let strong = scored.filter { $0.1 >= strongMatchScore }
        return (strong.isEmpty ? scored : strong)
            .sorted { lhs, rhs in lhs.1 != rhs.1 ? lhs.1 > rhs.1 : (order[lhs.0.id] ?? 0) < (order[rhs.0.id] ?? 0) }
            .map(\.0)
    }

    private static func buildTurnIntoItems(prefixed: Bool) -> [NoteCatalogItem] {
        let blocks = buildBlockItems()
        return NoteCatalogBlock.turnIntoTargets.compactMap { block in
            guard let base = item(for: block, in: blocks) else { return nil }
            return NoteCatalogItem(id: (prefixed ? "turn." : "into.") + base.id, title: prefixed ? "Turn into " + base.title : base.title,
                                   summary: "Keep the words, swap the block.", section: .actions, icon: base.icon,
                                   hint: prefixed ? nil : base.hint, aliases: base.aliases, keywords: base.keywords + [base.title],
                                   effect: .turnInto(block))
        }
    }

    private static func item(for block: NoteCatalogBlock, in list: [NoteCatalogItem]) -> NoteCatalogItem? {
        list.first { $0.effect == .block(block) }
    }

    private static func buildItems() -> [NoteCatalogItem] {
        buildBlockItems() + buildInlineItems() + buildColorItems() + buildActionItems()
    }

    private static func block(_ id: String, _ title: String, _ summary: String, _ section: NoteCatalogSection, _ icon: NoteCatalogIcon,
                              hint: String? = nil, aliases: [String] = [], keywords: [String] = [], _ block: NoteCatalogBlock) -> NoteCatalogItem {
        NoteCatalogItem(id: id, title: title, summary: summary, section: section, icon: icon, hint: hint,
                        aliases: aliases, keywords: keywords, effect: .block(block))
    }

    private static func buildBlockItems() -> [NoteCatalogItem] {
        var result: [NoteCatalogItem] = [
            block("text", "Text", "Just start writing.", .basic, .symbol("textformat"),
                  aliases: ["plain", "p", "txt"], keywords: ["paragraph", "normal", "body", "words"], .text),
            block("heading1", "Heading 1", "The big one, for sections.", .basic, .text("H1"), hint: "#",
                  aliases: ["h1", "#", "heading1", "title"], keywords: ["header", "big", "large"], .heading(1)),
            block("heading2", "Heading 2", "A medium heading for subsections.", .basic, .text("H2"), hint: "##",
                  aliases: ["h2", "##", "heading2", "subtitle"], keywords: ["header", "medium"], .heading(2)),
            block("heading3", "Heading 3", "A small heading, quietly in charge.", .basic, .text("H3"), hint: "###",
                  aliases: ["h3", "###", "heading3"], keywords: ["header", "small"], .heading(3)),
            block("heading4", "Heading 4", "The tiniest heading, for the fine print.", .basic, .text("H4"), hint: "####",
                  aliases: ["h4", "####", "heading4"], keywords: ["header", "smaller", "tiny"], .heading(4)),
            block("bulleted", "Bulleted list", "A simple list of points.", .basic, .symbol("list.bullet"), hint: "-",
                  aliases: ["ul", "-", "*", "bullet", "bullets", "unordered"], keywords: ["list", "points", "dots"], .bulleted),
            block("numbered", "Numbered list", "A list that counts for you.", .basic, .symbol("list.number"), hint: "1.",
                  aliases: ["ol", "num", "1.", "numbers", "ordered"], keywords: ["list", "steps", "order"], .numbered),
            block("todo", "To-do list", "Tick things off as you go.", .basic, .symbol("checkmark.square"), hint: "[]",
                  aliases: ["todo", "[]", "checkbox", "task", "tasks", "check"], keywords: ["list", "checklist", "done", "tick"], .todo),
            block("toggle", "Toggle list", "Tuck details away until needed.", .basic, .symbol("chevron.right.circle"), hint: ">",
                  aliases: ["toggle", ">", "collapse", "details", "disclosure", "fold"], keywords: ["list", "hide", "expand", "accordion"], .toggle),
            block("toggleHeading1", "Toggle heading 1", "A big heading that folds up.", .basic, .text("▸H1"), hint: "> #",
                  aliases: ["th1", "toggle h1", "toggleh1"], keywords: ["toggle", "heading", "collapse", "fold"], .toggleHeading(1)),
            block("toggleHeading2", "Toggle heading 2", "A medium heading that folds up.", .basic, .text("▸H2"), hint: "> ##",
                  aliases: ["th2", "toggle h2", "toggleh2"], keywords: ["toggle", "heading", "collapse", "fold"], .toggleHeading(2)),
            block("toggleHeading3", "Toggle heading 3", "A small heading that folds up.", .basic, .text("▸H3"), hint: "> ###",
                  aliases: ["th3", "toggle h3", "toggleh3"], keywords: ["toggle", "heading", "collapse", "fold"], .toggleHeading(3)),
            block("toggleHeading4", "Toggle heading 4", "A tiny heading that folds up.", .basic, .text("▸H4"), hint: "> ####",
                  aliases: ["th4", "toggle h4", "toggleh4"], keywords: ["toggle", "heading", "collapse", "fold"], .toggleHeading(4)),
            block("quote", "Quote", "When someone said it best.", .basic, .symbol("text.quote"), hint: "\"",
                  aliases: ["\"", "|", "blockquote", "cite"], keywords: ["quotation", "citation", "pull quote"], .quote),
            block("callout", "Callout", "Make something stand out.", .basic, .symbol("lightbulb"),
                  aliases: ["call", "note", "tip", "info", "warning", "alert"], keywords: ["box", "highlight", "important", "admonition"], .callout),
            block("divider", "Divider", "A quiet line between ideas.", .basic, .symbol("minus"), hint: "---",
                  aliases: ["div", "hr", "---", "line", "separator", "rule"], keywords: ["break", "split"], .divider),
            block("newNote", "New note", "Start a fresh note in this folder.", .basic, .symbol("doc.badge.plus"),
                  aliases: ["page", "new page", "subpage", "sub page"], keywords: ["note", "create", "file"], .newNote),
            block("linkToNote", "Link to note", "Point to a note you already have.", .basic, .symbol("arrow.up.right.square"),
                  aliases: ["link", "link to page", "page link", "[["], keywords: ["note", "reference", "page"], .linkToNote),
            block("table", "Table", "Rows and cells, nice and simple.", .basic, .symbol("tablecells"),
                  aliases: ["grid", "simple table"], keywords: ["rows", "cells", "spreadsheet", "matrix"], .table),
            block("image", "Image", "Drop in a picture, or paste a link.", .media, .symbol("photo"),
                  aliases: ["img", "picture", "photo", "pic"], keywords: ["png", "jpg", "jpeg", "gif", "screenshot", "upload"], .image),
            block("video", "Video", "Upload a clip, or embed one.", .media, .symbol("play.rectangle"),
                  aliases: ["movie", "clip", "mp4"], keywords: ["youtube", "vimeo", "film", "upload"], .video),
            block("audio", "Audio", "Add a recording or a song.", .media, .symbol("waveform"),
                  aliases: ["sound", "music", "mp3"], keywords: ["podcast", "song", "recording", "voice memo"], .audio),
            block("file", "File", "Attach any file to this note.", .media, .symbol("paperclip"),
                  aliases: ["attachment", "attach", "upload"], keywords: ["pdf", "document", "doc", "zip"], .file),
            block("bookmark", "Bookmark", "Save a link as a tidy card.", .media, .symbol("bookmark"),
                  aliases: ["book", "web", "web bookmark", "url"], keywords: ["link", "preview", "website"], .bookmark),
            block("embed", "Embed", "Bring a live page into the note.", .media, .symbol("chevron.left.forwardslash.chevron.right"),
                  aliases: ["iframe", "tweet", "maps"], keywords: ["website", "figma", "codepen", "youtube", "widget"], .embed),
            block("tableOfContents", "Table of contents", "A map of every heading here.", .advanced, .symbol("list.bullet.indent"),
                  aliases: ["toc", "contents", "outline"], keywords: ["index", "headings", "navigation"], .tableOfContents),
            block("equation", "Block equation", "Write TeX, get beautiful math.", .advanced, .symbol("function"), hint: "$$",
                  aliases: ["math", "tex", "latex", "equation", "$$"], keywords: ["katex", "formula", "maths"], .equation),
            block("code", "Code", "Code, with colors that make sense.", .advanced, .symbol("curlybraces"), hint: "```",
                  aliases: ["```", "snippet", "pre"], keywords: ["program", "syntax", "script", "monospace"], .code),
        ]
        let counts = ["two", "three", "four", "five"]
        let blurbs = ["Put blocks side by side.", "Three blocks, shoulder to shoulder.", "Four columns, getting cosy.", "Five columns. Bold move."]
        for count in 2...5 {
            result.append(block("columns\(count)", "\(count) columns", blurbs[count - 2], .advanced, .symbol("rectangle.split.\(min(count, 3))x1"),
                                aliases: ["\(count) col", "\(count)col", "col\(count)", "\(counts[count - 2]) columns"],
                                keywords: ["columns", "layout", "side by side", "split"], .columns(count)))
        }
        return result
    }

    private static func buildInlineItems() -> [NoteCatalogItem] {
        func inline(_ id: String, _ title: String, _ summary: String, _ icon: NoteCatalogIcon, hint: String? = nil,
                    aliases: [String], keywords: [String], _ value: NoteCatalogInline) -> NoteCatalogItem {
            NoteCatalogItem(id: id, title: title, summary: summary, section: .inline, icon: icon, hint: hint,
                            aliases: aliases, keywords: keywords, effect: .inline(value))
        }
        return [
            inline("mention", "Mention a note", "Link a note right in the sentence.", .symbol("at"), hint: "@",
                   aliases: ["@", "mention", "mention page", "page mention"], keywords: ["note", "reference", "cite note"], .mention),
            inline("date", "Date or reminder", "Pin a date here, or a nudge for later.", .symbol("calendar"), hint: "@",
                   aliases: ["date", "reminder", "remind", "today", "now"], keywords: ["calendar", "time", "deadline", "due"], .date),
            inline("emoji", "Emoji", "Find the perfect tiny picture.", .symbol("face.smiling"), hint: ":",
                   aliases: [":", "emoticon", "smiley"], keywords: ["face", "icon", "reaction"], .emoji),
            inline("inlineEquation", "Inline equation", "Math, mid-sentence.", .symbol("x.squareroot"),
                   aliases: ["inline math", "$"], keywords: ["math", "tex", "latex", "formula"], .equation),
        ]
    }

    private static func buildColorItems() -> [NoteCatalogItem] {
        var text: [NoteCatalogItem] = [
            NoteCatalogItem(id: "color.default", title: "Default", summary: "Back to plain ink.", section: .colors, icon: .swatch(nil), hint: nil,
                            aliases: ["default", "no color", "clear color"], keywords: ["color", "colour", "reset", "none", "plain"], effect: .color(nil)),
        ]
        var backgrounds: [NoteCatalogItem] = []
        for color in NoteColor.allCases {
            let name = color.rawValue.capitalized
            let aliases = color == .gray ? ["grey"] : []
            text.append(NoteCatalogItem(id: "color." + color.rawValue, title: name, summary: "\(name) text for this block.", section: .colors,
                                        icon: .swatch(.text(color)), hint: nil, aliases: aliases,
                                        keywords: ["color", "colour", "text color", "ink"], effect: .color(.text(color))))
            backgrounds.append(NoteCatalogItem(id: "background." + color.rawValue, title: name + " background",
                                               summary: "A \(color.rawValue) wash behind this block.", section: .colors,
                                               icon: .swatch(.background(color)), hint: nil, aliases: aliases.map { $0 + " background" },
                                               keywords: ["color", "colour", "background", "highlight", "back"], effect: .color(.background(color))))
        }
        return text + backgrounds
    }

    private static func buildActionItems() -> [NoteCatalogItem] {
        [
            NoteCatalogItem(id: "action.delete", title: "Delete", summary: "Gone. ⌘Z still remembers.", section: .actions, icon: .symbol("trash"),
                            hint: nil, aliases: ["del", "remove", "trash"], keywords: ["block", "erase"], effect: .action(.delete)),
            NoteCatalogItem(id: "action.duplicate", title: "Duplicate", summary: "A twin, right below.", section: .actions,
                            icon: .symbol("plus.square.on.square"), hint: nil, aliases: ["dup", "clone", "copy"], keywords: ["block", "again"],
                            effect: .action(.duplicate)),
            NoteCatalogItem(id: "action.moveUp", title: "Move up", summary: "Swap places with the block above.", section: .actions,
                            icon: .symbol("arrow.up"), hint: nil, aliases: ["up", "moveup"], keywords: ["move", "reorder"], effect: .action(.moveUp)),
            NoteCatalogItem(id: "action.moveDown", title: "Move down", summary: "Swap places with the block below.", section: .actions,
                            icon: .symbol("arrow.down"), hint: nil, aliases: ["down", "movedown"], keywords: ["move", "reorder"], effect: .action(.moveDown)),
        ]
    }
}

struct NoteQueryTracker: Hashable {
    enum Verdict: Hashable { case open, close }

    var closesOnSpace: Bool
    var slack: Int
    private(set) var matchedLength = 0

    init(closesOnSpace: Bool = true, slack: Int = 3) {
        self.closesOnSpace = closesOnSpace
        self.slack = slack
    }

    static let slash = NoteQueryTracker()
    static let mention = NoteQueryTracker(closesOnSpace: false, slack: 4)

    mutating func update(query: String, hasResults: Bool) -> Verdict {
        let length = (query as NSString).length
        if hasResults {
            matchedLength = length
            return .open
        }
        matchedLength = min(matchedLength, length)
        if let first = query.first, first.isWhitespace { return .close }
        if closesOnSpace, query.last?.isWhitespace == true { return .close }
        if query.contains(where: \.isNewline) { return .close }
        return length - matchedLength >= slack ? .close : .open
    }
}

enum NoteInlineTrigger: Hashable {
    case slash, mention, noteLink

    var symbol: String {
        switch self {
        case .slash: return "/"
        case .mention: return "@"
        case .noteLink: return "[["
        }
    }

    var length: Int { (symbol as NSString).length }
}

enum NoteTriggerRule {
    static let shortcodeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-")
    private static let openers = CharacterSet(charactersIn: "([{\"'“‘«")

    static func insertion(from old: String, to new: String, caret: Int) -> (range: Range<Int>, text: String)? {
        let before = old as NSString, after = new as NSString
        let inserted = after.length - before.length
        guard inserted > 0, caret >= inserted, caret <= after.length else { return nil }
        let start = caret - inserted
        guard after.substring(to: start) == before.substring(to: start),
              after.substring(from: caret) == before.substring(from: start) else { return nil }
        return (start..<caret, after.substring(with: NSRange(location: start, length: inserted)))
    }

    static func isBoundary(_ text: NSString, before offset: Int, allowingOpeners: Bool) -> Bool {
        guard offset > 0 else { return true }
        guard offset <= text.length, let scalar = Unicode.Scalar(text.character(at: offset - 1)) else { return false }
        if CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar == "\u{2028}" || scalar == "\u{2029}" { return true }
        return allowingOpeners && openers.contains(scalar)
    }

    static func trigger(from old: String, to new: String, caret: Int) -> (trigger: NoteInlineTrigger, start: Int)? {
        guard let typed = insertion(from: old, to: new, caret: caret), typed.text.count == 1 else { return nil }
        let text = new as NSString
        switch typed.text {
        case "/":
            return isBoundary(text, before: typed.range.lowerBound, allowingOpeners: false) ? (.slash, typed.range.lowerBound) : nil
        case "@":
            return isBoundary(text, before: typed.range.lowerBound, allowingOpeners: true) ? (.mention, typed.range.lowerBound) : nil
        case "[":
            let start = typed.range.lowerBound - 1
            guard start >= 0, text.character(at: start) == 91, isBoundary(text, before: start, allowingOpeners: false) else { return nil }
            return (.noteLink, start)
        default:
            return nil
        }
    }

    static func emojiQuery(in value: String, caret: Int) -> (start: Int, query: String)? {
        let text = value as NSString
        guard caret > 0, caret <= text.length else { return nil }
        var index = caret
        while index > 0, let scalar = Unicode.Scalar(text.character(at: index - 1)), shortcodeCharacters.contains(scalar) { index -= 1 }
        let colon = index - 1
        guard colon >= 0, text.character(at: colon) == 58, caret - index >= 2,
              let first = Unicode.Scalar(text.character(at: index)), CharacterSet.letters.contains(first),
              isBoundary(text, before: colon, allowingOpeners: true) else { return nil }
        return (colon, text.substring(with: NSRange(location: index, length: caret - index)))
    }

    static func completedShortcode(in value: String, caret: Int) -> (range: Range<Int>, shortcode: String)? {
        let text = value as NSString
        guard caret >= 4, caret <= text.length, text.character(at: caret - 1) == 58 else { return nil }
        guard let open = emojiQuery(in: text.substring(to: caret - 1), caret: caret - 1) else { return nil }
        return (open.start..<caret, open.query.lowercased())
    }

    static func isEmojiQuery(_ query: String) -> Bool {
        guard query.count >= 2, let first = query.unicodeScalars.first, CharacterSet.letters.contains(first) else { return false }
        return query.unicodeScalars.allSatisfy { shortcodeCharacters.contains($0) }
    }
}

struct NoteQueryMatch: Hashable {
    var query: String
    var range: Range<Int>
}

struct NoteQueryToken: Hashable {
    var start: Int
    var trigger: String
    private(set) var suffix: String

    init(start: Int, trigger: String, text: String, caret: Int) {
        let string = text as NSString
        self.start = start
        self.trigger = trigger
        let queryStart = start + (trigger as NSString).length
        suffix = string.substring(from: Swift.min(Swift.max(caret, queryStart, 0), string.length))
    }

    var queryStart: Int { start + (trigger as NSString).length }

    mutating func resolve(in text: String, caret: Int) -> NoteQueryMatch? {
        let string = text as NSString
        let queryStart = self.queryStart
        guard start >= 0, queryStart <= string.length, caret >= queryStart, caret <= string.length else { return nil }
        if !trigger.isEmpty, string.substring(with: NSRange(location: start, length: queryStart - start)) != trigger { return nil }
        var end = string.length - (suffix as NSString).length
        if end < queryStart || string.substring(from: end) != suffix {
            end = caret
            suffix = string.substring(from: end)
        }
        guard caret <= end else { return nil }
        let query = string.substring(with: NSRange(location: queryStart, length: end - queryStart))
        guard !query.contains(where: \.isNewline), !query.contains(NoteAtom.character) else { return nil }
        return NoteQueryMatch(query: query, range: start..<end)
    }
}


struct NoteCatalogOutcome {
    enum FollowUp: Hashable {
        case mention(NotePosition, datesOnly: Bool)
        case emoji(NotePosition)
        case pickNote(NotePosition)
        case editEquation(NotePosition)
    }

    var name: String
    var page: NotePage
    var selection: NotePageSelection
    var activate: NoteBlockID?
    var followUp: FollowUp?
}

enum NoteCatalogApplier {
    static func apply(_ effect: NoteCatalogEffect, to page: NotePage, at position: NotePosition, removing range: Range<Int>) -> NoteCatalogOutcome? {
        guard let block = page.block(position.block), let original = block.text(in: position.field) else { return nil }
        let bounds = clamp(range, original.length)
        var remaining = original
        remaining.delete(bounds)
        let caret = NotePosition(position.block, bounds.lowerBound, field: position.field)
        var next = page
        next.update(position.block) { $0.setText(remaining, in: position.field) }
        switch effect {
        case .block(.linkToNote):
            return NoteCatalogOutcome(name: "Link to Note", page: next, selection: .caret(caret), followUp: .pickNote(caret))
        case .block(.newNote):
            return nil
        case .block(let template):
            return place(template.makeBlock(), template: template, into: page, at: position, removing: range, name: "Insert")
        case .turnInto(let template):
            guard position.field == .body, !template.kind.isColumnStructure else { return nil }
            var converted = block
            converted.text = remaining
            converted = converted.converted(to: template.kind, configure: template.configure)
            let lifted = converted.acceptsChildren ? [] : converted.children
            if !lifted.isEmpty { converted.children = [] }
            next.update(position.block) { $0 = converted }
            if !lifted.isEmpty { next.insert(lifted, .after(position.block)) }
            let offset = min(caret.offset, converted.text.length)
            return NoteCatalogOutcome(name: "Turn Into", page: next, selection: .caret(NotePosition(position.block, offset)))
        case .inline(let inline):
            var text = remaining
            switch inline {
            case .mention, .date:
                text.insert(NoteText("@", marks: original.typingMarks(at: bounds.lowerBound).withoutAtom), at: bounds.lowerBound)
                next.update(position.block) { $0.setText(text, in: position.field) }
                let after = NotePosition(position.block, bounds.lowerBound + 1, field: position.field)
                return NoteCatalogOutcome(name: "Mention", page: next, selection: .caret(after), followUp: .mention(caret, datesOnly: inline == .date))
            case .emoji:
                return NoteCatalogOutcome(name: "Emoji", page: next, selection: .caret(caret), followUp: .emoji(caret))
            case .equation:
                text.insert(NoteText.atom(.equation(""), marks: original.typingMarks(at: bounds.lowerBound)), at: bounds.lowerBound)
                next.update(position.block) { $0.setText(text, in: position.field) }
                let after = NotePosition(position.block, bounds.lowerBound + 1, field: position.field)
                return NoteCatalogOutcome(name: "Inline Equation", page: next, selection: .caret(after), followUp: .editEquation(caret))
            }
        case .color(let style):
            next.update(position.block) { $0.color = style }
            return NoteCatalogOutcome(name: "Color", page: next, selection: .caret(caret))
        case .action(let action):
            switch action {
            case .delete:
                let landing = landingAfterDeleting(position.block, in: page)
                next.remove(position.block)
                next.collapseEmptyColumns()
                if next.blocks.isEmpty { next.blocks = [.paragraph()] }
                let selection = landing.flatMap { id -> NotePageSelection? in
                    guard let target = next.block(id) else { return nil }
                    return target.kind.hasRichText || target.kind.hasPlainText ? .caret(NotePosition(id, target.text.length)) : .blocks([id])
                } ?? .caret(NotePosition(next.blocks[0].id, 0))
                return NoteCatalogOutcome(name: "Delete", page: next, selection: selection)
            case .duplicate:
                guard let copy = next.block(position.block)?.withFreshIDs() else { return nil }
                next.insert([copy], .after(position.block))
                return NoteCatalogOutcome(name: "Duplicate", page: next, selection: .caret(caret))
            case .moveUp, .moveDown:
                move(position.block, action == .moveUp ? .up : .down, in: &next)
                return NoteCatalogOutcome(name: "Move", page: next, selection: .caret(caret))
            }
        }
    }

    static func place(_ fresh: NoteBlock, template: NoteCatalogBlock?, into page: NotePage, at position: NotePosition,
                      removing range: Range<Int>, name: String) -> NoteCatalogOutcome? {
        guard position.field == .body, let block = page.block(position.block), block.kind.hasRichText else { return nil }
        var remaining = block.text
        remaining.delete(clamp(range, block.text.length))
        var next = page
        var placed = fresh
        if remaining.isEmpty {
            if let template, template.bearsText {
                var emptied = block
                emptied.text = NoteText()
                var converted = emptied.converted(to: template.kind, configure: template.configure)
                let lifted = converted.acceptsChildren ? [] : converted.children
                if !lifted.isEmpty { converted.children = [] }
                next.update(block.id) { $0 = converted }
                if !lifted.isEmpty { next.insert(lifted, .after(block.id)) }
                placed = converted
            } else {
                let lifted = block.children
                next.update(block.id) { $0 = placed }
                if !lifted.isEmpty { next.insert(lifted, .after(placed.id)) }
            }
        } else {
            next.update(block.id) { $0.text = remaining }
            next.insert([placed], .after(block.id))
        }
        return NoteCatalogOutcome(name: name, page: next, selection: .none, activate: nil).focused(on: placed.id)
    }

    static func landingAfterDeleting(_ id: NoteBlockID, in page: NotePage) -> NoteBlockID? {
        let order = page.flattened().map(\.id)
        guard let index = order.firstIndex(of: id) else { return nil }
        let earlier = order[..<index].last { candidate in
            !page.isAncestor(id, of: candidate) && page.block(candidate).map { $0.kind != .column && $0.kind != .columns } == true
        }
        if let earlier { return earlier }
        return order[(index + 1)...].first { candidate in
            !page.isAncestor(id, of: candidate) && page.block(candidate).map { $0.kind != .column && $0.kind != .columns } == true
        }
    }

    static func move(_ id: NoteBlockID, _ direction: NoteMoveDirection, in page: inout NotePage) {
        let siblings = page.siblings(of: id)
        guard let index = siblings.firstIndex(where: { $0.id == id }) else { return }
        let parent = page.parent(of: id).flatMap { page.block($0) }
        let destination: NoteInsertion?
        switch direction {
        case .up:
            if index > 0 { destination = .before(siblings[index - 1].id) }
            else if let parent, parent.kind != .column { destination = .before(parent.id) }
            else { destination = nil }
        case .down:
            if index + 1 < siblings.count { destination = .after(siblings[index + 1].id) }
            else if let parent, parent.kind != .column { destination = .after(parent.id) }
            else { destination = nil }
        }
        guard let destination, let removed = page.remove(id) else { return }
        page.insert([removed], destination)
        page.collapseEmptyColumns()
    }

    private static func clamp(_ range: Range<Int>, _ length: Int) -> Range<Int> {
        let lower = min(max(0, range.lowerBound), length)
        return lower..<min(max(lower, range.upperBound), length)
    }
}

private extension NoteCatalogOutcome {
    func focused(on id: NoteBlockID) -> NoteCatalogOutcome {
        var result = self
        guard let block = page.block(id) else { return result }
        switch block.kind {
        case .divider, .tableOfContents:
            let siblings = page.siblings(of: id)
            if let index = siblings.firstIndex(where: { $0.id == id }), index + 1 < siblings.count,
               siblings[index + 1].kind == .paragraph, siblings[index + 1].text.isEmpty {
                result.selection = .caret(NotePosition(siblings[index + 1].id, 0))
            } else {
                let paragraph = NoteBlock.paragraph()
                result.page.insert([paragraph], .after(id))
                result.selection = .caret(NotePosition(paragraph.id, 0))
            }
        case .table:
            result.selection = .caret(NotePosition(id, 0, field: .cell(row: 0, column: 0)))
        case .columns:
            if let first = block.children.first?.children.first { result.selection = .caret(NotePosition(first.id, 0)) }
        case .equation:
            result.selection = .blocks([id])
            result.activate = id
        default:
            if block.kind.hasRichText || block.kind.hasPlainText {
                result.selection = .caret(NotePosition(id, 0))
            } else {
                result.selection = .blocks([id])
                result.activate = id
            }
        }
        return result
    }
}

struct NoteDateSuggestion: Hashable {
    var mention: NoteDateMention
    var title: String
}

struct NoteDateParser {
    var now: Date
    var calendar: Calendar
    var dayFirst: Bool
    var locale: Locale

    init(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) {
        self.now = now
        self.calendar = calendar
        self.locale = locale
        let pattern = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: locale) ?? "M/d/y"
        let day = pattern.firstIndex(of: "d") ?? pattern.endIndex, month = pattern.firstIndex(of: "M") ?? pattern.endIndex
        dayFirst = day < month
    }

    init(now: Date, calendar: Calendar, dayFirst: Bool, locale: Locale = Locale(identifier: "en_US_POSIX")) {
        self.now = now
        self.calendar = calendar
        self.dayFirst = dayFirst
        self.locale = locale
    }

    static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
    private static let numberWords = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
                                      "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12]
    private static let completions: [String] = {
        var phrases = ["today", "tomorrow", "yesterday", "next week", "next month", "next year", "last week", "last month", "this weekend"]
        phrases += weekdays
        phrases += weekdays.map { "next " + $0 }
        phrases += weekdays.map { "last " + $0 }
        phrases += weekdays.map { "this " + $0 }
        return phrases
    }()
    private static let vocabulary: Set<String> = {
        var words: Set<String> = ["today", "tomorrow", "yesterday", "tonight", "now", "next", "last", "this", "coming", "week", "weeks",
                                  "month", "months", "year", "years", "day", "days", "hour", "hours", "minute", "minutes", "min", "mins",
                                  "in", "at", "on", "of", "the", "from", "ago", "and", "noon", "midnight", "midday", "am", "pm",
                                  "weekend", "remind", "me", "reminder"]
        words.formUnion(weekdays)
        words.formUnion(months)
        words.formUnion(numberWords.keys)
        return words
    }()

    func parse(_ input: String) -> NoteDateMention? {
        var text = Self.clean(input)
        guard !text.isEmpty else { return nil }
        if let relative = relativeTime(text) { return relative }
        var time: (hour: Int, minute: Int)?
        if let found = extractTime(from: text) {
            time = found.time
            text = found.remainder
        }
        text = Self.strip(text, words: ["at", "on", "the", "by"])
        if text.isEmpty {
            guard let time else { return nil }
            return mention(on: now, time: time)
        }
        if text == "tonight" { return mention(on: now, time: time ?? (20, 0)) }
        if text == "now" { return mention(on: now, time: time ?? (calendar.component(.hour, from: now), calendar.component(.minute, from: now))) }
        guard let day = day(from: text) else { return nil }
        return mention(on: day, time: time)
    }

    func suggestions(for query: String, remind: Bool = false, limit: Int = 4) -> [NoteDateSuggestion] {
        let text = Self.clean(query)
        var found: [NoteDateMention] = []
        func add(_ mention: NoteDateMention?) {
            guard var mention else { return }
            if remind {
                mention = reminderVersion(of: mention)
                guard let fire = fireDate(for: mention), fire > now else { return }
            }
            if !found.contains(mention) { found.append(mention) }
        }
        if text.isEmpty {
            if remind {
                add(calendar.date(byAdding: .day, value: 1, to: now).flatMap { mention(on: $0, time: nil) })
                add(mention(on: now, time: nil))
            } else {
                for word in ["today", "tomorrow", "yesterday"] { add(parse(word)) }
            }
        } else {
            for word in ["today", "tomorrow", "yesterday"] where word.hasPrefix(text) { add(parse(word)) }
            add(parse(text))
            var extra = 0
            for phrase in Self.completions where phrase.hasPrefix(text) && phrase != text && text.count >= 2 && extra < 3 {
                let before = found.count
                add(parse(phrase))
                if found.count > before { extra += 1 }
            }
            if found.isEmpty, let completed = completingMonth(text) { add(parse(completed)) }
        }
        return found.prefix(limit).map { NoteDateSuggestion(mention: $0, title: NoteDateFormatting.label($0, now: now, calendar: calendar, locale: locale)) }
    }

    func isPlausiblePrefix(_ query: String) -> Bool {
        let text = Self.clean(query)
        guard !text.isEmpty else { return true }
        let tokens = text.split(separator: " ").map(String.init)
        for (index, token) in tokens.enumerated() {
            let isLast = index == tokens.count - 1 && !query.hasSuffix(" ")
            if token.allSatisfy({ $0.isNumber || "/-.:,".contains($0) }) { continue }
            if token.range(of: #"^\d{1,2}(st|nd|rd|th|am|pm|a|p)?$"#, options: .regularExpression) != nil { continue }
            if token.range(of: #"^\d{1,2}:\d{0,2}(am|pm|a|p)?$"#, options: .regularExpression) != nil { continue }
            if Self.vocabulary.contains(token) { continue }
            if Self.months.contains(where: { $0.hasPrefix(token) && token.count >= 3 }) { continue }
            if Self.weekdays.contains(where: { $0.hasPrefix(token) && token.count >= 3 }) { continue }
            if isLast, Self.vocabulary.contains(where: { $0.hasPrefix(token) }) { continue }
            return false
        }
        return true
    }

    static func reminderQuery(_ query: String) -> (query: String, remind: Bool) {
        let text = clean(query)
        for prefix in ["remind me", "reminder", "remind"] {
            if text == prefix || text.hasPrefix(prefix + " ") {
                return (String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces), true)
            }
        }
        if text.count >= 3, "remind".hasPrefix(text) { return ("", true) }
        return (query, false)
    }

    func reminderVersion(of mention: NoteDateMention) -> NoteDateMention {
        var value = mention
        value.remind = true
        guard value.hour == nil else { return value }
        value.hour = 9
        value.minute = 0
        if let fire = fireDate(for: value), fire <= now, calendar.isDate(fire, inSameDayAs: now) {
            let hour = calendar.component(.hour, from: now) + 1
            if hour < 24 {
                value.hour = hour
            } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                let parts = calendar.dateComponents([.year, .month, .day], from: tomorrow)
                value.year = parts.year ?? value.year
                value.month = parts.month ?? value.month
                value.day = parts.day ?? value.day
                value.hour = 9
            }
        }
        return value
    }

    func fireDate(for mention: NoteDateMention) -> Date? {
        var parts = DateComponents(year: mention.year, month: mention.month, day: mention.day)
        parts.hour = mention.hour ?? 9
        parts.minute = mention.hour == nil ? 0 : (mention.minute ?? 0)
        return calendar.date(from: parts)
    }

    func date(of mention: NoteDateMention) -> Date? {
        calendar.date(from: DateComponents(year: mention.year, month: mention.month, day: mention.day, hour: mention.hour ?? 0, minute: mention.minute ?? 0))
    }

    func mention(on date: Date, time: (hour: Int, minute: Int)?) -> NoteDateMention? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return NoteDateMention(year: year, month: month, day: day, hour: time?.hour, minute: time.map { $0.minute })
    }

    private static func clean(_ input: String) -> String {
        var text = input.lowercased().replacingOccurrences(of: ",", with: " ")
        while let first = text.first, first == "@" || first.isWhitespace { text.removeFirst() }
        while let last = text.last, last == "." || last.isWhitespace { text.removeLast() }
        return text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func strip(_ text: String, words: Set<String>) -> String {
        var tokens = text.split(separator: " ").map(String.init)
        while let first = tokens.first, words.contains(first) { tokens.removeFirst() }
        while let last = tokens.last, words.contains(last) { tokens.removeLast() }
        return tokens.joined(separator: " ")
    }

    private static func match(_ pattern: String, _ text: String) -> [String?]? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(location: 0, length: (text as NSString).length)
        guard let result = expression.firstMatch(in: text, range: range) else { return nil }
        return (0..<result.numberOfRanges).map { index in
            let part = result.range(at: index)
            return part.location == NSNotFound ? nil : (text as NSString).substring(with: part)
        }
    }

    private func extractTime(from text: String) -> (time: (hour: Int, minute: Int), remainder: String)? {
        let patterns: [(String, Bool)] = [
            (#"(?:^|\s)(?:at\s+)?(\d{1,2}):(\d{2})\s*(am|pm|a\.m\.|p\.m\.|a|p)?(?=\s|$)"#, true),
            (#"(?:^|\s)(?:at\s+)?(\d{1,2})\s*(am|pm|a\.m\.|p\.m\.|a|p)(?=\s|$)"#, false),
            (#"(?:^|\s)at\s+(\d{1,2})(?=\s|$)"#, false),
            (#"(?:^|\s)(?:at\s+)?(noon|midday|midnight)(?=\s|$)"#, false),
        ]
        for (index, (pattern, hasMinutes)) in patterns.enumerated() {
            guard let groups = Self.match(pattern, text), let whole = groups[0] else { continue }
            var hour: Int, minute = 0
            if index == 3 {
                hour = groups[1] == "midnight" ? 0 : 12
            } else {
                guard let hourText = groups[1], let parsed = Int(hourText) else { continue }
                hour = parsed
                if hasMinutes, let minuteText = groups[2], let parsedMinute = Int(minuteText) { minute = parsedMinute }
                let meridiem = hasMinutes ? groups[3] : (index == 1 ? groups[2] : nil)
                if let meridiem {
                    guard (1...12).contains(hour) else { return nil }
                    let pm = meridiem.hasPrefix("p")
                    hour = hour % 12 + (pm ? 12 : 0)
                } else if !(0...23).contains(hour) {
                    return nil
                }
            }
            guard (0...59).contains(minute) else { return nil }
            let remainder = text.replacingOccurrences(of: whole, with: " ").split(separator: " ").joined(separator: " ")
            return ((hour, minute), remainder)
        }
        return nil
    }

    private func relativeTime(_ text: String) -> NoteDateMention? {
        guard let groups = Self.match(#"^in\s+(\d+|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(minutes?|mins?|hours?|hrs?)$"#, text),
              let amountText = groups[1], let unit = groups[2] else { return nil }
        guard let amount = Int(amountText) ?? Self.numberWords[amountText] else { return nil }
        let component: Calendar.Component = unit.hasPrefix("h") ? .hour : .minute
        guard let date = calendar.date(byAdding: component, value: amount, to: now) else { return nil }
        return mention(on: date, time: (calendar.component(.hour, from: date), calendar.component(.minute, from: date)))
    }

    private func day(from text: String) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch text {
        case "today", "tod", "tdy": return today
        case "tomorrow", "tmr", "tmrw", "tom", "tomorow", "tommorow", "tommorrow": return calendar.date(byAdding: .day, value: 1, to: today)
        case "yesterday", "yday", "yest": return calendar.date(byAdding: .day, value: -1, to: today)
        case "next week": return calendar.date(byAdding: .day, value: 7, to: today)
        case "last week": return calendar.date(byAdding: .day, value: -7, to: today)
        case "next month": return calendar.date(byAdding: .month, value: 1, to: today)
        case "last month": return calendar.date(byAdding: .month, value: -1, to: today)
        case "next year": return calendar.date(byAdding: .year, value: 1, to: today)
        case "weekend", "this weekend": return weekday(7, modifier: nil, from: today)
        default: break
        }
        if let groups = Self.match(#"^(?:in\s+)?(\d+|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(days?|weeks?|months?|years?)(?:\s+(from now|ago))?$"#, text),
           let amountText = groups[1], let unit = groups[2] {
            let hasIn = text.hasPrefix("in ")
            let direction = groups[3]
            guard hasIn || direction != nil, let amount = Int(amountText) ?? Self.numberWords[amountText] else { return nil }
            let sign = direction == "ago" ? -1 : 1
            let component: Calendar.Component = unit.hasPrefix("d") ? .day : unit.hasPrefix("w") ? .weekOfYear : unit.hasPrefix("m") ? .month : .year
            return calendar.date(byAdding: component, value: sign * amount, to: today)
        }
        if let groups = Self.match(#"^(this|next|last|coming)?\s*([a-z]+)$"#, text), let name = groups[2], name.count >= 3,
           let index = Self.weekdays.firstIndex(where: { $0.hasPrefix(name) }) {
            return weekday(index + 1, modifier: groups[1], from: today)
        }
        if let groups = Self.match(#"^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$"#, text),
           let year = groups[1].flatMap({ Int($0) }), let month = groups[2].flatMap({ Int($0) }), let day = groups[3].flatMap({ Int($0) }) {
            return valid(year: year, month: month, day: day)
        }
        if let groups = Self.match(#"^(\d{1,2})([/.\-])(\d{1,2})(?:[/.\-](\d{2,4}))?$"#, text),
           let first = groups[1].flatMap({ Int($0) }), let separator = groups[2], let second = groups[3].flatMap({ Int($0) }) {
            let dayFirst = separator == "." ? true : self.dayFirst
            let year = groups[4].flatMap { Int($0) }.map { $0 < 100 ? 2000 + $0 : $0 } ?? calendar.component(.year, from: now)
            return valid(year: year, month: dayFirst ? second : first, day: dayFirst ? first : second)
        }
        if let groups = Self.match(#"^([a-z]{3,})\s+(\d{1,2})(?:st|nd|rd|th)?(?:\s+(\d{4}))?$"#, text),
           let name = groups[1], let month = monthNumber(name), let day = groups[2].flatMap({ Int($0) }) {
            return valid(year: groups[3].flatMap { Int($0) } ?? calendar.component(.year, from: now), month: month, day: day)
        }
        if let groups = Self.match(#"^(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?([a-z]{3,})(?:\s+(\d{4}))?$"#, text),
           let day = groups[1].flatMap({ Int($0) }), let name = groups[2], let month = monthNumber(name) {
            return valid(year: groups[3].flatMap { Int($0) } ?? calendar.component(.year, from: now), month: month, day: day)
        }
        return nil
    }

    private func completingMonth(_ text: String) -> String? {
        guard let groups = Self.match(#"^([a-z]{3,})(?:\s+(\d{1,2})(?:st|nd|rd|th)?)?$"#, text), let name = groups[1],
              let month = Self.months.first(where: { $0.hasPrefix(name) }), !Self.weekdays.contains(where: { $0.hasPrefix(name) }) else { return nil }
        return month + " " + (groups[2] ?? "1")
    }

    private func monthNumber(_ name: String) -> Int? {
        guard name.count >= 3 else { return nil }
        return Self.months.firstIndex { $0.hasPrefix(name) }.map { $0 + 1 }
    }

    private func valid(year: Int, month: Int, day: Int) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        return check.year == year && check.month == month && check.day == day ? date : nil
    }

    private func weekday(_ target: Int, modifier: String?, from today: Date) -> Date? {
        let current = calendar.component(.weekday, from: today)
        switch modifier {
        case "next":
            guard let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start,
                  let nextWeek = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
            return calendar.date(byAdding: .day, value: (target - calendar.firstWeekday + 7) % 7, to: nextWeek)
        case "last":
            let delta = (current - target + 7) % 7
            return calendar.date(byAdding: .day, value: -(delta == 0 ? 7 : delta), to: today)
        case "coming":
            let delta = (target - current + 7) % 7
            return calendar.date(byAdding: .day, value: delta == 0 ? 7 : delta, to: today)
        default:
            return calendar.date(byAdding: .day, value: (target - current + 7) % 7, to: today)
        }
    }
}

enum NoteDateFormatting {
    static func label(_ mention: NoteDateMention, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent,
                      locale: Locale = .autoupdatingCurrent) -> String {
        guard let date = calendar.date(from: DateComponents(year: mention.year, month: mention.month, day: mention.day,
                                                            hour: mention.hour ?? 12, minute: mention.minute ?? 0)) else {
            return NoteAtom.date(mention).fallbackText
        }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        var day: String
        switch days {
        case 0: day = "Today"
        case 1: day = "Tomorrow"
        case -1: day = "Yesterday"
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            day = format(date, template: sameYear ? (days > 1 && days < 7 ? "EEEE" : "EEEMMMd") : "MMMdy", calendar: calendar, locale: locale)
        }
        if mention.includesTime { day += " " + format(date, template: "jmm", calendar: calendar, locale: locale) }
        return day
    }

    static func longLabel(_ mention: NoteDateMention, calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) -> String {
        guard let date = calendar.date(from: DateComponents(year: mention.year, month: mention.month, day: mention.day,
                                                            hour: mention.hour ?? 12, minute: mention.minute ?? 0)) else {
            return NoteAtom.date(mention).fallbackText
        }
        var text = format(date, template: "EEEEMMMMdy", calendar: calendar, locale: locale)
        if mention.includesTime { text += " " + format(date, template: "jmm", calendar: calendar, locale: locale) }
        return text
    }

    static func format(_ date: Date, template: String, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

struct NoteReminderPlan: Hashable {
    var key: String
    var mention: NoteDateMention
    var fireDate: Date
    var body: String

    static func reminders(in page: NotePage, parser: NoteDateParser) -> [NoteReminderPlan] {
        var result: [NoteReminderPlan] = []
        var seen = Set<String>()
        for block in page.allBlocks() {
            var texts: [NoteText] = []
            if block.kind.hasRichText { texts.append(block.text) }
            if !block.props.caption.isEmpty { texts.append(block.props.caption) }
            if let table = block.props.table { texts += table.rows.flatMap { $0 } }
            for text in texts {
                for run in text.runs() {
                    guard case .date(let mention)? = run.marks.atom, mention.remind,
                          let fire = parser.fireDate(for: mention), fire > parser.now else { continue }
                    let key = String(format: "%04d-%02d-%02dT%02d:%02d", mention.year, mention.month, mention.day,
                                     mention.hour ?? 9, mention.hour == nil ? 0 : (mention.minute ?? 0))
                    guard seen.insert(key).inserted else { continue }
                    result.append(NoteReminderPlan(key: key, mention: mention, fireDate: fire, body: summary(of: text, parser: parser)))
                }
            }
        }
        return result.sorted { $0.fireDate < $1.fireDate }
    }

    static func summary(of text: NoteText, parser: NoteDateParser) -> String {
        var words = ""
        for run in text.runs() {
            switch run.marks.atom {
            case .date(let mention)?: words += NoteDateFormatting.label(mention, now: parser.now, calendar: parser.calendar, locale: parser.locale)
            case let atom?: words += atom.fallbackText
            case nil: words += (text.string as NSString).substring(with: NSRange(location: run.range.lowerBound, length: run.range.count))
            }
        }
        let trimmed = words.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return trimmed.count > 140 ? String(trimmed.prefix(139)) + "…" : trimmed
    }
}

struct NoteReminderRequest: Hashable {
    var identifier: String
    var noteID: String
    var title: String
    var body: String
    var fireDate: Date
    var bookmark: Data?
    var path: String?
}

@MainActor
protocol NoteReminderScheduling: AnyObject {
    func pendingRequests() async -> [NoteReminderRequest]
    func removeRequests(_ identifiers: [String])
    func add(_ request: NoteReminderRequest) async
}

struct NoteReminderRecord: Codable, Hashable {
    var id: String
    var bookmark: Data?
    var path: String
    var title: String
    var lastFire: Date
}

enum NoteReminderFiles {
    static func documentID(of url: URL, tracking: Bool) -> String? {
        let file = URL(fileURLWithPath: url.path)
        if let id = readDocumentID(file) { return id }
        guard tracking else { return nil }
        var info = stat()
        guard stat(file.path, &info) == 0, info.st_flags & UInt32(UF_TRACKED) == 0,
              chflags(file.path, info.st_flags | UInt32(UF_TRACKED)) == 0 else { return nil }
        return readDocumentID(file)
    }

    private static func readDocumentID(_ file: URL) -> String? {
        var probe = file
        probe.removeAllCachedResourceValues()
        guard let values = try? probe.resourceValues(forKeys: [.documentIdentifierKey, .volumeUUIDStringKey]),
              let document = values.documentIdentifier else { return nil }
        return "doc:\(values.volumeUUIDString ?? "local"):\(document)"
    }

    static func bookmark(for url: URL) -> Data? {
        try? URL(fileURLWithPath: url.path).bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolve(_ bookmark: Data) -> (url: URL, stale: Bool)? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        return (NoteFilePaths.canonical(url), stale)
    }

    static func isGone(_ url: URL) -> Bool {
        url.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" } || !NoteFilePaths.itemExists(url)
    }

    static func isUnmounted(_ path: String) -> Bool {
        let parts = URL(fileURLWithPath: path).pathComponents
        guard parts.count > 2, parts[1] == "Volumes" else { return false }
        return !FileManager.default.fileExists(atPath: "/Volumes/" + parts[2])
    }
}

@MainActor
final class NoteReminderQueue {
    private var tail: Task<Void, Never>?

    func run(_ job: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await job()
        }
    }

    func drain() async {
        while let current = tail {
            await current.value
            if tail == current { return }
        }
    }
}

@MainActor
final class NoteReminderBook {
    nonisolated static let identifierPrefix = "parc.notes.reminder|"
    static let recordsKey = "parc.notes.reminderNotes"
    static let legacyKey = "parc.notes.reminderDocuments"
    nonisolated static let fallbackTitle = "Untitled"
    nonisolated static let fallbackBody = "Here’s the nudge you asked for."

    private struct Signature: Equatable {
        var plans: [NoteReminderPlan]
        var title: String
        var path: String
    }

    let scheduler: NoteReminderScheduling?
    let defaults: UserDefaults
    var now: () -> Date = Date.init
    private(set) var records: [String: NoteReminderRecord] = [:]
    private var tombstones: [String: Date] = [:]
    private var signatures: [String: Signature] = [:]
    private let queue = NoteReminderQueue()

    init(scheduler: NoteReminderScheduling?, defaults: UserDefaults) {
        self.scheduler = scheduler
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.recordsKey),
           let stored = try? PropertyListDecoder().decode([NoteReminderRecord].self, from: data) {
            records = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        }
        defaults.removeObject(forKey: Self.legacyKey)
    }

    nonisolated static func identifierPrefix(for noteID: String) -> String { identifierPrefix + noteID + "|" }

    nonisolated static func noteID(fromIdentifier identifier: String) -> String? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        let rest = identifier.dropFirst(identifierPrefix.count)
        guard let bar = rest.lastIndex(of: "|") else { return nil }
        return String(rest[..<bar])
    }

    @discardableResult
    func reconcile(page: NotePage, document: URL?, title: String, openedAt: Date, parser: NoteDateParser = NoteDateParser()) -> Bool {
        guard scheduler != nil, let document, document.isFileURL else { return false }
        let file = NoteFilePaths.canonical(document)
        guard !isBuried(file.path, openedAt: openedAt) else { return false }
        let plans = NoteReminderPlan.reminders(in: page, parser: parser)
        guard !plans.isEmpty || !records.isEmpty else { return false }
        let known = record(at: file)
        guard !plans.isEmpty || known != nil, !NoteReminderFiles.isGone(file) else { return false }
        let id: String
        if let known {
            id = known.id
        } else {
            id = NoteReminderFiles.documentID(of: file, tracking: true) ?? "note:" + UUID().uuidString
        }
        guard !isBuried(id, openedAt: openedAt) else { return false }
        let signature = Signature(plans: plans, title: title, path: file.path)
        guard signatures[id] != signature else { return false }
        guard let last = plans.last else {
            signatures[id] = signature
            records[id] = nil
            save()
            unschedule([id])
            prune()
            return false
        }
        let bookmark = NoteReminderFiles.bookmark(for: file) ?? known?.bookmark
        signatures[id] = signature
        records[id] = NoteReminderRecord(id: id, bookmark: bookmark, path: file.path, title: title, lastFire: last.fireDate)
        save()
        let requests = plans.map { plan in
            NoteReminderRequest(identifier: Self.identifierPrefix(for: id) + plan.key, noteID: id,
                                title: title.isEmpty ? Self.fallbackTitle : title,
                                body: plan.body.isEmpty ? Self.fallbackBody : plan.body,
                                fireDate: plan.fireDate, bookmark: bookmark, path: file.path)
        }
        queue.run { [weak self] in await self?.replace(id, with: requests) }
        prune()
        return true
    }

    func forget(document: URL) {
        let file = NoteFilePaths.canonical(document)
        let moment = now()
        tombstones[file.path] = moment
        var ids = Set(records.values.filter { $0.path == file.path }.map(\.id))
        if let id = NoteReminderFiles.documentID(of: file, tracking: false) { ids.insert(id) }
        for id in ids {
            tombstones[id] = moment
            records[id] = nil
            signatures[id] = nil
        }
        save()
        unschedule(ids.sorted())
        prune()
    }

    func noteMoved(from old: URL, to new: URL) {
        let oldPath = NoteFilePaths.canonical(old).path
        let file = NoteFilePaths.canonical(new)
        guard oldPath != file.path else { return }
        let movedID = NoteReminderFiles.documentID(of: file, tracking: false)
        for var record in records.values where record.path == oldPath || record.id == movedID {
            record.path = file.path
            record.title = file.deletingPathExtension().lastPathComponent
            record.bookmark = NoteReminderFiles.bookmark(for: file) ?? record.bookmark
            records[record.id] = record
            signatures[record.id] = nil
        }
        save()
    }

    func prune() {
        guard let scheduler else { return }
        let moment = now()
        var renamed: [String: NoteReminderRecord] = [:]
        for record in records.values {
            if record.lastFire <= moment {
                records[record.id] = nil
                signatures[record.id] = nil
                continue
            }
            guard let resolved = Self.current(record), !NoteReminderFiles.isGone(resolved.url) else {
                if NoteReminderFiles.isUnmounted(record.path) { continue }
                records[record.id] = nil
                signatures[record.id] = nil
                continue
            }
            guard resolved.url.path != record.path || resolved.stale else { continue }
            var moved = record
            moved.path = resolved.url.path
            moved.title = resolved.url.deletingPathExtension().lastPathComponent
            moved.bookmark = NoteReminderFiles.bookmark(for: resolved.url) ?? record.bookmark
            records[record.id] = moved
            guard moved.path != record.path else { continue }
            signatures[record.id] = nil
            renamed[record.id] = moved
        }
        save()
        let live = Set(records.keys)
        queue.run {
            let pending = await scheduler.pendingRequests().filter { $0.identifier.hasPrefix(Self.identifierPrefix) }
            let orphans = pending.filter { !live.contains($0.noteID) }.map(\.identifier)
            if !orphans.isEmpty { scheduler.removeRequests(orphans) }
            for request in pending {
                guard let record = renamed[request.noteID] else { continue }
                var updated = request
                updated.title = record.title.isEmpty ? Self.fallbackTitle : record.title
                updated.bookmark = record.bookmark
                updated.path = record.path
                if updated != request { await scheduler.add(updated) }
            }
        }
    }

    func location(noteID: String?, bookmark: Data?, path: String?) -> URL? {
        for data in [bookmark, noteID.flatMap { records[$0]?.bookmark }].compactMap({ $0 }) {
            if let resolved = NoteReminderFiles.resolve(data), !NoteReminderFiles.isGone(resolved.url) { return resolved.url }
        }
        guard let path else { return nil }
        let file = NoteFilePaths.canonical(URL(fileURLWithPath: path))
        return NoteReminderFiles.isGone(file) ? nil : file
    }

    func drain() async { await queue.drain() }

    private static func current(_ record: NoteReminderRecord) -> (url: URL, stale: Bool)? {
        if let bookmark = record.bookmark { return NoteReminderFiles.resolve(bookmark) }
        return (NoteFilePaths.canonical(URL(fileURLWithPath: record.path)), false)
    }

    private func record(at file: URL) -> NoteReminderRecord? {
        let document = NoteReminderFiles.documentID(of: file, tracking: false)
        if let document, let record = records[document] { return record }
        return records.values.first { record in
            guard record.path == file.path else { return false }
            return !record.id.hasPrefix("doc:") || document == nil || document == record.id
        }
    }

    private func isBuried(_ key: String, openedAt: Date) -> Bool {
        guard let buried = tombstones[key] else { return false }
        if buried >= openedAt { return true }
        tombstones[key] = nil
        return false
    }

    private func unschedule(_ ids: [String]) {
        guard let scheduler, !ids.isEmpty else { return }
        let prefixes = ids.map(Self.identifierPrefix(for:))
        queue.run {
            let stale = await scheduler.pendingRequests().map(\.identifier).filter { identifier in
                prefixes.contains { identifier.hasPrefix($0) }
            }
            if !stale.isEmpty { scheduler.removeRequests(stale) }
        }
    }

    private func replace(_ id: String, with requests: [NoteReminderRequest]) async {
        guard let scheduler else { return }
        let prefix = Self.identifierPrefix(for: id)
        let keep = Set(requests.map(\.identifier))
        let stale = await scheduler.pendingRequests().map(\.identifier).filter { $0.hasPrefix(prefix) && !keep.contains($0) }
        if !stale.isEmpty { scheduler.removeRequests(stale) }
        for request in requests { await scheduler.add(request) }
    }

    private func save() {
        let sorted = records.values.sorted { $0.id < $1.id }
        if sorted.isEmpty {
            defaults.removeObject(forKey: Self.recordsKey)
        } else if let data = try? PropertyListEncoder().encode(sorted) {
            defaults.set(data, forKey: Self.recordsKey)
        }
    }
}
