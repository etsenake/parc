import Foundation
import ParcCore

extension CommandBarDocument {
    static let fileNoteID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    init(note: NoteReference) {
        let icon = note.icon.flatMap { $0.count == 1 ? $0 : nil }
        self.init(kind: .note, id: Self.fileNoteID, title: note.title, url: note.url.standardizedFileURL, icon: icon)
    }
}

@MainActor
enum CommandBarNotes {
    nonisolated static let contentLimit = 6
    nonisolated static let minimumContentQuery = 3

    static func documents(profileID: UUID, openTabURLs: Set<URL>) -> [CommandBarDocument] {
        documents(in: NoteFolderPreferences.library(for: profileID), openTabURLs: openTabURLs)
    }

    static func documents(in library: NoteLibrary, openTabURLs: Set<URL>) -> [CommandBarDocument] {
        let open = Set(openTabURLs.map(CommandBarDocument.noteKey))
        return ((try? library.notes()) ?? []).map(CommandBarDocument.init(note:)).filter { !open.contains($0.key) }
    }

    static func contentMatches(_ query: String, in library: NoteLibrary?, openNotes: [URL] = [], files: NoteFiles? = nil,
                               limit: Int = contentLimit) -> [CommandBarDocument] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumContentQuery else { return [] }
        var found = library.map { $0.search(trimmed, limit: limit).map(CommandBarDocument.init(note:)) } ?? []
        var keys = Set(found.map(\.key))
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        for url in openNotes where found.count < limit && library?.contains(url) != true {
            let files = files ?? library?.files ?? .shared
            guard let session = files.session(for: url), keys.insert(CommandBarDocument.noteKey(session.url)).inserted else { continue }
            let text = session.title + "\n" + session.page.page.plainText
            guard words.allSatisfy({ text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil }) else { continue }
            found.append(CommandBarDocument(kind: .note, id: CommandBarDocument.fileNoteID, title: session.title, url: session.url.standardizedFileURL,
                                            icon: session.page.page.settings.icon.flatMap { $0.count == 1 ? $0 : nil }))
        }
        return found
    }

    static func refreshedMatches(for query: String, replacing previous: [CommandBarDocument], in library: NoteLibrary?,
                                 openNotes: [URL] = []) -> [CommandBarDocument]? {
        let fresh = contentMatches(query, in: library, openNotes: openNotes)
        return fresh == previous ? nil : fresh
    }
}
