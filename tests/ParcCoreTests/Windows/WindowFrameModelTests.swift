import Foundation
import Testing
@testable import ParcCore

import CoreGraphics

struct WindowFrameModelTests {
    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.0001) -> Bool { abs(a - b) < tolerance }
    @Test static func thicknessRangeLabelsCornersAndGrip() {
        typealias T = WindowFrameThickness
        #expect(T.range == 3...13 && T.standard == 10, "range and default")
        #expect(T.clamped(1) == 3 && T.clamped(20) == 13 && T.clamped(7) == 7, "clamping")
        #expect(T.label(10) == "10 · Classic" && T.label(3) == "3 · Hairline" && T.label(13) == "13 · Gallery", "labels")
        #expect(T.spokenValue(10) == "10 points, Classic", "spoken value")
        #expect(T.range.allSatisfy { !T.name($0).isEmpty }, "every point has a name")
        #expect(T.cornerRadius(for: 10) == 6, "today's corner at the default")
        #expect(T.cornerRadius(for: 3) == 12 && T.cornerRadius(for: 13) == 4, "corners stay concentric and bounded")
        #expect(T.cornerRadius(for: 4) > T.cornerRadius(for: 12), "a thinner frame rounds the page more")
        #expect(!T.showsSplitGrip(5) && T.showsSplitGrip(6) && T.showsSplitGrip(10), "grip hides below six points")
        #expect(near(T.notchPitch(8), 1) && near(T.notchPitch(9) / T.notchPitch(8), pow(2, 1.0 / 12)), "a semitone per point")
        #expect(T.notchPitch(13) > T.notchPitch(3), "clicks rise as the frame opens")
    }

    @Test static func aCrankStartsAtTheSavedValueAndClicksOncePerPointPassed() {
        var crank = WindowFrameCrank(value: 10)
        #expect(crank.value == 10 && crank.litCount == 8 && near(crank.armDegrees, 90 - 7 * 120), "starts at the saved value")
        #expect(crank.turn(degrees: 60).isEmpty, "half a point between notches is silent")
        crank = WindowFrameCrank(value: 10)
        let first = crank.turn(degrees: 120)
        #expect(first == [.notch(11)] && crank.value == 11, "a third of a turn clicks one point")
        #expect(crank.turn(degrees: 5).isEmpty, "staying in a notch does not click again")
        #expect(crank.turn(degrees: -5).isEmpty, "wobbling inside a notch stays silent")
        let back = crank.turn(degrees: -360)
        #expect(back == [.notch(10), .notch(9), .notch(8)] && crank.value == 8, "fast turns click every point passed")
    }

    @Test static func pushingPastTheTopGivesALittleAndSpringsBack() {
        var crank = WindowFrameCrank(value: 12)
        var events = crank.turn(degrees: 120)
        #expect(events == [.notch(13)], "reaching the top clicks 13")
        events = crank.turn(degrees: 90)
        #expect(events == [.end(.thick)] && crank.displayed > 13 && crank.displayed < 13 + WindowFrameCrank.give, "pushing past 13 gives a little")
        #expect(crank.strain > 0, "giving strains")
        #expect(crank.turn(degrees: 400).isEmpty && crank.displayed < 13 + WindowFrameCrank.give, "the give is bounded and fires once")
        events = crank.release()
        #expect(events.isEmpty && crank.value == 13 && crank.displayed == 13 && crank.strain == 0, "letting go springs back to 13")
        #expect(crank.turn(degrees: 60) == [.end(.thick)], "pushing again gives again")
    }

    @Test static func pushingBelowTheBottomGivesAndSettles() {
        var crank = WindowFrameCrank(value: 3)
        #expect(crank.turn(degrees: -90) == [.end(.thin)] && crank.displayed < 3, "pushing below 3 gives")
        crank.release()
        #expect(crank.value == 3, "settles at 3")
    }

    @Test static func letGoBetweenNotchesSettlesOnTheNearestAndKeysStepOnePoint() {
        var crank = WindowFrameCrank(value: 10)
        _ = crank.turn(degrees: 70)
        #expect(crank.release() == [.notch(11)] && crank.value == 11, "letting go between notches settles and clicks the nearest")
        #expect(crank.step(points: 1) == [.notch(12)] && crank.value == 12, "a key moves one point")
        #expect(crank.step(points: 5) == [.notch(13), .end(.thick)] && crank.value == 13, "keys stop at the end and report it")
        #expect(crank.initialValue == 10, "remembers the value to restore")
    }

    @Test static func scrollAndDragTurnTheCrank() {
        #expect(near(WindowFrameCrank.scrollDegrees(deltaY: 10, precise: true), 15), "trackpad scroll turns gently")
        #expect(near(WindowFrameCrank.scrollDegrees(deltaY: -1, precise: false), -40), "a wheel line turns a third of a point")
        let hub = CGPoint(x: 100, y: 100)
        #expect(near(WindowFrameCrank.dragDegrees(from: CGPoint(x: 100, y: 150), to: CGPoint(x: 150, y: 100), around: hub), 90),
              "dragging clockwise winds open")
        #expect(near(WindowFrameCrank.dragDegrees(from: CGPoint(x: 50, y: 100.1), to: CGPoint(x: 50, y: 99.9), around: hub), -0.229, 0.01),
              "crossing the seam behind the hub does not jump a turn")
    }

    @Test static func theCrankPlacementFitsEveryWindowSize() {
        typealias P = WindowFrameCrankPlacement
        let window = CGRect(x: 0, y: 0, width: 1200, height: 760)
        #expect(P.hub(in: window, dockedSidebarEdge: nil) == CGPoint(x: 125, y: 125), "hidden sidebar sits 125 in")
        #expect(P.hub(in: window, dockedSidebarEdge: 240) == CGPoint(x: 240, y: 125), "docked sidebar sits on the seam")
        #expect(P.hub(in: window, dockedSidebarEdge: 90) == CGPoint(x: 125, y: 125), "a narrow sidebar never pushes it off the edge")
        for edge in [nil, CGFloat(180), 240, 400] as [CGFloat?] {
            for size in [CGSize(width: 800, height: 500), CGSize(width: 1512, height: 982), CGSize(width: 3024, height: 1964)] {
                let bounds = CGRect(origin: .zero, size: size)
                #expect(P.fits(hub: P.hub(in: bounds, dockedSidebarEdge: edge), in: bounds), "the swing and lights fit \(size) with sidebar edge \(String(describing: edge))")
            }
        }
        #expect(P.extent >= P.lightsRadius && P.lightsRadius > P.swingRadius && P.hubInset > P.extent, "the lights clear the knob and the edge")
        let tiny = CGRect(x: 0, y: 0, width: 200, height: 180)
        #expect(P.hub(in: tiny, dockedSidebarEdge: nil) == CGPoint(x: 100, y: 90), "a tiny window centres the crank")
    }
}
