import Foundation

struct EaselChord: Hashable {
    enum Key: Hashable {
        case character(Character)
        case delete
        case returnKey
        case up, down, left, right
    }

    let key: Key
    let modifiers: EaselKeyModifiers

    init(_ key: Key, _ modifiers: EaselKeyModifiers) {
        self.key = key
        self.modifiers = modifiers.intersection([.shift, .control, .option, .command])
    }

    init(_ character: Character, _ modifiers: EaselKeyModifiers) {
        self.init(.character(character), modifiers)
    }

    init?(characters: String?, keyCode: UInt16, modifiers: EaselKeyModifiers) {
        switch keyCode {
        case 51, 117: self.init(.delete, modifiers)
        case 36, 76: self.init(.returnKey, modifiers)
        case 126: self.init(.up, modifiers)
        case 125: self.init(.down, modifiers)
        case 123: self.init(.left, modifiers)
        case 124: self.init(.right, modifiers)
        default:
            guard let character = Self.character(characters: characters, keyCode: keyCode) else { return nil }
            self.init(.character(character), modifiers)
        }
    }

    static func character(characters: String?, keyCode: UInt16) -> Character? {
        if let letter = EaselKeyCommands.letter(characters: characters, keyCode: keyCode) { return letter }
        let typed = (characters ?? "").lowercased()
        if typed.count == 1, let first = typed.first, first.isASCII {
            if first == "?" { return "/" }
            return symbolKeyCodes.values.contains(first) ? first : nil
        }
        return symbolKeyCodes[keyCode]
    }

    private static let symbolKeyCodes: [UInt16: Character] = [
        30: "]", 33: "[", 24: "=", 27: "-", 29: "0", 18: "1", 19: "2", 44: "/", 43: ",", 47: ".",
    ]
}

enum EaselChordCommand: Hashable {
    case duplicate
    case group
    case ungroup
    case unwrap
    case toggleLock
    case layer(EaselLayerMove)
    case alignText(EaselTextStyle.Alignment)
    case focusSelectionToolbar
}

enum EaselChords {
    static let table: [EaselChord: EaselChordCommand] = [
        EaselChord("d", .command): .duplicate,
        EaselChord("g", .command): .group,
        EaselChord("g", [.command, .shift]): .ungroup,
        EaselChord(.delete, .command): .unwrap,
        EaselChord("l", [.command, .shift]): .toggleLock,
        EaselChord("]", .command): .layer(.forward),
        EaselChord("[", .command): .layer(.backward),
        EaselChord("l", [.command, .option]): .alignText(.left),
        EaselChord("t", [.command, .option]): .alignText(.center),
        EaselChord("r", [.command, .option]): .alignText(.right),
        EaselChord("/", [.command, .shift]): .focusSelectionToolbar,
    ]

    static let reserved: [EaselChord] = [
        EaselChord("l", .command), EaselChord("p", .command), EaselChord("k", .command),
        EaselChord("k", [.command, .shift]), EaselChord("c", [.command, .shift]),
        EaselChord(.up, [.command, .option]), EaselChord(.down, [.command, .option]),
    ]

    static func command(for chord: EaselChord) -> EaselChordCommand? { table[chord] }

    static func command(characters: String?, keyCode: UInt16, modifiers: EaselKeyModifiers) -> EaselChordCommand? {
        EaselChord(characters: characters, keyCode: keyCode, modifiers: modifiers).flatMap(command(for:))
    }

    static func bareLayerMove(characters: String?, keyCode: UInt16) -> EaselLayerMove? {
        switch EaselChord.character(characters: characters, keyCode: keyCode) {
        case "]": return .front
        case "[": return .back
        default: return nil
        }
    }
}

extension EaselChords {
    static func consults(canvasFocus: Bool, editorFocus: Bool) -> Bool { canvasFocus || editorFocus }

    static func applies(_ command: EaselChordCommand, selection: Set<UUID>, in document: EaselDocument) -> Bool {
        let live = selection.intersection(Set(document.items.map(\.id)))
        switch command {
        case .duplicate, .toggleLock: return !live.isEmpty
        case .group: return EaselArrange.canGroup(live, in: document)
        case .ungroup, .unwrap: return EaselArrange.canUngroup(live, in: document)
        case .layer: return EaselArrange.canMoveLayer(live, in: document)
        default: return false
        }
    }
}
