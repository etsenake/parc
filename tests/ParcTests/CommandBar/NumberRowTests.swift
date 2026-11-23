import AppKit
import Carbon.HIToolbox
import Testing
@testable import Parc
@testable import ParcKit

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

extension NumberRowTests {
    @MainActor private final class Target: NSObject {
        @objc func deliver(_ sender: NSMenuItem) {}
    }

    private static func injected(base: [String], command: [String]? = nil, shift: [String],
                                 extra: [UInt16: (String, String)] = [:]) -> KeyboardShortcut.LayoutTyping {
        { code, modifiers in
            if let index = codes.firstIndex(of: code) {
                if modifiers & shiftKey != 0 { return shift[index] }
                if modifiers & cmdKey != 0 { return (command ?? base)[index] }
                return base[index]
            }
            return extra[code].map { modifiers & shiftKey != 0 ? $0.1 : $0.0 }
        }
    }

    private static var azerty: KeyboardShortcut.LayoutTyping {
        injected(base: ["&", "é", "\"", "'", "(", "§", "è", "!", "ç", "à"], shift: digits,
                 extra: [12: ("a", "A"), 13: ("z", "Z"), 10: ("<", "5"), 84: ("2", "2")])
    }
    private static var lithuanian: KeyboardShortcut.LayoutTyping {
        injected(base: ["ą", "č", "ę", "ė", "į", "š", "ų", "ū", "„", "“"], command: digits,
                 shift: ["Ą", "Č", "Ę", "Ė", "Į", "Š", "Ų", "Ū", "(", ")"])
    }
    private static var czech: KeyboardShortcut.LayoutTyping {
        injected(base: ["+", "ě", "š", "č", "ř", "ž", "ý", "á", "í", "é"], shift: digits)
    }
    private static var qwerty: KeyboardShortcut.LayoutTyping {
        injected(base: digits, shift: ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")"], extra: [12: ("q", "Q")])
    }

    @MainActor private static func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        CommandBarTestSupport.keyEvent(code, flags, characters: characters)
    }

    private static func layoutSource(_ id: String) throws -> TISInputSource {
        let filter = [kTISPropertyInputSourceID as String: "com.apple.keylayout." + id] as CFDictionary
        let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
        return try #require(list?.first)
    }

    private static let captureChord = KeyboardShortcut(key: "2", flags: [.command, .shift])

    @Test @MainActor func numberRowKeysAreTheirDigitOnLayoutsThatTypeThemWithShiftOrCommand() {
        #expect(Self.codes.map { KeyboardShortcut.typedKey(forPhysicalCode: $0, layout: Self.azerty) } == Self.digits)
        #expect(Self.codes.map { KeyboardShortcut.typedKey(forPhysicalCode: $0, layout: Self.lithuanian) } == Self.digits)
        #expect(Self.codes.map { KeyboardShortcut.typedKey(forPhysicalCode: $0, layout: Self.qwerty) } == Self.digits)
    }

    @Test @MainActor func keysOffTheNumberRowKeepTheirUnshiftedCharacter() {
        #expect(KeyboardShortcut.typedKey(forPhysicalCode: 12, layout: Self.azerty) == "a")
        #expect(KeyboardShortcut.typedKey(forPhysicalCode: 10, layout: Self.azerty) == "<")
        let layout = Self.injected(base: ["&"] + Self.digits.dropFirst(), shift: ["!"] + Self.digits.dropFirst())
        #expect(KeyboardShortcut.typedKey(forPhysicalCode: 18, layout: layout) == "&")
    }

    @Test @MainActor func recordingOnAzertyUsesTheDigitAndKeepsKeypadAndLetters() {
        let event = Self.key(19, "2", [.command, .shift])
        #expect(KeyboardShortcut.characterCapture(event, layout: Self.azerty) == Self.captureChord)
        #expect(KeyboardShortcut.capture(event, layout: Self.azerty) == Self.captureChord)
        #expect(KeyboardShortcut.capture(Self.key(84, "2", [.command, .shift, .numericPad]), layout: Self.azerty)
                == KeyboardShortcut(key: "2\u{20e3}", flags: [.command, .shift]))
        #expect(KeyboardShortcut.capture(Self.key(13, "z", .command), layout: Self.azerty) == KeyboardShortcut(key: "z", flags: .command))
    }

    @MainActor private final class Bench {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = Target()
        let menu = NSMenu(title: "Commands")
        let registry: KeyboardShortcuts

        init() throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let root = menu
            registry = KeyboardShortcuts(mainMenu: { root }, observesKeyboardLayout: false)
            registry.configure(directory: directory)
            for (id, equivalent, flags) in [("captureTest:", "2", NSEvent.ModifierFlags([.command, .shift])),
                                            ("firstTest:", "1", .command), ("zoomTest:", "+", .command),
                                            ("legacyTest:", "", []), ("otherTest:", "", [])] {
                add(id, equivalent, flags)
            }
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func add(_ id: String, _ equivalent: String, _ flags: NSEvent.ModifierFlags) {
            let item = NSMenuItem(title: id, action: #selector(Target.deliver), keyEquivalent: equivalent)
            item.keyEquivalentModifierMask = flags
            item.target = target
            menu.addItem(item)
            registry.register(item, group: "Commands", bindingID: id)
        }
    }

    @Test @MainActor func pageShortcutsFindNumberRowBindingsOnEachLayout() throws {
        let bench = try Bench()
        let registry = bench.registry
        #expect(registry.chord(for: Self.key(19, "2", [.command, .shift]), layout: Self.azerty) == registry.shortcut(for: "captureTest:"))
        #expect(registry.chord(for: Self.key(18, "&", .command), layout: Self.azerty) == registry.shortcut(for: "firstTest:"))
        #expect(registry.chord(for: Self.key(18, "ą", .command), layout: Self.lithuanian) == registry.shortcut(for: "firstTest:"))
        #expect(registry.chord(for: Self.key(18, "+", .command), layout: Self.czech) == registry.shortcut(for: "zoomTest:"))
        #expect(registry.chord(for: Self.key(19, "2", [.command, .shift]), layout: Self.qwerty) == Self.captureChord)
        #expect(registry.chord(for: Self.key(12, "q", .command), layout: Self.qwerty) == KeyboardShortcut(key: "q", flags: .command))
    }

    @Test @MainActor func aChordRecordedBeforeKeepsWorkingAndTheRecorderMatchesPages() throws {
        let bench = try Bench()
        let registry = bench.registry
        let legacy = KeyboardShortcut(key: "é", flags: [.command, .option])
        try registry.set(legacy, for: "legacyTest:")
        try registry.set(KeyboardShortcut(key: "2", flags: [.command, .option]), for: "otherTest:")
        #expect(registry.chord(for: Self.key(19, "é", [.command, .option]), layout: Self.azerty) == legacy)
        #expect(registry.recordedChord(for: Self.key(19, "é", [.command, .option]), layout: Self.azerty) == legacy)
        #expect(registry.recordedChord(for: Self.key(19, "2", [.command, .shift]), layout: Self.azerty) == Self.captureChord)
        let keypad = Self.key(84, "2", [.command, .numericPad])
        #expect(registry.recordedChord(for: keypad, layout: Self.azerty) == KeyboardShortcut(key: "2\u{20e3}", flags: .command))
        #expect(registry.chord(for: keypad, layout: Self.azerty) == KeyboardShortcut(key: "2", flags: .command))
    }

    @Test @MainActor func alternatesNeverStealAMainBindingButKeepAFreeKey() throws {
        let bench = try Bench()
        let registry = bench.registry
        bench.add("zoomOutTest:", "-", .command)
        let zoomOutAlternate = KeyboardShortcut(key: "-", flags: [.command, .shift])
        let zoomInAlternate = KeyboardShortcut(key: "=", flags: .command)
        for (id, alternate) in [("zoomOutTest:", zoomOutAlternate), ("zoomTest:", zoomInAlternate)] {
            let item = NSMenuItem(title: id + " alternate", action: #selector(Target.deliver), keyEquivalent: "")
            item.target = bench.target
            bench.menu.addItem(item)
            registry.registerEquivalent(item, for: id, shortcut: alternate)
        }
        let layout = Self.injected(base: ["!", "-", "/", ";", ":", ",", ".", "=", "(", ")"], shift: Self.digits)
        #expect(registry.chord(for: Self.key(19, "-", [.command, .shift]), layout: layout) == Self.captureChord)
        #expect(registry.chord(for: Self.key(28, "=", .command), layout: layout) == zoomInAlternate)
    }

    @Test(arguments: [("French-PC", UInt16(22), true, "zoomOut"), ("French-PC", UInt16(19), true, "capture"),
                      ("Lithuanian-LST1582", UInt16(19), true, "capture"), ("Lithuanian-LST1582", UInt16(28), false, "zoomIn")])
    @MainActor func systemLayoutsFindAlternatesAndDigitsOnTheirKeys(layout: String, code: UInt16, shift: Bool, expected: String) throws {
        let bench = try Bench()
        let registry = bench.registry
        bench.add("zoomOutTest:", "-", .command)
        let zoomOutAlternate = KeyboardShortcut(key: "-", flags: [.command, .shift])
        let zoomInAlternate = KeyboardShortcut(key: "=", flags: .command)
        for (id, alternate) in [("zoomOutTest:", zoomOutAlternate), ("zoomTest:", zoomInAlternate)] {
            let item = NSMenuItem(title: id + " alternate", action: #selector(Target.deliver), keyEquivalent: "")
            item.target = bench.target
            bench.menu.addItem(item)
            registry.registerEquivalent(item, for: id, shortcut: alternate)
        }
        let source = try Self.layoutSource(layout)
        let real: KeyboardShortcut.LayoutTyping = { KeyboardShortcut.layoutCharacter(forPhysicalCode: $0, modifiers: $1, in: source) }
        let flags: NSEvent.ModifierFlags = shift ? [.command, .shift] : .command
        let chord: [String: KeyboardShortcut] = ["zoomOut": zoomOutAlternate, "capture": Self.captureChord, "zoomIn": zoomInAlternate]
        #expect(registry.chord(for: Self.key(code, "", flags), layout: real) == chord[expected])
    }

    @Test @MainActor func aDvorakCommandMapDoesNotChangeKeysOffTheNumberRow() throws {
        let source = try Self.layoutSource("DVORAK-QWERTYCMD")
        let layout: KeyboardShortcut.LayoutTyping = { KeyboardShortcut.layoutCharacter(forPhysicalCode: $0, modifiers: $1, in: source) }
        let offRow: [UInt16] = [1, 2, 3, 4, 5, 12, 13, 14]
        #expect(offRow.contains { layout($0, cmdKey) != layout($0, 0) })
        #expect(offRow.allSatisfy { KeyboardShortcut.keyForPhysicalCode($0, layout: layout) == layout($0, 0) })
    }

    @Test @MainActor func aMacShortcutOnTheCurrentDigitWarnsOnlyWhereTheLayoutDiffers() {
        let hotKey: [String: Any] = [kHISymbolicHotKeyEnabled as String: true, kHISymbolicHotKeyCode as String: 18,
                                     kHISymbolicHotKeyModifiers as String: controlKey]
        #expect(KeyboardShortcut.systemShortcuts(records: [hotKey], layout: Self.qwerty) == [KeyboardShortcut(key: "1", flags: .control)])
    }

    @Test(arguments: [("US", "}", Set(["]"])), ("German", "(", Set(["8"])), ("French", "%", Set(["ù"]))])
    @MainActor func aShiftedSymbolMapsToTheKeyThatTypesItOnASystemLayout(layout: String, symbol: String, keys: Set<String>) throws {
        let source = try Self.layoutSource(layout)
        let typing: KeyboardShortcut.LayoutTyping = { KeyboardShortcut.layoutCharacter(forPhysicalCode: $0, modifiers: $1, in: source) }
        #expect(KeyboardShortcut.physicalKeys(producingShifted: symbol, layout: typing) == keys)
    }

    @Test func aShiftedSymbolNoLayoutTypesHasNoPhysicalKey() {
        #expect(KeyboardShortcut.physicalKeys(producingShifted: "}") { _, _ in nil }.isEmpty)
    }
}
