import Foundation

package enum SplitPaneResize {
    package static let step = 0.1
    package static let snapTolerance = 0.01

    package static func movingDivider(_ divider: Int, in shares: [Double], forward: Bool, minimum: Double) -> [Double]? {
        guard isValid(shares, minimum: minimum),
              shares.indices.contains(divider), shares.indices.contains(divider + 1) else { return nil }
        let pair = shares[divider] + shares[divider + 1]
        guard pair >= 2 * minimum else { return nil }
        let first = stepped(shares[divider], forward: forward, center: pair / 2, lower: minimum, upper: pair - minimum)
        guard forward ? first > shares[divider] + 1e-9 : first < shares[divider] - 1e-9 else { return nil }
        var next = shares
        next[divider] = first
        next[divider + 1] = pair - first
        return BrowserSplitLayout.normalized(next, count: next.count)
    }

    package static func resizingPane(_ index: Int, in shares: [Double], growing: Bool, minimum: Double) -> [Double]? {
        guard isValid(shares, minimum: minimum), shares.indices.contains(index) else { return nil }
        let current = shares[index], center = 1 / Double(shares.count)
        let others = shares.indices.filter { $0 != index }
        var next = shares
        if growing {
            let room = others.map { max(0, shares[$0] - minimum) }
            let available = room.reduce(0, +)
            let amount = stepped(current, forward: true, center: center, lower: minimum, upper: current + available) - current
            guard amount > 1e-9, available > 0 else { return nil }
            for (offset, other) in others.enumerated() { next[other] -= amount * room[offset] / available }
            next[index] = current + amount
        } else {
            let amount = current - stepped(current, forward: false, center: center, lower: minimum, upper: 1)
            let weight = others.reduce(0) { $0 + shares[$1] }
            guard amount > 1e-9, weight > 0 else { return nil }
            for other in others { next[other] += amount * shares[other] / weight }
            next[index] = current - amount
        }
        return BrowserSplitLayout.normalized(next, count: next.count)
    }

    package static func equal(count: Int) -> [Double]? {
        BrowserSplitLayout.normalized(Array(repeating: 1, count: count), count: count)
    }

    package static func isEqual(_ factors: [Double]) -> Bool {
        guard let shares = BrowserSplitLayout.normalized(factors, count: factors.count) else { return false }
        return shares.allSatisfy { abs($0 - 1 / Double(shares.count)) < 1e-9 }
    }

    private static func isValid(_ shares: [Double], minimum: Double) -> Bool {
        guard (2...4).contains(shares.count), shares.allSatisfy({ $0.isFinite && $0 > 0 }),
              abs(shares.reduce(0, +) - 1) < 1e-6, minimum.isFinite, minimum >= 0 else { return false }
        return minimum * Double(shares.count) <= 1 + 1e-9
    }

    private static func stepped(_ value: Double, forward: Bool, center: Double, lower: Double, upper: Double) -> Double {
        let start = abs(value - center) <= snapTolerance ? center : value
        var next = start + (forward ? step : -step)
        if (start < center && next > center) || (start > center && next < center) { next = center }
        return min(max(next, lower), upper)
    }
}
