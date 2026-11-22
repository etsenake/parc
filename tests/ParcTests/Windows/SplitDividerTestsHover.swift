import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitDividerTestsHover {
    private typealias SeeThroughView = SplitDividerTestsSupport.SeeThroughView
    private typealias SplitRig = SplitDividerTestsSupport.SplitRig

    @MainActor private final class Rig {
        let rig = SplitRig(count: 4, factors: [1, 2, 3, 4], frame: NSRect(x: 0, y: 0, width: 1200, height: 1200))
        var view: ParcSplitView { rig.view }

        init() {
            view.appearance = NSAppearance(named: .aqua)
            view.viewDidChangeEffectiveAppearance()
        }

        func grips() -> [CALayer] { (view.layer?.sublayers ?? []).filter { $0.name == "Split divider grip" } }
        func ink(_ layer: CALayer) -> NSColor? { layer.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB) }
        func alpha(_ layer: CALayer) -> CGFloat { ink(layer)?.alphaComponent ?? -1 }
        var first: CALayer { grips()[0] }
        var hoverPoint: NSPoint { NSPoint(x: first.frame.midX, y: first.frame.midY) }
        var topGap: NSPoint { NSPoint(x: hoverPoint.x, y: 52) }
        var regionTop: NSPoint { NSPoint(x: hoverPoint.x, y: 53) }
        var windowPoint: NSPoint { view.convert(hoverPoint, to: nil) }
        var window: NSWindow { rig.window }
    }

    @Test func gripLayersDoNotBecomePanesOrChangeTheChildList() {
        let rig = Rig()
        #expect(rig.grips().count == 3)
        #expect(rig.view.arrangedSubviews.count == 4)
    }

    @Test func aHorizontalGripHasTheRecoveredSizeAndRadius() {
        let rig = Rig()
        #expect(rig.first.frame.size == NSSize(width: 2, height: 24))
        #expect(rig.first.cornerRadius == 1)
    }

    @Test func theGripCentersOnTheDividersActualFrame() {
        let rig = Rig()
        #expect(rig.first.frame.midX == rig.view.arrangedSubviews[0].frame.maxX + rig.view.dividerThickness / 2)
        #expect(rig.first.frame.midY == rig.view.bounds.midY)
    }

    @Test func lightAppearanceResolvesIdleDragHintBlackAtTwentyPercent() {
        let rig = Rig()
        #expect(abs(rig.alpha(rig.first) - 0.2) < 0.000001)
        #expect(rig.ink(rig.first)?.redComponent == 0)
    }

    @Test func aPointedDividerHighlightsItsVisibleGrip() {
        let rig = Rig()
        rig.view.updateDividerHover(at: rig.hoverPoint, animated: false)
        #expect(rig.grips().allSatisfy { !$0.isHidden })
        #expect(rig.alpha(rig.first) == 0.5)
    }

    @Test func hoverChangesOnlyGripInkNeverItsGeometryOrVisibility() {
        let rig = Rig()
        let frames = rig.grips().map(\.frame)
        rig.view.updateDividerHover(at: rig.hoverPoint, animated: false)
        rig.view.updateDividerHover(at: nil, animated: false)
        #expect(rig.grips().allSatisfy { !$0.isHidden })
        #expect(rig.grips().map(\.frame) == frames)
    }

    @Test func theTopFiftyThreePointsOfADividerAreOutsideItsHoverRegion() {
        let rig = Rig()
        rig.view.updateDividerHover(at: rig.topGap, animated: false)
        #expect(abs(rig.alpha(rig.first) - 0.2) < 0.000001)
    }

    @Test func theHoverRegionStartsFiftyThreePointsBelowTheDividerTop() {
        let rig = Rig()
        rig.view.updateDividerHover(at: rig.regionTop, animated: false)
        #expect(rig.alpha(rig.first) == 0.5)
    }

    @Test func panAdmissionUsesTheSameDraggableRegion() {
        let rig = Rig()
        rig.view.prepareDividerResize = { { _ in false } }
        #expect(!rig.view.beginDividerResize(at: rig.topGap))
        #expect(rig.view.beginDividerResize(at: rig.regionTop))
        rig.view.finishDividerResize(commit: false)
    }

    @Test func trackingAreasCoverEachDraggableRegionWithTheOriginalOptions() {
        let rig = Rig()
        rig.view.updateTrackingAreas()
        #expect(rig.view.trackingAreas.count == 3)
        #expect(rig.view.trackingAreas.allSatisfy {
            $0.rect.minY == 53 && $0.rect.maxY == rig.view.bounds.maxY && $0.rect.width == rig.view.dividerThickness
                && $0.options.contains(.enabledDuringMouseDrag) && $0.options.contains(.activeInKeyWindow)
        })
    }

    @Test func anUncoveredDividerSetsItsResizePointerThroughCursorUpdates() {
        let rig = Rig()
        rig.view.updateTrackingAreas()
        #expect(rig.view.trackingAreas.allSatisfy { $0.options.contains(.cursorUpdate) })
        #expect(rig.view.dividerCursor(atWindowPoint: rig.windowPoint) != nil)
    }

    @Test func aCommandSurfaceOverTheDividerKeepsTheResizePointerOffIt() {
        let rig = Rig()
        let cover = NSView(frame: rig.window.contentView!.convert(
            NSRect(x: rig.hoverPoint.x - 20, y: rig.hoverPoint.y - 20, width: 40, height: 40), from: rig.view))
        rig.window.contentView!.addSubview(cover)
        #expect(rig.view.dividerCursor(atWindowPoint: rig.windowPoint) == nil)
    }

    @Test func aSeeThroughOverlayLeavesTheDividersResizePointerAlone() {
        let rig = Rig()
        let glass = SeeThroughView(frame: rig.window.contentView!.convert(
            NSRect(x: rig.hoverPoint.x - 20, y: rig.hoverPoint.y - 20, width: 40, height: 40), from: rig.view))
        rig.window.contentView!.addSubview(glass)
        #expect(rig.view.dividerCursor(atWindowPoint: rig.windowPoint) != nil)
    }

    @Test func onlyTheExactPointedDividerReceivesHighlightedInk() {
        let rig = Rig()
        rig.view.updateDividerHover(at: rig.hoverPoint)
        #expect(rig.alpha(rig.first) == 0.5)
        #expect(abs(rig.alpha(rig.grips()[1]) - 0.2) < 0.000001)
    }

    @Test func hoverUsesTheRecoveredAnimationDurationWithNoReduceMotionGate() {
        let rig = Rig()
        rig.view.updateDividerHover(at: rig.hoverPoint)
        #expect(rig.first.animation(forKey: "Split grip hover")?.duration == 0.16)
    }

    @Test func immediateOwnerInvalidationClearsTheTransitionAndHover() {
        let rig = Rig()
        rig.view.updateDividerHover(at: rig.hoverPoint)
        rig.view.updateDividerHover(at: nil, animated: false)
        #expect(rig.first.animation(forKey: "Split grip hover") == nil)
        #expect(abs(rig.alpha(rig.first) - 0.2) < 0.000001)
    }

    @Test func anAppearanceChangePreservesHoverButResolvesHighlightedWhite() {
        let rig = Rig()
        rig.view.updateDividerHover(at: rig.hoverPoint)
        rig.view.appearance = NSAppearance(named: .darkAqua)
        rig.view.viewDidChangeEffectiveAppearance()
        #expect(rig.ink(rig.first)?.redComponent == 1)
        #expect(rig.alpha(rig.first) == 0.5)
        #expect(rig.first.animationKeys()?.isEmpty != false)
    }

    @Test func aNonfinitePointerCannotRetainTheHighlightedDivider() {
        let rig = Rig()
        rig.view.updateDividerHover(at: rig.hoverPoint)
        rig.view.updateDividerHover(at: NSPoint(x: CGFloat.nan, y: 10))
        #expect(abs(rig.alpha(rig.first) - 0.2) < 0.000001)
    }

    @Test func gripPresentationLeavesPaneInputOnItsExistingView() {
        let rig = Rig()
        rig.view.updateDividerHover(at: NSPoint(x: 10, y: 10), animated: false)
        #expect(rig.view.hitTest(NSPoint(x: 10, y: 10)) === rig.view.arrangedSubviews[0])
    }

    @Test func windowKeyLossImmediatelyRetiresHighlightedPresentation() {
        let rig = Rig()
        rig.view.updateDividerHover(at: rig.hoverPoint)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: rig.window)
        #expect(rig.first.animationKeys()?.isEmpty != false)
        #expect(abs(rig.alpha(rig.first) - 0.2) < 0.000001)
    }

    @Test func trackingAreasContainOnlyRealVisibleDividerGeometry() {
        let rig = Rig()
        rig.view.updateTrackingAreas()
        #expect(rig.view.trackingAreas.allSatisfy { !$0.rect.isNull && !$0.rect.isEmpty && $0.rect.minX.isFinite && $0.rect.minY.isFinite })
    }

    @Test func detachingTheViewRevokesItsHoverPresentation() {
        let rig = Rig()
        let grip = rig.first
        rig.view.updateDividerHover(at: rig.hoverPoint)
        rig.view.removeFromSuperview()
        #expect(grip.animationKeys()?.isEmpty != false)
        #expect(abs(rig.alpha(grip) - 0.2) < 0.000001)
    }

    @Test func retiredPanesRemoveTheirGripAndTrackingOwners() {
        let rig = Rig()
        for pane in rig.view.arrangedSubviews {
            rig.view.removeArrangedSubview(pane)
            pane.removeFromSuperview()
        }
        rig.view.adjustSubviews()
        #expect(rig.grips().isEmpty)
        #expect(rig.view.trackingAreas.isEmpty)
    }
}
