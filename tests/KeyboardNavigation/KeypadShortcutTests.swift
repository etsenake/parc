import AppKit

@MainActor private final class KeypadTarget: NSObject, NSMenuItemValidation {
    var disabled: Set<String> = []
    var delivered: [String] = []
    func validateMenuItem(_ item: NSMenuItem) -> Bool { !disabled.contains(item.title) }
    @objc func deliver(_ sender: NSMenuItem) { delivered.append(sender.title) }
}

@main @MainActor struct KeypadShortcutTests {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("keyboard-shortcuts.json")
        func record(_ key: String, _ flags: NSEvent.ModifierFlags) -> [String: Any] {
            ["shortcut": ["key": key, "modifiers": flags.rawValue]]
        }
        let legacy: [String: [String: Any]] = [
            "rowCustom:": record("1", [.control, .option]),
            "clearSaved:": record("\u{1b}", .control),
            "starSaved:": record("*", [.command, .option])
        ]
        try JSONSerialization.data(withJSONObject: ["version": 3, "overrides": legacy]).write(to: file)

        let target = KeypadTarget()
        let registry = KeyboardShortcuts(); registry.configure(directory: root)
        let mainMenu = ShortcutMainMenu(); mainMenu.shortcuts = registry
        let parent = NSMenuItem(title: "Commands", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Commands"); parent.submenu = menu; mainMenu.addItem(parent); NSApp.mainMenu = mainMenu
        var items: [String: NSMenuItem] = [:]
        for id in ["space1", "rowCustom:", "clearSaved:", "starSaved:", "keypadCommand:", "clearCommand:", "starCommand:"] {
            let item = NSMenuItem(title: id, action: #selector(KeypadTarget.deliver), keyEquivalent: id == "space1" ? "1" : "")
            item.keyEquivalentModifierMask = id == "space1" ? NSEvent.ModifierFlags.control : []
            item.target = target; menu.addItem(item); items[id] = item
            registry.register(item, group: "Commands", bindingID: id)
        }
        func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 1, windowNumber: 0,
                             context: nil, characters: characters, charactersIgnoringModifiers: characters,
                             isARepeat: false, keyCode: code)!
        }
        let keypadOne = key(83, "1", [.control, .numericPad]), rowOne = key(18, "1", .control)
        let clear = key(71, "\u{f739}", [.control, .numericPad]), escape = key(53, "\u{1b}", .control)
        let keypadStar = key(67, "*", [.command, .option, .numericPad]), shiftEight = key(28, "*", [.command, .option, .shift])

        expect(registry.loadError == nil, "A file written before keypad identities loads")
        expect(registry.shortcut(for: "rowCustom:") == .init(key: "1", flags: [.control, .option])
               && registry.shortcut(for: "clearSaved:") == .init(key: "\u{1b}", flags: .control)
               && registry.shortcut(for: "starSaved:") == .init(key: "*", flags: [.command, .option]),
               "Old saved chords keep their exact values")
        expect(registry.nativeCommand(for: key(83, "1", [.control, .option, .numericPad]), editable: false)?.item === items["rowCustom:"]
               && registry.nativeCommand(for: key(18, "1", [.control, .option]), editable: false)?.item === items["rowCustom:"],
               "An old number binding still answers both the row and the keypad")
        expect(registry.nativeCommand(for: clear, editable: false)?.item === items["clearSaved:"]
               && registry.nativeCommand(for: escape, editable: false)?.item === items["clearSaved:"],
               "An old Escape binding recorded from Clear still answers Clear and Escape")
        expect(registry.nativeCommand(for: keypadStar, editable: false)?.item === items["starSaved:"],
               "An old asterisk binding still answers keypad *")
        expect(items["rowCustom:"]?.keyEquivalent == "1" && items["clearSaved:"]?.keyEquivalent == "\u{1b}"
               && items["starSaved:"]?.keyEquivalent == "*", "Old bindings stay on their menu items")
        expect(registry.nativeCommand(for: keypadOne, editable: false)?.item === items["space1"]
               && registry.performKeypadEquivalent(keypadOne) == nil,
               "Without a keypad binding, keypad 1 keeps reaching the number-row command")

        let keypadChord = KeyboardShortcut.capture(keypadOne)
        expect(KeyboardShortcut.keypadKey(forPhysicalCode: 83) == "1\u{20e3}" && keypadChord?.key == "1\u{20e3}",
               "Keypad 1 records as its own key")
        expect(keypadChord != KeyboardShortcut.capture(rowOne) && keypadChord?.display == "⌃Keypad 1",
               "Keypad 1 and the row 1 record differently and read differently")
        expect(KeyboardShortcut.capture(clear)?.key == KeyboardShortcut.clearKey
               && KeyboardShortcut.capture(clear) != KeyboardShortcut.capture(escape),
               "Clear records as Clear, not Escape")
        let starChord = KeyboardShortcut.capture(keypadStar)
        expect(starChord?.isKeypadKey == true && starChord != KeyboardShortcut.capture(shiftEight)
               && starChord != .init(key: "*", flags: [.command, .option]), "Keypad * records apart from Shift-8's asterisk")
        expect(KeyboardShortcut.capture(key(83, "1", .numericPad)) == nil, "A bare keypad digit still needs a modifier")
        expect([UInt16](arrayLiteral: 65, 67, 69, 71, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 95).allSatisfy { code in
            KeyboardShortcut.keypadKey(forPhysicalCode: code).map {
                let chord = KeyboardShortcut(key: $0, flags: .control)
                return chord.key.count == 1 && chord.isValid && !chord.isReserved
            } ?? false
        }, "Every keypad key passes the validity check older Parc versions apply when loading")

        guard let keypadChord, let starChord, let clearChord = KeyboardShortcut.capture(clear) else {
            preconditionFailure("Keypad, * and Clear chords must record")
        }
        let keypadClash = try registry.conflictProposal(for: keypadChord, commandID: "keypadCommand:")
        let rowClash = try registry.conflictProposal(for: .init(key: "1", flags: .control), commandID: "keypadCommand:")
        expect(keypadClash == nil && rowClash?.conflicts.map(\.id) == ["space1"],
               "Keypad 1 does not clash with Control-1, while the row 1 still does")
        try registry.set(keypadChord, for: "keypadCommand:")
        try registry.set(clearChord, for: "clearCommand:")
        try registry.set(starChord, for: "starCommand:")
        expect(!registry.isConflicting("keypadCommand:") && !registry.isConflicting("space1")
               && !registry.isConflicting("clearCommand:") && !registry.isConflicting("clearSaved:")
               && !registry.isConflicting("starCommand:") && !registry.isConflicting("starSaved:"),
               "Keypad, Clear and * bindings sit beside their row, Escape and asterisk twins")
        expect(items["keypadCommand:"]?.keyEquivalent == "" && items["starCommand:"]?.keyEquivalent == ""
               && items["space1"]?.keyEquivalent == "1", "Keypad bindings stay off menus, which match by character")
        expect(items["clearCommand:"]?.keyEquivalent == KeyboardShortcut.clearKey, "Clear keeps its own menu character")

        expect(registry.nativeCommand(for: keypadOne, editable: false)?.item === items["keypadCommand:"]
               && registry.nativeCommand(for: rowOne, editable: false)?.item === items["space1"],
               "Pages send keypad 1 and the row 1 to their own commands")
        expect(registry.nativeCommand(for: clear, editable: false)?.item === items["clearCommand:"]
               && registry.nativeCommand(for: escape, editable: false)?.item === items["clearSaved:"],
               "Clear and Escape go to their own commands")
        expect(registry.nativeCommand(for: keypadStar, editable: false)?.item === items["starCommand:"]
               && registry.nativeCommand(for: shiftEight, editable: false) == nil,
               "Keypad * reaches its command and Shift-8 never does")

        expect(mainMenu.performKeyEquivalent(with: keypadOne) && target.delivered == ["keypadCommand:"],
               "The menu bar runs a keypad binding exactly once, without the row command")
        expect(registry.performKeypadEquivalent(rowOne) == nil, "The row 1 is left to the menu's own Control-1 item")
        target.delivered = []
        target.disabled = ["keypadCommand:"]
        expect(registry.nativeCommand(for: keypadOne, editable: false) == nil && registry.performKeypadEquivalent(keypadOne) == false
               && target.delivered.isEmpty, "An unavailable keypad command never falls through to the row command")
        target.disabled = []

        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        let overrides = saved["overrides"] as! [String: [String: Any]]
        expect(legacy.allSatisfy { NSDictionary(dictionary: overrides[$0.key] ?? [:]).isEqual(to: $0.value) },
               "Saving a keypad binding leaves older records byte-for-byte the same")
        expect(NSDictionary(dictionary: overrides["keypadCommand:"] ?? [:]).isEqual(to: record("1\u{20e3}", .control)),
               "A keypad binding saves in the existing key and modifier fields")
        let reloaded = KeyboardShortcuts(); reloaded.configure(directory: root)
        for (id, item) in items { reloaded.register(item, group: "Commands", bindingID: id) }
        expect(reloaded.loadError == nil && reloaded.shortcut(for: "keypadCommand:") == keypadChord
               && reloaded.shortcut(for: "starCommand:") == starChord && reloaded.shortcut(for: "clearCommand:") == clearChord,
               "Keypad bindings survive a relaunch")
        expect(KeyboardShortcut.characterCapture(keypadOne) != keypadChord && KeyboardShortcut.characterCapture(rowOne) != keypadChord,
               "Older Parc versions, which match by character, never fire a keypad binding or see it clash")
        print("PASS: \(count) keypad shortcut assertions")
    }
}
