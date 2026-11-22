import AppKit
import ParcCore
import Testing
@testable import Parc

@MainActor
struct ExternalSplitDropHandoffTerminationTests {
    @Test func leavingTheLastReceiverArmsTheRepeatingDragFallback() throws {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        try #require(scene.enterLeftEdge())
        let edit = try #require(scene.split.interactivePaneEdit)
        defer { scene.router.end() }
        var timers: [Timer] = []
        edit.scheduleFallbackTimer = { timers.append($0) }

        scene.leaveThePage()

        let timer = try #require(timers.first)
        #expect(timers.count == 1)
        #expect(timer.isValid)
        #expect(timer.timeInterval == 0.05)
    }

    @Test func enteringTheOtherPageBeforeReleaseContinuesTheSameEdit() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        #expect(scene.enterLeftEdge())
        scene.leaveThePage()
        let before = scene.editing
        let routerB = SplitDropRouterDouble(view: scene.pageB.body)
        #expect(routerB.begin(scene.drag))
        #expect(scene.split.isInteractivePaneEditing)
        #expect(scene.editing == before)
    }

    @Test func whileAPageHasTheDragButtonStateCannotEndTheEdit() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        #expect(scene.enterLeftEdge())
        scene.leaveThePage()
        let routerB = SplitDropRouterDouble(view: scene.pageB.body)
        #expect(routerB.begin(scene.drag))
        scene.buttonDown = false
        scene.split.interactivePaneEdit?.endIfDragReleased()
        #expect(scene.split.isInteractivePaneEditing)
    }

    @Test func leavingTheOtherPageKeepsTheEdit() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        #expect(scene.enterLeftEdge())
        scene.leaveThePage()
        let routerB = SplitDropRouterDouble(view: scene.pageB.body)
        #expect(routerB.begin(scene.drag))
        routerB.exit(scene.drag)
        #expect(scene.split.isInteractivePaneEditing)
        #expect(routerB.claimed)
    }

    @Test func withNoRouteHoldingTheDragButtonReleaseEndsTheEdit() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        #expect(scene.enterLeftEdge())
        scene.leaveThePage()
        let routerB = SplitDropRouterDouble(view: scene.pageB.body)
        #expect(routerB.begin(scene.drag))
        routerB.exit(scene.drag)
        scene.buttonDown = false
        scene.split.interactivePaneEdit?.endIfDragReleased()
        #expect(!scene.split.isInteractivePaneEditing)
        #expect(scene.editing.last == false)
    }

    @Test func lateTerminalCallbacksAfterTheFallbackChangeNothing() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        #expect(scene.enterLeftEdge())
        scene.leaveThePage()
        let routerB = SplitDropRouterDouble(view: scene.pageB.body)
        #expect(routerB.begin(scene.drag))
        routerB.exit(scene.drag)
        scene.buttonDown = false
        scene.split.interactivePaneEdit?.endIfDragReleased()
        let after = scene.editing
        scene.router.end()
        routerB.end()
        #expect(scene.editing == after)
        #expect(!scene.router.claimed)
        #expect(!routerB.claimed)
    }

    @Test func theOriginalPageOrEditorExpiringRefusesContinuationWithoutANewOwner() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        scene.beginHandoff()
        scene.sessionValid = false
        scene.host.validateDrop()
        #expect(scene.host.draggingUpdated(scene.drag).isEmpty)
        #expect(!scene.host.performDragOperation(scene.drag))
        #expect(scene.commits == 0)
    }

    @Test func leavingTheReservedHostAreaCancelsRatherThanRetainingAStrandedDraft() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        scene.beginHandoff()
        scene.host.draggingExited(scene.drag)
        #expect(scene.split.arrangedSubviews.map(\.frame) == scene.originalFrames)
        #expect(!scene.host.prepareForDragOperation(scene.drag))
        #expect(scene.split.isInteractivePaneEditing)
        #expect(scene.router.claimed)
    }

    @Test func theHostsTerminalDraggingEndedEndsTheEdit() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        scene.beginHandoff()
        scene.host.draggingExited(scene.drag)
        scene.host.draggingEnded(scene.drag)
        #expect(!scene.split.isInteractivePaneEditing)
    }

    @Test func aForeignSequenceCannotEnterTheOldReservedRegion() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        scene.beginHandoff()
        scene.drag.draggingSequenceNumber += 1
        #expect(scene.host.draggingUpdated(scene.drag).isEmpty)
        #expect(scene.split.subviews.count == 2)
    }

    @Test func aRefusedCommitRemovesTheReservationAndReportsFailure() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        scene.commitResult = false
        scene.beginHandoff()
        #expect(!scene.host.performDragOperation(scene.drag))
        #expect(scene.commits == 1)
        #expect(scene.split.subviews.count == 2)
    }

    @Test func detachingTheOriginalReceiverCannotRetargetARemainingPane() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        scene.beginHandoff()
        scene.pageA.removeFromSuperview()
        #expect(scene.host.draggingUpdated(scene.drag).isEmpty)
        #expect(!scene.host.performDragOperation(scene.drag))
        #expect(scene.commits == 0)
    }
}
