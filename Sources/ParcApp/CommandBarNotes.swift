import Foundation

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

    static func contentMatches(_ query: String, in library: NoteLibrary?, limit: Int = contentLimit) -> [CommandBarDocument] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let library, trimmed.count >= minimumContentQuery else { return [] }
        return library.search(trimmed, limit: limit).map(CommandBarDocument.init(note:))
    }
}
