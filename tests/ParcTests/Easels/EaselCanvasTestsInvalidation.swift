import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct EaselCanvasTestsInvalidation {
    private typealias GestureBoard = EaselCanvasTestsSupport.GestureBoard
    private typealias PageSurfaces = EaselCanvasTestsSupport.PageSurfaces

    @MainActor @Test
    func aCanvasWithoutEmbeddedPagesUsesSoftwarePaint() throws {
        let board = try GestureBoard([
            EaselItem(kind: .rectangle, frame: .init(x: 30, y: 30, width: 50, height: 50)),
            EaselItem(kind: .circle, frame: .init(x: 130, y: 130, width: 50, height: 50)),
        ])
        defer { board.close() }
        let canvas = board.canvas
        canvas.layoutSubtreeIfNeeded()
        #expect(!canvas.subviews.contains(where: { NSStringFromClass(type(of: $0)).contains("EaselCanvasArtwork") }),
               "Ordinary software canvas does not host per-object artwork")
        canvas.displayIfNeeded()
        #expect(!canvas.needsDisplay, "First software paint clears the canvas dirty flag")
    }

    @MainActor @Test
    func unchangedSoftwareLayoutLeavesTheCanvasClean() throws {
        let board = try GestureBoard([
            EaselItem(kind: .rectangle, frame: .init(x: 30, y: 30, width: 50, height: 50)),
            EaselItem(kind: .circle, frame: .init(x: 130, y: 130, width: 50, height: 50)),
        ])
        defer { board.close() }
        let canvas = board.canvas
        canvas.layoutSubtreeIfNeeded()
        canvas.displayIfNeeded()
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        #expect(!canvas.needsDisplay, "Unchanged software layout does not mark the canvas dirty")
    }

    @MainActor @Test
    func movingOneObjectDirtiesItsCanvasRegion() throws {
        let board = try GestureBoard([
            EaselItem(kind: .rectangle, frame: .init(x: 30, y: 30, width: 50, height: 50)),
            EaselItem(kind: .circle, frame: .init(x: 130, y: 130, width: 50, height: 50)),
        ])
        defer { board.close() }
        let canvas = board.canvas
        let window = board.window
        canvas.layoutSubtreeIfNeeded()
        canvas.displayIfNeeded()
        func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(NSPoint(x: x, y: y), to: nil), modifierFlags: [],
                               timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: mouse(.leftMouseDown, 40, 40))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, 100, 100))
        #expect(canvas.needsDisplay, "Moving one object still invalidates its dirty region")
    }

    @MainActor @Test
    func aMultiSelectionDirtiesItsChromeUntilPainted() throws {
        let board = try GestureBoard([
            EaselItem(kind: .rectangle, frame: .init(x: 30, y: 30, width: 50, height: 50)),
            EaselItem(kind: .circle, frame: .init(x: 130, y: 130, width: 50, height: 50)),
        ])
        defer { board.close() }
        let canvas = board.canvas
        let window = board.window
        canvas.layoutSubtreeIfNeeded()
        canvas.displayIfNeeded()
        func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(NSPoint(x: x, y: y), to: nil), modifierFlags: [],
                               timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: mouse(.leftMouseDown, 40, 40))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, 100, 100))
        canvas.displayIfNeeded()
        canvas.mouseUp(with: mouse(.leftMouseUp, 100, 100))
        canvas.displayIfNeeded()
        canvas.selectAll(nil)
        #expect(canvas.needsDisplay, "Selecting multiple objects still dirties selection chrome")
        canvas.displayIfNeeded()
        #expect(!canvas.needsDisplay, "Paint clears multi-select chrome dirty flags")
    }

    @MainActor @Test
    func identicalSoftwarePresentationSkipsDirtyRects() throws {
        let board = try GestureBoard([
            EaselItem(kind: .rectangle, frame: .init(x: 30, y: 30, width: 50, height: 50)),
            EaselItem(kind: .circle, frame: .init(x: 130, y: 130, width: 50, height: 50)),
        ])
        defer { board.close() }
        let canvas = board.canvas
        let window = board.window
        canvas.layoutSubtreeIfNeeded()
        canvas.displayIfNeeded()
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
        canvas.displayIfNeeded()
        canvas.mouseUp(with: mouse(.leftMouseUp, 100, 100))
        canvas.displayIfNeeded()
        canvas.selectAll(nil)
        canvas.displayIfNeeded()
        let skipsBeforeNoop = canvas.presentationNoOpSkipCount
        let dirtyBeforeNoop = canvas.presentationDirtyCount
        canvas.mouseExited(with: exitEvent())
        #expect(canvas.presentationNoOpSkipCount == skipsBeforeNoop + 1,
               "Identical presentation invalidation takes the no-op skip")
        #expect(canvas.presentationDirtyCount == dirtyBeforeNoop,
               "Identical presentation invalidation does not apply a dirty rect")
        #expect(!canvas.needsDisplay,
               "Identical presentation invalidation does not re-dirty multi-select outlines")
    }

    @MainActor @Test
    func titleChangesLeaveSoftwareArtworkClean() throws {
        let board = try GestureBoard([
            EaselItem(kind: .rectangle, frame: .init(x: 30, y: 30, width: 50, height: 50)),
            EaselItem(kind: .circle, frame: .init(x: 130, y: 130, width: 50, height: 50)),
        ])
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        let window = board.window
        canvas.layoutSubtreeIfNeeded()
        canvas.displayIfNeeded()
        func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(NSPoint(x: x, y: y), to: nil), modifierFlags: [],
                               timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: mouse(.leftMouseDown, 40, 40))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, 100, 100))
        canvas.displayIfNeeded()
        canvas.mouseUp(with: mouse(.leftMouseUp, 100, 100))
        canvas.displayIfNeeded()
        canvas.selectAll(nil)
        canvas.displayIfNeeded()
        let dirtyBeforeNoop = canvas.presentationDirtyCount
        try session.perform("Metadata title") { $0.title = "Presentation fingerprint" }
        canvas.documentDidChange()
        #expect(session.document.title == "Presentation fingerprint", "Metadata title publish actually lands")
        #expect(canvas.presentationDirtyCount == dirtyBeforeNoop,
               "Title-only document republish does not apply a dirty rect when presentation matches")
    }

    @MainActor @Test
    func startingStickyEditingInvalidatesItsDrawnText() throws {
        let board = try GestureBoard([
            EaselItem(kind: .rectangle, frame: .init(x: 30, y: 30, width: 50, height: 50)),
            EaselItem(kind: .circle, frame: .init(x: 130, y: 130, width: 50, height: 50)),
        ])
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
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
    }

    @MainActor @Test
    func finishingStickyEditingInvalidatesItsDrawnText() throws {
        let board = try GestureBoard([
            EaselItem(kind: .rectangle, frame: .init(x: 30, y: 30, width: 50, height: 50)),
            EaselItem(kind: .circle, frame: .init(x: 130, y: 130, width: 50, height: 50)),
        ])
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        let sticky = EaselItem(kind: .sticky, frame: .init(x: 300, y: 300, width: 220, height: 220), text: "Hello world 23")
        try session.perform("Sticky") { $0.items.append(sticky) }
        canvas.documentDidChange()
        let placed = try #require(session.document.items.first { $0.id == sticky.id })
        canvas.selection = [sticky.id]
        canvas.displayIfNeeded()
        canvas.beginEditing(placed)
        canvas.displayIfNeeded()
        let dirtyBeforeFinishing = canvas.presentationDirtyCount
        canvas.finishEditing()
        #expect(canvas.editingID == nil && canvas.selection == [sticky.id], "Finishing the edit keeps the sticky selected")
        #expect(canvas.presentationDirtyCount > dirtyBeforeFinishing && canvas.needsDisplay,
               "Finishing a sticky edit with nothing else changed repaints the sticky so its text comes back")
        canvas.displayIfNeeded()
    }

    @MainActor @Test
    func onlyTheCoverGetsAnArtworkSurfaceBesideAPage() throws {
        let board = try GestureBoard([
            EaselItem(kind: .rectangle, frame: .init(x: 30, y: 30, width: 50, height: 50)),
            EaselItem(kind: .circle, frame: .init(x: 130, y: 130, width: 50, height: 50)),
        ])
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
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
    }

    @MainActor @Test
    func unchangedLayoutLeavesPageNeighborArtworkClean() throws {
        let board = try GestureBoard([
            EaselItem(kind: .rectangle, frame: .init(x: 30, y: 30, width: 50, height: 50)),
            EaselItem(kind: .circle, frame: .init(x: 130, y: 130, width: 50, height: 50)),
        ])
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        let browser = EaselItem(kind: .browser, frame: .init(x: 80, y: 80, width: 400, height: 300), url: "https://example.org/original")
        let cover = EaselItem(kind: .rectangle, frame: .init(x: 500, y: 40, width: 80, height: 80), zIndex: 2)
        try session.perform("Pages") { $0.items = [browser, cover] }
        canvas.documentDidChange()
        let pages = PageSurfaces()
        canvas.pageObjects = pages
        canvas.layoutSubtreeIfNeeded()
        let artwork = canvas.subviews.filter { NSStringFromClass(type(of: $0)).contains("EaselCanvasArtwork") }
        canvas.displayIfNeeded()
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        #expect(artwork.allSatisfy { !$0.needsDisplay }, "Unchanged object-surface layout does not dirty every object")
    }

    @MainActor @Test
    func identicalPresentationSkipsPageNeighborDirtyRects() throws {
        let board = try GestureBoard([
            EaselItem(kind: .rectangle, frame: .init(x: 30, y: 30, width: 50, height: 50)),
            EaselItem(kind: .circle, frame: .init(x: 130, y: 130, width: 50, height: 50)),
        ])
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        let window = board.window
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
        _ = artwork
        canvas.displayIfNeeded()
        canvas.selectAll(nil)
        canvas.displayIfNeeded()
        let surfaceDirtyBefore = canvas.presentationDirtyCount
        let surfaceSkipBefore = canvas.presentationNoOpSkipCount
        canvas.mouseExited(with: exitEvent())
        #expect(canvas.presentationNoOpSkipCount == surfaceSkipBefore + 1,
               "Identical presentation invalidation skips on object-surface canvas")
        #expect(canvas.presentationDirtyCount == surfaceDirtyBefore,
               "Identical presentation invalidation does not dirty object-surface covers")
    }

    @MainActor @Test
    func titleOnlyChangesKeepPageNeighborArtworkClean() throws {
        let board = try GestureBoard([
            EaselItem(kind: .rectangle, frame: .init(x: 30, y: 30, width: 50, height: 50)),
            EaselItem(kind: .circle, frame: .init(x: 130, y: 130, width: 50, height: 50)),
        ])
        defer { board.close() }
        let session = board.session
        let canvas = board.canvas
        let window = board.window
        let browser = EaselItem(kind: .browser, frame: .init(x: 80, y: 80, width: 400, height: 300), url: "https://example.org/original")
        let cover = EaselItem(kind: .rectangle, frame: .init(x: 500, y: 40, width: 80, height: 80), zIndex: 2)
        try session.perform("Pages") { $0.items = [browser, cover] }
        canvas.documentDidChange()
        let pages = PageSurfaces()
        canvas.pageObjects = pages
        canvas.layoutSubtreeIfNeeded()
        canvas.displayIfNeeded()
        canvas.selectAll(nil)
        canvas.displayIfNeeded()
        let surfaceDirtyBefore = canvas.presentationDirtyCount
        try session.perform("Surface metadata") { $0.title = "Object-surface fingerprint" }
        canvas.documentDidChange()
        #expect(session.document.title == "Object-surface fingerprint", "Object-surface metadata title publish lands")
        #expect(canvas.presentationDirtyCount == surfaceDirtyBefore,
               "Title-only republish does not dirty object-surface covers when presentation matches")
        #expect(!window.isVisible, "Incremental display component never displayed a window")
    }
}
