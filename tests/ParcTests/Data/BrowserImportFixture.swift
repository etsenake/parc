import AppKit
import ParcCore
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import ParcOnboarding

struct RestrictedExtensionError: Error { let restriction: PCNativeExtensionRestriction }

final class BrowserImportWorkQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var work: [() -> Void] = []
    func add(_ item: @escaping () -> Void) { lock.lock(); work.append(item); lock.unlock() }
    func next() -> (() -> Void)? {
        lock.lock(); defer { lock.unlock() }
        return work.isEmpty ? nil : work.removeFirst()
    }
    var isEmpty: Bool { lock.lock(); defer { lock.unlock() }; return work.isEmpty }
}

@MainActor
final class BrowserImportEngineFake: BrowserImportNative {
    struct SourceRequest { let lease: PCNativeImportDiscovery; let complete: ([PCNativeImportSource]) -> Void }
    struct ProfileRequest {
        let source: PCNativeImportSource, lease: PCNativeImportDiscovery
        let complete: (PCNativeImportProfileResult) -> Void
    }
    struct ExportRequest {
        let directories: [URL], names: [String], lease: PCNativeImportDiscovery
        let complete: (PCNativeImportProfileResult) -> Void
    }
    struct BrowserRequest {
        let profile: PCNativeImportProfile, path: String, window: NSWindow
        let skipExistingCookies: Bool, categories: PCNativeImportCategories
        let progress: (PCNativeImportEvent) -> Void
    }
    struct PasswordRequest {
        let url: URL, path: String, window: NSWindow, lease: PCNativePasswordFileImportSession
        let complete: (PCNativePasswordFileImportResult) -> Void
    }
    struct ExtensionInstall {
        let requests: [PCNativeImportExtensionRequest], lease: PCNativeImportSession
        let complete: (PCNativeImportExtensionResult, [PCImportedExtensionFailure]) -> Void
        let background: ([PCImportedExtensionFailure]) -> Void
    }
    struct SetupChange { let kind: String, identifiers: Set<String>, path: String, complete: (Error?) -> Void }

    var sources: [SourceRequest] = [], profiles: [ProfileRequest] = [], exports: [ExportRequest] = []
    var browserRequests: [BrowserRequest] = []
    var browserCompletions: [(PCNativeImportResult) -> Void] = []
    var passwordRequests: [PasswordRequest] = []
    var extensionInstalls: [ExtensionInstall] = []
    var setupChanges: [SetupChange] = []
    var acceptsBrowserImport = true, rejectsPasswordImport = false, rejectsExtensionInstall = false
    private let work = BrowserImportWorkQueue()

    var imports: Int { browserRequests.count }

    func settle() { while let item = work.next() { item() } }
    var hasPendingWork: Bool { !work.isEmpty }

    func availableImportSources(completion: @escaping ([PCNativeImportSource]) -> Void) -> PCNativeImportDiscovery {
        let lease = ImportTestDiscovery() as! PCNativeImportDiscovery
        sources.append(.init(lease: lease, complete: completion))
        return lease
    }

    func loadImportSourceProfiles(_ source: PCNativeImportSource,
                                  completion: @escaping (PCNativeImportProfileResult) -> Void) -> PCNativeImportDiscovery {
        let lease = ImportTestDiscovery() as! PCNativeImportDiscovery
        profiles.append(.init(source: source, lease: lease, complete: completion))
        return lease
    }

    func loadSafariExportProfiles(_ directories: [URL], names: [String],
                                  completion: @escaping (PCNativeImportProfileResult) -> Void) -> PCNativeImportDiscovery {
        let lease = ImportTestDiscovery() as! PCNativeImportDiscovery
        exports.append(.init(directories: directories, names: names, lease: lease, complete: completion))
        return lease
    }

    func importBrowserData(from profile: PCNativeImportProfile, toProfilePath path: String, in window: NSWindow,
                           categories: PCNativeImportCategories, skipExistingCookies: Bool,
                           progress: @escaping (PCNativeImportEvent) -> Void,
                           completion: @escaping (PCNativeImportResult) -> Void) -> PCNativeImportSession? {
        browserRequests.append(.init(profile: profile, path: path, window: window,
            skipExistingCookies: skipExistingCookies, categories: categories, progress: progress))
        guard acceptsBrowserImport else { return nil }
        browserCompletions.append(completion)
        return ImportTestSession() as? PCNativeImportSession
    }

    func importPasswordFile(_ url: URL, toProfilePath path: String, in window: NSWindow,
                            completion: @escaping (PCNativePasswordFileImportResult) -> Void) -> PCNativePasswordFileImportSession? {
        guard !rejectsPasswordImport else { return nil }
        let lease = ImportTestPasswordSession() as! PCNativePasswordFileImportSession
        passwordRequests.append(.init(url: url, path: path, window: window, lease: lease, complete: completion))
        return lease
    }

    func installImportedExtensions(_ requests: [PCNativeImportExtensionRequest],
                                   completion: @escaping (PCNativeImportExtensionResult, [PCImportedExtensionFailure]) -> Void,
                                   backgroundFailures: @escaping ([PCImportedExtensionFailure]) -> Void) -> PCNativeImportSession? {
        guard !rejectsExtensionInstall else { return nil }
        let lease = ImportTestSession() as! PCNativeImportSession
        extensionInstalls.append(.init(requests: requests, lease: lease, complete: completion, background: backgroundFailures))
        return lease
    }

    func installICloudPasswordsExtension(toProfilePath path: String, completion: @escaping (Error?) -> Void) {
        setupChanges.append(.init(kind: "iCloud Passwords", identifiers: [], path: path, complete: completion))
    }

    func installSetupAdBlocker(toProfilePath path: String, completion: @escaping (Error?) -> Void) {
        setupChanges.append(.init(kind: "uBlock Origin", identifiers: [], path: path, complete: completion))
    }

    func removeSetupAdBlockers(_ identifiers: Set<String>, fromProfilePath path: String, completion: @escaping (Error?) -> Void) {
        setupChanges.append(.init(kind: "remove", identifiers: identifiers, path: path, complete: completion))
    }

    func extensionRestriction(for error: Error?) -> PCNativeExtensionRestriction {
        (error as? RestrictedExtensionError)?.restriction ?? .none
    }

    nonisolated func background(_ qos: DispatchQoS.QoSClass, _ work: @escaping @Sendable () -> Void) { self.work.add(work) }

    nonisolated func main(_ work: @escaping @Sendable @MainActor () -> Void) {
        self.work.add { MainActor.assumeIsolated { work() } }
    }

    func finishBrowser(_ outcome: PCNativeImportOutcome = .completed, bookmarks: [PCNativeImportedBookmark] = [],
                       warnings: [String] = [], error: NSError? = nil) {
        browserCompletions.removeFirst()(ImportFixture.result(outcome, bookmarks: bookmarks, warnings: warnings, error: error))
    }

    func finishAllBrowser() { while !browserCompletions.isEmpty { finishBrowser() } }
}

@MainActor
enum ImportFixture {
    static func source(_ identifier: String, _ url: URL) -> PCNativeImportSource {
        ImportTestSource(identifier: identifier, appURL: url) as! PCNativeImportSource
    }

    static func extensionItem(_ identifier: String = "extension", _ name: String = "Extension") -> PCNativeImportExtension {
        ImportTestExtension(identifier: identifier, displayName: name) as! PCNativeImportExtension
    }

    static func profile(_ identifier: String, _ categories: PCNativeImportCategories, _ access: PCNativeImportAccess = .complete,
                        name: String? = nil, directory: String? = nil,
                        extensions: [PCNativeImportExtension] = []) -> PCNativeImportProfile {
        ImportTestProfile(identifier: identifier, displayName: name ?? identifier, directoryName: directory ?? identifier,
                          categories: categories.rawValue, access: access.rawValue, extensions: extensions) as! PCNativeImportProfile
    }

    static func profiles(_ profiles: [PCNativeImportProfile], _ access: PCNativeImportAccess = .complete,
                         constraints: [String] = [], error: NSError? = nil) -> PCNativeImportProfileResult {
        ImportTestProfileResult(profiles: profiles, access: access.rawValue, constraints: constraints,
                                error: error) as! PCNativeImportProfileResult
    }

    static func bookmark(_ identifier: String = "bookmark", title: String = "Bookmark", url: String? = nil,
                         children: [PCNativeImportedBookmark] = []) -> PCNativeImportedBookmark {
        ImportTestBookmark(identifier: identifier, title: title, url: url.flatMap(URL.init(string:)),
                           children: children) as! PCNativeImportedBookmark
    }

    static func event(_ category: PCNativeImportCategories, _ phase: PCNativeImportPhase) -> PCNativeImportEvent {
        ImportTestEvent(message: nil, category: category.rawValue, phase: phase.rawValue) as! PCNativeImportEvent
    }

    static func result(_ outcome: PCNativeImportOutcome, bookmarks: [PCNativeImportedBookmark] = [],
                       warnings: [String] = [], error: NSError? = nil) -> PCNativeImportResult {
        ImportTestResult(outcome: outcome.rawValue, bookmarks: bookmarks, warnings: warnings, error: error) as! PCNativeImportResult
    }

    static func extensionResult(_ outcome: PCNativeImportOutcome, installed: Set<String> = [],
                                installing: Set<String> = []) -> PCNativeImportExtensionResult {
        ImportTestExtensionResult(outcome: outcome.rawValue, installed: installed,
                                  installing: installing) as! PCNativeImportExtensionResult
    }

    static func failure(_ name: String, identifier: String? = nil, path: String? = nil,
                        restriction: PCNativeExtensionRestriction = .none) -> PCImportedExtensionFailure {
        ImportTestExtensionFailure(name: name, identifier: identifier, profilePath: path,
                                   restriction: restriction.rawValue) as! PCImportedExtensionFailure
    }

    static func password(_ outcome: PCNativeImportOutcome, imported: UInt = 0, existing: UInt = 0, invalid: UInt = 0,
                         canRemove: Bool = false, error: NSError? = nil) -> PCNativePasswordFileImportResult {
        ImportTestPasswordResult(outcome: outcome.rawValue, imported: imported, existing: existing, invalid: invalid,
                                 canRemove: canRemove, error: error) as! PCNativePasswordFileImportResult
    }

    static func cancelled(_ lease: NSObject) -> Bool { ImportTestCancelled(lease) }
    static func requestSource(_ request: PCNativeImportExtensionRequest) -> PCNativeImportProfile {
        ImportTestRequestSource(request) as! PCNativeImportProfile
    }
    static func requestPath(_ request: PCNativeImportExtensionRequest) -> String { ImportTestRequestPath(request) }
    static func requestIDs(_ request: PCNativeImportExtensionRequest) -> Set<String> { ImportTestRequestIdentifiers(request) }
}

@MainActor
final class BrowserImportScene {
    let directory: URL
    let store: BrowserStore
    let destination: BrowserImportDestination
    let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
    let engine = BrowserImportEngineFake()
    var current = true
    private var coordinators: [BrowserImportCoordinator] = []

    init(now: (() -> Date)? = nil) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ParcImport-" + UUID().uuidString)
        let storeDirectory = directory.appendingPathComponent("Parc")
        store = try now.map { try BrowserStore(directory: storeDirectory, now: $0) } ?? BrowserStore(directory: storeDirectory)
        destination = BrowserImportDestination(spaceID: store.activeSpace.id, profileID: store.activeSpace.profileID)
        Self.clearNotices()
        SetupExtensionChanges.beginSetupRun()
    }

    static func clearNotices() {
        while ImportedExtensionFailures.take() != nil {}
        _ = ImportedBrowserDataFailures.take()
        ImportedExtensionFailures.clearFailed(ImportedExtensionFailures.failedIdentifiers)
        ImportedExtensionFailures.present = nil
        ImportedBrowserDataFailures.present = nil
    }

    static func run(now: (() -> Date)? = nil, _ body: (BrowserImportScene) throws -> Void) throws {
        let scene = try BrowserImportScene(now: now)
        defer { scene.finish() }
        try body(scene)
    }

    func finish() {
        coordinators.forEach { $0.cancel() }
        coordinators = []
        engine.settle()
        Self.clearNotices()
        try? FileManager.default.removeItem(at: directory)
    }

    func path(_ profileID: UUID) -> String { store.independentEngineProfilePath(for: profileID) }
    var originalPath: String { path(destination.profileID) }

    func app(_ name: String, _ bundleID: String) throws -> URL {
        let url = directory.appendingPathComponent("Apps/" + name + ".app")
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": bundleID,
            "CFBundleName": name, "CFBundlePackageType": "APPL"], format: .xml, options: 0)
        try plist.write(to: url.appendingPathComponent("Contents/Info.plist"))
        return url
    }

    func safari() throws -> PCNativeImportSource { ImportFixture.source("fresh Safari lease", try app("Fixture Safari", "com.apple.Safari")) }
    func impostor() throws -> PCNativeImportSource { ImportFixture.source("Safari", try app("Safari", "test.not-safari")) }
    func chrome() throws -> PCNativeImportSource { ImportFixture.source("com.google.Chrome", try app("Google Chrome", "com.google.Chrome")) }
    func firefox() -> PCNativeImportSource { ImportFixture.source("org.mozilla.firefox", directory.appendingPathComponent("Firefox.app")) }
    func zen() -> PCNativeImportSource { ImportFixture.source("app.zen-browser.zen", directory.appendingPathComponent("Zen.app")) }
    func arc() -> PCNativeImportSource {
        ImportFixture.source(BrowserImportCoordinator.arcBundleIdentifier, directory.appendingPathComponent("Arc", isDirectory: true))
    }

    func sidebarHome(arcSidebar: URL?, arcPreferences: URL?) -> URL {
        let home = directory.appendingPathComponent("Home-\(UUID().uuidString)", isDirectory: true)
        let files = FileManager.default
        for (source, target) in [(arcSidebar, ArcSidebarSnapshot.sidebarURL(home: home)),
                                 (arcPreferences, ArcSidebarSnapshot.preferencesURL(home: home))] {
            guard let source, files.fileExists(atPath: source.path) else { continue }
            try? files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? files.copyItem(at: source, to: target)
        }
        return home
    }

    func coordinator(store: BrowserStore? = nil, destination: BrowserImportDestination? = nil, onboarding: Bool = false,
                     iCloud: Bool = false, arcSidebar: URL? = nil, arcPreferences: URL? = nil,
                     exportRoot: URL? = nil) -> BrowserImportCoordinator {
        let coordinator = BrowserImportCoordinator(store: store ?? self.store, destination: destination ?? self.destination,
            window: window, onboarding: onboarding, supportsICloudPasswords: iCloud,
            sidebarHome: sidebarHome(arcSidebar: arcSidebar, arcPreferences: arcPreferences),
            safariExportRoot: exportRoot ?? directory.appendingPathComponent("ExportRoot"),
            native: engine, ownerIsCurrent: { [unowned self] in self.current })
        coordinators.append(coordinator)
        return coordinator
    }

    func discovered(_ coordinator: BrowserImportCoordinator, _ sources: [PCNativeImportSource]) {
        coordinator.discover()
        engine.sources.removeFirst().complete(sources)
    }

    func chosen(_ source: PCNativeImportSource, profiles result: PCNativeImportProfileResult, onboarding: Bool = false,
                iCloud: Bool = false, inline: Bool? = nil, exportRoot: URL? = nil,
                arcSidebar: URL? = nil, arcPreferences: URL? = nil,
                store: BrowserStore? = nil, destination: BrowserImportDestination? = nil) -> BrowserImportCoordinator {
        let coordinator = self.coordinator(store: store, destination: destination, onboarding: onboarding, iCloud: iCloud,
            arcSidebar: arcSidebar, arcPreferences: arcPreferences, exportRoot: exportRoot)
        discovered(coordinator, [source])
        if inline ?? onboarding { coordinator.selectSourceInline(source) } else { coordinator.select(source); coordinator.loadProfiles() }
        engine.profiles.removeFirst().complete(result)
        return coordinator
    }

    func started(_ source: PCNativeImportSource, _ profiles: [PCNativeImportProfile], onboarding: Bool = false,
                 iCloud: Bool = false) -> BrowserImportCoordinator {
        let coordinator = chosen(source, profiles: ImportFixture.profiles(profiles), onboarding: onboarding, iCloud: iCloud)
        coordinator.continueSourceInline()
        return coordinator
    }

    static func arcSidebar() throws -> URL {
        try #require(Bundle.module.url(forResource: "StorableSidebar", withExtension: "json", subdirectory: "ArcSidebar"))
    }
}
