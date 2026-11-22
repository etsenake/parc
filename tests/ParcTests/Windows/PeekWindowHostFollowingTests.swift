import AppKit
import QuartzCore
import Testing
@testable import Parc

struct PeekWindowHostFollowingTests {
    @MainActor @Test func withoutASlideTheStepSimplyHolds() {
        let (still, layer) = PeekWindowHostSupport.pageView()
        PeekStepBack([still]).set(1, scale: PeekWindowHostSupport.scale)
        let held = layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        #expect(held.flatMap { PeekWindowHostSupport.transform($0.fromValue) }.map { CATransform3DEqualToTransform($0, PeekWindowHostSupport.transform(held?.toValue)!) } == true)
    }

    @MainActor @Test func aHeldStepIsCentredOnThePage() {
        let (still, layer) = PeekWindowHostSupport.pageView()
        PeekStepBack([still]).set(1, scale: PeekWindowHostSupport.scale)
        let held = layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        #expect(PeekWindowHostSupport.close(PeekWindowHostSupport.centreOffset(of: PeekWindowHostSupport.transform(held?.toValue)!, width: PeekWindowHostSupport.wide.width), 0))
    }

    @MainActor @Test func aStepHeldForTheFinalWidthSitsOffCentreOnAPageStillSlidingFromTheOldWidth() {
        let (still, layer) = PeekWindowHostSupport.pageView()
        PeekStepBack([still]).set(1, scale: PeekWindowHostSupport.scale)
        let held = layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        #expect(abs(PeekWindowHostSupport.centreOffset(of: PeekWindowHostSupport.transform(held?.toValue)!, width: PeekWindowHostSupport.narrow.width)) > 1)
    }

    @MainActor private final class Following {
        let slide = CABasicAnimation(keyPath: PeekStepBack.slideKey)
        let view: NSView
        let layer: CALayer
        let step: PeekStepBack

        init() {
            slide.duration = 0.2
            slide.beginTime = 500
            slide.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
            (view, layer) = PeekWindowHostSupport.slidingPage(from: PeekWindowHostSupport.narrow, slide: slide)
            step = PeekStepBack([view])
            step.set(1, scale: PeekWindowHostSupport.scale)
        }

        var follow: CABasicAnimation? { layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation }
    }

    @MainActor @Test func aSlidingPageGetsAnAdditiveTransformStepThatStaysOnceTheSlideEnds() throws {
        let f = Following()
        let follow = try #require(f.follow)
        #expect(follow.keyPath == "transform")
        #expect(follow.isAdditive)
        #expect(!follow.isRemovedOnCompletion)
        #expect(follow.fillMode == .both)
    }

    @MainActor @Test func theStepRidesTheSlidesOwnClockAndCurve() throws {
        let f = Following()
        let follow = try #require(f.follow)
        #expect(follow.duration == f.slide.duration)
        #expect(follow.beginTime == 500)
        #expect(follow.timingFunction == f.slide.timingFunction)
    }

    @MainActor @Test func theStepEndsCentredOnTheFinalPage() throws {
        let f = Following()
        let follow = try #require(f.follow)
        let to = try #require(PeekWindowHostSupport.transform(follow.toValue))
        #expect(CATransform3DEqualToTransform(to, PeekWindowLayout.stepTransform(bounds: PeekWindowHostSupport.wide, anchor: f.layer.anchorPoint, scale: PeekWindowHostSupport.scale)))
    }

    @MainActor @Test(arguments: [CGFloat(0), 0.25, 0.5, 0.75, 1])
    func theStepStaysCentredOnThePageThroughoutTheSlide(_ fraction: CGFloat) throws {
        let f = Following()
        let follow = try #require(f.follow)
        let from = try #require(PeekWindowHostSupport.transform(follow.fromValue)), to = try #require(PeekWindowHostSupport.transform(follow.toValue))
        let width = PeekWindowHostSupport.narrow.width + (PeekWindowHostSupport.wide.width - PeekWindowHostSupport.narrow.width) * fraction
        #expect(PeekWindowHostSupport.close(PeekWindowHostSupport.centreOffset(of: PeekWindowHostSupport.midway(from, to, fraction), width: width), 0))
    }

    @MainActor @Test func aFadeDuringTheSlideKeepsFollowingItFromTheSameStart() {
        let f = Following()
        f.step.set(0.5, scale: PeekWindowHostSupport.scale)
        let fading = f.layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        let factor = 1 - 0.5 * (1 - PeekWindowHostSupport.scale)
        #expect(fading?.beginTime == 500)
        #expect(PeekWindowHostSupport.transform(fading?.fromValue).map {
            CATransform3DEqualToTransform($0, PeekWindowLayout.stepTransform(bounds: PeekWindowHostSupport.narrow, anchor: f.layer.anchorPoint, scale: factor))
        } == true)
    }

    @MainActor private func cutShort(_ f: Following) -> CABasicAnimation? {
        f.layer.removeAnimation(forKey: PeekStepBack.slideKey)
        f.step.refresh()
        return f.follow
    }

    @MainActor @Test func aSlideCutShortSnapsTheStepToTheFinalPageCentred() {
        let f = Following()
        let after = cutShort(f)
        #expect(after.flatMap { PeekWindowHostSupport.transform($0.fromValue) }.map { CATransform3DEqualToTransform($0, PeekWindowHostSupport.transform(after?.toValue)!) } == true)
        #expect(after?.duration == 1)
    }

    @MainActor @Test func aSettledStepIsNotReappliedOnEveryLayout() {
        let f = Following()
        let after = cutShort(f)
        f.step.refresh()
        #expect(f.follow === after)
    }

    @MainActor @Test func aFloatingSidebarsSpringSlideIsFollowedWithTheSameSpring() {
        let (springing, layer) = PeekWindowHostSupport.pageView()
        let spring = CASpringAnimation(keyPath: PeekStepBack.slideKey)
        spring.isAdditive = true
        spring.fromValue = NSValue(rect: CGRect(x: 0, y: 0, width: PeekWindowHostSupport.narrow.width - PeekWindowHostSupport.wide.width, height: 0))
        spring.toValue = NSValue(rect: .zero)
        spring.stiffness = 1218
        spring.damping = 55.8
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: PeekStepBack.slideKey)
        PeekStepBack([springing]).set(1, scale: PeekWindowHostSupport.scale)
        let sprung = layer.animation(forKey: PeekStepBack.key) as? CASpringAnimation
        #expect(sprung?.stiffness == 1218)
        #expect(sprung?.damping == 55.8)
        #expect(PeekWindowHostSupport.transform(sprung?.fromValue).map {
            CATransform3DEqualToTransform($0, PeekWindowLayout.stepTransform(bounds: PeekWindowHostSupport.narrow, anchor: layer.anchorPoint, scale: PeekWindowHostSupport.scale))
        } == true)
    }

    @MainActor @Test func aSlideThatDoesNotChangeThePagesSizeKeepsThePlainHold() {
        let (moving, layer) = PeekWindowHostSupport.pageView()
        let move = CABasicAnimation(keyPath: PeekStepBack.slideKey)
        move.fromValue = NSValue(rect: PeekWindowHostSupport.wide.offsetBy(dx: 40, dy: 0))
        layer.add(move, forKey: PeekStepBack.slideKey)
        PeekStepBack([moving]).set(1, scale: PeekWindowHostSupport.scale)
        let moved = layer.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        #expect(moved.flatMap { PeekWindowHostSupport.transform($0.fromValue) }.map { CATransform3DEqualToTransform($0, PeekWindowHostSupport.transform(moved?.toValue)!) } == true)
    }
}
