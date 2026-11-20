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
    var end: NoteDateEnd?
    var remindBefore: Int?
    var timeZone: String?
    var format: NoteDateFormat?
    var timeFormat: NoteTimeFormat?

    var components: DateComponents {
        DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    }
    var includesTime: Bool { hour != nil }
    var reminderLead: Int { remind ? max(0, remindBefore ?? 0) : 0 }
}

struct NoteDateEnd: Hashable, Codable {
    var year: Int
    var month: Int
    var day: Int
    var hour: Int?
    var minute: Int?

    var components: DateComponents {
        DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    }
}

enum NoteDateFormat: String, CaseIterable, Codable, Hashable {
    case full, short
    case monthDayYear = "mdy"
    case dayMonthYear = "dmy"
    case yearMonthDay = "ymd"
}

enum NoteTimeFormat: String, CaseIterable, Codable, Hashable {
    case twelveHour = "12h"
    case twentyFourHour = "24h"
}

enum NoteAtom: Hashable, Codable {
    case equation(String)
    case page(target: String, title: String)
    case date(NoteDateMention)
    case link(url: String, title: String)
    case raw(String)
    case customEmoji(String)

    static let character = "\u{FFFC}"

    var fallbackText: String {
        switch self {
        case .equation(let source): return source
        case .page(_, let title): return title
        case .link(let url, let title): return title.isEmpty ? url : title
        case .raw(let source): return source
        case .customEmoji(let name): return NoteCustomEmojiName.reference(name)
        case .date(let date):
            var value = String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
            if let hour = date.hour { value += String(format: " %02d:%02d", hour, date.minute ?? 0) }
            guard let end = date.end else { return value }
            value += String(format: " \u{2192} %04d-%02d-%02d", end.year, end.month, end.day)
            if let hour = end.hour { value += String(format: " %02d:%02d", hour, end.minute ?? 0) }
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
    var isPlain: Bool { spans.allSatisfy { $0.marks.isPlain } }

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
        guard !spans.isEmpty else { return .plain }
        let caret = min(max(0, offset), length)
        if caret == 0 {
            var leading = marks(at: 0).withoutAtom
            leading.link = nil
            return leading
        }
        var marks = self.marks(at: caret - 1).withoutAtom
        if self.marks(at: caret - 1).atom != nil { marks.link = nil }
        if caret >= length || self.marks(at: caret).link != marks.link { marks.link = nil }
        return marks
    }

    func linkRange(at offset: Int) -> Range<Int>? {
        let caret = min(max(0, offset), length)
        let probe = caret < length && marks(at: caret).link != nil ? caret : caret - 1
        guard probe >= 0, probe < length, let link = marks(at: probe).link else { return nil }
        let all = runs()
        guard let hit = all.firstIndex(where: { $0.range.contains(probe) }) else { return nil }
        var lower = hit, upper = hit
        while lower > 0, all[lower - 1].marks.link == link { lower -= 1 }
        while upper + 1 < all.count, all[upper + 1].marks.link == link { upper += 1 }
        return all[lower].range.lowerBound..<all[upper].range.upperBound
    }

    func composedRange(before offset: Int) -> Range<Int>? {
        let caret = min(max(0, offset), length)
        guard caret > 0 else { return nil }
        let range = (string as NSString).rangeOfComposedCharacterSequence(at: caret - 1)
        return range.location..<caret
    }

    func composedRange(after offset: Int) -> Range<Int>? {
        let caret = min(max(0, offset), length)
        guard caret < length else { return nil }
        let range = (string as NSString).rangeOfComposedCharacterSequence(at: caret)
        return caret..<(range.location + range.length)
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
    case code, equation, image, video, audio, file, pdf, bookmark, embed, table, tableOfContents
    case columns, column, pageLink, html, raw, synced

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
    var hasText: Bool { hasRichText || hasPlainText }
    var isMedia: Bool {
        switch self {
        case .image, .video, .audio, .file, .pdf: return true
        default: return false
        }
    }
    var isListItem: Bool { self == .bulletedItem || self == .numberedItem || self == .todo }
    var isColumnStructure: Bool { self == .columns || self == .column }
    var acceptsChildren: Bool { hasRichText || isColumnStructure || self == .synced }
    var hasCaption: Bool {
        switch self {
        case .image, .video, .audio, .file, .pdf, .bookmark, .embed, .code: return true
        default: return false
        }
    }
    var supportsColor: Bool { hasRichText || self == .tableOfContents || self == .table }
}

enum NoteDiagramMode: String, Codable, CaseIterable, Hashable, Sendable {
    case code, preview, split

    var title: String {
        switch self {
        case .code: return "Code"
        case .preview: return "Preview"
        case .split: return "Split"
        }
    }

    var showsCode: Bool { self != .preview }
    var showsDiagram: Bool { self != .code }
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

    func cell(_ row: Int, _ column: Int) -> NoteText? {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return nil }
        return rows[row][column]
    }

    mutating func insertRow(at index: Int) {
        normalize()
        rows.insert(Array(repeating: NoteText(), count: max(1, columnCount)), at: min(max(0, index), rows.count))
    }

    @discardableResult
    mutating func deleteRow(at index: Int) -> Bool {
        guard rows.count > 1, rows.indices.contains(index) else { return false }
        rows.remove(at: index)
        return true
    }

    @discardableResult
    mutating func duplicateRow(at index: Int) -> Bool {
        guard rows.indices.contains(index) else { return false }
        rows.insert(rows[index], at: index + 1)
        return true
    }

    @discardableResult
    mutating func moveRow(from source: Int, to destination: Int) -> Bool {
        guard rows.indices.contains(source), rows.indices.contains(destination), source != destination else { return false }
        let row = rows.remove(at: source)
        rows.insert(row, at: destination)
        return true
    }

    mutating func insertColumn(at index: Int) {
        normalize()
        let position = min(max(0, index), columnCount)
        for row in rows.indices { rows[row].insert(NoteText(), at: position) }
        alignments.insert(nil, at: position)
        columnWidths.insert(nil, at: position)
    }

    @discardableResult
    mutating func deleteColumn(at index: Int) -> Bool {
        normalize()
        guard columnCount > 1, index >= 0, index < columnCount else { return false }
        for row in rows.indices { rows[row].remove(at: index) }
        alignments.remove(at: index)
        columnWidths.remove(at: index)
        return true
    }

    @discardableResult
    mutating func duplicateColumn(at index: Int) -> Bool {
        normalize()
        guard index >= 0, index < columnCount else { return false }
        for row in rows.indices { rows[row].insert(rows[row][index], at: index + 1) }
        alignments.insert(alignments[index], at: index + 1)
        columnWidths.insert(columnWidths[index], at: index + 1)
        return true
    }

    @discardableResult
    mutating func moveColumn(from source: Int, to destination: Int) -> Bool {
        normalize()
        let count = columnCount
        guard source >= 0, source < count, destination >= 0, destination < count, source != destination else { return false }
        for row in rows.indices {
            let cell = rows[row].remove(at: source)
            rows[row].insert(cell, at: destination)
        }
        let alignment = alignments.remove(at: source)
        alignments.insert(alignment, at: destination)
        let width = columnWidths.remove(at: source)
        columnWidths.insert(width, at: destination)
        return true
    }

    mutating func setColumnWidth(_ width: Double?, at index: Int) {
        normalize()
        guard columnWidths.indices.contains(index) else { return }
        columnWidths[index] = width.map { max(NoteTable.minimumColumnWidth, $0) }
    }

    mutating func setAlignment(_ alignment: NoteAlignment?, at index: Int) {
        normalize()
        guard alignments.indices.contains(index) else { return }
        alignments[index] = alignment
    }

    static let minimumColumnWidth = 32.0

    static func movedIndex(_ index: Int, from source: Int, to destination: Int) -> Int {
        if index == source { return destination }
        if source < destination, index > source, index <= destination { return index - 1 }
        if destination < source, index >= destination, index < source { return index + 1 }
        return index
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
    var looseList = false
    var icon: String?
    var alert: String?
    var language = ""
    var wrap = false
    var fence: String?
    var info: String?
    var source: String?
    var alt: String?
    var crop: NoteImageCrop?
    var mask: NoteImageMask?
    var width: Double?
    var height: Double?
    var alignment: NoteAlignment = .center
    var caption = NoteText()
    var bookmark: NoteBookmark?
    var table: NoteTable?
    var target: String?
    var anchor: String?
    var diagramMode: NoteDiagramMode?
    var credit: NoteMediaCredit?
}

private final class NoteBlockPropsStorage {
    var value: NoteBlockProps
    init(_ value: NoteBlockProps) { self.value = value }
}

struct NoteBlock: Hashable, Identifiable, Codable {
    var id = NoteBlockID()
    var kind: NoteBlockKind
    var text = NoteText()
    var color: NoteColorStyle?
    var children: [NoteBlock] = []
    private var propsStorage: NoteBlockPropsStorage

    var props: NoteBlockProps {
        get { propsStorage.value }
        set {
            if isKnownUniquelyReferenced(&propsStorage) { propsStorage.value = newValue }
            else { propsStorage = NoteBlockPropsStorage(newValue) }
        }
    }

    init(_ kind: NoteBlockKind, text: NoteText = NoteText(), props: NoteBlockProps = NoteBlockProps(),
         color: NoteColorStyle? = nil, children: [NoteBlock] = [], id: NoteBlockID = NoteBlockID()) {
        self.id = id
        self.kind = kind
        self.text = text
        self.propsStorage = NoteBlockPropsStorage(props)
        self.color = color
        self.children = children
    }

    private enum CodingKeys: String, CodingKey { case id, kind, text, props, color, children }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(NoteBlockID.self, forKey: .id) ?? NoteBlockID()
        kind = try container.decode(NoteBlockKind.self, forKey: .kind)
        text = try container.decodeIfPresent(NoteText.self, forKey: .text) ?? NoteText()
        propsStorage = NoteBlockPropsStorage(try container.decodeIfPresent(NoteBlockProps.self, forKey: .props) ?? NoteBlockProps())
        color = try container.decodeIfPresent(NoteColorStyle.self, forKey: .color)
        children = try container.decodeIfPresent([NoteBlock].self, forKey: .children) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(text, forKey: .text)
        try container.encode(props, forKey: .props)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encode(children, forKey: .children)
    }

    static func == (lhs: NoteBlock, rhs: NoteBlock) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.color == rhs.color && lhs.text == rhs.text
            && (lhs.propsStorage === rhs.propsStorage || lhs.propsStorage.value == rhs.propsStorage.value)
            && lhs.children == rhs.children
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(kind)
        hasher.combine(text)
        hasher.combine(props)
        hasher.combine(color)
        hasher.combine(children)
    }

    static func paragraph(_ text: NoteText = NoteText()) -> NoteBlock { NoteBlock(.paragraph, text: text) }

    static func heading(_ level: Int, _ text: NoteText = NoteText()) -> NoteBlock {
        var props = NoteBlockProps()
        props.level = min(max(level, 1), 6)
        return NoteBlock(.heading, text: text, props: props)
    }

    var isToggle: Bool { kind == .toggle || (kind == .heading && props.toggleable) }
    var isSyncedOriginal: Bool { kind == .synced && props.target == nil }
    var isSyncedCopy: Bool { kind == .synced && props.target != nil }
    var acceptsChildren: Bool { kind.acceptsChildren }
    var showsChildren: Bool { !isToggle || props.expanded }
    var isCollapsed: Bool { isToggle && !props.expanded }

    func sameContent(as other: NoteBlock) -> Bool {
        kind == other.kind && text == other.text && color == other.color
            && (propsStorage === other.propsStorage || props == other.props)
            && children.count == other.children.count
            && zip(children, other.children).allSatisfy { $0.id == $1.id }
    }

    fileprivate var indexSignature: NoteBlockIndexSignature {
        NoteBlockIndexSignature(id: id, kind: kind, toggleable: props.toggleable, expanded: props.expanded, listStart: props.listStart)
    }

    func withFreshIDs() -> NoteBlock {
        var copy = self
        copy.id = NoteBlockID()
        if copy.props.anchor != nil { copy.props.anchor = nil }
        copy.children = children.map { $0.withFreshIDs() }
        return copy
    }

    func lastDescendant() -> NoteBlock {
        var current = self
        while let last = current.children.last { current = last }
        return current
    }

    func lastVisibleDescendant() -> NoteBlock {
        var current = self
        while current.showsChildren, let last = current.children.last { current = last }
        return current
    }
}

private struct NoteBlockIndexSignature: Equatable {
    var id: NoteBlockID
    var kind: NoteBlockKind
    var toggleable: Bool
    var expanded: Bool
    var listStart: Int?
}

enum NotePageFont: String, Hashable, Codable, CaseIterable {
    case standard, serif, mono, wide
}

enum NoteBacklinksDisplay: String, Hashable, Codable, CaseIterable {
    case expanded, popup, off
}

struct NoteCover: Hashable, Codable {
    var source: String
    var position = 0.5
    var credit: NoteMediaCredit?
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
    var backlinks: NoteBacklinksDisplay?
    var properties: [NotePageProperty] = []
    var preservedFrontMatter: [String] = []

    var isDefault: Bool { self == NotePageSettings() }

    var backlinksDisplay: NoteBacklinksDisplay {
        get { backlinks ?? .popup }
        set { backlinks = newValue == .popup ? nil : newValue }
    }
}

struct NoteListNumber: Hashable {
    var value: Int
    var level: Int

    var label: String {
        switch level % 3 {
        case 1: return (NoteListNumber.letters(value) ?? String(value)) + "."
        case 2: return (NoteListNumber.roman(value) ?? String(value)) + "."
        default: return String(value) + "."
        }
    }

    static func letters(_ value: Int) -> String? {
        guard value > 0 else { return nil }
        var remaining = value
        var result = ""
        while remaining > 0 {
            remaining -= 1
            result = String(Character(UnicodeScalar(UInt8(97 + remaining % 26)))) + result
            remaining /= 26
        }
        return result
    }

    static func roman(_ value: Int) -> String? {
        guard value > 0, value < 4000 else { return nil }
        let table: [(Int, String)] = [(1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"),
                                      (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")]
        var remaining = value
        var result = ""
        for (amount, symbol) in table {
            while remaining >= amount { result += symbol; remaining -= amount }
        }
        return result
    }
}

struct NotePageIndex {
    struct Entry {
        var path: [Int]
        var parent: NoteBlockID?
        var depth: Int
        var order: Int
        var visibleOrder: Int?
    }

    private(set) var entries: [NoteBlockID: Entry] = [:]
    private(set) var all: [NoteFlatBlock] = []
    private(set) var visible: [NoteFlatBlock] = []
    private(set) var allIDs: [NoteBlockID] = []
    private(set) var visibleIDs: [NoteBlockID] = []
    private(set) var numbers: [NoteBlockID: NoteListNumber] = [:]

    init(_ blocks: [NoteBlock]) {
        var path: [Int] = []
        func walk(_ list: [NoteBlock], parent: NoteBlockID?, depth: Int, isVisible: Bool, numberedLevel: Int) {
            var previous: Int?
            for (index, block) in list.enumerated() {
                path.append(index)
                let flat = NoteFlatBlock(id: block.id, parent: parent, depth: depth, indexInParent: index)
                var visibleOrder: Int?
                if isVisible {
                    visibleOrder = visible.count
                    visible.append(flat)
                    visibleIDs.append(block.id)
                }
                entries[block.id] = Entry(path: path, parent: parent, depth: depth, order: all.count, visibleOrder: visibleOrder)
                all.append(flat)
                allIDs.append(block.id)
                if block.kind == .numberedItem {
                    let value = previous.map { $0 + 1 } ?? (block.props.listStart ?? 1)
                    numbers[block.id] = NoteListNumber(value: value, level: numberedLevel)
                    previous = value
                } else {
                    previous = nil
                }
                if !block.children.isEmpty {
                    walk(block.children, parent: block.id, depth: depth + 1, isVisible: isVisible && block.showsChildren,
                         numberedLevel: numberedLevel + (block.kind == .numberedItem ? 1 : 0))
                }
                path.removeLast()
            }
        }
        walk(blocks, parent: nil, depth: 0, isVisible: true, numberedLevel: 0)
    }
}

private final class NotePageIndexStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var built: NotePageIndex?

    func index(for blocks: [NoteBlock]) -> NotePageIndex {
        lock.lock()
        defer { lock.unlock() }
        if let built { return built }
        let value = NotePageIndex(blocks)
        built = value
        return value
    }
}

struct NotePage: Hashable, Codable {
    var settings = NotePageSettings()
    var blocks: [NoteBlock] = [] { didSet { indexStorage = NotePageIndexStorage() } }
    private var indexStorage = NotePageIndexStorage()

    init(settings: NotePageSettings = NotePageSettings(), blocks: [NoteBlock] = []) {
        self.settings = settings
        self.blocks = blocks
    }

    private enum CodingKeys: String, CodingKey { case settings, blocks }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settings = try container.decodeIfPresent(NotePageSettings.self, forKey: .settings) ?? NotePageSettings()
        blocks = try container.decodeIfPresent([NoteBlock].self, forKey: .blocks) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(settings, forKey: .settings)
        try container.encode(blocks, forKey: .blocks)
    }

    static func == (lhs: NotePage, rhs: NotePage) -> Bool {
        lhs.settings == rhs.settings && lhs.blocks == rhs.blocks
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(settings)
        hasher.combine(blocks)
    }

    var index: NotePageIndex { indexStorage.index(for: blocks) }

    var withoutIndex: NotePage {
        var copy = self
        copy.indexStorage = NotePageIndexStorage()
        return copy
    }

    fileprivate mutating func keepingIndex(_ body: (inout [NoteBlock]) -> Bool) {
        let storage = indexStorage
        if body(&blocks) { indexStorage = storage }
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
        index.entries[id]?.path
    }

    func contains(_ id: NoteBlockID) -> Bool {
        index.entries[id] != nil
    }

    func parent(of id: NoteBlockID) -> NoteBlockID? {
        index.entries[id]?.parent
    }

    func depth(of id: NoteBlockID) -> Int? {
        index.entries[id]?.depth
    }

    func ancestors(of id: NoteBlockID) -> [NoteBlockID] {
        var result: [NoteBlockID] = []
        var current = parent(of: id)
        while let value = current {
            result.append(value)
            current = parent(of: value)
        }
        return result
    }

    func siblings(of id: NoteBlockID) -> [NoteBlock] {
        if let parent = parent(of: id) { return block(parent)?.children ?? [] }
        return blocks
    }

    func documentPosition(of id: NoteBlockID) -> Int? {
        index.entries[id]?.order
    }

    func visiblePosition(of id: NoteBlockID) -> Int? {
        index.entries[id]?.visibleOrder
    }

    func isVisible(_ id: NoteBlockID) -> Bool {
        visiblePosition(of: id) != nil
    }

    func flattened(includingCollapsed: Bool = false) -> [NoteFlatBlock] {
        includingCollapsed ? index.all : index.visible
    }

    func documentOrder(includingCollapsed: Bool = true) -> [NoteBlockID] {
        includingCollapsed ? index.allIDs : index.visibleIDs
    }

    func isAncestor(_ ancestor: NoteBlockID, of id: NoteBlockID) -> Bool {
        guard ancestor != id, contains(ancestor) else { return false }
        var current = parent(of: id)
        while let value = current {
            if value == ancestor { return true }
            current = parent(of: value)
        }
        return false
    }

    func containingColumn(of id: NoteBlockID) -> NoteBlockID? {
        var current = parent(of: id)
        while let value = current {
            if block(value)?.kind == .column { return value }
            current = parent(of: value)
        }
        return nil
    }

    func numberLabel(for id: NoteBlockID) -> String? {
        index.numbers[id]?.label
    }

    func listNumber(for id: NoteBlockID) -> NoteListNumber? {
        index.numbers[id]
    }

    func columnFractions(of id: NoteBlockID) -> [Double] {
        guard let columns = block(id), columns.kind == .columns, !columns.children.isEmpty else { return [] }
        let widths = columns.children.map { $0.props.width.map { max(0, $0) } }
        let known = widths.compactMap { $0 }.reduce(0, +)
        let unknown = widths.filter { $0 == nil }.count
        let share = unknown == 0 ? 0 : (known < 1 ? (1 - known) / Double(unknown) : 1 / Double(columns.children.count))
        let raw = widths.map { $0 ?? share }
        let total = raw.reduce(0, +)
        guard total > 0 else { return Array(repeating: 1 / Double(raw.count), count: raw.count) }
        return raw.map { $0 / total }
    }

    @discardableResult
    mutating func update(_ id: NoteBlockID, _ transform: (inout NoteBlock) -> Void) -> Bool {
        guard let path = path(of: id) else { return false }
        keepingIndex { list in
            var neutral = true
            Self.update(at: path, in: &list) { block in
                let signature = block.indexSignature
                let children = block.children
                transform(&block)
                neutral = block.indexSignature == signature && block.children == children
            }
            return neutral
        }
        return true
    }

    mutating func updateBlocks(_ ids: some Sequence<NoteBlockID>, _ transform: (inout NoteBlock) -> Void) {
        let paths = Set(ids).compactMap { path(of: $0) }.sorted { $0.lexicographicallyPrecedes($1) }
        guard !paths.isEmpty else { return }
        keepingIndex { list in
            var neutral = true
            for path in paths {
                Self.update(at: path, in: &list) { block in
                    let signature = block.indexSignature
                    let children = block.children
                    transform(&block)
                    if block.indexSignature != signature || block.children != children { neutral = false }
                }
            }
            return neutral
        }
    }

    mutating func convertBlocks(_ ids: some Sequence<NoteBlockID>, _ convert: (NoteBlock) -> NoteBlock?) {
        let paths = Set(ids).compactMap { path(of: $0) }.sorted { $0.lexicographicallyPrecedes($1) }
        for location in paths.reversed() {
            guard let current = Self.block(at: location, in: blocks), let converted = convert(current) else { continue }
            var replacement = converted
            let lifted = replacement.acceptsChildren ? [] : replacement.children
            if !lifted.isEmpty { replacement.children = [] }
            let parentPath = Array(location.dropLast())
            let index = location.last!
            if parentPath.isEmpty {
                blocks[index] = replacement
                blocks.insert(contentsOf: lifted, at: index + 1)
            } else {
                Self.update(at: parentPath, in: &blocks) { parent in
                    parent.children[index] = replacement
                    parent.children.insert(contentsOf: lifted, at: index + 1)
                }
            }
        }
    }

    @discardableResult
    mutating func remove(_ id: NoteBlockID) -> NoteBlock? {
        guard let path = path(of: id) else { return nil }
        return Self.remove(at: path, in: &blocks)
    }

    @discardableResult
    mutating func removeBlocks(_ ids: some Sequence<NoteBlockID>) -> [NoteBlock] {
        let wanted = Set(ids).filter { contains($0) }
        guard !wanted.isEmpty else { return [] }
        let roots = wanted.filter { id in !ancestors(of: id).contains(where: wanted.contains) }
        var byParent: [[Int]: [Int]] = [:]
        var removedByPath: [[Int]: NoteBlock] = [:]
        for id in roots {
            guard let path = path(of: id) else { continue }
            byParent[Array(path.dropLast()), default: []].append(path.last!)
        }
        for parentPath in byParent.keys.sorted(by: { $0.lexicographicallyPrecedes($1) }).reversed() {
            let indices = Set(byParent[parentPath]!)
            func strip(_ list: inout [NoteBlock]) {
                var kept: [NoteBlock] = []
                kept.reserveCapacity(list.count - indices.count)
                for (index, block) in list.enumerated() {
                    if indices.contains(index) { removedByPath[parentPath + [index]] = block } else { kept.append(block) }
                }
                list = kept
            }
            if parentPath.isEmpty { strip(&blocks) }
            else { Self.update(at: parentPath, in: &blocks) { strip(&$0.children) } }
        }
        return removedByPath.keys.sorted(by: { $0.lexicographicallyPrecedes($1) }).compactMap { removedByPath[$0] }
    }

    @discardableResult
    mutating func insert(_ inserted: [NoteBlock], _ position: NoteInsertion) -> Bool {
        guard !inserted.isEmpty else { return true }
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
            guard let path = path(of: id) else { return false }
            Self.update(at: path, in: &blocks) { $0.children.insert(contentsOf: inserted, at: 0) }
            return true
        case .lastChild(let id):
            guard let path = path(of: id) else { return false }
            Self.update(at: path, in: &blocks) { $0.children.append(contentsOf: inserted) }
            return true
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

    private static func block(at path: [Int], in list: [NoteBlock]) -> NoteBlock? {
        var current = list
        var found: NoteBlock?
        for index in path {
            guard current.indices.contains(index) else { return nil }
            found = current[index]
            current = current[index].children
        }
        return found
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

enum NoteAnchor {
    static let length = 6
    private static let letters = Array("abcdefghijkmnpqrstuvwxyz")
    private static let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")

    static func make<Generator: RandomNumberGenerator>(using generator: inout Generator) -> String {
        var result = String(letters.randomElement(using: &generator)!)
        while result.count < length { result.append(alphabet.randomElement(using: &generator)!) }
        return result
    }

    static func isValid(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 64 && value.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_")
        }
    }

    static func githubSlug(_ text: String) -> String {
        var result = ""
        for scalar in text.lowercased().unicodeScalars {
            if scalar == " " { result.append("-"); continue }
            if scalar == "-" || scalar == "_" { result.unicodeScalars.append(scalar); continue }
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber, .letterNumber, .otherNumber,
                 .connectorPunctuation:
                result.unicodeScalars.append(scalar)
            default:
                continue
            }
        }
        return result
    }

    static func fragment(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        return trimmed.removingPercentEncoding ?? trimmed
    }
}

extension NotePage {
    func headingSlugs() -> [(id: NoteBlockID, slug: String)] {
        var counts: [String: Int] = [:]
        var used: Set<String> = []
        var result: [(id: NoteBlockID, slug: String)] = []
        for block in allBlocks() where block.kind == .heading {
            let base = NoteAnchor.githubSlug(block.text.plainText.trimmingCharacters(in: .whitespacesAndNewlines))
            var slug = base
            var count = counts[base] ?? 0
            while used.contains(slug) {
                count += 1
                slug = base + "-" + String(count)
            }
            counts[base] = count
            used.insert(slug)
            result.append((block.id, slug))
        }
        return result
    }

    var blockAnchors: Set<String> {
        Set(allBlocks().compactMap(\.props.anchor))
    }

    var takenAnchorNames: Set<String> {
        blockAnchors.union(headingSlugs().map(\.slug))
    }

    func block(forAnchor value: String) -> NoteBlockID? {
        let fragment = NoteAnchor.fragment(value)
        guard !fragment.isEmpty else { return nil }
        if let match = allBlocks().first(where: { $0.props.anchor == fragment }) { return match.id }
        let slugs = headingSlugs()
        let lowered = fragment.lowercased()
        if let match = slugs.first(where: { $0.slug == lowered }) { return match.id }
        let slugged = NoteAnchor.githubSlug(fragment)
        guard !slugged.isEmpty else { return nil }
        return slugs.first(where: { $0.slug == slugged })?.id
    }

    func uniqueAnchor<Generator: RandomNumberGenerator>(using generator: inout Generator, avoiding extra: Set<String> = []) -> String {
        let taken = takenAnchorNames.union(extra)
        var candidate = NoteAnchor.make(using: &generator)
        var attempts = 0
        while taken.contains(candidate) {
            attempts += 1
            candidate = NoteAnchor.make(using: &generator)
            if attempts > 64 { candidate += String(attempts) }
        }
        return candidate
    }
}

enum NoteLinkPolicy {
    static let blockedSchemes: Set<String> = ["javascript", "vbscript", "data"]

    static func allowsOpening(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return true }
        return !blockedSchemes.contains(scheme)
    }

    static func allowsOpening(_ link: String) -> Bool {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard let colon = trimmed.firstIndex(of: ":") else { return true }
        let scheme = trimmed[..<colon].filter { !$0.isWhitespace && !$0.unicodeScalars.allSatisfy(CharacterSet.controlCharacters.contains) }
        return !blockedSchemes.contains(scheme.lowercased())
    }
}

struct NoteMediaCredit: Hashable, Codable {
    struct Provider: Hashable {
        var name: String
        var url: URL
    }

    enum Part: Hashable {
        case text(String)
        case link(String, URL)
    }

    var name: String
    var link: String?

    init(name: String, link: String? = nil) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = link?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.link = trimmed.isEmpty ? nil : trimmed
    }

    init?(name: String?, link: String?) {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.init(name: name, link: link)
    }

    static let referralSource = "parc"

    var profileURL: URL? {
        guard let link, let url = URL(string: link), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else { return nil }
        return Self.referral(url)
    }

    var provider: Provider? {
        guard let host = profileURL?.host?.lowercased(), Self.isUnsplash(host) else { return nil }
        return Provider(name: "Unsplash", url: Self.referral(URL(string: "https://unsplash.com/")!))
    }

    var parts: [Part] {
        var result: [Part] = [.text("Photo by ")]
        if let profileURL { result.append(.link(name, profileURL)) } else { result.append(.text(name)) }
        if let provider {
            result.append(.text(" on "))
            result.append(.link(provider.name, provider.url))
        }
        return result
    }

    var sentence: String {
        parts.map { part in
            switch part {
            case .text(let text): return text
            case .link(let text, _): return text
            }
        }.joined()
    }

    static func isUnsplash(_ host: String) -> Bool {
        host == "unsplash.com" || host.hasSuffix(".unsplash.com")
    }

    static func referral(_ url: URL) -> URL {
        guard let host = url.host?.lowercased(), isUnsplash(host),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = components.queryItems ?? []
        if !items.contains(where: { $0.name == "utm_source" }) { items.append(URLQueryItem(name: "utm_source", value: referralSource)) }
        if !items.contains(where: { $0.name == "utm_medium" }) { items.append(URLQueryItem(name: "utm_medium", value: "referral")) }
        components.queryItems = items
        return components.url ?? url
    }
}
