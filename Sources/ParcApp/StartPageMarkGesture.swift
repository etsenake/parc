import QuartzCore

struct StartPageMarkGestureRecognizer: Equatable {
    static let slop: CGFloat = 4
    static let holdDelay: TimeInterval = 0.35
    static let chargeSlop: CGFloat = 8
    static let clickRadius: CGFloat = 8
    static let clicksToSwoop = 3

    enum Press: Equatable {
        case pending(origin: CGPoint, time: TimeInterval)
        case stretching(origin: CGPoint)
        case charging(origin: CGPoint, since: TimeInterval)
        case ignored
    }

    struct Clicks: Equatable {
        var origin: CGPoint
        var count: Int
        var released: TimeInterval
    }

    var clickInterval: TimeInterval
    private(set) var press: Press?
    private(set) var clicks: Clicks?

    init(clickInterval: TimeInterval = 0.5) { self.clickInterval = clickInterval }

    var holdDeadline: TimeInterval? {
        guard case .pending(_, let time) = press else { return nil }
        return time + Self.holdDelay
    }

    mutating func pointerDown(at point: CGPoint, time: TimeInterval, idle: Bool) -> [StartPageMarkCue] {
        let chain = clicks.flatMap { time - $0.released <= clickInterval && Self.distance($0.origin, point) <= Self.clickRadius ? $0 : nil }
        guard idle else {
            clicks = nil
            press = .ignored
            return []
        }
        if let chain, chain.count + 1 >= Self.clicksToSwoop {
            clicks = nil
            press = .ignored
            return [.begin(.swoop)]
        }
        clicks = chain
        press = .pending(origin: point, time: time)
        return []
    }

    mutating func pointerDragged(to point: CGPoint, time: TimeInterval) -> [StartPageMarkCue] {
        var cues = advance(to: time)
        switch press {
        case .pending(let origin, _):
            let drag = Self.vector(from: origin, to: point)
            guard hypot(drag.dx, drag.dy) > Self.slop else { break }
            press = .stretching(origin: origin)
            clicks = nil
            cues += [.begin(.taffy), .track(TaffyStretch.pull(drag))]
        case .stretching(let origin):
            cues.append(.track(TaffyStretch.pull(Self.vector(from: origin, to: point))))
        case .charging(let origin, let since):
            guard Self.distance(origin, point) > Self.chargeSlop else { break }
            press = .ignored
            cues.append(.cancel(StartPageMarkCharge.level(held: time - since)))
        case .ignored, nil:
            break
        }
        return cues
    }

    mutating func pointerUp(at point: CGPoint, time: TimeInterval) -> [StartPageMarkCue] {
        var cues = advance(to: time)
        defer { press = nil }
        switch press {
        case .pending(let origin, _):
            guard Self.distance(origin, point) <= Self.slop else {
                clicks = nil
                break
            }
            if let chain = clicks {
                clicks = Clicks(origin: chain.origin, count: chain.count + 1, released: time)
            } else {
                clicks = Clicks(origin: origin, count: 1, released: time)
            }
        case .stretching(let origin):
            cues.append(.release(TaffyStretch.pull(Self.vector(from: origin, to: point))))
        case .charging(_, let since):
            cues.append(.discharge(StartPageMarkCharge.level(held: time - since)))
        case .ignored, nil:
            break
        }
        return cues
    }

    mutating func holdElapsed(at time: TimeInterval) -> [StartPageMarkCue] { advance(to: time) }

    mutating func reset() {
        press = nil
        clicks = nil
    }

    private mutating func advance(to time: TimeInterval) -> [StartPageMarkCue] {
        guard case .pending(let origin, let pressed) = press, time >= pressed + Self.holdDelay else { return [] }
        press = .charging(origin: origin, since: pressed + Self.holdDelay)
        clicks = nil
        return [.begin(.charge)]
    }

    private static func vector(from origin: CGPoint, to point: CGPoint) -> CGVector {
        CGVector(dx: point.x - origin.x, dy: point.y - origin.y)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }
}
