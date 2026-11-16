import AppKit
import Carbon.HIToolbox

@MainActor private final class NumberRowTarget: NSObject {
    @objc func deliver(_ sender: NSMenuItem) {}
}

@main @MainActor struct NumberRowTests {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static let row: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
    static func injected(base: [String], command: [String]? = nil, shift: [String],
                         extra: [UInt16: (String, String)] = [:]) -> KeyboardShortcut.LayoutTyping {
        { code, modifiers in
            if let index = row.firstIndex(of: code) {
                if modifiers & shiftKey != 0 { return shift[index] }
                if modifiers & cmdKey != 0 { return (command ?? base)[index] }
                return base[index]
            }
            return extra[code].map { modifiers & shiftKey != 0 ? $0.1 : $0.0 }
        }
    }
    static func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 1, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: code)!
    }
    static func source(_ id: String) -> TISInputSource {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first else { preconditionFailure("\(id) ships with macOS") }
        return source
    }

    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        let azerty = injected(base: ["&", "é", "\"", "'", "(", "§", "è", "!", "ç", "à"], shift: digits,
                              extra: [12: ("a", "A"), 13: ("z", "Z"), 10: ("<", "5"), 84: ("2", "2")])
        let lithuanian = injected(base: ["ą", "č", "ę", "ė", "į", "š", "ų", "ū", "„", "“"], command: digits,
                                  shift: ["Ą", "Č", "Ę", "Ė", "Į", "Š", "Ų", "Ū", "(", ")"])
        let czech = injected(base: ["+", "ě", "š", "č", "ř", "ž", "ý", "á", "í", "é"], shift: digits)
        let qwerty = injected(base: digits, shift: ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")"], extra: [12: ("q", "Q")])

        expect(row.map { KeyboardShortcut.typedKey(forPhysicalCode: $0, layout: azerty) } == digits,
               "On AZERTY each number-row key is the digit it types with Shift")
        expect(row.map { KeyboardShortcut.typedKey(forPhysicalCode: $0, layout: lithuanian) } == digits,
               "On Lithuanian each number-row key is the digit it types with Command")
        expect(row.map { KeyboardShortcut.typedKey(forPhysicalCode: $0, layout: qwerty) } == digits,
               "On a digit-first layout the number row is unchanged")
        expect(KeyboardShortcut.typedKey(forPhysicalCode: 12, layout: azerty) == "a"
               && KeyboardShortcut.typedKey(forPhysicalCode: 10, layout: azerty) == "<",
               "Keys off the number row keep their unshifted character, even one that types a digit with Shift")
        expect(KeyboardShortcut.typedKey(forPhysicalCode: 18, layout: injected(base: ["&"] + digits.dropFirst(), shift: ["!"] + digits.dropFirst()))
               == "&", "A number-row key with no digit on Command or Shift keeps its own character")

        let captureChord = KeyboardShortcut(key: "2", flags: [.command, .shift])
        expect(KeyboardShortcut.characterCapture(key(19, "2", [.command, .shift]), layout: azerty) == captureChord
               && KeyboardShortcut.capture(key(19, "2", [.command, .shift]), layout: azerty) == captureChord,
               "AZERTY Command-Shift-é/2 records and dispatches as Command-Shift-2")
        expect(KeyboardShortcut.capture(key(84, "2", [.command, .shift, .numericPad]), layout: azerty)
               == KeyboardShortcut(key: "2\u{20e3}", flags: [.command, .shift]),
               "Keypad 2 keeps its own keypad identity on AZERTY")
        expect(KeyboardShortcut.capture(key(13, "z", .command), layout: azerty) == KeyboardShortcut(key: "z", flags: .command),
               "Letters still record by what the key types")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = NumberRowTarget()
        let registry = KeyboardShortcuts(); registry.configure(directory: root)
        let menu = NSMenu(title: "Commands")
        for (id, equivalent, flags) in [("captureTest:", "2", NSEvent.ModifierFlags([.command, .shift])),
                                        ("firstTest:", "1", .command), ("zoomTest:", "+", .command),
                                        ("legacyTest:", "", []), ("otherTest:", "", [])] {
            let item = NSMenuItem(title: id, action: #selector(NumberRowTarget.deliver), keyEquivalent: equivalent)
            item.keyEquivalentModifierMask = flags; item.target = target; menu.addItem(item)
            registry.register(item, group: "Commands", bindingID: id)
        }
        expect(registry.chord(for: key(19, "2", [.command, .shift]), layout: azerty) == registry.shortcut(for: "captureTest:")
               && registry.chord(for: key(18, "&", .command), layout: azerty) == registry.shortcut(for: "firstTest:"),
               "AZERTY page shortcuts find Command-Shift-2 and Command-1")
        expect(registry.chord(for: key(18, "ą", .command), layout: lithuanian) == registry.shortcut(for: "firstTest:"),
               "Lithuanian page shortcuts find Command-1")
        expect(registry.chord(for: key(18, "+", .command), layout: czech) == registry.shortcut(for: "zoomTest:"),
               "A binding on the key's own character keeps it, so Czech Command-+ stays Zoom In")
        expect(registry.chord(for: key(19, "2", [.command, .shift]), layout: qwerty) == captureChord
               && registry.chord(for: key(12, "q", .command), layout: qwerty) == KeyboardShortcut(key: "q", flags: .command),
               "Digit-first layouts identify keys exactly as before")

        let legacy = KeyboardShortcut(key: "é", flags: [.command, .option])
        try registry.set(legacy, for: "legacyTest:")
        try registry.set(KeyboardShortcut(key: "2", flags: [.command, .option]), for: "otherTest:")
        expect(registry.chord(for: key(19, "é", [.command, .option]), layout: azerty) == legacy,
               "A chord recorded as é before keeps working, ahead of the key's digit")
        expect(registry.recordedChord(for: key(19, "é", [.command, .option]), layout: azerty) == legacy
               && registry.recordedChord(for: key(19, "2", [.command, .shift]), layout: azerty) == captureChord,
               "The recorder records what page shortcuts will match")
        expect(registry.recordedChord(for: key(84, "2", [.command, .numericPad]), layout: azerty)
               == KeyboardShortcut(key: "2\u{20e3}", flags: .command)
               && registry.chord(for: key(84, "2", [.command, .numericPad]), layout: azerty)
               == KeyboardShortcut(key: "2", flags: .command),
               "The recorder always records keypad 2 as keypad, while an unbound keypad press still falls back to its character")

        let zoomOutItem = NSMenuItem(title: "zoomOutTest:", action: #selector(NumberRowTarget.deliver), keyEquivalent: "-")
        zoomOutItem.keyEquivalentModifierMask = .command; zoomOutItem.target = target; menu.addItem(zoomOutItem)
        registry.register(zoomOutItem, group: "Commands", bindingID: "zoomOutTest:")
        let zoomOutAlternate = KeyboardShortcut(key: "-", flags: [.command, .shift]), zoomInAlternate = KeyboardShortcut(key: "=", flags: .command)
        for (id, alternate) in [("zoomOutTest:", zoomOutAlternate), ("zoomTest:", zoomInAlternate)] {
            let item = NSMenuItem(title: id + " alternate", action: #selector(NumberRowTarget.deliver), keyEquivalent: "")
            item.target = target; menu.addItem(item)
            registry.registerEquivalent(item, for: id, shortcut: alternate)
        }
        let lst = injected(base: ["!", "-", "/", ";", ":", ",", ".", "=", "(", ")"], shift: digits)
        expect(registry.chord(for: key(19, "-", [.command, .shift]), layout: lst) == captureChord,
               "A main binding on the digit beats an alternate on the key's own character, as alternates never steal one")
        expect(registry.chord(for: key(28, "=", .command), layout: lst) == zoomInAlternate,
               "An alternate on the key's own character keeps the key while the digit's shortcut is free")
        for (id, code, flags, expected) in [("French-PC", UInt16(22), NSEvent.ModifierFlags([.command, .shift]), zoomOutAlternate),
                                            ("French-PC", 19, [.command, .shift], captureChord),
                                            ("Lithuanian-LST1582", 19, [.command, .shift], captureChord),
                                            ("Lithuanian-LST1582", 28, .command, zoomInAlternate)] {
            let layoutSource = source("com.apple.keylayout." + id)
            let real: KeyboardShortcut.LayoutTyping = { KeyboardShortcut.layoutCharacter(forPhysicalCode: $0, modifiers: $1, in: layoutSource) }
            expect(registry.chord(for: key(code, "", flags), layout: real) == expected,
                   "\(id): key \(code) with \(flags.rawValue) finds \(expected.display)")
        }

        let hotKey: [String: Any] = [kHISymbolicHotKeyEnabled as String: true, kHISymbolicHotKeyCode as String: 18,
                                     kHISymbolicHotKeyModifiers as String: controlKey]
        expect(KeyboardShortcut.systemShortcuts(records: [hotKey], layout: azerty)
               == [KeyboardShortcut(key: "1", flags: .control), KeyboardShortcut(key: "&", flags: .control)]
               && KeyboardShortcut.systemShortcuts(records: [hotKey], layout: qwerty) == [KeyboardShortcut(key: "1", flags: .control)],
               "A macOS shortcut on the AZERTY 1 key clashes with Control-1 and with a Control-& recorded before")

        for id in ["French", "French-PC", "Belgian", "Czech", "Slovak", "Lithuanian", "US", "British", "German", "SwissFrench",
                   "Dvorak", "DVORAK-QWERTYCMD"] {
            let layoutSource = source("com.apple.keylayout." + id)
            let real: KeyboardShortcut.LayoutTyping = { KeyboardShortcut.layoutCharacter(forPhysicalCode: $0, modifiers: $1, in: layoutSource) }
            expect(row.map { KeyboardShortcut.typedKey(forPhysicalCode: $0, layout: real) } == digits,
                   "\(id): the number row reads 1 to 0")
        }
        let commandQwertySource = source("com.apple.keylayout.DVORAK-QWERTYCMD")
        let commandQwerty: KeyboardShortcut.LayoutTyping = {
            KeyboardShortcut.layoutCharacter(forPhysicalCode: $0, modifiers: $1, in: commandQwertySource)
        }
        let offRow: [UInt16] = [1, 2, 3, 4, 5, 12, 13, 14]
        expect(offRow.contains { commandQwerty($0, cmdKey) != commandQwerty($0, 0) }
               && offRow.allSatisfy { KeyboardShortcut.keyForPhysicalCode($0, layout: commandQwerty) == commandQwerty($0, 0) },
               "Keys off the number row keep their Dvorak character even where the Command map switches to QWERTY")
        print("PASS: \(count) number-row layout assertions")
    }
}
