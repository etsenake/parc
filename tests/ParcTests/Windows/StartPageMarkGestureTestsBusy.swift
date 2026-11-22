import CoreGraphics
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct StartPageMarkGestureTestsBusy {
    private typealias Pointer = StartPageMarkGestureTestsSupport.Pointer

    private func playingTaffy() -> (Pointer, Int) {
        var pointer = Pointer()
        _ = pointer.down(.zero, 0)
        _ = pointer.drag(CGPoint(x: 0, y: 20), 0.1)
        _ = pointer.up(CGPoint(x: 0, y: 20), 0.2)
        return (pointer, pointer.session.generation)
    }

    @Test func aPressDuringPlaybackDoesNotArmAHold() {
        let (started, _) = playingTaffy()
        var pointer = started
        #expect(pointer.session.phase == .playing(.taffy, .motion))
        #expect(pointer.recognizer.pointerDown(at: .zero, time: 0.3, idle: false).isEmpty)
        #expect(pointer.recognizer.holdDeadline == nil)
    }

    @Test func draggingAPressDuringPlaybackDoesNothing() {
        let (started, _) = playingTaffy()
        var pointer = started
        _ = pointer.recognizer.pointerDown(at: .zero, time: 0.3, idle: false)
        #expect(pointer.drag(CGPoint(x: 20, y: 0), 0.35).isEmpty)
    }

    @Test func aPressIgnoredDuringPlaybackStaysIgnoredAfterPlaybackEnds() {
        let (started, playing) = playingTaffy()
        var pointer = started
        _ = pointer.recognizer.pointerDown(at: .zero, time: 0.3, idle: false)
        _ = pointer.drag(CGPoint(x: 20, y: 0), 0.35)
        pointer.session.finish(generation: playing)
        #expect(pointer.drag(CGPoint(x: 40, y: 0), 0.45).isEmpty)
        #expect(pointer.up(CGPoint(x: 40, y: 0), 0.5).isEmpty)
    }

    @Test func clicksDuringPlaybackNeverCountTowardASwoop() {
        var clicks = Pointer()
        _ = clicks.down(.zero, 0)
        _ = clicks.hold(0.35)
        _ = clicks.up(.zero, 1.5)
        let loop = clicks.session.generation
        _ = clicks.click(.zero, 1.6)
        _ = clicks.click(.zero, 1.8)
        clicks.session.finish(generation: loop)
        #expect(clicks.down(.zero, 2.0).isEmpty)
        #expect(clicks.recognizer.clicks == nil)
    }

    @Test func holdingDuringARelaxDoesNotChargeAgain() {
        var holding = Pointer()
        _ = holding.down(.zero, 0)
        _ = holding.hold(0.35)
        _ = holding.up(.zero, 0.6)
        _ = holding.recognizer.pointerDown(at: .zero, time: 0.7, idle: holding.session.isIdle)
        #expect(holding.hold(1.1).isEmpty)
    }

    @Test(arguments: [StartPageMarkCue.begin(.swoop), .begin(.charge), .begin(.taffy), .track(CGVector(dx: 9, dy: 0)),
                      .release(CGVector(dx: 9, dy: 0)), .discharge(1), .cancel(1)])
    func aTriggerDuringPlaybackIsIgnored(cue: StartPageMarkCue) {
        var session = StartPageMarkSession()
        _ = session.handle(.begin(.swoop), canAnimate: true, reduceMotion: false)
        #expect(session.handle(cue, canAnimate: true, reduceMotion: false).isEmpty)
        #expect(session.phase == .playing(.swoop, .motion))
    }

    @Test func aStaleCompletionCannotEndANewerPlay() {
        var stale = StartPageMarkSession()
        _ = stale.handle(.begin(.taffy), canAnimate: true, reduceMotion: false)
        _ = stale.handle(.release(.zero), canAnimate: true, reduceMotion: false)
        let old = stale.generation
        _ = stale.pause()
        _ = stale.handle(.begin(.taffy), canAnimate: true, reduceMotion: false)
        _ = stale.handle(.release(.zero), canAnimate: true, reduceMotion: false)
        stale.finish(generation: old)
        #expect(stale.phase == .playing(.taffy, .motion))
    }

    @Test func theCurrentCompletionReturnsTheMarkToRest() {
        var stale = StartPageMarkSession()
        _ = stale.handle(.begin(.taffy), canAnimate: true, reduceMotion: false)
        _ = stale.handle(.release(.zero), canAnimate: true, reduceMotion: false)
        stale.finish(generation: stale.generation)
        #expect(stale.phase == .rest)
    }

    @Test func aCompletionCannotEndAChargeThatIsStillHeld() {
        var interacting = StartPageMarkSession()
        _ = interacting.handle(.begin(.charge), canAnimate: true, reduceMotion: false)
        interacting.finish(generation: interacting.generation)
        #expect(interacting.phase == .interacting(.charge, .motion))
    }

    struct MismatchedRelease: CustomTestStringConvertible {
        let label: String
        let egg: StartPageMarkEasterEgg
        let cue: StartPageMarkCue

        var testDescription: String { label }
    }

    @Test(arguments: [
        MismatchedRelease(label: "Charge release during taffy", egg: .taffy, cue: .discharge(1)),
        MismatchedRelease(label: "Taffy release during charge", egg: .charge, cue: .release(.zero)),
    ])
    func aMismatchedReleaseCannotEndTheGesture(_ sample: MismatchedRelease) {
        var session = StartPageMarkSession()
        _ = session.handle(.begin(sample.egg), canAnimate: true, reduceMotion: false)
        #expect(session.handle(sample.cue, canAnimate: true, reduceMotion: false).isEmpty)
    }
}
