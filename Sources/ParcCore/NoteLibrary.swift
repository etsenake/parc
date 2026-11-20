import Combine
import Foundation

@MainActor
final class NoteLibrary {
    private static var libraries: [String: NoteLibrary] = [:]

    static var defaultFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Parc Notes", isDirectory: true)
    }

    static func shared(folder: URL) -> NoteLibrary {
        let key = folder.standardizedFileURL.path
        if let existing = libraries[key] { return existing }
        let library = NoteLibrary(folder: folder.standardizedFileURL)
        libraries[key] = library
        return library
    }

    static func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    let folder: URL
    let changes = PassthroughSubject<Void, Never>()

    private init(folder: URL) { self.folder = folder }

    func createNote(title: String? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent((title ?? "Untitled") + ".md")
        try Data().write(to: url, options: .withoutOverwriting)
        changes.send()
        return url
    }

    func notes() throws -> [NoteReference] { [] }

    func search(_ query: String, limit: Int) -> [NoteReference] { [] }
}
