import AppKit
@testable import Parc
import ParcCore

@MainActor final class StackDrop {
    struct Motion { var from: [NSRect]; var to: [NSRect]; var start: Double }
    struct Region { var frame: NSRect; var opacity: CGFloat }
    struct RegionMotion { var from: Region; var to: Region; var start: Double; var removing: Bool }

    static let duration = 0.2
    static let minimum: CGFloat = 220

    let split: ParcSplitView
    let panes: [NSView]
    let stacks: BrowserSplitStacks
    let orientation: SplitOrientation
    let canPropose: (SplitDropTarget, SplitOrientation) -> Bool
    let original: [NSRect]
    private(set) var target: SplitDropTarget?
    private(set) var intent = SplitDropIntent()
    private(set) var appeared: Double?
    private var lastPoint: NSPoint?
    private var lastPlace: String?
    private var hostFrames: [NSRect]
    private var model: [NSRect]
    private var slot: NSRect?
    private var motion: Motion?
    private var regionMotion: RegionMotion?
    var log: [String] = []

    init(split: ParcSplitView, stacks: BrowserSplitStacks, orientation: SplitOrientation,
         canPropose: @escaping (SplitDropTarget, SplitOrientation) -> Bool) {
        self.split = split; self.stacks = stacks; self.orientation = orientation; self.canPropose = canPropose
        panes = split.arrangedSubviews
        original = panes.map(\.frame)
        model = original; hostFrames = original
    }

    var reserving: Bool { target != nil }

    var replace: Int? {
        if case .replace(let index)? = intent.shown?.target { return index }
        return nil
    }

    var incomingPaneSize: NSSize {
        let bounds = split.bounds
        guard case .stack(let pane, _)? = target, original.indices.contains(pane) else {
            return NSSize(width: bounds.width / CGFloat(stacks.slotSizes.count + 1), height: bounds.height)
        }
        let count = CGFloat(stacks.place(ofPane: pane).map { stacks.slotSizes[$0.slot] } ?? 1) + 1
        return orientation == .horizontal
            ? NSSize(width: original[pane].width, height: bounds.height / count)
            : NSSize(width: bounds.width / count, height: original[pane].height)
    }

    func update(at point: NSPoint, _ t: Double) {
        if let lastPoint {
            for _ in 0..<4 {
                guard let deadline = intent.deadline, deadline < t - 1e-9 else { break }
                evaluate(at: lastPoint, deadline)
                if let next = intent.deadline, next <= deadline { break }
            }
        }
        evaluate(at: point, t)
        lastPoint = point
    }

    private func evaluate(at point: NSPoint, _ t: Double) {
        let place: SplitDropIntent.Place
        if let target, let slot, slot.contains(point), canPropose(target, orientation) {
            place = .preview
        } else if hostFrames.contains(where: { $0.contains(point) }) {
            let proposed = SplitDropGeometry.proposal(at: point, frames: hostFrames, orientation: orientation,
                                                      slotSizes: stacks.slotSizes, canPropose: canPropose)
            place = .pane(proposed.map { SplitDropIntent.Zone(target: $0.0, orientation: $0.1) })
        } else if let shown = intent.shown, !canPropose(shown.target, shown.orientation) {
            place = .pane(nil)
        } else {
            place = .preview
        }
        let label: String
        switch place {
        case .pane(let zone): label = zone.map { "\($0.target)" } ?? "nothing"
        case .preview: label = target == nil ? "gap" : "seat"
        }
        if label != lastPlace { note(t, "over \(label)"); lastPlace = label }
        let step = intent.move(to: place, x: Double(point.x), y: Double(point.y), at: t)
        guard step.changed else { return }
        if step.appeared { appeared = t }
        if let zone = step.shown, zone.target.reservesRoom { open(zone.target, t) }
        else {
            clear(t)
            if case .replace(let index)? = step.shown?.target { note(t, "replace \(index)") }
        }
    }

    private func open(_ next: SplitDropTarget, _ t: Double) {
        guard target != next, let collapsed = collapsedFrame(next), let reserved = reservedFrames(next) else { return }
        let positions = presentedPanes(t)
        let visible = presentedRegion(t)
        target = next
        model = reserved.panes
        slot = reserved.slot
        hostFrames = model
        motion = Motion(from: positions, to: model, start: t)
        regionMotion = RegionMotion(from: visible ?? Region(frame: collapsed, opacity: 0), to: Region(frame: reserved.slot, opacity: 1),
                                    start: t, removing: false)
        note(t, "reserve \(next) slot \(NSStringFromRect(reserved.slot))")
    }

    func clear(_ t: Double) {
        guard let previous = target else { return }
        let positions = presentedPanes(t)
        let border = presentedRegion(t)
        target = nil
        model = original
        hostFrames = model
        slot = nil
        motion = Motion(from: positions, to: model, start: t)
        if let border, let collapsed = collapsedFrame(previous) {
            regionMotion = RegionMotion(from: border, to: Region(frame: collapsed, opacity: 0), start: t, removing: true)
        } else { regionMotion = nil }
        note(t, "clear \(previous)")
    }

    func leave(_ t: Double) {
        _ = intent.leave()
        lastPoint = nil; lastPlace = nil
        clear(t)
    }

    func finish() {
        intent.reset()
        lastPoint = nil
        motion = nil; regionMotion = nil; target = nil; slot = nil
    }

    func presentedPanes(_ t: Double) -> [NSRect] {
        guard let motion else { return model }
        let u = CGFloat(easeOut((t - motion.start) / Self.duration))
        return zip(motion.from, motion.to).map { lerp($0, $1, u) }
    }

    func presentedRegion(_ t: Double) -> Region? {
        guard let regionMotion else { return nil }
        let raw = (t - regionMotion.start) / Self.duration
        if regionMotion.removing && raw >= 1 { return nil }
        let u = CGFloat(easeOut(raw))
        return Region(frame: lerp(regionMotion.from.frame, regionMotion.to.frame, u),
                      opacity: regionMotion.from.opacity + (regionMotion.to.opacity - regionMotion.from.opacity) * u)
    }

    private func reservedFrames(_ target: SplitDropTarget) -> (panes: [NSRect], slot: NSRect)? {
        var shape = stacks
        let regionIndex: Int
        switch target {
        case .insert(let index):
            let boundaries = stacks.slotBoundaries
            let slot = boundaries.lastIndex { $0 <= index } ?? 0
            shape = stacks.reservingSlot(at: slot)
            regionIndex = boundaries[slot]
        case .stack(let pane, let after):
            guard let reserved = stacks.reservingStack(besidePane: pane, after: after) else { return nil }
            shape = reserved.stacks
            regionIndex = reserved.region
        case .replace:
            return nil
        }
        var frames = SplitStackGeometry.paneFrames(size: split.bounds.size, orientation: orientation, stacks: shape,
                                                   thickness: split.dividerThickness, minimum: Self.minimum, scale: 1)
        guard frames.count == panes.count + 1 else { return nil }
        let slot = frames.remove(at: regionIndex)
        return (frames, slot)
    }

    private func collapsedFrame(_ target: SplitDropTarget) -> NSRect? {
        let horizontal = orientation == .horizontal
        switch target {
        case .insert(let index):
            guard index >= 0, index <= model.count else { return nil }
            let edge: CGFloat
            if index == 0 { edge = 0 }
            else if index >= model.count { edge = horizontal ? model.last!.maxX : model.last!.maxY }
            else { edge = horizontal ? model[index].minX : model[index].minY }
            return horizontal ? NSRect(x: edge, y: 0, width: 0, height: split.bounds.height)
                              : NSRect(x: 0, y: edge, width: split.bounds.width, height: 0)
        case .stack(let pane, let after):
            guard model.indices.contains(pane) else { return nil }
            let frame = model[pane]
            return horizontal ? NSRect(x: frame.minX, y: after ? frame.maxY : frame.minY, width: frame.width, height: 0)
                              : NSRect(x: after ? frame.maxX : frame.minX, y: frame.minY, width: 0, height: frame.height)
        case .replace:
            return nil
        }
    }

    private func note(_ t: Double, _ text: String) {
        let line = String(format: "%.3f ", t) + text
        if log.last.map({ String($0.dropFirst(6)) }) != text { log.append(line) }
    }
}

func lerp(_ a: NSRect, _ b: NSRect, _ u: CGFloat) -> NSRect {
    NSRect(x: a.minX + (b.minX - a.minX) * u, y: a.minY + (b.minY - a.minY) * u,
           width: a.width + (b.width - a.width) * u, height: a.height + (b.height - a.height) * u)
}
