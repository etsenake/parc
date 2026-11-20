import Foundation

enum NoteAttachments {
    static let folderName = "Attachments"

    static func folder(for note: URL) -> URL {
        note.deletingLastPathComponent().appendingPathComponent(folderName, isDirectory: true)
    }

    static func importFile(_ source: URL, into note: URL) throws -> String {
        let noteFolder = NoteFilePaths.canonical(note.deletingLastPathComponent())
        let original = NoteFilePaths.canonical(source)
        guard NoteFilePaths.itemExists(original) else { throw NoteFileError.missing }
        if NoteFilePaths.contains(folder: noteFolder, item: original),
           let relative = NoteFilePaths.relativePath(from: noteFolder, to: original) {
            return relative
        }
        let destinationFolder = folder(for: note)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let pathExtension = original.pathExtension
        var base = NoteFileNaming.sanitizedTitle(original.deletingPathExtension().lastPathComponent)
        if base.isEmpty { base = "Attachment" }
        let directory = NoteFilePaths.isDirectory(original)
        for candidate in NoteFileNaming.candidates(in: destinationFolder, base: base, pathExtension: pathExtension).prefix(10_000) {
            if NoteFilePaths.itemExists(candidate) {
                if !directory, FileManager.default.contentsEqual(atPath: candidate.path, andPath: original.path) {
                    return relativeLink(to: candidate)
                }
                continue
            }
            do {
                try coordinatedCopy(original, to: candidate)
                return relativeLink(to: candidate)
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw NoteFileError.nameTaken(base)
    }

    static func importData(_ data: Data, fileExtension: String, suggestedName: String?, into note: URL, date: Date) throws -> String {
        let pathExtension = NoteFileNaming.sanitizedExtension(fileExtension)
        var base = ""
        if let suggestedName {
            let suggested = suggestedName as NSString
            let stem = suggested.pathExtension.lowercased() == pathExtension && !pathExtension.isEmpty
                ? suggested.deletingPathExtension : suggestedName
            base = NoteFileNaming.sanitizedTitle(stem)
        }
        if base.isEmpty { base = NoteFileNaming.pastedBaseName(at: date, isImage: NoteFileNaming.imageExtensions.contains(pathExtension)) }
        let destinationFolder = folder(for: note)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        for candidate in NoteFileNaming.candidates(in: destinationFolder, base: base, pathExtension: pathExtension).prefix(10_000) {
            if NoteFilePaths.itemExists(candidate) {
                if let existing = try? Data(contentsOf: candidate), existing == data { return relativeLink(to: candidate) }
                continue
            }
            do {
                try data.write(to: candidate, options: .withoutOverwriting)
                return relativeLink(to: candidate)
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw NoteFileError.nameTaken(base)
    }

    private static func relativeLink(to file: URL) -> String {
        NoteFilePaths.encodedPath([folderName, file.lastPathComponent])
    }

    private static func coordinatedCopy(_ source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: source, options: .withoutChanges,
                                                         writingItemAt: destination, options: [],
                                                         error: &coordinationError) { from, to in
            do { try FileManager.default.copyItem(at: from, to: to) } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError { throw error }
    }
}
