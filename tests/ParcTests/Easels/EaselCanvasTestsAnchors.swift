import AppKit
import Testing
@testable import ParcCore

struct EaselCanvasTestsAnchors {
    private typealias GestureBoard = EaselCanvasTestsSupport.GestureBoard

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
}
