import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct ContentDropGeometryTests {
    struct Edge: CustomTestStringConvertible {
        let frames: [NSRect]
        let axis: SplitOrientation
        let point: NSPoint
        let target: SplitDropTarget
        let proposedAxis: SplitOrientation
        var testDescription: String { "\(point) \(axis) -> \(target) \(proposedAxis)" }
    }

    struct Slot: CustomTestStringConvertible {
        let frames: [NSRect]
        let axis: SplitOrientation
        let slots: [Int]?
        let point: NSPoint
        let target: SplitDropTarget
        var testDescription: String { "\(point) \(axis) \(String(describing: slots)) -> \(target)" }
    }

    struct Blocked: CustomTestStringConvertible {
        let frames: [NSRect]
        let axis: SplitOrientation
        let slots: [Int]?
        let point: NSPoint
        var testDescription: String { "\(point) \(axis) \(String(describing: slots))" }
    }

    enum Frames {
        static let page = NSRect(x: 31, y: 76, width: 1000, height: 800)
        static let small = NSRect(x: 0, y: 0, width: 120, height: 120)
        static let horizontal = [NSRect(x: 10, y: 40, width: 600, height: 600), NSRect(x: 617, y: 40, width: 180, height: 600)]
        static let vertical = [NSRect(x: 10, y: 40, width: 600, height: 600), NSRect(x: 10, y: 647, width: 600, height: 120)]
        static let short = [NSRect(x: 0, y: 0, width: 300, height: 120), NSRect(x: 306, y: 0, width: 300, height: 120)]
        static let narrow = [NSRect(x: 0, y: 0, width: 150, height: 300), NSRect(x: 0, y: 306, width: 150, height: 300)]
        static let four = (0..<4).map { NSRect(x: CGFloat($0) * 206, y: 0, width: 200, height: 400) }
        static let fourRows = (0..<4).map { NSRect(x: 0, y: CGFloat($0) * 206, width: 600, height: 200) }
        static let quad = [NSRect(x: 0, y: 0, width: 300, height: 200), NSRect(x: 0, y: 206, width: 300, height: 200),
                           NSRect(x: 306, y: 0, width: 300, height: 200), NSRect(x: 306, y: 206, width: 300, height: 200)]
        static let column = [NSRect(x: 0, y: 0, width: 400, height: 300), NSRect(x: 0, y: 306, width: 400, height: 300),
                             NSRect(x: 406, y: 0, width: 400, height: 606)]
        static let trailingColumn = [NSRect(x: 0, y: 0, width: 400, height: 606), NSRect(x: 406, y: 0, width: 400, height: 300),
                                     NSRect(x: 406, y: 306, width: 400, height: 300)]
        static let row = [NSRect(x: 0, y: 0, width: 300, height: 400), NSRect(x: 306, y: 0, width: 300, height: 400),
                          NSRect(x: 0, y: 406, width: 606, height: 400)]
        static let flat = (0..<3).map { NSRect(x: CGFloat($0) * 306, y: 0, width: 300, height: 400) }
    }

    private static func edge(_ x: CGFloat, _ y: CGFloat, _ frames: [NSRect], _ axis: SplitOrientation,
                             _ target: SplitDropTarget, _ proposedAxis: SplitOrientation) -> Edge {
        Edge(frames: frames, axis: axis, point: NSPoint(x: x, y: y), target: target, proposedAxis: proposedAxis)
    }

    private static func slot(_ x: CGFloat, _ y: CGFloat, _ frames: [NSRect], _ axis: SplitOrientation,
                             _ slots: [Int]?, _ target: SplitDropTarget) -> Slot {
        Slot(frames: frames, axis: axis, slots: slots, point: NSPoint(x: x, y: y), target: target)
    }

    private static func blocked(_ x: CGFloat, _ y: CGFloat, _ frames: [NSRect], _ axis: SplitOrientation, _ slots: [Int]? = nil) -> Blocked {
        Blocked(frames: frames, axis: axis, slots: slots, point: NSPoint(x: x, y: y))
    }

    static let singlePage: [Edge] = [
        edge(430, 476, [Frames.page], .horizontal, .insert(0), .horizontal),
        edge(431, 476, [Frames.page], .horizontal, .replace(0), .horizontal),
        edge(631, 476, [Frames.page], .horizontal, .replace(0), .horizontal),
        edge(632, 476, [Frames.page], .horizontal, .insert(1), .horizontal),
        edge(40, 125, [Frames.page], .horizontal, .insert(0), .vertical),
        edge(531, 126, [Frames.page], .horizontal, .replace(0), .horizontal),
        edge(531, 826, [Frames.page], .horizontal, .replace(0), .horizontal),
        edge(1000, 827, [Frames.page], .horizontal, .insert(1), .vertical),
        edge(40, 476, [Frames.page], .vertical, .insert(0), .horizontal),
        edge(531, 80, [Frames.page], .vertical, .insert(0), .vertical),
        edge(60, 29, [Frames.small], .horizontal, .insert(0), .vertical),
        edge(60, 30, [Frames.small], .horizontal, .replace(0), .horizontal),
    ]

    static let sideBySide: [Edge] = [
        edge(89, 300, Frames.horizontal, .horizontal, .insert(0), .horizontal),
        edge(90, 300, Frames.horizontal, .horizontal, .replace(0), .horizontal),
        edge(530, 300, Frames.horizontal, .horizontal, .replace(0), .horizontal),
        edge(531, 300, Frames.horizontal, .horizontal, .insert(1), .horizontal),
        edge(676, 300, Frames.horizontal, .horizontal, .insert(1), .horizontal),
        edge(677, 300, Frames.horizontal, .horizontal, .replace(1), .horizontal),
        edge(737, 300, Frames.horizontal, .horizontal, .replace(1), .horizontal),
        edge(738, 300, Frames.horizontal, .horizontal, .insert(2), .horizontal),
    ]

    static let topAndBottom: [Edge] = [
        edge(300, 89, Frames.vertical, .vertical, .insert(0), .vertical),
        edge(300, 90, Frames.vertical, .vertical, .replace(0), .vertical),
        edge(300, 590, Frames.vertical, .vertical, .replace(0), .vertical),
        edge(300, 591, Frames.vertical, .vertical, .insert(1), .vertical),
        edge(300, 686, Frames.vertical, .vertical, .insert(1), .vertical),
        edge(300, 687, Frames.vertical, .vertical, .replace(1), .vertical),
        edge(300, 727, Frames.vertical, .vertical, .replace(1), .vertical),
        edge(300, 728, Frames.vertical, .vertical, .insert(2), .vertical),
    ]

    static let stacks: [Slot] = [
        slot(300, 89, Frames.horizontal, .horizontal, nil, .stack(0, after: false)),
        slot(300, 90, Frames.horizontal, .horizontal, nil, .replace(0)),
        slot(300, 590, Frames.horizontal, .horizontal, nil, .replace(0)),
        slot(300, 591, Frames.horizontal, .horizontal, nil, .stack(0, after: true)),
        slot(707, 89, Frames.horizontal, .horizontal, nil, .stack(1, after: false)),
        slot(707, 90, Frames.horizontal, .horizontal, nil, .replace(1)),
        slot(707, 590, Frames.horizontal, .horizontal, nil, .replace(1)),
        slot(707, 591, Frames.horizontal, .horizontal, nil, .stack(1, after: true)),
        slot(150, 29, Frames.short, .horizontal, nil, .stack(0, after: false)),
        slot(150, 30, Frames.short, .horizontal, nil, .replace(0)),
        slot(150, 90, Frames.short, .horizontal, nil, .replace(0)),
        slot(150, 91, Frames.short, .horizontal, nil, .stack(0, after: true)),
        slot(456, 29, Frames.short, .horizontal, nil, .stack(1, after: false)),
        slot(456, 91, Frames.short, .horizontal, nil, .stack(1, after: true)),
        slot(89, 340, Frames.vertical, .vertical, nil, .stack(0, after: false)),
        slot(90, 340, Frames.vertical, .vertical, nil, .replace(0)),
        slot(530, 340, Frames.vertical, .vertical, nil, .replace(0)),
        slot(531, 340, Frames.vertical, .vertical, nil, .stack(0, after: true)),
        slot(89, 707, Frames.vertical, .vertical, nil, .stack(1, after: false)),
        slot(90, 707, Frames.vertical, .vertical, nil, .replace(1)),
        slot(530, 707, Frames.vertical, .vertical, nil, .replace(1)),
        slot(531, 707, Frames.vertical, .vertical, nil, .stack(1, after: true)),
        slot(49, 150, Frames.narrow, .vertical, nil, .stack(0, after: false)),
        slot(50, 150, Frames.narrow, .vertical, nil, .replace(0)),
        slot(100, 150, Frames.narrow, .vertical, nil, .replace(0)),
        slot(101, 150, Frames.narrow, .vertical, nil, .stack(0, after: true)),
        slot(49, 456, Frames.narrow, .vertical, nil, .stack(1, after: false)),
        slot(101, 456, Frames.narrow, .vertical, nil, .stack(1, after: true)),
    ]

    static let corners: [Slot] = [
        slot(90, 90, Frames.horizontal, .horizontal, nil, .replace(0)),
        slot(90, 90, Frames.vertical, .vertical, nil, .replace(0)),
        slot(20, 50, Frames.horizontal, .horizontal, nil, .insert(0)),
        slot(600, 630, Frames.horizontal, .horizontal, nil, .insert(1)),
        slot(790, 50, Frames.horizontal, .horizontal, nil, .insert(2)),
        slot(20, 50, Frames.vertical, .vertical, nil, .insert(0)),
        slot(600, 630, Frames.vertical, .vertical, nil, .insert(1)),
    ]

    static let fullSplits: [Slot] = [
        slot(100, 10, Frames.four, .horizontal, nil, .replace(0)),
        slot(100, 390, Frames.four, .horizontal, nil, .replace(0)),
        slot(718, 390, Frames.four, .horizontal, nil, .replace(3)),
        slot(10, 200, Frames.four, .horizontal, nil, .insert(0)),
        slot(10, 100, Frames.fourRows, .vertical, nil, .replace(0)),
        slot(590, 718, Frames.fourRows, .vertical, nil, .replace(3)),
        slot(150, 216, Frames.quad, .horizontal, [2, 2], .replace(1)),
        slot(150, 190, Frames.quad, .horizontal, [2, 2], .replace(0)),
    ]

    static let quadInsertions: [Slot] = [
        slot(295, 300, Frames.quad, .horizontal, [2, 2], .insert(2)),
        slot(310, 100, Frames.quad, .horizontal, [2, 2], .insert(2)),
        slot(600, 300, Frames.quad, .horizontal, [2, 2], .insert(4)),
    ]

    static let leadingStack: [Slot] = [
        slot(200, 49, Frames.column, .horizontal, [2, 1], .stack(0, after: false)),
        slot(200, 50, Frames.column, .horizontal, [2, 1], .replace(0)),
        slot(200, 250, Frames.column, .horizontal, [2, 1], .replace(0)),
        slot(200, 251, Frames.column, .horizontal, [2, 1], .stack(0, after: true)),
        slot(200, 355, Frames.column, .horizontal, [2, 1], .stack(1, after: false)),
        slot(200, 557, Frames.column, .horizontal, [2, 1], .stack(1, after: true)),
        slot(606, 49, Frames.column, .horizontal, [2, 1], .stack(2, after: false)),
        slot(606, 556, Frames.column, .horizontal, [2, 1], .replace(2)),
        slot(606, 557, Frames.column, .horizontal, [2, 1], .stack(2, after: true)),
        slot(5, 100, Frames.column, .horizontal, [2, 1], .insert(0)),
        slot(320, 100, Frames.column, .horizontal, [2, 1], .replace(0)),
        slot(321, 100, Frames.column, .horizontal, [2, 1], .insert(2)),
        slot(5, 400, Frames.column, .horizontal, [2, 1], .insert(0)),
        slot(395, 400, Frames.column, .horizontal, [2, 1], .insert(2)),
        slot(410, 300, Frames.column, .horizontal, [2, 1], .insert(2)),
        slot(800, 300, Frames.column, .horizontal, [2, 1], .insert(3)),
        slot(5, 10, Frames.column, .horizontal, [2, 1], .insert(0)),
        slot(395, 596, Frames.column, .horizontal, [2, 1], .insert(2)),
        slot(79, 100, Frames.column, .horizontal, [2, 1], .insert(0)),
        slot(80, 100, Frames.column, .horizontal, [2, 1], .replace(0)),
    ]

    static let trailingStack: [Slot] = [
        slot(200, 10, Frames.trailingColumn, .horizontal, [1, 2], .stack(0, after: false)),
        slot(395, 300, Frames.trailingColumn, .horizontal, [1, 2], .insert(1)),
        slot(606, 49, Frames.trailingColumn, .horizontal, [1, 2], .stack(1, after: false)),
        slot(606, 251, Frames.trailingColumn, .horizontal, [1, 2], .stack(1, after: true)),
        slot(606, 355, Frames.trailingColumn, .horizontal, [1, 2], .stack(2, after: false)),
        slot(606, 557, Frames.trailingColumn, .horizontal, [1, 2], .stack(2, after: true)),
        slot(410, 100, Frames.trailingColumn, .horizontal, [1, 2], .insert(1)),
        slot(410, 400, Frames.trailingColumn, .horizontal, [1, 2], .insert(1)),
        slot(800, 100, Frames.trailingColumn, .horizontal, [1, 2], .insert(3)),
        slot(800, 400, Frames.trailingColumn, .horizontal, [1, 2], .insert(3)),
    ]

    static let rowStack: [Slot] = [
        slot(79, 200, Frames.row, .vertical, [2, 1], .stack(0, after: false)),
        slot(80, 200, Frames.row, .vertical, [2, 1], .replace(0)),
        slot(220, 200, Frames.row, .vertical, [2, 1], .replace(0)),
        slot(221, 200, Frames.row, .vertical, [2, 1], .stack(0, after: true)),
        slot(385, 200, Frames.row, .vertical, [2, 1], .stack(1, after: false)),
        slot(527, 200, Frames.row, .vertical, [2, 1], .stack(1, after: true)),
        slot(79, 600, Frames.row, .vertical, [2, 1], .stack(2, after: false)),
        slot(527, 600, Frames.row, .vertical, [2, 1], .stack(2, after: true)),
        slot(450, 10, Frames.row, .vertical, [2, 1], .insert(0)),
        slot(450, 395, Frames.row, .vertical, [2, 1], .insert(2)),
        slot(150, 395, Frames.row, .vertical, [2, 1], .insert(2)),
        slot(300, 410, Frames.row, .vertical, [2, 1], .insert(2)),
        slot(300, 800, Frames.row, .vertical, [2, 1], .insert(3)),
        slot(10, 10, Frames.row, .vertical, [2, 1], .insert(0)),
        slot(600, 395, Frames.row, .vertical, [2, 1], .insert(2)),
        slot(150, 49, Frames.row, .vertical, [2, 1], .insert(0)),
        slot(150, 50, Frames.row, .vertical, [2, 1], .replace(0)),
        slot(150, 350, Frames.row, .vertical, [2, 1], .replace(0)),
        slot(150, 351, Frames.row, .vertical, [2, 1], .insert(2)),
    ]

    static let ignoredSlotSizes: [Slot] = columnSlots.flatMap(columnCases) + flatSlots.flatMap(flatCases)

    static let columnSlots: [[Int]?] = [nil, [2, 2], [0, 3], [3, 0], [-1, 4], []]
    static let flatSlots: [[Int]?] = [nil, [1, 1, 1]]

    static func columnCases(_ slots: [Int]?) -> [Slot] {
        [slot(395, 100, Frames.column, .horizontal, slots, .insert(1)),
         slot(5, 400, Frames.column, .horizontal, slots, .insert(1))]
    }

    static func flatCases(_ slots: [Int]?) -> [Slot] {
        [slot(310, 200, Frames.flat, .horizontal, slots, .insert(1)),
         slot(600, 200, Frames.flat, .horizontal, slots, .insert(2)),
         slot(456, 10, Frames.flat, .horizontal, slots, .stack(1, after: false))]
    }

    static let paneTargets: [Slot] = [stacks, corners, fullSplits, quadInsertions, leadingStack, trailingStack, rowStack, ignoredSlotSizes]
        .flatMap { $0 }

    static let edgeTargets: [Edge] = [singlePage, sideBySide, topAndBottom].flatMap { $0 }

    static let gaps: [Blocked] = [
        blocked(614, 300, Frames.horizontal, .horizontal),
        blocked(300, 30, Frames.horizontal, .horizontal),
        blocked(.nan, 100, Frames.horizontal, .horizontal),
        blocked(200, 303, Frames.column, .horizontal, [2, 1]),
        blocked(403, 100, Frames.column, .horizontal, [2, 1]),
        blocked(606, 303, Frames.trailingColumn, .horizontal, [1, 2]),
        blocked(303, 200, Frames.row, .vertical, [2, 1]),
        blocked(300, 403, Frames.row, .vertical, [2, 1]),
    ]

    @MainActor private func proposal(_ point: NSPoint, _ frames: [NSRect], _ axis: SplitOrientation, slots: [Int]? = nil,
                          allowsSinglePaneVertical: Bool = true,
                          allowing allow: @escaping (SplitDropTarget) -> Bool = { _ in true }) -> (requested: [SplitDropTarget], proposal: SplitDropGeometry.Proposal?) {
        var requested: [SplitDropTarget] = []
        let proposal = SplitDropGeometry.proposal(at: point, frames: frames, orientation: axis, slotSizes: slots,
                                                  allowsSinglePaneVertical: allowsSinglePaneVertical,
                                                  canPropose: { target, _ in requested.append(target); return allow(target) })
        return (requested, proposal)
    }

    @Test(arguments: edgeTargets)
    @MainActor func aPointIsClassifiedByEdgeAndCentre(_ edge: Edge) {
        let proposal = SplitDropGeometry.proposal(at: edge.point, frames: edge.frames, orientation: edge.axis)
        #expect(proposal?.0 == edge.target)
        #expect(proposal?.1 == edge.proposedAxis)
    }

    @Test(arguments: paneTargets)
    @MainActor func aPointInAPaneProposesTheExpectedTarget(_ slot: Slot) {
        let proposal = SplitDropGeometry.proposal(at: slot.point, frames: slot.frames, orientation: slot.axis, slotSizes: slot.slots)
        #expect(proposal?.0 == slot.target)
        #expect(proposal?.1 == slot.axis)
        #expect(proposal?.2 == slot.frames.first { $0.contains(slot.point) })
    }

    @Test(arguments: gaps)
    @MainActor func gapsHeadersAndInvalidPointsAreNotPageContent(_ gap: Blocked) {
        #expect(SplitDropGeometry.proposal(at: gap.point, frames: gap.frames, orientation: gap.axis, slotSizes: gap.slots) == nil)
    }

    @Test @MainActor func aRefusedInsertionFallsBackToTheExactReplacementGate() {
        let result = proposal(NSPoint(x: 20, y: 300), Frames.horizontal, .horizontal) { $0 == .replace(0) }
        #expect(result.requested == [.insert(0), .replace(0)])
        #expect(result.proposal?.0 == .replace(0))
    }

    @Test @MainActor func aReplacementPreviewIsTheOriginalContentBounds() {
        let result = proposal(NSPoint(x: 20, y: 300), Frames.horizontal, .horizontal) { $0 == .replace(0) }
        #expect(result.proposal?.2 == Frames.horizontal[0])
    }

    @Test @MainActor func aFullyUnavailableTargetRefuses() {
        #expect(proposal(NSPoint(x: 20, y: 300), Frames.horizontal, .horizontal) { _ in false }.proposal == nil)
    }

    @Test @MainActor func anInsertionReportsTheExactClassifiedContentFrame() {
        let trailing = SplitDropGeometry.proposal(at: NSPoint(x: 1000, y: 827), frames: [Frames.page], orientation: .horizontal)
        #expect(trailing?.0 == .insert(1))
        #expect(trailing?.2 == Frames.page)
    }

    @Test @MainActor func anEdgeInsertionKeepsTheOriginalCapturedPaneFrame() {
        let leading = SplitDropGeometry.proposal(at: NSPoint(x: 20, y: 300), frames: Frames.horizontal, orientation: .horizontal)
        #expect(leading?.0 == .insert(0))
        #expect(leading?.2 == Frames.horizontal[0])
    }

    @Test @MainActor func aSinglePageIgnoresSlotSizes() {
        let slotted = SplitDropGeometry.proposal(at: NSPoint(x: 40, y: 125), frames: [Frames.page], orientation: .horizontal, slotSizes: [1])
        #expect(slotted?.0 == .insert(0))
        #expect(slotted?.1 == .vertical)
        #expect(slotted?.2 == Frames.page)
    }

    @Test(arguments: [
        (CGFloat(480), SplitDropTarget.insert(0), SplitOrientation.horizontal),
        (481, .replace(0), .horizontal),
        (581, .replace(0), .horizontal),
        (582, .insert(1), .horizontal),
    ])
    @MainActor func aSinglePageWithoutVerticalKeepsItsWideBands(x: CGFloat, target: SplitDropTarget, axis: SplitOrientation) {
        let result = SplitDropGeometry.proposal(at: NSPoint(x: x, y: 100), frames: [Frames.page], orientation: .horizontal,
                                                allowsSinglePaneVertical: false)
        #expect(result?.0 == target)
        #expect(result?.1 == axis)
    }

    @Test(arguments: [
        (NSPoint(x: 20, y: 50), Frames.horizontal, SplitOrientation.horizontal, [SplitDropTarget.insert(0), .replace(0)]),
        (NSPoint(x: 600, y: 630), Frames.vertical, .vertical, [.insert(1), .replace(0)]),
    ])
    @MainActor func aRefusedCornerInsertionReplacesAndNeverStacks(point: NSPoint, frames: [NSRect], axis: SplitOrientation, asked: [SplitDropTarget]) {
        let result = proposal(point, frames, axis) { target in
            if case .insert = target { return false }
            return true
        }
        #expect(result.requested == asked)
        #expect(result.proposal?.0 == .replace(0))
        #expect(result.proposal?.2 == frames[0])
    }

    @Test(arguments: [
        (NSPoint(x: 300, y: 50), Frames.horizontal, SplitOrientation.horizontal, SplitDropTarget.stack(0, after: false)),
        (NSPoint(x: 89, y: 340), Frames.vertical, .vertical, .stack(0, after: false)),
    ])
    @MainActor func aRefusedStackReplacesTheWholePane(point: NSPoint, frames: [NSRect], axis: SplitOrientation, stack: SplitDropTarget) {
        let result = proposal(point, frames, axis) { !$0.isStack }
        #expect(result.requested == [stack, .replace(0)])
        #expect(result.proposal?.0 == .replace(0))
        #expect(result.proposal?.1 == axis)
        #expect(result.proposal?.2 == frames[0])
    }

    @Test @MainActor func aRefusedInStackInsertionReplacesItsPane() {
        let result = proposal(NSPoint(x: 79, y: 200), Frames.row, .vertical, slots: [2, 1]) { !$0.isStack }
        #expect(result.requested == [.stack(0, after: false), .replace(0)])
        #expect(result.proposal?.0 == .replace(0))
        #expect(result.proposal?.1 == .vertical)
    }

    @Test @MainActor func aRefusedStackAndReplacementRefuse() {
        #expect(proposal(NSPoint(x: 300, y: 50), Frames.horizontal, .horizontal) { _ in false }.proposal == nil)
    }

    @Test(arguments: [
        (NSPoint(x: 100, y: 10), Frames.four, SplitOrientation.horizontal),
        (NSPoint(x: 10, y: 100), Frames.fourRows, .vertical),
    ])
    @MainActor func fourPanesNeverAskForAStack(point: NSPoint, frames: [NSRect], axis: SplitOrientation) {
        #expect(proposal(point, frames, axis).requested == [.replace(0)])
    }

    @Test @MainActor func aFullStackedSplitNeverAsksForAStack() {
        #expect(proposal(NSPoint(x: 150, y: 216), Frames.quad, .horizontal, slots: [2, 2]).requested == [.replace(1)])
    }

    @Test @MainActor func theTrackerPublishesAndGivesFeedbackWhenAPreviewAppears() {
        let tracker = Tracker()
        tracker.tracker.update(.insert(1), feedback: true)
        #expect(tracker.feedback == 1)
        #expect(tracker.published == [.insert(1)])
    }

    @Test @MainActor func anUnchangedShownTargetNeverRepeatsFeedbackOrPublication() {
        let tracker = Tracker()
        tracker.tracker.update(.insert(1), feedback: true)
        tracker.tracker.update(.insert(1), feedback: false)
        #expect(tracker.feedback == 1)
        #expect(tracker.published.count == 1)
    }

    @Test @MainActor func theReplacementRingAppearingPerformsFeedback() {
        let tracker = Tracker()
        tracker.tracker.update(.insert(1), feedback: true)
        tracker.tracker.update(.replace(0), feedback: true)
        #expect(tracker.feedback == 2)
        #expect(tracker.published.last == .replace(0))
    }

    @Test @MainActor func returningToACollapsingRegionPublishesWithoutFeedback() {
        let tracker = Tracker()
        tracker.tracker.update(.insert(1), feedback: true)
        tracker.tracker.update(.replace(0), feedback: true)
        tracker.tracker.update(.insert(1), feedback: false)
        #expect(tracker.feedback == 2)
        #expect(tracker.published.last == .insert(1))
    }

    @Test @MainActor func aNewPreviewForTheSameTargetGivesFeedbackWithoutRepublishing() {
        let tracker = Tracker()
        tracker.tracker.update(.insert(1), feedback: true)
        tracker.tracker.update(.insert(1), feedback: true)
        #expect(tracker.feedback == 2)
        #expect(tracker.published.count == 1)
    }

    @Test @MainActor func exitClearsTheProposalWithoutFeedback() {
        let tracker = Tracker()
        tracker.tracker.update(.insert(1), feedback: true)
        tracker.tracker.reset()
        #expect(tracker.feedback == 1)
        #expect(tracker.published.last == .some(nil))
    }

    @Test @MainActor func noProposalIsNotRepublished() {
        let tracker = Tracker()
        tracker.tracker.update(.insert(1), feedback: true)
        tracker.tracker.reset()
        tracker.tracker.update(nil, feedback: false)
        #expect(tracker.published.count == 2)
    }

    @Test @MainActor func republishingRepeatsTheShownTargetWithoutFeedback() {
        let tracker = Tracker()
        tracker.tracker.update(.insert(1), feedback: true)
        tracker.tracker.republish()
        #expect(tracker.published == [.insert(1), .insert(1)])
        #expect(tracker.feedback == 1)
    }

    @Test @MainActor func aTerminalClearPublishesOnce() {
        let tracker = Tracker()
        tracker.tracker.update(.insert(0), feedback: true)
        tracker.tracker.reset()
        tracker.tracker.reset()
        #expect(tracker.published == [.insert(0), nil])
        #expect(tracker.feedback == 1)
    }

    @MainActor private final class Tracker {
        let tracker = SplitDropTargetTracker()
        var feedback = 0
        var published: [SplitDropTarget?] = []

        init() {
            tracker.performFeedback = { [self] in feedback += 1 }
            tracker.onChange = { [self] in published.append($0) }
        }
    }
}
