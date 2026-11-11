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
    static func main() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-local-drop-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let noteStore = try NoteStore.sharedStore(directory: root.appendingPathComponent("notes"), diskSaveDelay: 0)
        let note = try noteStore.create()
        let editor = try NoteEditorViewController(directory: root.appendingPathComponent("notes"), documentID: note.document.id)
        let easelStore = try EaselStore(directory: root.appendingPathComponent("easels"))
        let easel = try easelStore.create()
        let canvas = EaselCanvasView(session: easel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = ExternalSplitDropHost(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.addSubview(editor.view); editor.view.frame = host.bounds; editor.view.layoutSubtreeIfNeeded()
        let drag = LocalDrag(); drag.draggingDestinationWindow = window
        defer { drag.draggingPasteboard.releaseGlobally() }
        var valid = true, commits = 0
        host.makeSession = { _, info in
            guard valid, editor.canAcceptExternalSplitDrop, canvas.canAcceptExternalSplitDrop else { return nil }
            return ExternalSplitDropSession(host: host, info: info, frames: [host.bounds], orientation: .horizontal,
                validate: { valid && editor.canAcceptExternalSplitDrop && canvas.canAcceptExternalSplitDrop },
                insertionColor: { .black }, canPropose: { _, _ in true }, commit: { _, _ in commits += 1; return true })
        }
        for text in [editor.titleText as NSTextView, editor.text] {
            drag.write("https://drop.invalid/original?q=a+b")
            let before = text.attributedString(), selected = text.selectedRanges
            try check(text.draggingEntered(drag) == .copy, "actual native text receiver claims URL")
            try check(text.prepareForDragOperation(drag), "native text prepare reaches original session")
            let old = commits
            try check(text.performDragOperation(drag) && commits == old + 1, "text receiver commits split once")
            try check(!text.performDragOperation(drag) && commits == old + 1, "duplicate drop cannot become text insertion")
            try check(text.attributedString().isEqual(to: before) && text.selectedRanges == selected, "claimed drop preserves original text/ranges")
            text.concludeDragOperation(drag)
        }
        drag.write("https://drop.invalid/expired")
        _ = editor.text.draggingEntered(drag); valid = false
        let beforeExpired = editor.text.attributedString(), old = commits
        try check(editor.text.draggingUpdated(drag).isEmpty && !editor.text.performDragOperation(drag), "expired owner refuses without fallback")
        try check(commits == old && editor.text.attributedString().isEqual(to: beforeExpired), "expired URL never edits text")
        valid = true
        drag.write("https://drop.invalid/detached"); _ = editor.text.draggingEntered(drag)
        let parent = editor.text.superview!; editor.text.removeFromSuperview()
        try check(!editor.text.performDragOperation(drag) && commits == old, "detached late perform remains a consumed native gesture")
        parent.addSubview(editor.text)
        drag.write("https://drop.invalid/changed"); _ = editor.text.draggingEntered(drag)
        drag.draggingPasteboard.clearContents(); drag.draggingPasteboard.setString("https://different.invalid", forType: .string)
        try check(!editor.text.performDragOperation(drag) && commits == old, "pasteboard replacement never retargets original editor")
        editor.text.setMarkedText("composition", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        try check(!editor.canAcceptExternalSplitDrop, "native body composition declines split admission")
        editor.text.unmarkText()
        editor.titleText.setMarkedText("title", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        try check(!editor.canAcceptExternalSplitDrop, "native title composition declines split admission")
        editor.titleText.unmarkText()
        drag.write("https://drop.invalid/later-composition"); _ = editor.text.draggingEntered(drag)
        editor.text.setMarkedText("later", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        try check(!editor.text.performDragOperation(drag) && editor.text.hasMarkedText(), "composition begun during preview cancels without discarding it")
        editor.text.unmarkText()
        editor.view.removeFromSuperview(); host.addSubview(canvas); canvas.frame = host.bounds
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
        let noteID = browser.openNote(id: note.document.id, title: "Original Note")!
        let easelID = browser.openEasel(id: easel.document.id, title: "Original Easel")!
        browser.setSplit([noteID, easelID])
        let original = browser.state, group = browser.activeSplitLayout!, newID = UUID()
        let noteBefore = note.document, easelBefore = easel.document
        try check(try browser.dropExternalURLIntoSplit(URL(string: "https://drop.invalid/new")!, tabID: newID,
            spaceID: browser.activeSpaceID, profileID: browser.activeSpace.profileID,
            expectedSelection: [noteID, easelID], expectedLayout: group, target: .replace(0), orientation: .horizontal, creation: nil), "real mixed document split replacement persists")
        try check(browser.state.tabs.first { $0.id == noteID } == original.tabs.first { $0.id == noteID }, "displaced Note original reference retained")
        try check(browser.state.tabs.first { $0.id == easelID }?.url == original.tabs.first { $0.id == easelID }?.url, "retained Easel original reference retained")
        try check(note.document == noteBefore && easel.document == easelBefore, "split creation never writes original documents")
        let reloaded = try BrowserStore(directory: root.appendingPathComponent("browser"))
        try check(reloaded.activeSplitLayout?.id == group.id && reloaded.activeSplitLayout?.tabIDs == [newID, easelID], "mixed split group identity survives persistence")
        try easelStore.delete(easel.document.id)
        try check(!canvas.canAcceptExternalSplitDrop, "deleted shared Easel session cannot admit a split target")
        print("Local editor native split drops: \(count) checks passed")
    }
}
