import AppKit
import Testing
@testable import Parc

struct NavigationLoadingTestsPillMotion {
    private typealias PillScene = NavigationLoadingTestsSupport.PillScene
    private typealias Frames = NavigationLoadingTestsSupport.Frames

    struct VisibilityCase: CustomTestStringConvertible {
        let label: String
        let occlusion: NSWindow.OcclusionState
        let miniaturized: Bool
        let hidden: Bool
        let visible: Bool

        var testDescription: String { label }
    }

    @Test(arguments: [
        VisibilityCase(label: "Visible window", occlusion: .visible, miniaturized: false, hidden: false, visible: true),
        VisibilityCase(label: "Occluded window", occlusion: [], miniaturized: false, hidden: false, visible: false),
        VisibilityCase(label: "Minimized window", occlusion: .visible, miniaturized: true, hidden: false, visible: false),
        VisibilityCase(label: "Hidden pill", occlusion: .visible, miniaturized: false, hidden: true, visible: false),
    ]) @MainActor
    func thePillCountsAsOnScreenOnlyWhenShownInAVisibleWindow(_ sample: VisibilityCase) {
        #expect(PageLoadingIndicator.isVisible(occlusion: sample.occlusion, miniaturized: sample.miniaturized,
                                               hidden: sample.hidden) == sample.visible)
    }

    @MainActor @Test func aPillWithoutAWindowCanStartLoading() {
        let pill = PageLoadingIndicator(frame: NSRect(x: 0, y: 0, width: 128, height: 4))
        let frames = Frames()
        pill.frames = frames
        pill.setLoading(true)
        #expect(pill.isLoading)
    }

    @MainActor @Test func aPillWithoutAWindowCanStopLoading() {
        let pill = PageLoadingIndicator(frame: NSRect(x: 0, y: 0, width: 128, height: 4))
        let frames = Frames()
        pill.frames = frames
        pill.setLoading(true)
        pill.setLoading(false)
        #expect(!pill.isLoading)
        #expect(frames.starts == 0)
    }

    @MainActor @Test func aLoadingPillOffScreenDoesNotTick() {
        let s = PillScene()
        s.onScreen = false
        s.startLoading()
        #expect(s.pill.isLoading)
        #expect(s.frames.starts == 0)
    }

    @MainActor @Test func aVisibleLoadingPillSamplesOnTheDisplayLink() {
        let s = PillScene()
        s.startLoading()
        #expect(s.frames.isRunning)
    }

    @MainActor @Test func loadingShowsTheFortyEightPointTrack() {
        let s = PillScene()
        s.startLoading()
        #expect(s.track.bounds.size == PageLoadingIndicator.trackSize(sweeping: false))
    }

    @MainActor @Test func thePillSweepsAtThePulseTroughOnTheFirstFrameAfterThreePointTwoSeconds() {
        let s = PillScene()
        s.startLoading()
        #expect(s.sweepFrame() == 193)
        #expect(s.bar.opacity == PageLoadingIndicator.sweepBarOpacity)
    }

    @MainActor @Test func theSweepSpringsTheTrackFromFortyEightToOneTwentyEightPoints() throws {
        let s = PillScene.sweeping()
        let widen = try #require(s.boundsSpring())
        #expect(s.track.bounds.size == PageLoadingIndicator.trackSize(sweeping: true))
        #expect(NavigationLoadingTestsSupport.near(widen.from, 48))
        #expect(widen.to == 128)
        #expect(PillScene.isSweepSpring(widen.spring))
    }

    @MainActor @Test func theSweepSpringsTheBarToPointNineTwo() throws {
        let s = PillScene.sweeping()
        let bar = try #require(s.barSpring())
        #expect(PillScene.isSweepSpring(bar))
        #expect((bar.toValue as? NSNumber)?.floatValue == PageLoadingIndicator.sweepBarOpacity)
    }

    @MainActor @Test func settledEmptyThirdTicksSkipLayerWritesWhileTheLinkKeepsSampling() {
        let s = PillScene.sweeping()
        #expect(s.settleSkippedTicks() == 2)
        #expect(s.frames.isRunning)
    }

    @MainActor @Test func strokeGrowthPresents() {
        let s = PillScene.sweeping()
        _ = s.settleSkippedTicks()
        var presented = false
        let limit = s.frame + 90
        while s.bar.strokeEnd == 0, s.frame < limit { presented = s.deliverFrame() }
        #expect(s.bar.strokeEnd > 0)
        #expect(presented)
    }

    @MainActor @Test func endingALoadMidSweepSpringsTheTrackBackToFortyEightPoints() throws {
        let s = PillScene.sweeping()
        s.pill.setLoading(false)
        let shrink = try #require(s.boundsSpring())
        #expect(s.track.bounds.size == PageLoadingIndicator.trackSize(sweeping: false))
        #expect(abs(shrink.from - 128) < 0.5)
        #expect(shrink.to == 48)
        #expect(PillScene.isSweepSpring(shrink.spring))
        #expect(s.frames.isRunning)
    }

    @MainActor @Test func endingALoadMidSweepSpringsTheBarToZero() throws {
        let s = PillScene.sweeping()
        s.pill.setLoading(false)
        let bar = try #require(s.barSpring())
        #expect(s.bar.opacity == 0)
        #expect((bar.toValue as? NSNumber)?.floatValue == 0)
    }

    @MainActor @Test func resetRemovesTheTrackAndBarSpringsAndIdlesThePill() {
        let s = PillScene.sweeping()
        s.pill.setLoading(false)
        s.pill.reset()
        #expect(s.track.animation(forKey: "bounds") == nil)
        #expect(s.bar.animation(forKey: "opacity") == nil)
        #expect(!s.frames.isRunning)
    }

    @MainActor @Test func aSecondLoadSweepsAgainOnTheFirstFrameAfterThreePointTwoSeconds() {
        let s = PillScene.sweeping()
        s.pill.setLoading(false)
        s.pill.reset()
        s.startLoading()
        #expect(s.sweepFrame() == 193)
        #expect(s.bar.opacity > 0)
    }

    @MainActor @Test func aReduceMotionSweepExitPresentsNarrowsWithoutASpringAndIdles() {
        let s = PillScene.sweeping()
        s.reduceMotion = true
        #expect(s.deliverFrame())
        #expect(s.bar.opacity == 0)
        #expect(!s.frames.isRunning)
        #expect(s.track.bounds.size == PageLoadingIndicator.trackSize(sweeping: false))
        #expect(s.track.animation(forKey: "bounds") == nil)
        #expect(s.bar.animation(forKey: "opacity") == nil)
    }

    @MainActor @Test func reduceMotionLoadingHoldsThePulseWithoutTicking() {
        let s = PillScene()
        s.reduceMotion = true
        s.startLoading()
        #expect(s.pill.isLoading)
        #expect(s.frames.starts == 0)
    }

    @MainActor private static func hidingAfterAReduceMotionLoad() -> PillScene {
        let s = PillScene()
        s.reduceMotion = true
        s.startLoading()
        s.reduceMotion = false
        s.pill.setLoading(false)
        return s
    }

    @MainActor @Test func hidingSamplesThePulseBackToRest() {
        let s = Self.hidingAfterAReduceMotionLoad()
        #expect(s.frames.starts == 1)
        #expect(s.frames.isRunning)
    }

    @MainActor @Test func resetIdlesAHidingPill() {
        let s = Self.hidingAfterAReduceMotionLoad()
        s.pill.reset()
        #expect(!s.frames.isRunning)
    }
}
