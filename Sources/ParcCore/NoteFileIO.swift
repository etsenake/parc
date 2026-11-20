import Foundation

enum NoteFileWriteOutcome: Sendable {
    case written
    case unchanged
    case conflict(NoteFileContents)
    case failed(String)
}

enum NoteFileProbe: Sendable {
    case contents(NoteFileContents)
    case moved(URL)
    case missing
    case unreadable(NoteFileError)
}

enum NoteFileIO {
    static func read(_ url: URL, kind: NoteFileKind, presenter: NSFilePresenter? = nil,
                     withoutChanges: Bool = false) throws -> NoteFileContents {
        var coordinationError: NSError?
        var result: Result<NoteFileContents, NoteFileError> = .failure(.missing)
        NSFileCoordinator(filePresenter: presenter).coordinate(
            readingItemAt: url, options: withoutChanges ? [.withoutChanges] : [], error: &coordinationError) { actual in
            result = Result { try readNow(actual, kind: kind) }.mapError(mapped)
        }
        if let coordinationError { throw mapped(coordinationError) }
        return try result.get()
    }

    static func readNow(_ url: URL, kind: NoteFileKind) throws -> NoteFileContents {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if values?.isDirectory == true { throw NoteFileError.notANote }
        if let size = values?.fileSize, size > NoteFileText.maximumSize { throw NoteFileError.tooLarge }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw mapped(error) }
        if data.count > NoteFileText.maximumSize { throw NoteFileError.tooLarge }
        guard let contents = NoteFileText.decode(data, kind: kind) else {
            throw NoteFileError.unreadable("It doesn’t look like text.")
        }
        return contents
    }

    static func probe(_ url: URL, kind: NoteFileKind, movedPath: String?, presenter: NSFilePresenter?) -> NoteFileProbe {
        if NoteFilePaths.itemExists(url) {
            do { return .contents(try read(url, kind: kind, presenter: presenter, withoutChanges: true)) }
            catch NoteFileError.missing { return .missing }
            catch let error as NoteFileError { return .unreadable(error) }
            catch { return .unreadable(.unreadable(error.localizedDescription)) }
        }
        if let movedPath, movedPath != url.path, NoteFilePaths.itemExists(atPath: movedPath) {
            let moved = URL(fileURLWithPath: movedPath)
            if !NoteFilePaths.isInTrash(moved) { return .moved(moved) }
        }
        return .missing
    }

    static func write(_ data: Data, text: String, to url: URL, kind: NoteFileKind, expecting expected: String?,
                      force: Bool, presenter: NSFilePresenter?) -> NoteFileWriteOutcome {
        var coordinationError: NSError?
        var outcome = NoteFileWriteOutcome.failed("Parc couldn’t get to the file.")
        NSFileCoordinator(filePresenter: presenter).coordinate(
            writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            outcome = writeNow(data, text: text, to: target, kind: kind, expecting: expected, force: force)
        }
        if let coordinationError { return .failed(coordinationError.localizedDescription) }
        return outcome
    }

    static func writeNow(_ data: Data, text: String, to target: URL, kind: NoteFileKind, expecting expected: String?,
                         force: Bool) -> NoteFileWriteOutcome {
        let exists = NoteFilePaths.itemExists(target)
        if exists && !force {
            do {
                let current = try readNow(target, kind: kind)
                if current.text == text { return .unchanged }
                if current.text != expected { return .conflict(current) }
            } catch let error as NoteFileError where error != .missing {
                return .failed(error.localizedDescription)
            } catch {}
        }
        do {
            if NoteFilePaths.itemExists(target) {
                try replace(target, with: data)
            } else {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target, options: .atomic)
            }
            return .written
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func move(_ source: URL, to destination: URL, presenter: NSFilePresenter?) throws {
        var coordinationError: NSError?
        var moveError: Error?
        let coordinator = NSFileCoordinator(filePresenter: presenter)
        coordinator.coordinate(writingItemAt: source, options: .forMoving, writingItemAt: destination,
                               options: .forReplacing, error: &coordinationError) { from, to in
            do {
                try moveNow(from, to: to)
                coordinator.item(at: from, didMoveTo: to)
            } catch {
                moveError = error
            }
        }
        if let error = coordinationError ?? moveError { throw error }
    }

    static func moveNow(_ source: URL, to destination: URL) throws {
        let caseOnly = NoteFilePaths.itemExists(destination) && NoteFilePaths.isSameFile(source, destination)
        let result = caseOnly ? rename(source.path, destination.path)
            : renamex_np(source.path, destination.path, UInt32(RENAME_EXCL))
        guard result == 0 else {
            let code = errno
            if code == EEXIST { throw NoteFileError.nameTaken(destination.deletingPathExtension().lastPathComponent) }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    nonisolated(unsafe) static var trashMover: (URL) throws -> URL? = { url in
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }

    @discardableResult
    static func trash(_ url: URL, presenter: NSFilePresenter? = nil) throws -> URL? {
        var coordinationError: NSError?
        var trashError: Error?
        var resulting: URL?
        NSFileCoordinator(filePresenter: presenter).coordinate(
            writingItemAt: url, options: .forDeleting, error: &coordinationError) { target in
            do { resulting = try trashMover(target) } catch { trashError = error }
        }
        if let error = coordinationError ?? trashError { throw error }
        return resulting
    }

    private static func replace(_ target: URL, with data: Data) throws {
        let manager = FileManager.default
        let scratch = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
        defer { try? manager.removeItem(at: scratch) }
        let staged = scratch.appendingPathComponent(target.lastPathComponent)
        try data.write(to: staged)
        _ = try manager.replaceItemAt(target, withItemAt: staged, backupItemName: nil, options: [])
    }

    static func mapped(_ error: Error) -> NoteFileError {
        if let error = error as? NoteFileError { return error }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError: return .missing
            case NSFileReadNoPermissionError: return .unreadable("Parc doesn’t have permission to open it.")
            default: break
            }
        }
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT) { return .missing }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain, underlying.code == Int(ENOENT) { return .missing }
        return .unreadable(nsError.localizedDescription)
    }
}
