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
    static func expect(_ point: NSPoint, _ frames: [NSRect], _ axis: SplitOrientation, slots: [Int]?,
                       _ target: SplitDropTarget) {
        let proposal = SplitDropGeometry.proposal(at: point, frames: frames, orientation: axis, slotSizes: slots)
        let pane = frames.first { $0.contains(point) }
        check(proposal?.0 == target && proposal?.1 == axis && proposal?.2 == pane, "wrong split target for \(point) in \(String(describing: slots))")
    }
    static func requests(_ point: NSPoint, _ frames: [NSRect], _ axis: SplitOrientation, slots: [Int]? = nil,
                         allowing allow: (SplitDropTarget) -> Bool) -> ([SplitDropTarget], SplitDropGeometry.Proposal?) {
        var requested: [SplitDropTarget] = []
        let proposal = SplitDropGeometry.proposal(at: point, frames: frames, orientation: axis, slotSizes: slots,
            canPropose: { target, _ in requested.append(target); return allow(target) })
        return (requested, proposal)
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
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
        let slotted = SplitDropGeometry.proposal(at: NSPoint(x: 40, y: 125), frames: [page], orientation: .horizontal, slotSizes: [1])
        check(slotted?.0 == .insert(0) && slotted?.1 == .vertical && slotted?.2 == page, "a single page ignores slot sizes")
        let noVertical = { (x: CGFloat) in SplitDropGeometry.proposal(at: NSPoint(x: x, y: 100), frames: [page], orientation: .horizontal, allowsSinglePaneVertical: false) }
        check(noVertical(480)?.0 == .insert(0) && noVertical(480)?.1 == .horizontal, "single page without vertical keeps its wide leading band")
        check(noVertical(481)?.0 == .replace(0) && noVertical(581)?.0 == .replace(0), "single page without vertical keeps its centre")
        check(noVertical(582)?.0 == .insert(1) && noVertical(582)?.1 == .horizontal, "single page without vertical keeps its wide trailing band")
        expect(NSPoint(x: 300, y: 89), horizontal, .horizontal, slots: nil, .stack(0, after: false))
        expect(NSPoint(x: 300, y: 90), horizontal, .horizontal, slots: nil, .replace(0))
        expect(NSPoint(x: 300, y: 590), horizontal, .horizontal, slots: nil, .replace(0))
        expect(NSPoint(x: 300, y: 591), horizontal, .horizontal, slots: nil, .stack(0, after: true))
        expect(NSPoint(x: 707, y: 89), horizontal, .horizontal, slots: nil, .stack(1, after: false))
        expect(NSPoint(x: 707, y: 90), horizontal, .horizontal, slots: nil, .replace(1))
        expect(NSPoint(x: 707, y: 590), horizontal, .horizontal, slots: nil, .replace(1))
        expect(NSPoint(x: 707, y: 591), horizontal, .horizontal, slots: nil, .stack(1, after: true))
        let short = [NSRect(x: 0, y: 0, width: 300, height: 120), NSRect(x: 306, y: 0, width: 300, height: 120)]
        expect(NSPoint(x: 150, y: 29), short, .horizontal, slots: nil, .stack(0, after: false))
        expect(NSPoint(x: 150, y: 30), short, .horizontal, slots: nil, .replace(0))
        expect(NSPoint(x: 150, y: 90), short, .horizontal, slots: nil, .replace(0))
        expect(NSPoint(x: 150, y: 91), short, .horizontal, slots: nil, .stack(0, after: true))
        expect(NSPoint(x: 456, y: 29), short, .horizontal, slots: nil, .stack(1, after: false))
        expect(NSPoint(x: 456, y: 91), short, .horizontal, slots: nil, .stack(1, after: true))
        expect(NSPoint(x: 89, y: 340), vertical, .vertical, slots: nil, .stack(0, after: false))
        expect(NSPoint(x: 90, y: 340), vertical, .vertical, slots: nil, .replace(0))
        expect(NSPoint(x: 530, y: 340), vertical, .vertical, slots: nil, .replace(0))
        expect(NSPoint(x: 531, y: 340), vertical, .vertical, slots: nil, .stack(0, after: true))
        expect(NSPoint(x: 89, y: 707), vertical, .vertical, slots: nil, .stack(1, after: false))
        expect(NSPoint(x: 90, y: 707), vertical, .vertical, slots: nil, .replace(1))
        expect(NSPoint(x: 530, y: 707), vertical, .vertical, slots: nil, .replace(1))
        expect(NSPoint(x: 531, y: 707), vertical, .vertical, slots: nil, .stack(1, after: true))
        let narrow = [NSRect(x: 0, y: 0, width: 150, height: 300), NSRect(x: 0, y: 306, width: 150, height: 300)]
        expect(NSPoint(x: 49, y: 150), narrow, .vertical, slots: nil, .stack(0, after: false))
        expect(NSPoint(x: 50, y: 150), narrow, .vertical, slots: nil, .replace(0))
        expect(NSPoint(x: 100, y: 150), narrow, .vertical, slots: nil, .replace(0))
        expect(NSPoint(x: 101, y: 150), narrow, .vertical, slots: nil, .stack(0, after: true))
        expect(NSPoint(x: 49, y: 456), narrow, .vertical, slots: nil, .stack(1, after: false))
        expect(NSPoint(x: 101, y: 456), narrow, .vertical, slots: nil, .stack(1, after: true))
        expect(NSPoint(x: 90, y: 90), horizontal, .horizontal, slots: nil, .replace(0))
        expect(NSPoint(x: 90, y: 90), vertical, .vertical, slots: nil, .replace(0))
        expect(NSPoint(x: 20, y: 50), horizontal, .horizontal, slots: nil, .insert(0))
        expect(NSPoint(x: 600, y: 630), horizontal, .horizontal, slots: nil, .insert(1))
        expect(NSPoint(x: 790, y: 50), horizontal, .horizontal, slots: nil, .insert(2))
        expect(NSPoint(x: 20, y: 50), vertical, .vertical, slots: nil, .insert(0))
        expect(NSPoint(x: 600, y: 630), vertical, .vertical, slots: nil, .insert(1))
        let refusesInsert: (SplitDropTarget) -> Bool = { if case .insert = $0 { return false }; return true }
        let corner = requests(NSPoint(x: 20, y: 50), horizontal, .horizontal, allowing: refusesInsert)
        check(corner.0 == [.insert(0), .replace(0)] && corner.1?.0 == .replace(0) && corner.1?.2 == horizontal[0], "a refused corner insertion replaces, never stacks")
        let rowCorner = requests(NSPoint(x: 600, y: 630), vertical, .vertical, allowing: refusesInsert)
        check(rowCorner.0 == [.insert(1), .replace(0)] && rowCorner.1?.0 == .replace(0) && rowCorner.1?.1 == .vertical, "a refused top-and-bottom corner replaces, never stacks")
        let refusedStack = requests(NSPoint(x: 300, y: 50), horizontal, .horizontal) { !$0.isStack }
        check(refusedStack.0 == [.stack(0, after: false), .replace(0)] && refusedStack.1?.0 == .replace(0), "a refused stack falls back to the replacement gate")
        check(refusedStack.1?.1 == .horizontal && refusedStack.1?.2 == horizontal[0], "a refused stack previews the whole pane")
        check(requests(NSPoint(x: 300, y: 50), horizontal, .horizontal) { _ in false }.1 == nil, "a refused stack and replacement refuse")
        let four = (0..<4).map { NSRect(x: CGFloat($0) * 206, y: 0, width: 200, height: 400) }
        expect(NSPoint(x: 100, y: 10), four, .horizontal, slots: nil, .replace(0))
        expect(NSPoint(x: 100, y: 390), four, .horizontal, slots: nil, .replace(0))
        expect(NSPoint(x: 718, y: 390), four, .horizontal, slots: nil, .replace(3))
        expect(NSPoint(x: 10, y: 200), four, .horizontal, slots: nil, .insert(0))
        check(requests(NSPoint(x: 100, y: 10), four, .horizontal) { _ in true }.0 == [.replace(0)], "four side-by-side panes never ask for a stack")
        let fourRows = (0..<4).map { NSRect(x: 0, y: CGFloat($0) * 206, width: 600, height: 200) }
        expect(NSPoint(x: 10, y: 100), fourRows, .vertical, slots: nil, .replace(0))
        expect(NSPoint(x: 590, y: 718), fourRows, .vertical, slots: nil, .replace(3))
        check(requests(NSPoint(x: 10, y: 100), fourRows, .vertical) { _ in true }.0 == [.replace(0)], "four top-and-bottom panes never ask for a stack")
        let quad = [NSRect(x: 0, y: 0, width: 300, height: 200), NSRect(x: 0, y: 206, width: 300, height: 200),
                    NSRect(x: 306, y: 0, width: 300, height: 200), NSRect(x: 306, y: 206, width: 300, height: 200)]
        expect(NSPoint(x: 150, y: 216), quad, .horizontal, slots: [2, 2], .replace(1))
        expect(NSPoint(x: 150, y: 190), quad, .horizontal, slots: [2, 2], .replace(0))
        expect(NSPoint(x: 295, y: 300), quad, .horizontal, slots: [2, 2], .insert(2))
        expect(NSPoint(x: 310, y: 100), quad, .horizontal, slots: [2, 2], .insert(2))
        expect(NSPoint(x: 600, y: 300), quad, .horizontal, slots: [2, 2], .insert(4))
        check(requests(NSPoint(x: 150, y: 216), quad, .horizontal, slots: [2, 2]) { _ in true }.0 == [.replace(1)], "a full stacked split never asks for a stack")
        let column = [NSRect(x: 0, y: 0, width: 400, height: 300), NSRect(x: 0, y: 306, width: 400, height: 300),
                      NSRect(x: 406, y: 0, width: 400, height: 606)]
        expect(NSPoint(x: 200, y: 49), column, .horizontal, slots: [2, 1], .stack(0, after: false))
        expect(NSPoint(x: 200, y: 50), column, .horizontal, slots: [2, 1], .replace(0))
        expect(NSPoint(x: 200, y: 250), column, .horizontal, slots: [2, 1], .replace(0))
        expect(NSPoint(x: 200, y: 251), column, .horizontal, slots: [2, 1], .stack(0, after: true))
        expect(NSPoint(x: 200, y: 355), column, .horizontal, slots: [2, 1], .stack(1, after: false))
        expect(NSPoint(x: 200, y: 557), column, .horizontal, slots: [2, 1], .stack(1, after: true))
        expect(NSPoint(x: 606, y: 49), column, .horizontal, slots: [2, 1], .stack(2, after: false))
        expect(NSPoint(x: 606, y: 556), column, .horizontal, slots: [2, 1], .replace(2))
        expect(NSPoint(x: 606, y: 557), column, .horizontal, slots: [2, 1], .stack(2, after: true))
        expect(NSPoint(x: 5, y: 100), column, .horizontal, slots: [2, 1], .insert(0))
        expect(NSPoint(x: 320, y: 100), column, .horizontal, slots: [2, 1], .replace(0))
        expect(NSPoint(x: 321, y: 100), column, .horizontal, slots: [2, 1], .insert(2))
        expect(NSPoint(x: 5, y: 400), column, .horizontal, slots: [2, 1], .insert(0))
        expect(NSPoint(x: 395, y: 400), column, .horizontal, slots: [2, 1], .insert(2))
        expect(NSPoint(x: 410, y: 300), column, .horizontal, slots: [2, 1], .insert(2))
        expect(NSPoint(x: 800, y: 300), column, .horizontal, slots: [2, 1], .insert(3))
        check(SplitDropGeometry.proposal(at: NSPoint(x: 200, y: 303), frames: column, orientation: .horizontal, slotSizes: [2, 1]) == nil, "the gap inside a stack is not page content")
        check(SplitDropGeometry.proposal(at: NSPoint(x: 403, y: 100), frames: column, orientation: .horizontal, slotSizes: [2, 1]) == nil, "the gap beside a stack is not page content")
        let trailingColumn = [NSRect(x: 0, y: 0, width: 400, height: 606), NSRect(x: 406, y: 0, width: 400, height: 300),
                              NSRect(x: 406, y: 306, width: 400, height: 300)]
        expect(NSPoint(x: 200, y: 10), trailingColumn, .horizontal, slots: [1, 2], .stack(0, after: false))
        expect(NSPoint(x: 395, y: 300), trailingColumn, .horizontal, slots: [1, 2], .insert(1))
        expect(NSPoint(x: 606, y: 49), trailingColumn, .horizontal, slots: [1, 2], .stack(1, after: false))
        expect(NSPoint(x: 606, y: 251), trailingColumn, .horizontal, slots: [1, 2], .stack(1, after: true))
        expect(NSPoint(x: 606, y: 355), trailingColumn, .horizontal, slots: [1, 2], .stack(2, after: false))
        expect(NSPoint(x: 606, y: 557), trailingColumn, .horizontal, slots: [1, 2], .stack(2, after: true))
        expect(NSPoint(x: 410, y: 100), trailingColumn, .horizontal, slots: [1, 2], .insert(1))
        expect(NSPoint(x: 410, y: 400), trailingColumn, .horizontal, slots: [1, 2], .insert(1))
        expect(NSPoint(x: 800, y: 100), trailingColumn, .horizontal, slots: [1, 2], .insert(3))
        expect(NSPoint(x: 800, y: 400), trailingColumn, .horizontal, slots: [1, 2], .insert(3))
        check(SplitDropGeometry.proposal(at: NSPoint(x: 606, y: 303), frames: trailingColumn, orientation: .horizontal, slotSizes: [1, 2]) == nil, "the gap inside a trailing stack is not page content")
        let row = [NSRect(x: 0, y: 0, width: 300, height: 400), NSRect(x: 306, y: 0, width: 300, height: 400),
                   NSRect(x: 0, y: 406, width: 606, height: 400)]
        expect(NSPoint(x: 79, y: 200), row, .vertical, slots: [2, 1], .stack(0, after: false))
        expect(NSPoint(x: 80, y: 200), row, .vertical, slots: [2, 1], .replace(0))
        expect(NSPoint(x: 220, y: 200), row, .vertical, slots: [2, 1], .replace(0))
        expect(NSPoint(x: 221, y: 200), row, .vertical, slots: [2, 1], .stack(0, after: true))
        expect(NSPoint(x: 385, y: 200), row, .vertical, slots: [2, 1], .stack(1, after: false))
        expect(NSPoint(x: 527, y: 200), row, .vertical, slots: [2, 1], .stack(1, after: true))
        expect(NSPoint(x: 79, y: 600), row, .vertical, slots: [2, 1], .stack(2, after: false))
        expect(NSPoint(x: 527, y: 600), row, .vertical, slots: [2, 1], .stack(2, after: true))
        expect(NSPoint(x: 450, y: 10), row, .vertical, slots: [2, 1], .insert(0))
        expect(NSPoint(x: 450, y: 395), row, .vertical, slots: [2, 1], .insert(2))
        expect(NSPoint(x: 150, y: 395), row, .vertical, slots: [2, 1], .insert(2))
        expect(NSPoint(x: 300, y: 410), row, .vertical, slots: [2, 1], .insert(2))
        expect(NSPoint(x: 300, y: 800), row, .vertical, slots: [2, 1], .insert(3))
        check(SplitDropGeometry.proposal(at: NSPoint(x: 303, y: 200), frames: row, orientation: .vertical, slotSizes: [2, 1]) == nil, "the gap inside a row stack is not page content")
        check(SplitDropGeometry.proposal(at: NSPoint(x: 300, y: 403), frames: row, orientation: .vertical, slotSizes: [2, 1]) == nil, "the gap below a row stack is not page content")
        expect(NSPoint(x: 5, y: 10), column, .horizontal, slots: [2, 1], .insert(0))
        expect(NSPoint(x: 395, y: 596), column, .horizontal, slots: [2, 1], .insert(2))
        expect(NSPoint(x: 79, y: 100), column, .horizontal, slots: [2, 1], .insert(0))
        expect(NSPoint(x: 80, y: 100), column, .horizontal, slots: [2, 1], .replace(0))
        expect(NSPoint(x: 10, y: 10), row, .vertical, slots: [2, 1], .insert(0))
        expect(NSPoint(x: 600, y: 395), row, .vertical, slots: [2, 1], .insert(2))
        expect(NSPoint(x: 150, y: 49), row, .vertical, slots: [2, 1], .insert(0))
        expect(NSPoint(x: 150, y: 50), row, .vertical, slots: [2, 1], .replace(0))
        expect(NSPoint(x: 150, y: 350), row, .vertical, slots: [2, 1], .replace(0))
        expect(NSPoint(x: 150, y: 351), row, .vertical, slots: [2, 1], .insert(2))
        let refusedRowStack = requests(NSPoint(x: 89, y: 340), vertical, .vertical) { !$0.isStack }
        check(refusedRowStack.0 == [.stack(0, after: false), .replace(0)] && refusedRowStack.1?.0 == .replace(0)
              && refusedRowStack.1?.1 == .vertical && refusedRowStack.1?.2 == vertical[0], "a refused top-and-bottom stack replaces the whole pane")
        let refusedInStack = requests(NSPoint(x: 79, y: 200), row, .vertical, slots: [2, 1]) { !$0.isStack }
        check(refusedInStack.0 == [.stack(0, after: false), .replace(0)] && refusedInStack.1?.0 == .replace(0)
              && refusedInStack.1?.1 == .vertical, "a refused in-stack insertion replaces its pane")
        for slots in [nil, [2, 2], [0, 3], [3, 0], [-1, 4], []] as [[Int]?] {
            expect(NSPoint(x: 395, y: 100), column, .horizontal, slots: slots, .insert(1))
            expect(NSPoint(x: 5, y: 400), column, .horizontal, slots: slots, .insert(1))
        }
        let flat = (0..<3).map { NSRect(x: CGFloat($0) * 306, y: 0, width: 300, height: 400) }
        for slots in [nil, [1, 1, 1]] as [[Int]?] {
            expect(NSPoint(x: 310, y: 200), flat, .horizontal, slots: slots, .insert(1))
            expect(NSPoint(x: 600, y: 200), flat, .horizontal, slots: slots, .insert(2))
            expect(NSPoint(x: 456, y: 10), flat, .horizontal, slots: slots, .stack(1, after: false))
        }
        let tracker = SplitDropTargetTracker()
        var feedback = 0, published: [SplitDropTarget?] = []
        tracker.performFeedback = { feedback += 1 }
        tracker.onChange = { published.append($0) }
        tracker.update(.insert(1), feedback: true)
        check(feedback == 1 && published == [.insert(1)], "a preview appearing publishes and performs generic feedback")
        tracker.update(.insert(1), feedback: false)
        check(feedback == 1 && published.count == 1, "an unchanged shown target never repeats feedback or delegate publication")
        tracker.update(.replace(0), feedback: true)
        check(feedback == 2 && published.last == .replace(0), "the replacement ring appearing performs feedback")
        tracker.update(.insert(1), feedback: false)
        check(feedback == 2 && published.last == .insert(1), "returning to a still-collapsing region publishes without feedback")
        tracker.update(.insert(1), feedback: true)
        check(feedback == 3 && published.count == 3, "a new preview for the same target, such as a single page's other edge axis, gives feedback without republishing")
        tracker.reset()
        check(feedback == 3 && published.last == .some(nil), "exit clears the proposal without feedback")
        tracker.update(nil, feedback: false)
        check(published.count == 4, "no proposal is not republished")
        tracker.republish()
        check(published.count == 5 && published.last == .some(nil) && feedback == 3, "republishing repeats the shown target without feedback")
        tracker.update(.insert(0), feedback: true); tracker.reset(); tracker.reset()
        check(feedback == 4 && published.last == .some(nil) && published.count == 7, "terminal clears the target once")
        print("Split drop geometry: \(count) checks passed")
    }
}
