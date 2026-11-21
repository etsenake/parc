import Foundation

package enum EaselTextEditing {
    package static let defaultText = "Start typing to enter text"

    package static func isEmpty(_ item: EaselItem) -> Bool {
        item.kind == .text && item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

package enum EaselCanvasSelection {
    package enum Operation { case replace, add, subtract }

    package static func marquee(from start: EaselPoint, to end: EaselPoint) -> EaselRect {
        EaselRect(x: min(start.x, end.x), y: min(start.y, end.y),
                  width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    package static func selecting(in rect: EaselRect, items: [EaselItem],
                          original: Set<UUID>, operation: Operation) -> Set<UUID> {
        let available = Set(items.map(\.id))
        let hits = Set(items.filter {
            EaselContentHitTest.intersects(rect, item: $0, selected: original.contains($0.id))
        }.map(\.id))
        switch operation {
        case .replace: return hits
        case .add: return original.union(hits).intersection(available)
        case .subtract: return original.subtracting(hits).intersection(available)
        }
    }
}

package enum EaselResizeHandle: Int, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight, top, left, bottom, right

    package var movesLeft: Bool { self == .topLeft || self == .bottomLeft || self == .left }
    package var movesRight: Bool { self == .topRight || self == .bottomRight || self == .right }
    package var movesTop: Bool { self == .topLeft || self == .topRight || self == .top }
    package var movesBottom: Bool { self == .bottomLeft || self == .bottomRight || self == .bottom }
    package var isCorner: Bool { rawValue < 4 }

    package func point(in rect: EaselRect) -> EaselPoint {
        EaselPoint(x: movesLeft ? rect.x : movesRight ? rect.x + rect.width : rect.x + rect.width / 2,
                   y: movesTop ? rect.y : movesBottom ? rect.y + rect.height : rect.y + rect.height / 2)
    }

    package func hitRect(in rect: EaselRect, scale: Double = 1) -> EaselRect? {
        guard scale.isFinite, scale > 0 else { return nil }
        let point = point(in: rect), radius = 10 / scale, thickness = 10 / scale
        if isCorner { return .init(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius) }
        guard rect.width * scale >= 30, rect.height * scale >= 30 else { return nil }
        if movesTop || movesBottom {
            return .init(x: rect.x + radius, y: point.y - thickness / 2, width: rect.width - 2 * radius, height: thickness)
        }
        return .init(x: point.x - thickness / 2, y: rect.y + radius, width: thickness, height: rect.height - 2 * radius)
    }
}

package enum EaselArrowEndpoint: CaseIterable {
    case start, end
    package func index(in item: EaselItem) -> Int { self == .start ? 0 : item.points.count - 1 }
    package func point(in item: EaselItem) -> EaselPoint? {
        guard item.kind == .arrow, item.points.count == 2 else { return nil }
        let p = item.points[index(in: item)]
        return .init(x: item.frame.x + p.x, y: item.frame.y + p.y)
    }
    package func hitRect(in item: EaselItem, scale: Double = 1) -> EaselRect? {
        guard let p = point(in: item), scale.isFinite, scale > 0 else { return nil }
        let radius = 10 / scale
        return .init(x: p.x - radius, y: p.y - radius, width: 2 * radius, height: 2 * radius)
    }
}

package struct EaselResizeCentering: OptionSet {
    package let rawValue: Int

    package init(rawValue: Int) {
        self.rawValue = rawValue
    }

    package static let horizontal = Self(rawValue: 1)
    package static let vertical = Self(rawValue: 2)
    package static let both: Self = [.horizontal, .vertical]
}

package struct EaselGeometryEdit {
    package let documentID: UUID
    package let originals: [EaselItem]
    package var ids: Set<UUID> { Set(originals.map(\.id)) }

    package init?(document: EaselDocument, selection: Set<UUID>) {
        let selected = document.items.filter { selection.contains($0.id) }
        guard !selected.isEmpty, selected.count == selection.count else { return nil }
        documentID = document.id; originals = selected
    }

    private init(documentID: UUID, originals: [EaselItem]) { self.documentID = documentID; self.originals = originals }

    package func isCurrent(in document: EaselDocument) -> Bool {
        guard document.id == documentID else { return false }
        let current = Dictionary(document.items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        return originals.allSatisfy { original in
            guard let item = current[original.id] else { return false }
            return item.kind == original.kind && item.frame == original.frame && item.points == original.points
                && item.rotation == original.rotation && item.flipHorizontal == original.flipHorizontal && item.flipVertical == original.flipVertical
        }
    }

    package func translated(x: Double, y: Double) -> [EaselItem] {
        guard x.isFinite, y.isFinite else { return originals }
        let box = EaselRotation.bounds(of: originals)
        let dx = max(-(originals.map { $0.frame.x }.min() ?? 0), -max(0, box?.x ?? 0), x)
        let dy = max(-(originals.map { $0.frame.y }.min() ?? 0), -max(0, box?.y ?? 0), y)
        return originals.map { item in
            var next = item; next.frame.x += dx; next.frame.y += dy; return next
        }
    }

    package var bounds: EaselRect { Self.bounds(of: originals)! }

    package static func bounds(of items: [EaselItem]) -> EaselRect? { EaselRotation.bounds(of: items) }

    package var resizesRotated: Bool { originals.count == 1 && originals.first.map(EaselRotation.isRotated) == true }
    package var canRotate: Bool { EaselRotation.canRotate(originals) }
    package var canFlip: Bool { EaselRotation.canFlip(originals) }

    package func rotated(by delta: Double, around pivot: EaselPoint) -> [EaselItem]? {
        guard let proposed = EaselRotation.rotated(originals, by: delta, around: pivot) else { return nil }
        return Self.validGeometry(proposed) ? proposed : nil
    }

    package func flipped(horizontally: Bool) -> [EaselItem]? {
        guard let proposed = EaselRotation.flipped(originals, horizontally: horizontally) else { return nil }
        return Self.validGeometry(proposed) ? proposed : nil
    }

    private func rotatedResize(using handle: EaselResizeHandle, x: Double, y: Double,
                               centering: EaselResizeCentering, preservingAspect: Bool) -> [EaselItem]? {
        guard let item = originals.first, x.isFinite, y.isFinite,
              let inverse = EaselRotation.transform(for: item).inverted else { return nil }
        let local = inverse.applyVector(EaselPoint(x: x, y: y))
        let offset = item.frame.width + item.frame.height + abs(local.x) + abs(local.y) + 1
        var shifted = EaselRotation.upright(item)
        shifted.frame.x = offset; shifted.frame.y = offset
        let upright = EaselGeometryEdit(documentID: documentID, originals: [shifted])
        let resized = preservingAspect ? upright.resizedPreservingAspect(using: handle, x: local.x, y: local.y, centering: centering)
            : upright.resized(using: handle, x: local.x, y: local.y, centering: centering)
        guard let proposal = resized?.first else { return nil }
        var frame = proposal.frame
        frame.x += item.frame.x - offset; frame.y += item.frame.y - offset
        var next = item
        next.frame = EaselRotation.recentred(item, frame: frame)
        next.points = proposal.points
        if proposal.flipHorizontal == true { next.flipHorizontal = item.flipHorizontal == true ? nil : true }
        if proposal.flipVertical == true { next.flipVertical = item.flipVertical == true ? nil : true }
        return Self.validGeometry([next]) ? [next] : nil
    }

    package func resized(using handle: EaselResizeHandle, x: Double, y: Double, centered: Bool) -> [EaselItem]? {
        resized(using: handle, x: x, y: y, centering: centered ? .both : [])
    }

    package func resized(using handle: EaselResizeHandle, x: Double, y: Double, centering: EaselResizeCentering) -> [EaselItem]? {
        if resizesRotated { return rotatedResize(using: handle, x: x, y: y, centering: centering, preservingAspect: false) }
        guard let proposal = resizingFrame(using: handle, x: x, y: y, centering: centering) else { return nil }
        return mapped(to: proposal.frame, flipX: proposal.flipX, flipY: proposal.flipY)
    }

    private func resizingFrame(using handle: EaselResizeHandle, x: Double, y: Double,
                               centering: EaselResizeCentering) -> (frame: EaselRect, flipX: Bool, flipY: Bool)? {
        guard x.isFinite, y.isFinite else { return nil }
        let original = bounds
        guard original.width > 0, original.height > 0 else { return nil }
        let dx = handle.movesLeft || handle.movesRight ? x : 0
        let dy = handle.movesTop || handle.movesBottom ? y : 0
        var left = original.x, right = left + original.width
        var top = original.y, bottom = top + original.height
        if handle.movesLeft { left += dx; if centering.contains(.horizontal) { right -= dx } }
        if handle.movesRight { right += dx; if centering.contains(.horizontal) { left -= dx } }
        if handle.movesTop { top += dy; if centering.contains(.vertical) { bottom -= dy } }
        if handle.movesBottom { bottom += dy; if centering.contains(.vertical) { top -= dy } }
        let target = EaselRect(x: min(left, right), y: min(top, bottom),
                               width: abs(right - left), height: abs(bottom - top))
        let flipX = original.width < (handle.movesLeft ? dx : -dx)
        let flipY = original.height < (handle.movesTop ? dy : -dy)
        return (target, flipX, flipY)
    }

    package func resizedPreservingAspect(using handle: EaselResizeHandle, x: Double, y: Double,
                                  centering: EaselResizeCentering) -> [EaselItem]? {
        if resizesRotated { return rotatedResize(using: handle, x: x, y: y, centering: centering, preservingAspect: true) }
        guard let plain = resizingFrame(using: handle, x: x, y: y, centering: centering) else { return nil }
        let r = plain.frame
        let ratio = bounds.width / bounds.height
        guard ratio.isFinite, ratio > 0 else { return nil }
        let target: EaselRect
        if handle.isCorner && centering.isEmpty {
            let fixed = EaselPoint(x: handle.movesLeft ? r.x + r.width : r.x,
                                   y: handle.movesTop ? r.y + r.height : r.y)
            let moving = handle.point(in: r)
            let slope = (handle.movesLeft == handle.movesTop ? 1.0 : -1.0) / ratio
            let t = ((moving.x - fixed.x) + (moving.y - fixed.y) * slope) / (1 + slope * slope)
            let end = EaselPoint(x: fixed.x + t, y: fixed.y + t * slope)
            target = .init(x: min(fixed.x, end.x), y: min(fixed.y, end.y),
                           width: abs(end.x - fixed.x), height: abs(end.y - fixed.y))
        } else {
            let width = handle == .top || handle == .bottom ? r.height * ratio : r.width
            let height = width / ratio
            var midX = r.x + r.width / 2, midY = r.y + r.height / 2
            if handle.isCorner && centering != .both {
                if centering.contains(.horizontal) {
                    midY = (handle.movesTop ? r.y + r.height : r.y) + (handle.movesTop ? -height : height) / 2
                }
                if centering.contains(.vertical) {
                    midX = (handle.movesLeft ? r.x + r.width : r.x) + (handle.movesLeft ? -width : width) / 2
                }
            }
            target = .init(x: midX - width / 2, y: midY - height / 2, width: width, height: height)
        }
        return mapped(to: target, flipX: false, flipY: false)
    }

    package func preservesAspect(shift: Bool, command: Bool) -> Bool {
        let intrinsic = originals.contains { $0.kind == .image || $0.kind == .video || $0.kind == .webCard || $0.kind == .link || $0.kind == .sticky || $0.kind == .stamp }
        return !command && (intrinsic || (shift && originals.count > 1))
    }

    package func movingEndpoint(_ endpoint: EaselArrowEndpoint, x: Double, y: Double) -> [EaselItem]? {
        guard originals.count == 1, let first = endpoint.point(in: originals[0]), x.isFinite, y.isFinite else { return nil }
        var next = originals[0]
        var absolute = next.points.map { EaselPoint(x: next.frame.x + $0.x, y: next.frame.y + $0.y) }
        absolute[endpoint.index(in: next)] = .init(x: first.x + x, y: first.y + y)
        let minX = absolute.map(\.x).min()!, minY = absolute.map(\.y).min()!
        let maxX = absolute.map(\.x).max()!, maxY = absolute.map(\.y).max()!
        next.frame = .init(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
        next.points = absolute.map { .init(x: $0.x - minX, y: $0.y - minY) }
        return Self.validGeometry([next]) ? [next] : nil
    }

    private func mapped(to target: EaselRect, flipX: Bool, flipY: Bool) -> [EaselItem]? {
        let original = bounds
        let scaleX = target.width / original.width, scaleY = target.height / original.height
        let proposed = originals.map { item in
            if EaselRotation.isRotated(item) {
                return Self.mappedRotated(item, from: original, to: target, scaleX: scaleX, scaleY: scaleY, flipX: flipX, flipY: flipY)
            }
            var next = item
            if EaselRotation.isFlippable(item.kind), item.kind != .freehand {
                if flipX { next.flipHorizontal = item.flipHorizontal == true ? nil : true }
                if flipY { next.flipVertical = item.flipVertical == true ? nil : true }
            }
            let width = item.frame.width * scaleX, height = item.frame.height * scaleY
            let relativeX = (item.frame.x - original.x) * scaleX
            let relativeY = (item.frame.y - original.y) * scaleY
            next.frame = EaselRect(x: target.x + (flipX ? target.width - relativeX - width : relativeX),
                                   y: target.y + (flipY ? target.height - relativeY - height : relativeY),
                                   width: width, height: height)
            next.points = item.points.map { point in
                EaselPoint(x: (item.kind == .freehand && flipX ? item.frame.width - point.x : point.x) * scaleX,
                           y: (item.kind == .freehand && flipY ? item.frame.height - point.y : point.y) * scaleY)
            }
            return next
        }
        return Self.validGeometry(proposed) ? proposed : nil
    }
    private static func mappedRotated(_ item: EaselItem, from original: EaselRect, to target: EaselRect,
                                      scaleX: Double, scaleY: Double, flipX: Bool, flipY: Bool) -> EaselItem {
        let box = EaselRotation.bounds(of: item), size = EaselRotation.scaledSize(item, scaleX: scaleX, scaleY: scaleY)
        let width = box.width * scaleX, height = box.height * scaleY
        let relativeX = (box.x - original.x) * scaleX, relativeY = (box.y - original.y) * scaleY
        let middle = EaselPoint(x: target.x + (flipX ? target.width - relativeX - width : relativeX) + width / 2,
                                y: target.y + (flipY ? target.height - relativeY - height : relativeY) + height / 2)
        var next = item
        next.frame = EaselRect(x: middle.x - size.width / 2, y: middle.y - size.height / 2, width: size.width, height: size.height)
        let localX = item.frame.width > 0 ? size.width / item.frame.width : 1
        let localY = item.frame.height > 0 ? size.height / item.frame.height : 1
        next.points = item.points.map { EaselPoint(x: $0.x * localX, y: $0.y * localY) }
        if flipX { next = EaselRotation.mirrored(next, horizontally: true, across: middle, moves: false) }
        if flipY { next = EaselRotation.mirrored(next, horizontally: false, across: middle, moves: false) }
        return next
    }
    private static func validGeometry(_ proposed: [EaselItem]) -> Bool {
        proposed.allSatisfy { item in
            let r = item.frame, origin = EaselRotation.isRotated(item) ? EaselRotation.center(of: r) : EaselPoint(x: r.x, y: r.y)
            return [r.x, r.y, r.width, r.height].allSatisfy { $0.isFinite && abs($0) <= 1_000_000 } &&
                origin.x >= 0 && origin.y >= 0 && r.width >= 1 && r.height >= 1 &&
                item.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }
        }
    }

    package func applying(_ proposed: [EaselItem], to document: EaselDocument) -> EaselDocument? {
        guard isCurrent(in: document), proposed.count == originals.count,
              Set(proposed.map(\.id)) == ids else { return nil }
        let changes = Dictionary(proposed.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let styles = Dictionary(originals.map { ($0.id, $0.textStyle) }, uniquingKeysWith: { first, _ in first })
        var next = document
        for index in next.items.indices {
            guard let change = changes[next.items[index].id] else { continue }
            next.items[index].frame = change.frame; next.items[index].points = change.points
            if let style = styles[change.id], change.textStyle != style { next.items[index].textStyle = change.textStyle }
            next.items[index].rotation = change.rotation; next.items[index].waypoints = change.waypoints
            next.items[index].flipHorizontal = change.flipHorizontal; next.items[index].flipVertical = change.flipVertical
        }
        return next
    }
}

package struct EaselObjectCommand {
    package let documentID: UUID
    package let originals: [EaselItem]
    package var ids: Set<UUID> { Set(originals.map(\.id)) }

    package init?(document: EaselDocument, selection: Set<UUID>) {
        let selected = document.items.filter { selection.contains($0.id) }
        guard !selected.isEmpty, selected.count == selection.count else { return nil }
        documentID = document.id
        originals = selected.sorted { $0.zIndex < $1.zIndex }
    }

    package func isCurrent(in document: EaselDocument) -> Bool {
        guard document.id == documentID else { return false }
        let current = Dictionary(document.items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        return originals.allSatisfy { current[$0.id] == $0 }
    }

    package func duplicates(in document: EaselDocument) -> [EaselItem]? {
        guard isCurrent(in: document) else { return nil }
        let maximum = document.items.map(\.zIndex).max() ?? 0
        guard maximum <= Int.max - originals.count else { return nil }
        return originals.enumerated().map { index, item in
            var copy = item; copy.id = UUID()
            copy.frame.x += 24; copy.frame.y += 24
            copy.zIndex = maximum + index + 1; copy.movedToFrontAt = nil
            return copy
        }
    }
}

package enum EaselContentHitTest {
    package static func contains(_ point: EaselPoint, item: EaselItem, selected: Bool, scale: Double = 1) -> Bool {
        guard scale.isFinite, scale > 0, point.x.isFinite, point.y.isFinite else { return false }
        if item.resolvedShape != nil, !EaselShapeGeometry.usesOriginalLook(item) {
            return EaselShapeGeometry.hits(point, item: item, selected: selected, scale: scale)
        }
        if let upright = EaselRotation.uprightHit(point, item: item) { return contains(upright.point, item: upright.item, selected: selected, scale: scale) }
        let r = item.frame, minimum = 30 / scale
        let target = EaselRect(x: r.x - max(0, minimum - r.width) / 2,
                               y: r.y - max(0, minimum - r.height) / 2,
                               width: max(minimum, r.width), height: max(minimum, r.height))
        guard contains(point, rect: target) else { return false }
        if selected || r.width <= minimum || r.height <= minimum { return true }
        switch item.kind {
        case .circle:
            return pow((point.x - r.x - r.width / 2) / (r.width / 2), 2) +
                   pow((point.y - r.y - r.height / 2) / (r.height / 2), 2) <= 1
        case .arrow, .freehand:
            let points = item.points.map { EaselPoint(x: r.x + $0.x, y: r.y + $0.y) }
            let segments = zip(points, points.dropFirst()).map { ($0, $1) } + arrowHead(item)
            return segments.contains { distance(point, from: $0.0, to: $0.1) <= minimum / 2 }
        default: return true
        }
    }

    package static func intersects(_ rect: EaselRect, item: EaselItem, selected: Bool) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        if item.resolvedShape != nil, !EaselShapeGeometry.usesOriginalLook(item) {
            return EaselShapeGeometry.intersects(rect, item: item, selected: selected)
        }
        if let rotated = EaselRotation.intersects(rect, item: item, selected: selected) { return rotated }
        if selected { return intersects(rect, item.frame) }
        let r = item.frame
        switch item.kind {
        case .freehand:
            return item.points.contains { contains(.init(x: r.x + $0.x, y: r.y + $0.y), rect: rect) }
        case .arrow:
            guard let first = item.points.first, let last = item.points.last else { return false }
            return segment(.init(x: r.x + first.x, y: r.y + first.y),
                           .init(x: r.x + last.x, y: r.y + last.y), intersects: rect)
        case .circle:
            guard intersects(rect, r), r.width > 0, r.height > 0 else { return false }
            let cx = r.x + r.width / 2, cy = r.y + r.height / 2
            let x = min(max(cx, rect.x), rect.x + rect.width)
            let y = min(max(cy, rect.y), rect.y + rect.height)
            return pow((x - cx) / (r.width / 2), 2) + pow((y - cy) / (r.height / 2), 2) <= 1
        default: return intersects(rect, r)
        }
    }
    package static func contains(_ point: EaselPoint, rect: EaselRect) -> Bool {
        point.x >= rect.x && point.x <= rect.x + rect.width && point.y >= rect.y && point.y <= rect.y + rect.height
    }
    package static func intersects(_ a: EaselRect, _ b: EaselRect) -> Bool {
        a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y
    }
    private static func distance(_ p: EaselPoint, from a: EaselPoint, to b: EaselPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy
        let t = length > 0 ? min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length)) : 0
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }
    private static func arrowHead(_ item: EaselItem) -> [(EaselPoint, EaselPoint)] {
        guard item.kind == .arrow, item.points.count >= 2, let last = item.points.last else { return [] }
        let previous = item.points[item.points.count - 2], angle = atan2(last.y - previous.y, last.x - previous.x)
        let end = EaselPoint(x: item.frame.x + last.x, y: item.frame.y + last.y)
        return [-0.5, 0.5].map { offset in
            (.init(x: end.x - cos(angle + offset) * 16, y: end.y - sin(angle + offset) * 16), end)
        }
    }
    private static func segment(_ a: EaselPoint, _ b: EaselPoint, intersects r: EaselRect) -> Bool {
        var low = 0.0, high = 1.0
        for (origin, delta, minimum, maximum) in [(a.x, b.x - a.x, r.x, r.x + r.width),
                                                  (a.y, b.y - a.y, r.y, r.y + r.height)] {
            if abs(delta) < 1e-12 { if origin < minimum || origin > maximum { return false } }
            else {
                let t1 = (minimum - origin) / delta, t2 = (maximum - origin) / delta
                low = max(low, min(t1, t2)); high = min(high, max(t1, t2))
                if low > high { return false }
            }
        }
        return true
    }
}

package enum EaselAnchor: Int, CaseIterable {
    case left, right, centerX, top, bottom, centerY
    package var horizontal: Bool { rawValue < 3 }
    package func value(in r: EaselRect) -> Double {
        switch self {
        case .left: return r.x
        case .right: return r.x + r.width
        case .centerX: return r.x + r.width / 2
        case .top: return r.y
        case .bottom: return r.y + r.height
        case .centerY: return r.y + r.height / 2
        }
    }
}

package struct EaselAlignmentGuides {
    package struct Segment: Equatable {
        package let start: EaselPoint
        package let end: EaselPoint

        package init(start: EaselPoint, end: EaselPoint) {
            self.start = start
            self.end = end
        }
    }
    package struct Line: Equatable {
        package let anchor: EaselAnchor
        package let coordinate: Double
        package let targetSegments: [Segment]
        package let anchorSegments: [Segment]

        package init(anchor: EaselAnchor, coordinate: Double, targetSegments: [Segment], anchorSegments: [Segment]) {
            self.anchor = anchor
            self.coordinate = coordinate
            self.targetSegments = targetSegments
            self.anchorSegments = anchorSegments
        }
    }
    private struct Guide {
        let itemID: UUID?
        let frame: EaselRect
        let anchor: EaselAnchor
        let spacing: Bool
        var offset: Double = 0
        var translationAtSnap: EaselPoint?
    }
    private var guides: [Guide]
    private let margin: Double
    private let canvasWidth: Double
    private let viewport: EaselRect
    package let activeAtDragBegin: Set<EaselAnchor>
    package private(set) var lines: [Line] = []
    package init(edit: EaselGeometryEdit, items: [EaselItem], viewport: EaselRect, canvasWidth: Double, scale: Double = 1) {
        self.canvasWidth = max(0, canvasWidth.isFinite ? canvasWidth : 0)
        margin = self.canvasWidth * 0.075
        self.viewport = viewport
        let canvas = EaselRect(x: 0, y: 0, width: self.canvasWidth, height: 0)
        let canvasGuides = self.canvasWidth > 0 ? [
            Guide(itemID: nil, frame: canvas, anchor: .left, spacing: false, offset: self.canvasWidth * 0.042),
            Guide(itemID: nil, frame: canvas, anchor: .centerX, spacing: false),
            Guide(itemID: nil, frame: canvas, anchor: .right, spacing: false, offset: -self.canvasWidth * 0.042)
        ] : []
        guides = canvasGuides + items.filter { !edit.ids.contains($0.id) }.flatMap { item in
            [EaselAnchor.top, .bottom, .left, .right, .centerY, .centerX].map {
                Guide(itemID: item.id, frame: EaselRotation.bounds(of: item), anchor: $0, spacing: false)
            } + [EaselAnchor.top, .bottom, .left, .right].map {
                Guide(itemID: item.id, frame: EaselRotation.bounds(of: item), anchor: $0, spacing: true)
            }
        }
        let original = edit.bounds
        let proximity = margin, tolerance = self.canvasWidth * 0.000001
        let initialScale = scale.isFinite && scale > 0 ? scale : 1
        activeAtDragBegin = Set(guides.filter {
            Self.isEligible($0, bounds: original, viewport: viewport, margin: proximity) &&
            abs(Self.target($0, scale: initialScale) - $0.anchor.value(in: original)) < tolerance
        }.map(\.anchor))
    }
    package func matchesCanvas(width: Double) -> Bool { width == canvasWidth }

    package mutating func proposal(edit: EaselGeometryEdit, document: EaselDocument, translation: EaselPoint,
                           velocity: EaselPoint, scale: Double = 1, handle: EaselResizeHandle?,
                           centered: Bool, enabled: Bool, preserveAspect: Bool = false,
                           aspectGuideRatio: Double? = nil, viewport liveViewport: EaselRect? = nil,
                           endpoint: EaselArrowEndpoint? = nil) -> [EaselItem]? {
        lines.removeAll()
        var x = translation.x, y = translation.y
        var centering: EaselResizeCentering = centered ? .both : []
        if activeAtDragBegin.contains(.centerX), !edit.resizesRotated { centering.insert(.horizontal) }
        if activeAtDragBegin.contains(.centerY), !edit.resizesRotated { centering.insert(.vertical) }
        func proposed(_ x: Double, _ y: Double) -> [EaselItem]? {
            if let endpoint { return edit.movingEndpoint(endpoint, x: x, y: y) }
            if let handle {
                return preserveAspect ? edit.resizedPreservingAspect(using: handle, x: x, y: y, centering: centering) :
                    edit.resized(using: handle, x: x, y: y, centering: centering)
            }
            return edit.translated(x: x, y: y)
        }
        guard edit.isCurrent(in: document), scale.isFinite, scale > 0, var result = proposed(x, y) else { return nil }
        guard enabled, handle == nil || !edit.resizesRotated else {
            for index in guides.indices { guides[index].translationAtSnap = nil }; return result
        }
        let current = Dictionary(document.items.map { ($0.id, EaselRotation.bounds(of: $0)) }, uniquingKeysWith: { _, last in last })
        var accepted: [Int] = []
        for index in guides.indices {
            let guide = guides[index]
            guard guide.itemID.map({ current[$0] == guide.frame }) ?? true,
                  let bounds = EaselGeometryEdit.bounds(of: result) else {
                guides[index].translationAtSnap = nil; continue
            }
            guard Self.isEligible(guide, bounds: bounds, viewport: liveViewport ?? viewport, margin: margin) else {
                guides[index].translationAtSnap = nil; continue
            }
            let anchor = guide.anchor
            let target = Self.target(guide, scale: scale)
            let difference = target - anchor.value(in: bounds)
            let multiplier = anchor == .centerX ? 2.0 : 1.0
            var threshold = 6 * multiplier
            if let beginning = guide.translationAtSnap {
                let crossTravel = anchor.horizontal ? translation.y - beginning.y : translation.x - beginning.x
                threshold *= 1 + min(abs(crossTravel) * scale / 300, 2.5)
            } else {
                let speed = abs(anchor.horizontal ? velocity.x : velocity.y) * scale
                if speed >= 125 * multiplier { continue }
            }
            guard abs(difference) * scale < threshold else { guides[index].translationAtSnap = nil; continue }
            if abs(difference) < canvasWidth * 0.000001 {
                accepted.append(index)
                if guides[index].translationAtSnap == nil { guides[index].translationAtSnap = translation }
                continue
            }
            guard endpoint == nil else { guides[index].translationAtSnap = nil; continue }
            let coefficient = handle.map { Self.coefficient(anchor, handle: $0, centering: centering) } ?? 1
            guard coefficient != 0 else { guides[index].translationAtSnap = nil; continue }
            var correctionX = anchor.horizontal ? difference / coefficient : 0
            var correctionY = anchor.horizontal ? 0 : difference / coefficient
            if preserveAspect, let handle, handle.isCorner {
                let ratio = aspectGuideRatio.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ??
                    (edit.bounds.width / edit.bounds.height)
                let sign = handle.movesLeft == handle.movesTop ? 1.0 : -1.0
                if anchor.horizontal { correctionY = sign * correctionX / ratio }
                else { correctionX = sign * correctionY * ratio }
            }
            let nextX = x + correctionX, nextY = y + correctionY
            guard let next = proposed(nextX, nextY) else { guides[index].translationAtSnap = nil; continue }
            x = nextX; y = nextY; result = next; accepted.append(index)
            if guides[index].translationAtSnap == nil { guides[index].translationAtSnap = translation }
        }
        if let final = EaselGeometryEdit.bounds(of: result) {
            for index in accepted {
                let guide = guides[index], value = Self.target(guide, scale: scale)
                guard abs(guide.anchor.value(in: final) - value) * scale < 0.01 else {
                    guides[index].translationAtSnap = nil; continue
                }
                let targetFrame = guide.itemID == nil ? (liveViewport ?? viewport) : guide.frame
                let line = highlight(anchor: guide.anchor, coordinate: value,
                                     moving: final, target: targetFrame, scale: scale)
                if !lines.contains(line) { lines.append(line) }
            }
        }
        return result
    }
    private func highlight(anchor: EaselAnchor, coordinate: Double, moving: EaselRect,
                           target: EaselRect, scale: Double) -> Line {
        let vertical = anchor.horizontal
        let centered = anchor == .centerX || anchor == .centerY
        let clearance = centered ? canvasWidth * 0.0091 : 0
        let lower = (vertical ? moving.y : moving.x) - clearance
        let upper = (vertical ? moving.y + moving.height : moving.x + moving.width) + clearance
        let from = min(lower, vertical ? target.y : target.x) - canvasWidth * 0.015
        let to = max(upper, vertical ? target.y + target.height : target.x + target.width) + canvasWidth * 0.015
        func segment(_ cross1: Double, _ along1: Double, _ cross2: Double, _ along2: Double) -> Segment {
            Segment(start: .init(x: vertical ? cross1 : along1, y: vertical ? along1 : cross1),
                    end: .init(x: vertical ? cross2 : along2, y: vertical ? along2 : cross2))
        }
        if centered {
            let tick = 7 / scale, half = tick * 0.75
            return Line(anchor: anchor, coordinate: coordinate,
                targetSegments: [segment(coordinate, from, coordinate, lower),
                                 segment(coordinate, upper, coordinate, to)],
                anchorSegments: [segment(coordinate - half, lower, coordinate + half, lower),
                                 segment(coordinate, lower, coordinate, lower - tick),
                                 segment(coordinate - half, upper, coordinate + half, upper),
                                 segment(coordinate, upper, coordinate, upper + tick)])
        }
        return Line(anchor: anchor, coordinate: coordinate,
            targetSegments: [segment(coordinate, from, coordinate, to)],
            anchorSegments: [segment(coordinate, lower, coordinate, upper)])
    }
    private static func isEligible(_ guide: Guide, bounds: EaselRect, viewport: EaselRect, margin: Double) -> Bool {
        if guide.itemID == nil { return true }
        let nearby = EaselRect(x: bounds.x - margin, y: bounds.y - margin,
                               width: bounds.width + 2 * margin, height: bounds.height + 2 * margin)
        guard EaselContentHitTest.intersects(guide.frame, viewport), EaselContentHitTest.intersects(guide.frame, nearby) else { return false }
        guard guide.spacing else { return true }
        return guide.anchor.horizontal ? bounds.y <= guide.frame.y + guide.frame.height && bounds.y + bounds.height >= guide.frame.y :
            bounds.x <= guide.frame.x + guide.frame.width && bounds.x + bounds.width >= guide.frame.x
    }
    private static func target(_ guide: Guide, scale: Double) -> Double {
        let value = guide.anchor.value(in: guide.frame) + guide.offset
        guard guide.spacing else { return value }
        let gap = 24 / scale
        switch guide.anchor {
        case .top: return value + guide.frame.height + gap
        case .bottom: return value - guide.frame.height - gap
        case .left: return value + guide.frame.width + gap
        case .right: return value - guide.frame.width - gap
        default: return value
        }
    }
    private static func coefficient(_ anchor: EaselAnchor, handle: EaselResizeHandle, centering: EaselResizeCentering) -> Double {
        switch anchor {
        case .left: return handle.movesLeft ? 1 : centering.contains(.horizontal) && handle.movesRight ? -1 : 0
        case .right: return handle.movesRight ? 1 : centering.contains(.horizontal) && handle.movesLeft ? -1 : 0
        case .top: return handle.movesTop ? 1 : 0
        case .bottom: return handle.movesBottom ? 1 : 0
        case .centerX: return !centering.contains(.horizontal) && (handle.movesLeft || handle.movesRight) ? 0.5 : 0
        case .centerY: return 0
        }
    }
}
