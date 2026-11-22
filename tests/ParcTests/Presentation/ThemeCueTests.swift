import AppKit
import Testing
import ParcCore
@testable import Parc
@testable import ParcKit
@testable import ParcSidebar

struct ThemeAppearanceTimerIdleTests {
    @MainActor private final class Frames {
        var time: CFTimeInterval = 0
        var timer: Timer?

        func makeCue(_ appearance: AppAppearance = .dark, allowsPlayback: Bool = true) -> ThemeAppearanceButton {
            _ = NSApplication.shared
            let cue = ThemeAppearanceButton(appearance: appearance, resources: Bundle.module,
                                            allowsPlayback: { allowsPlayback }, scheduleFrame: { [weak self] in self?.timer = $0 })
            cue.now = { [weak self] in self?.time ?? 0 }
            cue.setFrameSize(CGSize(width: 40, height: 40))
            return cue
        }

        func frame(at seconds: CFTimeInterval) {
            time = seconds
            timer?.fire()
        }
    }

    @Test @MainActor func identicalCueFramesSkipTheRedraw() throws {
        let frames = Frames()
        let cue = frames.makeCue()
        var redraws = 0
        cue.onDisplayInvalidated = { redraws += 1 }
        cue.isSelected = true
        let timer = try #require(frames.timer)
        frames.frame(at: 82.0 / 60.0)
        let before = redraws
        frames.frame(at: 88.0 / 60.0)
        #expect(timer.isValid)
        #expect(redraws == before)
    }

    @Test @MainActor func theCueRedrawsWhenItLeavesAnIdenticalHold() {
        let frames = Frames()
        let cue = frames.makeCue()
        var redraws = 0
        cue.onDisplayInvalidated = { redraws += 1 }
        cue.isSelected = true
        frames.frame(at: 88.0 / 60.0)
        let before = redraws
        frames.frame(at: 2)
        #expect(redraws == before + 1)
    }

    @Test(arguments: [true, false])
    @MainActor func aHiddenOrUnselectedCueStopsRequestingFrames(hidden: Bool) throws {
        let frames = Frames()
        let cue = frames.makeCue()
        cue.isSelected = true
        let timer = try #require(frames.timer)
        if hidden { cue.isHidden = true } else { cue.isSelected = false }
        frames.frame(at: 1.0 / 60.0)
        #expect(!timer.isValid)
    }

    @Test @MainActor func aHiddenCueCanResumeWhenItBecomesVisible() throws {
        let frames = Frames()
        let cue = frames.makeCue()
        cue.isSelected = true
        let first = try #require(frames.timer)
        cue.isHidden = true
        frames.frame(at: 1.0 / 60.0)
        cue.isHidden = false
        cue.viewDidUnhide()
        #expect(!first.isValid)
        #expect(frames.timer?.isValid == true && frames.timer !== first)
    }

    @Test @MainActor func aCueWithMotionDisabledDoesNotStartAFrameSource() {
        let frames = Frames()
        let cue = frames.makeCue(allowsPlayback: false)
        cue.isSelected = true
        #expect(frames.timer == nil)
    }

    @Test @MainActor func aSettledHoverStopsTheButtonsFrameSource() throws {
        _ = NSApplication.shared
        let view = NSView()
        let frames = Frames()
        let motion = ThemeButtonMotionDriver(view: view, now: { frames.time }, allowsMotion: { true },
                                            scheduleFrame: { frames.timer = $0 })
        motion.update(hovered: true)
        let timer = try #require(frames.timer)
        frames.frame(at: 0.05)
        #expect(timer.isValid)
        frames.frame(at: 0.11)
        #expect(motion.motion.isSettled && motion.motion.hover == 1)
        #expect(!timer.isValid)
    }

    @Test @MainActor func aSettledPressStopsTheButtonsFrameSource() throws {
        _ = NSApplication.shared
        let view = NSView()
        let frames = Frames()
        let motion = ThemeButtonMotionDriver(view: view, now: { frames.time }, allowsMotion: { true },
                                            scheduleFrame: { frames.timer = $0 })
        motion.update(pressed: true)
        let timer = try #require(frames.timer)
        frames.frame(at: 1)
        #expect(motion.motion.isSettled && motion.motion.press == 0.9)
        #expect(!timer.isValid)
    }

    @Test func theSunCueFingerprintIncludesRotation() throws {
        let sun = try #require(ThemeAppearanceAnimation(name: "sun", resources: Bundle.module))
        let size = CGSize(width: 28, height: 28)
        #expect(sun.presentationFingerprint(seconds: 0.1, size: size) != sun.presentationFingerprint(seconds: 0.4, size: size))
    }

    @Test func aResizedCueHasANewPresentationFingerprint() throws {
        let moon = try #require(ThemeAppearanceAnimation(name: "moon", resources: Bundle.module))
        let compact = moon.presentationFingerprint(seconds: 1.4, size: CGSize(width: 28, height: 28))
        let large = moon.presentationFingerprint(seconds: 1.4, size: CGSize(width: 40, height: 40))
        #expect(compact != large)
    }
}
