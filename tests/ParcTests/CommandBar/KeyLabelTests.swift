import AppKit
import Carbon.HIToolbox
import Testing
@testable import ParcKit

struct KeyLabelTests {

    @MainActor private func chord(_ key: String, _ flags: NSEvent.ModifierFlags = .control) -> KeyboardShortcut {
        KeyboardShortcut(key: key, flags: flags)
    }

    @Test(arguments: [
            (" ", "⌃⎵"), ("\t", "⌃⇥"), ("\r", "⌃↩"), ("\n", "⌃↩"), ("\u{3}", "⌃⌤"), (KeyboardShortcut.clearKey, "⌃⌧"),
            ("1\u{20e3}", "⌃Keypad 1"), ("*\u{20e3}", "⌃Keypad *"),
            ("\u{7f}", "⌃⌫"), ("\u{8}", "⌃⌫"), ("\u{f728}", "⌃⌦"), ("\u{1b}", "⌃⎋"),
            ("\u{f700}", "⌃↑"), ("\u{f701}", "⌃↓"), ("\u{f702}", "⌃←"), ("\u{f703}", "⌃→"),
            ("\u{f72c}", "⌃⇞"), ("\u{f72d}", "⌃⇟"), ("\u{f729}", "⌃↖"), ("\u{f72b}", "⌃↘"),
            ("\u{f704}", "⌃F1"), ("\u{f70f}", "⌃F12"), ("\u{f717}", "⌃F20"),
            ("\u{5}", "⌃?⃝"), ("+", "⌃+"), ("/", "⌃/"), ("=", "⌃="), ("-", "⌃-"), (".", "⌃."), ("7", "⌃7"),
            ("k", "⌃K"), ("[", "⌃[")]) @MainActor func specialKeysUseTheirMenuGlyphs(key: String, expected: String) {
        #expect(chord(key).display == expected)
    }

    @Test @MainActor func modifiersKeepTheirDisplayOrder() {
        #expect(chord(" ", [.control, .option, .shift, .command]).display == "⌃⌥⇧⌘⎵", "Modifiers keep modifierDisplayInfo's ⌃ ⌥ ⇧ ⌘ order")
        #expect(!chord(" ").display.contains("Space"), "Space is never written as a word")
    }

    @Test @MainActor func spaceUsesTheSameGlyphOnBothSurfaces() {
        #expect(chord(" ").symbols == ["⌃", "⎵"] && chord(" ").keycapSymbols == ["⌃", "⎵"], "Space keycaps are ⎵ on every surface")
    }

    @Test @MainActor func tabCanBeShownAsAGlyphOrKeycap() {
        #expect(chord("\t").symbols == ["⌃", "⇥"], "Settings detail keeps ⇥ for Tab")
        #expect(chord("\t").keycapSymbols == ["⌃", "TAB"], "Essentials keycaps spell Tab out")
    }

    @Test @MainActor func functionAndKeypadSymbolsDoNotNeedTextSubstitutions() {
        #expect(chord("\u{f708}", []).keycapSymbols == ["F5"] && chord("\u{3}", .command).keycapSymbols == ["⌘", "⌤"]
               && chord("1\u{20e3}").symbols == ["⌃", "Keypad 1"] && chord("1\u{20e3}").keycapSymbols == ["⌃", "Keypad 1"],
               "F-keys, Enter and keypad keys read the same in both keycap forms")
    }

    @Test @MainActor func uppercaseLettersPreserveImpliedShift() {
        #expect(chord("s", .command).symbols == ["⌘", "S"] && chord("S", .command).keycapSymbols == ["⇧", "⌘", "S"],
               "Letters uppercase, with an uppercase binding's implied Shift")
    }

    @Test @MainActor func aModifierPreviewNeedsNoKey() {
        #expect(KeyboardShortcut(key: "", flags: [.command, .shift]).symbols.filter { !$0.isEmpty } == ["⇧", "⌘"],
               "A held-modifier preview still shows modifiers alone")
    }

    @Test @MainActor func spaceCanBeFoundByNameOrGlyph() {
        #expect(chord(" ").searchText.contains("space") && chord(" ").searchText.contains("⎵"),
               "Settings search still finds a Space binding by name")
    }

    @Test @MainActor func accessibilitySpeaksSpaceByName() {
        #expect(chord(" ", [.control, .shift]).spokenDisplay == "⌃⇧Space", "Accessibility says Space, not the ⎵ symbol name")
    }

    @Test @MainActor func nativeKeyNamesAreReadableAndSearchable() {
        #expect(chord("\u{3}").spokenDisplay == "⌃Enter" && chord(KeyboardShortcut.clearKey).spokenDisplay == "⌃Clear"
               && chord("1\u{20e3}").searchText.contains("keypad 1"), "Enter, Clear and keypad keys are spoken and searchable by name")
    }

    @Test @MainActor func ordinaryChordsSpeakTheirDisplayText() {
        #expect(chord("\t").spokenDisplay == chord("\t").display && chord("k", .command).spokenDisplay == "⌘K",
               "Every other chord speaks its displayed text")
    }

    @Test @MainActor func onlyTheDecimalKeyFollowsTheLayout() {
        let decimal = KeyboardShortcut.keypadDecimalCode
        let commaLayout: (UInt16) -> String? = { $0 == decimal ? "," : "x" }
        #expect(KeyboardShortcut.keypadName(".", typing: commaLayout) == "Keypad ,",
               "On a comma-decimal layout the keypad decimal key reads Keypad ,")
        #expect(KeyboardShortcut.keypadName("1", typing: commaLayout) == "Keypad 1"
               && KeyboardShortcut.keypadName(",", typing: commaLayout) == "Keypad ,",
               "Only the decimal key follows the layout; digits and the keypad comma keep their own names")
    }

    @Test(arguments: [nil, "", " ", "\u{3}", "\u{301}", ".."] as [String?]) @MainActor func invalidDecimalTranslationsUseADot(translation: String?) {
        #expect(KeyboardShortcut.keypadName(".", typing: { _ in translation }) == "Keypad .")
    }

    @Test(arguments: [("com.apple.keylayout.German", "Keypad ,"), ("com.apple.keylayout.US", "Keypad .")]) @MainActor func macOSLayoutsSupplyTheDecimalLabel(id: String, label: String) throws {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
        let source = try #require(list?.first)
        #expect(KeyboardShortcut.keypadName(".", typing: { KeyboardShortcut.layoutCharacter(forPhysicalCode: $0, in: source) }) == label)
    }

    @Test @MainActor func aDecimalKeyTypingCommaKeepsItsStoredPhysicalIdentity() {
        let decimal = KeyboardShortcut.keypadDecimalCode
        let commaDecimal = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .numericPad], timestamp: 1,
                                            windowNumber: 0, context: nil, characters: ",", charactersIgnoringModifiers: ",",
                                            isARepeat: false, keyCode: decimal)
        let captured = commaDecimal.flatMap { KeyboardShortcut.capture($0) }
        let saved = captured.flatMap { try? JSONEncoder().encode($0) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        #expect(captured == KeyboardShortcut(key: ".\u{20e3}", flags: .control) && saved?["key"] as? String == ".\u{20e3}"
               && captured.map { $0.hashValue == chord(".\u{20e3}").hashValue } == true,
               "A decimal key typing a comma still records, saves and hashes as the same keypad . identity")
    }

    @Test @MainActor func allSurfacesUseTheLiveDecimalLabel() {
        let liveName = KeyboardShortcut.keypadName(".", typing: KeyboardShortcut.layoutCharacter(forPhysicalCode:))
        #expect(chord(".\u{20e3}").display == "⌃" + liveName && chord(".\u{20e3}").symbols.last == liveName
               && chord(".\u{20e3}").keycapSymbols.last == liveName && chord(".\u{20e3}").spokenDisplay == "⌃" + liveName,
               "Menu text, Settings caps, Essentials and tooltip keycaps and accessibility share the layout's decimal label")
    }
}
