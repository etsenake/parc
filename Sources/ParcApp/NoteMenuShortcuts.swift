import AppKit

extension NoteKeyChord {
    init?(_ equivalent: TextFormatKeyEquivalent) {
        let key = equivalent.key
        guard key.unicodeScalars.count == 1, let scalar = key.unicodeScalars.first else { return nil }
        if let digit = Int(key) {
            self.init(.digit(digit), equivalent.modifiers)
            return
        }
        switch Int(scalar.value) {
        case 3, 13: self.init(.returnKey, equivalent.modifiers)
        case NSUpArrowFunctionKey: self.init(.up, equivalent.modifiers)
        case NSDownArrowFunctionKey: self.init(.down, equivalent.modifiers)
        default: self.init(.character(key), equivalent.modifiers)
        }
    }

    var keyEquivalent: TextFormatKeyEquivalent {
        switch key {
        case .character(let character): return TextFormatKeyEquivalent(key: character, modifiers: modifiers)
        case .digit(let digit): return TextFormatKeyEquivalent(key: String(digit), modifiers: modifiers)
        case .returnKey: return TextFormatKeyEquivalent(key: "\r", modifiers: modifiers)
        case .up: return TextFormatKeyEquivalent(key: String(utf16CodeUnits: [unichar(NSUpArrowFunctionKey)], count: 1), modifiers: modifiers)
        case .down: return TextFormatKeyEquivalent(key: String(utf16CodeUnits: [unichar(NSDownArrowFunctionKey)], count: 1), modifiers: modifiers)
        }
    }
}

enum NoteFormatShortcuts {
    static func keyEquivalent(for format: TextFormatCommand) -> TextFormatKeyEquivalent? {
        NoteKeyCommands.command(for: format).flatMap(NoteKeyCommands.chord(for:))?.keyEquivalent
    }

    static func displacedFormat(for chord: NoteKeyChord, bound: (TextFormatCommand) -> TextFormatKeyEquivalent?) -> TextFormatCommand? {
        guard let owned = NoteKeyCommands.command(for: chord) else { return nil }
        return TextFormatCommand.allCases.first { format in
            guard let equivalent = bound(format), NoteKeyChord(equivalent) == chord else { return false }
            return NoteKeyCommands.command(for: format) != owned
        }
    }
}
