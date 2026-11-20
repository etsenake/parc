import AppKit

enum NoteTurnIntoTarget: Int, CaseIterable, Hashable {
    case text, heading1, heading2, heading3, todo, bulleted, numbered, toggle, code, page

    var kind: NoteBlockKind {
        switch self {
        case .text: return .paragraph
        case .heading1, .heading2, .heading3: return .heading
        case .todo: return .todo
        case .bulleted: return .bulletedItem
        case .numbered: return .numberedItem
        case .toggle: return .toggle
        case .code: return .code
        case .page: return .pageLink
        }
    }

    var headingLevel: Int? {
        switch self {
        case .heading1: return 1
        case .heading2: return 2
        case .heading3: return 3
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .text: return "Text"
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .todo: return "To-do List"
        case .bulleted: return "Bulleted List"
        case .numbered: return "Numbered List"
        case .toggle: return "Toggle List"
        case .code: return "Code"
        case .page: return "Note"
        }
    }
}

enum NoteKeyCommand: Hashable {
    case mark(NoteMarkKey)
    case inlineEquation
    case link
    case lastColor
    case turnInto(NoteTurnIntoTarget)
    case duplicate
    case moveBlocks(NoteMoveDirection)
    case modifyBlock
    case toggleAllToggles
    case blockActions
    case focusToolbar
    case indent
    case outdent
    case undo
    case redo
    case selectAll
    case copy
    case cut
    case paste
    case pastePlainText
    case delete
    case find
    case findAndReplace
    case findNext
    case findPrevious
    case useSelectionForFind
    case print

    var isEdit: Bool {
        switch self {
        case .mark, .inlineEquation, .link, .lastColor, .turnInto, .duplicate, .moveBlocks, .modifyBlock,
             .indent, .outdent, .undo, .redo, .cut, .paste, .pastePlainText, .delete, .findAndReplace:
            return true
        case .toggleAllToggles, .blockActions, .focusToolbar, .selectAll, .copy, .find, .findNext, .findPrevious,
             .useSelectionForFind, .print:
            return false
        }
    }

    var needsTextSelection: Bool {
        switch self {
        case .mark, .inlineEquation, .lastColor: return true
        default: return false
        }
    }
}

struct NoteKeyChord: Hashable, CustomStringConvertible {
    enum Key: Hashable {
        case character(String)
        case digit(Int)
        case returnKey
        case up
        case down
    }

    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .shift, .control]

    let key: Key
    let modifiers: NSEvent.ModifierFlags

    init(_ key: Key, _ modifiers: NSEvent.ModifierFlags) {
        self.key = key
        self.modifiers = modifiers.intersection(Self.relevantModifiers)
    }

    static func == (lhs: NoteKeyChord, rhs: NoteKeyChord) -> Bool {
        lhs.key == rhs.key && lhs.modifiers.rawValue == rhs.modifiers.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(modifiers.rawValue)
    }

    var description: String {
        var value = ""
        if modifiers.contains(.control) { value += "⌃" }
        if modifiers.contains(.option) { value += "⌥" }
        if modifiers.contains(.shift) { value += "⇧" }
        if modifiers.contains(.command) { value += "⌘" }
        switch key {
        case .character(let character): value += character.uppercased()
        case .digit(let digit): value += String(digit)
        case .returnKey: value += "↩"
        case .up: value += "↑"
        case .down: value += "↓"
        }
        return value
    }

    private static let digitKeyCodes: [UInt16: Int] = [29: 0, 18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
    private static let shiftedSymbols: [String: String] = ["?": "/"]

    init?(characters: String?, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        let flags = modifiers.intersection(Self.relevantModifiers)
        if let digit = Self.digitKeyCodes[keyCode] {
            self.init(.digit(digit), flags)
            return
        }
        switch keyCode {
        case 36, 76: self.init(.returnKey, flags); return
        case 126: self.init(.up, flags); return
        case 125: self.init(.down, flags); return
        default: break
        }
        guard let characters, characters.count == 1 else { return nil }
        var lowered = characters.lowercased()
        if let base = Self.shiftedSymbols[lowered], flags.contains(.shift) { lowered = base }
        self.init(.character(lowered), flags)
    }

    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        self.init(characters: event.charactersIgnoringModifiers, keyCode: event.keyCode, modifiers: event.modifierFlags)
    }
}

enum NoteKeyCommands {
    static let table: [NoteKeyChord: NoteKeyCommand] = {
        var value: [NoteKeyChord: NoteKeyCommand] = [
            NoteKeyChord(.character("b"), .command): .mark(.bold),
            NoteKeyChord(.character("i"), .command): .mark(.italic),
            NoteKeyChord(.character("u"), .command): .mark(.underline),
            NoteKeyChord(.character("s"), [.command, .shift]): .mark(.strikethrough),
            NoteKeyChord(.character("e"), .command): .mark(.code),
            NoteKeyChord(.character("e"), [.command, .shift]): .inlineEquation,
            NoteKeyChord(.character("k"), .command): .link,
            NoteKeyChord(.character("h"), [.command, .shift]): .lastColor,
            NoteKeyChord(.character("d"), .command): .duplicate,
            NoteKeyChord(.up, [.command, .shift]): .moveBlocks(.up),
            NoteKeyChord(.down, [.command, .shift]): .moveBlocks(.down),
            NoteKeyChord(.returnKey, .command): .modifyBlock,
            NoteKeyChord(.character("t"), [.command, .option]): .toggleAllToggles,
            NoteKeyChord(.character("/"), .command): .blockActions,
            NoteKeyChord(.character("/"), [.command, .shift]): .focusToolbar,
            NoteKeyChord(.character("z"), .command): .undo,
            NoteKeyChord(.character("z"), [.command, .shift]): .redo,
            NoteKeyChord(.character("y"), .command): .redo,
            NoteKeyChord(.character("a"), .command): .selectAll,
            NoteKeyChord(.character("c"), .command): .copy,
            NoteKeyChord(.character("x"), .command): .cut,
            NoteKeyChord(.character("v"), .command): .paste,
            NoteKeyChord(.character("v"), [.command, .shift]): .pastePlainText,
            NoteKeyChord(.character("v"), [.command, .shift, .option]): .pastePlainText,
            NoteKeyChord(.character("f"), .command): .find,
            NoteKeyChord(.character("f"), [.command, .option]): .findAndReplace,
            NoteKeyChord(.character("g"), .command): .findNext,
            NoteKeyChord(.character("g"), [.command, .shift]): .findPrevious,
            NoteKeyChord(.character("e"), [.command, .control]): .useSelectionForFind,
            NoteKeyChord(.character("p"), .command): .print,
        ]
        for target in NoteTurnIntoTarget.allCases {
            value[NoteKeyChord(.digit(target.rawValue), [.command, .option])] = .turnInto(target)
        }
        return value
    }()

    static func command(for chord: NoteKeyChord) -> NoteKeyCommand? { table[chord] }

    static func command(characters: String?, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> NoteKeyCommand? {
        NoteKeyChord(characters: characters, keyCode: keyCode, modifiers: modifiers).flatMap(command(for:))
    }

    static func command(for event: NSEvent) -> NoteKeyCommand? {
        NoteKeyChord(event: event).flatMap(command(for:))
    }

    static func chord(for command: NoteKeyCommand) -> NoteKeyChord? {
        table.filter { $0.value == command }.keys.min { $0.description.count < $1.description.count }
    }

    static func shortcutLabel(for command: NoteKeyCommand) -> String? { chord(for: command)?.description }

    static let formatTextAction = NSSelectorFromString("formatText:")

    static func command(forAction action: Selector, tag: Int = 0) -> NoteKeyCommand? {
        if action == formatTextAction { return TextFormatCommand(rawValue: tag).flatMap(command(for:)) }
        switch NSStringFromSelector(action) {
        case "undo:": return .undo
        case "redo:": return .redo
        case "copy:": return .copy
        case "cut:": return .cut
        case "paste:", "pasteAsRichText:": return .paste
        case "pasteAsPlainText:", "pasteAndMatchStyle:": return .pastePlainText
        case "delete:": return .delete
        case "selectAll:": return .selectAll
        case "toggleBoldface:": return .mark(.bold)
        case "toggleItalics:": return .mark(.italic)
        case "underline:": return .mark(.underline)
        case "print:": return .print
        default: return nil
        }
    }

    static func command(for format: TextFormatCommand) -> NoteKeyCommand? {
        switch format {
        case .bold: return .mark(.bold)
        case .italic: return .mark(.italic)
        case .underline: return .mark(.underline)
        case .strikethrough: return .mark(.strikethrough)
        case .heading1: return .turnInto(.heading1)
        case .heading2: return .turnInto(.heading2)
        case .heading3: return .turnInto(.heading3)
        case .body: return .turnInto(.text)
        case .bulletedList: return .turnInto(.bulleted)
        case .numberedList: return .turnInto(.numbered)
        case .increaseIndent: return .indent
        case .decreaseIndent: return .outdent
        case .link: return .link
        case .bigger, .smaller: return nil
        }
    }
}
