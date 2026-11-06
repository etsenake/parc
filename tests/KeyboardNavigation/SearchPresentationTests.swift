import AppKit

@MainActor private final class SearchOwnerWindow: NSWindow {
    var commandsAvailable = true
    override var isKeyWindow: Bool { commandsAvailable }
    override var isVisible: Bool { true }
}

@main @MainActor struct SearchPresentationTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1; precondition(condition(), message)
    }
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = KeyboardShortcuts(); registry.configure(directory: directory)
        let menu = NSMenu(); NSApp.mainMenu = menu
        for (title, id, key) in [("Archive Tab", "closeTab:", "w"), ("Open Extensions", "extensions:", "e")] {
            let item = NSMenuItem(title: title, action: NSSelectorFromString(id), keyEquivalent: key)
            item.keyEquivalentModifierMask = .command; menu.addItem(item); registry.register(item, group: "Tabs")
        }
        let view = ShortcutsSettingsView(shortcuts: registry)
        let window = SearchOwnerWindow(contentRect: view.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = view
        let header = view.subviews.compactMap { $0 as? ShortcutSearchHeader }.first!
        let field = header.field
        let clear = header.subviews.compactMap { $0 as? ShortcutSearchClearControl }.first!
        let icon = header.subviews.compactMap { $0 as? NSImageView }.first!
        let scroll = view.subviews.compactMap { $0 as? NSScrollView }.first!
        let table = scroll.documentView as! NSTableView
        view.layoutSubtreeIfNeeded()
        expect(header.frame == NSRect(x: 64, y: 84, width: 340, height: 41), "Original 24-point field plus 8-point padding and 1-point rule")
        expect(field.frame == NSRect(x: 33, y: 8, width: 291, height: 24), "Search image 13 plus 4 gap and 16-point leading/trailing padding")
        expect(scroll.frame.minY == header.frame.maxY && scroll.frame.maxY == 534, "Search header stays outside the full-height list scroller")
        expect(field.cell is NSTextFieldCell && !(field.cell is NSSearchFieldCell), "No stock search-cell magnifier or cancel offsets")
        expect(!field.isBordered && !field.isBezeled && !field.drawsBackground && field.focusRingType == .none, "Original ring-free plain editor")
        expect(field.maximumNumberOfLines == 1 && field.usesSingleLineMode, "Native single-line input is retained")
        expect(field.isEditable && field.isSelectable && field.accessibilityLabel() == "Search actions or shortcuts", "Original editable text owner retains its accessible label")
        expect(!icon.acceptsFirstResponder, "Search image cannot become a second input owner")
        expect(clear.isHidden, "Empty input has no clear control")
        expect(table.delegate?.tableView?(table, isGroupRow: 0) == true &&
               table.delegate?.tableView?(table, shouldSelectRow: 0) == false,
               "Native section header is explicitly a nonselectable group")
        expect(table.rect(ofRow: 0).height == 29 && table.rect(ofRow: 1).height == 58 && table.rect(ofRow: 2).height == 48,
               "Native section start retains its ten-point inset, with subsequent 48-point commands")
        let commandCell = table.view(atColumn: 0, row: 1, makeIfNecessary: true)!
        let commandTitle = commandCell.subviews.compactMap { $0 as? NSTextField }.first!
        expect(commandTitle.font?.pointSize == NSFont.systemFontSize && commandTitle.frame.minX == 22 &&
               commandTitle.frame.width == 200 && commandTitle.toolTip == "Archive Tab",
               "Original row uses body text, eight-point inner padding, max-width 200, and full-title help")
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let rowView = table.rowView(atRow: 1, makeIfNecessary: true)!
        rowView.layoutSubtreeIfNeeded()
        let selection = rowView.layer!.sublayers!.first!
        expect(selection.cornerRadius == 8 && selection.cornerCurve == .continuous &&
               selection.frame.height == 40 && selection.frame.minX == 16 &&
               abs((selection.backgroundColor?.alpha ?? 0) - 0.1) < 0.001,
               "Actual selected row owns the continuous eight-point accent shape at original opacity")
        table.deselectAll(nil); rowView.layoutSubtreeIfNeeded()
        expect(selection.isHidden, "Deselection retires the exact passive selection layer")
        expect(window.makeFirstResponder(field), "Original native text field accepts keyboard focus")
        let editor = field.currentEditor() as! NSTextView
        editor.insertText("extensions", replacementRange: NSRange(location: 0, length: 0))
        expect(field.stringValue == "extensions" && table.numberOfRows == 2, "Actual editor notification filters the registered commands")
        expect(!clear.isHidden, "Nonempty input exposes actual clear action")
        header.layoutSubtreeIfNeeded()
        expect(field.frame.maxX + 8 == clear.frame.minX, "Text and clear hit regions never overlap")
        let clearIdentity = clear
        header.refresh()
        expect(header.subviews.contains(where: { $0 === clearIdentity }), "Query refresh preserves original native hosting/control identity")
        expect(clear.rootView.presentation.present && clear.rootView.presentation.active, "Visible original key owner admits clear subtree")
        let banner = view.subviews.compactMap { $0 as? ShortcutBasicsBanner }.first!
        var bannerActions = 0
        banner.onPress = { bannerActions += 1 }
        banner.performPress()
        expect(bannerActions == 1, "Current Basics button dispatches through its original host")
        window.commandsAvailable = false; banner.performPress(); clear.refreshPresence()
        expect(bannerActions == 1 && !clear.rootView.presentation.active, "Key loss refuses Basics action and retires clear hover animation")
        window.commandsAvailable = true; clear.refreshPresence()
        let revision = registry.revision
        let originalResponder = window.firstResponder
        editor.setSelectedRange(NSRange(location: 1, length: 3))
        header.appearance = NSAppearance(named: .aqua)
        header.layoutSubtreeIfNeeded()
        expect(window.firstResponder === originalResponder && editor.selectedRange() == NSRange(location: 1, length: 3), "Appearance/layout preserves original selection and field editor")
        clear.performPress()
        expect(field.stringValue.isEmpty && editor.string.isEmpty && clear.isHidden, "Clear replaces text through original editor and reconciles the control")
        expect(window.firstResponder === originalResponder && editor.selectedRange() == NSRange(location: 0, length: 0), "Clear retains native caret/focus")
        expect(table.numberOfRows == 3 && registry.revision == revision, "Clear restores results without writing shortcuts")
        editor.setMarkedText("あ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let marked = editor.markedRange()
        header.refresh(); header.layoutSubtreeIfNeeded()
        expect(editor.hasMarkedText() && editor.markedRange() == marked, "Header refresh never replaces native IME composition")
        editor.unmarkText()
        editor.insertText("command", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        window.commandsAvailable = false; clear.performPress()
        expect(field.stringValue == "command", "Lost original key window refuses delayed clear")
        window.commandsAvailable = true; view.isHidden = true; clear.performPress()
        expect(field.stringValue == "command", "Hidden owner cannot clear native text")
        view.isHidden = false; clear.performPress()
        expect(field.stringValue.isEmpty, "Current original owner remains usable after refusal")
        // Read actual native drawing under both appearances. No pre-resolved
        // semantic alpha may leak from the original construction appearance.
        func sample(_ appearance: NSAppearance.Name, x: Int, y: Int) -> NSColor {
            header.appearance = NSAppearance(named: appearance)
            let bitmap = header.bitmapImageRepForCachingDisplay(in: header.bounds)!
            header.cacheDisplay(in: header.bounds, to: bitmap)
            let scaleX = CGFloat(bitmap.pixelsWide) / header.bounds.width
            let scaleY = CGFloat(bitmap.pixelsHigh) / header.bounds.height
            return bitmap.colorAt(x: Int((CGFloat(x) + 0.5) * scaleX),
                                  y: Int((CGFloat(y) + 0.5) * scaleY))!
        }
        let lightRule = sample(.aqua, x: 170, y: 40)
        let darkRule = sample(.darkAqua, x: 170, y: 40)
        expect(abs(lightRule.redComponent - 0.93) < 0.02 && abs(darkRule.redComponent - 0.158) < 0.02, "Actual separator resolves the attributed light/dark Gray4 values")
        let darkInk = icon.contentTintColor!.usingColorSpace(.sRGB)!
        expect(abs(darkInk.redComponent - 0.439) < 0.01, "Actual dark icon resolves Gray9")
        header.appearance = NSAppearance(named: .aqua)
        expect(abs(icon.contentTintColor!.usingColorSpace(.sRGB)!.redComponent - 0.561) < 0.01, "Returning to light appearance replaces cached dark ink")
        try registry.set(KeyboardShortcut(key: "w", flags: .command), for: "extensions:")
        expect(view.selectCommand("extensions:"), "Original customized command remains revealable")
        let customCell = table.view(atColumn: 0, row: 0, makeIfNecessary: true)!
        expect(customCell.subviews.compactMap { $0 as? NSTextField }.first?.stringValue == "Customized Shortcuts",
               "Changed binding uses the attributed Customized section title")
        let conflictRow = table.rowView(atRow: table.selectedRow, makeIfNecessary: true)!
        conflictRow.layoutSubtreeIfNeeded()
        let conflictLayer = conflictRow.layer!.sublayers!.first!
        expect(abs((conflictLayer.backgroundColor?.alpha ?? 0) - 0.2) < 0.001,
               "Selected persisted conflict uses the original stronger red selection")
        expect(registry.isConflicting("extensions:") && registry.isConflicting("closeTab:"),
               "Selection presentation does not resolve or replace either saved conflict")
        let afterConflictRevision = registry.revision
        let beforeDetach = field.stringValue
        window.contentView = nil; clear.performPress(); banner.performPress()
        expect(!clear.rootView.presentation.present && !clear.rootView.presentation.active && bannerActions == 1, "Detach retires clear subtree and rejects Basics action")
        expect(field.stringValue == beforeDetach && registry.revision == afterConflictRevision, "Detached clear cannot mutate input or persistent bindings")
        window.close()
        print("Shortcut search production component: \(assertions) assertions passed")
    }
}
