import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitDividerTestsScale {
    private typealias SplitRig = SplitDividerTestsSupport.SplitRig

    @Test func aDetachedViewRoundsEveryPaneIndependentlyWithoutLastPaneFill() {
        let rig = SplitRig(attached: false)
        #expect(rig.widths == [327, 327, 327])
        #expect(rig.panes.last?.frame.maxX == 1001)
    }

    @Test func theWindowBackingScaleRoundsLengthsBeforeFinalIntegerEdges() {
        let rig = SplitRig()
        #expect(rig.widths == [327, 326, 327])
        #expect(rig.panes.map { $0.frame.minX } == [0, 337, 673])
    }

    @Test func verticalPanesFollowTheSameLengthAndPrefixPositionCalculation() {
        let rig = SplitRig(orientation: .vertical)
        #expect(rig.heights == [327, 326, 327])
        #expect(rig.panes.map { $0.frame.minY } == [0, 337, 673])
    }

    @Test func aScaleChangeRecalculatesExistingPanesWithoutAModelWrite() {
        let rig = SplitRig()
        rig.window.testScale = 1
        rig.view.viewDidChangeBackingProperties()
        #expect(rig.widths == [327, 327, 327])
        #expect(rig.panes.last?.frame.maxX == 1001)
        #expect(rig.commits.isEmpty)
    }

    @Test func nativePreviewRecalculatesEveryFrameFromIndependentlyRoundedLengths() {
        let rig = SplitRig(factors: [0.3, 0.3, 0.4])
        let origin = rig.dividerOrigin()
        #expect(rig.view.beginDividerResize(at: origin))
        rig.view.updateDividerResize(at: NSPoint(x: origin.x + 30.3, y: 200), velocity: 200)
        #expect(rig.commits.isEmpty)
        #expect(rig.widths == [325, 263, 392])
        #expect(rig.panes.map { $0.frame.minX } == [0, 335, 608])
    }

    @Test func theDurableRatioUsesTheGlobalAvailableAxisNotThePairWidth() {
        let rig = SplitRig(factors: [0.3, 0.3, 0.4])
        let origin = rig.dividerOrigin()
        rig.view.beginDividerResize(at: origin)
        rig.view.updateDividerResize(at: NSPoint(x: origin.x + 30.3, y: 200), velocity: 200)
        rig.view.finishDividerResize(commit: true)
        #expect(rig.commits.count == 1)
        #expect(SplitDividerTestsSupport.near(rig.commits[0], [324.3 / 980, 0.6 - 324.3 / 980, 0.4]))
    }

    @Test func theAcceptedPreviewAndTheSavedLayoutHaveIdenticalGeometryOnTheSamePanes() {
        let rig = SplitRig(factors: [0.3, 0.3, 0.4])
        let origin = rig.dividerOrigin()
        rig.view.beginDividerResize(at: origin)
        rig.view.updateDividerResize(at: NSPoint(x: origin.x + 30.3, y: 200), velocity: 200)
        let preview = rig.frames
        rig.view.finishDividerResize(commit: true)
        #expect(rig.frames == preview)
        #expect(zip(rig.panes, rig.view.arrangedSubviews).allSatisfy { $0 === $1 })
    }

    @Test func aSameScaleBackingNotificationRetainsTheCurrentPreview() {
        let rig = SplitRig(factors: [0.3, 0.3, 0.4])
        let origin = rig.dividerOrigin()
        rig.view.beginDividerResize(at: origin)
        rig.view.updateDividerResize(at: NSPoint(x: origin.x + 30.3, y: 200), velocity: 200)
        let preview = rig.frames
        rig.view.viewDidChangeBackingProperties()
        #expect(rig.frames == preview)
    }

    @Test func anActualScaleChangeCancelsTheCapturedPreviewAndRestoresSourceRatios() {
        let rig = SplitRig(factors: [0.3, 0.3, 0.4])
        let before = rig.frames
        let origin = rig.dividerOrigin()
        rig.view.beginDividerResize(at: origin)
        rig.view.updateDividerResize(at: NSPoint(x: origin.x + 30.3, y: 200), velocity: 200)
        rig.window.testScale = 1
        rig.view.viewDidChangeBackingProperties()
        rig.view.finishDividerResize(commit: true)
        #expect(rig.commits.isEmpty)
        rig.window.testScale = 2
        rig.view.viewDidChangeBackingProperties()
        #expect(rig.frames == before)
    }

    @Test func completionRejectsAChangedScaleEvenBeforeItsNotificationArrives() {
        let rig = SplitRig(factors: [0.3, 0.3, 0.4])
        let before = rig.frames
        let origin = rig.dividerOrigin()
        rig.view.beginDividerResize(at: origin)
        rig.view.updateDividerResize(at: NSPoint(x: origin.x + 30.3, y: 200), velocity: 200)
        rig.window.testScale = 1
        rig.view.finishDividerResize(commit: true)
        rig.window.testScale = 2
        rig.view.viewDidChangeBackingProperties()
        #expect(rig.commits.isEmpty)
        #expect(rig.frames == before)
    }

    @Test func minimumRedistributionCanMoveTheLivePanesOriginWhileKeepingEarlierShare() {
        let rig = SplitRig(factors: [0.4, 0.01, 0.59])
        let origin = rig.dividerOrigin(1)
        #expect(rig.view.beginDividerResize(at: origin))
        rig.view.updateDividerResize(at: NSPoint(x: origin.x + 20, y: 200), velocity: 200)
        #expect(rig.panes[0].frame.width == 392)
        #expect(rig.panes[1].frame.minX == 402)
        #expect(rig.panes[1].frame.width == 240)
    }

    @Test func theNextUpdateRetainsTheCapturedHandleOffsetRelativeToTheLivePane() {
        let rig = SplitRig(factors: [0.4, 0.01, 0.59])
        let origin = rig.dividerOrigin(1)
        rig.view.beginDividerResize(at: origin)
        let held = NSPoint(x: origin.x + 20, y: 200)
        rig.view.updateDividerResize(at: held, velocity: 200)
        rig.view.updateDividerResize(at: held, velocity: 200)
        #expect(rig.panes[1].frame.width == 220)
        #expect(rig.commits.isEmpty)
    }

    @Test func cancelRestoresSourceRatiosAfterTheLiveOriginMoved() {
        let rig = SplitRig(factors: [0.4, 0.01, 0.59])
        let before = rig.frames
        let origin = rig.dividerOrigin(1)
        rig.view.beginDividerResize(at: origin)
        rig.view.updateDividerResize(at: NSPoint(x: origin.x + 20, y: 200), velocity: 200)
        rig.view.finishDividerResize(commit: false)
        #expect(rig.frames == before)
        #expect(rig.commits.isEmpty)
    }

    @Test func anInvalidWindowScaleCannotProduceNonfiniteGeometry() {
        let rig = SplitRig()
        rig.window.testScale = .nan
        rig.view.viewDidChangeBackingProperties()
        rig.view.configure(orientation: .horizontal, factors: [1, 1, 1])
        #expect(rig.widths == [327, 327, 327])
    }

    @Test func anUnpersistableNonPositiveFactorRefusesInsteadOfCorruptingItsGroup() {
        let rig = SplitRig(factors: [0.01, 0.01, 0.98], orientation: .vertical)
        let before = rig.frames
        let origin = NSPoint(x: 20, y: rig.panes[0].frame.maxY + 5)
        #expect(rig.view.beginDividerResize(at: origin))
        rig.view.updateDividerResize(at: NSPoint(x: 20, y: origin.y + 20), velocity: 200)
        rig.view.finishDividerResize(commit: true)
        #expect(rig.commits.isEmpty)
        #expect(rig.frames == before)
    }

    @Test func sideBySidePanesKeepOrdinaryHitTestingOutsideAPan() {
        let rig = SplitRig()
        #expect(rig.view.hitTest(NSPoint(x: 100, y: 500)) === rig.panes[0])
    }

    @Test func aSideBySidePanSetsItsReasonAndLocksPaneInput() {
        let rig = SplitRig()
        var activity: [Bool] = []
        rig.view.onDividerPanActivity = { activity.append($0) }
        let origin = rig.dividerOrigin()
        #expect(rig.view.beginDividerResize(at: origin))
        rig.view.beginDividerPan(at: origin)
        #expect(activity == [true])
        #expect(rig.view.hitTest(NSPoint(x: 100, y: 500)) === rig.view)
    }

    @Test func aBackingScaleChangeMidPanClearsTheReasonAndThePaneLock() {
        let rig = SplitRig()
        var activity: [Bool] = []
        rig.view.onDividerPanActivity = { activity.append($0) }
        let origin = rig.dividerOrigin()
        rig.view.beginDividerResize(at: origin)
        rig.view.beginDividerPan(at: origin)
        rig.window.testScale = 1
        rig.view.viewDidChangeBackingProperties()
        #expect(activity == [true, false])
        #expect(!rig.view.isDividerPanActive)
        #expect(rig.view.hitTest(NSPoint(x: 100, y: 500)) === rig.panes[0])
    }
}
