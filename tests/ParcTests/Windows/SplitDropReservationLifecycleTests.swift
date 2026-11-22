import AppKit
import ParcCore
import QuartzCore
import Testing
@testable import Parc

@MainActor
struct SplitDropReservationLifecycleTests {
    @Test func anAuthoritativeLayoutRetiresTheLeaseAndKeepsTheDragEdit() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        _ = lease.beginInteractivePaneEdit()
        _ = scene.leftEdge(lease)
        scene.split.configure(orientation: .vertical, factors: [0.5, 0.5])
        #expect(scene.editing == [true])
        #expect(scene.split.isInteractivePaneEditing)
        #expect(lease.ended)
        #expect(!lease.isCurrent)
        #expect(scene.split.subviews.count == 2)
        #expect(!scene.split.isVertical)
    }

    @Test func endingAStaleLeaseLeavesAuthoritativeGeometryInPlace() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        _ = lease.beginInteractivePaneEdit()
        _ = scene.leftEdge(lease)
        scene.split.configure(orientation: .vertical, factors: [0.5, 0.5])
        lease.end()
        #expect(!scene.split.isVertical)
        #expect(scene.first.layer?.animation(forKey: "Split reserved layout") == nil)
    }

    @Test func aNewDragsEditReplacesAnUnterminatedOneWithoutAGap() {
        let scene = SplitDropReservationSupport.Scene()
        let stale = scene.lease()
        let staleEdit = stale.beginInteractivePaneEdit()
        scene.split.configure(orientation: .vertical, factors: [0.5, 0.5])
        let next = scene.lease()
        let nextEdit = next.beginInteractivePaneEdit()
        #expect(staleEdit?.ended == true)
        #expect(nextEdit?.ended == false)
        #expect(scene.editing == [true])
    }

    @Test func endingThePreviousDragsEditLeavesTheNewEditActive() {
        let scene = SplitDropReservationSupport.Scene()
        let stale = scene.lease()
        let staleEdit = stale.beginInteractivePaneEdit()
        scene.split.configure(orientation: .vertical, factors: [0.5, 0.5])
        let next = scene.lease()
        let nextEdit = next.beginInteractivePaneEdit()
        staleEdit?.end()
        #expect(scene.editing == [true])
        #expect(scene.split.isInteractivePaneEditing)
        withExtendedLifetime(nextEdit) {}
    }

    @Test func endingTheCurrentDragsEditClosesItOnce() {
        let scene = SplitDropReservationSupport.Scene()
        let stale = scene.lease()
        let staleEdit = stale.beginInteractivePaneEdit()
        scene.split.configure(orientation: .vertical, factors: [0.5, 0.5])
        let next = scene.lease()
        let nextEdit = next.beginInteractivePaneEdit()
        staleEdit?.end()
        nextEdit?.end()
        #expect(scene.editing == [true, false])
    }

    @Test func anIncomingPaneAtATopAndBottomSplitsTopEdgeIsTheSplitWideAndAThirdHigh() {
        let scene = SplitDropReservationSupport.Scene()
        scene.split.configure(orientation: .vertical, factors: [0.5, 0.5])
        let lease = scene.lease()
        let topEdge = lease.proposal(at: NSPoint(x: 200, y: 41), canPropose: scene.allowAll)
        #expect(topEdge?.0 == .insert(0))
        #expect(topEdge?.1 == .vertical)
        #expect(lease.incomingPaneSize == NSSize(width: scene.split.bounds.width, height: scene.split.bounds.height / 3))
    }

    @Test func anOutsideHostResizeIsNeverAcceptedAsOwnedPreviewGeometry() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        scene.host.frame.size.width += 30
        #expect(!lease.isCurrent)
    }

    @Test func anAdmissionCallbackThatRetiresTheLeaseCannotAttachAnOrphanRegion() {
        let scene = SplitDropReservationSupport.Scene()
        scene.split.configure(orientation: .vertical, factors: [0.5, 0.5])
        let lease = scene.lease()
        let proposal = lease.proposal(at: NSPoint(x: 200, y: 41), canPropose: { _, _ in
            scene.split.configure(orientation: .horizontal, factors: [0.75, 0.25])
            return true
        })
        #expect(proposal == nil)
        #expect(lease.ended)
        #expect(scene.split.subviews.count == 2)
    }

    @Test func cancellingRetiresTheLeaseSynchronouslyBeforePassivePresentationFinishes() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        let before = scene.split.arrangedSubviews.map(\.frame)
        _ = scene.leftEdge(lease)
        lease.end(animated: true)
        #expect(lease.ended)
        #expect(!lease.isCurrent)
        #expect(scene.split.arrangedSubviews.map(\.frame) == before)
    }

    @Test func thePassiveCollapseCompletionRemovesItsOwnRegion() throws {
        let scene = SplitDropReservationSupport.Scene()
        var complete: (@MainActor () -> Void)?
        scene.split.registerDropRegionCompletion = { complete = $0 }
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        let region = try #require(scene.region())
        lease.end(animated: true)
        try #require(region.superview === scene.split)
        let finishCollapse = try #require(complete)

        finishCollapse()

        #expect(region.superview == nil)
        #expect(scene.split.subviews == scene.panes)
    }

    @Test func theOriginalWindowResigningKeyClearsTheTerminalBorderAndTransition() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        lease.end(animated: true)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: scene.window)
        #expect(scene.first.layer?.animation(forKey: "Split reserved layout") == nil)
        #expect(scene.split.subviews.count == 2)
    }

    @Test func hidingTheSplitRevokesTheGestureAndBorderPresentationAtOnce() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        scene.split.isHidden = true
        #expect(lease.ended)
        #expect(scene.split.subviews.count == 2)
        #expect(scene.first.layer?.animation(forKey: "Split reserved layout") == nil)
    }
}
