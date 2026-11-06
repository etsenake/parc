import AppKit

///
/// The original window's admission callback remains the placement authority.
@MainActor
enum SplitDropGeometry {
    typealias Proposal = (SplitDropTarget, SplitOrientation, NSRect)

    static func proposal(at point: NSPoint, frames: [NSRect], orientation: SplitOrientation,
                         allowsSinglePaneVertical: Bool = true,
                         canPropose: (SplitDropTarget, SplitOrientation) -> Bool = { _, _ in true }) -> Proposal? {
        guard point.x.isFinite, point.y.isFinite,
              let index = frames.firstIndex(where: { $0.contains(point) }) else { return nil }
        let rect = frames[index]
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else { return nil }
        let x = point.x - rect.minX, y = point.y - rect.minY
        let single = frames.count == 1
        var insertion: (before: Bool, axis: SplitOrientation)?

        // The original unflipped classifier checks vertical edges first when a
        // single pane permits either axis. Exact threshold equality is center.
        if single && allowsSinglePaneVertical {
            let vertical = min(rect.height * 0.25, 50)
            if y < vertical { insertion = (true, .vertical) }
            else if y > rect.height - vertical { insertion = (false, .vertical) }
            else if x < rect.width * 0.4 { insertion = (true, .horizontal) }
            else if x > rect.width * 0.6 { insertion = (false, .horizontal) }
        } else if single || orientation == .horizontal {
            let horizontal = single ? rect.width * 0.45 : min(rect.width / 3, 80)
            if x < horizontal { insertion = (true, .horizontal) }
            else if x > rect.width - horizontal { insertion = (false, .horizontal) }
        } else {
            let vertical = min(rect.height / 3, 50)
            if y < vertical { insertion = (true, .vertical) }
            else if y > rect.height - vertical { insertion = (false, .vertical) }
        }

        if let insertion {
            let target = SplitDropTarget.insert(index + (insertion.before ? 0 : 1))
            if canPropose(target, insertion.axis) {
                // The classified pane's exact captured frame, header included.
                //
                return (target, insertion.axis, rect)
            }
        }
        // The native proposal owner asks replacement permission when edge
        // insertion is refused; an unavailable insertion is not a dead region.
        return canPropose(.replace(index), orientation) ? (.replace(index), orientation, rect) : nil
    }
}

///
///
/// which publishes a replacement pane as `proposedWindowContentDropTarget`)
/// and, when the new proposal has no drop region already at its slot, performs
/// generic haptic feedback (`isDragDropHapticFeedbackEnabled` defaults to true).
@MainActor
final class SplitDropTargetTracker {
    private(set) var target: SplitDropTarget?
    var onChange: ((SplitDropTarget?) -> Void)?
    var performFeedback: () -> Void = {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    func update(_ next: SplitDropTarget?, reusedRegion: Bool) {
        guard next != target else { return }
        target = next
        onChange?(next)
        if next != nil, !reusedRegion { performFeedback() }
    }
    ///
    /// proposal without feedback. The interactive pane edit itself (delegate
    /// slots 6/7) is `ParcSplitView.InteractivePaneEdit`.
    func reset() { update(nil, reusedRegion: true) }
}
