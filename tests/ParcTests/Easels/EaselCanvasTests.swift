import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor private final class RecordedPanel: EaselPanelHandle {
    var isOpen = true
    func close() { isOpen = false }
}

@MainActor private final class RecordingPanels: EaselPanelPresenting {
    var links: [EaselLinkRequest] = []
    var sizes: [EaselTextSizeRequest] = []
    var staysOpen = true
    private func handle() -> EaselPanelHandle {
        let panel = RecordedPanel()
        panel.isOpen = staysOpen
        return panel
    }
    func presentLinkEditor(_ request: EaselLinkRequest) -> EaselPanelHandle? { links.append(request); return handle() }
    func presentTextSizeEditor(_ request: EaselTextSizeRequest) -> EaselPanelHandle? { sizes.append(request); return handle() }
    func hoverLink(_ request: EaselLinkHoverRequest?) {}
}

@MainActor private final class FormatKeyWindow: NSWindow {
    var key = true
    override var isKeyWindow: Bool { key }
}

@MainActor private final class CapturedCanvasMenu: EaselCanvasMenuPresenting {
    var rows: [EaselMenuRow] = []
    var isOpen = false
    func present(_ rows: [EaselMenuRow], in host: NSView, anchor: NSRect, keyboard: Bool, label: String) {
        self.rows = rows; isOpen = true
    }
    func close(animated: Bool) { isOpen = false }
}

@MainActor private final class CanvasTextDrop: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .copy
    var draggingLocation = NSPoint.zero
    var draggedImageLocation = NSPoint.zero
    nonisolated var draggedImage: NSImage? { nil }
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSource: Any?
    var draggingSequenceNumber = 1
    var draggingFormation = NSDraggingFormation.default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight = NSSpringLoadingHighlight.none
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    func resetSpringLoading() {}
}

struct EaselCanvasTests {
    private enum CanvasFixtureError: Error { case missingEditor }

    @MainActor
    private final class ManualQueue {
        private var work: [() -> Void] = []

        func schedule(_ job: @escaping () -> Void) { work.append(job) }

        func runPending() {
            let current = work
            work.removeAll()
            current.forEach { $0() }
        }
    }

    @MainActor
    private func contextMenu(_ canvas: EaselCanvasView, _ event: NSEvent) -> [EaselMenuRow] {
        let presenter = CapturedCanvasMenu()
        canvas.arrangeState.menu = presenter
        canvas.rightMouseDown(with: event)
        return presenter.rows
    }

    @MainActor
    private func menuRow(_ rows: [EaselMenuRow], _ title: String) throws -> EaselMenuRow {
        try #require(rows.first { $0.title == title })
    }

    @MainActor
    private final class Board {
        let directory: URL
        let session: EaselSession
        let canvas: EaselCanvasView
        let window: NSWindow
        let a = EaselItem(kind: .rectangle, frame: .init(x: 30, y: 30, width: 50, height: 50))
        let b = EaselItem(kind: .circle, frame: .init(x: 130, y: 130, width: 50, height: 50))
        let c = EaselItem(kind: .text, frame: .init(x: 500, y: 30, width: 150, height: 80), text: "Native text")
        var errors = 0

        init() throws {
            _ = NSApplication.shared
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            session = try EaselStore(directory: directory).create()
            let originals = [a, b, c]
            try session.perform("Seed") { $0.items = originals }
            canvas = EaselCanvasView(session: session)
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = canvas
            canvas.onError = { [weak self] _ in self?.errors += 1 }
        }

        func close() {
            window.contentView = nil
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }

        func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double, flags: NSEvent.ModifierFlags = [], clicks: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(NSPoint(x: x, y: y), to: nil), modifierFlags: flags,
                               timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        func key(_ code: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }
        func marquee(_ x: Double, _ y: Double, _ endX: Double, _ endY: Double, flags: NSEvent.ModifierFlags = []) {
            canvas.mouseDown(with: mouse(.leftMouseDown, x, y, flags: flags))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, endX, endY, flags: flags))
            canvas.mouseUp(with: mouse(.leftMouseUp, endX, endY, flags: flags))
        }
    }

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
    func aMovePreservesEditsToUnrelatedObjects() throws {
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
        try session.undo()
        #expect(session.document.items[0].frame == board.a.frame && session.document.items[1].color == "#112233", "Native group move is one independent undo transaction")
    }

    @MainActor @Test
    func duplicateFromTheMenuCreatesNewIdentitiesAndUndoesInOneStep() throws {
        let board = try Board()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        let a = board.a, c = board.c
        canvas.selection = [a.id, c.id]
        let duplicate = try menuRow(contextMenu(canvas, board.mouse(.rightMouseDown, 40, 40)), "Duplicate")
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
        let staleDuplicate = try menuRow(contextMenu(canvas, board.mouse(.rightMouseDown, 40, 40)), "Duplicate")
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
        let saveDuplicate = try menuRow(contextMenu(canvas, board.mouse(.rightMouseDown, 40, 40)), "Duplicate")
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
    func returnAndEscapeMoveFocusBetweenCanvasAndEditor() throws {
        let board = try Board()
        defer { board.close() }
        let canvas = board.canvas
        let window = board.window
        canvas.cancelOperation(nil)
        canvas.mouseDown(with: board.mouse(.leftMouseDown, 530, 55)); canvas.mouseUp(with: board.mouse(.leftMouseUp, 530, 55))
        canvas.keyDown(with: board.key(36))
        #expect(window.firstResponder is EaselStyledTextView, "Return on the original text object retains the real native range editor")
        if let text = window.firstResponder as? EaselStyledTextView {
            #expect(canvas.textView(text, doCommandBy: #selector(NSResponder.cancelOperation(_:))), "Native editor Escape uses its existing delegate")
        }
        #expect(window.firstResponder === canvas, "Editor Escape returns focus to the same canvas")
    }

    @MainActor @Test
    func detachingTheCanvasRetiresItsMenuActions() throws {
        let board = try Board()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        let window = board.window
        canvas.selectAll(nil)
        let detachMenu = contextMenu(canvas, board.mouse(.rightMouseDown, 40, 40))
        let detachDuplicate = try menuRow(detachMenu, "Duplicate")
        #expect(detachDuplicate.isEnabled, "Current original menu target is valid before detachment")
        window.contentView = nil
        let beforePaste = session.document
        detachDuplicate.perform?()
        #expect(session.document == beforePaste, "Detached canvas retires its exact-window menu target")
        try menuRow(detachMenu, "Paste").perform?()
        try menuRow(detachMenu, "Paste as Plain Text").perform?()
        #expect(session.document == beforePaste, "Stale paste dispatch leaves exact document unchanged without reading personal clipboard")
        #expect(!window.isVisible, "Component window was never displayed")
    }

    @MainActor @Test
    func formatMenuAndToolbarApplyTheSameBoldAndUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-format-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 600, y: 400, width: 60, height: 60))
        try session.perform("Seed") { $0.items = [shape] }
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = FormatKeyWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        var items: [TextFormatCommand: NSMenuItem] = [:]
        TextFormatMenu.add(to: NSMenu(title: "Edit")) { item, command in items[command] = item }
        func owner() -> NSResponder? {
            var responder = window.firstResponder
            while let current = responder, !current.responds(to: TextFormatCommand.action) { responder = current.nextResponder }
            return responder
        }
        func validate(_ command: TextFormatCommand) -> Bool { (owner() as? NSMenuItemValidation)?.validateMenuItem(items[command]!) ?? false }
        func state(_ command: TextFormatCommand) -> NSControl.StateValue { _ = validate(command); return items[command]!.state }
        func perform(_ command: TextFormatCommand) { _ = window.firstResponder?.tryToPerform(TextFormatCommand.action, with: items[command]!) }
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        #expect(canvas.insert(kind: .text, text: "Format me", edit: true), "A text object enters native editing")
        let editor = try #require(canvas.editor)
        editor.localUndo.groupsByEvent = false
        func run(_ command: TextFormatCommand) { editor.localUndo.beginUndoGrouping(); perform(command); editor.localUndo.endUndoGrouping() }
        let all = NSRange(location: 0, length: 9)
        #expect(window.firstResponder === editor && owner() === canvas && editor.selectedRange() == all, "The canvas owns formatting above its editor")
        #expect(validate(.bold) && state(.bold) == .off, "Bold is available without a checkmark on plain text")
        run(.bold)
        let menuBold = NSAttributedString(attributedString: editor.attributedString()), menuUndo = editor.localUndo.undoActionName
        #expect(editor.hasEmphasis(.bold) && state(.bold) == .on && menuUndo == "Bold", "Menu Bold formats the selection and shows its checkmark")
        editor.undo(nil)
        editor.localUndo.beginUndoGrouping(); canvas.performSelectionToolbar(.bold); editor.localUndo.endUndoGrouping()
        #expect(editor.attributedString().isEqual(to: menuBold) && editor.localUndo.undoActionName == menuUndo, "Menu Bold and the selection toolbar's B button produce the same text and Undo")
        run(.bold)
        #expect(!editor.hasEmphasis(.bold) && state(.bold) == .off, "Menu Bold toggles back off")
    }

    @MainActor @Test(arguments: [TextFormatCommand.italic, .underline, .strikethrough])
    func emphasisMenuTogglesAndChecksItsRange(_ command: TextFormatCommand) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-format-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 600, y: 400, width: 60, height: 60))
        try session.perform("Seed") { $0.items = [shape] }
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = FormatKeyWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        var items: [TextFormatCommand: NSMenuItem] = [:]
        TextFormatMenu.add(to: NSMenu(title: "Edit")) { item, command in items[command] = item }
        func owner() -> NSResponder? {
            var responder = window.firstResponder
            while let current = responder, !current.responds(to: TextFormatCommand.action) { responder = current.nextResponder }
            return responder
        }
        func validate(_ command: TextFormatCommand) -> Bool { (owner() as? NSMenuItemValidation)?.validateMenuItem(items[command]!) ?? false }
        func state(_ command: TextFormatCommand) -> NSControl.StateValue { _ = validate(command); return items[command]!.state }
        func perform(_ command: TextFormatCommand) { _ = window.firstResponder?.tryToPerform(TextFormatCommand.action, with: items[command]!) }
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        #expect(canvas.insert(kind: .text, text: "Format me", edit: true), "A text object enters native editing")
        let editor = try #require(canvas.editor)
        editor.localUndo.groupsByEvent = false
        func run(_ command: TextFormatCommand) { editor.localUndo.beginUndoGrouping(); perform(command); editor.localUndo.endUndoGrouping() }
        run(command)
        #expect(editor.hasEmphasis(command.emphasis!) && validate(command) && items[command]!.state == .on, "Menu \(command.title) formats and checks")
        run(command)
        #expect(!editor.hasEmphasis(command.emphasis!), "Menu \(command.title) toggles off")
    }

    @MainActor @Test
    func formatMenuAndToolbarShareTheSameSizeSteps() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-format-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 600, y: 400, width: 60, height: 60))
        try session.perform("Seed") { $0.items = [shape] }
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = FormatKeyWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        var items: [TextFormatCommand: NSMenuItem] = [:]
        TextFormatMenu.add(to: NSMenu(title: "Edit")) { item, command in items[command] = item }
        func owner() -> NSResponder? {
            var responder = window.firstResponder
            while let current = responder, !current.responds(to: TextFormatCommand.action) { responder = current.nextResponder }
            return responder
        }
        func validate(_ command: TextFormatCommand) -> Bool { (owner() as? NSMenuItemValidation)?.validateMenuItem(items[command]!) ?? false }
        func state(_ command: TextFormatCommand) -> NSControl.StateValue { _ = validate(command); return items[command]!.state }
        func perform(_ command: TextFormatCommand) { _ = window.firstResponder?.tryToPerform(TextFormatCommand.action, with: items[command]!) }
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        #expect(canvas.insert(kind: .text, text: "Format me", edit: true), "A text object enters native editing")
        let editor = try #require(canvas.editor)
        editor.localUndo.groupsByEvent = false
        func run(_ command: TextFormatCommand) { editor.localUndo.beginUndoGrouping(); perform(command); editor.localUndo.endUndoGrouping() }
        #expect(validate(.bigger) && !validate(.smaller), "Body-size text offers only Bigger, like the selection toolbar")
        run(.bigger)
        let menuBigger = NSAttributedString(attributedString: editor.attributedString())
        #expect(validate(.smaller) && menuBigger.attribute(.font, at: 0, effectiveRange: nil) as? NSFont != EaselTextAppearance.font(EaselTextStyle()), "Bigger steps the selected text up a size")
        editor.undo(nil)
        editor.localUndo.beginUndoGrouping(); canvas.performSelectionToolbar(.larger); editor.localUndo.endUndoGrouping()
        #expect(editor.attributedString().isEqual(to: menuBigger), "Menu Bigger matches the selection toolbar's bigger button")
        run(.smaller)
        #expect(!validate(.smaller), "Smaller returns the text to body size")
    }

    @MainActor @Test
    func formatMenuAppliesAndChecksParagraphStyles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-format-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 600, y: 400, width: 60, height: 60))
        try session.perform("Seed") { $0.items = [shape] }
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = FormatKeyWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        var items: [TextFormatCommand: NSMenuItem] = [:]
        TextFormatMenu.add(to: NSMenu(title: "Edit")) { item, command in items[command] = item }
        func owner() -> NSResponder? {
            var responder = window.firstResponder
            while let current = responder, !current.responds(to: TextFormatCommand.action) { responder = current.nextResponder }
            return responder
        }
        func validate(_ command: TextFormatCommand) -> Bool { (owner() as? NSMenuItemValidation)?.validateMenuItem(items[command]!) ?? false }
        func state(_ command: TextFormatCommand) -> NSControl.StateValue { _ = validate(command); return items[command]!.state }
        func perform(_ command: TextFormatCommand) { _ = window.firstResponder?.tryToPerform(TextFormatCommand.action, with: items[command]!) }
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        #expect(canvas.insert(kind: .text, text: "Format me", edit: true), "A text object enters native editing")
        let editor = try #require(canvas.editor)
        editor.localUndo.groupsByEvent = false
        func run(_ command: TextFormatCommand) { editor.localUndo.beginUndoGrouping(); perform(command); editor.localUndo.endUndoGrouping() }
        #expect(!validate(.increaseIndent), "List indent waits for a list paragraph")
        run(.bulletedList)
        #expect(editor.paragraphKind() == .bullets && state(.bulletedList) == .on && validate(.increaseIndent), "Bulleted List applies, checks and admits indent")
        run(.increaseIndent)
        let nested = editor.attributedString().attribute(.paragraphStyle, at: editor.selectedRange().location, effectiveRange: nil) as? NSParagraphStyle
        #expect(nested?.textLists.count == 2, "Increase indents the list item like Tab")
        run(.decreaseIndent)
        let outdented = editor.attributedString().attribute(.paragraphStyle, at: editor.selectedRange().location, effectiveRange: nil) as? NSParagraphStyle
        #expect(outdented?.textLists.count == 1, "Decrease outdents the list item like Shift-Tab")
        run(.heading2)
        #expect(editor.paragraphKind() == .heading2 && validate(.heading2) && state(.heading2) == .on && state(.heading1) == .off, "Heading 2 applies and checks only itself")
        run(.body)
        #expect(editor.paragraphKind() == .text && state(.body) == .on, "Body returns to body text")
        editor.selectedRanges = [NSValue(range: NSRange(location: 0, length: 2)), NSValue(range: NSRange(location: 4, length: 2))]
        #expect(validate(.bold) && !validate(.heading1), "Paragraph styles need one selection, like the style bar")
    }

    @MainActor @Test
    func theLinkMenuAnchorsToTheSelectionAndCommitsItsURL() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-format-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 600, y: 400, width: 60, height: 60))
        try session.perform("Seed") { $0.items = [shape] }
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = FormatKeyWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        var items: [TextFormatCommand: NSMenuItem] = [:]
        TextFormatMenu.add(to: NSMenu(title: "Edit")) { item, command in items[command] = item }
        func owner() -> NSResponder? {
            var responder = window.firstResponder
            while let current = responder, !current.responds(to: TextFormatCommand.action) { responder = current.nextResponder }
            return responder
        }
        func validate(_ command: TextFormatCommand) -> Bool { (owner() as? NSMenuItemValidation)?.validateMenuItem(items[command]!) ?? false }
        func state(_ command: TextFormatCommand) -> NSControl.StateValue { _ = validate(command); return items[command]!.state }
        func perform(_ command: TextFormatCommand) { _ = window.firstResponder?.tryToPerform(TextFormatCommand.action, with: items[command]!) }
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        #expect(canvas.insert(kind: .text, text: "Format me", edit: true), "A text object enters native editing")
        let editor = try #require(canvas.editor)
        editor.localUndo.groupsByEvent = false
        func run(_ command: TextFormatCommand) { editor.localUndo.beginUndoGrouping(); perform(command); editor.localUndo.endUndoGrouping() }
        editor.setSelectedRange(NSRange(location: 0, length: 6))
        #expect(validate(.link) && items[.link]!.title == TextFormatCommand.addLinkTitle, "Add Link is offered for selected text")
        let panels = RecordingPanels()
        canvas.panels = panels
        run(.link)
        let request = try #require(panels.links.first)
        #expect(request.host === editor && request.webOnly == false)
        #expect(!request.anchor.isEmpty && editor.bounds.contains(request.anchor) && request.anchor.width < editor.bounds.width)
        editor.localUndo.beginUndoGrouping()
        request.commit("https://example.com/")
        editor.localUndo.endUndoGrouping()
        #expect(editor.hasLink() && validate(.link) && items[.link]!.title == TextFormatCommand.editLinkTitle, "A linked selection offers Edit Link")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(!validate(.link), "Linking needs selected text")
    }

    @MainActor @Test
    func formattingRefusesCompositionAndUnownedResponders() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-format-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 600, y: 400, width: 60, height: 60))
        try session.perform("Seed") { $0.items = [shape] }
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = FormatKeyWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        var items: [TextFormatCommand: NSMenuItem] = [:]
        TextFormatMenu.add(to: NSMenu(title: "Edit")) { item, command in items[command] = item }
        func owner() -> NSResponder? {
            var responder = window.firstResponder
            while let current = responder, !current.responds(to: TextFormatCommand.action) { responder = current.nextResponder }
            return responder
        }
        func validate(_ command: TextFormatCommand) -> Bool { (owner() as? NSMenuItemValidation)?.validateMenuItem(items[command]!) ?? false }
        func state(_ command: TextFormatCommand) -> NSControl.StateValue { _ = validate(command); return items[command]!.state }
        func perform(_ command: TextFormatCommand) { _ = window.firstResponder?.tryToPerform(TextFormatCommand.action, with: items[command]!) }
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        #expect(canvas.insert(kind: .text, text: "Format me", edit: true), "A text object enters native editing")
        let editor = try #require(canvas.editor)
        editor.localUndo.groupsByEvent = false
        func run(_ command: TextFormatCommand) { editor.localUndo.beginUndoGrouping(); perform(command); editor.localUndo.endUndoGrouping() }
        editor.localUndo.beginUndoGrouping()
        editor.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 0, length: 0))
        #expect(!validate(.bold) && !validate(.bigger), "Composition keeps formatting disabled")
        editor.unmarkText(); editor.localUndo.endUndoGrouping()
        window.key = false
        #expect(!validate(.bold), "A canvas behind another key window is never formatted")
        window.key = true
        let page = EnginePage(frame: NSRect(x: 0, y: 0, width: 50, height: 50)); canvas.addSubview(page)
        #expect(window.makeFirstResponder(page) && owner() === canvas, "An embedded page shares the canvas responder chain")
        #expect(!validate(.bold) && !validate(.heading1) && !validate(.bigger) && !validate(.link), "An embedded web page never receives Parc formatting")
        page.removeFromSuperview()

        #expect(window.makeFirstResponder(editor), "Editor focus returns")
    }

    @MainActor @Test
    func aSelectedTextBoxGetsWholeObjectSizeSteps() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-format-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 600, y: 400, width: 60, height: 60))
        try session.perform("Seed") { $0.items = [shape] }
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = FormatKeyWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        var items: [TextFormatCommand: NSMenuItem] = [:]
        TextFormatMenu.add(to: NSMenu(title: "Edit")) { item, command in items[command] = item }
        func owner() -> NSResponder? {
            var responder = window.firstResponder
            while let current = responder, !current.responds(to: TextFormatCommand.action) { responder = current.nextResponder }
            return responder
        }
        func validate(_ command: TextFormatCommand) -> Bool { (owner() as? NSMenuItemValidation)?.validateMenuItem(items[command]!) ?? false }
        func state(_ command: TextFormatCommand) -> NSControl.StateValue { _ = validate(command); return items[command]!.state }
        func perform(_ command: TextFormatCommand) { _ = window.firstResponder?.tryToPerform(TextFormatCommand.action, with: items[command]!) }
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        #expect(canvas.insert(kind: .text, text: "Format me", edit: true), "A text object enters native editing")
        let editor = try #require(canvas.editor)
        editor.localUndo.groupsByEvent = false
        func run(_ command: TextFormatCommand) { editor.localUndo.beginUndoGrouping(); perform(command); editor.localUndo.endUndoGrouping() }
        _ = canvas.textView(editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        let text = session.document.items.first { $0.kind == .text }!
        canvas.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: text.frame.x + 10, y: text.frame.y + 10)))
        canvas.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: text.frame.x + 10, y: text.frame.y + 10)))
        #expect(window.firstResponder === canvas && !validate(.bold) && validate(.bigger), "A selected text box offers only the size steps its style bar shows")
        perform(.bigger)
        #expect(session.document.items.first { $0.id == text.id }?.resolvedTextStyle.size == text.resolvedTextStyle.size.shifted(by: 1), "Bigger restyles the whole selected text box")
        canvas.selectAll(nil)
        #expect(validate(.bigger), "Shapes hold text too, so a text box and a shape share the size steps")
        window.makeFirstResponder(canvas)
    }

    @MainActor @Test
    func accessibleObjectsHaveTheirOwnFocusAndSpokenIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-accessibility-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let text = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 160, height: 80), text: "Original words")
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 240, y: 50, width: 80, height: 90))
        try session.perform("Seed") { $0.items = [text, shape] }
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        let nodes = canvas.accessibilityChildren()!.compactMap { $0 as? NSView }
        let first = nodes.first { $0.accessibilityIdentifier() == "easel-object-" + text.id.uuidString }!
        let second = nodes.first { $0.accessibilityIdentifier() == "easel-object-" + shape.id.uuidString }!
        #expect(first.accessibilityValue() as? String == text.text && second.accessibilityLabel() == "Rectangle", "Each durable object has its own spoken identity/value")
        #expect(first.accessibilityPerformPress() && window.firstResponder === first, "Native object press selects and focuses its actual canvas stop")
        #expect(first.isAccessibilitySelected() && (canvas.accessibilitySelectedChildren()?.first as? NSView) === first, "AX selected children agrees with actual original selection")
        #expect((canvas.accessibilityFocusedUIElement as? NSView) === first, "Canvas reports actual object focus")
        #expect(first.frame == NSRect(x: 30, y: 30, width: 160, height: 80) && canvas.hitTest(NSPoint(x: 40, y: 40)) !== first, "Object focus view retains geometry without taking pointer input")
    }

    @MainActor @Test
    func aRetainedAccessibleActionRefusesChangedOriginalContent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-accessibility-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let text = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 160, height: 80), text: "Original words")
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 240, y: 50, width: 80, height: 90))
        try session.perform("Seed") { $0.items = [text, shape] }
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        let nodes = canvas.accessibilityChildren()!.compactMap { $0 as? NSView }
        let first = nodes.first { $0.accessibilityIdentifier() == "easel-object-" + text.id.uuidString }!
        let stale = first.accessibilityCustomActions()!.first { $0.name == "Duplicate" }!
        try session.perform("Other owner") { $0.items[0].text = "New original words" }
        #expect(stale.handler?() == false && session.document.items.count == 2, "Retained action refuses changed original content")
    }

    @MainActor @Test
    func anAccessibleResizeChangesOnePointAndIsUndoable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-accessibility-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let text = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 160, height: 80), text: "Original words")
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 240, y: 50, width: 80, height: 90))
        try session.perform("Seed") { $0.items = [text, shape] }
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        let nodes = canvas.accessibilityChildren()!.compactMap { $0 as? NSView }
        let second = nodes.first { $0.accessibilityIdentifier() == "easel-object-" + shape.id.uuidString }!
        #expect(second.accessibilityPerformPress(), "Other object admits native focus without synthetic key traversal")
        let handles = canvas.accessibilityChildren()!.compactMap { $0 as? NSAccessibilityElement }
        #expect(handles.count == 8, "Selected rectangle exposes exactly its eight visible frame controls")
        let right = handles.first { $0.accessibilityLabel() == "Resize Right" }!
        let resize = right.accessibilityCustomActions()!.first { $0.name == "Move right" }!
        #expect(resize.handler?() == true && session.document.items[1].frame.width == 81, "AX frame action applies original geometry transaction")
        #expect(resize.handler?() == false, "Retained control cannot replay against changed original geometry")
        try session.undo()
        #expect(session.document.items[1].frame == shape.frame, "Accessible frame manipulation has one durable undo")
    }

    @MainActor @Test
    func foreignAccessibleChildrenCannotReplaceTheSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-accessibility-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let text = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 160, height: 80), text: "Original words")
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 240, y: 50, width: 80, height: 90))
        try session.perform("Seed") { $0.items = [text, shape] }
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        let nodes = canvas.accessibilityChildren()!.compactMap { $0 as? NSView }
        let first = nodes.first { $0.accessibilityIdentifier() == "easel-object-" + text.id.uuidString }!
        let second = nodes.first { $0.accessibilityIdentifier() == "easel-object-" + shape.id.uuidString }!
        canvas.setAccessibilitySelectedChildren([first, second])
        #expect(canvas.accessibilitySelectedChildren()?.count == 2, "Canvas accepts exact original multi-selection")
        canvas.setAccessibilitySelectedChildren([NSView()])
        #expect(canvas.accessibilitySelectedChildren()?.count == 2, "Foreign AX children cannot replace selection")
    }

    @MainActor @Test
    func accessibleObjectPressDoesNotInterruptComposition() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-accessibility-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let text = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 160, height: 80), text: "Original words")
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 240, y: 50, width: 80, height: 90))
        try session.perform("Seed") { $0.items = [text, shape] }
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        let nodes = canvas.accessibilityChildren()!.compactMap { $0 as? NSView }
        let first = nodes.first { $0.accessibilityIdentifier() == "easel-object-" + text.id.uuidString }!
        let second = nodes.first { $0.accessibilityIdentifier() == "easel-object-" + shape.id.uuidString }!
        try session.perform("Other owner") { $0.items[0].text = "New original words" }
        let edit = first.accessibilityCustomActions()!.first { $0.name == "Edit text" }!
        #expect(edit.handler?() == true, "Text activation reaches existing native editor")
        let editor = first.accessibilityChildren()!.first as! EaselStyledTextView
        #expect(window.firstResponder === editor && editor.string == "New original words", "Object children retain actual text editor and latest content")
        editor.setMarkedText("composition", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!second.accessibilityPerformPress() && window.firstResponder === editor, "Object action does not commit or steal native composition")
        editor.unmarkText(); canvas.cancelOperation(nil)
        #expect(second.accessibilityPerformPress(), "Native object focus resumes after editor dismissal")
    }

    @MainActor @Test
    func accessibleConnectorEndpointsRetainTheirOriginalLease() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-accessibility-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let text = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 160, height: 80), text: "Original words")
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 240, y: 50, width: 80, height: 90))
        try session.perform("Seed") { $0.items = [text, shape] }
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        let nodes = canvas.accessibilityChildren()!.compactMap { $0 as? NSView }
        let second = nodes.first { $0.accessibilityIdentifier() == "easel-object-" + shape.id.uuidString }!
        let arrow = EaselItem(kind: .arrow, frame: .init(x: 400, y: 60, width: 50, height: 40),
            points: [.init(x: 0, y: 40), .init(x: 50, y: 0)])
        try session.perform("Arrow") { $0.items.append(arrow) }
        let arrowNode = canvas.accessibilityChildren()!.compactMap { $0 as? NSView }.first { $0.accessibilityIdentifier() == "easel-object-" + arrow.id.uuidString }!
        #expect(arrowNode.accessibilityPerformPress(), "Arrow admits its original object focus")
        let endpoints = canvas.accessibilityChildren()!.compactMap { $0 as? NSAccessibilityElement }
        #expect(endpoints.count == 2, "Selected arrow exposes only its real two endpoints")
        let endpointAction = endpoints.first { $0.accessibilityLabel() == "Connector end" }!.accessibilityCustomActions()!.first { $0.name == "Move right" }!
        #expect(endpointAction.handler?() == true && session.document.items.last!.frame.width == 51, "AX endpoint action preserves original arrow geometry owner")
        try session.undo()
        #expect(session.document.items.last == arrow && endpointAction.handler?() == true, "Undo restores the exact original endpoint lease")
        try session.undo()
        #expect(second.accessibilityPerformPress() && endpointAction.handler?() == false, "Changed selection refuses retained endpoint control")
    }

    @MainActor @Test
    func accessibleDuplicateReportsARealSaveFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-accessibility-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let text = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 160, height: 80), text: "Original words")
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 240, y: 50, width: 80, height: 90))
        try session.perform("Seed") { $0.items = [text, shape] }
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        let nodes = canvas.accessibilityChildren()!.compactMap { $0 as? NSView }
        let second = nodes.first { $0.accessibilityIdentifier() == "easel-object-" + shape.id.uuidString }!
        #expect(second.accessibilityPerformPress(), "Other object admits native focus without synthetic key traversal")
        let failed = second.accessibilityCustomActions()!.first { $0.name == "Duplicate" }!
        let original = session.document
        let path = directory.appendingPathComponent("documents/" + original.id.uuidString.lowercased() + ".json")
        let bytes = try Data(contentsOf: path)
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        #expect(failed.handler?() == false && session.document == original, "Failed persistence is not reported as a successful accessible duplicate")
        try FileManager.default.removeItem(at: path); try bytes.write(to: path)
    }

    @MainActor @Test
    func drawingSuspendsAndThenRestoresKeyboardStops() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-accessibility-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let text = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 160, height: 80), text: "Original words")
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 240, y: 50, width: 80, height: 90))
        try session.perform("Seed") { $0.items = [text, shape] }
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        let queue = ManualQueue()
        canvas.scheduleAfterInteraction = queue.schedule
        canvas.keyboardStructureChanged()
        queue.runPending()
        var relinks = 0
        canvas.onKeyboardStructureChange = { relinks += 1 }
        queue.runPending(); let beforeDrawing = relinks
        canvas.drawing = true; queue.runPending()
        #expect(relinks > beforeDrawing && canvas.objectKeyViews.allSatisfy { !$0.acceptsFirstResponder }, "Drawing transition rebuilds the native object chain with its real eligibility")
        let duringDrawing = relinks
        canvas.drawing = false; queue.runPending()
        #expect(relinks > duringDrawing && canvas.objectKeyViews.allSatisfy(\.acceptsFirstResponder), "Returning to Select restores native object chain without an unrelated layout")
    }

    @MainActor @Test
    func pointerRetirementRelinksKeyboardNavigation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-accessibility-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let text = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 160, height: 80), text: "Original words")
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 240, y: 50, width: 80, height: 90))
        try session.perform("Seed") { $0.items = [text, shape] }
        let canvas = EaselCanvasView(session: session)
        let queue = ManualQueue()
        canvas.scheduleAfterInteraction = queue.schedule
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        let nodes = canvas.accessibilityChildren()!.compactMap { $0 as? NSView }
        let second = nodes.first { $0.accessibilityIdentifier() == "easel-object-" + shape.id.uuidString }!
        #expect(second.accessibilityPerformPress(), "Other object admits native focus without synthetic key traversal")
        canvas.keyboardStructureChanged()
        queue.runPending()
        var relinks = 0
        canvas.onKeyboardStructureChange = { relinks += 1 }
        func pointer(_ type: NSEvent.EventType, x: Double) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(NSPoint(x: x, y: 80), to: nil), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: pointer(.leftMouseDown, x: 260)); canvas.mouseDragged(with: pointer(.leftMouseDragged, x: 268))
        _ = canvas.accessibilityChildren(); queue.runPending(); let duringPointer = relinks
        #expect(canvas.objectKeyViews.allSatisfy { !$0.acceptsFirstResponder }, "A real pending pointer transaction suspends object focus stops")
        canvas.mouseUp(with: pointer(.leftMouseUp, x: 268)); queue.runPending()
        #expect(relinks > duringPointer && canvas.objectKeyViews.allSatisfy(\.acceptsFirstResponder), "Pointer retirement relinks objects even when final geometry matches the last preview")
    }

    @MainActor @Test
    func detachingOrRetiringTheSessionRefusesRetainedAccessibilityActions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-accessibility-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let text = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 160, height: 80), text: "Original words")
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 240, y: 50, width: 80, height: 90))
        try session.perform("Seed") { $0.items = [text, shape] }
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        let nodes = canvas.accessibilityChildren()!.compactMap { $0 as? NSView }
        let second = nodes.first { $0.accessibilityIdentifier() == "easel-object-" + shape.id.uuidString }!
        #expect(second.accessibilityPerformPress(), "Other object admits native focus without synthetic key traversal")
        let detached = second.accessibilityCustomActions()!.first { $0.name == "Duplicate" }!
        window.contentView = nil
        #expect(detached.handler?() == false && !second.accessibilityPerformPress(), "Detached original window refuses retained actions and focus")
        window.contentView = canvas
        try store.retireSessionForRelocation(session.document.id)
        #expect(!second.accessibilityPerformPress() && detached.handler?() == false, "A retired cross-Profile session cannot regain object focus or action authority")
        #expect(!window.isVisible, "Accessibility component never displays or drives a browser or AX server")
    }

    @MainActor @Test
    func typingOverThePromptAndClearingTheObjectShareUndo() throws {
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
        #expect(prompt.text == "Start typing to enter text", "Text authoring inserts the recovered real default string")
        #expect(editor.selectedRange() == NSRange(location: 0, length: (prompt.text as NSString).length), "Default text is selected for replacement")
        #expect(editor.isContinuousSpellCheckingEnabled, "Native text spelling is enabled for the active editor")
        canvas.cancelOperation(nil)
        #expect(session.document.items == [prompt], "Untouched default text is content and survives dismissal")
        #expect(canvas.selection == [prompt.id], "Escape finishes text input and keeps the object selected")
        canvas.cancelOperation(nil)
        let returnKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 36)!
        canvas.keyDown(with: returnKey)
        #expect(canvas.subviews.allSatisfy { !($0 is EaselStyledTextView) }, "A second Escape clears canvas selection")
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
        func replace(_ editor: EaselStyledTextView, with string: String) {
            editor.textStorage?.setAttributedString(EaselTextAppearance.attributed(string, style: editor.objectStyle, color: editor.objectColor))
            editor.didChangeText()
        }
        canvas.insert(kind: .text, text: "Existing words", edit: true)
        let existing = currentEditor()
        #expect(existing.selectedRange().length == 14, "Keyboard/programmatic entry selects the existing original text")
        existing.setMarkedText("composing", selectedRange: NSRange(location: 0, length: 9), replacementRange: existing.selectedRange())
        #expect(!canvas.canFinishEditingForTransfer && !canvas.finishEditingForTransfer() && existing.hasMarkedText(), "Transfer refuses active composition without ending it")
        existing.unmarkText(); existing.didChangeText()
    }

    @MainActor @Test
    func transferAndReplacementRefuseAFailedEmptyTextSave() throws {
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

    @MainActor @Test
    func aClosedLinkEditorDoesNotBlockEmptyTextCleanup() throws {
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
        let canvas = EaselCanvasView(session: session)
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
        let canvas = EaselCanvasView(session: session)
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
        let fixed = EaselCanvasView(session: memory); fixed.fixedCanvasSize = NSSize(width: 400, height: 300)
        #expect(fixed.readPasteboard(board) && memory.document.items.first?.kind == .text, "CAP21 memory-only fixed canvas keeps URL paste as annotation text")
        #expect(memory.document.items.first?.text == "https://example.com/clipboard", "Capture annotation retains URL words without a browser object")
    }

    @MainActor @Test
    func anUnsupportedURLPastesAsInertText() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-clipboard-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let canvas = EaselCanvasView(session: session)
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.clearContents(); board.setString("https://example.com/clipboard", forType: .URL)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        board.clearContents(); board.setString("javascript:alert(1)", forType: .URL)
        #expect(canvas.readPasteboard(board) && session.document.items.last?.kind == .text, "Unsupported URL scheme is inert text on the canvas")
    }

    @MainActor @Test
    func textFillChangesOnlyTheSelectedObjectsStyleAndIsUndoable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-fill-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create(title: "Fill component")
        let one = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 180), text: "Longer text\nShort")
        let two = EaselItem(kind: .text, frame: .init(x: 350, y: 30, width: 200, height: 180), text: "Other", textStyle: .init(family: .fancy, size: .h2))
        try session.perform("Seed") { $0.items = [one, two] }
        let canvas = EaselCanvasView(session: session)
        canvas.selectAll(nil); canvas.setTextFill(.contentHugging)
        #expect(session.document.items.allSatisfy { $0.resolvedTextStyle.resolvedFill == .contentHugging }, "One real canvas operation fills the selected text objects")
        #expect(session.document.items.map(\.frame) == [one.frame, two.frame] && session.document.items.map(\.text) == [one.text, two.text], "Fill changes neither authored text nor geometry")
        #expect(try! EaselStore(directory: directory).load(session.document.id).document == session.document, "Filled styles survive real atomic save and reopen")
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
        let canvas = EaselCanvasView(session: session)
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
        let captureCanvas = EaselCanvasView(session: memory)
        captureCanvas.selectAll(nil); captureCanvas.setTextFill(.contentHugging)
        let output = try captureCanvas.renderImage(pixelSize: NSSize(width: 600, height: 240), backingScale: 1)
        #expect(output.width == 600 && memory.document.items[0].resolvedTextStyle.resolvedFill == .contentHugging, "CAP21 memory canvas renders the same fill without a saved Easel or browser")
    }

    @MainActor @Test
    func fillUndoKeepsTheOpenEditorAndItsNewText() throws {
        let one = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 180), text: "Longer text\nShort")
        let now = Date()
        let memory = try EaselSession(inMemory: EaselDocument(id: UUID(), title: "Memory fill", createdAt: now, modifiedAt: now, items: [one]), assets: [:])
        let captureCanvas = EaselCanvasView(session: memory)
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
        let typed = memory.document.items[0].text, selectedRange = editor.selectedRange()
        editor.localUndo.beginUndoGrouping(); captureCanvas.setTextFill(.none); editor.localUndo.endUndoGrouping()
        #expect(window.firstResponder === editor && editor.selectedRange() == selectedRange, "Fill returns the original editor focus and preserves its native selection")
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
        let captureCanvas = EaselCanvasView(session: memory)
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

    @MainActor @Test(arguments: [false, true])
    func documentUndoRestoresTextAfterLocalFillEdits(_ undoEdits: Bool) throws {
        let one = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 180), text: "Longer text\nShort")
        let now = Date()
        let memory = try EaselSession(inMemory: EaselDocument(id: UUID(), title: "Memory fill", createdAt: now, modifiedAt: now, items: [one]), assets: [:])
        let captureCanvas = EaselCanvasView(session: memory)
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
        let historyCanvas = EaselCanvasView(session: history)
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
            #expect(history.document.items[0].text == "First typing", "Later native range and typing inverses retain the earlier fill action")
            native.undo(nil)
            #expect(history.document.items[0].resolvedTextStyle.resolvedFill == .none, "Native fill undo remains ordered after later typing and range boundaries")
            native.redo(nil)
            #expect(history.document.items[0].resolvedTextStyle.resolvedFill == .contentHugging, "Native redo restores fill in the same durable editing group")
            native.undo(nil); native.undo(nil)
            #expect(history.document.items[0].text == one.text && history.document.items[0].resolvedTextStyle.resolvedFill == .none, "Complete native undo restores original content and fill")
        }
        #expect(historyCanvas.finishEditingForTransfer(), "The original hidden editor closes through its real lifecycle")
        historyCanvas.undo(nil)
        #expect(history.document.items == [one], "Document undo after normal or natively-undone editing restores the original object without replaying fill inverses")
        historyCanvas.redo(nil)
        #expect(history.document.items[0].resolvedTextStyle.resolvedFill == (undoEdits ? .none : .contentHugging), "Document redo preserves the editor's final fill state")
    }

    @MainActor @Test
    func aSeparateDocumentEditRetainsItsOwnUndoBoundary() throws {
        let one = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 180), text: "Longer text\nShort")
        let now = Date()
        let memory = try EaselSession(inMemory: EaselDocument(id: UUID(), title: "Memory fill", createdAt: now, modifiedAt: now, items: [one]), assets: [:])
        let captureCanvas = EaselCanvasView(session: memory)
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
        let sharedCanvas = EaselCanvasView(session: shared)
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
    func insertingAnInlineImageKeepsTheTextObjectAndItsUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-inline-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let item = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 100), text: "Before After")
        try session.perform("Seed") { $0.items = [item] }
        let canvas = EaselCanvasView(session: session)
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
        #expect(try! EaselStore(directory: directory).load(session.document.id).document == session.document, "Actual disk reopen restores the same inline image range")
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
        let canvas = EaselCanvasView(session: session)
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

    @MainActor
    private final class GestureBoard {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session: EaselSession
        let canvas: EaselCanvasView
        let window: NSWindow
        var errors = 0

        init(_ items: [EaselItem]) throws {
            _ = NSApplication.shared
            session = try EaselStore(directory: directory).create()
            try session.perform("Seed") { $0.items = items }
            canvas = EaselCanvasView(session: session)
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = canvas
            canvas.onError = { [weak self] _ in self?.errors += 1 }
        }

        func close() {
            window.contentView = nil
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }

        func event(_ type: NSEvent.EventType, _ x: Double, _ y: Double, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(NSPoint(x: x, y: y), to: nil), modifierFlags: flags,
                               timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }

        func modifiers(_ value: NSEvent.ModifierFlags) {
            let event = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: value,
                                        timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "",
                                        charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58)!
            canvas.flagsChanged(with: event)
        }
    }

    @MainActor @Test
    func aGroupCornerResizesAllMembersInOneUndoStep() throws {
        let a = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 100, height: 100))
        let b = EaselItem(kind: .circle, frame: .init(x: 300, y: 200, width: 100, height: 100))
        let board = try GestureBoard([a, b])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 400, 300))
        canvas.mouseDragged(with: board.event(.leftMouseDragged, 550, 400))
        #expect(session.document.items == [a, b], "Handle preview never publishes intermediate group frames")
        canvas.mouseUp(with: board.event(.leftMouseUp, 550, 400))
        #expect(session.document.items[0].frame == .init(x: 100, y: 100, width: 150, height: 150) && session.document.items[1].frame == .init(x: 400, y: 250, width: 150, height: 150), "Native group corner transforms original members and gaps")
        try session.undo(); #expect(session.document.items == [a, b], "Native complete group resize uses one shared-session undo")
    }

    @MainActor @Test
    func aGroupEdgeCanResizeFromTheGapBetweenObjects() throws {
        let a = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 100, height: 100))
        let b = EaselItem(kind: .circle, frame: .init(x: 300, y: 200, width: 100, height: 100))
        let board = try GestureBoard([a, b])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 400, 180))
        canvas.mouseDragged(with: board.event(.leftMouseDragged, 460, 250))
        canvas.mouseUp(with: board.event(.leftMouseUp, 460, 250))
        #expect(session.document.items[0].frame.height == 100 && session.document.items[1].frame.x == 340, "Whole original right edge hit strip resizes horizontally in the inter-object gap")
    }

    @MainActor @Test(arguments: [false, true])
    func changingOptionRecomputesTheResizeFromItsOriginalPosition(_ centered: Bool) throws {
        let a = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 100, height: 100))
        let b = EaselItem(kind: .circle, frame: .init(x: 300, y: 200, width: 100, height: 100))
        let board = try GestureBoard([a, b])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        let start: NSEvent.ModifierFlags = centered ? [] : .option
        let finish: NSEvent.ModifierFlags = centered ? .option : []
        canvas.mouseDown(with: board.event(.leftMouseDown, 400, 300))
        canvas.mouseDragged(with: board.event(.leftMouseDragged, 430, 320, flags: start))
        board.modifiers(finish)
        canvas.mouseUp(with: board.event(.leftMouseUp, 430, 320, flags: finish))
        let wanted = centered
            ? EaselRect(x: 70, y: 80, width: 120, height: 120)
            : EaselRect(x: 100, y: 100, width: 110, height: 110)
        let frame = session.document.items[0].frame
        #expect(zip([frame.x, frame.y, frame.width, frame.height], [wanted.x, wanted.y, wanted.width, wanted.height])
            .allSatisfy { abs($0 - $1) < 0.000001 })
    }

    @MainActor @Test(arguments: [false, true])
    func escapeOrFocusLossCancelsTheWholeGroupResize(_ escape: Bool) throws {
        let a = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 100, height: 100))
        let b = EaselItem(kind: .circle, frame: .init(x: 300, y: 200, width: 100, height: 100))
        let board = try GestureBoard([a, b])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        let saved = session.document
        canvas.mouseDown(with: board.event(.leftMouseDown, 400, 300))
        canvas.mouseDragged(with: board.event(.leftMouseDragged, 450, 350))
        if escape {
            canvas.cancelOperation(nil)
        } else {
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: board.window)
        }
        canvas.mouseUp(with: board.event(.leftMouseUp, 450, 350))
        #expect(session.document == saved)
    }

    @MainActor @Test
    func aZeroWidthResizeDoesNotCommitAnEarlierPreview() throws {
        let a = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 100, height: 100))
        let b = EaselItem(kind: .circle, frame: .init(x: 300, y: 200, width: 100, height: 100))
        let board = try GestureBoard([a, b])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        let saved = session.document
        canvas.mouseDown(with: board.event(.leftMouseDown, 400, 300))
        canvas.mouseDragged(with: board.event(.leftMouseDragged, 100, 300)); canvas.mouseUp(with: board.event(.leftMouseUp, 100, 300))
        #expect(session.document == saved, "Singular native proposal does not accidentally commit an earlier preview")
    }

    @MainActor @Test
    func crossingTheHandleCanResumeAfterAZeroWidthPreview() throws {
        let a = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 100, height: 100))
        let b = EaselItem(kind: .circle, frame: .init(x: 300, y: 200, width: 100, height: 100))
        let board = try GestureBoard([a, b])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 400, 300))
        canvas.mouseDragged(with: board.event(.leftMouseDragged, 100, 300))
        canvas.mouseDragged(with: board.event(.leftMouseDragged, 50, 300)); canvas.mouseUp(with: board.event(.leftMouseUp, 50, 300))
        #expect(abs(session.document.items[0].frame.x - 83.3333333333) < 0.00001 && abs(session.document.items[1].frame.x - 50) < 0.00001, "Crossing resumes from original group after zero-width preview refusal")
    }

    @MainActor @Test
    func concurrentGeometryCancelsAnInProgressResize() throws {
        let a = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 100, height: 100))
        let b = EaselItem(kind: .circle, frame: .init(x: 300, y: 200, width: 100, height: 100))
        let board = try GestureBoard([a, b])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 400, 300))
        canvas.mouseDragged(with: board.event(.leftMouseDragged, 450, 350))
        try session.perform("Concurrent geometry") { $0.items[1].frame.x += 1 }
        let external = session.document
        canvas.mouseUp(with: board.event(.leftMouseUp, 450, 350))
        #expect(session.document == external, "Original member geometry mutation cancels all resize output")
    }

    @MainActor @Test
    func aResizePreservesConcurrentStyling() throws {
        let a = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 100, height: 100))
        let b = EaselItem(kind: .circle, frame: .init(x: 300, y: 200, width: 100, height: 100))
        let board = try GestureBoard([a, b])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 400, 300))
        canvas.mouseDragged(with: board.event(.leftMouseDragged, 450, 350))
        try session.perform("Concurrent content") { $0.items[0].color = "#123456" }
        canvas.mouseUp(with: board.event(.leftMouseUp, 450, 350))
        #expect(session.document.items[0].color == "#123456" && session.document.items[1].frame.width > 100, "Native original-group resize preserves same-object concurrent styling")
    }

    @MainActor @Test(arguments: [false, true])
    func aBodyDragUsesTotalTravelToDecideWhetherToMove(_ exceedsThreshold: Bool) throws {
        let a = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 100, height: 100))
        let b = EaselItem(kind: .circle, frame: .init(x: 300, y: 200, width: 100, height: 100))
        let board = try GestureBoard([a, b])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        let saved = session.document
        canvas.mouseDown(with: board.event(.leftMouseDown, 150, 150))
        if exceedsThreshold {
            canvas.mouseDragged(with: board.event(.leftMouseDragged, 154, 150))
            canvas.mouseDragged(with: board.event(.leftMouseDragged, 151, 150))
            canvas.mouseUp(with: board.event(.leftMouseUp, 151, 150))
            #expect(session.document.items.map(\.frame.x) == [101, 301])
        } else {
            canvas.mouseDragged(with: board.event(.leftMouseDragged, 153, 150))
            canvas.mouseUp(with: board.event(.leftMouseUp, 153, 150))
            #expect(session.document == saved)
        }
    }

    @MainActor @Test
    func aFrameHandleAllowsAPreciseShortResize() throws {
        let a = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 100, height: 100))
        let b = EaselItem(kind: .circle, frame: .init(x: 300, y: 200, width: 100, height: 100))
        let board = try GestureBoard([a, b])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 400, 300))
        canvas.mouseDragged(with: board.event(.leftMouseDragged, 402, 300)); canvas.mouseUp(with: board.event(.leftMouseUp, 402, 300))
        #expect(session.document.items[1].frame.width > 100, "Frame controls retain separate precise short-resize end route")
    }

    @MainActor @Test
    func aFailedResizeSaveRetainsTheGroupAndReportsTheError() throws {
        let a = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 100, height: 100))
        let b = EaselItem(kind: .circle, frame: .init(x: 300, y: 200, width: 100, height: 100))
        let board = try GestureBoard([a, b])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        let beforeFailure = session.document, path = board.directory.appendingPathComponent("documents/" + beforeFailure.id.uuidString.lowercased() + ".json")
        let data = try Data(contentsOf: path)
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        canvas.mouseDown(with: board.event(.leftMouseDown, 400, 300))
        canvas.mouseDragged(with: board.event(.leftMouseDragged, 450, 350)); canvas.mouseUp(with: board.event(.leftMouseUp, 450, 350))
        #expect(board.errors == 1 && session.document == beforeFailure, "Native resize reports actual persistence failure without changing original group")
        try FileManager.default.removeItem(at: path); try data.write(to: path)
    }

    @MainActor @Test
    func clickingAnEmptyCircleCornerSelectsTheShapeBelow() throws {
        let bottom = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 100, height: 100))
        let top = EaselItem(kind: .circle, frame: bottom.frame, zIndex: 1)
        let board = try GestureBoard([bottom, top])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.mouseDown(with: board.event(.leftMouseDown, 103, 103)); canvas.mouseUp(with: board.event(.leftMouseUp, 103, 103))
        let right = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: board.window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124)!
        canvas.keyDown(with: right)
        #expect(session.document.items[0].frame.x == 101 && session.document.items[1].frame.x == 100, "Native click passes through empty ellipse corner to original lower object")
    }

    @MainActor @Test
    func contextMenusUseTheSameShapeHitTesting() throws {
        let bottom = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 100, height: 100))
        let top = EaselItem(kind: .circle, frame: bottom.frame, zIndex: 1)
        let board = try GestureBoard([bottom, top])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        try menuRow(contextMenu(canvas, board.event(.rightMouseDown, 103, 103)), "Duplicate").perform?()
        #expect(session.document.items.last?.kind == .rectangle, "Native contextual hit uses the same actual content delegate")
    }

    @MainActor @Test
    func draggingNearAGuideSnapsInOneUndoStep() throws {
        let bottom = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 100, height: 100))
        var target = bottom; target.id = UUID(); target.frame.x = 300
        let board = try GestureBoard([bottom, target])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.mouseDown(with: board.event(.leftMouseDown, 150, 150)); canvas.mouseDragged(with: board.event(.leftMouseDragged, 345, 150))
        #expect(session.document.items[0].frame.x == 100, "Guide preview never mutates durable original during drag")
        canvas.mouseUp(with: board.event(.leftMouseUp, 345, 150))
        #expect(session.document.items[0].frame.x == 300, "Native body move acquires actual target alignment")
        try session.undo()
        #expect(session.document.items[0].frame.x == 100, "One undo restores full snapped gesture")
    }

    @MainActor @Test
    func commandReleasesTheCurrentAlignmentGuide() throws {
        let bottom = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 100, height: 100))
        var target = bottom; target.id = UUID(); target.frame.x = 300
        let board = try GestureBoard([bottom, target])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.mouseDown(with: board.event(.leftMouseDown, 150, 150)); canvas.mouseDragged(with: board.event(.leftMouseDragged, 345, 150))
        let command = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: board.window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 55)!
        canvas.flagsChanged(with: command); canvas.mouseUp(with: board.event(.leftMouseUp, 345, 150, flags: .command))
        #expect(session.document.items[0].frame.x == 295, "Command modifier reversibly releases snap without another pointer move")
    }

    @MainActor @Test
    func togglingGuidesOffLeavesTheOriginalDragUnsnapped() throws {
        let bottom = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 100, height: 100))
        var target = bottom; target.id = UUID(); target.frame.x = 300
        let board = try GestureBoard([bottom, target])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        let alignment = try menuRow(contextMenu(canvas, board.event(.rightMouseDown, 50, 50)), "Use Alignment Guides")
        #expect(alignment.isEnabled && alignment.isChecked, "Native alignment menu advertises actual enabled state")
        alignment.perform?()
        canvas.mouseDown(with: board.event(.leftMouseDown, 150, 150)); canvas.mouseDragged(with: board.event(.leftMouseDragged, 345, 150)); canvas.mouseUp(with: board.event(.leftMouseUp, 345, 150))
        #expect(session.document.items[0].frame.x == 295, "Disabled guide preference preserves unmodified pointer transaction")
    }

    @MainActor @Test
    func detachingTheCanvasRetiresTheAlignmentMenuAction() throws {
        let bottom = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 100, height: 100))
        var target = bottom; target.id = UUID(); target.frame.x = 300
        let board = try GestureBoard([bottom, target])
        defer { board.close() }
        let canvas = board.canvas
        let staleToggle = try menuRow(contextMenu(canvas, board.event(.rightMouseDown, 50, 50)), "Use Alignment Guides")
        board.window.contentView = nil
        let guidesBefore = canvas.alignmentGuidesEnabled
        staleToggle.perform?()
        #expect(canvas.alignmentGuidesEnabled == guidesBefore, "Detached original canvas cannot dispatch captured guide preference")
    }

    @MainActor @Test
    func theStartEndpointCanCrossTheEndInOneUndoStep() throws {
        let arrow = EaselItem(kind: .arrow, frame: .init(x: 100, y: 100, width: 100, height: 80),
                              points: [.init(x: 0, y: 0), .init(x: 100, y: 80)])
        let board = try GestureBoard([arrow])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 100, 100))
        let pressedEnds = canvas.connectorChromeItems().filter { if case .endpoint = $0.chrome { return true }; return false }
        #expect(pressedEnds.count == 2, "Pressing a connector end keeps both end handles showing")
        canvas.mouseDragged(with: board.event(.leftMouseDragged, 250, 220, flags: [.option]))
        #expect(session.document.items[0] == arrow, "Arrow endpoint preview does not publish original content")
        canvas.mouseUp(with: board.event(.leftMouseUp, 250, 220, flags: [.option]))
        #expect(EaselArrowEndpoint.start.point(in: session.document.items[0]) == .init(x: 250, y: 220) && EaselArrowEndpoint.end.point(in: session.document.items[0]) == .init(x: 200, y: 180), "Native original endpoint crosses while Option leaves its payload owner unchanged")
        try session.undo(); #expect(session.document.items[0] == arrow, "Native endpoint drag is exactly one undo")
    }

    @MainActor @Test
    func shiftSnapsAConnectorEndpointToTheNearestAngle() throws {
        let arrow = EaselItem(kind: .arrow, frame: .init(x: 100, y: 100, width: 100, height: 80),
                              points: [.init(x: 0, y: 0), .init(x: 100, y: 80)])
        let board = try GestureBoard([arrow])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 100, 100))
        canvas.mouseDragged(with: board.event(.leftMouseDragged, 250, 220, flags: [.shift])); canvas.mouseUp(with: board.event(.leftMouseUp, 250, 220, flags: [.shift]))
        let shifted = EaselArrowEndpoint.start.point(in: session.document.items[0])
        #expect(shifted.map { abs(abs($0.x - 200) - abs($0.y - 180)) < 0.01 && $0.x > 200 } == true, "Shift snaps a connector end to 45° steps from its other end")
        try session.undo(); #expect(session.document.items[0] == arrow, "Shift-snapped end drag is one undo too")
    }

    @MainActor @Test
    func anEndpointAcceptsAPreciseOnePointDrag() throws {
        let arrow = EaselItem(kind: .arrow, frame: .init(x: 100, y: 100, width: 100, height: 80),
                              points: [.init(x: 0, y: 0), .init(x: 100, y: 80)])
        let board = try GestureBoard([arrow])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 200, 180))
        canvas.mouseDragged(with: board.event(.leftMouseDragged, 201, 180)); canvas.mouseUp(with: board.event(.leftMouseUp, 201, 180))
        #expect(EaselArrowEndpoint.end.point(in: session.document.items[0]) == .init(x: 201, y: 180), "Endpoint direct-end route accepts a precise one-point drag")
    }

    @MainActor @Test
    func escapeCancelsAnUncommittedEndpointDrag() throws {
        let arrow = EaselItem(kind: .arrow, frame: .init(x: 100, y: 100, width: 100, height: 80),
                              points: [.init(x: 0, y: 0), .init(x: 100, y: 80)])
        let board = try GestureBoard([arrow])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 200, 180)); canvas.mouseDragged(with: board.event(.leftMouseDragged, 220, 200))
        canvas.cancelOperation(nil); canvas.mouseUp(with: board.event(.leftMouseUp, 220, 200))
        #expect(session.document.items[0] == arrow, "Escape retires endpoint preview without a durable edit")
    }

    @MainActor @Test
    func changingTheOriginalEndpointInvalidatesTheDrag() throws {
        let arrow = EaselItem(kind: .arrow, frame: .init(x: 100, y: 100, width: 100, height: 80),
                              points: [.init(x: 0, y: 0), .init(x: 100, y: 80)])
        let board = try GestureBoard([arrow])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 200, 180)); canvas.mouseDragged(with: board.event(.leftMouseDragged, 220, 200))
        try session.perform("Original endpoint replaced") { $0.items[0].points[1].x = 80 }
        let external = session.document
        canvas.mouseUp(with: board.event(.leftMouseUp, 220, 200))
        #expect(session.document == external, "Replacement of the original endpoint invalidates native commit")
    }

    @MainActor @Test
    func anImageCornerProjectsTheDragOntoItsAspectRatio() throws {
        let board = try GestureBoard([])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let asset = try session.importPNG(png)
        let image = EaselItem(kind: .image, frame: .init(x: 100, y: 100, width: 200, height: 100), assetID: asset)
        try session.perform("Seed real image") { $0.items = [image] }
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 300, 200)); canvas.mouseDragged(with: board.event(.leftMouseDragged, 400, 200))
        canvas.mouseUp(with: board.event(.leftMouseUp, 400, 200))
        let projected = session.document.items[0]
        #expect(abs(projected.frame.width - 280) < 0.000001 && abs(projected.frame.height - 140) < 0.000001, "Native image corner applies real diagonal projection")
    }

    @MainActor @Test(arguments: [false, true])
    func commandDisablesAspectUntilReleased(_ release: Bool) throws {
        let board = try GestureBoard([])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let asset = try session.importPNG(png)
        let image = EaselItem(kind: .image, frame: .init(x: 100, y: 100, width: 200, height: 100), assetID: asset)
        try session.perform("Seed real image") { $0.items = [image] }
        canvas.selectAll(nil)
        let start: NSEvent.ModifierFlags = release ? .command : []
        let finish: NSEvent.ModifierFlags = release ? [] : .command
        canvas.mouseDown(with: board.event(.leftMouseDown, 300, 200))
        canvas.mouseDragged(with: board.event(.leftMouseDragged, 400, 200, flags: start))
        board.modifiers(finish)
        canvas.mouseUp(with: board.event(.leftMouseUp, 400, 200, flags: finish))
        let shape = session.document.items[0].frame
        #expect(abs(shape.width - (release ? 280 : 300)) < 0.000001)
        #expect(abs(shape.height - (release ? 140 : 100)) < 0.000001)
    }

    @MainActor @Test
    func optionResizesAnImageAroundItsCenter() throws {
        let board = try GestureBoard([])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let asset = try session.importPNG(png)
        let image = EaselItem(kind: .image, frame: .init(x: 100, y: 100, width: 200, height: 100), assetID: asset)
        try session.perform("Seed real image") { $0.items = [image] }
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 300, 200)); canvas.mouseDragged(with: board.event(.leftMouseDragged, 320, 250, flags: .option))
        canvas.mouseUp(with: board.event(.leftMouseUp, 320, 250, flags: .option))
        #expect(session.document.items[0].frame == .init(x: 80, y: 90, width: 240, height: 120), "Native Option uses the recovered centered aspect branch")
    }

    @MainActor @Test
    func focusLossCancelsAnInProgressImageResize() throws {
        let board = try GestureBoard([])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let asset = try session.importPNG(png)
        let image = EaselItem(kind: .image, frame: .init(x: 100, y: 100, width: 200, height: 100), assetID: asset)
        try session.perform("Seed real image") { $0.items = [image] }
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 300, 200)); canvas.mouseDragged(with: board.event(.leftMouseDragged, 400, 200))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: board.window)
        canvas.mouseUp(with: board.event(.leftMouseUp, 400, 200))
        #expect(session.document.items[0] == image, "Owner focus loss cancels pending aspect preview")
    }

    @MainActor @Test(arguments: [EaselItemKind.image, .webCard, .link])
    func theShiftGuideReadsIntrinsicImageOrCardSize(_ kind: EaselItemKind) throws {
        let board = try GestureBoard([])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let asset = try session.importPNG(png)
        let image = EaselItem(kind: .image, frame: .init(x: 100, y: 100, width: 200, height: 100), assetID: asset)
        var object = image
        object.kind = kind
        if kind != .image { object.url = "https://example.com/" }
        try session.perform("Seed original") { $0.items = [object] }
        canvas.selectAll(nil)
        let neighbor = EaselItem(kind: .rectangle, frame: .init(x: 300, y: 220, width: 50, height: 60))
        try session.perform("Add guide target") { $0.items.append(neighbor) }
        canvas.mouseDown(with: board.event(.leftMouseDown, 300, 200))
        canvas.mouseDragged(with: board.event(.leftMouseDragged, 348, 224, flags: .shift))
        canvas.mouseUp(with: board.event(.leftMouseUp, 348, 224, flags: .shift))
        let expected = kind == .link ? 248 + 1.6 + 0.8 / (220.0 / 160.0) : 250.4
        #expect(abs(session.document.items[0].frame.width - expected) < 0.000001)
        try session.undo()
        #expect(session.document.items[0] == object)
        #expect(try session.assetData(asset) == png)
    }

    @MainActor @Test(arguments: [(CGFloat(0.5), 200.0, 198.0), (CGFloat(2), 100.0, 200.0)])
    func magnifiedGuidesMeasureScreenVelocityOnce(_ scale: CGFloat, _ speed: Double, _ expectedX: Double) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-guide-scale-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let moving = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 50, height: 50))
        let target = EaselItem(kind: .rectangle, frame: .init(x: 200, y: 170, width: 100, height: 50))
        let canvas = EaselCanvasView(session: session)
        canvas.fixedCanvasSize = .init(width: 800, height: 800)
        canvas.setFrameSize(.init(width: 800, height: 800))
        _ = NSApplication.shared
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 800, height: 600))
        scroll.documentView = canvas; scroll.allowsMagnification = true
        scroll.minMagnification = 0.25; scroll.maxMagnification = 4; window.contentView = scroll
        defer { window.contentView = nil; window.close() }
        try session.perform("Seed magnified guides") { $0.items = [moving, target] }
        scroll.magnification = scale; scroll.contentView.scroll(to: .zero)
        let from = canvas.convert(NSPoint(x: 125, y: 125), to: nil)
        let to = canvas.convert(NSPoint(x: 223, y: 125), to: nil)
        let elapsed = abs(to.x - from.x) / speed
        func event(_ type: NSEvent.EventType, _ point: NSPoint, _ time: Double) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: time,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: event(.leftMouseDown, from, 1))
        canvas.mouseDragged(with: event(.leftMouseDragged, to, 1 + elapsed))
        canvas.mouseUp(with: event(.leftMouseUp, to, 1 + elapsed))
        #expect(abs(session.document.items[0].frame.x - expectedX) < 0.000001,
               "Guide admission measures screen velocity exactly once at non-unit magnification")
    }

    @MainActor private final class ExtentReentry: NSObject {
        let canvas: EaselCanvasView
        let scroll: NSScrollView
        var depth = 0, deepest = 0
        init(canvas: EaselCanvasView, scroll: NSScrollView) { self.canvas = canvas; self.scroll = scroll }
        @objc func boundsChanged(_ notification: Notification) {
            depth += 1; deepest = max(deepest, depth); defer { depth -= 1 }
            guard depth < 40 else { return }
            canvas.resizeCanvas(viewport: scroll.contentSize)
        }
    }

    @MainActor @Test(arguments: [CGFloat(0.4), 0.75, 1.5])
    func theCanvasExtentSettlesAfterAMagnificationChange(_ magnification: CGFloat) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-zoomed-extent-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        try session.perform("Seed zoomed extent") { $0.items = [EaselItem(kind: .rectangle, frame: .init(x: 60, y: 60, width: 700, height: 300))] }
        let canvas = EaselCanvasView(session: session)
        let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 1213, height: 731))
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        scroll.allowsMagnification = true; scroll.minMagnification = 0.3333; scroll.maxMagnification = 4
        scroll.documentView = canvas
        canvas.resizeCanvas(viewport: scroll.contentSize)
        scroll.contentView.postsBoundsChangedNotifications = true
        let probe = ExtentReentry(canvas: canvas, scroll: scroll)
        NotificationCenter.default.addObserver(probe, selector: #selector(ExtentReentry.boundsChanged(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        defer { NotificationCenter.default.removeObserver(probe) }
        scroll.setMagnification(magnification, centeredAt: NSPoint(x: 500, y: 400))
        #expect(probe.deepest <= 2, "Resizing the canvas from a zoomed clip view's bounds settles instead of feeding its own scroll")
        let clip = scroll.contentView.bounds.size
        #expect(canvas.frame.width >= clip.width - CGFloat(EaselZoom.extentTolerance) && canvas.frame.height >= clip.height - CGFloat(EaselZoom.extentTolerance),
               "The settled canvas still covers the zoomed viewport")
    }

    @MainActor @Test
    func theCanvasExtentStaysSettledAcrossALongZoomSequence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-zoomed-sweep-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        try session.perform("Seed zoomed extent") { $0.items = [EaselItem(kind: .rectangle, frame: .init(x: 60, y: 60, width: 700, height: 300))] }
        let canvas = EaselCanvasView(session: session)
        let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 1213, height: 731))
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        scroll.allowsMagnification = true; scroll.minMagnification = 0.3333; scroll.maxMagnification = 4
        scroll.documentView = canvas
        canvas.resizeCanvas(viewport: scroll.contentSize)
        scroll.contentView.postsBoundsChangedNotifications = true
        let probe = ExtentReentry(canvas: canvas, scroll: scroll)
        NotificationCenter.default.addObserver(probe, selector: #selector(ExtentReentry.boundsChanged(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        defer { NotificationCenter.default.removeObserver(probe) }
        for step in 1...3000 {
            let spread = (Double(step) * 0.6180339887).truncatingRemainder(dividingBy: 1)
            let magnification = CGFloat(0.3333 * pow(12.0, spread))
            let centre = NSPoint(x: (Double(step) * 0.7548776662).truncatingRemainder(dividingBy: 1) * 2400,
                                 y: (Double(step) * 0.5698402910).truncatingRemainder(dividingBy: 1) * 2400)
            scroll.setMagnification(magnification, centeredAt: centre)
        }
        #expect(probe.deepest <= 2, "Resizing the canvas from a zoomed clip view's bounds settles instead of feeding its own scroll")
        let clip = scroll.contentView.bounds.size
        #expect(canvas.frame.width >= clip.width - CGFloat(EaselZoom.extentTolerance) && canvas.frame.height >= clip.height - CGFloat(EaselZoom.extentTolerance),
               "The settled canvas still covers the zoomed viewport")
    }

    @MainActor @Test(arguments: [EaselTableHover.columnBorder(3), .rowBorder(2)])
    func aShrunkTableDrawsWithAStaleHover(_ hover: EaselTableHover) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-stale-table-hover-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        var wide = EaselItem(kind: .table, frame: .init(x: 40, y: 40, width: 500, height: 144))
        wide.table = EaselTable(columnWidths: Array(repeating: 100, count: 5), rowHeights: Array(repeating: 36, count: 4))
        try session.perform("Seed wide table") { $0.items = [wide] }
        let canvas = EaselCanvasView(session: session)
        canvas.setFrameSize(.init(width: 800, height: 600))
        canvas.tableState.hoverTable = wide.id
        canvas.tableState.hover = hover
        try session.perform("Shrink hovered table") { document in
            guard var table = document.items[0].table else { return }
            if case .columnBorder = hover { _ = table.removeColumns(2...4) } else { _ = table.removeRows(1...3) }
            document.items[0].table = table
            document.items[0].frame.width = table.columnWidths.reduce(0, +)
            document.items[0].frame.height = table.rowHeights.reduce(0, +)
        }
        let rep = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        #expect(canvas.tableState.hover == hover, "A table that shrank under a resting hover draws without its stale border")
    }

    @MainActor @Test
    func commandKeepsAnAlreadyCapturedHorizontalAnchor() throws {
        let item = EaselItem(kind: .rectangle, frame: .init(x: 350, y: 100, width: 100, height: 100))
        let board = try GestureBoard([item])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 450, 200))
        canvas.mouseDragged(with: board.event(.leftMouseDragged, 470, 230))
        #expect(session.document.items[0] == item, "Captured anchor preview leaves durable original unchanged")
        board.modifiers(.command)
        canvas.mouseUp(with: board.event(.leftMouseUp, 470, 230, flags: .command))
        #expect(session.document.items[0].frame == .init(x: 330, y: 100, width: 140, height: 130), "Native Command keeps captured horizontal symmetry while suppressing new guides")
        try session.undo(); #expect(session.document.items[0] == item, "One undo restores entire original anchored resize")
    }

    @MainActor @Test(arguments: [false, true])
    func optionAddsOrReleasesTheSecondAnchorAxis(_ release: Bool) throws {
        let item = EaselItem(kind: .rectangle, frame: .init(x: 350, y: 100, width: 100, height: 100))
        let board = try GestureBoard([item])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        let initial: NSEvent.ModifierFlags = release ? .option : []
        let final: NSEvent.ModifierFlags = release ? .command : [.option, .command]
        canvas.mouseDown(with: board.event(.leftMouseDown, 450, 200))
        canvas.mouseDragged(with: board.event(.leftMouseDragged, 470, 230, flags: initial))
        board.modifiers(final)
        canvas.mouseUp(with: board.event(.leftMouseUp, 470, 230, flags: final))
        let expected = release ? EaselRect(x: 330, y: 100, width: 140, height: 130)
            : EaselRect(x: 330, y: 70, width: 140, height: 160)
        #expect(session.document.items[0].frame == expected)
    }

    @MainActor @Test
    func escapeCancelsAnAnchoredResize() throws {
        let item = EaselItem(kind: .rectangle, frame: .init(x: 350, y: 100, width: 100, height: 100))
        let board = try GestureBoard([item])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 450, 200)); canvas.mouseDragged(with: board.event(.leftMouseDragged, 470, 230))
        canvas.cancelOperation(nil); canvas.mouseUp(with: board.event(.leftMouseUp, 470, 230))
        #expect(session.document.items[0] == item, "Escape retires anchor session and all preview geometry")
    }

    @MainActor @Test
    func changingCanvasWidthCancelsTheCapturedAnchor() throws {
        let item = EaselItem(kind: .rectangle, frame: .init(x: 350, y: 100, width: 100, height: 100))
        let board = try GestureBoard([item])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 450, 200)); canvas.mouseDragged(with: board.event(.leftMouseDragged, 470, 230))
        canvas.setFrameSize(.init(width: 900, height: 600)); canvas.mouseUp(with: board.event(.leftMouseUp, 470, 230))
        #expect(session.document.items[0] == item, "Changed logical canvas width cancels rather than retargeting captured center")
    }

    @MainActor @Test
    func focusLossCancelsTheCapturedAnchor() throws {
        let item = EaselItem(kind: .rectangle, frame: .init(x: 350, y: 100, width: 100, height: 100))
        let board = try GestureBoard([item])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 450, 200)); canvas.mouseDragged(with: board.event(.leftMouseDragged, 470, 230))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: board.window)
        canvas.mouseUp(with: board.event(.leftMouseUp, 470, 230))
        #expect(session.document.items[0] == item, "Original window resignation retires captured anchors with original transaction")
    }

    @MainActor @Test
    func theNextResizeRecomputesAnchorEligibilityAfterAnObjectMoves() throws {
        let item = EaselItem(kind: .rectangle, frame: .init(x: 350, y: 100, width: 100, height: 100))
        let board = try GestureBoard([item])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        canvas.selectAll(nil)
        try session.perform("Move original between gestures") { $0.items[0].frame.x += 10 }
        canvas.mouseDown(with: board.event(.leftMouseDown, 460, 200)); canvas.mouseDragged(with: board.event(.leftMouseDragged, 480, 230, flags: .command))
        canvas.mouseUp(with: board.event(.leftMouseUp, 480, 230, flags: .command))
        #expect(session.document.items[0].frame == .init(x: 360, y: 100, width: 120, height: 130), "New native gesture recomputes center ownership from actual new original position")
    }

    @MainActor private final class EnginePage: NSView {
        var requests = 0, mainFrame = true
        override var acceptsFirstResponder: Bool { true }
        @objc func pasteAndMatchStyle(_ sender: Any?) { requests += 1 }
        @objc func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool { mainFrame }
    }
    @MainActor private final class PageSurfaces: EaselBrowserObjectHosting {
        let view = NSView()
        var approved = false
        var pending: (() -> Void)?
        func surface(for item: EaselItem) -> NSView? { item.kind == .browser ? view : nil }
        func synchronize(items: [EaselItem], selection: Set<UUID>, interacting: Bool) {}
        func prepareReplacement(_ next: EaselDocument, valid: @escaping () -> Bool, completion: @escaping (Bool) -> Void) {
            pending = { [weak self] in completion(self?.approved == true && valid()) }
        }
    }

    @MainActor @Test
    func identicalPresentationInvalidationSkipsDirtyRects() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-dirty-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let moved = EaselItem(kind: .rectangle, frame: .init(x: 30, y: 30, width: 50, height: 50))
        let stationary = EaselItem(kind: .circle, frame: .init(x: 130, y: 130, width: 50, height: 50))
        try session.perform("Seed") { $0.items = [moved, stationary] }
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        canvas.layoutSubtreeIfNeeded()
        #expect(!canvas.subviews.contains(where: { NSStringFromClass(type(of: $0)).contains("EaselCanvasArtwork") }),
               "Ordinary software canvas does not host per-object artwork")
        canvas.displayIfNeeded()
        #expect(!canvas.needsDisplay, "First software paint clears the canvas dirty flag")
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        #expect(!canvas.needsDisplay, "Unchanged software layout does not mark the canvas dirty")
        func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(NSPoint(x: x, y: y), to: nil), modifierFlags: [],
                               timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func exitEvent() -> NSEvent {
            NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [],
                                   timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                   eventNumber: 0, trackingNumber: 0, userData: nil)!
        }
        canvas.mouseDown(with: mouse(.leftMouseDown, 40, 40))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, 100, 100))
        #expect(canvas.needsDisplay, "Moving one object still invalidates its dirty region")
        canvas.displayIfNeeded()
        canvas.mouseUp(with: mouse(.leftMouseUp, 100, 100))
        canvas.displayIfNeeded()
        canvas.selectAll(nil)
        #expect(canvas.needsDisplay, "Selecting multiple objects still dirties selection chrome")
        canvas.displayIfNeeded()
        #expect(!canvas.needsDisplay, "Paint clears multi-select chrome dirty flags")
        let skipsBeforeNoop = canvas.presentationNoOpSkipCount
        let dirtyBeforeNoop = canvas.presentationDirtyCount
        canvas.mouseExited(with: exitEvent())
        #expect(canvas.presentationNoOpSkipCount == skipsBeforeNoop + 1,
               "Identical presentation invalidation takes the no-op skip")
        #expect(canvas.presentationDirtyCount == dirtyBeforeNoop,
               "Identical presentation invalidation does not apply a dirty rect")
        #expect(!canvas.needsDisplay,
               "Identical presentation invalidation does not re-dirty multi-select outlines")
        try session.perform("Metadata title") { $0.title = "Presentation fingerprint" }
        canvas.documentDidChange()
        #expect(session.document.title == "Presentation fingerprint", "Metadata title publish actually lands")
        #expect(canvas.presentationDirtyCount == dirtyBeforeNoop,
               "Title-only document republish does not apply a dirty rect when presentation matches")
    }

    @MainActor @Test
    func editingAStickyInvalidatesItsDrawnText() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-dirty-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let moved = EaselItem(kind: .rectangle, frame: .init(x: 30, y: 30, width: 50, height: 50))
        let stationary = EaselItem(kind: .circle, frame: .init(x: 130, y: 130, width: 50, height: 50))
        try session.perform("Seed") { $0.items = [moved, stationary] }
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        let sticky = EaselItem(kind: .sticky, frame: .init(x: 300, y: 300, width: 220, height: 220), text: "Hello world 23")
        try session.perform("Sticky") { $0.items.append(sticky) }
        canvas.documentDidChange()
        let placed = try #require(session.document.items.first { $0.id == sticky.id })
        canvas.selection = [sticky.id]
        canvas.displayIfNeeded()
        let dirtyBeforeEditing = canvas.presentationDirtyCount
        canvas.beginEditing(placed)
        #expect(canvas.editingID == sticky.id && canvas.editor != nil, "Selected sticky enters text editing")
        #expect(canvas.presentationDirtyCount > dirtyBeforeEditing && canvas.needsDisplay,
               "Starting a sticky edit repaints the sticky so its drawn text gives way to the editor")
        canvas.displayIfNeeded()
        let dirtyBeforeFinishing = canvas.presentationDirtyCount
        canvas.finishEditing()
        #expect(canvas.editingID == nil && canvas.selection == [sticky.id], "Finishing the edit keeps the sticky selected")
        #expect(canvas.presentationDirtyCount > dirtyBeforeFinishing && canvas.needsDisplay,
               "Finishing a sticky edit with nothing else changed repaints the sticky so its text comes back")
        canvas.displayIfNeeded()
    }

    @MainActor @Test
    func titleOnlyChangesKeepPageNeighborArtworkClean() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-dirty-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let moved = EaselItem(kind: .rectangle, frame: .init(x: 30, y: 30, width: 50, height: 50))
        let stationary = EaselItem(kind: .circle, frame: .init(x: 130, y: 130, width: 50, height: 50))
        try session.perform("Seed") { $0.items = [moved, stationary] }
        let canvas = EaselCanvasView(session: session)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        func exitEvent() -> NSEvent {
            NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [],
                                   timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                   eventNumber: 0, trackingNumber: 0, userData: nil)!
        }
        let browser = EaselItem(kind: .browser, frame: .init(x: 80, y: 80, width: 400, height: 300), url: "https://example.org/original")
        let cover = EaselItem(kind: .rectangle, frame: .init(x: 500, y: 40, width: 80, height: 80), zIndex: 2)
        try session.perform("Pages") { $0.items = [browser, cover] }
        canvas.documentDidChange()
        let pages = PageSurfaces()
        canvas.pageObjects = pages
        canvas.layoutSubtreeIfNeeded()
        let artwork = canvas.subviews.filter { NSStringFromClass(type(of: $0)).contains("EaselCanvasArtwork") }
        #expect(artwork.count == 1, "Per-object surfaces stay limited to the non-page cover beside an embedded page")
        canvas.displayIfNeeded()
        #expect(artwork.allSatisfy { !$0.needsDisplay }, "First object-surface paint clears cover dirty flags")
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        #expect(artwork.allSatisfy { !$0.needsDisplay }, "Unchanged object-surface layout does not dirty every object")
        canvas.selectAll(nil)
        canvas.displayIfNeeded()
        let surfaceDirtyBefore = canvas.presentationDirtyCount
        let surfaceSkipBefore = canvas.presentationNoOpSkipCount
        canvas.mouseExited(with: exitEvent())
        #expect(canvas.presentationNoOpSkipCount == surfaceSkipBefore + 1,
               "Identical presentation invalidation skips on object-surface canvas")
        #expect(canvas.presentationDirtyCount == surfaceDirtyBefore,
               "Identical presentation invalidation does not dirty object-surface covers")
        try session.perform("Surface metadata") { $0.title = "Object-surface fingerprint" }
        canvas.documentDidChange()
        #expect(session.document.title == "Object-surface fingerprint", "Object-surface metadata title publish lands")
        #expect(canvas.presentationDirtyCount == surfaceDirtyBefore,
               "Title-only republish does not dirty object-surface covers when presentation matches")
        #expect(!window.isVisible, "Incremental display component never displayed a window")
    }

    @MainActor @Test
    func embeddedWebInputRespectsStackingSelectionAndHandles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-browser-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let browser = EaselItem(kind: .browser, frame: .init(x: 80, y: 80, width: 400, height: 300), url: "https://example.org/original")
        let cover = EaselItem(kind: .rectangle, frame: .init(x: 160, y: 160, width: 80, height: 80), zIndex: 2)
        try session.perform("Seed") { $0.items = [browser, cover] }
        let canvas = EaselCanvasView(session: session), surfaces = PageSurfaces()
        canvas.pageObjects = surfaces
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        canvas.selectBrowserObject(browser.id); canvas.layoutSubtreeIfNeeded()
        func hit(_ point: NSPoint) -> NSView? { canvas.hitTest(canvas.convert(point, to: canvas.superview)) }
        #expect(surfaces.view.frame == NSRect(x: 80, y: 80, width: 400, height: 300), "Actual browser surface follows original canvas geometry")
        #expect(hit(NSPoint(x: 300, y: 300)) === surfaces.view, "Selected browser body reaches its original native surface")
        #expect(hit(NSPoint(x: 190, y: 190)) === canvas, "Higher artwork blocks input to the lower native browser")
        #expect(hit(NSPoint(x: 80, y: 80)) === canvas, "Original resize handles retain canvas ownership over native view")
        canvas.cancelOperation(nil); canvas.layoutSubtreeIfNeeded()
        #expect(hit(NSPoint(x: 300, y: 300)) === canvas, "Unselected browser cannot consume native page input")
    }

    @MainActor @Test
    func aStaleOrRefusedRetirementLeavesTheEmbeddedPageInPlace() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-browser-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let browser = EaselItem(kind: .browser, frame: .init(x: 80, y: 80, width: 400, height: 300), url: "https://example.org/original")
        let cover = EaselItem(kind: .rectangle, frame: .init(x: 160, y: 160, width: 80, height: 80), zIndex: 2)
        try session.perform("Seed") { $0.items = [browser, cover] }
        let canvas = EaselCanvasView(session: session), surfaces = PageSurfaces()
        canvas.pageObjects = surfaces
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        canvas.selectBrowserObject(browser.id); canvas.layoutSubtreeIfNeeded()
        window.makeFirstResponder(canvas)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 51)!
        canvas.keyDown(with: event)
        #expect(session.document.items.count == 2 && surfaces.pending != nil, "Delete waits at actual asynchronous retirement boundary")
        surfaces.pending?(); surfaces.pending = nil
        #expect(session.document.items.count == 2, "Refused replacement leaves original objects intact")
        surfaces.approved = true; canvas.keyDown(with: event); canvas.cancelOperation(nil); surfaces.pending?()
        #expect(session.document.items.count == 2, "Intervening canvas selection cancels previously approved target")
    }

    @MainActor @Test
    func approvedRetirementRemovesOnlyThePageAndUndoRestoresIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-browser-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let browser = EaselItem(kind: .browser, frame: .init(x: 80, y: 80, width: 400, height: 300), url: "https://example.org/original")
        let cover = EaselItem(kind: .rectangle, frame: .init(x: 160, y: 160, width: 80, height: 80), zIndex: 2)
        try session.perform("Seed") { $0.items = [browser, cover] }
        let canvas = EaselCanvasView(session: session), surfaces = PageSurfaces()
        canvas.pageObjects = surfaces
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        canvas.selectBrowserObject(browser.id); canvas.layoutSubtreeIfNeeded()
        window.makeFirstResponder(canvas)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 51)!
        surfaces.approved = true
        canvas.selectBrowserObject(browser.id); canvas.keyDown(with: event); surfaces.pending?()
        #expect(session.document.items == [cover], "Approved exact original removal commits only the browser object")
        canvas.undo(nil); surfaces.pending?()
        #expect(session.document.items == [browser, cover], "Canvas document undo restores original durable browser identity")
    }

    @MainActor @Test
    func theFocusedEmbeddedPageOwnsPasteValidationAndDispatch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-browser-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let browser = EaselItem(kind: .browser, frame: .init(x: 80, y: 80, width: 400, height: 300), url: "https://example.org/original")
        let cover = EaselItem(kind: .rectangle, frame: .init(x: 160, y: 160, width: 80, height: 80), zIndex: 2)
        try session.perform("Seed") { $0.items = [browser, cover] }
        let canvas = EaselCanvasView(session: session), surfaces = PageSurfaces()
        canvas.pageObjects = surfaces
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        canvas.selectBrowserObject(browser.id); canvas.layoutSubtreeIfNeeded()
        let page = EnginePage(frame: surfaces.view.bounds); surfaces.view.addSubview(page)
        #expect(window.makeFirstResponder(page), "Embedded engine page owns focus")
        let style = NSMenuItem(title: "Paste and Match Style", action: NSSelectorFromString("pasteAsPlainText:"), keyEquivalent: "")
        #expect(canvas.validateMenuItem(style), "Focused embedded page validates its own Paste and Match Style")
        page.mainFrame = false
        #expect(!canvas.validateMenuItem(style), "Engine validation stays authoritative over canvas paste")
        page.mainFrame = true
        let items = session.document.items
        _ = canvas.perform(NSSelectorFromString("pasteAsPlainText:"), with: style)
        #expect(page.requests == 1 && session.document.items == items, "Embedded page receives the paste; canvas inserts no text object")
        _ = window.makeFirstResponder(canvas); page.removeFromSuperview()
    }

}
