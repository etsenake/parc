import AppKit
import QuartzCore

/// Inert poster/video handoff checks. No browser, engine or user profile.
@main
struct OnboardingVideoHandoffTests {
    static func main() {
        let now: TimeInterval = 1_000
        precondition(
            OnboardingVideoHandoff.recoveredDuration(imageBeginTime: now, now: now) == 0,
            "A just-started poster fade yields min(0.5, 0) = 0"
        )
        precondition(
            OnboardingVideoHandoff.recoveredDuration(imageBeginTime: now, now: now + 0.2) == 0,
            "A mid-fade remaining of 0.3 still clamps through min(..., 0)"
        )
        precondition(
            OnboardingVideoHandoff.recoveredDuration(imageBeginTime: now, now: now + 0.5) == 0,
            "Exact poster-fade completion yields 0"
        )
        let overdue = OnboardingVideoHandoff.recoveredDuration(imageBeginTime: now, now: now + 0.7)
        precondition(abs(overdue - (-0.2)) < 1e-9, "After the 0.5 s fade, recovered duration is negative: \(overdue)")
        precondition(
            OnboardingVideoHandoff.mediaDuration(recovered: overdue) == 0
                && OnboardingVideoHandoff.mediaDuration(recovered: 0) == 0,
            "Core Animation duration stays nonnegative; recovered timing is never a positive fade"
        )

        func action(_ opacity: Float?, begin: TimeInterval?) -> OnboardingVideoHandoff.Action {
            OnboardingVideoHandoff.action(presentationOpacity: opacity, imageBeginTime: begin, now: now)
        }
        precondition(action(nil, begin: now) == .cutToVideo, "Nil presentationLayer cuts")
        precondition(action(1, begin: now) == .cutToVideo, "An already opaque poster cuts")
        precondition(action(1.2, begin: now) == .cutToVideo, "Opacity ≥ 1 takes the cut branch")
        precondition(action(0.4, begin: nil) == .cutToVideo, "A missing imageOpacity animation cuts")
        precondition(
            action(0.4, begin: now) == .fadeVideo(from: 0.4, duration: 0),
            "A mid-fade poster still creates the video opacity animation; duration is 0"
        )
        precondition(
            action(0.4, begin: now - 0.7) == .fadeVideo(from: 0.4, duration: 0),
            "A finished poster fade still uses the fade branch with a zero CA duration"
        )

        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView?.wantsLayer = true
        window.orderBack(nil)
        window.displayIfNeeded()
        guard let host = window.contentView?.layer else {
            fatalError("The inert host needs a layer to attach poster and video")
        }

        let poster = CALayer()
        let video = CALayer()
        video.opacity = 0
        host.addSublayer(poster)
        host.addSublayer(video)
        OnboardingVideoHandoff.reveal(poster: poster, video: video, now: now)
        precondition(poster.superlayer == nil, "Cut removes the poster from the tree")
        precondition(video.opacity == 1, "An opaque or unpresented poster sets video opacity to 1")

        let fadingPoster = CALayer()
        let fadingVideo = CALayer()
        fadingVideo.opacity = 0
        host.addSublayer(fadingPoster)
        host.addSublayer(fadingVideo)
        fadingPoster.add(posterFade(begin: now), forKey: OnboardingVideoHandoff.imageOpacityKey)
        OnboardingVideoHandoff.reveal(
            poster: fadingPoster, video: fadingVideo, now: now, presentationOpacity: 0.4
        )
        precondition(fadingPoster.superlayer == nil, "The fade branch also removes the poster")
        precondition(fadingVideo.opacity == 0, "The fade branch leaves the video model opacity at 0")

        print("Onboarding video/poster handoff checks passed")
    }

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
}
