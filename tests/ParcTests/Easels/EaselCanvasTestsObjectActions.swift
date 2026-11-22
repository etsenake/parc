import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct EaselCanvasTestsObjectActions {
    private typealias Board = EaselCanvasTestsSupport.Board

    @MainActor @Test
    func duplicateFromTheMenuCreatesNewIdentitiesAndUndoesInOneStep() throws {
        let board = try Board()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        let a = board.a, c = board.c
        canvas.selection = [a.id, c.id]
        let duplicate = try EaselCanvasTestsSupport.menuRow(EaselCanvasTestsSupport.contextMenu(canvas, board.mouse(.rightMouseDown, 40, 40)), "Duplicate")
        #expect(duplicate.isEnabled, "Original selected objects admit native Duplicate")
        duplicate.perform?()
        #expect(session.document.items.count == 5 && Set(session.document.items.suffix(2).map(\.id)).isDisjoint(with: [a.id, c.id]), "Native Duplicate commits new identities for the complete selection")
        try session.undo()
        #expect(session.document.items.count == 3, "One undo removes complete native duplicate group")
    }

    @MainActor @Test
    func aMenuActionRefusesAStaleSelection() throws {
        let board = try Board()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        canvas.selectAll(nil)
        let staleDuplicate = try EaselCanvasTestsSupport.menuRow(EaselCanvasTestsSupport.contextMenu(canvas, board.mouse(.rightMouseDown, 40, 40)), "Duplicate")
        canvas.mouseDown(with: board.mouse(.leftMouseDown, 300, 400)); canvas.mouseUp(with: board.mouse(.leftMouseUp, 300, 400))
        #expect(canvas.selection.isEmpty, "Clicking empty canvas clears the selection the menu was built for")
        staleDuplicate.perform?()
        #expect(session.document.items.count == 3, "A menu row built for an earlier selection is refused at execution")
    }

    @MainActor @Test
    func aSingleObjectResizeHasOneUndoStep() throws {
        let board = try Board()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        canvas.mouseDown(with: board.mouse(.leftMouseDown, 40, 40)); canvas.mouseUp(with: board.mouse(.leftMouseUp, 40, 40))
        canvas.cancelOperation(nil)
        canvas.mouseDown(with: board.mouse(.leftMouseDown, 40, 40)); canvas.mouseUp(with: board.mouse(.leftMouseUp, 40, 40))
        let originalFrame = session.document.items[0].frame
        canvas.mouseDown(with: board.mouse(.leftMouseDown, 80, 80))
        canvas.mouseDragged(with: board.mouse(.leftMouseDragged, 100, 110)); canvas.mouseUp(with: board.mouse(.leftMouseUp, 100, 110))
        #expect(session.document.items[0].frame.width == 70 && session.document.items[0].frame.height == 80, "Original single-object resize remains a genuine geometry transaction")
        try session.undo(); #expect(session.document.items[0].frame == originalFrame, "Resize undo restores original frame")
        canvas.selectAll(nil)
    }

    @MainActor @Test
    func aFailedDuplicatePreservesTheSelectedObjects() throws {
        let board = try Board()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        let saveDuplicate = try EaselCanvasTestsSupport.menuRow(EaselCanvasTestsSupport.contextMenu(canvas, board.mouse(.rightMouseDown, 40, 40)), "Duplicate")
        let savedSelection = canvas.selection
        let saved = session.document, path = board.directory.appendingPathComponent("documents/" + saved.id.uuidString.lowercased() + ".json")
        let bytes = try Data(contentsOf: path)
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        saveDuplicate.perform?()
        #expect(board.errors == 1 && session.document == saved && canvas.selection == savedSelection, "Failed duplicate reports the real save error and retains original selected targets")
        try FileManager.default.removeItem(at: path); try bytes.write(to: path)
    }

    @MainActor @Test
    func resigningKeyCancelsTheMove() throws {
        let board = try Board()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        let saved = session.document
        canvas.mouseDown(with: board.mouse(.leftMouseDown, 40, 40)); canvas.mouseDragged(with: board.mouse(.leftMouseDragged, 90, 90))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: board.window)
        canvas.mouseUp(with: board.mouse(.leftMouseUp, 90, 90))
        #expect(session.document == saved, "Original owner resigning cancels native move")
    }

    @MainActor @Test
    func returnFocusesTheSelectedTextEditor() throws {
        let board = try Board()
        defer { board.close() }
        let canvas = board.canvas
        let window = board.window
        canvas.cancelOperation(nil)
        canvas.mouseDown(with: board.mouse(.leftMouseDown, 530, 55)); canvas.mouseUp(with: board.mouse(.leftMouseUp, 530, 55))
        canvas.keyDown(with: board.key(36))
        #expect(window.firstResponder is EaselStyledTextView, "Return on the original text object retains the real native range editor")
    }

    @MainActor @Test
    func escapeReturnsFocusFromTheEditorToTheCanvas() throws {
        let board = try Board()
        defer { board.close() }
        let canvas = board.canvas
        let window = board.window
        canvas.cancelOperation(nil)
        canvas.mouseDown(with: board.mouse(.leftMouseDown, 530, 55)); canvas.mouseUp(with: board.mouse(.leftMouseUp, 530, 55))
        canvas.keyDown(with: board.key(36))
        if let text = window.firstResponder as? EaselStyledTextView {
            #expect(canvas.textView(text, doCommandBy: #selector(NSResponder.cancelOperation(_:))), "Native editor Escape uses its existing delegate")
        }
        #expect(window.firstResponder === canvas, "Editor Escape returns focus to the same canvas")
    }

    @MainActor @Test
    func detachingTheCanvasRetiresItsDuplicateAction() throws {
        let board = try Board()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        let window = board.window
        canvas.selectAll(nil)
        let detachMenu = EaselCanvasTestsSupport.contextMenu(canvas, board.mouse(.rightMouseDown, 40, 40))
        let detachDuplicate = try EaselCanvasTestsSupport.menuRow(detachMenu, "Duplicate")
        #expect(detachDuplicate.isEnabled, "Current original menu target is valid before detachment")
        window.contentView = nil
        let beforePaste = session.document
        detachDuplicate.perform?()
        #expect(session.document == beforePaste, "Detached canvas retires its exact-window menu target")
        #expect(!window.isVisible, "Component window was never displayed")
    }

    @MainActor @Test
    func detachingTheCanvasRetiresItsPasteActions() throws {
        let board = try Board()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        let window = board.window
        canvas.selectAll(nil)
        let detachMenu = EaselCanvasTestsSupport.contextMenu(canvas, board.mouse(.rightMouseDown, 40, 40))
        window.contentView = nil
        let beforePaste = session.document
        try EaselCanvasTestsSupport.menuRow(detachMenu, "Paste").perform?()
        try EaselCanvasTestsSupport.menuRow(detachMenu, "Paste as Plain Text").perform?()
        #expect(session.document == beforePaste, "Stale paste dispatch leaves exact document unchanged without reading personal clipboard")
        #expect(!window.isVisible, "Component window was never displayed")
    }
}
