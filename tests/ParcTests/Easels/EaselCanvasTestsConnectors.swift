import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcEasels

struct EaselCanvasTestsConnectors {
    private typealias GestureBoard = EaselCanvasTestsSupport.GestureBoard

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
}
