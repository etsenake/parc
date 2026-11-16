import AppKit
import Combine
import CoreServices
import Darwin
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

struct ExternalMediaFile: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable { case image, movie }
    struct Revision: Equatable, Hashable, Sendable {
        let device: Int32; let inode: UInt64; let size: Int64
        let modified: Int; let modifiedNanos: Int; let changed: Int; let changedNanos: Int
        init(_ value: stat) {
            device = value.st_dev; inode = value.st_ino; size = value.st_size
            modified = value.st_mtimespec.tv_sec; modifiedNanos = value.st_mtimespec.tv_nsec
            changed = value.st_ctimespec.tv_sec; changedNanos = value.st_ctimespec.tv_nsec
        }
    }
    let url: URL
    let folder: URL
    let revision: Revision
    let kind: Kind
    let isScreenshot: Bool
    let isScreenRecording: Bool
    let isLocal: Bool
    var id: String { url.path }
    var title: String { url.lastPathComponent }
    var date: Date { Date(timeIntervalSince1970: Double(revision.modified)) }
    var detail: String { !isLocal ? "Download in Finder to preview" : isScreenshot ? "Screenshot" : kind == .movie ? "Video" : "Image" }
}

struct ExternalMediaFolder: Equatable, Identifiable, Sendable {
    enum Access: Equatable, Sendable { case available, disabled, unavailable(String) }
    let url: URL
    let name: String
    let access: Access
    var id: String { url.path }
}

enum ExternalMediaFailure: LocalizedError {
    case changed, unavailable, invalidConfiguration, sameFile, tooLarge
    var errorDescription: String? {
        switch self {
        case .changed: return "This file or its folder access changed. Refresh Media and try again."
        case .unavailable: return "This file is not available locally. Download it in Finder, then refresh Media."
        case .invalidConfiguration: return "Media folder preferences could not be read. The existing preferences and original files have been preserved."
        case .sameFile: return "Choose another location to keep the original file unchanged."
        case .tooLarge: return "This image is too large to copy as image data. Use Copy File or Save a Copy instead."
        }
    }
}

final class ExternalMediaAccess: @unchecked Sendable {
    let url: URL
    private let scoped: Bool
    init(url: URL, scoped: Bool) { self.url = url; self.scoped = scoped }
    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
}

protocol ExternalMediaCloudObservation: AnyObject, Sendable {
    func present(_ folders: Set<String>)
}

struct ExternalMediaCloud: Sendable {
    let isSynced: @Sendable (URL) -> Bool
    let isLocal: @Sendable (String, UInt32) -> Bool
    let observe: @Sendable (@escaping @Sendable (Set<String>) -> Void) -> any ExternalMediaCloudObservation
    static let system = ExternalMediaCloud(
        isSynced: { (try? $0.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true },
        isLocal: { _, flags in flags & UInt32(SF_DATALESS) == 0 },
        observe: { ExternalMediaCloudStatus(handler: $0) })
}

final class ExternalMediaCloudStatus: ExternalMediaCloudObservation, @unchecked Sendable {
    private final class Presenter: NSObject, NSFilePresenter, @unchecked Sendable {
        let presentedItemURL: URL?
        let presentedItemOperationQueue: OperationQueue
        let observedPresentedItemUbiquityAttributes: Set<URLResourceKey> = [.ubiquitousItemDownloadingStatusKey]
        private let changed: @Sendable (URL) -> Void
        private let evicted: @Sendable (Presenter) -> Void
        init(folder: URL, queue: OperationQueue, changed: @escaping @Sendable (URL) -> Void, evicted: @escaping @Sendable (Presenter) -> Void) {
            presentedItemURL = folder; presentedItemOperationQueue = queue; self.changed = changed; self.evicted = evicted
        }
        func presentedSubitemDidChange(at url: URL) { changed(url) }
        func accommodatePresentedItemEviction(completionHandler: @escaping @Sendable (Error?) -> Void) {
            NSFileCoordinator.removeFilePresenter(self); evicted(self); completionHandler(nil)
        }
    }
    private let handler: @Sendable (Set<String>) -> Void
    private let queue = DispatchQueue(label: "org.parc.media-cloud-status")
    private let callbacks = OperationQueue()
    private var presenters: [String: Presenter] = [:]
    private var changed = Set<String>()
    init(handler: @escaping @Sendable (Set<String>) -> Void) {
        self.handler = handler; callbacks.maxConcurrentOperationCount = 1; callbacks.qualityOfService = .utility
    }
    deinit {
        let retired = Array(presenters.values)
        queue.async { retired.forEach { NSFileCoordinator.removeFilePresenter($0) } }
    }
    func present(_ folders: Set<String>) {
        queue.async { [self] in
            for (folder, presenter) in presenters where !folders.contains(folder) {
                NSFileCoordinator.removeFilePresenter(presenter); presenters[folder] = nil
            }
            for folder in folders where presenters[folder] == nil {
                let aliases = Set([folder] + [Self.resolved(folder)].compactMap { $0 })
                let presenter = Presenter(folder: URL(fileURLWithPath: folder, isDirectory: true), queue: callbacks,
                                          changed: { [weak self] url in if let file = Self.mediaFile(url, in: folder, aliases: aliases) { self?.note(file) } },
                                          evicted: { [weak self] presenter in self?.retire(presenter, folder: folder) })
                NSFileCoordinator.addFilePresenter(presenter); presenters[folder] = presenter
            }
        }
    }
    private static func mediaFile(_ url: URL, in folder: String, aliases: Set<String>) -> String? {
        let name = url.lastPathComponent, parent = url.deletingLastPathComponent().path
        guard ExternalMediaDisk.isMedia(name), aliases.contains(parent) || resolved(parent).map(aliases.contains) == true else { return nil }
        return (folder as NSString).appendingPathComponent(name)
    }
    private static func resolved(_ path: String) -> String? {
        guard let real = realpath(path, nil) else { return nil }
        defer { free(real) }
        return String(cString: real)
    }
    private func retire(_ presenter: Presenter, folder: String) {
        queue.async { [self] in if presenters[folder] === presenter { presenters[folder] = nil } }
    }
    private func note(_ path: String) {
        queue.async { [weak self] in
            guard let self, self.changed.insert(path).inserted, self.changed.count == 1 else { return }
            self.queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, !self.changed.isEmpty else { return }
                let batch = self.changed; self.changed = []; self.handler(batch)
            }
        }
    }
}

private final class ExternalMediaPreferenceObserver: NSObject {
    private let defaults: UserDefaults
    private let key: String
    private let changed: @Sendable () -> Void
    init(_ defaults: UserDefaults, key: String, changed: @escaping @Sendable () -> Void) {
        self.defaults = defaults; self.key = key; self.changed = changed
        super.init()
        defaults.addObserver(self, forKeyPath: key, options: [], context: nil)
    }
    deinit { defaults.removeObserver(self, forKeyPath: key) }
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        changed()
    }
}

@MainActor
final class ExternalMediaLibrary: ObservableObject {
    private final class Weak { weak var value: ExternalMediaLibrary?; init(_ value: ExternalMediaLibrary) { self.value = value } }
    private static var owners: [String: Weak] = [:]
    static func shared(directory: URL) -> ExternalMediaLibrary {
        let key = directory.standardizedFileURL.path
        if let existing = owners[key]?.value { return existing }
        owners = owners.filter { $0.value.value != nil }
        let value = ExternalMediaLibrary(directory: directory); owners[key] = Weak(value); return value
    }
    @Published private(set) var items: [ExternalMediaFile] = []
    @Published private(set) var folders: [ExternalMediaFolder] = []
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false
    private(set) var revision: UInt64 = 0
    private var index: [String: ExternalMediaFile] = [:]
    private var appliedVersion: UInt64?
    private let disk: ExternalMediaDisk
    private let systemFolders: (() -> [URL])
    private var clients = Set<UUID>()
    private var watcher: ExternalMediaWatcher?
    private var watchedRoots: [String]?
    private var watchedAliases: [String: String]?
    private var watchSession: UInt64 = 0
    private var folderAccess: [ExternalMediaAccess] = []
    private var safetyTimer: DispatchSourceTimer?
    private var refreshTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var rescanPending = false
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private let cloud: ExternalMediaCloud
    private var cloudStatus: (any ExternalMediaCloudObservation)?
    private var cloudSession: UInt64 = 0
    private var settleTask: Task<Void, Never>?
    private let screenshotPreferences: UserDefaults?
    private var screenshotObserver: ExternalMediaPreferenceObserver?
    nonisolated static let screenshotDomain = "com.apple.screencapture"
    init(directory: URL, preferencesAreEphemeral: Bool = false, systemFolders: @escaping () -> [URL] = ExternalMediaLibrary.defaultFolders,
         cloud: ExternalMediaCloud = .system, screenshotPreferences: UserDefaults? = UserDefaults(suiteName: ExternalMediaLibrary.screenshotDomain)) {
        self.systemFolders = systemFolders; self.cloud = cloud; self.screenshotPreferences = screenshotPreferences
        disk = ExternalMediaDisk(directory: directory, preferencesAreEphemeral: preferencesAreEphemeral, cloud: cloud)
    }
    deinit {
        refreshTask?.cancel(); updateTask?.cancel(); settleTask?.cancel(); safetyTimer?.cancel()
        observers.forEach { $0.center.removeObserver($0.token) }
    }
    nonisolated static func defaultFolders() -> [URL] {
        let manager = FileManager.default
        let desktop = manager.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let setting = UserDefaults(suiteName: screenshotDomain)?.string(forKey: "location")
        let screenshots = setting.flatMap { path -> URL? in
            let expanded = (path as NSString).expandingTildeInPath
            return expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded, isDirectory: true) : nil
        } ?? desktop
        return [manager.urls(for: .downloadsDirectory, in: .userDomainMask).first!, desktop,
                manager.urls(for: .documentDirectory, in: .userDomainMask).first!, screenshots]
    }
    func activate(_ client: UUID) {
        guard clients.insert(client).inserted else { return }
        if observers.isEmpty {
            let center = NotificationCenter.default, workspace = NSWorkspace.shared.notificationCenter
            observers.append((center, center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reconcile() }
            }))
            for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
                observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    let volume = (note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.standardizedFileURL.path
                    MainActor.assumeIsolated { self?.volumeChanged(volume) }
                }))
            }
            screenshotObserver = screenshotPreferences.map {
                ExternalMediaPreferenceObserver($0, key: "location") { [weak self] in
                    Task { @MainActor [weak self] in self?.screenshotLocationChanged() }
                }
            }
        }
        if safetyTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(10))
            timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.reconcile() } }
            timer.resume(); safetyTimer = timer
        }
        startRefresh(announced: clients.count == 1)
    }
    func deactivate(_ client: UUID) {
        clients.remove(client)
        guard clients.isEmpty else { return }
        cancelRefresh(); updateTask?.cancel(); updateTask = nil; settleTask?.cancel(); settleTask = nil; stopWatching()
        safetyTimer?.cancel(); safetyTimer = nil
        observers.forEach { $0.center.removeObserver($0.token) }; observers = []; screenshotObserver = nil
        clear()
        if !folders.isEmpty { folders = [] }
        if isLoading { isLoading = false }
    }
    func refresh() { startRefresh(announced: true) }
    private func startRefresh(announced: Bool) {
        guard !clients.isEmpty else { return }
        generation &+= 1; let token = generation; let roots = systemFolders(); let mark = FSEventsGetCurrentEventId()
        refreshTask?.cancel(); rescanPending = false
        if announced, !isLoading { isLoading = true }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await self.disk.scan(systemFolders: roots)
                guard !Task.isCancelled, self.generation == token, !self.clients.isEmpty else { return }
                self.apply(snapshot, since: mark)
            } catch {
                guard !Task.isCancelled, self.generation == token else { return }
                let message = error.localizedDescription
                self.clear()
                if self.error != message { self.error = message }
                self.stopWatching()
            }
            self.refreshTask = nil
            if self.isLoading { self.isLoading = false }
            if self.rescanPending { self.startRefresh(announced: false) }
        }
    }
    private func requestRescan() {
        if refreshTask == nil { startRefresh(announced: false) } else { rescanPending = true }
    }
    private func reconcile() {
        guard !clients.isEmpty, refreshTask == nil else { return }
        guard watcher != nil else { startRefresh(announced: false); return }
        generation &+= 1; let token = generation; let roots = systemFolders(); let mark = FSEventsGetCurrentEventId()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = try? await self.disk.reconcile(systemFolders: roots)
            guard !Task.isCancelled, self.generation == token, !self.clients.isEmpty else { return }
            if let snapshot { self.apply(snapshot, since: mark) }
            self.refreshTask = nil
            if self.rescanPending { self.startRefresh(announced: false) }
        }
    }
    private func screenshotLocationChanged() {
        guard !clients.isEmpty else { return }
        if refreshTask == nil { reconcile() } else { rescanPending = true }
    }
    private func volumeChanged(_ volume: String?) {
        guard !clients.isEmpty else { return }
        guard let volume else { requestRescan(); return }
        let prefix = volume.hasSuffix("/") ? volume : volume + "/"
        if (watchedRoots ?? []).contains(where: { $0 == volume || $0.hasPrefix(prefix) }) { requestRescan() }
    }
    private func apply(_ snapshot: ExternalMediaDisk.Snapshot, since mark: FSEventStreamEventId) {
        publish(snapshot.catalog); observeCloud(snapshot.catalog.cloudFolders)
        if folders != snapshot.folders { folders = snapshot.folders }
        if error != snapshot.warning { error = snapshot.warning }
        watch(snapshot.watch, since: mark); folderAccess = snapshot.access
    }
    private func publish(_ catalog: ExternalMediaDisk.Catalog) {
        if let appliedVersion, catalog.version <= appliedVersion { return }
        appliedVersion = catalog.version; index = catalog.index
        observeCloud(catalog.cloudFolders)
        guard !(catalog.items.isEmpty && items.isEmpty) else { return }
        revision &+= 1; items = catalog.items
    }
    private func absorb(_ change: ExternalMediaDisk.Change) {
        if let catalog = change.catalog { publish(catalog) }
        guard let delay = change.settle, settleTask == nil else { return }
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.settleTask = nil
            guard !self.clients.isEmpty, let change = try? await self.disk.settle(), !self.clients.isEmpty else { return }
            self.absorb(change)
        }
    }
    private func clear() {
        appliedVersion = nil; index = [:]; stopCloud()
        if !items.isEmpty { revision &+= 1; items = [] }
    }
    private func observeCloud(_ folders: Set<String>) {
        guard !clients.isEmpty, !folders.isEmpty else { stopCloud(); return }
        if cloudStatus == nil {
            cloudSession &+= 1; let session = cloudSession
            cloudStatus = cloud.observe { [weak self] changed in
                Task { @MainActor [weak self] in self?.receiveCloud(changed, session: session) }
            }
        }
        cloudStatus?.present(folders)
    }
    private func stopCloud() {
        guard cloudStatus != nil else { return }
        cloudStatus = nil; cloudSession &+= 1
    }
    private func receiveCloud(_ paths: Set<String>, session: UInt64) {
        guard session == cloudSession, !clients.isEmpty else { return }
        let known = paths.filter { index[$0] != nil }
        if !known.isEmpty { reread(known) }
    }
    private func cancelRefresh() { generation &+= 1; refreshTask?.cancel(); refreshTask = nil; rescanPending = false }
    func contains(_ item: ExternalMediaFile) -> Bool { index[item.id] == item }
    func grant(_ url: URL) async throws {
        try await disk.grant(url); refresh()
    }
    func setEnabled(_ enabled: Bool, folder: URL) async throws {
        cancelRefresh(); stopWatching()
        defer { refresh() }
        publish(try await disk.setEnabled(enabled, folder: folder))
    }
    func hide(_ file: ExternalMediaFile) async throws { publish(try await disk.hide(file)) }
    func restoreHidden() async throws { try await disk.restoreHidden(); refresh() }
    func validate(_ file: ExternalMediaFile) async throws { try await disk.validate(file) }
    func acquire(_ file: ExternalMediaFile) async throws -> ExternalMediaAccess { try await disk.acquire(file) }
    func data(_ file: ExternalMediaFile) async throws -> Data { try await disk.data(file) }
    func thumbnail(_ file: ExternalMediaFile) async throws -> Data { try await disk.thumbnail(file) }
    func export(_ file: ExternalMediaFile, to url: URL) async throws { try await disk.export(file, to: url) }
    private func stopWatching() { watcher = nil; watchedRoots = nil; watchedAliases = nil; watchSession &+= 1; folderAccess = [] }
    private func watch(_ aliases: [String: String], since mark: FSEventStreamEventId) {
        let roots = Set(aliases.values).sorted()
        guard aliases != watchedAliases || (watcher == nil && !roots.isEmpty) else { return }
        watcher = nil; watchedRoots = roots; watchedAliases = aliases; watchSession &+= 1
        guard !roots.isEmpty else { return }
        let session = watchSession
        watcher = ExternalMediaWatcher(aliases: aliases, since: mark) { [weak self] batch in
            Task { @MainActor [weak self] in self?.receive(batch, session: session) }
        }
    }
    private func receive(_ batch: ExternalMediaWatcher.Batch, session: UInt64) {
        guard session == watchSession, !clients.isEmpty else { return }
        switch batch {
        case .rescan: requestRescan()
        case .paths(let paths): reread(paths)
        }
    }
    private func reread(_ paths: Set<String>) {
        updateTask = Task { [weak self] in
            guard let self, let change = try? await self.disk.update(paths: paths), !self.clients.isEmpty else { return }
            self.absorb(change)
        }
    }
}

final class ExternalMediaWatcher {
    enum Batch: Sendable { case rescan, paths(Set<String>) }
    private final class Sink {
        private let roots: [String: String]
        private let handler: @Sendable (Batch) -> Void
        init(aliases: [String: String], handler: @escaping @Sendable (Batch) -> Void) { roots = aliases; self.handler = handler }
        func receive(_ paths: [String], _ flags: UnsafeBufferPointer<FSEventStreamEventFlags>) {
            let dropped = FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped)
            let broad = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged
                | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount)
            let structural = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved
                | kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemChangeOwner | kFSEventStreamEventFlagItemInodeMetaMod)
            var changed = Set<String>()
            for (raw, flag) in zip(paths, flags) {
                let path = raw.count > 1 && raw.hasSuffix("/") ? String(raw.dropLast()) : raw
                if flag & dropped != 0 { handler(.rescan); return }
                if flag & broad != 0 {
                    if covers(path) { handler(.rescan); return }
                    continue
                }
                if roots[path] != nil {
                    if flag & structural != 0 { handler(.rescan); return }
                    continue
                }
                let name = (path as NSString).lastPathComponent
                guard let root = roots[(path as NSString).deletingLastPathComponent], ExternalMediaDisk.isMedia(name) else { continue }
                changed.insert((root as NSString).appendingPathComponent(name))
            }
            if !changed.isEmpty { handler(.paths(changed)) }
        }
        private func covers(_ path: String) -> Bool {
            path.isEmpty || path == "/" || roots.keys.contains { $0 == path || $0.hasPrefix(path + "/") }
        }
    }
    private let stream: FSEventStreamRef
    private let queue: DispatchQueue
    init?(aliases: [String: String], since: FSEventStreamEventId, handler: @escaping @Sendable (Batch) -> Void) {
        let roots = Set(aliases.values).sorted(), sink = Sink(aliases: aliases, handler: handler)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(sink).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                return UnsafeRawPointer(Unmanaged<Sink>.fromOpaque(info).retain().toOpaque())
            },
            release: { info in if let info { Unmanaged<Sink>.fromOpaque(info).release() } },
            copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info, let names = Unmanaged<CFArray>.fromOpaque(UnsafeRawPointer(paths)).takeUnretainedValue() as NSArray as? [String] else { return }
            Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue().receive(names, UnsafeBufferPointer(start: flags, count: count))
        }
        let options = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagUseCFTypes)
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, roots as CFArray, since, 0.3, options) else { return nil }
        let queue = DispatchQueue(label: "org.parc.media-folder-events")
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else { FSEventStreamInvalidate(stream); FSEventStreamRelease(stream); return nil }
        self.stream = stream; self.queue = queue
    }
    deinit {
        let stream = UncheckedStream(stream)
        queue.async { FSEventStreamStop(stream.value); FSEventStreamInvalidate(stream.value); FSEventStreamRelease(stream.value) }
    }
    private struct UncheckedStream: @unchecked Sendable { let value: FSEventStreamRef; init(_ value: FSEventStreamRef) { self.value = value } }
}

actor ExternalMediaDisk {
    struct Catalog: Sendable { let items: [ExternalMediaFile]; let index: [String: ExternalMediaFile]; let version: UInt64; let cloudFolders: Set<String> }
    struct Change: Sendable { let catalog: Catalog?; let settle: Duration? }
    static let settleDelay = Duration.seconds(1)
    struct Snapshot: Sendable {
        let catalog: Catalog
        let folders: [ExternalMediaFolder]; let warning: String?; let access: [ExternalMediaAccess]; let watch: [String: String]
    }
    private struct Grant: Codable { let path: String; var bookmark: Data?; var disabled: Bool }
    private struct Configuration: Codable { var version = 1; var grants: [Grant] = []; var hiddenPaths: Set<String> = [] }
    private let directory: URL
    private var configuration: Configuration?
    private let preferencesAreEphemeral: Bool
    private var current: [String: ExternalMediaFile] = [:]
    private var ordered: [ExternalMediaFile] = []
    private var version: UInt64 = 0
    private var scannedRoots: [String]?
    private var available: [String: URL] = [:]
    private var readable: [String: Bool] = [:]
    private var remote = false
    private let cloud: ExternalMediaCloud
    private var synced: Set<String> = []
    private var lastEvent: [String: ContinuousClock.Instant] = [:]
    private var settling: [String: ContinuousClock.Instant] = [:]
    init(directory: URL, preferencesAreEphemeral: Bool = false, cloud: ExternalMediaCloud = .system) {
        self.directory = directory; self.preferencesAreEphemeral = preferencesAreEphemeral; self.cloud = cloud
    }
    private var catalog: Catalog { Catalog(items: ordered, index: current, version: version, cloudFolders: synced) }
    private var manifest: URL { directory.appendingPathComponent("MediaFolders.json") }
    private func read() throws -> Configuration {
        if let configuration { return configuration }
        guard FileManager.default.fileExists(atPath: manifest.path) else { let empty = Configuration(); configuration = empty; return empty }
        guard let next = try? JSONDecoder().decode(Configuration.self, from: Data(contentsOf: manifest)), next.version == 1,
              Set(next.grants.map(\.path)).count == next.grants.count,
              next.grants.allSatisfy({ $0.path.hasPrefix("/") }) else { throw ExternalMediaFailure.invalidConfiguration }
        configuration = next; return next
    }
    private func commit(_ next: Configuration) throws {
        if preferencesAreEphemeral { configuration = next; return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: manifest, options: .atomic); configuration = next
    }
    func grant(_ selected: URL) throws {
        let scoped = selected.startAccessingSecurityScopedResource(); defer { if scoped { selected.stopAccessingSecurityScopedResource() } }
        let root = selected.standardizedFileURL.resolvingSymlinksInPath()
        guard try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw CocoaError(.fileReadUnsupportedScheme) }
        _ = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        let bookmark = try selected.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        var next = try read(); next.grants.removeAll { $0.path == root.path }
        next.grants.append(Grant(path: root.path, bookmark: bookmark, disabled: false)); try commit(next)
    }
    @discardableResult func setEnabled(_ enabled: Bool, folder: URL) throws -> Catalog {
        var next = try read(); let path = folder.standardizedFileURL.resolvingSymlinksInPath().path
        if let index = next.grants.firstIndex(where: { $0.path == path }) {
            next.grants[index].disabled = !enabled
            if !enabled { next.grants[index].bookmark = nil }
        } else { next.grants.append(Grant(path: path, bookmark: nil, disabled: !enabled)) }
        try commit(next); available[path] = nil
        let unsynced = synced.remove(path) != nil, kept = current.filter { $0.value.folder.path != path }
        if kept.count != current.count || unsynced { current = kept; ordered.removeAll { $0.folder.path == path }; version &+= 1 }
        return catalog
    }
    @discardableResult func hide(_ file: ExternalMediaFile) throws -> Catalog {
        let scope = try checkedAccess(file, requireLocal: false)
        defer { if scope.1 { scope.0.stopAccessingSecurityScopedResource() } }
        var next = try read(); next.hiddenPaths.insert(file.id); try commit(next)
        if current.removeValue(forKey: file.id) != nil { ordered.removeAll { $0.id == file.id }; version &+= 1 }
        return catalog
    }
    func restoreHidden() throws { var next = try read(); next.hiddenPaths = []; try commit(next) }
    private func access(_ root: URL, configuration: Configuration) throws -> (URL, Bool) {
        guard let grant = configuration.grants.first(where: { $0.path == root.path }) else { return (root, false) }
        guard !grant.disabled else { throw ExternalMediaFailure.changed }
        guard let bookmark = grant.bookmark else { return (root, false) }
        var stale = false
        let resolved = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale, resolved.standardizedFileURL.resolvingSymlinksInPath().path == root.path else { throw ExternalMediaFailure.changed }
        return (resolved, resolved.startAccessingSecurityScopedResource())
    }
    private static func roots(_ systemFolders: [URL], _ config: Configuration) -> [String] {
        Set((systemFolders + config.grants.map { URL(fileURLWithPath: $0.path, isDirectory: true) })
            .map { $0.standardizedFileURL.resolvingSymlinksInPath().path }).sorted()
    }
    func scan(systemFolders: [URL]) throws -> Snapshot {
        let config = try read()
        let roots = Self.roots(systemFolders, config)
        var files: [String: ExternalMediaFile] = [:], folders: [ExternalMediaFolder] = []; var skipped = 0
        var leases: [ExternalMediaAccess] = [], reached: [String: URL] = [:], probes: [String: Bool] = [:], aliases: [String: String] = [:], foundRemote = false
        var syncedRoots = Set<String>()
        for path in roots {
            try Task.checkCancellation()
            let root = URL(fileURLWithPath: path, isDirectory: true)
            if config.grants.contains(where: { $0.path == path && $0.disabled }) {
                folders.append(.init(url: root, name: root.lastPathComponent, access: .disabled)); continue
            }
            probes[path] = Self.isReadable(path); aliases[path] = path
            if let real = realpath(path, nil) { aliases[String(cString: real)] = path; free(real) }
            do {
                let (scope, scoped) = try access(root, configuration: config)
                let lease = ExternalMediaAccess(url: scope, scoped: scoped)
                defer { withExtendedLifetime(lease) {} }
                for name in try FileManager.default.contentsOfDirectory(atPath: path) where Self.isMedia(name) {
                    try Task.checkCancellation()
                    do { if let file = try describe(Self.url(name, in: root), folder: root), !config.hiddenPaths.contains(file.id) { files[file.id] = file } }
                    catch { skipped += 1 }
                }
                folders.append(.init(url: root, name: root.lastPathComponent, access: .available)); leases.append(lease); reached[path] = root
                if (try? root.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) == false { foundRemote = true }
                if cloud.isSynced(root) { syncedRoots.insert(path) }
            } catch is CancellationError { throw CancellationError() }
            catch { folders.append(.init(url: root, name: root.lastPathComponent, access: .unavailable(error.localizedDescription))) }
        }
        let resynced = syncedRoots != synced
        current = files; scannedRoots = roots; available = reached; readable = probes; remote = foundRemote; synced = syncedRoots; settling = [:]
        let sorted = files.values.sorted(by: Self.precedes)
        if sorted != ordered || resynced { ordered = sorted; version &+= 1 }
        return Snapshot(catalog: catalog, folders: folders,
                        warning: skipped == 0 ? nil : "\(skipped) file\(skipped == 1 ? " was" : "s were") unavailable while Media refreshed.", access: leases, watch: aliases)
    }
    func reconcile(systemFolders: [URL]) throws -> Snapshot? {
        let roots = Self.roots(systemFolders, try read())
        guard roots == scannedRoots, !remote, readable.allSatisfy({ Self.isReadable($0.key) == $0.value }) else { return try scan(systemFolders: systemFolders) }
        return nil
    }
    func update(paths: Set<String>) throws -> Change {
        let now = ContinuousClock.now
        lastEvent = lastEvent.filter { now - $0.value < Self.settleDelay }
        return try change(paths, at: now, coalescing: true)
    }
    func settle() throws -> Change {
        let now = ContinuousClock.now
        return try change(Set(settling.filter { now - $0.value >= Self.settleDelay }.keys), at: now, coalescing: false)
    }
    private func change(_ paths: Set<String>, at now: ContinuousClock.Instant, coalescing: Bool) throws -> Change {
        let config = try read()
        var replaced = Set<String>(), added: [ExternalMediaFile] = []
        for path in paths {
            let parent = (path as NSString).deletingLastPathComponent
            guard let root = available[parent] else { settling[path] = nil; continue }
            let name = (path as NSString).lastPathComponent, url = Self.url(name, in: root), key = url.path
            var next = config.hiddenPaths.contains(key) ? nil : try? describe(url, folder: root)
            if next != nil, Self.storedName(key) != name { next = nil }
            let previous = current[key]
            let recent = coalescing ? lastEvent.updateValue(now, forKey: key) : nil
            guard previous != next else { settling[key] = nil; continue }
            if recent != nil, let previous, let next, previous.isLocal == next.isLocal { settling[key] = now; continue }
            settling[key] = nil
            if previous != nil { replaced.insert(key) }
            current[key] = next
            if let next { added.append(next) }
        }
        let pending = settling.values.min().map { max(.zero, $0 + Self.settleDelay - now) }
        guard !replaced.isEmpty || !added.isEmpty else { return Change(catalog: nil, settle: pending) }
        var merged = replaced.isEmpty ? ordered : ordered.filter { !replaced.contains($0.id) }
        if added.count > 32 { merged = (merged + added).sorted(by: Self.precedes) }
        else {
            for file in added {
                var low = 0, high = merged.count
                while low < high { let middle = (low + high) / 2; if Self.precedes(merged[middle], file) { low = middle + 1 } else { high = middle } }
                merged.insert(file, at: low)
            }
        }
        ordered = merged; version &+= 1
        return Change(catalog: catalog, settle: pending)
    }
    static func precedes(_ a: ExternalMediaFile, _ b: ExternalMediaFile) -> Bool { a.date == b.date ? a.id < b.id : a.date > b.date }
    static func isMedia(_ name: String) -> Bool { mediaType(name) != nil }
    private static func mediaType(_ name: String) -> UTType? {
        let fileExtension = (name as NSString).pathExtension
        guard !name.hasPrefix("."), !fileExtension.lowercased().hasSuffix("download"),
              let type = UTType(filenameExtension: fileExtension), type.conforms(to: .image) || type.conforms(to: .movie) else { return nil }
        return type
    }
    private static func isReadable(_ path: String) -> Bool {
        guard let directory = opendir(path) else { return false }
        closedir(directory); return true
    }
    private static func storedName(_ path: String) -> String? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT); request.commonattr = attrgroup_t(ATTR_CMN_NAME)
        let header = MemoryLayout<UInt32>.size, capacity = header + MemoryLayout<attrreference_t>.size + Int(NAME_MAX) * 4 + 1
        var buffer = [UInt8](repeating: 0, count: capacity)
        guard getattrlist(path, &request, &buffer, capacity, UInt32(FSOPT_NOFOLLOW)) == 0 else { return nil }
        return buffer.withUnsafeBytes { raw -> String? in
            let reference = raw.loadUnaligned(fromByteOffset: header, as: attrreference_t.self)
            let start = header + Int(reference.attr_dataoffset), length = Int(reference.attr_length)
            guard length > 1, start + length <= raw.count else { return nil }
            return String(decoding: raw[start..<(start + length - 1)], as: UTF8.self)
        }
    }
    private static func url(_ name: String, in root: URL) -> URL { root.appendingPathComponent(name, isDirectory: false).standardizedFileURL }
    private func describe(_ url: URL, folder: URL) throws -> ExternalMediaFile? {
        guard let type = Self.mediaType(url.lastPathComponent) else { return nil }
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard (value.st_mode & S_IFMT) == S_IFREG, value.st_flags & UInt32(UF_HIDDEN) == 0 else { return nil }
        let screenshot = getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, XATTR_NOFOLLOW) >= 0
        let hasOrigin = getxattr(url.path, "com.apple.metadata:kMDItemWhereFroms", nil, 0, 0, XATTR_NOFOLLOW) >= 0
        let movie = type.conforms(to: .movie)
        return ExternalMediaFile(url: url.standardizedFileURL, folder: folder, revision: .init(value), kind: movie ? .movie : .image,
                                 isScreenshot: screenshot, isScreenRecording: movie && !hasOrigin, isLocal: cloud.isLocal(url.path, value.st_flags))
    }
    private func checkedAccess(_ file: ExternalMediaFile, requireLocal: Bool = true) throws -> (URL, Bool) {
        guard current[file.id] == file else { throw ExternalMediaFailure.changed }
        let scope = try access(file.folder, configuration: read())
        do {
            guard try describe(file.url, folder: file.folder) == file else { throw ExternalMediaFailure.changed }
            guard !requireLocal || file.isLocal else { throw ExternalMediaFailure.unavailable }
            return scope
        } catch { if scope.1 { scope.0.stopAccessingSecurityScopedResource() }; throw error }
    }
    func acquire(_ file: ExternalMediaFile) throws -> ExternalMediaAccess {
        let scope = try checkedAccess(file); return ExternalMediaAccess(url: scope.0, scoped: scope.1)
    }
    func validate(_ file: ExternalMediaFile) throws {
        let scope = try checkedAccess(file); if scope.1 { scope.0.stopAccessingSecurityScopedResource() }
    }
    private func openOriginal(_ file: ExternalMediaFile) throws -> Int32 {
        let descriptor = Darwin.open(file.url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var value = stat()
        guard fstat(descriptor, &value) == 0, ExternalMediaFile.Revision(value) == file.revision,
              value.st_flags & UInt32(SF_DATALESS) == 0 else { Darwin.close(descriptor); throw ExternalMediaFailure.changed }
        return descriptor
    }
    private func finishRead(_ descriptor: Int32, file: ExternalMediaFile) throws {
        var value = stat()
        guard fstat(descriptor, &value) == 0, ExternalMediaFile.Revision(value) == file.revision,
              try describe(file.url, folder: file.folder) == file else { throw ExternalMediaFailure.changed }
    }
    func data(_ file: ExternalMediaFile) throws -> Data {
        let scope = try checkedAccess(file); defer { if scope.1 { scope.0.stopAccessingSecurityScopedResource() } }
        guard file.revision.size <= 256 * 1024 * 1024 else { throw ExternalMediaFailure.tooLarge }
        let descriptor = try openOriginal(file)
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var bytes = Data()
        let maximum = Int(file.revision.size)
        while bytes.count <= maximum {
            let chunk = try handle.read(upToCount: min(1024 * 1024, maximum + 1 - bytes.count)) ?? Data()
            if chunk.isEmpty { break }; bytes.append(chunk)
        }
        guard bytes.count == maximum else { throw ExternalMediaFailure.changed }
        try finishRead(descriptor, file: file); try handle.close(); return bytes
    }
    func thumbnail(_ file: ExternalMediaFile) async throws -> Data {
        let scope = try checkedAccess(file); defer { if scope.1 { scope.0.stopAccessingSecurityScopedResource() } }
        let request = QLThumbnailGenerator.Request(fileAt: file.url, size: CGSize(width: 360, height: 360), scale: 1, representationTypes: .thumbnail)
        let operation = MediaLibraryThumbnailOperation(start: { completion in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
                guard let representation else { completion(.failure(error ?? CocoaError(.fileReadCorruptFile))); return }
                let result = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil) else { completion(.failure(CocoaError(.fileReadCorruptFile))); return }
                CGImageDestinationAddImage(destination, representation.cgImage, nil)
                guard CGImageDestinationFinalize(destination) else { completion(.failure(CocoaError(.fileReadCorruptFile))); return }
                completion(.success(result as Data))
            }
        }, stop: { QLThumbnailGenerator.shared.cancel(request) })
        let result = try await operation.value()
        try Task.checkCancellation(); try validate(file)
        return result
    }

    func export(_ file: ExternalMediaFile, to destination: URL) throws {
        let scope = try checkedAccess(file); defer { if scope.1 { scope.0.stopAccessingSecurityScopedResource() } }
        guard file.url.standardizedFileURL != destination.standardizedFileURL else { throw ExternalMediaFailure.sameFile }
        var target = stat()
        if stat(destination.path, &target) == 0, target.st_dev == file.revision.device, target.st_ino == file.revision.inode { throw ExternalMediaFailure.sameFile }
        let descriptor = try openOriginal(file)
        let source = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".parc-media-" + UUID().uuidString)
        let outputFD = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard outputFD >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let output = FileHandle(fileDescriptor: outputFD, closeOnDealloc: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var copied: Int64 = 0
        while copied <= file.revision.size {
            try Task.checkCancellation()
            let data = try source.read(upToCount: Int(min(1024 * 1024, file.revision.size - copied + 1))) ?? Data()
            if data.isEmpty { break }
            copied += Int64(data.count)
            guard copied <= file.revision.size else { throw ExternalMediaFailure.changed }
            try output.write(contentsOf: data)
        }
        guard copied == file.revision.size else { throw ExternalMediaFailure.changed }
        try finishRead(descriptor, file: file); try source.close(); try output.synchronize(); try output.close()
        guard Darwin.rename(temporary.path, destination.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
