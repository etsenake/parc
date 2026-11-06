import Foundation

/// The recovered export boundary carries a document identity, title, HTML and
/// modification date. It is independent of an editor's mutable draft/session.
struct NoteExportDocument: Sendable {
    let id: UUID
    let title: String
    let html: String
    let modifiedAt: Date
}

enum NoteExportError: Error, LocalizedError {
    case empty, invalid, archiveFailed
    var errorDescription: String? {
        switch self {
        case .empty: return "There are no notes to export in this profile."
        case .invalid: return "These notes could not be prepared for export."
        case .archiveFailed: return "The Notes archive could not be created. Your notes have not changed."
        }
    }
}

/// Owned temporary output, prepared away from the main thread. Publication is a
/// separate step so a cancelled or retired window cannot write a late result.
final class NoteExportArchive: @unchecked Sendable {
    let file: URL
    let suggestedName: String
    private let directory: URL
    private init(file: URL, directory: URL, suggestedName: String) {
        self.file = file; self.directory = directory; self.suggestedName = suggestedName
    }
    deinit { try? FileManager.default.removeItem(at: directory) }

    static func filename(title: String, id: UUID) -> String {
        // Arc100704e24: split invalid filename characters, discard empty pieces,
        // join with underscores and trim. Length/hidden-name guards are local
        // filesystem adaptations; collisions are resolved by original IDs below.
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
            .union(.newlines).union(.illegalCharacters).union(.controlCharacters)
        var stem = title.components(separatedBy: invalid).filter { !$0.isEmpty }
            .joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        while stem.utf8.count > 180 { stem.removeLast() }
        if stem.isEmpty || stem.hasPrefix(".") { stem = id.uuidString.lowercased() }
        return stem + ".html"
    }

    static func prepare(_ documents: [NoteExportDocument], now: Date = Date()) throws -> NoteExportArchive {
        guard !documents.isEmpty else { throw NoteExportError.empty }
        guard Set(documents.map(\.id)).count == documents.count,
              documents.allSatisfy({ $0.modifiedAt.timeIntervalSinceReferenceDate.isFinite }) else {
            throw NoteExportError.invalid
        }
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("Parc-Notes-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        var retained = false
        defer { if !retained { try? manager.removeItem(at: root) } }
        let contents = root.appendingPathComponent("notes", isDirectory: true)
        try manager.createDirectory(at: contents, withIntermediateDirectories: false)
        var names = Set<String>()
        for document in documents {
            try Task.checkCancellation()
            var name = filename(title: document.title, id: document.id)
            func key(_ name: String) -> String { name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
            if !names.insert(key(name)).inserted {
                name = document.id.uuidString.lowercased() + ".html"
                // A user's title may itself be another document UUID.
                while !names.insert(key(name)).inserted { name = "_" + name }
            }
            let target = contents.appendingPathComponent(name, isDirectory: false)
            try document.html.write(to: target, atomically: true, encoding: .utf8)
            try manager.setAttributes([.modificationDate: document.modifiedAt], ofItemAtPath: target.path)
        }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let suggestedName = "Parc-Notes-Export-" + formatter.string(from: now) + ".zip"
        let archive = root.appendingPathComponent(suggestedName)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-r", archive.path, "."]; process.currentDirectoryURL = contents
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        try Task.checkCancellation()
        guard process.terminationReason == .exit, process.terminationStatus == 0,
              (try archive.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0 > 0 else {
            throw NoteExportError.archiveFailed
        }
        retained = true
        return NoteExportArchive(file: archive, directory: root, suggestedName: suggestedName)
    }

    func save(to destination: URL) throws {
        guard destination.isFileURL else { throw NoteExportError.invalid }
        let manager = FileManager.default
        let staged = destination.deletingLastPathComponent().appendingPathComponent(".parc-notes-" + UUID().uuidString)
        defer { try? manager.removeItem(at: staged) }
        try manager.copyItem(at: file, to: staged)
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: staged)
        } else {
            try manager.moveItem(at: staged, to: destination)
        }
    }
}
