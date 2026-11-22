import AppKit
import ParcCore
import QuartzCore
import Testing
@testable import Parc

@MainActor
struct SplitDropReservationGeometryTests {
    @Test func onePresentationLeaseAdmitsOnlyTheExactOriginalSurfaces() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        #expect(lease.isCurrent)
        #expect(scene.split.prepareDropReservation(in: scene.host, contents: scene.panes.map(\.body)) == nil)
    }

    @Test func aReservedInsertionKeepsItsIdentityAndTheWholePaneSlotIncludingTheHeader() {
        let scene = SplitDropReservationSupport.Scene()
        let insert = scene.leftEdge(scene.lease())
        #expect(insert.0 == .insert(0))
        #expect(insert.1 == .horizontal)
        #expect(insert.2.minY == 0)
        #expect(insert.2.height == 700)
    }

    @Test func theIncomingPaneIsTheSplitsWidthOverOneMorePane() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        #expect(lease.incomingPaneSize == NSSize(width: scene.split.bounds.width / 3, height: scene.split.bounds.height))
    }

    @Test func aNewInsertionSlotHasNoExistingDropRegion() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        #expect(!lease.reusedRegion)
    }

    @Test func thePaneHighlightFollowsFromTheLayersPreviousBoundsOverTwoTenths() {
        let scene = SplitDropReservationSupport.Scene()
        _ = scene.leftEdge(scene.lease())
        #expect(scene.first.followed.contains { $0.duration == 0.2 && $0.previous != scene.first.layer?.bounds })
    }

    @Test func presentationNeverInsertsAPageIntoTheOriginalArrangedOwners() {
        let scene = SplitDropReservationSupport.Scene()
        _ = scene.leftEdge(scene.lease())
        #expect(scene.split.arrangedSubviews.count == 2)
        #expect(scene.split.arrangedSubviews[0] === scene.first)
        #expect(scene.split.arrangedSubviews[1] === scene.second)
    }

    @Test func theIncomingRegionGetsAThirdWhileOriginalsKeepTheirThreeToOneRatio() {
        let scene = SplitDropReservationSupport.Scene()
        let insert = scene.leftEdge(scene.lease())
        #expect(abs(insert.2.width - 597) <= 1)
        #expect(abs(scene.first.frame.width - 895) <= 1)
        #expect(abs(scene.second.frame.width - 298) <= 1)
    }

    @Test func reservedLayoutKeepsBothTenPointGaps() {
        let scene = SplitDropReservationSupport.Scene()
        let insert = scene.leftEdge(scene.lease())
        #expect(scene.first.frame.minX == insert.2.maxX + 10)
        #expect(scene.second.frame.minX == scene.first.frame.maxX + 10)
    }

    @Test func theReservedRegionRendersTheBorderOnTheOriginalContentGeometry() throws {
        let scene = SplitDropReservationSupport.Scene()
        let insert = scene.leftEdge(scene.lease())
        let region = try #require(scene.region())
        #expect(region.frame == insert.2)
        #expect(region.layer?.borderWidth == 2)
        #expect(region.layer?.cornerRadius == 6)
        #expect(region.layer?.backgroundColor == nil)
        #expect(region.layer?.opacity == 1)
    }

    @Test func theReservedRegionIsAPassivePresentation() throws {
        let scene = SplitDropReservationSupport.Scene()
        _ = scene.leftEdge(scene.lease())
        let region = try #require(scene.region())
        #expect(!region.isAccessibilityElement())
        #expect(region.accessibilityChildren()?.isEmpty == true)
        #expect(region.hitTest(.zero) == nil)
        #expect(!region.acceptsFirstResponder)
    }

    @Test func theBorderExpandsOverTwoTenthsWithEaseOutWhateverTheMotionSetting() throws {
        let scene = SplitDropReservationSupport.Scene()
        _ = scene.leftEdge(scene.lease())
        let motion = try #require(scene.region()?.layer?.animation(forKey: "Split drop region") as? CAAnimationGroup)
        #expect(motion.duration == 0.2)
        #expect(motion.timingFunction == CAMediaTimingFunction(name: .easeOut))
    }

    @Test func theBorderGrowsFromACollapsedZeroAxisToTheExactReservedSize() throws {
        let scene = SplitDropReservationSupport.Scene()
        _ = scene.leftEdge(scene.lease())
        let region = try #require(scene.region())
        let motion = try #require(region.layer?.animation(forKey: "Split drop region") as? CAAnimationGroup)
        let bounds = motion.animations?.compactMap { $0 as? CABasicAnimation }.first { $0.keyPath == "bounds" }
        #expect((bounds?.fromValue as? NSValue)?.rectValue.width == 0)
        #expect((bounds?.toValue as? NSValue)?.rectValue == region.layer?.bounds)
    }

    @Test func theBorderAlphaGoesFromCollapsedZeroToExpandedOne() throws {
        let scene = SplitDropReservationSupport.Scene()
        _ = scene.leftEdge(scene.lease())
        let motion = try #require(scene.region()?.layer?.animation(forKey: "Split drop region") as? CAAnimationGroup)
        let alpha = motion.animations?.compactMap { $0 as? CABasicAnimation }.first { $0.keyPath == "opacity" }
        #expect((alpha?.fromValue as? NSNumber)?.doubleValue == 0)
        #expect((alpha?.toValue as? NSNumber)?.doubleValue == 1)
    }

    @Test func theRegionResolvesTheOriginalWindowsHalfOpacityInk() throws {
        let scene = SplitDropReservationSupport.Scene()
        _ = scene.leftEdge(scene.lease())
        let region = try #require(scene.region())
        let border = try #require(region.layer?.borderColor)
        let ink = try #require(NSColor(cgColor: border)?.usingColorSpace(.deviceRGB))
        #expect(abs(ink.alphaComponent - 0.5) < 0.001)
    }

    @Test func theOriginalPaneLayerReceivesTheAttributedPositionAndBoundsTransition() throws {
        let scene = SplitDropReservationSupport.Scene()
        _ = scene.leftEdge(scene.lease())
        let movement = try #require(scene.first.layer?.animation(forKey: "Split reserved layout") as? CAAnimationGroup)
        #expect(movement.duration == 0.2)
        #expect(movement.animations?.count == 2)
        #expect(movement.timingFunction == CAMediaTimingFunction(name: .easeOut))
    }

    @Test func theReservationAnimatesTowardAlreadyAuthoritativeGeometry() throws {
        let scene = SplitDropReservationSupport.Scene()
        _ = scene.leftEdge(scene.lease())
        let movement = try #require(scene.first.layer?.animation(forKey: "Split reserved layout") as? CAAnimationGroup)
        let bounds = movement.animations?.first { ($0 as? CABasicAnimation)?.keyPath == "bounds" } as? CABasicAnimation
        #expect((bounds?.toValue as? NSValue)?.rectValue == scene.first.layer?.bounds)
    }

    @Test func controlledGeometryStaysAdmittedAndExposesNoDivider() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        _ = scene.leftEdge(lease)
        #expect(lease.isCurrent)
        #expect(!scene.split.isAccessibilityElement())
        #expect((scene.split.accessibilitySplitters() ?? []).isEmpty)
    }

    @Test func thePointerInItsOwnReservedRegionKeepsTheProposalAndRegion() {
        let scene = SplitDropReservationSupport.Scene()
        let lease = scene.lease()
        let insert = scene.leftEdge(lease)
        let held = lease.proposal(at: NSPoint(x: insert.2.midX, y: insert.2.midY), canPropose: scene.allowAll)!
        #expect(held.0 == insert.0)
        #expect(held.2 == insert.2)
        #expect(lease.reusedRegion)
    }
}
