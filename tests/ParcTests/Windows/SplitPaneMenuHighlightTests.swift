import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitPaneMenuHighlightTests {
    @MainActor private struct Fixture {
        let window: NSWindow
        let paneView: NSView
        let highlight = SplitPaneHighlight()
        var shape: CAShapeLayer { highlight.layer }

        init() {
            _ = NSApplication.shared
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            paneView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            window.contentView = paneView
            highlight.attach(to: paneView)
            CATransaction.flush()
        }

        func takeTransitions() -> [String: CFTimeInterval] {
            defer { shape.removeAllAnimations() }
            return Dictionary(uniqueKeysWithValues: (shape.animationKeys() ?? []).compactMap { key in
                shape.animation(forKey: key).map { (key, $0.duration) }
            })
        }

        func isRecovered(_ transitions: [String: CFTimeInterval]) -> Bool {
            transitions["opacity"] != nil && transitions.values.allSatisfy { abs($0 - 0.11) < 1e-9 }
        }
    }

    @Test func theLayerHasNoFillRoundJoinAndCapHighZAndStartsHidden() {
        let shape = Fixture().shape
        #expect(shape.fillColor == nil)
        #expect(shape.lineJoin == .round && shape.lineCap == .round)
        #expect(shape.zPosition == 8 && shape.opacity == 0)
    }

    @Test func theBorderStrokesTheFullContentBounds() {
        let fixture = Fixture()
        fixture.highlight.layout(bounds: fixture.paneView.bounds, cornerRadius: 6)
        #expect(fixture.shape.frame == fixture.paneView.bounds)
        #expect(fixture.shape.path?.boundingBox == CGRect(x: 0, y: 0, width: 300, height: 200))
    }

    @Test func theStrokeColorAppliesWithoutAnImplicitTransition() {
        let fixture = Fixture()
        fixture.highlight.color = NSColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1)
        #expect(fixture.shape.strokeColor != nil)
        #expect(fixture.shape.animationKeys()?.isEmpty != false)
    }

    @Test func focusedMultiPaneContentShowsTheTwoPointBorder() {
        #expect(SplitPaneHighlightState.resolve(isProposedDropTarget: false, isFocused: true, paneCount: 2, dragEditActive: false)
                == SplitPaneHighlightState(display: true, width: 2))
    }

    @Test func aProposedReplacementShowsTheThreePointBorderDuringADrag() {
        #expect(SplitPaneHighlightState.resolve(isProposedDropTarget: true, isFocused: false, paneCount: 2, dragEditActive: true)
                == SplitPaneHighlightState(display: true, width: 3))
    }

    @Test func aDragEditHidesTheFocusBorder() {
        #expect(!SplitPaneHighlightState.resolve(isProposedDropTarget: false, isFocused: true, paneCount: 2, dragEditActive: true).display)
    }

    @Test func aSingleContentShowsNoFocusBorder() {
        #expect(!SplitPaneHighlightState.resolve(isProposedDropTarget: false, isFocused: true, paneCount: 1, dragEditActive: false).display)
    }

    @Test func theFirstPublishedStateAppliesImmediately() {
        let fixture = Fixture()
        fixture.highlight.update(display: false, width: 2)
        #expect(fixture.shape.opacity == 0 && fixture.shape.lineWidth == 4)
        #expect(fixture.takeTransitions().isEmpty)
    }

    @Test func theVisibleWidthIsHalfTheDoubledStrokeAndOpacityIsOne() {
        let fixture = Fixture()
        fixture.highlight.update(display: false, width: 2)
        fixture.highlight.update(display: true, width: 3)
        #expect(fixture.shape.opacity == 1 && fixture.shape.lineWidth == 6)
    }

    @Test func aDisplayedStateChangeUsesTheElevenHundredthsTransition() {
        let fixture = Fixture()
        fixture.highlight.update(display: false, width: 2)
        _ = fixture.takeTransitions()
        fixture.highlight.update(display: true, width: 3)
        #expect(fixture.isRecovered(fixture.takeTransitions()))
    }

    @Test func aWidthOnlyChangeAppliesWithoutATransition() {
        let fixture = Fixture()
        fixture.highlight.update(display: true, width: 3)
        _ = fixture.takeTransitions()
        fixture.highlight.update(display: true, width: 2)
        #expect(fixture.shape.lineWidth == 4)
        #expect(fixture.takeTransitions().isEmpty)
    }

    @Test func hidingUsesTheSameTransition() {
        let fixture = Fixture()
        fixture.highlight.update(display: true, width: 2)
        _ = fixture.takeTransitions()
        fixture.highlight.update(display: false, width: 2)
        #expect(fixture.shape.opacity == 0)
        #expect(fixture.isRecovered(fixture.takeTransitions()))
    }

    @Test func aHiddenHostUpdatesImmediately() {
        let fixture = Fixture()
        fixture.highlight.update(display: false, width: 2)
        _ = fixture.takeTransitions()
        fixture.paneView.isHidden = true
        fixture.highlight.update(display: true, width: 2)
        #expect(fixture.shape.opacity == 1)
        #expect(fixture.takeTransitions().isEmpty)
    }

    @Test func thePathFollowsTheHostsBoundsTransitionFromItsPreviousSize() throws {
        let fixture = Fixture()
        fixture.highlight.layout(bounds: fixture.paneView.bounds, cornerRadius: 6)
        let animation = CABasicAnimation(keyPath: "bounds")
        animation.duration = 0.2
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fixture.highlight.followLayout(from: CGRect(x: 0, y: 0, width: 200, height: 200), animation: animation)
        let follow = try #require(fixture.shape.animation(forKey: "Split pane highlight layout") as? CABasicAnimation)
        #expect(follow.keyPath == "path")
        #expect(follow.duration == 0.2)
        #expect((follow.fromValue as! CGPath).boundingBox.width == 200)
    }

    @Test func theHostTransitionAddsAHighlightPathAnimation() {
        let fixture = Fixture()
        fixture.highlight.layout(bounds: fixture.paneView.bounds, cornerRadius: 6)
        fixture.highlight.followLayout(from: CGRect(x: 0, y: 0, width: 200, height: 200), animation: CABasicAnimation(keyPath: "bounds"))
        #expect(fixture.shape.animation(forKey: "Split pane highlight layout") != nil)
    }

    @Test func cancellingTheHostTransitionRemovesThePathTransition() {
        let fixture = Fixture()
        fixture.highlight.layout(bounds: fixture.paneView.bounds, cornerRadius: 6)
        fixture.highlight.followLayout(from: CGRect(x: 0, y: 0, width: 200, height: 200), animation: CABasicAnimation(keyPath: "bounds"))
        fixture.highlight.cancelFollow()
        #expect(fixture.shape.animation(forKey: "Split pane highlight layout") == nil)
    }
}
