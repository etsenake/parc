import AppKit
import ParcCore
import Testing
@testable import Parc
@testable import ParcEasels

@MainActor private final class Scene {
    let root: URL
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
    let host = ExternalSplitDropHost(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let routing = SplitDropRoutingPane(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let easelStore: EaselStore
    let easel: EaselSession
    let canvas: EaselCanvasView
    let drag: SplitDropDragInfo
    var valid = true
    var commits = 0

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-local-drop-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        easelStore = try EaselStore(directory: root.appendingPathComponent("easels"))
        easel = try easelStore.create()
        canvas = makeTestEaselCanvas(session: easel)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.addSubview(routing)
        routing.addSubview(canvas)
        canvas.frame = routing.bounds
        drag = SplitDropDragInfo(window: window, location: NSPoint(x: 400, y: 300))
        host.makeSession = { [weak self] _, info in
            guard let self, valid, canvas.canAcceptExternalSplitDrop else { return nil }
            return ExternalSplitDropSession(host: host, info: info, frames: [host.bounds], orientation: .horizontal,
                validate: { [weak self] in (self?.valid ?? false) && self?.canvas.canAcceptExternalSplitDrop == true },
                insertionColor: { .black }, canPropose: { _, _ in true }, commit: { [weak self] _, _ in self?.commits += 1; return true })
        }
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}

@MainActor struct LocalEditorDropTests {
    @Test func nonLinkCanvasTextFallsBackToAGenuineEaselImport() throws {
        let scene = try Scene()
        scene.drag.writeText("ordinary canvas text")
        #expect(scene.canvas.draggingEntered(scene.drag) == .copy)
        #expect(scene.canvas.performDragOperation(scene.drag))
        #expect(scene.easel.document.items.contains { $0.text == "ordinary canvas text" })
    }

    @Test func aCanvasLinkUsesTheSameNativeSplitRouterAndCreatesNoWebCard() throws {
        let scene = try Scene()
        let previous = scene.easel.document
        scene.drag.writeText("https://drop.invalid/canvas")
        #expect(scene.canvas.draggingEntered(scene.drag) == .copy)
        #expect(scene.canvas.performDragOperation(scene.drag))
        #expect(scene.easel.document == previous)
        #expect(scene.commits == 1)
    }

    @Test func anInProgressCanvasGestureCannotBeDisplacedUntilItIsCancelled() throws {
        let scene = try Scene()
        let location = scene.canvas.convert(NSPoint(x: 700, y: 500), to: nil)
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
            windowNumber: scene.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        scene.canvas.mouseDown(with: down)
        #expect(!scene.canvas.canAcceptExternalSplitDrop)
        scene.canvas.cancelOperation(nil)
        #expect(scene.canvas.canAcceptExternalSplitDrop)
    }

    @Test func aDeletedSharedEaselSessionCannotAdmitASplitTarget() throws {
        let scene = try Scene()
        try scene.easelStore.delete(scene.easel.document.id)
        #expect(!scene.canvas.canAcceptExternalSplitDrop)
    }

    @MainActor private final class MixedSplit {
        let root: URL
        let noteFile: URL
        let noteBytes = Data("Original\n".utf8)
        let easelStore: EaselStore
        let easel: EaselSession
        let browser: BrowserStore
        let noteID: UUID, easelID: UUID
        let original: BrowserState
        let group: BrowserSplitLayout
        let easelBefore: EaselDocument

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-mixed-split-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            noteFile = root.appendingPathComponent("Original Note.md")
            try noteBytes.write(to: noteFile)
            easelStore = try EaselStore(directory: root.appendingPathComponent("easels"))
            easel = try easelStore.create()
            browser = try BrowserStore(directory: root.appendingPathComponent("browser"))
            noteID = browser.openNote(url: noteFile, title: "Original Note")!
            easelID = browser.openEasel(id: easel.document.id, title: "Original Easel")!
            browser.setSplit([noteID, easelID])
            original = browser.state
            group = browser.activeSplitLayout!
            easelBefore = easel.document
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func replaceFirstPane(with newID: UUID) throws -> Bool {
            try browser.dropExternalURLIntoSplit(URL(string: "https://drop.invalid/new")!, tabID: newID,
                spaceID: browser.activeSpaceID, profileID: browser.activeSpace.profileID,
                expectedSelection: [noteID, easelID], expectedLayout: group, target: .replace(0), orientation: .horizontal, creation: nil)
        }
    }

    @Test func aMixedDocumentSplitReplacementPersistsAndRetainsTheOriginalReferences() throws {
        let mixed = try MixedSplit()
        #expect(try mixed.replaceFirstPane(with: UUID()))
        #expect(mixed.browser.state.tabs.first { $0.id == mixed.noteID } == mixed.original.tabs.first { $0.id == mixed.noteID })
        #expect(mixed.browser.state.tabs.first { $0.id == mixed.easelID }?.url == mixed.original.tabs.first { $0.id == mixed.easelID }?.url)
    }

    @Test func splitCreationNeverWritesTheOriginalDocuments() throws {
        let mixed = try MixedSplit()
        _ = try mixed.replaceFirstPane(with: UUID())
        #expect(try Data(contentsOf: mixed.noteFile) == mixed.noteBytes)
        #expect(mixed.easel.document == mixed.easelBefore)
    }

    @Test func theMixedSplitGroupIdentitySurvivesPersistence() throws {
        let mixed = try MixedSplit()
        let newID = UUID()
        _ = try mixed.replaceFirstPane(with: newID)
        let reloaded = try BrowserStore(directory: mixed.root.appendingPathComponent("browser"))
        #expect(reloaded.activeSplitLayout?.id == mixed.group.id)
        #expect(reloaded.activeSplitLayout?.tabIDs == [newID, mixed.easelID])
    }
}
