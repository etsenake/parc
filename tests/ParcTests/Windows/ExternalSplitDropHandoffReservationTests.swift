import AppKit
import ParcCore
import Testing
@testable import Parc

@MainActor
struct ExternalSplitDropHandoffReservationTests {
    @Test func anUnclaimedHostLinkCannotCreateASession() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        #expect(scene.host.draggingEntered(scene.drag).isEmpty)
        #expect(scene.admits == 0)
    }

    @Test func originalContentAdmitsAnExternalLinkAndReservesLayoutWithoutANewPageOwner() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        #expect(scene.enterLeftEdge())
        #expect(scene.router.operation == .copy)
        #expect(scene.split.arrangedSubviews.map(\.frame) != scene.originalFrames)
        #expect(scene.split.arrangedSubviews.count == 2)
    }

    @Test func anAdmittedLinkBeginsPaneEditingBeforeItsReservedLayout() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        scene.beginHandoff()
        #expect(scene.editing == [true])
        #expect(scene.split.isInteractivePaneEditing)
    }

    @Test func oneNativeGesturePerformsOnceThroughTheOriginalReceiver() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        scene.beginHandoff()
        #expect(scene.host.performDragOperation(scene.drag))
        #expect(scene.commits == 1)
        #expect(scene.admits == 1)
        #expect(scene.geometryRestoredAtCommit)
    }

    @Test func aPerformedDropEndsInteractiveEditing() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        scene.beginHandoff()
        _ = scene.host.performDragOperation(scene.drag)
        #expect(scene.editing == [true, false])
        #expect(!scene.split.isInteractivePaneEditing)
    }

    @Test func lateHostCallbacksCannotReplayOrLeaveARegion() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        scene.beginHandoff()
        _ = scene.host.performDragOperation(scene.drag)
        #expect(!scene.host.performDragOperation(scene.drag))
        #expect(scene.commits == 1)
        #expect(scene.split.subviews.count == 2)
    }

    @Test func theOriginalTerminalCallbackCancelsTheHandoffAndRestoresTheExactLayout() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        scene.beginHandoff()
        scene.router.end()
        #expect(scene.host.draggingUpdated(scene.drag).isEmpty)
        #expect(scene.commits == 0)
        #expect(scene.split.arrangedSubviews.map(\.frame) == scene.originalFrames)
        #expect(scene.editing == [true, false])
    }

    @Test func leavingThePageEndsItsPreviewButKeepsTheEditAndTheRouterAsTerminalWitness() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        #expect(scene.enterLeftEdge())
        scene.leaveThePage()
        #expect(scene.router.claimed)
        #expect(scene.split.arrangedSubviews.map(\.frame) == scene.originalFrames)
        #expect(scene.editing == [true])
        #expect(scene.split.isInteractivePaneEditing)
    }

    @Test func theWitnessRouterCannotDropThroughTheHost() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        #expect(scene.enterLeftEdge())
        scene.leaveThePage()
        #expect(scene.host.draggingUpdated(scene.drag).isEmpty)
        #expect(!scene.host.prepareForDragOperation(scene.drag))
    }

    @Test func reenteringTheSamePageResumesTheEditBeforeAnyLayout() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        #expect(scene.enterLeftEdge())
        scene.leaveThePage()
        #expect(scene.enterLeftEdge())
        #expect(scene.split.isInteractivePaneEditing)
        #expect(scene.editing.last == true)
    }

    @Test func theExitedPageViewsTerminalEndEndsTheEdit() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        #expect(scene.enterLeftEdge())
        scene.leaveThePage()
        scene.router.end()
        #expect(!scene.router.claimed)
        #expect(!scene.split.isInteractivePaneEditing)
        #expect(scene.editing.last == false)
    }

    @Test func outsideThePageWithTheButtonHeldTheEditStays() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        #expect(scene.enterLeftEdge())
        scene.leaveThePage()
        scene.split.interactivePaneEdit?.endIfDragReleased()
        #expect(scene.split.isInteractivePaneEditing)
    }
}
