import Foundation

struct DocumentsLibraryItem: Equatable {
    enum Identity: Hashable {
        case note(URL), easel(UUID)
    }

    let identity: Identity
    let title: String
    let emoji: String?
    let preview: String
    let detail: String
    let modified: Date

    var noteURL: URL? { if case .note(let url) = identity { return url }; return nil }
    var easelID: UUID? { if case .easel(let id) = identity { return id }; return nil }
    var isNote: Bool { noteURL != nil }
    var key: String {
        switch identity {
        case .note(let url): return "note:" + url.standardizedFileURL.path
        case .easel(let id): return "easel:" + id.uuidString.lowercased()
        }
    }
}

struct DocumentsLibraryInputs: Equatable {
    let notes: [NoteReference]
    let easels: [EaselSummary]
    let pending: Bool
    let query: String
    let noteMatches: [URL]
}

enum DocumentsLibraryRenameError: LocalizedError {
    case changed
    var errorDescription: String? { "This changed in another window. Give it another try." }
}

enum DocumentsLibraryCatalog {
    static let untitledNote = "Untitled"
    static let untitledEasel = "Untitled Easel"
    static let previewLimit = 160
    static let emptyText = "Your local Easels and Notes will appear here."
    static let noMatchesText = "Nothing matches that. Try fewer words?"

    static func items(notes: [NoteReference], easels: [EaselSummary]) -> [DocumentsLibraryItem] {
        notes.map { note in
            DocumentsLibraryItem(identity: .note(note.url.standardizedFileURL), title: displayTitle(note.title, untitled: untitledNote),
                                 emoji: emoji(note.icon), preview: preview(note.snippet), detail: "Note", modified: note.modifiedAt)
        } + easels.map { easel in
            DocumentsLibraryItem(identity: .easel(easel.id), title: displayTitle(easel.title, untitled: untitledEasel), emoji: nil,
                                 preview: "", detail: "Easel · \(easel.itemCount) objects", modified: easel.modifiedAt)
        }
    }

    @MainActor
    static func inputs(library: NoteLibrary, easels: () throws -> [EaselSummary], pending: Bool, query: String,
                       searchLimit: Int) throws -> DocumentsLibraryInputs {
        let notes = try library.notes()
        let easels = try easels()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = trimmed.isEmpty ? [] : library.search(trimmed, limit: searchLimit).map(\.url)
        return DocumentsLibraryInputs(notes: notes, easels: easels, pending: pending, query: trimmed, noteMatches: matches)
    }

    static func visible(_ inputs: DocumentsLibraryInputs) -> [DocumentsLibraryItem] {
        visible(items(notes: inputs.notes, easels: inputs.easels), query: inputs.query, noteMatches: inputs.noteMatches)
    }

    static func visible(_ items: [DocumentsLibraryItem], query: String, noteMatches: [URL] = []) -> [DocumentsLibraryItem] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return items.sorted(by: newestFirst) }
        let matched = Set(noteMatches.map { $0.standardizedFileURL.path })
        var titled: [DocumentsLibraryItem] = [], other: [DocumentsLibraryItem] = []
        for item in items {
            if contains(words, in: item.title) { titled.append(item); continue }
            let searched = item.noteURL.map { matched.contains($0.standardizedFileURL.path) } ?? false
            if searched || contains(words, in: item.title + " " + item.preview + " " + item.detail) { other.append(item) }
        }
        return titled.sorted(by: newestFirst) + other.sorted(by: newestFirst)
    }

    static func edited(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        func ago(_ count: Int, _ unit: String) -> String { "\(count) \(unit)\(count == 1 ? "" : "s") ago" }
        switch seconds {
        case ..<60: return "Just now"
        case ..<3_600: return ago(Int(seconds / 60), "minute")
        case ..<86_400: return ago(Int(seconds / 3_600), "hour")
        case ..<172_800: return "Yesterday"
        case ..<1_209_600: return ago(Int(seconds / 86_400), "day")
        case ..<5_184_000: return ago(Int(seconds / 604_800), "week")
        case ..<31_536_000: return ago(Int(seconds / 2_592_000), "month")
        default: return ago(Int(seconds / 31_536_000), "year")
        }
    }

    static func emptyMessage(query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? emptyText : noMatchesText
    }

    static func emoji(_ icon: String?) -> String? {
        guard let icon = icon?.trimmingCharacters(in: .whitespacesAndNewlines), icon.count == 1,
              let scalar = icon.unicodeScalars.first, scalar.properties.isEmoji,
              scalar.properties.isEmojiPresentation || icon.unicodeScalars.count > 1 else { return nil }
        return icon
    }

    static func preview(_ snippet: String?) -> String {
        let words = (snippet ?? "").split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        var text = words.joined(separator: " ")
        if text.count > previewLimit { text = String(text.prefix(previewLimit - 1)).trimmingCharacters(in: .whitespaces) + "…" }
        return text
    }

    private static func displayTitle(_ title: String, untitled: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? untitled : trimmed
    }

    private static func contains(_ words: [String], in text: String) -> Bool {
        words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil }
    }

    private static func newestFirst(_ lhs: DocumentsLibraryItem, _ rhs: DocumentsLibraryItem) -> Bool {
        lhs.modified == rhs.modified ? lhs.key < rhs.key : lhs.modified > rhs.modified
    }
}
