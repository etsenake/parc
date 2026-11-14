import CoreGraphics
import Foundation

@main struct WindowFrameModelTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("WindowFrame: \(message)") }
    }
    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.0001) -> Bool { abs(a - b) < tolerance }

    static func main() {
        typealias T = WindowFrameThickness
        check(T.range == 3...13 && T.standard == 10, "range and default")
        check(T.clamped(1) == 3 && T.clamped(20) == 13 && T.clamped(7) == 7, "clamping")
        check(T.label(10) == "10 · Classic" && T.label(3) == "3 · Hairline" && T.label(13) == "13 · Gallery", "labels")
        check(T.spokenValue(10) == "10 points, Classic", "spoken value")
        check(T.range.allSatisfy { !T.name($0).isEmpty }, "every point has a name")
        check(T.cornerRadius(for: 10) == 6, "today's corner at the default")
        check(T.cornerRadius(for: 3) == 12 && T.cornerRadius(for: 13) == 4, "corners stay concentric and bounded")
        check(T.cornerRadius(for: 4) > T.cornerRadius(for: 12), "a thinner frame rounds the page more")
        check(!T.showsSplitGrip(5) && T.showsSplitGrip(6) && T.showsSplitGrip(10), "grip hides below six points")
        check(near(T.notchPitch(8), 1) && near(T.notchPitch(9) / T.notchPitch(8), pow(2, 1.0 / 12)), "a semitone per point")
        check(T.notchPitch(13) > T.notchPitch(3), "clicks rise as the frame opens")

        var crank = WindowFrameCrank(value: 10)
        check(crank.value == 10 && crank.litCount == 8 && near(crank.armDegrees, 90 - 7 * 120), "starts at the saved value")
        check(crank.turn(degrees: 60).isEmpty, "half a point between notches is silent")
        crank = WindowFrameCrank(value: 10)
        let first = crank.turn(degrees: 120)
        check(first == [.notch(11)] && crank.value == 11, "a third of a turn clicks one point")
        check(crank.turn(degrees: 5).isEmpty, "staying in a notch does not click again")
        check(crank.turn(degrees: -5).isEmpty, "wobbling inside a notch stays silent")
        let back = crank.turn(degrees: -360)
        check(back == [.notch(10), .notch(9), .notch(8)] && crank.value == 8, "fast turns click every point passed")

        crank = WindowFrameCrank(value: 12)
        var events = crank.turn(degrees: 120)
        check(events == [.notch(13)], "reaching the top clicks 13")
        events = crank.turn(degrees: 90)
        check(events == [.end(.thick)] && crank.displayed > 13 && crank.displayed < 13 + WindowFrameCrank.give, "pushing past 13 gives a little")
        check(crank.strain > 0, "giving strains")
        check(crank.turn(degrees: 400).isEmpty && crank.displayed < 13 + WindowFrameCrank.give, "the give is bounded and fires once")
        events = crank.release()
        check(events.isEmpty && crank.value == 13 && crank.displayed == 13 && crank.strain == 0, "letting go springs back to 13")
        check(crank.turn(degrees: 60) == [.end(.thick)], "pushing again gives again")

        crank = WindowFrameCrank(value: 3)
        check(crank.turn(degrees: -90) == [.end(.thin)] && crank.displayed < 3, "pushing below 3 gives")
        crank.release()
        check(crank.value == 3, "settles at 3")

        crank = WindowFrameCrank(value: 10)
        _ = crank.turn(degrees: 70)
        check(crank.release() == [.notch(11)] && crank.value == 11, "letting go between notches settles and clicks the nearest")
        check(crank.step(points: 1) == [.notch(12)] && crank.value == 12, "a key moves one point")
        check(crank.step(points: 5) == [.notch(13), .end(.thick)] && crank.value == 13, "keys stop at the end and report it")
        check(crank.initialValue == 10, "remembers the value to restore")

        check(near(WindowFrameCrank.scrollDegrees(deltaY: 10, precise: true), 15), "trackpad scroll turns gently")
        check(near(WindowFrameCrank.scrollDegrees(deltaY: -1, precise: false), -40), "a wheel line turns a third of a point")
        let hub = CGPoint(x: 100, y: 100)
        check(near(WindowFrameCrank.dragDegrees(from: CGPoint(x: 100, y: 150), to: CGPoint(x: 150, y: 100), around: hub), 90),
              "dragging clockwise winds open")
        check(near(WindowFrameCrank.dragDegrees(from: CGPoint(x: 50, y: 100.1), to: CGPoint(x: 50, y: 99.9), around: hub), -0.229, 0.01),
              "crossing the seam behind the hub does not jump a turn")

        typealias P = WindowFrameCrankPlacement
        let window = CGRect(x: 0, y: 0, width: 1200, height: 760)
        check(P.hub(in: window, dockedSidebarEdge: nil) == CGPoint(x: 125, y: 125), "hidden sidebar sits 125 in")
        check(P.hub(in: window, dockedSidebarEdge: 240) == CGPoint(x: 240, y: 125), "docked sidebar sits on the seam")
        check(P.hub(in: window, dockedSidebarEdge: 90) == CGPoint(x: 125, y: 125), "a narrow sidebar never pushes it off the edge")
        for edge in [nil, CGFloat(180), 240, 400] as [CGFloat?] {
            for size in [CGSize(width: 800, height: 500), CGSize(width: 1512, height: 982), CGSize(width: 3024, height: 1964)] {
                let bounds = CGRect(origin: .zero, size: size)
                check(P.fits(hub: P.hub(in: bounds, dockedSidebarEdge: edge), in: bounds), "the swing and lights fit \(size) with sidebar edge \(String(describing: edge))")
            }
        }
        check(P.extent >= P.lightsRadius && P.lightsRadius > P.swingRadius && P.hubInset > P.extent, "the lights clear the knob and the edge")
        let tiny = CGRect(x: 0, y: 0, width: 200, height: 180)
        check(P.hub(in: tiny, dockedSidebarEdge: nil) == CGPoint(x: 100, y: 90), "a tiny window centres the crank")
        print("WindowFrame model: \(count) checks passed")
    }
}
