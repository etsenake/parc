import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct EaselCanvasTestsFormat {
    private typealias FormatBoard = EaselCanvasTestsSupport.FormatBoard

    @MainActor @Test
    func theCanvasOwnsFormatCommandsForItsEditor() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let window = board.window
        let editor = try board.startEditing()
        let all = NSRange(location: 0, length: 9)
        #expect(window.firstResponder === editor && board.owner() === board.canvas && editor.selectedRange() == all, "The canvas owns formatting above its editor")
    }

    @MainActor @Test
    func boldStartsUncheckedForPlainText() throws {
        let board = try FormatBoard()
        defer { board.close() }
        _ = try board.startEditing()
        #expect(board.validate(.bold) && board.state(.bold) == .off, "Bold is available without a checkmark on plain text")
    }

    @MainActor @Test
    func menuBoldFormatsAndChecksTheSelection() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let editor = try board.startEditing()
        board.run(.bold, in: editor)
        let menuUndo = editor.localUndo.undoActionName
        #expect(editor.hasEmphasis(.bold) && board.state(.bold) == .on && menuUndo == "Bold", "Menu Bold formats the selection and shows its checkmark")
    }

    @MainActor @Test
    func menuAndToolbarBoldProduceTheSameTextAndUndo() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let canvas = board.canvas
        let editor = try board.startEditing()
        board.run(.bold, in: editor)
        let menuBold = NSAttributedString(attributedString: editor.attributedString()), menuUndo = editor.localUndo.undoActionName
        editor.undo(nil)
        editor.localUndo.beginUndoGrouping(); canvas.performSelectionToolbar(.bold); editor.localUndo.endUndoGrouping()
        #expect(editor.attributedString().isEqual(to: menuBold) && editor.localUndo.undoActionName == menuUndo, "Menu Bold and the selection toolbar's B button produce the same text and Undo")
    }

    @MainActor @Test
    func menuBoldTogglesAnEmphasizedRangeOff() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let canvas = board.canvas
        let editor = try board.startEditing()
        editor.localUndo.beginUndoGrouping(); canvas.performSelectionToolbar(.bold); editor.localUndo.endUndoGrouping()
        board.run(.bold, in: editor)
        #expect(!editor.hasEmphasis(.bold) && board.state(.bold) == .off, "Menu Bold toggles back off")
    }

    @MainActor @Test(arguments: [TextFormatCommand.italic, .underline, .strikethrough])
    func theEmphasisMenuAppliesAndChecksItsRange(_ command: TextFormatCommand) throws {
        let board = try FormatBoard()
        defer { board.close() }
        let editor = try board.startEditing()
        board.run(command, in: editor)
        #expect(editor.hasEmphasis(command.emphasis!) && board.validate(command) && board.items[command]!.state == .on, "Menu \(command.title) formats and checks")
    }

    @MainActor @Test(arguments: [TextFormatCommand.italic, .underline, .strikethrough])
    func theEmphasisMenuTogglesItsRangeOff(_ command: TextFormatCommand) throws {
        let board = try FormatBoard()
        defer { board.close() }
        let editor = try board.startEditing()
        board.run(command, in: editor)
        board.run(command, in: editor)
        #expect(!editor.hasEmphasis(command.emphasis!), "Menu \(command.title) toggles off")
    }

    @MainActor @Test
    func bodyTextOffersBiggerOnly() throws {
        let board = try FormatBoard()
        defer { board.close() }
        _ = try board.startEditing()
        #expect(board.validate(.bigger) && !board.validate(.smaller), "Body-size text offers only Bigger, like the selection toolbar")
    }

    @MainActor @Test
    func biggerAdvancesTheSelectedRangeOneSize() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let editor = try board.startEditing()
        board.run(.bigger, in: editor)
        let menuBigger = NSAttributedString(attributedString: editor.attributedString())
        #expect(board.validate(.smaller) && menuBigger.attribute(.font, at: 0, effectiveRange: nil) as? NSFont != EaselTextAppearance.font(EaselTextStyle()), "Bigger steps the selected text up a size")
    }

    @MainActor @Test
    func menuAndToolbarBiggerProduceTheSameText() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let canvas = board.canvas
        let editor = try board.startEditing()
        board.run(.bigger, in: editor)
        let menuBigger = NSAttributedString(attributedString: editor.attributedString())
        editor.undo(nil)
        editor.localUndo.beginUndoGrouping(); canvas.performSelectionToolbar(.larger); editor.localUndo.endUndoGrouping()
        #expect(editor.attributedString().isEqual(to: menuBigger), "Menu Bigger matches the selection toolbar's bigger button")
    }

    @MainActor @Test
    func smallerReturnsTheSelectedRangeToBodySize() throws {
        let board = try FormatBoard()
        defer { board.close() }
        let canvas = board.canvas
        let editor = try board.startEditing()
        editor.localUndo.beginUndoGrouping(); canvas.performSelectionToolbar(.larger); editor.localUndo.endUndoGrouping()
        board.run(.smaller, in: editor)
        #expect(!board.validate(.smaller), "Smaller returns the text to body size")
    }
}
