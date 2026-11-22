import AppKit
import Testing
@testable import ParcCore
@testable import ParcEasels

struct EaselCanvasTestsAccessibility {
    private typealias AccessibilityBoard = EaselCanvasTestsSupport.AccessibilityBoard

    @MainActor @Test
    func accessibleObjectsExposeTheirOwnSpokenIdentity() throws {
        let board = try AccessibilityBoard()
        defer { board.close() }
        let first = try board.node(for: board.text)
        let second = try board.node(for: board.shape)
        #expect(first.accessibilityValue() as? String == board.text.text && second.accessibilityLabel() == "Rectangle", "Each durable object has its own spoken identity/value")
    }

    @MainActor @Test
    func pressingAnAccessibleObjectSelectsAndFocusesIt() throws {
        let board = try AccessibilityBoard()
        defer { board.close() }
        let canvas = board.canvas
        let window = board.window
        let first = try board.node(for: board.text)
        #expect(first.accessibilityPerformPress() && window.firstResponder === first, "Native object press selects and focuses its actual canvas stop")
        #expect(first.isAccessibilitySelected() && (canvas.accessibilitySelectedChildren()?.first as? NSView) === first, "AX selected children agrees with actual original selection")
        #expect((canvas.accessibilityFocusedUIElement as? NSView) === first, "Canvas reports actual object focus")
    }

    @MainActor @Test
    func anAccessibleObjectKeepsItsFrameWithoutTakingPointerInput() throws {
        let board = try AccessibilityBoard()
        defer { board.close() }
        let canvas = board.canvas
        let first = try board.node(for: board.text)
        #expect(first.frame == NSRect(x: 30, y: 30, width: 160, height: 80) && canvas.hitTest(NSPoint(x: 40, y: 40)) !== first, "Object focus view retains geometry without taking pointer input")
    }

    @MainActor @Test
    func aRetainedAccessibleActionRefusesChangedOriginalContent() throws {
        let board = try AccessibilityBoard()
        defer { board.close() }
        let session = board.session
        let first = try board.node(for: board.text)
        let stale = first.accessibilityCustomActions()!.first { $0.name == "Duplicate" }!
        try session.perform("Other owner") { $0.items[0].text = "New original words" }
        #expect(stale.handler?() == false && session.document.items.count == 2, "Retained action refuses changed original content")
    }

    @MainActor @Test
    func selectingAnAccessibleRectangleExposesEightResizeHandles() throws {
        let board = try AccessibilityBoard()
        defer { board.close() }
        let canvas = board.canvas
        let second = try board.node(for: board.shape)
        #expect(second.accessibilityPerformPress(), "Other object admits native focus without synthetic key traversal")
        let handles = canvas.accessibilityChildren()!.compactMap { $0 as? NSAccessibilityElement }
        #expect(handles.count == 8, "Selected rectangle exposes exactly its eight visible frame controls")
    }

    @MainActor @Test
    func anAccessibleResizeChangesOnePointAndIsUndoable() throws {
        let board = try AccessibilityBoard()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        let shape = board.shape
        let second = try board.node(for: board.shape)
        #expect(second.accessibilityPerformPress(), "Other object admits native focus without synthetic key traversal")
        let handles = canvas.accessibilityChildren()!.compactMap { $0 as? NSAccessibilityElement }
        let right = handles.first { $0.accessibilityLabel() == "Resize Right" }!
        let resize = right.accessibilityCustomActions()!.first { $0.name == "Move right" }!
        #expect(resize.handler?() == true && session.document.items[1].frame.width == 81, "AX frame action applies original geometry transaction")
        try session.undo()
        #expect(session.document.items[1].frame == shape.frame, "Accessible frame manipulation has one durable undo")
    }

    @MainActor @Test
    func aRetainedResizeActionRefusesChangedGeometry() throws {
        let board = try AccessibilityBoard()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        let second = try board.node(for: board.shape)
        #expect(second.accessibilityPerformPress(), "Other object admits native focus without synthetic key traversal")
        let handles = canvas.accessibilityChildren()!.compactMap { $0 as? NSAccessibilityElement }
        let right = handles.first { $0.accessibilityLabel() == "Resize Right" }!
        let resize = right.accessibilityCustomActions()!.first { $0.name == "Move right" }!
        #expect(resize.handler?() == true && session.document.items[1].frame.width == 81, "AX frame action applies original geometry transaction")
        #expect(resize.handler?() == false, "Retained control cannot replay against changed original geometry")
    }

    @MainActor @Test
    func accessibleSelectionAcceptsTheOriginalObjects() throws {
        let board = try AccessibilityBoard()
        defer { board.close() }
        let canvas = board.canvas
        let first = try board.node(for: board.text)
        let second = try board.node(for: board.shape)
        canvas.setAccessibilitySelectedChildren([first, second])
        #expect(canvas.accessibilitySelectedChildren()?.count == 2, "Canvas accepts exact original multi-selection")
    }

    @MainActor @Test
    func foreignAccessibleChildrenCannotReplaceTheSelection() throws {
        let board = try AccessibilityBoard()
        defer { board.close() }
        let canvas = board.canvas
        let first = try board.node(for: board.text)
        let second = try board.node(for: board.shape)
        canvas.setAccessibilitySelectedChildren([first, second])
        canvas.setAccessibilitySelectedChildren([NSView()])
        #expect(canvas.accessibilitySelectedChildren()?.count == 2, "Foreign AX children cannot replace selection")
    }

    @MainActor @Test
    func accessibleTextEditingUsesTheLatestContent() throws {
        let board = try AccessibilityBoard()
        defer { board.close() }
        let window = board.window
        let first = try board.node(for: board.text)
        try board.session.perform("Other owner") { $0.items[0].text = "New original words" }
        let edit = first.accessibilityCustomActions()!.first { $0.name == "Edit text" }!
        #expect(edit.handler?() == true, "Text activation reaches existing native editor")
        let editor = first.accessibilityChildren()!.first as! EaselStyledTextView
        #expect(window.firstResponder === editor && editor.string == "New original words", "Object children retain actual text editor and latest content")
    }

    @MainActor @Test
    func accessibleObjectPressDoesNotInterruptComposition() throws {
        let board = try AccessibilityBoard()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        let window = board.window
        let first = try board.node(for: board.text)
        let second = try board.node(for: board.shape)
        try session.perform("Other owner") { $0.items[0].text = "New original words" }
        let edit = first.accessibilityCustomActions()!.first { $0.name == "Edit text" }!
        #expect(edit.handler?() == true, "Text activation reaches existing native editor")
        let editor = first.accessibilityChildren()!.first as! EaselStyledTextView
        #expect(window.firstResponder === editor && editor.string == "New original words", "Object children retain actual text editor and latest content")
        editor.setMarkedText("composition", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!second.accessibilityPerformPress() && window.firstResponder === editor, "Object action does not commit or steal native composition")
        editor.unmarkText(); canvas.cancelOperation(nil)
    }

    @MainActor @Test
    func accessibleObjectFocusResumesAfterEditing() throws {
        let board = try AccessibilityBoard()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        let first = try board.node(for: board.text)
        let second = try board.node(for: board.shape)
        try session.perform("Other owner") { $0.items[0].text = "New original words" }
        let edit = first.accessibilityCustomActions()!.first { $0.name == "Edit text" }!
        #expect(edit.handler?() == true, "Text activation reaches existing native editor")
        let editor = first.accessibilityChildren()!.first as! EaselStyledTextView
        editor.setMarkedText("composition", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.unmarkText(); canvas.cancelOperation(nil)
        #expect(second.accessibilityPerformPress(), "Native object focus resumes after editor dismissal")
    }

    @MainActor @Test
    func accessibleConnectorEndpointsRetainTheirOriginalLease() throws {
        let board = try AccessibilityBoard()
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        let second = try board.node(for: board.shape)
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
        let board = try AccessibilityBoard()
        defer { board.close() }
        let directory = board.directory
        let session = board.session
        let second = try board.node(for: board.shape)
        #expect(second.accessibilityPerformPress(), "Other object admits native focus without synthetic key traversal")
        let failed = second.accessibilityCustomActions()!.first { $0.name == "Duplicate" }!
        let original = session.document
        let path = directory.appendingPathComponent("documents/" + original.id.uuidString.lowercased() + ".json")
        let bytes = try Data(contentsOf: path)
        try FileManager.default.removeItem(at: path); try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        #expect(failed.handler?() == false && session.document == original, "Failed persistence is not reported as a successful accessible duplicate")
        try FileManager.default.removeItem(at: path); try bytes.write(to: path)
    }
}
