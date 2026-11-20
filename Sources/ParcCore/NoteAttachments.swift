import Combine
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

enum NoteAttachmentImportState: Equatable {
    case pending
    case imported(String)
    case failed(missing: Bool)
}

@MainActor
final class NoteAttachmentImports {
    private struct Healer {
        weak var session: NotePageSession?
        var subscription: AnyCancellable
    }

    static let shared = NoteAttachmentImports()
    nonisolated static let scheme = "parc-attachment"

    var worker = NoteFileWorker(label: "org.parc.notes.attachments")
    let changes = PassthroughSubject<String, Never>()
    private var states: [String: NoteAttachmentImportState] = [:]
    private var healers: [String: Healer] = [:]

    nonisolated static func isToken(_ source: String?) -> Bool {
        source?.hasPrefix(scheme + ":") == true
    }

    func state(of source: String?) -> NoteAttachmentImportState? {
        guard let source, Self.isToken(source) else { return nil }
        return states[source] ?? .failed(missing: true)
    }

    func begin(in session: NotePageSession, _ work: @escaping () throws -> String) -> String {
        let token = Self.scheme + ":" + UUID().uuidString
        states[token] = .pending
        worker.perform({ Result { try work() } }) { [weak self, weak session] result in
            self?.finish(token, result, session: session)
        }
        return token
    }

    private func finish(_ token: String, _ result: Result<String, Error>, session: NotePageSession?) {
        switch result {
        case .success(let path):
            states[token] = .imported(path)
            healers = healers.filter { $0.value.session != nil }
            if let session {
                Self.settle(token, as: path, in: session)
                let subscription = session.changes.filter(\.isUndoRedo).sink { [weak session] _ in
                    _ = NoteFileSystemClock.shared.schedule(after: 0) { [weak session] in
                        guard let session else { return }
                        Self.settle(token, as: path, in: session)
                    }
                }
                healers[token] = Healer(session: session, subscription: subscription)
            }
        case .failure(let error):
            states[token] = .failed(missing: (error as? NoteFileError) == .missing)
        }
        changes.send(token)
    }

    static func settle(_ token: String, as path: String, in session: NotePageSession) {
        let page = session.page
        let waiting = page.documentOrder(includingCollapsed: true).filter { page.block($0)?.props.source == token }
        for id in waiting {
            session.updateBlockMetadata(id, kind: .structure) { block in
                if block.props.source == token { block.props.source = path }
            }
        }
    }
}
