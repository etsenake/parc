import CoreGraphics
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct StartPageMarkGestureTestsSwoop {
    private typealias Pointer = StartPageMarkGestureTestsSupport.Pointer

    private let spot = CGPoint(x: 30, y: 50)

    @Test func twoQuickClicksAreCounted() {
        var pointer = Pointer()
        _ = pointer.click(spot, 0)
        _ = pointer.click(CGPoint(x: 33, y: 52), 0.2)
        #expect(pointer.recognizer.clicks?.count == 2)
    }

    @Test func theThirdQuickClickSwoopsAtOnceConsumingTheClicks() {
        var pointer = Pointer()
        _ = pointer.click(spot, 0)
        _ = pointer.click(CGPoint(x: 33, y: 52), 0.2)
        let third = pointer.recognizer.pointerDown(at: CGPoint(x: 34, y: 47), time: 0.4, idle: true)
        #expect(third == [.begin(.swoop)])
        #expect(pointer.recognizer.holdDeadline == nil && pointer.recognizer.clicks == nil)
        #expect(pointer.send(third) == [.play(.swoop)])
        #expect(pointer.session.phase == .playing(.swoop, .motion) && pointer.session.landing)
    }

    @Test func draggingTheThirdPressDoesNothingMore() {
        var pointer = Pointer()
        _ = pointer.click(spot, 0)
        _ = pointer.click(CGPoint(x: 33, y: 52), 0.2)
        _ = pointer.down(CGPoint(x: 34, y: 47), 0.4)
        #expect(pointer.drag(CGPoint(x: 80, y: 80), 0.45).isEmpty)
    }

    @Test func releasingTheThirdPressDoesNothingMore() {
        var pointer = Pointer()
        _ = pointer.click(spot, 0)
        _ = pointer.click(CGPoint(x: 33, y: 52), 0.2)
        _ = pointer.down(CGPoint(x: 34, y: 47), 0.4)
        _ = pointer.drag(CGPoint(x: 80, y: 80), 0.45)
        #expect(pointer.up(CGPoint(x: 80, y: 80), 0.5).isEmpty)
    }

    @Test func theSwoopTicksOnLanding() {
        var pointer = Pointer()
        _ = pointer.click(spot, 0)
        _ = pointer.click(CGPoint(x: 33, y: 52), 0.2)
        _ = pointer.down(CGPoint(x: 34, y: 47), 0.4)
        _ = pointer.drag(CGPoint(x: 80, y: 80), 0.45)
        _ = pointer.up(CGPoint(x: 80, y: 80), 0.5)
        #expect(pointer.session.land(generation: pointer.session.generation) == [.haptic])
    }

    @Test func aSlowThirdClickDoesNotSwoopAndStartsANewCount() {
        var slow = Pointer()
        _ = slow.click(spot, 0)
        _ = slow.click(spot, 0.3)
        #expect(slow.down(spot, 0.38 + 0.51).isEmpty)
        #expect(slow.recognizer.clicks == nil)
    }

    @Test func aThirdClickAwayFromTheFirstDoesNotSwoop() {
        var far = Pointer()
        _ = far.click(spot, 0)
        _ = far.click(spot, 0.2)
        #expect(far.down(CGPoint(x: spot.x + 9, y: spot.y), 0.4).isEmpty)
    }

    @Test func theClickIntervalFollowsTheSystemSetting() {
        var system = Pointer()
        system.recognizer.clickInterval = 1.5
        _ = system.click(spot, 0)
        _ = system.click(spot, 1)
        #expect(system.down(spot, 2) == [.play(.swoop)])
    }

    @Test func aDragBetweenClicksBreaksTheTripleClick() {
        var broken = Pointer()
        _ = broken.click(spot, 0)
        _ = broken.down(spot, 0.2)
        _ = broken.drag(CGPoint(x: spot.x + 20, y: spot.y), 0.25)
        _ = broken.up(CGPoint(x: spot.x + 20, y: spot.y), 0.3)
        broken.session.finish(generation: broken.session.generation)
        _ = broken.click(spot, 0.4)
        #expect(broken.down(spot, 0.6).isEmpty)
    }
}
