import AppKit

enum NoteFormatItem: String, CaseIterable, Hashable {
    case turnInto, link, bold, italic, underline, strikethrough, code, equation, color, mention

    var title: String {
        switch self {
        case .turnInto: return "Turn Into"
        case .link: return "Link"
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .underline: return "Underline"
        case .strikethrough: return "Strikethrough"
        case .code: return "Code"
        case .equation: return "Equation"
        case .color: return "Color"
        case .mention: return "Mention"
        }
    }

    var chord: NoteFormatShortcut? {
        switch self {
        case .link: return .link
        case .bold: return .bold
        case .italic: return .italic
        case .underline: return .underline
        case .strikethrough: return .strikethrough
        case .code: return .code
        case .equation: return .equation
        case .turnInto, .color, .mention: return nil
        }
    }

    var markKey: NoteMarkKey? {
        switch self {
        case .bold: return .bold
        case .italic: return .italic
        case .underline: return .underline
        case .strikethrough: return .strikethrough
        case .code: return .code
        default: return nil
        }
    }

    var group: Int {
        switch self {
        case .turnInto: return 0
        case .link: return 1
        case .bold, .italic, .underline, .strikethrough, .code, .equation: return 2
        case .color, .mention: return 3
        }
    }

    var opensMenu: Bool { self == .turnInto || self == .color || self == .link }

    static func items(for context: NoteFormatContext) -> [NoteFormatItem] {
        context == .body ? allCases : allCases.filter { $0 != .turnInto }
    }

    static func shortcutItem(for event: (characters: String?, flags: NSEvent.ModifierFlags)) -> NoteFormatItem? {
        allCases.first { $0.chord?.matches(characters: event.characters, flags: event.flags) == true }
    }
}

enum NoteTurnIntoOption: String, CaseIterable, Hashable {
    case text, heading1, heading2, heading3, heading4, bulletedList, numberedList, todoList, toggleList
    case code, quote, callout, blockEquation, toggleHeading1, toggleHeading2, toggleHeading3, toggleHeading4

    var title: String {
        switch self {
        case .text: return "Text"
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .heading4: return "Heading 4"
        case .bulletedList: return "Bulleted List"
        case .numberedList: return "Numbered List"
        case .todoList: return "To-do List"
        case .toggleList: return "Toggle List"
        case .code: return "Code"
        case .quote: return "Quote"
        case .callout: return "Callout"
        case .blockEquation: return "Block Equation"
        case .toggleHeading1: return "Toggle Heading 1"
        case .toggleHeading2: return "Toggle Heading 2"
        case .toggleHeading3: return "Toggle Heading 3"
        case .toggleHeading4: return "Toggle Heading 4"
        }
    }

    var kind: NoteBlockKind {
        switch self {
        case .text: return .paragraph
        case .heading1, .heading2, .heading3, .heading4, .toggleHeading1, .toggleHeading2, .toggleHeading3, .toggleHeading4: return .heading
        case .bulletedList: return .bulletedItem
        case .numberedList: return .numberedItem
        case .todoList: return .todo
        case .toggleList: return .toggle
        case .code: return .code
        case .quote: return .quote
        case .callout: return .callout
        case .blockEquation: return .equation
        }
    }

    var level: Int? {
        switch self {
        case .heading1, .toggleHeading1: return 1
        case .heading2, .toggleHeading2: return 2
        case .heading3, .toggleHeading3: return 3
        case .heading4, .toggleHeading4: return 4
        default: return nil
        }
    }

    var isToggleHeading: Bool { self == .toggleHeading1 || self == .toggleHeading2 || self == .toggleHeading3 || self == .toggleHeading4 }

    var chord: NoteFormatShortcut? {
        switch self {
        case .text: return NoteFormatShortcut("0", [.command, .option])
        case .heading1: return NoteFormatShortcut("1", [.command, .option])
        case .heading2: return NoteFormatShortcut("2", [.command, .option])
        case .heading3: return NoteFormatShortcut("3", [.command, .option])
        case .todoList: return NoteFormatShortcut("4", [.command, .option])
        case .bulletedList: return NoteFormatShortcut("5", [.command, .option])
        case .numberedList: return NoteFormatShortcut("6", [.command, .option])
        case .toggleList: return NoteFormatShortcut("7", [.command, .option])
        case .code: return NoteFormatShortcut("8", [.command, .option])
        default: return nil
        }
    }

    init?(block: NoteBlock) {
        switch block.kind {
        case .paragraph: self = .text
        case .heading:
            switch (block.props.level, block.props.toggleable) {
            case (1, false): self = .heading1
            case (2, false): self = .heading2
            case (3, false): self = .heading3
            case (4, false): self = .heading4
            case (1, true): self = .toggleHeading1
            case (2, true): self = .toggleHeading2
            case (3, true): self = .toggleHeading3
            case (4, true): self = .toggleHeading4
            default: return nil
            }
        case .bulletedItem: self = .bulletedList
        case .numberedItem: self = .numberedList
        case .todo: self = .todoList
        case .toggle: self = .toggleList
        case .code: self = .code
        case .quote: self = .quote
        case .callout: self = .callout
        case .equation: self = .blockEquation
        default: return nil
        }
    }

    func configure(_ props: inout NoteBlockProps) {
        if let level { props.level = level }
        if kind == .heading {
            props.toggleable = isToggleHeading
            if isToggleHeading { props.expanded = true }
        }
    }

    static func label(for block: NoteBlock) -> String {
        if let option = NoteTurnIntoOption(block: block) { return option.title }
        if block.kind == .heading { return (block.props.toggleable ? "Toggle Heading " : "Heading ") + String(block.props.level) }
        return NoteTurnIntoOption.text.title
    }
}

enum NoteFormatContext: Hashable { case body, caption, cell }

struct NoteColorSummary: Hashable {
    var text: NoteColor?
    var background: NoteColor?
    var isTextMixed = false
    var isBackgroundMixed = false
    var uniform: NoteColorStyle?

    static let plain = NoteColorSummary()

    init(text: NoteColor? = nil, background: NoteColor? = nil, isTextMixed: Bool = false,
         isBackgroundMixed: Bool = false, uniform: NoteColorStyle? = nil) {
        self.text = text
        self.background = background
        self.isTextMixed = isTextMixed
        self.isBackgroundMixed = isBackgroundMixed
        self.uniform = uniform
    }

    init(styles: [NoteColorStyle?]) {
        func textColor(_ style: NoteColorStyle?) -> NoteColor? {
            if case .text(let color) = style { return color }
            return nil
        }
        func backgroundColor(_ style: NoteColorStyle?) -> NoteColor? {
            if case .background(let color) = style { return color }
            return nil
        }
        let texts = styles.map(textColor), backgrounds = styles.map(backgroundColor)
        text = texts.first ?? nil
        background = backgrounds.first ?? nil
        isTextMixed = texts.contains { $0 != text }
        isBackgroundMixed = backgrounds.contains { $0 != background }
        if isTextMixed { text = nil }
        if isBackgroundMixed { background = nil }
        let first = styles.first ?? nil
        uniform = styles.allSatisfy { $0 == first } ? first : nil
    }
}

struct NoteFormatSegment: Hashable {
    var position: NotePosition
    var range: Range<Int>
}

struct NoteFormatState: Hashable {
    var selection: NotePageSelection
    var context: NoteFormatContext
    var segments: [NoteFormatSegment]
    var bodyBlocks: [NoteBlockID]
    var turnInto: NoteTurnIntoOption?
    var turnIntoLabel: String
    var isTurnIntoUniform: Bool
    var marks: Set<NoteMarkKey>
    var isEquation: Bool
    var link: String?
    var firstLink: String?
    var color: NoteColorSummary
    var selectedText: String

    var spansBlocks: Bool { segments.count > 1 }
    var items: [NoteFormatItem] { NoteFormatItem.items(for: context) }

    func isActive(_ item: NoteFormatItem) -> Bool {
        if let key = item.markKey { return marks.contains(key) }
        switch item {
        case .equation: return isEquation
        case .link: return link != nil
        case .color: return color.uniform != nil
        default: return false
        }
    }

    func isEnabled(_ item: NoteFormatItem) -> Bool {
        switch item {
        case .turnInto: return context == .body && !bodyBlocks.isEmpty
        case .equation: return !spansBlocks
        case .mention: return !spansBlocks && !isEquation
        default: return true
        }
    }

    @MainActor
    static func resolve(session: NotePageSession, selection: NotePageSelection? = nil,
                        isPlainText: Bool, isReadOnly: Bool) -> NoteFormatState? {
        let target = selection ?? session.selection
        guard case .text = target else { return nil }
        let segments = session.textSegments(of: target).map { NoteFormatSegment(position: $0.position, range: $0.range) }
        return resolve(page: session.page, selection: target, segments: segments, isPlainText: isPlainText, isReadOnly: isReadOnly)
    }

    static func resolve(page: NotePage, selection: NotePageSelection, segments: [NoteFormatSegment],
                        isPlainText: Bool, isReadOnly: Bool) -> NoteFormatState? {
        guard !isPlainText, !isReadOnly, case .text(let anchor, let head) = selection, anchor != head else { return nil }
        var rich: [(segment: NoteFormatSegment, block: NoteBlock, text: NoteText)] = []
        for segment in segments where !segment.range.isEmpty {
            guard let block = page.block(segment.position.block), isRichField(segment.position.field, of: block),
                  let text = block.text(in: segment.position.field) else { continue }
            let lower = min(max(0, segment.range.lowerBound), text.length)
            let upper = min(max(lower, segment.range.upperBound), text.length)
            guard lower < upper else { continue }
            rich.append((NoteFormatSegment(position: segment.position, range: lower..<upper), block, text))
        }
        guard let first = rich.first else { return nil }
        let context: NoteFormatContext
        switch first.segment.position.field {
        case .body: context = .body
        case .caption: context = .caption
        case .cell: context = .cell
        }
        let runs = rich.flatMap { entry in entry.text.runs(in: entry.segment.range).map(\.marks) }
        let marks = Set(NoteMarkKey.allCases.filter { key in runs.allSatisfy { $0[key] } })
        let links = runs.map(\.link)
        let firstRunLink = links.first ?? nil
        let commonLink = links.allSatisfy { $0 == firstRunLink } ? firstRunLink : nil
        let bodyEntries = rich.filter { $0.segment.position.field == .body }
        var seen = Set<NoteBlockID>()
        let bodyBlocks = bodyEntries.map(\.block.id).filter { seen.insert($0).inserted }
        let options = bodyEntries.map { NoteTurnIntoOption(block: $0.block) }
        let firstOption = options.first ?? nil
        let selectedText = rich.map { $0.text.slice($0.segment.range).plainText }.joined(separator: "\n")
        return NoteFormatState(
            selection: selection, context: context, segments: rich.map(\.segment), bodyBlocks: bodyBlocks,
            turnInto: firstOption,
            turnIntoLabel: bodyEntries.first.map { NoteTurnIntoOption.label(for: $0.block) } ?? NoteTurnIntoOption.text.title,
            isTurnIntoUniform: !options.isEmpty && options.allSatisfy { $0 == firstOption && $0 != nil },
            marks: marks,
            isEquation: runs.allSatisfy { if case .equation = $0.atom { return true } else { return false } },
            link: commonLink, firstLink: links.compactMap { $0 }.first,
            color: NoteColorSummary(styles: runs.map(\.color)),
            selectedText: selectedText)
    }

    static func isRichField(_ field: NoteTextField, of block: NoteBlock) -> Bool {
        switch field {
        case .body: return block.kind.hasRichText
        case .caption: return block.kind.hasCaption
        case .cell: return block.kind == .table
        }
    }
}

enum NoteColorChoice: Hashable {
    case text(NoteColor?)
    case background(NoteColor?)

    init(_ style: NoteColorStyle) {
        switch style {
        case .text(let color): self = .text(color)
        case .background(let color): self = .background(color)
        }
    }

    init?(id: String) {
        let parts = id.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let color: NoteColor?
        if parts[1] == "default" { color = nil } else if let value = NoteColor(rawValue: parts[1]) { color = value } else { return nil }
        switch parts[0] {
        case "text": self = .text(color)
        case "background": self = .background(color)
        default: return nil
        }
    }

    var id: String {
        switch self {
        case .text(let color): return "text." + (color?.rawValue ?? "default")
        case .background(let color): return "background." + (color?.rawValue ?? "default")
        }
    }

    var color: NoteColor? {
        switch self { case .text(let color), .background(let color): return color }
    }

    var isBackground: Bool {
        if case .background = self { return true }
        return false
    }

    var style: NoteColorStyle? {
        switch self {
        case .text(let color): return color.map { .text($0) }
        case .background(let color): return color.map { .background($0) }
        }
    }

    var title: String {
        let name = color.map { $0.rawValue.capitalized } ?? "Default"
        return name + (isBackground ? " Background" : " Text")
    }

    func apply(to marks: inout NoteMarks) {
        if let style { marks.color = style; return }
        switch (self, marks.color) {
        case (.text, .text?), (.background, .background?): marks.color = nil
        default: break
        }
    }

    static let textChoices: [NoteColorChoice] = [.text(nil)] + NoteColor.allCases.map { .text($0) }
    static let backgroundChoices: [NoteColorChoice] = [.background(nil)] + NoteColor.allCases.map { .background($0) }
}

struct NoteColorMenuModel: Hashable {
    struct Section: Hashable {
        var id: String
        var title: String
        var choices: [NoteColorChoice]
    }

    var sections: [Section]
    var summary: NoteColorSummary

    init(recents: [NoteColorStyle], summary: NoteColorSummary, backgroundsOnly: Bool = false) {
        self.summary = summary
        var sections: [Section] = []
        let recent = NoteColorRecents.normalized(backgroundsOnly ? recents.filter(\.isBackground) : recents).map(NoteColorChoice.init)
        if !recent.isEmpty { sections.append(Section(id: "recent", title: "Last Used", choices: recent)) }
        if !backgroundsOnly { sections.append(Section(id: "text", title: "Text", choices: NoteColorChoice.textChoices)) }
        sections.append(Section(id: "background", title: backgroundsOnly ? "Highlight" : "Background", choices: NoteColorChoice.backgroundChoices))
        self.sections = sections
    }

    func isChecked(_ choice: NoteColorChoice) -> Bool {
        switch choice {
        case .text(let color): return !summary.isTextMixed && summary.text == color
        case .background(let color): return !summary.isBackgroundMixed && summary.background == color
        }
    }

    var choices: [(section: Int, index: Int, choice: NoteColorChoice)] {
        sections.enumerated().flatMap { section, value in
            value.choices.enumerated().map { (section, $0.offset, $0.element) }
        }
    }

    func move(from current: (section: Int, index: Int)?, dx: Int, dy: Int) -> (section: Int, index: Int)? {
        guard !sections.isEmpty else { return nil }
        guard let current else { return (dy < 0 ? sections.count - 1 : 0, 0) }
        if dx != 0 {
            let flat = choices
            guard let position = flat.firstIndex(where: { $0.section == current.section && $0.index == current.index }) else { return (0, 0) }
            let next = flat[(position + dx + flat.count) % flat.count]
            return (next.section, next.index)
        }
        let section = (current.section + dy + sections.count) % sections.count
        return (section, min(current.index, sections[section].choices.count - 1))
    }
}

enum NoteColorRecents {
    static let key = "Parc.Notes.Color.Recents"
    static let limit = 5

    static func normalized(_ list: [NoteColorStyle]) -> [NoteColorStyle] {
        var seen = Set<NoteColorStyle>()
        return Array(list.filter { seen.insert($0).inserted }.prefix(limit))
    }

    static func pushing(_ style: NoteColorStyle, onto list: [NoteColorStyle]) -> [NoteColorStyle] {
        normalized([style] + list)
    }

    static func load(from defaults: UserDefaults = .standard) -> [NoteColorStyle] {
        normalized((defaults.stringArray(forKey: key) ?? []).compactMap { NoteColorChoice(id: $0)?.style })
    }

    static func record(_ style: NoteColorStyle, in defaults: UserDefaults = .standard) {
        defaults.set(pushing(style, onto: load(from: defaults)).map { NoteColorChoice($0).id }, forKey: key)
    }
}

enum NoteLinkInput {
    static let unsafeSchemes: Set<String> = ["javascript", "vbscript", "data"]

    static func isUnsafe(_ link: String) -> Bool {
        let scalars = link.unicodeScalars.filter { $0.value > 0x20 && $0.value != 0x7F && !$0.properties.isWhitespace }
        let compact = String(String.UnicodeScalarView(scalars))
        guard let colon = compact.firstIndex(of: ":") else { return false }
        return unsafeSchemes.contains(compact[..<colon].lowercased())
    }

    static func normalize(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("<", ">"), ("\"", "\""), ("'", "'"), ("(", ")")] where value.count >= 2 && value.hasPrefix(open) && value.hasSuffix(close) {
            value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !value.isEmpty, !value.contains(where: \.isNewline), !isUnsafe(value) else { return nil }
        if value.hasPrefix("#") { return value.count > 1 && !value.contains(" ") ? value : nil }
        if value.hasPrefix("~/") { value = (value as NSString).expandingTildeInPath }
        if value.hasPrefix("/") { return URL(fileURLWithPath: value).absoluteString }
        if value.hasPrefix("./") || value.hasPrefix("../") || isNotePath(value) { return encodePath(value) }
        if let scheme = scheme(of: value) { return normalizeSchemed(value, scheme: scheme) }
        if isEmail(value) { return "mailto:" + value }
        guard !value.contains(where: \.isWhitespace) else { return nil }
        let hostEnd = value.firstIndex { $0 == "/" || $0 == "?" || $0 == "#" } ?? value.endIndex
        let authority = String(value[..<hostEnd])
        guard let host = validHost(authority) else { return nil }
        let prefix = host == "localhost" || isIPv4(host) ? "http://" : "https://"
        guard let url = URL(string: prefix + value), url.host != nil else { return nil }
        return url.absoluteString
    }

    static func isRelative(_ link: String) -> Bool {
        scheme(of: link) == nil && !link.hasPrefix("#")
    }

    static func isNotePath(_ value: String) -> Bool {
        guard scheme(of: value) == nil, !value.hasPrefix("#") else { return false }
        let path = value.split(separator: "#", maxSplits: 1).first.map(String.init) ?? value
        let decoded = path.removingPercentEncoding ?? path
        return NoteFileKind(pathExtension: (decoded as NSString).pathExtension) != nil
    }

    static func displayText(_ link: String) -> String {
        if link.lowercased().hasPrefix("mailto:") { return String(link.dropFirst(7)) }
        guard let components = URLComponents(string: link), let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = components.host else {
            return link.removingPercentEncoding ?? link
        }
        var result = host
        if let port = components.port { result += ":" + String(port) }
        let path = components.percentEncodedPath
        if path != "/" { result += path.removingPercentEncoding ?? path }
        if let query = components.percentEncodedQuery { result += "?" + query }
        if let fragment = components.percentEncodedFragment { result += "#" + fragment }
        return result
    }

    static func scheme(of value: String) -> String? {
        guard let colon = value.firstIndex(of: ":") else { return nil }
        let candidate = value[..<colon]
        guard let first = candidate.first, first.isASCII, first.isLetter,
              candidate.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == ".") }) else { return nil }
        let rest = value[value.index(after: colon)...]
        let port = rest.prefix { $0.isNumber }
        if !port.isEmpty, port.count <= 5, rest.dropFirst(port.count).first.map({ $0 == "/" || $0 == "?" || $0 == "#" }) ?? true {
            return nil
        }
        return candidate.lowercased()
    }

    private static func normalizeSchemed(_ value: String, scheme: String) -> String? {
        let rest = value[value.index(after: value.firstIndex(of: ":")!)...]
        switch scheme {
        case "http", "https":
            guard !value.contains(where: \.isWhitespace), let url = URL(string: value),
                  let host = url.host, !host.isEmpty else { return nil }
            return url.absoluteString
        case "mailto":
            return rest.contains("@") && !rest.contains(where: \.isWhitespace) ? value : nil
        case "file":
            return URL(string: value) != nil ? value : URL(string: value.replacingOccurrences(of: " ", with: "%20"))?.absoluteString
        default:
            guard !rest.isEmpty, !value.contains(where: \.isWhitespace) else { return nil }
            return value
        }
    }

    private static func encodePath(_ value: String) -> String? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.insert(charactersIn: "#")
        let decoded = value.removingPercentEncoding ?? value
        return decoded.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    private static func isEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !value.contains(where: { $0.isWhitespace || $0 == "/" }) else { return false }
        return validHost(String(parts[1])) != nil && parts[1].contains(".")
    }

    private static func validHost(_ authority: String) -> String? {
        var host = authority
        if let colon = authority.lastIndex(of: ":") {
            let port = authority[authority.index(after: colon)...]
            guard !port.isEmpty, port.count <= 5, port.allSatisfy(\.isNumber) else { return nil }
            host = String(authority[..<colon])
        }
        host = host.lowercased()
        if host == "localhost" || isIPv4(host) { return host }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, let tld = labels.last, tld.count >= 2, tld.allSatisfy(\.isLetter) else { return nil }
        for label in labels {
            guard !label.isEmpty, label.count <= 63, !label.hasPrefix("-"), !label.hasSuffix("-"),
                  label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        }
        return host
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            !part.isEmpty && part.count <= 3 && part.allSatisfy(\.isNumber) && (Int(part) ?? 256) <= 255
        }
    }
}

struct NoteFormatBarPlacement: Hashable {
    enum Edge: Hashable { case above, below, pinned }

    var frame: NSRect
    var edge: Edge

    static let gap: CGFloat = 8
    static let margin: CGFloat = 8

    static func lines(of rects: [NSRect]) -> (top: NSRect, bottom: NSRect, union: NSRect)? {
        let usable = rects.filter { $0.height > 0 && !$0.isNull && !$0.isInfinite }
        guard let first = usable.first else { return nil }
        let union = usable.dropFirst().reduce(first) { $0.union($1) }
        let top = union.minY, bottom = union.maxY
        let topLine = usable.filter { $0.minY < top + 1 }
        let bottomLine = usable.filter { $0.maxY > bottom - 1 }
        return (topLine.dropFirst().reduce(topLine[0]) { $0.union($1) },
                bottomLine.dropFirst().reduce(bottomLine[0]) { $0.union($1) }, union)
    }

    static func compute(lineRects: [NSRect], size: NSSize, visible: NSRect,
                        gap: CGFloat = gap, margin: CGFloat = margin) -> NoteFormatBarPlacement? {
        guard let lines = lines(of: lineRects), lines.union.intersects(visible) else { return nil }
        let edge: Edge
        let y: CGFloat
        let centre: CGFloat
        if lines.top.minY - gap - size.height >= visible.minY + margin {
            edge = .above
            y = lines.top.minY - gap - size.height
            centre = lines.top.midX
        } else if lines.bottom.maxY + gap + size.height <= visible.maxY - margin {
            edge = .below
            y = lines.bottom.maxY + gap
            centre = lines.bottom.midX
        } else {
            edge = .pinned
            y = visible.minY + margin
            let shown = lines.union.intersection(visible)
            centre = lines.top.intersects(visible) ? lines.top.midX : shown.midX
        }
        let x = clampX(centre - size.width / 2, width: size.width, visible: visible, margin: margin)
        return NoteFormatBarPlacement(frame: NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height), edge: edge)
    }

    static func dropdown(anchor: NSRect, size: NSSize, visible: NSRect, preferAbove: Bool = false,
                         gap: CGFloat = 6, margin: CGFloat = margin) -> NoteFormatBarPlacement {
        let roomBelow = visible.maxY - margin - (anchor.maxY + gap)
        let roomAbove = anchor.minY - gap - (visible.minY + margin)
        let fitsBelow = roomBelow >= size.height, fitsAbove = roomAbove >= size.height
        let above = preferAbove ? (fitsAbove || !fitsBelow && roomAbove > roomBelow) : (!fitsBelow && (fitsAbove || roomAbove > roomBelow))
        var y = above ? anchor.minY - gap - size.height : anchor.maxY + gap
        y = min(max(y, visible.minY + margin), max(visible.minY + margin, visible.maxY - margin - size.height))
        let x = clampX(anchor.minX, width: size.width, visible: visible, margin: margin)
        return NoteFormatBarPlacement(frame: NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height),
                                      edge: above ? .above : .below)
    }

    private static func clampX(_ x: CGFloat, width: CGFloat, visible: NSRect, margin: CGFloat) -> CGFloat {
        max(visible.minX + margin, min(x, visible.maxX - margin - width))
    }
}

enum NoteFormatBarFocus {
    static func move(from current: Int?, by delta: Int, enabled: [Bool]) -> Int? {
        let candidates = enabled.indices.filter { enabled[$0] }
        guard !candidates.isEmpty else { return nil }
        guard let current, let position = candidates.firstIndex(of: current) else {
            return delta < 0 ? candidates.last : candidates.first
        }
        return candidates[(position + delta % candidates.count + candidates.count) % candidates.count]
    }
}

enum NoteLinkSpan {
    static func at(_ offset: Int, in text: NoteText) -> (range: Range<Int>, link: String)? {
        guard offset >= 0, offset < text.length, let link = text.marks(at: offset).link else { return nil }
        let runs = text.runs()
        guard let index = runs.firstIndex(where: { $0.range.contains(offset) }) else { return nil }
        var lower = runs[index].range.lowerBound, upper = runs[index].range.upperBound
        var before = index - 1
        while before >= 0, runs[before].marks.link == link, runs[before].range.upperBound == lower {
            lower = runs[before].range.lowerBound
            before -= 1
        }
        var after = index + 1
        while after < runs.count, runs[after].marks.link == link, runs[after].range.lowerBound == upper {
            upper = runs[after].range.upperBound
            after += 1
        }
        return (lower..<upper, link)
    }
}

enum NoteInlineEquation {
    static func wrap(_ text: NoteText, range: Range<Int>) -> (text: NoteText, atom: Range<Int>)? {
        let lower = min(max(0, range.lowerBound), text.length), upper = min(max(lower, range.upperBound), text.length)
        let characters = text.string as NSString
        var start = lower, end = upper
        while start < end, isSpace(characters.character(at: start)) { start += 1 }
        while end > start, isSpace(characters.character(at: end - 1)) { end -= 1 }
        guard start < end else { return nil }
        let source = text.slice(start..<end).plainText
        var marks = text.marks(at: start).withoutAtom
        marks.code = false
        marks.link = nil
        var result = text
        result.replace(start..<end, with: .atom(.equation(source), marks: marks))
        return (result, start..<(start + 1))
    }

    static func unwrap(_ text: NoteText, range: Range<Int>) -> (text: NoteText, range: Range<Int>) {
        var replacement = NoteText()
        for run in text.runs(in: range) {
            if case .equation(let source) = run.marks.atom {
                replacement.append(NoteText(source, marks: run.marks.withoutAtom))
            } else {
                replacement.append(text.slice(run.range))
            }
        }
        var result = text
        let lower = min(max(0, range.lowerBound), text.length)
        result.replace(range, with: replacement)
        return (result, lower..<(lower + replacement.length))
    }

    private static func isSpace(_ character: unichar) -> Bool {
        character == 32 || character == 9 || character == 0xA0
    }
}
