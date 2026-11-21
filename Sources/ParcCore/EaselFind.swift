import Foundation

struct EaselFindMatch: Hashable {
    enum Part: Hashable { case text }

    var itemID: UUID
    var part: Part
    var range: Range<Int>
}

struct EaselFindReplacement: Equatable {
    var document: EaselDocument
    var count: Int
    var touched: Set<UUID>
}

enum EaselFinder {
    static func searchableParts(of item: EaselItem) -> [(part: EaselFindMatch.Part, text: String)] {
        switch item.kind {
        case .text, .sticky, .rectangle, .circle, .arrow, .section, .link, .webCard, .browser, .code:
            return item.text.isEmpty ? [] : [(.text, item.text)]
        case .image, .freehand, .table:
            return []
        }
    }

    static func isReplaceable(_ item: EaselItem) -> Bool {
        guard !item.isLocked else { return false }
        switch item.kind {
        case .text, .sticky, .rectangle, .circle, .arrow, .section, .code: return true
        case .image, .freehand, .link, .webCard, .browser, .table: return false
        }
    }

    static func readingOrder(_ items: [EaselItem]) -> [EaselItem] {
        let sorted = items.sorted { lhs, rhs in
            lhs.frame.y != rhs.frame.y ? lhs.frame.y < rhs.frame.y : (lhs.frame.x != rhs.frame.x ? lhs.frame.x < rhs.frame.x : lhs.id.uuidString < rhs.id.uuidString)
        }
        var rows: [[EaselItem]] = []
        var rowLimit = -Double.infinity
        for item in sorted {
            if !rows.isEmpty, item.frame.y < rowLimit {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
                rowLimit = item.frame.y + item.frame.height / 2
            }
        }
        return rows.flatMap { row in
            row.sorted { lhs, rhs in
                lhs.frame.x != rhs.frame.x ? lhs.frame.x < rhs.frame.x : (lhs.frame.y != rhs.frame.y ? lhs.frame.y < rhs.frame.y : lhs.id.uuidString < rhs.id.uuidString)
            }
        }
    }

    static func matches(of query: String, in document: EaselDocument, options: NoteFindOptions = NoteFindOptions()) -> [EaselFindMatch] {
        guard !query.isEmpty else { return [] }
        var result: [EaselFindMatch] = []
        for item in readingOrder(document.items) {
            for (part, text) in searchableParts(of: item) {
                for range in NotePageFinder.ranges(of: query, in: text, options: options) {
                    result.append(EaselFindMatch(itemID: item.id, part: part, range: range))
                }
            }
        }
        return result
    }

    static func index(of match: EaselFindMatch?, in matches: [EaselFindMatch], document: EaselDocument) -> Int? {
        guard !matches.isEmpty else { return nil }
        guard let match else { return 0 }
        if let exact = matches.firstIndex(of: match) { return exact }
        let order = Dictionary(readingOrder(document.items).enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let target = (order[match.itemID] ?? Int.max, match.range.lowerBound)
        return matches.firstIndex { (order[$0.itemID] ?? Int.max, $0.range.lowerBound) >= target } ?? 0
    }

    static func replace(_ targets: [EaselFindMatch], with replacement: String, in document: EaselDocument) -> EaselFindReplacement {
        var next = document
        var count = 0
        var touched = Set<UUID>()
        var grouped: [UUID: [EaselFindMatch]] = [:]
        for match in targets { grouped[match.itemID, default: []].append(match) }
        for (id, matches) in grouped {
            guard let index = next.items.firstIndex(where: { $0.id == id }), isReplaceable(next.items[index]) else { continue }
            var item = next.items[index]
            var replaced = 0
            var last = Int.max
            for match in matches.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) where match.part == .text {
                guard match.range.upperBound <= last, let updated = replacing(match.range, with: replacement, in: item) else { continue }
                item = updated
                last = match.range.lowerBound
                replaced += 1
            }
            guard replaced > 0, item != next.items[index] else { continue }
            if let rich = item.richText, (try? rich.validate(text: item.text)) == nil { continue }
            next.items[index] = item
            count += replaced
            touched.insert(id)
        }
        return EaselFindReplacement(document: next, count: count, touched: touched)
    }

    static func replacing(_ range: Range<Int>, with replacement: String, in item: EaselItem) -> EaselItem? {
        let text = item.text as NSString
        guard range.lowerBound >= 0, range.upperBound <= text.length, !range.isEmpty else { return nil }
        let nsRange = NSRange(location: range.lowerBound, length: range.count)
        guard text.substring(with: nsRange) != replacement else { return nil }
        var next = item
        next.text = text.replacingCharacters(in: nsRange, with: replacement)
        if let rich = item.richText {
            guard let updated = rich.replacing(range, with: (replacement as NSString).length) else { return nil }
            next.richText = updated
        }
        return next
    }
}

extension EaselRichText {
    func replacing(_ range: Range<Int>, with insertedLength: Int) -> EaselRichText? {
        guard insertedLength >= 0,
              let source = runs.first(where: { $0.location <= range.lowerBound && range.lowerBound < $0.location + $0.length }),
              !runs.contains(where: { $0.attributes.image != nil && $0.location < range.upperBound && range.lowerBound < $0.location + $0.length }) else {
            return nil
        }
        var segments: [(length: Int, attributes: Attributes)] = []
        for run in runs where run.location < range.lowerBound {
            segments.append((min(run.location + run.length, range.lowerBound) - run.location, run.attributes))
        }
        if insertedLength > 0 {
            var attributes = source.attributes
            attributes.image = nil
            segments.append((insertedLength, attributes))
        }
        for run in runs where run.location + run.length > range.upperBound {
            let start = max(run.location, range.upperBound)
            segments.append((run.location + run.length - start, run.attributes))
        }
        var merged: [Run] = []
        var location = 0
        for segment in segments where segment.length > 0 {
            if let last = merged.last, last.attributes == segment.attributes, segment.attributes.image == nil {
                merged[merged.count - 1].length += segment.length
            } else {
                merged.append(Run(location: location, length: segment.length, attributes: segment.attributes))
            }
            location += segment.length
        }
        return EaselRichText(runs: merged)
    }
}

enum EaselViewportFocus {
    struct Plan: Equatable {
        var magnification: Double
        var center: EaselPoint
    }

    enum Mode { case reveal, focus }

    static func plan(target: EaselRect, visible: EaselRect, magnification: Double, minimum: Double, maximum: Double,
                     mode: Mode = .reveal, preferred: Double = 1, legible: Double = 0.6, margin: Double = 72) -> Plan? {
        guard [target.x, target.y, target.width, target.height, visible.x, visible.y, visible.width, visible.height, magnification]
                .allSatisfy(\.isFinite), visible.width > 0, visible.height > 0, magnification > 0 else { return nil }
        let viewport = (width: visible.width * magnification, height: visible.height * magnification)
        let fit = EaselZoom.fitting(EaselRect(x: target.x, y: target.y, width: max(1, target.width), height: max(1, target.height)),
                                    viewport: viewport, padding: margin, minimum: minimum, maximum: maximum) ?? magnification
        var zoom = magnification
        switch mode {
        case .focus: zoom = min(fit, preferred)
        case .reveal: if zoom > fit + 0.0001 { zoom = fit } else if zoom < legible { zoom = min(fit, max(zoom, preferred)) }
        }
        zoom = EaselZoom.clamped(zoom, minimum: minimum, maximum: maximum)
        let center = EaselPoint(x: target.x + target.width / 2, y: target.y + target.height / 2)
        if mode == .reveal, abs(zoom - magnification) < 0.0001 {
            let inset = min(margin / magnification, visible.width / 4, visible.height / 4)
            let safe = EaselRect(x: visible.x + inset, y: visible.y + inset,
                                 width: max(0, visible.width - inset * 2), height: max(0, visible.height - inset * 2))
            let inside = target.x >= safe.x && target.y >= safe.y
                && target.x + target.width <= safe.x + safe.width && target.y + target.height <= safe.y + safe.height
            if inside { return nil }
        }
        return Plan(magnification: zoom, center: center)
    }
}
