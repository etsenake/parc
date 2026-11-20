import AppKit

@main @MainActor
struct NoteKeyCommandsTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func command(_ characters: String, _ modifiers: NSEvent.ModifierFlags, keyCode: UInt16 = 0) -> NoteKeyCommand? {
        NoteKeyCommands.command(characters: characters, keyCode: keyCode, modifiers: modifiers)
    }

    static func main() {
        expect(command("b", .command) == .mark(.bold), "⌘B is bold")
        expect(command("i", .command) == .mark(.italic), "⌘I is italic")
        expect(command("u", .command) == .mark(.underline), "⌘U is underline")
        expect(command("S", [.command, .shift]) == .mark(.strikethrough), "⌘⇧S is strikethrough")
        expect(command("s", .command) == nil, "⌘S stays with the app")
        expect(command("e", .command) == .mark(.code), "⌘E is inline code")
        expect(command("E", [.command, .shift]) == .inlineEquation, "⌘⇧E is an inline equation")
        expect(command("k", .command) == .link, "⌘K is link")
        expect(command("H", [.command, .shift]) == .lastColor, "⌘⇧H reapplies the last colour")
        expect(command("d", .command) == .duplicate, "⌘D duplicates")
        expect(command("t", [.command, .option]) == .toggleAllToggles, "⌘⌥T flips every toggle")
        expect(command("/", .command) == .blockActions, "⌘/ opens block actions")
        expect(command("/", [.command, .shift]) == .blockActions, "⌘/ works where slash needs shift")
        expect(command("z", .command) == .undo, "⌘Z undoes")
        expect(command("Z", [.command, .shift]) == .redo, "⌘⇧Z redoes")
        expect(command("a", .command) == .selectAll, "⌘A selects")
        expect(command("v", [.command, .shift]) == .pastePlainText, "⌘⇧V pastes plain text")
        expect(command("f", .command) == .find, "⌘F finds")
        expect(command("f", [.command, .option]) == .findAndReplace, "⌘⌥F replaces")
        expect(command("g", .command) == .findNext, "⌘G finds the next match")
        expect(command("G", [.command, .shift]) == .findPrevious, "⌘⇧G finds the previous match")
        expect(command("p", .command) == .print, "⌘P prints")
        expect(command("b", [.command, .capsLock, .function]) == .mark(.bold), "irrelevant flags are ignored")
        let digits: [UInt16] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25]
        let targets: [NoteTurnIntoTarget] = [.text, .heading1, .heading2, .heading3, .todo, .bulleted, .numbered, .toggle, .code, .page]
        for (index, keyCode) in digits.enumerated() {
            expect(command("º", [.command, .option], keyCode: keyCode) == .turnInto(targets[index]),
                   "⌘⌥\(index) turns into \(targets[index].title) by physical key")
            expect(command("&", [.command], keyCode: keyCode) == nil, "plain ⌘\(index) stays with the app")
        }
        expect(NoteTurnIntoTarget.heading2.kind == .heading && NoteTurnIntoTarget.heading2.headingLevel == 2, "heading targets carry a level")
        expect(NoteTurnIntoTarget.todo.kind == .todo && NoteTurnIntoTarget.code.kind == .code, "targets map to kinds")
        expect(command("", .command, keyCode: 36) == .modifyBlock, "⌘↩ modifies the block")
        expect(command("", .command, keyCode: 76) == .modifyBlock, "⌘Enter on the keypad too")
        expect(command("", [.command, .shift], keyCode: 126) == .moveBlocks(.up), "⌘⇧↑ moves up")
        expect(command("", [.command, .shift], keyCode: 125) == .moveBlocks(.down), "⌘⇧↓ moves down")
        expect(command("", .command, keyCode: 126) == nil, "⌘↑ is left to the text view")
        expect(NoteKeyCommands.shortcutLabel(for: .mark(.strikethrough)) == "⇧⌘S", "labels use Parc keycap order")
        expect(NoteKeyCommands.shortcutLabel(for: .turnInto(.heading1)) == "⌥⌘1", "turn-into labels read well")
        expect(NoteKeyCommands.command(forAction: NSSelectorFromString("undo:")) == .undo, "menu undo routes to the session")
        expect(NoteKeyCommands.command(forAction: NSSelectorFromString("pasteAsPlainText:")) == .pastePlainText, "Paste and Match Style is plain")
        expect(NoteKeyCommands.command(forAction: NSSelectorFromString("copy:")) == .copy, "menu copy routes to the clipboard")
        let format = NoteKeyCommands.formatTextAction
        expect(NoteKeyCommands.command(forAction: format, tag: TextFormatCommand.bold.rawValue) == .mark(.bold), "Format › Bold")
        expect(NoteKeyCommands.command(forAction: format, tag: TextFormatCommand.heading3.rawValue) == .turnInto(.heading3), "Format › Heading 3")
        expect(NoteKeyCommands.command(forAction: format, tag: TextFormatCommand.body.rawValue) == .turnInto(.text), "Format › Body")
        expect(NoteKeyCommands.command(forAction: format, tag: TextFormatCommand.increaseIndent.rawValue) == .indent, "Format › Indent")
        expect(NoteKeyCommands.command(forAction: format, tag: TextFormatCommand.bigger.rawValue) == nil, "Bigger has no Notes meaning")
        expect(NoteKeyCommands.command(forAction: NSSelectorFromString("terminate:")) == nil, "other actions pass through")
        expect(NoteKeyCommand.copy.isEdit == false && NoteKeyCommand.paste.isEdit, "read-only pages can copy but not paste")
        var seen: [NoteKeyChord: NoteKeyCommand] = [:]
        for (chord, value) in NoteKeyCommands.table {
            expect(seen[chord] == nil, "chord \(chord) is bound once")
            seen[chord] = value
        }
        print("NoteKeyCommandsTests passed")
    }
}
