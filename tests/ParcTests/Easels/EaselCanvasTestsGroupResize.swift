import AppKit
import Testing
@testable import ParcCore

struct EaselCanvasTestsGroupResize {
    private typealias GestureBoard = EaselCanvasTestsSupport.GestureBoard

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
}
