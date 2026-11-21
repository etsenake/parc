import Foundation

extension EaselBrush {
    var title: String {
        switch self {
        case .marker: return "Drawing"
        case .highlighter: return "Highlight"
        case .washi: return "Washi tape"
        }
    }

    var sticksToObjects: Bool { self != .marker }
    var alwaysStraight: Bool { self == .washi }
}

enum EaselDrawing {
    static let maximumPoints = 20_000
    static let eraserRadius = 9.0
    static let simplifyTolerance = 0.35
    static let straightMagnet = 5.0 * Double.pi / 180
    static let attachmentSamples = 48

    enum PathElement: Equatable {
        case move(EaselPoint)
        case line(EaselPoint)
        case quad(EaselPoint, control: EaselPoint)
    }

    static func safeScale(_ scale: Double) -> Double { scale.isFinite && scale > 0 ? scale : 1 }

    @discardableResult
    static func append(_ point: EaselPoint, to points: inout [EaselPoint], scale: Double) -> Bool {
        guard point.x.isFinite, point.y.isFinite, points.count < maximumPoints else { return false }
        if let last = points.last, hypot(point.x - last.x, point.y - last.y) < 1 / safeScale(scale) { return false }
        points.append(point)
        return true
    }

    static func smoothed(_ points: [EaselPoint]) -> [EaselPoint] {
        guard points.count > 2 else { return points }
        var result = points
        for index in 1..<(points.count - 1) {
            let a = points[index - 1], b = points[index], c = points[index + 1]
            result[index] = EaselPoint(x: (a.x + 2 * b.x + c.x) / 4, y: (a.y + 2 * b.y + c.y) / 4)
        }
        return result
    }

    static func simplified(_ points: [EaselPoint], tolerance: Double) -> [EaselPoint] {
        guard points.count > 2, tolerance.isFinite, tolerance > 0 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var ranges = [(0, points.count - 1)]
        while let (first, last) = ranges.popLast() {
            guard last > first + 1 else { continue }
            var farthest = first, distance = 0.0
            for index in (first + 1)..<last {
                let value = segmentDistance(points[index], points[first], points[last])
                if value > distance { distance = value; farthest = index }
            }
            guard distance > tolerance else { continue }
            keep[farthest] = true
            ranges.append((first, farthest))
            ranges.append((farthest, last))
        }
        return points.indices.compactMap { keep[$0] ? points[$0] : nil }
    }

    static func finished(_ points: [EaselPoint], scale: Double) -> [EaselPoint] {
        let clean = points.filter { $0.x.isFinite && $0.y.isFinite }
        guard let first = clean.first, let last = clean.last else { return [] }
        guard clean.count > 2 else { return [first, last] }
        let result = simplified(smoothed(clean), tolerance: simplifyTolerance / safeScale(scale))
        return result.count >= 2 ? result : [first, last]
    }

    static func straightEnd(from start: EaselPoint, to end: EaselPoint, strict: Bool) -> EaselPoint {
        let dx = end.x - start.x, dy = end.y - start.y, length = hypot(dx, dy)
        guard length > 0, length.isFinite else { return end }
        if strict { return EaselToolGeometry.snappedLineEnd(from: start, to: end) }
        let angle = atan2(dy, dx), step = Double.pi / 4
        let nearest = (angle / step).rounded() * step
        guard abs(angle - nearest) <= straightMagnet else { return end }
        let snapped = EaselPoint(x: start.x + cos(nearest) * length, y: start.y + sin(nearest) * length)
        return EaselPoint(x: abs(snapped.x - start.x) < 1e-9 ? start.x : snapped.x,
                          y: abs(snapped.y - start.y) < 1e-9 ? start.y : snapped.y)
    }

    static func geometry(_ absolute: [EaselPoint]) -> (frame: EaselRect, points: [EaselPoint])? {
        guard let first = absolute.first,
              absolute.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }) else { return nil }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in absolute.dropFirst() {
            minX = min(minX, point.x); minY = min(minY, point.y)
            maxX = max(maxX, point.x); maxY = max(maxY, point.y)
        }
        let frame = EaselRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
        return (frame, absolute.map { EaselPoint(x: $0.x - minX, y: $0.y - minY) })
    }

    static func isStraight(_ item: EaselItem) -> Bool { item.kind == .freehand && item.points.count == 2 }

    static func smoothPath(_ points: [EaselPoint]) -> [PathElement] {
        guard let first = points.first else { return [] }
        guard points.count > 2 else { return [.move(first), .line(points.count == 2 ? points[1] : first)] }
        var elements: [PathElement] = [.move(first), .line(midpoint(points[0], points[1]))]
        for index in 1..<(points.count - 1) {
            elements.append(.quad(midpoint(points[index], points[index + 1]), control: points[index]))
        }
        elements.append(.line(points[points.count - 1]))
        return elements
    }

    static func visualPoints(_ item: EaselItem) -> [EaselPoint] {
        let f = item.frame, center = EaselPoint(x: f.x + f.width / 2, y: f.y + f.height / 2)
        let flipX = item.flipHorizontal == true, flipY = item.flipVertical == true
        let radians = item.resolvedRotation * Double.pi / 180
        return item.points.map { point in
            let local = EaselPoint(x: (flipX ? f.width - point.x : point.x) - f.width / 2,
                                   y: (flipY ? f.height - point.y : point.y) - f.height / 2)
            let turned = rotated(local, by: radians)
            return EaselPoint(x: center.x + turned.x, y: center.y + turned.y)
        }
    }

    static func placing(_ visual: [EaselPoint], like item: EaselItem) -> (frame: EaselRect, points: [EaselPoint])? {
        guard let first = visual.first,
              visual.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }) else { return nil }
        let radians = item.resolvedRotation * Double.pi / 180
        let local = visual.map { rotated(EaselPoint(x: $0.x - first.x, y: $0.y - first.y), by: -radians) }
        var minX = local[0].x, minY = local[0].y, maxX = minX, maxY = minY
        for point in local.dropFirst() {
            minX = min(minX, point.x); minY = min(minY, point.y)
            maxX = max(maxX, point.x); maxY = max(maxY, point.y)
        }
        let middle = EaselPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let width = max(1, maxX - minX), height = max(1, maxY - minY)
        let turned = rotated(middle, by: radians)
        let center = EaselPoint(x: first.x + turned.x, y: first.y + turned.y)
        let flipX = item.flipHorizontal == true, flipY = item.flipVertical == true
        let points = local.map { point in
            EaselPoint(x: (flipX ? middle.x - point.x : point.x - middle.x) + width / 2,
                       y: (flipY ? middle.y - point.y : point.y - middle.y) + height / 2)
        }
        return (EaselRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height), points)
    }

    static func isErasable(_ item: EaselItem) -> Bool { item.kind == .freehand && !item.isLocked }

    static func reach(of item: EaselItem) -> Double {
        if item.resolvedBrush == .washi { return EaselWashi.width / 2 }
        return EaselPaintRules.strokeWidth(item) / 2
    }

    static func touches(_ item: EaselItem, from a: EaselPoint, to b: EaselPoint, radius: Double) -> Bool {
        guard isErasable(item), [a.x, a.y, b.x, b.y, radius].allSatisfy(\.isFinite) else { return false }
        let reach = max(0, radius) + reach(of: item)
        let points = visualPoints(item)
        guard let first = points.first else { return false }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x); minY = min(minY, point.y)
            maxX = max(maxX, point.x); maxY = max(maxY, point.y)
        }
        guard max(a.x, b.x) >= minX - reach, min(a.x, b.x) <= maxX + reach,
              max(a.y, b.y) >= minY - reach, min(a.y, b.y) <= maxY + reach else { return false }
        if points.count == 1 { return segmentDistance(first, a, b) <= reach }
        for (start, end) in zip(points, points.dropFirst()) where segmentsDistance(a, b, start, end) <= reach { return true }
        return false
    }

    static func erased(_ items: [EaselItem], from a: EaselPoint, to b: EaselPoint, radius: Double) -> Set<UUID> {
        Set(items.filter { touches($0, from: a, to: b, radius: radius) }.map(\.id))
    }

    static func canHold(_ item: EaselItem) -> Bool {
        item.kind != .section && item.kind != .freehand && item.kind != .arrow
    }

    static func attachmentTarget(for stroke: [EaselPoint], in items: [EaselItem], excluding: Set<UUID> = []) -> UUID? {
        let samples = resampled(stroke, count: attachmentSamples)
        guard !samples.isEmpty else { return nil }
        let candidates = items.enumerated()
            .filter { canHold($0.element) && !excluding.contains($0.element.id) }
            .sorted { ($0.element.zIndex, $0.offset) > ($1.element.zIndex, $1.offset) }
        var counts: [UUID: Int] = [:], rank: [UUID: Int] = [:]
        for (position, candidate) in candidates.enumerated() where rank[candidate.element.id] == nil {
            rank[candidate.element.id] = position
        }
        for sample in samples {
            guard let top = candidates.first(where: { covers($0.element, sample) }) else { continue }
            counts[top.element.id, default: 0] += 1
        }
        let best = counts.min { left, right in
            left.value != right.value ? left.value > right.value : (rank[left.key] ?? .max) < (rank[right.key] ?? .max)
        }
        guard let best, best.value * 2 > samples.count else { return nil }
        return best.key
    }

    static func covers(_ item: EaselItem, _ point: EaselPoint) -> Bool {
        let f = item.frame
        guard f.width > 0, f.height > 0 else { return false }
        let center = EaselPoint(x: f.x + f.width / 2, y: f.y + f.height / 2)
        let local = rotated(EaselPoint(x: point.x - center.x, y: point.y - center.y), by: -item.resolvedRotation * Double.pi / 180)
        if item.kind == .circle {
            return pow(local.x / (f.width / 2), 2) + pow(local.y / (f.height / 2), 2) <= 1
        }
        return abs(local.x) <= f.width / 2 && abs(local.y) <= f.height / 2
    }

    static func resampled(_ points: [EaselPoint], count: Int) -> [EaselPoint] {
        guard let first = points.first, count > 0 else { return [] }
        let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        let total = lengths.reduce(0, +)
        guard total > 0, total.isFinite, count > 1 else { return [first] }
        var result: [EaselPoint] = [], segment = 0, travelled = 0.0
        for index in 0..<count {
            let target = total * Double(index) / Double(count - 1)
            while segment < lengths.count - 1 && travelled + lengths[segment] < target {
                travelled += lengths[segment]; segment += 1
            }
            let length = lengths[segment], start = points[segment], end = points[segment + 1]
            let t = length > 0 ? min(1, max(0, (target - travelled) / length)) : 0
            result.append(EaselPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
        }
        return result
    }

    static func segmentDistance(_ p: EaselPoint, _ a: EaselPoint, _ b: EaselPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy
        let t = length > 0 ? min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length)) : 0
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }

    static func segmentsDistance(_ a: EaselPoint, _ b: EaselPoint, _ c: EaselPoint, _ d: EaselPoint) -> Double {
        func cross(_ o: EaselPoint, _ p: EaselPoint, _ q: EaselPoint) -> Double { (p.x - o.x) * (q.y - o.y) - (p.y - o.y) * (q.x - o.x) }
        let d1 = cross(c, d, a), d2 = cross(c, d, b), d3 = cross(a, b, c), d4 = cross(a, b, d)
        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) { return 0 }
        return min(segmentDistance(a, c, d), segmentDistance(b, c, d), segmentDistance(c, a, b), segmentDistance(d, a, b))
    }

    static func rotated(_ point: EaselPoint, by radians: Double) -> EaselPoint {
        guard radians != 0 else { return point }
        let c = cos(radians), s = sin(radians)
        return EaselPoint(x: point.x * c - point.y * s, y: point.x * s + point.y * c)
    }

    private static func midpoint(_ a: EaselPoint, _ b: EaselPoint) -> EaselPoint {
        EaselPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}

enum EaselAttachments {
    static func attaches(_ item: EaselItem) -> Bool { item.kind == .freehand && item.resolvedBrush.sticksToObjects }

    static func carry(_ next: EaselDocument, previous: EaselDocument, moved: Set<UUID> = []) -> EaselDocument {
        carrying(next, previous: previous, moved: moved).document
    }

    static func carrying(_ next: EaselDocument, previous: EaselDocument,
                         moved: Set<UUID> = []) -> (document: EaselDocument, moved: Set<UUID>) {
        guard next.id == previous.id else { return (next, moved) }
        var before: [UUID: EaselItem] = [:]
        for item in previous.items where before[item.id] == nil { before[item.id] = item }
        var result = next
        var positions: [UUID: Int] = [:]
        for (index, item) in result.items.enumerated() where positions[item.id] == nil { positions[item.id] = index }
        for id in moved {
            guard let index = positions[id], let old = before[id] else { continue }
            let item = result.items[index]
            guard attaches(item), placementChanged(old, item), !(item.attachedTo.map(moved.contains) ?? false) else { continue }
            result.items[index].attachedTo = EaselDrawing.attachmentTarget(for: EaselDrawing.visualPoints(item),
                                                                           in: result.items, excluding: [id])
        }
        var frontier = Set(result.items.compactMap { item -> UUID? in
            guard let old = before[item.id], placementChanged(old, item) else { return nil }
            return item.id
        })
        var carried = Set<UUID>(), rounds = 0
        while !frontier.isEmpty && rounds < result.items.count {
            rounds += 1
            var reached = Set<UUID>()
            for index in result.items.indices {
                let item = result.items[index]
                guard let target = item.attachedTo, frontier.contains(target), !carried.contains(item.id), !moved.contains(item.id),
                      let old = before[item.id], !placementChanged(old, item),
                      let targetBefore = before[target], let targetIndex = positions[target],
                      let placed = transformed(item, from: targetBefore, to: result.items[targetIndex]) else { continue }
                result.items[index] = placed
                carried.insert(item.id)
                reached.insert(item.id)
            }
            frontier = reached
        }
        return (result, moved.union(carried))
    }

    static func dependents(of ids: Set<UUID>, in document: EaselDocument) -> Set<UUID> {
        var found = Set<UUID>(), frontier = ids
        while !frontier.isEmpty {
            let reached = Set(document.items.filter { item in
                guard let target = item.attachedTo else { return false }
                return frontier.contains(target) && !ids.contains(item.id) && !found.contains(item.id)
            }.map(\.id))
            found.formUnion(reached)
            frontier = reached
        }
        return found
    }

    static func placementChanged(_ old: EaselItem, _ new: EaselItem) -> Bool {
        old.frame != new.frame || old.points != new.points || old.resolvedRotation != new.resolvedRotation
            || (old.flipHorizontal == true) != (new.flipHorizontal == true) || (old.flipVertical == true) != (new.flipVertical == true)
    }

    static func transformed(_ item: EaselItem, from old: EaselItem, to new: EaselItem) -> EaselItem? {
        let of = old.frame, nf = new.frame
        guard [of.x, of.y, of.width, of.height, nf.x, nf.y, nf.width, nf.height].allSatisfy(\.isFinite) else { return nil }
        let oldCenter = EaselPoint(x: of.x + of.width / 2, y: of.y + of.height / 2)
        let newCenter = EaselPoint(x: nf.x + nf.width / 2, y: nf.y + nf.height / 2)
        let oldTurn = old.resolvedRotation * Double.pi / 180, newTurn = new.resolvedRotation * Double.pi / 180
        let scaleX = of.width > 0 ? nf.width / of.width : 1, scaleY = of.height > 0 ? nf.height / of.height : 1
        func map(_ point: EaselPoint) -> EaselPoint {
            let local = EaselDrawing.rotated(EaselPoint(x: point.x - oldCenter.x, y: point.y - oldCenter.y), by: -oldTurn)
            let placed = EaselDrawing.rotated(EaselPoint(x: local.x * scaleX, y: local.y * scaleY), by: newTurn)
            return EaselPoint(x: newCenter.x + placed.x, y: newCenter.y + placed.y)
        }
        var next = item
        if of.width == nf.width && of.height == nf.height && oldTurn == newTurn {
            next.frame.x += newCenter.x - oldCenter.x
            next.frame.y += newCenter.y - oldCenter.y
        } else if item.kind == .freehand {
            guard let placed = EaselDrawing.placing(EaselDrawing.visualPoints(item).map(map), like: item) else { return nil }
            next.frame = placed.frame
            next.points = placed.points
        } else {
            let f = item.frame, center = map(EaselPoint(x: f.x + f.width / 2, y: f.y + f.height / 2))
            next.frame.x = center.x - f.width / 2
            next.frame.y = center.y - f.height / 2
            let turn = new.resolvedRotation - old.resolvedRotation
            if abs(turn) > 1e-9 { next.rotation = normalizedDegrees(item.resolvedRotation + turn) }
        }
        let r = next.frame
        guard [r.x, r.y, r.width, r.height].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }), r.width >= 1, r.height >= 1 else { return nil }
        return next
    }

    static func normalizedDegrees(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 } else if value <= -180 { value += 360 }
        return value
    }
}
