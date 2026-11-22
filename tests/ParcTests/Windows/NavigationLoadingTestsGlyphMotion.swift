import AppKit
import Testing
@testable import Parc
@testable import ParcKit

struct NavigationLoadingTestsGlyphMotion {
    private typealias GlyphScene = NavigationLoadingTestsSupport.GlyphScene

    @MainActor @Test func anUnanimatedSwitchToStopSettlesTheGlyph() {
        let s = GlyphScene()
        s.glyph.update(loading: true, forceReload: false, animated: false)
        #expect(s.glyph.progress == 1)
        #expect(s.glyph.loading)
    }

    @MainActor @Test func theForceDefaultSwitchesTheIdleGlyph() {
        let s = GlyphScene()
        s.glyph.update(loading: false, forceReload: true, animated: false)
        #expect(s.glyph.progress == 0)
        #expect(s.glyph.forceReload)
    }

    struct GlyphState: CustomTestStringConvertible {
        let label: String
        let loading: Bool
        let forceReload: Bool

        var testDescription: String { label }
    }

    @Test(arguments: [
        GlyphState(label: "Loading", loading: true, forceReload: false),
        GlyphState(label: "Force reload", loading: false, forceReload: true),
    ]) @MainActor
    func unanimatedGlyphChangesNeverTick(_ sample: GlyphState) {
        let s = GlyphScene()
        s.glyph.update(loading: sample.loading, forceReload: sample.forceReload, animated: false)
        #expect(s.frames.starts == 0)
    }

    struct MotionSetting: CustomTestStringConvertible {
        let label: String
        let animated: Bool
        let reduceMotion: Bool

        var testDescription: String { label }
    }

    @Test(arguments: [
        MotionSetting(label: "Animation disabled", animated: false, reduceMotion: false),
        MotionSetting(label: "Reduce Motion enabled", animated: true, reduceMotion: true),
    ]) @MainActor
    func anUnanimatedOrReduceMotionActionSpinLeavesTheGlyphUprightWithoutTicking(_ sample: MotionSetting) {
        let s = GlyphScene()
        s.reduceMotion = sample.reduceMotion
        s.glyph.playActionSpin(animated: sample.animated)
        #expect(abs(s.glyph.rotation) < 0.001)
        #expect(s.frames.starts == 0)
    }

    @MainActor @Test func reduceMotionSnapsTheGlyphToStopAndIdles() {
        let s = GlyphScene()
        s.reduceMotion = true
        s.glyph.update(loading: true, forceReload: false, animated: true)
        #expect(s.glyph.progress == 1)
        #expect(s.frames.starts == 0)
    }

    @MainActor @Test func theLoadSpringSamplesOnTheDisplayLink() {
        let s = GlyphScene()
        s.glyph.update(loading: true, forceReload: false, animated: true)
        #expect(s.frames.isRunning)
    }

    @MainActor @Test func aFrameInsideTheEnteringDelayRedrawsTheIdleGlyphAndKeepsSampling() {
        let s = GlyphScene()
        s.glyph.update(loading: true, forceReload: false, animated: true)
        let redraws = s.view.redraws
        s.clock += ReloadGlyph.delay(enteringLoading: true) - 1.0 / 60
        s.frames.fire()
        #expect(s.glyph.progress == 0)
        #expect(s.frames.isRunning)
        #expect(s.view.redraws == redraws + 1)
    }

    @MainActor @Test func stopSettlesTheGlyphAndIdles() {
        let s = GlyphScene()
        s.glyph.update(loading: true, forceReload: false, animated: true)
        s.glyph.stop()
        #expect(s.glyph.progress == 1)
        #expect(!s.frames.isRunning)
    }

    @MainActor @Test func theActionSpinSamplesOnTheDisplayLink() {
        let s = GlyphScene()
        s.glyph.playActionSpin(animated: true)
        #expect(s.frames.isRunning)
    }

    @MainActor @Test func stopIdlesTheActionSpin() {
        let s = GlyphScene()
        s.glyph.playActionSpin(animated: true)
        s.glyph.stop()
        #expect(!s.frames.isRunning)
    }

    @MainActor private static func unloading() -> GlyphScene {
        let s = GlyphScene()
        s.glyph.update(loading: true, forceReload: false, animated: false)
        s.glyph.update(loading: false, forceReload: false, animated: true)
        return s
    }

    @MainActor @Test func leavingLoadingSamplesOnTheDisplayLink() {
        #expect(Self.unloading().frames.isRunning)
    }

    @MainActor @Test func midSpringTheGlyphKeepsSamplingBetweenStopAndReload() {
        let s = Self.unloading()
        s.clock = ReloadGlyph.delay(enteringLoading: false) + ReloadGlyph.settlingTime / 2
        s.frames.fire()
        #expect(s.frames.isRunning)
        #expect(s.glyph.progress != 0)
        #expect(s.glyph.progress != 1)
    }

    @MainActor @Test func aSettledSpringStopsItsOwnDisplayLink() {
        let s = Self.unloading()
        s.clock = ReloadGlyph.delay(enteringLoading: false) + ReloadGlyph.settlingTime + 1.0 / 60
        s.frames.fire()
        #expect(s.glyph.progress == 0)
        #expect(!s.frames.isRunning)
    }
}
