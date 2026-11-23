import AppKit
import Testing
@testable import ParcCore
@testable import ParcEasels

struct EaselCanvasTestsEmbeddedRemoval {
    private typealias PageSurfaces = EaselCanvasTestsSupport.PageSurfaces

    @MainActor
    private final class Board {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-embedded-removal-" + UUID().uuidString)
        let session: EaselSession
        let canvas: EaselCanvasView
        let window: NSWindow
        let surfaces = PageSurfaces()
        private(set) var painted = NSRect.null

        init(_ items: [EaselItem], pages: [EaselPage]? = nil) throws {
            _ = NSApplication.shared
            session = try EaselStore(directory: directory).create()
            let asset = try session.importPNG(EaselPagePoolTestsSupport.Board.png)
            let seeded = items.map { item in
                var item = item
                if item.kind == .webCard { item.assetID = asset }
                return item
            }
            try session.perform("Seed") { $0.pages = pages; $0.items = seeded }
            canvas = makeTestEaselCanvas(session: session)
            surfaces.approved = true
            canvas.pageObjects = surfaces
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = canvas
            canvas.wantsLayer = true
            paint()
            canvas.onDrawOverlay = { [weak self] dirty, _ in
                guard let self else { return }
                self.painted = self.painted.union(dirty)
            }
        }

        func paint() {
            canvas.layoutSubtreeIfNeeded()
            canvas.layer?.displayIfNeeded()
        }

        func select(_ ids: Set<UUID>) {
            canvas.selection = ids
            paint()
            painted = .null
        }

        func settle() {
            let approve = surfaces.pending
            surfaces.pending = nil
            approve?()
            paint()
        }

        func repainted(_ item: EaselItem) -> Bool { painted.contains(canvas.rect(item)) }

        var repaintedEverythingVisible: Bool { !canvas.visibleRect.isEmpty && painted.contains(canvas.visibleRect) }

        var hostsSurface: Bool { surfaces.view.superview === canvas }

        func close() {
            canvas.onDrawOverlay = nil
            window.contentView = nil
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static let browser = EaselItem(kind: .browser, frame: .init(x: 40, y: 40, width: 320, height: 220),
                                           url: "https://example.org/original")
    private static let shape = EaselItem(kind: .rectangle, frame: .init(x: 620, y: 440, width: 60, height: 60))
    private static let sticky = EaselItem(kind: .sticky, frame: .init(x: 620, y: 40, width: 120, height: 120), zIndex: 1)

    private static func liveCapture(at frame: EaselRect = .init(x: 40, y: 300, width: 320, height: 220)) -> EaselItem {
        let layout = EaselCaptureLayout(viewport: .init(x: 1000, y: 700), scroll: .init(x: 0, y: 0),
                                        region: .init(x: 20, y: 40, width: 300, height: 200))
        return EaselItem(kind: .webCard, frame: frame, url: "https://example.org/captured",
                         capturedAt: Date(timeIntervalSince1970: 42), captureLayout: layout, liveCapture: true)
    }

    @MainActor @Test(arguments: [false, true])
    func deletingTheLastEmbeddedPageRepaintsTheWholeBoard(_ alongsideOtherObjects: Bool) throws {
        let board = try Board([Self.browser, Self.shape, Self.sticky])
        defer { board.close() }
        #expect(board.hostsSurface)
        board.select(alongsideOtherObjects ? [Self.browser.id, Self.sticky.id] : [Self.browser.id])
        #expect(board.canvas.deleteSelection())
        board.settle()
        #expect(board.session.document.items.map(\.id) == (alongsideOtherObjects ? [Self.shape.id] : [Self.shape.id, Self.sticky.id]))
        #expect(!board.hostsSurface)
        #expect(board.repainted(Self.shape), "Objects far from the deleted page are painted again when the canvas stops hosting pages")
        if !alongsideOtherObjects { #expect(board.repainted(Self.sticky)) }
    }

    @MainActor @Test
    func goingBackToTheSnapshotRepaintsTheWholeBoard() throws {
        let capture = Self.liveCapture()
        let board = try Board([capture, Self.shape])
        defer { board.close() }
        board.select([capture.id])
        board.canvas.setLiveCapture(capture.id, enabled: false)
        board.settle()
        #expect(board.session.document.items.first?.liveCapture == false)
        #expect(board.repainted(Self.shape))
        #expect(board.repainted(capture), "The returned snapshot is painted where the live page was")
    }

    @MainActor @Test
    func redoingTheDeleteRepaintsTheWholeBoard() throws {
        let board = try Board([Self.browser, Self.shape])
        defer { board.close() }
        board.select([Self.browser.id])
        board.canvas.deleteSelection()
        board.settle()
        board.canvas.undo(nil)
        board.settle()
        #expect(board.session.document.items.count == 2 && board.hostsSurface)
        board.select([])
        board.canvas.redo(nil)
        board.settle()
        #expect(board.session.document.items.map(\.id) == [Self.shape.id])
        #expect(board.repainted(Self.shape))
    }

    @MainActor @Test
    func undoingTheDeleteClearsTheSoftwarePaintUnderTheRestoredPage() throws {
        let board = try Board([Self.browser, Self.shape])
        defer { board.close() }
        board.select([Self.browser.id])
        board.canvas.deleteSelection()
        board.settle()
        board.select([])
        let layer = try #require(board.canvas.layer)
        try #require(!layer.needsDisplay())
        board.canvas.undo(nil)
        let approve = board.surfaces.pending
        board.surfaces.pending = nil
        approve?()
        board.canvas.layoutSubtreeIfNeeded()
        #expect(board.hostsSurface)
        #expect(layer.needsDisplay(), "The canvas clears its own painting once the restored page brings object surfaces back")
    }

    @MainActor @Test
    func cuttingALiveCaptureRepaintsTheWholeBoardAndPastesBackLive() throws {
        let capture = Self.liveCapture()
        let board = try Board([capture, Self.shape])
        defer { board.close() }
        let pasteboard = NSPasteboard(name: .init("parc-tests-cut-" + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        #expect(board.canvas.usesObjectSurfaces)
        board.select([capture.id])
        #expect(board.canvas.cutSelection(to: pasteboard))
        board.settle()
        #expect(board.session.document.items.map(\.id) == [Self.shape.id])
        #expect(!board.canvas.usesObjectSurfaces, "With the live page gone the canvas paints its objects itself again")
        #expect(board.canvas.artwork[capture.id] == nil)
        #expect(board.repainted(Self.shape), "Objects far from the cut page are painted again when the canvas stops hosting pages")
        let data = try #require(pasteboard.data(forType: EaselCanvasView.objectsPasteboardType))
        let payload = try EaselClipboardPayload.decoded(data)
        #expect(payload.items.map(\.id) == [capture.id] && payload.items.first?.liveCapture == true)
        board.select([])
        #expect(board.canvas.pasteObjects(from: pasteboard, at: nil) == true)
        board.settle()
        let restored = try #require(board.session.document.items.first { $0.kind == .webCard })
        #expect(restored.liveCapture == true && restored.ownsEmbeddedPage)
        #expect(board.canvas.usesObjectSurfaces, "The pasted capture is live again")
        #expect(board.canvas.artwork[restored.id]?.superview === board.canvas)
    }

    @MainActor @Test
    func removingOneOfSeveralPagesKeepsTheOthersHosted() throws {
        let capture = Self.liveCapture()
        let board = try Board([Self.browser, capture, Self.shape])
        defer { board.close() }
        board.select([capture.id])
        board.canvas.deleteSelection()
        board.settle()
        #expect(board.session.document.items.map(\.id) == [Self.browser.id, Self.shape.id])
        #expect(board.hostsSurface)
        #expect(board.canvas.artwork[Self.shape.id]?.superview === board.canvas)
        #expect(board.canvas.artwork[capture.id] == nil)
    }

    @MainActor @Test
    func deletingOnALaterPageRetiresOnlyThatPagesObjects() throws {
        let first = EaselPage(id: UUID(), name: "Page 1"), second = EaselPage(id: UUID(), name: "Page 2")
        var kept = Self.browser; kept.page = first.id
        var doomed = Self.liveCapture(); doomed.page = second.id
        var shape = Self.shape; shape.page = second.id
        let board = try Board([kept, doomed, shape], pages: [first, second])
        defer { board.close() }
        #expect(board.canvas.showPage(second.id))
        board.paint()
        board.select([doomed.id])
        board.canvas.deleteSelection()
        let replacement = try #require(board.surfaces.replacements.last)
        #expect(replacement.items.contains { $0.id == kept.id && $0.ownsEmbeddedPage },
                "A page on another Easel page is not asked to close")
        #expect(!replacement.items.contains { $0.id == doomed.id })
        board.settle()
        #expect(board.session.document.items.map(\.id) == [kept.id, shape.id])
        #expect(board.repaintedEverythingVisible)
    }

    @MainActor @Test
    func undoOnALaterPageOffersTheWholeEasel() throws {
        let first = EaselPage(id: UUID(), name: "Page 1"), second = EaselPage(id: UUID(), name: "Page 2")
        var kept = Self.browser; kept.page = first.id
        var shape = Self.shape; shape.page = second.id
        let board = try Board([kept, shape], pages: [first, second])
        defer { board.close() }
        #expect(board.canvas.showPage(second.id))
        board.select([shape.id])
        board.canvas.deleteSelection()
        board.settle()
        board.canvas.undo(nil)
        let replacement = try #require(board.surfaces.replacements.last)
        #expect(replacement.items.map(\.id) == [kept.id, shape.id])
    }
}
