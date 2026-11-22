import AppKit
import ParcCore
import Testing
@testable import Parc

@MainActor private final class Scene {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1810, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
    let host = ExternalSplitDropHost(frame: NSRect(x: 0, y: 0, width: 1810, height: 700))
    let split: ParcSplitView
    let pageA: SplitDropReservedPane, pageB: SplitDropReservedPane
    let drag: SplitDropDragInfo
    let router: SplitDropRouterDouble
    let originalFrames: [NSRect]
    var buttonDown = true
    var commits = 0, admits = 0
    var sessionValid = true
    var commitResult = true
    var geometryRestoredAtCommit = true
    var editing: [Bool] = []

    init() {
        window.isReleasedWhenClosed = false
        window.contentView = host
        split = ParcSplitView(frame: host.bounds)
        host.addSubview(split)
        pageA = SplitDropReservedPane(frame: host.bounds)
        pageB = SplitDropReservedPane(frame: host.bounds)
        split.addArrangedSubview(pageA)
        split.addArrangedSubview(pageB)
        split.configure(orientation: .horizontal, factors: [0.75, 0.25])
        split.constrain(to: host)
        originalFrames = split.arrangedSubviews.map(\.frame)
        drag = SplitDropDragInfo(window: window)
        drag.draggingPasteboard.setString("https://handoff.invalid/path", forType: .URL)
        router = SplitDropRouterDouble(view: pageA.body)
        split.primaryMouseButtonIsDown = { [weak self] in self?.buttonDown ?? false }
        split.onInteractivePaneEditing = { [weak self] in self?.editing.append($0) }
        host.makeSession = { [weak self] _, info in
            guard let self else { return nil }
            admits += 1
            let reservation = immediate(split.prepareDropReservation(in: host, contents: [pageA.body, pageB.body])!)
            return ExternalSplitDropSession(host: host, info: info,
                frames: [pageA.body, pageB.body].map { $0.convert($0.bounds, to: self.host) }, orientation: .horizontal,
                reservation: reservation, validate: { [weak self] in (self?.sessionValid ?? false) && reservation.isCurrent },
                insertionColor: { .black }, canPropose: { _, _ in true },
                commit: { [weak self] _, _ in
                    guard let self else { return false }
                    geometryRestoredAtCommit = geometryRestoredAtCommit && split.arrangedSubviews.map(\.frame) == originalFrames
                    commits += 1
                    return commitResult
                })
        }
    }

    func place(_ point: NSPoint) { drag.draggingLocation = host.convert(point, to: nil) }

    func enterLeftEdge(with router: SplitDropRouterDouble? = nil) -> Bool {
        place(NSPoint(x: 1, y: 200))
        return (router ?? self.router).begin(drag)
    }

    func leaveToHostRegion() {
        place(NSPoint(x: 200, y: 200))
        router.exit(drag)
    }

    func beginHandoff() {
        #expect(enterLeftEdge() && router.operation == .copy)
        #expect(split.arrangedSubviews.map(\.frame) != originalFrames)
        #expect(split.arrangedSubviews.count == 2)
        leaveToHostRegion()
        #expect(host.draggingEntered(drag) == .copy)
    }

    func leaveThePage(with router: SplitDropRouterDouble? = nil) {
        place(NSPoint(x: 1700, y: 200))
        (router ?? self.router).exit(drag)
    }

    func continuingSessions() {
        let plain = host.makeSession
        host.makeSession = { view, info in
            let session = plain?(view, info)
            session?.admitsReceiver = { _, _ in true }
            return session
        }
    }
}

@MainActor struct ExternalSplitDropHandoffTests {
    @Test func anUnclaimedHostLinkCannotCreateASession() {
        let scene = Scene()
        #expect(scene.host.draggingEntered(scene.drag).isEmpty)
        #expect(scene.admits == 0)
    }

    @Test func originalContentAdmitsAnExternalLinkAndReservesLayoutWithoutANewPageOwner() {
        let scene = Scene()
        #expect(scene.enterLeftEdge())
        #expect(scene.router.operation == .copy)
        #expect(scene.split.arrangedSubviews.map(\.frame) != scene.originalFrames)
        #expect(scene.split.arrangedSubviews.count == 2)
    }

    @Test func anAdmittedLinkBeginsPaneEditingBeforeItsReservedLayout() {
        let scene = Scene()
        scene.beginHandoff()
        #expect(scene.editing == [true])
        #expect(scene.split.isInteractivePaneEditing)
    }

    @Test func oneNativeGesturePerformsOnceThroughTheOriginalReceiver() {
        let scene = Scene()
        scene.beginHandoff()
        #expect(scene.host.performDragOperation(scene.drag))
        #expect(scene.commits == 1)
        #expect(scene.admits == 1)
        #expect(scene.geometryRestoredAtCommit)
    }

    @Test func aPerformedDropEndsInteractiveEditing() {
        let scene = Scene()
        scene.beginHandoff()
        _ = scene.host.performDragOperation(scene.drag)
        #expect(scene.editing == [true, false])
        #expect(!scene.split.isInteractivePaneEditing)
    }

    @Test func lateHostCallbacksCannotReplayOrLeaveARegion() {
        let scene = Scene()
        scene.beginHandoff()
        _ = scene.host.performDragOperation(scene.drag)
        #expect(!scene.host.performDragOperation(scene.drag))
        #expect(scene.commits == 1)
        #expect(scene.split.subviews.count == 2)
    }

    @Test func theOriginalTerminalCallbackCancelsTheHandoffAndRestoresTheExactLayout() {
        let scene = Scene()
        scene.beginHandoff()
        scene.router.end()
        #expect(scene.host.draggingUpdated(scene.drag).isEmpty)
        #expect(scene.commits == 0)
        #expect(scene.split.arrangedSubviews.map(\.frame) == scene.originalFrames)
        #expect(scene.editing == [true, false])
    }

    @Test func leavingThePageEndsItsPreviewButKeepsTheEditAndTheRouterAsTerminalWitness() {
        let scene = Scene()
        #expect(scene.enterLeftEdge())
        scene.leaveThePage()
        #expect(scene.router.claimed)
        #expect(scene.split.arrangedSubviews.map(\.frame) == scene.originalFrames)
        #expect(scene.editing == [true])
        #expect(scene.split.isInteractivePaneEditing)
    }

    @Test func theWitnessRouterCannotDropThroughTheHost() {
        let scene = Scene()
        #expect(scene.enterLeftEdge())
        scene.leaveThePage()
        #expect(scene.host.draggingUpdated(scene.drag).isEmpty)
        #expect(!scene.host.prepareForDragOperation(scene.drag))
    }

    @Test func reenteringTheSamePageResumesTheEditBeforeAnyLayout() {
        let scene = Scene()
        #expect(scene.enterLeftEdge())
        scene.leaveThePage()
        #expect(scene.enterLeftEdge())
        #expect(scene.split.isInteractivePaneEditing)
        #expect(scene.editing.last == true)
    }

    @Test func theExitedPageViewsTerminalEndEndsTheEdit() {
        let scene = Scene()
        #expect(scene.enterLeftEdge())
        scene.leaveThePage()
        scene.router.end()
        #expect(!scene.router.claimed)
        #expect(!scene.split.isInteractivePaneEditing)
        #expect(scene.editing.last == false)
    }

    @Test func outsideThePageWithTheButtonHeldTheEditStays() {
        let scene = Scene()
        #expect(scene.enterLeftEdge())
        scene.leaveThePage()
        scene.split.interactivePaneEdit?.endIfDragReleased()
        #expect(scene.split.isInteractivePaneEditing)
    }

    @Test func enteringTheOtherPageBeforeReleaseContinuesTheSameEdit() {
        let scene = Scene()
        #expect(scene.enterLeftEdge())
        scene.leaveThePage()
        let before = scene.editing
        let routerB = SplitDropRouterDouble(view: scene.pageB.body)
        #expect(routerB.begin(scene.drag))
        #expect(scene.split.isInteractivePaneEditing)
        #expect(scene.editing == before)
    }

    @Test func whileAPageHasTheDragButtonStateCannotEndTheEdit() {
        let scene = Scene()
        #expect(scene.enterLeftEdge())
        scene.leaveThePage()
        let routerB = SplitDropRouterDouble(view: scene.pageB.body)
        #expect(routerB.begin(scene.drag))
        scene.buttonDown = false
        scene.split.interactivePaneEdit?.endIfDragReleased()
        #expect(scene.split.isInteractivePaneEditing)
    }

    @Test func leavingTheOtherPageKeepsTheEdit() {
        let scene = Scene()
        #expect(scene.enterLeftEdge())
        scene.leaveThePage()
        let routerB = SplitDropRouterDouble(view: scene.pageB.body)
        #expect(routerB.begin(scene.drag))
        routerB.exit(scene.drag)
        #expect(scene.split.isInteractivePaneEditing)
        #expect(routerB.claimed)
    }

    @Test func withNoRouteHoldingTheDragButtonReleaseEndsTheEdit() {
        let scene = Scene()
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
        let scene = Scene()
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
        let scene = Scene()
        scene.beginHandoff()
        scene.sessionValid = false
        scene.host.validateDrop()
        #expect(scene.host.draggingUpdated(scene.drag).isEmpty)
        #expect(!scene.host.performDragOperation(scene.drag))
        #expect(scene.commits == 0)
    }

    @Test func leavingTheReservedHostAreaCancelsRatherThanRetainingAStrandedDraft() {
        let scene = Scene()
        scene.beginHandoff()
        scene.host.draggingExited(scene.drag)
        #expect(scene.split.arrangedSubviews.map(\.frame) == scene.originalFrames)
        #expect(!scene.host.prepareForDragOperation(scene.drag))
        #expect(scene.split.isInteractivePaneEditing)
        #expect(scene.router.claimed)
    }

    @Test func theHostsTerminalDraggingEndedEndsTheEdit() {
        let scene = Scene()
        scene.beginHandoff()
        scene.host.draggingExited(scene.drag)
        scene.host.draggingEnded(scene.drag)
        #expect(!scene.split.isInteractivePaneEditing)
    }

    @Test func aForeignSequenceCannotEnterTheOldReservedRegion() {
        let scene = Scene()
        scene.beginHandoff()
        scene.drag.draggingSequenceNumber += 1
        #expect(scene.host.draggingUpdated(scene.drag).isEmpty)
        #expect(scene.split.subviews.count == 2)
    }

    @Test func aRefusedCommitRemovesTheReservationAndReportsFailure() {
        let scene = Scene()
        scene.commitResult = false
        scene.beginHandoff()
        #expect(!scene.host.performDragOperation(scene.drag))
        #expect(scene.commits == 1)
        #expect(scene.split.subviews.count == 2)
    }

    @Test func detachingTheOriginalReceiverCannotRetargetARemainingPane() {
        let scene = Scene()
        scene.beginHandoff()
        scene.pageA.removeFromSuperview()
        #expect(scene.host.draggingUpdated(scene.drag).isEmpty)
        #expect(!scene.host.performDragOperation(scene.drag))
        #expect(scene.commits == 0)
    }

    @Test func aContinuingLinkSessionStartsOnTheFirstPage() {
        let scene = Scene()
        scene.continuingSessions()
        #expect(scene.enterLeftEdge())
        #expect(scene.admits == 1)
    }

    @Test func theGapBetweenPagesKeepsTheLinkDragAndItsOpenPreview() {
        let scene = Scene()
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
        let scene = Scene()
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

    private func pageToHostToPage() -> (Scene, NSView?) {
        let scene = Scene()
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

    @Test func theLocalDocumentForwarderAdmitsTheSameNativeReservation() {
        let scene = Scene()
        let receiver = LocalContentDropView(frame: scene.pageA.body.bounds)
        scene.pageA.body.addSubview(receiver)
        scene.place(NSPoint(x: 1, y: 200))
        #expect(receiver.draggingEntered(scene.drag) == .copy)
    }

    @Test func aLocalExitForwardsTheExactRouterInsteadOfTerminatingBeforeHostEntry() {
        let scene = Scene()
        let receiver = LocalContentDropView(frame: scene.pageA.body.bounds)
        scene.pageA.body.addSubview(receiver)
        scene.place(NSPoint(x: 1, y: 200))
        _ = receiver.draggingEntered(scene.drag)
        scene.place(NSPoint(x: 200, y: 200))
        receiver.draggingExited(scene.drag)
        #expect(scene.host.draggingEntered(scene.drag) == .copy)
        #expect(scene.host.performDragOperation(scene.drag))
        #expect(scene.commits == 1)
    }

    @Test func aLateLocalTerminalCallbackLeavesTheOriginalsAndTheConsumedTransactionUnchanged() {
        let scene = Scene()
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
        let scene = Scene()
        let receiver = LocalContentDropTextView(frame: scene.pageA.body.bounds)
        scene.pageA.body.addSubview(receiver)
        scene.place(NSPoint(x: 1, y: 200))
        #expect(receiver.draggingEntered(scene.drag) == .copy)
    }

    @Test func aTextReceiverExitRetainsTheOriginalHandoff() {
        let scene = Scene()
        let receiver = LocalContentDropTextView(frame: scene.pageA.body.bounds)
        scene.pageA.body.addSubview(receiver)
        scene.place(NSPoint(x: 1, y: 200))
        _ = receiver.draggingEntered(scene.drag)
        scene.place(NSPoint(x: 200, y: 200))
        receiver.draggingExited(scene.drag)
        #expect(scene.host.draggingEntered(scene.drag) == .copy)
    }

    @Test func aTextReceiversTerminalCleanupCancelsTheSameHandoffAndRestoresAuthority() {
        let scene = Scene()
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
        let scene = Scene()
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

@MainActor private final class HeaderScene {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1810, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
    let host = ExternalSplitDropHost(frame: NSRect(x: 0, y: 0, width: 1810, height: 700))
    let split: ParcSplitView
    let page: SplitDropReservedPane
    let drag: SplitDropDragInfo
    let router: SplitDropRouterDouble
    let item: NSDraggingItem
    let linkImage = NSImage(size: NSSize(width: 120, height: 20))
    var targets: [(SplitDropTarget, SplitOrientation)] = []

    init() {
        window.isReleasedWhenClosed = false
        window.contentView = host
        split = ParcSplitView(frame: host.bounds)
        host.addSubview(split)
        page = SplitDropReservedPane(frame: host.bounds)
        split.addArrangedSubview(page)
        split.configure(orientation: .horizontal, factors: [1])
        split.constrain(to: host)
        drag = SplitDropDragInfo(window: window)
        drag.draggingPasteboard.setString("https://header.invalid/path", forType: .URL)
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString("https://header.invalid/path", forType: .URL)
        item = NSDraggingItem(pasteboardWriter: pasteboardItem)
        item.setDraggingFrame(NSRect(x: 40, y: 50, width: 120, height: 20), contents: linkImage)
        drag.items = [item]
        router = SplitDropRouterDouble(view: page.body)
        host.makeSession = { [weak self] _, info in
            guard let self else { return nil }
            let reservation = immediate(split.prepareDropReservation(in: host, contents: [page.body])!)
            return ExternalSplitDropSession(host: host, info: info, frames: [], orientation: .horizontal,
                reservation: reservation, validate: { reservation.isCurrent }, insertionColor: { .black },
                canPropose: { _, _ in true }, commit: { [weak self] target, orientation in self?.targets.append((target, orientation)); return true })
        }
    }

    var cardSize: NSSize {
        SplitDropPlaceholderCard.size(forIncomingPane: NSSize(width: split.bounds.width / 2, height: split.bounds.height))!
    }

    func place(_ point: NSPoint) { drag.draggingLocation = host.convert(point, to: nil) }
}

@MainActor struct ExternalSplitDropPlaceholderCardTests {
    @Test func theAdmittedLinkBecomesAPlaceholderCardAtItsOwnBottomLeft() {
        let scene = HeaderScene()
        scene.place(NSPoint(x: 905, y: 400))
        #expect(scene.router.begin(scene.drag))
        #expect(scene.router.operation == .copy)
        let image = scene.item.imageComponentsProvider?().first?.contents as? NSImage
        #expect(image !== scene.linkImage)
        #expect(image?.size == scene.cardSize)
        #expect(scene.item.draggingFrame == NSRect(origin: NSPoint(x: 40, y: 50), size: scene.cardSize))
    }

    @Test func aSinglePanesHeaderIsInItsFiftyPointTopZone() {
        let scene = HeaderScene()
        scene.place(NSPoint(x: 905, y: 400))
        _ = scene.router.begin(scene.drag)
        scene.place(NSPoint(x: scene.page.frame.midX, y: 20))
        scene.router.exit(scene.drag)
        #expect(scene.host.draggingEntered(scene.drag) == .copy)
        #expect(scene.host.performDragOperation(scene.drag))
        #expect(scene.targets.count == 1)
        #expect(scene.targets.first?.0 == .insert(0))
        #expect(scene.targets.first?.1 == .vertical)
    }

    @Test func aPerformedDropKeepsTheCardReshapedForItsTarget() {
        let scene = HeaderScene()
        scene.place(NSPoint(x: 905, y: 400))
        _ = scene.router.begin(scene.drag)
        scene.place(NSPoint(x: scene.page.frame.midX, y: 20))
        scene.router.exit(scene.drag)
        _ = scene.host.draggingEntered(scene.drag)
        _ = scene.host.performDragOperation(scene.drag)
        let topZone = SplitDropPlaceholderCard.size(forIncomingPane: NSSize(width: scene.split.bounds.width, height: scene.split.bounds.height / 2))
        #expect(scene.item.draggingFrame.size == topZone)
        #expect((scene.item.imageComponentsProvider?().first?.contents as? NSImage) !== scene.linkImage)
    }

    @Test func aNewEntryShowsTheCardAgain() {
        let scene = HeaderScene()
        scene.place(NSPoint(x: 905, y: 400))
        _ = scene.router.begin(scene.drag)
        scene.router.end()
        scene.item.setDraggingFrame(NSRect(x: 40, y: 50, width: 120, height: 20), contents: scene.linkImage)
        scene.place(NSPoint(x: 905, y: 400))
        #expect(scene.router.begin(scene.drag))
        #expect(scene.item.draggingFrame.size == scene.cardSize)
    }

    @Test func leavingTheSplitGivesTheLinkItsOwnImageBack() {
        let scene = HeaderScene()
        scene.place(NSPoint(x: 905, y: 400))
        _ = scene.router.begin(scene.drag)
        scene.place(NSPoint(x: scene.page.frame.midX, y: scene.page.frame.maxY + 40))
        scene.router.exit(scene.drag)
        #expect(scene.item.draggingFrame == NSRect(x: 40, y: 50, width: 120, height: 20))
        #expect((scene.item.imageComponentsProvider?().first?.contents as? NSImage) === scene.linkImage)
    }
}
