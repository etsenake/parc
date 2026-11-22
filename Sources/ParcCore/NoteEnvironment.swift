import Foundation

package struct NoteReference: Hashable, Identifiable {
    package var url: URL
    package var title: String
    package var icon: String?
    package var modifiedAt: Date
    package var snippet: String? = nil
    package var id: URL { url }

    package init(url: URL, title: String, icon: String? = nil, modifiedAt: Date, snippet: String? = nil) {
        self.url = url
        self.title = title
        self.icon = icon
        self.modifiedAt = modifiedAt
        self.snippet = snippet
    }
}

@MainActor
package protocol NoteEnvironment: AnyObject {
    var documentURL: URL? { get }
    var isPlainText: Bool { get }
    var files: NoteFiles { get }
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
    package var files: NoteFiles { .shared }

    package var emojiLibrary: NoteEmojiLibrary? { nil }

    package var customEmojiNames: Set<String> { emojiLibrary?.names ?? [] }

    package func createNote(titled title: String) throws -> URL {
        guard let folder = documentURL?.deletingLastPathComponent() else { throw NoteFileError.missing }
        return try files.createNote(in: folder, title: title)
    }
}

@MainActor
final class NoteDetachedEnvironment: NoteEnvironment {
    let documentURL: URL?
    let isPlainText: Bool
    private let injectedFiles: NoteFiles?
    var files: NoteFiles { injectedFiles ?? .shared }

    init(documentURL: URL? = nil, isPlainText: Bool = false, files: NoteFiles? = nil) {
        self.documentURL = documentURL
        self.isPlainText = isPlainText
        injectedFiles = files
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
