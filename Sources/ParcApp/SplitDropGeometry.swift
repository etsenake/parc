import AppKit
import ParcCore

@MainActor
enum SplitDropGeometry {
    typealias Proposal = (SplitDropTarget, SplitOrientation, NSRect)

    static func proposal(at point: NSPoint, frames: [NSRect], orientation: SplitOrientation,
                         slotSizes: [Int]? = nil,
                         allowsSinglePaneVertical: Bool = true,
                         canPropose: (SplitDropTarget, SplitOrientation) -> Bool = { _, _ in true }) -> Proposal? {
        guard point.x.isFinite, point.y.isFinite,
              let index = frames.firstIndex(where: { $0.contains(point) }) else { return nil }
        let rect = frames[index]
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else { return nil }
        let x = point.x - rect.minX, y = point.y - rect.minY
        var insertion: (target: SplitDropTarget, axis: SplitOrientation)?

        if frames.count == 1 {
            if allowsSinglePaneVertical {
                let vertical = min(rect.height * 0.25, 50)
                if y < vertical { insertion = (.insert(0), .vertical) }
                else if y > rect.height - vertical { insertion = (.insert(1), .vertical) }
                else if x < rect.width * 0.4 { insertion = (.insert(0), .horizontal) }
                else if x > rect.width * 0.6 { insertion = (.insert(1), .horizontal) }
            } else {
                let horizontal = rect.width * 0.45
                if x < horizontal { insertion = (.insert(0), .horizontal) }
                else if x > rect.width - horizontal { insertion = (.insert(1), .horizontal) }
            }
        } else {
            let slot = slotRange(of: index, slotSizes: slotSizes, count: frames.count)
            let horizontal = orientation == .horizontal
            let along = horizontal ? x : y, alongLength = horizontal ? rect.width : rect.height
            let across = horizontal ? y : x, acrossLength = horizontal ? rect.height : rect.width
            let mainBand = horizontal ? min(rect.width / 3, 80) : min(rect.height / 3, 50)
            let crossBand = horizontal ? min(rect.height * 0.25, 50) : min(rect.width / 3, 80)
            if along < mainBand { insertion = (.insert(slot.lowerBound), orientation) }
            else if along > alongLength - mainBand { insertion = (.insert(slot.upperBound), orientation) }
            else if frames.count < 4, across < crossBand { insertion = (.stack(index, after: false), orientation) }
            else if frames.count < 4, across > acrossLength - crossBand { insertion = (.stack(index, after: true), orientation) }
        }

        if let insertion, canPropose(insertion.target, insertion.axis) {
            return (insertion.target, insertion.axis, rect)
        }
        return canPropose(.replace(index), orientation) ? (.replace(index), orientation, rect) : nil
    }

    private static func slotRange(of index: Int, slotSizes: [Int]?, count: Int) -> Range<Int> {
        guard let slotSizes, slotSizes.allSatisfy({ $0 > 0 }), slotSizes.reduce(0, +) == count else { return index..<index + 1 }
        var start = 0
        for size in slotSizes {
            if index < start + size { return start..<start + size }
            start += size
        }
        return index..<index + 1
    }
}

@MainActor
final class SplitDropTargetTracker {
    private(set) var target: SplitDropTarget?
    var onChange: ((SplitDropTarget?) -> Void)?
    var performFeedback: () -> Void = {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    func update(_ next: SplitDropTarget?, feedback: Bool) {
        if next != target { target = next; onChange?(next) }
        if feedback { performFeedback() }
    }
    func republish() { onChange?(target) }
    func reset() { update(nil, feedback: false) }
}
