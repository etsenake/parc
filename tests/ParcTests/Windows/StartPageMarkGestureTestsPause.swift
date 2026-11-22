import CoreGraphics
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct StartPageMarkGestureTestsPause {
    private typealias Pointer = StartPageMarkGestureTestsSupport.Pointer

    private let visible = StartPageMarkActivity(windowVisible: true, occluded: false, miniaturized: false, hidden: false)

    @Test func aVisibleWindowAnimates() {
        #expect(visible.canAnimate)
    }

    struct WindowChange: CustomTestStringConvertible {
        let label: String
        let key: WritableKeyPath<StartPageMarkActivity, Bool>
        let value: Bool

        var testDescription: String { label }
    }

    @Test(arguments: [
        WindowChange(label: "Occluded", key: \.occluded, value: true),
        WindowChange(label: "Minimized", key: \.miniaturized, value: true),
        WindowChange(label: "Hidden", key: \.hidden, value: true),
        WindowChange(label: "Invisible", key: \.windowVisible, value: false),
    ])
    func aWindowThatStopsBeingVisiblePauses(_ sample: WindowChange) {
        var activity = visible
        activity[keyPath: sample.key] = sample.value
        #expect(!activity.canAnimate)
    }

    @Test func aMarkWithoutAWindowPauses() {
        #expect(!StartPageMarkActivity.inactive.canAnimate)
    }

    @Test(arguments: [StartPageMarkEasterEgg.taffy, .swoop, .charge])
    func aTriggerInAPausedWindowIsSkipped(egg: StartPageMarkEasterEgg) {
        var session = StartPageMarkSession()
        #expect(session.handle(.begin(egg), canAnimate: false, reduceMotion: false).isEmpty && session.phase == .rest)
    }

    @Test func pausingAtRestDoesNothing() {
        var session = StartPageMarkSession()
        #expect(session.pause().isEmpty && session.generation == 0)
    }

    @Test func losingVisibilityMidStretchPutsTheMarkBackAtRest() {
        var session = StartPageMarkSession()
        _ = session.handle(.begin(.taffy), canAnimate: true, reduceMotion: false)
        #expect(session.handle(.track(CGVector(dx: 9, dy: 0)), canAnimate: false, reduceMotion: false) == [.reset])
    }

    @Test func aReleaseInAPausedWindowNeitherPlaysNorTicks() {
        var session = StartPageMarkSession()
        _ = session.handle(.begin(.charge), canAnimate: true, reduceMotion: false)
        #expect(session.handle(.discharge(1), canAnimate: false, reduceMotion: false) == [.reset])
    }

    @Test func occludingTheWindowMidSwoopSkipsToRest() {
        var session = StartPageMarkSession()
        _ = session.handle(.begin(.swoop), canAnimate: true, reduceMotion: false)
        #expect(session.pause() == [.reset] && session.phase == .rest)
    }

    @Test func landingAfterOcclusionDoesNotTick() {
        var session = StartPageMarkSession()
        _ = session.handle(.begin(.swoop), canAnimate: true, reduceMotion: false)
        let generation = session.generation
        _ = session.pause()
        #expect(session.land(generation: generation).isEmpty)
    }

    @Test func finishingAfterOcclusionKeepsTheMarkAtRest() {
        var session = StartPageMarkSession()
        _ = session.handle(.begin(.swoop), canAnimate: true, reduceMotion: false)
        let generation = session.generation
        _ = session.pause()
        _ = session.land(generation: generation)
        session.finish(generation: generation)
        #expect(session.phase == .rest && session.generation == generation + 1)
    }

    @Test func hidingTheWindowMidChargeResetsItAndEndsTheGesture() {
        var pointer = Pointer()
        _ = pointer.down(.zero, 0)
        _ = pointer.hold(0.35)
        pointer.canAnimate = false
        #expect(pointer.drag(CGPoint(x: 12, y: 0), 0.4) == [.reset])
        #expect(pointer.recognizer.press == nil && pointer.recognizer.holdDeadline == nil)
    }
}
