import AppKit
import Testing
@testable import ParcCore
@testable import ParcEasels

struct EaselCanvasTestsTeardown {
    @MainActor private final class Watch {
        weak var canvas: EaselCanvasView?
    }

    @MainActor @Test
    func theEraserTrailTimerStopsWhenTheCanvasIsGone() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-eraser-teardown-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let watch = Watch()
        let timer = autoreleasepool { () -> Timer? in
            let canvas = makeTestEaselCanvas(session: session)
            watch.canvas = canvas
            canvas.beginErasing(at: NSPoint(x: 20, y: 20))
            return canvas.brushes.trailTimer
        }
        guard let timer else { return }
        #expect(watch.canvas == nil, "Closing the Easel releases its canvas while the trail timer is still scheduled")
        timer.fire()
        #expect(!timer.isValid, "A trail timer whose canvas closed stops itself instead of ticking forever")
    }
}
