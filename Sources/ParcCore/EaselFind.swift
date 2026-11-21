import Foundation

package struct EaselFindMatch: Hashable {
    package enum Part: Hashable {
        case text
        case cell(row: Int, column: Int)
    }

    package var itemID: UUID
    package var part: Part
    package var range: Range<Int>
    package init(itemID: UUID, part: Part, range: Range<Int>) {
        self.itemID = itemID
        self.part = part
        self.range = range
    }
}

package enum EaselReplaceability: Equatable { case replaceable, locked, readOnly }

package struct EaselFindReplacement: Equatable {
    package var document: EaselDocument
    package var count = 0
    package var touched = Set<UUID>()
    package var skippedLocked = 0
    package var skippedReadOnly = 0
    package var skippedOther = 0
    package init(document: EaselDocument, count: Int = 0, touched: Set<UUID> = Set<UUID>(), skippedLocked: Int = 0, skippedReadOnly: Int = 0, skippedOther: Int = 0) {
        self.document = document
        self.count = count
        self.touched = touched
        self.skippedLocked = skippedLocked
        self.skippedReadOnly = skippedReadOnly
        self.skippedOther = skippedOther
    }

    package var skipped: Int { skippedLocked + skippedReadOnly + skippedOther }
}

package enum EaselFinder {
    package static func searchableParts(of item: EaselItem) -> [(part: EaselFindMatch.Part, text: String)] {
        switch item.kind {
        case .text, .sticky, .rectangle, .circle, .arrow, .section, .link, .code:
            return item.text.isEmpty ? [] : [(.text, item.text)]
        case .webCard:
            return item.assetID == nil && !item.text.isEmpty ? [(.text, item.text)] : []
        case .table:
            guard let table = item.table else { return [] }
            return table.visibleCells.compactMap { coordinate in
                guard let text = table.cell(coordinate)?.text, !text.isEmpty else { return nil }
                return (.cell(row: coordinate.row, column: coordinate.column), text)
            }
        case .image, .freehand, .browser, .stamp, .video, .audio, .file, .pdf, .equation:
            return []
        }
    }

    package static func richText(of item: EaselItem, part: EaselFindMatch.Part) -> EaselRichText? {
        switch part {
        case .text: return item.richText
        case .cell(let row, let column): return item.table?.cell(EaselTableCoordinate(row: row, column: column))?.richText
        }
    }

    package static func replaceability(of item: EaselItem) -> EaselReplaceability {
        switch item.kind {
        case .text, .sticky, .rectangle, .circle, .arrow, .section, .code, .table: return item.isLocked ? .locked : .replaceable
        case .image, .freehand, .link, .webCard, .browser, .stamp, .video, .audio, .file, .pdf, .equation: return .readOnly
        }
    }

    package static func readingOrder(_ items: [EaselItem]) -> [EaselItem] {
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

    package static func visibleItems(in document: EaselDocument) -> [EaselItem] {
        let hidden = EaselBoardObjects.hiddenIDs(in: document.items)
        return hidden.isEmpty ? document.items : document.items.filter { !hidden.contains($0.id) }
    }

    package static func matches(of query: String, in document: EaselDocument, options: NoteFindOptions = NoteFindOptions()) -> [EaselFindMatch] {
        guard !query.isEmpty else { return [] }
        var result: [EaselFindMatch] = []
        for item in EaselPages.pageDocuments(document).flatMap({ readingOrder(visibleItems(in: $0)) }) {
            for (part, text) in searchableParts(of: item) {
                let map = EaselRichText.readableMap(text, rich: richText(of: item, part: part))
                var last: Range<Int>?
                for found in NotePageFinder.ranges(of: query, in: map.text, options: options) {
                    guard found.lowerBound < map.starts.count, found.upperBound >= 1, found.upperBound <= map.ends.count else { continue }
                    let range = map.starts[found.lowerBound]..<map.ends[found.upperBound - 1]
                    guard range != last else { continue }
                    last = range
                    result.append(EaselFindMatch(itemID: item.id, part: part, range: range))
                }
            }
        }
        return result
    }

    package static func index(of match: EaselFindMatch?, in matches: [EaselFindMatch], document: EaselDocument) -> Int? {
        guard !matches.isEmpty else { return nil }
        guard let match else { return 0 }
        if let exact = matches.firstIndex(of: match) { return exact }
        var order: [UUID: Int] = [:]
        for (offset, item) in readingOrder(document.items).enumerated() where order[item.id] == nil { order[item.id] = offset }
        func key(_ value: EaselFindMatch) -> (Int, Int, Int) {
            let part: Int
            switch value.part {
            case .text: part = 0
            case .cell(let row, let column): part = 1 + row * 10_000 + column
            }
            return (order[value.itemID] ?? Int.max, part, value.range.lowerBound)
        }
        let target = key(match)
        return matches.firstIndex { key($0) >= target } ?? 0
    }

    package static func nextReplaceable(after index: Int, in matches: [EaselFindMatch], document: EaselDocument) -> Int? {
        guard matches.indices.contains(index) else { return nil }
        var kinds: [UUID: EaselReplaceability] = [:]
        for item in document.items where kinds[item.id] == nil { kinds[item.id] = replaceability(of: item) }
        for step in 1..<max(1, matches.count + 1) {
            let candidate = (index + step) % matches.count
            if kinds[matches[candidate].itemID] == .replaceable { return candidate }
        }
        return nil
    }

    package static func replace(_ targets: [EaselFindMatch], with replacement: String, in document: EaselDocument) -> EaselFindReplacement {
        var outcome = EaselFindReplacement(document: document)
        var grouped: [UUID: Set<EaselFindMatch>] = [:]
        var order: [UUID] = []
        for match in targets {
            if grouped[match.itemID] == nil { order.append(match.itemID) }
            grouped[match.itemID, default: []].insert(match)
        }
        for id in order {
            guard let matches = grouped[id], let index = outcome.document.items.firstIndex(where: { $0.id == id }) else { continue }
            switch replaceability(of: outcome.document.items[index]) {
            case .locked: outcome.skippedLocked += matches.count; continue
            case .readOnly: outcome.skippedReadOnly += matches.count; continue
            case .replaceable: break
            }
            guard let rewritten = rewrite(outcome.document.items[index], matches: matches, with: replacement) else {
                outcome.skippedOther += matches.count
                continue
            }
            outcome.count += rewritten.changed
            if rewritten.item != outcome.document.items[index] {
                outcome.document.items[index] = rewritten.item
                outcome.touched.insert(id)
            }
        }
        return outcome
    }

    package static func rewrite(_ item: EaselItem, matches: Set<EaselFindMatch>, with replacement: String) -> (item: EaselItem, changed: Int)? {
        var next = item
        var changed = 0
        var parts: [EaselFindMatch.Part: [EaselFindMatch]] = [:]
        for match in matches { parts[match.part, default: []].append(match) }
        for (part, group) in parts {
            switch part {
            case .text:
                guard let result = rewrite(next.text, rich: next.richText, group, with: replacement) else { return nil }
                next.text = result.text
                next.richText = result.rich
                changed += result.changed
            case .cell(let row, let column):
                let coordinate = EaselTableCoordinate(row: row, column: column)
                guard var table = next.table, table.visibleCells.contains(coordinate), let cell = table.cell(coordinate),
                      table.cells.indices.contains(row), table.cells[row].indices.contains(column),
                      let result = rewrite(cell.text, rich: cell.richText, group, with: replacement) else { return nil }
                table.cells[row][column].text = result.text
                table.cells[row][column].richText = result.rich
                next.table = table
                changed += result.changed
            }
        }
        return (next, changed)
    }

    package static func rewrite(_ text: String, rich: EaselRichText?, _ matches: [EaselFindMatch],
                        with replacement: String) -> (text: String, rich: EaselRichText?, changed: Int)? {
        var value = text, styled = rich, changed = 0, last = Int.max
        for match in matches.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            guard match.range.upperBound <= last else { return nil }
            switch replacing(match.range, with: replacement, text: value, rich: styled) {
            case .unchanged: break
            case .failed: return nil
            case .changed(let next, let nextRich):
                value = next
                styled = nextRich
                changed += 1
            }
            last = match.range.lowerBound
        }
        if let styled, (try? styled.validate(text: value)) == nil { return nil }
        return (value, styled, changed)
    }

    package enum Rewrite: Equatable {
        case changed(String, EaselRichText?), unchanged, failed
    }

    package static func replacing(_ range: Range<Int>, with replacement: String, text: String, rich: EaselRichText?) -> Rewrite {
        let source = text as NSString
        guard range.lowerBound >= 0, range.upperBound <= source.length, !range.isEmpty else { return .failed }
        let nsRange = NSRange(location: range.lowerBound, length: range.count)
        if let rich, rich.runs.contains(where: { $0.attributes.isAtomic && $0.location < range.upperBound && range.lowerBound < $0.location + $0.length }) {
            return .failed
        }
        guard source.substring(with: nsRange) != replacement else { return .unchanged }
        let next = source.replacingCharacters(in: nsRange, with: replacement)
        guard let rich else { return .changed(next, nil) }
        guard let updated = rich.replacing(range, with: (replacement as NSString).length) else { return .failed }
        return .changed(next, updated)
    }
}

extension EaselRichText {
    package func replacing(_ range: Range<Int>, with insertedLength: Int) -> EaselRichText? {
        guard insertedLength >= 0,
              let source = runs.first(where: { $0.location <= range.lowerBound && range.lowerBound < $0.location + $0.length }),
              !runs.contains(where: { $0.attributes.isAtomic && $0.location < range.upperBound && range.lowerBound < $0.location + $0.length }) else {
            return nil
        }
        var segments: [(length: Int, attributes: Attributes)] = []
        for run in runs where run.location < range.lowerBound {
            segments.append((min(run.location + run.length, range.lowerBound) - run.location, run.attributes))
        }
        if insertedLength > 0 {
            var attributes = source.attributes
            attributes.image = nil; attributes.inline = nil
            segments.append((insertedLength, attributes))
        }
        for run in runs where run.location + run.length > range.upperBound {
            let start = max(run.location, range.upperBound)
            segments.append((run.location + run.length - start, run.attributes))
        }
        var merged: [Run] = []
        var location = 0
        for segment in segments where segment.length > 0 {
            if let last = merged.last, last.attributes == segment.attributes, !segment.attributes.isAtomic {
                merged[merged.count - 1].length += segment.length
            } else {
                merged.append(Run(location: location, length: segment.length, attributes: segment.attributes))
            }
            location += segment.length
        }
        return EaselRichText(runs: merged)
    }
}

package struct EaselFindSession: Equatable {
    package enum ReplaceStep: Equatable {
        case replaced(EaselFindReplacement, next: EaselFindMatch)
        case moved
        case skipped
        case refused
    }

    package var query = ""
    package var options = NoteFindOptions()
    package private(set) var matches: [EaselFindMatch] = []
    package private(set) var currentIndex: Int?
    package init(query: String = "", options: NoteFindOptions = NoteFindOptions(), matches: [EaselFindMatch] = [], currentIndex: Int? = nil) {
        self.query = query
        self.options = options
        self.matches = matches
        self.currentIndex = currentIndex
    }

    package var currentMatch: EaselFindMatch? {
        guard let currentIndex, matches.indices.contains(currentIndex) else { return nil }
        return matches[currentIndex]
    }

    package mutating func clear() {
        matches = []
        currentIndex = nil
    }

    package mutating func refresh(in document: EaselDocument, keeping match: EaselFindMatch?, preferred: (([EaselFindMatch]) -> Int?)? = nil) {
        matches = EaselFinder.matches(of: query, in: document, options: options)
        if let match {
            currentIndex = EaselFinder.index(of: match, in: matches, document: document)
        } else {
            currentIndex = matches.isEmpty ? nil : (preferred?(matches) ?? 0)
        }
    }

    package mutating func step(_ delta: Int) {
        guard !matches.isEmpty else { return }
        let count = matches.count
        currentIndex = currentIndex.map { (($0 + delta) % count + count) % count } ?? (delta > 0 ? 0 : count - 1)
    }

    package func replaceability(in document: EaselDocument) -> EaselReplaceability? {
        guard let match = currentMatch, let item = document.items.first(where: { $0.id == match.itemID }) else { return nil }
        return EaselFinder.replaceability(of: item)
    }

    package mutating func replaceCurrent(with replacement: String, in document: EaselDocument) -> ReplaceStep {
        let previous = currentMatch
        let fresh = EaselFinder.matches(of: query, in: document, options: options)
        if fresh != matches {
            matches = fresh
            if let previous, let survived = fresh.firstIndex(of: previous) {
                currentIndex = survived
            } else {
                currentIndex = EaselFinder.index(of: previous, in: fresh, document: document)
                return currentIndex == nil ? .refused : .moved
            }
        }
        guard let index = currentIndex, let match = currentMatch,
              let item = document.items.first(where: { $0.id == match.itemID }) else { return .refused }
        guard EaselFinder.replaceability(of: item) == .replaceable else {
            guard let next = EaselFinder.nextReplaceable(after: index, in: matches, document: document) else { return .refused }
            currentIndex = next
            return .skipped
        }
        let outcome = EaselFinder.replace([match], with: replacement, in: document)
        guard outcome.skipped == 0 else { return .refused }
        let offset = match.range.lowerBound + (outcome.count > 0 ? (replacement as NSString).length : match.range.count)
        return .replaced(outcome, next: EaselFindMatch(itemID: match.itemID, part: match.part, range: offset..<offset))
    }

    package mutating func replaceAll(with replacement: String, in document: EaselDocument) -> EaselFindReplacement {
        refresh(in: document, keeping: currentMatch)
        return EaselFinder.replace(matches, with: replacement, in: document)
    }

    package func countLabel(replacing: Bool, in document: EaselDocument) -> String {
        guard !query.isEmpty else { return "" }
        guard let currentIndex, !matches.isEmpty else { return matches.isEmpty ? "No matches" : "\(matches.count) found" }
        let position = "\(currentIndex + 1) of \(matches.count)"
        guard replacing else { return position }
        switch replaceability(in: document) {
        case .locked?: return position + " · locked"
        case .readOnly?: return position + " · read-only"
        default: return position
        }
    }

    package static func summary(_ outcome: EaselFindReplacement) -> String {
        var parts: [String] = []
        if outcome.skippedLocked > 0 { parts.append("\(outcome.skippedLocked) locked") }
        if outcome.skippedReadOnly > 0 { parts.append("\(outcome.skippedReadOnly) read-only") }
        if outcome.skippedOther > 0 { parts.append("\(outcome.skippedOther) that couldn’t change") }
        guard !parts.isEmpty else { return "" }
        return "Skipped " + parts.joined(separator: ", ")
    }
}

package enum EaselViewportFocus {
    package struct Plan: Equatable {
        package var magnification: Double
        package var center: EaselPoint
        package init(magnification: Double, center: EaselPoint) {
            self.magnification = magnification
            self.center = center
        }
    }

    package enum Mode { case reveal, focus }

    package static func plan(target: EaselRect, visible: EaselRect, magnification: Double, minimum: Double, maximum: Double,
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
