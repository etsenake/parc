import Foundation

package struct SplitStackDivider: Equatable {
    package let slot: Int?
    package let index: Int

    package init(slot: Int?, index: Int) {
        self.slot = slot
        self.index = index
    }
}

package enum SplitStackResize: Equatable {
    case divider(Int, slot: Int?, leadingShare: Double)
    case level(slot: Int?, factors: [Double])
    case slots([Double])
    case equal
}

extension BrowserSplitLayout {
    package func resized(by change: SplitStackResize) -> BrowserSplitLayout? {
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
    package var paneCount: Int { slotSizes.reduce(0, +) }

    package var slotBoundaries: [Int] {
        slotSizes.reduce(into: [0]) { boundaries, size in boundaries.append(boundaries[boundaries.count - 1] + size) }
    }

    package func place(ofPane pane: Int) -> (slot: Int, index: Int)? {
        var start = 0
        for (slot, size) in slotSizes.enumerated() {
            if pane >= start, pane < start + size { return (slot, pane - start) }
            start += size
        }
        return nil
    }

    package func divider(after pane: Int) -> SplitStackDivider? {
        guard let first = place(ofPane: pane), let second = place(ofPane: pane + 1) else { return nil }
        return first.slot == second.slot
            ? SplitStackDivider(slot: first.slot, index: first.index)
            : SplitStackDivider(slot: nil, index: first.slot)
    }

    package func factors(inSlot slot: Int?) -> [Double]? {
        guard let slot else { return slotFactors }
        return stackFactors.indices.contains(slot) ? stackFactors[slot] : nil
    }

    package func replacing(_ factors: [Double], inSlot slot: Int?) -> BrowserSplitStacks {
        var result = self
        if let slot { result.stackFactors[slot] = factors } else { result.slotFactors = factors }
        return result
    }

    package func reservingSlot(at slot: Int) -> BrowserSplitStacks {
        let share = 1 / Double(slotSizes.count + 1)
        var result = self
        result.slotFactors = slotFactors.map { $0 * (1 - share) }
        result.slotFactors.insert(share, at: slot)
        result.slotSizes.insert(1, at: slot)
        result.stackFactors.insert([1], at: slot)
        return result
    }

    package static func flat(_ factors: [Double]) -> BrowserSplitStacks {
        BrowserSplitStacks(slotSizes: factors.map { _ in 1 }, slotFactors: factors, stackFactors: factors.map { _ in [1] })
    }

    package func reservingStack(besidePane pane: Int, after: Bool) -> (stacks: BrowserSplitStacks, region: Int)? {
        guard let place = place(ofPane: pane), stackFactors.indices.contains(place.slot),
              stackFactors[place.slot].count == slotSizes[place.slot] else { return nil }
        var factors = stackFactors[place.slot]
        factors.insert(1 / Double(factors.count), at: place.index + (after ? 1 : 0))
        var result = self
        result.slotSizes[place.slot] += 1
        result.stackFactors[place.slot] = BrowserSplitLayout.settled(factors) ?? factors.map { _ in 1 / Double(factors.count) }
        return (result, pane + (after ? 1 : 0))
    }

    package var isEven: Bool {
        ([slotFactors] + stackFactors).allSatisfy { factors in
            let total = factors.reduce(0, +)
            return total > 0 && factors.allSatisfy { abs($0 / total - 1 / Double(factors.count)) < 1e-9 }
        }
    }
}

package struct SplitDividerSnapState {
    package private(set) var canSnap = false
    package private(set) var isSnapped = false

    package init(canSnap: Bool = false, isSnapped: Bool = false) {
        self.canSnap = canSnap
        self.isSnapped = isSnapped
    }
    package static func velocity(_ pan: CGPoint, movingHorizontally horizontal: Bool) -> Double {
        Double(horizontal ? pan.x : pan.y)
    }
    package mutating func update(distance: Double, velocity: Double) -> Bool {
        guard distance.isFinite, velocity.isFinite else { return false }
        let previous = isSnapped
        if abs(distance) >= 14 { canSnap = true; isSnapped = false }
        else if canSnap, !isSnapped, abs(velocity) <= 120,
                (distance < 0) == (velocity >= 0) { isSnapped = true }
        return previous != isSnapped
    }
}

package struct SplitStackGeometry {
    package static let dividerTopInset: CGFloat = 53
    package static let dividerEndInset: CGFloat = 8

    package struct Divider: Equatable {
        package let id: SplitStackDivider
        package let rect: CGRect
        package let region: CGRect
        package let isVerticalBar: Bool

        package init(id: SplitStackDivider, rect: CGRect, region: CGRect, isVerticalBar: Bool) {
            self.id = id
            self.rect = rect
            self.region = region
            self.isVerticalBar = isVerticalBar
        }
    }

    package static func lengths(_ factors: [Double], available: CGFloat, minimum: CGFloat) -> [CGFloat] {
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

    package static func fittedMinimum(count: Int, available: CGFloat, minimum: CGFloat) -> CGFloat {
        count > 1 ? min(minimum, max(0, available) / CGFloat(count)) : minimum
    }

    package static func fittedLengths(_ factors: [Double], available: CGFloat, minimum: CGFloat,
                              scale: CGFloat) -> [CGFloat] {
        guard factors.count > 1, available < minimum * CGFloat(factors.count) else {
            return lengths(factors, available: available, minimum: minimum).map { max(minimum, ($0 * scale).rounded() / scale) }
        }
        let share = (max(0, available) / CGFloat(factors.count) * scale).rounded(.down) / scale
        return factors.map { _ in share }
    }

    package static func runs(_ factors: [Double], length: CGFloat, thickness: CGFloat, minimum: CGFloat,
                     scale: CGFloat) -> [(start: CGFloat, length: CGFloat)] {
        guard factors.count > 1 else { return factors.isEmpty ? [] : [(0, length)] }
        let available = max(0, length - thickness * CGFloat(factors.count - 1))
        var position: CGFloat = 0
        return fittedLengths(factors, available: available, minimum: minimum, scale: scale).map { fitted in
            defer { position += fitted + thickness }
            return (position, fitted)
        }
    }

    package static func flatFrames(size: CGSize, orientation: SplitOrientation, factors: [Double],
                           thickness: CGFloat, minimum: CGFloat, scale: CGFloat) -> [CGRect] {
        guard !factors.isEmpty else { return [] }
        let horizontal = orientation == .horizontal
        let available = max(0, (horizontal ? size.width : size.height) - thickness * CGFloat(factors.count - 1))
        var position: CGFloat = 0
        return fittedLengths(factors, available: available, minimum: factors.count > 1 ? minimum : 0, scale: scale).map { length in
            defer { position += length + thickness }
            return aligned(horizontal ? CGRect(x: position, y: 0, width: length, height: size.height)
                                      : CGRect(x: 0, y: position, width: size.width, height: length))
        }
    }

    package static func aligned(_ frame: CGRect) -> CGRect {
        let left = frame.minX.rounded(), top = frame.minY.rounded()
        return CGRect(x: left, y: top, width: max(0, frame.maxX.rounded() - left),
                      height: max(0, frame.maxY.rounded() - top))
    }

    package static func paneFrames(size: CGSize, orientation: SplitOrientation, stacks: BrowserSplitStacks,
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

    package static func dividers(paneFrames: [CGRect], size: CGSize, orientation: SplitOrientation,
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

    package static func adjustableShares(saved: [Double], shown: [Double], available: Double,
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

    package static func resizableFactors(saved: [Double], shown: [Double], divider: Int, available: Double,
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

    package static func splitterPosition(shares: [Double], index: Int,
                                 minimum: Double) -> (value: Double, minimum: Double, maximum: Double)? {
        guard index >= 0, shares.indices.contains(index + 1) else { return nil }
        let before = shares[..<index].reduce(0, +)
        let value = before + shares[index]
        return (value, min(value, before + minimum), max(value, value + shares[index + 1] - minimum))
    }

    package static func splitterLabel(index: Int, count: Int, slot: Int?, orientation: SplitOrientation) -> String {
        let name = count > 1 ? "Split View Divider \(index + 1)" : "Split View Divider"
        guard let slot else { return name }
        return "\(name), inside \(orientation == .horizontal ? "column" : "row") \(slot + 1)"
    }
}
