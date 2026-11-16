import AppKit

@MainActor private final class AlternateTarget: NSObject, NSMenuItemValidation {
    var enabled = true
    var delivered: NSMenuItem?
    func validateMenuItem(_ item: NSMenuItem) -> Bool { enabled }
    @objc func goBack(_ sender: NSMenuItem) { delivered = sender }
    @objc func goForward(_ sender: NSMenuItem) { delivered = sender }
    @objc func goBackArrow(_ sender: NSMenuItem) { delivered = sender }
    @objc func goForwardArrow(_ sender: NSMenuItem) { delivered = sender }
    @objc func developerTools(_ sender: NSMenuItem) { delivered = sender }
    @objc func zoomIn(_ sender: NSMenuItem) { delivered = sender }
    @objc func zoomOut(_ sender: NSMenuItem) { delivered = sender }
    @objc func custom(_ sender: NSMenuItem) { delivered = sender }
}

@main @MainActor struct AlternateBindingTests {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = AlternateTarget()
        let file = root.appendingPathComponent("keyboard-shortcuts.json")
        let rows: [(String, String, KeyboardShortcut)] = [
            ("goBack_Alternate", "goBack:", .init(key: "\u{f702}", flags: .command)),
            ("goForward_Alternate", "goForward:", .init(key: "\u{f703}", flags: .command)),
            ("developerTools_Alternate", "developerTools:", .init(key: "\u{f70f}", flags: []))
        ]
        func register(_ registry: KeyboardShortcuts) -> [String: NSMenuItem] {
            let rootMenu = NSMenu(), parent = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
            let menu = NSMenu(title: "View"); parent.submenu = menu; rootMenu.addItem(parent); NSApp.mainMenu = rootMenu
            var items: [String: NSMenuItem] = [:]
            for (id, key, flags) in [
                ("goBack:", "[", NSEvent.ModifierFlags.command), ("goForward:", "]", .command),
                ("developerTools:", "i", [.command, .option]), ("zoomIn:", "+", .command),
                ("zoomOut:", "-", .command), ("custom:", "", [])] {
                let item = NSMenuItem(title: id, action: NSSelectorFromString(id), keyEquivalent: key)
                item.keyEquivalentModifierMask = flags; item.target = target; menu.addItem(item)
                registry.register(item, group: "View"); items[id] = item
            }
            for (id, _, chord) in rows {
                let action = id == "developerTools_Alternate" ? "developerTools:" : id.replacingOccurrences(of: "_Alternate", with: "Arrow:")
                let item = NSMenuItem(title: id, action: NSSelectorFromString(action), keyEquivalent: chord.key)
                item.target = target; item.keyEquivalentModifierMask = chord.flags
                item.isHidden = true; item.allowsKeyEquivalentWhenHidden = true; menu.addItem(item)
                registry.register(item, group: "View", bindingID: id, discoverable: false); items[id] = item
            }
            for (id, key, flags) in [("zoomIn:", "=", NSEvent.ModifierFlags.command), ("zoomOut:", "-", [.command, .shift])] {
                let item = NSMenuItem(title: id, action: NSSelectorFromString(id), keyEquivalent: key)
                item.target = target; item.keyEquivalentModifierMask = flags
                item.isHidden = true; item.allowsKeyEquivalentWhenHidden = true; menu.addItem(item)
                registry.registerEquivalent(item, for: id, shortcut: .init(key: key, flags: flags)); items[id + "equivalent"] = item
            }
            return items
        }
        func event(_ code: UInt16, _ key: String, _ flags: NSEvent.ModifierFlags = [], repeat repeating: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 1,
                             windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key,
                             isARepeat: repeating, keyCode: code)!
        }
        let registry = KeyboardShortcuts(); registry.configure(directory: root); let items = register(registry)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [], backing: .buffered, defer: false)
        expect(registry.commands.count == 9, "Three alternates have their own editable identities; Zoom equivalents do not")
        for (id, _, chord) in rows {
            expect(registry.shortcut(for: id) == chord, "Distinct shipped binding \(id)")
            expect(items[id]?.keyEquivalent == chord.key, "Real alternate menu chord")
            expect(registry.supportsPriority(id), "Actual priority route supports the binding")
        }
        expect(registry.priority(for: "goBack_Alternate") == .preferWebsites, "Arrow default is low, not bracket priority")
        expect(registry.priority(for: "developerTools_Alternate") == .useBoth, "F12 original priority")
        let search = registry.menuCommands(in: window)
        expect(search.count == 6 && !search.contains(where: { $0.id.contains("_Alternate") }), "No duplicate Actions candidates from supplemental menu records")
        let f12 = event(111, "\u{f70f}", .function)
        let command = registry.nativeCommand(for: f12, editable: true)!
        expect(command.item === items["developerTools_Alternate"] && command.priority == .useBoth, "F12 original menu owner reaches existing renderer-priority DTO even in web editing")
        expect(registry.settingsCommandID(for: command) == "developerTools_Alternate", "Press Again edit targets alternate binding")
        expect(registry.perform(command, event: f12, editable: true), "Exact component target dispatch")
        expect(target.delivered === command.item, "Original sender, not reconstructed selector")
        expect(registry.nativeCommand(for: event(111, "\u{f70f}", [], repeat: true), editable: false) == nil, "Autorepeat remains excluded")
        expect(registry.nativeCommand(for: event(0, "a"), editable: false) == nil, "Unmodified printable input remains untouched")
        expect(registry.nativeCommand(for: event(53, "\u{1b}"), editable: false) == nil, "Escape owner unchanged")
        let editableBack = registry.nativeCommand(for: event(123, "\u{f702}", .command), editable: true)
        expect(editableBack?.item === items["goBack_Alternate"] && editableBack?.priority == .preferWebsites,
               "the same website-first priority applies in editable page content; the page still gets the arrow first")
        expect(registry.nativeCommand(for: event(123, "a", .command), editable: false) == nil,
               "A chord typing reserved characters stays with the page even when its physical key is registered")
        let back = registry.nativeCommand(for: event(123, "\u{f702}", .command), editable: false)!
        expect(back.item === items["goBack_Alternate"], "Arrow owns its original menu item")
        target.enabled = false
        expect(registry.nativeCommand(for: f12, editable: false) == nil, "Unavailable original target is not dispatched")
        target.enabled = true
        try registry.set(nil, for: "developerTools_Alternate")
        expect(registry.nativeCommand(for: f12, editable: false) == nil, "Disabled alternate is actually disabled")
        expect(registry.shortcut(for: "developerTools:") == .init(key: "i", flags: [.command, .option]), "Clearing F12 does not alter distinct primary")
        expect(!registry.perform(command, event: f12, editable: false), "Old native token invalidated by binding mutation")
        try registry.reset("developerTools_Alternate")
        try registry.setPriority(.preferParc, for: "developerTools_Alternate")
        expect(registry.nativeCommand(for: f12, editable: false)?.priority == .preferParc, "Independent priority edit reaches native owner")
        try registry.set(nil, for: "goBack:")
        expect(registry.shortcut(for: "goBack_Alternate") != nil, "After migration alternates are independently edited")
        expect(items["zoomIn:equivalent"]?.keyEquivalent == "=", "Cmd-equals menu equivalent")
        expect(items["zoomOut:equivalent"]?.keyEquivalentModifierMask == [.command, .shift], "Shift-Cmd-minus menu equivalent")
        let zoom = registry.nativeCommand(for: event(24, "=", .command), editable: false)!
        expect(zoom.item === items["zoomIn:equivalent"], "Supplemental key uses actual validated menu item")
        expect(registry.settingsCommandID(for: zoom) == "zoomIn:", "Supplemental cue edits original Zoom binding")
        let plus = event(24, "+", [.command, .shift])
        expect(KeyboardShortcut.capture(plus) == .init(key: "=", flags: [.command, .shift]),
               "Physical US equals plus Shift remains recorder-normalized")
        let cocoaMenu = NSMenu(), cocoaPlus = NSMenuItem(title: "Zoom In", action: #selector(AlternateTarget.zoomIn), keyEquivalent: "+")
        cocoaPlus.target = target; cocoaPlus.keyEquivalentModifierMask = .command; cocoaMenu.addItem(cocoaPlus)
        target.delivered = nil
        expect(cocoaMenu.performKeyEquivalent(with: plus) && target.delivered === cocoaPlus,
               "Actual inert AppKit menu establishes symbolic-plus matching")
        let symbolic = registry.nativeCommand(for: plus, editable: false)!
        expect(symbolic.item === items["zoomIn:"], "Shift-produced plus keeps original primary Zoom menu owner")
        expect(registry.settingsCommandID(for: symbolic) == "zoomIn:", "Symbol cue edits primary binding")
        let physicalPlus = KeyboardShortcut(key: "=", flags: [.command, .shift])
        try registry.set(physicalPlus, for: "custom:")
        expect(registry.nativeCommand(for: plus, editable: false)?.item === items["custom:"], "Saved physical chord wins symbolic menu matching")
        target.delivered = nil
        _ = NSApp.mainMenu!.performKeyEquivalent(with: plus)
        expect(target.delivered !== items["zoomIn:"], "AppKit fallback cannot bypass the saved physical owner")
        expect(items["zoomIn:"]!.keyEquivalent.isEmpty, "Conflict suppresses the live symbolic equivalent only")
        expect(registry.shortcut(for: "zoomIn:") == .init(key: "+", flags: .command), "Primary default/Reset metadata stays intact")
        let beforeLayout = registry.revision
        registry.keyboardLayoutDidChange()
        expect(registry.revision > beforeLayout && items["zoomIn:"]!.keyEquivalent.isEmpty,
               "Actual layout refresh recalculates suppression and expires retained command tokens")
        target.enabled = false; target.delivered = nil
        expect(registry.nativeCommand(for: plus, editable: false) == nil, "Unavailable physical owner cannot fall through to symbolic Zoom")
        _ = NSApp.mainMenu!.performKeyEquivalent(with: plus)
        expect(target.delivered == nil, "Native menu fallback cannot execute Zoom for unavailable physical owner")
        target.enabled = true
        try registry.set(nil, for: "custom:")
        expect(registry.nativeCommand(for: plus, editable: true)?.item === items["zoomIn:"], "Symbolic original target retains native priority in web editing")
        target.delivered = nil
        expect(items["zoomIn:"]!.keyEquivalent == "+" && NSApp.mainMenu!.performKeyEquivalent(with: plus)
               && target.delivered === items["zoomIn:"], "Clearing the physical conflict restores genuine AppKit Zoom")
        try registry.set(nil, for: "zoomIn:")
        expect(registry.nativeCommand(for: plus, editable: false) == nil, "Clearing primary also clears symbolic plus route")
        expect(items["zoomIn:equivalent"]?.keyEquivalent.isEmpty == true, "Disabled Zoom cannot be bypassed through equals")
        expect(!registry.perform(zoom, event: event(24, "=", .command), editable: false), "Old supplemental token expires")
        try registry.reset("zoomIn:")
        try registry.set(.init(key: "k", flags: [.command, .control]), for: "zoomIn:")
        expect(registry.nativeCommand(for: plus, editable: false) == nil, "Custom Zoom suppresses the old symbolic default")
        expect(items["zoomIn:equivalent"]!.keyEquivalent.isEmpty, "Custom Zoom suppresses its fixed equals supplement")
        try registry.reset("zoomIn:")
        let equals = KeyboardShortcut(key: "=", flags: .command)
        try registry.set(equals, for: "custom:")
        expect(items["zoomIn:equivalent"]?.keyEquivalent.isEmpty == true, "Saved custom binding wins supplemental collision")
        expect(registry.nativeCommand(for: event(24, "=", .command), editable: false)?.item === items["custom:"], "Collision dispatches actual custom action")
        try registry.set(nil, for: "custom:")
        expect(items["zoomIn:equivalent"]?.keyEquivalent == "=", "Supplement restores when collision clears")
        try registry.set(.init(key: "k", flags: [.command, .control]), for: "zoomOut:")
        expect(items["zoomOut:equivalent"]?.keyEquivalent.isEmpty == true, "Custom Zoom does not retain old supplemental chord")
        let container = NSView(), text = NSTextView(), child = NSView()
        window.contentView = container; container.addSubview(text); text.addSubview(child)
        window.makeFirstResponder(text)
        expect(!KeyboardShortcuts.permitsArrowNavigation(in: window), "Native text editor keeps arrows")
        let field = NSTextField(); container.addSubview(field); window.makeFirstResponder(field)
        expect(!KeyboardShortcuts.permitsArrowNavigation(in: window), "Native field/field editor keeps arrows")
        window.makeFirstResponder(nil)
        expect(KeyboardShortcuts.permitsArrowNavigation(in: window), "Non-text responder permits original navigation availability check")
        expect(!KeyboardShortcuts.permitsArrowNavigation(in: nil), "No window cannot authorize navigation")

        func encoded(_ key: KeyboardShortcut?) -> [String: Any] {
            key.map { ["shortcut": ["key": $0.key, "modifiers": $0.modifiers]] } ?? [:]
        }
        for version in 1...3 {
            let legacy: [String: Any] = ["version": version, "developerDefaults": 1,
                "selectionCommandDefaults": 1, "menuPriorityDefaults": 1, "creationShortcutDefaults": 1,
                "overrides": ["goBack:": encoded(nil), "goForward:": encoded(.init(key: "k", flags: .command)),
                              "custom:": encoded(rows[2].2)], "priorities": ["custom:": "preferParc"]]
            try JSONSerialization.data(withJSONObject: legacy).write(to: file)
            let old = KeyboardShortcuts(); old.configure(directory: root); _ = register(old)
            for (id, _, _) in rows { expect(old.shortcut(for: id) == nil, "Legacy customization/disable/custom collision is not bypassed") }
            expect(old.shortcut(for: "goBack:") == nil && old.shortcut(for: "goForward:") == .init(key: "k", flags: .command), "Original chord choices unchanged")
            expect(old.priority(for: "custom:") == .preferParc, "Saved priority unchanged")
            let migrated = try Data(contentsOf: file); old.configure(directory: root)
            let reloaded = try Data(contentsOf: file)
            expect(migrated == reloaded, "Additive migration idempotent")
            try old.reset("goBack_Alternate")
            expect(old.shortcut(for: "goBack_Alternate") == rows[0].2, "Explicit alternate Reset adopts actual default")
            try old.reset("developerTools_Alternate")
            expect(old.isConflicting("developerTools_Alternate") && old.activeShortcut(for: "developerTools_Alternate") == nil, "Explicit Reset keeps both saved assignments while suppressing conflicting F12 dispatch")
            try old.resetAll()
            for (id, _, chord) in rows { expect(old.shortcut(for: id) == chord, "Reset All restores alternate defaults") }
        }
        try JSONSerialization.data(withJSONObject: ["version": 3, "overrides": ["custom:": encoded(equals)]]).write(to: file)
        let zoomConflict = KeyboardShortcuts(); zoomConflict.configure(directory: root)
        let collisionItems = register(zoomConflict)
        expect(collisionItems["zoomIn:equivalent"]?.keyEquivalent.isEmpty == true,
               "Startup saved custom chord suppresses the fixed equivalent")
        try zoomConflict.set(nil, for: "custom:")
        expect(collisionItems["zoomIn:equivalent"]?.keyEquivalent == "=",
               "Declared equivalent survives AppKit clearing its insertion-time key")
        try JSONSerialization.data(withJSONObject: ["version": 3, "overrides": [String: Any]()]).write(to: file)
        let unedited = KeyboardShortcuts(); unedited.configure(directory: root); _ = register(unedited)
        for (id, _, chord) in rows { expect(unedited.shortcut(for: id) == chord, "Untouched legacy command receives genuinely new alternate") }
        let detached = items["developerTools_Alternate"]!
        detached.menu?.removeItem(detached)
        expect(registry.nativeCommand(for: f12, editable: false) == nil, "Detached menu owner cannot dispatch")
        print("PASS: \(count) alternate binding/menu/context/migration assertions")
    }
}
