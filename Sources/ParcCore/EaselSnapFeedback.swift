import Foundation

package enum EaselFeedbackSpring {
    package static let pop = EaselObjectSpring(response: 0.4, damping: 0.7)
    package static let settle = EaselObjectSpring(response: 0.34, damping: 0.86)
    package static let highlight = EaselObjectSpring(response: 0.15, damping: 0.825)
}

package struct EaselGuideSnapKey: Hashable {
    package let anchor: Int
    package let coordinate: Double

    package init(anchor: EaselAnchor, coordinate: Double) {
        self.anchor = anchor.rawValue
        self.coordinate = coordinate.isFinite ? (coordinate * 100).rounded() / 100 : 0
    }

    package init(_ line: EaselAlignmentGuides.Line) { self.init(anchor: line.anchor, coordinate: line.coordinate) }
}

package enum EaselFeedbackCurve {
    package static let guideFade: TimeInterval = 0.08
    package static let markPop: TimeInterval = 0.3
    package static let markFrom = 0.35
    package static let reveal: TimeInterval = 0.25
    package static let headPop: TimeInterval = 0.4
    package static let reducedFade: TimeInterval = 0.15
    package static let highlight: TimeInterval = 0.3
    package static let tray: TimeInterval = 0.1
    package static let flash: TimeInterval = 0.4
    package static let flashRise: TimeInterval = 0.06
    package static let page: TimeInterval = 0.22
    package static let pageSlide = 24.0
    package static let fold: TimeInterval = 0.2
    package static let unfoldStagger: TimeInterval = 0.035
    package static let unfoldSpread: TimeInterval = 0.16
    package static let grow: TimeInterval = 0.45
    package static let tableSlide: TimeInterval = 0.24

    package static func clamped(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 1 }

    package static func easeOut(_ t: Double) -> Double { let c = clamped(t); return 1 - pow(1 - c, 3) }

    package static func easeIn(_ t: Double) -> Double { let c = clamped(t); return c * c }

    package static func easeInOut(_ t: Double) -> Double {
        let c = clamped(t)
        return c < 0.5 ? 4 * c * c * c : 1 - pow(-2 * c + 2, 3) / 2
    }

    package static func guideOpacity(_ elapsed: Double) -> Double { easeOut(elapsed / guideFade) }

    package static func markScale(_ elapsed: Double, reduced: Bool) -> Double {
        guard !reduced, elapsed.isFinite else { return 1 }
        guard elapsed < markPop else { return 1 }
        return markFrom + (1 - markFrom) * EaselFeedbackSpring.pop.progress(at: max(0, elapsed))
    }

    package static func revealFraction(_ elapsed: Double, reduced: Bool) -> Double {
        reduced ? 1 : easeInOut(elapsed / reveal)
    }

    package static func revealOpacity(_ elapsed: Double, reduced: Bool) -> Double {
        reduced ? easeOut(elapsed / reducedFade) : easeOut(elapsed / 0.06)
    }

    package static func headScale(_ elapsed: Double, reduced: Bool) -> Double {
        guard !reduced, elapsed.isFinite else { return 1 }
        guard elapsed > 0 else { return 0 }
        guard elapsed < headPop else { return 1 }
        return max(0, EaselFeedbackSpring.pop.progress(at: elapsed))
    }

    package static func headOpacity(_ elapsed: Double, reduced: Bool) -> Double {
        reduced ? easeOut(elapsed / reducedFade) : easeOut(elapsed / 0.08)
    }

    package static func revealFinished(_ elapsed: Double, reduced: Bool, drawsLine: Bool) -> Bool {
        if reduced { return elapsed >= reducedFade }
        return elapsed >= (drawsLine ? reveal : 0) + headPop
    }

    package static func highlighted(_ elapsed: Double, from: Double, to: Double) -> Double {
        guard elapsed.isFinite, elapsed < highlight else { return to }
        return from + (to - from) * EaselFeedbackSpring.highlight.progress(at: max(0, elapsed))
    }

    package static func trayLevel(_ elapsed: Double, from: Double, rising: Bool) -> Double {
        let target = rising ? 1.0 : 0.0
        let t = easeOut(elapsed / tray)
        return from + (target - from) * t
    }

    package static func flashLevel(_ elapsed: Double) -> Double {
        guard elapsed.isFinite, elapsed >= 0, elapsed < flash else { return 0 }
        if elapsed < flashRise { return easeOut(elapsed / flashRise) }
        return 1 - easeOut((elapsed - flashRise) / (flash - flashRise))
    }

    package static func pageProgress(_ elapsed: Double) -> Double { easeOut(elapsed / page) }

    package static func foldPresentation(_ elapsed: Double, toward offset: EaselPoint, reduced: Bool) -> EaselObjectPresentation {
        let linear = clamped(elapsed / (reduced ? reducedFade : fold))
        var result = EaselObjectPresentation.identity
        result.opacity = 1 - easeOut(linear)
        guard !reduced else { return result }
        let travel = easeIn(linear) * 0.85 + linear * 0.15
        result.offset = EaselPoint(x: offset.x * travel, y: offset.y * travel)
        result.scale = 1 - 0.35 * easeIn(linear)
        return result
    }

    package static func unfoldDelays(depths: [Int]) -> [TimeInterval] {
        guard let deepest = depths.max(), let shallowest = depths.min(), deepest > shallowest else { return depths.map { _ in 0 } }
        let step = min(unfoldStagger, unfoldSpread / Double(deepest - shallowest))
        return depths.map { Double($0 - shallowest) * step }
    }

    package static func grownValue(_ elapsed: Double, from: Double, to: Double) -> Double {
        guard elapsed.isFinite, elapsed < grow else { return to }
        return from + (to - from) * EaselFeedbackSpring.settle.progress(at: max(0, elapsed))
    }

    package static func tableSlideProgress(_ elapsed: Double) -> Double {
        guard elapsed.isFinite, elapsed < tableSlide else { return 1 }
        return EaselFeedbackSpring.settle.progress(at: max(0, elapsed) * 0.45 / tableSlide)
    }
}

package enum EaselRotationSnap {
    package static func step(_ degrees: Double) -> Int? {
        guard degrees.isFinite else { return nil }
        let steps = Int((EaselRotation.normalized(degrees) / EaselRotation.dragStep).rounded())
        let count = Int((360 / EaselRotation.dragStep).rounded())
        return ((steps % count) + count) % count
    }
}

package enum EaselConnectorReveal {
    package static func length(of segment: EaselConnectorRoute.Segment) -> Double {
        let points = segment.samples
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for index in 1..<points.count {
            total += hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
        }
        return total
    }

    package static func length(of pieces: [[EaselConnectorRoute.Segment]]) -> Double {
        pieces.reduce(0) { sum, piece in piece.reduce(sum) { $0 + length(of: $1) } }
    }

    package static func parameter(_ segment: EaselConnectorRoute.Segment, at distance: Double) -> Double {
        let points = segment.samples
        guard points.count > 1, distance > 0 else { return 0 }
        var walked = 0.0
        for index in 1..<points.count {
            let step = hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
            if walked + step >= distance {
                let local = step > 0 ? (distance - walked) / step : 0
                return (Double(index - 1) + local) / Double(points.count - 1)
            }
            walked += step
        }
        return 1
    }

    package static func trimmed(_ pieces: [[EaselConnectorRoute.Segment]], fraction: Double) -> [[EaselConnectorRoute.Segment]] {
        let amount = EaselFeedbackCurve.clamped(fraction)
        guard amount < 1 else { return pieces }
        var budget = length(of: pieces) * amount
        var result: [[EaselConnectorRoute.Segment]] = []
        for piece in pieces {
            guard budget > 0 else { break }
            var kept: [EaselConnectorRoute.Segment] = []
            for segment in piece {
                guard budget > 0 else { break }
                let size = length(of: segment)
                if size <= budget { kept.append(segment); budget -= size; continue }
                kept.append(segment.portion(from: 0, to: parameter(segment, at: budget)))
                budget = 0
            }
            if !kept.isEmpty { result.append(kept) }
        }
        return result
    }

    package static func tip(_ pieces: [[EaselConnectorRoute.Segment]], fraction: Double) -> EaselPoint? {
        trimmed(pieces, fraction: fraction).last?.last?.end
    }
}

package enum EaselSectionDrop {
    package static func target(moving: [EaselItem], original: [EaselItem], in items: [EaselItem]) -> UUID? {
        let carried = moving.filter { $0.kind != .arrow }
        guard let bounds = EaselZoom.bounds(of: carried.map(\.frame)) else { return nil }
        let ids = Set(moving.map(\.id))
        let startBounds = EaselZoom.bounds(of: original.filter { $0.kind != .arrow }.map(\.frame))
        let hidden = EaselBoardObjects.hiddenIDs(in: items)
        let movingSections = moving.filter { $0.kind == .section }
        let candidates = items.filter { section in
            guard section.kind == .section, !ids.contains(section.id), !hidden.contains(section.id),
                  EaselBoardObjects.encloses(section.frame, bounds) else { return false }
            if let startBounds, EaselBoardObjects.encloses(section.frame, startBounds) { return false }
            return movingSections.allSatisfy { $0.frame.width * $0.frame.height < section.frame.width * section.frame.height }
        }
        return candidates.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?.id
    }
}

package struct EaselSizeMatch: Equatable, Hashable {
    package let other: UUID
    package let horizontal: Bool
    package init(other: UUID, horizontal: Bool) {
        self.other = other
        self.horizontal = horizontal
    }
}

package enum EaselEqualSize {
    package static let tolerance = 6.0
    package static let indicatorLimit = 3

    package static func resizes(_ kind: EaselItemKind) -> Bool {
        switch kind {
        case .rectangle, .circle, .section, .image, .video, .webCard, .link, .browser: return true
        default: return false
        }
    }

    package static func candidates(_ items: [EaselItem], excluding id: UUID, viewport: EaselRect) -> [EaselItem] {
        items.filter { item in
            item.id != id && resizes(item.kind) && !EaselRotation.isRotated(item)
                && EaselContentHitTest.intersects(item.frame, viewport) && item.frame.width > 0 && item.frame.height > 0
        }
    }

    package static func snap(_ item: EaselItem, handle: EaselResizeHandle, centered: Bool, candidates: [EaselItem], scale: Double,
                     lockedX: Bool, lockedY: Bool) -> (item: EaselItem, matches: [EaselSizeMatch]) {
        guard scale.isFinite, scale > 0 else { return (item, []) }
        var next = item
        func nearest(_ value: Double, _ size: (EaselItem) -> Double) -> Double? {
            let close = candidates.map(size).filter { abs($0 - value) * scale < tolerance && abs($0 - value) > 1e-9 }
            return close.min { abs($0 - value) < abs($1 - value) }
        }
        if !lockedX, handle.movesLeft || handle.movesRight, let width = nearest(next.frame.width, { $0.frame.width }) {
            let right = next.frame.x + next.frame.width, middle = next.frame.x + next.frame.width / 2
            if centered { next.frame.x = middle - width / 2 } else if handle.movesLeft { next.frame.x = right - width }
            next.frame.width = width
        }
        if !lockedY, handle.movesTop || handle.movesBottom, let height = nearest(next.frame.height, { $0.frame.height }) {
            let bottom = next.frame.y + next.frame.height, middle = next.frame.y + next.frame.height / 2
            if centered { next.frame.y = middle - height / 2 } else if handle.movesTop { next.frame.y = bottom - height }
            next.frame.height = height
        }
        guard next.frame.x >= 0, next.frame.y >= 0 else { return (item, matches(item, handle: handle, candidates: candidates)) }
        return (next, matches(next, handle: handle, candidates: candidates))
    }

    package static func matches(_ item: EaselItem, handle: EaselResizeHandle, candidates: [EaselItem]) -> [EaselSizeMatch] {
        func center(_ r: EaselRect) -> EaselPoint { EaselPoint(x: r.x + r.width / 2, y: r.y + r.height / 2) }
        let origin = center(item.frame)
        let ordered = candidates.sorted {
            let a = center($0.frame), b = center($1.frame)
            return hypot(a.x - origin.x, a.y - origin.y) < hypot(b.x - origin.x, b.y - origin.y)
        }
        var result: [EaselSizeMatch] = []
        if handle.movesLeft || handle.movesRight {
            result += ordered.filter { abs($0.frame.width - item.frame.width) < 1e-6 }.prefix(indicatorLimit).map { EaselSizeMatch(other: $0.id, horizontal: true) }
        }
        if handle.movesTop || handle.movesBottom {
            result += ordered.filter { abs($0.frame.height - item.frame.height) < 1e-6 }.prefix(indicatorLimit).map { EaselSizeMatch(other: $0.id, horizontal: false) }
        }
        return result
    }

    package static func lines(_ item: EaselItem, matches: [EaselSizeMatch], in items: [EaselItem], scale: Double) -> [EaselAlignmentGuides.Line] {
        let gap = 10 / max(scale, 0.05), tick = 4 / max(scale, 0.05)
        let lookup = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        func dimension(_ r: EaselRect, horizontal: Bool) -> [EaselAlignmentGuides.Segment] {
            if horizontal {
                let y = r.y - gap, a = r.x, b = r.x + r.width
                return [.init(start: .init(x: a, y: y), end: .init(x: b, y: y)),
                        .init(start: .init(x: a, y: y - tick), end: .init(x: a, y: y + tick)),
                        .init(start: .init(x: b, y: y - tick), end: .init(x: b, y: y + tick))]
            }
            let x = r.x - gap, a = r.y, b = r.y + r.height
            return [.init(start: .init(x: x, y: a), end: .init(x: x, y: b)),
                    .init(start: .init(x: x - tick, y: a), end: .init(x: x + tick, y: a)),
                    .init(start: .init(x: x - tick, y: b), end: .init(x: x + tick, y: b))]
        }
        return matches.compactMap { match in
            guard let other = lookup[match.other] else { return nil }
            let size = match.horizontal ? item.frame.width : item.frame.height
            return EaselAlignmentGuides.Line(anchor: match.horizontal ? .centerY : .centerX,
                                             coordinate: size + (match.horizontal ? other.frame.y : other.frame.x) * 1e-6,
                                             targetSegments: dimension(other.frame, horizontal: match.horizontal),
                                             anchorSegments: dimension(item.frame, horizontal: match.horizontal))
        }
    }
}
