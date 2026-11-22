import Foundation

package enum EaselBoardObjects {
    package static let stickySide = 220.0
    static let stickyWideWidth = 440.0
    static let stickyMaximumWidth = 880.0
    static let stickyPadding = 18.0
    static let textScales = EaselTextStyle.textScales
    static let sectionWidth = 640.0
    static let sectionHeight = 480.0
    static let sectionMinimumWidth = 120.0
    static let sectionMinimumHeight = 80.0
    static let sectionFitPadding = 48.0
    package static let sectionTitleHeight = 26.0
    package static let sectionTitleGap = 6.0
    package static let sectionTitlePadding = 10.0
    package static let sectionTitleLimit = 120
    static let sectionName = "Section"

    static func transforms(_ kind: EaselItemKind) -> Bool { kind != .sticky && kind != .section }

    package static func textScale(_ item: EaselItem) -> Double {
        guard let value = item.textStyle?.textScale, value.isFinite else { return 1 }
        return min(textScales.upperBound, max(textScales.lowerBound, value))
    }

    static func scaledStyle(_ style: EaselTextStyle?, scale: Double) -> EaselTextStyle? {
        let value = scale.isFinite ? min(textScales.upperBound, max(textScales.lowerBound, scale)) : 1
        var next = style ?? EaselTextStyle()
        next.textScale = abs(value - 1) < 0.0005 ? nil : (value * 1000).rounded() / 1000
        return next == EaselTextStyle() ? nil : next
    }

    static func stickyInset(_ item: EaselItem) -> Double { stickyPadding * textScale(item) }

    package static func stickyMinimumHeight(_ item: EaselItem) -> Double { stickySide * textScale(item) }

    static func stickyWidths(_ item: EaselItem) -> ClosedRange<Double> {
        let scale = textScale(item)
        return stickySide * scale...stickyMaximumWidth * scale
    }

    package static func isWide(_ item: EaselItem) -> Bool {
        item.kind == .sticky && item.frame.width >= (stickySide + stickyWideWidth) / 2 * textScale(item)
    }

    package static func stickyTextBox(_ item: EaselItem) -> EaselRect {
        let inset = stickyInset(item)
        return EaselRect(x: item.frame.x + inset, y: item.frame.y + inset,
                         width: max(1, item.frame.width - 2 * inset), height: max(1, item.frame.height - 2 * inset))
    }

    static func stickyHeight(_ item: EaselItem, textHeight: Double) -> Double {
        let minimum = stickyMinimumHeight(item)
        guard textHeight.isFinite, textHeight > 0 else { return minimum }
        return min(EaselRect.maximumCoordinate, max(minimum, (textHeight + 2 * stickyInset(item)).rounded(.up)))
    }

    package static func sticky(centeredAt point: EaselPoint, wide: Bool, zIndex: Int) -> EaselItem {
        let width = wide ? stickyWideWidth : stickySide
        return EaselItem(kind: .sticky, frame: EaselRect(x: max(0, point.x - width / 2), y: max(0, point.y - stickySide / 2),
                                                         width: width, height: stickySide), zIndex: zIndex)
    }

    package static func sticky(origin: EaselPoint, like source: EaselItem, zIndex: Int) -> EaselItem {
        let scale = textScale(source)
        var item = EaselItem(kind: .sticky, frame: EaselRect(x: max(0, origin.x), y: max(0, origin.y),
                                                             width: source.kind == .sticky ? source.frame.width : stickySide,
                                                             height: stickySide * scale), zIndex: zIndex)
        if source.kind == .sticky {
            item.fill = source.fill
            item.fillOpacity = source.fillOpacity
            item.textStyle = scaledStyle(source.textStyle, scale: scale)
        }
        return item
    }

    package static func widened(_ item: EaselItem, wide: Bool, textHeight: (EaselItem) -> Double) -> EaselItem {
        guard item.kind == .sticky else { return item }
        var next = item
        next.frame.width = (wide ? stickyWideWidth : stickySide) * textScale(item)
        next.frame.height = stickyHeight(next, textHeight: textHeight(next))
        return next
    }

    package static func fitted(_ item: EaselItem, textHeight: (EaselItem) -> Double) -> EaselItem {
        guard item.kind == .sticky else { return item }
        var next = item
        next.frame.height = stickyHeight(item, textHeight: textHeight(item))
        return next
    }

    package static func resizedSticky(_ original: EaselItem, proposed: EaselItem, handle: EaselResizeHandle, alone: Bool,
                              textHeight: (EaselItem) -> Double) -> EaselItem {
        guard original.kind == .sticky, original.frame.width > 0 else { return proposed }
        let old = original.frame
        var next = proposed
        if handle.isCorner {
            let scale = textScale(original)
            let requested = proposed.frame.width / old.width
            let factor = requested.isFinite && requested > 0
                ? min(textScales.upperBound / scale, max(textScales.lowerBound / scale, requested)) : 1
            next.textStyle = scaledStyle(original.textStyle, scale: scale * factor)
            next.frame.width = old.width * factor
        } else if handle.movesLeft || handle.movesRight {
            let widths = stickyWidths(original)
            next.textStyle = original.textStyle
            next.frame.width = min(widths.upperBound, max(widths.lowerBound, proposed.frame.width))
        } else {
            next.textStyle = original.textStyle
            next.frame.width = old.width
        }
        next.frame.height = stickyHeight(next, textHeight: textHeight(next))
        if alone {
            next.frame.x = handle.movesLeft ? old.x + old.width - next.frame.width : old.x
            next.frame.y = handle.movesTop ? old.y + old.height - next.frame.height : old.y
        }
        next.frame.x = max(0, next.frame.x)
        next.frame.y = max(0, next.frame.y)
        return next
    }

    static func encloses(_ outer: EaselRect, _ inner: EaselRect) -> Bool {
        let tolerance = 0.5
        return inner.x >= outer.x - tolerance && inner.y >= outer.y - tolerance
            && inner.x + inner.width <= outer.x + outer.width + tolerance
            && inner.y + inner.height <= outer.y + outer.height + tolerance
    }

    static func contains(_ section: EaselItem, _ item: EaselItem) -> Bool {
        guard section.kind == .section, item.id != section.id, encloses(section.frame, item.frame) else { return false }
        guard item.kind == .section else { return true }
        return item.frame.width * item.frame.height < section.frame.width * section.frame.height
    }

    static func members(of section: EaselItem, in items: [EaselItem]) -> [EaselItem] {
        guard section.kind == .section else { return [] }
        return items.filter { contains(section, $0) }
    }

    package static func contents(of section: EaselItem, in items: [EaselItem]) -> [EaselItem] {
        guard section.kind == .section else { return [] }
        var found: [EaselItem] = [], seen: Set<UUID> = [section.id], queue = [section]
        while let current = queue.popLast() {
            for item in items where !seen.contains(item.id) && contains(current, item) {
                seen.insert(item.id)
                found.append(item)
                if item.kind == .section { queue.append(item) }
            }
        }
        return found
    }

    package static func sections(containing point: EaselPoint, in items: [EaselItem]) -> Set<UUID> {
        Set(items.filter { $0.kind == .section && EaselContentHitTest.contains(point, rect: $0.frame) }.map(\.id))
    }

    package static func hiddenIDs(in items: [EaselItem]) -> Set<UUID> {
        let hiding = items.filter { $0.kind == .section && $0.contentsHidden == true }
        let folded = EaselMindMap.hiddenIDs(in: items)
        guard !hiding.isEmpty else { return folded }
        var hidden = folded
        for section in hiding where !hidden.contains(section.id) {
            hidden.formUnion(contents(of: section, in: items).map(\.id))
        }
        return hidden
    }

    static func paintOrder(_ items: [EaselItem]) -> [EaselItem] {
        let sections = items.filter { $0.kind == .section }
        guard !sections.isEmpty else { return items.sorted { $0.zIndex < $1.zIndex } }
        var depth: [UUID: Int] = [:]
        for section in sections { depth[section.id] = sections.filter { contains($0, section) }.count }
        let ordered = sections.sorted { (depth[$0.id] ?? 0, $0.zIndex) < (depth[$1.id] ?? 0, $1.zIndex) }
        return ordered + items.filter { $0.kind != .section }.sorted { $0.zIndex < $1.zIndex }
    }

    package static func displayed(_ items: [EaselItem]) -> [EaselItem] {
        let ordered = paintOrder(items)
        let hidden = hiddenIDs(in: items)
        return hidden.isEmpty ? ordered : ordered.filter { !hidden.contains($0.id) }
    }

    package static func marqueeCandidates(_ items: [EaselItem], in rect: EaselRect, excluding sections: Set<UUID>) -> [EaselItem] {
        let hidden = hiddenIDs(in: items)
        return items.filter { item in
            guard !hidden.contains(item.id), !sections.contains(item.id) else { return false }
            return item.kind != .section || encloses(rect, item.frame)
        }
    }

    package static func hiddenSummary(_ count: Int) -> String {
        count == 1 ? "1 object hidden" : "\(count) objects hidden"
    }

    package static func sectionName(in items: [EaselItem], excluding id: UUID? = nil) -> String {
        let taken = Set(items.filter { $0.kind == .section && $0.id != id }.map { displayTitle($0).lowercased() })
        let base = sectionName.lowercased()
        guard taken.contains(base) else { return sectionName }
        var number = 2
        while taken.contains(base + " " + String(number)) { number += 1 }
        return sectionName + " " + String(number)
    }

    package static func sectionTitle(_ raw: String) -> String {
        let flattened = raw.components(separatedBy: .newlines).joined(separator: " ")
        return String(flattened.trimmingCharacters(in: .whitespacesAndNewlines).prefix(sectionTitleLimit))
    }

    package static func displayTitle(_ section: EaselItem) -> String {
        let title = sectionTitle(section.text)
        return title.isEmpty ? sectionName : title
    }

    package static func section(frame: EaselRect, in items: [EaselItem], zIndex: Int) -> EaselItem {
        EaselItem(kind: .section, frame: frame, zIndex: zIndex, text: sectionName(in: items))
    }

    package static func sectionFrame(centeredAt point: EaselPoint) -> EaselRect {
        EaselRect(x: max(0, point.x - sectionWidth / 2), y: max(0, point.y - sectionHeight / 2),
                  width: sectionWidth, height: sectionHeight)
    }

    package static func sectionFrame(dragged frame: EaselRect) -> EaselRect {
        EaselRect(x: max(0, frame.x), y: max(0, frame.y),
                  width: max(sectionMinimumWidth, frame.width), height: max(sectionMinimumHeight, frame.height))
    }

    package static func sectionFrame(fitting frames: [EaselRect]) -> EaselRect? {
        let valid = frames.filter { [$0.x, $0.y, $0.width, $0.height].allSatisfy(\.isFinite) }
        guard let first = valid.first else { return nil }
        var minX = first.x, minY = first.y, maxX = first.x + first.width, maxY = first.y + first.height
        for frame in valid.dropFirst() {
            minX = min(minX, frame.x); minY = min(minY, frame.y)
            maxX = max(maxX, frame.x + frame.width); maxY = max(maxY, frame.y + frame.height)
        }
        let x = max(0, minX - sectionFitPadding), y = max(0, minY - sectionFitPadding)
        return EaselRect(x: x, y: y, width: max(sectionMinimumWidth, maxX + sectionFitPadding - x),
                         height: max(sectionMinimumHeight, maxY + sectionFitPadding - y))
    }

    package static func titleScale(zoom: Double) -> Double {
        guard zoom.isFinite, zoom > 0 else { return 1 }
        return min(3, max(1, 1 / zoom))
    }

    package static func titleTab(_ section: EaselItem, titleWidth: Double, zoom: Double) -> EaselRect {
        let scale = titleScale(zoom: zoom)
        let height = sectionTitleHeight * scale, gap = sectionTitleGap * scale
        let natural = (max(0, titleWidth.isFinite ? titleWidth : 0) + 2 * sectionTitlePadding) * scale
        let width = max(min(height, section.frame.width), min(section.frame.width, natural))
        let outside = section.frame.y >= height + gap
        return EaselRect(x: section.frame.x, y: outside ? section.frame.y - height - gap : section.frame.y + gap,
                         width: width, height: height)
    }

    static func withContents(_ ids: Set<UUID>, in document: EaselDocument) -> Set<UUID> {
        var result = ids
        for section in document.items where ids.contains(section.id) && section.kind == .section {
            result.formUnion(contents(of: section, in: document.items).map(\.id))
        }
        return result
    }

    static func deletion(_ ids: Set<UUID>, in document: EaselDocument) -> Set<UUID> {
        var result = ids
        for section in document.items where ids.contains(section.id) && section.kind == .section && !section.isLocked {
            for item in contents(of: section, in: document.items) where !item.isLocked { result.insert(item.id) }
        }
        return result
    }

    package static func removingSections(_ ids: Set<UUID>, from document: EaselDocument) -> EaselDocument? {
        let doomed = Set(document.items.filter { ids.contains($0.id) && $0.kind == .section && !$0.isLocked }.map(\.id))
        guard !doomed.isEmpty else { return nil }
        var next = document
        next.items.removeAll { doomed.contains($0.id) }
        return next
    }

    package static func settingContentsHidden(_ hidden: Bool, sections ids: Set<UUID>, in document: EaselDocument) -> EaselDocument? {
        var next = document, changed = false
        let value: Bool? = hidden ? true : nil
        for index in next.items.indices where ids.contains(next.items[index].id) && next.items[index].kind == .section {
            guard next.items[index].contentsHidden != value else { continue }
            next.items[index].contentsHidden = value
            changed = true
        }
        return changed ? next : nil
    }

    package static func lockTargets(_ ids: Set<UUID>, all: Bool, in document: EaselDocument) -> Set<UUID> {
        let sections = document.items.filter { ids.contains($0.id) && $0.kind == .section }
        var targets = Set(sections.map(\.id))
        if all {
            for section in sections { targets.formUnion(contents(of: section, in: document.items).map(\.id)) }
        }
        return targets
    }

    static func carryingSectionContents(_ next: EaselDocument, previous: EaselDocument,
                                        moved: Set<UUID>) -> (document: EaselDocument, moved: Set<UUID>) {
        let movedSections = next.items.filter { moved.contains($0.id) && $0.kind == .section }
        guard !movedSections.isEmpty else { return (next, moved) }
        var before: [UUID: EaselItem] = [:]
        for item in previous.items where before[item.id] == nil { before[item.id] = item }
        var shifts: [UUID: (dx: Double, dy: Double)] = [:], placed: [UUID: EaselPoint] = [:]
        for section in movedSections {
            guard let old = before[section.id], old.kind == .section,
                  old.frame.width == section.frame.width, old.frame.height == section.frame.height else { continue }
            let x = max(0, section.frame.x), y = max(0, section.frame.y)
            if x != section.frame.x || y != section.frame.y { placed[section.id] = EaselPoint(x: x, y: y) }
            let dx = x - old.frame.x, dy = y - old.frame.y
            guard dx.isFinite, dy.isFinite, dx != 0 || dy != 0 else { continue }
            for member in contents(of: old, in: previous.items) where !moved.contains(member.id) && shifts[member.id] == nil {
                shifts[member.id] = (dx, dy)
            }
        }
        guard !shifts.isEmpty || !placed.isEmpty else { return (next, moved) }
        var result = next, carried = moved
        for index in result.items.indices {
            let id = result.items[index].id
            if let point = placed[id] { result.items[index].frame.x = point.x; result.items[index].frame.y = point.y }
            guard let shift = shifts[id], let old = before[id] else { continue }
            result.items[index].frame.x = max(0, old.frame.x + shift.dx)
            result.items[index].frame.y = max(0, old.frame.y + shift.dy)
            carried.insert(id)
        }
        return (result, carried)
    }
}
