import AppKit
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes
@testable import ParcEasels

struct EaselPagePoolTestsTransfer {
    typealias Kind = EaselPagePoolTestsSupport.Kind
    private typealias Board = EaselPagePoolTestsSupport.Board
    private typealias Window = EaselPagePoolTestsSupport.Window

    enum InvalidRebind: CaseIterable {
        case notMoved, nativeOwnerUnchanged, differentProfile, revokedPage
    }

    @MainActor @Test
    func startingATransferSuspendsPageInput() throws {
        let board = try Board()
        defer { board.close() }
        let (surface, _, page) = try board.open()
        board.select()
        let snapshot = try #require(board.pool.snapshotForWindowTransfer())
        #expect(snapshot.pages.values.first === page)
        #expect(snapshot.views.values.first === surface.browser)
        try #require(board.pool.beginWindowTransfer(snapshot))
        #expect(board.pool.selectedPage == nil && board.pool.visiblePages.isEmpty)
        #expect(!board.pool.focusPage(for: board.item.id))
        #expect(board.pool.accessibilitySurface(for: board.item.id) == nil)
    }

    @MainActor @Test
    func startingATransferBlocksCompetingTransfers() throws {
        let board = try Board()
        defer { board.close() }
        let (surface, _, page) = try board.open()
        board.select()
        let snapshot = try #require(board.pool.snapshotForWindowTransfer())
        #expect(snapshot.pages.values.first === page)
        #expect(snapshot.views.values.first === surface.browser)
        try #require(board.pool.beginWindowTransfer(snapshot))
        #expect(!board.pool.beginWindowTransfer(snapshot))
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
    }

    @MainActor @Test
    func documentRemovalCannotRaceAnInProgressTransfer() throws {
        let board = try Board()
        defer { board.close() }
        _ = try board.open()
        let snapshot = try #require(board.pool.snapshotForWindowTransfer())
        try #require(board.pool.beginWindowTransfer(snapshot))
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
    }

    @MainActor @Test
    func aFinishedTransferCannotReuseItsSnapshot() throws {
        let board = try Board()
        defer { board.close() }
        let target = try Window()
        defer { target.close() }
        let (_, engine, _) = try board.open()
        board.select()
        let snapshot = try #require(board.pool.snapshotForWindowTransfer())
        try #require(board.pool.beginWindowTransfer(snapshot))
        target.window.contentView = board.canvas
        engine.owner = target.engine
        try #require(board.rebind(snapshot, to: target))
        try #require(board.pool.finishWindowTransfer(snapshot))
        board.pool.refreshVisibility()
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
    func aClosedPageCanBeRemovedDuringTransfer() throws {
        let board = try Board()
        defer { board.close() }
        let (_, engine, page) = try board.open()
        let snapshot = try #require(board.pool.snapshotForWindowTransfer())
        try #require(board.pool.beginWindowTransfer(snapshot))
        engine.isClosed = true
        board.pool.didClose(page)
        try board.session.perform("Remove closed page") { $0.items.removeAll() }
        _ = snapshot
        #expect(board.session.document.items.isEmpty)
    }

    @MainActor @Test
    func aClosedPageDoesNotKeepTheTransferGateOpen() throws {
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
    func movingAcrossProfilesPreservesTheSavedObjectAndItsAsset(_ kind: Kind) throws {
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
        #expect(arrived.document == original.session.document)
        #expect(original.session.isClosed && original.pool.pages.isEmpty)
        if let asset = original.item.assetID {
            #expect(try arrived.assetData(asset) == Board.png)
        }
    }

    @MainActor @Test(arguments: Kind.allCases)
    func openingAMovedObjectCreatesAPageInTheDestinationProfile(_ kind: Kind) throws {
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
        let canvas = makeTestEaselCanvas(session: arrived)
        destination.window.contentView = canvas
        let pool = EaselBrowserObjects(session: arrived, canvas: canvas, binding: destination.binding,
            profilePath: "/fixture/target-profile", validOwner: { true }, activeOwner: { true },
            selectionChanged: {}, metadataChanged: {})
        pool.loadsLinkPreviews = false
        pool.scheduleMetadataDelivery = { _ in }
        defer { pool.disposeAfterClosure() }
        let surface = try #require(pool.surface(for: arrived.document.items[0]) as? NoteEmbedSurface)
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
        #expect(destination.engine.requestedProfile == "/fixture/target-profile")
        #expect(destination.engine.requestedURL?.absoluteString == original.item.url)
    }
}
