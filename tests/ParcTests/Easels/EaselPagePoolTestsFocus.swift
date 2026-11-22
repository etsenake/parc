import AppKit
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import Parc
@testable import ParcCore

struct EaselPagePoolTestsFocus {
    private typealias Board = EaselPagePoolTestsSupport.Board

    @MainActor @Test
    func pendingCreationDoesNotRepeatOnLayout() throws {
        let board = try Board()
        defer { board.close() }
        let surface = try board.place()
        surface.needsLayout = true
        surface.layoutSubtreeIfNeeded()
        #expect(board.pool.hasPendingCreation)
        #expect(board.source.engine.creations == 1)
    }

    @MainActor @Test
    func pendingCreationRefusesAWindowTransfer() throws {
        let board = try Board()
        defer { board.close() }
        _ = try board.place()
        #expect(board.pool.snapshotForWindowTransfer() == nil)
    }

    @MainActor @Test
    func enteringASelectedPageFocusesItsNativeView() throws {
        let board = try Board()
        defer { board.close() }
        let (surface, engine, page) = try board.open()
        board.select()
        #expect(board.pool.selectedPage === page)
        #expect(board.pool.focusPage(for: board.item.id))
        #expect(board.source.window.firstResponder === engine.nativeView)
        #expect(board.pool.accessibilitySurface(for: board.item.id) === surface)
        #expect(!EmbeddedPagePool.excludesFromKeyboardNavigation(surface))
    }

    @MainActor @Test
    func returningFromAPageRestoresCanvasFocusWithoutReloading() throws {
        let board = try Board()
        defer { board.close() }
        let (surface, engine, page) = try board.open()
        board.select()
        _ = page
        try #require(board.pool.focusPage(for: board.item.id))
        surface.cancelOperation(nil)
        #expect(board.source.window.firstResponder === board.canvas)
        #expect(board.pool.selectedPage == nil)
        #expect(board.pool.accessibilitySurface(for: board.item.id) == nil)
        #expect(EmbeddedPagePool.excludesFromKeyboardNavigation(surface))
        #expect(board.source.engine.creations == 1 && engine.loads == 0)
    }

    @MainActor @Test
    func aCrashedPageFocusesRecovery() throws {
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
    }

    @MainActor @Test
    func clearingACrashRestoresNativePageFocus() throws {
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
}
