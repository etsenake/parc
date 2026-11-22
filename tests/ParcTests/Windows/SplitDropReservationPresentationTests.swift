import AppKit
import ParcCore
import QuartzCore
import Testing
@testable import Parc

@MainActor
struct SplitDropReservationPresentationTests {
    @Test func retargetingReordersTheSameReservedRegion() throws {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        let region = try #require(scene.region())
        let moved = lease.proposal(at: NSPoint(x: scene.second.frame.maxX - 1, y: 200), canPropose: scene.allowAll)!
        #expect(moved.0 == .insert(2))
        #expect(scene.split.subviews.contains { $0 === region })
        #expect(!lease.reusedRegion)
    }

    @Test func leavingRestoresTheOriginalFramesWithoutAModelTransaction() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        #expect(scene.leave(lease) == nil)
        #expect(scene.split.arrangedSubviews.map(\.frame) == scene.originalFrames)
    }

    @Test func aCollapsedBorderNeverRemainsAValidDropRegion() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        let insert = scene.leftEdge(lease)
        _ = scene.leave(lease)
        #expect(lease.isCurrent)
        #expect(!lease.containsReservedPoint(NSPoint(x: insert.2.midX, y: insert.2.midY)))
    }

    @Test func aNormalExitSynchronouslyPublishesTheCollapsedBorder() throws {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        let region = try #require(scene.region())
        _ = scene.leave(lease)
        #expect(region.layer?.opacity == 0)
        #expect(region.frame.width == 0)
    }

    @Test func onlyThePassiveBorderRemainsDuringItsExitTransition() throws {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        let region = try #require(scene.region())
        _ = scene.leave(lease)
        #expect(region.superview === scene.split)
        #expect(region.layer?.animation(forKey: "Split drop region") != nil)
        #expect(scene.first.layer?.animation(forKey: "Split reserved layout") != nil)
    }

    @Test func reenteringReusesTheRetiringRegionAndSupersedesItsTransition() throws {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        let region = try #require(scene.region())
        _ = lease.proposal(at: NSPoint(x: scene.second.frame.maxX - 1, y: 200), canPropose: scene.allowAll)
        _ = scene.leave(lease)
        _ = scene.leftEdge(lease)
        #expect(scene.split.subviews.contains { $0 === region })
        #expect(region.layer?.opacity == 1)
        #expect(!lease.reusedRegion)
    }

    @Test(arguments: [false, true])
    func returningToTheSameSlotOnlyAsksForFeedbackAfterCollapseCompletes(collapseCompleted: Bool) throws {
        let scene = SplitDropReservationSupport.Scene()
        var complete: (@MainActor () -> Void)?
        scene.split.registerDropRegionCompletion = { complete = $0 }
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        _ = scene.leave(lease)
        _ = scene.leftEdge(lease)
        _ = scene.leave(lease)
        let finishCollapse = try #require(complete)
        if collapseCompleted { finishCollapse() }
        _ = scene.leftEdge(lease)
        #expect(lease.reusedRegion == !collapseCompleted)
        #expect(lease.appeared == collapseCompleted)
    }

    @Test func aReenteredRegionSurvivesItsOldCollapseCompletion() throws {
        let scene = SplitDropReservationSupport.Scene()
        var complete: (@MainActor () -> Void)?
        scene.split.registerDropRegionCompletion = { complete = $0 }
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        let region = try #require(scene.region())
        _ = scene.leave(lease)
        let finishCollapse = try #require(complete)
        _ = scene.leftEdge(lease)

        finishCollapse()

        #expect(region.superview === scene.split)
        #expect(region.layer?.opacity == 1)
    }

    @Test func clearingSynchronouslyRemovesTheBorderAndItsAnimation() throws {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        let region = try #require(scene.region())
        lease.clear()
        #expect(region.superview == nil)
        #expect(region.layer?.animation(forKey: "Split drop region") == nil)
    }

    @Test func clearingRestoresGeometryAndEndsMotionWhileKeepingValidationAlive() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        lease.clear()
        #expect(lease.isCurrent)
        #expect(scene.split.arrangedSubviews.map(\.frame) == scene.originalFrames)
        #expect(scene.first.layer?.animation(forKey: "Split reserved layout") == nil)
    }
}
