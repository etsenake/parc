import Foundation
import Testing
@testable import ParcCore

enum NoteHTMLReaderTestsSupport {
    static func marks(_ word: String, _ text: NoteText) -> NoteMarks? { NoteHTMLCheck.marks(of: word, in: text) }

    static func read(_ html: String, base: String? = nil) -> [NoteBlock] {
        NoteHTMLReader.blocks(from: html, baseURL: base.flatMap(URL.init(string:)))
    }

    static func shape(_ blocks: [NoteBlock], _ expected: [String], _ label: String) {
        let kinds = blocks.map { $0.kind.rawValue }
        #expect(kinds == expected, "\(label) shape:\n\(NoteHTMLCheck.outline(blocks))")
    }
}
