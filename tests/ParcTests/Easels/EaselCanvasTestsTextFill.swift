import AppKit
import Testing
@testable import ParcCore
@testable import ParcEasels

struct EaselCanvasTestsTextFill {
    @MainActor @Test
    func textFillChangesOnlyTheSelectedObjectsStyle() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-fill-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create(title: "Fill component")
        let one = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 180), text: "Longer text\nShort")
        let two = EaselItem(kind: .text, frame: .init(x: 350, y: 30, width: 200, height: 180), text: "Other", textStyle: .init(family: .fancy, size: .h2))
        try session.perform("Seed") { $0.items = [one, two] }
        let canvas = makeTestEaselCanvas(session: session)
        canvas.selectAll(nil); canvas.setTextFill(.contentHugging)
        #expect(session.document.items.allSatisfy { $0.resolvedTextStyle.resolvedFill == .contentHugging }, "One real canvas operation fills the selected text objects")
        #expect(session.document.items.map(\.frame) == [one.frame, two.frame] && session.document.items.map(\.text) == [one.text, two.text], "Fill changes neither authored text nor geometry")
    }

    @MainActor @Test
    func textFillSurvivesReopeningTheDocument() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-fill-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create(title: "Fill component")
        let one = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 180), text: "Longer text\nShort")
        let two = EaselItem(kind: .text, frame: .init(x: 350, y: 30, width: 200, height: 180), text: "Other", textStyle: .init(family: .fancy, size: .h2))
        try session.perform("Seed") { $0.items = [one, two] }
        let canvas = makeTestEaselCanvas(session: session)
        canvas.selectAll(nil); canvas.setTextFill(.contentHugging)
        #expect(try! EaselStore(directory: directory).load(session.document.id).document == session.document, "Filled styles survive real atomic save and reopen")
    }

    @MainActor @Test
    func undoAndRedoRestoreTheWholeTextFillChange() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-fill-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create(title: "Fill component")
        let one = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 180), text: "Longer text\nShort")
        let two = EaselItem(kind: .text, frame: .init(x: 350, y: 30, width: 200, height: 180), text: "Other", textStyle: .init(family: .fancy, size: .h2))
        try session.perform("Seed") { $0.items = [one, two] }
        let canvas = makeTestEaselCanvas(session: session)
        canvas.selectAll(nil); canvas.setTextFill(.contentHugging)
        try session.undo()
        #expect(session.document.items == [one, two], "One document undo restores every original style")
        try session.redo()
        #expect(session.document.items.allSatisfy { $0.resolvedTextStyle.resolvedFill == .contentHugging }, "Document redo restores whole-object fill")
    }

    @MainActor @Test
    func aFailedFillSavePreservesTheOriginalDocument() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-fill-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create(title: "Fill component")
        let one = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 180), text: "Longer text\nShort")
        let two = EaselItem(kind: .text, frame: .init(x: 350, y: 30, width: 200, height: 180), text: "Other", textStyle: .init(family: .fancy, size: .h2))
        try session.perform("Seed") { $0.items = [one, two] }
        let canvas = makeTestEaselCanvas(session: session)
        canvas.selectAll(nil); canvas.setTextFill(.contentHugging)
        let saved = session.document
        try FileManager.default.removeItem(at: directory.appendingPathComponent("documents"))
        try Data().write(to: directory.appendingPathComponent("documents"))
        canvas.setTextFill(.none)
        #expect(session.document == saved, "A refused durable fill edit retains exact saved objects")
    }

    @MainActor @Test
    func captureCanvasRendersSavedTextFill() throws {
        let one = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 180), text: "Longer text\nShort")
        let now = Date()
        let memory = try EaselSession(inMemory: EaselDocument(id: UUID(), title: "Memory fill", createdAt: now, modifiedAt: now, items: [one]), assets: [:])
        let captureCanvas = makeTestEaselCanvas(session: memory)
        captureCanvas.selectAll(nil); captureCanvas.setTextFill(.contentHugging)
        let output = try captureCanvas.renderImage(pixelSize: NSSize(width: 600, height: 240), backingScale: 1)
        #expect(output.width == 600 && memory.document.items[0].resolvedTextStyle.resolvedFill == .contentHugging, "CAP21 memory canvas renders the same fill without a saved Easel or browser")
    }

    @MainActor @Test
    func changingFillPreservesEditorFocusAndSelection() throws {
        let one = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 180), text: "Longer text\nShort")
        let now = Date()
        let memory = try EaselSession(inMemory: EaselDocument(id: UUID(), title: "Memory fill", createdAt: now, modifiedAt: now, items: [one]), assets: [:])
        let captureCanvas = makeTestEaselCanvas(session: memory)
        captureCanvas.selectAll(nil); captureCanvas.setTextFill(.contentHugging)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = captureCanvas
        defer { window.contentView = nil; window.close() }
        captureCanvas.selectAll(nil)
        let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 36)!
        window.makeFirstResponder(captureCanvas); captureCanvas.keyDown(with: enter)
        let editor = captureCanvas.subviews.compactMap { $0 as? EaselStyledTextView }.first!
        editor.localUndo.groupsByEvent = false
        editor.localUndo.beginUndoGrouping()
        editor.insertText("Retyped text", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        editor.localUndo.endUndoGrouping()
        let selectedRange = editor.selectedRange()
        editor.localUndo.beginUndoGrouping(); captureCanvas.setTextFill(.none); editor.localUndo.endUndoGrouping()
        #expect(window.firstResponder === editor && editor.selectedRange() == selectedRange, "Fill returns the original editor focus and preserves its native selection")
    }

    @MainActor @Test
    func undoingAndRedoingFillPreservesTheNewText() throws {
        let one = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 180), text: "Longer text\nShort")
        let now = Date()
        let memory = try EaselSession(inMemory: EaselDocument(id: UUID(), title: "Memory fill", createdAt: now, modifiedAt: now, items: [one]), assets: [:])
        let captureCanvas = makeTestEaselCanvas(session: memory)
        captureCanvas.selectAll(nil); captureCanvas.setTextFill(.contentHugging)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = captureCanvas
        defer { window.contentView = nil; window.close() }
        captureCanvas.selectAll(nil)
        let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 36)!
        window.makeFirstResponder(captureCanvas); captureCanvas.keyDown(with: enter)
        let editor = captureCanvas.subviews.compactMap { $0 as? EaselStyledTextView }.first!
        editor.localUndo.groupsByEvent = false
        editor.localUndo.beginUndoGrouping()
        editor.insertText("Retyped text", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        editor.localUndo.endUndoGrouping()
        let typed = memory.document.items[0].text
        editor.localUndo.beginUndoGrouping(); captureCanvas.setTextFill(.none); editor.localUndo.endUndoGrouping()
        editor.undo(nil)
        #expect(memory.document.items[0].resolvedTextStyle.resolvedFill == .contentHugging && memory.document.items[0].text == typed,
               "Native Undo reverses the latest fill before older typing")
        editor.redo(nil)
        #expect(memory.document.items[0].resolvedTextStyle.resolvedFill == .none && memory.document.items[0].text == typed,
               "Native Redo restores fill without rewriting text")
    }

    @MainActor @Test
    func concurrentStyleChangesInvalidateNativeFillUndo() throws {
        let one = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 180), text: "Longer text\nShort")
        let now = Date()
        let memory = try EaselSession(inMemory: EaselDocument(id: UUID(), title: "Memory fill", createdAt: now, modifiedAt: now, items: [one]), assets: [:])
        let captureCanvas = makeTestEaselCanvas(session: memory)
        captureCanvas.selectAll(nil); captureCanvas.setTextFill(.contentHugging)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = captureCanvas
        defer { window.contentView = nil; window.close() }
        captureCanvas.selectAll(nil)
        let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 36)!
        window.makeFirstResponder(captureCanvas); captureCanvas.keyDown(with: enter)
        let editor = captureCanvas.subviews.compactMap { $0 as? EaselStyledTextView }.first!
        editor.localUndo.groupsByEvent = false
        editor.localUndo.beginUndoGrouping(); captureCanvas.setTextFill(.none); editor.localUndo.endUndoGrouping()
        try memory.perform("Concurrent style") { $0.items[0].textStyle?.family = .mono }
        let concurrent = memory.document
        editor.undo(nil)
        #expect(memory.document == concurrent, "Stale native fill undo refuses a different owner's replacement style")
    }

    @MainActor @Test
    func localUndoAndRedoKeepFillInOrderWithTextEdits() throws {
        let one = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 180), text: "Longer text\nShort")
        let now = Date()
        let memory = try EaselSession(inMemory: EaselDocument(id: UUID(), title: "Memory fill", createdAt: now, modifiedAt: now, items: [one]), assets: [:])
        let captureCanvas = makeTestEaselCanvas(session: memory)
        captureCanvas.selectAll(nil); captureCanvas.setTextFill(.contentHugging)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = captureCanvas
        defer { window.contentView = nil; window.close() }
        captureCanvas.selectAll(nil)
        let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 36)!
        window.makeFirstResponder(captureCanvas); captureCanvas.keyDown(with: enter)
        let editor = captureCanvas.subviews.compactMap { $0 as? EaselStyledTextView }.first!
        editor.localUndo.groupsByEvent = false
        let history = try EaselSession(inMemory: EaselDocument(id: UUID(), title: "History", createdAt: now, modifiedAt: now, items: [one]), assets: [:])
        let historyCanvas = makeTestEaselCanvas(session: history)
        window.contentView = historyCanvas; historyCanvas.selectAll(nil); window.makeFirstResponder(historyCanvas); historyCanvas.keyDown(with: enter)
        let native = historyCanvas.subviews.compactMap { $0 as? EaselStyledTextView }.first!
        native.localUndo.groupsByEvent = false
        func action(_ change: () -> Void) {
            native.localUndo.beginUndoGrouping(); change(); native.localUndo.endUndoGrouping()
        }
        action { native.insertText("First typing", replacementRange: NSRange(location: 0, length: native.string.utf16.count)) }
        action { historyCanvas.setTextFill(.contentHugging) }
        action { native.insertText(" Later", replacementRange: NSRange(location: native.string.utf16.count, length: 0)) }
        native.setSelectedRange(NSRange(location: 0, length: 5))
        action { native.toggle(.underline) }
        native.undo(nil); native.undo(nil)
        #expect(history.document.items[0].text == "First typing", "Later native range and typing inverses retain the earlier fill action")
        native.undo(nil)
        #expect(history.document.items[0].resolvedTextStyle.resolvedFill == .none, "Native fill undo remains ordered after later typing and range boundaries")
        native.redo(nil)
        #expect(history.document.items[0].resolvedTextStyle.resolvedFill == .contentHugging, "Native redo restores fill in the same durable editing group")
        native.undo(nil); native.undo(nil)
        #expect(history.document.items[0].text == one.text && history.document.items[0].resolvedTextStyle.resolvedFill == .none, "Complete native undo restores original content and fill")
    }

    @MainActor @Test(arguments: [false, true])
    func documentUndoRestoresTextAfterLocalFillEdits(_ undoEdits: Bool) throws {
        let one = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 180), text: "Longer text\nShort")
        let now = Date()
        let memory = try EaselSession(inMemory: EaselDocument(id: UUID(), title: "Memory fill", createdAt: now, modifiedAt: now, items: [one]), assets: [:])
        let captureCanvas = makeTestEaselCanvas(session: memory)
        captureCanvas.selectAll(nil); captureCanvas.setTextFill(.contentHugging)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = captureCanvas
        defer { window.contentView = nil; window.close() }
        captureCanvas.selectAll(nil)
        let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 36)!
        window.makeFirstResponder(captureCanvas); captureCanvas.keyDown(with: enter)
        let editor = captureCanvas.subviews.compactMap { $0 as? EaselStyledTextView }.first!
        editor.localUndo.groupsByEvent = false
        let history = try EaselSession(inMemory: EaselDocument(id: UUID(), title: "History", createdAt: now, modifiedAt: now, items: [one]), assets: [:])
        let historyCanvas = makeTestEaselCanvas(session: history)
        window.contentView = historyCanvas; historyCanvas.selectAll(nil); window.makeFirstResponder(historyCanvas); historyCanvas.keyDown(with: enter)
        let native = historyCanvas.subviews.compactMap { $0 as? EaselStyledTextView }.first!
        native.localUndo.groupsByEvent = false
        func action(_ change: () -> Void) {
            native.localUndo.beginUndoGrouping(); change(); native.localUndo.endUndoGrouping()
        }
        action { native.insertText("First typing", replacementRange: NSRange(location: 0, length: native.string.utf16.count)) }
        action { historyCanvas.setTextFill(.contentHugging) }
        action { native.insertText(" Later", replacementRange: NSRange(location: native.string.utf16.count, length: 0)) }
        native.setSelectedRange(NSRange(location: 0, length: 5))
        action { native.toggle(.underline) }
        if undoEdits {
            native.undo(nil); native.undo(nil)
            native.undo(nil)
            native.redo(nil)
            native.undo(nil); native.undo(nil)
        }
        #expect(historyCanvas.finishEditingForTransfer(), "The original hidden editor closes through its real lifecycle")
        historyCanvas.undo(nil)
        #expect(history.document.items == [one], "Document undo after normal or natively-undone editing restores the original object without replaying fill inverses")
        historyCanvas.redo(nil)
        #expect(history.document.items[0].resolvedTextStyle.resolvedFill == (undoEdits ? .none : .contentHugging), "Document redo preserves the editor's final fill state")
    }
}
