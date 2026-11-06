import AppKit

@main
struct ResultNavigationTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            if !value() { fatalError(message) }
        }
        let rows = Rows()
        let table = CommandResultsTable(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        table.addTableColumn(NSTableColumn(identifier: .init("result")))
        table.rowHeight = 50; table.headerView = nil
        table.dataSource = rows; table.delegate = rows; table.allowsEmptySelection = true
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let field = NSTextField(frame: NSRect(x: 0, y: 150, width: 400, height: 30))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 150))
        scroll.documentView = table
        window.contentView!.addSubview(scroll); window.contentView!.addSubview(field)
        field.stringValue = "space"; window.makeFirstResponder(field); field.selectText(nil)
        let editor = field.currentEditor() as! NSTextView
        var edit = CommandBarEditState(query: "space")
        var selectedID: String?
        var moves = 0
        var activations = 0
        rows.onActivate = { activations += 1 }; table.target = rows; table.action = #selector(Rows.activate(_:))
        func move(_ delta: Int, wrapping: Bool = true) {
            guard let row = table.keyboardSelectionRow(moving: delta, wrapping: wrapping) else { return }
            selectedID = rows.ids[row]
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
            moves += 1
            if let value = rows.completions[selectedID!] { edit.project(resultID: selectedID!, text: value) }
            else { edit.clearProjection() }
            editor.string = edit.displayedText; editor.setSelectedRange(edit.selection)
        }
        table.onKey = { event in
            guard !editor.hasMarkedText() else { return true }
            if event.keyCode == 126 { move(-1); return true }
            if event.keyCode == 125 { move(1); return true }
            return false
        }
        func key(_ code: UInt16, repeatKey: Bool = false) {
            table.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                characters: code == 126 ? "\u{F700}" : "\u{F701}", charactersIgnoringModifiers: "",
                isARepeat: repeatKey, keyCode: code)!)
        }
        table.reloadData()
        expect(table.keyboardSelectionRow(moving: 1, wrapping: true) == nil, "empty query result must not invent a row")
        expect(table.keyboardSelectionRow(moving: -1, wrapping: true) == nil, "empty upward traversal must not invent a row")
        rows.ids = ["first-native", "space-command", "folder-command", "note-tab", "expired", "last-native"]
        rows.completions = ["first-native": "space", "last-native": "space waves"]
        table.reloadData(); table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        key(126)
        expect(table.selectedRow == 5 && selectedID == "last-native", "Up from first wraps to original last result")
        expect(editor.string == "space waves" && editor.selectedRange() == NSRange(location: 5, length: 6), "native result keeps its actual suffix selection")
        expect(edit.query == "space", "projection must not replace provider query")
        expect(window.firstResponder === editor, "table selection must not steal field focus")
        expect(table.rows(in: table.visibleRect).contains(5), "wrapped last row must scroll into view")
        key(125)
        expect(table.selectedRow == 0 && selectedID == "first-native", "Down from last wraps to original first result")
        expect(editor.string == "space" && editor.selectedRange() == NSRange(location: 5, length: 0), "first result clears only projected suffix")
        expect(table.rows(in: table.visibleRect).contains(0), "wrapped first row must scroll into view")
        key(125)
        expect(selectedID == "space-command" && edit.projection == nil, "typed Space action must not become field text")
        key(125)
        expect(selectedID == "folder-command" && editor.string == "space", "typed folder action retains query")
        key(125)
        expect(selectedID == "note-tab", "local tab identity remains its original target")
        key(125)
        expect(selectedID == "expired", "navigation does not silently skip a visible expired target")
        key(125, repeatKey: true); key(125, repeatKey: true)
        expect(selectedID == "first-native", "key repeat follows the same live result cycle")
        expect(activations == 0, "selection must never activate any target")
        let beforeMoves = moves
        editor.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: 0, length: 5))
        key(126)
        expect(moves == beforeMoves && editor.hasMarkedText(), "input composition retains ownership")
        editor.unmarkText(); edit.edit("space"); editor.string = "space"
        table.deselectAll(nil)
        move(-1)
        expect(selectedID == "last-native", "unselected Up uses last live row")
        table.deselectAll(nil)
        move(1)
        expect(selectedID == "first-native", "unselected Down uses first live row")
        move(-1, wrapping: false)
        expect(selectedID == "first-native", "empty-query recent rows preserve existing first boundary")
        table.selectRowIndexes(IndexSet(integer: 5), byExtendingSelection: false)
        move(1, wrapping: false)
        expect(selectedID == "last-native", "empty-query recent rows preserve existing last boundary")
        rows.ids = ["surviving-note"]; table.reloadData()
        move(1); expect(selectedID == "surviving-note" && table.selectedRow == 0, "replacement snapshot cannot use an old row count")
        move(-1); expect(selectedID == "surviving-note" && table.selectedRow == 0, "single result is stable in both directions")
        expect(table.keyboardSelectionRow(moving: 0, wrapping: true) == nil, "zero is not a keyboard traversal")
        expect(table.keyboardSelectionRow(moving: Int.max, wrapping: true) == nil, "unsupported deltas cannot overflow row arithmetic")
        rows.ids = []; table.reloadData()
        let lastMoves = moves; key(125); key(126)
        expect(moves == lastMoves, "removed results cannot produce a stale target")
        expect(activations == 0 && window.firstResponder === editor, "no activation or focus loss across the whole interaction")
        window.orderOut(nil)
        print("Command result navigation: \(checks) assertions passed")
    }
}

@MainActor private final class Rows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var ids: [String] = []
    var completions: [String: String] = [:]
    var onActivate: (() -> Void)?
    func numberOfRows(in tableView: NSTableView) -> Int { ids.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        NSTextField(labelWithString: ids[row])
    }
    @objc func activate(_ sender: Any?) { onActivate?() }
}
