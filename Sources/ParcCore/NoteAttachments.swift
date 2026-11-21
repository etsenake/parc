import Combine
import Foundation

package enum NoteAttachments {
    package struct Placement: Equatable, Sendable {
        package var path: String
        package var created: Bool

        package init(path: String, created: Bool) {
            self.path = path
            self.created = created
        }
    }

    package static let folderName = "Attachments"
    package static let stagingFolder = FileManager.default.temporaryDirectory.appendingPathComponent("Parc Note Imports", isDirectory: true)

    package static func folder(for note: URL) -> URL {
        note.deletingLastPathComponent().appendingPathComponent(folderName, isDirectory: true)
    }

    package static func existingSource(for file: URL, in note: URL) -> String? {
        let noteFolder = NoteFilePaths.canonical(note.deletingLastPathComponent())
        let original = NoteFilePaths.canonical(file)
        guard NoteFilePaths.contains(folder: noteFolder, item: original) else { return nil }
        return NoteFilePaths.relativePath(from: noteFolder, to: original)
    }

    package static func importFile(_ source: URL, into note: URL) throws -> String {
        try placeFile(source, into: note).path
    }

    package static func placeFile(_ source: URL, into note: URL) throws -> Placement {
        let original = NoteFilePaths.canonical(source)
        guard NoteFilePaths.itemExists(original) else { throw NoteFileError.missing }
        if let relative = existingSource(for: original, in: note) { return Placement(path: relative, created: false) }
        let destinationFolder = folder(for: note)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let pathExtension = original.pathExtension
        var base = NoteFileNaming.sanitizedTitle(original.deletingPathExtension().lastPathComponent)
        if base.isEmpty { base = "Attachment" }
        let directory = NoteFilePaths.isDirectory(original)
        for candidate in NoteFileNaming.candidates(in: destinationFolder, base: base, pathExtension: pathExtension).prefix(10_000) {
            if NoteFilePaths.itemExists(candidate) {
                if !directory, fileSize(candidate) == fileSize(original),
                   FileManager.default.contentsEqual(atPath: candidate.path, andPath: original.path) {
                    return Placement(path: relativeLink(to: candidate), created: false)
                }
                continue
            }
            do {
                try coordinatedCopy(original, to: candidate)
                return Placement(path: relativeLink(to: candidate), created: true)
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw NoteFileError.nameTaken(base)
    }

    package static func importData(_ data: Data, fileExtension: String, suggestedName: String?, into note: URL, date: Date) throws -> String {
        try placeData(data, fileExtension: fileExtension, suggestedName: suggestedName, into: note, date: date).path
    }

    package static func placeData(_ data: Data, fileExtension: String, suggestedName: String?, into note: URL, date: Date) throws -> Placement {
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
                if fileSize(candidate) == data.count, let existing = try? Data(contentsOf: candidate), existing == data {
                    return Placement(path: relativeLink(to: candidate), created: false)
                }
                continue
            }
            do {
                try data.write(to: candidate, options: .withoutOverwriting)
                return Placement(path: relativeLink(to: candidate), created: true)
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw NoteFileError.nameTaken(base)
    }

    package static func stage(_ data: Data, fileExtension: String, suggestedName: String) throws -> URL {
        var base = NoteFileNaming.sanitizedTitle(suggestedName)
        if base.isEmpty { base = "Attachment" }
        let folder = stagingFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(NoteFileNaming.fileName(base: base, pathExtension: NoteFileNaming.sanitizedExtension(fileExtension)))
        try data.write(to: file, options: .withoutOverwriting)
        return NoteFilePaths.canonical(file)
    }

    package static func isStaged(_ file: URL) -> Bool {
        file.isFileURL && NoteFilePaths.contains(folder: stagingFolder, item: file)
    }

    private static func fileSize(_ file: URL) -> Int? {
        try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize
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

package enum NoteAttachmentError: LocalizedError, Equatable {
    case leftInPlace(String)

    package var errorDescription: String? {
        switch self {
        case .leftInPlace(let name): return "Couldn’t copy “\(name)” into Attachments, so the note still links to where it lives."
        }
    }
}

@MainActor
package final class NoteAttachmentImports {
    private final class Ledger {
        weak var session: NotePageSession?
        var pending: [String: Int] = [:]
        var tried: Set<String> = []
        var landed: [String: String] = [:]
        var failures: [String: Error] = [:]
        var healer: AnyCancellable?

        init(_ session: NotePageSession) { self.session = session }
    }

    package static var shared: NoteAttachmentImports { NoteFiles.shared.attachmentImports }

    package unowned let files: NoteFiles
    package let changes = PassthroughSubject<String, Never>()
    private var ledgers: [ObjectIdentifier: Ledger] = [:]
    private var originals: Set<String> = []
    private var orphans: [String: [String: String]] = [:]

    package init(files: NoteFiles) {
        self.files = files
    }

    private var worker: NoteFileWorker { files.settings.attachmentWorker }
    private var clock: NoteFileClock { files.clock }

    package func isPending(_ source: String?, in session: NotePageSession) -> Bool {
        guard let source, let ledger = existingLedger(for: session) else { return false }
        return ledger.pending[source] != nil
    }

    package func hasTried(_ source: String?, in session: NotePageSession) -> Bool {
        guard let source, let ledger = existingLedger(for: session) else { return false }
        return ledger.tried.contains(source)
    }

    package func landedPath(for source: String?, in session: NotePageSession) -> String? {
        guard let source else { return nil }
        return existingLedger(for: session)?.landed[source]
    }

    package func takeFailure(of source: String?, in session: NotePageSession) -> Error? {
        guard let source, let ledger = existingLedger(for: session) else { return nil }
        return ledger.failures.removeValue(forKey: source)
    }

    package func mayImport(_ file: URL) -> Bool {
        guard file.isFileURL else { return false }
        return originals.contains(NoteFilePaths.canonical(file).path) || NoteAttachments.isStaged(file)
    }

    package func begin(_ source: String, from original: URL, in session: NotePageSession, note: URL,
               _ work: @escaping () throws -> NoteAttachments.Placement) {
        let ledger = ledger(for: session)
        ledger.pending[source, default: 0] += 1
        ledger.tried.insert(source)
        ledger.failures[source] = nil
        originals.insert(NoteFilePaths.canonical(original).path)
        worker.perform({ Result { try work() } }) { [weak self, weak session] result in
            self?.finish(source, result, from: session, note: note)
        }
    }

    private func finish(_ source: String, _ result: Result<NoteAttachments.Placement, Error>, from origin: NotePageSession?, note: URL) {
        ledgers = ledgers.filter { $0.value.session != nil }
        if case .success(let placement) = result, let target = liveSession(origin, note: note),
           let moved = movedNote(of: target, from: note) {
            follow(source, placement, from: note, to: moved, origin: origin)
            return
        }
        if let origin, let ledger = existingLedger(for: origin), let count = ledger.pending[source] {
            ledger.pending[source] = count > 1 ? count - 1 : nil
        }
        switch result.map(\.path) {
        case .success(let path):
            if let target = liveSession(origin, note: note) {
                land([source: path], in: target)
            } else {
                orphans[NoteFilePaths.key(for: note), default: [:]][source] = path
            }
        case .failure(let error):
            if let origin { ledger(for: origin).failures[source] = error }
        }
        changes.send(source)
    }

    private func follow(_ source: String, _ placement: NoteAttachments.Placement, from note: URL, to moved: URL, origin: NotePageSession?) {
        let folder = note.deletingLastPathComponent()
        let landed = folder.appendingPathComponent(placement.path.removingPercentEncoding ?? placement.path)
        let discarding = placement.created && !isClaimed(landed, besides: origin, in: folder)
        worker.perform({ Result { try Self.rebase(landed, created: placement.created, into: moved, discardingOriginal: discarding) } }) {
            [weak self, weak origin] result in
            self?.finish(source, result, from: origin, note: moved)
        }
    }

    private func isClaimed(_ file: URL, besides origin: NotePageSession?, in folder: URL) -> Bool {
        let fileKey = NoteFilePaths.key(for: file), folderKey = NoteFilePaths.key(for: folder)
        for ledger in ledgers.values {
            guard let session = ledger.session,
                  let note = files.openSessions.first(where: { $0.page === session })?.url else { continue }
            let noteFolder = note.deletingLastPathComponent()
            if session !== origin, !ledger.pending.isEmpty, NoteFilePaths.key(for: noteFolder) == folderKey { return true }
            if ledger.landed.values.contains(where: { NoteFilePaths.key(for: noteFolder.appendingPathComponent($0.removingPercentEncoding ?? $0)) == fileKey }) {
                return true
            }
        }
        return orphans.contains { noteKey, found in
            let orphanFolder = (noteKey as NSString).deletingLastPathComponent
            return found.values.contains { path in
                NoteFilePaths.identityKey(ofCanonicalPath: (orphanFolder as NSString).appendingPathComponent(path.removingPercentEncoding ?? path)) == fileKey
            }
        }
    }

    package nonisolated static func rebase(_ landed: URL, created: Bool, into note: URL, discardingOriginal: Bool) throws -> NoteAttachments.Placement {
        let folder = note.deletingLastPathComponent()
        do {
            let placed = try NoteAttachments.placeFile(landed, into: note)
            let target = folder.appendingPathComponent(placed.path.removingPercentEncoding ?? placed.path)
            if NoteFilePaths.key(for: target) == NoteFilePaths.key(for: landed) { return NoteAttachments.Placement(path: placed.path, created: created) }
            if discardingOriginal { try? FileManager.default.removeItem(at: landed) }
            return placed
        } catch {
            guard NoteFilePaths.itemExists(landed), let relative = NoteFilePaths.relativePath(from: folder, to: landed) else { throw error }
            return NoteAttachments.Placement(path: relative, created: created)
        }
    }

    private func movedNote(of session: NotePageSession, from note: URL) -> URL? {
        guard let current = files.openSessions.first(where: { $0.page === session })?.url,
              NoteFilePaths.key(for: current.deletingLastPathComponent()) != NoteFilePaths.key(for: note.deletingLastPathComponent())
        else { return nil }
        return current
    }

    package func adoptOrphans(of note: URL, in session: NotePageSession) {
        guard !orphans.isEmpty, let found = orphans.removeValue(forKey: NoteFilePaths.key(for: note)) else { return }
        let folder = note.deletingLastPathComponent()
        land(found.filter { NoteFilePaths.itemExists(folder.appendingPathComponent($0.value.removingPercentEncoding ?? $0.value)) }, in: session)
    }

    private func land(_ replacements: [String: String], in session: NotePageSession) {
        guard !replacements.isEmpty else { return }
        let ledger = ledger(for: session)
        ledger.landed.merge(replacements) { $1 }
        Self.settle(replacements, in: session)
        heal(ledger)
    }

    private func heal(_ ledger: Ledger) {
        guard ledger.healer == nil, let session = ledger.session else { return }
        ledger.healer = session.changes.filter(\.isUndoRedo).sink { [weak ledger, clock = self.clock] _ in
            _ = clock.schedule(after: 0) { [weak ledger] in
                guard let ledger, let session = ledger.session else { return }
                Self.settle(ledger.landed, in: session)
            }
        }
    }

    private func existingLedger(for session: NotePageSession) -> Ledger? {
        guard let ledger = ledgers[ObjectIdentifier(session)], ledger.session === session else { return nil }
        return ledger
    }

    private func ledger(for session: NotePageSession) -> Ledger {
        if let existing = existingLedger(for: session) { return existing }
        let ledger = Ledger(session)
        ledgers[ObjectIdentifier(session)] = ledger
        return ledger
    }

    private func liveSession(_ origin: NotePageSession?, note: URL) -> NotePageSession? {
        if let origin, files.openSessions.contains(where: { $0.page === origin }) { return origin }
        return files.session(for: note)?.page
    }

    package static func settle(_ replacements: [String: String], in session: NotePageSession) {
        guard !replacements.isEmpty else { return }
        let page = session.page
        for id in page.documentOrder(includingCollapsed: true) {
            guard let block = page.block(id), block.kind.isMedia, let source = block.props.source,
                  let path = replacements[source] else { continue }
            session.updateBlockMetadata(id, kind: .structure) { block in
                if block.props.source == source { block.props.source = path }
            }
        }
        session.updateSettingsMetadata { settings in
            if let source = settings.cover?.source, let path = replacements[source] { settings.cover?.source = path }
            if let icon = settings.icon, let path = replacements[icon] { settings.icon = path }
        }
    }
}
