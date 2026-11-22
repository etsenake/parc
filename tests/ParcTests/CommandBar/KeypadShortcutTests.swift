import AppKit
import Testing
@testable import Parc

struct KeypadShortcutTests {
    @MainActor private final class Target: NSObject, NSMenuItemValidation {
        var disabled = false
        var dispatched: [String] = []
        func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { menuItem.title != "Keypad" || !disabled }
        @objc func run(_ item: NSMenuItem) { dispatched.append(item.title) }
    }

    @MainActor private final class Fixture {
        let target = Target()
        let menu = ShortcutMainMenu()
        let registry: KeyboardShortcuts
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        init() throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let root = menu
            registry = KeyboardShortcuts(mainMenu: { root }, observesKeyboardLayout: false)
            menu.shortcuts = registry
            register("Row", id: "space1", key: "1")
            register("Keypad", id: "keypad:", key: "")
            registry.configure(directory: directory)
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        private func register(_ title: String, id: String, key: String) {
            let item = NSMenuItem(title: title, action: #selector(Target.run(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = .control
            item.target = target
            menu.addItem(item)
            registry.register(item, group: "Commands", bindingID: id)
        }

        func bindKeypad() throws {
            try registry.set(KeyboardShortcut(key: "1\u{20e3}", flags: .control), for: "keypad:")
        }

        func event(keypad: Bool) -> NSEvent {
            CommandBarTestSupport.keyEvent(keypad ? 83 : 18, keypad ? [.control, .numericPad] : .control, characters: "1")
        }
    }

    @Test(arguments: [UInt16](arrayLiteral: 65, 67, 69, 71, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 95))
    func eachKeypadCodeCanBeSavedAsOneDistinctKey(code: UInt16) throws {
        let key = try #require(KeyboardShortcut.keypadKey(forPhysicalCode: code))
        let chord = KeyboardShortcut(key: key, flags: .control)
        #expect(chord.key.count == 1 && chord.isValid && !chord.isReserved)
    }

    @Test(arguments: [(UInt16(83), "1", "1\u{20e3}"), (UInt16(71), "\u{f739}", "\u{f739}"), (UInt16(67), "*", "*\u{20e3}")])
    @MainActor func recordingKeepsPhysicalKeypadIdentity(code: UInt16, typed: String, expected: String) {
        let event = CommandBarTestSupport.keyEvent(code, [.control, .numericPad], characters: typed)
        #expect(KeyboardShortcut.capture(event)?.key == expected)
    }

    @Test @MainActor func anUnboundKeypadDigitUsesTheExistingRowBinding() throws {
        let fixture = try Fixture()
        let event = fixture.event(keypad: true)
        #expect(fixture.registry.nativeCommand(for: event, editable: false)?.item?.title == "Row")
        #expect(fixture.registry.performKeypadEquivalent(event) == nil)
    }

    @Test(arguments: [false, true])
    @MainActor func bindingTheKeypadSeparatesItFromTheRow(keypad: Bool) throws {
        let fixture = try Fixture()
        try fixture.bindKeypad()
        #expect(!fixture.registry.isConflicting("space1"))
        #expect(fixture.registry.nativeCommand(for: fixture.event(keypad: keypad), editable: false)?.item?.title == (keypad ? "Keypad" : "Row"))
    }

    @Test(arguments: [false, true])
    @MainActor func aKeypadBindingNeverFallsThroughToTheRow(disabled: Bool) throws {
        let fixture = try Fixture()
        try fixture.bindKeypad()
        fixture.target.disabled = disabled
        #expect(fixture.registry.performKeypadEquivalent(fixture.event(keypad: true)) == !disabled)
        #expect(fixture.target.dispatched == (disabled ? [] : ["Keypad"]))
    }

    @Test @MainActor func keypadBindingsSurviveReload() throws {
        let fixture = try Fixture()
        try fixture.bindKeypad()
        fixture.registry.configure(directory: fixture.directory)
        #expect(fixture.registry.shortcut(for: "keypad:") == KeyboardShortcut(key: "1\u{20e3}", flags: .control))
        #expect(fixture.menu.items.first { $0.title == "Keypad" }?.keyEquivalent.isEmpty == true)
    }
}

extension KeypadShortcutTests {
    @MainActor private final class LegacyTarget: NSObject, NSMenuItemValidation {
        var disabled: Set<String> = []
        var delivered: [String] = []
        func validateMenuItem(_ item: NSMenuItem) -> Bool { !disabled.contains(item.title) }
        @objc func deliver(_ sender: NSMenuItem) { delivered.append(sender.title) }
    }

    @MainActor private final class Bench {
        static let legacy: [String: [String: Any]] = [
            "rowCustom:": record("1", [.control, .option]),
            "clearSaved:": record("\u{1b}", .control),
            "starSaved:": record("*", [.command, .option]),
        ]
        static let ids = ["space1", "rowCustom:", "clearSaved:", "starSaved:", "keypadCommand:", "clearCommand:", "starCommand:"]

        let directory: URL
        let file: URL
        let target = LegacyTarget()
        let mainMenu = ShortcutMainMenu()
        let registry: KeyboardShortcuts
        var items: [String: NSMenuItem] = [:]

        static func record(_ key: String, _ flags: NSEvent.ModifierFlags) -> [String: Any] {
            ["shortcut": ["key": key, "modifiers": flags.rawValue]]
        }

        init() throws {
            _ = NSApplication.shared
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            file = directory.appendingPathComponent("keyboard-shortcuts.json")
            try JSONSerialization.data(withJSONObject: ["version": 3, "overrides": Self.legacy]).write(to: file)
            let root = mainMenu
            registry = KeyboardShortcuts(mainMenu: { root }, observesKeyboardLayout: false)
            mainMenu.shortcuts = registry
            registry.configure(directory: directory)
            let menu = NSMenu(title: "Commands")
            let parent = NSMenuItem(title: "Commands", action: nil, keyEquivalent: "")
            parent.submenu = menu
            mainMenu.addItem(parent)
            for id in Self.ids {
                let item = NSMenuItem(title: id, action: #selector(LegacyTarget.deliver), keyEquivalent: id == "space1" ? "1" : "")
                item.keyEquivalentModifierMask = id == "space1" ? NSEvent.ModifierFlags.control : []
                item.target = target
                menu.addItem(item)
                items[id] = item
                registry.register(item, group: "Commands", bindingID: id)
            }
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
            CommandBarTestSupport.keyEvent(code, flags, characters: characters)
        }

        var keypadOne: NSEvent { key(83, "1", [.control, .numericPad]) }
        var rowOne: NSEvent { key(18, "1", .control) }
        var clear: NSEvent { key(71, "\u{f739}", [.control, .numericPad]) }
        var escape: NSEvent { key(53, "\u{1b}", .control) }
        var keypadStar: NSEvent { key(67, "*", [.command, .option, .numericPad]) }
        var shiftEight: NSEvent { key(28, "*", [.command, .option, .shift]) }

        func bindAll() throws {
            try registry.set(try #require(KeyboardShortcut.capture(keypadOne)), for: "keypadCommand:")
            try registry.set(try #require(KeyboardShortcut.capture(clear)), for: "clearCommand:")
            try registry.set(try #require(KeyboardShortcut.capture(keypadStar)), for: "starCommand:")
        }
    }

    @Test @MainActor func aFileWrittenBeforeKeypadIdentitiesKeepsItsExactChords() throws {
        let bench = try Bench()
        let registry = bench.registry
        #expect(registry.loadError == nil)
        #expect(registry.shortcut(for: "rowCustom:") == .init(key: "1", flags: [.control, .option]))
        #expect(registry.shortcut(for: "clearSaved:") == .init(key: "\u{1b}", flags: .control))
        #expect(registry.shortcut(for: "starSaved:") == .init(key: "*", flags: [.command, .option]))
        #expect(bench.items["rowCustom:"]?.keyEquivalent == "1")
        #expect(bench.items["clearSaved:"]?.keyEquivalent == "\u{1b}")
        #expect(bench.items["starSaved:"]?.keyEquivalent == "*")
    }

    @Test @MainActor func oldNumberEscapeAndAsteriskBindingsStillAnswerTheirKeypadTwins() throws {
        let bench = try Bench()
        let registry = bench.registry
        #expect(registry.nativeCommand(for: bench.key(83, "1", [.control, .option, .numericPad]), editable: false)?.item === bench.items["rowCustom:"])
        #expect(registry.nativeCommand(for: bench.key(18, "1", [.control, .option]), editable: false)?.item === bench.items["rowCustom:"])
        #expect(registry.nativeCommand(for: bench.clear, editable: false)?.item === bench.items["clearSaved:"])
        #expect(registry.nativeCommand(for: bench.escape, editable: false)?.item === bench.items["clearSaved:"])
        #expect(registry.nativeCommand(for: bench.keypadStar, editable: false)?.item === bench.items["starSaved:"])
    }

    @Test @MainActor func withoutAKeypadBindingKeypadOneReachesTheNumberRowCommand() throws {
        let bench = try Bench()
        #expect(bench.registry.nativeCommand(for: bench.keypadOne, editable: false)?.item === bench.items["space1"])
        #expect(bench.registry.performKeypadEquivalent(bench.keypadOne) == nil)
    }

    @Test @MainActor func keypadAndRowKeysRecordAndReadDifferently() throws {
        let bench = try Bench()
        let keypad = KeyboardShortcut.capture(bench.keypadOne)
        #expect(KeyboardShortcut.keypadKey(forPhysicalCode: 83) == "1\u{20e3}")
        #expect(keypad?.key == "1\u{20e3}")
        #expect(keypad != KeyboardShortcut.capture(bench.rowOne))
        #expect(keypad?.display == "⌃Keypad 1")
    }

    @Test @MainActor func clearRecordsAsClearNotEscape() throws {
        let bench = try Bench()
        #expect(KeyboardShortcut.capture(bench.clear)?.key == KeyboardShortcut.clearKey)
        #expect(KeyboardShortcut.capture(bench.clear) != KeyboardShortcut.capture(bench.escape))
    }

    @Test @MainActor func keypadAsteriskRecordsApartFromShiftEight() throws {
        let bench = try Bench()
        let star = KeyboardShortcut.capture(bench.keypadStar)
        #expect(star?.isKeypadKey == true)
        #expect(star != KeyboardShortcut.capture(bench.shiftEight))
        #expect(star != .init(key: "*", flags: [.command, .option]))
    }

    @Test @MainActor func aBareKeypadDigitStillNeedsAModifier() throws {
        let bench = try Bench()
        #expect(KeyboardShortcut.capture(bench.key(83, "1", .numericPad)) == nil)
    }

    @Test @MainActor func keypadOneOnlyClashesWithItselfNotTheRow() throws {
        let bench = try Bench()
        let keypad = try #require(KeyboardShortcut.capture(bench.keypadOne))
        let keypadClash = try bench.registry.conflictProposal(for: keypad, commandID: "keypadCommand:")
        let rowClash = try bench.registry.conflictProposal(for: .init(key: "1", flags: .control), commandID: "keypadCommand:")
        #expect(keypadClash == nil)
        #expect(rowClash?.conflicts.map(\.id) == ["space1"])
    }

    @Test @MainActor func keypadClearAndStarBindingsSitBesideTheirTwinsWithoutConflict() throws {
        let bench = try Bench()
        try bench.bindAll()
        for id in ["keypadCommand:", "space1", "clearCommand:", "clearSaved:", "starCommand:", "starSaved:"] {
            #expect(!bench.registry.isConflicting(id))
        }
        #expect(bench.items["keypadCommand:"]?.keyEquivalent == "")
        #expect(bench.items["starCommand:"]?.keyEquivalent == "")
        #expect(bench.items["space1"]?.keyEquivalent == "1")
        #expect(bench.items["clearCommand:"]?.keyEquivalent == KeyboardShortcut.clearKey)
    }

    @Test @MainActor func eachPhysicalKeyReachesItsOwnCommandOnPages() throws {
        let bench = try Bench()
        try bench.bindAll()
        let registry = bench.registry
        #expect(registry.nativeCommand(for: bench.keypadOne, editable: false)?.item === bench.items["keypadCommand:"])
        #expect(registry.nativeCommand(for: bench.rowOne, editable: false)?.item === bench.items["space1"])
        #expect(registry.nativeCommand(for: bench.clear, editable: false)?.item === bench.items["clearCommand:"])
        #expect(registry.nativeCommand(for: bench.escape, editable: false)?.item === bench.items["clearSaved:"])
        #expect(registry.nativeCommand(for: bench.keypadStar, editable: false)?.item === bench.items["starCommand:"])
        #expect(registry.nativeCommand(for: bench.shiftEight, editable: false) == nil)
    }

    @Test @MainActor func theMenuBarRunsAKeypadBindingOnceAndLeavesTheRowToItsMenuItem() throws {
        let bench = try Bench()
        try bench.bindAll()
        #expect(bench.mainMenu.performKeyEquivalent(with: bench.keypadOne))
        #expect(bench.target.delivered == ["keypadCommand:"])
        #expect(bench.registry.performKeypadEquivalent(bench.rowOne) == nil)
    }

    @Test @MainActor func anUnavailableKeypadCommandNeverFallsThroughToTheRowCommand() throws {
        let bench = try Bench()
        try bench.bindAll()
        bench.target.disabled = ["keypadCommand:"]
        #expect(bench.registry.nativeCommand(for: bench.keypadOne, editable: false) == nil)
        #expect(bench.registry.performKeypadEquivalent(bench.keypadOne) == false)
        #expect(bench.target.delivered.isEmpty)
    }

    @Test @MainActor func savingKeypadBindingsLeavesOlderRecordsUntouchedAndSurvivesRelaunch() throws {
        let bench = try Bench()
        try bench.bindAll()
        let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: bench.file)) as? [String: Any])
        let overrides = try #require(saved["overrides"] as? [String: [String: Any]])
        for (id, record) in Bench.legacy { #expect(NSDictionary(dictionary: overrides[id] ?? [:]).isEqual(to: record)) }
        #expect(NSDictionary(dictionary: overrides["keypadCommand:"] ?? [:]).isEqual(to: Bench.record("1\u{20e3}", .control)))
        let reloaded = KeyboardShortcuts(observesKeyboardLayout: false)
        reloaded.configure(directory: bench.directory)
        for (id, item) in bench.items { reloaded.register(item, group: "Commands", bindingID: id) }
        #expect(reloaded.loadError == nil)
        #expect(reloaded.shortcut(for: "keypadCommand:") == KeyboardShortcut.capture(bench.keypadOne))
        #expect(reloaded.shortcut(for: "starCommand:") == KeyboardShortcut.capture(bench.keypadStar))
        #expect(reloaded.shortcut(for: "clearCommand:") == KeyboardShortcut.capture(bench.clear))
    }

    @Test @MainActor func characterMatchingNeverSeesAKeypadBinding() throws {
        let bench = try Bench()
        let keypad = KeyboardShortcut.capture(bench.keypadOne)
        #expect(KeyboardShortcut.characterCapture(bench.keypadOne) != keypad)
        #expect(KeyboardShortcut.characterCapture(bench.rowOne) != keypad)
    }
}
