import Foundation

struct EaselObjectPresentation: Equatable {
    var opacity: Double
    var scale: Double
    var offset: EaselPoint
    var rotation: Double = 0
    var shadow: Double = 0
    var stretch = EaselPoint(x: 1, y: 1)

    static let identity = EaselObjectPresentation(opacity: 1, scale: 1, offset: EaselPoint(x: 0, y: 0))
    var isIdentity: Bool { self == .identity }
    var scaleX: Double { scale * stretch.x }
    var scaleY: Double { scale * stretch.y }
    var transforms: Bool { scaleX != 1 || scaleY != 1 || rotation != 0 || offset.x != 0 || offset.y != 0 }
}

enum EaselObjectEntrance: Equatable {
    case pop
    case drop(tilt: Double)
    case slam(tilt: Double, raised: Bool)
    case quick
    case fade

    static let dropTilt = 3.0
    static let slamTilt = 12.0
    static let pressedSlamTilt = 4.0

    static func of(_ item: EaselItem) -> EaselObjectEntrance {
        let side: Double = item.id.uuid.0 & 1 == 0 ? 1 : -1
        switch item.kind {
        case .sticky: return .drop(tilt: dropTilt * side)
        case .stamp: return .slam(tilt: slamTilt * side, raised: false)
        case .arrow, .freehand, .section: return .fade
        default: return .pop
        }
    }

    static func returning(_ item: EaselItem) -> EaselObjectEntrance { item.kind == .arrow ? .fade : .quick }

    static func cascades(_ item: EaselItem) -> Bool { item.kind != .arrow }
}

enum EaselObjectEffect: Equatable {
    case appear(EaselObjectEntrance)
    case vanish
    case glide(from: EaselPoint, fades: Bool, stretch: EaselPoint, turn: Double, lands: Bool)
    case lift(from: Double)
    case land(scale: Double, rotation: Double, shadow: Double)
    case pulse
    case shake
    case restyle
}

struct EaselObjectSpring: Equatable {
    let response: Double
    let damping: Double

    static let pop = EaselObjectSpring(response: 0.4, damping: 0.7)
    static let press = EaselObjectSpring(response: 0.3, damping: 0.6)
    static let toggle = EaselObjectSpring(response: 0.2, damping: 0.5)
    static let settle = EaselObjectSpring(response: 0.34, damping: 0.86)
    static let lift = EaselObjectSpring(response: 0.3, damping: 0.95)
    static let highlight = EaselObjectSpring(response: 0.15, damping: 0.825)
    static let glide = settle
    static let hover = highlight

    var omega: Double { 2 * Double.pi / response }

    func progress(at time: Double) -> Double {
        guard time > 0 else { return 0 }
        if damping < 1 {
            let damped = omega * (1 - damping * damping).squareRoot()
            let envelope = exp(-damping * omega * time)
            return 1 - envelope * (cos(damped * time) + damping * omega / damped * sin(damped * time))
        }
        return 1 - exp(-omega * time) * (1 + omega * time)
    }
}

struct EaselObjectTransition: Equatable {
    static let appearDuration: TimeInterval = 0.42
    static let appearFade: TimeInterval = 0.12
    static let slamDuration: TimeInterval = 0.36
    static let slamFade: TimeInterval = 0.08
    static let quickDuration: TimeInterval = 0.24
    static let vanishDuration: TimeInterval = 0.18
    static let glideDuration: TimeInterval = 0.45
    static let liftDuration: TimeInterval = 0.2
    static let landDuration: TimeInterval = 0.42
    static let pulseDuration: TimeInterval = 0.5
    static let pulseRise: TimeInterval = 0.09
    static let shakeDuration: TimeInterval = 0.3
    static let restyleDuration: TimeInterval = 0.15
    static let reducedFade: TimeInterval = 0.15
    static let hiddenScale = 0.8
    static let quickScale = 0.92
    static let dropScale = 1.08
    static let dropRise = 8.0
    static let slamScale = 1.6
    static let raisedScale = 1.15
    static let raisedOpacity = 0.8
    static let raisedShadow = 0.8
    static let breathDepth = 0.015
    static let breathPeriod = 1.1
    static let vanishScale = 0.85
    static let pulseScale = 1.05
    static let shakeDistance = 4.0
    static let shakeSwings = 3.0
    static let landingSquash = 0.025
    static let copySquash = 0.03

    let effect: EaselObjectEffect
    let start: TimeInterval
    let reduced: Bool

    var duration: TimeInterval {
        if reduced {
            switch effect {
            case .lift, .land, .pulse, .shake: return 0
            default: return Self.reducedFade
            }
        }
        switch effect {
        case .appear(let entrance):
            switch entrance {
            case .pop, .drop: return Self.appearDuration
            case .slam: return Self.slamDuration
            case .quick: return Self.quickDuration
            case .fade: return Self.reducedFade
            }
        case .vanish: return Self.vanishDuration
        case .glide: return Self.glideDuration
        case .lift: return Self.liftDuration
        case .land: return Self.landDuration
        case .pulse: return Self.pulseDuration
        case .shake: return Self.shakeDuration
        case .restyle: return Self.restyleDuration
        }
    }

    func finished(at time: TimeInterval) -> Bool { time - start >= duration }

    static func easeOut(_ t: Double) -> Double {
        let clamped = min(1, max(0, t))
        return 1 - pow(1 - clamped, 3)
    }

    static func easeIn(_ t: Double) -> Double {
        let clamped = min(1, max(0, t))
        return clamped * clamped
    }

    static func easeInOut(_ t: Double) -> Double {
        let clamped = min(1, max(0, t))
        return clamped * clamped * (3 - 2 * clamped)
    }

    static func squash(at elapsed: Double, from start: Double, length: Double, amount: Double) -> Double {
        let u = (elapsed - start) / length
        guard u > 0, u < 1 else { return 0 }
        return amount * sin(Double.pi * u) * (1 - 0.35 * u)
    }

    static func squashed(_ stretch: EaselPoint, by amount: Double) -> EaselPoint {
        EaselPoint(x: stretch.x * (1 + amount), y: stretch.y * (1 - amount))
    }

    func presentation(at time: TimeInterval) -> EaselObjectPresentation {
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
            case .glide(_, let fades, _, _, _): result.opacity = fades ? Self.easeOut(linear) : 0.4 + 0.6 * Self.easeOut(linear)
            case .restyle: result.opacity = Self.easeInOut(linear)
            case .lift, .land, .pulse, .shake: break
            }
            return result
        }
        switch effect {
        case .appear(let entrance):
            switch entrance {
            case .pop:
                result.opacity = Self.easeOut(elapsed / Self.appearFade)
                result.scale = Self.hiddenScale + (1 - Self.hiddenScale) * EaselObjectSpring.pop.progress(at: elapsed)
            case .drop(let tilt):
                let settled = EaselObjectSpring.settle.progress(at: elapsed)
                result.opacity = Self.easeOut(elapsed / 0.1)
                result.scale = Self.dropScale + (1 - Self.dropScale) * settled
                result.offset = EaselPoint(x: 0, y: -Self.dropRise * (1 - settled))
                result.rotation = tilt * (1 - settled)
                result.shadow = max(0, 1 - settled)
                result.stretch = Self.squashed(result.stretch, by: Self.squash(at: elapsed, from: 0.12, length: 0.22, amount: Self.landingSquash))
            case .slam(let tilt, let raised):
                let settled = EaselObjectSpring.toggle.progress(at: elapsed)
                let from = raised ? Self.raisedScale : Self.slamScale
                let lifted = raised ? Self.raisedOpacity : 0
                result.opacity = lifted + (1 - lifted) * Self.easeOut(elapsed / Self.slamFade)
                result.scale = from + (1 - from) * settled
                result.rotation = tilt * (1 - settled)
                result.shadow = max(0, 1 - settled) * (raised ? Self.raisedShadow : 0.6)
            case .quick:
                result.opacity = Self.easeOut(elapsed / 0.1)
                result.scale = Self.quickScale + (1 - Self.quickScale) * EaselObjectSpring.settle.progress(at: elapsed)
            case .fade:
                result.opacity = Self.easeOut(linear)
            }
        case .vanish:
            result.opacity = 1 - Self.easeOut(linear)
            result.scale = 1 - (1 - Self.vanishScale) * Self.easeOut(linear)
        case .glide(let from, _, let stretch, let turn, let lands):
            let remaining = 1 - EaselObjectSpring.glide.progress(at: elapsed)
            result.offset = EaselPoint(x: from.x * remaining, y: from.y * remaining)
            result.stretch = EaselPoint(x: 1 + (stretch.x - 1) * remaining, y: 1 + (stretch.y - 1) * remaining)
            result.rotation = turn * remaining
            if lands {
                result.stretch = Self.squashed(result.stretch, by: Self.squash(at: elapsed, from: 0.16, length: 0.24, amount: Self.copySquash))
            }
        case .lift(let from):
            result.scale = from + (1 - from) * Self.easeOut(linear)
        case .land(let scale, let rotation, let shadow):
            let settled = EaselObjectSpring.settle.progress(at: elapsed)
            result.scale = scale + (1 - scale) * settled
            result.rotation = rotation * (1 - settled)
            result.shadow = shadow * (1 - Self.easeOut(elapsed / 0.25))
            result.stretch = Self.squashed(result.stretch, by: Self.squash(at: elapsed, from: 0.04, length: 0.26, amount: Self.landingSquash))
        case .pulse:
            let swell = elapsed < Self.pulseRise ? Self.easeOut(elapsed / Self.pulseRise)
                : 1 - EaselObjectSpring.press.progress(at: elapsed - Self.pulseRise)
            result.scale = 1 + (Self.pulseScale - 1) * swell
        case .shake:
            result.offset = EaselPoint(x: Self.shakeDistance * sin(2 * Double.pi * Self.shakeSwings * linear) * (1 - linear), y: 0)
        case .restyle:
            result.opacity = Self.easeInOut(linear)
        }
        return result
    }
}

struct EaselCarryTilt: Equatable {
    static let maximum = 5.0
    static let gain = 0.006
    static let idle: TimeInterval = 0.06
    static let spring = EaselObjectSpring.press

    private(set) var angle = 0.0
    private(set) var velocity = 0.0

    static func target(forPointerSpeed speed: Double) -> Double {
        guard speed.isFinite else { return 0 }
        return min(maximum, max(-maximum, speed * gain))
    }

    mutating func step(by interval: Double, toward target: Double) {
        guard interval > 0, interval.isFinite, target.isFinite else { return }
        let omega = Self.spring.omega, zeta = Self.spring.damping
        var left = min(interval, 0.1)
        while left > 0 {
            let dt = min(left, 1.0 / 240.0)
            velocity += (omega * omega * (target - angle) - 2 * zeta * omega * velocity) * dt
            angle += velocity * dt
            left -= dt
        }
        angle = min(Self.maximum, max(-Self.maximum, angle))
    }

    var isResting: Bool { abs(angle) < 0.05 && abs(velocity) < 0.5 }
}

struct EaselObjectCarry: Equatable {
    static let scale = 1.025

    let ids: Set<UUID>
    let tilting: Set<UUID>
    let shadowOnly: Set<UUID>
    let start: TimeInterval
    private(set) var tilt = EaselCarryTilt()
    private(set) var stepped: TimeInterval
    private(set) var speed = 0.0
    private(set) var moved: TimeInterval

    init(ids: Set<UUID>, tilting: Set<UUID>, shadowOnly: Set<UUID>, at time: TimeInterval) {
        self.ids = ids
        self.tilting = tilting.intersection(ids)
        self.shadowOnly = shadowOnly.intersection(ids)
        start = time
        stepped = time
        moved = time
    }

    mutating func pointer(speed horizontal: Double, at time: TimeInterval) {
        speed = horizontal.isFinite ? horizontal : 0
        moved = time
    }

    mutating func advance(to time: TimeInterval) {
        guard time > stepped else { return }
        let target = time - moved > EaselCarryTilt.idle ? 0 : EaselCarryTilt.target(forPointerSpeed: speed)
        tilt.step(by: time - stepped, toward: target)
        stepped = time
    }

    func lift(at time: TimeInterval) -> Double { EaselObjectSpring.lift.progress(at: time - start) }

    func presentation(for id: UUID, at time: TimeInterval) -> EaselObjectPresentation {
        guard ids.contains(id) else { return .identity }
        let raised = min(1.2, max(0, lift(at: time)))
        var result = EaselObjectPresentation.identity
        result.shadow = min(1, raised)
        guard !shadowOnly.contains(id) else { return result }
        result.scale = 1 + (Self.scale - 1) * raised
        if tilting.contains(id) { result.rotation = tilt.angle }
        return result
    }
}

struct EaselObjectMotion {
    private(set) var transitions: [UUID: EaselObjectTransition] = [:]
    private(set) var ghosts: [EaselItem] = []
    private(set) var previousLooks: [UUID: EaselItem] = [:]
    var carry: EaselObjectCarry?
    private(set) var raised: [UUID: TimeInterval] = [:]

    var isEmpty: Bool { transitions.isEmpty && carry == nil && raised.isEmpty }
    var ids: Set<UUID> { Set(transitions.keys).union(carry?.ids ?? []).union(raised.keys) }

    mutating func raise(_ id: UUID, at time: TimeInterval, reduced: Bool) {
        guard !reduced else { return }
        raised[id] = raised[id] ?? time
    }

    mutating func lower(_ id: UUID) { raised.removeValue(forKey: id) }

    func isRaised(_ id: UUID) -> Bool { raised[id] != nil }

    static func raisedPresentation(since elapsed: TimeInterval) -> EaselObjectPresentation {
        let up = EaselObjectSpring.lift.progress(at: elapsed)
        let breath = 1 + EaselObjectTransition.breathDepth * sin(2 * Double.pi * max(0, elapsed) / EaselObjectTransition.breathPeriod) * min(1, max(0, elapsed) / 0.3)
        var result = EaselObjectPresentation.identity
        result.scale = (1 + (EaselObjectTransition.raisedScale - 1) * up) * breath
        result.opacity = 1 - (1 - EaselObjectTransition.raisedOpacity) * min(1, up)
        result.shadow = EaselObjectTransition.raisedShadow * min(1, up)
        return result
    }

    mutating func appear(_ ids: some Sequence<UUID>, at time: TimeInterval, reduced: Bool) {
        for id in ids { transitions[id] = EaselObjectTransition(effect: .appear(.pop), start: time, reduced: reduced) }
    }

    mutating func appear(_ entrances: [UUID: EaselObjectEntrance], delays: [UUID: TimeInterval] = [:], at time: TimeInterval, reduced: Bool) {
        for (id, entrance) in entrances {
            raised.removeValue(forKey: id)
            let delay = reduced ? 0 : max(0, delays[id] ?? 0)
            transitions[id] = EaselObjectTransition(effect: .appear(entrance), start: time + delay, reduced: reduced)
        }
    }

    mutating func vanish(_ items: [EaselItem], at time: TimeInterval, reduced: Bool) {
        let leaving = Set(items.map(\.id))
        ghosts.removeAll { leaving.contains($0.id) }
        for item in items {
            ghosts.append(item)
            previousLooks.removeValue(forKey: item.id)
            transitions[item.id] = EaselObjectTransition(effect: .vanish, start: time, reduced: reduced)
        }
    }

    mutating func glide(_ offsets: [UUID: EaselPoint], fades: Bool, stretches: [UUID: EaselPoint] = [:], turns: [UUID: Double] = [:],
                        lands: Bool = false, delays: [UUID: TimeInterval] = [:], at time: TimeInterval, reduced: Bool) {
        var candidates = offsets
        for id in stretches.keys where candidates[id] == nil { candidates[id] = EaselPoint(x: 0, y: 0) }
        for id in turns.keys where candidates[id] == nil { candidates[id] = EaselPoint(x: 0, y: 0) }
        for (id, offset) in candidates where offset.x.isFinite && offset.y.isFinite {
            let stretch = stretches[id].flatMap { $0.x.isFinite && $0.y.isFinite && $0.x > 0 && $0.y > 0 ? $0 : nil } ?? EaselPoint(x: 1, y: 1)
            let turn = turns[id].flatMap { $0.isFinite ? $0 : nil } ?? 0
            let resized = abs(stretch.x - 1) > 0.01 || abs(stretch.y - 1) > 0.01
            guard abs(offset.x) > 0.5 || abs(offset.y) > 0.5 || resized || abs(turn) > 0.5 else { continue }
            var start = offset
            if let current = transitions[id], case .glide = current.effect, !current.reduced, !reduced {
                let shown = current.presentation(at: time).offset
                start = EaselPoint(x: offset.x + shown.x, y: offset.y + shown.y)
            }
            let delay = reduced ? 0 : max(0, delays[id] ?? 0)
            transitions[id] = EaselObjectTransition(effect: .glide(from: start, fades: fades, stretch: stretch, turn: turn, lands: lands),
                                                    start: time + delay, reduced: reduced)
        }
    }

    mutating func lift(_ ids: some Sequence<UUID>, from scale: Double, at time: TimeInterval, reduced: Bool) {
        guard !reduced, scale.isFinite, scale > 0 else { return }
        for id in ids { transitions[id] = EaselObjectTransition(effect: .lift(from: scale), start: time, reduced: reduced) }
    }

    mutating func pulse(_ ids: some Sequence<UUID>, at time: TimeInterval, reduced: Bool) {
        guard !reduced else { return }
        for id in ids { transitions[id] = EaselObjectTransition(effect: .pulse, start: time, reduced: false) }
    }

    mutating func shake(_ ids: some Sequence<UUID>, at time: TimeInterval, reduced: Bool) {
        guard !reduced else { return }
        for id in ids { transitions[id] = EaselObjectTransition(effect: .shake, start: time, reduced: false) }
    }

    mutating func restyle(_ previous: [EaselItem], at time: TimeInterval, reduced: Bool) {
        for item in previous {
            if let current = transitions[item.id], current.effect != .restyle { continue }
            previousLooks[item.id] = item
            transitions[item.id] = EaselObjectTransition(effect: .restyle, start: time, reduced: reduced)
        }
    }

    mutating func pickUp(_ ids: Set<UUID>, tilting: Set<UUID>, shadowOnly: Set<UUID>, at time: TimeInterval, reduced: Bool) {
        guard !reduced, !ids.isEmpty else { carry = nil; return }
        carry = EaselObjectCarry(ids: ids, tilting: tilting, shadowOnly: shadowOnly, at: time)
        for id in ids { transitions.removeValue(forKey: id); previousLooks.removeValue(forKey: id) }
    }

    @discardableResult
    mutating func drop(at time: TimeInterval) -> Set<UUID> {
        guard var carried = carry else { return [] }
        carry = nil
        carried.advance(to: time)
        for id in carried.ids {
            let shown = carried.presentation(for: id, at: time)
            transitions[id] = EaselObjectTransition(effect: .land(scale: shown.scale, rotation: shown.rotation, shadow: shown.shadow),
                                                    start: time, reduced: false)
        }
        return carried.ids
    }

    func presentation(for id: UUID, at time: TimeInterval) -> EaselObjectPresentation {
        if let carry, carry.ids.contains(id) { return carry.presentation(for: id, at: time) }
        if let since = raised[id] { return Self.raisedPresentation(since: time - since) }
        return transitions[id]?.presentation(at: time) ?? .identity
    }

    func transition(for id: UUID) -> EaselObjectTransition? { transitions[id] }

    func previousLook(for id: UUID) -> EaselItem? {
        guard let transition = transitions[id], case .restyle = transition.effect else { return nil }
        return previousLooks[id]
    }

    @discardableResult
    mutating func prune(at time: TimeInterval) -> Set<UUID> {
        let done = Set(transitions.filter { $0.value.finished(at: time) }.map(\.key))
        guard !done.isEmpty else { return [] }
        for id in done { transitions.removeValue(forKey: id); previousLooks.removeValue(forKey: id) }
        ghosts.removeAll { done.contains($0.id) }
        return done
    }

    mutating func forget(missing present: Set<UUID>) {
        let ghostIDs = Set(ghosts.map(\.id))
        for id in Array(transitions.keys) where !present.contains(id) && !ghostIDs.contains(id) {
            transitions.removeValue(forKey: id)
            previousLooks.removeValue(forKey: id)
        }
        let reborn = ghostIDs.intersection(present)
        guard !reborn.isEmpty else { return }
        ghosts.removeAll { reborn.contains($0.id) }
        for id in reborn { transitions.removeValue(forKey: id) }
    }

    mutating func cancelAll() {
        transitions.removeAll()
        ghosts.removeAll()
        previousLooks.removeAll()
        carry = nil
        raised.removeAll()
    }

    static func glides(_ item: EaselItem) -> Bool {
        item.kind != .arrow || (item.startConnection == nil && item.endConnection == nil)
    }

    static func moves(from before: EaselDocument, to after: EaselDocument, among ids: Set<UUID>? = nil) -> [UUID: EaselPoint] {
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

    static func copyOffsets(sources: [UUID], copies: [UUID], before: EaselDocument, after: EaselDocument) -> [UUID: EaselPoint] {
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

    static func added(from before: EaselDocument, to after: EaselDocument) -> [UUID] {
        let old = Set(before.items.map(\.id))
        return after.items.filter { !old.contains($0.id) }.map(\.id)
    }

    static func removed(from before: EaselDocument, to after: EaselDocument) -> [EaselItem] {
        let remaining = Set(after.items.map(\.id))
        return before.items.filter { !remaining.contains($0.id) }
    }

    static let cascadeStep: TimeInterval = 0.04
    static let cascadeSpread: TimeInterval = 0.22

    static func cascade(_ frames: [UUID: EaselRect]) -> [UUID: TimeInterval] {
        guard frames.count > 1 else { return frames.mapValues { _ in 0 } }
        let minX = frames.values.map(\.x).min() ?? 0, minY = frames.values.map(\.y).min() ?? 0
        let maxX = frames.values.map { $0.x + $0.width }.max() ?? 0, maxY = frames.values.map { $0.y + $0.height }.max() ?? 0
        let centre = EaselPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        var distances: [UUID: Double] = [:]
        for (id, frame) in frames {
            let dx = frame.x + frame.width / 2 - centre.x, dy = frame.y + frame.height / 2 - centre.y
            distances[id] = (dx * dx + dy * dy).squareRoot()
        }
        let farthest = distances.values.max() ?? 0
        let spread = min(cascadeSpread, cascadeStep * Double(frames.count - 1))
        guard farthest > 0.5, farthest.isFinite else { return frames.mapValues { _ in 0 } }
        return distances.mapValues { spread * $0 / farthest }
    }

    struct HistoryChange: Equatable {
        var added: [UUID] = []
        var removed: [EaselItem] = []
        var offsets: [UUID: EaselPoint] = [:]
        var stretches: [UUID: EaselPoint] = [:]
        var turns: [UUID: Double] = [:]
        var restyled: [EaselItem] = []

        var isEmpty: Bool { added.isEmpty && removed.isEmpty && offsets.isEmpty && stretches.isEmpty && turns.isEmpty && restyled.isEmpty }
    }

    static func looksDifferent(_ old: EaselItem, _ new: EaselItem) -> Bool {
        guard old.text == new.text, old.table == new.table, old.points == new.points else { return false }
        var normalized = old
        normalized.frame = new.frame
        normalized.zIndex = new.zIndex
        normalized.movedToFrontAt = new.movedToFrontAt
        normalized.groupID = new.groupID
        normalized.locked = new.locked
        normalized.attachedTo = new.attachedTo
        normalized.mindMap = new.mindMap
        normalized.page = new.page
        normalized.startConnection = new.startConnection
        normalized.endConnection = new.endConnection
        normalized.waypoints = new.waypoints
        normalized.rotation = new.rotation
        normalized.contentsHidden = new.contentsHidden
        return normalized != new
    }

    static func history(from before: EaselDocument, to after: EaselDocument) -> HistoryChange {
        var change = HistoryChange()
        var previous: [UUID: EaselItem] = [:]
        for item in before.items { previous[item.id] = item }
        let remaining = Set(after.items.map(\.id))
        change.removed = before.items.filter { !remaining.contains($0.id) }
        for item in after.items {
            guard let old = previous[item.id] else { change.added.append(item.id); continue }
            guard old != item else { continue }
            if old.text != item.text || old.table != item.table { continue }
            let moved = glides(item) && old.frame != item.frame
            if moved {
                let oldMidX = old.frame.x + old.frame.width / 2, oldMidY = old.frame.y + old.frame.height / 2
                let newMidX = item.frame.x + item.frame.width / 2, newMidY = item.frame.y + item.frame.height / 2
                let offset = EaselPoint(x: oldMidX - newMidX, y: oldMidY - newMidY)
                if abs(offset.x) > 0.5 || abs(offset.y) > 0.5 { change.offsets[item.id] = offset }
                if item.frame.width > 1, item.frame.height > 1, old.frame.width > 1, old.frame.height > 1 {
                    let stretch = EaselPoint(x: min(4, max(0.25, old.frame.width / item.frame.width)),
                                             y: min(4, max(0.25, old.frame.height / item.frame.height)))
                    if abs(stretch.x - 1) > 0.01 || abs(stretch.y - 1) > 0.01 { change.stretches[item.id] = stretch }
                }
            }
            if glides(item) {
                var turn = old.resolvedRotation - item.resolvedRotation
                turn = turn.truncatingRemainder(dividingBy: 360)
                if turn > 180 { turn -= 360 } else if turn < -180 { turn += 360 }
                if abs(turn) > 0.5 { change.turns[item.id] = turn }
            }
            if !moved, change.turns[item.id] == nil, looksDifferent(old, item) { change.restyled.append(old) }
        }
        return change
    }

    static func restyled(from before: EaselDocument, to after: EaselDocument) -> [EaselItem] {
        var previous: [UUID: EaselItem] = [:]
        for item in before.items { previous[item.id] = item }
        return after.items.compactMap { item in
            guard let old = previous[item.id], old != item, old.text == item.text, old.table == item.table else { return nil }
            var normalized = old
            normalized.frame = item.frame
            return normalized != item ? old : nil
        }
    }
}

struct EaselBurstSpeck: Equatable {
    let angle: Double
    let distance: Double
    let size: Double
    let delay: TimeInterval
    let spin: Double
    let hue: Double
}

enum EaselBurstPlan {
    static let perCommand = 8
    static let rippleFrom = 0.6
    static let rippleTo = 1.6
    static let rippleDuration: TimeInterval = 0.35
    static let confettiDuration: TimeInterval = 0.4
    static let puffDuration: TimeInterval = 0.4
    static let glowDuration: TimeInterval = 0.45
    static let sweepDuration: TimeInterval = 0.4

    struct Random {
        private var state: UInt64
        init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
        mutating func next() -> Double {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
    }

    static func seed(_ id: UUID) -> UInt64 {
        let bytes = id.uuid
        return [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7]
            .reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    static func confetti(width: Double, height: Double, seed: UInt64) -> [EaselBurstSpeck] {
        var random = Random(seed: seed)
        let radius = max(width, height) / 2
        let count = 6 + Int(random.next() * 3)
        return (0..<count).map { index in
            let angle = (Double(index) + 0.2 + random.next() * 0.6) / Double(count) * 2 * Double.pi
            return EaselBurstSpeck(angle: angle, distance: radius * (0.9 + random.next() * 0.5) + 6,
                                   size: 3 + random.next() * 2.5, delay: random.next() * 0.04,
                                   spin: (random.next() - 0.5) * 300, hue: random.next())
        }
    }

    static func puff(width: Double, height: Double, seed: UInt64) -> [EaselBurstSpeck] {
        var random = Random(seed: seed)
        let radius = max(width, height) / 2
        let count = 5 + Int(random.next() * 2)
        return (0..<count).map { index in
            let angle = (Double(index) + random.next()) / Double(count) * 2 * Double.pi
            return EaselBurstSpeck(angle: angle, distance: radius * 0.25 + 8 + random.next() * 10,
                                   size: 7 + random.next() * 6, delay: random.next() * 0.03, spin: 0, hue: random.next())
        }
    }
}

enum EaselStampGrowth {
    static let spring = EaselObjectSpring.press

    static func side(from start: Double, to target: Double, since elapsed: TimeInterval, reduced: Bool) -> Double {
        guard !reduced, elapsed.isFinite, start.isFinite else { return target }
        return start + (target - start) * spring.progress(at: elapsed)
    }

    static func settled(since elapsed: TimeInterval) -> Bool { elapsed >= 0.45 }
}

enum EaselStampWheelMotion {
    static let stagger: TimeInterval = 0.022
    static let fade: TimeInterval = 0.08
    static let tuck: TimeInterval = 0.18
    static let hoverScale = 1.14
    static let startScale = 0.35

    struct Face: Equatable {
        var reach: Double
        var scale: Double
        var opacity: Double
    }

    static func duration(count: Int) -> TimeInterval { Double(max(0, count - 1)) * stagger + EaselObjectTransition.appearDuration }

    static func fan(slot index: Int, elapsed: TimeInterval) -> Face {
        let local = elapsed - Double(max(0, index)) * stagger
        guard local > 0 else { return Face(reach: 0, scale: startScale, opacity: 0) }
        let spring = EaselObjectSpring.pop.progress(at: local)
        return Face(reach: spring, scale: startScale + (1 - startScale) * spring, opacity: EaselObjectTransition.easeOut(local / fade))
    }

    static func tucked(_ face: Face, elapsed: TimeInterval) -> Face {
        let t = EaselObjectTransition.easeInOut(elapsed / tuck)
        return Face(reach: face.reach * (1 - 0.6 * t), scale: face.scale * (1 - 0.5 * t), opacity: face.opacity * (1 - t))
    }

    static func flight(elapsed: TimeInterval) -> (travel: Double, scale: Double, opacity: Double) {
        let t = EaselObjectTransition.easeOut(elapsed / tuck)
        return (t, 1.15 - 0.55 * t, 1 - EaselObjectTransition.easeIn(elapsed / tuck) * 0.9)
    }
}
