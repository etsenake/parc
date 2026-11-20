import Foundation

struct NoteReference: Hashable, Identifiable {
    var url: URL
    var title: String
    var icon: String?
    var modifiedAt: Date
    var snippet: String? = nil
    var id: URL { url }
}

@MainActor
protocol NoteEnvironment: AnyObject {
    var documentURL: URL? { get }
    var isPlainText: Bool { get }
    func resolve(_ source: String) -> URL?
    func importAsset(from url: URL) throws -> String
    func importAsset(data: Data, fileExtension: String, suggestedName: String?) throws -> String
    func searchNotes(_ query: String, limit: Int) -> [NoteReference]
    func linkTarget(for note: URL) -> String
    func resolveNoteLink(_ target: String) -> URL?
    func createNote(titled title: String) throws -> URL
    var emojiLibrary: NoteEmojiLibrary? { get }
}

extension NoteEnvironment {
    var emojiLibrary: NoteEmojiLibrary? { nil }

    var customEmojiNames: Set<String> { emojiLibrary?.names ?? [] }

    func createNote(titled title: String) throws -> URL {
        guard let folder = documentURL?.deletingLastPathComponent() else { throw NoteFileError.missing }
        return try NoteLibrary.createNote(in: folder, title: title)
    }
}

@MainActor
final class NoteDetachedEnvironment: NoteEnvironment {
    let documentURL: URL?
    let isPlainText: Bool

    init(documentURL: URL? = nil, isPlainText: Bool = false) {
        self.documentURL = documentURL
        self.isPlainText = isPlainText
    }

    func resolve(_ source: String) -> URL? {
        if let url = URL(string: source), url.scheme != nil { return url }
        guard let base = documentURL?.deletingLastPathComponent() else { return nil }
        let decoded = source.removingPercentEncoding ?? source
        return URL(fileURLWithPath: decoded, relativeTo: base).standardizedFileURL
    }

    func importAsset(from url: URL) throws -> String { url.absoluteString }

    func importAsset(data: Data, fileExtension: String, suggestedName: String?) throws -> String {
        throw CocoaError(.fileWriteNoPermission)
    }

    func searchNotes(_ query: String, limit: Int) -> [NoteReference] { [] }

    func linkTarget(for note: URL) -> String { note.absoluteString }

    func resolveNoteLink(_ target: String) -> URL? { resolve(target) }
}
