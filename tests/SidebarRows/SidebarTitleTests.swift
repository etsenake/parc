import AppKit

@MainActor private final class TitleTestWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}

@main @MainActor struct SidebarTitleTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1
        if try !value() { throw NSError(domain: message, code: count) }
    }
    static func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
    static func main() async { await exitOnFailure(runChecks) }
    static func runChecks() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-title-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let id = store.openResolvedURL(URL(string: "https://example.test/anchor")!)
        store.updateTab(id, title: "Original saved title")
        store.setKind(id, .pinned)
        let original = store.state.tabs.first { $0.id == id }!
        try check(SidebarTabTitle.display(original) == "Original saved title", "Saved label")
        store.updateTab(id, title: "Live destination title", url: "https://example.test/away")
        let away = store.state.tabs.first { $0.id == id }!
        try check(SidebarTabTitle.display(away) == "Original saved title", "Navigation does not replace saved sidebar label")
        try check(away.title == "Live destination title", "Page title remains independent")
        let before = store.state
        try store.saveSidebarTitle(away, title: "  My project\n")
        let custom = store.state.tabs.first { $0.id == id }!
        try check(custom.customTitle == "My project" && SidebarTabTitle.display(custom) == "My project", "Trimmed manual override")
        try check(custom.url == away.url && custom.title == away.title && custom.savedURL == away.savedURL && custom.savedTitle == away.savedTitle, "Rename changes no destination or page title")
        try check(store.state.selectedTabIDs == before.selectedTabIDs && store.state.history == before.history, "No selection/history event")
        let reopened = try BrowserStore(directory: directory)
        try check(reopened.state.tabs.first { $0.id == id }?.customTitle == "My project", "Custom title persists independently")
        do { try store.saveSidebarTitle(away, title: "Stale"); throw NSError(domain: "accepted stale override", code: 0) }
        catch SidebarTabTitle.EditError.unavailable { }
        try check(store.state.tabs.first { $0.id == id }?.customTitle == "My project", "Concurrent rename cannot overwrite")
        store.updateTab(id, title: "Updated live page", url: "https://example.test/next")
        try store.saveSidebarTitle(custom, title: "  \n")
        let cleared = store.state.tabs.first { $0.id == id }!
        try check(cleared.customTitle == nil && SidebarTabTitle.display(cleared) == original.savedTitle, "Empty edit restores saved title")
        try check(cleared.title == "Updated live page", "Live update survives edit transaction")
        var empty = cleared; empty.savedTitle = " \n"; empty.savedURL = "https://example.test/fallback"
        try check(SidebarTabTitle.display(empty) == empty.savedURL, "Missing saved title uses source URL")
        empty.savedURL = "about:blank"
        try check(SidebarTabTitle.display(empty) == "New tab", "Blank source placeholder")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(custom)) as! [String: Any]
        legacy.removeValue(forKey: "customTitle")
        let decoded = try JSONDecoder().decode(BrowserTab.self, from: JSONSerialization.data(withJSONObject: legacy))
        try check(decoded.customTitle == nil && decoded.title == custom.title, "Old session decodes without invented override")
        var moved = cleared; moved.spaceID = UUID()
        try check(!SidebarTabTitle.sameItemForEditing(moved, cleared), "Moved identity invalidates edit")
        moved = cleared; moved.folderID = UUID()
        try check(!SidebarTabTitle.sameItemForEditing(moved, cleared), "Folder change invalidates edit")
        moved = cleared; moved.archivedAt = Date()
        try check(!SidebarTabTitle.sameItemForEditing(moved, cleared), "Archived identity invalidates edit")
        let privateDirectory = directory.appendingPathComponent("uncreated-private")
        let privateStore = BrowserStore(privateParentProfileID: original.profileID, engineProfilePath: "/not-opened", directory: privateDirectory, settings: store.state.settings)
        let privateID = privateStore.openResolvedURL(URL(string: "https://private.test/")!)
        let privateTab = privateStore.state.tabs.first { $0.id == privateID }!
        try privateStore.saveSidebarTitle(privateTab, title: "Private name")
        try check(privateStore.state.tabs.first { $0.id == privateID }?.customTitle == "Private name", "Private custom title usable")
        try check(!FileManager.default.fileExists(atPath: privateDirectory.path), "Private rename creates no persistent storage")
        try store.save()
        let failedState = store.state
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
        do { try store.saveSidebarTitle(cleared, title: "Must not publish"); throw NSError(domain: "accepted failed write", code: 0) }
        catch { try check(store.state == failedState, "Failed persistence does not publish a title") }

        let field = SidebarTitleField()
        var values: [String?] = []
        field.onFinish = { values.append($0) }
        try check(!field.begin(title: "Detached"), "Detached editor refuses focus")
        let window = TitleTestWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        field.frame = NSRect(x: 20, y: 20, width: 180, height: 22)
        window.contentView!.addSubview(field)
        try check(field.begin(title: "Original"), "Attached original editor begins without browser")
        try check(field.currentEditor()?.selectedRange == NSRange(location: 0, length: 8), "Native editor selects whole title")
        let editor = field.currentEditor() as! NSTextView
        try check(!field.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))), "Ordinary caret editing remains native")
        editor.setMarkedText("入力", selectedRange: NSRange(location: 0, length: 2), replacementRange: NSRange(location: NSNotFound, length: 0))
        try check(!field.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))), "Return preserves active IME composition")
        editor.unmarkText()
        try check(field.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))), "Escape consumes only local editor cancellation")
        try check(values.count == 1 && values[0] == nil && !field.editingTitle, "Cancel publishes no text")
        field.cancel(); try check(values.count == 1, "Completion occurs only once")
        try check(field.begin(title: "Original"), "Editor may re-enter")
        (field.currentEditor() as! NSTextView).string = "Changed"
        (field.currentEditor() as! NSTextView).didChangeText()
        try check(field.control(field, textView: field.currentEditor() as! NSTextView, doCommandBy: #selector(NSResponder.insertNewline(_:))), "Return completes edit")
        try check(values.count == 2 && values[1] == "Changed", "Original callback receives actual text")
        try check(field.begin(title: "Again"), "Third original session")
        field.removeFromSuperview()
        try check(values.count == 3 && values[2] == nil, "Detachment cancels instead of saving draft")
        await drainMainQueue()
        try check(values.count == 3, "Queued end-edit cannot publish after detach cancellation")
        window.contentView!.addSubview(field)
        try check(field.begin(title: "Click away"), "Reattached editor has a fresh session")
        (field.currentEditor() as! NSTextView).string = "Blurred title"
        (field.currentEditor() as! NSTextView).didChangeText()
        _ = window.makeFirstResponder(window.contentView)
        await drainMainQueue()
        try check(values.count == 4 && values[3] == "Blurred title", "Original native focus loss completes once")
        window.close()
        print("\(count) sidebar title assertions passed (isolated model/AppKit; no browser)")
    }
}
