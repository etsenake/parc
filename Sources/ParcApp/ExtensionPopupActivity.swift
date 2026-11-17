import CoreGraphics
import Foundation

enum ExtensionPopupActivityPhase: Equatable {
    case loading, open
}

enum ExtensionPopupLifecycle: Int {
    case revealed = 1, closing, closed
}

struct ExtensionPopupActivityChange {
    let control: AnyObject
    let phase: ExtensionPopupActivityPhase?
}

struct ExtensionPopupActivityTracker {
    private struct Retired { weak var popup: AnyObject? }
    private weak var popup: AnyObject?
    private var retired: [Retired] = []
    private weak var control: AnyObject?
    private var revealed = false

    func tracks(_ popup: AnyObject) -> Bool { self.popup === popup }

    mutating func place(popup: AnyObject, control: AnyObject?) -> [ExtensionPopupActivityChange] {
        guard !retired.contains(where: { $0.popup === popup }) else { return [] }
        if popup !== self.popup {
            if let old = self.popup { retire(old) }
            self.popup = popup
            revealed = false
        } else if control === self.control {
            return []
        }
        var changes: [ExtensionPopupActivityChange] = []
        if let old = self.control, old !== control { changes.append(.init(control: old, phase: nil)) }
        self.control = control
        if let control { changes.append(.init(control: control, phase: revealed ? .open : .loading)) }
        return changes
    }

    mutating func reveal(popup: AnyObject) -> [ExtensionPopupActivityChange] {
        guard popup === self.popup, !revealed else { return [] }
        revealed = true
        return control.map { [.init(control: $0, phase: .open)] } ?? []
    }

    mutating func end(popup: AnyObject) -> [ExtensionPopupActivityChange] {
        guard popup === self.popup else { return [] }
        retire(popup)
        self.popup = nil
        revealed = false
        let changes = control.map { [ExtensionPopupActivityChange(control: $0, phase: nil)] } ?? []
        control = nil
        return changes
    }

    private mutating func retire(_ popup: AnyObject) {
        retired.removeAll { $0.popup == nil }
        retired.append(Retired(popup: popup))
    }
}

struct ExtensionPopupBounce: Equatable {
    static let delay: CFTimeInterval = 0.18
    static let hop: CFTimeInterval = 0.5
    static let rest: CFTimeInterval = 0.2
    static let rise = 0.42
    static let height: CGFloat = 3
    static let drop: CFTimeInterval = 0.14
    static var cycle: CFTimeInterval { hop + rest }

    enum Mode: Equatable {
        case bouncing
        case landing(at: CFTimeInterval)
        case dropping(from: CGFloat, at: CFTimeInterval, resumes: Bool)
    }

    private(set) var start: CFTimeInterval
    private(set) var mode = Mode.bouncing

    init(start: CFTimeInterval) { self.start = start }

    static func lift(atHopProgress progress: Double) -> CGFloat {
        guard progress > 0, progress < 1 else { return 0 }
        if progress < rise {
            let remaining = 1 - progress / rise
            return height * CGFloat(1 - remaining * remaining)
        }
        let fall = (progress - rise) / (1 - rise)
        return height * CGFloat(1 - fall * fall * (3 - 2 * fall))
    }

    func lift(at now: CFTimeInterval) -> CGFloat {
        switch mode {
        case .bouncing:
            return cycleLift(at: now)
        case .landing(let end):
            return now < end ? cycleLift(at: now) : 0
        case let .dropping(from, at, resumes):
            let progress = (now - at) / Self.drop
            if progress < 1 {
                let eased = max(0, progress)
                return from * CGFloat(1 - eased * eased * (3 - 2 * eased))
            }
            return resumes ? cycleLift(at: now) : 0
        }
    }

    func isFinished(at now: CFTimeInterval) -> Bool {
        switch mode {
        case .bouncing: false
        case .landing(let end): now >= end
        case let .dropping(_, at, resumes): !resumes && now >= at + Self.drop
        }
    }

    func landingTime(after now: CFTimeInterval) -> CFTimeInterval {
        let elapsed = now - start - Self.delay
        guard elapsed > 0 else { return now }
        let phase = elapsed.truncatingRemainder(dividingBy: Self.cycle)
        return phase < Self.hop ? now + Self.hop - phase : now
    }

    mutating func land(at now: CFTimeInterval) {
        switch mode {
        case .bouncing:
            mode = .landing(at: landingTime(after: now))
        case .landing:
            break
        case let .dropping(from, at, resumes):
            guard resumes else { break }
            mode = now < at + Self.drop ? .dropping(from: from, at: at, resumes: false) : .landing(at: landingTime(after: now))
        }
    }

    mutating func drop(at now: CFTimeInterval) {
        if case .dropping(_, _, false) = mode { return }
        let current = lift(at: now)
        mode = current > 0 ? .dropping(from: current, at: now, resumes: false) : .landing(at: now)
    }

    mutating func resume(at now: CFTimeInterval) {
        switch mode {
        case .bouncing:
            break
        case .landing(let end):
            if now >= end { start = now }
            mode = .bouncing
        case let .dropping(from, at, _):
            if now < at + Self.drop {
                start = at + Self.drop
                mode = .dropping(from: from, at: at, resumes: true)
            } else {
                start = now
                mode = .bouncing
            }
        }
    }

    private func cycleLift(at now: CFTimeInterval) -> CGFloat {
        let elapsed = now - start - Self.delay
        guard elapsed > 0 else { return 0 }
        let phase = elapsed.truncatingRemainder(dividingBy: Self.cycle)
        return phase < Self.hop ? Self.lift(atHopProgress: phase / Self.hop) : 0
    }
}

struct ExtensionPopupActivityFade: Equatable {
    static let lighten: CFTimeInterval = 0.18
    static let dim: CFTimeInterval = 0.15

    private(set) var from: CGFloat = 0
    private(set) var target: CGFloat = 0
    private(set) var start: CFTimeInterval = -.infinity

    private var duration: CFTimeInterval { target > from ? Self.lighten : Self.dim }

    func value(at now: CFTimeInterval) -> CGFloat {
        let progress = (now - start) / duration
        guard progress < 1 else { return target }
        let time = max(0, progress)
        let eased = time < 0.5 ? 4 * time * time * time : 1 - pow(2 - 2 * time, 3) / 2
        return from + (target - from) * CGFloat(eased)
    }

    func isFinished(at now: CFTimeInterval) -> Bool { from == target || now - start >= duration }

    mutating func retarget(_ value: CGFloat, at now: CFTimeInterval) {
        guard value != target else { return }
        from = self.value(at: now)
        target = value
        start = now
    }
}

struct ExtensionPopupActivityFrame: Equatable {
    let fill: CGFloat
    let lift: CGFloat
    let finished: Bool
}

struct ExtensionPopupActivityMotion: Equatable {
    private(set) var fade = ExtensionPopupActivityFade()
    private(set) var bounce: ExtensionPopupBounce?

    mutating func show(_ phase: ExtensionPopupActivityPhase?, at now: CFTimeInterval, reduceMotion: Bool) {
        fade.retarget(phase == nil ? 0 : 1, at: now)
        switch phase {
        case .loading?:
            if reduceMotion {
                bounce = nil
            } else if var current = bounce, !current.isFinished(at: now) {
                current.resume(at: now)
                bounce = current
            } else {
                bounce = ExtensionPopupBounce(start: now)
            }
        case .open?:
            bounce?.land(at: now)
        case nil:
            bounce?.drop(at: now)
        }
    }

    func frame(at now: CFTimeInterval, reduceMotion: Bool) -> ExtensionPopupActivityFrame {
        let lift = reduceMotion ? 0 : bounce?.lift(at: now) ?? 0
        let settled = reduceMotion || bounce?.isFinished(at: now) ?? true
        return ExtensionPopupActivityFrame(fill: fade.value(at: now), lift: lift,
                                           finished: settled && fade.isFinished(at: now))
    }
}
