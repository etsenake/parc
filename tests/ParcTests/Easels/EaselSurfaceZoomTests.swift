import AppKit
import Testing
@testable import ParcCore
@testable import ParcEasels

@MainActor
struct EaselSurfaceZoomTests {
    @MainActor
    private final class Board {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-surface-zoom-" + UUID().uuidString)
        let canvas: EaselCanvasView
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        let surfaces = EaselCanvasTestsSupport.PageSurfaces()
        let near: UUID, far: UUID

        init() throws {
            _ = NSApplication.shared
            let session = try EaselStore(directory: directory).create()
            let page = EaselItem(kind: .browser, frame: .init(x: 40, y: 40, width: 300, height: 200), url: "https://example.org")
            let nearCard = EaselItem(kind: .rectangle, frame: .init(x: 400, y: 40, width: 120, height: 80))
            let farCard = EaselItem(kind: .rectangle, frame: .init(x: 9_000, y: 9_000, width: 120, height: 80))
            near = nearCard.id; far = farCard.id
            try session.perform("Seed") { $0.items = [page, nearCard, farCard] }
            canvas = makeTestEaselCanvas(session: session)
            canvas.pageObjects = surfaces
            scroll.allowsMagnification = true
            scroll.maxMagnification = 8
            scroll.documentView = canvas
            window.isReleasedWhenClosed = false
            window.contentView = scroll
            canvas.layoutSubtreeIfNeeded()
            canvas.invalidateIncrementalDisplay()
        }

        func card(_ id: UUID) -> EaselCanvasArtwork? {
            canvas.subviews.lazy.compactMap { $0 as? EaselCanvasArtwork }.first { $0.id == id }
        }

        func paint(_ id: UUID) throws {
            let view = try #require(card(id))
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            view.needsDisplay = false
        }

        func zoom(to scale: CGFloat) {
            scroll.magnification = scale
            scroll.contentView.scroll(to: NSPoint(x: 300, y: 0))
            canvas.invalidateIncrementalDisplay()
        }

        func close() {
            window.contentView = nil
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test func aCardDrawnAtAnotherZoomIsRedrawnAtTheNewZoom() throws {
        let board = try Board()
        defer { board.close() }
        try board.paint(board.near)
        #expect(board.card(board.near)?.drawnScale == 1)
        board.zoom(to: 3)
        #expect(board.card(board.near)?.needsDisplay == true)
        try board.paint(board.near)
        #expect(board.card(board.near)?.drawnScale == 3)
    }

    @Test func cardsAlreadyAtTheCurrentZoomOrFarOffScreenAreLeftAlone() throws {
        let board = try Board()
        defer { board.close() }
        try board.paint(board.near)
        try board.paint(board.far)
        board.canvas.invalidateIncrementalDisplay()
        #expect(board.card(board.near)?.drawnScale == 1)
        board.zoom(to: 3)
        #expect(board.card(board.far)?.needsDisplay == false)
        #expect(board.card(board.far)?.drawnScale == 1)
    }
}
