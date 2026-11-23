import Foundation

package struct NoteFindOptions: Hashable {
    package var matchCase = false

    var compareOptions: NSString.CompareOptions { matchCase ? [] : [.caseInsensitive, .diacriticInsensitive] }

    package init(matchCase: Bool = false) {
        self.matchCase = matchCase
    }
}

package struct NoteFindMatch: Hashable {
    static let titleBlock = NoteBlockID(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))

    package var position: NotePosition
    var length: Int

    init(_ block: NoteBlockID, field: NoteTextField = .body, offset: Int, length: Int) {
        position = NotePosition(block, offset, field: field)
        self.length = length
    }

    static func title(offset: Int, length: Int) -> NoteFindMatch {
        NoteFindMatch(titleBlock, offset: offset, length: length)
    }

    package var block: NoteBlockID { position.block }
    package var field: NoteTextField { position.field }
    package var range: Range<Int> { position.offset..<(position.offset + length) }
    package var isTitle: Bool { position.block == Self.titleBlock }
}

struct NoteFindOrder {
    private var blocks: [NoteBlockID: Int] = [:]

    init(_ page: NotePage) {
        for (index, id) in page.documentOrder(includingCollapsed: true).enumerated() { blocks[id] = index }
    }

    func key(_ position: NotePosition) -> (Int, Int, Int) {
        if position.block == NoteFindMatch.titleBlock { return (-1, 0, position.offset) }
        let field: Int
        switch position.field {
        case .body: field = 0
        case .cell(let row, let column): field = 1 + row * 10_000 + column
        case .caption: field = Int.max
        }
        return (blocks[position.block] ?? Int.max, field, position.offset)
    }

    func precedes(_ lhs: NotePosition, _ rhs: NotePosition) -> Bool { key(lhs) < key(rhs) }
}

package enum NotePageFinder {
    static func fields(of block: NoteBlock) -> [NoteTextField] {
        var result: [NoteTextField] = []
        if block.kind.hasRichText || block.kind.hasPlainText { result.append(.body) }
        if let table = block.props.table {
            for row in table.rows.indices {
                for column in table.rows[row].indices { result.append(.cell(row: row, column: column)) }
            }
        }
        if block.kind.hasCaption && !block.props.caption.isEmpty { result.append(.caption) }
        return result
    }

    static func ranges(of query: String, in string: String, options: NoteFindOptions = NoteFindOptions()) -> [Range<Int>] {
        guard !query.isEmpty else { return [] }
        let haystack = string as NSString
        var result: [Range<Int>] = []
        var location = 0
        while location < haystack.length {
            let found = haystack.range(of: query, options: options.compareOptions,
                                       range: NSRange(location: location, length: haystack.length - location))
            guard found.location != NSNotFound, found.length > 0 else { break }
            result.append(found.location..<(found.location + found.length))
            location = found.location + found.length
        }
        return result
    }

    package static func matches(of query: String, in page: NotePage, title: String? = nil,
                        options: NoteFindOptions = NoteFindOptions()) -> [NoteFindMatch] {
        guard !query.isEmpty else { return [] }
        var result: [NoteFindMatch] = []
        if let title, !title.isEmpty {
            for range in ranges(of: query, in: title, options: options) {
                result.append(.title(offset: range.lowerBound, length: range.count))
            }
        }
        for id in page.documentOrder(includingCollapsed: true) {
            guard let block = page.block(id) else { continue }
            for field in fields(of: block) {
                guard let text = block.text(in: field), !text.isEmpty else { continue }
                for range in ranges(of: query, in: text.string, options: options) {
                    result.append(NoteFindMatch(id, field: field, offset: range.lowerBound, length: range.count))
                }
            }
        }
        return result
    }

    package static func firstIndex(atOrAfter position: NotePosition?, in matches: [NoteFindMatch], page: NotePage) -> Int? {
        guard !matches.isEmpty else { return nil }
        guard let position else { return 0 }
        let order = NoteFindOrder(page)
        let target = order.key(position)
        return matches.firstIndex { order.key($0.position) >= target } ?? 0
    }

    @discardableResult
    package static func replace(_ targets: [NoteFindMatch], with replacement: String, in page: inout NotePage) -> Set<NoteBlockID> {
        replaceCounting(targets, with: replacement, in: &page).touched
    }

    package static func replaceCounting(_ targets: [NoteFindMatch], with replacement: String,
                                in page: inout NotePage) -> (touched: Set<NoteBlockID>, count: Int) {
        var count = 0
        var grouped: [NotePosition: [NoteFindMatch]] = [:]
        for match in targets where !match.isTitle {
            grouped[NotePosition(match.block, 0, field: match.field), default: []].append(match)
        }
        var touched = Set<NoteBlockID>()
        for (key, matches) in grouped {
            page.update(key.block) { block in
                guard var text = block.text(in: key.field) else { return }
                var last = Int.max
                for match in matches.sorted(by: { $0.position.offset > $1.position.offset }) {
                    let range = match.range
                    guard range.lowerBound >= 0, range.upperBound <= text.length, range.upperBound <= last else { continue }
                    let slice = text.slice(range)
                    guard !slice.runs().contains(where: { $0.marks.atom != nil }) else { continue }
                    let marks = text.marks(at: range.lowerBound).withoutAtom
                    text.replace(range, with: NoteText(replacement, marks: marks))
                    last = range.lowerBound
                    touched.insert(key.block)
                    count += 1
                }
                block.setText(text, in: key.field)
            }
        }
        return (touched, count)
    }

    package static func positionAfterReplacing(_ match: NoteFindMatch, with replacement: String) -> NotePosition {
        NotePosition(match.block, match.position.offset + (replacement as NSString).length, field: match.field)
    }

    package static func titleReplacementCount(_ title: String, matches targets: [NoteFindMatch]) -> Int {
        let length = (title as NSString).length
        var last = Int.max
        var count = 0
        for match in targets.filter(\.isTitle).sorted(by: { $0.position.offset > $1.position.offset }) {
            let range = match.range
            guard range.lowerBound >= 0, range.upperBound <= length, range.upperBound <= last else { continue }
            last = range.lowerBound
            count += 1
        }
        return count
    }

    package static func replacingTitle(_ title: String, matches targets: [NoteFindMatch], with replacement: String) -> String {
        let text = NSMutableString(string: title)
        var last = Int.max
        for match in targets.filter(\.isTitle).sorted(by: { $0.position.offset > $1.position.offset }) {
            let range = match.range
            guard range.lowerBound >= 0, range.upperBound <= text.length, range.upperBound <= last else { continue }
            text.replaceCharacters(in: NSRange(location: range.lowerBound, length: range.count), with: replacement)
            last = range.lowerBound
        }
        return text as String
    }
}

package enum NotePageTitleCheck {
    package static func problem(renaming url: URL, to proposed: String) -> NoteFileError? {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if NoteFileNaming.sanitizedTitle(trimmed).isEmpty { return .invalidName }
        do {
            _ = try NoteFileNaming.renameTarget(for: url, to: trimmed)
        } catch let error as NoteFileError {
            return error
        } catch {
            return nil
        }
        return nil
    }
}

package struct NotePageHeaderGeometry: Equatable {
    package struct Layout: Equatable {
        package var cover: CGRect?
        package var icon: CGRect?
        package var affordances: CGRect
        package var title: CGRect
        package var error: CGRect?
        package var properties: CGRect?
        package var backlinks: CGRect?
        package var height: CGFloat

        init(cover: CGRect? = nil, icon: CGRect? = nil, affordances: CGRect, title: CGRect, error: CGRect? = nil, properties: CGRect? = nil, backlinks: CGRect? = nil, height: CGFloat) {
            self.cover = cover
            self.icon = icon
            self.affordances = affordances
            self.title = title
            self.error = error
            self.properties = properties
            self.backlinks = backlinks
            self.height = height
        }
    }

    package static let iconSide: CGFloat = 80
    static let iconLead: CGFloat = 6
    static let topPadding: CGFloat = 52
    static let plainTextTop: CGFloat = 56
    static let inkGap: CGFloat = 14
    static let affordanceGap: CGFloat = 8
    static let coverAffordanceGap: CGFloat = 14
    static let errorGap: CGFloat = 4
    static let propertiesGap: CGFloat = 8
    static let backlinksGap: CGFloat = 6
    static let bottomPadding: CGFloat = 14

    var width: CGFloat
    var column: CGRect
    package var coverHeight: CGFloat?
    package var hasIcon = false
    package var isPlainText = false
    package var iconInkInset: CGFloat = 11
    var titleHeight: CGFloat
    package var titleCapInset: CGFloat = 0
    package var affordanceHeight: CGFloat = 26
    package var errorHeight: CGFloat?
    package var propertiesHeight: CGFloat?
    package var propertiesGutter: CGFloat = 0
    package var backlinksHeight: CGFloat?
    package var backlinksGutter: CGFloat = 0

    var hasCover: Bool { (coverHeight ?? 0) > 0 && !isPlainText }

    package init(width: CGFloat, column: CGRect, coverHeight: CGFloat? = nil, hasIcon: Bool = false, isPlainText: Bool = false, iconInkInset: CGFloat = 11, titleHeight: CGFloat, titleCapInset: CGFloat = 0, affordanceHeight: CGFloat = 26, errorHeight: CGFloat? = nil, propertiesHeight: CGFloat? = nil, propertiesGutter: CGFloat = 0, backlinksHeight: CGFloat? = nil, backlinksGutter: CGFloat = 0) {
        self.width = width
        self.column = column
        self.coverHeight = coverHeight
        self.hasIcon = hasIcon
        self.isPlainText = isPlainText
        self.iconInkInset = iconInkInset
        self.titleHeight = titleHeight
        self.titleCapInset = titleCapInset
        self.affordanceHeight = affordanceHeight
        self.errorHeight = errorHeight
        self.propertiesHeight = propertiesHeight
        self.propertiesGutter = propertiesGutter
        self.backlinksHeight = backlinksHeight
        self.backlinksGutter = backlinksGutter
    }

    package func layout() -> Layout {
        let column = self.column.width > 0 ? self.column : CGRect(x: 0, y: 0, width: width, height: 0)
        var cover: CGRect?
        var icon: CGRect?
        let affordances: CGRect
        let titleTop: CGFloat
        let showsIcon = hasIcon && !isPlainText
        if hasCover, let height = coverHeight {
            cover = CGRect(x: 0, y: 0, width: width, height: height)
        }
        let side = Self.iconSide
        if isPlainText {
            titleTop = Self.plainTextTop
            affordances = CGRect(x: column.minX, y: max(0, titleTop - affordanceHeight - Self.affordanceGap), width: column.width,
                                 height: affordanceHeight)
        } else if showsIcon {
            let top = cover.map { $0.maxY - side / 2 } ?? Self.topPadding
            let box = CGRect(x: column.minX - Self.iconLead, y: top, width: side, height: side)
            icon = box
            titleTop = box.maxY - iconInkInset + Self.inkGap - titleCapInset
            let foot = side / 2
            let x = box.maxX + Self.affordanceGap
            affordances = CGRect(x: x, y: box.maxY - foot + (foot - affordanceHeight) / 2, width: max(0, column.maxX - x),
                                 height: affordanceHeight)
        } else {
            let rowTop = cover.map { $0.maxY + Self.coverAffordanceGap } ?? Self.topPadding
            affordances = CGRect(x: column.minX, y: rowTop, width: column.width, height: affordanceHeight)
            titleTop = affordances.maxY + Self.inkGap - titleCapInset
        }
        let title = CGRect(x: column.minX, y: titleTop.rounded(), width: column.width, height: titleHeight)
        var y = title.maxY
        var error: CGRect?
        if let errorHeight, errorHeight > 0 {
            let frame = CGRect(x: column.minX, y: y + Self.errorGap, width: column.width, height: errorHeight)
            error = frame
            y = frame.maxY
        }
        var properties: CGRect?
        if let propertiesHeight, !isPlainText {
            y += Self.propertiesGap
            let frame = CGRect(x: column.minX - propertiesGutter, y: y, width: column.width + propertiesGutter, height: propertiesHeight)
            properties = frame
            y = frame.maxY
        }
        var backlinks: CGRect?
        if let backlinksHeight, backlinksHeight > 0 {
            y += Self.backlinksGap
            let frame = CGRect(x: column.minX - backlinksGutter, y: y, width: column.width + backlinksGutter, height: backlinksHeight)
            backlinks = frame
            y = frame.maxY
        }
        return Layout(cover: cover, icon: icon, affordances: affordances, title: title, error: error, properties: properties,
                      backlinks: backlinks, height: (y + Self.bottomPadding).rounded(.up))
    }
}

package struct NotePageStats: Hashable {
    static let wordsPerMinute = 238.0

    package var words: Int
    package var characters: Int

    init(words: Int, characters: Int) {
        self.words = words
        self.characters = characters
    }

    package init(page: NotePage) {
        var pieces: [String] = []
        for block in page.allBlocks() {
            for field in NotePageFinder.fields(of: block) {
                if let text = block.text(in: field) { pieces.append(text.plainText) }
            }
        }
        let joined = pieces.joined(separator: "\n")
        var words = 0
        joined.enumerateSubstrings(in: joined.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in words += 1 }
        self.words = words
        characters = joined.reduce(0) { $1.isNewline ? $0 : $0 + 1 }
    }

    var readingMinutes: Int {
        words == 0 ? 0 : max(1, Int((Double(words) / Self.wordsPerMinute).rounded(.up)))
    }

    package var wordLabel: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let number = formatter.string(from: NSNumber(value: words)) ?? String(words)
        return words == 1 ? "1 word" : number + " words"
    }

    package var readingLabel: String {
        readingMinutes == 0 ? "Nothing to read yet" : "\(readingMinutes) min read"
    }

    package var summary: String { words == 0 ? "No words yet" : wordLabel + " · " + readingLabel }
}

package enum NoteRelativeTime {
    package static func phrase(for date: Date, now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 45 && elapsed > -45 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }

    package static func edited(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Not saved yet" }
        return "Edited " + phrase(for: date, now: now)
    }
}

package enum NotePropertyKind: String, CaseIterable, Hashable {
    case text, number, checkbox, date, list

    package var displayName: String {
        switch self {
        case .text: return "Text"
        case .number: return "Number"
        case .checkbox: return "Checkbox"
        case .date: return "Date"
        case .list: return "List"
        }
    }

    package var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .number: return "number"
        case .checkbox: return "checkmark.square"
        case .date: return "calendar"
        case .list: return "tag"
        }
    }

    var defaultValue: NotePropertyValue {
        switch self {
        case .text: return .text("")
        case .number: return .number(0)
        case .checkbox: return .checkbox(false)
        case .date: return .date("")
        case .list: return .list([])
        }
    }

    var suggestedKey: String {
        switch self {
        case .text: return "Notes"
        case .number: return "Number"
        case .checkbox: return "Done"
        case .date: return "Date"
        case .list: return "Tags"
        }
    }
}

extension NotePropertyValue {
    package var kind: NotePropertyKind {
        switch self {
        case .text: return .text
        case .number: return .number
        case .checkbox: return .checkbox
        case .date: return .date
        case .list: return .list
        }
    }

    package var isEmpty: Bool {
        switch self {
        case .text(let value), .date(let value): return value.trimmingCharacters(in: .whitespaces).isEmpty
        case .number: return false
        case .checkbox(let value): return !value
        case .list(let items): return items.isEmpty
        }
    }

    package var displayText: String {
        switch self {
        case .text(let value): return value
        case .number(let value): return NotePropertyEditing.format(value)
        case .checkbox(let value): return value ? "Yes" : "No"
        case .date(let value):
            guard let date = NotePropertyEditing.date(from: value) else { return value }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            formatter.timeZone = NotePropertyEditing.calendar.timeZone
            return formatter.string(from: date)
        case .list(let items): return items.joined(separator: ", ")
        }
    }

    func converted(to kind: NotePropertyKind) -> NotePropertyValue {
        guard kind != self.kind else { return self }
        switch (self, kind) {
        case (.text(let value), .number), (.date(let value), .number):
            return .number(NotePropertyEditing.parseNumber(value) ?? 0)
        case (.list(let items), .number):
            return .number(items.first.flatMap(NotePropertyEditing.parseNumber) ?? 0)
        case (.text(let value), .checkbox):
            return .checkbox(NotePropertyEditing.truthy(value))
        case (.number(let value), .checkbox):
            return .checkbox(value != 0)
        case (.list(let items), .checkbox):
            return .checkbox(!items.isEmpty)
        case (.date(let value), .checkbox):
            return .checkbox(!value.isEmpty)
        case (.text(let value), .date):
            return .date(NotePropertyEditing.date(from: value) == nil ? "" : value.trimmingCharacters(in: .whitespaces))
        case (.list(let items), .date):
            let first = items.first ?? ""
            return .date(NotePropertyEditing.date(from: first) == nil ? "" : first)
        case (.text(let value), .list), (.date(let value), .list):
            return .list(NotePropertyEditing.listItems(from: value))
        case (.number, .list), (.checkbox, .list):
            return .list([displayText])
        case (_, .text):
            return .text(self == .checkbox(false) ? "" : displayText)
        default:
            return kind.defaultValue
        }
    }
}

package enum NotePropertyEditing {
    static let reservedKeys: Set<String> = ["icon", "cover", "cover-position", "cover-credit", "cover-credit-url", "font", "small-text", "full-width", "locked", "title"]

    package static let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "UTC")!
        return value
    }()

    package static func normalizedKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
    }

    static func isUsable(_ key: String, among properties: [NotePageProperty], excluding index: Int? = nil) -> Bool {
        let value = normalizedKey(key)
        guard !value.isEmpty, !value.contains(":"), !reservedKeys.contains(value.lowercased()) else { return false }
        return !properties.indices.contains { $0 != index && properties[$0].key.lowercased() == value.lowercased() }
    }

    static func uniqueKey(_ base: String, among properties: [NotePageProperty]) -> String {
        let root = normalizedKey(base).isEmpty ? "Property" : normalizedKey(base)
        if isUsable(root, among: properties) { return root }
        var counter = 2
        while !isUsable("\(root) \(counter)", among: properties) { counter += 1 }
        return "\(root) \(counter)"
    }

    package static func adding(_ kind: NotePropertyKind, to properties: [NotePageProperty]) -> [NotePageProperty] {
        properties + [NotePageProperty(key: uniqueKey(kind.suggestedKey, among: properties), value: kind.defaultValue)]
    }

    package static func renaming(_ properties: [NotePageProperty], at index: Int, to key: String) -> [NotePageProperty]? {
        guard properties.indices.contains(index) else { return nil }
        let value = normalizedKey(key)
        if value == properties[index].key { return properties }
        guard isUsable(value, among: properties, excluding: index) else { return nil }
        var result = properties
        result[index].key = value
        return result
    }

    package static func changingKind(_ properties: [NotePageProperty], at index: Int, to kind: NotePropertyKind) -> [NotePageProperty] {
        guard properties.indices.contains(index) else { return properties }
        var result = properties
        result[index].value = result[index].value.converted(to: kind)
        return result
    }

    package static func moving(_ properties: [NotePageProperty], from source: Int, to destination: Int) -> [NotePageProperty] {
        guard properties.indices.contains(source) else { return properties }
        var result = properties
        let item = result.remove(at: source)
        result.insert(item, at: min(max(0, destination), result.count))
        return result
    }

    package static func removing(_ properties: [NotePageProperty], at index: Int) -> [NotePageProperty] {
        guard properties.indices.contains(index) else { return properties }
        var result = properties
        result.remove(at: index)
        return result
    }

    package static func parseNumber(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }

    static func format(_ value: Double) -> String {
        if value.rounded() == value && abs(value) < 1e15 { return String(Int64(value)) }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 6
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func truthy(_ text: String) -> Bool {
        ["true", "yes", "y", "1", "x", "done", "on"].contains(text.trimmingCharacters(in: .whitespaces).lowercased())
    }

    static func listItems(from text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { item in
            guard !item.isEmpty, !seen.contains(item.lowercased()) else { return false }
            seen.insert(item.lowercased())
            return true
        }
    }

    package static func addingTag(_ tag: String, to items: [String]) -> [String] {
        let value = tag.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: " ")
        guard !value.isEmpty, !items.contains(where: { $0.lowercased() == value.lowercased() }) else { return items }
        return items + [value]
    }

    package static func dateString(from date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    package static func date(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.prefix(10).split(separator: "-")
        guard trimmed.count >= 10, parts.count == 3, parts[0].count == 4, let year = Int(parts[0]),
              let month = Int(parts[1]), let day = Int(parts[2]), (1...12).contains(month), (1...31).contains(day) else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }

    package static func localDateString(from date: Date, in zone: TimeZone = .current) -> String {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = zone
        let parts = local.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }
}

package enum NotePageHistoryReason: Hashable { case save, idle, close }

package struct NotePageHistoryPolicy: Hashable {
    var minimumInterval: TimeInterval = 300
    package var idleDelay: TimeInterval = 120

    package init(minimumInterval: TimeInterval = 300, idleDelay: TimeInterval = 120) {
        self.minimumInterval = minimumInterval
        self.idleDelay = idleDelay
    }

    package func shouldRecord(_ reason: NotePageHistoryReason, current: String, lastRecorded: String?,
                      lastRecordedAt: Date?, now: Date) -> Bool {
        guard let lastRecorded else { return true }
        guard Self.isMeaningful(from: lastRecorded, to: current) else { return false }
        switch reason {
        case .close, .idle: return true
        case .save:
            guard let lastRecordedAt else { return true }
            return now.timeIntervalSince(lastRecordedAt) >= minimumInterval
        }
    }

    package static func isMeaningful(from old: String, to new: String) -> Bool {
        trimmed(old) != trimmed(new)
    }

    private static func trimmed(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                var value = Substring(line)
                while let last = value.last, last == " " || last == "\t" || last == "\r" { value = value.dropLast() }
                return value
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

package enum NotePageExport {
    package static func markdownForCopy(body: String, title: String) -> String {
        let trimmedBody = body.trimmingCharacters(in: .newlines)
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heading.isEmpty else { return trimmedBody + "\n" }
        return trimmedBody.isEmpty ? "# " + heading + "\n" : "# " + heading + "\n\n" + trimmedBody + "\n"
    }

    package static func isImageSource(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("file:") { return true }
        let ext = (value as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "svg", "avif"].contains(ext)
    }

    package static func relativeAssetSources(in page: NotePage) -> [String] {
        var sources: [String] = []
        if let cover = page.settings.cover?.source { sources.append(cover) }
        if let icon = page.settings.icon, isImageSource(icon) { sources.append(icon) }
        for block in page.allBlocks() where block.kind.isMedia {
            if let source = block.props.source { sources.append(source) }
            if block.kind == .image, let snapshot = block.props.capture?.snapshot { sources.append(snapshot) }
        }
        var seen = Set<String>()
        return sources.filter { source in
            guard !source.isEmpty, URL(string: source)?.scheme == nil, !source.hasPrefix("/"), !source.hasPrefix("~"),
                  !seen.contains(source) else { return false }
            let decoded = source.removingPercentEncoding ?? source
            guard !decoded.split(separator: "/").contains("..") else { return false }
            seen.insert(source)
            return true
        }
    }

    package static func markdownCopyURL(for source: URL, exists: (URL) -> Bool) -> URL {
        let folder = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent
        var candidate = folder.appendingPathComponent(base).appendingPathExtension("md")
        var counter = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(base) \(counter)").appendingPathExtension("md")
            counter += 1
        }
        return candidate
    }

    package static func validatedLink(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, host.contains(".") || host == "localhost" else { return nil }
        return url
    }

    package static func flattenedTitle(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "\r\n", with: " ")
        for separator in ["\n", "\r", "\u{2028}", "\u{2029}", "\t"] { value = value.replacingOccurrences(of: separator, with: " ") }
        return value
    }
}

struct NoteCalloutAlert: Hashable {
    var icon: String
    var color: NoteColor

    private static let table: [String: NoteCalloutAlert] = {
        let groups: [([String], String, NoteColor)] = [
            (["note"], "\u{2139}\u{FE0F}", .blue),
            (["tip", "hint"], "\u{1F4A1}", .green),
            (["important"], "\u{2757}\u{FE0F}", .purple),
            (["warning", "attention"], "\u{26A0}\u{FE0F}", .yellow),
            (["caution"], "\u{1F6D1}", .red),
            (["info"], "\u{2139}\u{FE0F}", .blue),
            (["todo"], "\u{2611}\u{FE0F}", .blue),
            (["abstract", "summary", "tldr"], "\u{1F4CB}", .blue),
            (["success", "check", "done"], "\u{2705}", .green),
            (["question", "help", "faq"], "\u{2753}", .orange),
            (["failure", "fail", "missing"], "\u{274C}", .red),
            (["danger", "error"], "\u{26A1}\u{FE0F}", .red),
            (["bug"], "\u{1F41B}", .red),
            (["example"], "\u{1F4DD}", .purple),
            (["quote", "cite"], "\u{1F4AC}", .gray),
        ]
        var result: [String: NoteCalloutAlert] = [:]
        for (names, icon, color) in groups {
            for name in names { result[name] = NoteCalloutAlert(icon: icon, color: color) }
        }
        return result
    }()

    static func defaults(for alert: String?) -> NoteCalloutAlert? {
        guard let alert else { return nil }
        return table[alert.lowercased()]
    }
}

extension NoteBlock {
    var calloutAlert: NoteCalloutAlert? {
        kind == .callout ? NoteCalloutAlert.defaults(for: props.alert) : nil
    }

    package var calloutDisplayIcon: String? {
        guard kind == .callout else { return nil }
        if let icon = props.icon { return icon.isEmpty ? nil : icon }
        return calloutAlert?.icon
    }

    package var calloutDisplayColor: NoteColorStyle? {
        guard kind == .callout else { return color }
        if let color { return color }
        return calloutAlert.map { .background($0.color) }
    }

    package var calloutIconRemoval: String? {
        calloutAlert == nil ? nil : ""
    }
}

package struct NotePagePrintSpan: Hashable {
    var minY: CGFloat
    var maxY: CGFloat
    var keepsTogether: Bool

    package init(minY: CGFloat, maxY: CGFloat, keepsTogether: Bool) {
        self.minY = minY
        self.maxY = maxY
        self.keepsTogether = keepsTogether
    }
}

package enum NotePagePagination {
    package static func pageBreak(proposed: CGFloat, limit: CGFloat, spans: [NotePagePrintSpan]) -> CGFloat {
        var bottom = proposed
        var moved = true
        while moved {
            moved = false
            for span in spans where span.keepsTogether && span.minY < bottom - 0.5 && span.maxY > bottom + 0.5 && span.minY >= limit {
                bottom = span.minY
                moved = true
            }
        }
        return bottom
    }

    package static func settledBottom(adjusted: CGFloat, preferred: CGFloat, bottom: CGFloat, limit: CGFloat) -> CGFloat {
        min(bottom, max(min(limit, bottom), min(adjusted, preferred)))
    }
}
