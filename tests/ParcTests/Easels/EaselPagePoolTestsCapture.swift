import AppKit
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes
@testable import ParcEasels

struct EaselPagePoolTestsCapture {
    private typealias Board = EaselPagePoolTestsSupport.Board
    private typealias Window = EaselPagePoolTestsSupport.Window

    @MainActor private func captureStatus(in surface: NoteEmbedSurface) -> NSTextField? {
        let fallback = surface.subviews.lazy.flatMap(\.subviews).compactMap { $0 as? NoteEmbedFallbackView }.first
        return fallback?.subviews.compactMap { $0 as? NSTextField }.first
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
    func theDestinationShowsItsOwnPendingCaptureStatus() throws {
        let board = try Board(.capture)
        defer { board.close() }
        let destination = try Window()
        defer { destination.close() }
        let (surface, engine, _) = try board.open()
        board.select()
        surface.needsLayout = true
        surface.layoutSubtreeIfNeeded()
        let sourceRequests = engine.positionRequests
        try #require(sourceRequests > 0)

        try board.transfer(surface, engine: engine, to: destination)

        #expect(surface.window === destination.window)
        #expect(engine.positionRequests == sourceRequests + 1)
        let status = try #require(captureStatus(in: surface))
        #expect(!status.isHiddenOrHasHiddenAncestor)
        #expect(status.stringValue == EmbeddedPageStatusText.friendly("Positioning live capture…", document: "Easel"))
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
        try board.transfer(surface, engine: engine, to: destination)
        #expect(engine.positionWasCancelled(at: sourcePosition))
        try #require(engine.positionRequests > sourcePosition + 1)
        let destinationPosition = engine.positionRequests - 1
        let status = try #require(captureStatus(in: surface))
        engine.reply(atPosition: sourcePosition, success: false)
        #expect(surface.showsRecovery)
        #expect(engine.positionRequests == destinationPosition + 1)
        #expect(!status.isHiddenOrHasHiddenAncestor)
        #expect(status.stringValue == EmbeddedPageStatusText.friendly("Positioning live capture…", document: "Easel"))
        #expect(board.session.document.items[0].liveCapture == true)
    }

    @MainActor @Test
    func aDestinationPositioningReplyClearsRecovery() throws {
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
        try board.transfer(surface, engine: engine, to: destination)
        try #require(engine.positionRequests > sourcePosition + 1)
        let destinationPosition = engine.positionRequests - 1
        let status = try #require(captureStatus(in: surface))
        engine.reply(atPosition: destinationPosition, success: true)
        #expect(!surface.showsRecovery)
        #expect(status.isHiddenOrHasHiddenAncestor)
        #expect(status.stringValue.isEmpty)
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
}
