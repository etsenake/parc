import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcEasels

struct EaselCanvasTestsTextPaste {
    private typealias ManualQueue = EaselCanvasTestsSupport.ManualQueue
    private typealias CanvasFixtureError = EaselCanvasTestsSupport.CanvasFixtureError
    private typealias RecordingPanels = EaselCanvasTestsSupport.RecordingPanels
    private typealias CanvasTextDrop = EaselCanvasTestsSupport.CanvasTextDrop

    @MainActor @Test
    func aClosedLinkEditorDoesNotBlockEmptyTextCleanup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-text-defaults-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let canvas = makeTestEaselCanvas(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        func currentEditor() -> EaselStyledTextView { canvas.subviews.compactMap { $0 as? EaselStyledTextView }.first! }
        func replace(_ editor: EaselStyledTextView, with string: String) {
            editor.textStorage?.setAttributedString(EaselTextAppearance.attributed(string, style: editor.objectStyle, color: editor.objectColor))
            editor.didChangeText()
        }
        canvas.insert(kind: .text, text: "Existing words", edit: true)
        let existing = currentEditor()
        let queue = ManualQueue()
        canvas.scheduleAfterInteraction = queue.schedule
        let linked = existing
        let closedPanels = RecordingPanels()
        closedPanels.staysOpen = false
        linked.editLink(relativeTo: linked, presenter: closedPanels)
        #expect(!linked.hasPendingRangeAction, "A retained closed link panel is not a pending range action")
        let closingID = session.document.items.last!.id
        replace(linked, with: " ")
        window.makeFirstResponder(canvas)
        canvas.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: linked))
        queue.runPending()
        #expect(linked.superview == nil && !session.document.items.contains { $0.id == closingID },
               "Focus dismissal after a closed link panel retires the editor and its empty object")
    }

    @MainActor @Test
    func droppingRichTextCanReplaceAnEmptyObject() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-text-defaults-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let canvas = makeTestEaselCanvas(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        func currentEditor() -> EaselStyledTextView { canvas.subviews.compactMap { $0 as? EaselStyledTextView }.first! }
        func replace(_ editor: EaselStyledTextView, with string: String) {
            editor.textStorage?.setAttributedString(EaselTextAppearance.attributed(string, style: editor.objectStyle, color: editor.objectColor))
            editor.didChangeText()
        }
        canvas.insert(kind: .text, edit: true)
        replace(currentEditor(), with: " ")
        let itemCount = session.document.items.count, replacedID = session.document.items.last!.id
        let drop = CanvasTextDrop(); drop.draggingDestinationWindow = window
        defer { drop.draggingPasteboard.releaseGlobally() }
        try EaselStyledText(text: "Replacement drop", style: .init(), color: "#252525").write(to: drop.draggingPasteboard)
        #expect(canvas.performDragOperation(drop), "A successful rich-text drop reports success when it first removes an empty editor")
        #expect(session.document.items.count == itemCount && session.document.items.last!.text == "Replacement drop" &&
               !session.document.items.contains { $0.id == replacedID }, "Replacement drop persists a new identity despite unchanged total item count")
    }

    @MainActor @Test
    func pastingAURLCreatesAnUndoableLocalLink() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-clipboard-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let canvas = makeTestEaselCanvas(session: session)
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.clearContents(); board.setString("https://example.com/clipboard", forType: .URL)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        #expect(canvas.readPasteboard(board), "Canvas accepts a URL-only external clipboard")
        #expect(session.document.items.count == 1 && session.document.items[0].kind == .link && session.document.items[0].url == "https://example.com/clipboard", "URL clipboard creates the original local link object")
        let id = session.document.id
        #expect(try! EaselStore(directory: directory).load(id).document.items == session.document.items, "Pasted link persists through the actual document store")
        try session.undo(); #expect(session.document.items.isEmpty, "Canvas URL paste is one durable undo")
    }

    @MainActor @Test
    func pastingAURLCanReplaceAnEmptyEditor() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-clipboard-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let canvas = makeTestEaselCanvas(session: session)
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.clearContents(); board.setString("https://example.com/clipboard", forType: .URL)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        canvas.insert(kind: .text, edit: true)
        guard let emptyEditor = window.firstResponder as? EaselStyledTextView else { throw CanvasFixtureError.missingEditor }
        emptyEditor.textStorage?.setAttributedString(EaselTextAppearance.attributed(" ", style: .init(), color: "#252525"))
        canvas.textDidChange(Notification(name: NSText.didChangeNotification, object: emptyEditor))
        let beforeReplacementCount = session.document.items.count, emptyID = session.document.items.last!.id
        #expect(canvas.readPasteboard(board), "URL-only paste reports success when it first disposes an empty editor")
        #expect(session.document.items.count == beforeReplacementCount && session.document.items.last!.kind == .link && !session.document.items.contains(where: { $0.id == emptyID }), "URL paste preserves explicit insertion success despite unchanged item count")
    }

    @MainActor @Test
    func pastingAURLOnACaptureAddsPlainAnnotationText() throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.clearContents(); board.setString("https://example.com/clipboard", forType: .URL)
        let memory = try EaselSession(inMemory: EaselDocument(id: UUID(), title: "Capture", createdAt: Date(), modifiedAt: Date()), assets: [:])
        let fixed = makeTestEaselCanvas(session: memory); fixed.fixedCanvasSize = NSSize(width: 400, height: 300)
        #expect(fixed.readPasteboard(board) && memory.document.items.first?.kind == .text, "CAP21 memory-only fixed canvas keeps URL paste as annotation text")
        #expect(memory.document.items.first?.text == "https://example.com/clipboard", "Capture annotation retains URL words without a browser object")
    }

    @MainActor @Test
    func anUnsupportedURLPastesAsInertText() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-clipboard-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let canvas = makeTestEaselCanvas(session: session)
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.clearContents(); board.setString("https://example.com/clipboard", forType: .URL)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        board.clearContents(); board.setString("javascript:alert(1)", forType: .URL)
        #expect(canvas.readPasteboard(board) && session.document.items.last?.kind == .text, "Unsupported URL scheme is inert text on the canvas")
    }
}
