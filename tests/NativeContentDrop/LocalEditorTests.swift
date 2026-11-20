import AppKit

@MainActor class LayoutView: NSView {}
@MainActor enum SidebarSplitDrag { static let pasteboardType = NSPasteboard.PasteboardType("org.parc.sidebar-split-drag") }
@MainActor enum SidebarMoveSession { static let pasteboardType = NSPasteboard.PasteboardType("org.parc.sidebar-item-move") }

@MainActor final class LocalDrag: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .copy
    var draggingLocation = NSPoint(x: 400, y: 300)
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
    func write(_ text: String) {
        draggingSequenceNumber += 1; draggingPasteboard.clearContents()
        let item = NSPasteboardItem(); item.setString(text, forType: .string); draggingPasteboard.writeObjects([item])
    }
}

@main @MainActor struct LocalEditorDropTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ reason: String) throws {
        count += 1; if try !value() { throw NSError(domain: reason, code: count) }
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-local-drop-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let noteFile = root.appendingPathComponent("Original Note.md"), noteBytes = Data("Original\n".utf8)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try noteBytes.write(to: noteFile)
        let easelStore = try EaselStore(directory: root.appendingPathComponent("easels"))
        let easel = try easelStore.create()
        let canvas = EaselCanvasView(session: easel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = ExternalSplitDropHost(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.addSubview(canvas); canvas.frame = host.bounds
        let drag = LocalDrag(); drag.draggingDestinationWindow = window
        defer { drag.draggingPasteboard.releaseGlobally() }
        var valid = true, commits = 0
        host.makeSession = { _, info in
            guard valid, canvas.canAcceptExternalSplitDrop else { return nil }
            return ExternalSplitDropSession(host: host, info: info, frames: [host.bounds], orientation: .horizontal,
                validate: { valid && canvas.canAcceptExternalSplitDrop },
                insertionColor: { .black }, canPropose: { _, _ in true }, commit: { _, _ in commits += 1; return true })
        }
        drag.write("ordinary canvas text")
        try check(canvas.draggingEntered(drag) == .copy && canvas.performDragOperation(drag), "non-URL canvas text falls back to genuine Easel import")
        try check(easel.document.items.contains { $0.text == "ordinary canvas text" }, "fallback creates actual durable text object")
        let previous = easel.document
        drag.write("https://drop.invalid/canvas")
        try check(canvas.draggingEntered(drag) == .copy && canvas.performDragOperation(drag), "canvas URL uses same native split router")
        try check(easel.document == previous, "claimed canvas URL creates no fake web card")
        canvas.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(NSPoint(x: 700, y: 500), to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        try check(!canvas.canAcceptExternalSplitDrop, "actual in-progress canvas gesture cannot be displaced")
        canvas.cancelOperation(nil)
        try check(canvas.canAcceptExternalSplitDrop, "cancelled original canvas gesture permits a later drop")
        let browser = try BrowserStore(directory: root.appendingPathComponent("browser"))
        let noteID = browser.openNote(url: noteFile, title: "Original Note")!
        let easelID = browser.openEasel(id: easel.document.id, title: "Original Easel")!
        browser.setSplit([noteID, easelID])
        let original = browser.state, group = browser.activeSplitLayout!, newID = UUID()
        let easelBefore = easel.document
        try check(try browser.dropExternalURLIntoSplit(URL(string: "https://drop.invalid/new")!, tabID: newID,
            spaceID: browser.activeSpaceID, profileID: browser.activeSpace.profileID,
            expectedSelection: [noteID, easelID], expectedLayout: group, target: .replace(0), orientation: .horizontal, creation: nil), "real mixed document split replacement persists")
        try check(browser.state.tabs.first { $0.id == noteID } == original.tabs.first { $0.id == noteID }, "displaced Note original reference retained")
        try check(browser.state.tabs.first { $0.id == easelID }?.url == original.tabs.first { $0.id == easelID }?.url, "retained Easel original reference retained")
        try check(try Data(contentsOf: noteFile) == noteBytes && easel.document == easelBefore, "split creation never writes original documents")
        let reloaded = try BrowserStore(directory: root.appendingPathComponent("browser"))
        try check(reloaded.activeSplitLayout?.id == group.id && reloaded.activeSplitLayout?.tabIDs == [newID, easelID], "mixed split group identity survives persistence")
        try easelStore.delete(easel.document.id)
        try check(!canvas.canAcceptExternalSplitDrop, "deleted shared Easel session cannot admit a split target")
        print("Local editor native split drops: \(count) checks passed")
    }
}
