import AppKit
import Testing
@testable import ParcCore
@testable import ParcEasels

struct EaselCanvasTestsKeyboardStops {
    private typealias AccessibilityBoard = EaselCanvasTestsSupport.AccessibilityBoard
    private typealias ManualQueue = EaselCanvasTestsSupport.ManualQueue

    @MainActor @Test
    func drawingSuspendsObjectKeyboardStops() throws {
        let board = try AccessibilityBoard()
        defer { board.close() }
        let canvas = board.canvas
        let queue = ManualQueue()
        canvas.scheduleAfterInteraction = queue.schedule
        canvas.keyboardStructureChanged()
        queue.runPending()
        var relinks = 0
        canvas.onKeyboardStructureChange = { relinks += 1 }
        queue.runPending(); let beforeDrawing = relinks
        canvas.drawing = true; queue.runPending()
        #expect(relinks > beforeDrawing && canvas.objectKeyViews.allSatisfy { !$0.acceptsFirstResponder }, "Drawing transition rebuilds the native object chain with its real eligibility")
    }

    @MainActor @Test
    func leavingDrawingRestoresObjectKeyboardStops() throws {
        let board = try AccessibilityBoard()
        defer { board.close() }
        let canvas = board.canvas
        let queue = ManualQueue()
        canvas.scheduleAfterInteraction = queue.schedule
        canvas.keyboardStructureChanged()
        queue.runPending()
        var relinks = 0
        canvas.onKeyboardStructureChange = { relinks += 1 }
        canvas.drawing = true; queue.runPending()
        let duringDrawing = relinks
        canvas.drawing = false; queue.runPending()
        #expect(relinks > duringDrawing && canvas.objectKeyViews.allSatisfy(\.acceptsFirstResponder), "Returning to Select restores native object chain without an unrelated layout")
    }

    @MainActor @Test
    func anActivePointerTransactionSuspendsKeyboardStops() throws {
        let queue = ManualQueue()
        let board = try AccessibilityBoard(queue: queue)
        defer { board.close() }
        let canvas = board.canvas
        let window = board.window
        let second = try board.node(for: board.shape)
        #expect(second.accessibilityPerformPress(), "Other object admits native focus without synthetic key traversal")
        canvas.keyboardStructureChanged()
        queue.runPending()
        func pointer(_ type: NSEvent.EventType, x: Double) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(NSPoint(x: x, y: 80), to: nil), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: pointer(.leftMouseDown, x: 260)); canvas.mouseDragged(with: pointer(.leftMouseDragged, x: 268))
        _ = canvas.accessibilityChildren(); queue.runPending()
        #expect(canvas.objectKeyViews.allSatisfy { !$0.acceptsFirstResponder }, "A real pending pointer transaction suspends object focus stops")
    }

    @MainActor @Test
    func pointerRetirementRelinksKeyboardNavigation() throws {
        let queue = ManualQueue()
        let board = try AccessibilityBoard(queue: queue)
        defer { board.close() }
        let canvas = board.canvas
        let window = board.window
        let second = try board.node(for: board.shape)
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
        canvas.mouseUp(with: pointer(.leftMouseUp, x: 268)); queue.runPending()
        #expect(relinks > duringPointer && canvas.objectKeyViews.allSatisfy(\.acceptsFirstResponder), "Pointer retirement relinks objects even when final geometry matches the last preview")
    }

    @MainActor @Test
    func detachingTheCanvasRefusesRetainedAccessibilityActions() throws {
        let board = try AccessibilityBoard()
        defer { board.close() }
        let window = board.window
        let second = try board.node(for: board.shape)
        #expect(second.accessibilityPerformPress(), "Other object admits native focus without synthetic key traversal")
        let detached = second.accessibilityCustomActions()!.first { $0.name == "Duplicate" }!
        window.contentView = nil
        #expect(detached.handler?() == false && !second.accessibilityPerformPress(), "Detached original window refuses retained actions and focus")
        #expect(!window.isVisible, "Accessibility component never displays or drives a browser or AX server")
    }

    @MainActor @Test
    func retiringTheSessionRefusesRetainedAccessibilityActions() throws {
        let board = try AccessibilityBoard()
        defer { board.close() }
        let store = board.store
        let session = board.session
        let canvas = board.canvas
        let window = board.window
        let second = try board.node(for: board.shape)
        #expect(second.accessibilityPerformPress(), "Other object admits native focus without synthetic key traversal")
        let detached = second.accessibilityCustomActions()!.first { $0.name == "Duplicate" }!
        window.contentView = nil
        window.contentView = canvas
        try store.retireSessionForRelocation(session.document.id)
        #expect(!second.accessibilityPerformPress() && detached.handler?() == false, "A retired cross-Profile session cannot regain object focus or action authority")
        #expect(!window.isVisible, "Accessibility component never displays or drives a browser or AX server")
    }
}
