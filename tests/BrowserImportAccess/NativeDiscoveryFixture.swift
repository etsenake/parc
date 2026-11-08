import AppKit

// Async boundary fixture for the actual app coordinator. No browser, importer,
// personal source, TCC access or native engine is loaded by these checks.
struct PCNativeImportCategories: OptionSet {
    let rawValue: UInt
    static let history = Self(rawValue: 1), bookmarks = Self(rawValue: 2), extensions = Self(rawValue: 32)
}
enum PCNativeImportAccess { case complete, restricted }
enum PCNativeImportOutcome { case completed, partial, cancelled, failed }
@MainActor final class PCNativeImportSource {
    let identifier: String, displayName: String, appURL: URL
    init(_ id: String, _ url: URL) { identifier = id; displayName = id; appURL = url }
}
@MainActor final class PCNativeImportExtension {
    let identifier: String
    let displayName: String
    init(identifier: String = "extension", displayName: String = "Extension") {
        self.identifier = identifier
        self.displayName = displayName
    }
}
@MainActor final class PCNativeImportProfile {
    let identifier: String, displayName: String, directoryName: String
    let supportedCategories: PCNativeImportCategories, access: PCNativeImportAccess
    var extensions: [PCNativeImportExtension] = []
    let constraints: [String] = []
    init(_ id: String, _ categories: PCNativeImportCategories, _ access: PCNativeImportAccess,
         name: String? = nil, directory: String? = nil) {
        identifier = id; displayName = name ?? id; directoryName = directory ?? id
        supportedCategories = categories; self.access = access
    }
}
@MainActor struct PCNativeImportProfileResult {
    var profiles: [PCNativeImportProfile]
    var access: PCNativeImportAccess
    var constraints: [String] = []
    var error: NSError?
}
@MainActor final class PCNativeImportedBookmark {
    let identifier: String, title: String
    let url: URL?
    let children: [PCNativeImportedBookmark]
    init(_ identifier: String = "bookmark", title: String = "Bookmark", url: URL? = nil,
         children: [PCNativeImportedBookmark] = []) {
        self.identifier = identifier; self.title = title; self.url = url; self.children = children
    }
}
@MainActor struct PCNativeImportEvent { let message: String? }
@MainActor struct PCNativeImportResult {
    let outcome: PCNativeImportOutcome, bookmarks: [PCNativeImportedBookmark], warnings: [String], error: NSError?
    var historyVisitCounts: [String: NSNumber] = [:]
}
@MainActor final class PCNativeImportDiscovery {
    private(set) var cancelled = false
    func cancel() { cancelled = true }
}
@MainActor final class PCNativeImportSession { func cancel() {} }
@MainActor enum PCNativeBrowserApplication {
    struct SourceRequest { let lease: PCNativeImportDiscovery; let complete: ([PCNativeImportSource]) -> Void }
    struct ProfileRequest {
        let source: PCNativeImportSource, lease: PCNativeImportDiscovery
        let complete: (PCNativeImportProfileResult) -> Void
    }
    static var sources: [SourceRequest] = [], profiles: [ProfileRequest] = []
    struct BrowserRequest {
        let profile: PCNativeImportProfile, path: String, window: NSWindow
        let skipExistingCookies: Bool, extensionIDs: Set<String>
    }
    static var browserRequests: [BrowserRequest] = []
    static var imports = 0
    static var acceptsBrowserImport = false
    static var browserCompletions: [(PCNativeImportResult) -> Void] = []
    struct PasswordRequest {
        let url: URL, path: String, window: NSWindow, lease: PCNativePasswordFileImportSession
        let complete: (PCNativePasswordFileImportResult) -> Void
    }
    static var passwordRequests: [PasswordRequest] = []
    static var rejectsPasswordImport = false
    static func importPasswordFile(_ url: URL, toProfilePath path: String, in window: NSWindow,
        completion: @escaping (PCNativePasswordFileImportResult) -> Void) -> PCNativePasswordFileImportSession? {
        guard !rejectsPasswordImport else { return nil }
        let lease = PCNativePasswordFileImportSession()
        passwordRequests.append(.init(url: url, path: path, window: window, lease: lease, complete: completion))
        return lease
    }
    static func availableImportSources(completion: @escaping ([PCNativeImportSource]) -> Void) -> PCNativeImportDiscovery {
        let lease = PCNativeImportDiscovery(); sources.append(.init(lease: lease, complete: completion)); return lease
    }
    static func loadImportSourceProfiles(_ source: PCNativeImportSource,
        completion: @escaping (PCNativeImportProfileResult) -> Void) -> PCNativeImportDiscovery {
        let lease = PCNativeImportDiscovery(); profiles.append(.init(source: source, lease: lease, complete: completion)); return lease
    }
    static func importBrowserData(from: PCNativeImportProfile, toProfilePath: String, in window: NSWindow,
        categories: PCNativeImportCategories, allowedExtensionIDs: Set<String>, skipExistingCookies: Bool,
        progress: @escaping (PCNativeImportEvent) -> Void,
        completion: @escaping (PCNativeImportResult) -> Void) -> PCNativeImportSession? {
        imports += 1
        browserRequests.append(.init(profile: from, path: toProfilePath, window: window,
            skipExistingCookies: skipExistingCookies, extensionIDs: allowedExtensionIDs))
        guard acceptsBrowserImport else { return nil }
        browserCompletions.append(completion); return PCNativeImportSession()
    }
}

@MainActor struct PCNativePasswordFileImportResult {
    var outcome: PCNativeImportOutcome
    var importedCount: Int = 0, existingCount: Int = 0, invalidCount: Int = 0
    var canRemoveSourceFile = false
    var error: NSError?
}
@MainActor final class PCNativePasswordFileImportSession {
    private(set) var cancelled = false
    private(set) var removalRequests: [(NSError?) -> Void] = []
    func cancel() { cancelled = true }
    func removeSourceFile(completion: @escaping (NSError?) -> Void) { removalRequests.append(completion) }
}
