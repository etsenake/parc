import Foundation

struct NoteFileStamp: Hashable, Sendable {
    var device: UInt64
    var inode: UInt64
    var size: Int64
    var seconds: Int
    var nanoseconds: Int

    init(_ info: stat) {
        device = UInt64(truncatingIfNeeded: info.st_dev)
        inode = UInt64(info.st_ino)
        size = Int64(info.st_size)
        seconds = info.st_mtimespec.tv_sec
        nanoseconds = info.st_mtimespec.tv_nsec
    }

    init?(path: String) {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        self.init(info)
    }
}

enum NoteFileSighting: Hashable, Sendable {
    case file(NoteFileStamp)
    case absent
}

enum NoteFileWriteOutcome: Sendable {
    case written(NoteFileStamp?)
    case unchanged
    case conflict(NoteFileContents)
    case missing
    case failed(String)

    var succeeded: Bool {
        switch self {
        case .written, .unchanged: return true
        case .conflict, .missing, .failed: return false
        }
    }

    var error: NoteFileError? {
        switch self {
        case .written, .unchanged: return nil
        case .conflict: return .conflict
        case .missing: return .missing
        case .failed(let message): return .unwritable(message)
        }
    }
}

enum NoteFileProbe: Sendable {
    case contents(NoteFileContents, NoteFileStamp?)
    case moved(URL)
    case missing
    case unreadable(NoteFileError)
}

final class NoteFileDisk: @unchecked Sendable {
    struct Staged {
        var page: NotePage
        var kind: NoteFileKind
        var format: NoteFileFormat
        var url: URL
        var force: Bool
        var customEmoji: Set<String> = []
    }

    struct StagedWrite {
        var staged: Staged
        var text: String
        var format: NoteFileFormat
        var outcome: NoteFileWriteOutcome
    }

    private let lock = NSLock()
    private var known: String?
    private var generationCount = 0
    private var staged: Staged?

    init(text: String?) { known = text }

    var text: String? { lock.withLock { known } }

    var generation: Int { lock.withLock { generationCount } }

    func adopt(_ text: String?) {
        lock.withLock {
            known = text
            generationCount += 1
        }
    }

    func stage(_ save: Staged?) { lock.withLock { staged = save } }

    func write(_ data: Data, text: String, to url: URL, kind: NoteFileKind, force: Bool) -> NoteFileWriteOutcome {
        lock.withLock {
            let outcome = NoteFileIO.writeNow(data, text: text, to: url, kind: kind, expecting: known, force: force)
            if outcome.succeeded {
                known = text
                generationCount += 1
            }
            return outcome
        }
    }

    func writeStaged() -> StagedWrite? {
        lock.withLock {
            guard let save = staged else { return nil }
            let text = NoteFileSession.render(save.page, kind: save.kind, format: save.format, customEmoji: save.customEmoji)
            let encoded = NoteFileText.encode(text, format: save.format)
            let outcome = NoteFileIO.writeNow(encoded.data, text: text, to: save.url, kind: save.kind, expecting: known, force: save.force)
            if outcome.succeeded {
                known = text
                generationCount += 1
                staged = nil
            }
            return StagedWrite(staged: save, text: text, format: encoded.format, outcome: outcome)
        }
    }
}

package enum NoteFileIO {
    static func read(_ url: URL, kind: NoteFileKind, presenter: NSFilePresenter? = nil,
                     withoutChanges: Bool = false) throws -> NoteFileContents {
        try readStamped(url, kind: kind, presenter: presenter, withoutChanges: withoutChanges).contents
    }

    static func readStamped(_ url: URL, kind: NoteFileKind, presenter: NSFilePresenter? = nil,
                            withoutChanges: Bool = false) throws -> (contents: NoteFileContents, stamp: NoteFileStamp?) {
        var coordinationError: NSError?
        var result: Result<(contents: NoteFileContents, stamp: NoteFileStamp?), NoteFileError> = .failure(.missing)
        NSFileCoordinator(filePresenter: presenter).coordinate(
            readingItemAt: url, options: withoutChanges ? [.withoutChanges] : [], error: &coordinationError) { actual in
            result = Result { try readStampedNow(actual, kind: kind) }.mapError(mapped)
        }
        if let coordinationError { throw mapped(coordinationError) }
        return try result.get()
    }

    package static func readNow(_ url: URL, kind: NoteFileKind) throws -> NoteFileContents {
        try readStampedNow(url, kind: kind).contents
    }

    static func readStampedNow(_ url: URL, kind: NoteFileKind) throws -> (contents: NoteFileContents, stamp: NoteFileStamp?) {
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw mapped(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw mapped(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)) }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw NoteFileError.notANote }
        if info.st_size > NoteFileText.maximumSize { throw NoteFileError.tooLarge }
        let data: Data
        do { data = try handle.readToEnd() ?? Data() } catch { throw mapped(error) }
        if data.count > NoteFileText.maximumSize { throw NoteFileError.tooLarge }
        guard let contents = NoteFileText.decode(data, kind: kind) else {
            throw NoteFileError.unreadable("It doesn’t look like text.")
        }
        return (contents, NoteFileStamp(info))
    }

    static func probe(_ url: URL, kind: NoteFileKind, movedPath: String?, presenter: NSFilePresenter?) -> NoteFileProbe {
        if NoteFilePaths.itemExists(url) {
            do {
                let read = try readStamped(url, kind: kind, presenter: presenter, withoutChanges: true)
                return .contents(read.contents, read.stamp)
            }
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

    static func write(_ data: Data, text: String, to url: URL, kind: NoteFileKind, disk: NoteFileDisk,
                      force: Bool, presenter: NSFilePresenter?) -> NoteFileWriteOutcome {
        var coordinationError: NSError?
        var outcome = NoteFileWriteOutcome.failed("Parc couldn’t get to the file.")
        NSFileCoordinator(filePresenter: presenter).coordinate(
            writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            outcome = disk.write(data, text: text, to: target, kind: kind, force: force)
        }
        if let coordinationError { return .failed(coordinationError.localizedDescription) }
        return outcome
    }

    static func writeNow(_ data: Data, text: String, to target: URL, kind: NoteFileKind, expecting expected: String?,
                         force: Bool) -> NoteFileWriteOutcome {
        let exists = NoteFilePaths.itemExists(target)
        if !exists && expected != nil && !force { return .missing }
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
            return .written(NoteFileStamp(path: target.path))
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

    static func moveToTrash(_ url: URL) throws -> URL? {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }

    @discardableResult
    static func trash(_ url: URL, presenter: NSFilePresenter? = nil,
                              mover: (URL) throws -> URL? = NoteFileIO.moveToTrash) throws -> URL? {
        var coordinationError: NSError?
        var trashError: Error?
        var resulting: URL?
        NSFileCoordinator(filePresenter: presenter).coordinate(
            writingItemAt: url, options: .forDeleting, error: &coordinationError) { target in
            do { resulting = try mover(target) } catch { trashError = error }
        }
        if let error = coordinationError ?? trashError { throw error }
        return resulting
    }

    private static func replace(_ target: URL, with data: Data) throws {
        let manager = FileManager.default
        guard let scratch = try? manager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
        else {
            try data.write(to: target, options: .atomic)
            return
        }
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
        if nsError.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(nsError.code) {
            return .unreadable("Parc doesn’t have permission to open it.")
        }
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(EISDIR) { return .notANote }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain, underlying.code == Int(ENOENT) { return .missing }
        return .unreadable(nsError.localizedDescription)
    }
}
