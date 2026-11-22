import AppKit
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import Parc
@testable import ParcCore

enum EaselPagePoolTestsSupport {
    enum Kind: CaseIterable {
        case webpage, capture
    }

    @MainActor
    final class ScheduledWork {
        private var jobs: [() -> Void] = []

        func schedule(_ job: @escaping () -> Void) { jobs.append(job) }

        func runPending() {
            let pending = jobs
            jobs.removeAll()
            pending.forEach { $0() }
        }
    }

    @MainActor
    final class Window {
        let window: NSWindow
        let engine: EaselTestEngineWindow
        let binding: PCNativeBrowserWindow

        init() throws {
            _ = NSApplication.shared
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
                              styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            engine = EaselTestEngineWindow(window: window)
            binding = try #require(engine.binding as? PCNativeBrowserWindow)
        }

        func close() {
            window.contentView = nil
            window.close()
        }
    }

    @MainActor
    final class Board {
        nonisolated static let profile = "/fixture/profile"
        static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!

        let source: Window
        let session: EaselSession
        let canvas: EaselCanvasView
        let pool: EaselBrowserObjects
        let scheduledMetadata = ScheduledWork()
        let deadlines = ScheduledWork()
        let item: EaselItem
        private var pages: [EaselTestEnginePage] = []

        init(_ kind: Kind = .webpage, store: EaselStore? = nil) throws {
            source = try Window()
            let url = "https://fixture.invalid/original"
            let frame = EaselRect(x: 40, y: 20, width: 480, height: 320)
            let date = Date(timeIntervalSince1970: 42)
            let assetName = UUID().uuidString.lowercased() + ".png"
            let capture = EaselCaptureLayout(viewport: .init(x: 1000, y: 700), scroll: .init(x: 10, y: 300),
                region: .init(x: 20, y: 40, width: 300, height: 200), scrollContainers: [
                    EaselScrollContainer(anchorID: "main", path: "div:1", scroll: .init(x: 0, y: 900),
                                         frame: .init(x: 0, y: 64, width: 1000, height: 636))
                ])
            if let store {
                session = try store.create()
                if kind == .capture {
                    let asset = try session.importPNG(Self.png)
                    item = EaselItem(kind: .webCard, frame: frame, url: url, assetID: asset, capturedAt: date,
                                     captureLayout: capture, liveCapture: true)
                } else {
                    item = EaselItem(kind: .browser, frame: frame, url: url)
                }
                let original = item
                try session.perform("Seed") { $0.items = [original] }
            } else {
                if kind == .capture {
                    item = EaselItem(kind: .webCard, frame: frame, url: url, assetID: assetName, capturedAt: date,
                                     captureLayout: capture, liveCapture: true)
                } else {
                    item = EaselItem(kind: .browser, frame: frame, url: url)
                }
                let document = EaselDocument(id: UUID(), title: "Page pool", createdAt: date, modifiedAt: date, items: [item])
                session = try EaselSession(inMemory: document, assets: kind == .capture ? [assetName: Self.png] : [:])
            }
            canvas = EaselCanvasView(session: session)
            source.window.contentView = canvas
            pool = EaselBrowserObjects(session: session, canvas: canvas, binding: source.binding,
                profilePath: Self.profile, validOwner: { true }, activeOwner: { true },
                selectionChanged: {}, metadataChanged: {})
            pool.loadsLinkPreviews = false
            pool.scheduleSnapshotDeadline = { [weak deadlines] _, job in deadlines?.schedule(job) }
            pool.scheduleMetadataDelivery = { [weak scheduledMetadata] job in scheduledMetadata?.schedule(job) }
        }

        func place(_ object: EaselItem? = nil) throws -> NoteEmbedSurface {
            let object = object ?? item
            let surface = try #require(pool.surface(for: object) as? NoteEmbedSurface)
            if surface.superview == nil { canvas.addSubview(surface) }
            surface.frame = NSRect(x: object.frame.x, y: object.frame.y,
                                   width: object.frame.width, height: object.frame.height)
            surface.needsLayout = true
            surface.layoutSubtreeIfNeeded()
            return surface
        }

        func open(_ object: EaselItem? = nil) throws -> (NoteEmbedSurface, EaselTestEnginePage, PCNativePage) {
            let object = object ?? item
            let surface = try place(object)
            let address = try #require(object.url.flatMap(URL.init(string:)))
            let page = EaselTestEnginePage(url: address)
            pages.append(page)
            page.owner = source.engine
            try #require(source.engine.reply(with: page.page))
            let native = try #require(page.page as? PCNativePage)
            return (surface, page, native)
        }

        func appendWebpage() throws -> EaselItem {
            let other = EaselItem(kind: .browser, frame: .init(x: 40, y: 365, width: 300, height: 200),
                                  url: "https://fixture.invalid/second")
            try session.perform("Second page") { $0.items.append(other) }
            return other
        }

        func select() {
            canvas.selectBrowserObject(item.id)
            pool.synchronize(items: session.document.items, selection: [item.id], interacting: true)
        }

        func rebind(_ snapshot: EmbeddedPagePool.WindowTransfer, to target: Window,
                    path: String = Board.profile, metadata: @escaping () -> Void = {}) -> Bool {
            pool.rebindWindowTransfer(snapshot, binding: target.binding, profilePath: path,
                validOwner: { true }, activeOwner: { true }, selectionChanged: {}, metadataChanged: metadata)
        }

        func transfer(_ surface: NoteEmbedSurface, engine: EaselTestEnginePage, to destination: Window) throws {
            let snapshot = try #require(pool.snapshotForWindowTransfer())
            try #require(pool.beginWindowTransfer(snapshot))
            destination.window.contentView = canvas
            engine.owner = destination.engine
            try #require(rebind(snapshot, to: destination))
            try #require(pool.finishWindowTransfer(snapshot))
            pool.refreshVisibility()
            surface.layoutSubtreeIfNeeded()
        }

        func close() {
            for page in pages {
                page.isClosed = true
                if let native = page.page as? PCNativePage { pool.didClose(native) }
            }
            pool.disposeAfterClosure()
            source.close()
        }
    }
}
