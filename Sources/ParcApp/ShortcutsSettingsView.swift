import AppKit
import Combine
import SwiftUI
import Carbon.HIToolbox

@MainActor
final class ShortcutsSettingsView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let shortcuts: KeyboardShortcuts
    private let numberedTargetDefaults: UserDefaults
    private let searchHeader = ShortcutSearchHeader()
    private var search: NSTextField { searchHeader.field }
    private let table = ShortcutTableView()
    private let keycaps = ShortcutKeycapView()
    private let heading = NSTextField(wrappingLabelWithString: "Custom Shortcuts")
    private let explanation = NSTextField(wrappingLabelWithString: "Change shortcuts for your favorite actions.")
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private let reset = PointingHandButton(title: "Reset All Shortcuts", target: nil, action: nil)
    private let more = PointingHandButton()
    private let priority = PointingHandPopUpButton(frame: .zero, pullsDown: false)
    private let priorityHelp = NSTextField(wrappingLabelWithString: "")
    private let detailDivider = NSBox()
    //
    // bindings: Favorites on item1…item8; item9 shows its ninth-item toggle,
    //
    private let includeFavorites = PointingHandButton(checkboxWithTitle: "Include Favorites in ordering.", target: nil, action: nil)
    private let ninthItem = PointingHandButton(checkboxWithTitle: "Switch to ninth tab.", target: nil, action: nil)
    private let captureGesture = PointingHandButton(checkboxWithTitle: "Hold Command and Shift to start a Capture.", target: nil, action: nil)
    private var interactiveSymbols: [String]?
    private var subscription: AnyCancellable?
    private var systemSubscriptions: [AnyCancellable] = []
    private let systemShortcutProvider: @MainActor () -> Set<KeyboardShortcut>
    private var systemShortcuts: Set<KeyboardShortcut> = []
    private enum Row { case group(String), command(KeyboardShortcuts.Command) }
    private var rows: [Row] = []
    private var selectedID: String?
    private var refreshing = false
    private weak var activeRecorder: ShortcutRecorderView?
    override var isFlipped: Bool { true }

    init(shortcuts: KeyboardShortcuts, numberedTargetDefaults: UserDefaults = .standard,
         systemShortcutProvider: @escaping @MainActor () -> Set<KeyboardShortcut> = { KeyboardShortcut.systemShortcuts() }) {
        self.shortcuts = shortcuts
        self.numberedTargetDefaults = numberedTargetDefaults
        self.systemShortcutProvider = systemShortcutProvider
        super.init(frame: NSRect(x: 0, y: 0, width: 684, height: 562))
        let basics = ShortcutBasicsBanner()
        basics.frame = NSRect(x: 0, y: 18, width: 684, height: 36)
        basics.onPress = { [weak self] in self?.showEssentials(nil) }
        addSubview(basics)
        let listBackground = ShortcutListSurface(frame: NSRect(x: 64, y: 84, width: 340, height: 450))
        addSubview(listBackground)
        searchHeader.frame = NSRect(x: 64, y: 84, width: 340, height: 41)
        search.delegate = self
        searchHeader.onClear = { [weak self] in self?.clearSearch() }
        addSubview(searchHeader)
        let column = NSTableColumn(identifier: .init("shortcut")); column.width = 324
        table.addTableColumn(column); table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.headerView = nil; table.style = .plain; table.rowHeight = 48
        table.intercellSpacing = .zero; table.backgroundColor = .clear
        table.dataSource = self; table.delegate = self; table.allowsEmptySelection = true
        table.setAccessibilityLabel("Keyboard shortcuts")
        table.commandMenu = { [weak self] row in
            guard let self, self.rows.indices.contains(row), case .command(let command) = self.rows[row] else { return nil }
            return self.commandMenu(for: command.id)
        }
        let scroll = NSScrollView(frame: NSRect(x: 64, y: 125, width: 340, height: 409))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        table.frame = scroll.bounds; table.autoresizingMask = [.width]
        scroll.documentView = table; addSubview(scroll)
        keycaps.size = .large; keycaps.alignment = .leading
        keycaps.frame = NSRect(x: 420, y: 84, width: 200, height: 64); addSubview(keycaps)
        heading.frame = NSRect(x: 420, y: 174, width: 200, height: 22)
        heading.font = .systemFont(ofSize: 14, weight: .bold); addSubview(heading)
        explanation.frame = NSRect(x: 420, y: 203, width: 200, height: 40)
        explanation.font = .systemFont(ofSize: 12); explanation.textColor = .secondaryLabelColor; addSubview(explanation)
        detailDivider.boxType = .separator; detailDivider.frame = NSRect(x: 420, y: 236, width: 200, height: 1)
        addSubview(detailDivider)
        priority.addItems(withTitles: KeyboardShortcuts.Priority.allCases.map(\.title))
        priority.font = .systemFont(ofSize: 12); priority.frame = NSRect(x: 420, y: 253, width: 148, height: 26)
        priority.target = self; priority.action = #selector(priorityChanged)
        priority.setAccessibilityLabel("Shortcut priority"); addSubview(priority)
        priorityHelp.frame = NSRect(x: 420, y: 285, width: 200, height: 86)
        priorityHelp.font = .systemFont(ofSize: 12); priorityHelp.textColor = .secondaryLabelColor; addSubview(priorityHelp)
        for toggle in [includeFavorites, ninthItem, captureGesture] {
            toggle.font = .systemFont(ofSize: 12); toggle.target = self
            toggle.action = #selector(numberedTargetSettingChanged(_:)); toggle.isHidden = true
            addSubview(toggle)
        }
        captureGesture.cell?.wraps = true
        captureGesture.cell?.lineBreakMode = .byWordWrapping
        feedback.frame = NSRect(x: 420, y: 402, width: 200, height: 90)
        feedback.font = .systemFont(ofSize: 11); feedback.textColor = .secondaryLabelColor
        feedback.setAccessibilityLabel("Shortcut status"); addSubview(feedback)
        reset.frame = NSRect(x: 420, y: 506, width: 174, height: 28)
        reset.bezelStyle = .rounded; reset.target = self; reset.action = #selector(resetShortcut); addSubview(reset)
        more.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More shortcut actions")
        more.bezelStyle = .circular; more.isBordered = true
        more.frame = NSRect(x: 596, y: 507, width: 26, height: 26)
        more.target = self; more.action = #selector(showMore); addSubview(more)
        subscription = shortcuts.$revision.receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }
        systemSubscriptions = [
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
                .receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshSystemShortcuts() },
            DistributedNotificationCenter.default().publisher(for: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String))
                .receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshSystemShortcuts() }
        ]
        systemShortcuts = systemShortcutProvider()
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { refreshSystemShortcuts() }
        else { endRecording() }
    }
    private func refreshSystemShortcuts() {
        systemShortcuts = systemShortcutProvider()
        updateVisibleRecorders()
    }

    @discardableResult func selectCommand(_ id: String) -> Bool {
        guard shortcuts.commands.contains(where: { $0.id == id }) else { return false }
        endRecording()
        search.stringValue = ""; feedback.stringValue = ""; selectedID = id
        refresh()
        guard let row = rows.firstIndex(where: {
            if case .command(let command) = $0 { return command.id == id }; return false
        }) else { return false }
        table.scrollRowToVisible(row)
        // Selection reveals the editor; it does not start recording or consume
        // the next key that the user intended for normal Settings navigation.
        return true
    }

    func endRecording() {
        stopRecorder(); interactiveSymbols = nil
        updateDetails(); table.reloadData()
    }
    private func stopRecorder() { activeRecorder?.cancelRecording() }
    func controlTextDidChange(_ notification: Notification) { stopRecorder(); feedback.stringValue = ""; refresh() }
    private func clearSearch() {
        guard let window, window.isKeyWindow, window.isVisible, window.attachedSheet == nil,
              !isHiddenOrHasHiddenAncestor else { return }
        if let editor = search.currentEditor() as? NSTextView {
            // Use the original editor so selection, marked text and its Undo
            // history belong to AppKit. A deliberate clear replaces its text.
            editor.insertText("", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        } else {
            search.stringValue = ""
            controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        }
    }
    private func refresh() {
        stopRecorder()
        searchHeader.refresh()
        let terms = search.stringValue.lowercased().split(whereSeparator: { $0.isWhitespace })
        let commands = shortcuts.commands.filter { command in
            let text = (command.title + " " + command.group + " " + (shortcuts.shortcut(for: command.id)?.searchText ?? "")).lowercased()
            return terms.allSatisfy { text.contains($0) }
        }
        rows = []
        for (title, customized) in [("Customized Shortcuts", true), ("Default Shortcuts", false)] {
            let matching = commands.filter { shortcuts.isCustomized($0.id) == customized }
            if !matching.isEmpty { rows.append(.group(title)); rows += matching.map(Row.command) }
        }
        refreshing = true; table.reloadData()
        if let index = rows.firstIndex(where: { if case .command(let command) = $0 { return command.id == selectedID }; return false }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else { selectedID = nil; table.deselectAll(nil) }
        refreshing = false
        updateDetails()
        if let error = shortcuts.loadError { showStatus(error, error: true) }
        else if commands.isEmpty { showStatus("No matching shortcuts.") }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = ShortcutRowView()
        view.sectionInset = sectionInset(for: row)
        if case .command(let command) = rows[row] { view.isConflicting = shortcuts.isConflicting(command.id) }
        return view
    }
    private func sectionInset(for row: Int) -> CGFloat {
        guard row > 0, case .command = rows[row], case .group = rows[row - 1] else { return 0 }
        return 10
    }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .group = rows[row] { return 29 }; return 48 + sectionInset(for: row)
    }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .group = rows[row] { return false }; return true
    }
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .group = rows[row] { return true }; return false
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let width = tableColumn?.width ?? 324
        let cell = ShortcutCellView(frame: NSRect(x: 0, y: 0, width: width, height: 48 + sectionInset(for: row)))
        switch rows[row] {
        case .group(let title):
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 11, weight: .semibold); label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 14, y: 7, width: width - 28, height: 18); cell.addSubview(label)
        case .command(let command):
            let label = NSTextField(labelWithString: command.title)
            label.textColor = .labelColor
            label.font = .systemFont(ofSize: NSFont.systemFontSize); label.lineBreakMode = .byTruncatingTail
            label.frame = NSRect(x: 22, y: 14, width: min(200, width - 122), height: 20)
            label.toolTip = command.title
            label.autoresizingMask = [.width]; cell.addSubview(label)
            let recorder = ShortcutRecorderView(frame: NSRect(x: width - 72, y: 12, width: 64, height: 24))
            recorder.autoresizingMask = [.minXMargin]
            recorder.identifier = NSUserInterfaceItemIdentifier(command.id)
            recorder.shortcut = shortcuts.shortcut(for: command.id)
            recorder.isConflicting = shortcuts.isConflicting(command.id)
            recorder.rowSelected = command.id == selectedID
            recorder.isEnabled = shortcuts.loadError == nil
            recorder.setAccessibilityLabel("Shortcut for " + command.title)
            recorder.onBegin = { [weak self, weak recorder] in
                guard let self else { return }
                self.interactiveSymbols = nil
                self.selectedID = command.id; self.activeRecorder = recorder
                self.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                self.updateDetails()
            }
            recorder.onPreview = { [weak self] symbols in
                guard let self, self.selectedID == command.id else { return }
                self.interactiveSymbols = symbols.isEmpty ? nil : symbols
                self.updateDetails()
            }
            recorder.onEnd = { [weak self, weak recorder] in
                guard let self, self.activeRecorder === recorder else { return }
                self.activeRecorder = nil; self.interactiveSymbols = nil; self.updateDetails()
            }
            recorder.onChange = { [weak self, weak recorder] value in
                guard let self else { return false }
                do {
                    try self.shortcuts.set(value, for: command.id)
                    self.interactiveSymbols = nil; self.updateDetails()
                    recorder?.isConflicting = self.shortcuts.isConflicting(command.id)
                    self.showStatus(value == nil ? "Shortcut removed." : "Shortcut updated."); return true
                } catch { self.showStatus(error.localizedDescription, error: true); return false }
            }
            cell.addSubview(recorder)
            updateWarning(in: cell, commandID: command.id)
            let separator = NSBox(); separator.boxType = .separator
            separator.frame = NSRect(x: 12, y: 0, width: width - 24, height: 1); separator.autoresizingMask = [.width]; cell.addSubview(separator)
        }
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !refreshing else { return }
        let row = table.selectedRow
        guard rows.indices.contains(row), case .command(let command) = rows[row] else { selectedID = nil; updateDetails(); return }
        if selectedID != command.id { stopRecorder(); feedback.stringValue = "" }
        selectedID = command.id; updateDetails()
    }
    private func updateDetails() {
        let command = shortcuts.commands.first { $0.id == selectedID }
        let savedBinding = command.flatMap { shortcuts.shortcut(for: $0.id) }
        let binding = savedBinding
        keycaps.isInConflict = command.map { shortcuts.isConflicting($0.id) } ?? false
        keycaps.symbols = interactiveSymbols ?? binding?.symbols ?? []
        keycaps.presentation = command == nil ? .introduction : keycaps.symbols.isEmpty ? .unassigned : .binding
        keycaps.bindingDescription = interactiveSymbols == nil ? binding?.spokenDisplay : nil
        heading.stringValue = command?.title ?? "Custom Shortcuts"
        let descriptions = ["exit:": "Exit the current context, such as closing a Peek window or exiting fullscreen.",
                            "newTab:": "Creates a new tab.", "closeTab:": "Closes the tab or window that’s in focus.",
                            "capturePage:": "Click or drag to capture a portion of this page.",
                            "captureFullPage:": "Captures the entire webpage as an image.", "cycleToNextRecentTab:": "Switches to a recently used tab.",
                            "cycleToPreviousRecentTab:": "Switches backward through recently used tabs.",
                            "copyCurrentURL:": "Copies the current tab’s URL.", "split:": "Adds a new page to your current Split View.",
                            //
                            "closeSplitPane:": "Closes the Split View page that’s currently in focus.",
                            "separateSplitPane:": "Separate Page from Split View.",
                            "firstSplitPane:": "Jumps to the first Split View page in your current window.",
                            "secondSplitPane:": "Jumps to the second Split View page in your current window.",
                            "thirdSplitPane:": "Jumps to the third Split View page in your current window.",
                            "fourthSplitPane:": "Jumps to the fourth Split View page in your current window.",
                            "nextSplitPane:": "Jumps to the next Split View page in your current window.",
                            "previousSplitPane:": "Jumps to the previous Split View page in your current window."]
        let defaults = numberedTargetDefaults
        let excludeFavorites = defaults.bool(forKey: NumberedTarget.excludeFavoritesKey)
        let ninthEnabled = defaults.bool(forKey: NumberedTarget.ninthItemKey)
        let itemNumber = command.flatMap { NumberedTarget.itemNumber($0.id) }
        includeFavorites.isHidden = itemNumber == nil || (itemNumber == 9 && !ninthEnabled)
        includeFavorites.state = excludeFavorites ? .off : .on
        ninthItem.isHidden = itemNumber != 9; ninthItem.state = ninthEnabled ? .on : .off
        captureGesture.isHidden = command?.id != "capturePage:"
        captureGesture.state = CaptureGesturePreference.isEnabled(defaults: defaults) ? .on : .off
        explanation.stringValue = command.flatMap { descriptions[$0.id]
            ?? NumberedTarget.description(for: $0.id, excludeFavorites: excludeFavorites, ninthItemEnabled: ninthEnabled) } ?? (command == nil
            ? "Change shortcuts for your favorite actions, and choose whether Parc or a website takes priority." : "")
        // The binding, not an in-progress modifier preview, owns priority.
        //
        let showsPriority = command != nil && savedBinding != nil
        priority.isHidden = !showsPriority; detailDivider.isHidden = !showsPriority; priorityHelp.isHidden = !showsPriority
        priority.isEnabled = command.map { shortcuts.supportsPriority($0.id) } == true && shortcuts.loadError == nil
        let choice = command.map { shortcuts.priority(for: $0.id) } ?? .preferWebsites
        priority.selectItem(at: KeyboardShortcuts.Priority.allCases.firstIndex(of: choice) ?? 0)
        if command.map({ shortcuts.supportsPriority($0.id) }) != true {
            priorityHelp.stringValue = "Assign a shortcut with Command, Control or Option to choose its priority."
        } else {
            switch choice {
            case .preferWebsites: priorityHelp.stringValue = "When shortcuts conflict, the website wins."
            case .preferParc: priorityHelp.stringValue = "When shortcuts conflict, Parc wins."
            case .useBoth: priorityHelp.stringValue = "Press this shortcut once to use the website’s shortcut. Press it twice to use Parc’s shortcut."
            }
        }
        layoutDetails()
        reset.title = command == nil ? "Reset All Shortcuts" : "Reset Shortcut to Default"
        reset.isEnabled = command.map { shortcuts.isCustomized($0.id) } ?? shortcuts.hasOverrides
        updateVisibleRecorders()
    }
    @objc private func numberedTargetSettingChanged(_ sender: NSButton) {
        let defaults = numberedTargetDefaults
        if sender === includeFavorites { defaults.set(sender.state == .off, forKey: NumberedTarget.excludeFavoritesKey) }
        else if sender === ninthItem { defaults.set(sender.state == .on, forKey: NumberedTarget.ninthItemKey) }
        else if sender === captureGesture { CaptureGesturePreference.setEnabled(sender.state == .on, defaults: defaults) }
        updateDetails()
    }
    private func layoutDetails() {
        // Original VStack: 64-point keycap region, 24 below, title, 8 below,
        // natural description height, 24 below, then the conditional priority.
        func fittedHeight(_ field: NSTextField) -> CGFloat {
            guard !field.stringValue.isEmpty else { return 0 }
            field.preferredMaxLayoutWidth = 200
            field.invalidateIntrinsicContentSize()
            return ceil(field.sizeThatFits(NSSize(width: 200, height: CGFloat.greatestFiniteMagnitude)).height)
        }
        heading.frame = NSRect(x: 420, y: keycaps.frame.maxY + 24, width: 200, height: fittedHeight(heading))
        explanation.frame = NSRect(x: 420, y: heading.frame.maxY + 8, width: 200, height: fittedHeight(explanation))
        detailDivider.frame.origin.y = explanation.frame.maxY + 24
        priority.frame.origin.y = detailDivider.frame.maxY + 16
        priorityHelp.frame = NSRect(x: 420, y: priority.frame.maxY + 8, width: 200, height: fittedHeight(priorityHelp))
        var toggleY = (priority.isHidden ? explanation.frame.maxY : priorityHelp.frame.maxY) + 24
        for toggle in [ninthItem, includeFavorites, captureGesture] where !toggle.isHidden {
            let height = ceil(toggle.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 200, height: 1000)).height ?? toggle.fittingSize.height)
            toggle.frame = NSRect(x: 420, y: toggleY, width: 200, height: height)
            toggleY += height + 8
        }
        // Extra settings share the detail column without covering save feedback.
        let feedbackY = max(402, toggleY + 8)
        feedback.frame = NSRect(x: 420, y: feedbackY, width: 200,
                                height: max(0, reset.frame.minY - feedbackY - 8))
        feedback.toolTip = feedback.stringValue
        // These wrapping fields change between one and several lines while
        // retaining their native cells. Re-layout the original text subviews
        // after manual frame changes; otherwise AppKit can keep the old clip.
        for field in [heading, explanation, priorityHelp] {
            field.needsLayout = true
            field.layoutSubtreeIfNeeded()
            field.needsDisplay = true
        }
    }
    private func updateVisibleRecorders() {
        for row in rows.indices {
            guard let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) else { continue }
            for case let recorder as ShortcutRecorderView in cell.subviews {
                guard let id = recorder.identifier?.rawValue else { continue }
                recorder.rowSelected = id == selectedID
                recorder.isConflicting = shortcuts.isConflicting(id)
                recorder.shortcut = shortcuts.shortcut(for: id)
                if let cell = cell as? ShortcutCellView { updateWarning(in: cell, commandID: id) }
            }
        }
    }
    private func updateWarning(in cell: ShortcutCellView, commandID: String) {
        let binding = shortcuts.shortcut(for: commandID)
        let conflicts = shortcuts.conflictingCommands(for: commandID)
        if let first = conflicts.first, let binding {
            let revision = shortcuts.revision
            let ids = conflicts.map(\.id)
            cell.showConflict(help: Self.conflictDescription(binding, conflicts: conflicts),
                              spoken: Self.conflictDescription(binding, conflicts: conflicts, spoken: true)) { [weak self, weak window] in
                guard let self, let window, self.window === window, window.isKeyWindow, window.isVisible,
                      window.attachedSheet == nil, !self.isHiddenOrHasHiddenAncestor,
                      self.shortcuts.revision == revision,
                      self.shortcuts.shortcut(for: commandID) == binding,
                      self.shortcuts.conflictingCommands(for: commandID).map(\.id) == ids,
                      let row = self.rows.firstIndex(where: { if case .command(let command) = $0 { return command.id == first.id }; return false }),
                      let clip = self.table.enclosingScrollView?.contentView else { return }
                // Original ScrollViewProxy.scrollTo(id, anchor: .center): reveal
                // only. Preserve the query, detail selection, edit and responder.
                let rect = self.table.rect(ofRow: row)
                let y = max(0, min(rect.midY - clip.bounds.height / 2, self.table.bounds.height - clip.bounds.height))
                clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
                self.table.enclosingScrollView?.reflectScrolledClipView(clip)
            }
        } else if let binding, systemShortcuts.contains(binding) {
            cell.showSystemWarning()
        } else { cell.clearWarning() }
    }
    static func conflictDescription(_ binding: KeyboardShortcut, conflicts: [KeyboardShortcuts.Command], spoken: Bool = false) -> String {
        guard let first = conflicts.first else { return "" }
        let suffix = conflicts.count == 1 ? "" : conflicts.count == 2 ? " and one other action" : " and \(conflicts.count - 1) other actions"
        return (spoken ? binding.spokenDisplay : binding.display) + " is already in use by “" + first.title + "”" + suffix
    }
    @objc private func priorityChanged(_ sender: NSPopUpButton) {
        guard let id = selectedID, KeyboardShortcuts.Priority.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        stopRecorder()
        do {
            try shortcuts.setPriority(KeyboardShortcuts.Priority.allCases[sender.indexOfSelectedItem], for: id)
            updateDetails(); showStatus("Shortcut priority updated.")
        } catch { updateDetails(); showStatus(error.localizedDescription, error: true) }
    }
    private func showStatus(_ message: String, error: Bool = false) {
        feedback.stringValue = message; feedback.toolTip = message; feedback.textColor = error ? .systemRed : .secondaryLabelColor
        NSAccessibility.post(element: feedback, notification: .valueChanged)
    }
    @objc private func resetShortcut(_ sender: Any?) {
        stopRecorder()
        if let id = selectedID { resetCommand(id) } else { resetAll() }
    }
    private func resetCommand(_ id: String) {
        do { try shortcuts.reset(id); refresh(); showStatus("Default shortcut restored.") }
        catch { updateDetails(); showStatus(error.localizedDescription, error: true) }
    }
    private func resetAll() {
        guard let window, permitsSettingsAction(in: window, revision: shortcuts.revision), shortcuts.hasOverrides else { return }
        // Original Action.keyBinding(.onResetToDefaults) directly invokes the
        // client reset. No extra confirmation sheet or delayed completion.
        do { try shortcuts.resetAll(); refresh(); showStatus("Default shortcuts restored.") }
        catch { showStatus(error.localizedDescription, error: true) }
    }
    func moreMenu() -> NSMenu? {
        guard let window else { return nil }
        stopRecorder()
        let menu = NSMenu(); menu.autoenablesItems = false
        if let id = selectedID, let proposal = conflict(for: id) {
            menu.addItem(conflictMenuItem(proposal)); menu.addItem(.separator())
        }
        if let id = selectedID {
            let remove = NSMenuItem(title: "Remove Shortcut", action: #selector(removeShortcut), keyEquivalent: "")
            remove.target = self; remove.representedObject = menuTarget(for: id)
            remove.isEnabled = shortcuts.loadError == nil && shortcuts.shortcut(for: id) != nil; menu.addItem(remove)
            menu.addItem(.separator())
        }
        let all = NSMenuItem(title: "Reset All Shortcuts", action: #selector(resetEveryShortcut), keyEquivalent: "")
        all.target = self; all.representedObject = ShortcutMenuTarget(id: "", revision: shortcuts.revision, window: window)
        all.isEnabled = shortcuts.hasOverrides; menu.addItem(all)
        return menu
    }
    @objc private func showMore(_ sender: NSButton) {
        moreMenu()?.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY), in: sender)
    }
    private func conflictMenuItem(_ proposal: KeyboardShortcuts.ConflictProposal) -> NSMenuItem {
        let item = NSMenuItem(title: proposal.conflicts.count == 1 ? "Remove Conflicting Shortcut" : "Remove Conflicting Shortcuts",
                             action: #selector(resolveConflict), keyEquivalent: "")
        item.target = self; item.representedObject = menuTarget(for: proposal.commandID)
        item.isEnabled = shortcuts.loadError == nil && proposal.revision == shortcuts.revision
        return item
    }
    private func conflict(for id: String) -> KeyboardShortcuts.ConflictProposal? {
        guard let binding = shortcuts.shortcut(for: id) else { return nil }
        return try? shortcuts.conflictProposal(for: binding, commandID: id)
    }
    @objc private func resolveConflict(_ sender: NSMenuItem) {
        guard let id = commandID(from: sender), let proposal = conflict(for: id) else { return }
        do {
            try shortcuts.resolveConflict(proposal)
            refresh(); showStatus("Conflicting shortcuts removed.")
        } catch { showStatus(error.localizedDescription, error: true) }
    }
    /// A row menu does not select the row or move native text focus.
    /// Its receipt keeps later actions on this original command.
    func commandMenu(for id: String) -> NSMenu? {
        guard shortcuts.commands.contains(where: { $0.id == id }), let target = menuTarget(for: id) else { return nil }
        stopRecorder()
        let menu = NSMenu(); menu.autoenablesItems = false
        if let proposal = conflict(for: id) {
            menu.addItem(conflictMenuItem(proposal)); menu.addItem(.separator())
        }
        let remove = NSMenuItem(title: "Remove Shortcut", action: #selector(removeShortcut), keyEquivalent: "")
        remove.target = self; remove.representedObject = target
        remove.isEnabled = shortcuts.loadError == nil && shortcuts.shortcut(for: id) != nil
        menu.addItem(remove)
        let reset = NSMenuItem(title: "Reset Shortcut to Default", action: #selector(resetMenuShortcut), keyEquivalent: "")
        reset.target = self; reset.representedObject = target
        reset.isEnabled = shortcuts.loadError == nil && shortcuts.isCustomized(id)
        menu.addItem(reset)
        return menu
    }
    private func menuTarget(for id: String) -> ShortcutMenuTarget? {
        guard let window else { return nil }
        return ShortcutMenuTarget(id: id, revision: shortcuts.revision, window: window)
    }
    private func permitsSettingsAction(in window: NSWindow, revision: Int) -> Bool {
        self.window === window && window.isVisible && window.isKeyWindow && window.attachedSheet == nil
            && !isHiddenOrHasHiddenAncestor && revision == shortcuts.revision
    }
    private func commandID(from sender: NSMenuItem) -> String? {
        guard let target = sender.representedObject as? ShortcutMenuTarget,
              let window = target.window, self.window === window,
              window.isVisible, window.isKeyWindow, window.attachedSheet == nil,
              !isHiddenOrHasHiddenAncestor, target.revision == shortcuts.revision,
              shortcuts.loadError == nil, shortcuts.commands.contains(where: { $0.id == target.id }) else { return nil }
        return target.id
    }
    @objc private func resetMenuShortcut(_ sender: NSMenuItem) {
        guard let id = commandID(from: sender), shortcuts.isCustomized(id) else { return }
        resetCommand(id)
    }
    @objc private func removeShortcut(_ sender: NSMenuItem) {
        guard let id = commandID(from: sender), shortcuts.shortcut(for: id) != nil else { return }
        let effect = id == selectedID ? ShortcutRemovalEffect.capture(keycaps) : nil
        do {
            // The file commit can fail. Preserve the original frame, but show
            // removal only after the durable write succeeds.
            try shortcuts.set(nil, for: id)
            effect?.show(); refresh(); showStatus("Shortcut removed.")
        } catch { showStatus(error.localizedDescription, error: true) }
    }
    @objc private func resetEveryShortcut(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? ShortcutMenuTarget, let window = target.window,
              permitsSettingsAction(in: window, revision: target.revision) else { return }
        resetAll()
    }
    @objc private func showEssentials(_ sender: Any?) {
        guard let window, window.isKeyWindow, window.isVisible,
              window.attachedSheet == nil, !isHiddenOrHasHiddenAncestor else { return }
        stopRecorder()
        NSApp.sendAction(NSSelectorFromString("showEssentialShortcuts:"), to: nil, from: self)
    }
}

@MainActor
private final class ShortcutRowView: NSTableRowView {
    var sectionInset: CGFloat = 0 { didSet { needsLayout = true } }
    var isConflicting = false { didSet { refreshSelection() } }
    private let selectionLayer = CALayer()
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    override var isSelected: Bool { didSet { refreshSelection() } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        selectionLayer.cornerRadius = 8; selectionLayer.cornerCurve = .continuous
        layer?.insertSublayer(selectionLayer, at: 0)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() { super.layout(); refreshSelection() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshSelection() }
    override func drawSelection(in dirtyRect: NSRect) { refreshSelection() }
    private func refreshSelection() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        selectionLayer.isHidden = !isSelected || selectionHighlightStyle == .none
        selectionLayer.frame = NSRect(x: 16, y: (isFlipped ? sectionInset : 0) + 4,
                                      width: max(0, bounds.width - 32), height: 40)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            selectionLayer.backgroundColor = (isConflicting ? NSColor.systemRed : .controlAccentColor)
                .withAlphaComponent(isConflicting ? 0.2 : 0.1).cgColor
        }
        CATransaction.commit()
    }
}

@MainActor
private final class ShortcutMenuTarget: NSObject {
    let id: String
    let revision: Int
    weak var window: NSWindow?
    init(id: String, revision: Int, window: NSWindow) {
        self.id = id; self.revision = revision; self.window = window
    }
}

@MainActor
private final class ShortcutTableView: NSTableView {
    var commandMenu: ((Int) -> NSMenu?)?
    override func menu(for event: NSEvent) -> NSMenu? {
        guard event.window === window else { return nil }
        return commandMenu?(row(at: convert(event.locationInWindow, from: nil)))
    }
}

///
/// a custom keycap transition. Native conversion handles flipped view geometry.
@MainActor
struct ShortcutRemovalEffect {
    private weak var view: ShortcutKeycapView?
    private weak var window: NSWindow?
    let screenFrame: NSRect
    static func capture(_ view: ShortcutKeycapView, reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) -> Self? {
        guard !reduceMotion, let window = view.window, window.isKeyWindow, window.isVisible,
              window.attachedSheet == nil, !view.isHiddenOrHasHiddenAncestor,
              view.presentation == .binding, !view.symbols.isEmpty,
              view.keycapBounds.width > 0, view.keycapBounds.height > 0 else { return nil }
        let frame = window.convertToScreen(view.convert(view.keycapBounds, to: nil))
        guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy({ $0.isFinite }) else { return nil }
        return Self(view: view, window: window, screenFrame: frame)
    }
    var isCurrent: Bool {
        guard let view, let window, view.window === window,
              let current = Self.capture(view) else { return false }
        return current.screenFrame == screenFrame
    }
    func show() {
        guard isCurrent else { return }
        NSAnimationEffect.poof.show(centeredAt: NSPoint(x: screenFrame.midX, y: screenFrame.midY),
                                    size: screenFrame.size, completionHandler: {})
    }
}

/// Original warning owns only its action/tooltip. It never selects a row.
@MainActor private final class ShortcutCellView: NSView {
    private var warning: NSView?
    private var onReveal: (() -> Void)?
    func clearWarning() { warning?.removeFromSuperview(); warning = nil; onReveal = nil }
    func showConflict(help: String, spoken: String, reveal: @escaping () -> Void) {
        onReveal = reveal
        let button = (warning as? NSButton) ?? PointingHandButton(image: NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)!,
                              target: self, action: #selector(revealConflict))
        button.isBordered = false; button.imagePosition = .imageOnly; button.contentTintColor = .systemRed
        button.toolTip = help; button.setAccessibilityLabel(spoken); button.setAccessibilityHelp("Show the conflicting shortcut")
        install(button)
    }
    func showSystemWarning() {
        onReveal = nil
        let image = (warning as? NSImageView) ?? NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)!)
        image.contentTintColor = .systemOrange
        let help = "System shortcuts may take priority over this shortcut"
        image.toolTip = help; image.setAccessibilityLabel(help)
        install(image)
    }
    private func install(_ view: NSView) {
        if warning !== view { warning?.removeFromSuperview() }
        view.frame = NSRect(x: bounds.width - 100, y: 16, width: 16, height: 16)
        view.autoresizingMask = [.minXMargin]; addSubview(view); warning = view
    }
    @objc private func revealConflict(_ sender: NSButton) { onReveal?() }
}


/// The callout keeps the actual SwiftUI prominent Button, including its native
/// focus, pressed and accessibility behavior. Its parent remains the Settings
/// action owner; the background and symbol do not introduce separate actions.
@MainActor final class ShortcutBasicsBanner: NSHostingView<ShortcutBasicsContent> {
    var onPress: (() -> Void)?
    required init(rootView: ShortcutBasicsContent) { super.init(rootView: rootView) }
    convenience init() {
        self.init(rootView: ShortcutBasicsContent(onPress: {}))
        rootView = ShortcutBasicsContent(onPress: { [weak self] in self?.performPress() })
    }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func performPress() {
        guard let window, window.isVisible, window.isKeyWindow,
              window.attachedSheet == nil, !isHiddenOrHasHiddenAncestor else { return }
        onPress?()
    }
}

struct ShortcutBasicsContent: View {
    @Environment(\.colorScheme) private var colorScheme
    let onPress: () -> Void
    var body: some View {
        HStack {
            Text("Start with the basics").font(.system(size: 13)).opacity(0.85)
            Button(action: onPress) {
                Image(systemName: "command.circle.fill").frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text("Learn the Essential Shortcuts").font(.system(size: 13)).opacity(0.85)
            }
            .buttonStyle(.borderedProminent)
            .pointingHandCursor()
            .accessibilityLabel("Learn the Essential Shortcuts")
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(colorScheme == .dark
                  ? Color(.sRGB, red: 101/255, green: 96/255, blue: 104/255, opacity: 1)
                  : .white)
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
            .allowsHitTesting(false))
        .frame(maxWidth: .infinity)
    }
}

@MainActor final class ShortcutClearPresentation: ObservableObject {
    @Published var present = false
    @Published var active = false
}

/// One real borderless SwiftUI Button owns the attributed opacity spring.
/// Removing the conditional subtree retires its hover/animation state. Native
/// editing, composition and Undo remain with the adjacent NSTextField editor.
@MainActor final class ShortcutSearchClearControl: NSHostingView<ShortcutClearContent> {
    private let presentation: ShortcutClearPresentation
    private var observations: [NSObjectProtocol] = []
    var onPress: (() -> Void)?
    required init(rootView: ShortcutClearContent) {
        presentation = rootView.presentation
        super.init(rootView: rootView)
    }
    convenience init() {
        self.init(rootView: ShortcutClearContent(presentation: ShortcutClearPresentation(), onPress: {}))
        rootView = ShortcutClearContent(presentation: presentation, onPress: { [weak self] in self?.performPress() })
    }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observations.forEach(NotificationCenter.default.removeObserver); observations.removeAll()
        if let window {
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                         NSWindow.willBeginSheetNotification, NSWindow.didEndSheetNotification,
                         NSWindow.willCloseNotification] {
                observations.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                    MainActor.assumeIsolated {
                        guard let self, let original = notification.object as? NSWindow,
                              self.window === original else { return }
                        if notification.name == NSWindow.willCloseNotification {
                            self.presentation.active = false; self.presentation.present = false
                        } else if notification.name == NSWindow.willBeginSheetNotification {
                            self.presentation.active = false
                        } else { self.refreshPresence() }
                    }
                })
            }
        }
        refreshPresence()
    }
    override func viewDidHide() { super.viewDidHide(); refreshPresence() }
    override func viewDidUnhide() { super.viewDidUnhide(); refreshPresence() }
    func refreshPresence() {
        let present = window != nil && !isHiddenOrHasHiddenAncestor
        let active = present && window?.isKeyWindow == true && window?.isVisible == true && window?.attachedSheet == nil
        // Retire hover state first when its original owner is lost. Unchanged
        // query updates leave the existing SwiftUI subtree and focus intact.
        if presentation.active != active { presentation.active = active }
        if presentation.present != present { presentation.present = present }
    }
    func performPress() {
        guard let window, window.isVisible, window.isKeyWindow,
              window.attachedSheet == nil, !isHiddenOrHasHiddenAncestor else { return }
        onPress?()
    }
    deinit { observations.forEach(NotificationCenter.default.removeObserver) }
}

struct ShortcutClearContent: View {
    @ObservedObject var presentation: ShortcutClearPresentation
    let onPress: () -> Void
    var body: some View {
        if presentation.present {
            ShortcutClearButton(active: presentation.active, onPress: onPress)
        }
    }
}

private struct ShortcutClearButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opacity = 0.0
    let active: Bool
    let onPress: () -> Void
    var body: some View {
        Button(action: onPress) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color(white: colorScheme == .dark ? 0.439 : 0.561))
                .pointingHandCursor()
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Clear search")
        .opacity(opacity)
        .animation(active && !reduceMotion ? .spring(response: 0.28, dampingFraction: 0.63, blendDuration: 0) : nil,
                   value: opacity)
        .onAppear { opacity = 1 }
        .onDisappear { opacity = 0 }
        .onHover { hovered in opacity = active && hovered ? 0.3 : 1 }
        .onChange(of: active) { isActive in if !isActive { opacity = 1 } }
    }
}

/// The original Shortcuts producer uses a plain native text field with no
/// focus ring, plus independent search and clear controls. NSSearchField's
/// bezel/cell offsets are not part of this presentation.
@MainActor final class ShortcutSearchHeader: NSView {
    let field = NSTextField(string: "")
    private let icon = NSImageView()
    private let clear = ShortcutSearchClearControl()
    var onClear: (() -> Void)?
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8; layer?.cornerCurve = .continuous
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer?.masksToBounds = true
        field.isBordered = false; field.isBezeled = false; field.drawsBackground = false
        field.focusRingType = .none; field.maximumNumberOfLines = 1
        field.usesSingleLineMode = true; field.font = .systemFont(ofSize: 13)
        field.placeholderString = "Type a feature name or shortcut (like “Command E”)"
        field.setAccessibilityLabel("Search actions or shortcuts")
        icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        icon.setAccessibilityElement(false)
        clear.onPress = { [weak self] in self?.onClear?() }
        clear.isHidden = true
        addSubview(icon); addSubview(field); addSubview(clear)
        refreshColors()
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); refreshColors()
    }
    private func refreshColors() {
        let ink = ShortcutListSurface.gray(light: 0.561, dark: 0.439, appearance: effectiveAppearance)
        icon.contentTintColor = ink; needsDisplay = true
    }
    func refresh() {
        clear.isHidden = field.stringValue.isEmpty
        clear.refreshPresence()
        needsLayout = true
    }
    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 16, y: 13.5, width: 13, height: 13)
        clear.frame = NSRect(x: bounds.width - 29, y: 13.5, width: 13, height: 13)
        field.frame = NSRect(x: 33, y: 8, width: max(0, bounds.width - 49 - (clear.isHidden ? 0 : 21)), height: 24)
    }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSColor.white.withAlphaComponent(dark ? 0.1 : 1).setFill()
        bounds.fill()
        ShortcutListSurface.gray(light: 0.93, dark: 0.158, appearance: effectiveAppearance).setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }
}

@MainActor private final class ShortcutListSurface: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8; layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        refreshColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); refreshColors()
    }
    private func refreshColors() {
        layer?.borderColor = Self.gray(light: 0.858, dark: 0.243, appearance: effectiveAppearance).cgColor
    }
    static func gray(light: CGFloat, dark: CGFloat, appearance: NSAppearance) -> NSColor {
        let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        return NSColor(srgbRed: value, green: value, blue: value, alpha: 1)
    }
}
