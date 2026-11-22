import AppKit
import Testing
@testable import ParcCore
@testable import ParcKit
@testable import ParcNotes

@MainActor
struct NoteFormatMenuTests {
    final class NoteOwner: TextFormatShortcutOwner {
        func formatKeyEquivalent(for command: TextFormatCommand) -> TextFormatKeyEquivalent? {
            NoteFormatShortcuts.keyEquivalent(for: command)
        }
    }

    struct Command: @unchecked Sendable, CustomTestStringConvertible {
        let command: TextFormatCommand
        var testDescription: String { command.title }
    }

    struct Chord: @unchecked Sendable, CustomTestStringConvertible {
        let chord: NoteKeyChord
        var testDescription: String { "\(chord)" }
    }

    nonisolated static let commands = TextFormatCommand.allCases.map(Command.init)
    nonisolated static let chords = NoteKeyCommands.table.keys.map(Chord.init)

    func key(_ key: String, _ modifiers: NSEvent.ModifierFlags) -> TextFormatKeyEquivalent {
        TextFormatKeyEquivalent(key: key, modifiers: modifiers)
    }

    var parcDefaults: [TextFormatCommand: TextFormatKeyEquivalent] {
        [
            .bold: key("b", .command), .italic: key("i", .command), .underline: key("u", .command),
            .heading1: key("h", [.command, .shift]), .body: key("b", [.command, .shift]),
            .bulletedList: key("7", [.command, .shift]), .numberedList: key("9", [.command, .shift]),
            .link: key("k", .command),
        ]
    }

    func chord(_ characters: String, _ modifiers: NSEvent.ModifierFlags, keyCode: UInt16 = 0) -> NoteKeyChord {
        NoteKeyChord(characters: characters, keyCode: keyCode, modifiers: modifiers)!
    }

    @Test func anUppercaseLetterReadsAsShiftPlusTheLetter() {
        #expect(key("H", .command) == key("h", [.command, .shift]))
    }

    @Test func onlyTheFourShortcutModifiersCount() {
        #expect(key("k", [.command, .function]).modifiers == .command)
    }

    @Test(arguments: NoteFormatMenuTests.commands)
    func aCommandShowsTheNotesOwnNotionShortcut(item: Command) {
        let expected: [TextFormatCommand: TextFormatKeyEquivalent] = [
            .bold: key("b", .command), .italic: key("i", .command), .underline: key("u", .command),
            .strikethrough: key("s", [.command, .shift]), .heading1: key("1", [.command, .option]),
            .heading2: key("2", [.command, .option]), .heading3: key("3", [.command, .option]),
            .body: key("0", [.command, .option]), .bulletedList: key("5", [.command, .option]),
            .numberedList: key("6", [.command, .option]), .link: key("k", .command),
        ]
        #expect(NoteFormatShortcuts.keyEquivalent(for: item.command) == expected[item.command])
    }

    @Test(arguments: NoteFormatMenuTests.chords)
    func aNoteChordSurvivesATripThroughAMenuKeyEquivalent(item: Chord) {
        #expect(NoteKeyChord(item.chord.keyEquivalent) == item.chord)
    }

    func displaced(_ chord: NoteKeyChord, defaults: [TextFormatCommand: TextFormatKeyEquivalent]) -> TextFormatCommand? {
        NoteFormatShortcuts.displacedFormat(for: chord) { defaults[$0] }
    }

    @Test func commandShiftHBelongsToTheNotesLastColourSoHeading1NeverFiresInsideANote() {
        #expect(displaced(chord("H", [.command, .shift], keyCode: 4), defaults: parcDefaults) == .heading1)
    }

    @Test func commandBMeansBoldInBothPlacesSoNothingIsDisplaced() {
        #expect(displaced(chord("b", .command, keyCode: 11), defaults: parcDefaults) == nil)
    }

    @Test func commandKMeansLinkInBothPlaces() {
        #expect(displaced(chord("k", .command, keyCode: 40), defaults: parcDefaults) == nil)
    }

    @Test func parcsCommandShiftSevenIsNotANoteChordSoItStillReachesBulletedList() {
        #expect(displaced(chord("&", [.command, .shift], keyCode: 26), defaults: parcDefaults) == nil)
    }

    @Test func aHeading1MovedOffCommandShiftHNoLongerClashes() {
        var rebound = parcDefaults
        rebound[.heading1] = key("1", [.command, .control])
        #expect(displaced(chord("H", [.command, .shift], keyCode: 4), defaults: rebound) == nil)
    }

    @Test func aCustomFormatChordANoteAlreadyUsesGivesWayToTheNote() {
        var rebound = parcDefaults
        rebound[.body] = key("d", .command)
        #expect(displaced(chord("d", .command, keyCode: 2), defaults: rebound) == .body)
    }

    @Test func aCustomChordTheNoteDoesNotUseKeepsWorkingThroughTheFormatMenu() {
        var rebound = parcDefaults
        rebound[.heading1] = key("1", [.command, .control])
        #expect(displaced(chord("1", [.command, .control], keyCode: 18), defaults: rebound) == nil)
    }

    @MainActor struct Menu {
        let items: [TextFormatCommand: NSMenuItem]
        let format: NSMenu
        let font: NSMenu
        let defaults: [TextFormatCommand: TextFormatKeyEquivalent]
    }

    func makeMenu() -> Menu {
        let defaults = parcDefaults
        let edit = NSMenu(title: "Edit")
        var items: [TextFormatCommand: NSMenuItem] = [:]
        let root = TextFormatMenu.add(to: edit) { item, command in
            items[command] = item
            if let chord = defaults[command] {
                item.keyEquivalent = chord.key
                item.keyEquivalentModifierMask = chord.modifiers
            }
        }
        let format = root.submenu!
        let font = format.item(withTitle: "Font")!.submenu!
        return Menu(items: items, format: format, font: font, defaults: defaults)
    }

    func shown(_ menu: Menu, _ command: TextFormatCommand) -> TextFormatKeyEquivalent? {
        TextFormatKeyEquivalent(of: menu.items[command]!)
    }

    @Test func withNoNoteInChargeTheFormatMenuKeepsParcsShortcuts() {
        let menu = makeMenu()
        menu.format.delegate?.menuWillOpen?(menu.format)
        #expect(shown(menu, .heading1) == menu.defaults[.heading1])
    }

    @Test(arguments: [
        (TextFormatCommand.heading1, "1", NSEvent.ModifierFlags.option), (.bulletedList, "5", .option),
    ] as [(TextFormatCommand, String, NSEvent.ModifierFlags)])
    func aNotesFormatMenuShowsItsOwnShortcuts(command: TextFormatCommand, character: String, modifier: NSEvent.ModifierFlags) {
        let menu = makeMenu()
        var swap = TextFormatShortcutSwap()
        swap.show(NoteOwner(), in: menu.format)
        swap.show(NoteOwner(), in: menu.font)
        #expect(shown(menu, command) == key(character, [.command, modifier]))
    }

    @Test func strikethroughShowsTheNotesCommandShiftS() {
        let menu = makeMenu()
        var swap = TextFormatShortcutSwap()
        swap.show(NoteOwner(), in: menu.format)
        swap.show(NoteOwner(), in: menu.font)
        #expect(shown(menu, .strikethrough) == key("s", [.command, .shift]))
    }

    @Test func commandsANoteCannotDoShowNoShortcut() {
        let menu = makeMenu()
        var swap = TextFormatShortcutSwap()
        swap.show(NoteOwner(), in: menu.format)
        swap.show(NoteOwner(), in: menu.font)
        #expect(shown(menu, .bigger) == nil)
    }

    @Test(arguments: NoteFormatMenuTests.commands)
    func aCommandGetsParcsShortcutBackWhenTheMenuClosesEvenAfterOpeningTwice(item: Command) {
        let menu = makeMenu()
        var swap = TextFormatShortcutSwap()
        swap.show(NoteOwner(), in: menu.format)
        swap.show(NoteOwner(), in: menu.font)
        swap.show(NoteOwner(), in: menu.format)
        swap.restore(in: menu.format)
        swap.restore(in: menu.font)
        #expect(shown(menu, item.command) == menu.defaults[item.command])
    }

    func changedWhileOpen() -> Menu {
        let menu = makeMenu()
        var swap = TextFormatShortcutSwap()
        swap.show(NoteOwner(), in: menu.format)
        menu.items[.heading1]!.keyEquivalent = "j"
        menu.items[.heading1]!.keyEquivalentModifierMask = [.command, .control]
        swap.restore(in: menu.format)
        return menu
    }

    @Test func aShortcutChangedInSettingsWhileTheMenuWasOpenIsKept() {
        #expect(shown(changedWhileOpen(), .heading1) == key("j", [.command, .control]))
    }

    @Test func untouchedItemsStillGoBack() {
        let menu = changedWhileOpen()
        #expect(shown(menu, .body) == menu.defaults[.body])
    }
}
