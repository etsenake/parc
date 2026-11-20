import Foundation

struct NoteBlockID: Hashable, Codable, CustomStringConvertible {
    let raw: UUID
    init() { raw = UUID() }
    init(_ raw: UUID) { self.raw = raw }
    var description: String { raw.uuidString }
}

enum NoteColor: String, CaseIterable, Codable, Hashable {
    case gray, brown, orange, yellow, green, blue, purple, pink, red
}

enum NoteColorStyle: Hashable, Codable {
    case text(NoteColor)
    case background(NoteColor)

    var color: NoteColor {
        switch self { case .text(let value), .background(let value): return value }
    }
    var isBackground: Bool {
        if case .background = self { return true }
        return false
    }
}

struct NoteDateMention: Hashable, Codable {
    var year: Int
    var month: Int
    var day: Int
    var hour: Int?
    var minute: Int?
    var remind = false

    var components: DateComponents {
        DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    }
    var includesTime: Bool { hour != nil }
}

enum NoteAtom: Hashable, Codable {
    case equation(String)
    case page(target: String, title: String)
    case date(NoteDateMention)
    case link(url: String, title: String)

    static let character = "\u{FFFC}"

    var fallbackText: String {
        switch self {
        case .equation(let source): return source
        case .page(_, let title): return title
        case .link(let url, let title): return title.isEmpty ? url : title
        case .date(let date):
            var value = String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
            if let hour = date.hour { value += String(format: " %02d:%02d", hour, date.minute ?? 0) }
            return value
        }
    }
}

enum NoteMarkKey: String, CaseIterable, Codable, Hashable {
    case bold, italic, underline, strikethrough, code
}

struct NoteMarks: Hashable, Codable {
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var code = false
    var link: String?
    var color: NoteColorStyle?
    var atom: NoteAtom?

    static let plain = NoteMarks()

    subscript(key: NoteMarkKey) -> Bool {
        get {
            switch key {
            case .bold: return bold
            case .italic: return italic
            case .underline: return underline
            case .strikethrough: return strikethrough
            case .code: return code
            }
        }
        set {
            switch key {
            case .bold: bold = newValue
            case .italic: italic = newValue
            case .underline: underline = newValue
            case .strikethrough: strikethrough = newValue
            case .code: code = newValue
            }
        }
    }

    var withoutAtom: NoteMarks {
        var value = self
        value.atom = nil
        return value
    }
    var isPlain: Bool { self == .plain }
}

struct NoteSpan: Hashable, Codable {
    var length: Int
    var marks: NoteMarks
}

struct NoteText: Hashable, Codable, ExpressibleByStringLiteral {
    private(set) var string: String
    private(set) var spans: [NoteSpan]

    init(_ string: String = "", marks: NoteMarks = .plain) {
        self.string = string
        let length = (string as NSString).length
        spans = length == 0 ? [] : [NoteSpan(length: length, marks: marks)]
    }

    init(stringLiteral value: String) { self.init(value) }

    init(pieces: [(String, NoteMarks)]) {
        var value = NoteText()
        for (text, marks) in pieces { value.append(NoteText(text, marks: marks)) }
        self = value
    }

    static func atom(_ atom: NoteAtom, marks: NoteMarks = .plain) -> NoteText {
        var value = marks
        value.atom = atom
        return NoteText(NoteAtom.character, marks: value)
    }

    var length: Int { (string as NSString).length }
    var isEmpty: Bool { string.isEmpty }

    var plainText: String {
        var result = ""
        for run in runs() {
            if let atom = run.marks.atom { result += atom.fallbackText }
            else { result += (string as NSString).substring(with: NSRange(location: run.range.lowerBound, length: run.range.count)) }
        }
        return result
    }

    func runs(in range: Range<Int>? = nil) -> [(range: Range<Int>, marks: NoteMarks)] {
        let bounds = range.map { clamp($0) } ?? 0..<length
        var result: [(range: Range<Int>, marks: NoteMarks)] = []
        var offset = 0
        for span in spans {
            let spanRange = offset..<(offset + span.length)
            offset += span.length
            let lower = max(spanRange.lowerBound, bounds.lowerBound), upper = min(spanRange.upperBound, bounds.upperBound)
            if lower < upper { result.append((lower..<upper, span.marks)) }
            if offset >= bounds.upperBound { break }
        }
        return result
    }

    func marks(at offset: Int) -> NoteMarks {
        guard !spans.isEmpty else { return .plain }
        let target = min(max(0, offset), length - 1)
        var position = 0
        for span in spans {
            if target < position + span.length { return span.marks }
            position += span.length
        }
        return spans.last?.marks ?? .plain
    }

    func typingMarks(at offset: Int) -> NoteMarks {
        guard offset > 0, !spans.isEmpty else {
            var first = spans.first?.marks.withoutAtom ?? .plain
            first.link = nil
            return offset == 0 ? first : .plain
        }
        var marks = self.marks(at: offset - 1).withoutAtom
        if offset >= length || self.marks(at: offset).link != marks.link { marks.link = nil }
        return marks
    }

    func slice(_ range: Range<Int>) -> NoteText {
        let bounds = clamp(range)
        var result = NoteText()
        result.string = (string as NSString).substring(with: NSRange(location: bounds.lowerBound, length: bounds.count))
        result.spans = runs(in: bounds).map { NoteSpan(length: $0.range.count, marks: $0.marks) }
        result.normalize()
        return result
    }

    mutating func replace(_ range: Range<Int>, with text: NoteText) {
        let bounds = clamp(range)
        let before = slice(0..<bounds.lowerBound), after = slice(bounds.upperBound..<length)
        var result = before
        result.append(text)
        result.append(after)
        self = result
    }

    mutating func insert(_ text: NoteText, at offset: Int) {
        replace(offset..<offset, with: text)
    }

    mutating func insert(_ value: String, at offset: Int) {
        insert(NoteText(value, marks: typingMarks(at: offset)), at: offset)
    }

    mutating func delete(_ range: Range<Int>) {
        replace(range, with: NoteText())
    }

    mutating func append(_ text: NoteText) {
        guard !text.isEmpty else { return }
        string += text.string
        spans += text.spans
        normalize()
    }

    static func + (lhs: NoteText, rhs: NoteText) -> NoteText {
        var value = lhs
        value.append(rhs)
        return value
    }

    mutating func updateMarks(in range: Range<Int>, _ transform: (inout NoteMarks) -> Void) {
        let bounds = clamp(range)
        guard !bounds.isEmpty else { return }
        var next: [NoteSpan] = []
        var offset = 0
        for span in spans {
            let spanRange = offset..<(offset + span.length)
            offset += span.length
            let lower = max(spanRange.lowerBound, bounds.lowerBound), upper = min(spanRange.upperBound, bounds.upperBound)
            guard lower < upper else { next.append(span); continue }
            if spanRange.lowerBound < lower { next.append(NoteSpan(length: lower - spanRange.lowerBound, marks: span.marks)) }
            var changed = span.marks
            let atom = changed.atom
            transform(&changed)
            changed.atom = atom
            next.append(NoteSpan(length: upper - lower, marks: changed))
            if upper < spanRange.upperBound { next.append(NoteSpan(length: spanRange.upperBound - upper, marks: span.marks)) }
        }
        spans = next
        normalize()
    }

    func allHave(_ key: NoteMarkKey, in range: Range<Int>) -> Bool {
        let selected = runs(in: range)
        return !selected.isEmpty && selected.allSatisfy { $0.marks[key] }
    }

    func trimmingTrailingNewlines() -> NoteText {
        var end = length
        let characters = string as NSString
        while end > 0, characters.character(at: end - 1) == 10 || characters.character(at: end - 1) == 13 { end -= 1 }
        return slice(0..<end)
    }

    private func clamp(_ range: Range<Int>) -> Range<Int> {
        let lower = min(max(0, range.lowerBound), length)
        let upper = min(max(lower, range.upperBound), length)
        return lower..<upper
    }

    private mutating func normalize() {
        var merged: [NoteSpan] = []
        for span in spans where span.length > 0 {
            if let last = merged.last, last.marks == span.marks, last.marks.atom == nil {
                merged[merged.count - 1].length += span.length
            } else {
                merged.append(span)
            }
        }
        spans = merged
    }
}

enum NoteBlockKind: String, Hashable, Codable, CaseIterable {
    case paragraph, heading, bulletedItem, numberedItem, todo, toggle, quote, callout, divider
    case code, equation, image, video, audio, file, bookmark, embed, table, tableOfContents
    case columns, column, pageLink, html, raw

    var hasRichText: Bool {
        switch self {
        case .paragraph, .heading, .bulletedItem, .numberedItem, .todo, .toggle, .quote, .callout: return true
        default: return false
        }
    }
    var hasPlainText: Bool {
        switch self {
        case .code, .equation, .html, .raw: return true
        default: return false
        }
    }
    var isMedia: Bool {
        switch self {
        case .image, .video, .audio, .file: return true
        default: return false
        }
    }
    var isListItem: Bool { self == .bulletedItem || self == .numberedItem || self == .todo }
    var acceptsChildren: Bool {
        switch self {
        case .bulletedItem, .numberedItem, .todo, .toggle, .quote, .callout, .columns, .column: return true
        default: return false
        }
    }
    var hasCaption: Bool {
        switch self {
        case .image, .video, .audio, .file, .bookmark, .embed, .code: return true
        default: return false
        }
    }
}

enum NoteAlignment: String, Hashable, Codable, CaseIterable {
    case left, center, right
}

struct NoteBookmark: Hashable, Codable {
    var title: String?
    var summary: String?
    var siteName: String?
    var iconURL: String?
    var imageURL: String?
}

struct NoteTable: Hashable, Codable {
    var rows: [[NoteText]]
    var headerRow = true
    var headerColumn = false
    var alignments: [NoteAlignment?] = []
    var columnWidths: [Double?] = []

    init(rows: [[NoteText]], headerRow: Bool = true, headerColumn: Bool = false) {
        self.rows = rows
        self.headerRow = headerRow
        self.headerColumn = headerColumn
        normalize()
    }

    static func empty(rows: Int = 3, columns: Int = 3) -> NoteTable {
        NoteTable(rows: Array(repeating: Array(repeating: NoteText(), count: max(1, columns)), count: max(1, rows)))
    }

    var columnCount: Int { rows.map(\.count).max() ?? 0 }
    var rowCount: Int { rows.count }

    mutating func normalize() {
        let columns = max(1, columnCount)
        if rows.isEmpty { rows = [Array(repeating: NoteText(), count: columns)] }
        for index in rows.indices where rows[index].count < columns {
            rows[index] += Array(repeating: NoteText(), count: columns - rows[index].count)
        }
        if alignments.count < columns { alignments += Array(repeating: nil, count: columns - alignments.count) }
        if alignments.count > columns { alignments.removeLast(alignments.count - columns) }
        if columnWidths.count < columns { columnWidths += Array(repeating: nil, count: columns - columnWidths.count) }
        if columnWidths.count > columns { columnWidths.removeLast(columnWidths.count - columns) }
    }
}

struct NoteBlockProps: Hashable, Codable {
    var level = 1
    var toggleable = false
    var expanded = true
    var checked = false
    var listStart: Int?
    var bulletMarker: String?
    var orderedDelimiter: String?
    var icon: String?
    var alert: String?
    var language = ""
    var wrap = false
    var fence: String?
    var source: String?
    var alt: String?
    var width: Double?
    var alignment: NoteAlignment = .center
    var caption = NoteText()
    var bookmark: NoteBookmark?
    var table: NoteTable?
    var target: String?
}

struct NoteBlock: Hashable, Identifiable, Codable {
    var id = NoteBlockID()
    var kind: NoteBlockKind
    var text = NoteText()
    var props = NoteBlockProps()
    var color: NoteColorStyle?
    var children: [NoteBlock] = []

    init(_ kind: NoteBlockKind, text: NoteText = NoteText(), props: NoteBlockProps = NoteBlockProps(),
         color: NoteColorStyle? = nil, children: [NoteBlock] = [], id: NoteBlockID = NoteBlockID()) {
        self.id = id
        self.kind = kind
        self.text = text
        self.props = props
        self.color = color
        self.children = children
    }

    static func paragraph(_ text: NoteText = NoteText()) -> NoteBlock { NoteBlock(.paragraph, text: text) }

    static func heading(_ level: Int, _ text: NoteText = NoteText()) -> NoteBlock {
        var props = NoteBlockProps()
        props.level = min(max(level, 1), 6)
        return NoteBlock(.heading, text: text, props: props)
    }

    var isToggle: Bool { kind == .toggle || (kind == .heading && props.toggleable) }
    var acceptsChildren: Bool { kind.acceptsChildren || (kind == .heading && props.toggleable) }
    var showsChildren: Bool { !isToggle || props.expanded }

    func withFreshIDs() -> NoteBlock {
        var copy = self
        copy.id = NoteBlockID()
        copy.children = children.map { $0.withFreshIDs() }
        return copy
    }
}

enum NotePageFont: String, Hashable, Codable, CaseIterable {
    case standard, serif, mono, wide
}

struct NoteCover: Hashable, Codable {
    var source: String
    var position = 0.5
}

enum NotePropertyValue: Hashable, Codable {
    case text(String)
    case number(Double)
    case checkbox(Bool)
    case date(String)
    case list([String])
}

struct NotePageProperty: Hashable, Codable {
    var key: String
    var value: NotePropertyValue
}

struct NotePageSettings: Hashable, Codable {
    var icon: String?
    var cover: NoteCover?
    var font: NotePageFont = .standard
    var smallText = false
    var fullWidth = false
    var locked = false
    var properties: [NotePageProperty] = []
    var preservedFrontMatter: [String] = []

    var isDefault: Bool { self == NotePageSettings() }
}

struct NotePage: Hashable, Codable {
    var settings = NotePageSettings()
    var blocks: [NoteBlock] = []

    init(settings: NotePageSettings = NotePageSettings(), blocks: [NoteBlock] = []) {
        self.settings = settings
        self.blocks = blocks
    }
}

struct NoteFlatBlock: Hashable {
    var id: NoteBlockID
    var parent: NoteBlockID?
    var depth: Int
    var indexInParent: Int
}

enum NoteInsertion: Hashable {
    case before(NoteBlockID)
    case after(NoteBlockID)
    case firstChild(of: NoteBlockID)
    case lastChild(of: NoteBlockID)
    case top(Int)
}

extension NotePage {
    func block(_ id: NoteBlockID) -> NoteBlock? {
        guard let path = path(of: id) else { return nil }
        return Self.block(at: path, in: blocks)
    }

    func path(of id: NoteBlockID) -> [Int]? {
        Self.path(of: id, in: blocks)
    }

    func parent(of id: NoteBlockID) -> NoteBlockID? {
        guard let path = path(of: id), path.count > 1 else { return nil }
        return Self.block(at: Array(path.dropLast()), in: blocks)?.id
    }

    func siblings(of id: NoteBlockID) -> [NoteBlock] {
        if let parent = parent(of: id) { return block(parent)?.children ?? [] }
        return blocks
    }

    func flattened(includingCollapsed: Bool = false) -> [NoteFlatBlock] {
        var result: [NoteFlatBlock] = []
        func walk(_ list: [NoteBlock], parent: NoteBlockID?, depth: Int) {
            for (index, block) in list.enumerated() {
                result.append(NoteFlatBlock(id: block.id, parent: parent, depth: depth, indexInParent: index))
                if includingCollapsed || block.showsChildren { walk(block.children, parent: block.id, depth: depth + 1) }
            }
        }
        walk(blocks, parent: nil, depth: 0)
        return result
    }

    func documentOrder(includingCollapsed: Bool = true) -> [NoteBlockID] {
        flattened(includingCollapsed: includingCollapsed).map(\.id)
    }

    func isAncestor(_ ancestor: NoteBlockID, of id: NoteBlockID) -> Bool {
        guard let outer = path(of: ancestor), let inner = path(of: id), inner.count > outer.count else { return false }
        return Array(inner.prefix(outer.count)) == outer
    }

    @discardableResult
    mutating func update(_ id: NoteBlockID, _ transform: (inout NoteBlock) -> Void) -> Bool {
        guard let path = path(of: id) else { return false }
        Self.update(at: path, in: &blocks, transform)
        return true
    }

    @discardableResult
    mutating func remove(_ id: NoteBlockID) -> NoteBlock? {
        guard let path = path(of: id) else { return nil }
        return Self.remove(at: path, in: &blocks)
    }

    @discardableResult
    mutating func insert(_ inserted: [NoteBlock], _ position: NoteInsertion) -> Bool {
        switch position {
        case .top(let index):
            blocks.insert(contentsOf: inserted, at: min(max(0, index), blocks.count))
            return true
        case .before(let id), .after(let id):
            guard let path = path(of: id) else { return false }
            let parentPath = Array(path.dropLast())
            var index = path.last!
            if case .after = position { index += 1 }
            if parentPath.isEmpty { blocks.insert(contentsOf: inserted, at: index); return true }
            Self.update(at: parentPath, in: &blocks) { $0.children.insert(contentsOf: inserted, at: index) }
            return true
        case .firstChild(let id):
            return update(id) { $0.children.insert(contentsOf: inserted, at: 0) }
        case .lastChild(let id):
            return update(id) { $0.children.append(contentsOf: inserted) }
        }
    }

    func allBlocks() -> [NoteBlock] {
        var result: [NoteBlock] = []
        func walk(_ list: [NoteBlock]) { for block in list { result.append(block); walk(block.children) } }
        walk(blocks)
        return result
    }

    var plainText: String {
        allBlocks().compactMap { block -> String? in
            if block.kind.hasRichText || block.kind.hasPlainText { return block.text.plainText }
            if let table = block.props.table { return table.rows.map { $0.map(\.plainText).joined(separator: "\t") }.joined(separator: "\n") }
            return nil
        }.joined(separator: "\n")
    }

    var wordCount: Int {
        var count = 0
        plainText.enumerateSubstrings(in: plainText.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in count += 1 }
        return count
    }

    private static func path(of id: NoteBlockID, in list: [NoteBlock]) -> [Int]? {
        for (index, block) in list.enumerated() {
            if block.id == id { return [index] }
            if let inner = path(of: id, in: block.children) { return [index] + inner }
        }
        return nil
    }

    private static func block(at path: [Int], in list: [NoteBlock]) -> NoteBlock? {
        guard let first = path.first, list.indices.contains(first) else { return nil }
        return path.count == 1 ? list[first] : block(at: Array(path.dropFirst()), in: list[first].children)
    }

    private static func update(at path: [Int], in list: inout [NoteBlock], _ transform: (inout NoteBlock) -> Void) {
        guard let first = path.first, list.indices.contains(first) else { return }
        if path.count == 1 { transform(&list[first]); return }
        update(at: Array(path.dropFirst()), in: &list[first].children, transform)
    }

    private static func remove(at path: [Int], in list: inout [NoteBlock]) -> NoteBlock? {
        guard let first = path.first, list.indices.contains(first) else { return nil }
        if path.count == 1 { return list.remove(at: first) }
        return remove(at: Array(path.dropFirst()), in: &list[first].children)
    }
}

enum NoteTextField: Hashable, Codable {
    case body
    case caption
    case cell(row: Int, column: Int)
}

struct NotePosition: Hashable, Codable {
    var block: NoteBlockID
    var offset: Int
    var field: NoteTextField = .body

    init(_ block: NoteBlockID, _ offset: Int, field: NoteTextField = .body) {
        self.block = block
        self.offset = offset
        self.field = field
    }
}

struct NoteTableCell: Hashable, Codable {
    var row: Int
    var column: Int
}

enum NotePageSelection: Hashable {
    case none
    case text(anchor: NotePosition, head: NotePosition)
    case blocks([NoteBlockID])
    case cells(table: NoteBlockID, anchor: NoteTableCell, head: NoteTableCell)

    static func caret(_ position: NotePosition) -> NotePageSelection { .text(anchor: position, head: position) }

    var isCollapsed: Bool {
        if case .text(let anchor, let head) = self { return anchor == head }
        return false
    }
    var caret: NotePosition? {
        if case .text(let anchor, let head) = self, anchor == head { return head }
        return nil
    }
}
