import Foundation

package struct EaselObjectPresentation: Equatable {
    package var opacity: Double
    package var scale: Double
    package var offset: EaselPoint
    package var rotation: Double = 0
    package var shadow: Double = 0
    package var stretch = EaselPoint(x: 1, y: 1)
    package init(opacity: Double, scale: Double, offset: EaselPoint, rotation: Double = 0, shadow: Double = 0, stretch: EaselPoint = EaselPoint(x: 1, y: 1)) {
        self.opacity = opacity
        self.scale = scale
        self.offset = offset
        self.rotation = rotation
        self.shadow = shadow
        self.stretch = stretch
    }

    package static let identity = EaselObjectPresentation(opacity: 1, scale: 1, offset: EaselPoint(x: 0, y: 0))
    package var isIdentity: Bool { self == .identity }
    package var scaleX: Double { scale * stretch.x }
    package var scaleY: Double { scale * stretch.y }
    package var transforms: Bool { scaleX != 1 || scaleY != 1 || rotation != 0 || offset.x != 0 || offset.y != 0 }
}

package enum EaselObjectEntrance: Equatable {
    case pop
    case drop(tilt: Double)
    case slam(tilt: Double, raised: Bool, from: Double)
    case quick
    case fade

    package static let dropTilt = 3.0
    package static let slamTilt = 12.0
    package static let pressedSlamTilt = 4.0

    package static func of(_ item: EaselItem) -> EaselObjectEntrance {
        let side: Double = item.id.uuid.0 & 1 == 0 ? 1 : -1
        switch item.kind {
        case .sticky: return .drop(tilt: dropTilt * side)
        case .stamp: return .slam(tilt: slamTilt * side, raised: false, from: EaselObjectTransition.slamScale)
        case .arrow, .freehand, .section: return .fade
        default: return .pop
        }
    }

    package static func returning(_ item: EaselItem) -> EaselObjectEntrance { item.kind == .arrow ? .fade : .quick }

    package static func cascades(_ item: EaselItem) -> Bool { item.kind != .arrow }
}

package enum EaselObjectEffect: Equatable {
    case appear(EaselObjectEntrance)
    case vanish
    case glide(from: EaselPoint, fades: Bool, stretch: EaselPoint, turn: Double, lands: Bool)
    case lift(from: Double)
    case land(scale: Double, rotation: Double, shadow: Double)
    case pulse
    case shake
    case restyle
}

package struct EaselObjectSpring: Equatable {
    package let response: Double
    package let damping: Double
    package init(response: Double, damping: Double) {
        self.response = response
        self.damping = damping
    }

    package static let pop = EaselObjectSpring(response: 0.4, damping: 0.7)
    package static let press = EaselObjectSpring(response: 0.3, damping: 0.6)
    package static let toggle = EaselObjectSpring(response: 0.2, damping: 0.5)
    package static let settle = EaselObjectSpring(response: 0.34, damping: 0.86)
    package static let lift = EaselObjectSpring(response: 0.3, damping: 0.95)
    package static let highlight = EaselObjectSpring(response: 0.15, damping: 0.825)
    package static let glide = settle
    package static let hover = highlight

    package var omega: Double { 2 * Double.pi / response }

    package func progress(at time: Double) -> Double {
        guard time > 0 else { return 0 }
        if damping < 1 {
            let damped = omega * (1 - damping * damping).squareRoot()
            let envelope = exp(-damping * omega * time)
            return 1 - envelope * (cos(damped * time) + damping * omega / damped * sin(damped * time))
        }
        return 1 - exp(-omega * time) * (1 + omega * time)
    }
}

package struct EaselObjectTransition: Equatable {
    package static let appearDuration: TimeInterval = 0.42
    package static let appearFade: TimeInterval = 0.12
    package static let slamDuration: TimeInterval = 0.36
    package static let slamFade: TimeInterval = 0.08
    package static let quickDuration: TimeInterval = 0.24
    package static let vanishDuration: TimeInterval = 0.18
    package static let glideDuration: TimeInterval = 0.45
    package static let liftDuration: TimeInterval = 0.2
    package static let landDuration: TimeInterval = 0.42
    package static let pulseDuration: TimeInterval = 0.5
    package static let pulseRise: TimeInterval = 0.09
    package static let shakeDuration: TimeInterval = 0.3
    package static let restyleDuration: TimeInterval = 0.15
    package static let reducedFade: TimeInterval = 0.15
    package static let hiddenScale = 0.8
    package static let quickScale = 0.92
    package static let dropScale = 1.08
    package static let dropRise = 8.0
    package static let slamScale = 1.6
    package static let raisedScale = 1.15
    package static let raisedOpacity = 0.8
    package static let raisedShadow = 0.8
    package static let breathDepth = 0.015
    package static let breathPeriod = 1.1
    package static let vanishScale = 0.85
    package static let pulseScale = 1.05
    package static let shakeDistance = 4.0
    package static let shakeSwings = 3.0
    package static let landingSquash = 0.025
    package static let copySquash = 0.03

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

    package func finished(at time: TimeInterval) -> Bool { time - start >= duration }

    package static func easeOut(_ t: Double) -> Double {
        let clamped = min(1, max(0, t))
        return 1 - pow(1 - clamped, 3)
    }

    package static func easeIn(_ t: Double) -> Double {
        let clamped = min(1, max(0, t))
        return clamped * clamped
    }

    package static func easeInOut(_ t: Double) -> Double {
        let clamped = min(1, max(0, t))
        return clamped * clamped * (3 - 2 * clamped)
    }

    package static func squash(at elapsed: Double, from start: Double, length: Double, amount: Double) -> Double {
        let u = (elapsed - start) / length
        guard u > 0, u < 1 else { return 0 }
        return amount * sin(Double.pi * u) * (1 - 0.35 * u)
    }

    package static func squashed(_ stretch: EaselPoint, by amount: Double) -> EaselPoint {
        EaselPoint(x: stretch.x * (1 + amount), y: stretch.y * (1 - amount))
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
            case .slam(let tilt, let raised, let from):
                let settled = EaselObjectSpring.toggle.progress(at: elapsed)
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

package struct EaselFadingLook: Equatable {
    package let item: EaselItem
    package let weight: Double
    package init(item: EaselItem, weight: Double) {
        self.item = item
        self.weight = weight
    }
}

package struct EaselCarryTilt: Equatable {
    package static let maximum = 5.0
    package static let gain = 0.006
    package static let idle: TimeInterval = 0.06
    package static let spring = EaselObjectSpring.press

    package private(set) var angle = 0.0
    package private(set) var velocity = 0.0
    package init(angle: Double = 0.0, velocity: Double = 0.0) {
        self.angle = angle
        self.velocity = velocity
    }

    package static func target(forPointerSpeed speed: Double) -> Double {
        guard speed.isFinite else { return 0 }
        return min(maximum, max(-maximum, speed * gain))
    }

    package mutating func step(by interval: Double, toward target: Double) {
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

    package var isResting: Bool { abs(angle) < 0.05 && abs(velocity) < 0.5 }
}

package struct EaselObjectCarry: Equatable {
    package static let scale = 1.025

    package let ids: Set<UUID>
    package let tilting: Set<UUID>
    package let shadowOnly: Set<UUID>
    package let start: TimeInterval
    package private(set) var tilt = EaselCarryTilt()
    package private(set) var stepped: TimeInterval
    package private(set) var speed = 0.0
    package private(set) var moved: TimeInterval

    package init(ids: Set<UUID>, tilting: Set<UUID>, shadowOnly: Set<UUID>, at time: TimeInterval) {
        self.ids = ids
        self.tilting = tilting.intersection(ids)
        self.shadowOnly = shadowOnly.intersection(ids)
        start = time
        stepped = time
        moved = time
    }

    package mutating func pointer(speed horizontal: Double, at time: TimeInterval) {
        speed = horizontal.isFinite ? horizontal : 0
        moved = time
    }

    package mutating func advance(to time: TimeInterval) {
        guard time > stepped else { return }
        let target = time - moved > EaselCarryTilt.idle ? 0 : EaselCarryTilt.target(forPointerSpeed: speed)
        tilt.step(by: time - stepped, toward: target)
        stepped = time
    }

    package func lift(at time: TimeInterval) -> Double { EaselObjectSpring.lift.progress(at: time - start) }

    package func presentation(for id: UUID, at time: TimeInterval) -> EaselObjectPresentation {
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

package struct EaselObjectMotion {
    package private(set) var transitions: [UUID: EaselObjectTransition] = [:]
    package private(set) var ghosts: [EaselItem] = []
    package private(set) var previousLooks: [UUID: [EaselFadingLook]] = [:]
    package static let fadingLookLimit = 3
    package var carry: EaselObjectCarry?
    package private(set) var raised: [UUID: TimeInterval] = [:]
    package private(set) var raisedRatio: [UUID: Double] = [:]
    package init(transitions: [UUID: EaselObjectTransition] = [:], ghosts: [EaselItem] = [], previousLooks: [UUID: [EaselFadingLook]] = [:], carry: EaselObjectCarry? = nil, raised: [UUID: TimeInterval] = [:], raisedRatio: [UUID: Double] = [:]) {
        self.transitions = transitions
        self.ghosts = ghosts
        self.previousLooks = previousLooks
        self.carry = carry
        self.raised = raised
        self.raisedRatio = raisedRatio
    }
    private var queued: [UUID: EaselObjectTransition] = [:]
    private var promoted: Set<UUID> = []

    package var isEmpty: Bool { transitions.isEmpty && carry == nil && raised.isEmpty }
    package var ids: Set<UUID> { Set(transitions.keys).union(carry?.ids ?? []).union(raised.keys) }

    package mutating func raise(_ id: UUID, at time: TimeInterval, reduced: Bool) {
        guard !reduced else { return }
        raised[id] = raised[id] ?? time
    }

    package mutating func lower(_ id: UUID) { raised.removeValue(forKey: id); raisedRatio.removeValue(forKey: id) }

    package mutating func settleRaised(_ id: UUID, ratio: Double) {
        guard raised[id] != nil, ratio.isFinite, ratio > 0 else { return }
        raisedRatio[id] = ratio
    }

    package func slamStart(for id: UUID, at time: TimeInterval) -> Double {
        guard let since = raised[id] else { return EaselObjectTransition.raisedScale }
        return Self.raisedPresentation(since: time - since).scale * (raisedRatio[id] ?? 1)
    }

    package func isRaised(_ id: UUID) -> Bool { raised[id] != nil }

    package static func raisedPresentation(since elapsed: TimeInterval) -> EaselObjectPresentation {
        let up = EaselObjectSpring.lift.progress(at: elapsed)
        let breath = 1 + EaselObjectTransition.breathDepth * sin(2 * Double.pi * max(0, elapsed) / EaselObjectTransition.breathPeriod) * min(1, max(0, elapsed) / 0.3)
        var result = EaselObjectPresentation.identity
        result.scale = (1 + (EaselObjectTransition.raisedScale - 1) * up) * breath
        result.opacity = 1 - (1 - EaselObjectTransition.raisedOpacity) * min(1, up)
        result.shadow = EaselObjectTransition.raisedShadow * min(1, up)
        return result
    }

    package mutating func appear(_ ids: some Sequence<UUID>, at time: TimeInterval, reduced: Bool) {
        for id in ids { transitions[id] = EaselObjectTransition(effect: .appear(.pop), start: time, reduced: reduced) }
    }

    package mutating func appear(_ entrances: [UUID: EaselObjectEntrance], delays: [UUID: TimeInterval] = [:], at time: TimeInterval, reduced: Bool) {
        for (id, entrance) in entrances {
            raised.removeValue(forKey: id)
            raisedRatio.removeValue(forKey: id)
            let delay = reduced ? 0 : max(0, delays[id] ?? 0)
            transitions[id] = EaselObjectTransition(effect: .appear(entrance), start: time + delay, reduced: reduced)
        }
    }

    package mutating func vanish(_ items: [EaselItem], at time: TimeInterval, reduced: Bool) {
        let leaving = Set(items.map(\.id))
        ghosts.removeAll { leaving.contains($0.id) }
        for item in items {
            ghosts.append(item)
            previousLooks.removeValue(forKey: item.id)
            queued.removeValue(forKey: item.id)
            transitions[item.id] = EaselObjectTransition(effect: .vanish, start: time, reduced: reduced)
        }
    }

    package mutating func glide(_ offsets: [UUID: EaselPoint], fades: Bool, stretches: [UUID: EaselPoint] = [:], turns: [UUID: Double] = [:],
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

    package mutating func lift(_ ids: some Sequence<UUID>, from scale: Double, at time: TimeInterval, reduced: Bool) {
        guard !reduced, scale.isFinite, scale > 0 else { return }
        for id in ids where transitions[id].map({ $0.finished(at: time) }) ?? true {
            transitions[id] = EaselObjectTransition(effect: .lift(from: scale), start: time, reduced: reduced)
        }
    }

    package mutating func pulse(_ ids: some Sequence<UUID>, at time: TimeInterval, reduced: Bool) {
        guard !reduced else { return }
        for id in ids { follow(id, with: .pulse, at: time) }
    }

    package mutating func shake(_ ids: some Sequence<UUID>, at time: TimeInterval, reduced: Bool) {
        guard !reduced else { return }
        for id in ids { follow(id, with: .shake, at: time) }
    }

    private mutating func follow(_ id: UUID, with effect: EaselObjectEffect, at time: TimeInterval) {
        if let current = transitions[id], !current.finished(at: time), current.effect != effect {
            if case .vanish = current.effect { return }
            queued[id] = EaselObjectTransition(effect: effect, start: current.start + current.duration, reduced: false)
            return
        }
        queued.removeValue(forKey: id)
        transitions[id] = EaselObjectTransition(effect: effect, start: time, reduced: false)
    }

    package func queuedTransition(for id: UUID) -> EaselObjectTransition? { queued[id] }

    package mutating func takePromoted() -> Set<UUID> {
        defer { promoted.removeAll() }
        return promoted
    }

    package mutating func restyle(_ previous: [EaselItem], at time: TimeInterval, reduced: Bool) {
        for item in previous {
            var stack = [EaselFadingLook(item: item, weight: 1)]
            if let current = transitions[item.id] {
                guard current.effect == .restyle else { continue }
                if !current.finished(at: time) {
                    let shown = min(1, max(0, current.presentation(at: time).opacity))
                    stack = (previousLooks[item.id] ?? []).map { EaselFadingLook(item: $0.item, weight: $0.weight * (1 - shown)) }
                    stack.append(EaselFadingLook(item: item, weight: shown))
                    stack = Self.trimmed(stack)
                }
            }
            previousLooks[item.id] = stack
            transitions[item.id] = EaselObjectTransition(effect: .restyle, start: time, reduced: reduced)
        }
    }

    package static func trimmed(_ looks: [EaselFadingLook]) -> [EaselFadingLook] {
        var kept = looks.filter { $0.weight > 0.001 }
        if kept.count > fadingLookLimit {
            let floor = kept.map(\.weight).sorted(by: >)[fadingLookLimit - 1]
            var chosen: [EaselFadingLook] = []
            for look in kept where look.weight >= floor && chosen.count < fadingLookLimit { chosen.append(look) }
            kept = chosen
        }
        let total = kept.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return Array(looks.suffix(1)).map { EaselFadingLook(item: $0.item, weight: 1) } }
        return kept.map { EaselFadingLook(item: $0.item, weight: $0.weight / total) }
    }

    package mutating func pickUp(_ ids: Set<UUID>, tilting: Set<UUID>, shadowOnly: Set<UUID>, at time: TimeInterval, reduced: Bool) {
        guard !reduced, !ids.isEmpty else { carry = nil; return }
        carry = EaselObjectCarry(ids: ids, tilting: tilting, shadowOnly: shadowOnly, at: time)
        for id in ids { transitions.removeValue(forKey: id); previousLooks.removeValue(forKey: id) }
    }

    @discardableResult
    package mutating func drop(at time: TimeInterval) -> Set<UUID> {
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

    package func presentation(for id: UUID, at time: TimeInterval) -> EaselObjectPresentation {
        if let carry, carry.ids.contains(id) { return carry.presentation(for: id, at: time) }
        if let since = raised[id] { return Self.raisedPresentation(since: time - since) }
        if let next = queued[id], transitions[id].map({ $0.finished(at: time) }) ?? true { return next.presentation(at: time) }
        return transitions[id]?.presentation(at: time) ?? .identity
    }

    package func transition(for id: UUID) -> EaselObjectTransition? { transitions[id] }

    package func previousLook(for id: UUID) -> EaselItem? {
        guard let transition = transitions[id], case .restyle = transition.effect else { return nil }
        return previousLooks[id]?.max { $0.weight < $1.weight }?.item
    }

    package func fadingLooks(for id: UUID, at time: TimeInterval) -> [EaselFadingLook] {
        guard let transition = transitions[id], case .restyle = transition.effect, let looks = previousLooks[id] else { return [] }
        let fading = 1 - min(1, max(0, transition.presentation(at: time).opacity))
        return looks.map { EaselFadingLook(item: $0.item, weight: $0.weight * fading) }
    }

    @discardableResult
    package mutating func prune(at time: TimeInterval) -> Set<UUID> {
        var done = Set(transitions.filter { $0.value.finished(at: time) }.map(\.key))
        for id in done {
            guard let next = queued.removeValue(forKey: id) else { continue }
            transitions[id] = next
            previousLooks.removeValue(forKey: id)
            promoted.insert(id)
            done.remove(id)
        }
        guard !done.isEmpty else { return [] }
        for id in done { transitions.removeValue(forKey: id); previousLooks.removeValue(forKey: id) }
        ghosts.removeAll { done.contains($0.id) }
        return done
    }

    package mutating func forget(missing present: Set<UUID>) {
        let ghostIDs = Set(ghosts.map(\.id))
        for id in Array(transitions.keys) where !present.contains(id) && !ghostIDs.contains(id) {
            transitions.removeValue(forKey: id)
            previousLooks.removeValue(forKey: id)
            queued.removeValue(forKey: id)
        }
        let reborn = ghostIDs.intersection(present)
        guard !reborn.isEmpty else { return }
        ghosts.removeAll { reborn.contains($0.id) }
        for id in reborn { transitions.removeValue(forKey: id) }
    }

    package mutating func cancelAll() {
        transitions.removeAll()
        ghosts.removeAll()
        previousLooks.removeAll()
        carry = nil
        raised.removeAll()
        raisedRatio.removeAll()
        queued.removeAll()
        promoted.removeAll()
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

    package static let cascadeStep: TimeInterval = 0.04
    package static let cascadeSpread: TimeInterval = 0.22

    package static func cascade(_ frames: [UUID: EaselRect]) -> [UUID: TimeInterval] {
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

    package struct HistoryChange: Equatable {
        package var added: [UUID] = []
        package var removed: [EaselItem] = []
        package var offsets: [UUID: EaselPoint] = [:]
        package var stretches: [UUID: EaselPoint] = [:]
        package var turns: [UUID: Double] = [:]
        package var restyled: [EaselItem] = []
        package init(added: [UUID] = [], removed: [EaselItem] = [], offsets: [UUID: EaselPoint] = [:], stretches: [UUID: EaselPoint] = [:], turns: [UUID: Double] = [:], restyled: [EaselItem] = []) {
            self.added = added
            self.removed = removed
            self.offsets = offsets
            self.stretches = stretches
            self.turns = turns
            self.restyled = restyled
        }

        package var isEmpty: Bool { added.isEmpty && removed.isEmpty && offsets.isEmpty && stretches.isEmpty && turns.isEmpty && restyled.isEmpty }
    }

    package static func looksDifferent(_ old: EaselItem, _ new: EaselItem) -> Bool {
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

    package static func history(from before: EaselDocument, to after: EaselDocument) -> HistoryChange {
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

    package static func restyled(from before: EaselDocument, to after: EaselDocument) -> [EaselItem] {
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

package struct EaselBurstSpeck: Equatable {
    package let angle: Double
    package let distance: Double
    package let size: Double
    package let delay: TimeInterval
    package let spin: Double
    package let hue: Double
    package init(angle: Double, distance: Double, size: Double, delay: TimeInterval, spin: Double, hue: Double) {
        self.angle = angle
        self.distance = distance
        self.size = size
        self.delay = delay
        self.spin = spin
        self.hue = hue
    }
}

package enum EaselBurstPlan {
    package static let perCommand = 8
    package static let rippleFrom = 0.6
    package static let rippleTo = 1.6
    package static let rippleDuration: TimeInterval = 0.35
    package static let confettiDuration: TimeInterval = 0.4
    package static let puffDuration: TimeInterval = 0.4
    package static let glowDuration: TimeInterval = 0.45
    package static let sweepDuration: TimeInterval = 0.4

    package struct Random {
        private var state: UInt64
        package init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
        package mutating func next() -> Double {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
    }

    package static func seed(_ id: UUID) -> UInt64 {
        let bytes = id.uuid
        return [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7]
            .reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    package static func confetti(width: Double, height: Double, seed: UInt64) -> [EaselBurstSpeck] {
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

    package static func puff(width: Double, height: Double, seed: UInt64) -> [EaselBurstSpeck] {
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

package enum EaselStampGrowth {
    package static let spring = EaselObjectSpring.press

    package static func side(from start: Double, to target: Double, since elapsed: TimeInterval, reduced: Bool) -> Double {
        guard !reduced, elapsed.isFinite, start.isFinite else { return target }
        return start + (target - start) * spring.progress(at: elapsed)
    }

    package static func settled(since elapsed: TimeInterval) -> Bool { elapsed >= 0.45 }
}

package enum EaselStampWheelMotion {
    package static let stagger: TimeInterval = 0.022
    package static let fade: TimeInterval = 0.08
    package static let tuck: TimeInterval = 0.18
    package static let hoverScale = 1.14
    package static let startScale = 0.35

    package struct Face: Equatable {
        package var reach: Double
        package var scale: Double
        package var opacity: Double
        package init(reach: Double, scale: Double, opacity: Double) {
            self.reach = reach
            self.scale = scale
            self.opacity = opacity
        }
    }

    package static func duration(count: Int) -> TimeInterval { Double(max(0, count - 1)) * stagger + EaselObjectTransition.appearDuration }

    package static func fan(slot index: Int, elapsed: TimeInterval) -> Face {
        let local = elapsed - Double(max(0, index)) * stagger
        guard local > 0 else { return Face(reach: 0, scale: startScale, opacity: 0) }
        let spring = EaselObjectSpring.pop.progress(at: local)
        return Face(reach: spring, scale: startScale + (1 - startScale) * spring, opacity: EaselObjectTransition.easeOut(local / fade))
    }

    package static func tucked(_ face: Face, elapsed: TimeInterval) -> Face {
        let t = EaselObjectTransition.easeInOut(elapsed / tuck)
        return Face(reach: face.reach * (1 - 0.6 * t), scale: face.scale * (1 - 0.5 * t), opacity: face.opacity * (1 - t))
    }

    package static func flight(elapsed: TimeInterval) -> (travel: Double, scale: Double, opacity: Double) {
        let t = EaselObjectTransition.easeOut(elapsed / tuck)
        return (t, 1.15 - 0.55 * t, 1 - EaselObjectTransition.easeIn(elapsed / tuck) * 0.9)
    }
}

extension EaselMindMapTree {
    package func foldAnchor(of id: UUID, among targets: Set<UUID>) -> UUID? {
        var current = nodes[id]?.parent, steps = 0
        while let candidate = current, steps <= nodes.count {
            if targets.contains(candidate) { return candidate }
            current = nodes[candidate]?.parent
            steps += 1
        }
        return nil
    }
}
