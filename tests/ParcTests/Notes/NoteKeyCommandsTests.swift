import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct NoteKeyCommandsTests {
    struct Chord: @unchecked Sendable, CustomTestStringConvertible {
        let name: String
        let characters: String
        let modifiers: NSEvent.ModifierFlags
        let keyCode: UInt16
        let expected: NoteKeyCommand?

        init(_ name: String, _ characters: String, _ modifiers: NSEvent.ModifierFlags, keyCode: UInt16 = 0, is expected: NoteKeyCommand?) {
            self.name = name
            self.characters = characters
            self.modifiers = modifiers
            self.keyCode = keyCode
            self.expected = expected
        }

        var testDescription: String { name }
        var command: NoteKeyCommand? { NoteKeyCommands.command(characters: characters, keyCode: keyCode, modifiers: modifiers) }
    }

    static let chords: [Chord] = [
        Chord("⌘B is bold", "b", .command, is: .mark(.bold)),
        Chord("⌘I is italic", "i", .command, is: .mark(.italic)),
        Chord("⌘U is underline", "u", .command, is: .mark(.underline)),
        Chord("⌘⇧S is strikethrough", "S", [.command, .shift], is: .mark(.strikethrough)),
        Chord("⌘S stays with the app", "s", .command, is: nil),
        Chord("⌘E is inline code", "e", .command, is: .mark(.code)),
        Chord("⌘⇧E is an inline equation", "E", [.command, .shift], is: .inlineEquation),
        Chord("⌘K is link", "k", .command, is: .link),
        Chord("⌘⇧H reapplies the last colour", "H", [.command, .shift], is: .lastColor),
        Chord("⌘D duplicates", "d", .command, is: .duplicate),
        Chord("⌘⌥T flips every toggle", "t", [.command, .option], is: .toggleAllToggles),
        Chord("⌘/ opens block actions", "/", .command, is: .blockActions),
        Chord("⇧⌘/ focuses the format bar", "?", [.command, .shift], is: .focusToolbar),
        Chord("⇧⌘/ reads the same on layouts that report the slash", "/", [.command, .shift], is: .focusToolbar),
        Chord("⌘Z undoes", "z", .command, is: .undo),
        Chord("⌘⇧Z redoes", "Z", [.command, .shift], is: .redo),
        Chord("⌘Y still redoes", "y", .command, is: .redo),
        Chord("⌘A selects", "a", .command, is: .selectAll),
        Chord("⌘⇧V pastes plain text", "v", [.command, .shift], is: .pastePlainText),
        Chord("⌘F finds", "f", .command, is: .find),
        Chord("⌘⌥F replaces", "f", [.command, .option], is: .findAndReplace),
        Chord("⌘G finds the next match", "g", .command, is: .findNext),
        Chord("⌘⇧G finds the previous match", "G", [.command, .shift], is: .findPrevious),
        Chord("⌘P prints", "p", .command, is: .print),
        Chord("irrelevant flags are ignored", "b", [.command, .capsLock, .function], is: .mark(.bold)),
        Chord("⌘↩ modifies the block", "", .command, keyCode: 36, is: .modifyBlock),
        Chord("⌘Enter on the keypad modifies the block too", "", .command, keyCode: 76, is: .modifyBlock),
        Chord("⌘⇧↑ moves up", "", [.command, .shift], keyCode: 126, is: .moveBlocks(.up)),
        Chord("⌘⇧↓ moves down", "", [.command, .shift], keyCode: 125, is: .moveBlocks(.down)),
        Chord("⌘↑ is left to the text view", "", .command, keyCode: 126, is: nil),
    ]

    @Test(arguments: NoteKeyCommandsTests.chords)
    func aChordMapsToItsCommand(chord: Chord) {
        #expect(chord.command == chord.expected)
    }

    struct TurnInto: @unchecked Sendable, CustomTestStringConvertible {
        let digit: Int
        let keyCode: UInt16
        let target: NoteTurnIntoTarget

        var testDescription: String { "⌘⌥\(digit)" }
    }

    static let turnIntoKeys: [TurnInto] = {
        let digits: [UInt16] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25]
        let targets: [NoteTurnIntoTarget] = [.text, .heading1, .heading2, .heading3, .todo, .bulleted, .numbered, .toggle, .code, .page]
        return zip(digits, targets).enumerated().map { TurnInto(digit: $0.offset, keyCode: $0.element.0, target: $0.element.1) }
    }()

    @Test(arguments: NoteKeyCommandsTests.turnIntoKeys)
    func optionCommandDigitTurnsIntoItsTargetByPhysicalKey(key: TurnInto) {
        #expect(NoteKeyCommands.command(characters: "º", keyCode: key.keyCode, modifiers: [.command, .option]) == .turnInto(key.target))
    }

    @Test(arguments: NoteKeyCommandsTests.turnIntoKeys)
    func plainCommandDigitStaysWithTheApp(key: TurnInto) {
        #expect(NoteKeyCommands.command(characters: "&", keyCode: key.keyCode, modifiers: [.command]) == nil)
    }

    @Test func headingTargetsCarryALevel() {
        #expect(NoteTurnIntoTarget.heading2.kind == .heading)
        #expect(NoteTurnIntoTarget.heading2.headingLevel == 2)
    }

    @Test func targetsMapToKinds() {
        #expect(NoteTurnIntoTarget.todo.kind == .todo)
        #expect(NoteTurnIntoTarget.code.kind == .code)
    }

    @Test(arguments: [
        (NoteKeyCommand.mark(.strikethrough), "⇧⌘S"),
        (.turnInto(.heading1), "⌥⌘1"),
        (.redo, "⇧⌘Z"),
        (.pastePlainText, "⇧⌘V"),
    ] as [(NoteKeyCommand, String)])
    func shortcutLabelsUseParcKeycapOrder(command: NoteKeyCommand, label: String) {
        #expect(NoteKeyCommands.shortcutLabel(for: command) == label)
    }

    @Test(arguments: [
        ("undo:", NoteKeyCommand.undo),
        ("pasteAsPlainText:", .pastePlainText),
        ("copy:", .copy),
    ] as [(String, NoteKeyCommand)])
    func menuActionsRouteToTheSession(selector: String, command: NoteKeyCommand) {
        #expect(NoteKeyCommands.command(forAction: NSSelectorFromString(selector)) == command)
    }

    @Test(arguments: [
        (TextFormatCommand.bold, NoteKeyCommand.mark(.bold)),
        (.heading3, .turnInto(.heading3)),
        (.body, .turnInto(.text)),
        (.increaseIndent, .indent),
    ] as [(TextFormatCommand, NoteKeyCommand)])
    func theFormatMenuRoutesToNotes(format: TextFormatCommand, command: NoteKeyCommand) {
        #expect(NoteKeyCommands.command(forAction: NoteKeyCommands.formatTextAction, tag: format.rawValue) == command)
    }

    @Test func biggerHasNoNotesMeaning() {
        #expect(NoteKeyCommands.command(forAction: NoteKeyCommands.formatTextAction, tag: TextFormatCommand.bigger.rawValue) == nil)
    }

    @Test func otherActionsPassThrough() {
        #expect(NoteKeyCommands.command(forAction: NSSelectorFromString("terminate:")) == nil)
    }

    @Test func readOnlyPagesCanCopyButNotPaste() {
        #expect(!NoteKeyCommand.copy.isEdit)
        #expect(NoteKeyCommand.paste.isEdit)
    }

    @Test func modifyBlockCanStillOpenAPageLinkInALockedNote() {
        #expect(!NoteKeyCommand.modifyBlock.isEdit)
    }

    @Test func everyChordIsBoundOnce() {
        var seen: [NoteKeyChord: NoteKeyCommand] = [:]
        var repeated: [NoteKeyChord] = []
        for (chord, value) in NoteKeyCommands.table {
            if seen[chord] != nil { repeated.append(chord) }
            seen[chord] = value
        }
        #expect(repeated.isEmpty)
    }
}
