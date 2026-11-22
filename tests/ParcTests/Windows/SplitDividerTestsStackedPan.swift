import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitDividerTestsStackedPan {
    private typealias SplitRig = SplitDividerTestsSupport.SplitRig

    private final class Activity { var values: [Bool] = [] }

    private static func rig() -> (rig: SplitRig, activity: Activity, point: NSPoint) {
        let rig = SplitRig(count: 2, orientation: .vertical, frame: NSRect(x: 0, y: 0, width: 900, height: 900))
        let activity = Activity()
        rig.view.onDividerPanActivity = { activity.values.append($0) }
        return (rig, activity, NSPoint(x: 450, y: rig.panes[0].frame.maxY + 5))
    }

    private static func paneHit(_ rig: SplitRig, _ y: CGFloat) -> Bool {
        rig.panes.contains { $0 === rig.view.hitTest(NSPoint(x: 450, y: y)) }
    }

    @Test func aStackedPaneDividerExcludesEightPointsAtEachEnd() {
        let (rig, _, _) = Self.rig()
        let y = rig.panes[0].frame.maxY + 5
        #expect(!rig.view.beginDividerResize(at: NSPoint(x: 7, y: y)))
        #expect(!rig.view.beginDividerResize(at: NSPoint(x: 893, y: y)))
        #expect(rig.view.beginDividerResize(at: NSPoint(x: 8, y: y)))
    }

    @Test func mouseDownAdmissionAloneSetsNoResizeReasonAndKeepsPaneInput() {
        let (rig, activity, point) = Self.rig()
        #expect(rig.view.beginDividerResize(at: point))
        #expect(activity.values.isEmpty)
        #expect(Self.paneHit(rig, 100) && Self.paneHit(rig, 800))
    }

    @Test func panBeganSetsTheReasonAndEveryPaneRefusesHitTesting() {
        let (rig, activity, point) = Self.rig()
        rig.view.beginDividerResize(at: point)
        rig.view.beginDividerPan(at: point)
        #expect(activity.values == [true])
        #expect(rig.view.isDividerPanActive)
        #expect(rig.view.hitTest(NSPoint(x: 450, y: 100)) === rig.view)
        #expect(rig.view.hitTest(NSPoint(x: 450, y: 800)) === rig.view)
    }

    @Test func anEndedPanClearsTheReasonAndRestoresPaneInput() {
        let (rig, activity, point) = Self.rig()
        rig.view.beginDividerResize(at: point)
        rig.view.beginDividerPan(at: point)
        rig.view.updateDividerResize(at: NSPoint(x: 450, y: point.y + 30), velocity: 200)
        rig.view.finishDividerResize(commit: true)
        #expect(activity.values == [true, false])
        #expect(!rig.view.isDividerPanActive)
        #expect(Self.paneHit(rig, 100) && Self.paneHit(rig, 800))
    }

    @Test func anOwnerChangeThatCancelsTheCapturedPanAlsoClearsItsReason() {
        let (rig, activity, point) = Self.rig()
        rig.view.beginDividerResize(at: point)
        rig.view.beginDividerPan(at: point)
        rig.view.configure(orientation: .vertical, factors: [2, 1])
        #expect(activity.values == [true, false])
        #expect(Self.paneHit(rig, 100))
    }

    @Test func laterRecognizerEventsAfterCancellationReportNothingFurther() {
        let (rig, activity, point) = Self.rig()
        rig.view.beginDividerResize(at: point)
        rig.view.beginDividerPan(at: point)
        rig.view.configure(orientation: .vertical, factors: [2, 1])
        rig.view.updateDividerResize(at: NSPoint(x: 450, y: point.y + 30), velocity: 200)
        rig.view.finishDividerResize(commit: true)
        #expect(activity.values.count == 2)
    }

    @Test func doubleClickEqualizesOnlyInsideTheDraggableRegionAndNeverSetsTheDragReason() {
        let (rig, activity, point) = Self.rig()
        rig.doubleClick(at: NSPoint(x: 4, y: point.y))
        rig.doubleClick(at: NSPoint(x: 450, y: point.y))
        #expect(rig.commits.count == 1)
        #expect(activity.values.isEmpty)
    }

    @Test func detachmentMidPanClearsTheReasonAndThePaneLock() {
        let (rig, activity, point) = Self.rig()
        #expect(rig.view.beginDividerResize(at: point))
        rig.view.beginDividerPan(at: point)
        #expect(activity.values.last == true && rig.view.isDividerPanActive && !Self.paneHit(rig, 100))
        rig.view.removeFromSuperview()
        #expect(activity.values.last == false)
        #expect(!rig.view.isDividerPanActive)
        #expect(Self.paneHit(rig, 100) && Self.paneHit(rig, 800))
    }
}
