import AppKit
import Testing
@testable import ParcCore
@testable import ParcEasels
@testable import ParcNotes

@MainActor
struct EaselOpenInPeekTests {
    private func png() throws -> Data {
        try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)?
            .representation(using: .png, properties: [:]))
    }

    private func menuRow(for kind: EaselItemKind, livePeek: Bool) throws -> (EaselMenuRow?, [URL], [URL]) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-open-in-peek-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try EaselStore(directory: directory).create()
        let asset = kind == .webCard ? try session.importPNG(try png()) : nil
        let item = EaselItem(kind: kind, frame: .init(x: 0, y: 0, width: 300, height: 200), url: "https://example.org/page", assetID: asset)
        try session.perform("Seed") { $0.items = [item] }
        let canvas = makeTestEaselCanvas(session: session)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        var peeked: [URL] = [], tabbed: [URL] = []
        if livePeek { canvas.onOpenLivePage = { peeked.append($0) } }
        canvas.onOpenURL = { tabbed.append($0) }
        let rows = EaselMenuRow.flattened(canvas.contextMenuSections(EaselMenuContext(target: .object, items: [item], point: .init(x: 1, y: 1))))
        let row = rows.first { $0.id == "open-source" }
        row?.perform?()
        return (row, peeked, tabbed)
    }

    @Test(arguments: [EaselItemKind.webCard, .browser])
    func aWebpageCardOpensInPeekWithThePeekIcon(_ kind: EaselItemKind) throws {
        let (row, peeked, tabbed) = try menuRow(for: kind, livePeek: true)
        #expect(row?.title == "Open in Peek")
        #expect(row?.icon == .peek)
        #expect(peeked == [URL(string: "https://example.org/page")!] && tabbed.isEmpty)
    }

    @Test func withoutPeekTheSourceStillOpensInATab() throws {
        let (row, peeked, tabbed) = try menuRow(for: .webCard, livePeek: false)
        #expect(row?.title == "Open Source")
        #expect(peeked.isEmpty && tabbed == [URL(string: "https://example.org/page")!])
    }

    @Test func thePeekIconIsParcsOwnTemplateArtwork() throws {
        let image = try #require(NoteIconRenderer.peekImage(pointSize: 14, bundle: .module))
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 16, height: 16))
        #expect(NoteIconRenderer.peekImage(pointSize: 14, bundle: Bundle(for: NSObject.self)) == nil)
    }
}
