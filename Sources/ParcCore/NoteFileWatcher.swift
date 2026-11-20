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

    func start() {
        let shouldPresent = lock.withLock { () -> Bool in
            defer { isPresenting = true }
            return !isPresenting
        }
        if shouldPresent { NSFileCoordinator.addFilePresenter(self) }
        rearm()
    }

    func stop() {
        let wasPresenting = lock.withLock { () -> Bool in
            defer { isPresenting = false }
            return isPresenting
        }
        if wasPresenting { NSFileCoordinator.removeFilePresenter(self) }
        sourceQueue.async { [self] in
            source?.cancel()
            source = nil
        }
    }

    func update(url next: URL) {
        lock.withLock { url = next }
        rearm()
    }

    func rearm() {
        sourceQueue.async { [self] in
            source?.cancel()
            source = nil
            let (path, active) = lock.withLock { (url.path, isPresenting) }
            guard active else { return }
            var descriptor = open(path, O_EVTONLY)
            let watchingFolder = descriptor < 0
            if watchingFolder { descriptor = open((path as NSString).deletingLastPathComponent, O_EVTONLY) }
            guard descriptor >= 0 else { return }
            var info = stat()
            let identity = fstat(descriptor, &info) == 0
                ? WatchedIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino), isFolder: watchingFolder) : nil
            if let previous = watchedIdentity, previous != identity { events(.changed) }
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
            watched.resume()
            let opened = info
            sourceQueue.asyncAfter(deadline: .now() + Self.registrationGrace) { [weak self, weak watched] in
                guard let self, let watched, watched === self.source else { return }
                if Self.differs(path: path, from: opened, watchingFolder: watchingFolder) { self.events(.changed) }
            }
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
            watched.cancel()
            source = nil
            events(.relocated(current))
        } else {
            events(.changed)
        }
    }

    private func receivedInFolder(_ mask: DispatchSource.FileSystemEvent, from watched: DispatchSourceFileSystemObject) {
        guard watched === source else { return }
        if mask.contains(.delete) || mask.contains(.rename) || mask.contains(.revoke) {
            watched.cancel()
            source = nil
        }
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

final class NoteFileFolderWatcher {
    private final class Sink: @unchecked Sendable {
        let handler: @Sendable (Set<String>, Bool) -> Void
        init(handler: @escaping @Sendable (Set<String>, Bool) -> Void) { self.handler = handler }
    }

    private let stream: FSEventStreamRef

    init?(folder: URL, latency: TimeInterval = 0.25, handler: @escaping @Sendable (Set<String>, Bool) -> Void) {
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
            for index in 0..<count where flags[index] & rescan != 0 { broad = true }
            Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue().handler(Set(names), broad)
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
