import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct EaselCanvasTestsEmbeddedPages {
    private typealias EnginePage = EaselCanvasTestsSupport.EnginePage
    private typealias PageSurfaces = EaselCanvasTestsSupport.PageSurfaces

    @MainActor @Test
    func anEmbeddedPageFollowsItsCanvasFrame() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-browser-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let browser = EaselItem(kind: .browser, frame: .init(x: 80, y: 80, width: 400, height: 300), url: "https://example.org/original")
        let cover = EaselItem(kind: .rectangle, frame: .init(x: 160, y: 160, width: 80, height: 80), zIndex: 2)
        try session.perform("Seed") { $0.items = [browser, cover] }
        let canvas = EaselCanvasView(session: session), surfaces = PageSurfaces()
        canvas.pageObjects = surfaces
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        canvas.selectBrowserObject(browser.id); canvas.layoutSubtreeIfNeeded()
        #expect(surfaces.view.frame == NSRect(x: 80, y: 80, width: 400, height: 300), "Actual browser surface follows original canvas geometry")
    }

    @MainActor @Test
    func aSelectedPageRoutesInputToItsNativeSurface() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-browser-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let browser = EaselItem(kind: .browser, frame: .init(x: 80, y: 80, width: 400, height: 300), url: "https://example.org/original")
        let cover = EaselItem(kind: .rectangle, frame: .init(x: 160, y: 160, width: 80, height: 80), zIndex: 2)
        try session.perform("Seed") { $0.items = [browser, cover] }
        let canvas = EaselCanvasView(session: session), surfaces = PageSurfaces()
        canvas.pageObjects = surfaces
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        canvas.selectBrowserObject(browser.id); canvas.layoutSubtreeIfNeeded()
        func hit(_ point: NSPoint) -> NSView? { canvas.hitTest(canvas.convert(point, to: canvas.superview)) }
        #expect(hit(NSPoint(x: 300, y: 300)) === surfaces.view, "Selected browser body reaches its original native surface")
    }

    @MainActor @Test
    func higherArtworkBlocksEmbeddedPageInput() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-browser-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let browser = EaselItem(kind: .browser, frame: .init(x: 80, y: 80, width: 400, height: 300), url: "https://example.org/original")
        let cover = EaselItem(kind: .rectangle, frame: .init(x: 160, y: 160, width: 80, height: 80), zIndex: 2)
        try session.perform("Seed") { $0.items = [browser, cover] }
        let canvas = EaselCanvasView(session: session), surfaces = PageSurfaces()
        canvas.pageObjects = surfaces
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        canvas.selectBrowserObject(browser.id); canvas.layoutSubtreeIfNeeded()
        func hit(_ point: NSPoint) -> NSView? { canvas.hitTest(canvas.convert(point, to: canvas.superview)) }
        #expect(hit(NSPoint(x: 190, y: 190)) === canvas, "Higher artwork blocks input to the lower native browser")
    }

    @MainActor @Test
    func resizeHandlesRetainCanvasInput() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-browser-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let browser = EaselItem(kind: .browser, frame: .init(x: 80, y: 80, width: 400, height: 300), url: "https://example.org/original")
        let cover = EaselItem(kind: .rectangle, frame: .init(x: 160, y: 160, width: 80, height: 80), zIndex: 2)
        try session.perform("Seed") { $0.items = [browser, cover] }
        let canvas = EaselCanvasView(session: session), surfaces = PageSurfaces()
        canvas.pageObjects = surfaces
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        canvas.selectBrowserObject(browser.id); canvas.layoutSubtreeIfNeeded()
        func hit(_ point: NSPoint) -> NSView? { canvas.hitTest(canvas.convert(point, to: canvas.superview)) }
        #expect(hit(NSPoint(x: 80, y: 80)) === canvas, "Original resize handles retain canvas ownership over native view")
    }

    @MainActor @Test
    func anUnselectedPageCannotConsumeCanvasInput() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-browser-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let browser = EaselItem(kind: .browser, frame: .init(x: 80, y: 80, width: 400, height: 300), url: "https://example.org/original")
        let cover = EaselItem(kind: .rectangle, frame: .init(x: 160, y: 160, width: 80, height: 80), zIndex: 2)
        try session.perform("Seed") { $0.items = [browser, cover] }
        let canvas = EaselCanvasView(session: session), surfaces = PageSurfaces()
        canvas.pageObjects = surfaces
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        canvas.selectBrowserObject(browser.id); canvas.layoutSubtreeIfNeeded()
        func hit(_ point: NSPoint) -> NSView? { canvas.hitTest(canvas.convert(point, to: canvas.superview)) }
        canvas.cancelOperation(nil); canvas.layoutSubtreeIfNeeded()
        #expect(hit(NSPoint(x: 300, y: 300)) === canvas, "Unselected browser cannot consume native page input")
    }

    @MainActor @Test
    func deleteWaitsForEmbeddedPageRetirement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-browser-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let browser = EaselItem(kind: .browser, frame: .init(x: 80, y: 80, width: 400, height: 300), url: "https://example.org/original")
        let cover = EaselItem(kind: .rectangle, frame: .init(x: 160, y: 160, width: 80, height: 80), zIndex: 2)
        try session.perform("Seed") { $0.items = [browser, cover] }
        let canvas = EaselCanvasView(session: session), surfaces = PageSurfaces()
        canvas.pageObjects = surfaces
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        canvas.selectBrowserObject(browser.id); canvas.layoutSubtreeIfNeeded()
        window.makeFirstResponder(canvas)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 51)!
        canvas.keyDown(with: event)
        #expect(session.document.items.count == 2 && surfaces.pending != nil, "Delete waits at actual asynchronous retirement boundary")
    }

    @MainActor @Test
    func refusedRetirementLeavesTheEmbeddedPageInPlace() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-browser-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let browser = EaselItem(kind: .browser, frame: .init(x: 80, y: 80, width: 400, height: 300), url: "https://example.org/original")
        let cover = EaselItem(kind: .rectangle, frame: .init(x: 160, y: 160, width: 80, height: 80), zIndex: 2)
        try session.perform("Seed") { $0.items = [browser, cover] }
        let canvas = EaselCanvasView(session: session), surfaces = PageSurfaces()
        canvas.pageObjects = surfaces
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        canvas.selectBrowserObject(browser.id); canvas.layoutSubtreeIfNeeded()
        window.makeFirstResponder(canvas)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 51)!
        canvas.keyDown(with: event)
        surfaces.pending?(); surfaces.pending = nil
        #expect(session.document.items.count == 2, "Refused replacement leaves original objects intact")
    }

    @MainActor @Test
    func aSelectionChangeInvalidatesPreviouslyApprovedRetirement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-browser-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let browser = EaselItem(kind: .browser, frame: .init(x: 80, y: 80, width: 400, height: 300), url: "https://example.org/original")
        let cover = EaselItem(kind: .rectangle, frame: .init(x: 160, y: 160, width: 80, height: 80), zIndex: 2)
        try session.perform("Seed") { $0.items = [browser, cover] }
        let canvas = EaselCanvasView(session: session), surfaces = PageSurfaces()
        canvas.pageObjects = surfaces
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        canvas.selectBrowserObject(browser.id); canvas.layoutSubtreeIfNeeded()
        window.makeFirstResponder(canvas)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 51)!
        surfaces.approved = true; canvas.keyDown(with: event); canvas.cancelOperation(nil); surfaces.pending?()
        #expect(session.document.items.count == 2, "Intervening canvas selection cancels previously approved target")
    }

    @MainActor @Test
    func approvedRetirementRemovesOnlyThePageAndUndoRestoresIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-browser-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let browser = EaselItem(kind: .browser, frame: .init(x: 80, y: 80, width: 400, height: 300), url: "https://example.org/original")
        let cover = EaselItem(kind: .rectangle, frame: .init(x: 160, y: 160, width: 80, height: 80), zIndex: 2)
        try session.perform("Seed") { $0.items = [browser, cover] }
        let canvas = EaselCanvasView(session: session), surfaces = PageSurfaces()
        canvas.pageObjects = surfaces
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        canvas.selectBrowserObject(browser.id); canvas.layoutSubtreeIfNeeded()
        window.makeFirstResponder(canvas)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 51)!
        surfaces.approved = true
        canvas.selectBrowserObject(browser.id); canvas.keyDown(with: event); surfaces.pending?()
        #expect(session.document.items == [cover], "Approved exact original removal commits only the browser object")
        canvas.undo(nil); surfaces.pending?()
        #expect(session.document.items == [browser, cover], "Canvas document undo restores original durable browser identity")
    }

    @MainActor @Test
    func theFocusedEmbeddedPageOwnsPasteValidation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-browser-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let browser = EaselItem(kind: .browser, frame: .init(x: 80, y: 80, width: 400, height: 300), url: "https://example.org/original")
        let cover = EaselItem(kind: .rectangle, frame: .init(x: 160, y: 160, width: 80, height: 80), zIndex: 2)
        try session.perform("Seed") { $0.items = [browser, cover] }
        let canvas = EaselCanvasView(session: session), surfaces = PageSurfaces()
        canvas.pageObjects = surfaces
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        canvas.selectBrowserObject(browser.id); canvas.layoutSubtreeIfNeeded()
        let page = EnginePage(frame: surfaces.view.bounds); surfaces.view.addSubview(page)
        #expect(window.makeFirstResponder(page), "Embedded engine page owns focus")
        let style = NSMenuItem(title: "Paste and Match Style", action: NSSelectorFromString("pasteAsPlainText:"), keyEquivalent: "")
        #expect(canvas.validateMenuItem(style), "Focused embedded page validates its own Paste and Match Style")
        page.mainFrame = false
        #expect(!canvas.validateMenuItem(style), "Engine validation stays authoritative over canvas paste")
        _ = window.makeFirstResponder(canvas); page.removeFromSuperview()
    }

    @MainActor @Test
    func theFocusedEmbeddedPageReceivesPasteDispatch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-browser-canvas-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let browser = EaselItem(kind: .browser, frame: .init(x: 80, y: 80, width: 400, height: 300), url: "https://example.org/original")
        let cover = EaselItem(kind: .rectangle, frame: .init(x: 160, y: 160, width: 80, height: 80), zIndex: 2)
        try session.perform("Seed") { $0.items = [browser, cover] }
        let canvas = EaselCanvasView(session: session), surfaces = PageSurfaces()
        canvas.pageObjects = surfaces
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        defer { window.contentView = nil; window.close() }
        canvas.selectBrowserObject(browser.id); canvas.layoutSubtreeIfNeeded()
        let page = EnginePage(frame: surfaces.view.bounds); surfaces.view.addSubview(page)
        #expect(window.makeFirstResponder(page), "Embedded engine page owns focus")
        let style = NSMenuItem(title: "Paste and Match Style", action: NSSelectorFromString("pasteAsPlainText:"), keyEquivalent: "")
        let items = session.document.items
        _ = canvas.perform(NSSelectorFromString("pasteAsPlainText:"), with: style)
        #expect(page.requests == 1 && session.document.items == items, "Embedded page receives the paste; canvas inserts no text object")
        _ = window.makeFirstResponder(canvas); page.removeFromSuperview()
    }
}
