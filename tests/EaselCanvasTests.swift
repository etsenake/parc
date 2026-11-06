import AppKit
import ObjectiveC

// Keep the real link controller/owner while preventing native panel display.
extension NSPopover {
    @objc fileprivate func easelTestSuppressShow(relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge) {}
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

// Real native canvas events over an isolated file-backed session. No browser,
// visible window, personal document, or user's pasteboard is involved.
@main
struct EaselCanvasTests {
    @MainActor static var count = 0
    @MainActor static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; if !value() { fatalError(message) }
    }
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let a = EaselItem(kind: .rectangle, frame: .init(x: 30, y: 30, width: 50, height: 50))
        let b = EaselItem(kind: .circle, frame: .init(x: 130, y: 130, width: 50, height: 50))
        let c = EaselItem(kind: .text, frame: .init(x: 500, y: 30, width: 150, height: 80), text: "Native text")
        try session.perform("Seed") { $0.items = [a, b, c] }
        let canvas = EaselCanvasView(session: session)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        var errors = 0; canvas.onError = { _ in errors += 1 }
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
        marquee(250, 250, 0, 0)
        canvas.keyDown(with: key(124))
        expect(session.document.items[0].frame.x == 31 && session.document.items[1].frame.x == 131 && session.document.items[2].frame.x == 500, "Native reverse marquee selects original first two objects for nudge")
        try session.undo()
        marquee(250, 250, 100, 100, flags: .command)
        canvas.keyDown(with: key(124, flags: .shift))
        expect(session.document.items[0].frame.x == 40 && session.document.items[1].frame.x == 130, "Command marquee subtracts without adding and Shift nudge uses existing 10pt step")
        try session.undo()
        marquee(450, 200, 700, 0, flags: .shift)
        canvas.keyDown(with: key(125))
        expect(session.document.items[0].frame.y == 31 && session.document.items[1].frame.y == 130 && session.document.items[2].frame.y == 31, "Shift marquee unions original selection with text")
        try session.undo()
        let before = session.document
        canvas.mouseDown(with: mouse(.leftMouseDown, 40, 40))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, 100, 100))
        canvas.cancelOperation(nil); canvas.mouseUp(with: mouse(.leftMouseUp, 100, 100))
        expect(session.document == before, "Escape cancels transient original-object move without writing or undo")
        canvas.mouseDown(with: mouse(.leftMouseDown, 250, 250))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, 0, 0))
        canvas.cancelOperation(nil)
        canvas.keyDown(with: key(124))
        expect(session.document.items[0].frame.x == 31 && session.document.items[2].frame.x == 501 && session.document.items[1].frame.x == 130, "Cancelled marquee preserves committed selection")
        try session.undo()
        canvas.mouseDown(with: mouse(.leftMouseDown, 40, 40))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, 90, 90))
        try session.perform("Other owner geometry") { $0.items[0].frame.x += 7 }
        let external = session.document
        canvas.mouseUp(with: mouse(.leftMouseUp, 90, 90))
        expect(session.document == external, "Same-object external geometry cancels the whole native move")
        try session.undo()
        canvas.mouseDown(with: mouse(.leftMouseDown, 40, 40))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, 90, 90))
        try session.perform("Other owner content") { $0.items[1].color = "#112233" }
        canvas.mouseUp(with: mouse(.leftMouseUp, 90, 90))
        // The new real canvas center attracts the original group's 390pt center to 400pt.
        expect(session.document.items[0].frame.x == 90 && session.document.items[2].frame.x == 560 && session.document.items[1].color == "#112233", "Native canvas-center move preserves latest unrelated changes and selected group spacing")
        try session.undo()
        expect(session.document.items[0].frame == a.frame && session.document.items[1].color == "#112233", "Native group move is one independent undo transaction")
        let menu = canvas.menu(for: mouse(.rightMouseDown, 40, 40))!
        let duplicate = menu.items.first { $0.title == "Duplicate" }!
        expect(canvas.validateMenuItem(duplicate), "Original selected objects admit native Duplicate")
        _ = NSApp.sendAction(duplicate.action!, to: duplicate.target, from: duplicate)
        expect(session.document.items.count == 5 && Set(session.document.items.suffix(2).map(\.id)).isDisjoint(with: [a.id, c.id]), "Native Duplicate commits new identities for the complete selection")
        try session.undo()
        expect(session.document.items.count == 3, "One undo removes complete native duplicate group")
        canvas.selectAll(nil)
        let staleMenu = canvas.menu(for: mouse(.rightMouseDown, 40, 40))!
        let staleDuplicate = staleMenu.items.first { $0.title == "Duplicate" }!
        try session.perform("Replace menu source") { $0.items[0].color = "#223344" }
        expect(!canvas.validateMenuItem(staleDuplicate), "Changed original content disables captured menu target")
        _ = NSApp.sendAction(staleDuplicate.action!, to: staleDuplicate.target, from: staleDuplicate)
        expect(session.document.items.count == 3, "Stale menu action is refused at execution too")
        canvas.mouseDown(with: mouse(.leftMouseDown, 40, 40)); canvas.mouseUp(with: mouse(.leftMouseUp, 40, 40))
        // Select only the first object before exercising its existing resize handle.
        canvas.cancelOperation(nil)
        canvas.mouseDown(with: mouse(.leftMouseDown, 40, 40)); canvas.mouseUp(with: mouse(.leftMouseUp, 40, 40))
        let originalFrame = session.document.items[0].frame
        canvas.mouseDown(with: mouse(.leftMouseDown, 80, 80))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, 100, 110)); canvas.mouseUp(with: mouse(.leftMouseUp, 100, 110))
        expect(session.document.items[0].frame.width == 70 && session.document.items[0].frame.height == 80, "Original single-object resize remains a genuine geometry transaction")
        try session.undo(); expect(session.document.items[0].frame == originalFrame, "Resize undo restores original frame")
        canvas.selectAll(nil)
        let saveMenu = canvas.menu(for: mouse(.rightMouseDown, 40, 40))!
        let saveDuplicate = saveMenu.items.first { $0.title == "Duplicate" }!
        let saved = session.document, path = directory.appendingPathComponent("documents/" + saved.id.uuidString.lowercased() + ".json")
        let bytes = try Data(contentsOf: path)
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        _ = NSApp.sendAction(saveDuplicate.action!, to: saveDuplicate.target, from: saveDuplicate)
        expect(errors == 1 && session.document == saved && canvas.validateMenuItem(saveDuplicate), "Failed duplicate reports the real save error and retains original selected targets")
        try FileManager.default.removeItem(at: path); try bytes.write(to: path)
        canvas.mouseDown(with: mouse(.leftMouseDown, 40, 40)); canvas.mouseDragged(with: mouse(.leftMouseDragged, 90, 90))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        canvas.mouseUp(with: mouse(.leftMouseUp, 90, 90))
        expect(session.document == saved, "Original owner resigning cancels native move")
        expect(!canvas.validateMenuItem(saveDuplicate), "Owner resignation also retires its native menu commands")
        canvas.cancelOperation(nil)
        canvas.mouseDown(with: mouse(.leftMouseDown, 530, 55)); canvas.mouseUp(with: mouse(.leftMouseUp, 530, 55))
        canvas.keyDown(with: key(36))
        expect(window.firstResponder is EaselStyledTextView, "Return on the original text object retains the real native range editor")
        if let text = window.firstResponder as? EaselStyledTextView {
            expect(canvas.textView(text, doCommandBy: #selector(NSResponder.cancelOperation(_:))), "Native editor Escape uses its existing delegate")
        }
        expect(window.firstResponder === canvas, "Editor Escape returns focus to the same canvas")
        canvas.selectAll(nil)
        let detachMenu = canvas.menu(for: mouse(.rightMouseDown, 40, 40))!
        let detachDuplicate = detachMenu.items.first { $0.title == "Duplicate" }!
        expect(canvas.validateMenuItem(detachDuplicate), "Current original menu target is valid before detachment")
        window.contentView = nil
        expect(!canvas.validateMenuItem(detachDuplicate), "Detached canvas retires its exact-window menu target")
        let detachedPaste = detachMenu.items.first { $0.title == "Paste" }!
        let detachedPlainPaste = detachMenu.items.first { $0.title == "Paste as Plain Text" }!
        expect(!canvas.validateMenuItem(detachedPaste) && !canvas.validateMenuItem(detachedPlainPaste), "Detached menu also refuses both original-owner paste commands before clipboard access")
        let beforePaste = session.document
        _ = NSApp.sendAction(detachedPaste.action!, to: detachedPaste.target, from: detachedPaste)
        _ = NSApp.sendAction(detachedPlainPaste.action!, to: detachedPlainPaste.target, from: detachedPlainPaste)
        expect(session.document == beforePaste, "Stale paste dispatch leaves exact document unchanged without reading personal clipboard")
        expect(!window.isVisible, "Component window was never displayed")
        try textFillTransactions()
        try resizeInteractions()
        try hitAndGuideInteractions()
        try anchorInteractions()
        try directControlInteractions()
        try magnifiedGuideInteractions()
        try inlineImageEditing()
        try await textDefaultsAndDisposal()
        try browserObjectCanvas()
        try await incrementalObjectDisplay()
        try externalClipboard()
        try await accessibleObjects()
        print("EaselCanvas: \(count) native event assertions passed")
    }
    @MainActor static func accessibleObjects() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-accessibility-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let text = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 160, height: 80), text: "Original words")
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 240, y: 50, width: 80, height: 90))
        try session.perform("Seed") { $0.items = [text, shape] }
        let canvas = EaselCanvasView(session: session)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        let nodes = canvas.accessibilityChildren()!.compactMap { $0 as? NSView }
        let first = nodes.first { $0.accessibilityIdentifier() == "easel-object-" + text.id.uuidString }!
        let second = nodes.first { $0.accessibilityIdentifier() == "easel-object-" + shape.id.uuidString }!
        expect(first.accessibilityValue() as? String == text.text && second.accessibilityLabel() == "Rectangle", "Each durable object has its own spoken identity/value")
        expect(first.accessibilityPerformPress() && window.firstResponder === first, "Native object press selects and focuses its actual canvas stop")
        expect(first.isAccessibilitySelected() && (canvas.accessibilitySelectedChildren()?.first as? NSView) === first, "AX selected children agrees with actual original selection")
        expect((canvas.accessibilityFocusedUIElement as? NSView) === first, "Canvas reports actual object focus")
        expect(first.frame == NSRect(x: 30, y: 30, width: 160, height: 80) && canvas.hitTest(NSPoint(x: 40, y: 40)) !== first, "Object focus view retains geometry without taking pointer input")
        let stale = first.accessibilityCustomActions()!.first { $0.name == "Duplicate" }!
        try session.perform("Other owner") { $0.items[0].text = "New original words" }
        expect(stale.handler?() == false && session.document.items.count == 2, "Retained action refuses changed original content")
        expect(second.accessibilityPerformPress(), "Other object admits native focus without synthetic key traversal")
        let handles = canvas.accessibilityChildren()!.compactMap { $0 as? NSAccessibilityElement }
        expect(handles.count == 8, "Selected rectangle exposes exactly its eight visible frame controls")
        let right = handles.first { $0.accessibilityLabel() == "Resize Right" }!
        let resize = right.accessibilityCustomActions()!.first { $0.name == "Move right" }!
        expect(resize.handler?() == true && session.document.items[1].frame.width == 81, "AX frame action applies original geometry transaction")
        expect(resize.handler?() == false, "Retained control cannot replay against changed original geometry")
        try session.undo()
        expect(session.document.items[1].frame == shape.frame, "Accessible frame manipulation has one durable undo")
        canvas.setAccessibilitySelectedChildren([first, second])
        expect(canvas.accessibilitySelectedChildren()?.count == 2, "Canvas accepts exact original multi-selection")
        canvas.setAccessibilitySelectedChildren([NSView()])
        expect(canvas.accessibilitySelectedChildren()?.count == 2, "Foreign AX children cannot replace selection")
        let edit = first.accessibilityCustomActions()!.first { $0.name == "Edit text" }!
        expect(edit.handler?() == true, "Text activation reaches existing native editor")
        let editor = first.accessibilityChildren()!.first as! EaselStyledTextView
        expect(window.firstResponder === editor && editor.string == "New original words", "Object children retain actual text editor and latest content")
        editor.setMarkedText("composition", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        expect(!second.accessibilityPerformPress() && window.firstResponder === editor, "Object action does not commit or steal native composition")
        editor.unmarkText(); canvas.cancelOperation(nil)
        expect(second.accessibilityPerformPress(), "Native object focus resumes after editor dismissal")
        let arrow = EaselItem(kind: .arrow, frame: .init(x: 400, y: 60, width: 50, height: 40),
            points: [.init(x: 0, y: 40), .init(x: 50, y: 0)])
        try session.perform("Arrow") { $0.items.append(arrow) }
        let arrowNode = canvas.accessibilityChildren()!.compactMap { $0 as? NSView }.first { $0.accessibilityIdentifier() == "easel-object-" + arrow.id.uuidString }!
        expect(arrowNode.accessibilityPerformPress(), "Arrow admits its original object focus")
        let endpoints = canvas.accessibilityChildren()!.compactMap { $0 as? NSAccessibilityElement }
        expect(endpoints.count == 2, "Selected arrow exposes only its real two endpoints")
        let endpointAction = endpoints.first { $0.accessibilityLabel() == "Arrow end" }!.accessibilityCustomActions()!.first { $0.name == "Move right" }!
        expect(endpointAction.handler?() == true && session.document.items.last!.frame.width == 51, "AX endpoint action preserves original arrow geometry owner")
        try session.undo()
        expect(session.document.items.last == arrow && endpointAction.handler?() == true, "Undo restores the exact original endpoint lease")
        try session.undo()
        expect(second.accessibilityPerformPress() && endpointAction.handler?() == false, "Changed selection refuses retained endpoint control")
        let failed = second.accessibilityCustomActions()!.first { $0.name == "Duplicate" }!
        let original = session.document
        let path = directory.appendingPathComponent("documents/" + original.id.uuidString.lowercased() + ".json")
        let bytes = try Data(contentsOf: path)
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        expect(failed.handler?() == false && session.document == original, "Failed persistence is not reported as a successful accessible duplicate")
        try FileManager.default.removeItem(at: path); try bytes.write(to: path)
        var relinks = 0
        canvas.onKeyboardStructureChange = { relinks += 1 }
        func drainFocusChanges() async {
            // Yield this main-actor test before awaiting the queued native
            // structure callback; a nested synchronous RunLoop cannot do that.
            for _ in 0..<2 {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
        }
        await drainFocusChanges(); let beforeDrawing = relinks
        canvas.drawing = true; await drainFocusChanges()
        expect(relinks > beforeDrawing && canvas.objectKeyViews.allSatisfy { !$0.acceptsFirstResponder }, "Drawing transition rebuilds the native object chain with its real eligibility")
        let duringDrawing = relinks
        canvas.drawing = false; await drainFocusChanges()
        expect(relinks > duringDrawing && canvas.objectKeyViews.allSatisfy(\.acceptsFirstResponder), "Returning to Select restores native object chain without an unrelated layout")
        func pointer(_ type: NSEvent.EventType, x: Double) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(NSPoint(x: x, y: 80), to: nil), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: pointer(.leftMouseDown, x: 260)); canvas.mouseDragged(with: pointer(.leftMouseDragged, x: 268))
        _ = canvas.accessibilityChildren(); await drainFocusChanges(); let duringPointer = relinks
        expect(canvas.objectKeyViews.allSatisfy { !$0.acceptsFirstResponder }, "A real pending pointer transaction suspends object focus stops")
        canvas.mouseUp(with: pointer(.leftMouseUp, x: 268)); await drainFocusChanges()
        expect(relinks > duringPointer && canvas.objectKeyViews.allSatisfy(\.acceptsFirstResponder), "Pointer retirement relinks objects even when final geometry matches the last preview")
        let detached = second.accessibilityCustomActions()!.first { $0.name == "Duplicate" }!
        window.contentView = nil
        expect(detached.handler?() == false && !second.accessibilityPerformPress(), "Detached original window refuses retained actions and focus")
        window.contentView = canvas
        try store.retireSessionForRelocation(session.document.id)
        expect(!second.accessibilityPerformPress() && detached.handler?() == false, "A retired cross-Profile session cannot regain object focus or action authority")
        expect(!window.isVisible, "Accessibility component never displays or drives a browser or AX server")
    }
    @MainActor static func textDefaultsAndDisposal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-text-defaults-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let canvas = EaselCanvasView(session: session)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        var errors = 0; canvas.onError = { _ in errors += 1 }
        func currentEditor() -> EaselStyledTextView { canvas.subviews.compactMap { $0 as? EaselStyledTextView }.first! }
        func replace(_ editor: EaselStyledTextView, with string: String) {
            editor.textStorage?.setAttributedString(EaselTextAppearance.attributed(string, style: editor.objectStyle, color: editor.objectColor))
            editor.didChangeText()
        }
        canvas.insert(kind: .text, edit: true)
        let prompt = session.document.items[0], editor = currentEditor()
        expect(prompt.text == "Start typing to enter text", "Text authoring inserts the recovered real default string")
        expect(editor.selectedRange() == NSRange(location: 0, length: (prompt.text as NSString).length), "Default text is selected for replacement")
        expect(editor.isContinuousSpellCheckingEnabled, "Native text spelling is enabled for the active editor")
        canvas.cancelOperation(nil)
        expect(session.document.items == [prompt], "Untouched default text is content and survives dismissal")
        let returnKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 36)!
        canvas.keyDown(with: returnKey)
        expect(canvas.subviews.allSatisfy { !($0 is EaselStyledTextView) }, "Escape clears canvas selection as well as text input")
        canvas.selectAll(nil); window.makeFirstResponder(canvas); canvas.keyDown(with: returnKey)
        let clearing = currentEditor()
        replace(clearing, with: " \t\n\u{00a0}")
        let empty = session.document.items[0]
        expect(empty.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Whitespace is saved while editing, before disposal")
        expect(canvas.canFinishEditingForTransfer && canvas.finishEditingForTransfer(), "Transfer flush uses the same accepted final edit boundary")
        expect(session.document.items.isEmpty, "Final edit removes whitespace-only original text")
        try session.undo()
        expect(session.document.items == [prompt], "Empty cleanup coalesces with typing so undo restores the original nonempty object")
        try session.redo(); expect(session.document.items.isEmpty, "Redo restores the complete empty-text deletion")

        canvas.insert(kind: .text, text: "Existing words", edit: true)
        let existing = currentEditor()
        expect(existing.selectedRange().length == 14, "Keyboard/programmatic entry selects the existing original text")
        existing.setMarkedText("composing", selectedRange: NSRange(location: 0, length: 9), replacementRange: existing.selectedRange())
        expect(!canvas.canFinishEditingForTransfer && !canvas.finishEditingForTransfer() && existing.hasMarkedText(), "Transfer refuses active composition without ending it")
        existing.unmarkText(); existing.didChangeText()
        replace(existing, with: " ")
        let saved = session.document, path = directory.appendingPathComponent("documents/" + saved.id.uuidString.lowercased() + ".json")
        let bytes = try Data(contentsOf: path)
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        expect(!canvas.finishEditingForTransfer(), "Failed empty-object persistence refuses transfer completion")
        expect(errors == 1 && session.document == saved && existing.superview === canvas, "Failed cleanup preserves document and the original native editor")
        canvas.insert(kind: .rectangle)
        expect(errors == 2 && session.document == saved, "A failed final edit also refuses replacement insertion")
        try FileManager.default.removeItem(at: path); try bytes.write(to: path)
        try session.perform("Other window text") { $0.items[0].text = "Keep the other window"; $0.items[0].richText = nil }
        expect(canvas.finishEditingForTransfer(), "A stale empty editor can retire without deleting newer saved content")
        expect(session.document.items[0].text == "Keep the other window", "Queued shared-session text update survives empty disposal")

        canvas.selectAll(nil); window.makeFirstResponder(canvas); canvas.keyDown(with: returnKey)
        let stale = currentEditor()
        try session.perform("Concurrent text") { $0.items[0].text = "Latest original text"; $0.items[0].richText = nil }
        replace(stale, with: "stale replacement")
        expect(session.document.items[0].text == "Latest original text" && stale.string == "Latest original text", "Late native edit refuses and reloads an intervening original-content change")
        expect(canvas.finishEditingForTransfer(), "Nonempty editor transfer finalization succeeds")
        canvas.insert(kind: .text, text: "\u{fffc}", edit: false)
        expect(!EaselTextEditing.isEmpty(session.document.items.last!), "Attachment replacement character is meaningful content, never whitespace")
        canvas.insert(kind: .rectangle)
        expect(!EaselTextEditing.isEmpty(session.document.items.last!), "Non-text objects do not acquire text disposal policy")
        let insertionPoint = NSPoint(x: 40, y: 450)
        let doubleClick = NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(insertionPoint, to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 1)!
        canvas.mouseDown(with: doubleClick)
        expect(session.document.items.last!.text == EaselTextEditing.defaultText && currentEditor().selectedRange().length == 26,
               "Blank-canvas double click authors and selects the actual default prompt")
        expect(session.document.items.last!.frame == EaselRect(x: 40, y: 436, width: 280, height: 28),
               "Blank-canvas insertion uses the recovered point-relative text frame")
        let linked = currentEditor()
        let nativeShow = class_getInstanceMethod(NSPopover.self, #selector(NSPopover.show(relativeTo:of:preferredEdge:)))!
        let hiddenShow = class_getInstanceMethod(NSPopover.self, #selector(NSPopover.easelTestSuppressShow(relativeTo:of:preferredEdge:)))!
        method_exchangeImplementations(nativeShow, hiddenShow)
        linked.editLink(relativeTo: linked)
        method_exchangeImplementations(nativeShow, hiddenShow)
        expect(!linked.hasPendingRangeAction, "A retained closed Link popover is not a pending range action")
        let closingID = session.document.items.last!.id
        replace(linked, with: " ")
        window.makeFirstResponder(canvas)
        canvas.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: linked))
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
        expect(linked.superview == nil && !session.document.items.contains { $0.id == closingID },
               "Focus dismissal after a closed Link popover retires the editor and its empty object")

        canvas.insert(kind: .text, edit: true)
        replace(currentEditor(), with: " ")
        let itemCount = session.document.items.count, replacedID = session.document.items.last!.id
        let drop = CanvasTextDrop(); drop.draggingDestinationWindow = window
        defer { drop.draggingPasteboard.releaseGlobally() }
        try EaselStyledText(text: "Replacement drop", style: .init(), color: "#252525").write(to: drop.draggingPasteboard)
        expect(canvas.performDragOperation(drop), "A successful rich-text drop reports success when it first removes an empty editor")
        expect(session.document.items.count == itemCount && session.document.items.last!.text == "Replacement drop" &&
               !session.document.items.contains { $0.id == replacedID }, "Replacement drop persists a new identity despite unchanged total item count")
        expect(!window.isVisible, "Default/disposal checks never display a window or start a browser")
    }

    @MainActor static func externalClipboard() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-clipboard-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let canvas = EaselCanvasView(session: session)
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.clearContents(); board.setString("https://example.com/clipboard", forType: .URL)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        expect(canvas.readPasteboard(board), "Canvas accepts a URL-only external clipboard")
        expect(session.document.items.count == 1 && session.document.items[0].kind == .link && session.document.items[0].url == "https://example.com/clipboard", "URL clipboard creates the original local link object")
        let id = session.document.id
        expect(try! EaselStore(directory: directory).load(id).document.items == session.document.items, "Pasted link persists through the actual document store")
        try session.undo(); expect(session.document.items.isEmpty, "Canvas URL paste is one durable undo")
        canvas.insert(kind: .text, edit: true)
        guard let emptyEditor = window.firstResponder as? EaselStyledTextView else { fatalError("Missing actual empty-edit owner") }
        emptyEditor.textStorage?.setAttributedString(EaselTextAppearance.attributed(" ", style: .init(), color: "#252525"))
        canvas.textDidChange(Notification(name: NSText.didChangeNotification, object: emptyEditor))
        let beforeReplacementCount = session.document.items.count, emptyID = session.document.items.last!.id
        expect(canvas.readPasteboard(board), "URL-only paste reports success when it first disposes an empty editor")
        expect(session.document.items.count == beforeReplacementCount && session.document.items.last!.kind == .link && !session.document.items.contains(where: { $0.id == emptyID }), "URL paste preserves explicit insertion success despite unchanged item count")
        try session.undo()
        try session.undo()
        let memory = try EaselSession(inMemory: EaselDocument(id: UUID(), title: "Capture", createdAt: Date(), modifiedAt: Date()), assets: [:])
        let fixed = EaselCanvasView(session: memory); fixed.fixedCanvasSize = NSSize(width: 400, height: 300)
        window.contentView = fixed
        expect(fixed.readPasteboard(board) && memory.document.items.first?.kind == .text, "CAP21 memory-only fixed canvas keeps URL paste as annotation text")
        expect(memory.document.items.first?.text == "https://example.com/clipboard", "Capture annotation retains URL words without a browser object")
        window.contentView = canvas
        board.clearContents(); board.setString("javascript:alert(1)", forType: .URL)
        expect(canvas.readPasteboard(board) && session.document.items.last?.kind == .text, "Unsupported URL scheme is inert text on the canvas")
    }

    @MainActor static func textFillTransactions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-fill-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create(title: "Fill component")
        let one = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 180), text: "Longer text\nShort")
        let two = EaselItem(kind: .text, frame: .init(x: 350, y: 30, width: 200, height: 180), text: "Other", textStyle: .init(family: .fancy, size: .h2))
        try session.perform("Seed") { $0.items = [one, two] }
        let canvas = EaselCanvasView(session: session)
        canvas.selectAll(nil); canvas.setTextFill(.contentHugging)
        expect(session.document.items.allSatisfy { $0.resolvedTextStyle.resolvedFill == .contentHugging }, "One real canvas operation fills the selected text objects")
        expect(session.document.items.map(\.frame) == [one.frame, two.frame] && session.document.items.map(\.text) == [one.text, two.text], "Fill changes neither authored text nor geometry")
        expect(try! EaselStore(directory: directory).load(session.document.id).document == session.document, "Filled styles survive real atomic save and reopen")
        try session.undo()
        expect(session.document.items == [one, two], "One document undo restores every original style")
        try session.redo()
        expect(session.document.items.allSatisfy { $0.resolvedTextStyle.resolvedFill == .contentHugging }, "Document redo restores whole-object fill")
        let saved = session.document
        try FileManager.default.removeItem(at: directory.appendingPathComponent("documents"))
        try Data().write(to: directory.appendingPathComponent("documents"))
        canvas.setTextFill(.none)
        expect(session.document == saved, "A refused durable fill edit retains exact saved objects")
        let now = Date()
        let memory = try EaselSession(inMemory: EaselDocument(id: UUID(), title: "Memory fill", createdAt: now, modifiedAt: now, items: [one]), assets: [:])
        let captureCanvas = EaselCanvasView(session: memory)
        captureCanvas.selectAll(nil); captureCanvas.setTextFill(.contentHugging)
        let output = try captureCanvas.renderImage(pixelSize: NSSize(width: 600, height: 240), backingScale: 1)
        expect(output.width == 600 && memory.document.items[0].resolvedTextStyle.resolvedFill == .contentHugging, "CAP21 memory canvas renders the same fill without a saved Easel or browser")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
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
        expect(window.firstResponder === editor && editor.selectedRange() == selectedRange, "Fill returns the original editor focus and preserves its native selection")
        editor.undo(nil)
        expect(memory.document.items[0].resolvedTextStyle.resolvedFill == .contentHugging && memory.document.items[0].text == typed,
               "Native Undo reverses the latest fill before older typing")
        editor.redo(nil)
        expect(memory.document.items[0].resolvedTextStyle.resolvedFill == .none && memory.document.items[0].text == typed,
               "Native Redo restores fill without rewriting text")
        try memory.perform("Concurrent style") { $0.items[0].textStyle?.family = .mono }
        let concurrent = memory.document
        editor.undo(nil)
        expect(memory.document == concurrent, "Stale native fill undo refuses a different owner's replacement style")
        for undoEdits in [false, true] {
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
            // A real range action is also a native boundary, but stays inside
            // the same durable editing lifetime.
            native.setSelectedRange(NSRange(location: 0, length: 5))
            action { native.toggle(.underline) }
            if undoEdits {
                native.undo(nil); native.undo(nil)
                expect(history.document.items[0].text == "First typing", "Later native range and typing inverses retain the earlier fill action")
                native.undo(nil)
                expect(history.document.items[0].resolvedTextStyle.resolvedFill == .none, "Native fill undo remains ordered after later typing and range boundaries")
                native.redo(nil)
                expect(history.document.items[0].resolvedTextStyle.resolvedFill == .contentHugging, "Native redo restores fill in the same durable editing group")
                native.undo(nil); native.undo(nil)
                expect(history.document.items[0].text == one.text && history.document.items[0].resolvedTextStyle.resolvedFill == .none, "Complete native undo restores original content and fill")
            }
            expect(historyCanvas.finishEditingForTransfer(), "The original hidden editor closes through its real lifecycle")
            historyCanvas.undo(nil)
            expect(history.document.items == [one], "Document undo after normal or natively-undone editing restores the original object without replaying fill inverses")
            historyCanvas.redo(nil)
            expect(history.document.items[0].resolvedTextStyle.resolvedFill == (undoEdits ? .none : .contentHugging), "Document redo preserves the editor's final fill state")
        }
        let shared = try EaselSession(inMemory: EaselDocument(id: UUID(), title: "Shared", createdAt: now, modifiedAt: now, items: [one]), assets: [:])
        let sharedCanvas = EaselCanvasView(session: shared)
        window.contentView = sharedCanvas; sharedCanvas.selectAll(nil); window.makeFirstResponder(sharedCanvas); sharedCanvas.keyDown(with: enter)
        let sharedEditor = sharedCanvas.subviews.compactMap { $0 as? EaselStyledTextView }.first!
        sharedEditor.localUndo.groupsByEvent = false
        sharedEditor.localUndo.beginUndoGrouping(); sharedCanvas.setTextFill(.contentHugging); sharedEditor.localUndo.endUndoGrouping()
        try shared.perform("Other owner title") { $0.title = "Other owner" }
        let external = shared.document
        sharedEditor.undo(nil)
        expect(shared.document == external, "A native fill inverse refuses an intervening unrelated shared-owner transaction")
        sharedEditor.localUndo.beginUndoGrouping(); sharedEditor.insertText("After external", replacementRange: NSRange(location: 0, length: sharedEditor.string.utf16.count)); sharedEditor.localUndo.endUndoGrouping()
        expect(sharedCanvas.finishEditingForTransfer(), "Edited shared canvas finishes without replacing another owner's state")
        sharedCanvas.undo(nil)
        expect(shared.document.items == external.items && shared.document.title == "Other owner", "Later native edits start a fresh durable group after an external transaction")
        sharedCanvas.undo(nil)
        expect(shared.document.title == "Shared" && shared.document.items[0].resolvedTextStyle.resolvedFill == .contentHugging, "The external transaction retains its own document history boundary")
        expect(!window.isVisible, "Text fill checks never display their native window")
        if let path = ProcessInfo.processInfo.environment["PARC_EASEL_FILL_PREVIEW"] {
            let preview = CGContext(data: nil, width: output.width, height: output.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let area = CGRect(x: 0, y: 0, width: output.width, height: output.height)
            preview.setFillColor(NSColor.white.cgColor); preview.fill(area); preview.draw(output, in: area)
            try NSBitmapImageRep(cgImage: preview.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        }
    }

    @MainActor static func inlineImageEditing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-inline-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let item = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 300, height: 100), text: "Before After")
        try session.perform("Seed") { $0.items = [item] }
        let canvas = EaselCanvasView(session: session)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        var errors = 0; canvas.onError = { _ in errors += 1 }
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(NSPoint(x: 60, y: 45), to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 1)!
        canvas.mouseDown(with: event)
        guard let editor = window.firstResponder as? EaselStyledTextView else { fatalError("Original text editor missing") }
        editor.localUndo.groupsByEvent = false; editor.setSelectedRange(NSRange(location: 7, length: 5))
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        editor.localUndo.beginUndoGrouping(); let inserted = try editor.insertImage(png); editor.localUndo.endUndoGrouping()
        expect(inserted && errors == 0, "Real canvas editor commits native attachment without a clipboard surrogate")
        expect(session.document.items.count == 1 && session.document.items[0].id == item.id && session.document.items[0].kind == .text, "Inline insertion keeps the original text-object identity")
        expect(session.document.items[0].richText?.runs.contains(where: { $0.attributes.image?.data == png }) == true, "Native edit delegate persists real original bytes in the shared document")
        expect(try! EaselStore(directory: directory).load(session.document.id).document == session.document, "Actual disk reopen restores the same inline image range")
        expect(editor.localUndo.canUndo, "Session notification preserves local native image undo")
        editor.undo(nil)
        expect(session.document.items[0].text == item.text && session.document.items[0].richText?.runs.allSatisfy({ $0.attributes.image == nil }) != false, "Native editor undo commits restored text through the same session")
        editor.redo(nil)
        expect(session.document.items[0].richText?.runs.contains(where: { $0.attributes.image?.data == png }) == true, "Native editor redo restores durable original image bytes")
        let saved = session.document, path = directory.appendingPathComponent("documents/" + saved.id.uuidString.lowercased() + ".json")
        let bytes = try Data(contentsOf: path)
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        editor.setSelectedRange(NSRange(location: editor.attributedString().length, length: 0))
        editor.localUndo.beginUndoGrouping(); let refused = try editor.insertImage(png); editor.localUndo.endUndoGrouping()
        expect(!refused && errors == 1 && session.document == saved, "Real persistence refusal rejects insertion and preserves original document")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(editor.string == saved.items[0].text && !editor.localUndo.canUndo, "Failed-save rollback restores the real editor and retires uncommitted local undo")
        try FileManager.default.removeItem(at: path); try bytes.write(to: path)
        expect(!window.isVisible, "Inline native component never displays a window")
    }
    @MainActor static func resizeInteractions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-resize-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let a = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 100, height: 100))
        let b = EaselItem(kind: .circle, frame: .init(x: 300, y: 200, width: 100, height: 100))
        try session.perform("Seed") { $0.items = [a, b] }
        let canvas = EaselCanvasView(session: session)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        var errors = 0; canvas.onError = { _ in errors += 1 }
        func event(_ type: NSEvent.EventType, _ x: Double, _ y: Double, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(.init(x: x, y: y), to: nil), modifierFlags: flags,
                               timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func flags(_ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58)!
        }
        func close(_ a: EaselRect, _ b: EaselRect) -> Bool {
            zip([a.x, a.y, a.width, a.height], [b.x, b.y, b.width, b.height]).allSatisfy { abs($0 - $1) < 0.000001 }
        }
        canvas.selectAll(nil)
        canvas.mouseDown(with: event(.leftMouseDown, 400, 300))
        canvas.mouseDragged(with: event(.leftMouseDragged, 550, 400))
        expect(session.document.items == [a, b], "Handle preview never publishes intermediate group frames")
        canvas.mouseUp(with: event(.leftMouseUp, 550, 400))
        expect(session.document.items[0].frame == .init(x: 100, y: 100, width: 150, height: 150) && session.document.items[1].frame == .init(x: 400, y: 250, width: 150, height: 150), "Native group corner transforms original members and gaps")
        try session.undo(); expect(session.document.items == [a, b], "Native complete group resize uses one shared-session undo")
        canvas.mouseDown(with: event(.leftMouseDown, 400, 180))
        canvas.mouseDragged(with: event(.leftMouseDragged, 460, 250))
        canvas.mouseUp(with: event(.leftMouseUp, 460, 250))
        expect(session.document.items[0].frame.height == 100 && session.document.items[1].frame.x == 340, "Whole original right edge hit strip resizes horizontally in the inter-object gap")
        try session.undo()
        canvas.mouseDown(with: event(.leftMouseDown, 400, 300))
        canvas.mouseDragged(with: event(.leftMouseDragged, 430, 320))
        canvas.flagsChanged(with: flags(.option))
        canvas.mouseUp(with: event(.leftMouseUp, 430, 320, .option))
        expect(session.document.items[0].frame == .init(x: 70, y: 80, width: 120, height: 120), "Changing Option during original drag recomputes centered transform")
        try session.undo()
        canvas.mouseDown(with: event(.leftMouseDown, 400, 300))
        canvas.mouseDragged(with: event(.leftMouseDragged, 430, 320, .option))
        canvas.flagsChanged(with: flags([]))
        canvas.mouseUp(with: event(.leftMouseUp, 430, 320))
        expect(close(session.document.items[0].frame, .init(x: 100, y: 100, width: 110, height: 110)), "Releasing Option restores ordinary anchored transform without cumulative drift")
        try session.undo()
        let saved = session.document
        canvas.mouseDown(with: event(.leftMouseDown, 400, 300))
        canvas.mouseDragged(with: event(.leftMouseDragged, 450, 350))
        canvas.cancelOperation(nil); canvas.mouseUp(with: event(.leftMouseUp, 450, 350))
        expect(session.document == saved, "Escape cancels full group resize and leaves original selection")
        canvas.mouseDown(with: event(.leftMouseDown, 400, 300))
        canvas.mouseDragged(with: event(.leftMouseDragged, 100, 300)); canvas.mouseUp(with: event(.leftMouseUp, 100, 300))
        expect(session.document == saved, "Singular native proposal does not accidentally commit an earlier preview")
        canvas.mouseDown(with: event(.leftMouseDown, 400, 300))
        canvas.mouseDragged(with: event(.leftMouseDragged, 100, 300))
        canvas.mouseDragged(with: event(.leftMouseDragged, 50, 300)); canvas.mouseUp(with: event(.leftMouseUp, 50, 300))
        expect(abs(session.document.items[0].frame.x - 83.3333333333) < 0.00001 && abs(session.document.items[1].frame.x - 50) < 0.00001, "Crossing resumes from original group after zero-width preview refusal")
        try session.undo()
        canvas.mouseDown(with: event(.leftMouseDown, 400, 300))
        canvas.mouseDragged(with: event(.leftMouseDragged, 450, 350))
        try session.perform("Concurrent geometry") { $0.items[1].frame.x += 1 }
        let external = session.document
        canvas.mouseUp(with: event(.leftMouseUp, 450, 350))
        expect(session.document == external, "Original member geometry mutation cancels all resize output")
        try session.undo()
        canvas.mouseDown(with: event(.leftMouseDown, 400, 300))
        canvas.mouseDragged(with: event(.leftMouseDragged, 450, 350))
        try session.perform("Concurrent content") { $0.items[0].color = "#123456" }
        canvas.mouseUp(with: event(.leftMouseUp, 450, 350))
        expect(session.document.items[0].color == "#123456" && session.document.items[1].frame.width > 100, "Native original-group resize preserves same-object concurrent styling")
        try session.undo(); try session.undo()
        let beforeShort = session.document
        canvas.mouseDown(with: event(.leftMouseDown, 150, 150))
        canvas.mouseDragged(with: event(.leftMouseDragged, 153, 150)); canvas.mouseUp(with: event(.leftMouseUp, 153, 150))
        expect(session.document == beforeShort, "Body drag at recovered cumulative three-point threshold cancels")
        canvas.mouseDown(with: event(.leftMouseDown, 150, 150))
        canvas.mouseDragged(with: event(.leftMouseDragged, 154, 150))
        canvas.mouseDragged(with: event(.leftMouseDragged, 151, 150)); canvas.mouseUp(with: event(.leftMouseUp, 151, 150))
        expect(session.document.items[0].frame.x == 101 && session.document.items[1].frame.x == 301, "Body short-drag rule uses cumulative travel, not final displacement")
        try session.undo()
        canvas.mouseDown(with: event(.leftMouseDown, 400, 300))
        canvas.mouseDragged(with: event(.leftMouseDragged, 402, 300)); canvas.mouseUp(with: event(.leftMouseUp, 402, 300))
        expect(session.document.items[1].frame.width > 100, "Frame controls retain separate precise short-resize end route")
        try session.undo()
        let beforeFailure = session.document, path = directory.appendingPathComponent("documents/" + beforeFailure.id.uuidString.lowercased() + ".json")
        let data = try Data(contentsOf: path)
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        canvas.mouseDown(with: event(.leftMouseDown, 400, 300))
        canvas.mouseDragged(with: event(.leftMouseDragged, 450, 350)); canvas.mouseUp(with: event(.leftMouseUp, 450, 350))
        expect(errors == 1 && session.document == beforeFailure, "Native resize reports actual persistence failure without changing original group")
        try FileManager.default.removeItem(at: path); try data.write(to: path)
        canvas.mouseDown(with: event(.leftMouseDown, 400, 300)); canvas.mouseDragged(with: event(.leftMouseDragged, 450, 350))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        canvas.mouseUp(with: event(.leftMouseUp, 450, 350))
        expect(session.document == beforeFailure, "Owning window resignation cancels original group resize")
        expect(!window.isVisible, "Resize component never displayed a window")
    }

    @MainActor static func hitAndGuideInteractions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-hit-guides-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let bottom = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 100, height: 100))
        let top = EaselItem(kind: .circle, frame: bottom.frame, zIndex: 1)
        try session.perform("Seed") { $0.items = [bottom, top] }
        let canvas = EaselCanvasView(session: session)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        func event(_ type: NSEvent.EventType, _ x: Double, _ y: Double, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(.init(x: x, y: y), to: nil), modifierFlags: flags,
                               timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: event(.leftMouseDown, 103, 103)); canvas.mouseUp(with: event(.leftMouseUp, 103, 103))
        let right = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124)!
        canvas.keyDown(with: right)
        expect(session.document.items[0].frame.x == 101 && session.document.items[1].frame.x == 100, "Native click passes through empty ellipse corner to original lower object")
        try session.undo(); canvas.cancelOperation(nil)
        let menu = canvas.menu(for: event(.rightMouseDown, 103, 103))!
        let duplicate = menu.items.first { $0.title == "Duplicate" }!
        _ = NSApp.sendAction(duplicate.action!, to: duplicate.target, from: duplicate)
        expect(session.document.items.last?.kind == .rectangle, "Native contextual hit uses the same actual content delegate")
        try session.undo(); canvas.cancelOperation(nil)
        var target = bottom; target.id = UUID(); target.frame.x = 300
        try session.perform("Guide objects") { $0.items = [bottom, target] }
        canvas.mouseDown(with: event(.leftMouseDown, 150, 150)); canvas.mouseDragged(with: event(.leftMouseDragged, 345, 150))
        expect(session.document.items[0].frame.x == 100, "Guide preview never mutates durable original during drag")
        canvas.mouseUp(with: event(.leftMouseUp, 345, 150))
        expect(session.document.items[0].frame.x == 300, "Native body move acquires actual target alignment")
        try session.undo()
        expect(session.document.items[0].frame.x == 100, "One undo restores full snapped gesture")
        canvas.mouseDown(with: event(.leftMouseDown, 150, 150)); canvas.mouseDragged(with: event(.leftMouseDragged, 345, 150))
        let command = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 55)!
        canvas.flagsChanged(with: command); canvas.mouseUp(with: event(.leftMouseUp, 345, 150, flags: .command))
        expect(session.document.items[0].frame.x == 295, "Command modifier reversibly releases snap without another pointer move")
        try session.undo()
        let preferences = canvas.menu(for: event(.rightMouseDown, 50, 50))!
        let alignment = preferences.items.first { $0.title == "Use Alignment Guides" }!
        expect(canvas.validateMenuItem(alignment) && alignment.state == .on, "Native alignment menu advertises actual enabled state")
        _ = NSApp.sendAction(alignment.action!, to: alignment.target, from: alignment)
        canvas.mouseDown(with: event(.leftMouseDown, 150, 150)); canvas.mouseDragged(with: event(.leftMouseDragged, 345, 150)); canvas.mouseUp(with: event(.leftMouseUp, 345, 150))
        expect(session.document.items[0].frame.x == 295, "Disabled guide preference preserves unmodified pointer transaction")
        try session.undo()
        let staleMenu = canvas.menu(for: event(.rightMouseDown, 50, 50))!
        let staleToggle = staleMenu.items.first { $0.title == "Use Alignment Guides" }!
        window.contentView = nil
        expect(!canvas.validateMenuItem(staleToggle), "Detached original canvas cannot dispatch captured guide preference")
        expect(!window.isVisible, "Hit/guide component never displayed a window")
    }

    @MainActor static func directControlInteractions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-direct-controls-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let arrow = EaselItem(kind: .arrow, frame: .init(x: 100, y: 100, width: 100, height: 80),
                              points: [.init(x: 0, y: 0), .init(x: 100, y: 80)])
        try session.perform("Seed arrow") { $0.items = [arrow] }
        let canvas = EaselCanvasView(session: session)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(NSPoint(x: x, y: y), to: nil), modifierFlags: flags,
                               timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func flags(_ modifiers: NSEvent.ModifierFlags) {
            canvas.flagsChanged(with: NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 0)!)
        }
        func renderedCanvas() -> Data {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 600,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            let context = NSGraphicsContext(bitmapImageRep: bitmap)!
            NSGraphicsContext.current = context
            context.cgContext.translateBy(x: 0, y: 600); context.cgContext.scaleBy(x: 1, y: -1)
            canvas.draw(.init(x: 0, y: 0, width: 800, height: 600))
            NSGraphicsContext.restoreGraphicsState()
            return bitmap.representation(using: .png, properties: [:])!
        }
        canvas.selectAll(nil)
        let selectedArtwork = renderedCanvas()
        canvas.mouseDown(with: mouse(.leftMouseDown, 100, 100))
        expect(renderedCanvas() == selectedArtwork, "Pressing the original endpoint retains its selected mark without an invented pressed fill")
        canvas.mouseDragged(with: mouse(.leftMouseDragged, 250, 220, [.option, .shift, .command]))
        expect(session.document.items[0] == arrow, "Arrow endpoint preview does not publish original content")
        canvas.mouseUp(with: mouse(.leftMouseUp, 250, 220))
        expect(EaselArrowEndpoint.start.point(in: session.document.items[0]) == .init(x: 250, y: 220) && EaselArrowEndpoint.end.point(in: session.document.items[0]) == .init(x: 200, y: 180), "Native original endpoint crosses while modifiers leave its payload owner unchanged")
        try session.undo(); expect(session.document.items[0] == arrow, "Native endpoint drag is exactly one undo")
        canvas.mouseDown(with: mouse(.leftMouseDown, 200, 180))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, 201, 180)); canvas.mouseUp(with: mouse(.leftMouseUp, 201, 180))
        expect(EaselArrowEndpoint.end.point(in: session.document.items[0]) == .init(x: 201, y: 180), "Endpoint direct-end route accepts a precise one-point drag")
        try session.undo()
        canvas.mouseDown(with: mouse(.leftMouseDown, 200, 180)); canvas.mouseDragged(with: mouse(.leftMouseDragged, 220, 200))
        canvas.cancelOperation(nil); canvas.mouseUp(with: mouse(.leftMouseUp, 220, 200))
        expect(session.document.items[0] == arrow, "Escape retires endpoint preview without a durable edit")
        canvas.mouseDown(with: mouse(.leftMouseDown, 200, 180)); canvas.mouseDragged(with: mouse(.leftMouseDragged, 220, 200))
        try session.perform("Original endpoint replaced") { $0.items[0].points[1].x = 80 }
        let external = session.document
        canvas.mouseUp(with: mouse(.leftMouseUp, 220, 200))
        expect(session.document == external, "Replacement of the original endpoint invalidates native commit")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let asset = try session.importPNG(png)
        let image = EaselItem(kind: .image, frame: .init(x: 100, y: 100, width: 200, height: 100), assetID: asset)
        try session.perform("Seed real image") { $0.items = [image] }
        canvas.selectAll(nil)
        canvas.mouseDown(with: mouse(.leftMouseDown, 300, 200)); canvas.mouseDragged(with: mouse(.leftMouseDragged, 400, 200))
        canvas.mouseUp(with: mouse(.leftMouseUp, 400, 200))
        let projected = session.document.items[0]
        expect(abs(projected.frame.width - 280) < 0.000001 && abs(projected.frame.height - 140) < 0.000001, "Native image corner applies real diagonal projection")
        try session.undo()
        canvas.mouseDown(with: mouse(.leftMouseDown, 300, 200)); canvas.mouseDragged(with: mouse(.leftMouseDragged, 400, 200))
        flags(.command); canvas.mouseUp(with: mouse(.leftMouseUp, 400, 200, .command))
        expect(session.document.items[0].frame == .init(x: 100, y: 100, width: 300, height: 100), "Command interrupts aspect preview using the same original frame")
        try session.undo()
        canvas.mouseDown(with: mouse(.leftMouseDown, 300, 200)); canvas.mouseDragged(with: mouse(.leftMouseDragged, 400, 200, .command))
        flags([]); canvas.mouseUp(with: mouse(.leftMouseUp, 400, 200))
        expect(abs(session.document.items[0].frame.height - 140) < 0.000001, "Command release restores aspect without accumulating prior preview")
        try session.undo()
        canvas.mouseDown(with: mouse(.leftMouseDown, 300, 200)); canvas.mouseDragged(with: mouse(.leftMouseDragged, 320, 250, .option))
        canvas.mouseUp(with: mouse(.leftMouseUp, 320, 250, .option))
        expect(session.document.items[0].frame == .init(x: 80, y: 90, width: 240, height: 120), "Native Option uses the recovered centered aspect branch")
        try session.undo()
        canvas.mouseDown(with: mouse(.leftMouseDown, 300, 200)); canvas.mouseDragged(with: mouse(.leftMouseDragged, 400, 200))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        canvas.mouseUp(with: mouse(.leftMouseUp, 400, 200))
        expect(session.document.items[0] == image, "Owner focus loss cancels pending aspect preview")
        let neighbor = EaselItem(kind: .rectangle, frame: .init(x: 300, y: 220, width: 50, height: 60))
        try session.perform("Add guide target") { $0.items.append(neighbor) }
        canvas.mouseDown(with: mouse(.leftMouseDown, 300, 200))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, 348, 224, .shift))
        canvas.mouseUp(with: mouse(.leftMouseUp, 348, 224, .shift))
        expect(abs(session.document.items[0].frame.width - 250.4) < 0.000001,
               "Native Shift guide reads real one-pixel image dimensions without changing its original frame ratio")
        for kind in [EaselItemKind.webCard, .link] {
            var card = image; card.kind = kind; card.url = "https://example.com/"
            try session.perform("Seed intrinsic card") { $0.items = [card] }
            canvas.selectAll(nil)
            try session.perform("Add intrinsic target") { $0.items.append(neighbor) }
            canvas.mouseDown(with: mouse(.leftMouseDown, 300, 200))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, 348, 224, .shift))
            canvas.mouseUp(with: mouse(.leftMouseUp, 348, 224, .shift))
            let expectedWidth = kind == .webCard ? 250.4 : 248 + 1.6 + 0.8 / (220.0 / 160.0)
            expect(abs(session.document.items[0].frame.width - expectedWidth) < 0.000001,
                   "Native Shift guide uses captured web-card pixels or fixed link intrinsic dimensions")
            try session.undo()
            expect(session.document.items[0] == card, "Intrinsic card resize is one original-identity undo")
        }
        expect(try! Data(contentsOf: session.assetURL(asset)) == png, "Native resize leaves original captured image asset bytes intact")
        expect(!window.isVisible, "Direct-control components never present a browser or editor window")
    }

    @MainActor static func magnifiedGuideInteractions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-guide-scale-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let moving = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 50, height: 50))
        let target = EaselItem(kind: .rectangle, frame: .init(x: 200, y: 170, width: 100, height: 50))
        let canvas = EaselCanvasView(session: session)
        canvas.fixedCanvasSize = .init(width: 800, height: 800)
        canvas.setFrameSize(.init(width: 800, height: 800))
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 800, height: 600))
        scroll.documentView = canvas; scroll.allowsMagnification = true
        scroll.minMagnification = 0.25; scroll.maxMagnification = 4; window.contentView = scroll
        defer { window.contentView = nil; window.close() }
        for (scale, speed, expectedX) in [(0.5, 200.0, 198.0), (2.0, 100.0, 200.0)] {
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
            expect(abs(session.document.items[0].frame.x - expectedX) < 0.000001,
                   "Guide admission measures screen velocity exactly once at non-unit magnification")
        }
        expect(!window.isVisible, "Magnified guide checks remain an inert hidden native component")
    }

    @MainActor static func anchorInteractions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-anchors-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let item = EaselItem(kind: .rectangle, frame: .init(x: 350, y: 100, width: 100, height: 100))
        try session.perform("Seed") { $0.items = [item] }
        let canvas = EaselCanvasView(session: session)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        func event(_ type: NSEvent.EventType, _ x: Double, _ y: Double, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(.init(x: x, y: y), to: nil), modifierFlags: flags,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func flags(_ value: NSEvent.ModifierFlags) {
            canvas.flagsChanged(with: NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: value,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58)!)
        }
        canvas.selectAll(nil)
        canvas.mouseDown(with: event(.leftMouseDown, 450, 200))
        canvas.mouseDragged(with: event(.leftMouseDragged, 470, 230))
        expect(session.document.items[0] == item, "Captured anchor preview leaves durable original unchanged")
        flags(.command)
        canvas.mouseUp(with: event(.leftMouseUp, 470, 230, flags: .command))
        expect(session.document.items[0].frame == .init(x: 330, y: 100, width: 140, height: 130), "Native Command keeps captured horizontal symmetry while suppressing new guides")
        try session.undo(); expect(session.document.items[0] == item, "One undo restores entire original anchored resize")
        canvas.mouseDown(with: event(.leftMouseDown, 450, 200))
        canvas.mouseDragged(with: event(.leftMouseDragged, 470, 230))
        flags([.option, .command])
        canvas.mouseUp(with: event(.leftMouseUp, 470, 230, flags: [.option, .command]))
        expect(session.document.items[0].frame == .init(x: 330, y: 70, width: 140, height: 160), "Native Option adds other-axis symmetry during same original gesture")
        try session.undo()
        canvas.mouseDown(with: event(.leftMouseDown, 450, 200))
        canvas.mouseDragged(with: event(.leftMouseDragged, 470, 230, flags: .option))
        flags(.command)
        canvas.mouseUp(with: event(.leftMouseUp, 470, 230, flags: .command))
        expect(session.document.items[0].frame == .init(x: 330, y: 100, width: 140, height: 130), "Native Option release recomputes from original captured axes without extra pointer movement")
        try session.undo()
        canvas.mouseDown(with: event(.leftMouseDown, 450, 200)); canvas.mouseDragged(with: event(.leftMouseDragged, 470, 230))
        canvas.cancelOperation(nil); canvas.mouseUp(with: event(.leftMouseUp, 470, 230))
        expect(session.document.items[0] == item, "Escape retires anchor session and all preview geometry")
        canvas.mouseDown(with: event(.leftMouseDown, 450, 200)); canvas.mouseDragged(with: event(.leftMouseDragged, 470, 230))
        canvas.setFrameSize(.init(width: 900, height: 600)); canvas.mouseUp(with: event(.leftMouseUp, 470, 230))
        expect(session.document.items[0] == item, "Changed logical canvas width cancels rather than retargeting captured center")
        canvas.setFrameSize(.init(width: 800, height: 600))
        canvas.mouseDown(with: event(.leftMouseDown, 450, 200)); canvas.mouseDragged(with: event(.leftMouseDragged, 470, 230))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        canvas.mouseUp(with: event(.leftMouseUp, 470, 230))
        expect(session.document.items[0] == item, "Original window resignation retires captured anchors with original transaction")
        try session.perform("Move original between gestures") { $0.items[0].frame.x += 10 }
        canvas.mouseDown(with: event(.leftMouseDown, 460, 200)); canvas.mouseDragged(with: event(.leftMouseDragged, 480, 230, flags: .command))
        canvas.mouseUp(with: event(.leftMouseUp, 480, 230, flags: .command))
        expect(session.document.items[0].frame == .init(x: 360, y: 100, width: 120, height: 130), "New native gesture recomputes center ownership from actual new original position")
        expect(!window.isVisible, "Anchor component never displayed a window")
    }

    /// Stands in for the engine page view: pasteAndMatchStyle: only.
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
    @MainActor static func incrementalObjectDisplay() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-dirty-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let moved = EaselItem(kind: .rectangle, frame: .init(x: 30, y: 30, width: 50, height: 50))
        let stationary = EaselItem(kind: .circle, frame: .init(x: 130, y: 130, width: 50, height: 50))
        try session.perform("Seed") { $0.items = [moved, stationary] }
        let canvas = EaselCanvasView(session: session)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        canvas.layoutSubtreeIfNeeded()
        expect(!canvas.subviews.contains(where: { NSStringFromClass(type(of: $0)).contains("EaselCanvasArtwork") }),
               "Ordinary software canvas does not host per-object artwork")
        canvas.displayIfNeeded()
        expect(!canvas.needsDisplay, "First software paint clears the canvas dirty flag")
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        expect(!canvas.needsDisplay, "Unchanged software layout does not mark the canvas dirty")
        func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(NSPoint(x: x, y: y), to: nil), modifierFlags: [],
                               timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func drainDocumentPublishes() async {
            for _ in 0..<2 {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
        }
        canvas.mouseDown(with: mouse(.leftMouseDown, 40, 40))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, 100, 100))
        expect(canvas.needsDisplay, "Moving one object still invalidates its dirty region")
        canvas.displayIfNeeded()
        canvas.mouseUp(with: mouse(.leftMouseUp, 100, 100))
        canvas.displayIfNeeded()
        canvas.selectAll(nil)
        expect(canvas.needsDisplay, "Selecting multiple objects still dirties selection chrome")
        canvas.displayIfNeeded()
        expect(!canvas.needsDisplay, "Paint clears multi-select chrome dirty flags")
        // mouseExited always invalidates; with hover already nil this is a pure
        // presentation-fingerprint no-op and must not re-dirty group outlines.
        func exitEvent() -> NSEvent {
            NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [],
                                   timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                   eventNumber: 0, trackingNumber: 0, userData: nil)!
        }
        let skipsBeforeNoop = canvas.presentationNoOpSkipCount
        let dirtyBeforeNoop = canvas.presentationDirtyCount
        canvas.mouseExited(with: exitEvent())
        expect(canvas.presentationNoOpSkipCount == skipsBeforeNoop + 1,
               "Identical presentation invalidation takes the no-op skip")
        expect(canvas.presentationDirtyCount == dirtyBeforeNoop,
               "Identical presentation invalidation does not apply a dirty rect")
        expect(!canvas.needsDisplay,
               "Identical presentation invalidation does not re-dirty multi-select outlines")
        try session.perform("Metadata title") { $0.title = "Presentation fingerprint" }
        await drainDocumentPublishes()
        expect(session.document.title == "Presentation fingerprint", "Metadata title publish actually lands")
        expect(canvas.presentationDirtyCount == dirtyBeforeNoop,
               "Title-only document republish does not apply a dirty rect when presentation matches")
        expect(!canvas.needsDisplay,
               "Title-only document republish with matching presentation does not re-dirty multi-select outlines")
        // Real selection chrome change after a no-op must apply a dirty rect.
        // Probe counts — AX summary after selection mutation can paint immediately.
        let dirtyBeforeClear = canvas.presentationDirtyCount
        canvas.setAccessibilitySelectedChildren([])
        expect(canvas.presentationDirtyCount > dirtyBeforeClear,
               "Clearing selection after a presentation no-op still applies a dirty rect")
        canvas.displayIfNeeded()

        let browser = EaselItem(kind: .browser, frame: .init(x: 80, y: 80, width: 400, height: 300), url: "https://example.org/original")
        let cover = EaselItem(kind: .rectangle, frame: .init(x: 500, y: 40, width: 80, height: 80), zIndex: 2)
        try session.perform("Pages") { $0.items = [browser, cover] }
        await drainDocumentPublishes()
        let pages = PageSurfaces()
        canvas.pageObjects = pages
        canvas.layoutSubtreeIfNeeded()
        let artwork = canvas.subviews.filter { NSStringFromClass(type(of: $0)).contains("EaselCanvasArtwork") }
        expect(artwork.count == 1, "Per-object surfaces stay limited to the non-page cover beside an embedded page")
        canvas.displayIfNeeded()
        expect(artwork.allSatisfy { !$0.needsDisplay }, "First object-surface paint clears cover dirty flags")
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        expect(artwork.allSatisfy { !$0.needsDisplay }, "Unchanged object-surface layout does not dirty every object")
        canvas.selectAll(nil)
        canvas.displayIfNeeded()
        let surfaceDirtyBefore = canvas.presentationDirtyCount
        let surfaceSkipBefore = canvas.presentationNoOpSkipCount
        canvas.mouseExited(with: exitEvent())
        expect(canvas.presentationNoOpSkipCount == surfaceSkipBefore + 1,
               "Identical presentation invalidation skips on object-surface canvas")
        expect(canvas.presentationDirtyCount == surfaceDirtyBefore,
               "Identical presentation invalidation does not dirty object-surface covers")
        try session.perform("Surface metadata") { $0.title = "Object-surface fingerprint" }
        await drainDocumentPublishes()
        expect(session.document.title == "Object-surface fingerprint", "Object-surface metadata title publish lands")
        expect(canvas.presentationDirtyCount == surfaceDirtyBefore,
               "Title-only republish does not dirty object-surface covers when presentation matches")
        expect(!window.isVisible, "Incremental display component never displayed a window")
    }
    @MainActor static func browserObjectCanvas() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-browser-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let browser = EaselItem(kind: .browser, frame: .init(x: 80, y: 80, width: 400, height: 300), url: "https://example.org/original")
        let cover = EaselItem(kind: .rectangle, frame: .init(x: 160, y: 160, width: 80, height: 80), zIndex: 2)
        try session.perform("Seed") { $0.items = [browser, cover] }
        let canvas = EaselCanvasView(session: session), surfaces = PageSurfaces()
        canvas.pageObjects = surfaces
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        canvas.selectBrowserObject(browser.id); canvas.layoutSubtreeIfNeeded()
        func hit(_ point: NSPoint) -> NSView? { canvas.hitTest(canvas.convert(point, to: canvas.superview)) }
        expect(surfaces.view.frame == NSRect(x: 80, y: 80, width: 400, height: 300), "Actual browser surface follows original canvas geometry")
        expect(hit(NSPoint(x: 300, y: 300)) === surfaces.view, "Selected browser body reaches its original native surface")
        expect(hit(NSPoint(x: 190, y: 190)) === canvas, "Higher artwork blocks input to the lower native browser")
        expect(hit(NSPoint(x: 80, y: 80)) === canvas, "Original resize handles retain canvas ownership over native view")
        canvas.cancelOperation(nil); canvas.layoutSubtreeIfNeeded()
        expect(hit(NSPoint(x: 300, y: 300)) === canvas, "Unselected browser cannot consume native page input")
        canvas.selectBrowserObject(browser.id); canvas.layoutSubtreeIfNeeded()
        window.makeFirstResponder(canvas)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 51)!
        canvas.keyDown(with: event)
        expect(session.document.items.count == 2 && surfaces.pending != nil, "Delete waits at actual asynchronous retirement boundary")
        surfaces.pending?(); surfaces.pending = nil
        expect(session.document.items.count == 2, "Refused replacement leaves original objects intact")
        surfaces.approved = true; canvas.keyDown(with: event); canvas.cancelOperation(nil); surfaces.pending?()
        expect(session.document.items.count == 2, "Intervening canvas selection cancels previously approved target")
        canvas.selectBrowserObject(browser.id); canvas.keyDown(with: event); surfaces.pending?()
        expect(session.document.items == [cover], "Approved exact original removal commits only the browser object")
        canvas.undo(nil); surfaces.pending?()
        expect(session.document.items == [browser, cover], "Canvas document undo restores original durable browser identity")
        canvas.selectBrowserObject(browser.id); canvas.layoutSubtreeIfNeeded()
        let page = EnginePage(frame: surfaces.view.bounds); surfaces.view.addSubview(page)
        expect(window.makeFirstResponder(page), "Embedded engine page owns focus")
        let style = NSMenuItem(title: "Paste and Match Style", action: NSSelectorFromString("pasteAsPlainText:"), keyEquivalent: "")
        expect(canvas.validateMenuItem(style), "Focused embedded page validates its own Paste and Match Style")
        page.mainFrame = false
        expect(!canvas.validateMenuItem(style), "Engine validation stays authoritative over canvas paste")
        page.mainFrame = true
        let items = session.document.items
        _ = canvas.perform(NSSelectorFromString("pasteAsPlainText:"), with: style)
        expect(page.requests == 1 && session.document.items == items, "Embedded page receives the paste; canvas inserts no text object")
        _ = window.makeFirstResponder(canvas); page.removeFromSuperview()
        expect(!window.isVisible, "Native canvas component never displayed a window or loaded a page")
    }

}
