import AppKit
import QuartzCore
import Testing
@testable import Parc

struct PeekWindowHostReplacementTests {
    private static let midwayRect = CGRect(x: 0, y: 0, width: 1042 + 114, height: 780)

    @MainActor private final class Replaced {
        let first = CABasicAnimation(keyPath: PeekStepBack.slideKey)
        let view: NSView
        let layer: CALayer
        let step: PeekStepBack
        let now = CACurrentMediaTime()

        init() {
            first.duration = 0.2
            first.beginTime = now - 0.1
            (view, layer) = PeekWindowHostSupport.slidingPage(from: PeekWindowHostSupport.narrow, slide: first)
            step = PeekStepBack([view])
            step.set(1, scale: PeekWindowHostSupport.scale)
        }

        func replace() -> (slide: CABasicAnimation, tracking: CABasicAnimation?) {
            let second = CABasicAnimation(keyPath: PeekStepBack.slideKey)
            second.fromValue = NSValue(rect: PeekWindowHostReplacementTests.midwayRect)
            second.duration = 0.2
            second.beginTime = now - 0.1
            second.isRemovedOnCompletion = false
            layer.add(second, forKey: PeekStepBack.slideKey)
            step.refresh()
            return (second, layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation)
        }
    }

    @MainActor @Test func theStepFollowsTheFirstSlideFromThePagesOldWidth() {
        let r = Replaced()
        let following = r.layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        #expect(following?.beginTime == r.first.beginTime)
        #expect(PeekWindowHostSupport.transform(following?.fromValue).map {
            CATransform3DEqualToTransform($0, PeekWindowLayout.stepTransform(bounds: PeekWindowHostSupport.narrow, anchor: .zero, scale: PeekWindowHostSupport.scale))
        } == true)
    }

    @MainActor @Test func theStepRidesTheReplacementSlidesClockToTheSameFinalStep() throws {
        let r = Replaced()
        let (second, tracking) = r.replace()
        let t = try #require(tracking)
        #expect(t.beginTime == second.beginTime)
        #expect(t.duration == second.duration)
        #expect(CATransform3DEqualToTransform(try #require(PeekWindowHostSupport.transform(t.toValue)), PeekWindowHostSupport.finalStep))
    }

    @MainActor @Test(arguments: [CGFloat(0), 0.25, 0.5, 0.75, 1])
    func theStepStaysCentredOnTheInFlightWidthAtEachPointOfTheReplacementSlide(_ fraction: CGFloat) throws {
        let r = Replaced()
        let t = try #require(r.replace().tracking)
        let from = try #require(PeekWindowHostSupport.transform(t.fromValue)), to = try #require(PeekWindowHostSupport.transform(t.toValue))
        let width = Self.midwayRect.width + (PeekWindowHostSupport.wide.width - Self.midwayRect.width) * fraction
        #expect(PeekWindowHostSupport.close(PeekWindowHostSupport.centreOffset(of: PeekWindowHostSupport.midway(from, to, fraction), width: width), 0))
    }

    @Test func aStepStillFollowingTheFirstSlidesStartWouldSitOffCentreWhenTheReplacementBegins() {
        let stale = PeekWindowLayout.stepTransform(bounds: PeekWindowHostSupport.narrow, anchor: .zero, scale: PeekWindowHostSupport.scale)
        #expect(abs(PeekWindowHostSupport.centreOffset(of: stale, width: Self.midwayRect.width)) > 0.5)
    }

    @MainActor @Test func theReplacementSlideIsFollowedOnceNotOnEveryLayout() {
        let r = Replaced()
        let (_, tracking) = r.replace()
        r.step.refresh()
        #expect(r.layer.animation(forKey: PeekStepBack.key) === tracking)
    }

    @MainActor @Test func aReplacementSlideThatHasNotStartedYetIsRestartedFromTheSlideItReplaced() {
        let r = Replaced()
        let (_, tracking) = r.replace()
        let third = CABasicAnimation(keyPath: PeekStepBack.slideKey)
        third.fromValue = NSValue(rect: Self.midwayRect)
        third.duration = 0.2
        third.isRemovedOnCompletion = false
        r.layer.add(third, forKey: PeekStepBack.slideKey)
        r.step.refresh()
        let restarted = r.layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        #expect(restarted !== tracking)
        #expect((restarted?.beginTime ?? 0) > (tracking?.beginTime ?? .infinity))
    }

    @MainActor @Test func aSlideThatOnlyMovesThePageLeavesTheHeldStepAloneOnLaterLayouts() {
        let resting = NSView(frame: PeekWindowHostSupport.wide)
        resting.wantsLayer = true
        let layer = resting.layer!
        let moving = CABasicAnimation(keyPath: PeekStepBack.slideKey)
        moving.fromValue = NSValue(rect: PeekWindowHostSupport.wide.offsetBy(dx: 30, dy: 0))
        moving.isRemovedOnCompletion = false
        layer.add(moving, forKey: PeekStepBack.slideKey)
        let still = PeekStepBack([resting])
        still.set(1, scale: PeekWindowHostSupport.scale)
        let held = layer.animation(forKey: PeekStepBack.key)
        still.refresh()
        #expect(layer.animation(forKey: PeekStepBack.key) === held)
    }
}
