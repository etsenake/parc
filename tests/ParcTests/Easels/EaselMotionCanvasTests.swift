import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcEasels

@MainActor private final class CanvasMotionWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}

struct EaselMotionCanvasTests {
    @MainActor
    private struct Board {
        let document: EaselDocument
        let session: EaselSession
        let canvas: EaselCanvasView
        let window: CanvasMotionWindow
        let scroll: NSScrollView

        init(_ object: EaselItem = EaselItem(kind: .rectangle, frame: .init(x: 80, y: 80, width: 100, height: 100))) throws {
            let date = Date(timeIntervalSince1970: 0)
            document = EaselDocument(id: UUID(), title: "Motion", createdAt: date, modifiedAt: date, items: [object])
            session = try EaselSession(inMemory: document, assets: [:])
            canvas = makeTestEaselCanvas(session: session)
            scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            scroll.allowsMagnification = true
            scroll.minMagnification = 0.3333
            scroll.maxMagnification = 4
            scroll.documentView = canvas
            window = CanvasMotionWindow(contentRect: scroll.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = scroll
            canvas.layoutSubtreeIfNeeded()
            canvas.selectAll(nil)
        }

        var handles: [NSAccessibilityElement] {
            (canvas.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityElement }
                .filter { $0.accessibilityRole() == .handle }
        }

        func begin() {
            NotificationCenter.default.post(name: NSScrollView.willStartLiveMagnifyNotification, object: scroll)
        }

        func end() {
            NotificationCenter.default.post(name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)
        }

        func boundsChanged() {
            NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        }
    }

    @MainActor @Test
    func thePinchHidesHandlesAndRejectsTheirRetainedActions() throws {
        let board = try Board()
        let handle = try #require(board.handles.first)
        let retained = try #require(handle.accessibilityCustomActions()?.first)
        board.scroll.magnification = 0.8
        board.begin()
        #expect(board.handles.isEmpty)
        #expect(retained.handler?() == false && board.session.document == board.document)
    }

    @MainActor @Test
    func theCanvasCoversItsViewportWhileZoomedOut() throws {
        let board = try Board()
        board.begin()
        board.scroll.magnification = 0.5
        board.boundsChanged()
        let extent = board.canvas.frame.size
        #expect(extent.width >= board.scroll.contentView.bounds.width)
        #expect(extent.height >= board.scroll.contentView.bounds.height)
        board.boundsChanged()
        #expect(board.canvas.frame.size == extent && board.session.document == board.document)
    }

    @MainActor @Test(arguments: [false, true])
    func endingOrResigningThePinchRestoresHandles(_ resign: Bool) throws {
        let board = try Board()
        board.begin()
        try #require(board.handles.isEmpty)
        if resign {
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: board.window)
        } else {
            board.end()
        }
        #expect(!board.handles.isEmpty && board.session.document == board.document)
    }

    @MainActor @Test
    func aRetainedEdgeRechecksEligibilityAfterZooming() throws {
        let small = EaselItem(kind: .rectangle, frame: .init(x: 80, y: 80, width: 40, height: 40))
        let board = try Board(small)
        let edge = try #require(board.handles.first { $0.accessibilityLabel() == "Resize Right" })
        let action = try #require(edge.accessibilityCustomActions()?.first)
        board.begin()
        board.scroll.magnification = 0.5
        board.end()
        #expect(!board.handles.contains { $0.accessibilityLabel() == "Resize Right" })
        #expect(action.handler?() == false && board.session.document == board.document)
    }

    @MainActor @Test
    func pinchingRejectsRetainedArrowEndpoints() throws {
        let arrow = EaselItem(kind: .arrow, frame: .init(x: 80, y: 80, width: 100, height: 100),
                              points: [.init(x: 0, y: 100), .init(x: 100, y: 0)])
        let board = try Board(arrow)
        #expect(board.handles.count == 2)
        let node = try #require(board.handles.first)
        let action = try #require(node.accessibilityCustomActions()?.first)
        board.begin()
        #expect(board.handles.isEmpty && action.handler?() == false)
        #expect(board.session.document.items == [arrow])
    }

    @MainActor @Test
    func aFixedCaptureCanvasDoesNotExpandToTheViewport() throws {
        let board = try Board()
        board.canvas.fixedCanvasSize = NSSize(width: 40, height: 20)
        board.canvas.resizeCanvas(viewport: NSSize(width: 800, height: 600))
        #expect(board.canvas.frame.size == NSSize(width: 40, height: 20))
    }

}
