import AppKit
import ParcCore
import QuartzCore
import Testing
@testable import Parc

@MainActor
struct SplitDropReservationEditingTests {
    @Test func aLeaseAloneIsNotInteractivePaneEditing() {
        let scene = SplitDropReservationSupport.Scene()
        _ = scene.lease()
        #expect(scene.editing.isEmpty)
        #expect(!scene.split.isInteractivePaneEditing)
    }

    @Test func theFirstAdmittedEntryBeginsEditing() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        #expect(lease.beginInteractivePaneEdit() != nil)
        #expect(scene.editing == [true])
        #expect(scene.split.isInteractivePaneEditing)
    }

    @Test func leavingThePaneAreaKeepsEditingUntilTheDragEnds() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        _ = lease.beginInteractivePaneEdit()
        _ = scene.leave(lease)
        #expect(scene.editing == [true])
        #expect(scene.split.isInteractivePaneEditing)
    }

    @Test func clearingPaneMotionAlsoCancelsThePaneHighlightsPathTransition() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        lease.clear()
        #expect(scene.panes.contains { $0.cancelled > 0 })
    }

    @Test func endingALeaseIsOneShotAndRetainsTheOriginalOwners() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        lease.end()
        lease.end()
        #expect(lease.ended)
        #expect(!lease.isCurrent)
        #expect(scene.split.subviews.count == 2)
    }

    @Test func theDragsEditOutlivesItsLease() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        let edit = lease.beginInteractivePaneEdit()
        lease.end()
        #expect(scene.editing == [true])
        #expect(scene.split.isInteractivePaneEditing)
        #expect(lease.beginInteractivePaneEdit() == nil)
        withExtendedLifetime(edit) {}
    }

    @Test func endingTheDragEndsAnEditWhoseLeaseAlreadyEnded() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        let edit = lease.beginInteractivePaneEdit()
        lease.end()
        _ = lease.beginInteractivePaneEdit()
        edit?.end()
        edit?.end()
        #expect(scene.editing == [true, false])
        #expect(!scene.split.isInteractivePaneEditing)
    }

    @Test func aRefusedInsertionKeepsTheGenuineReplacementWithoutReservingLayout() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        let replace = lease.proposal(at: NSPoint(x: 1, y: 200), canPropose: { target, _ in
            if case .replace = target { return true }
            return false
        })!
        #expect(replace.0 == .replace(0))
        #expect(scene.split.arrangedSubviews.map(\.frame) == scene.originalFrames)
        #expect(!lease.reusedRegion)
    }

    @Test func aPointerOverAPaneHeaderTargetsThatPanesEdge() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        let header = lease.proposal(at: NSPoint(x: 1, y: 20), canPropose: scene.allowAll)
        #expect(header?.0 == .insert(0))
        #expect(header?.2.minY == 0)
        #expect(header?.2.height == 700)
    }

    @Test func endingAHeaderReservationRestoresTheOriginalFrames() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        _ = lease.proposal(at: NSPoint(x: 1, y: 20), canPropose: scene.allowAll)
        lease.end()
        #expect(scene.split.arrangedSubviews.map(\.frame) == scene.originalFrames)
    }
}
