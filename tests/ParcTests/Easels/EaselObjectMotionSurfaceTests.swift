import AppKit
import QuartzCore
import Testing
@testable import ParcCore
@testable import ParcEasels

@MainActor
struct EaselObjectMotionSurfaceTests {
    @MainActor
    private final class Board {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-object-motion-" + UUID().uuidString)
        let session: EaselSession
        let canvas: EaselCanvasView
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        let surfaces = EaselCanvasTestsSupport.PageSurfaces()
        let left: UUID, right: UUID
        var now: CFTimeInterval = 100
        var reduced = false

        init() throws {
            _ = NSApplication.shared
            session = try EaselStore(directory: directory).create()
            let page = EaselItem(kind: .browser, frame: .init(x: 40, y: 300, width: 300, height: 200), url: "https://example.org")
            let first = EaselItem(kind: .rectangle, frame: .init(x: 40, y: 40, width: 120, height: 80), zIndex: 1)
            let second = EaselItem(kind: .rectangle, frame: .init(x: 400, y: 120, width: 120, height: 80), zIndex: 2)
            left = first.id; right = second.id
            try session.perform("Seed") { $0.items = [page, first, second] }
            canvas = makeTestEaselCanvas(session: session)
            canvas.pageObjects = surfaces
            canvas.objectMotion.frameTime = { [unowned self] in self.now }
            canvas.objectMotion.reducesMotion = { [unowned self] in self.reduced }
            scroll.documentView = canvas
            window.isReleasedWhenClosed = false
            window.contentView = scroll
            canvas.layoutSubtreeIfNeeded()
        }

        func card(_ id: UUID) -> EaselCanvasArtwork? {
            canvas.subviews.lazy.compactMap { $0 as? EaselCanvasArtwork }.first { $0.id == id }
        }

        func motion(_ view: NSView?, _ path: String, vanishing: Bool = false) -> CAKeyframeAnimation? {
            view?.layer?.animation(forKey: "parc.easel.motion." + (vanishing ? "vanish." : "") + path) as? CAKeyframeAnimation
        }

        func paint(_ id: UUID) throws {
            let view = try #require(card(id))
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            view.needsDisplay = false
        }

        func finish() {
            now += 2
            canvas.objectMotionFrame()
            canvas.layoutSubtreeIfNeeded()
        }

        func close() {
            canvas.settleObjectMotion()
            window.contentView = nil
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test func anArrangeGlideMovesTheObjectViewAndEndsAtItsFinalFrame() throws {
        let board = try Board()
        defer { board.close() }
        #expect(board.canvas.usesObjectSurfaces)
        try board.paint(board.right)
        board.canvas.selection = [board.left, board.right]
        #expect(board.canvas.alignSelection(.left))
        board.canvas.layoutSubtreeIfNeeded()
        let view = try #require(board.card(board.right))
        let landed = view.frame
        let glide = try #require(board.motion(view, "position"))
        #expect(glide.isAdditive)
        #expect((glide.values?.last as? NSValue)?.pointValue == .zero)
        #expect((glide.values?.first as? NSValue)?.pointValue.x != 0)
        for step in 1...10 {
            board.now += 0.03
            #expect(board.canvas.objectMotionFrame())
            #expect(view.needsDisplay == false, "frame \(step) moves the view without redrawing it")
        }
        board.finish()
        #expect(board.canvas.objectMotion.timeline.isEmpty)
        #expect(!board.canvas.objectMotionFrame())
        #expect(board.card(board.right) === view)
        #expect(view.frame == landed)
        #expect(CATransform3DIsIdentity(try #require(view.layer).transform))
        #expect(view.layer?.opacity == 1)
    }

    @Test func anInsertedObjectGrowsInOnItsOwnViewAndSettlesWhole() throws {
        let board = try Board()
        defer { board.close() }
        let before = Set(board.session.document.items.map(\.id))
        #expect(board.canvas.insert(kind: .rectangle, at: NSPoint(x: 500, y: 400)))
        board.canvas.layoutSubtreeIfNeeded()
        let added = try #require(board.session.document.items.map(\.id).first { !before.contains($0) })
        let view = try #require(board.card(added))
        let grow = try #require(board.motion(view, "transform"))
        #expect(!CATransform3DIsIdentity(try #require((grow.values?.first as? NSValue)?.caTransform3DValue)))
        #expect(CATransform3DIsIdentity(try #require((grow.values?.last as? NSValue)?.caTransform3DValue)))
        let fade = try #require(board.motion(view, "opacity"))
        #expect((fade.values?.first as? Double).map { $0 < 1 } == true)
        #expect(fade.values?.last as? Double == 1)
        board.finish()
        #expect(board.canvas.objectMotion.timeline.isEmpty)
        #expect(board.card(added) === view)
        #expect(view.layer?.opacity == 1)
        #expect(CATransform3DIsIdentity(try #require(view.layer).transform))
    }

    @Test func aDeletedObjectFadesOutOnItsOwnViewAndThenLeaves() throws {
        let board = try Board()
        defer { board.close() }
        let view = try #require(board.card(board.left))
        let gone = board.left
        #expect(board.canvas.withObjectMotion(.vanish) { board.canvas.commit("Delete") { $0.items.removeAll { $0.id == gone } } })
        board.canvas.layoutSubtreeIfNeeded()
        #expect(board.canvas.artwork[gone] == nil)
        #expect(view.superview === board.canvas, "the leaving view stays on the board while it fades")
        let fade = try #require(board.motion(view, "opacity", vanishing: true))
        #expect(fade.values?.last as? Double == 0)
        #expect(fade.isRemovedOnCompletion == false)
        board.finish()
        #expect(board.canvas.objectMotion.timeline.isEmpty)
        board.canvas.settleObjectMotion()
        #expect(view.superview == nil)
    }

    @Test func reduceMotionTurnsAGlideIntoAShortFadeWithoutMovingTheView() throws {
        let board = try Board()
        defer { board.close() }
        board.reduced = true
        board.canvas.selection = [board.left, board.right]
        #expect(board.canvas.alignSelection(.left))
        board.canvas.layoutSubtreeIfNeeded()
        let view = try #require(board.card(board.right))
        let transition = try #require(board.canvas.objectMotion.timeline.transition(for: board.right))
        #expect(transition.reduced)
        #expect(transition.duration == EaselObjectTransition.reducedFade)
        #expect(board.motion(view, "position") == nil)
        #expect(board.motion(view, "transform") == nil)
        let fade = try #require(board.motion(view, "opacity"))
        #expect(fade.values?.last as? Double == 1)
        board.finish()
        #expect(board.canvas.objectMotion.timeline.isEmpty)
        #expect(view.layer?.opacity == 1)
        #expect(CATransform3DIsIdentity(try #require(view.layer).transform))
    }

    @Test func settlingMidMotionLeavesEveryObjectViewAtRest() throws {
        let board = try Board()
        defer { board.close() }
        board.canvas.selection = [board.left, board.right]
        #expect(board.canvas.alignSelection(.left))
        board.canvas.layoutSubtreeIfNeeded()
        let view = try #require(board.card(board.right))
        try #require(board.motion(view, "position") != nil)
        board.now += 0.1
        board.canvas.settleObjectMotion()
        #expect(board.canvas.objectMotion.timeline.isEmpty)
        #expect(board.motion(view, "position") == nil)
        #expect(!board.canvas.objectMotionFrame())
    }
}
