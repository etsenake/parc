import Foundation

struct EaselCountdown: Equatable {
    enum Phase: Equatable { case idle, running, paused, finished }

    static let maximum: TimeInterval = 99 * 60 + 59
    static let defaultDuration: TimeInterval = 5 * 60

    private(set) var phase: Phase = .idle
    private(set) var duration: TimeInterval = defaultDuration
    private var remainingAtPause: TimeInterval = defaultDuration
    private var endsAt: Date?

    func remaining(at now: Date) -> TimeInterval {
        switch phase {
        case .idle: return duration
        case .paused: return remainingAtPause
        case .finished: return 0
        case .running: return max(0, (endsAt ?? now).timeIntervalSince(now))
        }
    }

    func isDue(at now: Date) -> Bool { phase == .running && remaining(at: now) <= 0 }

    mutating func set(minutes: Int) {
        guard phase == .idle || phase == .finished else { return }
        duration = Self.clamped(TimeInterval(max(0, minutes) * 60))
        remainingAtPause = duration
        endsAt = nil
        phase = .idle
    }

    mutating func adjust(minutes: Int, at now: Date) {
        switch phase {
        case .idle, .finished:
            let base = phase == .finished ? 0 : duration
            let next = Self.clamped(Self.snapped(base, minutes: minutes))
            duration = next
            remainingAtPause = next
            phase = .idle
        case .running, .paused:
            guard minutes > 0 else { return }
            addTime(TimeInterval(minutes * 60), at: now)
        }
    }

    mutating func addMinute(at now: Date) {
        switch phase {
        case .running, .paused: addTime(60, at: now)
        case .idle, .finished: adjust(minutes: 1, at: now)
        }
    }

    mutating func start(at now: Date) {
        switch phase {
        case .idle:
            guard duration > 0 else { return }
            endsAt = now.addingTimeInterval(duration)
            phase = .running
        case .paused: resume(at: now)
        case .finished:
            guard duration > 0 else { return }
            endsAt = now.addingTimeInterval(duration)
            phase = .running
        case .running: break
        }
    }

    mutating func pause(at now: Date) {
        guard phase == .running else { return }
        remainingAtPause = remaining(at: now)
        endsAt = nil
        phase = remainingAtPause > 0 ? .paused : .finished
    }

    mutating func resume(at now: Date) {
        guard phase == .paused else { return }
        endsAt = now.addingTimeInterval(remainingAtPause)
        phase = .running
    }

    mutating func toggle(at now: Date) {
        phase == .running ? pause(at: now) : start(at: now)
    }

    mutating func finish() {
        guard phase == .running else { return }
        endsAt = nil
        remainingAtPause = 0
        phase = .finished
    }

    mutating func reset() {
        phase = .idle
        endsAt = nil
        remainingAtPause = duration
    }

    static func label(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, min(maximum, seconds.rounded(.up))))
        return String(format: "%02d:%02d", whole / 60, whole % 60)
    }

    static func spoken(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, min(maximum, seconds.rounded(.up))))
        let minutes = whole / 60, rest = whole % 60
        let minuteText = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        let secondText = rest == 1 ? "1 second" : "\(rest) seconds"
        if minutes == 0 { return secondText }
        return rest == 0 ? minuteText : minuteText + " " + secondText
    }

    private mutating func addTime(_ seconds: TimeInterval, at now: Date) {
        switch phase {
        case .running:
            let next = min(Self.maximum, remaining(at: now) + seconds)
            endsAt = now.addingTimeInterval(next)
        case .paused:
            remainingAtPause = min(Self.maximum, remainingAtPause + seconds)
        case .idle, .finished:
            break
        }
    }

    private static func snapped(_ value: TimeInterval, minutes: Int) -> TimeInterval {
        let whole = (value / 60).rounded(minutes >= 0 ? .down : .up)
        return (whole + Double(minutes)) * 60
    }

    private static func clamped(_ value: TimeInterval) -> TimeInterval {
        min(maximum, max(0, value))
    }
}
