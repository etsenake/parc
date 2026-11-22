import AppKit
import ParcCore
import Testing
@testable import Parc

@MainActor
struct ExternalSplitDropHandoffReceiversTests {
    @Test func theLocalDocumentForwarderAdmitsTheSameNativeReservation() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        let receiver = LocalContentDropView(frame: scene.pageA.body.bounds)
        scene.pageA.body.addSubview(receiver)
        scene.place(NSPoint(x: 1, y: 200))
        #expect(receiver.draggingEntered(scene.drag) == .copy)
    }

    @Test func aLocalExitForwardsTheExactRouterToTheHost() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        let receiver = LocalContentDropView(frame: scene.pageA.body.bounds)
        scene.pageA.body.addSubview(receiver)
        scene.place(NSPoint(x: 1, y: 200))
        _ = receiver.draggingEntered(scene.drag)
        scene.place(NSPoint(x: 200, y: 200))
        receiver.draggingExited(scene.drag)
        #expect(scene.host.draggingEntered(scene.drag) == .copy)
    }

    @Test func aForwardedLocalDragCommitsThroughTheHost() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        let receiver = LocalContentDropView(frame: scene.pageA.body.bounds)
        scene.pageA.body.addSubview(receiver)
        scene.place(NSPoint(x: 1, y: 200))
        _ = receiver.draggingEntered(scene.drag)
        scene.place(NSPoint(x: 200, y: 200))
        receiver.draggingExited(scene.drag)
        _ = scene.host.draggingEntered(scene.drag)
        #expect(scene.host.performDragOperation(scene.drag))
        #expect(scene.commits == 1)
    }

    @Test func aLateLocalTerminalCallbackLeavesTheOriginalsAndTheConsumedTransactionUnchanged() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        let receiver = LocalContentDropView(frame: scene.pageA.body.bounds)
        scene.pageA.body.addSubview(receiver)
        scene.place(NSPoint(x: 1, y: 200))
        _ = receiver.draggingEntered(scene.drag)
        scene.place(NSPoint(x: 200, y: 200))
        receiver.draggingExited(scene.drag)
        _ = scene.host.draggingEntered(scene.drag)
        _ = scene.host.performDragOperation(scene.drag)
        receiver.draggingEnded(scene.drag)
        #expect(scene.split.subviews.count == 2)
        #expect(scene.split.arrangedSubviews.map(\.frame) == scene.originalFrames)
    }

    @Test func theNativeTextReceiverAdmitsTheOriginalLink() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        let receiver = LocalContentDropTextView(frame: scene.pageA.body.bounds)
        scene.pageA.body.addSubview(receiver)
        scene.place(NSPoint(x: 1, y: 200))
        #expect(receiver.draggingEntered(scene.drag) == .copy)
    }

    @Test func aTextReceiverExitRetainsTheOriginalHandoff() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        let receiver = LocalContentDropTextView(frame: scene.pageA.body.bounds)
        scene.pageA.body.addSubview(receiver)
        scene.place(NSPoint(x: 1, y: 200))
        _ = receiver.draggingEntered(scene.drag)
        scene.place(NSPoint(x: 200, y: 200))
        receiver.draggingExited(scene.drag)
        #expect(scene.host.draggingEntered(scene.drag) == .copy)
    }

    @Test func aTextReceiversTerminalCleanupCancelsTheSameHandoffAndRestoresAuthority() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        let receiver = LocalContentDropTextView(frame: scene.pageA.body.bounds)
        scene.pageA.body.addSubview(receiver)
        scene.place(NSPoint(x: 1, y: 200))
        _ = receiver.draggingEntered(scene.drag)
        scene.place(NSPoint(x: 200, y: 200))
        receiver.draggingExited(scene.drag)
        _ = scene.host.draggingEntered(scene.drag)
        receiver.draggingEnded(scene.drag)
        #expect(scene.host.draggingUpdated(scene.drag).isEmpty)
        #expect(scene.commits == 0)
        #expect(scene.split.arrangedSubviews.map(\.frame) == scene.originalFrames)
    }

    @Test func aTextReceiversTerminalCollapseRemovesItsPassiveRegion() throws {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        var complete: (@MainActor () -> Void)?
        scene.split.registerDropRegionCompletion = { complete = $0 }
        let receiver = LocalContentDropTextView(frame: scene.pageA.body.bounds)
        scene.pageA.body.addSubview(receiver)
        scene.place(NSPoint(x: 1, y: 200))
        try #require(receiver.draggingEntered(scene.drag) == .copy)
        let region = try #require(scene.split.subviews.first { $0 !== scene.pageA && $0 !== scene.pageB })
        scene.place(NSPoint(x: 200, y: 200))
        receiver.draggingExited(scene.drag)
        try #require(scene.host.draggingEntered(scene.drag) == .copy)
        receiver.draggingEnded(scene.drag)
        try #require(region.superview === scene.split)
        let finishCollapse = try #require(complete)

        finishCollapse()

        #expect(region.superview == nil)
        #expect(scene.split.subviews == [scene.pageA, scene.pageB])
    }
}
