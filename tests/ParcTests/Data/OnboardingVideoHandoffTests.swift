import QuartzCore
import Testing
@testable import Parc

struct OnboardingVideoHandoffTests {
    private static let now: TimeInterval = 1_000

    private static func posterFade(begin: TimeInterval) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = OnboardingVideoHandoff.posterFadeDuration
        animation.beginTime = begin
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        return animation
    }

    private static func action(_ opacity: Float?, begin: TimeInterval?) -> OnboardingVideoHandoff.Action {
        OnboardingVideoHandoff.action(presentationOpacity: opacity, imageBeginTime: begin, now: now)
    }

    @Test(arguments: [0.0, 0.2, 0.5])
    func aPosterFadeThatHasNotOverrunRecoversNoDuration(elapsed: Double) {
        #expect(OnboardingVideoHandoff.recoveredDuration(imageBeginTime: Self.now, now: Self.now + elapsed) == 0)
    }

    @Test func aPosterFadeThatOverranRecoversANegativeDuration() {
        let overdue = OnboardingVideoHandoff.recoveredDuration(imageBeginTime: Self.now, now: Self.now + 0.7)
        #expect(abs(overdue - (-0.2)) < 1e-9)
    }

    @Test(arguments: [0.0, -0.2])
    func theMediaDurationNeverGoesNegative(recovered: Double) {
        #expect(OnboardingVideoHandoff.mediaDuration(recovered: recovered) == 0)
    }

    @Test(arguments: [(nil, Self.now), (1, Self.now), (1.2, Self.now), (0.4, nil)] as [(Float?, TimeInterval?)])
    func aMissingOrOpaquePosterCutsToTheVideo(opacity: Float?, begin: TimeInterval?) {
        #expect(Self.action(opacity, begin: begin) == .cutToVideo)
    }

    @Test(arguments: [Self.now, Self.now - 0.7])
    func aFadingPosterFadesTheVideoWithAZeroDuration(begin: TimeInterval) {
        #expect(Self.action(0.4, begin: begin) == .fadeVideo(from: 0.4, duration: 0))
    }

    @Test func aCutRemovesThePosterAndShowsTheVideo() {
        let host = CALayer(), poster = CALayer(), video = CALayer()
        video.opacity = 0
        host.addSublayer(poster)
        host.addSublayer(video)
        OnboardingVideoHandoff.reveal(poster: poster, video: video, now: Self.now)
        #expect(poster.superlayer == nil)
        #expect(video.opacity == 1)
    }

    @Test func aFadeRemovesThePoster() {
        let host = CALayer(), poster = CALayer(), video = CALayer()
        video.opacity = 0
        host.addSublayer(poster)
        host.addSublayer(video)
        poster.add(Self.posterFade(begin: Self.now), forKey: OnboardingVideoHandoff.imageOpacityKey)
        OnboardingVideoHandoff.reveal(poster: poster, video: video, now: Self.now, presentationOpacity: 0.4)
        #expect(poster.superlayer == nil)
    }

    @Test func aFadeLeavesTheVideoModelOpacityAtZero() {
        let host = CALayer(), poster = CALayer(), video = CALayer()
        video.opacity = 0
        host.addSublayer(poster)
        host.addSublayer(video)
        poster.add(Self.posterFade(begin: Self.now), forKey: OnboardingVideoHandoff.imageOpacityKey)
        OnboardingVideoHandoff.reveal(poster: poster, video: video, now: Self.now, presentationOpacity: 0.4)
        #expect(video.opacity == 0)
    }
}
