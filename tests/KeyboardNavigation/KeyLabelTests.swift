import AppKit
import Carbon.HIToolbox

@main @MainActor struct KeyLabelTests {
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) { checks += 1; precondition(value(), message) }
        func chord(_ key: String, _ flags: NSEvent.ModifierFlags = .control) -> KeyboardShortcut {
            KeyboardShortcut(key: key, flags: flags)
        }
        let text: [(String, String)] = [
            (" ", "⌃⎵"), ("\t", "⌃⇥"), ("\r", "⌃↩"), ("\n", "⌃↩"), ("\u{3}", "⌃⌤"), (KeyboardShortcut.clearKey, "⌃⌧"),
            ("1\u{20e3}", "⌃Keypad 1"), ("*\u{20e3}", "⌃Keypad *"),
            ("\u{7f}", "⌃⌫"), ("\u{8}", "⌃⌫"), ("\u{f728}", "⌃⌦"), ("\u{1b}", "⌃⎋"),
            ("\u{f700}", "⌃↑"), ("\u{f701}", "⌃↓"), ("\u{f702}", "⌃←"), ("\u{f703}", "⌃→"),
            ("\u{f72c}", "⌃⇞"), ("\u{f72d}", "⌃⇟"), ("\u{f729}", "⌃↖"), ("\u{f72b}", "⌃↘"),
            ("\u{f704}", "⌃F1"), ("\u{f70f}", "⌃F12"), ("\u{f717}", "⌃F20"),
            ("\u{5}", "⌃?⃝"), ("+", "⌃+"), ("/", "⌃/"), ("=", "⌃="), ("-", "⌃-"), (".", "⌃."), ("7", "⌃7"),
            ("k", "⌃K"), ("[", "⌃[")]
        for (key, expected) in text {
            expect(chord(key).display == expected, "\(key.debugDescription) reads \(expected) in menu text, not \(chord(key).display)")
        }
        expect(chord(" ", [.control, .option, .shift, .command]).display == "⌃⌥⇧⌘⎵", "Modifiers keep modifierDisplayInfo's ⌃ ⌥ ⇧ ⌘ order")
        expect(!chord(" ").display.contains("Space"), "Space is never written as a word")

        expect(chord(" ").symbols == ["⌃", "⎵"] && chord(" ").keycapSymbols == ["⌃", "⎵"], "Space keycaps are ⎵ on every surface")
        expect(chord("\t").symbols == ["⌃", "⇥"], "Settings detail keeps ⇥ for Tab")
        expect(chord("\t").keycapSymbols == ["⌃", "TAB"], "Essentials keycaps spell Tab out")
        expect(chord("\u{f708}", []).keycapSymbols == ["F5"] && chord("\u{3}", .command).keycapSymbols == ["⌘", "⌤"]
               && chord("1\u{20e3}").symbols == ["⌃", "Keypad 1"] && chord("1\u{20e3}").keycapSymbols == ["⌃", "Keypad 1"],
               "F-keys, Enter and keypad keys read the same in both keycap forms")
        expect(chord("s", .command).symbols == ["⌘", "S"] && chord("S", .command).keycapSymbols == ["⇧", "⌘", "S"],
               "Letters uppercase, with an uppercase binding's implied Shift")
        expect(KeyboardShortcut(key: "", flags: [.command, .shift]).symbols.filter { !$0.isEmpty } == ["⇧", "⌘"],
               "A held-modifier preview still shows modifiers alone")

        expect(chord(" ").searchText.contains("space") && chord(" ").searchText.contains("⎵"),
               "Settings search still finds a Space binding by name")
        expect(chord(" ", [.control, .shift]).spokenDisplay == "⌃⇧Space", "Accessibility says Space, not the ⎵ symbol name")
        expect(chord("\u{3}").spokenDisplay == "⌃Enter" && chord(KeyboardShortcut.clearKey).spokenDisplay == "⌃Clear"
               && chord("1\u{20e3}").searchText.contains("keypad 1"), "Enter, Clear and keypad keys are spoken and searchable by name")
        expect(chord("\t").spokenDisplay == chord("\t").display && chord("k", .command).spokenDisplay == "⌘K",
               "Every other chord speaks its displayed text")

        let decimal = KeyboardShortcut.keypadDecimalCode
        let commaLayout: (UInt16) -> String? = { $0 == decimal ? "," : "x" }
        expect(KeyboardShortcut.keypadName(".", typing: commaLayout) == "Keypad ,",
               "On a comma-decimal layout the keypad decimal key reads Keypad ,")
        expect(KeyboardShortcut.keypadName("1", typing: commaLayout) == "Keypad 1"
               && KeyboardShortcut.keypadName(",", typing: commaLayout) == "Keypad ,",
               "Only the decimal key follows the layout; digits and the keypad comma keep their own names")
        expect([nil, "", " ", "\u{3}", "\u{301}", ".."].allSatisfy { typed in
            KeyboardShortcut.keypadName(".", typing: { _ in typed }) == "Keypad ."
        }, "A missing, blank, control, lone combining or multi-character translation falls back to Keypad .")
        func layout(_ id: String) -> TISInputSource {
            let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
            guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
                  let source = list.first else { preconditionFailure("\(id) ships with macOS") }
            return source
        }
        let german = layout("com.apple.keylayout.German"), english = layout("com.apple.keylayout.US")
        expect(KeyboardShortcut.keypadName(".", typing: { KeyboardShortcut.layoutCharacter(forPhysicalCode: $0, in: german) }) == "Keypad ,"
               && KeyboardShortcut.keypadName(".", typing: { KeyboardShortcut.layoutCharacter(forPhysicalCode: $0, in: english) }) == "Keypad .",
               "The shortcut layout translation names the decimal key Keypad , on German and Keypad . on U.S.")
        let commaDecimal = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .numericPad], timestamp: 1,
                                            windowNumber: 0, context: nil, characters: ",", charactersIgnoringModifiers: ",",
                                            isARepeat: false, keyCode: decimal)
        let captured = commaDecimal.flatMap { KeyboardShortcut.capture($0) }
        let saved = captured.flatMap { try? JSONEncoder().encode($0) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        expect(captured == KeyboardShortcut(key: ".\u{20e3}", flags: .control) && saved?["key"] as? String == ".\u{20e3}"
               && captured.map { $0.hashValue == chord(".\u{20e3}").hashValue } == true,
               "A decimal key typing a comma still records, saves and hashes as the same keypad . identity")
        let liveName = KeyboardShortcut.keypadName(".", typing: KeyboardShortcut.layoutCharacter(forPhysicalCode:))
        expect(chord(".\u{20e3}").display == "⌃" + liveName && chord(".\u{20e3}").symbols.last == liveName
               && chord(".\u{20e3}").keycapSymbols.last == liveName && chord(".\u{20e3}").spokenDisplay == "⌃" + liveName,
               "Menu text, Settings caps, Essentials and tooltip keycaps and accessibility share the layout's decimal label")
        print("Shortcut key label checks passed: \(checks)")
    }
}
