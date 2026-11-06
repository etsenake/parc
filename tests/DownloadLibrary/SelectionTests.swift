import AppKit

// Real model snapshots and native table input. No browser, file action,
// pasteboard write, download or personal profile is opened by this component.
@main @MainActor
struct DownloadLibrarySelectionTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1; precondition(condition(), message)
    }
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        var state = store.state
        let profile = state.profiles[0].id
        func item(_ name: String, identity: String) -> BrowserDownload {
            var item = BrowserDownload(id: name, name: name, path: "", receivedBytes: 10, totalBytes: 10, status: .completed)
            item.profileID = profile; item.nativeID = name; item.nativeIdentity = identity
            item.canOpen = true; item.canRemove = true; item.canCopyFile = true
            item.canToggleOpen = true; item.sourceURL = "https://example.invalid/" + name
            return item
        }
        let first = item("first", identity: "original-a"), second = item("second", identity: "original-b")
        state.downloads = [first, second]
        let rows: [BrowserDownload?] = [nil, first, nil, second]
        expect(DownloadLibrarySelection.retainedRows([first], in: rows) == IndexSet(integer: 1), "Original single item restores across date headings")
        expect(DownloadLibrarySelection.retainedRows([first, second], in: rows).isEmpty, "A plural snapshot cannot become the original optional selection")
        var changed = first; changed.receivedBytes += 1; changed.name = "Updated name"
        expect(DownloadLibrarySelection.retainedRows([first], in: [changed]) == IndexSet(integer: 0), "Progress/name changes preserve original identity")
        changed.nativeIdentity = "replacement"
        expect(DownloadLibrarySelection.retainedRows([first], in: [changed]).isEmpty, "Replacement incarnation cannot inherit highlight")
        changed = first; changed.nativeID = "different-guid"
        expect(DownloadLibrarySelection.retainedRows([first], in: [changed]).isEmpty, "GUID participates in identity")
        changed = first; changed.profileID = UUID()
        expect(DownloadLibrarySelection.retainedRows([first], in: [changed]).isEmpty, "Profile participates in identity")
        var restored = first; restored.nativeIdentity = nil
        expect(DownloadLibrarySelection.retainedRows([restored], in: [first]).isEmpty, "Restored metadata selection cannot become a new live lease")
        var stale = first; stale.nativeIdentity = nil
        state.downloads = [stale]
        expect(DownloadLibrarySelection.resolve([stale], for: .open, in: state) == nil, "Capability flags without manager incarnation never authorize output")
        state.downloads = [first, second]
        expect(DownloadLibrarySelection.resolve([first], for: .open, in: state)?.count == 1, "Original one-item action remains reachable")
        expect(DownloadLibrarySelection.resolve([first, second], for: .open, in: state) == nil, "No plural Open is synthesized from singular menu ownership")
        state.downloads[1].canOpen = false
        expect(DownloadLibrarySelection.resolve([first, second], for: .open, in: state) == nil, "Mixed eligibility refuses whole set before dispatch")
        state.downloads = [first]
        expect(DownloadLibrarySelection.resolve([first, second], for: .remove, in: state) == nil, "Missing member refuses captured confirmation set")
        state.downloads = [first, second]; state.downloads[0].nativeIdentity = "replacement"
        expect(DownloadLibrarySelection.resolve([first], for: .remove, in: state) == nil, "Same public ID replacement cannot accept old confirmation")
        state.downloads = [first, second]
        expect(DownloadLibrarySelection.resolve([first, first], for: .remove, in: state) == nil, "Duplicate snapshot cannot dispatch an operation twice")
        state.profiles = []
        expect(DownloadLibrarySelection.resolve([first], for: .copyFile, in: state) == nil, "Retired profile revokes file commands")
        state = store.state; state.downloads = [first, second]
        state.downloads[0].sourceURL = "https://example.invalid/replaced"
        expect(DownloadLibrarySelection.resolve([first], for: .copyLink, in: state) == nil, "Source-link command keeps original URL")
        state.downloads = [first, second]
        expect(DownloadLibrarySelection.resolve([first, second], for: .copyLink, in: state) == nil, "Single-source command never becomes a new bulk command")
        expect(DownloadLibrarySelection.resolve([first, second], for: .toggleOpen, in: state) == nil, "No plural toggle is synthesized even when capabilities match")
        state.downloads[1].openWhenComplete = true
        expect(DownloadLibrarySelection.resolve([first, second], for: .toggleOpen, in: state) == nil, "Mixed toggle states do not invert into an unintended result")
        state.downloads[0].openWhenComplete = true
        expect(DownloadLibrarySelection.resolve([first], for: .toggleOpen, in: state) == nil, "A stale unchecked menu cannot toggle an already changed original state")
        state.downloads = [first, second]; state.downloads[0].canCopyFile = false
        expect(DownloadLibrarySelection.resolve([first, second], for: .trash, in: state) == nil, "Incomplete/restricted file blocks Trash before output")
        state.downloads[0].canReview = true
        expect(DownloadLibrarySelection.resolve([first], for: .review, in: state)?.first?.canReview == true, "Real review capability remains usable")
        expect(DownloadLibrarySelection.resolve([first, second], for: .review, in: state) == nil, "Review keeps its single security owner")

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let table = DownloadLibraryTable(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let fixture = Rows()
        table.addTableColumn(NSTableColumn(identifier: .init("download")))
        table.delegate = fixture; table.dataSource = fixture
        table.allowsMultipleSelection = false; table.allowsEmptySelection = true; table.reloadData()
        var confirmations = 0, previews = 0, copies = 0, deletes = 0, searches = 0, closes = 0
        table.onConfirmSelection = { confirmations += 1 }; table.onPreview = { previews += 1 }
        table.onCopy = { copies += 1 }; table.onDelete = { deletes += 1 }
        table.onSearch = { searches += 1 }; table.onClose = { closes += 1 }
        table.onMove = { forward in
            guard let row = DownloadLibrarySelection.nextRow(in: fixture.selectable, selected: table.selectedRowIndexes, forward: forward) else { return }
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        func key(_ code: UInt16, _ chars: String, flags: NSEvent.ModifierFlags = []) {
            table.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: chars,
                charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!)
        }
        key(126, "\u{f700}")
        expect(table.selectedRowIndexes == IndexSet(integer: 1), "Up from no cursor selects first actual item")
        key(125, "\u{f701}")
        expect(table.selectedRowIndexes == IndexSet(integer: 3), "Down skips a date heading")
        key(125, "\u{f701}")
        expect(table.selectedRowIndexes == IndexSet(integer: 3), "Down stops at final item")
        key(126, "\u{f700}"); key(126, "\u{f700}")
        expect(table.selectedRowIndexes == IndexSet(integer: 1), "Up stops at first item")
        key(36, "\r"); key(49, " ")
        expect(confirmations == 1 && previews == 1, "Return confirms selection while Space invokes its separate preview route")
        key(76, "\r")
        expect(confirmations == 2 && table.selectedRowIndexes == IndexSet(integer: 1), "Keypad Enter retains the original cursor")
        key(36, "\r", flags: .command); key(49, " ", flags: .option)
        expect(confirmations == 2 && previews == 1, "Modified keys do not invoke ordinary selection or file actions")
        key(8, "c", flags: .command); key(3, "f", flags: .command)
        expect(copies == 1 && searches == 1, "Command-C/F use owned callbacks")
        key(51, "\u{7f}", flags: .command)
        expect(deletes == 0, "Modified Delete never invokes ordinary Remove")
        key(51, "\u{7f}"); key(53, "\u{1b}")
        expect(deletes == 1 && closes == 1, "Delete routes original Hide; Escape routes owned dismissal")
        let copyItem = NSMenuItem(title: "Copy", action: #selector(DownloadLibraryTable.copy(_:)), keyEquivalent: "c")
        table.canCopy = { false }
        expect(!table.validateUserInterfaceItem(copyItem), "Responder Copy validates current capability")
        table.canCopy = { true }
        expect(table.validateUserInterfaceItem(copyItem), "Responder Copy enables only with a valid selection")
        key(0, "a", flags: .command)
        expect(table.selectedRowIndexes == IndexSet(integer: 1), "Command-A cannot turn the optional cursor into a range")
        expect(!table.validateUserInterfaceItem(NSMenuItem(title: "Select All", action: #selector(NSTableView.selectAll(_:)), keyEquivalent: "a")), "Responder Select All stays unavailable for Downloads")
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        key(125, "\u{f701}", flags: .shift)
        expect(table.selectedRowIndexes == IndexSet(integer: 3), "Shift-Down moves one original cursor instead of extending a range")
        key(126, "\u{f700}", flags: .shift)
        expect(table.selectedRowIndexes == IndexSet(integer: 1), "Shift-Up replaces the same cursor and skips headings")
        print("Download Library selection: \(assertions) assertions passed")
    }
    @MainActor final class Rows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        let selectable = IndexSet([1, 3])
        func numberOfRows(in tableView: NSTableView) -> Int { 4 }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { selectable.contains(row) }
        func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet { proposed.intersection(selectable) }
    }
}
