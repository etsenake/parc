import Combine
import Foundation

enum NoteFileSaveState: Equatable {
    case saved
    case unsaved
    case saving
    case failed(String)
    case conflict
    case missing
}

enum NoteFileError: Error, LocalizedError, Equatable {
    case unreadable(String)
    case tooLarge
    case nameTaken(String)
    case invalidName
    case missing
    case notANote

    var errorDescription: String? {
        switch self {
        case .unreadable(let detail): return "Parc couldn’t read this note. \(detail)"
        case .tooLarge: return "This file is too big to open as a note."
        case .nameTaken(let name): return "There’s already a note called “\(name)” here."
        case .invalidName: return "Notes can’t be named that."
        case .missing: return "This note isn’t where it used to be."
        case .notANote: return "Parc can only open Markdown and text files as notes."
        }
    }
}

@MainActor
final class NoteFileSession {
    private static var sessions: [String: NoteFileSession] = [:]

    static func open(_ url: URL) throws -> NoteFileSession {
        let key = url.standardizedFileURL.path
        if let existing = sessions[key] { return existing }
        guard let kind = NoteFileKind(url: url) else { throw NoteFileError.notANote }
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        let blocks = text.components(separatedBy: "\n").map { NoteBlock.paragraph(NoteText($0)) }
        let session = NoteFileSession(url: url.standardizedFileURL, kind: kind, page: NotePage(blocks: blocks))
        sessions[key] = session
        return session
    }

    static func session(for url: URL) -> NoteFileSession? { sessions[url.standardizedFileURL.path] }

    static func flushAll() throws {
        for session in sessions.values { try session.flush() }
    }

    private(set) var url: URL
    let kind: NoteFileKind
    let page: NotePageSession
    let environment: NoteEnvironment
    @Published private(set) var state: NoteFileSaveState = .saved
    let urlChanges = PassthroughSubject<URL, Never>()

    private init(url: URL, kind: NoteFileKind, page: NotePage) {
        self.url = url
        self.kind = kind
        self.page = NotePageSession(page: page)
        environment = NoteDetachedEnvironment(documentURL: url, isPlainText: kind == .plainText)
    }

    var title: String { url.deletingPathExtension().lastPathComponent }

    func rename(to title: String) throws -> URL { url }

    func flush() throws {}

    func resolveConflict(keepMine: Bool) {}

    func retain() {}

    func release() {}
}
