import Foundation

package struct NoteBlockID: Hashable, Codable, CustomStringConvertible {
    package let raw: UUID
    package init() { raw = UUID() }
    package init(_ raw: UUID) { self.raw = raw }
    package var description: String { raw.uuidString }
}

package enum NoteColor: String, CaseIterable, Codable, Hashable {
    case gray, brown, orange, yellow, green, blue, purple, pink, red
}

package enum NoteColorStyle: Hashable, Codable {
    case text(NoteColor)
    case background(NoteColor)

    package var color: NoteColor {
        switch self { case .text(let value), .background(let value): return value }
    }
    package var isBackground: Bool {
        if case .background = self { return true }
        return false
    }
}

package struct NoteDateMention: Hashable, Codable {
    package var year: Int
    package var month: Int
    package var day: Int
    package var hour: Int?
    package var minute: Int?
    package var remind = false
    package var end: NoteDateEnd?
    package var remindBefore: Int?
    package var timeZone: String?
    package var format: NoteDateFormat?
    package var timeFormat: NoteTimeFormat?

    package var components: DateComponents {
        DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    }
    package var includesTime: Bool { hour != nil }
    package var reminderLead: Int { remind ? max(0, remindBefore ?? 0) : 0 }

    package init(year: Int, month: Int, day: Int, hour: Int? = nil, minute: Int? = nil, remind: Bool = false, end: NoteDateEnd? = nil, remindBefore: Int? = nil, timeZone: String? = nil, format: NoteDateFormat? = nil, timeFormat: NoteTimeFormat? = nil) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.remind = remind
        self.end = end
        self.remindBefore = remindBefore
        self.timeZone = timeZone
        self.format = format
        self.timeFormat = timeFormat
    }
}

package struct NoteDateEnd: Hashable, Codable {
    package var year: Int
    package var month: Int
    package var day: Int
    package var hour: Int?
    package var minute: Int?

    package init(year: Int, month: Int, day: Int, hour: Int? = nil, minute: Int? = nil) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
    }

    package var components: DateComponents {
        DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    }
}

package enum NoteDateFormat: String, CaseIterable, Codable, Hashable {
    case full, short
    case monthDayYear = "mdy"
    case dayMonthYear = "dmy"
    case yearMonthDay = "ymd"
}

package enum NoteTimeFormat: String, CaseIterable, Codable, Hashable {
    case twelveHour = "12h"
    case twentyFourHour = "24h"
}

package enum NoteAtom: Hashable, Codable {
    case equation(String)
    case page(target: String, title: String)
    case date(NoteDateMention)
    case link(url: String, title: String)
    case raw(String)
    case customEmoji(String)

    package static let character = "\u{FFFC}"

    package var fallbackText: String {
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

package enum NoteMarkKey: String, CaseIterable, Codable, Hashable {
    case bold, italic, underline, strikethrough, code
}

package struct NoteMarks: Hashable, Codable {
    package var bold = false
    package var italic = false
    package var underline = false
    package var strikethrough = false
    package var code = false
    package var link: String?
    package var color: NoteColorStyle?
    package var atom: NoteAtom?

    package static let plain = NoteMarks()

    package subscript(key: NoteMarkKey) -> Bool {
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

    package var withoutAtom: NoteMarks {
        var value = self
        value.atom = nil
        return value
    }
    var isPlain: Bool { self == .plain }

    package init(bold: Bool = false, italic: Bool = false, underline: Bool = false, strikethrough: Bool = false, code: Bool = false, link: String? = nil, color: NoteColorStyle? = nil, atom: NoteAtom? = nil) {
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.code = code
        self.link = link
        self.color = color
        self.atom = atom
    }
}

package struct NoteSpan: Hashable, Codable {
    package var length: Int
    package var marks: NoteMarks
}


package struct NoteText: Hashable, Codable, ExpressibleByStringLiteral {
    package private(set) var string: String
    package private(set) var spans: [NoteSpan]

    package init(_ string: String = "", marks: NoteMarks = .plain) {
        self.string = string
        let length = (string as NSString).length
        spans = length == 0 ? [] : [NoteSpan(length: length, marks: marks)]
    }

    package init(stringLiteral value: String) { self.init(value) }

    package init(pieces: [(String, NoteMarks)]) {
        var value = NoteText()
        for (text, marks) in pieces { value.append(NoteText(text, marks: marks)) }
        self = value
    }

    package static func atom(_ atom: NoteAtom, marks: NoteMarks = .plain) -> NoteText {
        var value = marks
        value.atom = atom
        return NoteText(NoteAtom.character, marks: value)
    }

    package var length: Int { (string as NSString).length }
    package var isEmpty: Bool { string.isEmpty }
    var isPlain: Bool { spans.allSatisfy { $0.marks.isPlain } }

    package var plainText: String {
        var result = ""
        for run in runs() {
            if let atom = run.marks.atom { result += atom.fallbackText }
            else { result += (string as NSString).substring(with: NSRange(location: run.range.lowerBound, length: run.range.count)) }
        }
        return result
    }

    package func runs(in range: Range<Int>? = nil) -> [(range: Range<Int>, marks: NoteMarks)] {
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

    package func marks(at offset: Int) -> NoteMarks {
        guard !spans.isEmpty else { return .plain }
        let target = min(max(0, offset), length - 1)
        var position = 0
        for span in spans {
            if target < position + span.length { return span.marks }
            position += span.length
        }
        return spans.last?.marks ?? .plain
    }

    package func typingMarks(at offset: Int) -> NoteMarks {
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

    package func linkRange(at offset: Int) -> Range<Int>? {
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

    package func slice(_ range: Range<Int>) -> NoteText {
        let bounds = clamp(range)
        var result = NoteText()
        result.string = (string as NSString).substring(with: NSRange(location: bounds.lowerBound, length: bounds.count))
        result.spans = runs(in: bounds).map { NoteSpan(length: $0.range.count, marks: $0.marks) }
        result.normalize()
        return result
    }

    package mutating func replace(_ range: Range<Int>, with text: NoteText) {
        let bounds = clamp(range)
        let before = slice(0..<bounds.lowerBound), after = slice(bounds.upperBound..<length)
        var result = before
        result.append(text)
        result.append(after)
        self = result
    }

    package mutating func insert(_ text: NoteText, at offset: Int) {
        replace(offset..<offset, with: text)
    }

    package mutating func insert(_ value: String, at offset: Int) {
        insert(NoteText(value, marks: typingMarks(at: offset)), at: offset)
    }

    package mutating func delete(_ range: Range<Int>) {
        replace(range, with: NoteText())
    }

    package mutating func append(_ text: NoteText) {
        guard !text.isEmpty else { return }
        string += text.string
        spans += text.spans
        normalize()
    }

    package static func + (lhs: NoteText, rhs: NoteText) -> NoteText {
        var value = lhs
        value.append(rhs)
        return value
    }

    package mutating func updateMarks(in range: Range<Int>, _ transform: (inout NoteMarks) -> Void) {
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

package enum NoteBlockKind: String, Hashable, Codable, CaseIterable {
    case paragraph, heading, bulletedItem, numberedItem, todo, toggle, quote, callout, divider
    case code, equation, image, video, audio, file, pdf, bookmark, embed, easel, table, tableOfContents, breadcrumb
    case columns, column, pageLink, html, raw, synced, button

    package var hasRichText: Bool {
        switch self {
        case .paragraph, .heading, .bulletedItem, .numberedItem, .todo, .toggle, .quote, .callout: return true
        default: return false
        }
    }
    package var hasPlainText: Bool {
        switch self {
        case .code, .equation, .html, .raw: return true
        default: return false
        }
    }
    var hasText: Bool { hasRichText || hasPlainText }
    package var isMedia: Bool {
        switch self {
        case .image, .video, .audio, .file, .pdf: return true
        default: return false
        }
    }
    var isListItem: Bool { self == .bulletedItem || self == .numberedItem || self == .todo }
    package var isColumnStructure: Bool { self == .columns || self == .column }
    package var acceptsChildren: Bool { hasRichText || isColumnStructure || self == .synced }
    package var hasCaption: Bool {
        switch self {
        case .image, .video, .audio, .file, .pdf, .bookmark, .embed, .code: return true
        default: return false
        }
    }
    var supportsColor: Bool { hasRichText || self == .tableOfContents || self == .breadcrumb || self == .table || self == .button }
}

package enum NoteDiagramMode: String, Codable, CaseIterable, Hashable, Sendable {
    case code, preview, split

    package var title: String {
        switch self {
        case .code: return "Code"
        case .preview: return "Preview"
        case .split: return "Split"
        }
    }

    package var showsCode: Bool { self != .preview }
    package var showsDiagram: Bool { self != .code }
}

package enum NoteAlignment: String, Hashable, Codable, CaseIterable {
    case left, center, right
}

package struct NoteBookmark: Hashable, Codable {
    package var title: String?
    package var summary: String?
    package var siteName: String?
    package var iconURL: String?
    package var imageURL: String?

    package init(title: String? = nil, summary: String? = nil, siteName: String? = nil, iconURL: String? = nil, imageURL: String? = nil) {
        self.title = title
        self.summary = summary
        self.siteName = siteName
        self.iconURL = iconURL
        self.imageURL = imageURL
    }
}

package struct NoteTable: Hashable, Codable {
    package var rows: [[NoteText]]
    package var headerRow = true
    package var headerColumn = false
    package var alignments: [NoteAlignment?] = []
    package var columnWidths: [Double?] = []
    package var merges: [NoteTableMerge] = []
    package var cellColors: [NoteTableCell: NoteColorStyle] = [:]

    package init(rows: [[NoteText]], headerRow: Bool = true, headerColumn: Bool = false) {
        self.rows = rows
        self.headerRow = headerRow
        self.headerColumn = headerColumn
        normalize()
    }

    private enum CodingKeys: String, CodingKey {
        case rows, headerRow, headerColumn, alignments, columnWidths, merges, cellColors
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rows = try container.decode([[NoteText]].self, forKey: .rows)
        headerRow = try container.decodeIfPresent(Bool.self, forKey: .headerRow) ?? true
        headerColumn = try container.decodeIfPresent(Bool.self, forKey: .headerColumn) ?? false
        alignments = try container.decodeIfPresent([NoteAlignment?].self, forKey: .alignments) ?? []
        columnWidths = try container.decodeIfPresent([Double?].self, forKey: .columnWidths) ?? []
        merges = try container.decodeIfPresent([NoteTableMerge].self, forKey: .merges) ?? []
        cellColors = try container.decodeIfPresent([NoteTableCell: NoteColorStyle].self, forKey: .cellColors) ?? [:]
    }

    package static func empty(rows: Int = 3, columns: Int = 3) -> NoteTable {
        NoteTable(rows: Array(repeating: Array(repeating: NoteText(), count: max(1, columns)), count: max(1, rows)))
    }

    package var columnCount: Int { rows.map(\.count).max() ?? 0 }
    package var rowCount: Int { rows.count }

    package mutating func normalize() {
        let columns = max(1, columnCount)
        if rows.isEmpty { rows = [Array(repeating: NoteText(), count: columns)] }
        for index in rows.indices where rows[index].count < columns {
            rows[index] += Array(repeating: NoteText(), count: columns - rows[index].count)
        }
        if alignments.count < columns { alignments += Array(repeating: nil, count: columns - alignments.count) }
        if alignments.count > columns { alignments.removeLast(alignments.count - columns) }
        if columnWidths.count < columns { columnWidths += Array(repeating: nil, count: columns - columnWidths.count) }
        if columnWidths.count > columns { columnWidths.removeLast(columnWidths.count - columns) }
        normalizeSpans()
    }

    package func cell(_ row: Int, _ column: Int) -> NoteText? {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return nil }
        return rows[row][column]
    }

    package mutating func insertRow(at index: Int) {
        insertRows(at: index, count: 1)
    }

    @discardableResult
    mutating func deleteRow(at index: Int) -> Bool {
        guard rows.count > 1, rows.indices.contains(index) else { return false }
        return removeRows(index..<(index + 1))
    }

    @discardableResult
    mutating func duplicateRow(at index: Int) -> Bool {
        guard rows.indices.contains(index) else { return false }
        insertRows(at: index + 1, count: 1, copying: index)
        return true
    }

    @discardableResult
    package mutating func moveRow(from source: Int, to destination: Int) -> Bool {
        guard rows.indices.contains(source), rows.indices.contains(destination), source != destination else { return false }
        reorderRows { NoteTable.movedIndex($0, from: source, to: destination) }
        return true
    }

    package mutating func insertColumn(at index: Int) {
        insertColumns(at: index, count: 1)
    }

    @discardableResult
    mutating func deleteColumn(at index: Int) -> Bool {
        normalize()
        guard columnCount > 1, index >= 0, index < columnCount else { return false }
        return removeColumns(index..<(index + 1))
    }

    @discardableResult
    mutating func duplicateColumn(at index: Int) -> Bool {
        normalize()
        guard index >= 0, index < columnCount else { return false }
        insertColumns(at: index + 1, count: 1, copying: index)
        return true
    }

    @discardableResult
    package mutating func moveColumn(from source: Int, to destination: Int) -> Bool {
        normalize()
        let count = columnCount
        guard source >= 0, source < count, destination >= 0, destination < count, source != destination else { return false }
        reorderColumns { NoteTable.movedIndex($0, from: source, to: destination) }
        return true
    }

    mutating func setColumnWidth(_ width: Double?, at index: Int) {
        normalize()
        guard columnWidths.indices.contains(index) else { return }
        columnWidths[index] = width.map { max(NoteTable.minimumColumnWidth, $0) }
    }

    package mutating func setAlignment(_ alignment: NoteAlignment?, at index: Int) {
        normalize()
        guard alignments.indices.contains(index) else { return }
        alignments[index] = alignment
    }

    package static let minimumColumnWidth = 32.0

    static func movedIndex(_ index: Int, from source: Int, to destination: Int) -> Int {
        if index == source { return destination }
        if source < destination, index > source, index <= destination { return index - 1 }
        if destination < source, index >= destination, index < source { return index + 1 }
        return index
    }
}

package struct NoteBlockProps: Hashable, Codable {
    package var level = 1
    package var toggleable = false
    package var expanded = true
    package var checked = false
    package var listStart: Int?
    package var bulletMarker: String?
    package var orderedDelimiter: String?
    var looseList = false
    package var icon: String?
    package var alert: String?
    package var language = ""
    package var wrap = false
    var fence: String?
    package var info: String?
    package var source: String?
    package var alt: String?
    package var crop: NoteImageCrop?
    package var mask: NoteImageMask?
    package var width: Double?
    package var height: Double?
    package var alignment: NoteAlignment = .center
    package var caption = NoteText()
    package var bookmark: NoteBookmark?
    package var table: NoteTable?
    package var target: String?
    package var anchor: String?
    package var diagramMode: NoteDiagramMode?
    package var credit: NoteMediaCredit?
    package var button: NoteButton?
    package var capture: NoteCapture?

    package init(level: Int = 1, toggleable: Bool = false, expanded: Bool = true, checked: Bool = false, listStart: Int? = nil, bulletMarker: String? = nil, orderedDelimiter: String? = nil, looseList: Bool = false, icon: String? = nil, alert: String? = nil, language: String = "", wrap: Bool = false, fence: String? = nil, info: String? = nil, source: String? = nil, alt: String? = nil, crop: NoteImageCrop? = nil, mask: NoteImageMask? = nil, width: Double? = nil, height: Double? = nil, alignment: NoteAlignment = .center, caption: NoteText = NoteText(), bookmark: NoteBookmark? = nil, table: NoteTable? = nil, target: String? = nil, anchor: String? = nil, diagramMode: NoteDiagramMode? = nil, credit: NoteMediaCredit? = nil, button: NoteButton? = nil, capture: NoteCapture? = nil) {
        self.level = level
        self.toggleable = toggleable
        self.expanded = expanded
        self.checked = checked
        self.listStart = listStart
        self.bulletMarker = bulletMarker
        self.orderedDelimiter = orderedDelimiter
        self.looseList = looseList
        self.icon = icon
        self.alert = alert
        self.language = language
        self.wrap = wrap
        self.fence = fence
        self.info = info
        self.source = source
        self.alt = alt
        self.crop = crop
        self.mask = mask
        self.width = width
        self.height = height
        self.alignment = alignment
        self.caption = caption
        self.bookmark = bookmark
        self.table = table
        self.target = target
        self.anchor = anchor
        self.diagramMode = diagramMode
        self.credit = credit
        self.button = button
        self.capture = capture
    }
}

private final class NoteBlockPropsStorage {
    var value: NoteBlockProps
    init(_ value: NoteBlockProps) { self.value = value }
}

package struct NoteBlock: Hashable, Identifiable, Codable {
    package var id = NoteBlockID()
    package var kind: NoteBlockKind
    package var text = NoteText()
    package var color: NoteColorStyle?
    package var children: [NoteBlock] = []
    private var propsStorage: NoteBlockPropsStorage

    package var props: NoteBlockProps {
        get { propsStorage.value }
        set {
            if isKnownUniquelyReferenced(&propsStorage) { propsStorage.value = newValue }
            else { propsStorage = NoteBlockPropsStorage(newValue) }
        }
    }

    package init(_ kind: NoteBlockKind, text: NoteText = NoteText(), props: NoteBlockProps = NoteBlockProps(),
         color: NoteColorStyle? = nil, children: [NoteBlock] = [], id: NoteBlockID = NoteBlockID()) {
        self.id = id
        self.kind = kind
        self.text = text
        self.propsStorage = NoteBlockPropsStorage(props)
        self.color = color
        self.children = children
    }

    private enum CodingKeys: String, CodingKey { case id, kind, text, props, color, children }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(NoteBlockID.self, forKey: .id) ?? NoteBlockID()
        kind = try container.decode(NoteBlockKind.self, forKey: .kind)
        text = try container.decodeIfPresent(NoteText.self, forKey: .text) ?? NoteText()
        propsStorage = NoteBlockPropsStorage(try container.decodeIfPresent(NoteBlockProps.self, forKey: .props) ?? NoteBlockProps())
        color = try container.decodeIfPresent(NoteColorStyle.self, forKey: .color)
        children = try container.decodeIfPresent([NoteBlock].self, forKey: .children) ?? []
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(text, forKey: .text)
        try container.encode(props, forKey: .props)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encode(children, forKey: .children)
    }

    package static func == (lhs: NoteBlock, rhs: NoteBlock) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.color == rhs.color && lhs.text == rhs.text
            && (lhs.propsStorage === rhs.propsStorage || lhs.propsStorage.value == rhs.propsStorage.value)
            && lhs.children == rhs.children
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(kind)
        hasher.combine(text)
        hasher.combine(props)
        hasher.combine(color)
        hasher.combine(children)
    }

    package static func paragraph(_ text: NoteText = NoteText()) -> NoteBlock { NoteBlock(.paragraph, text: text) }

    package static func heading(_ level: Int, _ text: NoteText = NoteText()) -> NoteBlock {
        var props = NoteBlockProps()
        props.level = min(max(level, 1), 6)
        return NoteBlock(.heading, text: text, props: props)
    }

    package var isToggle: Bool { kind == .toggle || (kind == .heading && props.toggleable) }
    var isSyncedOriginal: Bool { kind == .synced && props.target == nil }
    package var isSyncedCopy: Bool { kind == .synced && props.target != nil }
    var containsSynced: Bool { kind == .synced || children.contains { $0.containsSynced } }

    func referencingSyncedOriginals(_ target: (String) -> String) -> NoteBlock {
        var copy = self
        if isSyncedOriginal, let anchor = props.anchor, NoteAnchor.isValid(anchor) {
            copy.props.target = target(anchor)
            copy.props.anchor = nil
            return copy
        }
        guard !children.isEmpty else { return copy }
        copy.children = children.map { $0.referencingSyncedOriginals(target) }
        return copy
    }
    package var acceptsChildren: Bool { kind.acceptsChildren }
    package var showsChildren: Bool { !isToggle || props.expanded }
    package var isCollapsed: Bool { isToggle && !props.expanded }

    func sameContent(as other: NoteBlock) -> Bool {
        kind == other.kind && text == other.text && color == other.color
            && (propsStorage === other.propsStorage || props == other.props)
            && children.count == other.children.count
            && zip(children, other.children).allSatisfy { $0.id == $1.id }
    }

    fileprivate var indexSignature: NoteBlockIndexSignature {
        NoteBlockIndexSignature(id: id, kind: kind, toggleable: props.toggleable, expanded: props.expanded, listStart: props.listStart)
    }

    package func withFreshIDs() -> NoteBlock {
        var copy = self
        copy.id = NoteBlockID()
        if copy.props.anchor != nil && !isSyncedOriginal { copy.props.anchor = nil }
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

package enum NotePageFont: String, Hashable, Codable, CaseIterable {
    case standard, serif, mono, wide
}

package enum NoteBacklinksDisplay: String, Hashable, Codable, CaseIterable {
    case expanded, popup, off
}

package struct NoteCover: Hashable, Codable {
    package var source: String
    package var position = 0.5
    package var credit: NoteMediaCredit?

    package init(source: String, position: Double = 0.5, credit: NoteMediaCredit? = nil) {
        self.source = source
        self.position = position
        self.credit = credit
    }
}

package enum NotePropertyValue: Hashable, Codable {
    case text(String)
    case number(Double)
    case checkbox(Bool)
    case date(String)
    case list([String])
}

package struct NotePageProperty: Hashable, Codable {
    package var key: String
    package var value: NotePropertyValue

    package init(key: String, value: NotePropertyValue) {
        self.key = key
        self.value = value
    }
}

package struct NotePageSettings: Hashable, Codable {
    package var icon: String?
    package var cover: NoteCover?
    package var font: NotePageFont = .standard
    package var smallText = false
    package var fullWidth = false
    package var locked = false
    package var backlinks: NoteBacklinksDisplay?
    package var properties: [NotePageProperty] = []
    var preservedFrontMatter: [String] = []

    package var isDefault: Bool { self == NotePageSettings() }

    package init(icon: String? = nil, cover: NoteCover? = nil, font: NotePageFont = .standard, smallText: Bool = false, fullWidth: Bool = false, locked: Bool = false, backlinks: NoteBacklinksDisplay? = nil, properties: [NotePageProperty] = [], preservedFrontMatter: [String] = []) {
        self.icon = icon
        self.cover = cover
        self.font = font
        self.smallText = smallText
        self.fullWidth = fullWidth
        self.locked = locked
        self.backlinks = backlinks
        self.properties = properties
        self.preservedFrontMatter = preservedFrontMatter
    }

    package var backlinksDisplay: NoteBacklinksDisplay {
        get { backlinks ?? .popup }
        set { backlinks = newValue == .popup ? nil : newValue }
    }
}

package struct NoteListNumber: Hashable {
    package var value: Int
    package var level: Int

    package var label: String {
        switch level % 3 {
        case 1: return (NoteListNumber.letters(value) ?? String(value)) + "."
        case 2: return (NoteListNumber.roman(value) ?? String(value)) + "."
        default: return String(value) + "."
        }
    }

    package static func letters(_ value: Int) -> String? {
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

    package static func roman(_ value: Int) -> String? {
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

package struct NotePageIndex {
    package struct Entry {
        package var path: [Int]
        package var parent: NoteBlockID?
        package var depth: Int
        package var order: Int
        var visibleOrder: Int?

        package init(path: [Int], parent: NoteBlockID? = nil, depth: Int, order: Int, visibleOrder: Int? = nil) {
            self.path = path
            self.parent = parent
            self.depth = depth
            self.order = order
            self.visibleOrder = visibleOrder
        }
    }

    package private(set) var entries: [NoteBlockID: Entry] = [:]
    package private(set) var all: [NoteFlatBlock] = []
    package private(set) var visible: [NoteFlatBlock] = []
    package private(set) var allIDs: [NoteBlockID] = []
    private(set) var visibleIDs: [NoteBlockID] = []
    package private(set) var numbers: [NoteBlockID: NoteListNumber] = [:]

    package init(_ blocks: [NoteBlock]) {
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

package struct NotePage: Hashable, Codable {
    package var settings = NotePageSettings()
    package var blocks: [NoteBlock] = [] { didSet { indexStorage = NotePageIndexStorage() } }
    private var indexStorage = NotePageIndexStorage()

    package init(settings: NotePageSettings = NotePageSettings(), blocks: [NoteBlock] = []) {
        self.settings = settings
        self.blocks = blocks
    }

    private enum CodingKeys: String, CodingKey { case settings, blocks }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settings = try container.decodeIfPresent(NotePageSettings.self, forKey: .settings) ?? NotePageSettings()
        blocks = try container.decodeIfPresent([NoteBlock].self, forKey: .blocks) ?? []
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(settings, forKey: .settings)
        try container.encode(blocks, forKey: .blocks)
    }

    package static func == (lhs: NotePage, rhs: NotePage) -> Bool {
        lhs.settings == rhs.settings && lhs.blocks == rhs.blocks
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(settings)
        hasher.combine(blocks)
    }

    package var index: NotePageIndex { indexStorage.index(for: blocks) }

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

package struct NoteFlatBlock: Hashable {
    package var id: NoteBlockID
    package var parent: NoteBlockID?
    package var depth: Int
    var indexInParent: Int
}

package enum NoteInsertion: Hashable {
    case before(NoteBlockID)
    case after(NoteBlockID)
    case firstChild(of: NoteBlockID)
    case lastChild(of: NoteBlockID)
    case top(Int)
}

extension NotePage {
    package func block(_ id: NoteBlockID) -> NoteBlock? {
        guard let path = path(of: id) else { return nil }
        return Self.block(at: path, in: blocks)
    }

    package func path(of id: NoteBlockID) -> [Int]? {
        index.entries[id]?.path
    }

    package func contains(_ id: NoteBlockID) -> Bool {
        index.entries[id] != nil
    }

    package func parent(of id: NoteBlockID) -> NoteBlockID? {
        index.entries[id]?.parent
    }

    package func depth(of id: NoteBlockID) -> Int? {
        index.entries[id]?.depth
    }

    package func ancestors(of id: NoteBlockID) -> [NoteBlockID] {
        var result: [NoteBlockID] = []
        var current = parent(of: id)
        while let value = current {
            result.append(value)
            current = parent(of: value)
        }
        return result
    }

    package func siblings(of id: NoteBlockID) -> [NoteBlock] {
        if let parent = parent(of: id) { return block(parent)?.children ?? [] }
        return blocks
    }

    func documentPosition(of id: NoteBlockID) -> Int? {
        index.entries[id]?.order
    }

    package func visiblePosition(of id: NoteBlockID) -> Int? {
        index.entries[id]?.visibleOrder
    }

    package func isVisible(_ id: NoteBlockID) -> Bool {
        visiblePosition(of: id) != nil
    }

    package func flattened(includingCollapsed: Bool = false) -> [NoteFlatBlock] {
        includingCollapsed ? index.all : index.visible
    }

    package func documentOrder(includingCollapsed: Bool = true) -> [NoteBlockID] {
        includingCollapsed ? index.allIDs : index.visibleIDs
    }

    package func isAncestor(_ ancestor: NoteBlockID, of id: NoteBlockID) -> Bool {
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

    package func numberLabel(for id: NoteBlockID) -> String? {
        index.numbers[id]?.label
    }

    package func listNumber(for id: NoteBlockID) -> NoteListNumber? {
        index.numbers[id]
    }

    package func columnFractions(of id: NoteBlockID) -> [Double] {
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
    package mutating func update(_ id: NoteBlockID, _ transform: (inout NoteBlock) -> Void) -> Bool {
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
    package mutating func remove(_ id: NoteBlockID) -> NoteBlock? {
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
    package mutating func insert(_ inserted: [NoteBlock], _ position: NoteInsertion) -> Bool {
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

    package func allBlocks() -> [NoteBlock] {
        var result: [NoteBlock] = []
        func walk(_ list: [NoteBlock]) { for block in list { result.append(block); walk(block.children) } }
        walk(blocks)
        return result
    }

    func allBlocksIncludingTemplates() -> [NoteBlock] {
        var result: [NoteBlock] = []
        func walk(_ list: [NoteBlock]) {
            for block in list {
                result.append(block)
                walk(block.children)
                if let button = block.props.button { walk(button.templateBlocks) }
            }
        }
        walk(blocks)
        return result
    }

    package var plainText: String {
        allBlocks().compactMap { block -> String? in
            if block.kind.hasRichText || block.kind.hasPlainText { return block.text.plainText }
            if block.kind == .button { return block.buttonValue.displayName }
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

package enum NoteTextField: Hashable, Codable {
    case body
    case caption
    case cell(row: Int, column: Int)
}

package struct NotePosition: Hashable, Codable {
    package var block: NoteBlockID
    package var offset: Int
    package var field: NoteTextField = .body

    package init(_ block: NoteBlockID, _ offset: Int, field: NoteTextField = .body) {
        self.block = block
        self.offset = offset
        self.field = field
    }
}

package struct NoteTableCell: Hashable, Codable {
    package var row: Int
    package var column: Int

    package init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}

package enum NotePageSelection: Hashable {
    case none
    case text(anchor: NotePosition, head: NotePosition)
    case blocks([NoteBlockID])
    case cells(table: NoteBlockID, anchor: NoteTableCell, head: NoteTableCell)

    package static func caret(_ position: NotePosition) -> NotePageSelection { .text(anchor: position, head: position) }

    package var isCollapsed: Bool {
        if case .text(let anchor, let head) = self { return anchor == head }
        return false
    }
    package var caret: NotePosition? {
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
    package func headingSlugs() -> [(id: NoteBlockID, slug: String)] {
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

    package func syncedSite(containing id: NoteBlockID) -> NoteBlockID? {
        guard contains(id) else { return nil }
        return ([id] + ancestors(of: id)).last { block($0)?.kind == .synced }
    }

    func syncedOriginals(within ids: some Sequence<NoteBlockID>) -> [NoteBlockID] {
        var result: [NoteBlockID] = []
        func walk(_ block: NoteBlock) {
            if block.isSyncedOriginal { result.append(block.id); return }
            block.children.forEach(walk)
        }
        let wanted = Set(ids)
        for id in wanted where !ancestors(of: id).contains(where: wanted.contains) {
            if let block = block(id) { walk(block) }
        }
        return result
    }

    var blockAnchors: Set<String> {
        Set(allBlocks().compactMap(\.props.anchor))
    }

    var takenAnchorNames: Set<String> {
        blockAnchors.union(headingSlugs().map(\.slug))
    }

    package func block(forAnchor value: String) -> NoteBlockID? {
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

package enum NoteLinkPolicy {
    static let blockedSchemes: Set<String> = ["javascript", "vbscript", "data"]

    package static func allowsOpening(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return true }
        return !blockedSchemes.contains(scheme)
    }

    package static func allowsOpening(_ link: String) -> Bool {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard let colon = trimmed.firstIndex(of: ":") else { return true }
        let scheme = trimmed[..<colon].filter { !$0.isWhitespace && !$0.unicodeScalars.allSatisfy(CharacterSet.controlCharacters.contains) }
        return !blockedSchemes.contains(scheme.lowercased())
    }
}

package struct NoteMediaCredit: Hashable, Codable {
    package struct Provider: Hashable {
        package var name: String
        package var url: URL

        package init(name: String, url: URL) {
            self.name = name
            self.url = url
        }
    }

    package enum Part: Hashable {
        case text(String)
        case link(String, URL)
    }

    package var name: String
    package var link: String?

    package init(name: String, link: String? = nil) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = link?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.link = trimmed.isEmpty ? nil : trimmed
    }

    package init?(name: String?, link: String?) {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.init(name: name, link: link)
    }

    static let referralSource = "parc"

    package var profileURL: URL? {
        guard let link, let url = URL(string: link), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else { return nil }
        return Self.referral(url)
    }

    package var provider: Provider? {
        guard let host = profileURL?.host?.lowercased(), Self.isUnsplash(host) else { return nil }
        return Provider(name: "Unsplash", url: Self.referral(URL(string: "https://unsplash.com/")!))
    }

    package var parts: [Part] {
        var result: [Part] = [.text("Photo by ")]
        if let profileURL { result.append(.link(name, profileURL)) } else { result.append(.text(name)) }
        if let provider {
            result.append(.text(" on "))
            result.append(.link(provider.name, provider.url))
        }
        return result
    }

    package var sentence: String {
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

    package static func referral(_ url: URL) -> URL {
        guard let host = url.host?.lowercased(), isUnsplash(host),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = components.queryItems ?? []
        if !items.contains(where: { $0.name == "utm_source" }) { items.append(URLQueryItem(name: "utm_source", value: referralSource)) }
        if !items.contains(where: { $0.name == "utm_medium" }) { items.append(URLQueryItem(name: "utm_medium", value: "referral")) }
        components.queryItems = items
        return components.url ?? url
    }
}

package enum NoteButtonPlacement: String, Hashable, Codable, CaseIterable {
    case below, above, top, bottom

    package var title: String {
        switch self {
        case .below: return "Below the button"
        case .above: return "Above the button"
        case .top: return "Top of the note"
        case .bottom: return "Bottom of the note"
        }
    }
}

package enum NoteButtonAction: Hashable, Codable {
    package enum Kind: String, Hashable, CaseIterable {
        case insert, confirm, open
    }

    case insert(placement: NoteButtonPlacement, blocks: [NoteBlock])
    case confirm(message: String)
    case open(target: String)

    package var kind: Kind {
        switch self {
        case .insert: return .insert
        case .confirm: return .confirm
        case .open: return .open
        }
    }

    package var blocks: [NoteBlock] {
        if case .insert(_, let blocks) = self { return blocks }
        return []
    }

    package static func blank(_ kind: Kind) -> NoteButtonAction {
        switch kind {
        case .insert: return .insert(placement: .below, blocks: [])
        case .confirm: return .confirm(message: "")
        case .open: return .open(target: "")
        }
    }

    package static func == (lhs: NoteButtonAction, rhs: NoteButtonAction) -> Bool {
        switch (lhs, rhs) {
        case (.insert(let leftPlacement, let leftBlocks), .insert(let rightPlacement, let rightBlocks)):
            return leftPlacement == rightPlacement && NoteBlock.sameTrees(leftBlocks, rightBlocks)
        case (.confirm(let left), .confirm(let right)):
            return left == right
        case (.open(let left), .open(let right)):
            return left == right
        default:
            return false
        }
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        switch self {
        case .insert(let placement, let blocks):
            hasher.combine(placement)
            hasher.combine(blocks.count)
            for block in blocks {
                hasher.combine(block.kind)
                hasher.combine(block.text)
            }
        case .confirm(let message):
            hasher.combine(message)
        case .open(let target):
            hasher.combine(target)
        }
    }
}

package struct NoteButton: Hashable, Codable {
    package static let placeholderName = "New button"
    static let maximumSuggestedName = 80

    package var name = ""
    package var actions: [NoteButtonAction] = []

    static let starter = NoteButton(name: "", actions: [.blank(.insert)])

    package var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.placeholderName : trimmed
    }

    package var templateBlocks: [NoteBlock] { actions.flatMap(\.blocks) }

    var insertsBlocks: Bool { actions.contains { !$0.blocks.isEmpty } }

    package init(name: String = "", actions: [NoteButtonAction] = []) {
        self.name = name
        self.actions = actions
    }

    package static func suggestedName(from text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > maximumSuggestedName else { return trimmed }
        return String(trimmed.prefix(maximumSuggestedName - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    package static func normalizedName(_ value: String) -> String {
        value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

extension NoteButtonPlacement {
    package var phrase: String {
        switch self {
        case .below: return "below"
        case .above: return "above"
        case .top: return "at the top"
        case .bottom: return "at the bottom"
        }
    }
}

extension NoteBlock {
    package static func button(name: String = "", icon: String? = nil, actions: [NoteButtonAction] = NoteButton.starter.actions,
                       id: NoteBlockID = NoteBlockID()) -> NoteBlock {
        var props = NoteBlockProps()
        props.icon = icon
        props.expanded = false
        props.button = NoteButton(name: name, actions: actions)
        return NoteBlock(.button, props: props, id: id)
    }

    package var buttonValue: NoteButton { props.button ?? NoteButton() }

    func sameTree(as other: NoteBlock) -> Bool {
        kind == other.kind && text == other.text && color == other.color && props == other.props
            && NoteBlock.sameTrees(children, other.children)
    }

    static func sameTrees(_ lhs: [NoteBlock], _ rhs: [NoteBlock]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.sameTree(as: $1) }
    }

    func convertedToButton() -> NoteBlock {
        guard kind != .button else { return self }
        var props = NoteBlockProps()
        props.icon = kind == .callout ? self.props.icon : nil
        props.anchor = self.props.anchor
        props.expanded = false
        let name = NoteButton.suggestedName(from: kind.hasText ? text.plainText : "")
        props.button = NoteButton(name: name, actions: [.insert(placement: .below, blocks: children.map { $0.withFreshIDs() })])
        return NoteBlock(.button, props: props, color: color, id: id)
    }

    func convertedFromButton(to kind: NoteBlockKind) -> NoteBlock {
        guard self.kind == .button else { return self }
        let button = buttonValue
        var source = NoteBlock(.paragraph, text: NoteText(button.name.trimmingCharacters(in: .whitespacesAndNewlines)), color: color,
                               children: button.templateBlocks.map { $0.withFreshIDs() }, id: id)
        source.props.anchor = props.anchor
        if kind == .callout { source.props.icon = props.icon }
        return source
    }
}
