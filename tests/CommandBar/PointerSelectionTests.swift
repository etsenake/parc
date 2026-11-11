import AppKit

@main @MainActor struct PointerSelectionTests {
    static func main() {
        _ = NSApplication.shared
        var count = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            count += 1; precondition(value(), message)
        }
        let rows = Rows()
        let table = CommandResultsTable(frame: NSRect(x: 0, y: 0, width: 500, height: 150))
        table.addTableColumn(NSTableColumn(identifier: .init("result")))
        table.headerView = nil; table.rowHeight = 50; table.intercellSpacing = .zero
        table.dataSource = rows; table.delegate = rows; table.selectionHighlightStyle = .regular
        let window = OwnedWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let field = NSTextField(frame: NSRect(x: 0, y: 160, width: 500, height: 30))
        window.contentView!.addSubview(table); window.contentView!.addSubview(field)
        table.reloadData(); table.layoutSubtreeIfNeeded()
        field.stringValue = "space waves"; window.makeFirstResponder(field); field.selectText(nil)
        let editor = field.currentEditor() as! NSTextView
        editor.setSelectedRange(NSRange(location: 5, length: 6))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let first = table.rowView(atRow: 0, makeIfNecessary: true) as! CommandResultRowView
        let second = table.rowView(atRow: 1, makeIfNecessary: true) as! CommandResultRowView
        let secondCell = table.view(atColumn: 0, row: 1, makeIfNecessary: true) as! CommandResultCell
        let button = secondCell.subviews.compactMap { $0 as? NSButton }.first!
        second.updateTrackingAreas(); secondCell.layoutSubtreeIfNeeded()
        let point = second.convert(NSPoint(x: 80, y: 25), to: nil)
        func event(_ type: NSEvent.EventType, at location: NSPoint? = nil, flags: NSEvent.ModifierFlags = [], in owner: NSWindow? = nil) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: location ?? point, modifierFlags: flags, timestamp: 0,
                windowNumber: (owner ?? window).windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        expect(first.isSelected && !second.isSelected, "keyboard selection belongs to the first native row")
        let entered = NSEvent.enterExitEvent(with: .mouseEntered, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, trackingNumber: 1, userData: nil)!
        second.mouseEntered(with: entered)
        expect(!second.isHovered && button.isHidden, "mere row appearance does not hover or reveal deletion")
        second.mouseMoved(with: event(.mouseMoved))
        expect(second.isHovered && !button.isHidden, "real row pointer movement owns highlight and delete visibility")
        expect(table.selectedRow == 0 && first.isSelected && !second.isSelected, "hover cannot replace the keyboard-selected result")
        expect(editor.string == "space waves" && editor.selectedRange() == NSRange(location: 5, length: 6), "hover keeps the provider projection and native suffix selection")
        expect(window.firstResponder === editor && rows.opened.isEmpty, "hover neither steals field focus nor opens a result")
        second.isSelected = true
        expect(second.isHovered && secondCell.isAccessibilitySelected(), "selected and hover states coexist without losing AX selection")
        second.isSelected = false
        let staleExit = NSEvent.enterExitEvent(with: .mouseExited, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 2, trackingNumber: 99, userData: nil)!
        second.mouseExited(with: staleExit)
        expect(second.isHovered, "an unrelated tracking-area exit does not revoke the current hover")
        let hit = table.hitTest(table.convert(point, from: nil))
        expect(hit === second, "decorative row hit testing bypasses stock table selection")
        second.mouseDown(with: event(.leftMouseDown))
        expect(rows.opened == ["second"] && table.selectedRow == 0, "pointer activates the original second row without first selecting it")
        expect(window.firstResponder === editor && editor.selectedRange() == NSRange(location: 5, length: 6), "direct row press preserves input focus until its real action takes over")
        second.mouseDown(with: event(.leftMouseDown, flags: [.command, .option]))
        expect(rows.modifiers.last == [.command, .option], "original mouse modifiers reach the action owner intact")
        let deletePoint = button.convert(NSPoint(x: 10, y: 10), to: table.superview)
        let deleteHit = table.hitTest(deletePoint)
        expect(deleteHit === button || deleteHit?.isDescendant(of: button) == true, "delete accessory retains its actual native hit target")
        button.performClick(nil)
        expect(rows.deleted == 1 && rows.opened.count == 2, "accessory removal does not become row activation")
        second.mouseMoved(with: event(.mouseMoved, at: NSPoint(x: -200, y: -200)))
        expect(!second.isHovered && button.isHidden, "pointer leaving live bounds clears both row and accessory")
        second.mouseMoved(with: event(.mouseMoved)); second.updateTrackingAreas()
        expect(!second.isHovered && button.isHidden, "tracking replacement retires its prior hover state")
        second.mouseMoved(with: event(.mouseMoved))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        expect(!second.isHovered && button.isHidden, "original parent deactivation removes pointer presentation")
        window.ownsKey = false
        second.mouseMoved(with: event(.mouseMoved)); second.mouseDown(with: event(.leftMouseDown))
        expect(!second.isHovered && rows.opened.count == 2, "inactive original window cannot hover or dispatch a row")
        window.ownsKey = true
        let other = OwnedWindow(contentRect: .init(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        second.mouseMoved(with: event(.mouseMoved, in: other)); second.mouseDown(with: event(.leftMouseDown, in: other))
        expect(!second.isHovered && rows.opened.count == 2, "events belonging to another window never retarget the row")
        second.isHidden = true
        second.mouseDown(with: event(.leftMouseDown)); second.mouseMoved(with: event(.mouseMoved))
        expect(rows.opened.count == 2 && !second.isHovered, "hidden row cannot activate or remain highlighted")
        second.isHidden = false; second.mouseMoved(with: event(.mouseMoved))
        second.prepareForReuse()
        expect(!second.isHovered && button.isHidden && second.onPress == nil, "reuse clears hover and original pointer callback")
        expect(!secondCell.accessibilityPerformPress() && secondCell.onDelete == nil, "reuse also retires retained accessibility actions")
        second.mouseDown(with: event(.leftMouseDown))
        expect(rows.opened.count == 2 && table.selectedRow == 0, "retired row cannot fall through into table activation")
        first.mouseMoved(with: event(.mouseMoved, at: first.convert(.init(x: 80, y: 25), to: nil)))
        expect(first.isHovered, "selected row still receives its independent hover state")
        table.removeFromSuperview()
        expect(!first.isHovered, "physical detach revokes original parent hover")
        expect(rows.opened.count == 2, "no other interaction invoked an output action")
        print("Command result pointer ownership: \(count) assertions passed")
    }
}

@MainActor private final class OwnedWindow: NSWindow {
    var ownsKey = true
    override var isKeyWindow: Bool { ownsKey }
}
@MainActor private final class Rows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let ids = ["first", "second", "third"]
    var opened: [String] = []
    var modifiers: [NSEvent.ModifierFlags] = []
    var deleted = 0
    func numberOfRows(in tableView: NSTableView) -> Int { ids.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let original = ids[row], view = CommandResultRowView()
        view.onPress = { [weak self] event in
            self?.opened.append(original); self?.modifiers.append(event.modifierFlags); return true
        }
        return view
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let original = ids[row]
        let cell = CommandResultCell(title: original, detail: "example.test", accessory: "", isTab: false, icon: nil, enabled: true)
        cell.onDelete = { [weak self] in self?.deleted += 1; return true }
        cell.onPress = { [weak self] in self?.opened.append(original); return true }
        return cell
    }
}
