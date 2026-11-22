import AppKit
import QuartzCore
import Testing
@testable import ParcCore
@testable import Parc

@MainActor
struct SplitDividerTestsDegenerate {
    private typealias SplitRig = SplitDividerTestsSupport.SplitRig

    private static func rig(scale: CGFloat, factors: [Double] = [0.75, 0.25, 1e-9]) -> SplitRig {
        SplitRig(factors: factors, frame: NSRect(x: 0, y: 0, width: 1210, height: 800), window: NSSize(width: 1610, height: 800), scale: scale)
    }

    @Test func minimumRedistributionDisplaysMoreThanThePairsSavedShare() {
        let rig = Self.rig(scale: 2)
        #expect(rig.widths[2] == 220)
        #expect(rig.widths[1] > 220 && rig.widths[1] < 0.25 * 1190)
    }

    @Test func itsDividerMovesOnlyTheTwoPanesDisplayedSpace() {
        let rig = Self.rig(scale: 2)
        let widths = rig.widths
        let origin = rig.dividerOrigin(1)
        #expect(rig.view.beginDividerResize(at: origin))
        rig.view.updateDividerResize(at: NSPoint(x: origin.x - 10, y: 200), velocity: 200)
        #expect(rig.widths[0] == widths[0])
        #expect(rig.widths[1] == widths[1] - 10)
        #expect(rig.widths[2] == 230)
    }

    @Test func theDragCommitsValidWeightsAndKeepsTheOtherPanesSize() {
        let rig = Self.rig(scale: 2)
        let widths = rig.widths
        let origin = rig.dividerOrigin(1)
        rig.view.beginDividerResize(at: origin)
        rig.view.updateDividerResize(at: NSPoint(x: origin.x - 10, y: 200), velocity: 200)
        rig.view.finishDividerResize(commit: true)
        #expect(rig.commits.count == 1)
        #expect(BrowserSplitLayout.normalized(rig.commits[0], count: 3) != nil)
        #expect(rig.widths[0] == widths[0])
    }

    @Test func doubleClickSplitsThePairsDisplayedSpaceAndLeavesTheOtherPaneAlone() {
        let rig = Self.rig(scale: 2)
        let widths = rig.widths
        rig.doubleClick(at: NSPoint(x: rig.panes[1].frame.maxX + 3, y: 200))
        #expect(rig.commits.count == 1)
        #expect(rig.widths[0] == widths[0])
        #expect(abs(rig.widths[1] - rig.widths[2]) <= 1)
    }

    @Test func atOneXIndependentlyRoundedLengthsOverrunTheAvailableLength() {
        let rig = Self.rig(scale: 1)
        #expect(rig.widths.reduce(0, +) > 1190)
    }

    @Test func atOneXThePairTakesTheRoundingRemainderAndTheOtherPaneKeepsItsSize() {
        let rig = Self.rig(scale: 1)
        let widths = rig.widths
        let origin = rig.dividerOrigin(1)
        #expect(rig.view.beginDividerResize(at: origin))
        rig.view.updateDividerResize(at: NSPoint(x: origin.x - 10, y: 200), velocity: 200)
        #expect(rig.widths[0] == widths[0])
        #expect(rig.widths[1] == widths[1] - 10)
        #expect(rig.widths[2] == 229)
        #expect(rig.panes[2].frame.maxX == 1210)
    }

    @Test func theOneXCommitKeepsTheOtherPanesSize() {
        let rig = Self.rig(scale: 1)
        let widths = rig.widths
        let origin = rig.dividerOrigin(1)
        rig.view.beginDividerResize(at: origin)
        rig.view.updateDividerResize(at: NSPoint(x: origin.x - 10, y: 200), velocity: 200)
        rig.view.finishDividerResize(commit: true)
        #expect(rig.widths[0] == widths[0])
    }

    @Test func aOneXDoubleClickSplitsThePairEvenlyAndLeavesTheOtherPaneAlone() {
        let rig = Self.rig(scale: 1)
        let widths = rig.widths
        rig.doubleClick(at: NSPoint(x: rig.panes[1].frame.maxX + 3, y: 200))
        #expect(rig.widths[0] == widths[0])
        #expect(rig.widths[1] == rig.widths[2])
    }

    @Test func atOneXTheLeadingDegeneratePairOverrunsToo() {
        let rig = Self.rig(scale: 1, factors: [1e-9, 0.25, 0.75])
        #expect(rig.widths[0] == 220)
        #expect(rig.widths.reduce(0, +) > 1190)
    }

    @Test func atOneXTheFirstDividerMovesItsPairAndTheLastPaneKeepsItsSize() {
        let rig = Self.rig(scale: 1, factors: [1e-9, 0.25, 0.75])
        let widths = rig.widths
        let origin = rig.dividerOrigin(0)
        #expect(rig.view.beginDividerResize(at: origin))
        rig.view.updateDividerResize(at: NSPoint(x: origin.x + 10, y: 200), velocity: 200)
        #expect(rig.widths[0] == 230)
        #expect(rig.widths[2] == widths[2])
        #expect(rig.panes[2].frame.maxX == 1210)
    }

    @Test func theOneXLeadingCommitKeepsTheLastPanesSize() {
        let rig = Self.rig(scale: 1, factors: [1e-9, 0.25, 0.75])
        let widths = rig.widths
        let origin = rig.dividerOrigin(0)
        rig.view.beginDividerResize(at: origin)
        rig.view.updateDividerResize(at: NSPoint(x: origin.x + 10, y: 200), velocity: 200)
        rig.view.finishDividerResize(commit: true)
        #expect(rig.widths[2] == widths[2])
    }
}
