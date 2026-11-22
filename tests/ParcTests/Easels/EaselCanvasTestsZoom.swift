import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct EaselCanvasTestsZoom {
    @MainActor private final class ExtentReentry: NSObject {
        let canvas: EaselCanvasView
        let scroll: NSScrollView
        var depth = 0, deepest = 0
        init(canvas: EaselCanvasView, scroll: NSScrollView) { self.canvas = canvas; self.scroll = scroll }
        @objc func boundsChanged(_ notification: Notification) {
            depth += 1; deepest = max(deepest, depth); defer { depth -= 1 }
            guard depth < 40 else { return }
            canvas.resizeCanvas(viewport: scroll.contentSize)
        }
    }

    struct GuideSpeed: CustomTestStringConvertible {
        let testDescription: String
        let scale: CGFloat
        let speed: Double
        let expectedX: Double
    }

    @MainActor @Test(arguments: [
        GuideSpeed(testDescription: "Half zoom at 200 points per second", scale: 0.5, speed: 200, expectedX: 198),
        GuideSpeed(testDescription: "Double zoom at 100 points per second", scale: 2, speed: 100, expectedX: 200),
    ])
    func magnifiedGuidesMeasureScreenVelocityOnce(_ speed: GuideSpeed) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-guide-scale-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let moving = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 50, height: 50))
        let target = EaselItem(kind: .rectangle, frame: .init(x: 200, y: 170, width: 100, height: 50))
        let canvas = makeTestEaselCanvas(session: session)
        canvas.fixedCanvasSize = .init(width: 800, height: 800)
        canvas.setFrameSize(.init(width: 800, height: 800))
        _ = NSApplication.shared
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 800, height: 600))
        scroll.documentView = canvas; scroll.allowsMagnification = true
        scroll.minMagnification = 0.25; scroll.maxMagnification = 4; window.contentView = scroll
        defer { window.contentView = nil; window.close() }
        try session.perform("Seed magnified guides") { $0.items = [moving, target] }
        scroll.magnification = speed.scale; scroll.contentView.scroll(to: .zero)
        let from = canvas.convert(NSPoint(x: 125, y: 125), to: nil)
        let to = canvas.convert(NSPoint(x: 223, y: 125), to: nil)
        let elapsed = abs(to.x - from.x) / speed.speed
        func event(_ type: NSEvent.EventType, _ point: NSPoint, _ time: Double) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: time,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: event(.leftMouseDown, from, 1))
        canvas.mouseDragged(with: event(.leftMouseDragged, to, 1 + elapsed))
        canvas.mouseUp(with: event(.leftMouseUp, to, 1 + elapsed))
        #expect(abs(session.document.items[0].frame.x - speed.expectedX) < 0.000001,
               "Guide admission measures screen velocity exactly once at non-unit magnification")
    }

    @MainActor @Test(arguments: [CGFloat(0.4), 0.75, 1.5])
    func theCanvasExtentSettlesAfterAMagnificationChange(_ magnification: CGFloat) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-zoomed-extent-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        try session.perform("Seed zoomed extent") { $0.items = [EaselItem(kind: .rectangle, frame: .init(x: 60, y: 60, width: 700, height: 300))] }
        let canvas = makeTestEaselCanvas(session: session)
        let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 1213, height: 731))
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        scroll.allowsMagnification = true; scroll.minMagnification = 0.3333; scroll.maxMagnification = 4
        scroll.documentView = canvas
        canvas.resizeCanvas(viewport: scroll.contentSize)
        scroll.contentView.postsBoundsChangedNotifications = true
        let probe = ExtentReentry(canvas: canvas, scroll: scroll)
        NotificationCenter.default.addObserver(probe, selector: #selector(ExtentReentry.boundsChanged(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        defer { NotificationCenter.default.removeObserver(probe) }
        scroll.setMagnification(magnification, centeredAt: NSPoint(x: 500, y: 400))
        #expect(probe.deepest <= 2, "Resizing the canvas from a zoomed clip view's bounds settles instead of feeding its own scroll")
        let clip = scroll.contentView.bounds.size
        #expect(canvas.frame.width >= clip.width - CGFloat(EaselZoom.extentTolerance) && canvas.frame.height >= clip.height - CGFloat(EaselZoom.extentTolerance),
               "The settled canvas still covers the zoomed viewport")
    }

    @MainActor @Test
    func theCanvasExtentStaysSettledAcrossALongZoomSequence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-zoomed-sweep-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        try session.perform("Seed zoomed extent") { $0.items = [EaselItem(kind: .rectangle, frame: .init(x: 60, y: 60, width: 700, height: 300))] }
        let canvas = makeTestEaselCanvas(session: session)
        let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 1213, height: 731))
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        scroll.allowsMagnification = true; scroll.minMagnification = 0.3333; scroll.maxMagnification = 4
        scroll.documentView = canvas
        canvas.resizeCanvas(viewport: scroll.contentSize)
        scroll.contentView.postsBoundsChangedNotifications = true
        let probe = ExtentReentry(canvas: canvas, scroll: scroll)
        NotificationCenter.default.addObserver(probe, selector: #selector(ExtentReentry.boundsChanged(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        defer { NotificationCenter.default.removeObserver(probe) }
        for step in 1...3000 {
            let spread = (Double(step) * 0.6180339887).truncatingRemainder(dividingBy: 1)
            let magnification = CGFloat(0.3333 * pow(12.0, spread))
            let centre = NSPoint(x: (Double(step) * 0.7548776662).truncatingRemainder(dividingBy: 1) * 2400,
                                 y: (Double(step) * 0.5698402910).truncatingRemainder(dividingBy: 1) * 2400)
            scroll.setMagnification(magnification, centeredAt: centre)
        }
        #expect(probe.deepest <= 2, "Resizing the canvas from a zoomed clip view's bounds settles instead of feeding its own scroll")
        let clip = scroll.contentView.bounds.size
        #expect(canvas.frame.width >= clip.width - CGFloat(EaselZoom.extentTolerance) && canvas.frame.height >= clip.height - CGFloat(EaselZoom.extentTolerance),
               "The settled canvas still covers the zoomed viewport")
    }

    @MainActor @Test(arguments: [EaselTableHover.columnBorder(3), .rowBorder(2)])
    func aShrunkTableDrawsWithAStaleHover(_ hover: EaselTableHover) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-stale-table-hover-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        var wide = EaselItem(kind: .table, frame: .init(x: 40, y: 40, width: 500, height: 144))
        wide.table = EaselTable(columnWidths: Array(repeating: 100, count: 5), rowHeights: Array(repeating: 36, count: 4))
        try session.perform("Seed wide table") { $0.items = [wide] }
        let canvas = makeTestEaselCanvas(session: session)
        canvas.setFrameSize(.init(width: 800, height: 600))
        canvas.tableState.hoverTable = wide.id
        canvas.tableState.hover = hover
        try session.perform("Shrink hovered table") { document in
            guard var table = document.items[0].table else { return }
            if case .columnBorder = hover { _ = table.removeColumns(2...4) } else { _ = table.removeRows(1...3) }
            document.items[0].table = table
            document.items[0].frame.width = table.columnWidths.reduce(0, +)
            document.items[0].frame.height = table.rowHeights.reduce(0, +)
        }
        let rep = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        #expect(canvas.tableState.hover == hover, "A table that shrank under a resting hover draws without its stale border")
    }
}
