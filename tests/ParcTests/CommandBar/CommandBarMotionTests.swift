import AppKit
import Testing
@testable import Parc

@MainActor
struct CommandBarMotionTests {
    @MainActor struct Fixture {
        let view: CommandBarShadowView
        let bar = NSRect(x: 100, y: 200, width: 700, height: 326)

        init() {
            CommandBarTestSupport.prepareAppKit()
            let m = CommandBarShadowView.margins
            view = CommandBarShadowView(frame: NSRect(x: 0, y: 0, width: bar.width + m.left + m.right, height: bar.height + m.top + m.bottom))
            view.layoutSubtreeIfNeeded()
        }
    }

    func transform(of animation: CABasicAnimation?) -> CATransform3D {
        (animation?.fromValue as? NSValue)?.caTransform3DValue ?? CATransform3DIdentity
    }

    @Test func theBarKeepsItsPlaceInItsShadow() {
        let fixture = Fixture()
        #expect(fixture.view.barFrame.size == fixture.bar.size)
    }

    @Test func theShadowNeverTakesTheMouse() {
        #expect(Fixture().view.hitTest(NSPoint(x: 2, y: 2)) == nil)
    }

    @Test func theShadowLayerIsAttached() {
        let view = Fixture().view
        #expect(view.shadowLayer.superlayer === view.layer)
    }

    @Test func theShadowIsBlackHalfOpaqueWith48RadiusAnd24Offset() {
        let layer = Fixture().view.shadowLayer
        #expect(layer.shadowOpacity == 0.5)
        #expect(layer.shadowRadius == 48)
        #expect(layer.shadowOffset == CGSize(width: 0, height: 24))
    }

    @Test func theShadowIsMaskedToOutsideTheBar() {
        let view = Fixture().view
        let mask = view.shadowLayer.mask as? CAShapeLayer
        #expect(mask?.fillRule == .evenOdd)
        #expect(mask?.path?.contains(CGPoint(x: 4, y: 4), using: .evenOdd) == true)
        #expect(mask?.path?.contains(CGPoint(x: view.barFrame.midX, y: view.barFrame.midY), using: .evenOdd) == false)
    }

    @Test func theShadowBouncesAboutTheBarsCentreNotItsOwn() {
        let view = Fixture().view
        CommandBarBounce.play(on: view.shadowLayer, about: view.barCentreOffset)
        let from = transform(of: view.shadowLayer.animation(forKey: CommandBarBounce.key) as? CASpringAnimation)
        let barFromAnchor = CGPoint(x: view.barFrame.midX - view.shadowLayer.bounds.midX, y: view.barFrame.midY - view.shadowLayer.bounds.midY)
        let moved = barFromAnchor.applying(CATransform3DGetAffineTransform(from))
        #expect(view.shadowLayer.anchorPoint == CGPoint(x: 0.5, y: 0.5))
        #expect(view.shadowLayer.frame == view.bounds)
        #expect(barFromAnchor.y != 0)
        #expect(abs(moved.x - barFromAnchor.x) < 0.0001)
        #expect(abs(moved.y - barFromAnchor.y) < 0.0001)
        #expect(abs(from.m11 - 0.95) < 0.0001)
    }

    @Test func theBounceIsASpringWithTheRecoveredDampingAndPeriod() {
        let bounce = CommandBarBounce.animation(about: CGPoint(x: 350, y: 32))
        let stiffness = pow(2 * CGFloat.pi / 0.7, 2)
        let damping = 4 * CGFloat.pi * 0.9 / 0.7
        #expect(bounce.keyPath == "transform")
        #expect(bounce.mass == 1)
        #expect(abs(bounce.stiffness - stiffness) < 0.001)
        #expect(abs(bounce.damping - damping) < 0.001)
        #expect(bounce.duration == bounce.settlingDuration)
    }

    @Test func theBounceSpringsFrom95PercentToFullSizeAboutTheGivenCentre() {
        let bounce = CommandBarBounce.animation(about: CGPoint(x: 350, y: 32))
        let from = transform(of: bounce)
        let centre = CGPoint(x: 350, y: 32).applying(CATransform3DGetAffineTransform(from))
        #expect(abs(from.m11 - 0.95) < 0.0001)
        #expect(abs(from.m22 - 0.95) < 0.0001)
        #expect(abs(centre.x - 350) < 0.0001)
        #expect(abs(centre.y - 32) < 0.0001)
        #expect(CATransform3DIsIdentity((bounce.toValue as? NSValue)?.caTransform3DValue ?? from))
    }

    @Test func aLayerAnchoredAtItsCornerBouncesAboutItsMiddle() {
        let bounced = CALayer()
        bounced.bounds = CGRect(x: 0, y: 0, width: 700, height: 64)
        bounced.anchorPoint = .zero
        CommandBarBounce.play(on: bounced)
        let from = transform(of: bounced.animation(forKey: CommandBarBounce.key) as? CASpringAnimation)
        #expect(abs(from.m41 - 0.05 * 350) < 0.0001)
        #expect(abs(from.m42 - 0.05 * 32) < 0.0001)
    }

    @Test func theSplashLeavesTwoBlurRadiiAroundTheBar() {
        #expect(CommandBarSplashView.padding == 2 * CommandBarSplashView.blurRadius)
    }

    @Test func theSplashBlursTo150AndFadesOver1Point2Seconds() {
        #expect(CommandBarSplashView.blurRadius == 150)
        #expect(CommandBarSplashView.duration == 1.2)
    }
}
