import AppKit
import Testing
@testable import ParcCore
@testable import ParcEasels

@MainActor
struct EaselLargeBoardViewChangeTests {
    @Test func aZoomRedrawsOnlyTheCardsNearTheScreen() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-large-board-" + UUID().uuidString)
        let session = try EaselStore(directory: directory).create()
        var items = [EaselItem(kind: .browser, frame: .init(x: 40, y: 40, width: 300, height: 200), url: "https://example.org")]
        for row in 0..<20 {
            for column in 0..<20 {
                items.append(EaselItem(kind: .rectangle, frame: .init(x: Double(column) * 300, y: Double(row) * 300, width: 120, height: 80)))
            }
        }
        try session.perform("Seed") { $0.items = items }
        let canvas = makeTestEaselCanvas(session: session)
        canvas.pageObjects = EaselCanvasTestsSupport.PageSurfaces()
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scroll.allowsMagnification = true
        scroll.maxMagnification = 8
        scroll.documentView = canvas
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        defer {
            window.contentView = nil
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }
        canvas.layoutSubtreeIfNeeded()
        canvas.invalidateIncrementalDisplay()

        let artworks = canvas.subviews.compactMap { $0 as? EaselCanvasArtwork }
        for artwork in artworks {
            artwork.drawnScale = 1
            artwork.needsDisplay = false
        }
        scroll.magnification = 2
        canvas.viewChanged()

        let seen = canvas.visibleRect
        let reach = seen.insetBy(dx: -seen.width / 2, dy: -seen.height / 2)
        let near = artworks.filter { $0.frame.intersects(reach) }
        let far = artworks.filter { !$0.frame.intersects(reach) }
        let redrawn = artworks.filter { $0.needsDisplay || $0.drawnScale == 2 }

        #expect(artworks.count >= 400)
        #expect(!near.isEmpty)
        let stale = near.filter { !$0.needsDisplay && $0.drawnScale == 1 }
        #expect(stale.isEmpty, "\(stale.count) near cards left stale; reach \(reach); first \(stale.first.map { "\($0.frame)" } ?? "-")")
        #expect(far.filter { $0.needsDisplay }.isEmpty)
        #expect(far.filter { $0.drawnScale != 1 }.isEmpty)
        #expect(redrawn.count < 60)
    }
}
