import Foundation

@main
struct EaselFloatingBarTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

    static func main() {
        barFrame()
        coverage()
        fitting()
        chip()
        flourishes()
        print("EaselFloatingBarTests passed")
    }

    static func barFrame() {
        let bar = EaselFloatingBar.frame(containerWidth: 1000, containerHeight: 700, preferredWidth: 600, height: 36, top: 72)
        expect(bar == EaselRect(x: 200, y: 648, width: 600, height: 36), "the bar is centred and floats 16 points above the bottom")
        let narrow = EaselFloatingBar.frame(containerWidth: 400, containerHeight: 700, preferredWidth: 600, height: 36, top: 72)
        expect(narrow.width == 376 && narrow.x == 12, "a narrow window clamps the bar inside 12-point side margins")
        let short = EaselFloatingBar.frame(containerWidth: 1000, containerHeight: 100, preferredWidth: 600, height: 36, top: 72)
        expect(short.y == 72, "a very short window keeps the bar under the title row")
        let broken = EaselFloatingBar.frame(containerWidth: .nan, containerHeight: 700, preferredWidth: 600, height: 36, top: 72)
        expect(broken.width == 0, "invalid sizes give an empty bar instead of a garbage frame")
        let tiny = EaselFloatingBar.frame(containerWidth: 10, containerHeight: 700, preferredWidth: 600, height: 36, top: 72)
        expect(tiny.width == 0, "a window narrower than the margins gives the bar no width")
    }

    static func coverage() {
        let bar = EaselRect(x: 200, y: 648, width: 600, height: 36)
        expect(EaselFloatingBar.coveredBottom(containerHeight: 700, bar: bar) == 60, "the covered band runs from the bar's top plus clearance to the bottom")
        expect(EaselFloatingBar.coveredBottom(containerHeight: 700, bar: EaselRect(x: 0, y: 0, width: 0, height: 0)) == 0,
               "an empty bar covers nothing")
        expect(EaselFloatingBar.cover(60, viewportHeight: 100) == 50, "the bar never claims more than half of a tiny viewport")
        expect(EaselFloatingBar.cover(-5, viewportHeight: 600) == 0, "negative cover is ignored")
        let visible = EaselRect(x: 100, y: 200, width: 400, height: 300)
        let shown = EaselFloatingBar.uncovered(visible, coveredBottom: 60, magnification: 2)
        expect(shown == EaselRect(x: 100, y: 200, width: 400, height: 270), "zoomed in, the covered band shrinks in document points")
        let zoomedOut = EaselFloatingBar.uncovered(visible, coveredBottom: 60, magnification: 0.5)
        expect(near(zoomedOut.height, 180), "zoomed out, the covered band grows in document points")
        expect(EaselFloatingBar.uncovered(visible, coveredBottom: 60, magnification: 0) == visible, "invalid zoom leaves the view whole")
        expect(EaselFloatingBar.uncovered(visible, coveredBottom: 0, magnification: 1) == visible, "no bar leaves the view whole")
    }

    static func fitting() {
        let room = EaselFloatingBar.viewport(width: 800, height: 600, coveredBottom: 60)
        expect(room.width == 800 && room.height == 540, "fitting uses the viewport above the bar")
        let centre = EaselFloatingBar.clipCentre(showing: EaselPoint(x: 500, y: 400), coveredBottom: 60, viewportHeight: 600, magnification: 1)
        expect(centre == EaselPoint(x: 500, y: 430), "the clip centre drops by half the cover so content centres above the bar")
        let zoomed = EaselFloatingBar.clipCentre(showing: EaselPoint(x: 500, y: 400), coveredBottom: 60, viewportHeight: 600, magnification: 2)
        expect(near(zoomed.y, 415), "the centre shift scales with zoom")
        let content = EaselRect(x: 0, y: 0, width: 400, height: 1000)
        let plain = EaselZoom.fitting(content, viewport: (800, 600), minimum: 0.25, maximum: 4) ?? 0
        let covered = EaselZoom.fitting(content, viewport: room, minimum: 0.25, maximum: 4) ?? 0
        expect(covered < plain, "Zoom to fit leaves room for the bar")
        let visibleTop = 430.0 - 300, visibleBottom = 430.0 + 300 - 60
        expect(near((visibleTop + visibleBottom) / 2, 400), "the uncovered area is centred on the content")
    }

    static func chip() {
        let bar = EaselRect(x: 200, y: 648, width: 600, height: 36)
        let chip = EaselFloatingBar.chipFrame(width: 120, height: 28, containerWidth: 1000, bar: bar, top: 64)
        expect(chip == EaselRect(x: 440, y: 610, width: 120, height: 28), "the Recenter chip floats 10 points above the bar")
        let cramped = EaselFloatingBar.chipFrame(width: 120, height: 28, containerWidth: 1000, bar: EaselRect(x: 0, y: 70, width: 10, height: 36), top: 64)
        expect(cramped.y == 64, "the chip never rises above the canvas top")
        let pill = EaselFloatingBar.pillFrame(button: EaselRect(x: 40, y: 4, width: 28, height: 28), inset: 1)
        expect(pill == EaselRect(x: 41, y: 5, width: 26, height: 26), "the current-tool pill hugs its button")
    }

    static func flourishes() {
        expect(EaselToolFlourish.flourish(for: .select) == nil, "Select has no flourish")
        expect(EaselToolFlourish.flourish(for: .sticky) == .hop, "the sticky hops")
        expect(EaselToolFlourish.flourish(for: .marker) == .tilt && EaselToolFlourish.flourish(for: .highlighter) == .tilt,
               "the marker and highlighter tilt")
        expect(EaselToolFlourish.flourish(for: .eraser) == .wiggle, "the eraser wiggles")
        expect(EaselToolFlourish.flourish(for: .stamp) == .thump, "the stamp thumps")
        expect(EaselToolFlourish.flourish(for: .hand) == .open, "the hand opens")
        for tool in [EaselTool.rectangle, .ellipse, .elbowConnector, .curvedConnector, .straightConnector] {
            expect(EaselToolFlourish.flourish(for: tool) == .pop, "\(tool) pops")
        }
        let all: [EaselToolFlourish] = [.hop, .tilt, .wiggle, .thump, .pop, .open]
        for flourish in all {
            let frames = flourish.frames()
            expect(frames.first?.isRest == true && frames.last?.isRest == true, "\(flourish) starts and ends at rest")
            expect(frames.contains { !$0.isRest }, "\(flourish) moves")
            expect(flourish.duration >= 0.3 && flourish.duration <= 0.45, "\(flourish) settles quickly")
            expect(flourish.frame(at: -1).isRest && flourish.frame(at: flourish.duration + 1).isRest, "\(flourish) rests outside its run")
            let biggestStep = zip(frames, frames.dropFirst()).map { a, b in
                max(abs(a.dx - b.dx), abs(a.dy - b.dy), abs(a.rotation - b.rotation) / 10, abs(a.scaleX - b.scaleX) * 20, abs(a.scaleY - b.scaleY) * 20)
            }.max() ?? 0
            expect(biggestStep < 2.5, "\(flourish) moves smoothly between frames, never jumping")
        }
        let hop = EaselToolFlourish.hop.frames()
        expect(near(hop.map(\.dy).min() ?? 0, -4, 0.15), "the sticky hops about 4 points up")
        let thump = EaselToolFlourish.thump.frames()
        let firstMove = thump.first { !$0.isRest }
        expect((firstMove?.scaleY ?? 1) < 1 && thump.contains { $0.scaleY > 1 }, "the stamp squashes first, then pops")
        let wiggle = EaselToolFlourish.wiggle.frames().map(\.rotation).filter { abs($0) > 0.5 }
        let swings = zip(wiggle, wiggle.dropFirst()).filter { ($0 > 0) != ($1 > 0) }.count
        expect(swings >= 2, "the eraser wiggles back and forth")
        expect(near(EaselToolFlourish.kick(at: 0, response: 0.3, damping: 0.5), 0), "a kick starts at rest")
        let peak = (1...400).map { EaselToolFlourish.kick(at: Double($0) / 1000, response: 0.3, damping: 0.5) }.max() ?? 0
        expect(near(peak, 1, 0.01), "a kick peaks at its full amplitude")
        expect(EaselToolFlourish.kick(at: 0.1, response: 0.3, damping: 1.2) == 0, "overdamped kicks are ignored")
    }
}
