import Foundation

enum NoteFileWatchEvent: Sendable, Equatable {
    case changed
    case moved(URL)
    case relocated(String?)
    case deleted
}

final class NoteFileWatcher: NSObject, NSFilePresenter, @unchecked Sendable {
    private struct WatchedIdentity: Equatable {
        var device: UInt64
        var inode: UInt64
        var isFolder: Bool
    }

    typealias SaveRequest = @Sendable (@escaping @Sendable (Error?) -> Void) -> Void

    let presentedItemOperationQueue: OperationQueue
    private let lock = NSLock()
    private var url: URL
    private var isPresenting = false
    private var source: DispatchSourceFileSystemObject?
    private var watchedIdentity: WatchedIdentity?
    private var watchedFile: Int32?
    private var relocatedPath: String?
    private let sourceQueue = DispatchQueue(label: "org.parc.notes.file-watch")
    private let events: @Sendable (NoteFileWatchEvent) -> Void
    private let saveRequest: SaveRequest

    init(url: URL, events: @escaping @Sendable (NoteFileWatchEvent) -> Void, saveRequest: @escaping SaveRequest) {
        self.url = url
        self.events = events
        self.saveRequest = saveRequest
        presentedItemOperationQueue = OperationQueue()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        presentedItemOperationQueue.qualityOfService = .userInitiated
        super.init()
    }

    var presentedItemURL: URL? { lock.withLock { url } }

    func start(seen: NoteFileSighting? = nil) {
        let shouldPresent = lock.withLock { () -> Bool in
            defer { isPresenting = true }
            return !isPresenting
        }
        if shouldPresent { NSFileCoordinator.addFilePresenter(self) }
        sourceQueue.sync { arm(seen: seen) }
    }

    func stop() {
        let wasPresenting = lock.withLock { () -> Bool in
            defer { isPresenting = false }
            return isPresenting
        }
        if wasPresenting { NSFileCoordinator.removeFilePresenter(self) }
        sourceQueue.async { [self] in disarm() }
    }

    func update(url next: URL) {
        lock.withLock { url = next }
        rearm()
    }

    func rearm(seen: NoteFileSighting? = nil) {
        sourceQueue.async { [self] in arm(seen: seen) }
    }

    func movedPath() -> String? {
        sourceQueue.sync { relocatedPath ?? watchedFile.flatMap(Self.currentPath(of:)) }
    }

    private func disarm() {
        source?.cancel()
        source = nil
        watchedFile = nil
    }

    private func arm(seen: NoteFileSighting?) {
        disarm()
        relocatedPath = nil
        let (path, active) = lock.withLock { (url.path, isPresenting) }
        guard active else { return }
        var descriptor = open(path, O_EVTONLY | O_CLOEXEC)
        let watchingFolder = descriptor < 0
        if watchingFolder { descriptor = open((path as NSString).deletingLastPathComponent, O_EVTONLY | O_CLOEXEC) }
        guard descriptor >= 0 else {
            if let seen, seen != .absent { events(.changed) }
            return
        }
        var info = stat()
        let described = fstat(descriptor, &info) == 0
        let identity = described ? WatchedIdentity(device: UInt64(truncatingIfNeeded: info.st_dev), inode: UInt64(info.st_ino), isFolder: watchingFolder) : nil
        let sighting: NoteFileSighting? = watchingFolder ? .absent : (described ? .file(NoteFileStamp(info)) : nil)
        if let seen {
            if sighting != seen { events(.changed) }
        } else if let previous = watchedIdentity, previous != identity {
            events(.changed)
        }
        watchedIdentity = identity
        let watched = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke, .link],
            queue: sourceQueue)
        watched.setEventHandler { [weak self, weak watched] in
            guard let self, let watched else { return }
            if watchingFolder { self.receivedInFolder(watched.data, from: watched) } else {
                self.received(watched.data, descriptor: descriptor, from: watched)
            }
        }
        watched.setCancelHandler { close(descriptor) }
        source = watched
        if !watchingFolder { watchedFile = descriptor }
        watched.resume()
        let opened = info
        sourceQueue.asyncAfter(deadline: .now() + Self.registrationGrace) { [weak self, weak watched] in
            guard let self, let watched, watched === self.source else { return }
            if Self.differs(path: path, from: opened, watchingFolder: watchingFolder) { self.events(.changed) }
        }
    }

    private static let registrationGrace: TimeInterval = 0.05

    private static func differs(path: String, from opened: stat, watchingFolder: Bool) -> Bool {
        var current = stat()
        let exists = stat(path, &current) == 0
        if watchingFolder { return exists }
        guard exists else { return true }
        return current.st_dev != opened.st_dev || current.st_ino != opened.st_ino || current.st_size != opened.st_size
            || current.st_mtimespec.tv_sec != opened.st_mtimespec.tv_sec || current.st_mtimespec.tv_nsec != opened.st_mtimespec.tv_nsec
    }

    private func received(_ mask: DispatchSource.FileSystemEvent, descriptor: Int32, from watched: DispatchSourceFileSystemObject) {
        guard watched === source else { return }
        if mask.contains(.rename) || mask.contains(.delete) || mask.contains(.revoke) {
            let current = mask.contains(.rename) ? Self.currentPath(of: descriptor) : nil
            disarm()
            relocatedPath = current
            events(.relocated(current))
        } else {
            events(.changed)
        }
    }

    private func receivedInFolder(_ mask: DispatchSource.FileSystemEvent, from watched: DispatchSourceFileSystemObject) {
        guard watched === source else { return }
        if mask.contains(.delete) || mask.contains(.rename) || mask.contains(.revoke) { disarm() }
        events(.changed)
    }

    private static func currentPath(of descriptor: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) != -1 else { return nil }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    func presentedItemDidChange() { events(.changed) }

    func presentedItemDidMove(to newURL: URL) {
        lock.withLock { url = newURL }
        events(.moved(newURL))
    }

    func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable (Error?) -> Void) {
        events(.deleted)
        completionHandler(nil)
    }

    func savePresentedItemChanges(completionHandler: @escaping @Sendable (Error?) -> Void) {
        saveRequest(completionHandler)
    }
}

struct NoteFolderEvent: Hashable, Sendable {
    var path: String
    var isFile: Bool

    init(path: String, isFile: Bool = true) {
        self.path = path
        self.isFile = isFile
    }

    init(path: String, flags: FSEventStreamEventFlags) {
        self.path = path
        let file = FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile | kFSEventStreamEventFlagItemIsSymlink
            | kFSEventStreamEventFlagItemIsHardlink | kFSEventStreamEventFlagItemIsLastHardlink)
        let folder = FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir)
        isFile = flags & file != 0 && flags & folder == 0
    }
}

final class NoteFileFolderWatcher {
    private final class Sink: @unchecked Sendable {
        let handler: @Sendable ([NoteFolderEvent], Bool) -> Void
        init(handler: @escaping @Sendable ([NoteFolderEvent], Bool) -> Void) { self.handler = handler }
    }

    private let stream: FSEventStreamRef

    init?(folder: URL, latency: TimeInterval = 0.25, handler: @escaping @Sendable ([NoteFolderEvent], Bool) -> Void) {
        let sink = Sink(handler: handler)
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(sink).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                return UnsafeRawPointer(Unmanaged<Sink>.fromOpaque(info).retain().toOpaque())
            },
            release: { info in if let info { Unmanaged<Sink>.fromOpaque(info).release() } },
            copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info,
                  let names = Unmanaged<CFArray>.fromOpaque(UnsafeRawPointer(paths)).takeUnretainedValue() as NSArray as? [String]
            else { return }
            let rescan = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagEventIdsWrapped)
            var broad = false
            var events: [NoteFolderEvent] = []
            for index in 0..<min(count, names.count) {
                if flags[index] & rescan != 0 { broad = true }
                events.append(NoteFolderEvent(path: names[index], flags: flags[index]))
            }
            Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue().handler(events, broad)
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot
            | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(nil, callback, &context, [folder.path] as CFArray,
                                                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return nil }
        stream = created
        FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "org.parc.notes.folder-watch", qos: .utility))
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
    }

    deinit {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
