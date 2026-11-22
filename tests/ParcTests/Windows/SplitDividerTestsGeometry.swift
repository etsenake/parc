import AppKit
import QuartzCore
import Testing
@testable import ParcCore
@testable import Parc

@MainActor
struct SplitDividerTestsGeometry {
    private typealias SplitRig = SplitDividerTestsSupport.SplitRig

    private static func integralEdges(_ rect: NSRect) -> Bool {
        [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy { $0 == $0.rounded() }
    }

    private static func detached() -> SplitRig {
        SplitRig(factors: [0.01, 0.49, 0.5], frame: NSRect(x: 0, y: 0, width: 1201, height: 901), attached: false)
    }

    @Test func theBrowsersContentInsetSuppliesTenPointDividers() {
        let rig = SplitRig(count: 4, factors: [1, 2, 3, 4], frame: NSRect(x: 0, y: 0, width: 1200, height: 1200))
        #expect(rig.view.dividerThickness == 10)
    }

    @Test func expandedHorizontalPanesEnforceTheRecoveredMinimum() {
        let rig = SplitRig(count: 4, factors: [1, 2, 3, 4], frame: NSRect(x: 0, y: 0, width: 1200, height: 1200))
        #expect(rig.panes.allSatisfy { $0.frame.width >= 220 })
    }

    @Test func fractionalSharesClampAndAlignThePaneEdges() {
        let rig = Self.detached()
        #expect(rig.panes[0].frame.width == 220)
        #expect(rig.frames.allSatisfy(Self.integralEdges))
    }

    @Test func roundedEdgesPreserveExactGapsAndFillTheViewport() {
        let rig = Self.detached()
        #expect(zip(rig.panes, rig.panes.dropFirst()).allSatisfy { $1.frame.minX - $0.frame.maxX == 10 })
        #expect(rig.panes.last?.frame.maxX == rig.view.bounds.maxX)
    }

    @Test func aMinimumClampedLiveMutationRerendersAllPanesKeepingTheThirdSourceFactor() {
        let rig = Self.detached()
        let origin = NSPoint(x: rig.panes[0].frame.maxX + 5, y: 200)
        #expect(rig.view.beginDividerResize(at: origin))
        rig.view.updateDividerResize(at: NSPoint(x: -900, y: 200), velocity: -200)
        #expect(rig.panes[0].frame.width == 220)
        #expect(rig.panes[2].frame.width == 591)
        #expect(rig.commits.isEmpty)
    }

    @Test func verticalExpandedPanesUseTheSameMinimumAndAlignedEdges() {
        let rig = Self.detached()
        rig.view.configure(orientation: .vertical, factors: [0.01, 0.49, 0.5])
        #expect(rig.panes[0].frame.height == 220)
        #expect(rig.frames.allSatisfy(Self.integralEdges))
    }

    @Test func verticalLayoutPreservesExactGapsAndTheViewportExtent() {
        let rig = Self.detached()
        rig.view.configure(orientation: .vertical, factors: [0.01, 0.49, 0.5])
        #expect(zip(rig.panes, rig.panes.dropFirst()).allSatisfy { $1.frame.minY - $0.frame.maxY == 10 })
        #expect(rig.panes.last?.frame.maxY == rig.view.bounds.maxY)
    }

    @Test func panesShortOfRoomInAnUndersizedViewportShareItsHeightEvenly() {
        let rig = Self.detached()
        rig.view.configure(orientation: .vertical, factors: [0.01, 0.49, 0.5])
        rig.view.frame.size.height = 400
        rig.view.adjustSubviews()
        #expect(rig.heights == [126, 126, 126])
        #expect(rig.frames.allSatisfy(Self.integralEdges))
        #expect(rig.panes.map { $0.frame.minY } == [0, 136, 272])
        #expect(rig.panes.last!.frame.maxY <= rig.view.bounds.maxY)
    }

    @Test func aRestoredViewportRecoversSourceRatiosWithoutRewritingTheDurableLayout() {
        let rig = Self.detached()
        rig.view.configure(orientation: .vertical, factors: [0.01, 0.49, 0.5])
        rig.view.frame.size.height = 400
        rig.view.adjustSubviews()
        rig.view.frame.size.height = 901
        rig.view.adjustSubviews()
        #expect(rig.panes[0].frame.height == 220)
        #expect(rig.commits.isEmpty)
    }
}
