import AppKit

@MainActor
private final class NoteOwner: TextFormatShortcutOwner {
    func formatKeyEquivalent(for command: TextFormatCommand) -> TextFormatKeyEquivalent? {
        NoteFormatShortcuts.keyEquivalent(for: command)
    }
}

@main @MainActor
struct NoteFormatMenuTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func key(_ key: String, _ modifiers: NSEvent.ModifierFlags) -> TextFormatKeyEquivalent {
        TextFormatKeyEquivalent(key: key, modifiers: modifiers)
    }

    static let parcDefaults: [TextFormatCommand: TextFormatKeyEquivalent] = [
        .bold: key("b", .command), .italic: key("i", .command), .underline: key("u", .command),
        .heading1: key("h", [.command, .shift]), .body: key("b", [.command, .shift]),
        .bulletedList: key("7", [.command, .shift]), .numberedList: key("9", [.command, .shift]),
        .link: key("k", .command),
    ]

    static func chord(_ characters: String, _ modifiers: NSEvent.ModifierFlags, keyCode: UInt16 = 0) -> NoteKeyChord {
        NoteKeyChord(characters: characters, keyCode: keyCode, modifiers: modifiers)!
    }

    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        expect(key("H", .command) == key("h", [.command, .shift]), "An uppercase letter reads as Shift plus the letter")
        expect(key("k", [.command, .function]).modifiers == .command, "Only the four shortcut modifiers count")

        let expected: [TextFormatCommand: TextFormatKeyEquivalent?] = [
            .bold: key("b", .command), .italic: key("i", .command), .underline: key("u", .command),
            .strikethrough: key("s", [.command, .shift]), .heading1: key("1", [.command, .option]),
            .heading2: key("2", [.command, .option]), .heading3: key("3", [.command, .option]),
            .body: key("0", [.command, .option]), .bulletedList: key("5", [.command, .option]),
            .numberedList: key("6", [.command, .option]), .link: key("k", .command),
            .bigger: nil, .smaller: nil, .increaseIndent: nil, .decreaseIndent: nil,
        ]
        for command in TextFormatCommand.allCases {
            expect(NoteFormatShortcuts.keyEquivalent(for: command) == expected[command] ?? nil,
                   "\(command.title) shows the note's own Notion shortcut")
        }

        for (chord, _) in NoteKeyCommands.table {
            expect(NoteKeyChord(chord.keyEquivalent) == chord, "\(chord) survives a trip through a menu key equivalent")
        }

        let heading = chord("H", [.command, .shift], keyCode: 4)
        expect(NoteFormatShortcuts.displacedFormat(for: heading) { parcDefaults[$0] } == .heading1,
               "⌘⇧H belongs to the note's last colour, so Heading 1 never fires inside a note")
        expect(NoteFormatShortcuts.displacedFormat(for: chord("b", .command, keyCode: 11)) { parcDefaults[$0] } == nil,
               "⌘B means bold in both places, so nothing is displaced")
        expect(NoteFormatShortcuts.displacedFormat(for: chord("k", .command, keyCode: 40)) { parcDefaults[$0] } == nil,
               "⌘K means link in both places")
        expect(NoteFormatShortcuts.displacedFormat(for: chord("&", [.command, .shift], keyCode: 26)) { parcDefaults[$0] } == nil,
               "Parc's ⌘⇧7 isn't a note chord, so it still reaches Bulleted List")
        var rebound = parcDefaults
        rebound[.heading1] = key("1", [.command, .control])
        expect(NoteFormatShortcuts.displacedFormat(for: heading) { rebound[$0] } == nil,
               "A Heading 1 moved off ⌘⇧H in Settings no longer clashes")
        rebound[.body] = key("d", .command)
        expect(NoteFormatShortcuts.displacedFormat(for: chord("d", .command, keyCode: 2)) { rebound[$0] } == .body,
               "A custom Format chord that a note already uses gives way to the note")
        expect(NoteFormatShortcuts.displacedFormat(for: chord("1", [.command, .control], keyCode: 18)) { rebound[$0] } == nil,
               "A custom chord the note doesn't use keeps working through the Format menu")

        let edit = NSMenu(title: "Edit")
        var items: [TextFormatCommand: NSMenuItem] = [:]
        let root = TextFormatMenu.add(to: edit) { item, command in
            items[command] = item
            if let chord = parcDefaults[command] {
                item.keyEquivalent = chord.key
                item.keyEquivalentModifierMask = chord.modifiers
            }
        }
        let format = root.submenu!
        let font = format.item(withTitle: "Font")!.submenu!
        format.delegate?.menuWillOpen?(format)
        expect(TextFormatKeyEquivalent(of: items[.heading1]!) == parcDefaults[.heading1],
               "With no note in charge, the Format menu keeps Parc's shortcuts")

        var swap = TextFormatShortcutSwap()
        swap.show(NoteOwner(), in: format)
        swap.show(NoteOwner(), in: font)
        expect(TextFormatKeyEquivalent(of: items[.heading1]!) == key("1", [.command, .option]), "A note's Format menu shows ⌥⌘1 for Heading 1")
        expect(TextFormatKeyEquivalent(of: items[.bulletedList]!) == key("5", [.command, .option]), "A note's Format menu shows ⌥⌘5 for bullets")
        expect(TextFormatKeyEquivalent(of: items[.strikethrough]!) == key("s", [.command, .shift]), "Strikethrough shows the note's ⌘⇧S")
        expect(TextFormatKeyEquivalent(of: items[.bigger]!) == nil, "Commands a note can't do show no shortcut")
        swap.show(NoteOwner(), in: format)
        swap.restore(in: format)
        swap.restore(in: font)
        for command in TextFormatCommand.allCases {
            expect(TextFormatKeyEquivalent(of: items[command]!) == parcDefaults[command],
                   "\(command.title) gets Parc's shortcut back when the menu closes, even after opening twice")
        }

        swap.show(NoteOwner(), in: format)
        items[.heading1]!.keyEquivalent = "j"
        items[.heading1]!.keyEquivalentModifierMask = [.command, .control]
        swap.restore(in: format)
        expect(TextFormatKeyEquivalent(of: items[.heading1]!) == key("j", [.command, .control]),
               "A shortcut changed in Settings while the menu was open is kept, not overwritten")
        expect(TextFormatKeyEquivalent(of: items[.body]!) == parcDefaults[.body], "Untouched items still go back")
        print("NoteFormatMenuTests passed")
    }
}
