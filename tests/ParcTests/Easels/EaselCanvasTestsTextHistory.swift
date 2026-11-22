import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct EaselCanvasTestsTextHistory {
    private typealias CanvasFixtureError = EaselCanvasTestsSupport.CanvasFixtureError

    @MainActor @Test
    func aSeparateDocumentEditRetainsItsOwnUndoBoundary() throws {
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
        let shared = try EaselSession(inMemory: EaselDocument(id: UUID(), title: "Shared", createdAt: now, modifiedAt: now, items: [one]), assets: [:])
        let sharedCanvas = makeTestEaselCanvas(session: shared)
        window.contentView = sharedCanvas; sharedCanvas.selectAll(nil); window.makeFirstResponder(sharedCanvas); sharedCanvas.keyDown(with: enter)
        let sharedEditor = sharedCanvas.subviews.compactMap { $0 as? EaselStyledTextView }.first!
        sharedEditor.localUndo.groupsByEvent = false
        sharedEditor.localUndo.beginUndoGrouping(); sharedCanvas.setTextFill(.contentHugging); sharedEditor.localUndo.endUndoGrouping()
        try shared.perform("Other owner title") { $0.title = "Other owner" }
        let external = shared.document
        sharedEditor.undo(nil)
        #expect(shared.document == external, "A native fill inverse refuses an intervening unrelated shared-owner transaction")
        sharedEditor.localUndo.beginUndoGrouping(); sharedEditor.insertText("After external", replacementRange: NSRange(location: 0, length: sharedEditor.string.utf16.count)); sharedEditor.localUndo.endUndoGrouping()
        #expect(sharedCanvas.finishEditingForTransfer(), "Edited shared canvas finishes without replacing another owner's state")
        sharedCanvas.undo(nil)
        #expect(shared.document.items == external.items && shared.document.title == "Other owner", "Later native edits start a fresh durable group after an external transaction")
        sharedCanvas.undo(nil)
        #expect(shared.document.title == "Shared" && shared.document.items[0].resolvedTextStyle.resolvedFill == .contentHugging, "The external transaction retains its own document history boundary")
    }

    @MainActor @Test
    func insertingAnInlineImageKeepsTheOriginalTextObject() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-inline-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let item = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 100), text: "Before After")
        try session.perform("Seed") { $0.items = [item] }
        let canvas = makeTestEaselCanvas(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        var errors = 0; canvas.onError = { _ in errors += 1 }
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(NSPoint(x: 60, y: 45), to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 1)!
        canvas.mouseDown(with: event)
        guard let editor = window.firstResponder as? EaselStyledTextView else { throw CanvasFixtureError.missingEditor }
        editor.localUndo.groupsByEvent = false; editor.setSelectedRange(NSRange(location: 7, length: 5))
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        editor.localUndo.beginUndoGrouping(); let inserted = try editor.insertImage(png); editor.localUndo.endUndoGrouping()
        #expect(inserted && errors == 0, "Real canvas editor commits native attachment without a clipboard surrogate")
        #expect(session.document.items.count == 1 && session.document.items[0].id == item.id && session.document.items[0].kind == .text, "Inline insertion keeps the original text-object identity")
        #expect(session.document.items[0].richText?.runs.contains(where: { $0.attributes.image?.data == png }) == true, "Native edit delegate persists real original bytes in the shared document")
    }

    @MainActor @Test
    func reopeningAnEaselRestoresTheInlineImageRange() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-inline-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let item = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 100), text: "Before After")
        try session.perform("Seed") { $0.items = [item] }
        let canvas = makeTestEaselCanvas(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        var errors = 0; canvas.onError = { _ in errors += 1 }
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(NSPoint(x: 60, y: 45), to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 1)!
        canvas.mouseDown(with: event)
        guard let editor = window.firstResponder as? EaselStyledTextView else { throw CanvasFixtureError.missingEditor }
        editor.localUndo.groupsByEvent = false; editor.setSelectedRange(NSRange(location: 7, length: 5))
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        editor.localUndo.beginUndoGrouping(); let inserted = try editor.insertImage(png); editor.localUndo.endUndoGrouping()
        #expect(inserted && errors == 0, "Real canvas editor commits native attachment without a clipboard surrogate")
        #expect(try! EaselStore(directory: directory).load(session.document.id).document == session.document, "Actual disk reopen restores the same inline image range")
    }

    @MainActor @Test
    func nativeImageUndoAndRedoUpdateTheSavedDocument() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-inline-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let item = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 100), text: "Before After")
        try session.perform("Seed") { $0.items = [item] }
        let canvas = makeTestEaselCanvas(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        var errors = 0; canvas.onError = { _ in errors += 1 }
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(NSPoint(x: 60, y: 45), to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 1)!
        canvas.mouseDown(with: event)
        guard let editor = window.firstResponder as? EaselStyledTextView else { throw CanvasFixtureError.missingEditor }
        editor.localUndo.groupsByEvent = false; editor.setSelectedRange(NSRange(location: 7, length: 5))
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        editor.localUndo.beginUndoGrouping(); let inserted = try editor.insertImage(png); editor.localUndo.endUndoGrouping()
        #expect(inserted && errors == 0, "Real canvas editor commits native attachment without a clipboard surrogate")
        #expect(editor.localUndo.canUndo, "Session notification preserves local native image undo")
        editor.undo(nil)
        #expect(session.document.items[0].text == item.text && session.document.items[0].richText?.runs.allSatisfy({ $0.attributes.image == nil }) != false, "Native editor undo commits restored text through the same session")
        editor.redo(nil)
        #expect(session.document.items[0].richText?.runs.contains(where: { $0.attributes.image?.data == png }) == true, "Native editor redo restores durable original image bytes")
    }

    @MainActor @Test
    func aRefusedInlineImageSaveRestoresTheEditor() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-inline-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let item = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 100), text: "Before After")
        try session.perform("Seed") { $0.items = [item] }
        let canvas = makeTestEaselCanvas(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        var errors = 0; canvas.onError = { _ in errors += 1 }
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(NSPoint(x: 60, y: 45), to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 1)!
        canvas.mouseDown(with: event)
        guard let editor = window.firstResponder as? EaselStyledTextView else { throw CanvasFixtureError.missingEditor }
        editor.localUndo.groupsByEvent = false; editor.setSelectedRange(NSRange(location: 7, length: 5))
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        editor.localUndo.beginUndoGrouping(); let inserted = try editor.insertImage(png); editor.localUndo.endUndoGrouping()
        #expect(inserted && errors == 0, "Real canvas editor commits native attachment without a clipboard surrogate")
        var cleanup: (() -> Void)?
        editor.scheduleHistoryCleanup = { cleanup = $0 }
        let saved = session.document, path = directory.appendingPathComponent("documents/" + saved.id.uuidString.lowercased() + ".json")
        let bytes = try Data(contentsOf: path)
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        editor.setSelectedRange(NSRange(location: editor.attributedString().length, length: 0))
        editor.localUndo.beginUndoGrouping(); let refused = try editor.insertImage(png); editor.localUndo.endUndoGrouping()
        #expect(!refused && errors == 1 && session.document == saved, "Real persistence refusal rejects insertion and preserves original document")
        cleanup?()
        #expect(editor.string == saved.items[0].text && !editor.localUndo.canUndo, "Failed-save rollback restores the real editor and retires uncommitted local undo")
        try FileManager.default.removeItem(at: path); try bytes.write(to: path)
        #expect(!window.isVisible, "Inline native component never displays a window")
    }
}
