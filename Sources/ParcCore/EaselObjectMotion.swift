import Foundation

package struct EaselObjectPresentation: Equatable {
    package var opacity: Double
    package var scale: Double
    package var offset: EaselPoint

    package static let identity = EaselObjectPresentation(opacity: 1, scale: 1, offset: EaselPoint(x: 0, y: 0))
    package var isIdentity: Bool { self == .identity }

    package init(opacity: Double, scale: Double, offset: EaselPoint) {
        self.opacity = opacity
        self.scale = scale
        self.offset = offset
    }
}

package enum EaselObjectEffect: Equatable {
    case appear
    case vanish
    case glide(from: EaselPoint, fades: Bool)
    case lift(from: Double)
}

package struct EaselObjectSpring: Equatable {
    package let response: Double
    package let damping: Double

    package init(response: Double, damping: Double) {
        self.response = response
        self.damping = damping
    }

    package static let glide = EaselObjectSpring(response: 0.34, damping: 0.86)
    package static let hover = EaselObjectSpring(response: 0.15, damping: 0.825)

    package func progress(at time: Double) -> Double {
        guard time > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        if damping < 1 {
            let damped = omega * (1 - damping * damping).squareRoot()
            let envelope = exp(-damping * omega * time)
            return 1 - envelope * (cos(damped * time) + damping * omega / damped * sin(damped * time))
        }
        return 1 - exp(-omega * time) * (1 + omega * time)
    }
}

package struct EaselObjectTransition: Equatable {
    package static let appearDuration: TimeInterval = 0.2
    package static let appearFade: TimeInterval = 0.12
    package static let vanishDuration: TimeInterval = 0.15
    package static let glideDuration: TimeInterval = 0.45
    package static let liftDuration: TimeInterval = 0.2
    package static let reducedFade: TimeInterval = 0.15
    package static let hiddenScale = 0.95
    package static let vanishScale = 0.97

    package let effect: EaselObjectEffect
    package let start: TimeInterval
    package let reduced: Bool

    package init(effect: EaselObjectEffect, start: TimeInterval, reduced: Bool) {
        self.effect = effect
        self.start = start
        self.reduced = reduced
    }

    package var duration: TimeInterval {
        if reduced {
            if case .lift = effect { return 0 }
            return Self.reducedFade
        }
        switch effect {
        case .appear: return Self.appearDuration
        case .vanish: return Self.vanishDuration
        case .glide: return Self.glideDuration
        case .lift: return Self.liftDuration
        }
    }

    package func finished(at time: TimeInterval) -> Bool { time - start >= duration }

    package static func easeOut(_ t: Double) -> Double {
        let clamped = min(1, max(0, t))
        return 1 - pow(1 - clamped, 3)
    }

    package static func easeIn(_ t: Double) -> Double {
        let clamped = min(1, max(0, t))
        return clamped * clamped
    }

    package func presentation(at time: TimeInterval) -> EaselObjectPresentation {
        let elapsed = max(0, time - start)
        guard elapsed < duration, time.isFinite else {
            if case .vanish = effect { return EaselObjectPresentation(opacity: 0, scale: 1, offset: EaselPoint(x: 0, y: 0)) }
            return .identity
        }
        let linear = elapsed / duration
        var result = EaselObjectPresentation.identity
        if reduced {
            switch effect {
            case .appear: result.opacity = Self.easeOut(linear)
            case .vanish: result.opacity = 1 - Self.easeOut(linear)
            case .glide(_, let fades): result.opacity = fades ? Self.easeOut(linear) : 0.4 + 0.6 * Self.easeOut(linear)
            case .lift: break
            }
            return result
        }
        switch effect {
        case .appear:
            result.opacity = Self.easeOut(elapsed / Self.appearFade)
            result.scale = Self.hiddenScale + (1 - Self.hiddenScale) * Self.easeOut(linear)
        case .vanish:
            result.opacity = 1 - Self.easeOut(linear)
            result.scale = 1 - (1 - Self.vanishScale) * Self.easeIn(linear)
        case .glide(let from, _):
            let remaining = 1 - EaselObjectSpring.glide.progress(at: elapsed)
            result.offset = EaselPoint(x: from.x * remaining, y: from.y * remaining)
        case .lift(let from):
            result.scale = from + (1 - from) * Self.easeOut(linear)
        }
        return result
    }
}

package struct EaselObjectMotion {
    package private(set) var transitions: [UUID: EaselObjectTransition] = [:]
    package private(set) var ghosts: [EaselItem] = []

    package var isEmpty: Bool { transitions.isEmpty }
    package var ids: Set<UUID> { Set(transitions.keys) }

    package init(transitions: [UUID: EaselObjectTransition] = [:], ghosts: [EaselItem] = []) {
        self.transitions = transitions
        self.ghosts = ghosts
    }

    package mutating func appear(_ ids: some Sequence<UUID>, at time: TimeInterval, reduced: Bool) {
        for id in ids { transitions[id] = EaselObjectTransition(effect: .appear, start: time, reduced: reduced) }
    }

    package mutating func vanish(_ items: [EaselItem], at time: TimeInterval, reduced: Bool) {
        let leaving = Set(items.map(\.id))
        ghosts.removeAll { leaving.contains($0.id) }
        for item in items {
            ghosts.append(item)
            transitions[item.id] = EaselObjectTransition(effect: .vanish, start: time, reduced: reduced)
        }
    }

    package mutating func glide(_ offsets: [UUID: EaselPoint], fades: Bool, at time: TimeInterval, reduced: Bool) {
        for (id, offset) in offsets where offset.x.isFinite && offset.y.isFinite && (abs(offset.x) > 0.5 || abs(offset.y) > 0.5) {
            var start = offset
            if let current = transitions[id], case .glide = current.effect, !current.reduced, !reduced {
                let shown = current.presentation(at: time).offset
                start = EaselPoint(x: offset.x + shown.x, y: offset.y + shown.y)
            }
            transitions[id] = EaselObjectTransition(effect: .glide(from: start, fades: fades), start: time, reduced: reduced)
        }
    }

    package mutating func lift(_ ids: some Sequence<UUID>, from scale: Double, at time: TimeInterval, reduced: Bool) {
        guard !reduced, scale.isFinite, scale > 0 else { return }
        for id in ids { transitions[id] = EaselObjectTransition(effect: .lift(from: scale), start: time, reduced: reduced) }
    }

    package func presentation(for id: UUID, at time: TimeInterval) -> EaselObjectPresentation {
        transitions[id]?.presentation(at: time) ?? .identity
    }

    package func transition(for id: UUID) -> EaselObjectTransition? { transitions[id] }

    @discardableResult
    package mutating func prune(at time: TimeInterval) -> Set<UUID> {
        let done = Set(transitions.filter { $0.value.finished(at: time) }.map(\.key))
        guard !done.isEmpty else { return [] }
        for id in done { transitions.removeValue(forKey: id) }
        ghosts.removeAll { done.contains($0.id) }
        return done
    }

    package mutating func forget(missing present: Set<UUID>) {
        let ghostIDs = Set(ghosts.map(\.id))
        for id in Array(transitions.keys) where !present.contains(id) && !ghostIDs.contains(id) {
            transitions.removeValue(forKey: id)
        }
        let reborn = ghostIDs.intersection(present)
        guard !reborn.isEmpty else { return }
        ghosts.removeAll { reborn.contains($0.id) }
        for id in reborn { transitions.removeValue(forKey: id) }
    }

    package mutating func cancelAll() {
        transitions.removeAll()
        ghosts.removeAll()
    }

    package static func glides(_ item: EaselItem) -> Bool {
        item.kind != .arrow || (item.startConnection == nil && item.endConnection == nil)
    }

    package static func moves(from before: EaselDocument, to after: EaselDocument, among ids: Set<UUID>? = nil) -> [UUID: EaselPoint] {
        var previous: [UUID: EaselRect] = [:]
        for item in before.items { previous[item.id] = item.frame }
        var result: [UUID: EaselPoint] = [:]
        for item in after.items where ids?.contains(item.id) ?? true {
            guard glides(item), let old = previous[item.id] else { continue }
            let dx = old.x - item.frame.x, dy = old.y - item.frame.y
            if abs(dx) > 0.5 || abs(dy) > 0.5 { result[item.id] = EaselPoint(x: dx, y: dy) }
        }
        return result
    }

    package static func copyOffsets(sources: [UUID], copies: [UUID], before: EaselDocument, after: EaselDocument) -> [UUID: EaselPoint] {
        var frames: [UUID: EaselRect] = [:]
        for item in before.items { frames[item.id] = item.frame }
        var placed: [UUID: EaselItem] = [:]
        for item in after.items { placed[item.id] = item }
        var result: [UUID: EaselPoint] = [:]
        for (source, copy) in zip(sources, copies) {
            guard let from = frames[source], let item = placed[copy], glides(item) else { continue }
            result[copy] = EaselPoint(x: from.x - item.frame.x, y: from.y - item.frame.y)
        }
        return result
    }

    package static func added(from before: EaselDocument, to after: EaselDocument) -> [UUID] {
        let old = Set(before.items.map(\.id))
        return after.items.filter { !old.contains($0.id) }.map(\.id)
    }

    package static func removed(from before: EaselDocument, to after: EaselDocument) -> [EaselItem] {
        let remaining = Set(after.items.map(\.id))
        return before.items.filter { !remaining.contains($0.id) }
    }
}
