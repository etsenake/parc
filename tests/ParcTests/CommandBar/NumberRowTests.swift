import AppKit
import Carbon.HIToolbox
import Testing
@testable import Parc

struct NumberRowTests {
    private static let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    private static let codes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
    private static let layouts = ["French", "French-PC", "Belgian", "Czech", "Slovak", "Lithuanian", "US",
                                  "British", "German", "SwissFrench", "Dvorak", "DVORAK-QWERTYCMD"]

    @Test(arguments: layouts)
    @MainActor func aSystemLayoutResolvesThePhysicalNumberRow(layout: String) throws {
        let filter = [kTISPropertyInputSourceID as String: "com.apple.keylayout." + layout] as CFDictionary
        let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
        let source = try #require(sources?.first)
        let actual = Self.codes.map { code in
            KeyboardShortcut.typedKey(forPhysicalCode: code) { code, modifiers in
                KeyboardShortcut.layoutCharacter(forPhysicalCode: code, modifiers: modifiers, in: source)
            }
        }
        #expect(actual == Self.digits)
    }

    @Test(arguments: [(UInt16(18), "&", "1"), (UInt16(10), "<", "<")])
    func shiftSuppliesADigitOnlyOnTheNumberRow(code: UInt16, base: String, expected: String) {
        let key = KeyboardShortcut.typedKey(forPhysicalCode: code) { _, flags in
            flags & shiftKey == 0 ? base : "1"
        }
        #expect(key == expected)
    }

    @Test @MainActor func aMacShortcutWarnsForTheCurrentDigitAndItsLegacyCharacter() {
        let hotKey: [String: Any] = [kHISymbolicHotKeyEnabled as String: true, kHISymbolicHotKeyCode as String: 18,
                                     kHISymbolicHotKeyModifiers as String: controlKey]
        let actual = KeyboardShortcut.systemShortcuts(records: [hotKey]) { _, modifiers in
            modifiers & shiftKey == 0 ? "&" : "1"
        }
        #expect(actual == [KeyboardShortcut(key: "1", flags: .control), KeyboardShortcut(key: "&", flags: .control)])
    }
}
