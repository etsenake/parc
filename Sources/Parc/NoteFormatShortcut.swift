import AppKit

struct NoteFormatShortcut: Hashable {
    let key: String
    let modifiers: UInt

    init(_ key: String, _ flags: NSEvent.ModifierFlags) {
        self.key = key.lowercased()
        modifiers = flags.intersection([.control, .option, .shift, .command]).rawValue
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var glyphs: [String] {
        var result: [String] = []
        if flags.contains(.control) { result.append("⌃") }
        if flags.contains(.option) { result.append("⌥") }
        if flags.contains(.shift) { result.append("⇧") }
        if flags.contains(.command) { result.append("⌘") }
        result.append(Self.keyGlyph(key))
        return result
    }

    var display: String { glyphs.joined() }

    func matches(characters: String?, flags eventFlags: NSEvent.ModifierFlags) -> Bool {
        guard eventFlags.intersection([.control, .option, .shift, .command]) == flags,
              let typed = characters?.lowercased(), !typed.isEmpty else { return false }
        if typed == key { return true }
        return Self.shiftedPairs[key] == typed || Self.shiftedPairs[typed] == key
    }

    func matches(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        return matches(characters: event.charactersIgnoringModifiers, flags: event.modifierFlags)
    }

    private static let shiftedPairs: [String: String] = ["/": "?"]

    private static func keyGlyph(_ key: String) -> String {
        switch key {
        case "\r": return "↩"
        case "\u{1b}": return "⎋"
        case "\t": return "⇥"
        case " ": return "⎵"
        default: return key.uppercased()
        }
    }

    static let link = NoteFormatShortcut("k", .command)
    static let bold = NoteFormatShortcut("b", .command)
    static let italic = NoteFormatShortcut("i", .command)
    static let underline = NoteFormatShortcut("u", .command)
    static let strikethrough = NoteFormatShortcut("s", [.command, .shift])
    static let code = NoteFormatShortcut("e", .command)
    static let equation = NoteFormatShortcut("e", [.command, .shift])
    static let lastColor = NoteFormatShortcut("h", [.command, .shift])
    static let focusToolbar = NoteFormatShortcut("/", [.command, .shift])
}
