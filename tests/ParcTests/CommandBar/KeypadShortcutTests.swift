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
