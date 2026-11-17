import Foundation

struct SplitStackDivider: Equatable {
    let slot: Int?
    let index: Int
}

enum SplitStackResize: Equatable {
    case divider(Int, slot: Int?, leadingShare: Double)
    case level(slot: Int?, factors: [Double])
    case slots([Double])
    case equal
}

extension BrowserSplitLayout {
    func resized(by change: SplitStackResize) -> BrowserSplitLayout? {
        switch change {
        case .divider(let divider, let slot, let leadingShare):
            return resizingDivider(divider, inSlot: slot, leadingShare: leadingShare)
        case .level(let slot, let factors):
            guard let slot else { return resizingSlots(factors) }
            return resizingStack(slot, factors: factors)
        case .slots(let factors): return resizingSlots(factors)
        case .equal: return equalized()
        }
    }
}

extension BrowserSplitStacks {
    var paneCount: Int { slotSizes.reduce(0, +) }

    var slotBoundaries: [Int] {
        slotSizes.reduce(into: [0]) { boundaries, size in boundaries.append(boundaries[boundaries.count - 1] + size) }
    }

    func place(ofPane pane: Int) -> (slot: Int, index: Int)? {
        var start = 0
        for (slot, size) in slotSizes.enumerated() {
            if pane >= start, pane < start + size { return (slot, pane - start) }
            start += size
        }
        return nil
    }

    func divider(after pane: Int) -> SplitStackDivider? {
        guard let first = place(ofPane: pane), let second = place(ofPane: pane + 1) else { return nil }
        return first.slot == second.slot
            ? SplitStackDivider(slot: first.slot, index: first.index)
            : SplitStackDivider(slot: nil, index: first.slot)
    }

    func factors(inSlot slot: Int?) -> [Double]? {
        guard let slot else { return slotFactors }
        return stackFactors.indices.contains(slot) ? stackFactors[slot] : nil
    }

    func replacing(_ factors: [Double], inSlot slot: Int?) -> BrowserSplitStacks {
        var result = self
        if let slot { result.stackFactors[slot] = factors } else { result.slotFactors = factors }
        return result
    }

    func reservingSlot(at slot: Int) -> BrowserSplitStacks {
        let share = 1 / Double(slotSizes.count + 1)
        var result = self
        result.slotFactors = slotFactors.map { $0 * (1 - share) }
        result.slotFactors.insert(share, at: slot)
        result.slotSizes.insert(1, at: slot)
        result.stackFactors.insert([1], at: slot)
        return result
    }

    var isEven: Bool {
        ([slotFactors] + stackFactors).allSatisfy { factors in
            let total = factors.reduce(0, +)
            return total > 0 && factors.allSatisfy { abs($0 / total - 1 / Double(factors.count)) < 1e-9 }
        }
    }
}

struct SplitStackGeometry {
    static let dividerTopInset: CGFloat = 53
    static let dividerEndInset: CGFloat = 8
    static let splitHeightMinimum: CGFloat = 382

    struct Divider: Equatable {
        let id: SplitStackDivider
        let rect: CGRect
        let region: CGRect
        let isVerticalBar: Bool
    }

    static func lengths(_ factors: [Double], available: CGFloat, minimum: CGFloat) -> [CGFloat] {
        var lengths = Array(repeating: CGFloat(0), count: factors.count)
        var remaining = available
        var pending = Array(factors.indices)
        while !pending.isEmpty {
            let weight = pending.reduce(0.0) { $0 + factors[$1] }
            let small = pending.filter { CGFloat(factors[$0] / weight) * remaining < minimum }
            if small.isEmpty {
                for index in pending { lengths[index] = CGFloat(factors[index] / weight) * remaining }
                break
            }
            for index in small { lengths[index] = minimum; remaining -= minimum }
            pending.removeAll { small.contains($0) }
        }
        return lengths
    }

    static func runs(_ factors: [Double], length: CGFloat, thickness: CGFloat, minimum: CGFloat,
                     scale: CGFloat) -> [(start: CGFloat, length: CGFloat)] {
        guard factors.count > 1 else { return factors.isEmpty ? [] : [(0, length)] }
        let available = max(0, length - thickness * CGFloat(factors.count - 1))
        var position: CGFloat = 0
        return lengths(factors, available: available, minimum: minimum).map { raw in
            let rounded = max(minimum, (raw * scale).rounded() / scale)
            defer { position += rounded + thickness }
            return (position, rounded)
        }
    }

    static func aligned(_ frame: CGRect) -> CGRect {
        let left = frame.minX.rounded(), top = frame.minY.rounded()
        return CGRect(x: left, y: top, width: max(0, frame.maxX.rounded() - left),
                      height: max(0, frame.maxY.rounded() - top))
    }

    static func paneFrames(size: CGSize, orientation: SplitOrientation, stacks: BrowserSplitStacks,
                           thickness: CGFloat, minimum: CGFloat, scale: CGFloat) -> [CGRect] {
        let horizontal = orientation == .horizontal
        let slots = runs(stacks.slotFactors, length: horizontal ? size.width : size.height,
                         thickness: thickness, minimum: minimum, scale: scale)
        var frames: [CGRect] = []
        for (slot, run) in slots.enumerated() {
            let panes = runs(stacks.stackFactors[slot], length: horizontal ? size.height : size.width,
                             thickness: thickness, minimum: minimum, scale: scale)
            for pane in panes {
                frames.append(aligned(horizontal
                    ? CGRect(x: run.start, y: pane.start, width: run.length, height: pane.length)
                    : CGRect(x: pane.start, y: run.start, width: pane.length, height: run.length)))
            }
        }
        return frames
    }

    static func dividers(paneFrames: [CGRect], size: CGSize, orientation: SplitOrientation,
                         stacks: BrowserSplitStacks, thickness: CGFloat) -> [Divider] {
        guard paneFrames.count == stacks.paneCount else { return [] }
        let horizontal = orientation == .horizontal
        return paneFrames.indices.dropLast().compactMap { pane in
            guard let id = stacks.divider(after: pane) else { return nil }
            let frame = paneFrames[pane]
            let verticalBar = (id.slot == nil) == horizontal
            let rect: CGRect
            switch (id.slot == nil, horizontal) {
            case (true, true): rect = CGRect(x: frame.maxX, y: 0, width: thickness, height: size.height)
            case (true, false): rect = CGRect(x: 0, y: frame.maxY, width: size.width, height: thickness)
            case (false, true): rect = CGRect(x: frame.minX, y: frame.maxY, width: frame.width, height: thickness)
            case (false, false): rect = CGRect(x: frame.maxX, y: frame.minY, width: thickness, height: frame.height)
            }
            let region = verticalBar
                ? CGRect(x: rect.minX, y: rect.minY + dividerTopInset,
                         width: rect.width, height: max(0, rect.height - dividerTopInset))
                : CGRect(x: rect.minX + dividerEndInset, y: rect.minY,
                         width: max(0, rect.width - 2 * dividerEndInset), height: rect.height)
            return Divider(id: id, rect: rect, region: region, isVerticalBar: verticalBar)
        }
    }

    static func minimumSize(orientation: SplitOrientation, slotSizes: [Int], minimum: CGFloat,
                            thickness: CGFloat) -> CGSize {
        func run(_ count: Int) -> CGFloat { minimum * CGFloat(count) + thickness * CGFloat(max(0, count - 1)) }
        let main = run(slotSizes.count)
        let cross = slotSizes.map(run).max() ?? 0
        return orientation == .horizontal
            ? CGSize(width: main, height: max(splitHeightMinimum, cross))
            : CGSize(width: cross, height: max(splitHeightMinimum, main))
    }

    static func adjustableShares(saved: [Double], shown: [Double], available: Double,
                                 minimum: Double) -> (shares: [Double], minimum: Double)? {
        guard available.isFinite, available > 0 else { return nil }
        if let settled = BrowserSplitLayout.normalized(saved, count: saved.count),
           settled.allSatisfy({ $0 * available >= minimum - 0.5 }) {
            return (settled, minimum / available)
        }
        let total = shown.reduce(0, +)
        guard total.isFinite, total > 0, let visible = BrowserSplitLayout.normalized(shown, count: shown.count) else { return nil }
        return (visible, minimum / total)
    }

    static func resizableFactors(saved: [Double], shown: [Double], divider: Int, available: Double,
                                 minimum: Double) -> [Double]? {
        guard saved.indices.contains(divider + 1), divider >= 0, shown.count == saved.count,
              let factors = BrowserSplitLayout.normalized(saved, count: saved.count) else { return nil }
        guard (factors[divider] + factors[divider + 1]) * available < 2 * minimum else { return factors }
        var lengths = shown
        let pair = lengths[divider] + lengths[divider + 1]
        let room = available - (lengths.reduce(0, +) - pair)
        guard pair > 2 * minimum, room > 2 * minimum else { return factors }
        lengths[divider] *= room / pair; lengths[divider + 1] *= room / pair
        return BrowserSplitLayout.normalized(lengths, count: lengths.count) ?? factors
    }

    static func splitterPosition(shares: [Double], index: Int,
                                 minimum: Double) -> (value: Double, minimum: Double, maximum: Double)? {
        guard index >= 0, shares.indices.contains(index + 1) else { return nil }
        let before = shares[..<index].reduce(0, +)
        let value = before + shares[index]
        return (value, before + minimum, value + shares[index + 1] - minimum)
    }

    static func splitterLabel(index: Int, count: Int, slot: Int?, orientation: SplitOrientation) -> String {
        let name = count > 1 ? "Split View Divider \(index + 1)" : "Split View Divider"
        guard let slot else { return name }
        return "\(name), inside \(orientation == .horizontal ? "column" : "row") \(slot + 1)"
    }
}
