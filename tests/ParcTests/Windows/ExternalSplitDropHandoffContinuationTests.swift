import AppKit
import ParcCore
import Testing
@testable import Parc

@MainActor
struct ExternalSplitDropHandoffContinuationTests {
    @Test func aContinuingLinkSessionStartsOnTheFirstPage() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        scene.continuingSessions()
        #expect(scene.enterLeftEdge())
        #expect(scene.admits == 1)
    }

    @Test func theGapBetweenPagesKeepsTheLinkDragAndItsOpenPreview() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        scene.continuingSessions()
        _ = scene.enterLeftEdge()
        let region = scene.split.subviews.first { $0 !== scene.pageA && $0 !== scene.pageB }
        scene.place(NSPoint(x: scene.pageA.frame.maxX + 5, y: 200))
        scene.router.exit(scene.drag)
        #expect(scene.host.draggingEntered(scene.drag) == .copy)
        #expect(region?.superview === scene.split)
        #expect(region?.layer?.opacity == 1)
    }

    @Test func theHostsExitIntoAPagesContentLeavesTheSessionForThatPageToCarryOn() {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        scene.continuingSessions()
        _ = scene.enterLeftEdge()
        let region = scene.split.subviews.first { $0 !== scene.pageA && $0 !== scene.pageB }
        scene.place(NSPoint(x: scene.pageA.frame.maxX + 5, y: 200))
        scene.router.exit(scene.drag)
        _ = scene.host.draggingEntered(scene.drag)
        scene.place(NSPoint(x: scene.pageA.frame.minX + 40, y: 200))
        scene.host.draggingExited(scene.drag)
        #expect(region?.superview === scene.split)
        #expect(region?.layer?.opacity == 1)
    }

    private func pageToHostToPage() -> (ExternalSplitDropHandoffSupport.Scene, NSView?) {
        let scene = ExternalSplitDropHandoffSupport.Scene()
        scene.continuingSessions()
        _ = scene.enterLeftEdge()
        let region = scene.split.subviews.first { $0 !== scene.pageA && $0 !== scene.pageB }
        scene.place(NSPoint(x: scene.pageA.frame.maxX + 5, y: 200))
        scene.router.exit(scene.drag)
        _ = scene.host.draggingEntered(scene.drag)
        scene.place(NSPoint(x: scene.pageA.frame.minX + 40, y: 200))
        scene.host.draggingExited(scene.drag)
        return (scene, region)
    }

    @Test func comingBackIntoTheSamePageContinuesTheSessionWithoutRestartingTheEdit() {
        let (scene, region) = pageToHostToPage()
        let editsBefore = scene.editing
        #expect(scene.router.begin(scene.drag))
        #expect(scene.router.claimed)
        #expect(scene.router.operation == .copy)
        #expect(scene.admits == 1)
        #expect(region?.layer?.opacity == 1)
        #expect(scene.split.isInteractivePaneEditing)
        #expect(scene.editing == editsBefore)
    }

    @Test func theDeferredTeardownsAreCancelledOnceTheSameDragCarriesOn() async {
        let (scene, region) = pageToHostToPage()
        let editsBefore = scene.editing
        _ = scene.router.begin(scene.drag)
        await settleMainQueue()
        #expect(region?.superview === scene.split)
        #expect(region?.layer?.opacity == 1)
        #expect(scene.host.contentView(scene.pageA.body, updateDrop: scene.drag) == .copy)
        #expect(scene.editing == editsBefore)
    }

    @Test func jumpingStraightFromOnePageIntoTheNextKeepsTheSessionForTheNextPage() {
        let (scene, region) = pageToHostToPage()
        _ = scene.router.begin(scene.drag)
        scene.place(NSPoint(x: scene.pageB.frame.maxX - 10, y: 200))
        scene.router.exit(scene.drag)
        #expect(scene.router.claimed)
        #expect(region?.layer?.opacity == 1)
    }

    @Test func enteringTheNextPageContinuesTheSameSessionAndEndsTheOldPagesRouter() {
        let (scene, region) = pageToHostToPage()
        _ = scene.router.begin(scene.drag)
        let editsBefore = scene.editing
        scene.place(NSPoint(x: scene.pageB.frame.maxX - 10, y: 200))
        scene.router.exit(scene.drag)
        let routerB = SplitDropRouterDouble(view: scene.pageB.body)
        #expect(routerB.begin(scene.drag))
        #expect(routerB.operation == .copy)
        #expect(scene.admits == 1)
        #expect(region?.superview === scene.split)
        #expect(region?.layer?.opacity == 1)
        #expect(scene.split.isInteractivePaneEditing)
        #expect(scene.editing == editsBefore)
        #expect(!scene.router.claimed)
    }

    @Test func theNextPageKeepsTheContinuedSessionAfterTheDeferredTeardownWouldHaveRun() async {
        let (scene, region) = pageToHostToPage()
        _ = scene.router.begin(scene.drag)
        scene.place(NSPoint(x: scene.pageB.frame.maxX - 10, y: 200))
        scene.router.exit(scene.drag)
        let routerB = SplitDropRouterDouble(view: scene.pageB.body)
        _ = routerB.begin(scene.drag)
        await settleMainQueue()
        #expect(region?.layer?.opacity == 1)
        #expect(scene.host.contentView(scene.pageB.body, updateDrop: scene.drag) == .copy)
    }

    @Test func theContinuedSessionDropsThroughThePageItMovedInto() {
        let (scene, _) = pageToHostToPage()
        _ = scene.router.begin(scene.drag)
        scene.place(NSPoint(x: scene.pageB.frame.maxX - 10, y: 200))
        scene.router.exit(scene.drag)
        let routerB = SplitDropRouterDouble(view: scene.pageB.body)
        _ = routerB.begin(scene.drag)
        scene.place(NSPoint(x: scene.pageB.frame.maxX - 10, y: 200))
        #expect(routerB.perform(scene.drag))
        #expect(scene.commits == 1)
        #expect(scene.split.subviews.count == 2)
    }
}
