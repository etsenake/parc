import AppKit
import ParcEngine
import Testing
@testable import ParcCore
@testable import ParcEasels

struct EaselPagePoolTestsPageSwitching {
    private typealias Board = EaselPagePoolTestsSupport.Board
    typealias Kind = EaselPagePoolTestsSupport.Kind

    @MainActor @Test(arguments: Kind.allCases)
    func anotherBoardPageKeepsLiveWebpagesAttachedForClosing(_ kind: Kind) throws {
        let board = try Board(kind)
        defer { board.close() }
        let (surface, _, page) = try board.open()
        board.select()
        board.canvas.layoutSubtreeIfNeeded()
        try #require(page.nativeView.window === board.source.window)

        try #require(board.canvas.addPage())
        board.canvas.layoutSubtreeIfNeeded()

        #expect(board.canvas.session.document.items.isEmpty)
        #expect(board.pool.pages.contains { $0 === page })
        #expect(page.nativeView.window === board.source.window)
        #expect(surface.isHiddenOrHasHiddenAncestor)
        #expect(board.pool.visiblePages.isEmpty)
        #expect(board.pool.selectedPage == nil)
        #expect(!surface.inputAvailable)
    }

    @MainActor @Test(arguments: Kind.allCases)
    func returningToABoardPageReusesItsLiveWebpage(_ kind: Kind) throws {
        let board = try Board(kind)
        defer { board.close() }
        let (surface, engine, page) = try board.open()
        board.canvas.layoutSubtreeIfNeeded()
        try #require(board.canvas.addPage())
        board.canvas.layoutSubtreeIfNeeded()
        let first = try #require(board.session.document.pages?.first?.id)

        try #require(board.canvas.showPage(first))
        board.canvas.layoutSubtreeIfNeeded()

        #expect(board.canvas.artwork[board.item.id] === surface)
        #expect(surface.browser.nativePage === page)
        #expect(page.nativeView.window === board.source.window)
        #expect(!surface.isHiddenOrHasHiddenAncestor)
        #expect(board.pool.visiblePages.contains { $0 === page })
        #expect(board.source.engine.creations == 1)
        #expect(engine.loads == 0)
    }

    @MainActor @Test(arguments: Kind.allCases)
    func removingAClosedWebpageReleasesItsHiddenSurface(_ kind: Kind) throws {
        let board = try Board(kind)
        defer { board.close() }
        let (surface, engine, page) = try board.open()
        board.canvas.layoutSubtreeIfNeeded()
        try #require(board.canvas.addPage())
        board.canvas.layoutSubtreeIfNeeded()

        engine.isClosed = true
        board.pool.didClose(page)
        try board.session.perform("Remove webpage") { $0.items.removeAll() }
        board.canvas.documentDidChange()
        board.canvas.layoutSubtreeIfNeeded()

        #expect(surface.superview == nil)
        #expect(board.canvas.artwork[board.item.id] == nil)
        #expect(board.pool.pages.isEmpty)
    }
}
