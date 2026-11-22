import AppKit
import Testing
@testable import Parc
@testable import ParcCore

enum EaselCanvasTestsSupport {
    @MainActor final class RecordedPanel: EaselPanelHandle {
        var isOpen = true
        func close() { isOpen = false }
    }

    @MainActor final class RecordingPanels: EaselPanelPresenting {
        var links: [EaselLinkRequest] = []
        var sizes: [EaselTextSizeRequest] = []
        var staysOpen = true
        private func handle() -> EaselPanelHandle {
            let panel = RecordedPanel()
            panel.isOpen = staysOpen
            return panel
        }
        func presentLinkEditor(_ request: EaselLinkRequest) -> EaselPanelHandle? { links.append(request); return handle() }
        func presentTextSizeEditor(_ request: EaselTextSizeRequest) -> EaselPanelHandle? { sizes.append(request); return handle() }
        func hoverLink(_ request: EaselLinkHoverRequest?) {}
    }

    @MainActor final class FormatKeyWindow: NSWindow {
        var key = true
        override var isKeyWindow: Bool { key }
    }

    @MainActor final class CapturedCanvasMenu: EaselCanvasMenuPresenting {
        var rows: [EaselMenuRow] = []
        var isOpen = false
        func present(_ rows: [EaselMenuRow], in host: NSView, anchor: NSRect, keyboard: Bool, label: String) {
            self.rows = rows; isOpen = true
        }
        func close(animated: Bool) { isOpen = false }
    }

    @MainActor final class CanvasTextDrop: NSObject, NSDraggingInfo {
        var draggingDestinationWindow: NSWindow?
        var draggingSourceOperationMask: NSDragOperation = .copy
        var draggingLocation = NSPoint.zero
        var draggedImageLocation = NSPoint.zero
        nonisolated var draggedImage: NSImage? { nil }
        let draggingPasteboard = NSPasteboard.withUniqueName()
        var draggingSource: Any?
        var draggingSequenceNumber = 1
        var draggingFormation = NSDraggingFormation.default
        var animatesToDestination = false
        var numberOfValidItemsForDrop = 1
        var springLoadingHighlight = NSSpringLoadingHighlight.none
        func slideDraggedImage(to screenPoint: NSPoint) {}
        nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
        func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
        func resetSpringLoading() {}
    }

    enum CanvasFixtureError: Error { case missingEditor }

    @MainActor
    final class ManualQueue {
        private var work: [() -> Void] = []

        func schedule(_ job: @escaping () -> Void) { work.append(job) }

        func runPending() {
            let current = work
            work.removeAll()
            current.forEach { $0() }
        }
    }

    @MainActor
    static func contextMenu(_ canvas: EaselCanvasView, _ event: NSEvent) -> [EaselMenuRow] {
        let presenter = CapturedCanvasMenu()
        canvas.arrangeState.menu = presenter
        canvas.rightMouseDown(with: event)
        return presenter.rows
    }

    @MainActor
    static func menuRow(_ rows: [EaselMenuRow], _ title: String) throws -> EaselMenuRow {
        try #require(rows.first { $0.title == title })
    }

    @MainActor
    final class Board {
        let directory: URL
        let session: EaselSession
        let canvas: EaselCanvasView
        let window: NSWindow
        let a = EaselItem(kind: .rectangle, frame: .init(x: 30, y: 30, width: 50, height: 50))
        let b = EaselItem(kind: .circle, frame: .init(x: 130, y: 130, width: 50, height: 50))
        let c = EaselItem(kind: .text, frame: .init(x: 500, y: 30, width: 150, height: 80), text: "Native text")
        var errors = 0

        init() throws {
            _ = NSApplication.shared
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            session = try EaselStore(directory: directory).create()
            let originals = [a, b, c]
            try session.perform("Seed") { $0.items = originals }
            canvas = EaselCanvasView(session: session)
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = canvas
            canvas.onError = { [weak self] _ in self?.errors += 1 }
        }

        func close() {
            window.contentView = nil
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }

        func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double, flags: NSEvent.ModifierFlags = [], clicks: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(NSPoint(x: x, y: y), to: nil), modifierFlags: flags,
                               timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        func key(_ code: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }
        func marquee(_ x: Double, _ y: Double, _ endX: Double, _ endY: Double, flags: NSEvent.ModifierFlags = []) {
            canvas.mouseDown(with: mouse(.leftMouseDown, x, y, flags: flags))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, endX, endY, flags: flags))
            canvas.mouseUp(with: mouse(.leftMouseUp, endX, endY, flags: flags))
        }
    }

    @MainActor
    final class GestureBoard {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session: EaselSession
        let canvas: EaselCanvasView
        let window: NSWindow
        var errors = 0

        init(_ items: [EaselItem]) throws {
            _ = NSApplication.shared
            session = try EaselStore(directory: directory).create()
            try session.perform("Seed") { $0.items = items }
            canvas = EaselCanvasView(session: session)
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = canvas
            canvas.onError = { [weak self] _ in self?.errors += 1 }
        }

        func close() {
            window.contentView = nil
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }

        func event(_ type: NSEvent.EventType, _ x: Double, _ y: Double, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(NSPoint(x: x, y: y), to: nil), modifierFlags: flags,
                               timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }

        func modifiers(_ value: NSEvent.ModifierFlags) {
            let event = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: value,
                                        timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "",
                                        charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58)!
            canvas.flagsChanged(with: event)
        }
    }

    @MainActor final class EnginePage: NSView {
        var requests = 0, mainFrame = true
        override var acceptsFirstResponder: Bool { true }
        @objc func pasteAndMatchStyle(_ sender: Any?) { requests += 1 }
        @objc func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool { mainFrame }
    }
    @MainActor final class PageSurfaces: EaselBrowserObjectHosting {
        let view = NSView()
        var approved = false
        var pending: (() -> Void)?
        func surface(for item: EaselItem) -> NSView? { item.kind == .browser ? view : nil }
        func synchronize(items: [EaselItem], selection: Set<UUID>, interacting: Bool) {}
        func prepareReplacement(_ next: EaselDocument, valid: @escaping () -> Bool, completion: @escaping (Bool) -> Void) {
            pending = { [weak self] in completion(self?.approved == true && valid()) }
        }
    }

    @MainActor
    final class FormatBoard {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-format-" + UUID().uuidString)
        let session: EaselSession
        let canvas: EaselCanvasView
        let window: FormatKeyWindow
        private(set) var items: [TextFormatCommand: NSMenuItem] = [:]

        init() throws {
            session = try EaselStore(directory: directory).create()
            let shape = EaselItem(kind: .rectangle, frame: .init(x: 600, y: 400, width: 60, height: 60))
            try session.perform("Seed") { $0.items = [shape] }
            canvas = EaselCanvasView(session: session)
            _ = NSApplication.shared
            window = FormatKeyWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = canvas
            TextFormatMenu.add(to: NSMenu(title: "Edit")) { item, command in self.items[command] = item }
        }

        func close() {
            window.contentView = nil
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }

        func startEditing() throws -> EaselStyledTextView {
            #expect(canvas.insert(kind: .text, text: "Format me", edit: true), "A text object enters native editing")
            let editor = try #require(canvas.editor)
            editor.localUndo.groupsByEvent = false
            return editor
        }

        func run(_ command: TextFormatCommand, in editor: EaselStyledTextView) {
            editor.localUndo.beginUndoGrouping()
            perform(command)
            editor.localUndo.endUndoGrouping()
        }

        func owner() -> NSResponder? {
            var responder = window.firstResponder
            while let current = responder, !current.responds(to: TextFormatCommand.action) { responder = current.nextResponder }
            return responder
        }
        func validate(_ command: TextFormatCommand) -> Bool { (owner() as? NSMenuItemValidation)?.validateMenuItem(items[command]!) ?? false }
        func state(_ command: TextFormatCommand) -> NSControl.StateValue { _ = validate(command); return items[command]!.state }
        func perform(_ command: TextFormatCommand) { _ = window.firstResponder?.tryToPerform(TextFormatCommand.action, with: items[command]!) }
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
    }

    @MainActor
    final class AccessibilityBoard {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-canvas-accessibility-" + UUID().uuidString)
        let store: EaselStore
        let session: EaselSession
        let text = EaselItem(kind: .text, frame: .init(x: 30, y: 30, width: 160, height: 80), text: "Original words")
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 240, y: 50, width: 80, height: 90))
        let canvas: EaselCanvasView
        let window: NSWindow

        init(queue: ManualQueue? = nil) throws {
            store = try EaselStore(directory: directory)
            session = try store.create()
            let items = [text, shape]
            try session.perform("Seed") { $0.items = items }
            canvas = EaselCanvasView(session: session)
            if let queue { canvas.scheduleAfterInteraction = queue.schedule }
            _ = NSApplication.shared
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = canvas
        }

        func close() {
            window.contentView = nil
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }

        func node(for item: EaselItem) throws -> NSView {
            let nodes = canvas.accessibilityChildren()!.compactMap { $0 as? NSView }
            return try #require(nodes.first { $0.accessibilityIdentifier() == "easel-object-" + item.id.uuidString })
        }
    }
}
