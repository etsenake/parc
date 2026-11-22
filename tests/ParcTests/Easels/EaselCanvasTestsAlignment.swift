import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcEasels

struct EaselCanvasTestsAlignment {
    private typealias GestureBoard = EaselCanvasTestsSupport.GestureBoard

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
        try EaselCanvasTestsSupport.menuRow(EaselCanvasTestsSupport.contextMenu(canvas, board.event(.rightMouseDown, 103, 103)), "Duplicate").perform?()
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
        let alignment = try EaselCanvasTestsSupport.menuRow(EaselCanvasTestsSupport.contextMenu(canvas, board.event(.rightMouseDown, 50, 50)), "Use Alignment Guides")
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
        let staleToggle = try EaselCanvasTestsSupport.menuRow(EaselCanvasTestsSupport.contextMenu(canvas, board.event(.rightMouseDown, 50, 50)), "Use Alignment Guides")
        board.window.contentView = nil
        let guidesBefore = canvas.alignmentGuidesEnabled
        staleToggle.perform?()
        #expect(canvas.alignmentGuidesEnabled == guidesBefore, "Detached original canvas cannot dispatch captured guide preference")
    }
}
