import CoreGraphics
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct StartPageMarkGestureTestsClick {
    private typealias Pointer = StartPageMarkGestureTestsSupport.Pointer

    private let origin = CGPoint(x: 30, y: 40)

    @Test func pressingTheMarkDoesNothingOnItsOwnAndArmsOneHoldDeadline() {
        var recognizer = StartPageMarkGestureRecognizer(clickInterval: 0.5)
        #expect(recognizer.pointerDown(at: origin, time: 0, idle: true).isEmpty)
        #expect(recognizer.holdDeadline == StartPageMarkGestureRecognizer.holdDelay)
    }

    @Test func aSingleClickDoesNothingAndCountsAsAClick() {
        var recognizer = StartPageMarkGestureRecognizer(clickInterval: 0.5)
        _ = recognizer.pointerDown(at: origin, time: 0, idle: true)
        #expect(recognizer.pointerUp(at: origin, time: 0.1).isEmpty)
        #expect(recognizer.holdDeadline == nil)
        #expect(recognizer.clicks?.count == 1)
    }

    @Test func aSingleClickDoesNotTriggerPlayback() {
        var pointer = Pointer()
        #expect(pointer.click(origin, 0).isEmpty)
    }

    @Test func aDoubleClickLeavesTheMarkAtRest() {
        var pointer = Pointer()
        _ = pointer.click(origin, 0)
        #expect(pointer.click(origin, 0.3).isEmpty)
        #expect(pointer.session.phase == .rest && pointer.session.generation == 0)
    }

    @Test func aWobbleInsideTheSlopDoesNotStartTheStretchOrCountAsAnythingMore() {
        var pointer = Pointer()
        _ = pointer.down(origin, 5)
        #expect(pointer.drag(CGPoint(x: 33, y: 42), 5.05).isEmpty)
        #expect(pointer.drag(CGPoint(x: 34, y: 40), 5.06).isEmpty)
        #expect(pointer.up(CGPoint(x: 33, y: 42), 5.1).isEmpty)
    }

    @Test func draggingWithoutAPressDoesNothing() {
        var pointer = Pointer()
        #expect(pointer.drag(CGPoint(x: 90, y: 40), 5.2).isEmpty)
    }

    @Test func releasingWithoutAPressDoesNothing() {
        var pointer = Pointer()
        _ = pointer.drag(CGPoint(x: 90, y: 40), 5.2)
        #expect(pointer.up(CGPoint(x: 90, y: 40), 5.3).isEmpty)
    }

    @Test func aHoldDeadlineWithoutAPressDoesNothing() {
        var pointer = Pointer()
        _ = pointer.drag(CGPoint(x: 90, y: 40), 5.2)
        _ = pointer.up(CGPoint(x: 90, y: 40), 5.3)
        #expect(pointer.hold(6).isEmpty)
    }

    @Test func followUpCuesWithoutATriggerDoNothing() {
        var session = StartPageMarkSession()
        let cues: [StartPageMarkCue] = [.track(CGVector(dx: 5, dy: 0)), .release(CGVector(dx: 5, dy: 0)), .discharge(1), .cancel(1)]
        #expect(cues.flatMap { session.handle($0, canAnimate: true, reduceMotion: false) }.isEmpty)
        #expect(session.phase == .rest && session.generation == 0)
    }
}
