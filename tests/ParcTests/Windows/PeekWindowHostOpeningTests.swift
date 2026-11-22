import AppKit
import QuartzCore
import Testing
@testable import Parc

struct PeekWindowHostOpeningTests {
    @MainActor @Test func aPeekOpeningWithNoSlideKeepsItsPlainEaseOutStep() {
        let resting = NSView(frame: PeekWindowHostSupport.wide)
        resting.wantsLayer = true
        PeekStepBack([resting]).animateIn(scale: PeekWindowHostSupport.scale)
        let plain = resting.layer?.animation(forKey: PeekStepBack.key) as? CABasicAnimation
        #expect(plain?.duration == PeekStepBack.openDuration)
        #expect(plain?.timingFunction == CAMediaTimingFunction(name: .easeOut))
        #expect(PeekWindowHostSupport.transform(plain?.toValue).map { CATransform3DEqualToTransform($0, PeekWindowHostSupport.finalStep) } == true)
    }

    private struct Opening {
        let animation: CAKeyframeAnimation
        let values: [CATransform3D]
        let times: [Double]
    }

    @MainActor private static func opening(riding slide: CABasicAnimation) throws -> Opening {
        let (view, layer) = PeekWindowHostSupport.slidingPage(from: PeekWindowHostSupport.narrow, slide: slide)
        PeekStepBack([view]).animateIn(scale: PeekWindowHostSupport.scale)
        let animation = try #require(layer.animation(forKey: PeekStepBack.key) as? CAKeyframeAnimation)
        let values = try #require(animation.values?.compactMap(PeekWindowHostSupport.transform))
        let times = try #require(animation.keyTimes?.map(\.doubleValue))
        #expect(values.count == times.count)
        #expect(values.count > 2)
        return Opening(animation: animation, values: values, times: times)
    }

    @MainActor private static func libraryOpening() throws -> (slide: CABasicAnimation, opening: Opening) {
        let library = CABasicAnimation(keyPath: PeekStepBack.slideKey)
        library.duration = 0.2
        library.beginTime = CACurrentMediaTime() - 0.05
        return (library, try opening(riding: library))
    }

    @MainActor @Test func theOpeningThatRidesASlideStaysPutOnceItEnds() throws {
        let o = try Self.libraryOpening().opening.animation
        #expect(o.isAdditive)
        #expect(!o.isRemovedOnCompletion)
        #expect(o.fillMode == .both)
        #expect(o.calculationMode == .linear)
    }

    @MainActor @Test func itEndsExactlyOnTheFinalStepAndStartsFromThePageAtRest() throws {
        let o = try Self.libraryOpening().opening
        #expect(CATransform3DEqualToTransform(o.values[o.values.count - 1], PeekWindowHostSupport.finalStep))
        #expect(PeekWindowHostSupport.close(o.values[0].m11, 1))
    }

    @MainActor @Test func theOpeningKeepsItsThreeTenthsOfASecondWhenTheSlideEndsFirst() throws {
        let o = try Self.libraryOpening().opening.animation
        #expect(PeekWindowHostSupport.close(CGFloat(o.duration), CGFloat(PeekStepBack.openDuration), 0.005))
    }

    @MainActor @Test func theOpeningStepStaysCentredOnTheSlidingPage() throws {
        let (library, o) = try Self.libraryOpening()
        for (value, time) in zip(o.values, o.times) {
            let moment = o.animation.beginTime + time * o.animation.duration
            let slid = CGFloat(min(1, max(0, (moment - library.beginTime) / library.duration)))
            let width = PeekWindowHostSupport.narrow.width + (PeekWindowHostSupport.wide.width - PeekWindowHostSupport.narrow.width) * slid
            #expect(PeekWindowHostSupport.close(PeekWindowHostSupport.centreOffset(of: value, width: width), 0))
        }
    }

    @MainActor @Test func thePageOnlyStepsBackWhileOpening() throws {
        let o = try Self.libraryOpening().opening
        #expect(zip(o.values, o.values.dropFirst()).allSatisfy { $1.m11 <= $0.m11 + 1e-9 })
    }

    @MainActor private static func longOpening() throws -> (slide: CABasicAnimation, opening: Opening) {
        let long = CABasicAnimation(keyPath: PeekStepBack.slideKey)
        long.duration = 0.5
        long.beginTime = CACurrentMediaTime()
        return (long, try opening(riding: long))
    }

    @MainActor @Test func theComposedStepLastsUntilALongerSlideEnds() throws {
        let (long, o) = try Self.longOpening()
        #expect(PeekWindowHostSupport.close(CGFloat(o.animation.duration), CGFloat(long.beginTime + long.duration - o.animation.beginTime), 0.001))
    }

    @MainActor @Test func theStepStaysCentredWhileALongSlideRuns() throws {
        let (long, o) = try Self.longOpening()
        for (value, time) in zip(o.values, o.times) {
            let moment = o.animation.beginTime + time * o.animation.duration
            let width = PeekWindowHostSupport.narrow.width + (PeekWindowHostSupport.wide.width - PeekWindowHostSupport.narrow.width) * CGFloat(min(1, (moment - long.beginTime) / long.duration))
            #expect(PeekWindowHostSupport.close(PeekWindowHostSupport.centreOffset(of: value, width: width), 0))
        }
    }

    @MainActor @Test func afterTheOpeningEndsTheStepHoldsItsFinalSize() throws {
        let (_, o) = try Self.longOpening()
        for (value, time) in zip(o.values, o.times) where time * o.animation.duration >= PeekStepBack.openDuration + 0.01 {
            #expect(PeekWindowHostSupport.close(value.m11, PeekWindowHostSupport.finalStep.m11))
        }
    }

    @MainActor @Test func anOpeningAimedOnlyAtTheFinalWidthWouldSitOffCentreDuringTheseSlides() throws {
        let (library, lo) = try Self.libraryOpening()
        let (long, go) = try Self.longOpening()
        func aimed(_ value: CATransform3D, width: CGFloat) -> CGFloat {
            let eased = (1 - value.m11) / (1 - PeekWindowHostSupport.finalStep.m11)
            return abs(eased * PeekWindowHostSupport.finalStep.m41 + (1 + eased * (PeekWindowHostSupport.finalStep.m11 - 1)) * width / 2 - width / 2)
        }
        var worst: CGFloat = 0
        for (value, time) in zip(lo.values, lo.times) {
            let moment = lo.animation.beginTime + time * lo.animation.duration
            let slid = CGFloat(min(1, max(0, (moment - library.beginTime) / library.duration)))
            worst = max(worst, aimed(value, width: PeekWindowHostSupport.narrow.width + (PeekWindowHostSupport.wide.width - PeekWindowHostSupport.narrow.width) * slid))
        }
        for (value, time) in zip(go.values, go.times) {
            let moment = go.animation.beginTime + time * go.animation.duration
            let slid = CGFloat(min(1, (moment - long.beginTime) / long.duration))
            worst = max(worst, aimed(value, width: PeekWindowHostSupport.narrow.width + (PeekWindowHostSupport.wide.width - PeekWindowHostSupport.narrow.width) * slid))
        }
        #expect(worst > 0.5)
    }

    private static func springSlide() -> CASpringAnimation {
        let spring = CASpringAnimation(keyPath: PeekStepBack.slideKey)
        spring.stiffness = 1218
        spring.damping = 55.8
        spring.duration = spring.settlingDuration
        return spring
    }

    @MainActor @Test func aSpringSlideIsComposedForAsLongAsTheSpringRuns() throws {
        let spring = Self.springSlide()
        let o = try Self.opening(riding: spring)
        #expect(PeekWindowHostSupport.close(CGFloat(o.animation.duration), CGFloat(max(PeekStepBack.openDuration, spring.duration)), 0.01))
    }

    @MainActor @Test func theOpeningStepStaysCentredOnTheSpringingPage() throws {
        let spring = Self.springSlide()
        let o = try Self.opening(riding: spring)
        func springWidth(at elapsed: Double) -> CGFloat {
            var offset = 1.0, velocity = 0.0, clock = 0.0
            let step = 1e-5, mass = Double(spring.mass), stiffness = Double(spring.stiffness), damping = Double(spring.damping)
            while clock < elapsed {
                velocity += (-stiffness * offset - damping * velocity) / mass * step
                offset += velocity * step
                clock += step
            }
            return PeekWindowHostSupport.narrow.width + (PeekWindowHostSupport.wide.width - PeekWindowHostSupport.narrow.width) * CGFloat(1 - offset)
        }
        var checks = 0
        for (index, (value, time)) in zip(o.values, o.times).enumerated() where index > 0 && index < o.values.count - 1 && index % 4 == 0 {
            checks += 1
            #expect(PeekWindowHostSupport.close(PeekWindowHostSupport.centreOffset(of: value, width: springWidth(at: time * o.animation.duration)), 0, 0.02))
        }
        #expect(checks >= 6)
    }
}
