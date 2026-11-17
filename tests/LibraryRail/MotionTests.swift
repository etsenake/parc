import AppKit
import QuartzCore

@main
struct LibraryRailMotionTests {
    @MainActor static func main() { exitOnFailure(run) }

    @MainActor static func run() {
        var count = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); count += 1
        }
        func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }

        let library = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/Library").standardizedFileURL
        for name in ["screenshots", "downloads", "easels", "spaces", "archive"] {
            let data = try? Data(contentsOf: library.appendingPathComponent(name + ".json"))
            guard let data, let animation = LibraryRailAnimation(data: data),
                  let from = animation.frame(forMarker: "hover-start"), let windup = animation.frame(forMarker: "hover-end"),
                  let end = animation.frame(forMarker: "selection-end") else { preconditionFailure("\(name) loads with its markers") }
            let duration = LibraryRailMotion.playbackDuration(from: from, to: end, frameRate: animation.frameRate)
            let native = (end - from) / animation.frameRate
            expect(duration >= 0.9 && duration <= 1 && duration >= native * 1.6,
                   "\(name) hops over a little under a second, well behind the composition's own \(native) seconds")
            expect(LibraryRailMotion.playbackDuration(from: from, to: windup, frameRate: animation.frameRate) >= 0.25,
                   "\(name) winds up for at least a quarter second before it launches")
            expect(LibraryRailMotion.playbackFrame(from: from, to: end, frameRate: animation.frameRate, elapsed: 0) == from
                   && LibraryRailMotion.playbackFrame(from: from, to: end, frameRate: animation.frameRate, elapsed: -1) == from,
                   "\(name) starts on hover-start")
            expect(near(LibraryRailMotion.playbackFrame(from: from, to: end, frameRate: animation.frameRate, elapsed: duration / 2), (from + end) / 2),
                   "\(name) is halfway through its frames halfway through its time")
            expect(LibraryRailMotion.playbackFrame(from: from, to: end, frameRate: animation.frameRate, elapsed: duration + 1) == end,
                   "\(name) parks on selection-end")
        }
        expect(near(LibraryRailMotion.playbackFrame(from: 1, to: 35, frameRate: 60, elapsed: 0.375), 14.5),
               "Playback runs at 36 composition frames a second")

        expect(LibraryRailMotion.arrival == 0.34 && LibraryRailMotion.departure == 0.26 && LibraryRailMotion.pageFade == 0.3,
               "Fades take about a third of a second in, a quarter out, and pages fade in over 0.3 seconds")
        expect(LibraryRailMotion.fadeDuration(rising: true) == LibraryRailMotion.arrival
               && LibraryRailMotion.fadeDuration(rising: false) == LibraryRailMotion.departure,
               "Lighting up uses the arrival time and dimming the departure time")

        expect(LibraryRailMotion.eased(0) == 0 && LibraryRailMotion.eased(1) == 1
               && LibraryRailMotion.eased(-0.5) == 0 && LibraryRailMotion.eased(1.5) == 1, "The curve is pinned at both ends")
        var previous = 0.0, monotonic = true
        for step in 1...100 {
            let value = LibraryRailMotion.eased(Double(step) / 100)
            monotonic = monotonic && value >= previous; previous = value
        }
        expect(monotonic, "The curve never reverses")
        expect(LibraryRailMotion.eased(0.5) > 0.6 && LibraryRailMotion.eased(0.5) < 0.9,
               "The curve answers quickly and decelerates into place")
        func controlPoints(_ timing: CAMediaTimingFunction?) -> [Float] {
            guard let timing else { return [] }
            var first = [Float](repeating: 0, count: 2), second = first
            timing.getControlPoint(at: 1, values: &first)
            timing.getControlPoint(at: 2, values: &second)
            return first + second
        }
        expect(controlPoints(LibraryRailMotion.timing) == [0.25, 0.46, 0.45, 0.94], "Core Animation fades follow the same curve as the drawn ink")

        var fade = LibraryRailMotion.Fade(0)
        expect(fade.value(at: 0) == 0 && fade.isSettled(at: 0), "A new fade rests on its value")
        fade.retarget(1, at: 10, animated: true)
        expect(fade.value(at: 10) == 0 && !fade.isSettled(at: 10 + LibraryRailMotion.arrival / 2)
               && fade.value(at: 10 + LibraryRailMotion.arrival / 2) > 0.5 && fade.value(at: 10 + LibraryRailMotion.arrival / 2) < 1,
               "Lighting up starts where the tile is and eases toward full")
        let arrived = 10 + LibraryRailMotion.arrival + 1e-9
        expect(fade.value(at: arrived) == 1 && fade.isSettled(at: arrived),
               "Lighting up settles exactly on full at the arrival time")
        let turn = 10 + LibraryRailMotion.arrival / 3, reached = fade.value(at: turn)
        fade.retarget(0, at: turn, animated: true)
        expect(near(fade.value(at: turn), reached) && fade.value(at: turn + 0.01) < reached,
               "A quick click away turns the fade around from where it is, without a jump")
        fade.retarget(0, at: turn + 0.1, animated: true)
        let departed = turn + LibraryRailMotion.departure + 1e-9
        expect(fade.isSettled(at: departed) && fade.value(at: departed) == 0,
               "Asking for the same target again does not restart the fade")
        fade.retarget(1, at: 20, animated: true)
        fade.retarget(1, at: 20.05, animated: false)
        expect(fade.isSettled(at: 20.05) && fade.value(at: 20.05) == 1, "Settling a running fade jumps it to its target")
        fade.retarget(0, at: 21, animated: false)
        expect(fade.isSettled(at: 21) && fade.value(at: 21) == 0, "Without a window a change applies at once")

        let fill = LibraryRailMotion.fade("backgroundColor", from: CGColor(gray: 0, alpha: 0), duration: LibraryRailMotion.arrival)
        expect(fill.keyPath == "backgroundColor" && fill.fromValue != nil && fill.toValue == nil && fill.duration == LibraryRailMotion.arrival
               && controlPoints(fill.timingFunction) == [0.25, 0.46, 0.45, 0.94],
               "The fill fades from what is on screen to whatever the tile now wants")
        let page = LibraryRailMotion.fade("opacity", from: 0, to: Float(1), duration: LibraryRailMotion.pageFade)
        expect(page.keyPath == "opacity" && (page.fromValue as? Int) == 0 && (page.toValue as? Float) == 1 && page.duration == 0.3,
               "A new page fades up from clear to its own opacity")

        let spring = LibraryRailMotion.pressSpring("bounds", from: NSValue(rect: .zero), to: NSValue(rect: NSRect(x: 2, y: 2, width: 4, height: 4)))
        let ratio = spring.damping / (2 * (spring.stiffness * spring.mass).squareRoot())
        let response = 2 * Double.pi / (spring.stiffness / spring.mass).squareRoot()
        let overshoot = exp(-Double.pi * ratio / (1 - ratio * ratio).squareRoot())
        expect(near(response, LibraryRailMotion.pressResponse, 1e-6) && near(ratio, LibraryRailMotion.pressDamping, 1e-6),
               "The press spring has the rail's response and damping")
        expect(LibraryRailMotion.pressResponse >= 0.25 && overshoot < 0.01 && spring.duration == spring.settlingDuration
               && spring.duration > 0.3 && spring.duration < 1,
               "The press sinks in softly and settles with no visible overshoot")

        print("Library rail motion: \(count) assertions passed")
    }
}
