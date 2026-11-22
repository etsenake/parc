import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct EaselCanvasTestsTextEditing {
    @MainActor @Test
    func insertingTextSelectsTheDefaultPrompt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-text-defaults-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        func currentEditor() -> EaselStyledTextView { canvas.subviews.compactMap { $0 as? EaselStyledTextView }.first! }
        canvas.insert(kind: .text, edit: true)
        let prompt = session.document.items[0], editor = currentEditor()
        #expect(prompt.text == "Start typing to enter text", "Text authoring inserts the recovered real default string")
        #expect(editor.selectedRange() == NSRange(location: 0, length: (prompt.text as NSString).length), "Default text is selected for replacement")
        #expect(editor.isContinuousSpellCheckingEnabled, "Native text spelling is enabled for the active editor")
    }

    @MainActor @Test
    func escapeKeepsTheUntouchedPromptSelected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-text-defaults-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        func currentEditor() -> EaselStyledTextView { canvas.subviews.compactMap { $0 as? EaselStyledTextView }.first! }
        canvas.insert(kind: .text, edit: true)
        let prompt = session.document.items[0], editor = currentEditor()
        _ = editor
        canvas.cancelOperation(nil)
        #expect(session.document.items == [prompt], "Untouched default text is content and survives dismissal")
        #expect(canvas.selection == [prompt.id], "Escape finishes text input and keeps the object selected")
    }

    @MainActor @Test
    func twoEscapesLeaveReturnWithoutAnEditorToReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-text-defaults-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        func currentEditor() -> EaselStyledTextView { canvas.subviews.compactMap { $0 as? EaselStyledTextView }.first! }
        canvas.insert(kind: .text, edit: true)
        canvas.cancelOperation(nil)
        canvas.cancelOperation(nil)
        let returnKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 36)!
        canvas.keyDown(with: returnKey)
        #expect(canvas.subviews.allSatisfy { !($0 is EaselStyledTextView) }, "A second Escape clears canvas selection")
    }

    @MainActor @Test
    func clearingATextObjectCoalescesWithTypingForUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-text-defaults-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let canvas = EaselCanvasView(session: session)
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
        let prompt = session.document.items[0], editor = currentEditor()
        _ = editor
        canvas.cancelOperation(nil)
        canvas.cancelOperation(nil)
        let returnKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 36)!
        canvas.keyDown(with: returnKey)
        canvas.selectAll(nil); window.makeFirstResponder(canvas); canvas.keyDown(with: returnKey)
        let clearing = currentEditor()
        replace(clearing, with: " \t\n\u{00a0}")
        let empty = session.document.items[0]
        #expect(empty.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Whitespace is saved while editing, before disposal")
        #expect(canvas.canFinishEditingForTransfer && canvas.finishEditingForTransfer(), "Transfer flush uses the same accepted final edit boundary")
        #expect(session.document.items.isEmpty, "Final edit removes whitespace-only original text")
        try session.undo()
        #expect(session.document.items == [prompt], "Empty cleanup coalesces with typing so undo restores the original nonempty object")
        try session.redo(); #expect(session.document.items.isEmpty, "Redo restores the complete empty-text deletion")
    }

    @MainActor @Test
    func enteringTextEditingSelectsTheExistingWords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-text-defaults-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        func currentEditor() -> EaselStyledTextView { canvas.subviews.compactMap { $0 as? EaselStyledTextView }.first! }
        canvas.insert(kind: .text, text: "Existing words", edit: true)
        let existing = currentEditor()
        #expect(existing.selectedRange().length == 14, "Keyboard/programmatic entry selects the existing original text")
    }

    @MainActor @Test
    func transferRefusesActiveComposition() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-text-defaults-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        func currentEditor() -> EaselStyledTextView { canvas.subviews.compactMap { $0 as? EaselStyledTextView }.first! }
        canvas.insert(kind: .text, text: "Existing words", edit: true)
        let existing = currentEditor()
        existing.setMarkedText("composing", selectedRange: NSRange(location: 0, length: 9), replacementRange: existing.selectedRange())
        #expect(!canvas.canFinishEditingForTransfer && !canvas.finishEditingForTransfer() && existing.hasMarkedText(), "Transfer refuses active composition without ending it")
        existing.unmarkText(); existing.didChangeText()
    }

    @MainActor @Test
    func transferRefusesAFailedEmptyTextSave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-text-defaults-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        func currentEditor() -> EaselStyledTextView { canvas.subviews.compactMap { $0 as? EaselStyledTextView }.first! }
        func replace(_ editor: EaselStyledTextView, with string: String) {
            editor.textStorage?.setAttributedString(EaselTextAppearance.attributed(string, style: editor.objectStyle, color: editor.objectColor))
            editor.didChangeText()
        }
        var errors = 0; canvas.onError = { _ in errors += 1 }
        canvas.insert(kind: .text, text: "Existing words", edit: true)
        let existing = currentEditor()
        replace(existing, with: " ")
        let saved = session.document, path = directory.appendingPathComponent("documents/" + saved.id.uuidString.lowercased() + ".json")
        let bytes = try Data(contentsOf: path)
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        #expect(!canvas.finishEditingForTransfer(), "Failed empty-object persistence refuses transfer completion")
        #expect(errors == 1 && session.document == saved && existing.superview === canvas, "Failed cleanup preserves document and the original native editor")
        try FileManager.default.removeItem(at: path); try bytes.write(to: path)
    }

    @MainActor @Test
    func replacementRefusesAFailedEmptyTextSave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-text-defaults-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        func currentEditor() -> EaselStyledTextView { canvas.subviews.compactMap { $0 as? EaselStyledTextView }.first! }
        func replace(_ editor: EaselStyledTextView, with string: String) {
            editor.textStorage?.setAttributedString(EaselTextAppearance.attributed(string, style: editor.objectStyle, color: editor.objectColor))
            editor.didChangeText()
        }
        var errors = 0; canvas.onError = { _ in errors += 1 }
        canvas.insert(kind: .text, text: "Existing words", edit: true)
        let existing = currentEditor()
        replace(existing, with: " ")
        let saved = session.document, path = directory.appendingPathComponent("documents/" + saved.id.uuidString.lowercased() + ".json")
        let bytes = try Data(contentsOf: path)
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        #expect(!canvas.finishEditingForTransfer(), "Failed empty-object persistence refuses transfer completion")
        canvas.insert(kind: .rectangle)
        #expect(errors == 2 && session.document == saved, "A failed final edit also refuses replacement insertion")
        try FileManager.default.removeItem(at: path); try bytes.write(to: path)
    }

    @MainActor @Test
    func anInterveningTextUpdateWinsOverAnOldEditor() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-text-defaults-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let canvas = EaselCanvasView(session: session)
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
        let stale = currentEditor()
        try session.perform("Concurrent text") { $0.items[0].text = "Latest original text"; $0.items[0].richText = nil }
        replace(stale, with: "stale replacement")
        #expect(session.document.items[0].text == "Latest original text" && stale.string == "Latest original text", "Late native edit refuses and reloads an intervening original-content change")
        #expect(canvas.finishEditingForTransfer(), "Nonempty editor transfer finalization succeeds")
    }

    @MainActor @Test
    func doubleClickCreatesAnEditablePointTextPrompt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-text-defaults-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        func currentEditor() -> EaselStyledTextView { canvas.subviews.compactMap { $0 as? EaselStyledTextView }.first! }
        func replace(_ editor: EaselStyledTextView, with string: String) {
            editor.textStorage?.setAttributedString(EaselTextAppearance.attributed(string, style: editor.objectStyle, color: editor.objectColor))
            editor.didChangeText()
        }
        let insertionPoint = NSPoint(x: 40, y: 450)
        let doubleClick = NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(insertionPoint, to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 1)!
        canvas.mouseDown(with: doubleClick)
        #expect(session.document.items.last!.text == EaselTextEditing.defaultText && currentEditor().selectedRange().length == 26,
               "Blank-canvas double click authors and selects the actual default prompt")
        let created = session.document.items.last!
        #expect(created.frame.x == 40 && created.frame.y == 436 && created.textStyle?.autoWidth == true &&
               created.frame.width > 120 && created.frame.width < 280 && created.frame.height < 40,
               "Blank-canvas insertion makes point text fitted to the prompt at the click")
    }
}
