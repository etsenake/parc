import Foundation
import Testing
@testable import ParcCore

enum NoteCustomEmojiCodecTestsSupport {
    static let names: Set<String> = ["party", "parrot", "b", "a", "+1"]

    static func atom(_ name: String) -> NoteText { .atom(.customEmoji(name)) }

    static func text(_ pieces: NoteText...) -> NoteText {
        var value = NoteText()
        for piece in pieces { value.append(piece) }
        return value
    }

    static func firstText(_ markdown: String, names: Set<String> = Self.names) -> NoteText {
        NoteMarkdown.parse(markdown, customEmoji: names).blocks.first?.text ?? NoteText()
    }

    static func write(_ value: NoteText, names: Set<String> = Self.names) -> String {
        NoteMarkdown.serialize(NotePage(blocks: [.paragraph(value)]), customEmoji: names)
    }
}
