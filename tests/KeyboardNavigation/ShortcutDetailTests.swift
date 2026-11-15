import AppKit
import Carbon.HIToolbox

@MainActor private final class ShortcutMenuWindow: NSWindow {
    var permitsCommands = true
    override var isKeyWindow: Bool { permitsCommands }
    override var isVisible: Bool { true }
}

@main @MainActor struct ShortcutDetailTests {
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
        for (title, id, key) in [("Archive Tab", "closeTab:", "w"), ("Capture Full Page", "captureFullPage:", ""),
                                 ("Capture Portion…", "capturePage:", ""),
                                 ("Switch to next Split View", "nextSplitPane:", "")] {
            let item = NSMenuItem(title: title, action: NSSelectorFromString(id), keyEquivalent: key)
            item.keyEquivalentModifierMask = .command; menu.addItem(item); registry.register(item, group: "File")
        }
        let numberedDomain = "Parc.KB04." + UUID().uuidString
        let numberedDefaults = UserDefaults(suiteName: numberedDomain)!
        defer { numberedDefaults.removePersistentDomain(forName: numberedDomain) }
        for number in [1, 9] {
            let item = NSMenuItem(title: number == 9 ? "Go to last Sidebar Item" : "Go to Sidebar Item 1",
                                  action: NSSelectorFromString("goToSidebarItem:"), keyEquivalent: String(number))
            item.keyEquivalentModifierMask = .command; menu.addItem(item)
            registry.register(item, group: "Tabs", bindingID: NumberedTarget.itemBindingID(number))
        }
        let view = ShortcutsSettingsView(shortcuts: registry, numberedTargetDefaults: numberedDefaults)
        let window = NSWindow(contentRect: view.frame, styleMask: .titled, backing: .buffered, defer: true)
        window.contentView = view
        let keycaps = view.subviews.compactMap { $0 as? ShortcutKeycapView }.first!
        let picker = view.subviews.compactMap { $0 as? NSPopUpButton }.first!
        let labels = view.subviews.compactMap { $0 as? NSTextField }
        let heading = labels.first { $0.stringValue == "Custom Shortcuts" }!
        let explanation = labels.first { $0.stringValue.hasPrefix("Change shortcuts") }!
        let search = view.subviews.compactMap { $0 as? ShortcutSearchHeader }.first!.field
        expect(keycaps.presentation == .introduction && keycaps.symbols.isEmpty, "No selection uses artwork, not a fake bound Command key")
        expect(keycaps.accessibilityValue() as? String == "Customize keyboard shortcuts", "Decorative introduction has one semantic AX owner")
        expect(picker.isHidden, "No selection has no command priority")
        expect(keycaps.frame.size == NSSize(width: 200, height: 64), "Original detail geometry")
        expect(heading.font?.pointSize == 14 && heading.frame.minY == keycaps.frame.maxY + 24, "Title follows original keycap gap")
        expect(explanation.frame.height > 40 && explanation.frame.minY == heading.frame.maxY + 8, "Introduction fits three lines without truncation")
        window.makeFirstResponder(search)
        let responder = window.firstResponder
        func renderedDescription() -> Data {
            let bitmap = explanation.bitmapImageRepForCachingDisplay(in: explanation.bounds)!
            explanation.cacheDisplay(in: explanation.bounds, to: bitmap)
            return Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        }
        expect(view.selectCommand("closeTab:"), "First command selection uses the original detail owner")
        let firstDescriptionFrame = explanation.frame
        let firstDescription = renderedDescription()
        expect(firstDescription.contains { $0 != 0 }, "First-selection native wrapped description actually draws")
        view.selectCommand("captureFullPage:"); view.selectCommand("closeTab:")
        expect(explanation.frame == firstDescriptionFrame && renderedDescription() == firstDescription,
               "First-selection text and clipping equal the same command after reselection")
        expect(window.firstResponder === responder, "Wrapped detail remeasurement preserves the original editor")
        expect(view.selectCommand("captureFullPage:"), "Existing unassigned command can be selected")
        expect(keycaps.presentation == .unassigned && keycaps.accessibilityValue() as? String == "No shortcut", "Unassigned action has blank artwork and truthful AX")
        expect(picker.isHidden, "Unassigned action omits priority")
        expect(window.firstResponder === responder, "Detail selection never starts a recorder or steals search focus")
        let table = view.subviews.compactMap { ($0 as? NSScrollView)?.documentView as? NSTableView }.first!
        let recorder = (0..<table.numberOfRows).compactMap { table.view(atColumn: 0, row: $0, makeIfNecessary: true) }
            .flatMap(\.subviews).compactMap { $0 as? ShortcutRecorderView }
            .first { $0.identifier?.rawValue == "captureFullPage:" }!
        recorder.onBegin?(); recorder.onPreview?(["⌘"])
        expect(keycaps.presentation == .binding && picker.isHidden, "Modifier preview does not create priority for an unassigned action")
        let revision = registry.revision
        expect(recorder.onChange?(registry.shortcut(for: "closeTab:")!) == true, "Conflicting chord is saved by the real editor")
        expect(keycaps.isInConflict && !picker.isHidden && picker.isEnabled, "Saved conflict retains actual binding priority")
        expect(registry.revision == revision + 1 && registry.shortcut(for: "captureFullPage:") == registry.shortcut(for: "closeTab:"), "Recorded conflict publishes one durable binding revision")
        view.endRecording()
        expect(keycaps.isInConflict && registry.isConflicting("closeTab:"), "Ending capture preserves both saved conflicting owners")
        try registry.set(nil, for: "captureFullPage:")
        expect(view.selectCommand("closeTab:"), "Bound action can be selected")
        expect(keycaps.presentation == .binding && keycaps.symbols == ["⌘", "W"], "Original actual binding is displayed")
        expect(!picker.isHidden && picker.isEnabled, "Bound priority remains actionable")
        let divider = view.subviews.compactMap { $0 as? NSBox }.first!
        expect(divider.frame.minY == explanation.frame.maxY + 24, "Divider follows natural description rather than overlapping it")
        expect(!keycaps.acceptsFirstResponder && keycaps.hitTest(.zero) == nil, "Decorative caps cannot own native keyboard/pointer input")
        for (count, side) in [(1, 64.0), (2, 64), (3, 64), (4, 47.75), (5, 37.6)] {
            expect(abs(ShortcutKeycapView.largeSide(width: 200, count: count) - side) < 0.001, "Count-sensitive actual column sizing")
        }
        let wide = KeyboardShortcut(key: "k", flags: [.command, .option, .control, .shift])
        try registry.set(wide, for: "closeTab:")
        view.selectCommand("closeTab:")
        expect(keycaps.symbols == wide.symbols && keycaps.accessibilityValue() as? String == wide.spokenDisplay, "Five-key custom binding updates existing detail owner")
        try registry.set(KeyboardShortcut(key: " ", flags: .control), for: "closeTab:"); view.selectCommand("closeTab:")
        expect(keycaps.symbols == ["⌃", "⎵"] && keycaps.accessibilityValue() as? String == "⌃Space",
               "Detail keycaps show Space as ⎵ and speak it as Space")
        try registry.set(KeyboardShortcut(key: "\t", flags: .control), for: "closeTab:"); view.selectCommand("closeTab:")
        expect(keycaps.symbols == ["⌃", "⇥"], "Detail keycaps keep ⇥ for Tab; Essentials and tooltip keycaps spell it out")
        try registry.set(nil, for: "closeTab:"); view.selectCommand("closeTab:")
        expect(keycaps.presentation == .unassigned && picker.isHidden, "Clear transitions away from stale keys and priority")
        try registry.reset("closeTab:"); view.selectCommand("closeTab:")
        expect(keycaps.presentation == .binding && !picker.isHidden, "Reset restores the actual binding and its priority")
        expect(view.selectCommand("nextSplitPane:")
               && explanation.stringValue == "Jumps to the next Split View page in your current window.",
               "Split commands carry their shortcut description")
        let numberedToggles = view.subviews.compactMap { $0 as? NSButton }
        let favorites = numberedToggles.first { $0.title == "Include Favorites in ordering." }!
        let ninth = numberedToggles.first { $0.title == "Switch to ninth tab." }!
        expect(view.selectCommand("item1") && !favorites.isHidden && ninth.isHidden && favorites.state == .on,
               "First eight items expose the included-Favorites default")
        expect(view.selectCommand("item9") && favorites.isHidden && !ninth.isHidden && ninth.state == .off,
               "Last-item mode exposes only the ninth-item toggle")
        ninth.performClick(nil)
        expect(numberedDefaults.bool(forKey: NumberedTarget.ninthItemKey) && !favorites.isHidden
               && ninth.frame.maxY < favorites.frame.minY, "Ninth mode persists and reveals Favorites beneath its toggle")
        favorites.performClick(nil)
        expect(numberedDefaults.bool(forKey: NumberedTarget.excludeFavoritesKey)
               && explanation.stringValue.contains("after your Favorites"), "Favorites toggle persists its inverse and refreshes the real description")
        try registry.setPriority(.useBoth, for: "item9"); view.selectCommand("item9")
        let status = labels.first { $0.accessibilityLabel() == "Shortcut status" }!
        expect(favorites.frame.maxY < status.frame.minY && status.frame.height > 0,
               "Additional controls leave the actual status field visible at the longest priority description")
        ninth.performClick(nil)
        expect(favorites.isHidden && numberedDefaults.bool(forKey: NumberedTarget.excludeFavoritesKey),
               "Returning to last-item mode hides Favorites without resetting the saved choice")
        expect(view.selectCommand("item1") && favorites.state == .off && !favorites.isHidden && ninth.isHidden,
               "Other numbered items read the shared saved ordering")
        view.selectCommand("closeTab:")
        expect(favorites.isHidden && ninth.isHidden, "Unrelated command removes numbered controls")
        let dragCapture = numberedToggles.first { $0.title == "Hold Command and Shift to start a Capture." }!
        expect(view.selectCommand("capturePage:") && !dragCapture.isHidden && dragCapture.state == .on,
               "Capture details expose the independent enabled drag preference")
        let captureBinding = registry.shortcut(for: "capturePage:")
        dragCapture.performClick(nil)
        expect(!CaptureGesturePreference.isEnabled(defaults: numberedDefaults)
               && registry.shortcut(for: "capturePage:") == captureBinding,
               "Disabling drag preserves the registered keyboard shortcut")
        try registry.set(nil, for: "capturePage:"); view.selectCommand("capturePage:")
        expect(!dragCapture.isHidden && dragCapture.state == .off && picker.isHidden,
               "Unassigned capture still exposes its saved independent gesture control")
        dragCapture.performClick(nil)
        expect(CaptureGesturePreference.isEnabled(defaults: numberedDefaults)
               && registry.shortcut(for: "capturePage:") == nil, "Enabling drag does not recreate a cleared chord")
        expect(dragCapture.frame.height > 20 && dragCapture.frame.maxY < status.frame.minY,
               "Wrapped capture control fits above feedback without clipping")
        expect(CaptureGesturePreference.permits([.command, .shift])
               && CaptureGesturePreference.permits([.command, .shift, .option, .control])
               && !CaptureGesturePreference.permits(.command) && !CaptureGesturePreference.permits(.shift),
               "Original drag mask requires both flags but does not reject extra modifiers")
        view.selectCommand("closeTab:")
        expect(dragCapture.isHidden, "Capture control is scoped to its own command")
        search.stringValue = "not an action"; view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        expect(keycaps.presentation == .introduction && picker.isHidden, "Filtering selected action away restores introduction")
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let artwork = ShortcutSmileyArtwork(data: data)!
        expect(artwork.frameRate == 30 && artwork.duration == 5, "Bundled winking-face timeline")
        func pixels(_ seconds: Double) -> Data {
            let context = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            artwork.draw(in: NSRect(x: 0, y: 0, width: 100, height: 100), seconds: seconds, context: context)
            return Data(bytes: context.data!, count: 40000)
        }
        let initial = pixels(0), middle = pixels(1), final = pixels(5)
        expect(initial != middle && middle != final, "Face transform, eye scale and mouth morph affect rendered vectors")
        expect(final == pixels(50), "Play-once endpoint clamps instead of looping")
        expect(initial == pixels(-1), "Reduced-motion initial frame is stable")
        let alpha = stride(from: 3, to: initial.count, by: 4).filter { initial[$0] != 0 }
        expect(alpha.count > 500 && alpha.count < 1800, "The face's three strokes render inside the mask without a solid rectangle")
        expect(initial[(60 * 100 + 39) * 4 + 3] > 0 && initial[(60 * 100 + 60) * 4 + 3] > 0,
               "Both eyes occupy their canvas positions")
        let smiley = ShortcutSmileyView(frame: .zero)
        expect(!smiley.acceptsFirstResponder && smiley.hitTest(.zero) == nil && !smiley.isAccessibilityElement(), "Animated decoration is passive and hidden from AX")
        let commandWindow = ShortcutMenuWindow(contentRect: view.frame, styleMask: .titled, backing: .buffered, defer: false)
        window.contentView = nil; commandWindow.contentView = view
        view.selectCommand("captureFullPage:")
        let selectedCaps = keycaps.accessibilityValue() as? String
        let closeRow = (0..<table.numberOfRows).first { row in
            table.view(atColumn: 0, row: row, makeIfNecessary: true)?.subviews.contains(where: {
                ($0 as? ShortcutRecorderView)?.identifier?.rawValue == "closeTab:"
            }) == true
        }!
        let rowFrame = table.rect(ofRow: closeRow)
        let rowEvent = NSEvent.mouseEvent(with: .rightMouseDown,
            location: table.convert(NSPoint(x: 20, y: rowFrame.midY), to: nil), modifierFlags: [],
            timestamp: 1, windowNumber: commandWindow.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
        let previousRow = table.selectedRow
        let rowMenu = table.menu(for: rowEvent)!
        expect(table.selectedRow == previousRow, "Native contextual entry never activates its target row")
        expect(rowMenu.items.map(\.title) == ["Remove Shortcut", "Reset Shortcut to Default"], "Original row context entries and ordering")
        expect(rowMenu.items[0].isEnabled && !rowMenu.items[1].isEnabled, "Bound default can be removed but has no reset")
        expect(keycaps.accessibilityValue() as? String == selectedCaps, "Opening another row's menu does not change detail selection")
        func invoke(_ item: NSMenuItem) { _ = NSApp.sendAction(item.action!, to: item.target, from: item) }
        invoke(rowMenu.items[0])
        expect(registry.shortcut(for: "closeTab:") == nil && registry.shortcut(for: "captureFullPage:") == nil, "Menu removes only the original unselected command")
        expect(keycaps.accessibilityValue() as? String == selectedCaps, "Removal elsewhere leaves selected details unchanged")
        let removedRevision = registry.revision
        invoke(rowMenu.items[0]); expect(registry.revision == removedRevision, "Old menu receipt cannot execute twice")
        let resetMenu = view.commandMenu(for: "closeTab:")!
        expect(!resetMenu.items[0].isEnabled && resetMenu.items[1].isEnabled, "Disabled shortcut has only Reset available")
        invoke(resetMenu.items[1])
        expect(registry.shortcut(for: "closeTab:")?.key == "w", "Original unselected row reset reaches the existing persistence owner")
        expect(keycaps.accessibilityValue() as? String == selectedCaps, "Ordinary reset does not select another command")
        let stale = view.commandMenu(for: "closeTab:")!
        try registry.set(KeyboardShortcut(key: "q", flags: [.command, .control]), for: "captureFullPage:")
        invoke(stale.items[0]); expect(registry.shortcut(for: "closeTab:") != nil, "Concurrent registry change invalidates menu receipt")
        let failing = view.commandMenu(for: "closeTab:")!
        let backup = directory.appendingPathExtension("backup")
        try FileManager.default.moveItem(at: directory, to: backup)
        try Data("blocked".utf8).write(to: directory)
        invoke(failing.items[0])
        expect(registry.shortcut(for: "closeTab:") != nil, "Failed durable menu removal retains binding")
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: backup, to: directory)
        let original = view.commandMenu(for: "closeTab:")!
        commandWindow.permitsCommands = false; invoke(original.items[0])
        expect(registry.shortcut(for: "closeTab:") != nil, "Lost original key window rejects menu action")
        commandWindow.permitsCommands = true; view.isHidden = true; invoke(original.items[0])
        expect(registry.shortcut(for: "closeTab:") != nil, "Hidden settings owner rejects action")
        view.isHidden = false; commandWindow.contentView = nil; window.contentView = view; invoke(original.items[0])
        expect(registry.shortcut(for: "closeTab:") != nil, "Reparented settings cannot use old window receipt")
        window.contentView = nil; commandWindow.contentView = view
        try registry.set(KeyboardShortcut(key: "k", flags: [.command, .control]), for: "closeTab:")
        try registry.set(KeyboardShortcut(key: "w", flags: .command), for: "captureFullPage:")
        view.selectCommand("captureFullPage:")
        let conflictMenu = view.commandMenu(for: "closeTab:")!
        let beforeConflict = registry.revision
        invoke(conflictMenu.items[1])
        expect(registry.revision == beforeConflict + 1 && keycaps.isInConflict, "Explicit reset durably restores default and shows both conflicts")
        expect(heading.stringValue == "Capture Full Page", "Resetting another row preserves actual detail selection")
        let conflictAction = view.commandMenu(for: "closeTab:")!.items.first { $0.title == "Remove Conflicting Shortcut" }!
        invoke(conflictAction)
        expect(registry.shortcut(for: "closeTab:")?.key == "w" && registry.shortcut(for: "captureFullPage:") == nil,
               "Context reset reuses the actual atomic conflict resolution")
        expect(!keycaps.isInConflict, "Resolved menu reset clears actual conflict state")
        view.selectCommand("closeTab:")
        func record(_ code: Int, _ modifiers: Int, enabled: Bool = true) -> [String: Any] {
            [kHISymbolicHotKeyCode as String: code, kHISymbolicHotKeyModifiers as String: modifiers,
             kHISymbolicHotKeyEnabled as String: enabled]
        }
        let osChord = KeyboardShortcut(key: " ", flags: [.control, .option, .command, .shift])
        let osRecords = [record(49, controlKey | optionKey | cmdKey | shiftKey),
                         record(49, cmdKey, enabled: false), record(-1, cmdKey), record(65536, cmdKey),
                         record(49, 0), [kHISymbolicHotKeyEnabled as String: true]]
        expect(KeyboardShortcut.systemShortcuts(records: osRecords) == [osChord], "Only complete enabled translated OS shortcuts warn")
        expect(KeyboardShortcut.systemShortcuts(records: [record(123, controlKey)]) == [KeyboardShortcut(key: "\u{f702}", flags: .control)],
               "OS arrow key uses the same physical translation as native recording")
        expect(KeyboardShortcut.systemShortcuts(records: [record(122, controlKey)]) == [KeyboardShortcut(key: "\u{f704}", flags: .control)],
               "OS function key retains its physical identity")
        let other = KeyboardShortcuts.Command(id: "other", title: "Other", group: "File", defaultShortcut: nil)
        expect(ShortcutsSettingsView.conflictDescription(osChord, conflicts: [other, other]).hasSuffix("and one other action"), "Two-owner original help uses singular count")
        expect(ShortcutsSettingsView.conflictDescription(osChord, conflicts: [other, other, other]).hasSuffix("and 2 other actions"), "Plural original conflict help")
        var osSnapshot: Set<KeyboardShortcut> = [registry.shortcut(for: "closeTab:")!]
        let warningsView = ShortcutsSettingsView(shortcuts: registry, systemShortcutProvider: { osSnapshot })
        let warningsWindow = ShortcutMenuWindow(contentRect: warningsView.frame, styleMask: .titled, backing: .buffered, defer: false)
        warningsWindow.contentView = warningsView
        let warningsTable = warningsView.subviews.compactMap { ($0 as? NSScrollView)?.documentView as? NSTableView }.first!
        let warningsSearch = warningsView.subviews.compactMap { $0 as? ShortcutSearchHeader }.first!.field
        func cell(_ id: String) -> NSView {
            (0..<warningsTable.numberOfRows).compactMap { warningsTable.view(atColumn: 0, row: $0, makeIfNecessary: true) }.first {
                $0.subviews.contains { ($0 as? ShortcutRecorderView)?.identifier?.rawValue == id }
            }!
        }
        let warningHelp = "System shortcuts may take priority over this shortcut"
        expect(cell("closeTab:").subviews.contains { ($0 as? NSImageView)?.toolTip == warningHelp }, "Actual matching record displays passive OS warning")
        expect(!cell("captureFullPage:").subviews.contains { $0 is NSImageView }, "Unassigned action has no fabricated warning")
        warningsView.selectCommand("captureFullPage:")
        let proposed = cell("captureFullPage:").subviews.compactMap { $0 as? ShortcutRecorderView }.first!
        proposed.onBegin?()
        expect(proposed.onChange?(registry.shortcut(for: "closeTab:")!) == true, "Conflict is saved through actual recorder callback")
        let warningCell = cell("captureFullPage:")
        let reveal = warningCell.subviews.compactMap { $0 as? NSButton }.first!
        expect(reveal.frame.size == NSSize(width: 16, height: 16) && reveal.contentTintColor == .systemRed, "Conflict has original red16-point button")
        expect(!warningCell.subviews.contains { $0 is NSImageView }, "Browser conflict takes precedence over OS warning")
        expect(reveal.toolTip?.contains("Archive Tab") == true, "Warning help names actual other action")
        warningsWindow.makeFirstResponder(warningsSearch)
        let warningResponder = warningsWindow.firstResponder, warningSelection = warningsTable.selectedRow
        let warningRevision = registry.revision
        _ = NSApp.sendAction(reveal.action!, to: reveal.target, from: reveal)
        expect(warningsTable.selectedRow == warningSelection && warningsWindow.firstResponder === warningResponder,
               "Conflict reveal scroll never selects another command or steals text focus")
        expect(registry.revision == warningRevision && registry.shortcut(for: "captureFullPage:")?.key == "w", "Reveal never changes the actual saved conflict")
        expect(warningsView.commandMenu(for: "captureFullPage:")?.items.first?.title == "Remove Conflicting Shortcut", "Actual conflict row context exposes removal")
        expect(warningsView.moreMenu()?.items.first?.title == "Remove Conflicting Shortcut", "Same original conflict action is discoverable in More")
        expect(!warningsView.subviews.contains { ($0 as? NSButton)?.title == "Remove Conflicting Shortcut" }, "No invented duplicate conflict detail button")
        let pendingAction = warningsView.moreMenu()!.items.first!
        warningsWindow.permitsCommands = false; invoke(pendingAction)
        expect(registry.revision == warningRevision, "Conflict resolution refuses lost original key owner")
        warningsWindow.permitsCommands = true; invoke(pendingAction)
        expect(registry.shortcut(for: "closeTab:") == nil && registry.shortcut(for: "captureFullPage:")?.key == "w", "Menu commits shown conflict through durable atomic owner")
        warningsView.endRecording()
        let all = warningsView.moreMenu()!.items.last!
        expect(all.title == "Reset All Shortcuts" && all.isEnabled, "Original Reset All entry has no invented confirmation ellipsis")
        try registry.setPriority(.preferParc, for: "captureFullPage:")
        let newer = registry.revision; invoke(all)
        expect(registry.revision == newer, "A stale Reset All menu cannot discard later edits")
        let currentAll = warningsView.moreMenu()!.items.last!
        warningsWindow.permitsCommands = false; invoke(currentAll)
        expect(registry.revision == newer, "Reset All refuses lost exact owner")
        warningsWindow.permitsCommands = true; invoke(currentAll)
        expect(!registry.hasOverrides && registry.shortcut(for: "closeTab:")?.key == "w" && registry.shortcut(for: "captureFullPage:") == nil,
               "Direct Reset All restores the actual registered defaults and priorities")
        expect(warningsWindow.attachedSheet == nil, "Recovered reset has no extra modal confirmation")
        expect(warningsView.moreMenu()?.items.last?.isEnabled == false, "Reset All becomes unavailable after defaults are restored")
        osSnapshot = []
        warningsView.viewDidMoveToWindow()
        expect(!cell("closeTab:").subviews.contains { $0 is NSImageView }, "System refresh removes obsolete warnings without changing bindings")
        expect(warningsWindow.firstResponder === warningResponder, "System refresh preserves native editing focus")
        for id in ["closeTab:", "captureFullPage:"] {
            warningsView.selectCommand(id)
            let recorder = cell(id).subviews.compactMap { $0 as? ShortcutRecorderView }.first!
            recorder.onBegin?(); _ = recorder.onChange?(KeyboardShortcut(key: " ", flags: .control)); warningsView.endRecording()
        }
        let spaceWarning = cell("captureFullPage:").subviews.compactMap { $0 as? NSButton }.first!
        expect(spaceWarning.toolTip?.hasPrefix("⌃⎵ is already in use by “") == true
               && spaceWarning.accessibilityLabel()?.hasPrefix("⌃Space is already in use by “") == true,
               "Conflict help shows ⎵ but its accessibility label says Space")
        try registry.resetAll()
        warningsWindow.contentView = nil
        view.selectCommand("closeTab:")
        let captured = ShortcutRemovalEffect.capture(keycaps, reduceMotion: false)!
        let actual = commandWindow.convertToScreen(keycaps.convert(keycaps.keycapBounds, to: nil))
        expect(keycaps.keycapBounds.size == NSSize(width: 132, height: 64), "Two-key effect measures actual HStack, not unused detail column space")
        expect(captured.screenFrame == actual, "Effect uses actual flipped-view to original-window screen coordinates")
        expect(ShortcutRemovalEffect.capture(keycaps, reduceMotion: true) == nil, "Reduced Motion suppresses effect without altering action")
        keycaps.frame.origin.x += 1; expect(!captured.isCurrent, "Moved keycaps invalidate the old effect frame")
        keycaps.frame.origin.x -= 1; commandWindow.permitsCommands = false
        expect(!captured.isCurrent && ShortcutRemovalEffect.capture(keycaps, reduceMotion: false) == nil, "Key-window loss cancels effect")
        commandWindow.permitsCommands = true; commandWindow.contentView = nil
        expect(!captured.isCurrent, "Detached keycaps cancel effect without retained view ownership")
        window.contentView = view
        commandWindow.close()
        let saved = try Data(contentsOf: directory.appendingPathComponent("keyboard-shortcuts.json"))
        view.endRecording(); window.contentView = nil; window.close()
        expect(saved == (try? Data(contentsOf: directory.appendingPathComponent("keyboard-shortcuts.json"))), "Presentation teardown never persists bindings")
        print("Shortcut detail production component: \(assertions) assertions passed")
    }
}
