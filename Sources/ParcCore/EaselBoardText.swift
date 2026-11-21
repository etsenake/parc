import Foundation

enum EaselBoardText {
    static func plainParts(in document: EaselDocument) -> [String] {
        var parts: [String] = []
        for page in EaselPages.pageDocuments(document) {
            for item in EaselFinder.readingOrder(page.items) {
                for part in EaselFinder.searchableParts(of: item) { parts.append(part.text) }
            }
        }
        return parts
    }

    static func stats(of document: EaselDocument) -> NotePageStats {
        let joined = plainParts(in: document).joined(separator: "\n")
        var words = 0
        joined.enumerateSubstrings(in: joined.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in words += 1 }
        return NotePageStats(words: words, characters: joined.reduce(0) { $1.isNewline ? $0 : $0 + 1 })
    }
}
