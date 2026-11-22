import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct EaselCanvasTestsFormatOwnership {
    private typealias EnginePage = EaselCanvasTestsSupport.EnginePage
    private typealias FormatBoard = EaselCanvasTestsSupport.FormatBoard

    @MainActor @Test
    func anActiveCompositionDisablesFormatting() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let editor = try board.startEditing()
        editor.localUndo.beginUndoGrouping()
        editor.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 0, length: 0))
        #expect(!board.validate(.bold) && !board.validate(.bigger), "Composition keeps formatting disabled")
        editor.unmarkText(); editor.localUndo.endUndoGrouping()
    }

    @MainActor @Test
    func anInactiveWindowCannotFormatItsCanvas() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let window = board.window
        _ = try board.startEditing()
        window.key = false
        #expect(!board.validate(.bold), "A canvas behind another key window is never formatted")
    }

    @MainActor @Test
    func anEmbeddedPageCannotReceiveCanvasFormatting() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let canvas = board.canvas
        let window = board.window
        let editor = try board.startEditing()
        let page = EnginePage(frame: NSRect(x: 0, y: 0, width: 50, height: 50)); canvas.addSubview(page)
        #expect(window.makeFirstResponder(page) && board.owner() === canvas, "An embedded page shares the canvas responder chain")
        #expect(!board.validate(.bold) && !board.validate(.heading1) && !board.validate(.bigger) && !board.validate(.link), "An embedded web page never receives Parc formatting")
        page.removeFromSuperview()

        #expect(window.makeFirstResponder(editor), "Editor focus returns")
    }

    @MainActor @Test
    func aSelectedTextBoxGetsWholeObjectSizeSteps() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let canvas = board.canvas
        let window = board.window
        let editor = try board.startEditing()
        let session = board.session
        _ = canvas.textView(editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        let text = session.document.items.first { $0.kind == .text }!
        canvas.mouseDown(with: board.mouse(.leftMouseDown, NSPoint(x: text.frame.x + 10, y: text.frame.y + 10)))
        canvas.mouseUp(with: board.mouse(.leftMouseUp, NSPoint(x: text.frame.x + 10, y: text.frame.y + 10)))
        #expect(window.firstResponder === canvas && !board.validate(.bold) && board.validate(.bigger), "A selected text box offers only the size steps its style bar shows")
        board.perform(.bigger)
        #expect(session.document.items.first { $0.id == text.id }?.resolvedTextStyle.size == text.resolvedTextStyle.size.shifted(by: 1), "Bigger restyles the whole selected text box")
    }

    @MainActor @Test
    func shapesAndTextBoxesShareSizeSteps() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let canvas = board.canvas
        let window = board.window
        let editor = try board.startEditing()
        let session = board.session
        _ = canvas.textView(editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        let text = session.document.items.first { $0.kind == .text }!
        canvas.mouseDown(with: board.mouse(.leftMouseDown, NSPoint(x: text.frame.x + 10, y: text.frame.y + 10)))
        canvas.mouseUp(with: board.mouse(.leftMouseUp, NSPoint(x: text.frame.x + 10, y: text.frame.y + 10)))
        board.perform(.bigger)
        canvas.selectAll(nil)
        #expect(board.validate(.bigger), "Shapes hold text too, so a text box and a shape share the size steps")
        window.makeFirstResponder(canvas)
    }
}
