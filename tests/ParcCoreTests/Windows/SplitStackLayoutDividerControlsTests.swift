import Foundation
import Testing
@testable import ParcCore

struct SplitStackLayoutDividerControlsTests {
    struct LabelCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let index: Int
        let count: Int
        let slot: Int?
        let expected: String
        let orientation: SplitOrientation
    }

    @Test(arguments: [
        LabelCase(testDescription: "First divider in a column", index: 0, count: 2, slot: 0,
                  expected: "Split View Divider 1, inside column 1", orientation: .horizontal),
        LabelCase(testDescription: "Second divider in a column", index: 1, count: 3, slot: 0,
                  expected: "Split View Divider 2, inside column 1", orientation: .horizontal),
        LabelCase(testDescription: "Divider inside a row", index: 1, count: 2, slot: 1,
                  expected: "Split View Divider 2, inside row 2", orientation: .vertical),
        LabelCase(testDescription: "Main row divider", index: 1, count: 2, slot: nil,
                  expected: "Split View Divider 2", orientation: .horizontal),
        LabelCase(testDescription: "Only one divider", index: 0, count: 1, slot: nil,
                  expected: "Split View Divider", orientation: .horizontal),
    ])
    func splittersAreLabelledWithTheirReadingOrderNumberAndContainer(_ label: LabelCase) {
        #expect(SplitStackGeometry.splitterLabel(
            index: label.index, count: label.count, slot: label.slot, orientation: label.orientation
        ) == label.expected)
    }

    @Test func aStackSplitterReportsItsShareWithinItsSlotBoundedByTheMinimumOnEachSide() throws {
        let pair = try #require(SplitStackGeometry.splitterPosition(shares: [0.25, 0.75], index: 0, minimum: 0.2))
        #expect(SplitStackLayoutTestsSupport.close([pair.value, pair.minimum, pair.maximum], [0.25, 0.2, 0.8]))
    }

    @Test func aLaterSplitterCountsThePanesBeforeIt() throws {
        let middle = try #require(SplitStackGeometry.splitterPosition(shares: [0.25, 0.25, 0.5], index: 1, minimum: 0.2))
        #expect(SplitStackLayoutTestsSupport.close([middle.value, middle.minimum, middle.maximum], [0.5, 0.45, 0.8]))
    }

    @Test func aSplitterPastTheLastPairHasNoValue() {
        #expect(SplitStackGeometry.splitterPosition(shares: [0.5, 0.5], index: 1, minimum: 0.2) == nil)
    }

    @Test func validSavedStackSharesMeasureAgainstTheSlotsOwnLength() throws {
        let saved = try #require(SplitStackGeometry.adjustableShares(saved: [0.5, 0.5], shown: [350, 350], available: 700, minimum: 220))
        #expect(SplitStackLayoutTestsSupport.close(saved.shares, [0.5, 0.5]))
        #expect(abs(saved.minimum - 220.0 / 700) < 1e-12)
    }

    @Test func sharesSqueezedBelowTheMinimumFallBackToWhatIsShown() throws {
        let shown = try #require(SplitStackGeometry.adjustableShares(saved: [0.95, 0.05], shown: [480, 220], available: 700, minimum: 220))
        #expect(SplitStackLayoutTestsSupport.close(shown.shares, [480.0 / 700, 220.0 / 700]))
    }

    @Test func aRoomyPairDragsFromItsSavedShares() throws {
        let factors = try #require(SplitStackGeometry.resizableFactors(saved: [0.5, 0.5], shown: [350, 350], divider: 0, available: 700, minimum: 220))
        #expect(SplitStackLayoutTestsSupport.close(factors, [0.5, 0.5]))
    }

    private static let commandValue = SplitStackLayoutTestsSupport.stacks([2, 1], [0.6, 0.4], [[0.3, 0.7], [1]])
    private static let commandIDs = [UUID(), UUID(), UUID()]
    private static func commandLayout() -> BrowserSplitLayout {
        BrowserSplitLayout(id: UUID(), spaceID: UUID(), tabIDs: commandIDs, orientation: .horizontal,
                           widthFactors: commandValue.flattenedFactors, stacks: commandValue)
    }

    @Test func expandGivesTheFocusedPaneTheLargestShareOnBothLevels() throws {
        let layout = Self.commandLayout()
        let expanded = try #require(layout.expanded(focusing: layout.tabIDs[1])?.stacks)
        #expect(expanded.slotFactors[0] > 0.999)
        #expect(expanded.stackFactors[0][1] > 0.999)
    }

    @Test func anExpandedStackedPaneLeavesItsNeighboursAtTheMinimumOnBothAxes() throws {
        let layout = Self.commandLayout()
        let expanded = try #require(layout.expanded(focusing: layout.tabIDs[1])?.stacks)
        let expandedFrames = SplitStackLayoutTestsSupport.frames(expanded)
        #expect(expandedFrames[2].width == 220)
        #expect(expandedFrames[0].height == 220)
        #expect(expandedFrames[1].height == 480)
    }

    @Test func makeAllEqualEvensTheSlotsThenEachStack() throws {
        let equal = try #require(Self.commandLayout().resized(by: .equal)?.stacks)
        #expect(equal.slotFactors == [0.5, 0.5])
        #expect(equal.stackFactors == [[0.5, 0.5], [1]])
        #expect(equal.isEven)
    }

    @Test func evennessChecksBothLevels() {
        #expect(!Self.commandValue.isEven)
        #expect(SplitStackLayoutTestsSupport.stacks([2, 2], [1, 1], [[2, 2], [3, 3]]).isEven)
    }

    @Test func widenStepsTheFocusedPanesSlotAlongTheMainRowOnly() throws {
        let widened = try #require(SplitPaneResize.resizingPane(0, in: Self.commandValue.slotFactors, growing: true, minimum: 0.22))
        let wide = try #require(Self.commandLayout().resized(by: .slots(widened))?.stacks)
        #expect(SplitStackLayoutTestsSupport.close(wide.slotFactors, [0.7, 0.3]))
        #expect(wide.stackFactors == Self.commandValue.stackFactors)
    }

    @Test func narrowStepsTheSlotBackTowardEvenAndLeavesTheStackAlone() throws {
        let narrowed = try #require(SplitPaneResize.resizingPane(0, in: Self.commandValue.slotFactors, growing: false, minimum: 0.22))
        let narrow = try #require(Self.commandLayout().resized(by: .slots(narrowed))?.stacks)
        #expect(SplitStackLayoutTestsSupport.close(narrow.slotFactors, [0.5, 0.5]))
        #expect(narrow.stackFactors == Self.commandValue.stackFactors)
    }

    @Test func eveningAStackDividerMovesOnlyItsTwoPanes() throws {
        let divider = try #require(Self.commandLayout().resized(by: .divider(0, slot: 0, leadingShare: 0.5))?.stacks)
        #expect(SplitStackLayoutTestsSupport.close(divider.stackFactors[0], [0.5, 0.5]))
        #expect(SplitStackLayoutTestsSupport.close(divider.slotFactors, Self.commandValue.slotFactors))
    }

    @Test func aMainRowDividerMovesOnlyItsTwoSlots() throws {
        let divider = try #require(Self.commandLayout().resized(by: .divider(0, slot: nil, leadingShare: 0.25))?.stacks)
        #expect(SplitStackLayoutTestsSupport.close(divider.slotFactors, [0.25, 0.75]))
        #expect(divider.stackFactors == Self.commandValue.stackFactors)
    }

    @Test func aKeyboardStepOnAStackDividerUsesTheSlotsOwnShares() throws {
        let stepped = try #require(SplitPaneResize.movingDivider(0, in: [0.3, 0.7], forward: true, minimum: 0.3))
        #expect(SplitStackLayoutTestsSupport.close(stepped, [0.4, 0.6]))
    }

    @Test func aDividerOutsideTheStackIsRefused() {
        #expect(Self.commandLayout().resized(by: .divider(1, slot: 0, leadingShare: 0.5)) == nil)
    }

    @Test func aPairSqueezedBelowTheMinimumDragsFromWhatIsShown() throws {
        let squeezed = try #require(SplitStackGeometry.resizableFactors(saved: [0.05, 0.24, 0.71], shown: [220, 318, 942], divider: 0, available: 1480, minimum: 220))
        #expect(SplitStackLayoutTestsSupport.close(squeezed, [220.0 / 1480, 318.0 / 1480, 942.0 / 1480]))
    }

    @Test func aSqueezedDragSavesItsWholeLevelAsPreviewedSoTheOtherSlotKeepsItsSize() throws {
        let three = SplitStackLayoutTestsSupport.stacks([1, 1, 2], [0.05, 0.24, 0.71], [[1], [1], [0.5, 0.5]])
        let trio = BrowserSplitLayout(id: UUID(), spaceID: UUID(), tabIDs: [UUID(), UUID(), UUID(), UUID()], orientation: .horizontal,
                                      widthFactors: three.flattenedFactors, stacks: three)
        let whole = try #require(trio.resized(by: .level(slot: nil, factors: [269.0 / 1480, 269.0 / 1480, 942.0 / 1480]))?.stacks)
        #expect(SplitStackLayoutTestsSupport.close(whole.slotFactors, [269.0 / 1480, 269.0 / 1480, 942.0 / 1480]))
        #expect(whole.stackFactors == three.stackFactors)
    }

    @Test func aWholeLevelSaveInsideAStackChangesOnlyThatStack() throws {
        let inner = try #require(Self.commandLayout().resized(by: .level(slot: 0, factors: [0.2, 0.8]))?.stacks)
        #expect(SplitStackLayoutTestsSupport.close(inner.stackFactors[0], [0.2, 0.8]))
        #expect(SplitStackLayoutTestsSupport.close(inner.slotFactors, Self.commandValue.slotFactors))
    }

    @Test func aLiveDragReplacesOnlyItsOwnLevel() {
        #expect(Self.commandValue.replacing([0.2, 0.8], inSlot: 0).stackFactors[0] == [0.2, 0.8])
        #expect(Self.commandValue.replacing([0.1, 0.9], inSlot: nil).slotFactors == [0.1, 0.9])
    }

    @Test func aMainRowDropReservationMakesAWholeNewSlot() {
        let reserved = Self.commandValue.reservingSlot(at: 1)
        #expect(reserved.slotSizes == [2, 1, 1])
        #expect(SplitStackLayoutTestsSupport.close(reserved.slotFactors, [0.4, 1.0 / 3, 0.4 * 2 / 3]))
        #expect(reserved.stackFactors == [[0.3, 0.7], [1], [1]])
    }
}
