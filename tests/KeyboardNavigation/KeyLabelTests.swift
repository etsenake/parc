import AppKit

@main struct KeyLabelTests {
    static func main() {
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
        print("Shortcut key label checks passed: \(checks)")
    }
}
