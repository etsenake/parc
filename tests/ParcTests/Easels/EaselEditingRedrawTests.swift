import AppKit
import Testing
@testable import ParcCore
@testable import ParcEasels

@MainActor
struct EaselEditingRedrawTests {
    @MainActor
    private final class Board {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-editing-redraw-" + UUID().uuidString)
        let session: EaselSession
        let canvas: EaselCanvasView
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
        let surfaces = EaselCanvasTestsSupport.PageSurfaces()
        let table: UUID, image: UUID, card: UUID

        init() throws {
            _ = NSApplication.shared
            session = try EaselStore(directory: directory).create()
            let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
            let asset = try session.importPNG(png)
            let page = EaselItem(kind: .browser, frame: .init(x: 40, y: 40, width: 300, height: 200), url: "https://example.org")
            let tableItem = EaselTableGeometry.item(columns: 2, rows: 2, frame: .init(x: 400, y: 40, width: 240, height: 80), zIndex: 1)
            let imageItem = EaselItem(kind: .image, frame: .init(x: 400, y: 300, width: 200, height: 100), assetID: asset)
            let cardItem = EaselItem(kind: .rectangle, frame: .init(x: 40, y: 400, width: 200, height: 120))
            table = tableItem.id; image = imageItem.id; card = cardItem.id
            try session.perform("Seed") { $0.items = [page, tableItem, imageItem, cardItem] }
            canvas = makeTestEaselCanvas(session: session)
            canvas.pageObjects = surfaces
            scroll.documentView = canvas
            window.isReleasedWhenClosed = false
            window.contentView = scroll
            canvas.layoutSubtreeIfNeeded()
            canvas.invalidateIncrementalDisplay()
        }

        func view(_ id: UUID) -> EaselCanvasArtwork? {
            canvas.subviews.lazy.compactMap { $0 as? EaselCanvasArtwork }.first { $0.id == id }
        }

        func settle() {
            canvas.layoutSubtreeIfNeeded()
            canvas.invalidateIncrementalDisplay()
            for view in canvas.subviews.compactMap({ $0 as? EaselCanvasArtwork }) { view.needsDisplay = false }
            canvas.decoration.needsDisplay = false
        }

        func close() {
            window.contentView = nil
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test func editingATableCellRedrawsThatTablesView() throws {
        let board = try Board()
        defer { board.close() }
        #expect(board.canvas.usesObjectSurfaces)
        let item = try #require(board.session.document.items.first { $0.id == board.table })
        board.settle()
        board.canvas.beginEditingTableCell(item, cell: EaselTableCoordinate(row: 0, column: 1))
        #expect(board.canvas.isEditingTableCell)
        #expect(board.view(board.table)?.needsDisplay == true)
        #expect(board.view(board.card)?.needsDisplay == false)
    }

    @Test func tableChromeAndPlacementRedrawOnlyTheOverlay() throws {
        let board = try Board()
        defer { board.close() }
        board.settle()
        board.canvas.invalidateTableChrome(board.table)
        #expect(board.canvas.decoration.needsDisplay)
        #expect(board.view(board.table)?.needsDisplay == false)
        board.settle()
        board.canvas.tablePlacementMoved(from: NSPoint(x: 60, y: 420), to: NSPoint(x: 220, y: 500))
        #expect(board.canvas.decoration.needsDisplay)
        #expect(board.view(board.card)?.needsDisplay == false)
        board.canvas.cancelTablePlacement()
    }

    @Test func aBrushStrokeInProgressRedrawsTheOverlayAndNotTheObjectsBeneathIt() throws {
        let board = try Board()
        defer { board.close() }
        board.settle()
        board.canvas.beginBrushStroke(.marker, at: NSPoint(x: 60, y: 420), flags: [])
        #expect(board.canvas.decoration.needsDisplay)
        board.canvas.decoration.needsDisplay = false
        board.canvas.dragBrushStroke(to: NSPoint(x: 200, y: 480), flags: [])
        #expect(board.canvas.decoration.needsDisplay)
        #expect(board.view(board.card)?.needsDisplay == false)
        board.canvas.cancelBrushStroke()
    }

    @Test func aCropEditRedrawsItsImagesView() throws {
        let board = try Board()
        defer { board.close() }
        board.canvas.selection = [board.image]
        board.settle()
        #expect(board.canvas.beginImageCrop())
        #expect(board.view(board.image)?.needsDisplay == true)
        board.settle()
        board.canvas.setCropZoom(2)
        #expect(board.canvas.decoration.needsDisplay)
        #expect(board.view(board.card)?.needsDisplay == false)
        board.canvas.finishImageCrop(save: true)
        #expect(board.session.document.items.first { $0.id == board.image }?.crop != nil)
        #expect(board.view(board.image)?.needsDisplay == true)
    }
}
