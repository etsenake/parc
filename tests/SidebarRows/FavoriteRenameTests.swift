import AppKit
import Combine

@MainActor final class CompositionTextView: NSTextView {
    override func hasMarkedText() -> Bool { true }
}

@main @MainActor struct FavoriteRenameTests {
    static var count = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1
        if try !value() { throw NSError(domain: message, code: count) }
    }
    static func main() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-favorite-rename-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let id = store.openResolvedURL(URL(string: "https://favorite.test/original")!)
        store.updateTab(id, title: "Saved page"); store.setKind(id, .favorite)
        func tab() -> BrowserTab { store.state.tabs.first { $0.id == id }! }
        let original = tab(), undo = FolderUndoManager()
        var publications = 0
        let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
        let snapshot = store.state
        do { _ = try store.saveFavoriteTitle(original, title: ""); throw NSError(domain: "empty accepted", code: 1) }
        catch SidebarTabTitle.EditError.unavailable {}
        try expect(store.state == snapshot && publications == 0, "Empty dialog name never writes or clears")
        store.updateTab(id, title: "Live title", url: "https://favorite.test/current")
        let before = store.state, publicationBefore = publications
        let change = try store.saveFavoriteTitle(original, title: "  Research 🪐  ")!
        try expect(change.tabID == id && change.previousTitle == nil && change.title == "  Research 🪐  ", "Dialog supplies literal text for original ID")
        var expected = before; expected.tabs[expected.tabs.firstIndex { $0.id == id }!].customTitle = change.title
        try expect(store.state == expected && publications == publicationBefore + 1, "Only original manual title publishes atomically")
        try expect(tab().savedURL == original.savedURL && tab().url == "https://favorite.test/current", "Original saved/live destinations are untouched")
        try expect(try BrowserStore(directory: directory).state.tabs.first { $0.id == id }?.customTitle == change.title, "Favorite title persists")
        _ = undo.appendTabTitleChange(change, store: store, available: { true }, onError: { _ in })
        try expect(undo.undoMenuItemTitle == "Undo Rename Item", "Recovered shared Undo name")
        undo.undo(); try expect(tab().customTitle == nil && tab().kind == .favorite, "Undo restores Favorite fallback without changing membership")
        undo.redo(); try expect(tab().customTitle == change.title, "Redo applies original name")
        try expect(try store.saveFavoriteTitle(tab(), title: change.title!) == nil, "Unchanged confirm creates no inverse")
        do { _ = try store.saveFavoriteTitle(original, title: "Stale"); throw NSError(domain: "stale accepted", code: 1) }
        catch SidebarTabTitle.EditError.unavailable {}
        try expect(tab().customTitle == change.title, "Competing shared name refuses stale dialog")
        let beforeMembership = tab(); store.setKind(id, .pinned)
        do { _ = try store.saveFavoriteTitle(beforeMembership, title: "Stale"); throw NSError(domain: "membership accepted", code: 1) }
        catch SidebarTabTitle.EditError.unavailable {}
        try expect(tab().kind == .pinned && tab().customTitle == change.title, "Unfavorite invalidates the original editor")
        store.setKind(id, .favorite)
        let valid = tab(), beforeFailure = store.state
        try FileManager.default.removeItem(at: directory); try Data().write(to: directory)
        do { _ = try store.saveFavoriteTitle(valid, title: "Failure"); throw NSError(domain: "write accepted", code: 1) }
        catch { try expect(store.state == beforeFailure, "Real storage failure retains original shared state") }
        try FileManager.default.removeItem(at: directory); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pending = tab(); var completion: ((Bool) -> Void)?
        store.requestPageRetirement = { _, _, done in completion = done }; store.closeTab(id)
        do { _ = try store.saveFavoriteTitle(pending, title: "Retiring"); throw NSError(domain: "retirement accepted", code: 1) }
        catch SidebarTabTitle.EditError.unavailable {}
        completion?(false)
        try expect(try store.saveFavoriteTitle(tab(), title: "After cancellation") != nil, "Refused native retirement preserves actual original")

        let dialog = FavoriteRenameDialog(title: "Original")
        var commits = [String](), finishes = 0
        dialog.isCurrent = { true }; dialog.onCommit = { commits.append($0) }; dialog.onFinish = { finishes += 1 }
        try expect(dialog.sheetWindow.accessibilityLabel() == "Rename Tab…" && dialog.field.placeholderString == "Keep it short and sweet!"
                   && dialog.dialog.confirmButton.title == "Rename" && dialog.dialog.cancelButton?.title == "Cancel", "Recovered dialog strings")
        try expect(!dialog.field.isBordered && !dialog.field.isBezeled && !dialog.field.drawsBackground && dialog.field.focusRingType == .none
                   && dialog.field.font?.pointSize == 14 && dialog.field.superview?.superview === dialog.sheetWindow.contentView,
                   "the borderless 14-point field on its card inside the dialog sheet")
        try expect(dialog.field.usesSingleLineMode && dialog.field.isEditable && dialog.field.isSelectable, "Native single-line selection/text owner")
        dialog.field.stringValue = ""; dialog.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: dialog.field))
        try expect(!dialog.dialog.confirmButton.isEnabled, "Required input disables Rename")
        dialog.field.stringValue = "Literal 🪐"; dialog.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: dialog.field))
        try expect(dialog.dialog.confirmButton.isEnabled, "Nonempty text enables explicit confirm")
        let marked = CompositionTextView()
        try expect(!dialog.control(dialog.field, textView: marked, doCommandBy: #selector(NSResponder.insertNewline(_:))), "IME owns marked-text Return")
        try expect(!dialog.control(dialog.field, textView: marked, doCommandBy: #selector(NSResponder.cancelOperation(_:))), "IME owns marked-text Escape")
        let text = NSTextView()
        try expect(!dialog.control(dialog.field, textView: text, doCommandBy: #selector(NSResponder.moveLeft(_:))), "Native caret keys pass through")
        try expect(dialog.control(dialog.field, textView: text, doCommandBy: #selector(NSResponder.insertNewline(_:))), "Unmarked Return invokes explicit confirm")
        dialog.dialog.confirmButton.performClick(nil); dialog.cancel()
        try expect(commits == ["Literal 🪐"] && finishes == 1, "Commit and completion are once-only")
        let cancel = FavoriteRenameDialog(title: "Original")
        cancel.isCurrent = { true }; cancel.onCommit = { _ in commits.append("bad") }
        _ = cancel.control(cancel.field, textView: text, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        try expect(cancel.finished && commits.count == 1, "Escape cancels without a model write")
        let stale = FavoriteRenameDialog(title: "Original")
        stale.isCurrent = { false }; stale.onCommit = { _ in commits.append("bad") }; stale.reconcile()
        try expect(stale.finished && commits.count == 1, "Original owner invalidation cancels")
        let retry = FavoriteRenameDialog(title: "Draft")
        retry.isCurrent = { true }; var fails = true
        retry.onCommit = { value in if fails { throw NSError(domain: "Storage unavailable", code: 1) }; commits.append(value) }
        retry.dialog.confirmButton.performClick(nil)
        try expect(!retry.finished && retry.field.stringValue == "Draft", "Failed commit keeps native draft")
        fails = false; retry.dialog.confirmButton.performClick(nil)
        try expect(retry.finished && commits.last == "Draft", "Explicit retry commits preserved draft")
        withExtendedLifetime(observation) {}
        print("FavoriteRenameTests: \(count) assertions passed")
    }
}
