import AppKit
import Testing
@testable import ParcCore
@testable import ParcEasels

struct EaselFullPageLiveTests {
    private typealias PageSurfaces = EaselCanvasTestsSupport.PageSurfaces

    @MainActor
    private final class Board {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-full-page-live-" + UUID().uuidString)
        let session: EaselSession
        let canvas: EaselCanvasView
        let window: NSWindow
        let surfaces = PageSurfaces()
        let id: UUID

        init(layout: EaselCaptureLayout, frame: EaselRect, live: Bool?) throws {
            _ = NSApplication.shared
            session = try EaselStore(directory: directory).create()
            let asset = try session.importPNG(try #require(Self.png(width: 40, height: 300)))
            let card = EaselItem(kind: .webCard, frame: frame, url: "https://example.org/long", assetID: asset,
                                 capturedAt: Date(timeIntervalSince1970: 42), captureLayout: layout, liveCapture: live)
            id = card.id
            try session.perform("Seed") { $0.items = [card] }
            canvas = makeTestEaselCanvas(session: session)
            surfaces.approved = true
            canvas.pageObjects = surfaces
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = canvas
        }

        static func png(width: Int, height: Int) -> Data? {
            NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)?
                .representation(using: .png, properties: [:])
        }

        var card: EaselItem? { session.document.items.first { $0.id == id } }

        func settle() {
            let approve = surfaces.pending
            surfaces.pending = nil
            approve?()
        }

        func close() {
            window.contentView = nil
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }
    }

    static let fullPage = EaselCaptureGeometry.captured(viewport: .init(x: 1280, y: 800), scroll: .init(x: 0, y: 0),
        region: .init(x: 0, y: 0, width: 1280, height: 800), scrollContainers: [], fullPage: true)!
    static let region = EaselCaptureLayout(viewport: .init(x: 1000, y: 700), scroll: .init(x: 0, y: 300),
                                           region: .init(x: 20, y: 40, width: 300, height: 200))

    @MainActor @Test
    func backToSnapshotRestoresTheTallCardAtTheLiveWidthInOneUndoStep() throws {
        let board = try Board(layout: Self.fullPage, frame: .init(x: 40, y: 60, width: 200, height: 125), live: true)
        defer { board.close() }
        board.canvas.setLiveCapture(board.id, enabled: false)
        board.settle()
        #expect(board.card?.liveCapture == false)
        #expect(board.card?.frame == EaselRect(x: 40, y: 60, width: 200, height: 1500))
        board.canvas.undo(nil)
        board.settle()
        #expect(board.card?.liveCapture == true)
        #expect(board.card?.frame == EaselRect(x: 40, y: 60, width: 200, height: 125))
        board.canvas.redo(nil)
        board.settle()
        #expect(board.card?.liveCapture == false)
        #expect(board.card?.frame == EaselRect(x: 40, y: 60, width: 200, height: 1500))
    }

    @MainActor @Test
    func aRefusedCloseKeepsTheLiveWindowAndItsShape() throws {
        let board = try Board(layout: Self.fullPage, frame: .init(x: 40, y: 60, width: 200, height: 125), live: true)
        defer { board.close() }
        board.surfaces.approved = false
        board.canvas.setLiveCapture(board.id, enabled: false)
        board.settle()
        #expect(board.card?.liveCapture == true)
        #expect(board.card?.frame == EaselRect(x: 40, y: 60, width: 200, height: 125))
    }

    @MainActor @Test
    func regionCapturesKeepTheirFrameWhenTheyGoBackToTheSnapshot() throws {
        let frame = EaselRect(x: 40, y: 60, width: 300, height: 200)
        let board = try Board(layout: Self.region, frame: frame, live: true)
        defer { board.close() }
        board.canvas.setLiveCapture(board.id, enabled: false)
        board.settle()
        #expect(board.card?.liveCapture == false)
        #expect(board.card?.frame == frame)
    }
}
