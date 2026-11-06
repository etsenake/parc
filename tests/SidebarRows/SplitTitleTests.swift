import AppKit

extension NSColor { static var parcInk: NSColor { .labelColor } }
@MainActor private final class SplitTitleTestWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}

@main @MainActor struct SplitTitleTests {
    static var checks = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !value() { throw NSError(domain: message, code: checks) }
    }
    static func main() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-title-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let first = store.openResolvedURL(URL(string: "https://one.test/")!)
        let second = store.openResolvedURL(URL(string: "https://two.test/")!)
        store.updateTab(first, title: "One"); store.updateTab(second, title: "Two")
        store.setSplit([first, second])
        let space = store.activeSpaceID, profile = store.activeSpace.profileID
        func current() -> SidebarSplitTitleEdit {
            SidebarSplitTitleEdit.current(state: store.state, spaceID: space, profileID: profile, selectedTabIDs: [first, second])!
        }
        let initial = current(), before = store.state
        try expect(initial.group.customTitle == nil, "An unnamed split has no invented title")
        try expect(SidebarSplitTitleEdit.current(state: before, spaceID: space, profileID: profile, selectedTabIDs: [second]) == nil, "Focused child is never the container target")
        try expect(SidebarSplitTitleEdit.current(state: before, spaceID: space, profileID: profile, selectedTabIDs: [second, first]) == nil, "Pane order is part of original identity")
        try expect(SidebarSplitTitleEdit.current(state: before, spaceID: space, profileID: UUID(), selectedTabIDs: [first, second]) == nil, "Foreign profile refuses target")
        try store.saveSidebarSplitTitle(initial, title: "  Research\n")
        let named = current()
        try expect(named.group.customTitle == "Research", "Container receives trimmed name")
        try expect(named.group.id == initial.group.id && named.group.tabIDs == initial.group.tabIDs && named.group.sidebarAnchorID == initial.group.sidebarAnchorID, "Original group and child identities survive")
        try expect(store.state.tabs == before.tabs, "No child page, saved title, URL or override is altered")
        try expect(store.state.selectedTabIDs == before.selectedTabIDs && store.state.history == before.history, "No selection or history mutation")
        let reopened = try BrowserStore(directory: directory)
        try expect(reopened.state.splitLayouts.first { $0.id == named.group.id }?.customTitle == "Research", "Container title persists")
        do { try store.saveSidebarSplitTitle(initial, title: "Stale"); throw NSError(domain: "stale accepted", code: 0) }
        catch SidebarSplitTitleEdit.EditError.unavailable { }
        try expect(current().group.customTitle == "Research", "Earlier editor cannot overwrite a concurrent name")
        store.updateTab(first, title: "New live title", url: "https://one.test/next")
        try expect(named.matches(store.state), "Live Today metadata retains the original group lease")
        try store.saveSidebarSplitTitle(named, title: " \n ")
        try expect(current().group.customTitle == nil, "Empty edit clears the container override")
        try expect(store.state.tabs.first { $0.id == first }?.title == "New live title", "Clearing never erases live metadata")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(named.group)) as! [String: Any]
        legacy.removeValue(forKey: "customTitle")
        let decoded = try JSONDecoder().decode(BrowserSplitLayout.self, from: JSONSerialization.data(withJSONObject: legacy))
        try expect(decoded.customTitle == nil && decoded.id == named.group.id, "Existing sessions decode without a name")
        let lease = current()
        var changed = store.state
        changed.splitLayouts[0].tabIDs.reverse()
        try expect(!lease.matches(changed), "Reordered membership invalidates an edit")
        changed = store.state; changed.splitLayouts[0].id = UUID()
        try expect(!lease.matches(changed), "Replacement container is not the original")
        changed = store.state; changed.tabs[changed.tabs.firstIndex { $0.id == first }!].folderID = UUID()
        try expect(!lease.matches(changed), "Moved child invalidates edit")
        changed = store.state; changed.tabs[changed.tabs.firstIndex { $0.id == first }!].archivedAt = Date()
        try expect(!lease.matches(changed), "Retired child invalidates edit")
        changed = store.state; changed.tabs[changed.tabs.firstIndex { $0.id == first }!].kind = .favorite
        try expect(SidebarSplitTitleEdit(group: lease.group, profileID: profile, state: changed) == nil, "Unestablished App Tray editor is not fabricated")
        try store.saveSidebarSplitTitle(current(), title: "Preserved")
        try expect(store.setSplitLayout(orientation: .vertical, widthFactors: [1, 2]), "Resize accepted")
        try expect(current().group.customTitle == "Preserved", "Orientation and divider changes preserve container title")
        let oldLayout = initial.group
        try expect(store.setWindowPresentation(spaceID: space, selectedTabIDs: [first, second], splitLayout: oldLayout), "Original remembered geometry restores")
        try expect(current().group.customTitle == "Preserved", "Remembered geometry cannot overwrite newer shared name")
        let presentation = WindowPresentation(state: store.state, ready: true)
        try expect(presentation.splitLayout?.customTitle == "Preserved", "Window layout projection preserves title")
        let third = store.openResolvedURL(URL(string: "https://three.test/")!)
        store.setSplit([first, second]); store.setSplit([first, second, third])
        try expect(store.state.splitLayouts.first { $0.tabIDs == [first, second, third] }?.customTitle == "Preserved", "Expanded original group preserves title")
        let three = SidebarSplitTitleEdit.current(state: store.state, spaceID: space, profileID: profile, selectedTabIDs: [first, second, third])!
        try expect(store.separateTabFromSplit(third, expected: three.group), "Original child separates")
        try expect(current().group.customTitle == "Preserved", "Surviving group preserves name")
        let privateDirectory = directory.appendingPathComponent("uncreated-private")
        let privateStore = BrowserStore(privateParentProfileID: profile, engineProfilePath: "/not-opened", directory: privateDirectory, settings: store.state.settings)
        let pa = privateStore.openResolvedURL(URL(string: "https://private-one.test")!)
        let pb = privateStore.openResolvedURL(URL(string: "https://private-two.test")!)
        privateStore.setSplit([pa, pb])
        let privateTarget = SidebarSplitTitleEdit.current(state: privateStore.state, spaceID: privateStore.activeSpaceID, profileID: privateStore.activeSpace.profileID, selectedTabIDs: [pa, pb])!
        try privateStore.saveSidebarSplitTitle(privateTarget, title: "Private")
        try expect(privateStore.state.splitLayouts.first?.customTitle == "Private", "Private group name works in memory")
        try expect(!FileManager.default.fileExists(atPath: privateDirectory.path), "Private rename creates no persistent profile/model")
        let failedLease = current(), failedState = store.state
        try FileManager.default.removeItem(at: directory); try Data().write(to: directory)
        do { try store.saveSidebarSplitTitle(failedLease, title: "Not published"); throw NSError(domain: "write accepted", code: 0) }
        catch { try expect(store.state == failedState, "Failed save publishes no container title") }

        let view = SidebarSplitTitleView(title: "Research", count: 2)
        try expect(view.accessibilityLabel() == "Research, Split View, 2 tabs", "Container name and count are accessible")
        view.applyColors(title: .systemPurple, secondary: .systemOrange)
        try expect(view.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Research" && $0.textColor == .systemPurple }, "Container label retains sidebar theme owner")
        var values: [String?] = []
        try expect(!view.begin(title: "Research", finished: { values.append($0) }), "Detached original editor refuses focus")
        let window = SplitTitleTestWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        view.frame = NSRect(x: 0, y: 0, width: 220, height: 35); window.contentView!.addSubview(view)
        try expect(view.begin(title: "Research", finished: { values.append($0) }), "Real custom-info native editor begins")
        let field = view.subviews.compactMap { $0 as? SidebarTitleField }.first!
        try expect(view.accessibilityRole() == .group && view.accessibilityChildren()?.contains { ($0 as? SidebarTitleField) === field } == true, "Editing exposes actual native field to accessibility")
        try expect(field.currentEditor()?.selectedRange == NSRange(location: 0, length: 8), "Whole container name selected")
        try expect(field.placeholderString == "Title" && field.accessibilityLabel() == "Split View name", "Recovered placeholder and explicit native field ownership")
        let editor = field.currentEditor() as! NSTextView
        editor.setMarkedText("入力", selectedRange: NSRange(location: 0, length: 2), replacementRange: NSRange(location: NSNotFound, length: 0))
        try expect(!field.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))), "IME retains Return")
        editor.unmarkText(); view.cancel()
        try expect(values.count == 1 && values[0] == nil, "Cancel does not commit container name")
        try expect(view.accessibilityRole() == .button, "Cancellation restores container activation role")
        try expect(view.begin(title: "Research", finished: { values.append($0) }), "Container editor re-enters")
        let next = field.currentEditor() as! NSTextView
        next.string = "New name"; next.didChangeText()
        try expect(field.control(field, textView: next, doCommandBy: #selector(NSResponder.insertNewline(_:))), "Return completes actual native field")
        try expect(values.count == 2 && values[1] == "New name", "One original completion receives actual text")
        try expect(view.begin(title: "Again", finished: { values.append($0) }), "Fresh edit for owner loss")
        view.removeFromSuperview()
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        try expect(values.count == 3 && values[2] == nil, "Owner removal cancels queued blur completion")
        try expect(!view.accessibilityPerformPress(), "Detached named container cannot activate a page")
        window.close()
        print("PASS: \(checks) split-title model/native-editor assertions (no browser)")
    }
}
