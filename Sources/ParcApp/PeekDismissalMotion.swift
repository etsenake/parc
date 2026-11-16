import CoreGraphics
import Foundation

enum PeekDismissalTiming {
    static let springDamping = 0.86
    static let springResponse = 0.34
    static let slide: TimeInterval = 0.22
    static let fade: TimeInterval = 0.2
    static let reduced: TimeInterval = 0.15
    static let reducedDragFade = 0.7
    static let minimumTravel: CGFloat = 0.12
    static let maximumTravel: CGFloat = 0.5
    static let reappearFade = 1.6
    static let shadowMargin: CGFloat = 8
}

struct PeekDismissalFrame: Equatable {
    var offset: CGFloat
    var card: Double
    var wash: Double

    static let rest = PeekDismissalFrame(offset: 0, card: 1, wash: 1)
}

struct PeekDismissalMotion: Equatable {
    struct Geometry: Equatable {
        var exitDistance: CGFloat
        var paneWidth: CGFloat

        init(exitDistance: CGFloat, paneWidth: CGFloat) {
            self.exitDistance = max(1, exitDistance)
            self.paneWidth = max(1, paneWidth)
        }

        init(paneWidth: CGFloat, cardMinX: CGFloat) {
            self.init(exitDistance: paneWidth - cardMinX + PeekDismissalTiming.shadowMargin, paneWidth: paneWidth)
        }
    }

    private enum Phase: Equatable {
        case still(PeekDismissalFrame)
        case following(Double)
        case spring(from: CGFloat, velocity: CGFloat, start: TimeInterval)
        case slide(from: PeekDismissalFrame, travel: CGFloat, start: TimeInterval)
        case fade(from: PeekDismissalFrame, to: PeekDismissalFrame, duration: TimeInterval, start: TimeInterval)
        case reappear(from: CGFloat, start: TimeInterval)
    }

    var geometry: Geometry
    private(set) var reducesMotion = false
    private var phase = Phase.still(.rest)

    init(geometry: Geometry = Geometry(exitDistance: 1, paneWidth: 1)) {
        self.geometry = geometry
    }

    mutating func begin(reducesMotion: Bool) {
        self.reducesMotion = reducesMotion
        phase = .following(0)
    }

    mutating func follow(_ fraction: Double) {
        phase = .following(min(max(fraction, 0), 1))
    }

    mutating func springBack(velocity: Double, at time: TimeInterval) {
        let current = frame(at: time)
        if reducesMotion || abs(current.offset) < 0.5 {
            phase = .fade(from: current, to: .rest, duration: PeekDismissalTiming.reduced, start: time)
        } else {
            phase = .spring(from: current.offset, velocity: CGFloat(velocity) * geometry.exitDistance, start: time)
        }
    }

    @discardableResult
    mutating func exit(_ kind: PeekCloseTransition.Exit, velocity: Double, reducesMotion: Bool,
                       at time: TimeInterval) -> TimeInterval {
        self.reducesMotion = reducesMotion
        let current = frame(at: time)
        let gone = PeekDismissalFrame(offset: current.offset, card: 0, wash: 0)
        switch kind {
        case .slide where !reducesMotion:
            let speed = CGFloat(max(0, velocity)) * geometry.exitDistance
            let travel = min(PeekDismissalTiming.maximumTravel * geometry.paneWidth,
                             max(PeekDismissalTiming.minimumTravel * geometry.paneWidth,
                                 speed * PeekDismissalTiming.slide / 2))
            phase = .slide(from: current, travel: travel, start: time)
            return PeekDismissalTiming.slide
        case .slide:
            phase = .fade(from: current, to: gone, duration: PeekDismissalTiming.reduced, start: time)
            return PeekDismissalTiming.reduced
        case .fade:
            phase = .fade(from: current, to: gone, duration: PeekDismissalTiming.fade, start: time)
            return PeekDismissalTiming.fade
        }
    }

    mutating func reappear(reducesMotion: Bool, at time: TimeInterval) {
        self.reducesMotion = reducesMotion
        let current = frame(at: time)
        if reducesMotion || abs(current.offset) < 1 {
            let duration = reducesMotion ? PeekDismissalTiming.reduced : PeekDismissalTiming.fade
            phase = .fade(from: PeekDismissalFrame(offset: 0, card: current.card, wash: current.wash), to: .rest,
                          duration: duration, start: time)
        } else {
            phase = .reappear(from: current.offset, start: time)
        }
    }

    mutating func vanish(at time: TimeInterval) {
        phase = .still(PeekDismissalFrame(offset: frame(at: time).offset, card: 0, wash: 0))
    }

    mutating func settle() {
        phase = .still(.rest)
    }

    mutating func complete(at time: TimeInterval) {
        switch phase {
        case .still, .following:
            return
        case .spring, .reappear:
            phase = .still(.rest)
        case let .slide(from, travel, _):
            phase = .still(PeekDismissalFrame(offset: from.offset + travel, card: 0, wash: 0))
        case let .fade(_, to, _, _):
            phase = .still(to)
        }
    }

    var isFollowing: Bool {
        if case .following = phase { return true }
        return false
    }

    func isAnimating(at time: TimeInterval) -> Bool {
        switch phase {
        case .still, .following:
            return false
        case let .spring(from, velocity, start):
            return !Self.springSettled(from: from, velocity: velocity, t: time - start)
        case let .reappear(from, start):
            return !Self.springSettled(from: from, velocity: 0, t: time - start)
        case let .slide(_, _, start):
            return time - start < PeekDismissalTiming.slide
        case let .fade(_, _, duration, start):
            return time - start < duration
        }
    }

    func frame(at time: TimeInterval) -> PeekDismissalFrame {
        let exit = geometry.exitDistance
        switch phase {
        case let .still(frame):
            return frame
        case let .following(fraction):
            if reducesMotion {
                return PeekDismissalFrame(offset: 0, card: 1 - PeekDismissalTiming.reducedDragFade * fraction,
                                          wash: 1 - fraction)
            }
            return PeekDismissalFrame(offset: CGFloat(fraction) * exit, card: 1, wash: 1 - fraction)
        case let .spring(from, velocity, start):
            let t = time - start
            guard !Self.springSettled(from: from, velocity: velocity, t: t) else { return .rest }
            let offset = max(0, Self.spring(from: from, velocity: velocity, t: t).position)
            return PeekDismissalFrame(offset: offset, card: 1, wash: 1 - Self.unit(Double(offset / exit)))
        case let .reappear(from, start):
            let t = time - start
            guard !Self.springSettled(from: from, velocity: 0, t: t) else { return .rest }
            let offset = max(0, Self.spring(from: from, velocity: 0, t: t).position)
            let card = Self.unit(PeekDismissalTiming.reappearFade * (1 - Double(offset / from)))
            return PeekDismissalFrame(offset: offset, card: card, wash: card)
        case let .slide(from, travel, start):
            let u = Self.unit((time - start) / PeekDismissalTiming.slide)
            let eased = 1 - (1 - u) * (1 - u)
            return PeekDismissalFrame(offset: from.offset + travel * CGFloat(eased), card: from.card * (1 - u * u),
                                      wash: from.wash * (1 - eased))
        case let .fade(from, to, duration, start):
            let u = Self.unit((time - start) / duration)
            let eased = 1 - (1 - u) * (1 - u)
            return PeekDismissalFrame(offset: from.offset + (to.offset - from.offset) * CGFloat(eased),
                                      card: from.card + (to.card - from.card) * eased,
                                      wash: from.wash + (to.wash - from.wash) * eased)
        }
    }

    private static func unit(_ value: Double) -> Double { min(max(value, 0), 1) }

    static func spring(from: CGFloat, velocity: CGFloat, t: TimeInterval) -> (position: CGFloat, velocity: CGFloat) {
        let omega = 2 * Double.pi / PeekDismissalTiming.springResponse, zeta = PeekDismissalTiming.springDamping
        let damped = omega * (1 - zeta * zeta).squareRoot(), decay = exp(-zeta * omega * t)
        let x0 = Double(from), v0 = Double(velocity)
        let cosine = cos(damped * t), sine = sin(damped * t)
        let position = decay * (x0 * cosine + (v0 + zeta * omega * x0) / damped * sine)
        let speed = decay * (v0 * cosine - (zeta * omega * v0 + omega * omega * x0) / damped * sine)
        return (CGFloat(position), CGFloat(speed))
    }

    private static func springSettled(from: CGFloat, velocity: CGFloat, t: TimeInterval) -> Bool {
        let state = spring(from: from, velocity: velocity, t: t)
        return t > 0 && abs(state.position) < 0.5 && abs(state.velocity) < 10
    }
}
