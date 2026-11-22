import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct EaselCanvasTestsSelection {
    private typealias Board = EaselCanvasTestsSupport.Board

    @MainActor @Test
    func reverseMarqueeSelectsObjectsForTheNudge() throws {
        let board = try Board()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        board.marquee(250, 250, 0, 0)
        canvas.keyDown(with: board.key(124))
        #expect(session.document.items[0].frame.x == 31 && session.document.items[1].frame.x == 131 && session.document.items[2].frame.x == 500, "Native reverse marquee selects original first two objects for nudge")
    }

    @MainActor @Test
    func commandMarqueeSubtractsAndShiftNudgesTenPoints() throws {
        let board = try Board()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        canvas.selection = [board.a.id, board.b.id]
        board.marquee(250, 250, 100, 100, flags: .command)
        canvas.keyDown(with: board.key(124, flags: .shift))
        #expect(session.document.items[0].frame.x == 40 && session.document.items[1].frame.x == 130, "Command marquee subtracts without adding and Shift nudge uses existing 10pt step")
    }

    @MainActor @Test
    func shiftMarqueeAddsToTheSelection() throws {
        let board = try Board()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        canvas.selection = [board.a.id]
        board.marquee(450, 200, 700, 0, flags: .shift)
        canvas.keyDown(with: board.key(125))
        #expect(session.document.items[0].frame.y == 31 && session.document.items[1].frame.y == 130 && session.document.items[2].frame.y == 31, "Shift marquee unions original selection with text")
    }

    @MainActor @Test
    func escapeCancelsAnInProgressMove() throws {
        let board = try Board()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        let before = session.document
        canvas.mouseDown(with: board.mouse(.leftMouseDown, 40, 40))
        canvas.mouseDragged(with: board.mouse(.leftMouseDragged, 100, 100))
        canvas.cancelOperation(nil); canvas.mouseUp(with: board.mouse(.leftMouseUp, 100, 100))
        #expect(session.document == before, "Escape cancels transient original-object move without writing or undo")
    }

    @MainActor @Test
    func cancelingMarqueePreservesTheCommittedSelection() throws {
        let board = try Board()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        canvas.selection = [board.a.id, board.c.id]
        canvas.mouseDown(with: board.mouse(.leftMouseDown, 250, 250))
        canvas.mouseDragged(with: board.mouse(.leftMouseDragged, 0, 0))
        canvas.cancelOperation(nil)
        canvas.keyDown(with: board.key(124))
        #expect(session.document.items[0].frame.x == 31 && session.document.items[2].frame.x == 501 && session.document.items[1].frame.x == 130, "Cancelled marquee preserves committed selection")
    }

    @MainActor @Test
    func anInterveningEditOfTheMovedObjectCancelsTheGesture() throws {
        let board = try Board()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        canvas.mouseDown(with: board.mouse(.leftMouseDown, 40, 40))
        canvas.mouseDragged(with: board.mouse(.leftMouseDragged, 90, 90))
        try session.perform("Other owner geometry") { $0.items[0].frame.x += 7 }
        let external = session.document
        canvas.mouseUp(with: board.mouse(.leftMouseUp, 90, 90))
        #expect(session.document == external, "Same-object external geometry cancels the whole native move")
    }

    @MainActor @Test
    func movingASelectionPreservesUnrelatedContent() throws {
        let board = try Board()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        canvas.selection = [board.a.id, board.c.id]
        canvas.mouseDown(with: board.mouse(.leftMouseDown, 40, 40))
        canvas.mouseDragged(with: board.mouse(.leftMouseDragged, 90, 90))
        try session.perform("Other owner content") { $0.items[1].color = "#112233" }
        canvas.mouseUp(with: board.mouse(.leftMouseUp, 90, 90))
        #expect(session.document.items[0].frame.x == 90 && session.document.items[2].frame.x == 560 && session.document.items[1].color == "#112233", "Native canvas-center move preserves latest unrelated changes and selected group spacing")
    }

    @MainActor @Test
    func undoingAGroupMovePreservesUnrelatedContent() throws {
        let board = try Board()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        canvas.selection = [board.a.id, board.c.id]
        canvas.mouseDown(with: board.mouse(.leftMouseDown, 40, 40))
        canvas.mouseDragged(with: board.mouse(.leftMouseDragged, 90, 90))
        try session.perform("Other owner content") { $0.items[1].color = "#112233" }
        canvas.mouseUp(with: board.mouse(.leftMouseUp, 90, 90))
        try session.undo()
        #expect(session.document.items[0].frame == board.a.frame && session.document.items[1].color == "#112233", "Native group move is one independent undo transaction")
    }
}
