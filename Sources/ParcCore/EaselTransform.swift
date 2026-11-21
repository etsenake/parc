import Foundation

package struct EaselTransform: Equatable {
    package var a = 1.0, b = 0.0, c = 0.0, d = 1.0, tx = 0.0, ty = 0.0
    package init(a: Double = 1.0, b: Double = 0.0, c: Double = 0.0, d: Double = 1.0, tx: Double = 0.0, ty: Double = 0.0) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    package static let identity = EaselTransform()

    package static func rotation(degrees: Double, around center: EaselPoint) -> EaselTransform {
        guard degrees.isFinite, degrees.truncatingRemainder(dividingBy: 360) != 0 else { return .identity }
        let quarter = degrees / 90, radians = degrees * .pi / 180
        let exact = abs(quarter) < 1_000_000 && quarter == quarter.rounded() ? Int(quarter.rounded()) % 4 : nil
        let cosine = exact.map { [1.0, 0, -1, 0][($0 + 4) % 4] } ?? cos(radians)
        let sine = exact.map { [0.0, 1, 0, -1][($0 + 4) % 4] } ?? sin(radians)
        return EaselTransform(a: cosine, b: sine, c: -sine, d: cosine,
                              tx: center.x - center.x * cosine + center.y * sine,
                              ty: center.y - center.x * sine - center.y * cosine)
    }

    package static func translation(x: Double, y: Double) -> EaselTransform { EaselTransform(tx: x, ty: y) }

    package var isIdentity: Bool { self == .identity }

    package func apply(_ point: EaselPoint) -> EaselPoint {
        EaselPoint(x: a * point.x + c * point.y + tx, y: b * point.x + d * point.y + ty)
    }

    package func applyVector(_ vector: EaselPoint) -> EaselPoint {
        EaselPoint(x: a * vector.x + c * vector.y, y: b * vector.x + d * vector.y)
    }

    package var inverted: EaselTransform? {
        let determinant = a * d - b * c
        guard determinant.isFinite, abs(determinant) > 1e-12 else { return nil }
        return EaselTransform(a: d / determinant, b: -b / determinant, c: -c / determinant, d: a / determinant,
                              tx: (c * ty - d * tx) / determinant, ty: (b * tx - a * ty) / determinant)
    }

    package static func mirror(horizontally: Bool, vertically: Bool, around center: EaselPoint) -> EaselTransform {
        guard horizontally || vertically else { return .identity }
        return EaselTransform(a: horizontally ? -1 : 1, b: 0, c: 0, d: vertically ? -1 : 1,
                              tx: horizontally ? 2 * center.x : 0, ty: vertically ? 2 * center.y : 0)
    }

    package func concatenating(_ next: EaselTransform) -> EaselTransform {
        EaselTransform(a: next.a * a + next.c * b, b: next.b * a + next.d * b,
                       c: next.a * c + next.c * d, d: next.b * c + next.d * d,
                       tx: next.a * tx + next.c * ty + next.tx, ty: next.b * tx + next.d * ty + next.ty)
    }

    package func bounds(of r: EaselRect) -> EaselRect {
        let corners = [EaselPoint(x: r.x, y: r.y), EaselPoint(x: r.x + r.width, y: r.y),
                       EaselPoint(x: r.x + r.width, y: r.y + r.height), EaselPoint(x: r.x, y: r.y + r.height)].map(apply)
        let xs = corners.map(\.x), ys = corners.map(\.y)
        let minX = xs.min() ?? r.x, minY = ys.min() ?? r.y
        return EaselRect(x: minX, y: minY, width: (xs.max() ?? minX) - minX, height: (ys.max() ?? minY) - minY)
    }
}

package enum EaselRotation {
    package static let dragStep = 15.0
    package static let keyStep = 1.0
    package static let largeKeyStep = 15.0

    package static func isRotatable(_ kind: EaselItemKind) -> Bool {
        switch kind {
        case .text, .image, .rectangle, .circle, .freehand, .stamp, .equation: return true
        default: return false
        }
    }

    package static func isFlippable(_ kind: EaselItemKind) -> Bool {
        switch kind {
        case .image, .rectangle, .circle, .freehand, .stamp: return true
        default: return false
        }
    }

    package static func canRotate(_ item: EaselItem) -> Bool { isRotatable(item.kind) && !item.isLocked }
    package static func canFlip(_ item: EaselItem) -> Bool { isFlippable(item.kind) && !item.isLocked }
    package static func canRotate(_ items: [EaselItem]) -> Bool { items.contains(where: canRotate) }
    package static func canFlip(_ items: [EaselItem]) -> Bool { items.contains(where: canFlip) }

    package static func normalized(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 } else if value <= -180 { value += 360 }
        return abs(value) < 1e-9 ? 0 : value
    }

    package static func stored(_ degrees: Double) -> Double? {
        let value = normalized((normalized(degrees) * 100).rounded() / 100)
        return value == 0 ? nil : value
    }

    package static func snapped(_ degrees: Double, step: Double = dragStep) -> Double {
        guard degrees.isFinite, step > 0 else { return 0 }
        return (degrees / step).rounded() * step
    }

    package static func degrees(of item: EaselItem) -> Double { isRotatable(item.kind) ? normalized(item.rotation ?? 0) : 0 }
    package static func mirrorsHorizontally(_ item: EaselItem) -> Bool { isFlippable(item.kind) && item.flipHorizontal == true }
    package static func mirrorsVertically(_ item: EaselItem) -> Bool { isFlippable(item.kind) && item.flipVertical == true }
    package static func isRotated(_ item: EaselItem) -> Bool { degrees(of: item) != 0 }

    package static func isTransformed(_ item: EaselItem) -> Bool {
        isRotated(item) || mirrorsHorizontally(item) || mirrorsVertically(item)
    }

    package static func center(of r: EaselRect) -> EaselPoint { EaselPoint(x: r.x + r.width / 2, y: r.y + r.height / 2) }

    package static func transform(for item: EaselItem) -> EaselTransform {
        let middle = center(of: item.frame)
        return EaselTransform.mirror(horizontally: mirrorsHorizontally(item), vertically: mirrorsVertically(item), around: middle)
            .concatenating(.rotation(degrees: degrees(of: item), around: middle))
    }

    package static func readableTransform(for item: EaselItem, in rect: EaselRect) -> EaselTransform {
        .mirror(horizontally: mirrorsHorizontally(item), vertically: mirrorsVertically(item), around: center(of: rect))
    }

    package static func canvasPoint(_ point: EaselPoint, in item: EaselItem) -> EaselPoint { transform(for: item).apply(point) }

    package static func localPoint(_ point: EaselPoint, in item: EaselItem) -> EaselPoint {
        let forward = transform(for: item)
        guard !forward.isIdentity, let inverse = forward.inverted else { return point }
        return inverse.apply(point)
    }

    package static func corners(of r: EaselRect) -> [EaselPoint] {
        [EaselPoint(x: r.x, y: r.y), EaselPoint(x: r.x + r.width, y: r.y),
         EaselPoint(x: r.x + r.width, y: r.y + r.height), EaselPoint(x: r.x, y: r.y + r.height)]
    }

    package static func polygon(of item: EaselItem) -> [EaselPoint] {
        let forward = transform(for: item)
        return corners(of: item.frame).map(forward.apply)
    }

    package static func bounds(of item: EaselItem) -> EaselRect {
        let angle = degrees(of: item)
        guard angle != 0 else { return item.frame }
        return EaselTransform.rotation(degrees: angle, around: center(of: item.frame)).bounds(of: item.frame)
    }

    package static func bounds(of items: [EaselItem]) -> EaselRect? {
        guard let first = items.first else { return nil }
        let start = bounds(of: first)
        var left = start.x, top = start.y, right = start.x + start.width, bottom = start.y + start.height
        for item in items.dropFirst() {
            let box = bounds(of: item)
            left = min(left, box.x); top = min(top, box.y)
            right = max(right, box.x + box.width); bottom = max(bottom, box.y + box.height)
        }
        return EaselRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    package static func upright(_ item: EaselItem) -> EaselItem {
        var next = item
        next.rotation = nil; next.flipHorizontal = nil; next.flipVertical = nil
        return next
    }

    package static func uprightHit(_ point: EaselPoint, item: EaselItem) -> (point: EaselPoint, item: EaselItem)? {
        guard isTransformed(item), let inverse = transform(for: item).inverted else { return nil }
        return (inverse.apply(point), upright(item))
    }

    package static func intersects(_ rect: EaselRect, item: EaselItem, selected: Bool) -> Bool? {
        guard isTransformed(item), let inverse = transform(for: item).inverted else { return nil }
        guard rect.width > 0, rect.height > 0 else { return false }
        let area = corners(of: rect).map(inverse.apply), r = item.frame
        if selected { return polygonsOverlap(area, corners(of: r)) }
        switch item.kind {
        case .freehand: return item.points.contains { contains(EaselPoint(x: r.x + $0.x, y: r.y + $0.y), polygon: area) }
        case .circle: return ellipse(r, overlaps: area)
        default: return polygonsOverlap(area, corners(of: r))
        }
    }

    package static func contains(_ point: EaselPoint, polygon: [EaselPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false, previous = polygon[polygon.count - 1]
        for current in polygon {
            if (current.y > point.y) != (previous.y > point.y) {
                let crossing = (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x
                if point.x < crossing { inside.toggle() }
            }
            previous = current
        }
        return inside
    }

    package static func polygonsOverlap(_ first: [EaselPoint], _ second: [EaselPoint]) -> Bool {
        guard first.count >= 3, second.count >= 3 else { return false }
        for polygon in [first, second] {
            for index in polygon.indices {
                let p = polygon[index], q = polygon[(index + 1) % polygon.count]
                let axis = EaselPoint(x: q.y - p.y, y: p.x - q.x)
                guard axis.x != 0 || axis.y != 0 else { continue }
                let one = first.map { $0.x * axis.x + $0.y * axis.y }, two = second.map { $0.x * axis.x + $0.y * axis.y }
                guard let oneLow = one.min(), let oneHigh = one.max(), let twoLow = two.min(), let twoHigh = two.max() else { return false }
                if oneHigh <= twoLow || twoHigh <= oneLow { return false }
            }
        }
        return true
    }

    package static func ellipse(_ r: EaselRect, overlaps polygon: [EaselPoint]) -> Bool {
        guard r.width > 0, r.height > 0, polygon.count >= 3 else { return false }
        let middle = center(of: r)
        let unit = polygon.map { EaselPoint(x: ($0.x - middle.x) / (r.width / 2), y: ($0.y - middle.y) / (r.height / 2)) }
        let origin = EaselPoint(x: 0, y: 0)
        if contains(origin, polygon: unit) { return true }
        return unit.indices.contains { index in
            distance(origin, from: unit[index], to: unit[(index + 1) % unit.count]) <= 1
        }
    }

    package static func distance(_ p: EaselPoint, from a: EaselPoint, to b: EaselPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy
        let t = length > 0 ? min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length)) : 0
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }

    package static func angle(of point: EaselPoint, around center: EaselPoint) -> Double? {
        let dx = point.x - center.x, dy = point.y - center.y
        guard dx.isFinite, dy.isFinite, hypot(dx, dy) > 1e-6 else { return nil }
        return atan2(dy, dx) * 180 / .pi
    }

    package static func recentred(_ item: EaselItem, frame next: EaselRect) -> EaselRect {
        let original = center(of: item.frame), proposed = center(of: next)
        let shift = transform(for: item).applyVector(EaselPoint(x: proposed.x - original.x, y: proposed.y - original.y))
        return EaselRect(x: original.x + shift.x - next.width / 2, y: original.y + shift.y - next.height / 2,
                         width: next.width, height: next.height)
    }

    package static func localFrame(_ item: EaselItem, from placed: EaselRect) -> EaselRect {
        guard let inverse = transform(for: item).inverted else { return placed }
        let original = center(of: item.frame), middle = center(of: placed)
        let shift = inverse.applyVector(EaselPoint(x: middle.x - original.x, y: middle.y - original.y))
        return EaselRect(x: original.x + shift.x - placed.width / 2, y: original.y + shift.y - placed.height / 2,
                         width: placed.width, height: placed.height)
    }

    package static func scaledSize(_ item: EaselItem, scaleX: Double, scaleY: Double) -> (width: Double, height: Double) {
        let radians = degrees(of: item) * .pi / 180, cosine = cos(radians), sine = sin(radians)
        return (item.frame.width * hypot(scaleX * cosine, scaleY * sine),
                item.frame.height * hypot(scaleX * sine, scaleY * cosine))
    }

    package static func mirrored(_ item: EaselItem, horizontally: Bool, across pivot: EaselPoint, moves: Bool) -> EaselItem {
        var next = item
        if moves {
            let middle = center(of: item.frame)
            let target = horizontally ? EaselPoint(x: 2 * pivot.x - middle.x, y: middle.y) : EaselPoint(x: middle.x, y: 2 * pivot.y - middle.y)
            next.frame.x = target.x - item.frame.width / 2; next.frame.y = target.y - item.frame.height / 2
        }
        if isRotatable(item.kind) { next.rotation = stored(-degrees(of: item)) }
        if isFlippable(item.kind) {
            if horizontally { next.flipHorizontal = item.flipHorizontal == true ? nil : true }
            else { next.flipVertical = item.flipVertical == true ? nil : true }
        }
        return next
    }

    package static func flipped(_ items: [EaselItem], horizontally: Bool) -> [EaselItem]? {
        guard canFlip(items), let box = bounds(of: items) else { return nil }
        let pivot = center(of: box), moves = items.count > 1
        return items.map { item in
            if canFlip(item) || (moves && item.kind == .text && !item.isLocked) {
                return mirrored(item, horizontally: horizontally, across: pivot, moves: moves)
            }
            if moves, item.kind == .arrow, !item.isLocked {
                return reshaped(item) { point in
                    horizontally ? EaselPoint(x: 2 * pivot.x - point.x, y: point.y) : EaselPoint(x: point.x, y: 2 * pivot.y - point.y)
                }
            }
            return item
        }
    }

    package static func rotated(_ items: [EaselItem], by delta: Double, around pivot: EaselPoint) -> [EaselItem]? {
        guard delta.isFinite, canRotate(items) else { return nil }
        let turn = EaselTransform.rotation(degrees: delta, around: pivot), moves = items.count > 1
        return items.map { item in
            if canRotate(item) {
                var next = item
                if moves {
                    let middle = turn.apply(center(of: item.frame))
                    next.frame.x = middle.x - item.frame.width / 2; next.frame.y = middle.y - item.frame.height / 2
                }
                next.rotation = stored(degrees(of: item) + delta)
                return next
            }
            if moves, item.kind == .arrow, !item.isLocked { return reshaped(item, turn.apply) }
            return item
        }
    }

    package static func reshaped(_ item: EaselItem, _ map: (EaselPoint) -> EaselPoint) -> EaselItem {
        guard !item.points.isEmpty else { return item }
        var next = item
        let absolute = item.points.map { map(EaselPoint(x: item.frame.x + $0.x, y: item.frame.y + $0.y)) }
        let minX = absolute.map(\.x).min() ?? 0, minY = absolute.map(\.y).min() ?? 0
        let maxX = absolute.map(\.x).max() ?? minX, maxY = absolute.map(\.y).max() ?? minY
        next.frame = EaselRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
        next.points = absolute.map { EaselPoint(x: $0.x - minX, y: $0.y - minY) }
        next.waypoints = item.waypoints.map { $0.map(map) }
        return next
    }

    package static func turnLabel(_ degrees: Double) -> String {
        let value = normalized(degrees), whole = value.rounded()
        let text = abs(value - whole) < 0.05 ? String(Int(whole)) : String(format: "%.1f", value)
        return text.replacingOccurrences(of: "-", with: "\u{2212}") + "°"
    }
}

package struct EaselRotationDrag: Equatable {
    package let pivot: EaselPoint
    package let startAngle: Double
    package let baseRotation: Double?

    package init?(items: [EaselItem], pointer: EaselPoint) {
        guard EaselRotation.canRotate(items), let box = EaselRotation.bounds(of: items) else { return nil }
        let single = items.count == 1 ? items.first : nil
        let pivot = single.map { EaselRotation.center(of: $0.frame) } ?? EaselRotation.center(of: box)
        guard let angle = EaselRotation.angle(of: pointer, around: pivot) else { return nil }
        self.pivot = pivot; startAngle = angle
        baseRotation = single.map(EaselRotation.degrees(of:))
    }

    package func delta(to pointer: EaselPoint, free: Bool) -> Double? {
        guard let angle = EaselRotation.angle(of: pointer, around: pivot) else { return nil }
        let raw = EaselRotation.normalized(angle - startAngle)
        guard !free else { return raw }
        if let baseRotation { return EaselRotation.snapped(baseRotation + raw) - baseRotation }
        return EaselRotation.snapped(raw)
    }
}

package struct EaselSelectionChrome: Equatable {
    package let frame: EaselRect
    package let transform: EaselTransform

    package init(frame: EaselRect, items: [EaselItem]) {
        if items.count == 1, let item = items.first, EaselRotation.isRotated(item) {
            self.frame = item.frame; transform = EaselRotation.transform(for: item)
        } else {
            self.frame = frame; transform = .identity
        }
    }

    package var isTurned: Bool { !transform.isIdentity }
    package var corners: [EaselPoint] { EaselRotation.corners(of: frame).map(transform.apply) }
    package var center: EaselPoint { transform.apply(EaselRotation.center(of: frame)) }

    package func point(_ handle: EaselResizeHandle) -> EaselPoint { transform.apply(handle.point(in: frame)) }
    package func local(_ point: EaselPoint) -> EaselPoint { transform.inverted?.apply(point) ?? point }

    package func handle(at point: EaselPoint, scale: Double, where shows: (EaselResizeHandle) -> Bool) -> EaselResizeHandle? {
        let inside = local(point)
        return EaselResizeHandle.allCases.first { handle in
            guard shows(handle), let r = handle.hitRect(in: frame, scale: scale) else { return false }
            return EaselContentHitTest.contains(inside, rect: r)
        }
    }

    package func outward(_ handle: EaselResizeHandle) -> EaselPoint {
        let x = handle.movesLeft ? -1.0 : handle.movesRight ? 1 : 0, y = handle.movesTop ? -1.0 : handle.movesBottom ? 1 : 0
        let vector = transform.applyVector(EaselPoint(x: x, y: y)), length = hypot(vector.x, vector.y)
        return length > 0 ? EaselPoint(x: vector.x / length, y: vector.y / length) : EaselPoint(x: 0, y: -1)
    }

    package func rotateZones(scale: Double) -> [(corner: EaselResizeHandle, rect: EaselRect)] {
        guard scale.isFinite, scale > 0 else { return [] }
        let offset = 19 / scale, half = 9 / scale
        return EaselResizeHandle.allCases.filter(\.isCorner).map { corner in
            let tip = point(corner), direction = outward(corner)
            let middle = EaselPoint(x: tip.x + direction.x * offset, y: tip.y + direction.y * offset)
            return (corner, EaselRect(x: middle.x - half, y: middle.y - half, width: 2 * half, height: 2 * half))
        }
    }

    package func rotateZone(at point: EaselPoint, scale: Double) -> EaselResizeHandle? {
        rotateZones(scale: scale).first { EaselContentHitTest.contains(point, rect: $0.rect) }?.corner
    }
}
