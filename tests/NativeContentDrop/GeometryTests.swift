import AppKit

@main @MainActor struct GeometryTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ reason: String) {
        count += 1; precondition(value(), reason)
    }
    static func expect(_ point: NSPoint, _ frames: [NSRect], _ axis: SplitOrientation,
                       _ target: SplitDropTarget, _ proposedAxis: SplitOrientation) {
        let proposal = SplitDropGeometry.proposal(at: point, frames: frames, orientation: axis)
        check(proposal?.0 == target && proposal?.1 == proposedAxis, "wrong edge/center for \(point)")
    }
    static func main() {
        let page = NSRect(x: 31, y: 76, width: 1000, height: 800)
        expect(NSPoint(x: 430, y: 476), [page], .horizontal, .insert(0), .horizontal)
        expect(NSPoint(x: 431, y: 476), [page], .horizontal, .replace(0), .horizontal)
        expect(NSPoint(x: 631, y: 476), [page], .horizontal, .replace(0), .horizontal)
        expect(NSPoint(x: 632, y: 476), [page], .horizontal, .insert(1), .horizontal)
        expect(NSPoint(x: 40, y: 125), [page], .horizontal, .insert(0), .vertical)
        expect(NSPoint(x: 531, y: 126), [page], .horizontal, .replace(0), .horizontal)
        expect(NSPoint(x: 531, y: 826), [page], .horizontal, .replace(0), .horizontal)
        expect(NSPoint(x: 1000, y: 827), [page], .horizontal, .insert(1), .vertical)
        expect(NSPoint(x: 40, y: 476), [page], .vertical, .insert(0), .horizontal)
        expect(NSPoint(x: 531, y: 80), [page], .vertical, .insert(0), .vertical)
        let small = NSRect(x: 0, y: 0, width: 120, height: 120)
        expect(NSPoint(x: 60, y: 29), [small], .horizontal, .insert(0), .vertical)
        expect(NSPoint(x: 60, y: 30), [small], .horizontal, .replace(0), .horizontal)
        let horizontal = [NSRect(x: 10, y: 40, width: 600, height: 600), NSRect(x: 617, y: 40, width: 180, height: 600)]
        expect(NSPoint(x: 89, y: 300), horizontal, .horizontal, .insert(0), .horizontal)
        expect(NSPoint(x: 90, y: 300), horizontal, .horizontal, .replace(0), .horizontal)
        expect(NSPoint(x: 530, y: 300), horizontal, .horizontal, .replace(0), .horizontal)
        expect(NSPoint(x: 531, y: 300), horizontal, .horizontal, .insert(1), .horizontal)
        expect(NSPoint(x: 676, y: 300), horizontal, .horizontal, .insert(1), .horizontal)
        expect(NSPoint(x: 677, y: 300), horizontal, .horizontal, .replace(1), .horizontal)
        expect(NSPoint(x: 737, y: 300), horizontal, .horizontal, .replace(1), .horizontal)
        expect(NSPoint(x: 738, y: 300), horizontal, .horizontal, .insert(2), .horizontal)
        let vertical = [NSRect(x: 10, y: 40, width: 600, height: 600), NSRect(x: 10, y: 647, width: 600, height: 120)]
        expect(NSPoint(x: 300, y: 89), vertical, .vertical, .insert(0), .vertical)
        expect(NSPoint(x: 300, y: 90), vertical, .vertical, .replace(0), .vertical)
        expect(NSPoint(x: 300, y: 590), vertical, .vertical, .replace(0), .vertical)
        expect(NSPoint(x: 300, y: 591), vertical, .vertical, .insert(1), .vertical)
        expect(NSPoint(x: 300, y: 686), vertical, .vertical, .insert(1), .vertical)
        expect(NSPoint(x: 300, y: 687), vertical, .vertical, .replace(1), .vertical)
        expect(NSPoint(x: 300, y: 727), vertical, .vertical, .replace(1), .vertical)
        expect(NSPoint(x: 300, y: 728), vertical, .vertical, .insert(2), .vertical)
        check(SplitDropGeometry.proposal(at: NSPoint(x: 614, y: 300), frames: horizontal, orientation: .horizontal) == nil, "divider gap is not page content")
        check(SplitDropGeometry.proposal(at: NSPoint(x: 300, y: 30), frames: horizontal, orientation: .horizontal) == nil, "header remains outside drop content")
        check(SplitDropGeometry.proposal(at: NSPoint(x: CGFloat.nan, y: 100), frames: horizontal, orientation: .horizontal) == nil, "invalid point refuses")
        var requested: [SplitDropTarget] = []
        let fallback = SplitDropGeometry.proposal(at: NSPoint(x: 20, y: 300), frames: horizontal, orientation: .horizontal,
            canPropose: { target, _ in requested.append(target); return target == .replace(0) })
        check(requested == [.insert(0), .replace(0)] && fallback?.0 == .replace(0), "capacity refusal uses exact original replacement gate")
        check(fallback?.2 == horizontal[0], "replacement preview is original content bounds")
        check(SplitDropGeometry.proposal(at: NSPoint(x: 20, y: 300), frames: horizontal, orientation: .horizontal, canPropose: { _, _ in false }) == nil, "fully unavailable target refuses")
        let trailing = SplitDropGeometry.proposal(at: NSPoint(x: 1000, y: 827), frames: [page], orientation: .horizontal)
        check(trailing?.0 == .insert(1) && trailing?.2 == page, "insertion reports the exact classified content frame, not a half-pane preview")
        let leading = SplitDropGeometry.proposal(at: NSPoint(x: 20, y: 300), frames: horizontal, orientation: .horizontal)
        check(leading?.0 == .insert(0) && leading?.2 == horizontal[0], "edge insertion keeps the original captured pane frame")
        let tracker = SplitDropTargetTracker()
        var feedback = 0, published: [SplitDropTarget?] = []
        tracker.performFeedback = { feedback += 1 }
        tracker.onChange = { published.append($0) }
        tracker.update(.insert(1), reusedRegion: false)
        check(feedback == 1 && published == [.insert(1)], "new insertion region publishes and performs generic feedback")
        tracker.update(.insert(1), reusedRegion: false)
        check(feedback == 1 && published.count == 1, "an unchanged target never repeats feedback or delegate publication")
        tracker.update(.replace(0), reusedRegion: false)
        check(feedback == 2 && published.last == .replace(0), "replacement has no drop region and performs feedback")
        tracker.update(.insert(1), reusedRegion: true)
        check(feedback == 2 && published.last == .insert(1), "returning to an existing region publishes without feedback")
        tracker.reset()
        check(feedback == 2 && published.last == .some(nil), "exit clears the proposal without feedback")
        tracker.update(nil, reusedRegion: false)
        check(published.count == 4, "no proposal is not republished")
        tracker.update(.insert(0), reusedRegion: false); tracker.reset(); tracker.reset()
        check(feedback == 3 && published.last == .some(nil) && published.count == 6, "terminal clears the target once")
        print("Split drop geometry: \(count) checks passed")
    }
}
