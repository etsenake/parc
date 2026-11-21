import AppKit
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import Parc
@testable import ParcCore

struct EaselPagePoolTests {
    enum Kind: CaseIterable {
        case webpage, capture
    }

    @MainActor
    private final class ScheduledWork {
        private var jobs: [() -> Void] = []

        func schedule(_ job: @escaping () -> Void) { jobs.append(job) }

        func runPending() {
            let pending = jobs
            jobs.removeAll()
            pending.forEach { $0() }
        }
    }

    @MainActor
    private final class Window {
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
    private final class Board {
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

        func place(_ object: EaselItem? = nil) throws -> EaselBrowserSurface {
            let object = object ?? item
            let surface = try #require(pool.surface(for: object) as? EaselBrowserSurface)
            if surface.superview == nil { canvas.addSubview(surface) }
            surface.frame = NSRect(x: object.frame.x, y: object.frame.y,
                                   width: object.frame.width, height: object.frame.height)
            surface.needsLayout = true
            surface.layoutSubtreeIfNeeded()
            return surface
        }

        func open(_ object: EaselItem? = nil) throws -> (EaselBrowserSurface, EaselTestEnginePage, PCNativePage) {
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

        func close() {
            for page in pages {
                page.isClosed = true
                if let native = page.page as? PCNativePage { pool.didClose(native) }
            }
            pool.disposeAfterClosure()
            source.close()
        }
    }

    @MainActor @Test
    func pendingCreationRefusesATransferAndDoesNotRepeatOnLayout() throws {
        let board = try Board()
        defer { board.close() }
        let surface = try board.place()
        surface.needsLayout = true
        surface.layoutSubtreeIfNeeded()
        #expect(board.pool.hasPendingCreation)
        #expect(board.source.engine.creations == 1)
        #expect(board.pool.snapshotForWindowTransfer() == nil)
    }

    @MainActor @Test
    func pageEntryAndReturnPreserveTheSameNativePage() throws {
        let board = try Board()
        defer { board.close() }
        let (surface, engine, page) = try board.open()
        board.select()
        #expect(board.pool.selectedPage === page)
        #expect(board.pool.focusPage(for: board.item.id))
        #expect(board.source.window.firstResponder === engine.nativeView)
        #expect(board.pool.accessibilitySurface(for: board.item.id) === surface)
        #expect(!EmbeddedPagePool.excludesFromKeyboardNavigation(surface))

        surface.cancelOperation(nil)
        #expect(board.source.window.firstResponder === board.canvas)
        #expect(board.pool.selectedPage == nil)
        #expect(board.pool.accessibilitySurface(for: board.item.id) == nil)
        #expect(EmbeddedPagePool.excludesFromKeyboardNavigation(surface))
        #expect(board.source.engine.creations == 1 && engine.loads == 0)
    }

    @MainActor @Test
    func aCrashedPageFocusesRecoveryUntilItClears() throws {
        let board = try Board()
        defer { board.close() }
        let (surface, engine, _) = try board.open()
        board.select()
        engine.setCrashed(true)
        let crash = try #require(engine.crash as? PCNativeRendererCrash)
        board.pool.browserView(surface.browser, didChangeRendererCrash: crash)
        #expect(board.pool.focusPage(for: board.item.id))
        #expect(board.source.window.firstResponder !== engine.nativeView)
        #expect(surface.showsRecovery)

        engine.setCrashed(false)
        board.pool.browserView(surface.browser, didChangeRendererCrash: nil)
        #expect(board.pool.focusPage(for: board.item.id))
        #expect(board.source.window.firstResponder === engine.nativeView)
    }

    @MainActor @Test(arguments: [false, true])
    func aDetachedOrRevokedPageCannotTakeFocus(_ detach: Bool) throws {
        let board = try Board()
        defer { board.close() }
        let (surface, engine, _) = try board.open()
        board.select()
        if detach { engine.nativeView.removeFromSuperview() } else { engine.embeddedOwnerValid = false }
        #expect(!board.pool.focusPage(for: board.item.id))
        if !detach {
            #expect(board.pool.accessibilitySurface(for: board.item.id) == nil)
            #expect(EmbeddedPagePool.excludesFromKeyboardNavigation(surface))
        }
    }

    @MainActor @Test
    func deletingWhileAWebpageOwnsInputDoesNotDeleteTheObject() throws {
        let board = try Board()
        defer { board.close() }
        _ = try board.open()
        board.select()
        try #require(board.pool.focusPage(for: board.item.id))
        let before = board.session.document
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: board.source.window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 51))
        board.canvas.keyDown(with: event)
        #expect(board.session.document == before)
    }

    @MainActor @Test
    func transferSuspendsInputAndBlocksCompetingOperations() throws {
        let board = try Board()
        defer { board.close() }
        let (surface, _, page) = try board.open()
        board.select()
        let snapshot = try #require(board.pool.snapshotForWindowTransfer())
        #expect(snapshot.pages.values.first === page)
        #expect(snapshot.views.values.first === surface.browser)
        try #require(board.pool.beginWindowTransfer(snapshot))
        #expect(!board.pool.beginWindowTransfer(snapshot))
        #expect(board.pool.selectedPage == nil && board.pool.visiblePages.isEmpty)
        #expect(!board.pool.focusPage(for: board.item.id))
        #expect(board.pool.accessibilitySurface(for: board.item.id) == nil)
        #expect(board.pool.snapshotForWindowTransfer() == nil)
    }

    @MainActor @Test
    func replacementCannotRaceAnInProgressTransfer() throws {
        let board = try Board()
        defer { board.close() }
        _ = try board.open()
        let snapshot = try #require(board.pool.snapshotForWindowTransfer())
        try #require(board.pool.beginWindowTransfer(snapshot))
        var replacement = board.session.document
        replacement.items.removeAll()
        var accepted: Bool?
        board.pool.prepareReplacement(replacement, valid: { true }) { accepted = $0 }
        #expect(accepted == false && board.source.engine.closeRequests == 0)
        #expect(throws: EaselStoreError.self) { try board.session.perform("Remove page") { $0.items.removeAll() } }
        #expect(board.session.document.items == [board.item])
    }

    @MainActor @Test
    func unrelatedDocumentEditsKeepTheTransferSnapshotCurrent() throws {
        let board = try Board()
        defer { board.close() }
        _ = try board.open()
        let snapshot = try #require(board.pool.snapshotForWindowTransfer())
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 500, y: 0, width: 20, height: 20))
        try board.session.perform("Other content") { $0.items.append(shape) }
        #expect(board.pool.isCurrent(snapshot))
    }

    enum InvalidRebind: CaseIterable {
        case notMoved, nativeOwnerUnchanged, differentProfile, revokedPage
    }

    @MainActor @Test(arguments: InvalidRebind.allCases)
    func rebindRequiresTheOriginalPageAndAnActualSameProfileMove(_ cause: InvalidRebind) throws {
        let board = try Board()
        defer { board.close() }
        let target = try Window()
        defer { target.close() }
        let (_, page, _) = try board.open()
        let snapshot = try #require(board.pool.snapshotForWindowTransfer())
        try #require(board.pool.beginWindowTransfer(snapshot))
        if cause != .notMoved { target.window.contentView = board.canvas }
        if cause == .differentProfile || cause == .revokedPage { page.owner = target.engine }
        if cause == .revokedPage { page.embeddedOwnerValid = false }

        #expect(!board.rebind(snapshot, to: target, path: cause == .differentProfile ? "/another/profile" : Board.profile))
    }

    @MainActor @Test
    func transferKeepsTheOriginalWrapperPageAndSelection() throws {
        let board = try Board()
        defer { board.close() }
        let target = try Window()
        defer { target.close() }
        let (surface, engine, page) = try board.open()
        board.select()
        let snapshot = try #require(board.pool.snapshotForWindowTransfer())
        try #require(board.pool.beginWindowTransfer(snapshot))
        target.window.contentView = board.canvas
        engine.owner = target.engine
        try #require(board.rebind(snapshot, to: target))
        try #require(board.pool.finishWindowTransfer(snapshot))
        board.pool.refreshVisibility()
        #expect(board.pool.selectedPage === page)
        #expect(surface.browser.window === target.window)
        #expect(board.source.engine.creations == 1 && target.engine.creations == 0 && engine.loads == 0)
        #expect(!board.pool.beginWindowTransfer(snapshot))
    }

    @MainActor @Test
    func deferredMetadataDeliveryFollowsTheNewOwner() throws {
        let board = try Board()
        defer { board.close() }
        let target = try Window()
        defer { target.close() }
        let (surface, engine, _) = try board.open()
        let snapshot = try #require(board.pool.snapshotForWindowTransfer())
        try #require(board.pool.beginWindowTransfer(snapshot))
        target.window.contentView = board.canvas
        engine.owner = target.engine
        var changes = 0
        try #require(board.rebind(snapshot, to: target, metadata: { changes += 1 }))
        try #require(board.pool.finishWindowTransfer(snapshot))
        board.scheduledMetadata.runPending()
        let before = changes
        board.pool.browserView(surface.browser, didChangeTitle: "New title")
        #expect(changes == before)
        board.scheduledMetadata.runPending()
        #expect(changes == before + 1)
    }

    @MainActor @Test
    func rollbackKeepsTheOriginalPageOwner() throws {
        let board = try Board()
        defer { board.close() }
        let (_, engine, page) = try board.open()
        let snapshot = try #require(board.pool.snapshotForWindowTransfer())
        try #require(board.pool.beginWindowTransfer(snapshot))
        try #require(board.rebind(snapshot, to: board.source))
        try #require(board.pool.finishWindowTransfer(snapshot))
        #expect(board.pool.pages.first === page)
        #expect(board.source.engine.creations == 1 && engine.loads == 0)
    }

    @MainActor @Test
    func aClosedPageCanBeRemovedDuringTransferAndTheGateCanDrain() throws {
        let board = try Board()
        defer { board.close() }
        let (_, engine, page) = try board.open()
        let snapshot = try #require(board.pool.snapshotForWindowTransfer())
        try #require(board.pool.beginWindowTransfer(snapshot))
        engine.isClosed = true
        board.pool.didClose(page)
        try board.session.perform("Remove closed page") { $0.items.removeAll() }
        #expect(board.pool.canFinishWindowTransfer(snapshot))
        #expect(board.pool.finishWindowTransfer(snapshot))
        #expect(board.session.document.items.isEmpty)
    }

    @MainActor @Test(arguments: [false, true])
    func crossProfileRetirementRefusesPendingAndLiveChildren(_ open: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory)
        let board = try Board(store: store)
        defer { board.close() }
        if open { _ = try board.open() } else { _ = try board.place() }
        #expect(throws: EaselStoreError.self) { try store.retireSessionForRelocation(board.session.document.id) }
        #expect(!board.session.isClosed)
    }

    @MainActor @Test(arguments: Kind.allCases)
    func crossProfileMovePreservesTheSavedObjectButRecreatesItsPage(_ kind: Kind) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceStore = try EaselStore(directory: directory.appendingPathComponent("source"))
        let targetStore = try EaselStore(directory: directory.appendingPathComponent("target"))
        let original = try Board(kind, store: sourceStore)
        defer { original.close() }
        let (_, first, page) = try original.open()
        first.isClosed = true
        original.pool.didClose(page)
        original.pool.disposeAfterClosure()
        let id = original.session.document.id
        try sourceStore.retireSessionForRelocation(id)
        _ = try sourceStore.relocate(id, to: targetStore)
        let arrived = try targetStore.load(id)
        let destination = try Window()
        defer { destination.close() }
        let canvas = EaselCanvasView(session: arrived)
        destination.window.contentView = canvas
        let pool = EaselBrowserObjects(session: arrived, canvas: canvas, binding: destination.binding,
            profilePath: "/fixture/target-profile", validOwner: { true }, activeOwner: { true },
            selectionChanged: {}, metadataChanged: {})
        pool.loadsLinkPreviews = false
        pool.scheduleMetadataDelivery = { _ in }
        defer { pool.disposeAfterClosure() }
        let surface = try #require(pool.surface(for: arrived.document.items[0]) as? EaselBrowserSurface)
        if surface.superview == nil { canvas.addSubview(surface) }
        surface.frame = NSRect(x: 40, y: 20, width: 480, height: 320)
        surface.needsLayout = true
        surface.layoutSubtreeIfNeeded()
        let next = EaselTestEnginePage(url: first.url)
        next.owner = destination.engine
        try #require(destination.engine.reply(with: next.page))
        let native = try #require(next.page as? PCNativePage)
        defer { next.isClosed = true; pool.didClose(native) }
        #expect(pool.pages.first === native && native !== page)
        #expect(arrived.document == original.session.document)
        #expect(destination.engine.requestedProfile == "/fixture/target-profile")
        #expect(destination.engine.requestedURL?.absoluteString == original.item.url)
        #expect(original.session.isClosed && original.pool.pages.isEmpty)
        if let asset = original.item.assetID {
            #expect(try arrived.assetData(asset) == Board.png)
        }
    }

    @MainActor @Test
    func aPausedCaptureDoesNotCreateAWebpage() throws {
        let board = try Board(.capture)
        defer { board.close() }
        try board.session.perform("Pause capture") { $0.items[0].liveCapture = false }
        #expect(board.pool.surface(for: board.session.document.items[0]) == nil)
        #expect(!board.pool.hasPendingCreation && board.source.engine.creations == 0)
        #expect(board.session.document.items[0].captureLayout == board.item.captureLayout)
    }

    @MainActor @Test
    func liveCapturePositioningUsesTheOriginalRegionAndOffsets() throws {
        let board = try Board(.capture)
        defer { board.close() }
        let (surface, engine, page) = try board.open()
        board.select()
        surface.needsLayout = true
        surface.layoutSubtreeIfNeeded()
        #expect(board.pool.selectedPage === page)
        #expect(engine.positionedRegion == NSRect(x: 20, y: 40, width: 300, height: 200))
        #expect(engine.positionedScroll == NSPoint(x: 10, y: 300))
        #expect(engine.positionedContainerPaths == ["div:1"])
        #expect(engine.positionedContainerOffsets.map(\.pointValue) == [NSPoint(x: 0, y: 900)])
        #expect(surface.browser.frame.size == NSSize(width: 1000, height: 700))
    }

    @MainActor @Test
    func navigationDoesNotReplaceTheCaptureProvenance() throws {
        let board = try Board(.capture)
        defer { board.close() }
        let (surface, engine, _) = try board.open()
        board.select()
        let destination = try #require(URL(string: "https://fixture.invalid/later"))
        engine.url = destination
        board.pool.browserView(surface.browser, didChangeURL: destination)
        #expect(board.session.document.items[0].url == board.item.url)
    }

    @MainActor @Test
    func aLateSourcePositioningReplyCannotReplaceDestinationWork() throws {
        let board = try Board(.capture)
        defer { board.close() }
        let destination = try Window()
        defer { destination.close() }
        let (surface, engine, _) = try board.open()
        board.select()
        surface.needsLayout = true
        surface.layoutSubtreeIfNeeded()
        try #require(engine.positionRequests > 0)
        let sourcePosition = engine.positionRequests - 1
        let snapshot = try #require(board.pool.snapshotForWindowTransfer())
        try #require(board.pool.beginWindowTransfer(snapshot))
        #expect(engine.positionWasCancelled(at: sourcePosition))
        destination.window.contentView = board.canvas
        engine.owner = destination.engine
        try #require(board.rebind(snapshot, to: destination))
        try #require(board.pool.finishWindowTransfer(snapshot))
        board.pool.refreshVisibility()
        surface.layoutSubtreeIfNeeded()
        try #require(engine.positionRequests > sourcePosition + 1)
        let destinationPosition = engine.positionRequests - 1
        engine.reply(atPosition: sourcePosition, success: false)
        #expect(surface.showsRecovery)
        #expect(board.session.document.items[0].liveCapture == true)
        engine.reply(atPosition: destinationPosition, success: true)
        #expect(!surface.showsRecovery)
    }

    @MainActor @Test(arguments: [false, true])
    func returnToSnapshotWaitsForTheCloseDecision(_ allow: Bool) throws {
        let board = try Board(.capture)
        defer { board.close() }
        let (_, engine, _) = try board.open()
        board.select()
        board.source.engine.allowsClose = allow
        board.canvas.setLiveCapture(board.item.id, enabled: false)
        #expect(engine.isClosed == allow)
        #expect((board.session.document.items[0].liveCapture != true) == allow)
        let asset = try #require(board.item.assetID)
        #expect(try board.session.assetData(asset) == Board.png)
    }

    @MainActor @Test
    func snapshotCollectionKeepsThePageGeometryAndRejectsASecondCollection() throws {
        let board = try Board()
        defer { board.close() }
        let (surface, engine, _) = try board.open()
        var collected: [UUID: EaselPageSnapshot]?
        try #require(board.canvas.collectExportPages { collected = $0 })
        #expect(!board.canvas.collectExportPages { _ in Issue.record("Unexpected second snapshot delivery") })
        let image = NSImage(size: NSSize(width: 480, height: 288))
        engine.reply(withSnapshot: image)
        let snapshots = try #require(collected)
        let snapshot = try #require(snapshots[board.item.id])
        #expect(engine.snapshotRequests == 1)
        #expect(snapshot.image === image)
        #expect(snapshot.pageFrame == surface.pageArea.page && snapshot.visibleFrame == surface.pageArea.visible)
        #expect(snapshot.pageFrame.minY == EmbeddedPageHeader.height)
    }

    @MainActor @Test
    func snapshotExportDrawsPagePixelsBelowTheControls() throws {
        let board = try Board()
        defer { board.close() }
        let (_, engine, _) = try board.open()
        board.canvas.appearance = NSAppearance(named: .aqua)
        let red = NSImage(size: NSSize(width: 480, height: 288), flipped: false) { rect in
            NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
            rect.fill()
            return true
        }
        var collected: [UUID: EaselPageSnapshot]?
        try #require(board.canvas.collectExportPages { collected = $0 })
        engine.reply(withSnapshot: red)
        let pages = try #require(collected)
        let image = try #require(board.canvas.exportImage(backingScale: 1, pages: pages))
        let provider = try #require(image.dataProvider)
        let bytes = try #require(provider.data) as Data
        func rgb(x: Int, y: Int) -> [UInt8] {
            let position = y * image.bytesPerRow + x * 4
            return Array(bytes[position..<(position + 3)])
        }
        #expect(rgb(x: 280, y: 200) == [255, 0, 0])
        #expect(rgb(x: 280, y: 30) == [255, 255, 255])
    }

    @MainActor @Test
    func aSnapshotReplyWithoutPixelsLeavesThatPageOutOfTheCollection() throws {
        let board = try Board()
        defer { board.close() }
        let (_, first, _) = try board.open()
        let secondItem = try board.appendWebpage()
        let (_, second, _) = try board.open(secondItem)
        var collected: [UUID: EaselPageSnapshot]?
        try #require(board.canvas.collectExportPages { collected = $0 })
        first.reply(withSnapshot: NSImage(size: NSSize(width: 10, height: 10)))
        second.reply(withSnapshot: nil)
        let pages = try #require(collected)
        #expect(Set(pages.keys) == [board.item.id])
    }

    @MainActor @Test(arguments: [false, true])
    func anUnsupportedOrRefusedSnapshotLeavesTheSavedCard(_ supports: Bool) throws {
        let board = try Board()
        defer { board.close() }
        let (_, engine, _) = try board.open()
        engine.supportsSnapshot = supports
        engine.refusesSnapshot = true
        var snapshots: [UUID: EaselPageSnapshot]?
        try #require(board.canvas.collectExportPages { snapshots = $0 })
        #expect(snapshots?.isEmpty == true)
        #expect(engine.snapshotRequests == (supports ? 1 : 0))
    }

    @MainActor @Test
    func aSnapshotDeadlineDeliversRepliesSoFarAndIgnoresLateOnes() throws {
        let board = try Board()
        defer { board.close() }
        let (_, first, _) = try board.open()
        let secondItem = try board.appendWebpage()
        let (_, second, _) = try board.open(secondItem)
        var replies: [[UUID: EaselPageSnapshot]] = []
        try #require(board.canvas.collectExportPages { replies.append($0) })
        first.reply(withSnapshot: NSImage(size: NSSize(width: 10, height: 10)))
        #expect(replies.isEmpty)

        board.deadlines.runPending()
        let snapshots = try #require(replies.first)
        #expect(Set(snapshots.keys) == [board.item.id])
        second.reply(withSnapshot: NSImage(size: NSSize(width: 10, height: 10)))
        #expect(replies.count == 1)
    }
}
