import Foundation

struct SplitDropIntent {
    struct Zone: Equatable {
        let target: SplitDropTarget
        let orientation: SplitOrientation
    }
    enum Place: Equatable {
        case pane(Zone?)
        case preview
    }
    struct Step: Equatable {
        let shown: Zone?
        let changed: Bool
        var appeared: Bool { changed && shown != nil }
    }
    private struct Sample {
        let x: Double
        let y: Double
        let time: TimeInterval
    }
    private struct Pending {
        let zone: Zone?
        var since: TimeInterval
    }

    let settleSpeed: Double
    let traversalSpeed: Double
    let dwell: TimeInterval
    let window: TimeInterval
    private(set) var shown: Zone?
    private var pending: Pending?
    private var samples: [Sample] = []

    init(settleSpeed: Double = 250, traversalSpeed: Double = 500, dwell: TimeInterval = 0.12, window: TimeInterval = 0.05) {
        self.settleSpeed = settleSpeed; self.traversalSpeed = traversalSpeed
        self.dwell = dwell; self.window = window
    }

    var isPending: Bool { pending != nil }

    var deadline: TimeInterval? {
        guard let pending, let last = samples.last else { return nil }
        return min(pending.since + dwell, last.time + window)
    }

    func dropZone(at place: Place) -> Zone? {
        if case .pane(let zone) = place { return zone }
        return shown
    }

    mutating func move(to place: Place, x: Double, y: Double, at time: TimeInterval) -> Step {
        guard x.isFinite, y.isFinite, time.isFinite else { return Step(shown: shown, changed: false) }
        record(Sample(x: x, y: y, time: time))
        guard case .pane(let zone) = place, zone != shown else {
            pending = nil
            return Step(shown: shown, changed: false)
        }
        let speed = self.speed(at: time)
        if var current = pending, current.zone == zone {
            if let speed, speed > traversalSpeed { current.since = time }
            pending = current
        } else {
            pending = Pending(zone: zone, since: time)
        }
        let settled = speed.map { $0 < settleSpeed } ?? false
        guard let since = pending?.since, settled || time - since >= dwell else {
            return Step(shown: shown, changed: false)
        }
        shown = zone; pending = nil
        return Step(shown: zone, changed: true)
    }

    mutating func leave() -> Step {
        pending = nil; samples = []
        let changed = shown != nil
        shown = nil
        return Step(shown: nil, changed: changed)
    }

    mutating func reset() {
        shown = nil; pending = nil; samples = []
    }

    private func speed(at time: TimeInterval) -> Double? {
        guard let current = samples.last, window > 0,
              let anchor = samples.last(where: { $0.time <= time - window + 1e-6 }) else { return nil }
        return hypot(current.x - anchor.x, current.y - anchor.y) / window
    }

    private mutating func record(_ sample: Sample) {
        if let last = samples.last, sample.time < last.time {
            samples.removeAll()
            if var current = pending, current.since > sample.time { current.since = sample.time; pending = current }
        }
        samples.append(sample)
        if let anchor = samples.lastIndex(where: { $0.time <= sample.time - window + 1e-6 }), anchor > 0 {
            samples.removeFirst(anchor)
        }
    }
}

extension SplitDropTarget {
    var reservesRoom: Bool {
        if case .replace = self { return false }
        return true
    }
}
