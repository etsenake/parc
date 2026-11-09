import Foundation
import Darwin
import Combine

//
// distinguish top apps, pinned and unpinned containers, profile-bound Spaces,
// hierarchical items, saved tab destinations, and split-pane state.
// This is Parc's source implementation of those concepts, not recovered source.

enum TabKind: String, Codable, CaseIterable { case favorite, pinned, today }

//
// sessions may also contain 1h/6h/Never; preserve those values on migration.
enum AutoArchiveInterval: Double, CaseIterable {
    case never = 0, oneHour = 1, sixHours = 6, twelveHours = 12
    case twentyFourHours = 24, sevenDays = 168, thirtyDays = 720

    static let settingsChoices: [Self] = [.twelveHours, .twentyFourHours, .sevenDays, .thirtyDays]
    var seconds: TimeInterval? { self == .never ? nil : rawValue * 3600 }
    var durationTitle: String { self == .twelveHours ? "12 hours" : title }
    var title: String {
        switch self {
        case .never: return "Never"
        case .oneHour: return "1 hour"
        case .sixHours: return "6 hours"
        case .twelveHours: return "12 hours (default)"
        case .twentyFourHours: return "24 hours"
        case .sevenDays: return "7 days"
        case .thirtyDays: return "30 days"
        }
    }
}

struct BrowserProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var autoArchiveHours: Double = AutoArchiveInterval.twelveHours.rawValue
}

/// Captures the exact Profiles reviewed by the automatic-archive scope sheet.
/// Newly created, renamed or changed Profiles cannot join a retained callback.
struct AutoArchiveProfileChange: Equatable {
    let profileID: UUID
    let profiles: [BrowserProfile]
    let interval: AutoArchiveInterval
    var profileName: String { profiles.first { $0.id == profileID }?.name ?? "" }
}

struct BrowserSpace: Codable, Identifiable, Equatable {
    var id: UUID
    /// Optional authored title; all existing callers read the positional display
    /// name through `name`. Setting it remains an explicit rename.
    var title: String?
    private var placeholderName = "Space"
    var name: String {
        get { title ?? placeholderName }
        set { title = newValue.isEmpty ? nil : newValue }
    }
    private var migratesLegacyTitle = false
    var symbol: String
    var customIcon: SidebarGroupIcon? = nil
    var theme: SpaceTheme
    var profileID: UUID

    init(id: UUID, name: String, symbol: String, color: String, profileID: UUID) {
        self.id = id; self.title = name.isEmpty ? nil : name
        self.symbol = symbol; self.profileID = profileID
        theme = .singleColor(ThemeColor(hex: color) ?? ThemeColor(hex: "B9B5D4")!)
    }

    private enum CodingKeys: String, CodingKey { case id, name, title, symbol, customIcon, theme, color, profileID }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        let legacyName = try c.decode(String.self, forKey: .name)
        placeholderName = legacyName
        migratesLegacyTitle = !c.contains(.title)
        title = migratesLegacyTitle ? legacyName : try c.decodeIfPresent(String.self, forKey: .title)
        symbol = try c.decode(String.self, forKey: .symbol)
        customIcon = SidebarGroupIcon.decodeIfValid(c, forKey: .customIcon)
        profileID = try c.decode(UUID.self, forKey: .profileID)
        if c.contains(.theme) {
            theme = try c.decode(SpaceTheme.self, forKey: .theme)
        } else {
            let legacy = try c.decode(String.self, forKey: .color)
            guard let color = ThemeColor(hex: legacy) else {
                throw DecodingError.dataCorruptedError(forKey: .color, in: c,
                    debugDescription: "Legacy Space color must contain six hexadecimal digits.")
            }
            theme = .singleColor(color)
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(title, forKey: .title)
        try c.encode(symbol, forKey: .symbol); try c.encode(profileID, forKey: .profileID)
        try c.encode(theme, forKey: .theme)
        try c.encodeIfPresent(customIcon, forKey: .customIcon)
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        // Migration/cache bookkeeping is not authored Space state. In
        // particular a titled Space constructed in memory equals its decoded
        // form even when their unused positional placeholders differ.
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.name == rhs.name
            && lhs.symbol == rhs.symbol && lhs.customIcon == rhs.customIcon
            && lhs.theme == rhs.theme && lhs.profileID == rhs.profileID
    }
    mutating func updateDisplayName(position: Int) {
        let placeholder = "Space \(position + 1)"
        if migratesLegacyTitle {
            if name == placeholder || name.isEmpty { title = nil }
            migratesLegacyTitle = false
        }
        placeholderName = placeholder
    }
}

//
// Nil provenance is intentionally unknown for sessions predating this schema.
/// Library Put Back follows the initiating window and its selected source filter.
/// Reopen Closed Tab keeps its separate previous-Space policy.
enum ArchiveRestoreDestination {
    case putBack(currentSpaceID: UUID, requestedSpaceID: UUID?)
    case previousSpace(fallbackSpaceID: UUID?)
}

enum ArchiveReason: String, Codable {
    case automatic, manual, clearButton, clearTabGroup, session
    var isManual: Bool { self != .automatic }
}

struct ArchiveProvenance: Codable, Equatable {
    var reason: ArchiveReason
    var spaceID: UUID
    var spaceName: String
    var groupID: UUID?
    var split: BrowserSplitLayout?
}

struct BrowserArchivedItem: Identifiable {
    var tabs: [BrowserTab]
    var id: UUID { tabs[0].id }
    var archivedAt: Date { tabs[0].archivedAt! }
    var provenance: ArchiveProvenance? { tabs[0].archiveProvenance }
    var title: String { tabs.map { $0.title.isEmpty ? $0.url : $0.title }.joined(separator: " · ") }
    var urls: [String] { tabs.map(\.url) }
}

struct ArchivePreviewLease: Equatable {
    let token: UUID
    let profileID: UUID
    let tabs: [BrowserTab]
}

struct BrowserTab: Codable, Identifiable, Equatable {
    var id: UUID
    var spaceID: UUID
    var profileID: UUID
    var url: String
    var title: String
    var kind: TabKind
    var folderID: UUID?
    var createdAt: Date
    var lastAccessed: Date
    var archivedAt: Date?
    var savedURL: String
    var savedTitle: String
    var customTitle: String? = nil
    var isMuted: Bool = false
    var isUnread: Bool = false
    var archiveProvenance: ArchiveProvenance? = nil
    // Original creation identities; never reconstructed from a URL or a later
    // global selection. Older saved records deliberately decode these as nil.
    var referrerID: UUID? = nil
    var activeTabBeforeCreationID: UUID? = nil
}

/// Saved-tab presentation equality, not a navigation or security canonicalizer.
/// Always dispatch the original destination; these comparison-only transforms
///
enum SavedTabURLComparison {
    static func isAway(current: URL?, saved: URL?) -> Bool {
        guard let current, let saved, current != saved else { return false }
        return normalized(current) != normalized(saved)
    }

    /// Comparison key for deduplicating saved URL strings.
    static func key(_ string: String) -> String {
        URL(string: string).map { normalized($0).absoluteString } ?? string
    }

    private static func normalized(_ original: URL) -> URL {
        guard var parts = URLComponents(string: original.absoluteString.lowercased()) else { return original }
        let originalPath = parts.path
        // The original component helper repairs only a missing scheme AND host.
        if parts.scheme == nil, parts.host == nil, let string = parts.string,
           let repaired = URLComponents(string: "https://" + string) { parts = repaired }
        if parts.scheme == nil || parts.scheme == "http" { parts.scheme = "https" }
        if let host = parts.host, host.hasPrefix("www.") {
            parts.host = host.split(separator: ".").dropFirst().joined(separator: ".")
        }
        if let fragment = parts.fragment, fragment.first == "!" {
            if fragment.last == "/" { parts.fragment = String(fragment.dropLast()) }
        } else {
            parts.fragment = nil
            if parts.path.last == "/" { parts.path = String(originalPath.dropLast()) }
        }
        if let items = parts.queryItems {
            let kept = items.filter { !($0.value ?? "").isEmpty && !$0.name.hasPrefix("utm_") }
            // Preserve original encoding/order when there is nothing to remove.
            // Reassigning even an unchanged array can alter percent escapes.
            if items.isEmpty || kept.count != items.count { parts.queryItems = kept.isEmpty ? nil : kept }
        }
        return parts.url ?? original
    }
}

extension BrowserTab {
    // The saved destination belongs to the Sidebar item; navigation changes
    // its live URL without moving that destination.
    var resetDestination: URL? {
        guard archivedAt == nil, kind != .today,
              !InternalPage.isInternal(url), !InternalPage.isInternal(savedURL),
              let destination = URL(string: savedURL), destination.scheme != nil,
              SavedTabURLComparison.isAway(current: URL(string: url), saved: destination) else { return nil }
        return destination
    }

    private enum CodingKeys: String, CodingKey {
        case id, spaceID, profileID, url, title, kind, folderID, createdAt, lastAccessed,
             archivedAt, savedURL, savedTitle, customTitle, isMuted, isUnread, archiveProvenance, referrerID, activeTabBeforeCreationID
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        spaceID = try values.decode(UUID.self, forKey: .spaceID)
        profileID = try values.decode(UUID.self, forKey: .profileID)
        url = try values.decode(String.self, forKey: .url)
        title = try values.decode(String.self, forKey: .title)
        kind = try values.decode(TabKind.self, forKey: .kind)
        folderID = try values.decodeIfPresent(UUID.self, forKey: .folderID)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        lastAccessed = try values.decode(Date.self, forKey: .lastAccessed)
        archivedAt = try values.decodeIfPresent(Date.self, forKey: .archivedAt)
        savedURL = try values.decode(String.self, forKey: .savedURL)
        savedTitle = try values.decode(String.self, forKey: .savedTitle)
        customTitle = try values.decodeIfPresent(String.self, forKey: .customTitle)
        isMuted = try values.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        // Earlier Parc opened every new tab as selected, so those existing
        // tabs were already seen. Preserve explicit unread values if present.
        isUnread = try values.decodeIfPresent(Bool.self, forKey: .isUnread) ?? false
        archiveProvenance = try values.decodeIfPresent(ArchiveProvenance.self, forKey: .archiveProvenance)
        referrerID = try values.decodeIfPresent(UUID.self, forKey: .referrerID)
        activeTabBeforeCreationID = try values.decodeIfPresent(UUID.self, forKey: .activeTabBeforeCreationID)
    }
}

struct TabCreationProvenance: Equatable {
    let referrerID: UUID?
    let activeTabBeforeCreationID: UUID?
    init(referrerID: UUID?, activeTabID: UUID?, profileID: UUID, state: BrowserState) {
        func original(_ id: UUID?) -> UUID? {
            id.flatMap { value in state.tabs.contains {
                $0.id == value && $0.profileID == profileID && $0.archivedAt == nil
            } ? value : nil }
        }
        self.referrerID = original(referrerID)
        // WindowData+TabCreation 10261e650–680: explicit referrer wins;
        // otherwise the original window's active item is captured at creation.
        activeTabBeforeCreationID = self.referrerID ?? original(activeTabID)
    }
    ///
    ///
    ///
    ///
    /// its active item. Without a same-Profile source the adopting window is
    /// not the creating window, so its own current item is never substituted.
    init(routedFrom source: UUID?, openedLink: Bool, profileID: UUID, state: BrowserState) {
        self.init(referrerID: openedLink ? nil : source, activeTabID: source, profileID: profileID, state: state)
    }
    func validated(profileID: UUID, state: BrowserState) -> Self {
        Self(referrerID: referrerID, activeTabID: activeTabBeforeCreationID, profileID: profileID, state: state)
    }
}

///
///
///
enum TodayInsertion: Equatable {
    /// The nil-strategy default: after the referrer's opened run, else the top.
    case automatic
    /// `absolute(index: 0)`. Both matched routes supply it: created contents
    ///
    ///
    /// So does an alternate Back/Forward in a new tab, in the current Space's
    ///
    case top
}

struct BrowserFolder: Codable, Identifiable, Equatable {
    var id: UUID
    var spaceID: UUID
    var name: String
    var parentID: UUID?
    var isExpanded: Bool = true
    ///
    var customIcon: SidebarGroupIcon? = nil
}

extension BrowserFolder {
    private enum CodingKeys: String, CodingKey { case id, spaceID, name, parentID, isExpanded, customIcon }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        spaceID = try c.decode(UUID.self, forKey: .spaceID)
        name = try c.decode(String.self, forKey: .name)
        parentID = try c.decodeIfPresent(UUID.self, forKey: .parentID)
        isExpanded = try c.decode(Bool.self, forKey: .isExpanded)
        customIcon = SidebarGroupIcon.decodeIfValid(c, forKey: .customIcon)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(spaceID, forKey: .spaceID)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(parentID, forKey: .parentID)
        try c.encode(isExpanded, forKey: .isExpanded)
        try c.encodeIfPresent(customIcon, forKey: .customIcon)
    }
}

struct BrowserHistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var url: String
    var title: String
    var visitedAt: Date
    var profileID: UUID
}

/// `history.jsonl`: one compact JSON visit per line, appended as visits are
/// added or retitled, so a navigation writes one line instead of the whole
/// history. Removals rewrite the file. A later record for the same visit
/// replaces the earlier one; the oldest visits beyond capacity are dropped
/// on load and the file is compacted once it holds `compactionSlack` extra
/// records.
enum BrowserHistoryFile {
    static let name = "history.jsonl"
    static let compactionSlack = 5_000

    static func encode(_ visits: some Sequence<BrowserHistoryEntry>) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = Data()
        for visit in visits {
            data.append(try encoder.encode(visit))
            data.append(UInt8(ascii: "\n"))
        }
        return data
    }

    /// Visits oldest-first. An unreadable line (an append cut short) is
    /// skipped; the first write after launch rewrites the file without it.
    static func decode(_ data: Data) -> [BrowserHistoryEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var order: [UUID] = [], latest: [UUID: BrowserHistoryEntry] = [:]
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let visit = try? decoder.decode(BrowserHistoryEntry.self, from: Data(line)) else { continue }
            if latest.updateValue(visit, forKey: visit.id) == nil { order.append(visit.id) }
        }
        var visits = order.map { latest[$0]! }
        if visits.count > BrowserHistoryOrder.capacity {
            visits.removeFirst(visits.count - BrowserHistoryOrder.capacity)
        }
        return visits
    }

    /// The records to append when `next` only adds visits at the end, retitles
    /// visits, or drops the oldest for capacity; nil when it needs a rewrite.
    /// Oldest visits dropped below capacity were deleted, and loading would
    /// bring them back, so that is a rewrite too.
    static func appended(from previous: [BrowserHistoryEntry],
                         to next: [BrowserHistoryEntry]) -> [BrowserHistoryEntry]? {
        var dropped = 0
        if let first = next.first, !previous.isEmpty {
            guard let index = previous.firstIndex(where: { $0.id == first.id }),
                  index == 0 || next.count == BrowserHistoryOrder.capacity else { return nil }
            dropped = index
        } else if next.isEmpty {
            return previous.isEmpty ? [] : nil
        }
        let overlap = previous.count - dropped
        guard overlap <= next.count else { return nil }
        var records: [BrowserHistoryEntry] = []
        for offset in 0..<overlap {
            let old = previous[dropped + offset], new = next[offset]
            guard old.id == new.id else { return nil }
            if old != new { records.append(new) }
        }
        records += next[overlap...]
        return records
    }
}

/// Visit records in `BrowserState.history` are oldest-first: new visits append
/// and overflow drops the oldest prefix. Newest-first surfaces reuse that order
/// when timestamps are strictly increasing, and otherwise use the same
/// `sorted { $0.visitedAt > $1.visitedAt }` as before (including same-second ties).
enum BrowserHistoryOrder {
    static let capacity = 20_000

    static func isStrictlyChronological(_ history: [BrowserHistoryEntry]) -> Bool {
        guard history.count > 1 else { return true }
        var previous = history[0].visitedAt
        for index in 1..<history.count {
            let date = history[index].visitedAt
            if date <= previous { return false }
            previous = date
        }
        return true
    }

    /// Identity and order match `history.sorted { $0.visitedAt > $1.visitedAt }`.
    static func newestFirst(_ history: [BrowserHistoryEntry]) -> [BrowserHistoryEntry] {
        if isStrictlyChronological(history) { return Array(history.reversed()) }
        return history.sorted { $0.visitedAt > $1.visitedAt }
    }
}

/// A deletion from Chromium's history, as `PCNativeHistoryDidDeleteNotification`
/// reports it: all history, a time range (perhaps for given URLs only), the URLs
/// removed outright and their hosts. From overlay 320 it also names the profile
/// and those URLs; an older engine's names neither, so its deletions reach every
/// profile and, outside a time range, the reported hosts stand in for URLs.
struct ChromiumHistoryDeletion {
    var profilePath: String?
    var all: Bool
    var range: ClosedRange<Date>?
    var rangeURLs: Set<String>?
    var urls: Set<String>?
    var hosts: Set<String>

    init(userInfo: [AnyHashable: Any]) {
        func urls(_ key: String) -> Set<String>? {
            (userInfo[key] as? [String]).map { Set($0.map(BrowserInternalURL.publicString)) }
        }
        profilePath = userInfo["profilePath"] as? String
        all = userInfo["allHistory"] as? Bool ?? false
        if userInfo["timeRange"] as? Bool == true,
           let begin = userInfo["begin"] as? Double, let end = userInfo["end"] as? Double, begin <= end {
            range = Date(timeIntervalSinceReferenceDate: begin)...Date(timeIntervalSinceReferenceDate: end)
        }
        rangeURLs = urls("restrictURLs")
        self.urls = urls("urls")
        hosts = Set(userInfo["hosts"] as? [String] ?? [])
    }

    func removes(_ visit: BrowserHistoryEntry) -> Bool {
        if all { return true }
        if let range, range.contains(visit.visitedAt), rangeURLs?.contains(visit.url) ?? true { return true }
        if let urls { return urls.contains(visit.url) }
        return range == nil && URL(string: visit.url)?.host.map(hosts.contains) == true
    }
}

enum BrowserDownloadStatus: String, Codable, CaseIterable {
    case pending, downloading, paused, completed, cancelled, failed

    static func inferred(isComplete: Bool, isCancelled: Bool, isFailed: Bool = false,
                         isPaused: Bool = false, receivedBytes: Int64) -> Self {
        if isComplete { return .completed }
        if isCancelled { return .cancelled }
        if isFailed { return .failed }
        if isPaused { return .paused }
        return receivedBytes > 0 ? .downloading : .pending
    }
}

struct BrowserDownload: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var path: String
    var receivedBytes: Int64
    var totalBytes: Int64
    var status: BrowserDownloadStatus
    var profileID: UUID? = nil
    var nativeID: String? = nil
    var errorCode: Int? = nil
    var requiresReview = false
    var sourceURL: String?
    var startedAt: Date?
    // Capabilities are live leases, deliberately never restored from disk.
    var canPause = false
    var canResume = false
    var canCancel = false
    var canReview = false
    var canRetry = false
    var nativeIdentity: String?
    // An original live OTR manager lease; never serialized with session data.
    var privateContextID: String?
    var canOpen = false
    var canReveal = false
    var canRemove = false
    var canCopyFile = false
    var canToggleOpen = false
    var openWhenComplete = false
    var fileMissing = false
    var statusText = ""
    // Presentation metadata from this live manager, never restored as progress.
    var sourceDomain: String?
    var mimeType: String?
    var timeRemaining: TimeInterval?
    var isComplete: Bool { status == .completed }
    var isCancelled: Bool { status == .cancelled }

    init(id: String, name: String, path: String, receivedBytes: Int64, totalBytes: Int64,
         status: BrowserDownloadStatus) {
        self.id = id
        self.name = name
        self.path = path
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
        self.status = status
    }

    static func snapshot(_ values: [String: Any], id: String, nativeID: String,
                         profileID: UUID?) -> BrowserDownload {
        let receivedBytes = (values["receivedBytes"] as? NSNumber)?.int64Value ?? 0
        let status = (values["status"] as? String).flatMap(BrowserDownloadStatus.init(rawValue:))
            ?? .inferred(isComplete: values["isComplete"] as? Bool ?? false,
                         isCancelled: values["isCancelled"] as? Bool ?? false,
                         isFailed: values["isFailed"] as? Bool ?? false,
                         isPaused: values["isPaused"] as? Bool ?? false,
                         receivedBytes: receivedBytes)
        var value = BrowserDownload(id: id, name: values["name"] as? String ?? "Download",
                                    path: values["path"] as? String ?? "", receivedBytes: receivedBytes,
                                    totalBytes: (values["totalBytes"] as? NSNumber)?.int64Value ?? 0,
                                    status: status)
        value.profileID = profileID
        value.nativeID = profileID == nil ? nil : nativeID
        value.errorCode = (values["errorCode"] as? NSNumber)?.intValue
        value.requiresReview = values["requiresReview"] as? Bool ?? false
        let live = profileID != nil && values["available"] as? Bool == true
        value.canPause = live && values["canPause"] as? Bool == true
        value.canResume = live && values["canResume"] as? Bool == true
        value.canCancel = live && values["canCancel"] as? Bool == true
        value.canReview = live && values["canReview"] as? Bool == true
        value.canRetry = live && values["canRetry"] as? Bool == true
        value.sourceURL = values["sourceURL"] as? String
        if let seconds = (values["startedAt"] as? NSNumber)?.doubleValue, seconds.isFinite, seconds > 0 {
            value.startedAt = Date(timeIntervalSince1970: seconds)
        }
        value.nativeIdentity = live ? (values["itemIdentity"] as? String).flatMap { $0.isEmpty ? nil : $0 } : nil
        let identified = live && value.nativeIdentity != nil
        value.canOpen = identified && values["canOpen"] as? Bool == true
        value.canReveal = identified && values["canReveal"] as? Bool == true
        value.canRemove = identified && values["canRemove"] as? Bool == true
        value.canCopyFile = identified && values["canCopyFile"] as? Bool == true
        value.canToggleOpen = identified && values["canToggleOpen"] as? Bool == true
        value.openWhenComplete = values["openWhenComplete"] as? Bool ?? false
        value.fileMissing = values["fileMissing"] as? Bool ?? false
        value.statusText = values["statusText"] as? String ?? ""
        value.sourceDomain = (values["sourceDomain"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        value.mimeType = (values["mimeType"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        if live, let remaining = (values["timeRemaining"] as? NSNumber)?.doubleValue,
           remaining.isFinite, remaining > 0 { value.timeRemaining = remaining }
        return value
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, path, receivedBytes, totalBytes, status, isComplete, isCancelled
        case profileID, nativeID, errorCode, requiresReview, sourceURL, startedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        path = try values.decode(String.self, forKey: .path)
        receivedBytes = try values.decode(Int64.self, forKey: .receivedBytes)
        totalBytes = try values.decode(Int64.self, forKey: .totalBytes)
        profileID = try values.decodeIfPresent(UUID.self, forKey: .profileID)
        nativeID = try values.decodeIfPresent(String.self, forKey: .nativeID)
        errorCode = try values.decodeIfPresent(Int.self, forKey: .errorCode)
        requiresReview = try values.decodeIfPresent(Bool.self, forKey: .requiresReview) ?? false
        sourceURL = try values.decodeIfPresent(String.self, forKey: .sourceURL)
        startedAt = try values.decodeIfPresent(Date.self, forKey: .startedAt)
        // Earlier sessions only recorded completion/cancellation. Preserve
        // those outcomes; byte progress distinguishes active from pending.
        status = try values.decodeIfPresent(BrowserDownloadStatus.self, forKey: .status)
            ?? .inferred(isComplete: values.decodeIfPresent(Bool.self, forKey: .isComplete) ?? false,
                         isCancelled: values.decodeIfPresent(Bool.self, forKey: .isCancelled) ?? false,
                         receivedBytes: receivedBytes)
    }

    func encode(to encoder: Encoder) throws {
        guard privateContextID == nil else {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath,
                debugDescription: "Private download records are memory-only."))
        }
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(path, forKey: .path)
        try values.encode(receivedBytes, forKey: .receivedBytes)
        try values.encode(totalBytes, forKey: .totalBytes)
        try values.encode(status, forKey: .status)
        try values.encodeIfPresent(profileID, forKey: .profileID)
        try values.encodeIfPresent(nativeID, forKey: .nativeID)
        try values.encodeIfPresent(errorCode, forKey: .errorCode)
        try values.encode(requiresReview, forKey: .requiresReview)
        try values.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try values.encodeIfPresent(startedAt, forKey: .startedAt)
        // Keep the original fields readable by earlier Parc session readers.
        try values.encode(isComplete, forKey: .isComplete)
        try values.encode(isCancelled, forKey: .isCancelled)
    }
}

struct BrowserSettings: Codable, Equatable {
    ///
    var sidebarWidth: Double = 228
    // Legacy session decoding/model-only fallback. Native address input uses the selected Profile.
    var searchEngine: String = "https://duckduckgo.com/?q="
    var restoreSession: Bool = true
    var onboardingComplete: Bool = false
    var settingsPane: String?
    var settingsProfileID: UUID?
    var defaultProfileID: UUID?
    // Optional storage keeps older sessions decodable. These names/polarities
    //
    //
    var modalEnabled: Bool?
    var disableShiftClickToOpenLinksInModal: Bool?
    var automaticPeekEnabled: Bool {
        get { modalEnabled ?? true }
        set { modalEnabled = newValue }
    }
    var shiftPeekEnabled: Bool {
        get { !(disableShiftClickToOpenLinksInModal ?? false) }
        set { disableShiftClickToOpenLinksInModal = !newValue }
    }
    ///
    /// dismissed; the App Tray reads it as hasDismissedEmptyState
    ///
    var topAppsEmptyStateDismissedForProfiles: [UUID]?
    func favoritesEmptyStateDismissed(for profileID: UUID) -> Bool {
        topAppsEmptyStateDismissedForProfiles?.contains(profileID) == true
    }
    ///
    ///
    ///
    ///
    /// reads as that default.
    var showSpaceHeaderOnSingleUnnamedSpaces: Bool?
    ///
    ///
    /// AppReducer registers no default for it, so nil reads false.
    var shouldBypassConfirmInterProfileMoveDialog: Bool?
}

//
// each split. Horizontal describes the page arrangement, not the divider.
enum SplitOrientation: String, Codable, CaseIterable { case horizontal, vertical }

///
/// 61 cases in this order, a String raw value equal to the case name
///
///
/// icon fonts and assets (see `Resources/CustomInfoPicker/README.md`).
enum SidebarIconType: String, Codable, CaseIterable {
    case star, bookmark, heart, flag, flash, triangle, medical, notifications, bulb, shapes
    case grid, apps, layers, server, albums, copy, folder, fileTrayFull, calendar, mail
    case checkbox, document, book, chatBubbleEllipses, people, terminal, construction, square, egg, ellipse
    case moon, sunny, planet, leaf, cloud, paw, bag, gift, bed, restaurant
    case barbell, airplane, musicalNote, colorPallete, video, bandage, code, baseball, cloudOutline, map
    case bonfire, pizza, skull, receipt, thumbsUp, train, rss, github, linear, figma
    case search

    ///
    /// star through train (no rss, github, linear, figma or search).
    static let tabAndSpacePicker = Array(allCases.prefix(56))
    ///
    static let folderPicker: [SidebarIconType] = [.star, .bookmark, .heart, .flash, .triangle, .medical,
        .notifications, .bulb, .chatBubbleEllipses, .people, .construction, .egg, .ellipse, .moon, .planet,
        .leaf, .cloud, .paw, .restaurant, .airplane, .musicalNote, .video, .code, .skull]
}

///
/// Character, one `SidebarIconType`, or an SF Symbol name. Spaces and split
///
enum SidebarGroupIcon: Codable, Equatable {
    case emoji(String)
    case icon(SidebarIconType)
    case symbol(String)

    var isValid: Bool {
        switch self {
        case .emoji(let value): return value.count == 1 && value.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F || $0.value > 0x1F000 }
        case .icon: return true
        //
        // but its picker never produces one. Parc's only symbols are those its
        // earlier picker stored, so only those names remain valid.
        case .symbol(let value): return Self.storedSymbols.contains(value)
        }
    }
    /// Symbols written by Parc's pre-catalog picker; kept so stored values
    /// still decode and render. Nothing new is created with them.
    static let storedSymbols: Set<String> = ["square.grid.2x2", "star", "heart", "bookmark", "briefcase", "house",
        "globe", "book", "music.note", "camera", "gamecontroller", "paintbrush", "leaf", "sun.max", "moon", "bolt",
        "flame", "flag", "gift", "graduationcap", "lightbulb", "paperplane", "puzzlepiece", "sparkles"]

    /// An unknown stored icon (for example a raw value this build does not
    /// know) decodes as absent instead of failing the whole document.
    static func decodeIfValid<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, forKey key: Key) -> SidebarGroupIcon? {
        guard let icon = try? container.decodeIfPresent(SidebarGroupIcon.self, forKey: key), icon.isValid else { return nil }
        return icon
    }
}

struct BrowserSplitLayout: Codable, Equatable, Identifiable {
    ///
    /// 1.122's split removal (WindowContentPresentationMutationContext+SplitView
    ///
    /// index, else the new last one (SP32).
    static func focusSuccessor(_ remaining: [UUID], removedAt index: Int?) -> UUID? {
        guard !remaining.isEmpty else { return nil }
        return remaining[min(max(index ?? 0, 0), remaining.count - 1)]
    }
    var id: UUID = UUID()
    var sidebarAnchorID: UUID? = nil
    var customTitle: String? = nil
    var customIcon: SidebarGroupIcon? = nil
    var spaceID: UUID
    var tabIDs: [UUID]
    var orientation: SplitOrientation = .horizontal
    var widthFactors: [Double]

    private enum CodingKeys: String, CodingKey {
        case id, sidebarAnchorID, customTitle, customIcon, spaceID, tabIDs, orientation, widthFactors
    }
    init(id: UUID = UUID(), sidebarAnchorID: UUID? = nil, customTitle: String? = nil, customIcon: SidebarGroupIcon? = nil, spaceID: UUID,
         tabIDs: [UUID], orientation: SplitOrientation = .horizontal, widthFactors: [Double]) {
        self.id = id; self.sidebarAnchorID = sidebarAnchorID ?? tabIDs.first
        self.customTitle = customTitle; self.customIcon = customIcon
        self.spaceID = spaceID; self.tabIDs = tabIDs
        self.orientation = orientation; self.widthFactors = widthFactors
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        spaceID = try c.decode(UUID.self, forKey: .spaceID)
        tabIDs = try c.decode([UUID].self, forKey: .tabIDs)
        sidebarAnchorID = try c.decodeIfPresent(UUID.self, forKey: .sidebarAnchorID) ?? tabIDs.first
        customTitle = try c.decodeIfPresent(String.self, forKey: .customTitle)
        customIcon = SidebarGroupIcon.decodeIfValid(c, forKey: .customIcon)
        orientation = try c.decodeIfPresent(SplitOrientation.self, forKey: .orientation) ?? .horizontal
        widthFactors = try c.decode([Double].self, forKey: .widthFactors)
    }

    static func normalized(_ factors: [Double], count: Int) -> [Double]? {
        guard (2...4).contains(count), factors.count == count,
              factors.allSatisfy({ $0.isFinite && $0 > 0 }), let largest = factors.max() else { return nil }
        // Scaling first avoids overflowing the sum for valid, large weights.
        let scaled = factors.map { $0 / largest }
        let sum = scaled.reduce(0, +)
        let result = scaled.map { $0 / sum }
        guard result.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        return result
    }

    ///
    /// focused content 1 and every other pane 0; the split's effective-factor
    /// layout gives a zero weight the expanded pane minimum. Saved weights stay
    /// positive here, so that zero is kept as a weight the same minimum
    /// redistribution resolves to the minimum at any window size.
    func expandedFactors(focusing id: UUID) -> [Double]? {
        guard tabIDs.contains(id) else { return nil }
        return Self.normalized(tabIDs.map { $0 == id ? 1 : 1e-9 }, count: tabIDs.count)
    }
}

struct BrowserState: Codable, Equatable {
    var version: Int = 1
    var profiles: [BrowserProfile]
    var spaces: [BrowserSpace]
    var tabs: [BrowserTab] = []
    var folders: [BrowserFolder] = []
    var activeSpaceID: UUID
    var selectedTabIDs: [UUID] = []
    var selectionBySpace: [String: [UUID]] = [:]
    var splitLayouts: [BrowserSplitLayout] = []
    var sidebarItemOrder: [String: [SidebarItemReference]] = [:]
    var autoArchiveStartedAt: Date?
    var autoArchiveDefaultHours = AutoArchiveInterval.twelveHours.rawValue
    var autoArchiveEducationEligible = false
    var history: [BrowserHistoryEntry] = []
    var downloads: [BrowserDownload] = []
    var recentlyClosedIDs: [UUID] = []
    var settings = BrowserSettings()
    var profileRemovals: [ProfileRemovalRecord] = []
    ///
    var arcImportedSpaces: [String: UUID] = [:]
    /// The session file's window records (Windows and lifecycle hook). They
    /// drive no UI, so BrowserStore keeps them off this published state as
    /// `windowRecords`; in memory this list is always empty.
    var windows: [BrowserWindowRecord] = []

    static func initial() -> Self {
        let profile = BrowserProfile(id: UUID(), name: "Default")
        var space = BrowserSpace(id: UUID(), name: "", symbol: "circle.fill", color: "B9B5D4", profileID: profile.id)
        space.updateDisplayName(position: 0)
        return Self(profiles: [profile], spaces: [space], activeSpaceID: space.id)
    }

    /// Outline membership, selection, folder expansion, and sidebar chrome
    /// structure that live metadata does not rebuild (spaces/profiles/settings/
    /// splits/order). Title/URL/customTitle, unread/mute flags, downloads and
    /// other non-outline fields may differ so `SidebarView` can patch cells
    /// instead of reallocating rows.
    func preservesSidebarOutline(relativeTo previous: BrowserState) -> Bool {
        profiles == previous.profiles
            && spaces == previous.spaces
            && folders == previous.folders
            && activeSpaceID == previous.activeSpaceID
            && selectedTabIDs == previous.selectedTabIDs
            && selectionBySpace == previous.selectionBySpace
            && splitLayouts == previous.splitLayouts
            && sidebarItemOrder == previous.sidebarItemOrder
            && settings == previous.settings
            && tabs.count == previous.tabs.count
            && zip(tabs, previous.tabs).allSatisfy { current, prior in
                current.id == prior.id
                    && current.spaceID == prior.spaceID
                    && current.profileID == prior.profileID
                    && current.kind == prior.kind
                    && current.folderID == prior.folderID
                    && current.archivedAt == prior.archivedAt
                    && InternalPage(urlString: current.url) == InternalPage(urlString: prior.url)
                    && Self.isBlankPage(current.url) == Self.isBlankPage(prior.url)
            }
    }

    /// Title, URL, saved metadata and history may differ. Membership, selection
    /// and chrome-owning fields must not, so a metadata tick can patch rows
    /// instead of reconstructing the sidebar and window chrome.
    func preservesChromeLayout(relativeTo previous: BrowserState) -> Bool {
        preservesSidebarOutline(relativeTo: previous)
            && version == previous.version
            && autoArchiveStartedAt == previous.autoArchiveStartedAt
            && autoArchiveDefaultHours == previous.autoArchiveDefaultHours
            && autoArchiveEducationEligible == previous.autoArchiveEducationEligible
            && recentlyClosedIDs == previous.recentlyClosedIDs
            && profileRemovals == previous.profileRemovals
            && downloads == previous.downloads
            && zip(tabs, previous.tabs).allSatisfy { current, prior in
                current.customTitle == prior.customTitle
                    && current.isMuted == prior.isMuted
                    && current.isUnread == prior.isUnread
                    && current.archiveProvenance == prior.archiveProvenance
                    && current.referrerID == prior.referrerID
                    && current.activeTabBeforeCreationID == prior.activeTabBeforeCreationID
            }
    }

    static func isBlankPage(_ url: String) -> Bool {
        url.isEmpty || url == "about:blank"
    }
}

extension BrowserState {
    private enum CodingKeys: String, CodingKey {
        case version, profiles, spaces, tabs, folders, activeSpaceID, selectedTabIDs,
             selectionBySpace, splitLayouts, sidebarItemOrder, autoArchiveStartedAt, autoArchiveDefaultHours, autoArchiveEducationEligible, history, downloads, recentlyClosedIDs, settings, profileRemovals, arcImportedSpaces, windows
    }
    private enum LegacySplitKeys: String, CodingKey { case splitWidthFactors }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        profiles = try values.decode([BrowserProfile].self, forKey: .profiles)
        spaces = try values.decode([BrowserSpace].self, forKey: .spaces)
        for index in spaces.indices { spaces[index].updateDisplayName(position: index) }
        tabs = try values.decode([BrowserTab].self, forKey: .tabs)
        folders = try values.decode([BrowserFolder].self, forKey: .folders)
        activeSpaceID = try values.decode(UUID.self, forKey: .activeSpaceID)
        selectedTabIDs = try values.decode([UUID].self, forKey: .selectedTabIDs)
        selectionBySpace = try values.decode([String: [UUID]].self, forKey: .selectionBySpace)
        history = try values.decode([BrowserHistoryEntry].self, forKey: .history)
        downloads = try values.decode([BrowserDownload].self, forKey: .downloads)
        recentlyClosedIDs = try values.decode([UUID].self, forKey: .recentlyClosedIDs)
        settings = try values.decode(BrowserSettings.self, forKey: .settings)
        profileRemovals = try values.decodeIfPresent([ProfileRemovalRecord].self, forKey: .profileRemovals) ?? []
        arcImportedSpaces = try values.decodeIfPresent([String: UUID].self, forKey: .arcImportedSpaces) ?? [:]
        sidebarItemOrder = try values.decodeIfPresent([String: [SidebarItemReference]].self, forKey: .sidebarItemOrder) ?? [:]
        autoArchiveStartedAt = try values.decodeIfPresent(Date.self, forKey: .autoArchiveStartedAt)
        autoArchiveDefaultHours = try values.decodeIfPresent(Double.self, forKey: .autoArchiveDefaultHours) ?? AutoArchiveInterval.twelveHours.rawValue
        autoArchiveEducationEligible = try values.decodeIfPresent(Bool.self, forKey: .autoArchiveEducationEligible) ?? false
        windows = try values.decodeIfPresent([BrowserWindowRecord].self, forKey: .windows) ?? []
        if let saved = try values.decodeIfPresent([BrowserSplitLayout].self, forKey: .splitLayouts) {
            splitLayouts = saved
        } else {
            // Earlier Parc always rendered side by side; its unused global
            // splitIsVertical flag never affected the displayed arrangement.
            let legacy = try decoder.container(keyedBy: LegacySplitKeys.self)
            let weights = try legacy.decodeIfPresent([Double].self, forKey: .splitWidthFactors) ?? []
            var selections = selectionBySpace
            selections[activeSpaceID.uuidString] = selectedTabIDs
            splitLayouts = selections.keys.sorted().compactMap { key in
                guard let spaceID = UUID(uuidString: key), let space = spaces.first(where: { $0.id == spaceID }),
                      let previousIDs = selections[key] else { return nil }
                var seen = Set<UUID>()
                let positions = Array(previousIDs.indices.filter { position in
                    let id = previousIDs[position]
                    return seen.insert(id).inserted && tabs.contains { $0.id == id && $0.archivedAt == nil
                        && $0.profileID == space.profileID && ($0.kind == .favorite || $0.spaceID == spaceID) }
                }.prefix(4))
                let ids = positions.map { previousIDs[$0] }
                guard ids.count > 1 else { return nil }
                let equal = Array(repeating: 1.0 / Double(ids.count), count: ids.count)
                let activeWeights = weights.count == previousIDs.count ? positions.map { weights[$0] } : []
                let factors = spaceID == activeSpaceID
                    ? BrowserSplitLayout.normalized(activeWeights, count: ids.count) ?? equal : equal
                return BrowserSplitLayout(spaceID: spaceID, tabIDs: ids, widthFactors: factors)
            }
        }
    }
}

///
/// SharedWindowFeature.CodableWindowData in StorableWindows.windows.
///
///
struct BrowserWindowRecord: Codable, Equatable {
    var sidebarWidth: Double
    var itemLastActiveDates: [UUID: Date]
    var id: UUID?
    var focusedSpaceID: UUID?
    var selectedTabIDs: [UUID]?
    var focusedTabID: UUID?
    var sidebarHidden: Bool?
    var stayOnTop: Bool
    ///
    /// the items each collapsed folder still shows, in peek order.
    var peekedFolders: [UUID: [SidebarItemReference]]?
    private enum CodingKeys: String, CodingKey {
        case sidebarWidth, itemLastActiveDates, id, focusedSpaceID, selectedTabIDs, focusedTabID, sidebarHidden, stayOnTop, peekedFolders
    }

    init(sidebarWidth: Double, itemLastActiveDates: [UUID: Date] = [:], id: UUID? = nil,
         focusedSpaceID: UUID? = nil, selectedTabIDs: [UUID]? = nil, focusedTabID: UUID? = nil,
         sidebarHidden: Bool? = nil, stayOnTop: Bool = false, peekedFolders: [UUID: [SidebarItemReference]]? = nil) {
        self.sidebarWidth = sidebarWidth
        self.itemLastActiveDates = itemLastActiveDates
        self.id = id; self.focusedSpaceID = focusedSpaceID; self.selectedTabIDs = selectedTabIDs
        self.focusedTabID = focusedTabID; self.sidebarHidden = sidebarHidden
        self.stayOnTop = stayOnTop
        self.peekedFolders = peekedFolders
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sidebarWidth = try values.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? 228
        id = try values.decodeIfPresent(UUID.self, forKey: .id)
        focusedSpaceID = try values.decodeIfPresent(UUID.self, forKey: .focusedSpaceID)
        selectedTabIDs = try values.decodeIfPresent([UUID].self, forKey: .selectedTabIDs)
        focusedTabID = try values.decodeIfPresent(UUID.self, forKey: .focusedTabID)
        sidebarHidden = try values.decodeIfPresent(Bool.self, forKey: .sidebarHidden)
        stayOnTop = try values.decodeIfPresent(Bool.self, forKey: .stayOnTop) ?? false
        peekedFolders = try? values.decodeIfPresent([UUID: [SidebarItemReference]].self, forKey: .peekedFolders)
        if let intervals = try? values.decode([UUID: Double].self, forKey: .itemLastActiveDates) {
            itemLastActiveDates = intervals.mapValues { Date(timeIntervalSinceReferenceDate: $0) }
        } else {
            // Earlier session records used the store's ISO-8601 date strategy.
            itemLastActiveDates = try values.decodeIfPresent([UUID: Date].self, forKey: .itemLastActiveDates) ?? [:]
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(sidebarWidth, forKey: .sidebarWidth)
        try values.encodeIfPresent(id, forKey: .id)
        try values.encodeIfPresent(focusedSpaceID, forKey: .focusedSpaceID)
        try values.encodeIfPresent(selectedTabIDs, forKey: .selectedTabIDs)
        try values.encodeIfPresent(focusedTabID, forKey: .focusedTabID)
        try values.encodeIfPresent(sidebarHidden, forKey: .sidebarHidden)
        try values.encode(stayOnTop, forKey: .stayOnTop)
        try values.encodeIfPresent(peekedFolders, forKey: .peekedFolders)
        // The store's ISO-8601 strategy drops fractions of a second, which
        // would change the ranking of rapid selections after a restart.
        try values.encode(itemLastActiveDates.mapValues(\.timeIntervalSinceReferenceDate), forKey: .itemLastActiveDates)
    }

    /// Keep windows the single-window launcher did not reopen. If the original
    /// owner was reopened, its live record replaces that same saved identity.
    static func preservingUnrestored(live: [Self], unrestored: [Self]) -> [Self] {
        let liveIDs = Set(live.compactMap(\.id))
        return live + unrestored.filter { $0.id.map { !liveIDs.contains($0) } ?? true }
    }

    /// The order the open windows' records are saved in, as indices into the
    /// windows given: the one holding the shared frame autosave name first,
    /// then front to back (`frontToBack`, nil for a window not on screen),
    /// then opening order. A Parc adaptation for the one window it reopens,
    /// which takes that autosaved frame, so the first record is the same
    ///
    /// list carries no window identity a multi-window restorer could match.
    static func sessionOrder(holdsFrameAutosave: [Bool], frontToBack: [Int?]) -> [Int] {
        func rank(_ index: Int) -> Int { holdsFrameAutosave[index] ? -1 : frontToBack[index] ?? .max }
        return holdsFrameAutosave.indices.sorted { (rank($0), $0) < (rank($1), $1) }
    }
}

/// Typed sidebar identity: split containers move together and retain their
/// original children. Pasteboard bytes never authorize one of these moves.
enum SidebarItemReference: Codable, Hashable {
    case tab(UUID), folder(UUID), split(UUID)
}

struct SidebarContainerLocation: Equatable {
    let spaceID: UUID
    let folderID: UUID?
    let section: TabKind
    var profileID: UUID? = nil
    var key: String {
        if section == .favorite, let profileID { return "favorites:" + profileID.uuidString }
        return spaceID.uuidString + ":" + (folderID?.uuidString ?? section.rawValue)
    }
}

struct SidebarHierarchySnapshot: Equatable {
    struct Placement: Equatable {
        let id: UUID, profileID: UUID, spaceID: UUID
        let kind: TabKind
        let folderID: UUID?
    }
    let spaceID: UUID, profileID: UUID
    let includesFavorites: Bool
    let tabs: [Placement]
    let folders: [BrowserFolder]
    let groups: [BrowserSplitLayout]
    let order: [String: [SidebarItemReference]]

    init?(state: BrowserState, spaceID: UUID, profileID: UUID, includesFavorites: Bool = false) {
        guard state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }),
              state.profiles.contains(where: { $0.id == profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == profileID }) else { return nil }
        self.spaceID = spaceID; self.profileID = profileID; self.includesFavorites = includesFavorites
        tabs = state.tabs.filter { $0.archivedAt == nil && ($0.kind == .favorite
            ? includesFavorites && $0.profileID == profileID : $0.spaceID == spaceID) }
            .map { Placement(id: $0.id, profileID: $0.profileID, spaceID: $0.spaceID, kind: $0.kind, folderID: $0.folderID) }
        folders = state.folders.filter { $0.spaceID == spaceID }
        groups = state.splitLayouts.filter { $0.spaceID == spaceID
            || (includesFavorites && SidebarSplitItems.isFavorite($0, in: state, profileID: profileID)) }
        order = state.sidebarItemOrder.filter { $0.key.hasPrefix(spaceID.uuidString + ":")
            || (includesFavorites && $0.key == "favorites:" + profileID.uuidString) }
        guard Set(tabs.map(\.id)).count == tabs.count, Set(folders.map(\.id)).count == folders.count,
              Set(groups.map(\.id)).count == groups.count,
              tabs.allSatisfy({ $0.profileID == profileID }) else { return nil }
        guard tabs.allSatisfy({ tab in tab.folderID == nil || folders.contains { $0.id == tab.folderID } }) else { return nil }
        for folder in folders {
            var current: UUID? = folder.id, visited = Set<UUID>()
            while let id = current {
                guard visited.insert(id).inserted, let item = folders.first(where: { $0.id == id }) else { return nil }
                current = item.parentID
            }
        }
    }
}

enum SidebarHierarchy {
    static func location(of item: SidebarItemReference, state: BrowserState, spaceID: UUID) -> SidebarContainerLocation? {
        location(of: item, state: state, spaceID: spaceID, groups: nil)
    }
    private static func location(of item: SidebarItemReference, state: BrowserState, spaceID: UUID,
                                 groups: [BrowserSplitLayout]?) -> SidebarContainerLocation? {
        switch item {
        case .folder(let id):
            guard let folder = state.folders.first(where: { $0.id == id && $0.spaceID == spaceID }) else { return nil }
            return .init(spaceID: spaceID, folderID: folder.parentID, section: .pinned)
        case .split(let id):
            guard let group = (groups ?? SidebarSplitItems.groups(in: state, spaceID: spaceID)).first(where: { $0.id == id }),
                  let anchor = group.sidebarAnchorID else { return nil }
            return tabLocation(anchor, state: state, spaceID: spaceID)
        case .tab(let id):
            guard !(groups ?? SidebarSplitItems.groups(in: state, spaceID: spaceID)).contains(where: { $0.tabIDs.contains(id) }) else { return nil }
            return tabLocation(id, state: state, spaceID: spaceID)
        }
    }
    private static func tabLocation(_ id: UUID, state: BrowserState, spaceID: UUID) -> SidebarContainerLocation? {
        guard let profileID = state.spaces.first(where: { $0.id == spaceID })?.profileID,
              let tab = state.tabs.first(where: { $0.id == id && $0.archivedAt == nil && $0.profileID == profileID
                  && ($0.kind == .favorite || $0.spaceID == spaceID) }) else { return nil }
        return tabLocation(of: tab, spaceID: spaceID, profileID: profileID)
    }
    /// The location of a live tab of the Space's profile, a Favorite or in the Space.
    private static func tabLocation(of tab: BrowserTab, spaceID: UUID, profileID: UUID) -> SidebarContainerLocation? {
        if tab.kind == .favorite {
            guard tab.folderID == nil else { return nil }
            return .init(spaceID: spaceID, folderID: nil, section: .favorite, profileID: profileID)
        }
        return .init(spaceID: spaceID, folderID: tab.folderID, section: tab.folderID == nil ? tab.kind : .pinned)
    }
    static func children(in location: SidebarContainerLocation, state: BrowserState) -> [SidebarItemReference] {
        guard let profileID = state.spaces.first(where: { $0.id == location.spaceID })?.profileID,
              location.section != .favorite || (location.folderID == nil && location.profileID == profileID) else { return [] }
        let groups = SidebarSplitItems.groups(in: state, spaceID: location.spaceID)
        var legacy: [SidebarItemReference] = []
        for tab in state.tabs where tab.archivedAt == nil && tab.profileID == profileID
            && (location.section == .favorite ? tab.kind == .favorite : tab.spaceID == location.spaceID && tab.kind != .favorite) {
            let item: SidebarItemReference
            if let group = groups.first(where: { $0.tabIDs.contains(tab.id) }) {
                guard group.sidebarAnchorID == tab.id else { continue }
                item = .split(group.id)
            } else { item = .tab(tab.id) }
            // The tab is the item's (or its split's anchor's) own record, so
            // its location needn't be looked up again among every tab.
            if tabLocation(of: tab, spaceID: location.spaceID, profileID: profileID) == location { legacy.append(item) }
        }
        if location.section == .pinned {
            legacy += state.folders.filter { $0.spaceID == location.spaceID && $0.parentID == location.folderID }.map { .folder($0.id) }
        }
        // Persist a split at its original anchor. Creating/separating a split
        // therefore cannot erase that item's established mixed sibling slot.
        let stored = (state.sidebarItemOrder[location.key] ?? []).map { item -> SidebarItemReference in
            if case .tab(let id) = item, let group = groups.first(where: { $0.sidebarAnchorID == id }) { return .split(group.id) }
            return item
        }
        var seen = Set<SidebarItemReference>()
        let present = Set(legacy)
        return (stored + legacy).filter { present.contains($0) && seen.insert($0).inserted }
    }
    /// `children(in:state:)` of every pinned, Today and folder (pinned)
    /// container of a Space, keyed by location key, from one pass over the
    /// tabs; a container without children has no entry.
    static func childrenByContainer(spaceID: UUID, state: BrowserState) -> [String: [SidebarItemReference]] {
        guard let profileID = state.spaces.first(where: { $0.id == spaceID })?.profileID else { return [:] }
        let groups = SidebarSplitItems.groups(in: state, spaceID: spaceID)
        var legacy: [String: [SidebarItemReference]] = [:]
        for tab in state.tabs where tab.archivedAt == nil && tab.profileID == profileID && tab.spaceID == spaceID && tab.kind != .favorite {
            let item: SidebarItemReference
            if let group = groups.first(where: { $0.tabIDs.contains(tab.id) }) {
                guard group.sidebarAnchorID == tab.id else { continue }
                item = .split(group.id)
            } else { item = .tab(tab.id) }
            guard let location = tabLocation(of: tab, spaceID: spaceID, profileID: profileID) else { continue }
            legacy[location.key, default: []].append(item)
        }
        for folder in state.folders where folder.spaceID == spaceID {
            legacy[SidebarContainerLocation(spaceID: spaceID, folderID: folder.parentID, section: .pinned).key, default: []].append(.folder(folder.id))
        }
        var result: [String: [SidebarItemReference]] = [:]
        for (key, items) in legacy {
            let stored = (state.sidebarItemOrder[key] ?? []).map { item -> SidebarItemReference in
                if case .tab(let id) = item, let group = groups.first(where: { $0.sidebarAnchorID == id }) { return .split(group.id) }
                return item
            }
            var seen = Set<SidebarItemReference>()
            let present = Set(items)
            result[key] = (stored + items).filter { present.contains($0) && seen.insert($0).inserted }
        }
        return result
    }
    ///
    /// tab enters at index 0. Otherwise the scan starts at the referrer's whole
    /// root item, or the top when the referrer is pinned, a Favorite or outside
    /// this Today list, and passes that item plus following tabs opened from
    ///
    static func placingCreatedTab(_ id: UUID, insertion: TodayInsertion, in state: inout BrowserState) {
        guard let tab = state.tabs.first(where: { $0.id == id && $0.archivedAt == nil
                  && $0.kind == .today && $0.folderID == nil }) else { return }
        let location = SidebarContainerLocation(spaceID: tab.spaceID, folderID: nil, section: .today)
        var items = children(in: location, state: state)
        // A tab created directly into a split keeps that group's anchor slot.
        guard let current = items.firstIndex(of: .tab(id)) else { return }
        items.remove(at: current)
        var index = 0
        if insertion == .automatic, let referrer = tab.referrerID {
            let snapshot = state
            func holdsReferrer(_ item: SidebarItemReference) -> Bool {
                tabIDs(in: item, state: snapshot, spaceID: tab.spaceID).contains(referrer)
            }
            let start = items.firstIndex(where: holdsReferrer) ?? 0
            index = items[start...].firstIndex { item in
                if holdsReferrer(item) { return false }
                guard case .tab(let other) = item else { return true }
                return snapshot.tabs.first { $0.id == other }?.referrerID != referrer
            } ?? items.endIndex
        }
        items.insert(.tab(id), at: index)
        state.sidebarItemOrder[location.key] = items.map { storedReference($0, state: state) }
    }
    private static func storedReference(_ item: SidebarItemReference, state: BrowserState) -> SidebarItemReference {
        if case .split(let id) = item, let anchor = state.splitLayouts.first(where: { $0.id == id })?.sidebarAnchorID { return .tab(anchor) }
        return item
    }
    static func tabIDs(in item: SidebarItemReference, state: BrowserState, spaceID: UUID) -> [UUID] {
        switch item {
        case .tab(let id): return [id]
        case .split(let id): return SidebarSplitItems.groups(in: state, spaceID: spaceID).first { $0.id == id }?.tabIDs ?? []
        case .folder(let id):
            var result: [UUID] = [], visited = Set<UUID>()
            func collect(_ folderID: UUID) {
                guard visited.insert(folderID).inserted else { return }
                for child in children(in: .init(spaceID: spaceID, folderID: folderID, section: .pinned), state: state) {
                    if case .folder(let nested) = child { collect(nested) }
                    else { result += tabIDs(in: child, state: state, spaceID: spaceID) }
                }
            }
            collect(id); var seen = Set<UUID>(); return result.filter { seen.insert($0).inserted }
        }
    }
    static func moving(_ item: SidebarItemReference, to destination: SidebarContainerLocation,
                       before: SidebarItemReference?, expected: SidebarHierarchySnapshot,
                       state: BrowserState) -> BrowserState? {
        guard SidebarHierarchySnapshot(state: state, spaceID: expected.spaceID, profileID: expected.profileID, includesFavorites: expected.includesFavorites) == expected,
              destination.spaceID == expected.spaceID,
              destination.section != .favorite || (expected.includesFavorites && destination.profileID == expected.profileID && destination.folderID == nil),
              let source = location(of: item, state: state, spaceID: expected.spaceID),
              destination.folderID == nil || (destination.section == .pinned && state.folders.contains {
                  $0.id == destination.folderID && $0.spaceID == destination.spaceID
              }) else { return nil }
        if case .folder(let id) = item {
            guard destination.section == .pinned else { return nil }
            var ancestor = destination.folderID
            while let current = ancestor {
                guard current != id else { return nil }
                ancestor = state.folders.first { $0.id == current }?.parentID
            }
        }
        let sourceChildren = children(in: source, state: state)
        let destinationChildren = children(in: destination, state: state)
        guard sourceChildren.contains(item), before != item,
              before == nil || destinationChildren.contains(before!) else { return nil }
        let ids = tabIDs(in: item, state: state, spaceID: expected.spaceID)
        guard ids.allSatisfy({ id in expected.tabs.contains { $0.id == id } }),
              source.section != .favorite || expected.includesFavorites else { return nil }
        if case .split(let id) = item {
            guard let group = expected.groups.first(where: { $0.id == id }), group.tabIDs.count > 1,
                  group.tabIDs == ids, Set(ids).count == ids.count,
                  BrowserSplitLayout.normalized(group.widthFactors, count: ids.count) != nil,
                  ids.allSatisfy({ id in expected.tabs.contains {
                      // Ordinary split children keep their original kind/folder
                      // until this explicit whole-group placement assigns all
                      // of them to the requested destination. Favorites remain
                      // a separate, uniformly profile-wide collection.
                      $0.id == id && $0.profileID == expected.profileID &&
                          (source.section == .favorite
                              ? $0.kind == .favorite && $0.folderID == nil
                              : $0.kind != .favorite && $0.spaceID == expected.spaceID)
                  } }) else { return nil }
        }
        var next = state
        switch item {
        case .folder(let id):
            let index = next.folders.firstIndex { $0.id == id }!
            next.folders[index].parentID = destination.folderID
        case .tab, .split:
            for index in next.tabs.indices where ids.contains(next.tabs[index].id) {
                if next.tabs[index].kind != destination.section && (next.tabs[index].kind == .today || destination.section == .today) {
                    next.tabs[index].savedURL = next.tabs[index].url
                    next.tabs[index].savedTitle = next.tabs[index].title
                }
                next.tabs[index].kind = destination.section
                next.tabs[index].folderID = destination.folderID
                if source.section == .favorite && destination.section != .favorite { next.tabs[index].spaceID = destination.spaceID }
            }
        }
        if case .split(let id) = item, source.section == .favorite, destination.section != .favorite,
           let index = next.splitLayouts.firstIndex(where: { $0.id == id }) { next.splitLayouts[index].spaceID = destination.spaceID }
        let storedItem = storedReference(item, state: state)
        for key in next.sidebarItemOrder.keys { next.sidebarItemOrder[key]?.removeAll { $0 == item || $0 == storedItem } }
        next.sidebarItemOrder[source.key] = sourceChildren.filter { $0 != item }.map { storedReference($0, state: next) }
        var ordered = destinationChildren.filter { $0 != item }
        let position = before.flatMap { ordered.firstIndex(of: $0) } ?? ordered.count
        ordered.insert(item, at: position)
        next.sidebarItemOrder[destination.key] = ordered.map { storedReference($0, state: next) }
        if destination.section == .favorite, ordered.count > 12 { return nil }
        if let folderID = destination.folderID, let index = next.folders.firstIndex(where: { $0.id == folderID }) {
            next.folders[index].isExpanded = true
        }
        return next
    }
}


/// A typed document reference retains the original profile and document, never
/// a second document serialized from its URL. The real store supplies the pure
/// validity check; creating another sidebar alias does not finish an editor draft.
struct SidebarDocumentReference {
    let page: InternalPage
    let profileID: UUID
    private let validate: @MainActor () throws -> Void
    init(page: InternalPage, profileID: UUID, validate: @escaping @MainActor () throws -> Void) {
        self.page = page; self.profileID = profileID; self.validate = validate
    }
    @MainActor func isCurrent() -> Bool { do { try validate(); return true } catch { return false } }
    /// Archive/Undo consumes existing typed identities, never a document writer.
    @MainActor static func validates(_ originals: [BrowserTab], references: [UUID: Self]) -> Bool {
        guard Set(references.keys).isSubset(of: Set(originals.map(\.id))) else { return false }
        return originals.allSatisfy { original in
            guard let page = InternalPage(urlString: original.savedURL) else {
                return !InternalPage.isInternal(original.savedURL) && references[original.id] == nil
            }
            guard let reference = references[original.id], reference.page == page,
                  reference.profileID == original.profileID else { return false }
            return reference.isCurrent()
        }
    }
}

struct SidebarCopySources {
    var destinations: [UUID: String] = [:]
    var documents: [UUID: SidebarDocumentReference] = [:]
    @MainActor func validates(_ originals: [BrowserTab]) -> Bool {
        guard Set(destinations.keys) == Set(originals.map(\.id)),
              Set(documents.keys).isSubset(of: Set(originals.map(\.id))) else { return false }
        return originals.allSatisfy { original in
            guard let destination = destinations[original.id] else { return false }
            if let page = InternalPage(urlString: original.savedURL) {
                guard let reference = documents[original.id], reference.page == page,
                      reference.profileID == original.profileID,
                      InternalPage(urlString: destination) == page else { return false }
                return reference.isCurrent()
            }
            return documents[original.id] == nil && FolderDuplicateTarget.validDestination(original.savedURL)
                && FolderDuplicateTarget.validDestination(destination)
        }
    }
}

/// A folder command binds its original tree and saved items. Live destinations
/// are resolved by the owning window at invocation, never by a global current tab.
/// One original ordered collection. The command-bar source already normalizes
/// ancestor ownership and validates whole splits; context copies additionally
/// reject Favorites and retain every original saved record for stale refusal.
struct SidebarDuplicateTarget: Equatable {
    let source: CommandBarFolderMoveSource
    let folderIDs: [UUID]
    let tabs: [BrowserTab]
    let groups: [BrowserSplitLayout]
    var roots: [SidebarItemReference] { source.roots }
    var hierarchy: SidebarHierarchySnapshot { source.hierarchy }

    init?(items: [SidebarItemReference], spaceID: UUID, profileID: UUID, state: BrowserState) {
        guard items.allSatisfy({ SidebarHierarchy.location(of: $0, state: state, spaceID: spaceID) != nil }),
              let source = CommandBarFolderMoveSource(items: items, spaceID: spaceID, profileID: profileID, state: state) else { return nil }
        let tabs = source.tabIDs.compactMap { id in state.tabs.first { $0.id == id } }
        guard tabs.count == source.tabIDs.count, tabs.allSatisfy({
            $0.kind != .favorite && $0.spaceID == spaceID && $0.profileID == profileID
                && $0.archivedAt == nil && ($0.folderID == nil || $0.kind == .pinned)
                && FolderDuplicateTarget.validSource($0.savedURL)
        }) else { return nil }
        var folders: [UUID] = [], groupIDs: [UUID] = []
        func collect(_ item: SidebarItemReference) -> Bool {
            if case .split(let id) = item { groupIDs.append(id); return true }
            guard case .folder(let id) = item else { return true }
            guard !folders.contains(id) else { return false }
            folders.append(id)
            return SidebarHierarchy.children(in: .init(spaceID: spaceID, folderID: id, section: .pinned), state: state).allSatisfy(collect)
        }
        guard source.roots.allSatisfy(collect),
              Set(state.tabs.filter { $0.archivedAt == nil && $0.folderID.map(folders.contains) == true }.map(\.id)).isSubset(of: Set(source.tabIDs)) else { return nil }
        let groups = groupIDs.compactMap { id in source.hierarchy.groups.first { $0.id == id } }
        guard groups.count == source.groupIDs.count, Set(groupIDs) == Set(source.groupIDs), groups.allSatisfy({ group in
            group.tabIDs.count > 1 && Set(group.tabIDs).count == group.tabIDs.count
                && group.sidebarAnchorID.map(group.tabIDs.contains) == true
                && BrowserSplitLayout.normalized(group.widthFactors, count: group.tabIDs.count) != nil
                && Set(tabs.filter { group.tabIDs.contains($0.id) }.map(\.folderID)).count == 1
                && Set(tabs.filter { group.tabIDs.contains($0.id) }.map(\.kind)).count == 1
        }) else { return nil }
        self.source = source; folderIDs = folders; self.tabs = tabs; self.groups = groups
    }
}

/// The single-folder public entry is the same collection transaction, not a
/// separate copy loop with independently visible saves.
struct FolderDuplicateTarget: Equatable {
    let folderID: UUID
    let collection: SidebarDuplicateTarget
    var hierarchy: SidebarHierarchySnapshot { collection.hierarchy }
    var folderIDs: [UUID] { collection.folderIDs }
    var tabs: [BrowserTab] { collection.tabs }
    var groups: [BrowserSplitLayout] { collection.groups }

    init?(folderID: UUID, spaceID: UUID, profileID: UUID, state: BrowserState) {
        guard let collection = SidebarDuplicateTarget(items: [.folder(folderID)], spaceID: spaceID, profileID: profileID, state: state) else { return nil }
        self.folderID = folderID; self.collection = collection
    }

    static func validSource(_ value: String) -> Bool {
        InternalPage(urlString: value) != nil || validDestination(value)
    }
    static func validDestination(_ value: String) -> Bool {
        // Renderer destinations remain separate from typed document aliases.
        guard !InternalPage.isInternal(value), let url = URL(string: value),
              let scheme = url.scheme, !scheme.isEmpty else { return false }
        return true
    }
}

struct SidebarDuplicateResult {
    let roots: [SidebarItemReference]
    let tabIDs: [UUID]
    let openTabIDs: [UUID]
}

/// The originals of an Option-drag copy of whole splits (SP23): ordinary or
///
///
///
struct SidebarSplitCopy: Equatable {
    let collection: SidebarMoveCollection
    let groups: [BrowserSplitLayout]
    var roots: [SidebarItemReference] { collection.roots }
    var tabs: [BrowserTab] { collection.tabs }
    var source: SidebarHierarchySnapshot { collection.hierarchy }

    init?(items: [SidebarItemReference], spaceID: UUID, profileID: UUID, state: BrowserState) {
        guard !items.isEmpty, items.allSatisfy({ if case .split = $0 { return true } else { return false } }),
              let collection = SidebarMoveCollection(items: items, spaceID: spaceID, profileID: profileID, state: state),
              collection.folderIDs.isEmpty, collection.tabs.count == collection.tabIDs.count,
              collection.tabs.allSatisfy({ $0.archivedAt == nil && FolderDuplicateTarget.validSource($0.savedURL) }) else { return nil }
        let groups = collection.roots.compactMap { root -> BrowserSplitLayout? in
            guard case .split(let id) = root else { return nil }
            return collection.hierarchy.groups.first { $0.id == id }
        }
        guard groups.count == collection.roots.count,
              groups.flatMap(\.tabIDs) == collection.tabIDs else { return nil }
        self.collection = collection; self.groups = groups
    }

    /// The same splits in the same place: group identity and geometry, child
    /// IDs and each child's Profile, Space, section and folder. Titles, URLs,
    /// activity and unrelated items may change while a decision is pending.
    func matchesPlacement(of other: SidebarSplitCopy) -> Bool {
        func placement(_ tab: BrowserTab) -> [String] {
            [tab.id.uuidString, tab.profileID.uuidString, tab.spaceID.uuidString, tab.kind.rawValue, tab.folderID?.uuidString ?? ""]
        }
        return roots == other.roots && groups == other.groups && collection.tabIDs == other.collection.tabIDs
            && source.spaceID == other.source.spaceID && source.profileID == other.source.profileID
            && tabs.map(placement) == other.tabs.map(placement)
    }
}

struct FolderDuplicateResult {
    let folderID: UUID
    let tabIDs: [UUID]
    ///
    /// folder-tab descendants remain saved-only until selected.
    let openTabIDs: [UUID]
}

/// The Delete command binds the original folder subtree and archives its
/// sidebar references. Typed Notes/Easels remain in their document stores. It is
/// separate from Close (unload saved tabs) and from archiving a folder itself.
/// One captured collection. Selected ancestors own their descendants; split
/// panes remain a single root. The single-folder entry shares this transaction.
struct FolderRemovalTarget: Equatable {
    let roots: [SidebarItemReference]
    let name: String
    let hierarchy: SidebarHierarchySnapshot
    let folderIDs: [UUID]
    let tabs: [BrowserTab]
    let groups: [BrowserSplitLayout]

    init?(folderID: UUID, spaceID: UUID, profileID: UUID, state: BrowserState) {
        self.init(items: [.folder(folderID)], spaceID: spaceID, profileID: profileID, state: state)
    }

    init?(items: [SidebarItemReference], spaceID: UUID, profileID: UUID, state: BrowserState) {
        guard let hierarchy = SidebarHierarchySnapshot(state: state, spaceID: spaceID, profileID: profileID),
              let roots = SidebarHierarchy.roots(items, state: state, spaceID: spaceID), !roots.isEmpty else { return nil }
        var folders: [UUID] = [], tabIDs: [UUID] = []
        func collect(_ item: SidebarItemReference) -> Bool {
            switch item {
            case .folder(let id):
                guard !folders.contains(id) else { return false }
                folders.append(id)
                for child in SidebarHierarchy.children(in: .init(spaceID: spaceID, folderID: id, section: .pinned), state: state) {
                    if !collect(child) { return false }
                }
            case .tab(let id): tabIDs.append(id)
            case .split(let id):
                guard let split = hierarchy.groups.first(where: { $0.id == id }) else { return false }
                tabIDs += split.tabIDs
            }
            return true
        }
        guard roots.allSatisfy(collect), Set(tabIDs).count == tabIDs.count else { return nil }
        let tabs = tabIDs.compactMap { id in state.tabs.first { $0.id == id } }
        guard tabs.count == tabIDs.count, tabs.allSatisfy({
            $0.spaceID == spaceID && $0.profileID == profileID && $0.kind != .favorite && $0.archivedAt == nil
                && ($0.folderID == nil || $0.kind == .pinned)
                && FolderDuplicateTarget.validSource($0.savedURL)
        }), Set(state.tabs.filter { $0.archivedAt == nil && $0.folderID.map(folders.contains) == true }.map(\.id)).isSubset(of: Set(tabIDs)) else { return nil }
        let groups = hierarchy.groups.filter { !$0.tabIDs.allSatisfy { !tabIDs.contains($0) } }
        guard groups.allSatisfy({ split in
            Set(split.tabIDs).count == split.tabIDs.count && split.tabIDs.allSatisfy(tabIDs.contains)
                && Set(tabs.filter { split.tabIDs.contains($0.id) }.map(\.folderID)).count == 1
                && BrowserSplitLayout.normalized(split.widthFactors, count: split.tabIDs.count) != nil
        }) else { return nil }
        self.roots = roots
        if roots.count == 1, case .folder(let id) = roots[0] { name = hierarchy.folders.first { $0.id == id }!.name }
        else { name = "Selected Items" }
        self.hierarchy = hierarchy; folderIDs = folders; self.tabs = tabs; self.groups = groups
    }
}

/// Keyboard Close classifies the selected original sidebar roots, not each
///
/// collection when any original item belongs to Today; a saved-only collection
/// instead deselects/unloads its content and retains the saved references.
struct SidebarKeyboardCloseTarget: Equatable {
    let items: FolderRemovalTarget
    let archivesItems: Bool

    init?(items: [SidebarItemReference], spaceID: UUID, profileID: UUID, state: BrowserState) {
        guard let target = FolderRemovalTarget(items: items, spaceID: spaceID,
                                               profileID: profileID, state: state) else { return nil }
        self.items = target
        archivesItems = target.roots.contains {
            SidebarHierarchy.location(of: $0, state: state, spaceID: spaceID)?.section == .today
        }
    }

    // Ordinary tab Close has no extra Parc warning. A mixed command containing
    // an ordinary folder keeps the actual folder-deletion confirmation.
    var requiresConfirmation: Bool { archivesItems && !items.folderIDs.isEmpty }
}

/// One original-window close group, not a snapshot of the browser store. The
/// archived afterimages authorize restoration of these exact saved identities.
///
/// regroup actions; its separate folder-archive feature is not required.
struct FolderDeletionUndo {
    let id = UUID()
    let roots: [SidebarItemReference]
    let spaceID: UUID, profileID: UUID
    let folders: [BrowserFolder]
    let tabs: [BrowserTab]
    let archivedTabs: [BrowserTab]
    let documentReferences: [UUID: SidebarDocumentReference]
    let groups: [BrowserSplitLayout]
    struct Location {
        let container: SidebarContainerLocation
        let siblings: [SidebarItemReference]
    }
    let locations: [Location]
    let childOrder: [String: [SidebarItemReference]]
    let detachedArchive: [BrowserTab]
    let focusedTabID: UUID?

    var actionName: String { tabs.count == 1 ? "Archive Tab" : "Archive Tabs" }

    @MainActor var documentsAreAvailable: Bool {
        SidebarDocumentReference.validates(tabs, references: documentReferences)
    }

    fileprivate init(target: FolderRemovalTarget, selection: FolderRemovalSelection?,
                     documents: [UUID: SidebarDocumentReference], before: BrowserState, after: BrowserState) {
        documentReferences = documents
        roots = target.roots
        spaceID = target.hierarchy.spaceID; profileID = target.hierarchy.profileID
        folders = target.hierarchy.folders.filter { target.folderIDs.contains($0.id) }
        tabs = target.tabs; groups = target.groups
        archivedTabs = target.tabs.compactMap { original in after.tabs.first { $0.id == original.id } }
        var seen = Set<String>()
        locations = target.roots.compactMap { root in
            guard let container = SidebarHierarchy.location(of: root, state: before, spaceID: target.hierarchy.spaceID),
                  seen.insert(container.key).inserted else { return nil }
            return Location(container: container, siblings: SidebarHierarchy.children(in: container, state: before))
        }
        childOrder = Dictionary(uniqueKeysWithValues: folders.map { folder in
            let location = SidebarContainerLocation(spaceID: target.hierarchy.spaceID, folderID: folder.id, section: .pinned)
            return (location.key, SidebarHierarchy.children(in: location, state: before).map { item in
                if case .split(let id) = item, let anchor = target.groups.first(where: { $0.id == id })?.sidebarAnchorID { return .tab(anchor) }
                return item
            })
        })
        detachedArchive = before.tabs.filter { $0.archivedAt != nil && $0.folderID.map(target.folderIDs.contains) == true }
        focusedTabID = selection?.originalFocus.flatMap { focus in target.tabs.contains { $0.id == focus } ? focus : nil }
    }

    /// Navigation/title changes after Undo are legitimate. Redo still closes
    /// only the recorded tree and original members, never newly added children.
    func redoTarget(in state: BrowserState) -> FolderRemovalTarget? {
        guard let target = FolderRemovalTarget(items: roots, spaceID: spaceID, profileID: profileID, state: state),
              locations.allSatisfy({ location in
                  location.siblings.filter(roots.contains).allSatisfy {
                      SidebarHierarchy.location(of: $0, state: state, spaceID: spaceID) == location.container
                  }
              }),
              Set(target.folderIDs) == Set(folders.map(\.id)),
              Set(target.tabs.map(\.id)) == Set(tabs.map(\.id)),
              target.tabs.allSatisfy({ tab in tabs.contains { $0.id == tab.id && $0.folderID == tab.folderID } }),
              target.hierarchy.folders.filter({ target.folderIDs.contains($0.id) }).allSatisfy({ folder in
                  folders.contains { $0.id == folder.id && $0.parentID == folder.parentID }
              }), target.groups.count == groups.count,
              target.groups.allSatisfy({ group in groups.contains { $0.id == group.id && $0.tabIDs == group.tabIDs } }) else { return nil }
        return target
    }
}

///
///
/// It holds the pre-close records and archived afterimages, not a store
///
struct ClosedTabsUndo {
    ///
    ///
    ///
    ///
    ///
    enum Prompt {
        case clear, archive
        ///
        ///
        func name(count: Int) -> String {
            switch self {
            case .clear: return count == 1 ? "Clear Tab" : "Clear Tabs"
            case .archive: return count == 1 ? "Archive Tab" : "Archive Tabs"
            }
        }
    }
    let prompt: Prompt
    let spaceID: UUID, profileID: UUID
    /// Pre-close records in model order.
    let tabs: [BrowserTab]
    /// Their archived afterimages. Empty when the close removed them, as a
    /// private window's does.
    let archivedTabs: [BrowserTab]
    /// Every split the close touched, with its pre-close geometry.
    let groups: [BrowserSplitLayout]
    ///
    /// into the survivor, or regroupItems when this close dissolved it.
    let memberships: [UUID: ClosedSplitMembership]
    /// The Space's Today list before the close.
    let order: [SidebarItemReference]
    /// The window's focused tab, when this close took it. The shared
    ///
    /// configuration's focusedTabItemID with the focused item only when it is
    /// among the closed items, and Undo selects that one step's item
    ///
    let focusedTabID: UUID?

    var actionName: String { prompt.name(count: itemCount(of: Set(tabs.map(\.id)))) }
    /// Each tab, plus a split this close removes with its children
    ///
    func itemCount(of ids: Set<UUID>) -> Int {
        let closed = Set(tabs.map(\.id))
        let removed = groups.filter { group in
            group.tabIDs.allSatisfy(closed.contains)
                || memberships.values.contains { $0.layout.id == group.id && $0.dissolved }
        }
        return ids.count + removed.filter { !Set($0.tabIDs).isDisjoint(with: ids) }.count
    }
    ///
    ///
    func reopenedIDs(_ reopened: ClosedItemRecord) -> Set<UUID> {
        Set(reopened.tabs.filter { tab in archivedTabs.contains {
            $0.id == tab.id && $0.archivedAt == tab.archivedAt && $0.archiveProvenance == tab.archiveProvenance
        } }.map(\.id))
    }
    private var removesTabs: Bool { archivedTabs.isEmpty }
    private var location: SidebarContainerLocation { .init(spaceID: spaceID, folderID: nil, section: .today) }

    /// Nil when the close took nothing out of the sidebar: a saved tab's close
    ///
    init?(prompt: Prompt, ids: Set<UUID>, spaceID: UUID, profileID: UUID, focusedTabID: UUID?,
          before: BrowserState, after: BrowserState) {
        let candidates = before.tabs.filter { ids.contains($0.id) && $0.archivedAt == nil && $0.kind == .today
            && $0.folderID == nil && $0.spaceID == spaceID && $0.profileID == profileID }
        let archived = candidates.compactMap { original in after.tabs.first { $0.id == original.id && $0.archivedAt != nil } }
        let originals = archived.isEmpty
            ? candidates.filter { original in !after.tabs.contains { $0.id == original.id } }
            : candidates.filter { original in archived.contains { $0.id == original.id } }
        guard !originals.isEmpty else { return nil }
        let closed = Set(originals.map(\.id))
        self.prompt = prompt; self.spaceID = spaceID; self.profileID = profileID
        tabs = originals; archivedTabs = archived
        groups = before.splitLayouts.filter { $0.spaceID == spaceID && !closed.isDisjoint(with: $0.tabIDs) }
        let intent = ClosedItemIntent(ids: closed, state: before, spaceID: spaceID, profileID: profileID, focusedTabID: nil)
        var memberships: [UUID: ClosedSplitMembership] = [:]
        for id in closed { memberships[id] = intent?.membership(of: id, in: after) }
        self.memberships = memberships
        order = SidebarHierarchy.children(in: .init(spaceID: spaceID, folderID: nil, section: .today), state: before)
        self.focusedTabID = focusedTabID.flatMap { closed.contains($0) ? $0 : nil }
    }

    ///
    /// still archived by this close, by the identity an Archive preview checks,
    /// or one a private window's close removed. A tab reopened, put back,
    /// deleted or archived again stays as it is.
    func restorableIDs(in state: BrowserState) -> Set<UUID> {
        if removesTabs { return Set(tabs.filter { original in !state.tabs.contains { $0.id == original.id } }.map(\.id)) }
        return Set(archivedTabs.filter { recorded in state.tabs.contains { current in
            current.id == recorded.id && current.profileID == recorded.profileID
                && current.spaceID == recorded.spaceID && current.createdAt == recorded.createdAt
                && current.archivedAt == recorded.archivedAt && current.archiveProvenance == recorded.archiveProvenance
        } }.map(\.id))
    }

    /// Redo closes the recorded tabs that are live Today tabs again.
    func redoIDs(in state: BrowserState) -> Set<UUID> {
        Set(tabs.filter { original in state.tabs.contains {
            $0.id == original.id && $0.archivedAt == nil && $0.kind == .today && $0.folderID == nil
                && $0.spaceID == spaceID && $0.profileID == profileID
        } }.map(\.id))
    }

    /// The restored tabs, regrouped splits and Today positions, with
    /// unrelated state read from `state`. Selection is untouched. `regroupable`
    /// admits a surviving pane a restored one may rejoin.
    func restoring(_ state: BrowserState, regroupable: (UUID) -> Bool = { _ in true }) -> BrowserState? {
        let ids = restorableIDs(in: state)
        guard !ids.isEmpty else { return nil }
        var next = state
        for original in tabs where ids.contains(original.id) {
            guard let index = next.tabs.firstIndex(where: { $0.id == original.id }) else {
                next.tabs.append(original); continue
            }
            // Only its place and archive state return; a title or address
            // edited in the Archive since (a Note, say) is kept.
            next.tabs[index].archivedAt = original.archivedAt
            next.tabs[index].archiveProvenance = original.archiveProvenance
            next.tabs[index].kind = original.kind
            next.tabs[index].folderID = original.folderID
        }
        next.recentlyClosedIDs.removeAll { ids.contains($0) }
        // regroupItems: a split closed whole returns whole when every pane
        // does and none has joined another split.
        let closed = Set(tabs.map(\.id))
        var regrouped = Set<UUID>()
        for group in groups where group.tabIDs.allSatisfy({ closed.contains($0) && ids.contains($0) })
            && !next.splitLayouts.contains(where: { $0.id == group.id || !Set($0.tabIDs).isDisjoint(with: group.tabIDs) }) {
            next.splitLayouts.append(group); regrouped.insert(group.id)
        }
        var rejoined = Set<UUID>(), rejoinedGroups = Set<UUID>()
        for original in tabs where ids.contains(original.id) {
            guard let membership = memberships[original.id],
                  var group = membership.restoredLayout(restoring: original.id, in: next, available: regroupable) else { continue }
            // The pane that took over the split's sidebar slot during the close
            // hands it back, so Undo leaves the split as it was.
            if let anchor = membership.layout.sidebarAnchorID, group.tabIDs.contains(anchor) { group.sidebarAnchorID = anchor }
            next.splitLayouts.removeAll { $0.id == group.id }
            next.splitLayouts.append(group)
            rejoined.formUnion(group.tabIDs.filter(ids.contains)); rejoinedGroups.insert(group.id)
        }
        var entries: [SidebarItemReference] = []
        for item in order {
            guard case .split(let id) = item, let group = groups.first(where: { $0.id == id }) else { entries.append(item); continue }
            if regrouped.contains(id) { entries.append(item); continue }
            // A pane that did not regroup or rejoin returns alone in its split's slot.
            if !group.tabIDs.allSatisfy(closed.contains) { entries.append(item) }
            entries += group.tabIDs.filter { closed.contains($0) && !rejoined.contains($0) }.map { .tab($0) }
        }
        let restored = entries.filter { item in
            switch item {
            case .tab(let id): return ids.contains(id) && !rejoined.contains(id)
            case .split(let id): return regrouped.contains(id) || rejoinedGroups.contains(id)
            case .folder: return false
            }
        }
        //
        // returns to its slot even if losing that pane moved it.
        let rejoinedMembers = Set(next.splitLayouts.filter { rejoinedGroups.contains($0.id) }.flatMap(\.tabIDs))
        var siblings = SidebarHierarchy.children(in: location, state: state).filter { item in
            switch item {
            case .split(let id): return !rejoinedGroups.contains(id)
            case .tab(let id): return !rejoinedMembers.contains(id)
            case .folder: return true
            }
        }
        for root in restored where !siblings.contains(root) {
            guard let position = entries.firstIndex(of: root) else { continue }
            let following = entries.dropFirst(position + 1).first { siblings.contains($0) }
            let preceding = entries.prefix(position).reversed().first { siblings.contains($0) }
            let insertion = following.flatMap { siblings.firstIndex(of: $0) }
                ?? preceding.flatMap { siblings.firstIndex(of: $0).map { $0 + 1 } }
                ?? min(position, siblings.count)
            siblings.insert(root, at: insertion)
        }
        // A survivor that a restored pane regrouped with now stands for the split.
        let shown = SidebarSplitItems.groups(in: next, spaceID: spaceID)
        var seen = Set<SidebarItemReference>()
        let roots = siblings.map { item -> SidebarItemReference in
            if case .tab(let id) = item, let group = shown.first(where: { $0.tabIDs.contains(id) }) { return .split(group.id) }
            return item
        }.filter { seen.insert($0).inserted }
        next.sidebarItemOrder[location.key] = roots.map { item in
            if case .split(let id) = item, let anchor = next.splitLayouts.first(where: { $0.id == id })?.sidebarAnchorID { return .tab(anchor) }
            return item
        }
        return next
    }
}

///
/// nextItemToSelect before close; the saved deletion and this selection publish
/// together. Referrer/creation-history branches are not inferred from URLs.
struct FolderRemovalSelection: Equatable {
    let spaceID: UUID, profileID: UUID
    let original: [UUID]
    let originalFocus: UUID?
    let tabIDs: [UUID]
    let focusedTabID: UUID?
    let removed: Set<UUID>
    let referrerPool: Set<UUID>
    let previouslySelectedItemID: UUID?
    let replacementSpaceID: UUID

    init(spaceID: UUID, profileID: UUID, original: [UUID], originalFocus: UUID?,
         tabIDs: [UUID], focusedTabID: UUID?, removed: Set<UUID> = [], referrerPool: Set<UUID> = [],
         previouslySelectedItemID: UUID? = nil, replacementSpaceID: UUID? = nil) {
        self.spaceID = spaceID; self.profileID = profileID; self.original = original
        self.originalFocus = originalFocus; self.tabIDs = tabIDs; self.focusedTabID = focusedTabID
        self.removed = removed; self.referrerPool = referrerPool
        self.previouslySelectedItemID = previouslySelectedItemID
        self.replacementSpaceID = replacementSpaceID ?? spaceID
    }

    static func resolve(target: FolderRemovalTarget, state: BrowserState,
                        selected: [UUID], focused: UUID?, referrerPool: Set<UUID> = [],
                        previouslySelectedItemID: UUID? = nil, available: (UUID) -> Bool) -> Self? {
        let space = target.hierarchy.spaceID, profile = target.hierarchy.profileID
        guard FolderRemovalTarget(items: target.roots, spaceID: space,
            profileID: profile, state: state) == target else { return nil }
        return resolve(removing: Set(target.tabs.map(\.id)), spaceID: space,
            profileID: profile, state: state, selected: selected, focused: focused, referrerPool: referrerPool,
            previouslySelectedItemID: previouslySelectedItemID, available: available)
    }

    /// Shared original-window close decision. The original IDs remain an
    /// anchor even after native unload; candidate pages are never recreated.
    static func resolve(removing removed: Set<UUID>, spaceID space: UUID,
                        profileID profile: UUID, state: BrowserState,
                        selected: [UUID], focused: UUID?, referrerPool: Set<UUID> = [],
                        previouslySelectedItemID: UUID? = nil, available: (UUID) -> Bool) -> Self? {
        guard state.spaces.contains(where: { $0.id == space && $0.profileID == profile }),
              selected.count <= 4, Set(selected).count == selected.count,
              selected.allSatisfy({ id in state.tabs.contains {
                  $0.id == id && $0.archivedAt == nil && $0.profileID == profile
                      && ($0.spaceID == space || $0.kind == .favorite)
              } }), focused == nil || selected.contains(focused!) else { return nil }
        let survivors = selected.filter { !removed.contains($0) }
        func decision(_ ids: [UUID], focus: UUID?, replacementSpaceID: UUID? = nil) -> Self {
            .init(spaceID: space, profileID: profile, original: selected,
                  originalFocus: focused, tabIDs: ids, focusedTabID: focus, removed: removed, referrerPool: referrerPool,
                  previouslySelectedItemID: previouslySelectedItemID, replacementSpaceID: replacementSpaceID)
        }
        // Closing a background folder never selects a different page. A
        // surviving original pane retains focus; otherwise the pane that takes
        // the closed focused pane's place does, else the new last (SP32).
        if !survivors.isEmpty || selected.isEmpty {
            guard survivors.allSatisfy(available) else { return nil }
            return decision(survivors, focus: focused.flatMap { survivors.contains($0) ? $0 : nil }
                ?? BrowserSplitLayout.focusSuccessor(survivors, removedAt: focused.flatMap { selected.firstIndex(of: $0) }))
        }
        let current = focused ?? selected.first
        struct Item { let ids: [UUID]; let accessed: Date }
        var ordered: [Item] = [], visited = Set<UUID>(), assigned = Set<UUID>()
        let tabs = Dictionary(uniqueKeysWithValues: state.tabs.filter {
            $0.archivedAt == nil && $0.spaceID == space && $0.profileID == profile && $0.kind != .favorite
        }.map { ($0.id, $0) })
        func append(_ ids: [UUID]) {
            guard !ids.isEmpty, Set(ids).count == ids.count,
                  ids.allSatisfy({ tabs[$0] != nil && !assigned.contains($0) }) else { return }
            assigned.formUnion(ids)
            ordered.append(Item(ids: ids, accessed: ids.compactMap { tabs[$0]?.lastAccessed }.max()!))
        }
        func collect(_ parent: UUID?, section: TabKind) {
            for item in SidebarHierarchy.children(in: .init(spaceID: space, folderID: parent, section: section), state: state) {
                switch item {
                case .folder(let id):
                    if visited.insert(id).inserted { collect(id, section: .pinned) }
                case .tab(let id): append([id])
                case .split(let id):
                    if let group = state.splitLayouts.first(where: { $0.id == id && $0.spaceID == space }) {
                        append(group.tabIDs)
                    }
                }
            }
        }
        // The recovered close traversal descends folder children independently
        // of disclosure, and does not flatten a split into individual panes.
        collect(nil, section: .pinned); collect(nil, section: .today)
        func eligible(_ item: Item) -> Bool {
            item.ids.allSatisfy { !removed.contains($0) && available($0) }
        }
        let candidates = ordered.filter { eligible($0) || current.map($0.ids.contains) == true }
        if let current, let index = candidates.firstIndex(where: { $0.ids.contains(current) }) {
            //
            // genuine tab whose referrer is this closing item, before the
            // ordinary neighbor fallback. A split remains one item.
            for neighbor in [index - 1, index + 1] where candidates.indices.contains(neighbor) {
                let item = candidates[neighbor]
                if item.ids.count == 1, let id = item.ids.first,
                   tabs[id]?.referrerID == current, eligible(item) {
                    return decision(item.ids, focus: id)
                }
            }
            // 1025d2a20 walks forward through original items for a sibling
            // with the same explicit referrer, requiring both IDs in this
            // physical window's actual referrer pool.
            if referrerPool.contains(current), let referrer = tabs[current]?.referrerID {
                for item in candidates.dropFirst(index + 1) where item.ids.count == 1 {
                    if let id = item.ids.first, referrerPool.contains(id),
                       tabs[id]?.referrerID == referrer, eligible(item) {
                        return decision(item.ids, focus: id)
                    }
                }
            }
        }
        // 1025d332c: a Favorite is profile-wide; a pinned/Today return
        // belongs to this Space. Preserve a real split as one item.
        if let current, let previous = state.tabs.first(where: { $0.id == current })?.activeTabBeforeCreationID,
           referrerPool.contains(previous), !removed.contains(previous), available(previous),
           let tab = state.tabs.first(where: { $0.id == previous && $0.archivedAt == nil
               && $0.profileID == profile && ($0.kind == .favorite || $0.spaceID == space) }) {
            if tab.kind == .favorite { return decision([previous], focus: previous) }
            if let item = ordered.first(where: { $0.ids.contains(previous) }), eligible(item) {
                return decision(item.ids, focus: previous)
            }
        }
        //
        // compares outer itemContainer values, not immediate folder parents:
        // two Space containers require the same Space; a Favorite container
        // compares its Profile with the other Favorite or Space's Profile.
        if let current, let previous = previouslySelectedItemID, previous != current,
           let source = state.tabs.first(where: { $0.id == current && $0.archivedAt == nil && $0.profileID == profile }),
           let tab = state.tabs.first(where: { $0.id == previous && $0.archivedAt == nil && $0.profileID == profile }),
           !removed.contains(previous), available(previous),
           source.kind == .favorite || tab.kind == .favorite || source.spaceID == tab.spaceID,
           state.spaces.contains(where: { $0.id == tab.spaceID && $0.profileID == profile }) {
            let destination = tab.kind == .favorite ? space : tab.spaceID
            let groups = state.splitLayouts.filter { $0.tabIDs.contains(previous) }
            if groups.isEmpty {
                return decision([previous], focus: previous, replacementSpaceID: destination)
            }
            if groups.count == 1, let group = groups.first, group.spaceID == destination,
               (2...4).contains(group.tabIDs.count), Set(group.tabIDs).count == group.tabIDs.count,
               BrowserSplitLayout.normalized(group.widthFactors, count: group.tabIDs.count) != nil,
               group.tabIDs.allSatisfy({ id in
                   !removed.contains(id) && available(id) && state.tabs.contains {
                       $0.id == id && $0.archivedAt == nil && $0.profileID == profile
                           && $0.spaceID == destination && $0.kind == tab.kind && $0.folderID == tab.folderID
                   }
               }) {
                return decision(group.tabIDs, focus: previous, replacementSpaceID: destination)
            }
        }
        if let current, let index = candidates.firstIndex(where: { $0.ids.contains(current) }) {
            //
            // original closing item stays as the traversal anchor only.
            for neighbor in [index - 1, index + 1] where candidates.indices.contains(neighbor) {
                let item = candidates[neighbor]
                if eligible(item) { return decision(item.ids, focus: item.ids.first) }
            }
        }
        //
        // dates retain the source-owned mixed sidebar order in Parc.
        let fallback = ordered.enumerated().filter { eligible($0.element) }.sorted {
            if $0.element.accessed != $1.element.accessed { return $0.element.accessed > $1.element.accessed }
            return $0.offset < $1.offset
        }.first?.element.ids ?? []
        return decision(fallback, focus: fallback.first)
    }
}


/// Window-local sidebar selection, distinct from the pages visible in a split.
/// AppKit's outline proposals are represented explicitly for Parc's existing
/// view-backed rows. Anchor/focus are original item IDs, never row indices.
struct SidebarItemSelection: Equatable {
    private(set) var items: [SidebarItemReference] = []
    private(set) var singleItem: SidebarItemReference?
    private(set) var anchor: SidebarItemReference?
    private(set) var focus: SidebarItemReference?
    mutating func clear() { items = []; singleItem = nil; anchor = nil; focus = nil }
    /// The native outline's Select All proposal is its currently displayed rows;
    /// hidden descendants are included only by the later item action, not here.
    mutating func selectAll(order: [SidebarItemReference], active: SidebarItemReference?) {
        var seen = Set<SidebarItemReference>()
        let visible = order.filter { seen.insert($0).inserted }
        reconcile(order: visible)
        items = visible.count > 1 ? visible : []
        singleItem = visible.count == 1 ? visible.first : nil
        anchor = visible.first
        focus = focus.flatMap { visible.contains($0) ? $0 : nil }
            ?? active.flatMap { visible.contains($0) ? $0 : nil } ?? visible.first
    }
    mutating func reconcile(order: [SidebarItemReference]) {
        let allowed = Set(order)
        items.removeAll { !allowed.contains($0) }
        if let singleItem, !allowed.contains(singleItem) { self.singleItem = nil }
        if let anchor, !allowed.contains(anchor) { self.anchor = nil }
        if let focus, !allowed.contains(focus) { self.focus = nil }
        if items.count < 2 { items = [] }
    }
    mutating func select(_ item: SidebarItemReference, order: [SidebarItemReference],
                         active: SidebarItemReference?, extending: Bool, toggling: Bool) {
        guard order.contains(item) else { return }
        reconcile(order: order)
        let visibleActive = active.flatMap { order.contains($0) ? $0 : nil }
        var proposed = items.isEmpty ? visibleActive.map { [$0] } ?? [] : items
        if extending {
            let start = anchor ?? active ?? item
            if let a = order.firstIndex(of: start), let b = order.firstIndex(of: item) {
                let range = Array(order[min(a, b)...max(a, b)])
                proposed = toggling ? proposed + range : range
                anchor = start
            } else { proposed = [item]; anchor = item }
        } else if toggling {
            if let i = proposed.firstIndex(of: item) { proposed.remove(at: i) }
            else { proposed.append(item) }
            anchor = item
        } else { proposed = [item]; anchor = item }
        //
        if proposed.count > 1, let active, order.contains(active) { proposed.append(active) }
        let selected = Set(proposed)
        items = order.filter { selected.contains($0) }
        singleItem = items.count == 1 ? items.first : (items.isEmpty ? visibleActive : nil)
        if items.count < 2 { items = [] }
        focus = item
    }
}

extension SidebarHierarchy {
    /// Ancestor selection owns its subtree; preserve visible original order and
    /// remove duplicate descendants before a bulk mutation.
    static func roots(_ items: [SidebarItemReference], state: BrowserState, spaceID: UUID) -> [SidebarItemReference]? {
        guard !items.isEmpty, Set(items).count == items.count,
              items.allSatisfy({ location(of: $0, state: state, spaceID: spaceID) != nil }) else { return nil }
        let folders = Set(items.compactMap { if case .folder(let id) = $0 { return id }; return nil })
        return items.filter { item in
            var parent = location(of: item, state: state, spaceID: spaceID)?.folderID
            var seen = Set<UUID>()
            while let id = parent {
                guard seen.insert(id).inserted else { return false }
                if folders.contains(id) { return false }
                parent = state.folders.first { $0.id == id && $0.spaceID == spaceID }?.parentID
            }
            return true
        }
    }
    static func moving(_ items: [SidebarItemReference], to destination: SidebarContainerLocation,
                       before: SidebarItemReference?, expected: SidebarHierarchySnapshot,
                       state: BrowserState) -> BrowserState? {
        guard SidebarHierarchySnapshot(state: state, spaceID: expected.spaceID, profileID: expected.profileID, includesFavorites: expected.includesFavorites) == expected,
              let sources = roots(items, state: state, spaceID: expected.spaceID),
              !sources.isEmpty, before == nil || !items.contains(before!) else { return nil }
        var next = state
        for item in sources {
            guard let current = SidebarHierarchySnapshot(state: next, spaceID: expected.spaceID, profileID: expected.profileID, includesFavorites: expected.includesFavorites),
                  let proposal = moving(item, to: destination, before: before, expected: current, state: next) else { return nil }
            next = proposal
        }
        if destination.section == .favorite, children(in: destination, state: next).count > 12 { return nil }
        return next
    }
}

/// Public browser addresses. Chromium still owns the actual WebUI origin and
/// request; this projection never touches an HTTP URL, embedded URL, or query.
enum BrowserInternalURL {
    static func publicString(_ input: String) -> String {
        guard var value = URLComponents(string: input),
              value.scheme?.lowercased() == "chrome", value.host?.isEmpty == false,
              !["easel", "note"].contains(value.host?.lowercased() ?? "") else { return input }
        value.scheme = "parc"
        return value.string ?? input
    }
    static func isWebUI(_ url: URL) -> Bool {
        ["parc", "chrome"].contains(url.scheme?.lowercased() ?? "") &&
            url.host?.isEmpty == false && !InternalPage.isInternal(url.absoluteString)
    }
}

enum InternalPage: Equatable {
    case easel(UUID), note(UUID)
    init?(urlString: String) {
        guard let value = URLComponents(string: urlString), value.scheme?.lowercased() == "parc",
              ["easel", "note"].contains(value.host?.lowercased() ?? ""), value.user == nil, value.password == nil,
              value.port == nil, value.query == nil, value.fragment == nil,
              value.path.hasPrefix("/"), let id = UUID(uuidString: String(value.path.dropFirst())) else { return nil }
        self = value.host?.lowercased() == "note" ? .note(id) : .easel(id)
    }
    var urlString: String {
        switch self {
        case .easel(let id): return "parc://easel/" + id.uuidString.lowercased()
        case .note(let id): return "parc://note/" + id.uuidString.lowercased()
        }
    }
    var easelID: UUID? { if case let .easel(id) = self { return id }; return nil }
    var noteID: UUID? { if case let .note(id) = self { return id }; return nil }
    var untitledTitle: String { noteID != nil ? "Untitled Note" : "Untitled Easel" }
    ///
    var sidebarFallbackSymbol: String {
        switch self {
        case .note: return "note.text"
        case .easel: return "square.on.square"
        }
    }
    static func sidebarFallbackSymbol(urlString: String) -> String {
        InternalPage(urlString: urlString)?.sidebarFallbackSymbol ?? "globe"
    }
    static func isInternal(_ input: String) -> Bool {
        guard let value = URLComponents(string: input) else { return false }
        return value.scheme?.lowercased() == "parc" && ["easel", "note"].contains(value.host?.lowercased() ?? "")
    }
}

enum NavigationInput {
    static func resolve(_ input: String, searchEngine: String = "https://duckduckgo.com/?q=") -> URL? {
        let value = BrowserInternalURL.publicString(input.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !value.isEmpty, !InternalPage.isInternal(value),
              URL(string: value)?.scheme?.lowercased() != "arc" else { return nil }
        if let url = URL(string: value), url.scheme?.lowercased() == "parc" {
            return url.host?.isEmpty == false ? url : nil
        }
        if let url = URL(string: value), let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "about", "chrome"].contains(scheme) {
            return url
        }
        let host = String(value.split(separator: "/", maxSplits: 1).first ?? "")
        if !value.contains(where: { $0.isWhitespace }),
           (host.contains(".") || host == "localhost" || host.hasPrefix("localhost:") || host.hasPrefix("[")),
           let url = URL(string: "https://" + value), url.host != nil {
            if host.hasPrefix("localhost") || host.hasPrefix("127.0.0.1") || host.hasPrefix("[::1]") {
                return URL(string: "http://" + value)
            }
            return url
        }
        let engines = ["duckduckgo": "https://duckduckgo.com/?q=", "google": "https://www.google.com/search?q=", "bing": "https://www.bing.com/search?q="]
        guard var components = URLComponents(string: engines[searchEngine.lowercased()] ?? searchEngine),
              ["https", "http"].contains(components.scheme ?? "") else { return nil }
        var items = components.queryItems ?? []
        if let index = items.lastIndex(where: { ($0.value ?? "").isEmpty }) {
            items[index].value = value
        } else {
            items.append(URLQueryItem(name: "q", value: value))
        }
        components.queryItems = items
        return components.url
    }
}

/// A window Undo payload outlives the transient theme editor. Only the captured
/// Space's theme is replaced; its name, icon, ordering and tabs remain current.
struct SpaceThemeChange: Equatable {
    let spaceID: UUID
    let profileID: UUID
    let previousTheme: SpaceTheme
    let theme: SpaceTheme
    var actionName: String { "Update Theme" }

    func target(in state: BrowserState, undo: Bool) -> BrowserSpace? {
        guard state.profiles.contains(where: { $0.id == profileID }) else { return nil }
        return state.spaces.first {
            $0.id == spaceID && $0.profileID == profileID && $0.theme == (undo ? theme : previousTheme)
        }
    }
}

@MainActor
final class BrowserStore: ObservableObject {
    /// Published snapshot. Activity-only `lastAccessed` stamps install through
    /// `activityOnlyState` so archive/session persistence sees them without a
    /// `@Published` UI fan-out (sidebar/window sinks, `stateRevision` caches).
    /// Default satisfies definite initialization; inits overwrite before use.
    @Published private var publishedState: BrowserState = .initial() {
        didSet { stateRevision &+= 1 }
    }
    /// Overlay installed by `refreshVisibleTabs` when only access dates change.
    /// Cleared on the next published assign. Reads prefer this over `publishedState`.
    private var activityOnlyState: BrowserState?
    /// Current model state. Distinct assignments clear any activity overlay and
    /// publish. Identical assigns are true no-ops: `@Published` would still fan
    /// out sidebar/window sinks on equal writes (for example `changed()`
    /// rewriting `selectionBySpace` to the same ids after `updateTab`).
    private(set) var state: BrowserState {
        get { activityOnlyState ?? publishedState }
        set {
            let current = activityOnlyState ?? publishedState
            guard newValue != current else { return }
            activityOnlyState = nil
            publishedState = newValue
            // A Space moved off its previewed theme (another editor, removal) ends that preview.
            if !themePreviews.isEmpty {
                themePreviews = themePreviews.filter { id, entry in
                    newValue.spaces.contains { $0.id == id && $0.theme == entry.preview }
                }
            }
        }
    }
    /// Replay's live Space themes. Windows render them from `state`; every
    /// session write keeps the saved theme until Finish commits the preview.
    private var themePreviews: [UUID: (saved: SpaceTheme, preview: SpaceTheme)] = [:]
    /// Former `$state` Combine surface; emits only on published assigns.
    var statePublisher: Published<BrowserState>.Publisher { $publishedState }
    /// Changes with every state publication; drop proposals cache against it.
    private(set) var stateRevision: UInt64 = 0
    /// Changes only when visit records change, so History and command-bar
    /// recents can skip rebuilding against unrelated publications.
    private(set) var historyRevision: UInt64 = 0
    @Published private(set) var persistenceError: String?
    @Published private(set) var autoArchiveEducationPending = false
    // The shared Library projects these live manager records without placing
    // them in BrowserState or its durable session file.
    @Published private(set) var transientDownloads: [BrowserDownload] = []
    var downloadItems: [BrowserDownload] {
        let profiles = Set(state.profiles.map(\.id))
        return state.downloads + transientDownloads.filter { $0.profileID.map(profiles.contains) == true }
    }
    var downloadState: BrowserState {
        var snapshot = state; snapshot.downloads = downloadItems; return snapshot
    }
    lazy var linkRouting = LinkRoutingStore(directory: directory)
    let directory: URL
    // The directory belongs to the normal application. Ephemeral initialization
    // never reads or creates it; every model persistence entry is gated below.
    let privateParentProfileID: UUID?
    private let privateEnginePath: String?
    var isEphemeral: Bool { privateEnginePath != nil }
    private let clock: () -> Date
    private var pendingSave: DispatchWorkItem?
    /// Persisted snapshot last handed to a still-pending debounce. Used so a
    /// no-op `changed()`/`scheduleSave` does not cancel and reset the timer.
    private var pendingSaveSnapshot: BrowserState?
    private let sessionWriter = SessionFileWriter()
    /// Never part of `state` or the session file.
    var closedPageHistory = ClosedPageHistory<AnyObject>()
    /// Live pages' back/forward entries for the next launch; none when private.
    lazy var tabHistory: TabHistoryArchive? = isEphemeral ? nil
        : TabHistoryArchive(directory: directory.appendingPathComponent("Tab History", isDirectory: true))
    /// The open standard windows' session records, the first the window Parc
    /// reopens. They stay off the published state: each window's render
    /// follows `state`, and the records change on every width commit and
    /// window close. Session writes put them back into the file.
    private(set) var windowRecords: [BrowserWindowRecord] = []
    // Installed by the native application. The model keeps the saved tab
    // unchanged until every real page using it has accepted retirement. The
    // native owner MUST call shouldCommit after all approvals and before any
    // unload, then report success only after every actual page is destroyed.
    var requestPageRetirement: ((Set<UUID>, @escaping () -> Bool, @escaping (Bool) -> Void) -> Void)?
    private var profileWriteReservations: [UUID: UUID] = [:]
    /// Capture output is an explicit durable write. Reserve its original
    /// parent before launching the disk actor so removal cannot cross it.
    func reserveProfileWrite(_ profileID: UUID) -> ProfileWriteReservation? {
        guard !isEphemeral, !isProfileRemovalPending(profileID),
              state.profiles.contains(where: { $0.id == profileID }) else { return nil }
        let token = UUID(); profileWriteReservations[token] = profileID
        return ProfileWriteReservation { [self] in profileWriteReservations.removeValue(forKey: token) }
    }
    private func hasProfileWrite(_ profileID: UUID) -> Bool {
        profileWriteReservations.values.contains(profileID)
    }

    private var retirementRequests: [UUID: UUID] = [:]
    private var committingRetirementIDs: Set<UUID> = []
    private var exclusiveRetirementIDs: Set<UUID> = []
    private var archivePreviewLeases: [UUID: ArchivePreviewLease] = [:]
    var retiringTabIDs: Set<UUID> { Set(retirementRequests.keys).union(exclusiveRetirementIDs) }
    private var stateURL: URL { directory.appendingPathComponent("session.json") }

    init(directory: URL, now: @escaping () -> Date = Date.init) throws {
        self.directory = directory
        privateParentProfileID = nil; privateEnginePath = nil
        self.clock = now
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("session.json")
        if FileManager.default.fileExists(atPath: file.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let bytes = try Data(contentsOf: file)
            var decoded = try decoder.decode(BrowserState.self, from: bytes)
            windowRecords = decoded.windows; decoded.windows = []
            let historyFile = directory.appendingPathComponent(BrowserHistoryFile.name)
            if FileManager.default.fileExists(atPath: historyFile.path) {
                let bytes = try? Data(contentsOf: historyFile)
                let saved = bytes.map(BrowserHistoryFile.decode) ?? []
                // An unreadable file, or one with records this build cannot
                // read, is left untouched for the session instead of being
                // replaced by the visits that did load.
                if bytes == nil || (saved.isEmpty && bytes?.isEmpty == false) { sessionWriter.preserveHistoryFile() }
                // A session written before the split (the file may already
                // hold those visits) or by an older build since (newer visits)
                // still carries visits inline; the file's come first.
                let filed = Set(saved.map(\.id))
                var merged = saved + decoded.history.filter { !filed.contains($0.id) }
                if merged.count > BrowserHistoryOrder.capacity {
                    merged.removeFirst(merged.count - BrowserHistoryOrder.capacity)
                }
                decoded.history = merged
            }
            let legacyLayouts = (try? JSONSerialization.jsonObject(with: bytes) as? [String: Any])?["splitLayouts"] as? [[String: Any]]
            let needsGroupIdentityMigration = legacyLayouts?.contains { $0["id"] == nil || $0["sidebarAnchorID"] == nil } == true
            guard decoded.version == 1, !decoded.spaces.isEmpty, !decoded.profiles.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            state = decoded
            for i in state.tabs.indices {
                state.tabs[i].url = BrowserInternalURL.publicString(state.tabs[i].url)
                state.tabs[i].savedURL = BrowserInternalURL.publicString(state.tabs[i].savedURL)
            }
            for i in state.history.indices {
                state.history[i].url = BrowserInternalURL.publicString(state.history[i].url)
            }
            try validateState()
            if state.settings.restoreSession {
                normalizeSelection()
                state = SplitMembership.resolvingSharedLegacyFavorites(state)
                reconcileSplitLayouts()
                migrateLegacySplitContainers()
                // Persist normalized legacy groups and their newly assigned identities.
                if needsGroupIdentityMigration || state != decoded { try save() }
            } else {
                beginFreshSession()
                state = SplitMembership.resolvingSharedLegacyFavorites(state)
                reconcileSplitLayouts()
                migrateLegacySplitContainers()
                if state != decoded { try save() }
            }
        } else {
            state = .initial()
        }
    }

    init(privateParentProfileID: UUID, engineProfilePath: String, directory: URL,
         settings: BrowserSettings, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.privateParentProfileID = privateParentProfileID
        privateEnginePath = engineProfilePath
        clock = now
        let profile = BrowserProfile(id: UUID(), name: "Incognito")
        let space = BrowserSpace(id: UUID(), name: "Space 1", symbol: "circle.fill", color: "202020", profileID: profile.id)
        var initial = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
        initial.settings = settings
        state = initial
    }

    var activeSpaceID: UUID { state.activeSpaceID }
    var activeSpace: BrowserSpace { state.spaces.first { $0.id == activeSpaceID } ?? state.spaces[0] }
    var selectedTabID: UUID? { state.selectedTabIDs.first }
    var activeSplitLayout: BrowserSplitLayout? {
        SidebarSplitItems.groups(in: state, spaceID: activeSpaceID).first { $0.tabIDs == state.selectedTabIDs }
    }
    var visibleTabs: [BrowserTab] { state.tabs.filter { $0.archivedAt == nil && ($0.kind == .favorite ? $0.profileID == activeSpace.profileID : $0.spaceID == activeSpaceID) } }
    var favorites: [BrowserTab] { visibleTabs.filter { $0.kind == .favorite } }
    var pinnedTabs: [BrowserTab] { visibleTabs.filter { $0.kind == .pinned } }
    var todayTabs: [BrowserTab] { visibleTabs.filter { $0.kind == .today } }
    var folders: [BrowserFolder] { state.folders.filter { $0.spaceID == activeSpaceID } }
    var archivedTabs: [BrowserTab] { state.tabs.filter { $0.archivedAt != nil && $0.profileID == activeSpace.profileID }.sorted { $0.archivedAt! > $1.archivedAt! } }

    func archivedItems(profileID: UUID) -> [BrowserArchivedItem] {
        let tabs = state.tabs.filter { $0.archivedAt != nil && $0.profileID == profileID }
            .sorted { $0.archivedAt! > $1.archivedAt! }
        var consumed = Set<UUID>()
        return tabs.compactMap { tab in
            guard consumed.insert(tab.id).inserted else { return nil }
            if let group = tab.archiveProvenance?.groupID,
               let layout = tab.archiveProvenance?.split,
               Set(layout.tabIDs).count == layout.tabIDs.count,
               BrowserSplitLayout.normalized(layout.widthFactors, count: layout.tabIDs.count) != nil {
                let members = layout.tabIDs.compactMap { id in
                    tabs.first { $0.id == id && $0.archivedAt == tab.archivedAt && $0.archiveProvenance?.groupID == group }
                }
                if members.count == layout.tabIDs.count {
                    consumed.formUnion(members.map(\.id))
                    return BrowserArchivedItem(tabs: members)
                }
            }
            return BrowserArchivedItem(tabs: [tab])
        }
    }

    private func archiveProvenance(for ids: Set<UUID>, reason: ArchiveReason) -> [UUID: ArchiveProvenance] {
        var result: [UUID: ArchiveProvenance] = [:]
        for tab in state.tabs where ids.contains(tab.id) && tab.archivedAt == nil {
            result[tab.id] = ArchiveProvenance(reason: reason, spaceID: tab.spaceID,
                spaceName: state.spaces.first { $0.id == tab.spaceID }?.name ?? "Space")
        }
        // Preserve only a complete archived split; a partially closed group
        // must never restore or steal panes which stayed open in another window.
        for layout in state.splitLayouts where layout.tabIDs.allSatisfy({ ids.contains($0) }) {
            guard layout.tabIDs.allSatisfy({ id in state.tabs.contains { $0.id == id && $0.kind == .today && $0.archivedAt == nil } }),
                  layout.tabIDs.allSatisfy({ result[$0]?.groupID == nil }) else { continue }
            let group = UUID()
            for id in layout.tabIDs { result[id]?.groupID = group; result[id]?.split = layout }
        }
        return result
    }

    //
    // its age comparison retains age < threshold and removes age >= threshold.
    static let archiveRetention: TimeInterval = 60 * 24 * 60 * 60
    func cleanExpiredArchive(now: Date? = nil) {
        let cutoff = (now ?? clock()).addingTimeInterval(-Self.archiveRetention)
        let ids = Set(state.tabs.filter { $0.archivedAt.map { $0 <= cutoff } ?? false }.map(\.id))
        deleteArchivedTabs(ids)
    }

    /// A preview reserves an exact archived item, including its ordered group.
    /// Mutable titles and URLs may legitimately change while a Note is edited.
    func acquireArchivePreview(id: UUID, profileID: UUID) -> ArchivePreviewLease? {
        guard !isEphemeral, !isProfileRemovalPending(profileID),
              state.profiles.contains(where: { $0.id == profileID }),
              let item = archivedItems(profileID: profileID).first(where: { $0.id == id }) else { return nil }
        let ids = Set(item.tabs.map(\.id))
        guard ids.isDisjoint(with: retiringTabIDs),
              archivePreviewLeases.values.allSatisfy({ ids.isDisjoint(with: Set($0.tabs.map(\.id))) }) else { return nil }
        let lease = ArchivePreviewLease(token: UUID(), profileID: profileID, tabs: item.tabs)
        archivePreviewLeases[lease.token] = lease
        return lease
    }

    func archivePreviewIsValid(_ lease: ArchivePreviewLease) -> Bool {
        guard archivePreviewLeases[lease.token] == lease, !isProfileRemovalPending(lease.profileID),
              state.profiles.contains(where: { $0.id == lease.profileID }),
              let first = lease.tabs.first,
              let current = archivedItems(profileID: lease.profileID).first(where: { $0.id == first.id }),
              current.tabs.count == lease.tabs.count else { return false }
        return zip(current.tabs, lease.tabs).allSatisfy { current, original in
            current.id == original.id && current.profileID == original.profileID
                && current.spaceID == original.spaceID && current.createdAt == original.createdAt
                && current.archivedAt == original.archivedAt && current.archiveProvenance == original.archiveProvenance
        }
    }

    func releaseArchivePreview(_ lease: ArchivePreviewLease) {
        if archivePreviewLeases[lease.token] == lease { archivePreviewLeases.removeValue(forKey: lease.token) }
    }

    /// Native retirement compares this exact set with the original live
    /// preview owners before unloading and again at its consent gate.
    func archivePreviewLeases(intersecting ids: Set<UUID>) -> [ArchivePreviewLease] {
        archivePreviewLeases.values.filter { !ids.isDisjoint(with: Set($0.tabs.map(\.id))) }
    }

    private func archivePreviewOverlaps(_ ids: Set<UUID>) -> Bool {
        !archivePreviewLeases(intersecting: ids).isEmpty
    }

    func deleteArchivedTabs(_ ids: Set<UUID>, profileID: UUID? = nil) {
        let originals = state.tabs.filter { ids.contains($0.id) && $0.archivedAt != nil
            && (profileID == nil || $0.profileID == profileID) }
        guard !originals.isEmpty else { return }
        let removing = Set(originals.map(\.id))
        // Retire the entire original group even for a partial selection: a
        // preview may own all its panes under a single archive item.
        let groups = Set(originals.map(\.profileID)).flatMap { archivedItems(profileID: $0) }
            .filter { !removing.isDisjoint(with: Set($0.tabs.map(\.id))) }
        let snapshots = groups.map(\.tabs)
        let retiring = Set(snapshots.flatMap { $0.map(\.id) })
        guard retiring.isDisjoint(with: retiringTabIDs),
              originals.allSatisfy({ !isProfileRemovalPending($0.profileID) }) else { return }
        func current() -> Bool {
            snapshots.allSatisfy { tabs in
                guard let first = tabs.first, !self.isProfileRemovalPending(first.profileID),
                      self.state.profiles.contains(where: { $0.id == first.profileID }) else { return false }
                return self.archivedItems(profileID: first.profileID).contains { $0.tabs == tabs }
            }
        }
        withRetiredPages(retiring, shouldCommit: current, exclusive: true) { [weak self] in
            guard let self, current(), !self.archivePreviewOverlaps(retiring) else { return }
            var next = self.state
            next.tabs.removeAll { removing.contains($0.id) }
            next.recentlyClosedIDs.removeAll { removing.contains($0) }
            self.state = next
            self.changed()
        }
    }

    func clearArchive(profileID: UUID) {
        deleteArchivedTabs(Set(state.tabs.filter { $0.profileID == profileID && $0.archivedAt != nil }.map(\.id)), profileID: profileID)
    }

    func profilePath(for tab: BrowserTab) -> String {
        directory.appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(tab.profileID.uuidString, isDirectory: true).path
    }

    var independentEngineRoot: URL {
        directory.appendingPathComponent("Chromium-v1", isDirectory: true)
    }

    func independentEngineProfilePath(for profileID: UUID) -> String {
        if let privateEnginePath { return privateEnginePath }
        // Current CEF requires an immediate child of root_cache_path. Nested
        // paths silently become off-the-record contexts, so reject aliases.
        return independentEngineRoot.appendingPathComponent(profileID.uuidString, isDirectory: true).path
    }

    func profileID(forEnginePath path: String) -> UUID? {
        let supplied = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
        return state.profiles.first {
            URL(fileURLWithPath: independentEngineProfilePath(for: $0.id), isDirectory: true).standardizedFileURL.path == supplied
        }?.id
    }

    // Records an already-created engine page. This deliberately does not use
    // NavigationInput: the page may be a POST popup or an extension document,
    // and recording its identity must never issue another navigation.
    func adoptNativePage(url: URL?, title: String, profilePath: String,
                         preferredSpaceID: UUID, select: Bool, creation: TabCreationProvenance? = nil,
                         insertion: TodayInsertion = .automatic) -> UUID? {
        guard let profileID = profileID(forEnginePath: profilePath),
              let space = state.spaces.first(where: { $0.id == preferredSpaceID && $0.profileID == profileID })
                ?? state.spaces.first(where: { $0.profileID == profileID }) else { return nil }
        let creation = creation?.validated(profileID: profileID, state: state)
        let id = UUID()
        let destination = BrowserInternalURL.publicString(url?.absoluteString ?? "about:blank")
        let name = title.isEmpty ? (url?.host ?? "New Tab") : title
        // One published assign: append + place + optional selection must not
        // multi-fire window/sidebar sinks mid-adoption.
        var next = state
        next.tabs.append(BrowserTab(id: id, spaceID: space.id, profileID: profileID,
                                    url: destination, title: name, kind: .today,
                                    createdAt: clock(), lastAccessed: clock(),
                                    savedURL: destination, savedTitle: name,
                                    referrerID: creation?.referrerID,
                                    activeTabBeforeCreationID: creation?.activeTabBeforeCreationID))
        SidebarHierarchy.placingCreatedTab(id, insertion: insertion, in: &next)
        if select {
            if next.activeSpaceID != space.id {
                next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
                next.activeSpaceID = space.id
            }
            next.selectedTabIDs = [id]
            next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
        }
        state = next
        changed(selectionAlreadyStamped: select)
        return id
    }

    // A renderer may refuse retirement after an archive/profile/internal-page
    // model change. Restore only that exact outstanding mutation, never a newer
    // edit made while the confirmation was open.
    @discardableResult
    func restoreLiveTab(_ original: BrowserTab, replacing expected: BrowserTab?) -> Bool {
        guard state.tabs.first(where: { $0.id == original.id }) == expected,
              original.archivedAt == nil,
              state.profiles.contains(where: { $0.id == original.profileID }),
              state.spaces.contains(where: { $0.id == original.spaceID && $0.profileID == original.profileID }) else { return false }
        if let index = state.tabs.firstIndex(where: { $0.id == original.id }) { state.tabs[index] = original }
        else { state.tabs.append(original) }
        state.recentlyClosedIDs.removeAll { $0 == original.id }
        reconcileSplitLayouts()
        changed()
        return true
    }

    func easelsDirectory(for profileID: UUID) -> URL {
        directory.appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(profileID.uuidString, isDirectory: true)
            .appendingPathComponent("Easels", isDirectory: true)
    }
    var activeEaselsDirectory: URL { easelsDirectory(for: activeSpace.profileID) }

    func capturesDirectory(for profileID: UUID) -> URL {
        directory.appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(profileID.uuidString, isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
    }

    func notesDirectory(for profileID: UUID) -> URL {
        directory.appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(profileID.uuidString, isDirectory: true)
            .appendingPathComponent("Notes", isDirectory: true)
    }

    @discardableResult
    func openNote(id documentID: UUID, title: String, inSplit: Bool = false) -> UUID? {
        guard !isEphemeral, !isProfileRemovalPending(activeSpace.profileID),
              !inSplit || (!state.selectedTabIDs.isEmpty && state.selectedTabIDs.count < 4) else { return nil }
        let original = state.selectedTabIDs, page = InternalPage.note(documentID)
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Note" : title
        if let index = localDocumentTabIndex(page, profileID: activeSpace.profileID) {
            let existing = state.tabs[index]
            guard !inSplit || existing.spaceID == activeSpaceID else { return nil }
            let id = presentLocalDocument(at: index, page: page, title: name)
            if inSplit { setSplit(original + [id]) } else { selectTab(id) }
            return id
        }
        let id = UUID()
        // The new note is the item being added: it joins the split without a copy.
        var next = state
        next.tabs.append(BrowserTab(id: id, spaceID: activeSpaceID, profileID: activeSpace.profileID,
            url: page.urlString, title: name, kind: .today, createdAt: clock(), lastAccessed: clock(),
            savedURL: page.urlString, savedTitle: name))
        if inSplit {
            state = next
            setSplit(original + [id], adding: id)
        } else {
            SidebarHierarchy.placingCreatedTab(id, insertion: .automatic, in: &next)
            next.selectedTabIDs = [id]
            next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
            state = next
            changed(selectionAlreadyStamped: true)
        }
        return id
    }
    func updateNoteTitle(id documentID: UUID, profileID: UUID, title: String) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Note" : title
        var next = state, didChange = false
        for index in next.tabs.indices where next.tabs[index].profileID == profileID {
            if InternalPage(urlString: next.tabs[index].url)?.noteID == documentID && next.tabs[index].title != name {
                next.tabs[index].title = name; didChange = true
            }
            if InternalPage(urlString: next.tabs[index].savedURL)?.noteID == documentID && next.tabs[index].savedTitle != name {
                next.tabs[index].savedTitle = name; didChange = true
            }
        }
        if didChange { state = next; changed() }
    }
    func deleteLocalDocument(_ page: InternalPage, profileID: UUID,
                             ownerValid: @escaping () -> Bool,
                             deleteDocument: @escaping () throws -> Void,
                             completion: @escaping (Error?) -> Void) {
        guard !isEphemeral, state.profiles.contains(where: { $0.id == profileID }),
              !isProfileRemovalPending(profileID) else { completion(CocoaError(.userCancelled)); return }
        let originals = state.tabs.filter { $0.profileID == profileID && ($0.url == page.urlString || $0.savedURL == page.urlString) }
        let ids = Set(originals.map(\.id))
        let archiveGroups = archivedItems(profileID: profileID).filter { !ids.isDisjoint(with: Set($0.tabs.map(\.id))) }.map(\.tabs)
        let retiring = ids.union(archiveGroups.flatMap { $0.map(\.id) })
        guard retiring.isDisjoint(with: retiringTabIDs) else { completion(CocoaError(.userCancelled)); return }
        func current() -> Bool {
            ownerValid() && !self.isProfileRemovalPending(profileID)
                && self.state.profiles.contains(where: { $0.id == profileID })
                && self.state.tabs.filter { $0.profileID == profileID && ($0.url == page.urlString || $0.savedURL == page.urlString) } == originals
                && archiveGroups.allSatisfy { group in self.archivedItems(profileID: profileID).contains { $0.tabs == group } }
        }
        withRetiredPages(retiring, shouldCommit: current, onRefusal: { completion(CocoaError(.userCancelled)) }, exclusive: true) { [weak self] in
            guard let self, current(), !self.archivePreviewOverlaps(retiring) else { completion(CocoaError(.userCancelled)); return }
            do {
                var next = self.state
                next.tabs.removeAll { ids.contains($0.id) }; next.selectedTabIDs.removeAll { ids.contains($0) }
                next.recentlyClosedIDs.removeAll { ids.contains($0) }
                next.splitLayouts = next.splitLayouts.compactMap { original in
                    var layout = original
                    let positions = layout.tabIDs.indices.filter { !ids.contains(layout.tabIDs[$0]) }
                    let weights = positions.map { layout.widthFactors[$0] }
                    guard let factors = BrowserSplitLayout.normalized(weights, count: positions.count) else { return nil }
                    layout.tabIDs = positions.map { original.tabIDs[$0] }; layout.widthFactors = factors
                    if layout.sidebarAnchorID.map({ layout.tabIDs.contains($0) }) != true { layout.sidebarAnchorID = layout.tabIDs.first }
                    return layout
                }
                // Persist removal of original tab references first. If this
                // write fails, the document is untouched. If document deletion
                // fails afterward, its real Library entry remains retryable.
                try self.commitProfileSettings(next)
                try deleteDocument(); completion(nil)
            } catch { completion(error) }
        }
    }

    @discardableResult
    func openEasel(id documentID: UUID, title: String, inSplit: Bool = false) -> UUID? {
        guard !inSplit || (!isEphemeral && !isProfileRemovalPending(activeSpace.profileID)
              && !state.selectedTabIDs.isEmpty && state.selectedTabIDs.count < 4) else { return nil }
        let original = state.selectedTabIDs, page = InternalPage.easel(documentID)
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = name.isEmpty ? "Untitled Easel" : name
        if let index = localDocumentTabIndex(page, profileID: activeSpace.profileID) {
            let existing = state.tabs[index]
            guard !inSplit || existing.spaceID == activeSpaceID else { return nil }
            let id = presentLocalDocument(at: index, page: page, title: title)
            if inSplit { setSplit(original + [id]) } else { selectTab(id) }
            return id
        }
        let id = UUID()
        // The new Easel is the item being added: it joins the split without a copy.
        var next = state
        next.tabs.append(BrowserTab(id: id, spaceID: activeSpaceID, profileID: activeSpace.profileID,
                                     url: page.urlString, title: title, kind: .today,
                                     createdAt: clock(), lastAccessed: clock(),
                                     savedURL: page.urlString, savedTitle: title))
        if inSplit {
            state = next
            setSplit(original + [id], adding: id)
        } else {
            SidebarHierarchy.placingCreatedTab(id, insertion: .automatic, in: &next)
            next.selectedTabIDs = [id]
            next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
            state = next
            changed(selectionAlreadyStamped: true)
        }
        return id
    }

    /// Live and archived aliases of one profile-local document share a tab.
    /// Prefer a live tab so a pinned SP21 home is not ignored for an archived pane.
    private func localDocumentTabIndex(_ page: InternalPage, profileID: UUID) -> Int? {
        let matches = state.tabs.indices.filter { index in
            let tab = state.tabs[index]
            return tab.profileID == profileID
                && !retiringTabIDs.contains(tab.id)
                && !archivePreviewOverlaps([tab.id])
                && (InternalPage(urlString: tab.url) == page || InternalPage(urlString: tab.savedURL) == page)
        }
        return matches.first { state.tabs[$0].archivedAt == nil } ?? matches.first
    }

    /// Library reopen restores a closeable Today tab; a Favorite stays a Favorite.
    private func presentLocalDocument(at index: Int, page: InternalPage, title: String) -> UUID {
        let id = state.tabs[index].id
        state.tabs[index].url = page.urlString
        state.tabs[index].savedURL = page.urlString
        state.tabs[index].title = title
        state.tabs[index].savedTitle = title
        if state.tabs[index].archivedAt != nil {
            if state.tabs[index].kind != .favorite {
                state.tabs[index].kind = .today
                state.tabs[index].folderID = nil
            }
            state.tabs[index].archivedAt = nil
            state.tabs[index].archiveProvenance = nil
            if state.tabs[index].kind == .today {
                SidebarHierarchy.placingCreatedTab(id, insertion: .automatic, in: &state)
            }
        }
        return id
    }

    func updateEaselTitle(id documentID: UUID, profileID: UUID, title: String) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var didChange = false
        for index in state.tabs.indices where state.tabs[index].profileID == profileID {
            if InternalPage(urlString: state.tabs[index].url)?.easelID == documentID && state.tabs[index].title != name {
                state.tabs[index].title = name; didChange = true
            }
            if InternalPage(urlString: state.tabs[index].savedURL)?.easelID == documentID && state.tabs[index].savedTitle != name {
                state.tabs[index].savedTitle = name; didChange = true
            }
        }
        if didChange { changed() }
    }

    @discardableResult
    func open(_ input: String, kind: TabKind = .today, creation: TabCreationProvenance? = nil) -> UUID {
        let resolved = NavigationInput.resolve(input, searchEngine: state.settings.searchEngine) ?? URL(string: "about:blank")!
        return openResolvedURL(resolved, kind: kind, creation: creation)
    }

    @discardableResult
    func openResolvedURL(_ url: URL, id: UUID = UUID(), kind: TabKind = .today, creation: TabCreationProvenance? = nil) -> UUID {
        let creation = creation?.validated(profileID: activeSpace.profileID, state: state)
        let resolved = BrowserInternalURL.publicString(url.absoluteString)
        let title = url.host ?? "New Tab"
        // Append + Today placement + selection publish once (same end state).
        var next = state
        next.tabs.append(BrowserTab(id: id, spaceID: activeSpaceID, profileID: activeSpace.profileID,
                                     url: resolved, title: title, kind: kind, createdAt: clock(), lastAccessed: clock(),
                                     savedURL: resolved, savedTitle: title,
                                     referrerID: creation?.referrerID,
                                     activeTabBeforeCreationID: creation?.activeTabBeforeCreationID))
        SidebarHierarchy.placingCreatedTab(id, insertion: .automatic, in: &next)
        next.selectedTabIDs = [id]
        next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
        state = next
        changed(selectionAlreadyStamped: true)
        return id
    }

    /// A force-open creates a distinct unread Today tab without presenting it.
    /// The native request remains with the originating window, not this URL metadata.
    @discardableResult
    func insertCommandBarBackground(tabID: UUID, url: URL, spaceID: UUID,
                                    profileID: UUID, expectedSelection: [UUID], creation: TabCreationProvenance? = nil) -> Bool {
        guard activeSpaceID == spaceID, activeSpace.profileID == profileID,
              state.selectedTabIDs == expectedSelection, !isProfileRemovalPending(profileID),
              !state.tabs.contains(where: { $0.id == tabID }),
              !retiringTabIDs.contains(tabID), expectedSelection.allSatisfy({ id in
                  visibleTabs.contains { $0.id == id } && !retiringTabIDs.contains(id)
              }), !InternalPage.isInternal(url.absoluteString) else { return false }
        let creation = creation?.validated(profileID: profileID, state: state)
        let resolved = BrowserInternalURL.publicString(url.absoluteString), title = url.host ?? "New Tab"
        state.tabs.append(BrowserTab(id: tabID, spaceID: spaceID, profileID: profileID,
            url: resolved, title: title, kind: .today, createdAt: clock(), lastAccessed: clock(),
            savedURL: resolved, savedTitle: title, isUnread: true,
            referrerID: creation?.referrerID, activeTabBeforeCreationID: creation?.activeTabBeforeCreationID))
        SidebarHierarchy.placingCreatedTab(tabID, insertion: .automatic, in: &state)
        changed()
        return true
    }

    /// Commit a command-bar split in one model publication. The caller retains
    /// the original classified native request separately; this URL is metadata.
    @discardableResult
    /// The member a command-bar split result adds, plus the saved homes it
    /// needs (`savedHomeSources`); a new URL tab is the item being added.
    func commandBarSplitHomes(after focusedID: UUID, expectedSelection: [UUID], tabID: UUID, isNew: Bool) -> [BrowserTab]? {
        guard let index = expectedSelection.firstIndex(of: focusedID), expectedSelection.count < 4,
              !expectedSelection.contains(tabID) else { return nil }
        var ids = expectedSelection
        ids.insert(tabID, at: index + 1)
        let previous = activeSplitLayout.flatMap { $0.tabIDs == expectedSelection ? $0 : nil }
        // A new URL tab is the item being added; displayed saved panes of a
        // new split still need their homes.
        return SplitMembership.savedHomeSources(joining: ids, existing: previous, added: isNew ? tabID : nil, state: state)
    }

    func insertCommandBarSplit(after focusedID: UUID, expectedSelection: [UUID],
                               tabID: UUID, newURL: URL? = nil, creation: TabCreationProvenance? = nil,
                               savedHomeIDs: [UUID: UUID] = [:], documents: [UUID: SidebarDocumentReference]? = nil) -> Bool {
        guard state.selectedTabIDs == expectedSelection,
              !isProfileRemovalPending(activeSpace.profileID),
              let index = expectedSelection.firstIndex(of: focusedID),
              expectedSelection.allSatisfy({ id in
                  visibleTabs.contains { $0.id == id } && !retiringTabIDs.contains(id)
              }), !retiringTabIDs.contains(tabID) else { return false }
        if newURL == nil, expectedSelection.contains(tabID) { return true }
        guard expectedSelection.count < 4 else { return false }
        var next = state
        let creation = creation?.validated(profileID: activeSpace.profileID, state: state)
        // Option-Return on a tab from another Space of the Profile joins as
        // Add Split's result does (SplitCrossSpaceAdd); a pinned one leaves
        // its planned saved home in its own Space. Its typed reference was
        // planned before the move, so validate against those homes.
        var savedHomeIDs = savedHomeIDs, validatedBeforeMove = false
        if newURL == nil, let foreign = state.tabs.first(where: { $0.id == tabID && $0.archivedAt == nil
            && $0.kind != .favorite && $0.profileID == activeSpace.profileID && $0.spaceID != activeSpaceID }) {
            if let documents {
                var planned = expectedSelection; planned.insert(tabID, at: index + 1)
                let previous = activeSplitLayout.flatMap { $0.tabIDs == expectedSelection ? $0 : nil }
                guard SidebarDocumentReference.validates(SplitMembership.savedHomeSources(joining: planned, existing: previous,
                    added: nil, state: state), references: documents) else { return false }
                validatedBeforeMove = true
            }
            let homeID = SplitMembership.isSaved(foreign) ? savedHomeIDs.removeValue(forKey: tabID) ?? UUID() : nil
            guard let moved = SplitCrossSpaceAdd.relocated(state, source: tabID, into: activeSpaceID,
                profileID: activeSpace.profileID, pane: focusedID, homeID: homeID, now: clock()) else { return false }
            next = moved
        }
        if let url = newURL {
            guard !state.tabs.contains(where: { $0.id == tabID }) else { return false }
            let title = url.host ?? "New Tab", resolved = BrowserInternalURL.publicString(url.absoluteString)
            next.tabs.append(BrowserTab(id: tabID, spaceID: activeSpaceID,
                profileID: activeSpace.profileID, url: resolved, title: title, kind: .today,
                createdAt: clock(), lastAccessed: clock(), savedURL: resolved, savedTitle: title,
                referrerID: creation?.referrerID, activeTabBeforeCreationID: creation?.activeTabBeforeCreationID))
            //
            SidebarHierarchy.placingCreatedTab(tabID, insertion: .automatic, in: &next)
        } else {
            guard next.tabs.contains(where: { $0.id == tabID && $0.archivedAt == nil
                && ($0.kind == .favorite ? $0.profileID == activeSpace.profileID : $0.spaceID == activeSpaceID) }) else { return false }
        }
        var ids = expectedSelection
        ids.insert(tabID, at: index + 1)
        let previous = activeSplitLayout.flatMap { $0.tabIDs == expectedSelection ? $0 : nil }
        let factors = ids.map { id in
            previous.flatMap { layout in
                layout.tabIDs.firstIndex(of: id).map { layout.widthFactors[$0] }
            } ?? (1.0 / Double(expectedSelection.count))
        }
        let group = BrowserSplitLayout(id: previous?.id ?? UUID(), sidebarAnchorID: previous?.sidebarAnchorID, customTitle: previous?.customTitle, customIcon: previous?.customIcon,
            spaceID: previous?.spaceID ?? activeSpaceID, tabIDs: ids, orientation: previous?.orientation ?? .horizontal,
            widthFactors: BrowserSplitLayout.normalized(factors, count: ids.count)!)
        let added = newURL == nil ? nil : tabID
        let homes = SplitMembership.savedHomeSources(joining: ids, existing: previous, added: added, state: next)
        if let documents, !validatedBeforeMove, !SidebarDocumentReference.validates(homes, references: documents) { return false }
        var homeIDs = savedHomeIDs
        for home in homes where homeIDs[home.id] == nil { homeIDs[home.id] = UUID() }
        guard let admitted = SplitMembership.admitting(group, existing: previous, added: added, state: next,
            spaceID: activeSpaceID, homeIDs: homeIDs, now: clock(),
            activeTabBeforeCreationID: creation?.activeTabBeforeCreationID) else { return false }
        next = admitted
        next.selectedTabIDs = ids
        next.selectionBySpace[activeSpaceID.uuidString] = ids
        for i in next.tabs.indices where ids.contains(next.tabs[i].id) {
            next.tabs[i].lastAccessed = clock(); next.tabs[i].isUnread = false
        }
        // Apply exclusive membership before the one publication.
        next.splitLayouts = Self.reconciledSplitLayouts(in: next, activeSpaceID: activeSpaceID)
        state = next
        changed(selectionAlreadyStamped: true)
        return true
    }

    /// Save before exposing the new split/item to any observing window.
    func commitFavoriteSplit(_ request: FavoriteSplitRequest) throws -> UUID? {
        guard !isEphemeral, let next = request.applying(to: state, retiring: retiringTabIDs, now: clock()) else { return nil }
        try commitProfileSettings(next)
        return request.targetID
    }

    func navigate(_ id: UUID, input: String) {
        guard let url = NavigationInput.resolve(input, searchEngine: state.settings.searchEngine) else { return }
        guard let tab = state.tabs.first(where: { $0.id == id }) else { return }
        if !InternalPage.isInternal(tab.url), InternalPage.isInternal(url.absoluteString) {
            withRetiredPages([id]) { [weak self] in self?.updateTab(id, url: url.absoluteString) }
        } else { updateTab(id, url: url.absoluteString) }
    }

    func updateTab(_ id: UUID, title: String? = nil, url: String? = nil) {
        guard let index = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        let current = state.tabs[index]
        let nextTitle = title.flatMap { $0.isEmpty ? nil : $0 } ?? current.title
        let nextURL = url.map(BrowserInternalURL.publicString) ?? current.url
        let nextSavedURL = current.kind == .today ? nextURL : current.savedURL
        let nextSavedTitle = current.kind == .today ? nextTitle : current.savedTitle
        var historyTitle: String?
        var appendHistory = false
        if let url, url.hasPrefix("https://") || url.hasPrefix("http://") {
            if let last = state.history.last, last.url == url, last.profileID == current.profileID,
               clock().timeIntervalSince(last.visitedAt) < 2 {
                if last.title != nextTitle { historyTitle = nextTitle }
            } else if !isEphemeral {
                appendHistory = true
            }
        }
        if nextTitle == current.title, nextURL == current.url,
           nextSavedURL == current.savedURL, nextSavedTitle == current.savedTitle,
           historyTitle == nil, !appendHistory {
            return
        }
        // A native metadata callback is one model update. Publishing each
        // field separately queues a full window/sidebar render for every write,
        // even though the window reads the latest state when the queue runs.
        var next = state
        next.tabs[index].title = nextTitle
        next.tabs[index].url = nextURL
        next.tabs[index].savedURL = nextSavedURL
        next.tabs[index].savedTitle = nextSavedTitle
        if let historyTitle {
            next.history[next.history.count - 1].title = historyTitle
            historyRevision &+= 1
        } else if appendHistory, let url {
            next.history.append(BrowserHistoryEntry(id: UUID(), url: url, title: nextTitle, visitedAt: clock(), profileID: current.profileID))
            if next.history.count > BrowserHistoryOrder.capacity {
                next.history.removeFirst(next.history.count - BrowserHistoryOrder.capacity)
            }
            historyRevision &+= 1
        }
        guard next != state else { return }
        state = next
        changed()
    }

    ///
    /// moveFromOriginalLocation false) use the caller's fixed IDs; a caller
    /// supplying typed-document references has every typed home validated.
    func splitExtensionHomes(_ id: UUID) -> [BrowserTab] {
        guard !state.selectedTabIDs.contains(id), state.selectedTabIDs.count < 4 else { return [] }
        let ids = state.selectedTabIDs + [id]
        let previous = activeSplitLayout.flatMap { old in ids.contains(where: { old.tabIDs.contains($0) }) ? old : nil }
        return SplitMembership.savedHomeSources(joining: ids, existing: previous, added: nil, state: state)
    }

    func selectTab(_ id: UUID, extendingSplit: Bool = false, savedHomeIDs: [UUID: UUID] = [:],
                   documents: [UUID: SidebarDocumentReference]? = nil) {
        guard let index = state.tabs.firstIndex(where: { $0.id == id && $0.archivedAt == nil }) else { return }
        if extendingSplit, let documents, !SidebarDocumentReference.validates(splitExtensionHomes(id), references: documents) { return }
        let tab = state.tabs[index]
        if tab.kind != .favorite && tab.spaceID != activeSpaceID { selectSpace(tab.spaceID) }
        if tab.profileID != activeSpace.profileID {
            guard let compatible = state.spaces.first(where: { $0.profileID == tab.profileID }) else { return }
            selectSpace(compatible.id)
        }
        // Space switches above may already have published; batch the remaining
        // selection stamp (and any split activation) into one assignment before
        // the final changed().
        guard let index = state.tabs.firstIndex(where: { $0.id == id && $0.archivedAt == nil }) else { return }
        var next = state
        next.tabs[index].lastAccessed = clock()
        next.tabs[index].isUnread = false
        if extendingSplit, !next.selectedTabIDs.contains(id), next.selectedTabIDs.count < 4 {
            _ = activateSplit(next.selectedTabIDs + [id], savedHomeIDs: savedHomeIDs, into: &next)
        } else if !extendingSplit {
            next.selectedTabIDs = SidebarSplitItems.groups(in: next, spaceID: next.activeSpaceID)
                .first { $0.tabIDs.contains(id) }?.tabIDs ?? [id]
        }
        next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
        state = next
        changed(selectionAlreadyStamped: true)
    }

    func selectSpace(_ id: UUID) {
        guard state.spaces.contains(where: { $0.id == id }), id != activeSpaceID else { return }
        var next = state
        next.selectionBySpace[activeSpaceID.uuidString] = state.selectedTabIDs
        next.activeSpaceID = id
        next.selectedTabIDs = next.selectionBySpace[id.uuidString] ?? []
        normalizeSelection(in: &next)
        stampSelection(in: &next)
        next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
        state = next
        changed(selectionAlreadyStamped: true)
    }

    // Select the initiating window's command context without briefly restoring
    // another window's cached page selection or marking those pages as read.
    @discardableResult
    func setWindowPresentation(spaceID: UUID, selectedTabIDs: [UUID],
                               splitLayout: BrowserSplitLayout? = nil) -> Bool {
        guard let space = state.spaces.first(where: { $0.id == spaceID }) else { return false }
        let available = Set(state.tabs.filter { $0.archivedAt == nil && $0.profileID == space.profileID
            && ($0.kind == .favorite || $0.spaceID == spaceID) }.map(\.id))
        var seen = Set<UUID>()
        let selected = Array(selectedTabIDs.filter { available.contains($0) && seen.insert($0).inserted }.prefix(4))
        var next = state
        next.selectionBySpace[activeSpaceID.uuidString] = state.selectedTabIDs
        next.activeSpaceID = spaceID
        next.selectedTabIDs = selected
        if var layout = splitLayout {
            guard layout.spaceID == spaceID, layout.tabIDs == selected,
                  let factors = BrowserSplitLayout.normalized(layout.widthFactors, count: selected.count) else { return false }
            layout.widthFactors = factors
            // Window-local geometry cannot restore an old shared container name.
            if let original = SidebarSplitItems.groups(in: state, spaceID: spaceID).first(where: { $0.id == layout.id && $0.tabIDs == selected }) {
                layout.customTitle = original.customTitle
                layout.customIcon = original.customIcon
                // Window-local projection must not mint another shared Favorite
                // group when it is selected from a different Space.
                layout.spaceID = original.spaceID
                next.splitLayouts.removeAll { $0.id == original.id }
                next.splitLayouts.append(layout)
            } else {
                // A window's own split that the shared model no longer holds is
                // formed again through the membership owner, never mixed.
                next.splitLayouts.removeAll { $0.spaceID == spaceID && $0.tabIDs == selected }
                if let admitted = admittingNewSplit(layout, in: next) { next = admitted }
            }
        }
        let now = clock()
        for index in next.tabs.indices where selected.contains(next.tabs[index].id) {
            next.tabs[index].lastAccessed = now
            next.tabs[index].isUnread = false
        }
        state = next
        changed()
        return true
    }

    func closeTab(_ id: UUID) {
        closeTabs([id])
    }

    func closeTabs(_ ids: Set<UUID>, reason: ArchiveReason = .manual, completion: ((Bool) -> Void)? = nil) {
        closeTabs(ids, reason: reason, shouldCommit: { true }, completion: completion)
    }

    /// `didCommit` receives the state the close replaced, after it published.
    func closeTabs(_ ids: Set<UUID>, reason: ArchiveReason = .manual,
                   selection: FolderRemovalSelection? = nil,
                   didCommit: ((BrowserState) -> Void)? = nil,
                   shouldCommit: @escaping () -> Bool, completion: ((Bool) -> Void)? = nil) {
        let liveIDs = Set(state.tabs.filter { ids.contains($0.id) && $0.archivedAt == nil }.map(\.id))
        let valid: () -> Bool = { [weak self] in
            guard let self else { return false }
            guard let selection else { return true }
            return selection.removed == liveIDs && FolderRemovalSelection.resolve(removing: liveIDs,
                spaceID: selection.spaceID, profileID: selection.profileID, state: self.state,
                selected: selection.original, focused: selection.originalFocus, referrerPool: selection.referrerPool,
                previouslySelectedItemID: selection.previouslySelectedItemID, available: { selection.tabIDs.contains($0) }) == selection
        }
        guard valid() else { completion?(false); return }
        withRetiredPages(liveIDs, shouldCommit: { valid() && shouldCommit() && valid() },
                         onRefusal: { completion?(false) }) { [weak self] in
            guard let self, valid() else { completion?(false); return }
            let before = self.state
            self.finishClosingTabs(liveIDs, reason: reason, selection: selection)
            didCommit?(before)
            completion?(true)
        }
    }

    private func finishClosingTabs(_ ids: Set<UUID>, reason: ArchiveReason, selection: FolderRemovalSelection? = nil) {
        let closing = state.tabs.filter { ids.contains($0.id) && $0.archivedAt == nil }.map(\.id)
        guard !closing.isEmpty else { return }
        // @Published sends for mutations of nested value properties too.
        // Build the entire close result locally so no subscriber observes a
        // half-closed group or materializes an intermediate fallback page.
        let provenance = archiveProvenance(for: Set(closing), reason: reason)
        var next = state
        let oldVisible = visibleTabs.map(\.id)
        let now = clock()
        let retainedSavedGroups = Set(state.splitLayouts.filter { group in
            !isEphemeral && group.tabIDs.allSatisfy { id in
                ids.contains(id) && state.tabs.contains { $0.id == id && $0.kind != .today && $0.archivedAt == nil }
            }
        }.map(\.id))
        // The displayed split, by identity: a Favorite split is stored under
        // its home Space but is the same item from every Space of its Profile.
        let displayedGroupID = SidebarSplitItems.groups(in: state, spaceID: activeSpaceID)
            .first { $0.tabIDs == state.selectedTabIDs }?.id
        for id in closing {
            // A close archives or resets the tab; its next page starts afresh.
            tabHistory?.remove(id)
            guard let index = next.tabs.firstIndex(where: { $0.id == id }) else { continue }
            if let layoutIndex = next.splitLayouts.firstIndex(where: { $0.id == displayedGroupID && $0.tabIDs == next.selectedTabIDs && !retainedSavedGroups.contains($0.id) }),
               let pane = next.splitLayouts[layoutIndex].tabIDs.firstIndex(of: id) {
                var layout = next.splitLayouts.remove(at: layoutIndex)
                layout.tabIDs.remove(at: pane)
                layout.widthFactors.remove(at: pane)
                next.splitLayouts.append(layout)
            }
            if isEphemeral {
                next.tabs.remove(at: index)
            } else if next.tabs[index].kind == .today {
                next.tabs[index].archiveProvenance = provenance[id]
                next.tabs[index].archivedAt = now
                next.recentlyClosedIDs.removeAll { $0 == id }
                next.recentlyClosedIDs.append(id)
            } else {
                // Closing a saved website unloads its live tab; it does not erase the bookmark.
                next.tabs[index].url = next.tabs[index].savedURL
                next.tabs[index].title = next.tabs[index].savedTitle
            }
            next.selectedTabIDs.removeAll { $0 == id }
        }
        //
        // shown or not, drops the panes this close took out of the sidebar
        // before slots are kept, so a remaining pane stands for it in place.
        for index in next.splitLayouts.indices where !retainedSavedGroups.contains(next.splitLayouts[index].id) {
            var layout = next.splitLayouts[index]
            guard state.splitLayouts.contains(where: { $0.id == layout.id && !Set($0.tabIDs).isDisjoint(with: closing) }) else { continue }
            if layout.widthFactors.count == layout.tabIDs.count {
                for pane in layout.tabIDs.indices.reversed() where closing.contains(layout.tabIDs[pane])
                    && !next.tabs.contains(where: { $0.id == layout.tabIDs[pane] && $0.archivedAt == nil }) {
                    layout.tabIDs.remove(at: pane); layout.widthFactors.remove(at: pane)
                }
            }
            if layout.sidebarAnchorID.map(layout.tabIDs.contains) != true { layout.sidebarAnchorID = layout.tabIDs.first }
            next.splitLayouts[index] = layout
        }
        if let selection, next.activeSpaceID == selection.spaceID, state.selectedTabIDs == selection.original {
            next.activeSpaceID = selection.replacementSpaceID
            next.selectedTabIDs = selection.tabIDs
        } else if selection == nil, next.selectedTabIDs.isEmpty, let position = oldVisible.firstIndex(where: { ids.contains($0) }) {
            let candidates = Array(oldVisible[..<position].reversed()) + Array(oldVisible.dropFirst(position + 1))
            let available = Set(next.tabs.filter { $0.archivedAt == nil && ($0.kind == .favorite
                ? $0.profileID == activeSpace.profileID : $0.spaceID == activeSpaceID) }.map(\.id))
            next.selectedTabIDs = Array(candidates.filter { available.contains($0) && !ids.contains($0) }.prefix(1))
        }
        let selectedProfile = next.spaces.first { $0.id == next.activeSpaceID }?.profileID
        let available = Set(next.tabs.filter { $0.archivedAt == nil && ($0.kind == .favorite
            ? $0.profileID == selectedProfile : $0.spaceID == next.activeSpaceID) }.map(\.id))
        var seen = Set<UUID>()
        next.selectedTabIDs = Array(next.selectedTabIDs.filter { available.contains($0) && seen.insert($0).inserted }.prefix(4))
        for index in next.tabs.indices where next.selectedTabIDs.contains(next.tabs[index].id) {
            next.tabs[index].lastAccessed = now
            next.tabs[index].isUnread = false
        }
        if let selection {
            for key in Array(next.selectionBySpace.keys) { next.selectionBySpace[key]?.removeAll { ids.contains($0) } }
            next.selectionBySpace[selection.replacementSpaceID.uuidString] = selection.tabIDs
        }
        // A split losing a pane keeps its slot; a dissolved split leaves its
        //
        SplitMembership.preservingSlots(before: state, after: &next)
        state = next
        changed(selectionAlreadyStamped: selection != nil)
    }

    func removeTab(_ id: UUID) {
        withRetiredPages([id]) { [weak self] in self?.finishRemovingTab(id) }
    }

    private func finishRemovingTab(_ id: UUID) {
        var next = state
        next.tabs.removeAll { $0.id == id }
        next.recentlyClosedIDs.removeAll { $0 == id }
        next.selectedTabIDs.removeAll { $0 == id }
        normalizeSelection(in: &next)
        stampSelection(in: &next)
        next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
        state = next
        changed(selectionAlreadyStamped: true)
    }

    // The caller supplies its physical window's exact close capability. Never
    // search another window's global Archive or resurrect a destroyed page.
    // `regroupable` admits surviving split panes for that physical window; a
    // refused pane is never moved and the closed pane returns alone.
    @discardableResult
    func restoreClosedItem(_ record: ClosedItemRecord,
                           regroupable: (UUID) -> Bool = { _ in true }) throws -> Bool {
        guard !isEphemeral, record.isValid(in: state),
              record.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }),
              !archivePreviewOverlaps(Set(record.tabIDs)) else { return false }
        var next = state
        next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
        next.activeSpaceID = record.spaceID
        next.selectedTabIDs = record.tabIDs
        let now = clock()
        for index in next.tabs.indices where record.tabIDs.contains(next.tabs[index].id) {
            if record.kind == .archived {
                next.tabs[index].archivedAt = nil
                next.tabs[index].archiveProvenance = nil
                // Original location survives only while its exact parent exists.
                if let folder = next.tabs[index].folderID,
                   !next.folders.contains(where: { $0.id == folder && $0.spaceID == record.spaceID }) {
                    next.tabs[index].folderID = nil
                }
            }
            next.tabs[index].lastAccessed = now
            next.tabs[index].isUnread = false
        }
        next.recentlyClosedIDs.removeAll { record.tabIDs.contains($0) }
        if record.kind == .archived, let split = record.split {
            // Saved groups remain in place; only archived groups are reinserted.
            next.splitLayouts.append(split)
        }
        // A pane closed out of a larger split rejoins its surviving original
        // container, or regroups the original one that close dissolved.
        if let membership = record.membership,
           let group = membership.restoredLayout(restoring: record.tabs[0].id, in: next,
               available: { [retiringTabIDs] id in !retiringTabIDs.contains(id) && regroupable(id) }) {
            next.splitLayouts.removeAll { $0.id == group.id }
            next.splitLayouts.append(group)
            next.selectedTabIDs = group.tabIDs
            for index in next.tabs.indices where group.tabIDs.contains(next.tabs[index].id) {
                next.tabs[index].lastAccessed = now
                next.tabs[index].isUnread = false
            }
        }
        try commitProfileSettings(next)
        return true
    }

    @discardableResult
    func restoreArchivedTab(_ id: UUID, profileID requestedProfile: UUID? = nil,
                            destination target: ArchiveRestoreDestination) -> [UUID] {
        restoreArchivedTab(id, profileID: requestedProfile, destination: target, preview: nil)
    }

    func restoreArchivePreview(_ lease: ArchivePreviewLease, destination: ArchiveRestoreDestination) -> [UUID] {
        guard archivePreviewIsValid(lease), let first = lease.tabs.first else { return [] }
        return restoreArchivedTab(first.id, profileID: lease.profileID, destination: destination, preview: lease)
    }

    private func restoreArchivedTab(_ id: UUID, profileID requestedProfile: UUID?,
                                    destination target: ArchiveRestoreDestination, preview: ArchivePreviewLease?) -> [UUID] {
        guard let original = state.tabs.first(where: { $0.id == id && $0.archivedAt != nil }),
              requestedProfile == nil || original.profileID == requestedProfile,
              let item = archivedItems(profileID: original.profileID).first(where: { $0.tabs.contains { $0.id == id } }) else { return [] }
        let preferred: UUID?, fallback: UUID?
        switch target {
        case let .putBack(currentSpaceID, requestedSpaceID):
            //
            // initiating window's focused Space when absent or no longer valid.
            preferred = requestedSpaceID; fallback = currentSpaceID
        case let .previousSpace(fallbackSpaceID):
            preferred = item.provenance?.spaceID ?? original.spaceID
            fallback = fallbackSpaceID
        }
        func compatibleSpace(_ id: UUID?) -> BrowserSpace? {
            state.spaces.first { $0.id == id && $0.profileID == original.profileID }
        }
        guard let destination = compatibleSpace(preferred) ?? compatibleSpace(fallback) else { return [] }
        let ids = item.tabs.map(\.id), now = clock()
        guard Set(ids).isDisjoint(with: retiringTabIDs), !isProfileRemovalPending(original.profileID),
              preview.map({ archivePreviewIsValid($0) && $0.tabs.map(\.id) == ids })
                ?? !archivePreviewOverlaps(Set(ids)) else { return [] }
        var next = state
        next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
        next.activeSpaceID = destination.id
        next.selectedTabIDs = ids
        next.recentlyClosedIDs.removeAll { ids.contains($0) }
        //
        // and Put Back returns it there (`unarchiveAndPutBackItem`,
        //
        // folder when it is put back into its own Space and the folder is
        // still there. A deleted folder is not invented again.
        let folderID = original.kind == .pinned && (item.provenance?.spaceID ?? original.spaceID) == destination.id
            ? original.folderID.flatMap { id in next.folders.contains { $0.id == id && $0.spaceID == destination.id } ? id : nil }
            : nil
        for index in next.tabs.indices where ids.contains(next.tabs[index].id) {
            next.tabs[index].archivedAt = nil
            next.tabs[index].archiveProvenance = nil
            next.tabs[index].spaceID = destination.id
            next.tabs[index].folderID = folderID
            next.tabs[index].lastAccessed = now
            next.tabs[index].isUnread = false
        }
        if ids.count > 1, var split = item.provenance?.split {
            split.spaceID = destination.id
            split.widthFactors = BrowserSplitLayout.normalized(split.widthFactors, count: ids.count)!
            next.splitLayouts.removeAll { $0.spaceID == destination.id && $0.tabIDs == ids }
            next.splitLayouts.append(split)
        }
        if let preview {
            // Published state invokes observers during willSet. Keep admission
            // blocked until the new state is visible, even after lease release.
            exclusiveRetirementIDs.formUnion(ids)
            releaseArchivePreview(preview)
        }
        state = next
        if preview != nil { exclusiveRetirementIDs.subtract(ids) }
        changed()
        return ids
    }

    // Only the shell may use this after confirming that no native page owns
    // the item. Live reset waits for the original page's committed URL callback.
    func resetDormantSavedTab(_ expected: BrowserTab) {
        guard let index = state.tabs.firstIndex(where: { $0.id == expected.id }),
              state.tabs[index] == expected, expected.resetDestination != nil,
              !retiringTabIDs.contains(expected.id) else { return }
        tabHistory?.remove(expected.id)
        state.tabs[index].url = expected.savedURL
        state.tabs[index].title = expected.savedTitle
        changed()
    }

    ///
    /// keeps its identity and takes the page it shows as its new home.
    @discardableResult
    func replaceSavedHome(_ expected: BrowserTab, url: String, title: String) -> Bool {
        //
        let url = BrowserInternalURL.publicString(url)
        guard let index = state.tabs.firstIndex(where: { $0.id == expected.id }),
              state.tabs[index] == expected, expected.resetDestination != nil,
              !retiringTabIDs.contains(expected.id), !isProfileRemovalPending(expected.profileID),
              !InternalPage.isInternal(url), let page = URL(string: url), page.scheme != nil else { return false }
        state.tabs[index].savedURL = url
        state.tabs[index].savedTitle = title.isEmpty ? (page.host ?? url) : title
        changed()
        return true
    }

    ///
    ///
    /// page's URL and title enters the top of its Space's Today list
    ///
    /// returns to its saved destination. The shell moves the live page to the
    /// new tab in the same turn; selection is left to it.
    @discardableResult
    func separateFromPinnedTab(_ expected: BrowserTab, todayID: UUID, title: String) -> Bool {
        guard let index = state.tabs.firstIndex(where: { $0.id == expected.id }),
              state.tabs[index] == expected, expected.kind == .pinned, expected.resetDestination != nil,
              !retiringTabIDs.contains(expected.id), !state.tabs.contains(where: { $0.id == todayID }),
              !isProfileRemovalPending(expected.profileID),
              state.spaces.contains(where: { $0.id == expected.spaceID && $0.profileID == expected.profileID }),
              !SidebarSplitItems.groups(in: state, spaceID: expected.spaceID)
                  .contains(where: { $0.tabIDs.contains(expected.id) }) else { return false }
        let name = title.isEmpty ? (URL(string: expected.url)?.host ?? "New Tab") : title
        tabHistory?.remove(expected.id)
        state.tabs[index].url = expected.savedURL
        state.tabs[index].title = expected.savedTitle
        state.tabs.append(BrowserTab(id: todayID, spaceID: expected.spaceID, profileID: expected.profileID,
                                     url: expected.url, title: name, kind: .today,
                                     createdAt: clock(), lastAccessed: clock(),
                                     savedURL: expected.url, savedTitle: name))
        SidebarHierarchy.placingCreatedTab(todayID, insertion: .top, in: &state)
        changed()
        return true
    }

    /// A split formed outside the explicit routes (a window's own selection)
    /// still follows `SplitMembership`: a new Today split with fresh homes.
    private func admittingNewSplit(_ layout: BrowserSplitLayout, in base: BrowserState) -> BrowserState? {
        var homeIDs: [UUID: UUID] = [:]
        for home in SplitMembership.savedHomeSources(joining: layout.tabIDs, existing: nil, added: nil, state: base) {
            homeIDs[home.id] = UUID()
        }
        return SplitMembership.admitting(layout, existing: nil, added: nil, state: base,
                                         spaceID: base.activeSpaceID, homeIDs: homeIDs, now: clock())
    }

    ///
    ///
    ///
    ///
    /// pane's Pin/Unpin moves its whole split, every child together.
    func setKind(_ id: UUID, _ kind: TabKind) {
        guard !retiringTabIDs.contains(id), let tab = state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }) else { return }
        let group = SidebarSplitItems.groups(in: state, spaceID: tab.kind == .favorite ? activeSpaceID : tab.spaceID)
            .first { $0.tabIDs.contains(id) }
        let ids = group?.tabIDs ?? [id]
        guard ids.allSatisfy({ !retiringTabIDs.contains($0) }) else { return }
        var destination: UUID?
        if tab.kind == .favorite && kind != .favorite {
            guard let space = state.spaces.first(where: { $0.id == activeSpaceID && $0.profileID == tab.profileID })
                ?? state.spaces.first(where: { $0.profileID == tab.profileID }) else { return }
            destination = space.id
        }
        for member in ids {
            guard let index = state.tabs.firstIndex(where: { $0.id == member && $0.archivedAt == nil }) else { continue }
            let previousKind = state.tabs[index].kind
            if let destination { state.tabs[index].spaceID = destination }
            state.tabs[index].kind = kind
            state.tabs[index].archivedAt = nil
            state.tabs[index].archiveProvenance = nil
            if kind != .pinned { state.tabs[index].folderID = nil }
            // Reclassifying a saved item does not silently repin a navigated-away
            // live page. Entering/leaving Today establishes its current destination.
            if previousKind == .today || kind == .today {
                state.tabs[index].savedURL = state.tabs[index].url
                state.tabs[index].savedTitle = state.tabs[index].title
            }
        }
        if let group, let destination, let index = state.splitLayouts.firstIndex(where: { $0.id == group.id }) {
            state.splitLayouts[index].spaceID = destination
        }
        changed()
    }

    func moveTab(_ id: UUID, toSpace spaceID: UUID, folderID: UUID? = nil) {
        guard let tab = state.tabs.first(where: { $0.id == id }),
              let space = state.spaces.first(where: { $0.id == spaceID }) else { return }
        if let folderID, !state.folders.contains(where: { $0.id == folderID && $0.spaceID == spaceID }) { return }
        if tab.profileID != space.profileID {
            withRetiredPages([id], shouldCommit: { [weak self] in
                guard let self,
                      let current = self.state.tabs.first(where: { $0.id == id }),
                      current.profileID == tab.profileID, current.spaceID == tab.spaceID,
                      self.state.spaces.first(where: { $0.id == spaceID })?.profileID == space.profileID else { return false }
                return folderID == nil || self.state.folders.contains { $0.id == folderID && $0.spaceID == spaceID }
            }) { [weak self] in self?.finishMovingTab(id, toSpace: spaceID, folderID: folderID) }
        } else { finishMovingTab(id, toSpace: spaceID, folderID: folderID) }
    }

    private func finishMovingTab(_ id: UUID, toSpace spaceID: UUID, folderID: UUID?) {
        guard let index = state.tabs.firstIndex(where: { $0.id == id }),
              let space = state.spaces.first(where: { $0.id == spaceID }) else { return }
        if let folderID, !state.folders.contains(where: { $0.id == folderID && $0.spaceID == spaceID }) { return }
        var next = state
        next.tabs[index].spaceID = spaceID
        next.tabs[index].profileID = space.profileID
        next.tabs[index].folderID = folderID
        if folderID != nil { next.tabs[index].kind = .pinned }
        normalizeSelection(in: &next)
        next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
        state = next
        changed(selectionAlreadyStamped: true)
    }

    func reorderTab(_ id: UUID, before otherID: UUID?) {
        guard id != otherID, let index = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        let item = state.tabs[index]
        if let otherID, let target = state.tabs.first(where: { $0.id == otherID }),
           (target.kind != item.kind || target.spaceID != item.spaceID || target.folderID != item.folderID) { return }
        state.tabs.remove(at: index)
        let position = otherID.flatMap { id in state.tabs.firstIndex { $0.id == id } } ?? state.tabs.count
        state.tabs.insert(item, at: position)
        changed()
    }

    @discardableResult
    func createSpace(name: String, color: String = "B9B5D4") -> UUID {
        var space = BrowserSpace(id: UUID(), name: name,
                                 symbol: "circle.fill", color: color, profileID: activeSpace.profileID)
        space.updateDisplayName(position: state.spaces.count)
        // Append + Space selection normalize/stamp publish once (same end state).
        var next = state
        next.spaces.append(space)
        next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
        next.activeSpaceID = space.id
        next.selectedTabIDs = next.selectionBySpace[space.id.uuidString] ?? []
        normalizeSelection(in: &next)
        stampSelection(in: &next)
        next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
        state = next
        changed(selectionAlreadyStamped: true)
        return space.id
    }

    func renameSpace(_ id: UUID, name: String) {
        guard !name.isEmpty, let index = state.spaces.firstIndex(where: { $0.id == id }) else { return }
        state.spaces[index].title = name
        state.spaces[index].updateDisplayName(position: index)
        changed()
    }

    /// Original-Space title/icon leases deliberately do not include the theme:
    /// another editor may change the palette while this native control is open.
    func saveSpaceTitle(_ expected: BrowserSpace, title: String?) throws {
        guard !isEphemeral, !isProfileRemovalPending(expected.profileID),
              let index = state.spaces.firstIndex(where: { $0.id == expected.id && $0.profileID == expected.profileID }),
              state.spaces[index].title == expected.title else { throw CocoaError(.userCancelled) }
        var next = state
        next.spaces[index].title = title.flatMap { $0.isEmpty ? nil : $0 }
        next.spaces[index].updateDisplayName(position: index)
        if next != state { try commitProfileSettings(next) }
    }

    func saveSpaceIcon(_ expected: BrowserSpace, icon: SidebarGroupIcon?) throws {
        guard !isEphemeral, icon?.isValid != false, !isProfileRemovalPending(expected.profileID),
              let index = state.spaces.firstIndex(where: { $0.id == expected.id && $0.profileID == expected.profileID }),
              state.spaces[index].customIcon == expected.customIcon else { throw CocoaError(.userCancelled) }
        var next = state
        next.spaces[index].customIcon = icon
        if next != state { try commitProfileSettings(next) }
    }

    /// Complete original-Space teardown joins the same native consent and
    /// typed document barriers as ordinary folder deletion before one save.
    func deleteSpace(_ target: SpaceDeletionTarget, documents: [UUID: SidebarDocumentReference],
                     shouldCommit: @escaping () -> Bool,
                     didCommit: @escaping (SpaceDeletionUndo) -> Void,
                     completion: @escaping (Result<Bool, Error>) -> Void) {
        let current: () -> Bool = { [weak self] in
            guard let self, !self.isEphemeral else { return false }
            return SpaceDeletionTarget(spaceID: target.space.id, state: self.state) == target
                && SidebarDocumentReference.validates(target.tabs, references: documents)
        }
        guard current(), target.tabIDs.isDisjoint(with: retiringTabIDs) else { completion(.success(false)); return }
        withRetiredPages(target.tabIDs, shouldCommit: { current() && shouldCommit() && current() },
            onRefusal: { completion(.success(false)) }) { [weak self] in
            guard let self, current(),
                  let (undo, next) = SpaceDeletionUndo.make(target: target, state: self.state, now: self.clock(), documents: documents) else {
                completion(.success(false)); return
            }
            do { try self.commitProfileSettings(next); didCommit(undo); completion(.success(true)) }
            catch { completion(.failure(error)) }
        }
    }
    func canUndoSpaceDeletion(_ undo: SpaceDeletionUndo) -> Bool { undo.restoring(in: state) != nil }
    @discardableResult func undoSpaceDeletion(_ undo: SpaceDeletionUndo, shouldCommit: () -> Bool) throws -> Bool {
        guard !isEphemeral, undo.documentsAreAvailable, undo.target.tabIDs.isDisjoint(with: retiringTabIDs),
              shouldCommit(), undo.documentsAreAvailable, undo.target.tabIDs.isDisjoint(with: retiringTabIDs),
              let next = undo.restoring(in: state) else { return false }
        try commitProfileSettings(next); return true
    }

    @discardableResult func reorderSpace(_ id: UUID, before: UUID?, expectedOrder: [UUID]) throws -> Bool {
        guard !isEphemeral, state.spaces.map(\.id) == expectedOrder,
              let old = state.spaces.firstIndex(where: { $0.id == id }), before != id,
              before == nil || state.spaces.contains(where: { $0.id == before }),
              !state.spaces.contains(where: { isProfileRemovalPending($0.profileID) }) else { return false }
        var next = state
        let space = next.spaces.remove(at: old)
        let index = before.flatMap { id in next.spaces.firstIndex { $0.id == id } } ?? next.spaces.count
        next.spaces.insert(space, at: index)
        for i in next.spaces.indices { next.spaces[i].updateDisplayName(position: i) }
        guard next != state else { return true }
        try commitProfileSettings(next); return true
    }

    @discardableResult
    func setSpaceTheme(_ id: UUID, theme: SpaceTheme) -> Bool {
        guard theme.isValid, let index = state.spaces.firstIndex(where: { $0.id == id }) else { return false }
        themePreviews[id] = nil
        guard state.spaces[index].theme != theme else { return true }
        state.spaces[index].theme = theme
        changed()
        return true
    }

    /// Show `theme` on the Space's windows without saving it. A crash or any
    /// session write in the meantime keeps the Space's saved theme.
    @discardableResult
    func previewSpaceTheme(_ id: UUID, theme: SpaceTheme) -> Bool {
        guard theme.isValid, let index = state.spaces.firstIndex(where: { $0.id == id }) else { return false }
        themePreviews[id] = (themePreviews[id]?.saved ?? state.spaces[index].theme, theme)
        // Publish only: a theme moves no split layout or selection, and the
        // session file never records the preview.
        if state.spaces[index].theme != theme { state.spaces[index].theme = theme }
        return true
    }

    /// Drop a preview, showing the saved theme again unless another editor
    /// has since replaced the preview.
    func endSpaceThemePreview(_ id: UUID) {
        guard let entry = themePreviews.removeValue(forKey: id),
              let index = state.spaces.firstIndex(where: { $0.id == id }),
              state.spaces[index].theme == entry.preview else { return }
        state.spaces[index].theme = entry.saved
        changed()
    }

    /// The theme a session write records for the Space, ignoring any preview.
    func savedTheme(of space: BrowserSpace) -> SpaceTheme {
        themePreviews[space.id]?.saved ?? space.theme
    }

    /// A theme commit for a Space under preview replaces the preview.
    private func commitSpaceTheme(_ next: BrowserState, spaceID: UUID) throws {
        let preview = themePreviews.removeValue(forKey: spaceID)
        do { try commitProfileSettings(next) } catch { themePreviews[spaceID] = preview; throw error }
    }

    /// Commit a completed editor gesture only if its original Space/Profile and
    /// before-image still match. Disk failure never publishes a partial theme.
    @discardableResult
    func saveSpaceTheme(spaceID: UUID, profileID: UUID, previous: SpaceTheme,
                        theme: SpaceTheme) throws -> SpaceThemeChange? {
        guard theme.isValid, !isEphemeral, !isProfileRemovalPending(profileID),
              state.profiles.contains(where: { $0.id == profileID }),
              let index = state.spaces.firstIndex(where: {
                  $0.id == spaceID && $0.profileID == profileID && ($0.theme == previous || savedTheme(of: $0) == previous)
              }) else { throw CocoaError(.userCancelled) }
        guard previous != theme else { return nil }
        let change = SpaceThemeChange(spaceID: spaceID, profileID: profileID,
                                      previousTheme: previous, theme: theme)
        var next = state
        next.spaces[index].theme = theme
        try commitSpaceTheme(next, spaceID: spaceID)
        return change
    }

    func canApplySpaceThemeChange(_ change: SpaceThemeChange, undo: Bool) -> Bool {
        !isEphemeral && !isProfileRemovalPending(change.profileID)
            && change.target(in: state, undo: undo) != nil
    }

    @discardableResult
    func applySpaceThemeChange(_ change: SpaceThemeChange, undo: Bool) throws -> Bool {
        guard canApplySpaceThemeChange(change, undo: undo),
              let index = state.spaces.firstIndex(where: { $0.id == change.spaceID }) else { return false }
        var next = state
        next.spaces[index].theme = undo ? change.previousTheme : change.theme
        try commitSpaceTheme(next, spaceID: change.spaceID)
        return true
    }

    /// Sidebar names are independent of the original page's title and saved URL.
    /// Revalidate the original item, but permit live navigation/title updates.
    @discardableResult
    func saveSidebarTitle(_ expected: BrowserTab, title: String) throws -> SidebarTabTitleChange? {
        guard !isProfileRemovalPending(expected.profileID), !retiringTabIDs.contains(expected.id),
              let index = state.tabs.firstIndex(where: { $0.id == expected.id }),
              SidebarTabTitle.sameItemForEditing(state.tabs[index], expected) else {
            throw SidebarTabTitle.EditError.unavailable
        }
        let title = SidebarTabTitle.customValue(title)
        guard state.tabs[index].customTitle != title else { return nil }
        let change = SidebarTabTitleChange(tabID: expected.id, profileID: expected.profileID,
                                           previousTitle: state.tabs[index].customTitle, title: title)
        var next = state
        next.tabs[index].customTitle = title
        try commitProfileSettings(next)
        return change
    }

    /// Favorite Rename is a dialog with a required, literal title. Its supplied
    /// text does not use the ordinary inline editor's empty-name reset path.
    @discardableResult
    func saveFavoriteTitle(_ expected: BrowserTab, title: String) throws -> SidebarTabTitleChange? {
        guard !title.isEmpty, !isEphemeral, expected.kind == .favorite,
              state.profiles.contains(where: { $0.id == expected.profileID }),
              !isProfileRemovalPending(expected.profileID), !retiringTabIDs.contains(expected.id),
              let index = state.tabs.firstIndex(where: { $0.id == expected.id }),
              SidebarTabTitle.sameItemForEditing(state.tabs[index], expected) else {
            throw SidebarTabTitle.EditError.unavailable
        }
        guard state.tabs[index].customTitle != title else { return nil }
        let change = SidebarTabTitleChange(tabID: expected.id, profileID: expected.profileID,
            previousTitle: state.tabs[index].customTitle, title: title)
        var next = state
        next.tabs[index].customTitle = title
        try commitProfileSettings(next)
        return change
    }

    func canApplyTabTitleChange(_ change: SidebarTabTitleChange, undo: Bool) -> Bool {
        !isProfileRemovalPending(change.profileID) && !retiringTabIDs.contains(change.tabID) &&
            change.target(in: state, undo: undo) != nil
    }

    /// Resolve the original item, changing only its manual title. Its current
    /// page, saved destination, membership and selection belong to other owners.
    @discardableResult
    func applyTabTitleChange(_ change: SidebarTabTitleChange, undo: Bool) throws -> Bool {
        guard canApplyTabTitleChange(change, undo: undo),
              let index = state.tabs.firstIndex(where: { $0.id == change.tabID }) else { return false }
        var next = state
        next.tabs[index].customTitle = undo ? change.previousTitle : change.title
        try commitProfileSettings(next)
        return true
    }

    /// A split name belongs to the original container, never its focused child.
    @discardableResult
    func saveSidebarSplitTitle(_ expected: SidebarSplitTitleEdit, title: String) throws -> SidebarSplitTitleChange? {
        guard expected.matches(state), !isProfileRemovalPending(expected.profileID),
              expected.group.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }),
              let index = state.splitLayouts.firstIndex(where: { $0.id == expected.group.id }) else {
            throw SidebarSplitTitleEdit.EditError.unavailable
        }
        if expected.isFavorite && title.isEmpty { throw SidebarSplitTitleEdit.EditError.unavailable }
        let value = expected.isFavorite ? title : SidebarTabTitle.customValue(title)
        guard state.splitLayouts[index].customTitle != value else { return nil }
        let change = SidebarSplitTitleChange(containerID: expected.group.id, profileID: expected.profileID,
                                             previousTitle: state.splitLayouts[index].customTitle, title: value)
        var next = state
        next.splitLayouts[index].customTitle = value
        try commitProfileSettings(next)
        return change
    }

    @discardableResult
    func saveSplitAppearance(_ expected: SidebarSplitTitleEdit, icon: SidebarGroupIcon?, reset: Bool = false) throws -> SidebarSplitAppearanceChange? {
        guard expected.matches(state), icon?.isValid != false,
              !isProfileRemovalPending(expected.profileID),
              Set(expected.group.tabIDs).isDisjoint(with: retiringTabIDs),
              let index = state.splitLayouts.firstIndex(where: { $0.id == expected.group.id }) else { throw SidebarSplitTitleEdit.EditError.unavailable }
        let original = state.splitLayouts[index]
        let title = reset ? nil : original.customTitle
        guard original.customIcon != icon || original.customTitle != title else { return nil }
        let change = SidebarSplitAppearanceChange(containerID: original.id, profileID: expected.profileID,
            previousTitle: original.customTitle, title: title, previousIcon: original.customIcon, icon: icon, resetsTitle: reset)
        var next = state
        next.splitLayouts[index].customIcon = icon
        next.splitLayouts[index].customTitle = title
        try commitProfileSettings(next)
        return change
    }

    func canApplySplitAppearance(_ change: SidebarSplitAppearanceChange, undo: Bool) -> Bool {
        guard let group = change.target(in: state, undo: undo) else { return false }
        return Set(group.tabIDs).isDisjoint(with: retiringTabIDs)
    }
    @discardableResult
    func applySplitAppearance(_ change: SidebarSplitAppearanceChange, undo: Bool) throws -> Bool {
        guard canApplySplitAppearance(change, undo: undo),
              let index = state.splitLayouts.firstIndex(where: { $0.id == change.containerID }) else { return false }
        var next = state
        next.splitLayouts[index].customIcon = undo ? change.previousIcon : change.icon
        if change.resetsTitle { next.splitLayouts[index].customTitle = undo ? change.previousTitle : change.title }
        try commitProfileSettings(next)
        return true
    }

    func canApplySplitTitleChange(_ change: SidebarSplitTitleChange, undo: Bool) -> Bool {
        guard !isProfileRemovalPending(change.profileID), let group = change.target(in: state, undo: undo) else { return false }
        return Set(group.tabIDs).isDisjoint(with: retiringTabIDs)
    }

    /// Re-resolve the original container at commit. Never restore an old layout,
    /// selection, child title or physical page just to apply a name inverse.
    @discardableResult
    func applySplitTitleChange(_ change: SidebarSplitTitleChange, undo: Bool) throws -> Bool {
        guard canApplySplitTitleChange(change, undo: undo),
              let index = state.splitLayouts.firstIndex(where: { $0.id == change.containerID }) else { return false }
        var next = state
        next.splitLayouts[index].customTitle = undo ? change.previousTitle : change.title
        try commitProfileSettings(next)
        return true
    }

    func renameProfile(_ id: UUID, name: String) {
        guard !isProfileRemovalPending(id) else { return }
        guard !name.isEmpty, let index = state.profiles.firstIndex(where: { $0.id == id }) else { return }
        state.profiles[index].name = name
        changed()
    }

    /// Settings commits before publishing, so a write error keeps the name,
    /// native profile path, Space assignments and selected profile unchanged.
    func saveProfileName(_ id: UUID, expectedName: String, name: String) throws {
        guard !isProfileRemovalPending(id) else { throw ProfileRemovalError.incompleteOperation }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ProfileSettingsError.emptyName }
        guard let index = state.profiles.firstIndex(where: { $0.id == id }) else {
            throw ProfileSettingsError.unavailable
        }
        guard state.profiles[index].name == expectedName else {
            throw ProfileSettingsError.nameChanged
        }
        guard expectedName != name else { return }
        var next = state
        next.profiles[index].name = name
        try commitProfileSettings(next)
    }

    func saveSettingsSelection(pane: String, profileID: UUID?) throws {
        guard profileID == nil || state.profiles.contains(where: { $0.id == profileID }) else {
            throw ProfileSettingsError.unavailable
        }
        var next = state
        next.settings.settingsPane = pane
        next.settings.settingsProfileID = profileID
        guard next != state else { return }
        try commitProfileSettings(next)
    }

    /// Settings controls publish only after the session is durably replaced.
    /// Browser gestures retain their existing debounced updateSettings path.
    func saveRestoreSession(_ enabled: Bool) throws {
        var next = state
        next.settings.restoreSession = enabled
        guard next != state else { return }
        try commitProfileSettings(next)
    }

    func saveSidebarWidth(_ width: Double) throws {
        guard width.isFinite else { throw ProfileSettingsError.invalidSidebarWidth }
        var next = state
        next.settings.sidebarWidth = min(500, max(164, width))
        guard next != state else { return }
        try commitProfileSettings(next)
    }

    /// Resolve the editing selection without reassigning the originating Space.
    func settingsPageSpace(profileID: UUID?, originatingSpaceID: UUID?) -> BrowserSpace? {
        guard let profileID, !isEphemeral, !isProfileRemovalPending(profileID),
              state.profiles.contains(where: { $0.id == profileID }) else { return nil }
        return state.spaces.first { $0.id == originatingSpaceID && $0.profileID == profileID }
            ?? state.spaces.first { $0.profileID == profileID }
    }

    private func hasArchiveActivity(_ profileID: UUID) -> Bool {
        archivePreviewLeases.values.contains { $0.profileID == profileID }
            || state.tabs.contains { $0.profileID == profileID && retiringTabIDs.contains($0.id) }
    }

    /// Durable authorization/identity is staged before asking the native owner
    /// to cross its irreversible boundary. The profile remains visible but busy.
    func stageProfileRemoval(_ profileID: UUID, expectedName: String, confirmation: String) throws -> ProfileRemovalRecord {
        let summary = try validateProfileRemoval(profileID, expectedName: expectedName, confirmation: confirmation)
        guard !hasProfileWrite(profileID), !hasArchiveActivity(profileID) else { throw ProfileRemovalError.activeDocumentWrite }
        let record = ProfileRemovalRecord(id: UUID(), profileID: profileID, profileName: summary.profile.name)
        var next = state
        next.settings.defaultProfileID = defaultProfileID
        next.profileRemovals.append(record)
        try commitProfileSettings(next)
        return record
    }

    /// Authorize exactly the reviewed profiles in one durable write. A later
    /// native failure is per profile; it cannot imply rollback of another
    /// profile's completed removal or authorize a newly created profile.
    func stageUnusedProfileRemovals(_ profiles: [BrowserProfile], confirmation: String) throws -> [ProfileRemovalRecord] {
        try validateUnusedProfileRemoval(profiles, confirmation: confirmation)
        guard profiles.allSatisfy({ !hasProfileWrite($0.id) && !hasArchiveActivity($0.id) }) else { throw ProfileRemovalError.activeDocumentWrite }
        let records = profiles.map { ProfileRemovalRecord(id: UUID(), profileID: $0.id, profileName: $0.name) }
        var next = state
        next.settings.defaultProfileID = defaultProfileID
        next.profileRemovals.append(contentsOf: records)
        try commitProfileSettings(next)
        return records
    }

    func cancelProfileRemoval(_ record: ProfileRemovalRecord) throws {
        guard state.profileRemovals.contains(record) else { throw ProfileRemovalError.unavailable }
        var next = state
        next.profileRemovals.removeAll { $0.id == record.id }
        try commitProfileSettings(next)
    }

    /// Called only for a successful, exact native removal receipt. A failed
    /// metadata write leaves the durable record blocking profile reuse for retry.
    func finishProfileRemoval(_ record: ProfileRemovalRecord) throws {
        guard state.profileRemovals.contains(record),
              state.profiles.contains(where: { $0.id == record.profileID }) else {
            throw ProfileRemovalError.unavailable
        }
        guard record.profileID != defaultProfileID else { throw ProfileRemovalError.defaultProfile }
        guard !state.spaces.contains(where: { $0.profileID == record.profileID }) else {
            throw ProfileRemovalError.assignedToSpaces
        }
        let removedTabs = Set(state.tabs.filter { $0.profileID == record.profileID }.map(\.id))
        var next = state
        next.profiles.removeAll { $0.id == record.profileID }
        next.tabs.removeAll { $0.profileID == record.profileID }
        next.history.removeAll { $0.profileID == record.profileID }
        let historyChanged = next.history.count != state.history.count
        next.downloads.removeAll { $0.profileID == record.profileID }
        next.selectedTabIDs.removeAll { removedTabs.contains($0) }
        next.recentlyClosedIDs.removeAll { removedTabs.contains($0) }
        for key in next.selectionBySpace.keys {
            next.selectionBySpace[key]?.removeAll { removedTabs.contains($0) }
        }
        let removedGroups = Set(next.splitLayouts.filter { $0.tabIDs.contains { removedTabs.contains($0) } }.map(\.id))
        next.splitLayouts.removeAll { removedGroups.contains($0.id) }
        for key in next.sidebarItemOrder.keys {
            next.sidebarItemOrder[key]?.removeAll { item in
                switch item {
                case .tab(let id): return removedTabs.contains(id)
                case .split(let id): return removedGroups.contains(id)
                case .folder: return false
                }
            }
        }
        next.profileRemovals.removeAll { $0.id == record.id }
        if next.settings.settingsProfileID == record.profileID {
            next.settings.settingsProfileID = defaultProfileID
        }
        // Easels are app-global. Routes retain their destination UUID and the
        // existing unavailable-destination fallback; neither store is rewritten.
        try commitProfileSettings(next)
        if historyChanged { historyRevision &+= 1 }
    }

    private func commitProfileSettings(_ next: BrowserState) throws {
        if isEphemeral { state = next; return }
        do {
            // Same ISO-8601 / pretty-printed / sorted-keys session bytes as
            // `save()`. Encode runs off the calling thread; when those bytes
            // match the last successful write the atomic replace is a true
            // no-op. Distinct settings revisions still replace in FIFO order.
            // Cancel the debounce only after the persist succeeds so a failed
            // settings write cannot drop an already-scheduled session persist.
            try persistSnapshot(persisted(next), wait: true)
            pendingSave?.cancel(); pendingSave = nil
            pendingSaveSnapshot = nil
            state = next
            reportPersistence(nil)
        } catch {
            reportPersistence(error)
            throw error
        }
    }

    @discardableResult
    func createProfile(name: String) -> UUID {
        let profile = BrowserProfile(id: UUID(), name: name.isEmpty ? "Profile" : name,
                                     autoArchiveHours: state.autoArchiveDefaultHours)
        state.profiles.append(profile)
        changed()
        return profile.id
    }

    @discardableResult
    func createProfilePersisted(name: String) throws -> UUID {
        guard !isEphemeral else { throw CocoaError(.userCancelled) }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw CocoaError(.userCancelled) }
        let profile = BrowserProfile(id: UUID(), name: name, autoArchiveHours: state.autoArchiveDefaultHours)
        var next = state; next.profiles.append(profile)
        try commitProfileSettings(next); return profile.id
    }

    /// Profile assignment shares the real inter-Profile retirement/document
    /// transaction. Never publish new Profile IDs before typed content moves
    /// and the durable session write succeeds.
    func assignProfile(_ profileID: UUID, toSpace spaceID: UUID,
                       shouldCommit: @escaping () -> Bool = { true },
                       completion: @escaping (Result<Bool, Error>) -> Void = { _ in }) {
        guard !isEphemeral, let space = state.spaces.first(where: { $0.id == spaceID }),
              InterProfileMove.profilesAvailable(space.profileID, profileID, in: state) else { completion(.success(false)); return }
        let ids = Set(state.tabs.filter { $0.spaceID == spaceID && $0.kind != .favorite && $0.archivedAt == nil }.map(\.id))
        moveAcrossProfiles(ids, proposal: { current in
            guard shouldCommit(), InterProfileMove.profilesAvailable(space.profileID, profileID, in: current),
                  let index = current.spaces.firstIndex(where: { $0.id == spaceID && $0.profileID == space.profileID }),
                  Set(current.tabs.filter { $0.spaceID == spaceID && $0.kind != .favorite && $0.archivedAt == nil }.map(\.id)) == ids else { return nil }
            var next = current
            if let keeper = next.spaces.first(where: { $0.id != spaceID && $0.profileID == space.profileID }) {
                for i in next.splitLayouts.indices where next.splitLayouts[i].spaceID == spaceID
                    && SidebarSplitItems.isFavorite(next.splitLayouts[i], in: current, profileID: space.profileID) {
                    next.splitLayouts[i].spaceID = keeper.id
                }
            }
            next.spaces[index].profileID = profileID
            for i in next.tabs.indices where ids.contains(next.tabs[i].id) { next.tabs[i].profileID = profileID }
            // A Profile's Favorites may have remained parked after its last
            // Space was removed. Reattach the original whole groups.
            for i in next.splitLayouts.indices where SidebarSplitItems.isFavorite(next.splitLayouts[i], in: next, profileID: profileID)
                && !next.spaces.contains(where: { $0.id == next.splitLayouts[i].spaceID && $0.profileID == profileID }) {
                next.splitLayouts[i].spaceID = spaceID
            }
            for key in next.selectionBySpace.keys {
                next.selectionBySpace[key]?.removeAll { id in
                    guard let tab = next.tabs.first(where: { $0.id == id }), tab.kind == .favorite else { return false }
                    return next.spaces.first { $0.id.uuidString == key }?.profileID != tab.profileID
                }
            }
            if next.activeSpaceID == spaceID {
                next.selectedTabIDs.removeAll { id in next.tabs.first { $0.id == id }?.profileID != profileID }
            }
            return next
        }, completion: completion)
    }

    private func withRetiredPages(_ ids: Set<UUID>,
                                  shouldCommit: @escaping () -> Bool = { true },
                                  onRefusal: (() -> Void)? = nil,
                                  exclusive: Bool = false,
                                  commit: @escaping () -> Void) {
        guard committingRetirementIDs.isDisjoint(with: ids), exclusiveRetirementIDs.isDisjoint(with: ids),
              !exclusive || retiringTabIDs.isDisjoint(with: ids) else { onRefusal?(); return }
        guard !ids.isEmpty, let requestPageRetirement else {
            if exclusive { exclusiveRetirementIDs.formUnion(ids) }
            defer { if exclusive { exclusiveRetirementIDs.subtract(ids) } }
            if shouldCommit() { commit() } else { onRefusal?() }
            return
        }
        let token = UUID()
        if exclusive { exclusiveRetirementIDs.formUnion(ids) }
        var finished = false
        var approved = false
        for id in ids { retirementRequests[id] = token }
        requestPageRetirement(ids, { [weak self] in
            guard let self, !finished, !approved,
                  ids.allSatisfy({ self.retirementRequests[$0] == token }),
                  shouldCommit() else { return false }
            // A validator may reenter the model. Do not authorize an older
            // transaction after it has been replaced by that callback.
            guard ids.allSatisfy({ self.retirementRequests[$0] == token }) else { return false }
            approved = true
            self.committingRetirementIDs.formUnion(ids)
            return true
        }) { [weak self] allowed in
            guard !finished else { return }
            finished = true
            guard let self else { onRefusal?(); return }
            let current = ids.allSatisfy { self.retirementRequests[$0] == token }
            for id in ids where self.retirementRequests[id] == token { self.retirementRequests.removeValue(forKey: id) }
            if !exclusive && approved { self.committingRetirementIDs.subtract(ids) }
            // Exclusive reservations survive synchronous model publication:
            // @Published observers can run before the new state is installed.
            if current && approved && allowed { commit() }
            else { onRefusal?() }
            if exclusive {
                if approved { self.committingRetirementIDs.subtract(ids) }
                self.exclusiveRetirementIDs.subtract(ids)
            }
        }
    }

    @discardableResult
    func createFolder(name: String, parentID: UUID? = nil) -> UUID {
        let id = UUID()
        let parent = parentID.flatMap { parent in folders.contains { $0.id == parent } ? parent : nil }
        state.folders.append(BrowserFolder(id: id, spaceID: activeSpaceID, name: name.isEmpty ? SidebarFolderFromItems.defaultName : name, parentID: parent))
        changed()
        return id
    }

    /// Management sheets retain their original Space/Profile across focus changes.
    @discardableResult
    func createFolder(name: String, in expected: BrowserSpace, parent: BrowserFolder? = nil) throws -> UUID? {
        guard !isEphemeral, state.spaces.contains(where: { $0.id == expected.id && $0.profileID == expected.profileID }),
              !isProfileRemovalPending(expected.profileID),
              parent.map({ $0.spaceID == expected.id && state.folders.contains($0) }) ?? true else { return nil }
        let folder = BrowserFolder(id: UUID(), spaceID: expected.id, name: name.isEmpty ? SidebarFolderFromItems.defaultName : name, parentID: parent?.id)
        var next = state; next.folders.append(folder)
        try commitProfileSettings(next); return folder.id
    }

    @discardableResult
    func convertSpaceToFolder(_ conversion: SpaceFolderConversion) throws -> SpaceFolderUndo? {
        guard !isEphemeral, !conversion.crossesProfiles, conversion.tabIDs.isDisjoint(with: retiringTabIDs),
              SidebarDocumentReference.validates(conversion.target.tabs, references: conversion.documents),
              let (next, undo) = conversion.applying(to: state) else { return nil }
        try commitProfileSettings(next); return undo
    }
    @discardableResult
    func undoSpaceFolderConversion(_ undo: SpaceFolderUndo) throws -> Bool {
        guard !isEphemeral, undo.conversion.tabIDs.isDisjoint(with: retiringTabIDs), undo.documentsAreAvailable,
              let next = undo.restoring(in: state) else { return false }
        try commitProfileSettings(next); return true
    }

    /// A management draft belongs to the original name, placement and Profile.
    /// Disclosure may change independently while the sheet is open.
    @discardableResult
    func renameFolder(_ expected: BrowserFolder, profileID: UUID, name: String) throws -> Bool {
        guard !isEphemeral, !name.isEmpty, !isProfileRemovalPending(profileID),
              state.spaces.contains(where: { $0.id == expected.spaceID && $0.profileID == profileID }),
              let index = state.folders.firstIndex(where: { $0.id == expected.id }),
              state.folders[index].spaceID == expected.spaceID,
              state.folders[index].parentID == expected.parentID,
              state.folders[index].name == expected.name else { return false }
        var next = state; next.folders[index].name = name
        try commitProfileSettings(next); return true
    }

    /// Change Icon… keeps the original folder, Space and Profile.
    @discardableResult
    func setFolderIcon(_ icon: SidebarGroupIcon?, expected: BrowserFolder, profileID: UUID) throws -> Bool {
        guard !isEphemeral, icon?.isValid ?? true, !isProfileRemovalPending(profileID),
              state.spaces.contains(where: { $0.id == expected.spaceID && $0.profileID == profileID }),
              let index = state.folders.firstIndex(where: { $0.id == expected.id }),
              state.folders[index].spaceID == expected.spaceID else { return false }
        guard state.folders[index].customIcon != icon else { return true }
        var next = state; next.folders[index].customIcon = icon
        try commitProfileSettings(next); return true
    }

    func renameFolder(_ id: UUID, name: String) {
        guard !name.isEmpty, let index = state.folders.firstIndex(where: { $0.id == id }) else { return }
        state.folders[index].name = name
        changed()
    }

    func toggleFolder(_ id: UUID) {
        guard let index = state.folders.firstIndex(where: { $0.id == id }) else { return }
        state.folders[index].isExpanded.toggle()
        changed()
    }

    /// Keyboard Return toggles one original folder while the input keeps focus.
    /// Persist the exact disclosure before notifying any window; do not publish
    /// a different folder or a temporary mutation when saving fails.
    @discardableResult
    func setFolderExpanded(_ expanded: Bool, expected: BrowserFolder, profileID: UUID) throws -> Bool {
        guard !isEphemeral,
              state.spaces.contains(where: { $0.id == expected.spaceID && $0.profileID == profileID }),
              state.profiles.contains(where: { $0.id == profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == profileID }),
              let index = state.folders.firstIndex(where: { $0.id == expected.id }),
              state.folders[index] == expected else { return false }
        guard expected.isExpanded != expanded else { return true }
        var next = state
        next.folders[index].isExpanded = expanded
        try commitProfileSettings(next)
        return true
    }

    /// Disclosure belongs to the originating Space, not whichever window most
    /// recently changed the shared store's active selection. Include descendants
    /// hidden by a collapsed parent and publish the entire change atomically.
    @discardableResult
    func setFoldersExpanded(_ expanded: Bool, in spaceID: UUID, profileID: UUID,
                            expectedFolders: [BrowserFolder]) throws -> Bool {
        guard state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }),
              state.profiles.contains(where: { $0.id == profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == profileID }),
              !expectedFolders.isEmpty,
              state.folders.filter({ $0.spaceID == spaceID }) == expectedFolders else { return false }
        guard expectedFolders.contains(where: { $0.isExpanded != expanded }) else { return true }
        var next = state
        for index in next.folders.indices where next.folders[index].spaceID == spaceID {
            next.folders[index].isExpanded = expanded
        }
        // This operation cannot change tab/Space selection, content ownership,
        // split geometry, saved URLs or the other windows' browsing activity.
        try commitProfileSettings(next)
        return true
    }

    @discardableResult
    func revealSidebarItem(_ reveal: SidebarItemReveal) throws -> Bool {
        guard !isEphemeral, let next = reveal.applying(to: state) else { return false }
        if next != state { try commitProfileSettings(next) }
        return true
    }

    /// Persist before publishing. Reordering never closes or reloads a page.
    @discardableResult
    func moveSidebarItem(_ item: SidebarItemReference, to destination: SidebarContainerLocation,
                         before: SidebarItemReference?, expected: SidebarHierarchySnapshot) throws -> Bool {
        let ids = SidebarHierarchy.tabIDs(in: item, state: state, spaceID: expected.spaceID)
        guard ids.allSatisfy({ !retiringTabIDs.contains($0) }),
              let next = SidebarHierarchy.moving(item, to: destination, before: before, expected: expected, state: state) else { return false }
        if next != state { try commitProfileSettings(next) }
        return true
    }

    @discardableResult
    func moveSidebarItems(_ items: [SidebarItemReference], to destination: SidebarContainerLocation,
                          before: SidebarItemReference?, expected: SidebarHierarchySnapshot) throws -> Bool {
        let ids = items.flatMap { SidebarHierarchy.tabIDs(in: $0, state: state, spaceID: expected.spaceID) }
        guard ids.allSatisfy({ !retiringTabIDs.contains($0) }),
              let next = SidebarHierarchy.moving(items, to: destination, before: before, expected: expected, state: state) else { return false }
        if next != state { try commitProfileSettings(next) }
        return true
    }


    /// The draft is window-owned and never persisted. Publish the new Space and
    /// all original item placements only after the same atomic session write.
    /// A failed write leaves the draft's fixed ID available for an explicit retry.
    @discardableResult
    func createSpaceAndMoveSidebarItems(_ draft: SidebarNewSpaceDraft) throws -> UUID? {
        guard !isEphemeral, !draft.tabIDs.contains(where: { retiringTabIDs.contains($0) }),
              let next = draft.applying(to: state) else { return nil }
        try commitProfileSettings(next)
        return draft.spaceID
    }

    ///
    ///
    /// order, and the emptied folder goes in the same atomic write.
    @discardableResult
    func turnFolderIntoSpace(_ draft: SidebarNewSpaceDraft, folder expected: BrowserFolder) throws -> UUID? {
        let contents = SidebarContainerLocation(spaceID: expected.spaceID, folderID: expected.id, section: .pinned)
        guard !isEphemeral, !draft.tabIDs.contains(where: { retiringTabIDs.contains($0) }),
              state.folders.contains(expected), expected.spaceID == draft.source.spaceID,
              let staged = draft.applying(to: state),
              let location = SidebarHierarchy.location(of: .folder(expected.id), state: staged, spaceID: expected.spaceID),
              SidebarHierarchy.children(in: contents, state: staged).isEmpty else { return nil }
        var next = staged
        next.folders.removeAll { $0.id == expected.id }
        // As deleteFolder does: archived records may still name the folder.
        for index in next.tabs.indices where next.tabs[index].folderID == expected.id { next.tabs[index].folderID = nil }
        next.sidebarItemOrder[location.key]?.removeAll { $0 == .folder(expected.id) }
        next.sidebarItemOrder.removeValue(forKey: contents.key)
        try commitProfileSettings(next)
        return draft.spaceID
    }

    /// All affected windows retain their native owners. Commit membership and
    /// hierarchy together only after the original owner leases were validated.
    @discardableResult
    func moveSidebarItemsAcrossSpaces(_ move: SidebarSpaceMove) throws -> Bool {
        guard !isEphemeral, !move.crossesProfiles, move.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }),
              let next = move.applying(to: state) else { return false }
        try commitProfileSettings(next)
        return true
    }

    /// Called only after all original native pages have reached their reserved
    /// destination containers. A failed save asks that same transfer to roll back.
    @discardableResult
    func commitSidebarWindowMove(_ move: SidebarWindowMove) throws -> Bool {
        guard !isEphemeral, !move.crossesProfiles, move.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }),
              let next = move.applying(to: state) else { return false }
        if next != state { try commitProfileSettings(next) }
        return true
    }

    ///
    /// records and deleting/reloading their window contents in the destination
    /// Profile (`WindowAction.deleteAndReloadWindowContentsFor`, emitted by
    ///
    /// moved tabs accepts retirement first, then one durable save publishes
    /// the moved records. The destination recreates each page from its current
    /// URL in its new Profile. A refusal or failed save changes no record.
    func moveAcrossProfiles(_ ids: Set<UUID>, proposal: @escaping (BrowserState) -> BrowserState?,
                            completion: @escaping (Result<Bool, Error>) -> Void) {
        // Each moved tab's Profile before and after, and the local documents
        // (Notes/Easels) that move into the destination Profile's storage.
        func admitted(_ state: BrowserState) -> (next: BrowserState, from: UUID, to: UUID, documents: [InternalPage])? {
            guard let next = proposal(state),
                  let from = InterProfileMove.sourceProfile(of: Array(ids), in: state),
                  let to = InterProfileMove.sourceProfile(of: Array(ids), in: next), from != to,
                  let documents = InterProfileMove.documents(moving: ids, after: next),
                  documents.isEmpty || relocateLocalDocuments != nil else { return nil }
            return (next, from, to, documents)
        }
        //
        // page or document to retire it publishes at once.
        if ids.isEmpty {
            guard !isEphemeral, let next = proposal(state) else { completion(.success(false)); return }
            do { try commitProfileSettings(next); completion(.success(true)) } catch { completion(.failure(error)) }
            return
        }
        guard !isEphemeral, ids.isDisjoint(with: retiringTabIDs),
              ids.allSatisfy({ id in state.tabs.first { $0.id == id }.map(InterProfileMove.admits) == true }),
              admitted(state) != nil else { completion(.success(false)); return }
        // Capture the exact original Easel editors before asynchronous native
        // consent. Revalidate their draft/composition boundary before unload
        // and again before relocating; a replacement editor cannot inherit it.
        let validateEditors: () -> Bool
        if let prepare = prepareLocalDocumentRelocation {
            guard let validate = prepare(ids), validate() else { completion(.success(false)); return }
            validateEditors = validate
        } else { validateEditors = { true } }
        withRetiredPages(ids, shouldCommit: { [weak self] in
            guard let self else { return false }
            return !self.isEphemeral && validateEditors() && admitted(self.state) != nil
        }, onRefusal: { completion(.success(false)) }) { [weak self] in
            guard let self, validateEditors(), let value = admitted(self.state) else { completion(.success(false)); return }
            var rollback: (() -> Void)?
            do {
                if !value.documents.isEmpty, let relocate = self.relocateLocalDocuments {
                    rollback = try relocate(ids, value.documents, value.from, value.to)
                }
                try self.commitProfileSettings(value.next)
                completion(.success(true))
            } catch {
                rollback?()
                completion(.failure(error))
            }
        }
    }

    /// Installed by the native application: closes the moved tabs' local
    /// editors in every window, then moves the exact documents from the source
    /// Profile's stores into the destination's. Returns the undo of that move,
    /// used when the durable save fails.
    var relocateLocalDocuments: ((Set<UUID>, [InternalPage], UUID, UUID) throws -> () -> Void)?
    /// Native editor identity/draft admission for that same Profile transaction.
    var prepareLocalDocumentRelocation: ((Set<UUID>) -> (() -> Bool)?)?

    ///
    /// page/editor to this window first (SP19's collection owner); this then
    /// publishes the placement in one durable save. No page reloads.
    @discardableResult
    func commitForeignSplitDrop(_ ids: Set<UUID>, proposal: (BrowserState) -> BrowserState?) throws -> Bool {
        guard !isEphemeral, !ids.isEmpty, ids.isDisjoint(with: retiringTabIDs), let next = proposal(state),
              ids.allSatisfy({ id in state.tabs.first { $0.id == id }?.profileID == next.tabs.first { $0.id == id }?.profileID }) else { return false }
        try commitProfileSettings(next)
        return true
    }

    var bypassesInterProfileMoveConfirmation: Bool { state.settings.shouldBypassConfirmInterProfileMoveDialog ?? false }

    ///
    func rememberInterProfileMoveChoice() {
        updateSettings { $0.shouldBypassConfirmInterProfileMoveDialog = true }
    }

    /// Folder placement uses one durable commit, including any original same-
    /// profile Space relocation. No intermediate root move is ever published.
    @discardableResult
    func performCommandBarFolderMove(_ move: CommandBarFolderMove) throws -> Bool {
        guard !isEphemeral, move.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }),
              let next = move.applying(to: state) else { return false }
        if next != state { try commitProfileSettings(next) }
        return true
    }

    /// One durable membership transaction; pages and selections retain identity.
    @discardableResult
    func performFavoriteAction(_ action: CommandBarFavoriteAction) throws -> Bool {
        guard !isEphemeral, action.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }),
              let next = action.applying(to: state) else { return false }
        try commitProfileSettings(next)
        return true
    }

    /// The command publishes all original-root copies in one durable write.
    /// Native eager-open requests occur only after these exact IDs exist.
    func copyCommandBarItemsToFolder(_ move: CommandBarFolderMove,
                                     destinations: [UUID: String],
                                     documents: [UUID: SidebarDocumentReference] = [:],
                                     creation: TabCreationProvenance? = nil) throws -> CommandBarFolderCopy? {
        guard !isEphemeral, move.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }),
              let copy = CommandBarFolderCopy(move: move, destinations: destinations, documents: documents,
                  creation: creation, state: state, now: clock()),
              let next = copy.applying(to: state) else { return nil }
        try commitProfileSettings(next)
        return copy
    }

    /// Publish the complete copied tree only after its durable write succeeds.
    /// No original page, selection, history or native retirement is mutated.
    func duplicateFolder(_ target: FolderDuplicateTarget,
                         destinations: [UUID: String],
                         documents: [UUID: SidebarDocumentReference] = [:],
                         creation: TabCreationProvenance? = nil) throws -> FolderDuplicateResult? {
        guard let copied = try duplicateSidebarItems(target.collection, destinations: destinations, documents: documents, creation: creation),
              let first = copied.roots.first, case .folder(let id) = first else { return nil }
        return FolderDuplicateResult(folderID: id, tabIDs: copied.tabIDs, openTabIDs: copied.openTabIDs)
    }

    func duplicateSidebarItems(_ target: SidebarDuplicateTarget,
                         destinations: [UUID: String],
                         documents: [UUID: SidebarDocumentReference] = [:],
                         creation: TabCreationProvenance? = nil) throws -> SidebarDuplicateResult? {
        let expected = target.hierarchy
        guard !isEphemeral, SidebarDuplicateTarget(items: target.roots, spaceID: expected.spaceID,
                profileID: expected.profileID, state: state) == target,
              SidebarCopySources(destinations: destinations, documents: documents).validates(target.tabs),
              target.tabs.allSatisfy({ !retiringTabIDs.contains($0.id) }) else { return nil }
        let previous = creation?.validated(profileID: expected.profileID, state: state).activeTabBeforeCreationID
        let folderMap = Dictionary(uniqueKeysWithValues: target.folderIDs.map { ($0, UUID()) })
        let tabMap = Dictionary(uniqueKeysWithValues: target.tabs.map { ($0.id, UUID()) })
        let groupMap = Dictionary(uniqueKeysWithValues: target.groups.map { ($0.id, UUID()) })
        var next = state
        let now = clock()
        for id in target.folderIDs {
            guard var copy = state.folders.first(where: { $0.id == id }), let newID = folderMap[id] else { return nil }
            copy.id = newID
            if let parent = copy.parentID, let newParent = folderMap[parent] { copy.parentID = newParent }
            next.folders.append(copy)
        }
        for original in target.tabs {
            guard let id = tabMap[original.id], let url = destinations[original.id] else { return nil }
            var copy = original
            copy.id = id
            // Original duplicate constructor102568d9c passes nil referrer and
            // a fresh original-window active item, never the source's chain.
            copy.referrerID = nil; copy.activeTabBeforeCreationID = previous
            if let parent = original.folderID, let folder = folderMap[parent] { copy.folderID = folder }
            copy.url = url; copy.savedURL = url
            copy.title = original.savedTitle; copy.savedTitle = original.savedTitle
            copy.createdAt = now; copy.lastAccessed = now
            copy.isUnread = true; copy.archiveProvenance = nil
            next.tabs.append(copy)
        }
        for group in target.groups {
            guard let id = groupMap[group.id], let anchor = group.sidebarAnchorID,
                  let newAnchor = tabMap[anchor] else { return nil }
            let children = group.tabIDs.compactMap { tabMap[$0] }
            guard children.count == group.tabIDs.count else { return nil }
            next.splitLayouts.append(BrowserSplitLayout(id: id, sidebarAnchorID: newAnchor, customTitle: group.customTitle, customIcon: group.customIcon,
                spaceID: group.spaceID, tabIDs: children, orientation: group.orientation, widthFactors: group.widthFactors))
        }
        for id in target.folderIDs {
            let sourceLocation = SidebarContainerLocation(spaceID: expected.spaceID, folderID: id, section: .pinned)
            let destination = SidebarContainerLocation(spaceID: expected.spaceID, folderID: folderMap[id]!, section: .pinned)
            let children = SidebarHierarchy.children(in: sourceLocation, state: state)
            var copied: [SidebarItemReference] = []
            for child in children {
                switch child {
                case .folder(let id): guard let mapped = folderMap[id] else { return nil }; copied.append(.folder(mapped))
                case .tab(let id): guard let mapped = tabMap[id] else { return nil }; copied.append(.tab(mapped))
                case .split(let id):
                    guard let anchor = target.groups.first(where: { $0.id == id })?.sidebarAnchorID,
                          let mapped = tabMap[anchor] else { return nil }
                    copied.append(.tab(mapped))
                }
            }
            next.sidebarItemOrder[destination.key] = copied
        }
        func mapped(_ item: SidebarItemReference) -> SidebarItemReference? {
            switch item {
            case .folder(let id): return folderMap[id].map(SidebarItemReference.folder)
            case .tab(let id): return tabMap[id].map(SidebarItemReference.tab)
            case .split(let id): return groupMap[id].map(SidebarItemReference.split)
            }
        }
        func stored(_ item: SidebarItemReference) -> SidebarItemReference {
            if case .split(let id) = item, let anchor = next.splitLayouts.first(where: { $0.id == id })?.sidebarAnchorID { return .tab(anchor) }
            return item
        }
        // Adjacent insertion remains Parc's explicit placement policy. Build
        // every affected container from its original mixed order, then save once.
        var siblingsByKey: [String: [SidebarItemReference]] = [:]
        var copiedRoots: [SidebarItemReference] = [], eager: [UUID] = []
        func requestOpen(_ item: SidebarItemReference, shouldOpen: Bool) {
            switch item {
            case .tab(let id):
                if shouldOpen,
                   target.tabs.first(where: { $0.id == id }).map({ InternalPage(urlString: $0.savedURL) == nil }) == true,
                   let copied = tabMap[id] { eager.append(copied) }
            case .folder(let id):
                for child in SidebarHierarchy.children(in: .init(spaceID: expected.spaceID, folderID: id, section: .pinned), state: state) {
                    requestOpen(child, shouldOpen: false)
                }
            case .split(let id):
                for child in target.groups.first(where: { $0.id == id })?.tabIDs ?? [] {
                    requestOpen(.tab(child), shouldOpen: true)
                }
            }
        }
        for (index, root) in target.roots.enumerated() {
            guard let source = SidebarHierarchy.location(of: root, state: state, spaceID: expected.spaceID),
                  let copy = mapped(root) else { return nil }
            var siblings = siblingsByKey[source.key] ?? SidebarHierarchy.children(in: source, state: state)
            guard let position = siblings.firstIndex(of: root) else { return nil }
            siblings.insert(copy, at: position + 1); siblingsByKey[source.key] = siblings
            copiedRoots.append(copy)
            // Context policy2 is the same original indexed adapter: only the
            // first five ordinary roots open, with no truncation of saved copies.
            requestOpen(root, shouldOpen: index < 5)
        }
        for (key, siblings) in siblingsByKey { next.sidebarItemOrder[key] = siblings.map(stored) }
        let result = SidebarDuplicateResult(roots: copiedRoots,
            tabIDs: target.tabs.compactMap { tabMap[$0.id] }, openTabIDs: eager)
        try commitProfileSettings(next)
        return result
    }

    ///
    ///
    ///
    ///
    /// `0x100`, so every web child opens — and the copy then takes the ordinary
    ///
    ///
    /// durable save publishes the placed copies; originals stay untouched.
    func copySidebarSplits(_ copy: SidebarSplitCopy, to destination: SidebarContainerLocation,
                           before: SidebarItemReference?, destinations: [UUID: String],
                           documents: [UUID: SidebarDocumentReference] = [:],
                           creation: TabCreationProvenance? = nil) throws -> SidebarDuplicateResult? {
        guard let placed = placedSplitCopy(copy, to: destination, before: before, destinations: destinations,
                                           documents: documents, creation: creation) else { return nil }
        try commitProfileSettings(placed.state)
        return placed.result
    }

    ///
    /// `WindowAction.deleteAndReloadWindowContentsFor` the dragged originals
    ///
    /// effect), so the originals' live pages are retired through their real
    /// leave-page consent first and reload when shown again in their own
    /// Profile. Only then does one durable save publish the placed copy. A
    /// refusal or failed save publishes nothing.
    func copySidebarSplitsReloadingOriginals(_ copy: SidebarSplitCopy, to destination: SidebarContainerLocation,
                                             before: SidebarItemReference?, destinations: [UUID: String],
                                             documents: [UUID: SidebarDocumentReference] = [:],
                                             creation: TabCreationProvenance? = nil,
                                             completion: @escaping (Result<SidebarDuplicateResult?, Error>) -> Void) {
        let originals = Set(copy.tabs.map(\.id))
        func placed(holding: Bool) -> (state: BrowserState, result: SidebarDuplicateResult)? {
            placedSplitCopy(copy, to: destination, before: before, destinations: destinations,
                            documents: documents, creation: creation, holdingRetirement: holding)
        }
        guard placed(holding: false) != nil else { completion(.success(nil)); return }
        withRetiredPages(originals, shouldCommit: { placed(holding: true) != nil },
                         onRefusal: { completion(.success(nil)) }) { [weak self] in
            guard let self, let value = placed(holding: false) else { completion(.success(nil)); return }
            do { try self.commitProfileSettings(value.state); completion(.success(value.result)) }
            catch { completion(.failure(error)) }
        }
    }

    /// The drop proposal: whether this copy would be placed, without saving.
    func canCopySidebarSplits(_ copy: SidebarSplitCopy, to destination: SidebarContainerLocation,
                              before: SidebarItemReference?, destinations: [UUID: String],
                              documents: [UUID: SidebarDocumentReference] = [:]) -> Bool {
        placedSplitCopy(copy, to: destination, before: before, destinations: destinations,
                        documents: documents, creation: nil) != nil
    }

    private func placedSplitCopy(_ original: SidebarSplitCopy, to destination: SidebarContainerLocation,
                                 before: SidebarItemReference?, destinations: [UUID: String],
                                 documents: [UUID: SidebarDocumentReference],
                                 creation: TabCreationProvenance?,
                                 holdingRetirement: Bool = false) -> (state: BrowserState, result: SidebarDuplicateResult)? {
        let source = original.source
        // The gesture binds the splits' placement; the copy takes their
        // current records.
        guard !isEphemeral,
              let copy = SidebarSplitCopy(items: original.roots, spaceID: source.spaceID, profileID: source.profileID, state: state),
              copy.matchesPlacement(of: original),
              SidebarCopySources(destinations: destinations, documents: documents).validates(copy.tabs),
              holdingRetirement || copy.tabs.allSatisfy({ !retiringTabIDs.contains($0.id) }),
              let destinationProfile = state.spaces.first(where: { $0.id == destination.spaceID })?.profileID,
              destination.profileID == nil || destination.profileID == destinationProfile else { return nil }
        // Parc keeps Notes and Easels per Profile, so a document alias cannot
        //
        guard destinationProfile == source.profileID
                || copy.tabs.allSatisfy({ InternalPage(urlString: $0.savedURL) == nil }) else { return nil }
        let previous = creation?.validated(profileID: source.profileID, state: state).activeTabBeforeCreationID
        let now = clock()
        var next = state
        var roots: [SidebarItemReference] = [], tabIDs: [UUID] = [], open: [UUID] = []
        var siblingsByKey: [String: [SidebarItemReference]] = [:]
        for group in copy.groups {
            guard let anchor = group.sidebarAnchorID,
                  let location = SidebarHierarchy.location(of: .split(group.id), state: state, spaceID: source.spaceID) else { return nil }
            let map = Dictionary(uniqueKeysWithValues: group.tabIDs.map { ($0, UUID()) })
            for id in group.tabIDs {
                guard let original = copy.tabs.first(where: { $0.id == id }), let url = destinations[id], let newID = map[id] else { return nil }
                // The duplicate constructor (102568d9c) passes nil referrer and a
                // fresh active-before item, as the context Duplicate does.
                var tab = original
                tab.id = newID; tab.referrerID = nil; tab.activeTabBeforeCreationID = previous
                tab.url = url; tab.savedURL = url
                tab.title = original.savedTitle; tab.savedTitle = original.savedTitle
                tab.createdAt = now; tab.lastAccessed = now
                tab.isUnread = true; tab.archiveProvenance = nil
                next.tabs.append(tab); tabIDs.append(newID)
                if InternalPage(urlString: original.savedURL) == nil { open.append(newID) }
            }
            let id = UUID()
            guard let newAnchor = map[anchor] else { return nil }
            next.splitLayouts.append(BrowserSplitLayout(id: id, sidebarAnchorID: newAnchor, customTitle: group.customTitle,
                customIcon: group.customIcon, spaceID: group.spaceID, tabIDs: group.tabIDs.compactMap { map[$0] },
                orientation: group.orientation, widthFactors: group.widthFactors))
            var siblings = siblingsByKey[location.key] ?? SidebarHierarchy.children(in: location, state: state)
            guard let index = siblings.firstIndex(of: .split(group.id)) else { return nil }
            siblings.insert(.split(id), at: index + 1); siblingsByKey[location.key] = siblings
            roots.append(.split(id))
        }
        func stored(_ item: SidebarItemReference) -> SidebarItemReference {
            if case .split(let id) = item, let anchor = next.splitLayouts.first(where: { $0.id == id })?.sidebarAnchorID { return .tab(anchor) }
            return item
        }
        for (key, siblings) in siblingsByKey { next.sidebarItemOrder[key] = siblings.map(stored) }
        guard let move = SidebarWindowMove(items: roots, sourceSpaceID: source.spaceID, profileID: source.profileID,
                  destinationProfileID: destinationProfile, to: destination, before: before, state: next),
              let placed = move.applying(to: next) else { return nil }
        return (placed, SidebarDuplicateResult(roots: roots, tabIDs: tabIDs, openTabIDs: open))
    }

    /// The shell confirms Delete first. All original pages, including owners in
    /// other windows and Peek children, then join the existing retirement gate.
    /// A refusal never publishes partial folder removal or archive records.
    func deleteFolder(_ target: FolderRemovalTarget, selection: FolderRemovalSelection? = nil,
                      documents: [UUID: SidebarDocumentReference] = [:],
                      shouldCommit: @escaping () -> Bool,
                      didCommit: ((FolderDeletionUndo) -> Void)? = nil,
                      completion: @escaping (Result<Bool, Error>) -> Void) {
        let expected = target.hierarchy, ids = Set(target.tabs.map(\.id))
        let current: () -> Bool = { [weak self] in
            guard let self else { return false }
            guard FolderRemovalTarget(items: target.roots, spaceID: expected.spaceID,
                profileID: expected.profileID, state: self.state) == target,
                  SidebarDocumentReference.validates(target.tabs, references: documents) else { return false }
            guard let selection else { return true }
            return FolderRemovalSelection.resolve(target: target, state: self.state,
                selected: selection.original, focused: selection.originalFocus, referrerPool: selection.referrerPool,
                previouslySelectedItemID: selection.previouslySelectedItemID, available: { selection.tabIDs.contains($0) }) == selection
        }
        guard current(), ids.isDisjoint(with: retiringTabIDs) else { completion(.success(false)); return }
        withRetiredPages(ids, shouldCommit: {
            guard current(), shouldCommit() else { return false }
            // The originating validator may synchronously mutate the model.
            return current()
        }, onRefusal: { completion(.success(false)) }) { [weak self] in
            guard let self, current() else { completion(.success(false)); return }
            var next = self.state
            let now = self.clock()
            var provenance = Dictionary(uniqueKeysWithValues: target.tabs.map { tab in
                (tab.id, ArchiveProvenance(reason: .manual, spaceID: tab.spaceID,
                    spaceName: next.spaces.first { $0.id == tab.spaceID }?.name ?? "Space"))
            })
            // Preserve an entire original split as one archive item. No pane
            // outside this exact subtree is closed or attached to the archive.
            for split in target.groups where split.tabIDs.allSatisfy({ provenance[$0]?.groupID == nil }) {
                let group = UUID()
                for id in split.tabIDs { provenance[id]?.groupID = group; provenance[id]?.split = split }
            }
            for index in next.tabs.indices {
                if ids.contains(next.tabs[index].id) {
                    next.tabs[index].archivedAt = now
                    next.tabs[index].archiveProvenance = provenance[next.tabs[index].id]
                }
                // Previously archived records may still name a deleted folder.
                if next.tabs[index].folderID.map(target.folderIDs.contains) == true { next.tabs[index].folderID = nil }
            }
            next.folders.removeAll { target.folderIDs.contains($0.id) }
            next.splitLayouts.removeAll { !$0.tabIDs.allSatisfy { !ids.contains($0) } }
            next.recentlyClosedIDs.removeAll { ids.contains($0) }
            next.recentlyClosedIDs += target.tabs.map(\.id)
            next.selectedTabIDs.removeAll { ids.contains($0) }
            for key in Array(next.selectionBySpace.keys) { next.selectionBySpace[key]?.removeAll { ids.contains($0) } }
            if let selection {
                next.selectionBySpace[selection.replacementSpaceID.uuidString] = selection.tabIDs
                // Another physical window's last-used shared selection is not
                // the origin of this command. Do not overwrite it by coincidence.
                if next.activeSpaceID == expected.spaceID && self.state.selectedTabIDs == selection.original {
                    next.activeSpaceID = selection.replacementSpaceID
                    next.selectedTabIDs = selection.tabIDs
                }
            }
            let deletedContainers = Set(target.folderIDs.map {
                SidebarContainerLocation(spaceID: expected.spaceID, folderID: $0, section: .pinned).key
            })
            for key in Array(next.sidebarItemOrder.keys) {
                if deletedContainers.contains(key) { next.sidebarItemOrder.removeValue(forKey: key); continue }
                next.sidebarItemOrder[key]?.removeAll { item in
                    switch item {
                    case .folder(let id): return target.folderIDs.contains(id)
                    case .tab(let id): return ids.contains(id)
                    case .split(let id): return target.groups.contains { $0.id == id }
                    }
                }
            }
            do {
                // Existing owners have closed. A save failure keeps the saved
                // tree intact and reports failure; it must not fake success.
                let undo = FolderDeletionUndo(target: target, selection: selection, documents: documents, before: self.state, after: next)
                try self.commitProfileSettings(next)
                didCommit?(undo)
                completion(.success(true))
            } catch { completion(.failure(error)) }
        }
    }

    func canUndoFolderDeletion(_ undo: FolderDeletionUndo) -> Bool {
        let folderIDs = Set(undo.folders.map(\.id)), ids = Set(undo.tabs.map(\.id))
        guard !isEphemeral, !isProfileRemovalPending(undo.profileID),
              state.profiles.contains(where: { $0.id == undo.profileID }),
              state.spaces.contains(where: { $0.id == undo.spaceID && $0.profileID == undo.profileID }),
              folderIDs.count == undo.folders.count, ids.count == undo.tabs.count,
              undo.archivedTabs.count == undo.tabs.count,
              state.folders.allSatisfy({ !folderIDs.contains($0.id) }),
              state.splitLayouts.allSatisfy({ group in !undo.groups.contains { $0.id == group.id }
                  && group.tabIDs.allSatisfy { !ids.contains($0) } }),
              undo.archivedTabs.allSatisfy({ archived in archived.archivedAt != nil
                  && state.tabs.first(where: { $0.id == archived.id }) == archived }),
              undo.locations.allSatisfy({ location in
                  location.container.folderID == nil || state.folders.contains(where: {
                      $0.id == location.container.folderID && $0.spaceID == undo.spaceID
                  })
              }) else { return false }
        return true
    }

    /// Restores only the recorded original subtree and its exact still-archived
    /// members. Unrelated state is read from the current store, not rolled back.
    @discardableResult
    func undoFolderDeletion(_ undo: FolderDeletionUndo, shouldCommit: () -> Bool) throws -> Bool {
        let ids = Set(undo.tabs.map(\.id))
        guard canUndoFolderDeletion(undo), undo.documentsAreAvailable, ids.isDisjoint(with: retiringTabIDs),
              shouldCommit(), canUndoFolderDeletion(undo), undo.documentsAreAvailable,
              ids.isDisjoint(with: retiringTabIDs) else { return false }
        var next = state
        next.folders += undo.folders
        for original in undo.tabs {
            guard let index = next.tabs.firstIndex(where: { $0.id == original.id }) else { return false }
            next.tabs[index] = original
        }
        // Delete had detached preexisting archived records from removed containers.
        // Restore that reference only if that exact archived record is unchanged.
        for original in undo.detachedArchive {
            var expected = original; expected.folderID = nil
            if let index = next.tabs.firstIndex(where: { $0.id == original.id && $0 == expected }) {
                next.tabs[index].folderID = original.folderID
            }
        }
        next.splitLayouts += undo.groups
        next.recentlyClosedIDs.removeAll { ids.contains($0) }
        for (key, order) in undo.childOrder { next.sidebarItemOrder[key] = order }
        for location in undo.locations {
            var siblings = SidebarHierarchy.children(in: location.container, state: state)
            // Restore original roots in their original local order. Existing
            // survivors anchor each insertion, including roots restored above.
            for root in location.siblings where undo.roots.contains(root) {
                guard let position = location.siblings.firstIndex(of: root), !siblings.contains(root) else { return false }
                let following = location.siblings.dropFirst(position + 1).first { siblings.contains($0) }
                let preceding = location.siblings.prefix(position).reversed().first { siblings.contains($0) }
                let insertion = following.flatMap { siblings.firstIndex(of: $0) }
                    ?? preceding.flatMap { siblings.firstIndex(of: $0).map { $0 + 1 } }
                    ?? min(position, siblings.count)
                siblings.insert(root, at: insertion)
            }
            next.sidebarItemOrder[location.container.key] = siblings.map { item in
                if case .split(let id) = item, let anchor = next.splitLayouts.first(where: { $0.id == id })?.sidebarAnchorID { return .tab(anchor) }
                return item
            }
        }
        // Physical-window selection is deliberately completed by its owner.
        try commitProfileSettings(next)
        return true
    }

    func canUndoClosedTabs(_ undo: ClosedTabsUndo) -> Bool {
        !isProfileRemovalPending(undo.profileID)
            && state.profiles.contains(where: { $0.id == undo.profileID })
            && state.spaces.contains(where: { $0.id == undo.spaceID && $0.profileID == undo.profileID })
            && !undo.restorableIDs(in: state).isEmpty
    }

    /// Durable before publication: a failed write leaves the tabs archived
    /// and the Undo retryable. An archived item open in a Library preview waits.
    @discardableResult
    func undoClosedTabs(_ undo: ClosedTabsUndo, regroupable: (UUID) -> Bool = { _ in true },
                        shouldCommit: () -> Bool) throws -> Bool {
        let ids = undo.restorableIDs(in: state)
        guard canUndoClosedTabs(undo), ids.isDisjoint(with: retiringTabIDs), !archivePreviewOverlaps(ids),
              shouldCommit(), canUndoClosedTabs(undo), undo.restorableIDs(in: state) == ids,
              ids.isDisjoint(with: retiringTabIDs), !archivePreviewOverlaps(ids),
              let next = undo.restoring(state, regroupable: { [retiringTabIDs] id in
                  !retiringTabIDs.contains(id) && regroupable(id)
              }) else { return false }
        try commitProfileSettings(next)
        return true
    }

    func setSplit(_ ids: [UUID], adding added: UUID? = nil) {
        let available = Set(visibleTabs.map(\.id))
        var unique: [UUID] = []
        for id in ids where available.contains(id) && !unique.contains(id) { unique.append(id) }
        var next = state
        _ = activateSplit(Array(unique.prefix(4)), adding: added, into: &next)
        stampSelection(in: &next)
        next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
        state = next
        changed(selectionAlreadyStamped: true)
    }

    @discardableResult
    func setSplitLayout(orientation: SplitOrientation, widthFactors: [Double]) -> Bool {
        guard let factors = BrowserSplitLayout.normalized(widthFactors, count: state.selectedTabIDs.count) else { return false }
        let layout = BrowserSplitLayout(id: activeSplitLayout?.id ?? UUID(), sidebarAnchorID: activeSplitLayout?.sidebarAnchorID, customTitle: activeSplitLayout?.customTitle, customIcon: activeSplitLayout?.customIcon, spaceID: activeSplitLayout?.spaceID ?? activeSpaceID, tabIDs: state.selectedTabIDs,
                                        orientation: orientation, widthFactors: factors)
        if let index = state.splitLayouts.firstIndex(where: { $0.id == layout.id }) {
            if state.splitLayouts[index] == layout { return true }
            state.splitLayouts[index] = layout
        } else {
            // A selection without its split forms one through the membership owner.
            guard let next = admittingNewSplit(layout, in: state) else { return false }
            state = next
        }
        changed()
        return true
    }

    /// New Folder with *n* Items (SidebarFolderFromItems): the folder and the
    /// moved items publish together after one durable write.
    @discardableResult
    func createFolder(containing items: [SidebarItemReference], folderID: UUID,
                      expected: SidebarHierarchySnapshot) throws -> SidebarFolderFromItems? {
        // The snapshot names its Space; another window may have made a
        // different Space the store's active one since.
        guard !isEphemeral, !isProfileRemovalPending(expected.profileID),
              let (receipt, next) = SidebarFolderFromItems.make(items: items, folderID: folderID, expected: expected, state: state),
              receipt.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }) else { return nil }
        try commitProfileSettings(next)
        return receipt
    }

    /// Undo (true) or Redo (false) of one New Folder with *n* Items. The
    /// returned receipt keeps the folder's current name and presentation for
    /// Redo, including the name entered immediately after creation.
    @discardableResult
    func revertFolderCreation(_ receipt: SidebarFolderFromItems, undo: Bool) throws -> SidebarFolderFromItems? {
        guard !isEphemeral, !isProfileRemovalPending(receipt.profileID),
              receipt.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }),
              let next = receipt.reverting(state, undo: undo) else { return nil }
        var updated = receipt
        if undo, let folder = state.folders.first(where: { $0.id == receipt.folderID }) {
            updated.folder = folder
        }
        try commitProfileSettings(next)
        return updated
    }

    /// Convert to Vertical/Horizontal Split View from the split cell menu
    ///
    ///
    /// proportions, membership and selection stay. A displayed split shows the
    /// new orientation.
    @discardableResult
    func flipSplitOrientation(expected: BrowserSplitLayout) -> Bool {
        guard !isProfileRemovalPending(activeSpace.profileID),
              SidebarSplitItems.groups(in: state, spaceID: activeSpaceID).contains(expected),
              let index = state.splitLayouts.firstIndex(of: expected),
              expected.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }) else { return false }
        var next = state
        next.splitLayouts[index].orientation = expected.orientation == .horizontal ? .vertical : .horizontal
        do { try commitProfileSettings(next); return true }
        catch { return false }
    }

    ///
    ///
    ///
    /// keeps its saved placement. A displayed split keeps the focused original
    /// page displayed alone, because the focused content is among those
    ///
    ///
    /// reloaded.
    @discardableResult
    func separateAllTabsFromSplit(expected: BrowserSplitLayout, focusedID: UUID?) -> Bool {
        guard !isProfileRemovalPending(activeSpace.profileID),
              SidebarSplitItems.groups(in: state, spaceID: activeSpaceID).contains(expected),
              let index = state.splitLayouts.firstIndex(of: expected),
              expected.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }) else { return false }
        var next = state
        next.splitLayouts.remove(at: index)
        // Replace the split's one stored slot with its children in pane order,
        // including after a whole-split move stored only its anchor there.
        SplitMembership.preservingSlots(before: state, after: &next)
        if next.selectedTabIDs == expected.tabIDs, let first = expected.tabIDs.first {
            let kept = focusedID.flatMap { expected.tabIDs.contains($0) ? $0 : nil } ?? first
            next.selectedTabIDs = [kept]
            next.selectionBySpace[activeSpaceID.uuidString] = [kept]
            if let tab = next.tabs.firstIndex(where: { $0.id == kept }) {
                next.tabs[tab].lastAccessed = clock(); next.tabs[tab].isUnread = false
            }
        }
        do { try commitProfileSettings(next); return true }
        catch { return false }
    }

    /// Commit one admitted original divider operation before publishing the
    /// new geometry. Selection, membership, placement and live page IDs survive.
    @discardableResult
    func resizeSplit(expected: BrowserSplitLayout, widthFactors: [Double]) -> Bool {
        guard activeSplitLayout == expected, state.selectedTabIDs == expected.tabIDs,
              !isProfileRemovalPending(activeSpace.profileID),
              SidebarSplitItems.groups(in: state, spaceID: activeSpaceID).contains(expected),
              expected.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }),
              let factors = BrowserSplitLayout.normalized(widthFactors, count: expected.tabIDs.count),
              let index = state.splitLayouts.firstIndex(of: expected) else { return false }
        var next = state
        next.splitLayouts[index].widthFactors = factors
        do { try commitProfileSettings(next); return true }
        catch { return false }
    }

    /// A pane-menu reorder moves the original ID and its size together. Saved
    /// parent placement, group identity, focused item and every live owner stay.
    @discardableResult
    func moveSplitPane(_ id: UUID, offset: Int, expected: BrowserSplitLayout) -> Bool {
        guard (offset == -1 || offset == 1), activeSplitLayout == expected,
              state.selectedTabIDs == expected.tabIDs,
              !isProfileRemovalPending(activeSpace.profileID),
              SidebarSplitItems.groups(in: state, spaceID: activeSpaceID).contains(expected),
              expected.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }),
              let index = expected.tabIDs.firstIndex(of: id),
              expected.tabIDs.indices.contains(index + offset),
              let stored = state.splitLayouts.firstIndex(of: expected) else { return false }
        var next = state, layout = expected
        layout.tabIDs.swapAt(index, index + offset)
        layout.widthFactors.swapAt(index, index + offset)
        next.splitLayouts[stored] = layout
        next.selectedTabIDs = layout.tabIDs
        next.selectionBySpace[activeSpaceID.uuidString] = layout.tabIDs
        do { try commitProfileSettings(next); return true } catch { return false }
    }

    /// The URL is metadata from an already classified native navigation. Its
    /// full request remains retained by the originating window until adoption.
    @discardableResult
    func insertSplitPane(_ request: SplitPaneInsertion, tabID: UUID, navigationURL: URL?,
                         creation: TabCreationProvenance?, savedHomeIDs: [UUID: UUID],
                         documents: [UUID: SidebarDocumentReference],
                         localPage: InternalPage? = nil, localTitle: String? = nil) -> Bool {
        var savedHomeIDs = savedHomeIDs
        //
        // (SplitCrossSpaceAdd); its saved home, if any, stays in its Space.
        let foreign = state.tabs.contains { $0.id == tabID && $0.spaceID != request.spaceID && $0.kind != .favorite }
        let foreignHomeID = foreign ? savedHomeIDs.removeValue(forKey: tabID) : nil
        guard (request.selection + [tabID] + Array(savedHomeIDs.values) + [foreignHomeID].compactMap { $0 })
                .allSatisfy({ !retiringTabIDs.contains($0) }),
              let current = request.preparedState(state, tabID: tabID, navigationURL: navigationURL,
                  localPage: localPage, localTitle: localTitle, now: clock(), creation: creation),
              // The window planned homes and typed references before the move,
              // when a pinned source from another Space still needed one.
              let homes = OriginalSplitDrop.savedHomes(source: tabID, state: current,
                  selection: request.selection, layout: request.layout, target: .insert(request.index),
                  orientation: request.orientation, spaceID: request.spaceID),
              SidebarDocumentReference.validates(homes, references: documents),
              let prepared = foreign ? SplitCrossSpaceAdd.relocated(current, source: tabID, into: request.spaceID,
                  profileID: request.profileID, pane: request.paneID, homeID: foreignHomeID, now: clock()) : current,
              let next = OriginalSplitDrop.proposal(source: tabID, state: prepared,
                  selection: request.selection, layout: request.layout, target: .insert(request.index),
                  orientation: request.orientation, spaceID: request.spaceID, profileID: request.profileID,
                  now: clock(), savedHomeIDs: savedHomeIDs, creation: creation) else { return false }
        do { try commitProfileSettings(next); return true } catch { return false }
    }

    func closeSplit() {
        let originalID = activeSplitLayout?.id, before = state
        var next = state
        next.splitLayouts.removeAll { $0.id == originalID }
        //
        SplitMembership.preservingSlots(before: before, after: &next)
        next.selectedTabIDs = Array(next.selectedTabIDs.prefix(1))
        stampSelection(in: &next)
        next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
        state = next
        changed(selectionAlreadyStamped: true)
    }
    /// The main-menu action separates the original focused page and keeps it
    /// displayed. It does not close either side of the former split.
    @discardableResult
    func separateSplitPane(_ id: UUID) -> Bool {
        guard let group = activeSplitLayout else { return false }
        return separateTabFromSplit(id, expected: group, focusedID: id)
    }

    /// A background sidebar target changes its saved container only. When the
    /// target is displayed, the original focus determines which side stays on
    /// screen; the window owns native focus after the durable publication.
    @discardableResult
    func separateTabFromSplit(_ id: UUID, expected: BrowserSplitLayout, focusedID: UUID? = nil) -> Bool {
        guard !isProfileRemovalPending(activeSpace.profileID),
              SidebarSplitItems.groups(in: state, spaceID: activeSpaceID).contains(expected), expected.tabIDs.contains(id),
              let index = state.splitLayouts.firstIndex(of: expected),
              expected.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }),
              focusedID.map({ state.selectedTabIDs.contains($0) }) ?? true else { return false }
        var next = state, remaining = expected
        let position = remaining.tabIDs.firstIndex(of: id)!
        remaining.tabIDs.remove(at: position); remaining.widthFactors.remove(at: position)
        if let weights = BrowserSplitLayout.normalized(remaining.widthFactors, count: remaining.tabIDs.count) {
            remaining.widthFactors = weights
            if remaining.sidebarAnchorID == id { remaining.sidebarAnchorID = remaining.tabIDs.first }
            next.splitLayouts[index] = remaining
        } else { next.splitLayouts.remove(at: index) }
        // The separated child follows the split in its container; a split left
        //
        SplitMembership.preservingSlots(before: state, after: &next)
        if next.selectedTabIDs == expected.tabIDs {
            next.selectedTabIDs = focusedID == id ? [id] : remaining.tabIDs
            next.selectionBySpace[activeSpaceID.uuidString] = next.selectedTabIDs
            let now = clock(), selected = Set(next.selectedTabIDs)
            for index in next.tabs.indices where selected.contains(next.tabs[index].id) {
                next.tabs[index].lastAccessed = now
                next.tabs[index].isUnread = false
            }
        }
        do { try commitProfileSettings(next); return true }
        catch { return false }
    }

    ///
    /// Extending or editing the displayed split keeps that container; other
    /// sets form a new Today split. Saved members newly joining leave fresh
    /// homes (`SplitMembership`). A refused change leaves the selection as it was.
    /// Mutates `next` only so callers can publish once with surrounding work.
    @discardableResult
    private func activateSplit(_ ids: [UUID], savedHomeIDs: [UUID: UUID] = [:], adding added: UUID? = nil,
                               into next: inout BrowserState) -> Bool {
        let spaceID = next.activeSpaceID
        let previous = SidebarSplitItems.groups(in: next, spaceID: spaceID)
            .first { $0.tabIDs == next.selectedTabIDs }
        let previousSelection = next.selectedTabIDs
        next.selectedTabIDs = ids
        let active = SidebarSplitItems.groups(in: next, spaceID: spaceID)
            .first { $0.tabIDs == next.selectedTabIDs }
        guard ids.count > 1, active == nil else { return true }
        var factors = Array(repeating: 1.0, count: ids.count)
        var orientation = SplitOrientation.horizontal
        if let previous, ids.contains(where: { previous.tabIDs.contains($0) }) {
            orientation = previous.orientation
            if ids.count == previous.tabIDs.count {
                // Cycling a tab replaces content in a pane without moving the divider.
                factors = previous.widthFactors
            } else {
                factors = ids.map { id in
                    previous.tabIDs.firstIndex(of: id).map { previous.widthFactors[$0] }
                        ?? (1.0 / Double(previous.tabIDs.count))
                }
            }
        }
        let retained = previous.flatMap { old in ids.contains(where: { old.tabIDs.contains($0) }) ? old : nil }
        let group = BrowserSplitLayout(id: retained?.id ?? UUID(), sidebarAnchorID: retained?.sidebarAnchorID, customTitle: retained?.customTitle, customIcon: retained?.customIcon, spaceID: retained?.spaceID ?? spaceID, tabIDs: ids,
            orientation: orientation, widthFactors: BrowserSplitLayout.normalized(factors, count: ids.count)!)
        var homeIDs = savedHomeIDs
        for home in SplitMembership.savedHomeSources(joining: ids, existing: retained, added: added, state: next)
            where homeIDs[home.id] == nil { homeIDs[home.id] = UUID() }
        guard let admitted = SplitMembership.admitting(group, existing: retained, added: added, state: next,
                                                       spaceID: spaceID, homeIDs: homeIDs, now: clock()) else {
            next.selectedTabIDs = previous == nil ? Array(previousSelection.prefix(1)) : previousSelection
            return false
        }
        next = admitted
        return true
    }

    private func removePaneFromActiveSplit(_ id: UUID) {
        guard let original = activeSplitLayout, let index = state.splitLayouts.firstIndex(of: original),
              let pane = state.splitLayouts[index].tabIDs.firstIndex(of: id) else { return }
        var layout = state.splitLayouts.remove(at: index)
        layout.tabIDs.remove(at: pane)
        layout.widthFactors.remove(at: pane)
        // If this becomes an existing group, the visible split's geometry wins.
        state.splitLayouts.append(layout)
    }

    ///
    /// result is written back with the rest of the restored session.
    private func migrateLegacySplitContainers() {
        var next = SplitMembership.normalizingLegacyContainers(state, now: clock())
        guard next != state else { return }
        normalizeSelection(in: &next)
        reconcileSplitLayouts(into: &next)
        state = next
    }

    private func reconcileSplitLayouts() {
        var next = state
        reconcileSplitLayouts(into: &next)
        if next != state { state = next }
    }

    private func reconcileSplitLayouts(into next: inout BrowserState) {
        let layouts = Self.reconciledSplitLayouts(in: next, activeSpaceID: next.activeSpaceID)
        if layouts != next.splitLayouts { next.splitLayouts = layouts }
        let active = SidebarSplitItems.groups(in: next, spaceID: next.activeSpaceID)
            .first { $0.tabIDs == next.selectedTabIDs }
        guard next.selectedTabIDs.count > 1 && active == nil else { return }
        let visible = SidebarSplitItems.groups(in: next, spaceID: next.activeSpaceID)
        if let first = next.selectedTabIDs.first,
           next.selectedTabIDs.contains(where: { id in visible.contains { $0.tabIDs.contains(id) } }) {
            // A remembered selection made stale by a split change shows the
            // split holding its first page; it never forms a new split that
            // takes members (and saved homes) from existing splits.
            next.selectedTabIDs = visible.first { $0.tabIDs.contains(first) }?.tabIDs ?? [first]
        } else {
            _ = activateSplit(next.selectedTabIDs, into: &next)
            reconcileSplitLayouts(into: &next)
        }
    }

    /// The exclusive-membership normalization `changed()` applies, as a value
    /// function so a transaction can publish its already-normalized state once.
    static func reconciledSplitLayouts(in state: BrowserState, activeSpaceID: UUID) -> [BrowserSplitLayout] {
        // A tab belongs to one typed split: an ordinary tab per Space, and a
        // Favorite per Profile, since Favorites (topApps) are one profile-wide
        //
        //
        // overlapping layout caches, then the most recently stored one.
        var candidates = state.splitLayouts
        let visible = SidebarSplitItems.groups(in: state, spaceID: activeSpaceID)
        if let active = candidates.lastIndex(where: { group in group.tabIDs == state.selectedTabIDs
            && visible.contains { $0.id == group.id } }) {
            candidates.append(candidates.remove(at: active))
        }
        var layouts: [BrowserSplitLayout] = [], assigned: [UUID: Set<UUID>] = [:], favorites: [UUID: Set<UUID>] = [:]
        for var layout in candidates.reversed() {
            guard let space = state.spaces.first(where: { $0.id == layout.spaceID }),
                  layout.widthFactors.count == layout.tabIDs.count else { continue }
            let favoriteProfile = layout.tabIDs.first.flatMap { id in state.tabs.first { $0.id == id }?.profileID }
                .flatMap { id in SidebarSplitItems.isFavorite(layout, in: state, profileID: id) ? id : nil }
            let ownerProfile = favoriteProfile ?? space.profileID
            var seen = Set<UUID>()
            let positions = layout.tabIDs.indices.filter { index in
                let id = layout.tabIDs[index]
                guard seen.insert(id).inserted, let tab = state.tabs.first(where: { $0.id == id && $0.archivedAt == nil
                    && $0.profileID == ownerProfile && ($0.kind == .favorite || $0.spaceID == space.id) }) else { return false }
                return tab.kind == .favorite ? !(favorites[ownerProfile] ?? []).contains(id) : !(assigned[space.id] ?? []).contains(id)
            }
            let ids = positions.map { layout.tabIDs[$0] }
            let weights = positions.map { layout.widthFactors[$0] }
            guard let factors = BrowserSplitLayout.normalized(weights, count: ids.count) else { continue }
            layout.tabIDs = ids
            if layout.sidebarAnchorID.map({ ids.contains($0) }) != true { layout.sidebarAnchorID = ids.first }
            if weights.count != layout.widthFactors.count || abs(weights.reduce(0, +) - 1) > 1e-12 {
                layout.widthFactors = factors
            }
            // Legacy overlapping entries may carry the same identity after a
            // pane replacement. Only the winning container retains that ID.
            if layouts.contains(where: { $0.id == layout.id }) { layout.id = UUID() }
            for id in ids {
                if state.tabs.contains(where: { $0.id == id && $0.kind == .favorite }) {
                    favorites[ownerProfile, default: []].insert(id)
                } else { assigned[space.id, default: []].insert(id) }
            }
            layouts.append(layout)
        }
        layouts.reverse()
        return layouts
    }

    /// External URL creation and placement publish once, after durable save.
    /// Replacement leaves the displaced original tab/page and its content intact.
    func dropExternalURLIntoSplit(_ url: URL, tabID: UUID, spaceID: UUID, profileID: UUID,
                                  expectedSelection: [UUID], expectedLayout: BrowserSplitLayout?,
                                  target: SplitDropTarget, orientation: SplitOrientation,
                                  creation: TabCreationProvenance?, savedHomeID: UUID? = nil,
                                  documents: [UUID: SidebarDocumentReference] = [:]) throws -> Bool {
        let homeSource = ExternalSplitDrop.savedHomeSource(state: state, selection: expectedSelection,
            layout: expectedLayout, target: target)
        guard homeSource.map({ SidebarDocumentReference.validates([$0], references: documents) }) ?? documents.isEmpty,
              !isProfileRemovalPending(profileID),
              !retiringTabIDs.contains(tabID), savedHomeID.map({ !retiringTabIDs.contains($0) }) ?? true,
              expectedSelection.allSatisfy({ !retiringTabIDs.contains($0) }),
              let next = ExternalSplitDrop.proposal(url: url, tabID: tabID, state: state,
                  spaceID: spaceID, profileID: profileID, selection: expectedSelection,
                  layout: expectedLayout, target: target, orientation: orientation,
                  creation: creation, now: clock(), savedHomeID: savedHomeID) else { return false }
        try commitProfileSettings(next)
        return true
    }

    @discardableResult
    func dropTabIntoSplit(_ id: UUID, expectedSelection: [UUID], expectedLayout: BrowserSplitLayout?,
                          target: SplitDropTarget, orientation: SplitOrientation,
                          savedHomeIDs: [UUID: UUID] = [:], creation: TabCreationProvenance? = nil,
                          documents: [UUID: SidebarDocumentReference] = [:]) -> Bool {
        guard state.selectedTabIDs == expectedSelection, activeSplitLayout == expectedLayout,
              (expectedSelection + [id] + Array(savedHomeIDs.values)).allSatisfy({ !retiringTabIDs.contains($0) }),
              let homes = OriginalSplitDrop.savedHomes(source: id, state: state, selection: expectedSelection,
                  layout: expectedLayout, target: target, orientation: orientation, spaceID: activeSpaceID),
              SidebarDocumentReference.validates(homes, references: documents),
              let next = OriginalSplitDrop.proposal(source: id, state: state, selection: expectedSelection,
                  layout: expectedLayout, target: target, orientation: orientation, spaceID: activeSpaceID,
                  profileID: activeSpace.profileID, now: clock(), savedHomeIDs: savedHomeIDs, creation: creation) else { return false }
        do { try commitProfileSettings(next); return true }
        catch { return false }
    }

    func autoArchiveInterval(for profileID: UUID) -> AutoArchiveInterval? {
        state.profiles.first { $0.id == profileID }.flatMap { AutoArchiveInterval(rawValue: $0.autoArchiveHours) }
    }

    @discardableResult
    func setAutoArchiveInterval(_ interval: AutoArchiveInterval, for profileID: UUID) -> Bool {
        do { _ = try changeAutoArchiveInterval(interval, for: profileID); return true }
        catch { return false }
    }

    ///
    ///
    @discardableResult
    func changeAutoArchiveInterval(_ interval: AutoArchiveInterval, for profileID: UUID) throws -> AutoArchiveProfileChange? {
        guard !isProfileRemovalPending(profileID),
              let index = state.profiles.firstIndex(where: { $0.id == profileID }) else {
            throw ProfileSettingsError.unavailable
        }
        guard state.profiles[index].autoArchiveHours != interval.rawValue else { return nil }
        var next = state
        next.profiles[index].autoArchiveHours = interval.rawValue
        if Set(next.profiles.map(\.autoArchiveHours)).count == 1 {
            next.autoArchiveDefaultHours = interval.rawValue
        }
        // The original threshold change also disarms default-interval education.
        next.autoArchiveEducationEligible = false
        try commitProfileSettings(next)
        guard state.profiles.count > 1, Set(state.profiles.map(\.autoArchiveHours)).count > 1,
              !state.profiles.contains(where: { isProfileRemovalPending($0.id) }) else { return nil }
        return AutoArchiveProfileChange(profileID: profileID, profiles: state.profiles, interval: interval)
    }

    func applyAutoArchiveIntervalToAllProfiles(_ change: AutoArchiveProfileChange) throws {
        guard state.profiles == change.profiles,
              state.profiles.contains(where: { $0.id == change.profileID }),
              !state.profiles.contains(where: { isProfileRemovalPending($0.id) }) else {
            throw ProfileSettingsError.unavailable
        }
        var next = state
        for index in next.profiles.indices { next.profiles[index].autoArchiveHours = change.interval.rawValue }
        next.autoArchiveDefaultHours = change.interval.rawValue
        next.autoArchiveEducationEligible = false
        try commitProfileSettings(next)
    }

    func dismissAutoArchiveEducation() {
        autoArchiveEducationPending = false
    }

    /// AppKit owns the windows; it replaces their records as a whole, which
    /// publishes nothing and only schedules the debounced save. Private
    /// stores never persist, so they keep none.
    func updateWindowRecords(_ records: [BrowserWindowRecord]) {
        guard !isEphemeral, records != windowRecords else { return }
        windowRecords = records
        scheduleSave()
    }

    func updateSettings(_ mutation: (inout BrowserSettings) -> Void) {
        var updated = state.settings
        mutation(&updated)
        updated.sidebarWidth = min(500, max(164, updated.sidebarWidth))
        guard updated != state.settings else { return }
        state.settings = updated
        changed()
    }

    /// The Favorites empty state's Dismiss button and Hide item record the
    ///
    ///
    /// profile, and only once, is [I]: the reducer was not traced.
    func dismissFavoritesEmptyState(profileID: UUID) {
        guard state.profiles.contains(where: { $0.id == profileID }),
              !state.settings.favoritesEmptyStateDismissed(for: profileID) else { return }
        updateSettings { $0.topAppsEmptyStateDismissedForProfiles = ($0.topAppsEmptyStateDismissedForProfiles ?? []) + [profileID] }
    }

    ///
    ///
    ///
    func toggleSpaceHeaderOnSingleUnnamedSpaces() {
        updateSettings { $0.showSpaceHeaderOnSingleUnnamedSpaces = !($0.showSpaceHeaderOnSingleUnnamedSpaces ?? false) }
    }

    // The native timer stamps current contents only for visible windows.
    // Callers provide actual visibility; app/key-window focus is not the gate.
    // Activity-only stamps keep archive/session lastAccessed correct but do not
    // publish: lastAccessed is outside preservesChromeLayout / sidebar outline,
    // and RecentTabOrder ignores archive-safety refreshes for already-ranked items.
    func refreshVisibleTabs(_ ids: Set<UUID>) {
        let now = clock()
        var next = state, didChange = false
        for index in next.tabs.indices where ids.contains(next.tabs[index].id) && next.tabs[index].archivedAt == nil {
            if next.tabs[index].lastAccessed != now {
                next.tabs[index].lastAccessed = now
                didChange = true
            }
        }
        guard didChange else { return }
        activityOnlyState = next
        scheduleSave()
    }

    private func stampSelection() {
        var next = state
        if stampSelection(in: &next) { state = next }
    }

    @discardableResult
    private func stampSelection(in next: inout BrowserState) -> Bool {
        let now = clock(), ids = Set(next.selectedTabIDs)
        var touched = false
        for index in next.tabs.indices where ids.contains(next.tabs[index].id) && next.tabs[index].archivedAt == nil {
            next.tabs[index].lastAccessed = now
            next.tabs[index].isUnread = false
            touched = true
        }
        return touched
    }

    @discardableResult
    func archiveExpiredTabs(protectedTabIDs: Set<UUID> = []) -> [UUID] {
        // Pure-model callers have no live pages. Native callers use the
        // completion overload so the result follows real beforeunload consent.
        guard requestPageRetirement == nil else {
            archiveExpiredTabs(protectedTabIDs: protectedTabIDs, completion: { _ in })
            return []
        }
        return finishArchiving(Set(expiredArchiveItems(protectedTabIDs: protectedTabIDs).flatMap(\.tabIDs)))
    }

    func archiveExpiredTabs(protectedTabIDs: Set<UUID>,
                            currentProtection: (() -> Set<UUID>)? = nil,
                            completion: @escaping ([UUID]) -> Void) {
        let originalItems = expiredArchiveItems(protectedTabIDs: protectedTabIDs.union(currentProtection?() ?? []))
        let candidates = Set(originalItems.flatMap(\.tabIDs))
        guard !candidates.isEmpty else { completion([]); return }
        withRetiredPages(candidates, shouldCommit: { [weak self] in
            guard let self else { return false }
            // Revalidate the WHOLE set before native unload. Rechecking only
            // after destruction could leave a selected page saved but gone.
            let protected = protectedTabIDs.union(currentProtection?() ?? [])
            let current = self.expiredArchiveItems(protectedTabIDs: protected)
            return originalItems.allSatisfy { current.contains($0) }
        }, onRefusal: { completion([]) }) { [weak self] in
            guard let self else { completion([]); return }
            completion(self.finishArchiving(candidates))
        }
    }

    /// The archive candidate is an original sidebar item, not an independently
    /// eligible child of a split. Keep the placement/document identity through
    /// beforeunload without treating an unrelated title/favicon update as a move.
    private struct AutomaticArchiveItem: Equatable {
        struct Member: Equatable {
            let id: UUID, profileID: UUID, spaceID: UUID
            let kind: TabKind
            let folderID: UUID?
            let createdAt: Date
            let url: String, savedURL: String
            init(_ tab: BrowserTab) {
                id = tab.id; profileID = tab.profileID; spaceID = tab.spaceID
                kind = tab.kind; folderID = tab.folderID; createdAt = tab.createdAt
                url = tab.url; savedURL = tab.savedURL
            }
        }
        let reference: SidebarItemReference
        let members: [Member]
        let split: BrowserSplitLayout?
        var tabIDs: [UUID] { members.map(\.id) }
    }

    private func expiredArchiveItems(protectedTabIDs: Set<UUID>) -> [AutomaticArchiveItem] {
        let now = clock()
        guard let startedAt = state.autoArchiveStartedAt else {
            //
            // and preserves it across launch/wake and subsequent sweeps.
            state.autoArchiveStartedAt = now
            changed()
            return []
        }
        // Current contents are excluded regardless of window occlusion. The
        // application contributes every physical window's own presentation.
        let excluded = protectedTabIDs.union(state.selectedTabIDs)
        var candidates: [AutomaticArchiveItem] = []
        for space in state.spaces {
            guard !isProfileRemovalPending(space.profileID),
                  let threshold = autoArchiveInterval(for: space.profileID)?.seconds,
                  now.timeIntervalSince(startedAt) > threshold else { continue }
            let location = SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .today)
            for item in SidebarHierarchy.children(in: location, state: state) {
                let ids = SidebarHierarchy.tabIDs(in: item, state: state, spaceID: space.id)
                let tabs = ids.compactMap { id in state.tabs.first { $0.id == id } }
                guard !ids.isEmpty, tabs.count == ids.count, tabs.allSatisfy({ tab in
                    tab.kind == .today && tab.folderID == nil && tab.archivedAt == nil
                        && tab.profileID == space.profileID && tab.spaceID == space.id
                        && !tab.isUnread && !excluded.contains(tab.id)
                        && now.timeIntervalSince(tab.lastAccessed) > threshold
                        //
                        // Malformed local-document addresses have no such owner.
                        && (!InternalPage.isInternal(tab.url) || InternalPage(urlString: tab.url) != nil)
                }) else { continue }
                let split: BrowserSplitLayout?
                switch item {
                case .tab:
                    // Do not detach a child from an unavailable/mixed group.
                    guard !state.splitLayouts.contains(where: { $0.tabIDs.contains(where: ids.contains) }) else { continue }
                    split = nil
                case .split(let id):
                    guard let group = state.splitLayouts.first(where: { $0.id == id }),
                          group.tabIDs == ids,
                          state.splitLayouts.filter({ $0.tabIDs.contains(where: ids.contains) }).count == 1 else { continue }
                    split = group
                case .folder: continue
                }
                candidates.append(.init(reference: item, members: tabs.map(AutomaticArchiveItem.Member.init), split: split))
            }
        }
        return candidates
    }

    private func finishArchiving(_ candidates: Set<UUID>) -> [UUID] {
        guard !candidates.isEmpty else { return [] }
        let now = clock()
        let archived = state.tabs.filter { candidates.contains($0.id) }.map(\.id)
        let provenance = archiveProvenance(for: candidates, reason: .automatic)
        var next = state
        // SharedAppFeature's real autoArchiveItems route enqueues one shared
        // education banner and clears eligibility before presentation. Private
        // stores never participate in application education or persistence.
        if !isEphemeral && next.autoArchiveEducationEligible {
            next.autoArchiveEducationEligible = false
            autoArchiveEducationPending = true
        }
        for index in next.tabs.indices where candidates.contains(next.tabs[index].id) {
            next.tabs[index].archiveProvenance = provenance[next.tabs[index].id]
            next.tabs[index].archivedAt = now
        }
        for key in next.selectionBySpace.keys {
            next.selectionBySpace[key]?.removeAll { candidates.contains($0) }
        }
        state = next
        changed()
        return archived
    }

    // Called only after the original Profile manager reports real history
    // readiness. Unknown-profile legacy records are not assigned elsewhere.
    func reconcileDownloads(profileID: UUID, nativeIDs: Set<String>) {
        guard state.profiles.contains(where: { $0.id == profileID }) else { return }
        let retained = state.downloads.filter { item in
            guard item.profileID == profileID, let nativeID = item.nativeID else { return true }
            return nativeIDs.contains(nativeID)
        }
        guard retained != state.downloads else { return }
        state.downloads = retained; changed()
    }

    /// Only the application-owned original context registry calls this path.
    /// The native context token separates even equal GUIDs across OTR lifetimes.
    func recordTransientDownload(_ values: [String: Any], contextID: String) {
        guard !isEphemeral, !contextID.isEmpty, values["offTheRecord"] as? Bool == true,
              let path = values["profilePath"] as? String,
              let profile = profileID(forEnginePath: path), !isProfileRemovalPending(profile),
              let rawID = values["id"] else { return }
        let nativeID = String(describing: rawID)
        guard !nativeID.isEmpty else { return }
        let id = "private:" + contextID + ":" + profile.uuidString + ":" + nativeID
        if values["removed"] as? Bool == true {
            transientDownloads.removeAll { $0.id == id }; return
        }
        var value = BrowserDownload.snapshot(values, id: id, nativeID: nativeID, profileID: profile)
        value.privateContextID = contextID
        if let index = transientDownloads.firstIndex(where: { $0.id == id }) { transientDownloads[index] = value }
        else { transientDownloads.append(value) }
    }
    func reconcileTransientDownloads(contextID: String, nativeIDs: Set<String>) {
        transientDownloads.removeAll {
            $0.privateContextID == contextID && !($0.nativeID.map(nativeIDs.contains) ?? false)
        }
    }
    func retireTransientDownloads(contextID: String) {
        transientDownloads.removeAll { $0.privateContextID == contextID }
    }

    // Private manager publications can only enter this original window's
    // memory-only store. They never enter a persisted regular catalog.
    func recordPrivateDownload(_ values: [String: Any]) {
        guard isEphemeral, values["offTheRecord"] as? Bool == true,
              let path = values["profilePath"] as? String,
              path == privateEnginePath else { return }
        recordDownload(values)
    }
    func clearPrivateDownloads() {
        guard isEphemeral, !state.downloads.isEmpty else { return }
        state.downloads.removeAll(); changed()
    }
    func recordDownload(_ values: [String: Any]) {
        guard isEphemeral || values["offTheRecord"] as? Bool != true else { return }
        guard let rawID = values["id"] else { return }
        let nativeID = String(describing: rawID)
        let profileID: UUID?
        if let path = values["profilePath"] as? String {
            guard let id = self.profileID(forEnginePath: path) else { return }
            profileID = id
        } else { profileID = nil } // Preserve legacy records without controls.
        let id = profileID.map { $0.uuidString + ":" + nativeID } ?? nativeID
        if values["removed"] as? Bool == true {
            state.downloads.removeAll { $0.id == id }; changed(); return
        }
        let value = BrowserDownload.snapshot(values, id: id, nativeID: nativeID, profileID: profileID)
        if let index = state.downloads.firstIndex(where: { $0.id == id }) { state.downloads[index] = value }
        else { state.downloads.append(value) }
        changed()
    }

    /// Commit setup and its completion marker in the same atomic session write.
    /// No page is created here. Failed persistence restores the original model.
    func completeOnboarding(_ draft: OnboardingDraft) throws {
        guard !state.settings.onboardingComplete else { return }
        try commitOnboardingSetup(draft, replay: false)
    }

    /// Settings → General → Replay onboarding: the same Space name, theme,
    /// Favorites and bookmark-file writes as first launch, added to the
    /// existing session. Existing tabs, Spaces and settings stay; the active
    /// Space, completion marker and first-setup education gate are unchanged.
    func applyOnboardingReplay(_ draft: OnboardingDraft) throws {
        try commitOnboardingSetup(draft, replay: true)
    }

    private func commitOnboardingSetup(_ draft: OnboardingDraft, replay: Bool) throws {
        guard let index = state.spaces.firstIndex(where: { $0.id == draft.spaceID }),
              draft.theme.isValid else {
            throw NSError(domain: "Parc.Onboarding", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The selected Space or theme is no longer available."])
        }
        let previous = state, previousPreviews = themePreviews
        pendingSave?.cancel(); pendingSave = nil
        pendingSaveSnapshot = nil
        let space = state.spaces[index]
        let saved = savedTheme(of: space)
        themePreviews[space.id] = nil
        let name = draft.spaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Replay applies only what it changed from where it started, so edits
        // made elsewhere meanwhile (and placeholder titles) survive.
        if !name.isEmpty, !replay || name != (draft.replayBaseName ?? space.name) {
            state.spaces[index].title = name; state.spaces[index].updateDisplayName(position: index)
        }
        state.spaces[index].theme = replay && draft.theme == (draft.replayBaseTheme ?? saved) ? saved : draft.theme
        if !replay { state.activeSpaceID = space.id }
        var favorites = Set(state.tabs.filter {
            $0.profileID == space.profileID && $0.kind == .favorite && $0.archivedAt == nil
        }.map { SavedTabURLComparison.key(OnboardingDraft.favoriteKey($0.savedURL)) })
        var pinned = Set(state.tabs.filter {
            $0.spaceID == space.id && $0.kind == .pinned && $0.archivedAt == nil
        }.map(\.savedURL))
        for item in draft.selectedFavorites where favorites.insert(SavedTabURLComparison.key(item.url)).inserted {
            state.tabs.append(BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID,
                url: item.url, title: item.title, kind: .favorite, createdAt: clock(), lastAccessed: clock(),
                savedURL: item.url, savedTitle: item.title))
        }
        for item in draft.bookmarks {
            guard let url = URL(string: item.url), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.host != nil, pinned.insert(url.absoluteString).inserted else { continue }
            let title = item.title.isEmpty ? url.host! : item.title
            state.tabs.append(BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID,
                url: url.absoluteString, title: title, kind: .pinned, createdAt: clock(), lastAccessed: clock(),
                savedURL: url.absoluteString, savedTitle: title))
        }
        if !replay {
            state.settings.onboardingComplete = true
            //
            // genuine first local setup is the equivalent one-time education gate.
            state.autoArchiveEducationEligible = true
        }
        do { try save() }
        catch { state = previous; themePreviews = previousPreviews; throw error }
        changed()
    }

    /// Imported native profile data has its own category transactions. This
    /// writes only selected sidebar bookmarks into the original local target.
    @discardableResult
    func commitImportedBookmarks(_ roots: [BrowserImportBookmark], destination: BrowserImportDestination) throws -> BrowserImportPlacement {
        try commitImportedBookmarks([(roots, destination, BrowserImportPlacement())])[0]
    }

    /// Every page in one write. A page's `placed` is what it added before;
    /// its new roots replace that (setup's Back to an accepted page).
    func commitImportedBookmarks(_ pages: [(roots: [BrowserImportBookmark], destination: BrowserImportDestination,
                                            placed: BrowserImportPlacement)]) throws -> [BrowserImportPlacement] {
        guard !isEphemeral, pages.allSatisfy({ $0.destination.isCurrent(in: state) }) else { throw CocoaError(.userCancelled) }
        var next = state, placements: [BrowserImportPlacement] = []
        for page in pages {
            let result = try page.destination.replacing(page.placed, with: page.roots, in: next, at: clock())
            next = result.state; placements.append(result.placement)
        }
        guard next != state else { return placements }
        let previous = state
        state = next
        do { try save() } catch { state = previous; throw error }
        changed()
        return placements
    }

    ///
    /// standard Profile maps to `standardProfileID`; a custom one to an unused
    /// live Profile with its name, else a new one. Each Profile in `profiles`
    /// gets a destination Space for its native data import. The active Space
    /// does not change. The `primary` Profile goes into `target`, as any
    /// browser's default profile does. The others map as above.
    func importArcSidebar(_ arc: ArcSidebarImport, profiles: [(key: ArcSidebarImport.ProfileKey, name: String)],
                          standardProfileID: UUID, primary: ArcSidebarImport.ProfileKey? = nil,
                          into target: UUID? = nil) throws
        -> [ArcSidebarImport.ProfileKey: BrowserImportDestination] {
        guard !isEphemeral else { throw CocoaError(.userCancelled) }
        let previous = state
        var chosen: (key: ArcSidebarImport.ProfileKey, profileID: UUID)?
        if let primary, let target { chosen = (primary, target) }
        let result = try arc.inserting(into: state, profiles: profiles, standardProfileID: standardProfileID,
                                       target: chosen, at: clock())
        state = result.state
        do { try save() } catch { state = previous; throw error }
        changed()
        return result.destinations
    }

    /// Create a distinct local destination before the native profile service is
    /// acquired. Does not change the active Space or any existing page owner.
    func createImportDestination(name: String, basedOn original: BrowserImportDestination) throws -> BrowserImportDestination {
        guard !isEphemeral else { throw CocoaError(.userCancelled) }
        let previous = state
        guard original.isCurrent(in: state),
              let originalSpace = state.spaces.first(where: { $0.id == original.spaceID }) else {
            throw CocoaError(.userCancelled)
        }
        let profile = BrowserProfile(id: UUID(), name: name.isEmpty ? "Imported Profile" : name,
                                     autoArchiveHours: state.autoArchiveDefaultHours)
        var space = originalSpace
        space.theme = savedTheme(of: originalSpace)
        space.id = UUID(); space.name = profile.name; space.title = profile.name; space.symbol = "circle.fill"; space.profileID = profile.id
        state.profiles.append(profile); state.spaces.append(space)
        do { try save() } catch { state = previous; throw error }
        changed()
        return BrowserImportDestination(spaceID: space.id, profileID: profile.id)
    }

    /// Resolve an existing Profile target. An unused existing Profile gets a
    /// sidebar Space without replacing its native context or identity.
    func prepareImportDestination(_ target: BrowserImportProfileTarget,
                                  basedOn original: BrowserImportDestination) throws -> BrowserImportDestination {
        guard !isEphemeral, original.isCurrent(in: state), target.isCurrent(in: state) else {
            throw CocoaError(.userCancelled)
        }
        if let spaceID = target.spaceID {
            return BrowserImportDestination(spaceID: spaceID, profileID: target.profileID)
        }
        guard let profile = state.profiles.first(where: { $0.id == target.profileID }),
              var space = state.spaces.first(where: { $0.id == original.spaceID }) else {
            throw CocoaError(.userCancelled)
        }
        let previous = state
        space.theme = savedTheme(of: space)
        space.id = UUID(); space.name = profile.name; space.title = profile.name; space.symbol = "circle.fill"
        space.profileID = profile.id
        state.spaces.append(space)
        do { try save() } catch { state = previous; throw error }
        changed()
        return BrowserImportDestination(spaceID: space.id, profileID: profile.id)
    }

    func importBookmarks(_ items: [(title: String, url: String)]) {
        var existing = Set(pinnedTabs.map(\.savedURL))
        for item in items {
            guard let url = URL(string: item.url), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.host != nil, existing.insert(url.absoluteString).inserted else { continue }
            let title = item.title.isEmpty ? (url.host ?? "Bookmark") : item.title
            state.tabs.append(BrowserTab(id: UUID(), spaceID: activeSpaceID, profileID: activeSpace.profileID,
                                         url: url.absoluteString, title: title, kind: .pinned,
                                         createdAt: clock(), lastAccessed: clock(), savedURL: url.absoluteString, savedTitle: title))
        }
        changed()
    }

    func clearHistory() { clearHistory(profileID: activeSpace.profileID) }
    func clearHistory(profileID: UUID) {
        state.history.removeAll { $0.profileID == profileID }
        tabHistory?.removeAll()
        historyRevision &+= 1
        changed()
    }
    func deleteHistory(_ ids: Set<UUID>, profileID: UUID) {
        state.history.removeAll { ids.contains($0.id) && $0.profileID == profileID }
        tabHistory?.removeAll()
        historyRevision &+= 1
        changed()
    }
    /// Chromium's history is the one history; the visits Parc keeps for the
    /// command bar's recents and site ranking drop what it deletes.
    func forgetHistory(_ deletion: ChromiumHistoryDeletion) {
        let profileID = deletion.profilePath.flatMap(profileID(forEnginePath:))
        guard deletion.profilePath == nil || profileID != nil else { return }
        let count = state.history.count
        state.history.removeAll { (profileID == nil || $0.profileID == profileID) && deletion.removes($0) }
        guard state.history.count != count else { return }
        historyRevision &+= 1
        changed()
    }

    func save() throws {
        pendingSave?.cancel(); pendingSave = nil
        pendingSaveSnapshot = nil
        guard !isEphemeral else { return }
        do {
            try persistSnapshot(persisted(state), wait: true)
            reportPersistence(nil)
        } catch {
            reportPersistence(error)
            throw error
        }
    }

    /// The session file's form of a state: the window records join it.
    private func persisted(_ state: BrowserState) -> BrowserState {
        var saved = state; saved.windows = windowRecords
        for (id, entry) in themePreviews {
            if let index = saved.spaces.firstIndex(where: { $0.id == id && $0.theme == entry.preview }) {
                saved.spaces[index].theme = entry.saved
            }
        }
        return saved
    }

    private func changed(selectionAlreadyStamped: Bool = false) {
        // Batch reconcile + selection cache into at most one published assign so
        // callers that already published their mutation do not multi-fire again.
        var next = state
        let selectedBeforeReconcile = next.selectedTabIDs
        reconcileSplitLayouts(into: &next)
        // Refresh the active-Space selection cache unless the caller already
        // stamped it and reconcile left selection alone (true no-op).
        if !selectionAlreadyStamped || next.selectedTabIDs != selectedBeforeReconcile {
            let key = next.activeSpaceID.uuidString
            if next.selectionBySpace[key] != next.selectedTabIDs {
                next.selectionBySpace[key] = next.selectedTabIDs
            }
        }
        if next != state { state = next }
        scheduleSave()
    }

    private func scheduleSave() {
        guard !isEphemeral else { return }
        let snapshot = persisted(state)
        // True no-op: a debounce already covers this exact persisted state.
        // Distinct revisions still cancel/reset the 0.25s timer so the latest
        // mutation is not dropped.
        if pendingSave != nil, pendingSaveSnapshot == snapshot { return }
        pendingSave?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSave = nil
            self.pendingSaveSnapshot = nil
            // Snapshot on main, then return immediately. Encode/write run on
            // the session queue; waiting here would hitch input and layout.
            try? self.persistSnapshot(self.persisted(self.state), wait: false)
        }
        pendingSave = task
        pendingSaveSnapshot = snapshot
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
    }

    /// `wait` is for explicit callers (quit, tests, onboarding, settings
    /// commits) that must observe the file before continuing. The 0.25s
    /// debounce uses `wait: false` so page-load metadata never encodes on
    /// the calling thread. JSON schema and `JSONEncoder` formatting are
    /// unchanged. Identical pretty/sorted bytes skip the atomic replace on
    /// every path; Equatable snapshot skip is only for the coalesced debounce
    /// so it can avoid encode entirely when state has not changed.
    private func persistSnapshot(_ snapshot: BrowserState, wait: Bool) throws {
        guard !isEphemeral else { return }
        let url = stateURL
        if wait {
            var caught: Error?
            sessionWriter.write(snapshot, to: url, wait: true, allowSkip: false) { caught = $0 }
            if let caught { throw caught }
            return
        }
        sessionWriter.write(snapshot, to: url, wait: false, allowSkip: true) { [weak self] error in
            DispatchQueue.main.async { self?.reportPersistence(error) }
        }
    }

    private func reportPersistence(_ error: Error?) {
        let message = error?.localizedDescription
        if persistenceError != message { persistenceError = message }
    }

    private func beginFreshSession() {
        let closedAt = clock()
        let provenance = archiveProvenance(for: Set(state.tabs.filter { $0.kind == .today && $0.archivedAt == nil }.map(\.id)), reason: .session)
        for index in state.tabs.indices where state.tabs[index].archivedAt == nil {
            if state.tabs[index].kind == .today {
                let id = state.tabs[index].id
                state.tabs[index].archiveProvenance = provenance[id]
                state.tabs[index].archivedAt = closedAt
                state.recentlyClosedIDs.removeAll { $0 == id }
                state.recentlyClosedIDs.append(id)
            } else {
                state.tabs[index].url = state.tabs[index].savedURL
                state.tabs[index].title = state.tabs[index].savedTitle
            }
        }
        // Saved destinations remain in the sidebar, without loading a web page.
        state.selectedTabIDs = []
        state.selectionBySpace = [:]
        state.splitLayouts = []
    }

    private func normalizeSelection(selectFallback: Bool = true) {
        var next = state
        normalizeSelection(in: &next, selectFallback: selectFallback)
        state = next
    }

    private func normalizeSelection(in next: inout BrowserState, selectFallback: Bool = true) {
        let spaceID = next.activeSpaceID
        let space = next.spaces.first { $0.id == spaceID } ?? next.spaces[0]
        let visible = next.tabs.filter {
            $0.archivedAt == nil && ($0.kind == .favorite ? $0.profileID == space.profileID : $0.spaceID == spaceID)
        }
        let available = Set(visible.map(\.id))
        var seen = Set<UUID>()
        next.selectedTabIDs = Array(next.selectedTabIDs.filter { available.contains($0) && seen.insert($0).inserted }.prefix(4))
        if selectFallback && next.selectedTabIDs.isEmpty { next.selectedTabIDs = Array(visible.suffix(1).map(\.id)) }
    }

    private func validateState() throws {
        if let id = state.settings.defaultProfileID, !state.profiles.contains(where: { $0.id == id }) {
            throw CocoaError(.fileReadCorruptFile)
        }
        var removalIDs = Set<UUID>(), removalProfiles = Set<UUID>()
        for record in state.profileRemovals {
            guard removalIDs.insert(record.id).inserted, removalProfiles.insert(record.profileID).inserted,
                  record.profileID != defaultProfileID,
                  state.profiles.contains(where: { $0.id == record.profileID }),
                  !state.spaces.contains(where: { $0.profileID == record.profileID }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }

        let profiles = Set(state.profiles.map(\.id)), spaces = Set(state.spaces.map(\.id)), tabs = Set(state.tabs.map(\.id))
        let folders = Set(state.folders.map(\.id))
        guard profiles.count == state.profiles.count, spaces.count == state.spaces.count,
              tabs.count == state.tabs.count, folders.count == state.folders.count,
              state.profiles.allSatisfy({ AutoArchiveInterval(rawValue: $0.autoArchiveHours) != nil }),
              AutoArchiveInterval(rawValue: state.autoArchiveDefaultHours) != nil,
              spaces.contains(state.activeSpaceID), state.spaces.allSatisfy({ profiles.contains($0.profileID) }),
              state.tabs.allSatisfy({ spaces.contains($0.spaceID) && profiles.contains($0.profileID) }),
              state.folders.allSatisfy({ spaces.contains($0.spaceID) }) else { throw CocoaError(.fileReadCorruptFile) }
        var splitKeys = Set<String>()
        for layout in state.splitLayouts {
            guard let space = state.spaces.first(where: { $0.id == layout.spaceID }),
                  Set(layout.tabIDs).count == layout.tabIDs.count,
                  BrowserSplitLayout.normalized(layout.widthFactors, count: layout.tabIDs.count) != nil,
                  abs(layout.widthFactors.reduce(0, +) - 1) < 1e-9,
                  splitKeys.insert(layout.spaceID.uuidString + layout.tabIDs.map(\.uuidString).joined()).inserted,
                  layout.tabIDs.allSatisfy({ id in state.tabs.contains { $0.id == id && $0.archivedAt == nil
                      && (($0.profileID == space.profileID && ($0.kind == .favorite || $0.spaceID == space.id))
                          || SidebarSplitItems.isFavorite(layout, in: state, profileID: $0.profileID)) } })
            else { throw CocoaError(.fileReadCorruptFile) }
        }
        for folder in state.folders {
            var seen: Set<UUID> = [folder.id]
            var parent = folder.parentID
            while let id = parent {
                guard seen.insert(id).inserted, let value = state.folders.first(where: { $0.id == id && $0.spaceID == folder.spaceID }) else { throw CocoaError(.fileReadCorruptFile) }
                parent = value.parentID
            }
        }
        for tab in state.tabs {
            if tab.archivedAt == nil, tab.kind != .favorite, state.spaces.first(where: { $0.id == tab.spaceID })?.profileID != tab.profileID { throw CocoaError(.fileReadCorruptFile) }
            if let id = tab.folderID, !state.folders.contains(where: { $0.id == id && $0.spaceID == tab.spaceID }) { throw CocoaError(.fileReadCorruptFile) }
        }
    }
}


enum ProfileSettingsError: LocalizedError {
    case invalidSidebarWidth
    case emptyName, unavailable, nameChanged
    var errorDescription: String? {
        switch self {
        case .invalidSidebarWidth: return "Choose a valid sidebar width."
        case .emptyName: return "Enter a name for this profile."
        case .unavailable: return "This profile is no longer available."
        case .nameChanged: return "This profile was renamed in another window. Cancel and reopen Rename to use its current name."
        }
    }
}


//
// SplitViewController delegate. This transaction never carries a URL.
enum SplitDropTarget: Equatable {
    case insert(Int)
    case replace(Int)
}

/// A public pasteboard URL is a new navigation value, never an original tab ID.
/// File/internal/custom-scheme activation is intentionally not part of this route.
enum ExternalSplitDrop {
    static func url(_ string: String) -> URL? {
        guard !string.isEmpty, string == string.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), url.host?.isEmpty == false,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    /// The original saved-item branch replaces the pinned/Favorite parent-list slot
    /// with a fresh saved-home copy; the original live ID enters the new split.
    /// Existing group children and single-pane replacement do not take that branch.
    static func savedHomeSource(state: BrowserState, selection: [UUID],
                                layout: BrowserSplitLayout?, target: SplitDropTarget) -> BrowserTab? {
        guard layout == nil, selection.count == 1, case .insert = target else { return nil }
        return state.tabs.first { $0.id == selection[0] && ($0.kind == .favorite || $0.kind == .pinned) }
    }

    static func proposal(url: URL, tabID: UUID, state: BrowserState,
                         spaceID: UUID, profileID: UUID, selection: [UUID],
                         layout: BrowserSplitLayout?, target: SplitDropTarget,
                         orientation: SplitOrientation, creation: TabCreationProvenance?,
                         now: Date, savedHomeID: UUID? = nil) -> BrowserState? {
        guard Self.url(url.absoluteString) == url, state.activeSpaceID == spaceID,
              state.profiles.contains(where: { $0.id == profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == profileID }),
              state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }),
              state.selectedTabIDs == selection, !state.tabs.contains(where: { $0.id == tabID }),
              !selection.isEmpty else { return nil }
        let originals = selection.compactMap { id in state.tabs.first { $0.id == id && $0.archivedAt == nil
            && $0.profileID == profileID && ($0.kind == .favorite || $0.spaceID == spaceID) } }
        guard originals.count == selection.count,
              originals.allSatisfy({ tab in tab.kind != .favorite || (tab.folderID == nil && state.spaces.contains {
                  $0.id == tab.spaceID && $0.profileID == profileID
              }) }) else { return nil }
        let actual = SidebarSplitItems.groups(in: state, spaceID: spaceID).first { $0.tabIDs == selection }
        guard actual == layout,
              layout.map({ group in state.spaces.contains { $0.id == group.spaceID && $0.profileID == profileID } }) ?? true,
              layout != nil || !state.splitLayouts.contains(where: { !$0.tabIDs.allSatisfy { !selection.contains($0) } }) else { return nil }
        guard let group = SplitDropTransaction.make(source: tabID, selection: selection,
                  layout: layout, target: target, orientation: orientation, spaceID: layout?.spaceID ?? spaceID) else { return nil }
        var next = state
        let receipt = creation?.validated(profileID: profileID, state: state)
        let title = url.host ?? "New Tab", address = url.absoluteString
        next.tabs.append(BrowserTab(id: tabID, spaceID: spaceID, profileID: profileID,
            url: address, title: title, kind: .today, createdAt: now, lastAccessed: now,
            savedURL: address, savedTitle: title, referrerID: receipt?.referrerID,
            activeTabBeforeCreationID: receipt?.activeTabBeforeCreationID))
        //
        //
        SidebarHierarchy.placingCreatedTab(tabID, insertion: .automatic, in: &next)
        var homeIDs: [UUID: UUID] = [:]
        if let original = savedHomeSource(state: state, selection: selection, layout: layout, target: target) {
            guard let savedHomeID, savedHomeID != tabID else { return nil }
            homeIDs[original.id] = savedHomeID
        }
        guard SplitMembership.savedHomeSources(joining: group.tabIDs, existing: layout, added: tabID, state: next)
                  .allSatisfy({ homeIDs[$0.id] != nil }),
              let admitted = SplitMembership.admitting(group, existing: layout, added: tabID, state: next,
                  spaceID: spaceID, homeIDs: homeIDs, now: now,
                  activeTabBeforeCreationID: receipt?.activeTabBeforeCreationID) else { return nil }
        next = admitted
        next.selectedTabIDs = group.tabIDs
        next.selectionBySpace[spaceID.uuidString] = group.tabIDs
        for index in next.tabs.indices where group.tabIDs.contains(next.tabs[index].id) {
            next.tabs[index].isUnread = false; next.tabs[index].lastAccessed = now
        }
        return next
    }

}


enum SplitDropTransaction {
    static func make(source: UUID, selection: [UUID], layout: BrowserSplitLayout?,
                     target: SplitDropTarget, orientation: SplitOrientation,
                     spaceID: UUID) -> BrowserSplitLayout? {
        //
        //
        guard !selection.isEmpty, selection.count <= 4, Set(selection).count == selection.count, !selection.contains(source),
              layout == nil || (layout?.spaceID == spaceID && layout?.tabIDs == selection),
              selection.count == 1 || layout != nil,
              layout == nil || BrowserSplitLayout.normalized(layout!.widthFactors, count: selection.count) != nil else { return nil }
        var ids = selection
        switch target {
        case .insert(let index):
            guard (0...ids.count).contains(index), ids.count < 4 else { return nil }
            ids.insert(source, at: index)
        case .replace(let index):
            guard ids.indices.contains(index) else { return nil }
            ids[index] = source
        }
        guard ids != selection || (ids.count > 1 && orientation != layout?.orientation) else { return nil }
        let previous = layout?.widthFactors ?? [1]
        let weights: [Double]
        if case .replace = target { weights = previous }
        else {
            weights = ids.map { id in selection.firstIndex(of: id).map { previous[$0] } ?? (1 / Double(selection.count)) }
        }
        let factors = ids.count == 1 ? [1] : BrowserSplitLayout.normalized(weights, count: ids.count)
        guard let factors else { return nil }
        let anchor = layout?.sidebarAnchorID ?? selection.first
        return BrowserSplitLayout(id: layout?.id ?? UUID(), sidebarAnchorID: anchor.flatMap { ids.contains($0) ? $0 : nil }, customTitle: layout?.customTitle, customIcon: layout?.customIcon,
            spaceID: spaceID, tabIDs: ids, orientation: orientation, widthFactors: factors)
    }
}

// Typed sidebar projection. The container is positioned at its original
// anchor; members retain their saved kind/folder for later separation.
enum SidebarSplitItems {
    static func isFavorite(_ group: BrowserSplitLayout, in state: BrowserState, profileID: UUID) -> Bool {
        group.tabIDs.count > 1 && group.tabIDs.allSatisfy { id in
            state.tabs.contains { $0.id == id && $0.archivedAt == nil && $0.profileID == profileID && $0.kind == .favorite && $0.folderID == nil }
        }
    }
    static func groups(in state: BrowserState, spaceID: UUID) -> [BrowserSplitLayout] {
        guard let space = state.spaces.first(where: { $0.id == spaceID }) else { return [] }
        return state.splitLayouts.filter { group in
            (group.spaceID == spaceID || isFavorite(group, in: state, profileID: space.profileID)) && group.tabIDs.count > 1 && group.tabIDs.allSatisfy { id in
                state.tabs.contains { $0.id == id && $0.archivedAt == nil && $0.profileID == space.profileID
                    && ($0.kind == .favorite || $0.spaceID == spaceID) }
            }
        }
    }
}

// Application commands leave the ephemeral model only through its explicit
// normal parent. A missing/retiring parent never falls back to another profile.
extension BrowserStore {
    struct ApplicationContext: Equatable {
        let profileID: UUID
        let spaceID: UUID?
    }

    func applicationContext(from source: BrowserStore, spaceID: UUID) -> ApplicationContext? {
        guard !isEphemeral, source === self || source.isEphemeral,
              let profileID = source.privateParentProfileID
                ?? source.state.spaces.first(where: { $0.id == spaceID })?.profileID,
              state.profiles.contains(where: { $0.id == profileID }),
              !isProfileRemovalPending(profileID) else { return nil }
        let destination = state.spaces.first { $0.id == spaceID && $0.profileID == profileID }
            ?? state.spaces.first { $0.id == state.activeSpaceID && $0.profileID == profileID }
            ?? state.spaces.first { $0.profileID == profileID }
        return ApplicationContext(profileID: profileID, spaceID: destination?.id)
    }
}

///
/// the Sidebar's saved label and explicit user override have their own lifetime.
enum SidebarTabTitle {
    /// Global Rename resolves the window's selected sidebar item. A split is
    /// an original container, not whichever child currently has page focus.
    static func currentRenameTab(state: BrowserState, spaceID: UUID, profileID: UUID,
                                 selectedTabIDs: [UUID]) -> BrowserTab? {
        guard selectedTabIDs.count == 1, let id = selectedTabIDs.first,
              state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }),
              !state.splitLayouts.contains(where: { $0.spaceID == spaceID && $0.tabIDs.contains(id) }),
              let tab = state.tabs.first(where: { $0.id == id && $0.spaceID == spaceID
                  && $0.profileID == profileID && $0.archivedAt == nil }),
              tab.kind != .favorite, !InternalPage.isInternal(tab.url) else { return nil }
        return tab
    }

    enum EditError: LocalizedError {
        case unavailable
        var errorDescription: String? { "This tab changed while its name was being edited. Please try again." }
    }

    /// A tab the sidebar can rename: not a Favorite (its own rename) and not a
    /// Parc document page.
    static func isRenameable(_ tab: BrowserTab) -> Bool {
        tab.kind != .favorite && !InternalPage.isInternal(tab.url)
    }

    static func customValue(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func display(_ tab: BrowserTab) -> String {
        if let custom = tab.customTitle { return custom }
        if let saved = customValue(tab.savedTitle), saved != "about:blank" { return saved }
        //
        // shortening rules are separate from the recovered title precedence.
        return tab.savedURL.isEmpty || tab.savedURL == "about:blank" ? "New tab" : tab.savedURL
    }

    static func sameItemForEditing(_ current: BrowserTab, _ original: BrowserTab) -> Bool {
        current.id == original.id && current.spaceID == original.spaceID &&
            current.profileID == original.profileID && current.kind == original.kind &&
            current.folderID == original.folderID && current.archivedAt == nil &&
            original.archivedAt == nil && current.customTitle == original.customTitle &&
            (current.kind == .today || current.savedURL == original.savedURL)
    }
}

/// The committed name inverse follows the original tab ID in its profile.
/// Later same-profile membership changes do not rename the page or replace it.
/// A different shared name, archived/deleted item or different profile refuses.
struct SidebarTabTitleChange: Equatable {
    let tabID: UUID
    let profileID: UUID
    let previousTitle: String?
    let title: String?
    var actionName: String { "Rename Item" }

    func target(in state: BrowserState, undo: Bool) -> BrowserTab? {
        guard previousTitle != title, state.profiles.contains(where: { $0.id == profileID }),
              let tab = state.tabs.first(where: { $0.id == tabID && $0.profileID == profileID }),
              tab.archivedAt == nil, tab.customTitle == (undo ? title : previousTitle) else { return nil }
        return tab
    }
}

/// Original container + child placements form a short-lived name-edit lease.
/// Navigation metadata may change; membership, placement and the saved name may not.
struct SidebarSplitTitleEdit: Equatable {
    let group: BrowserSplitLayout
    let profileID: UUID
    let children: [BrowserTab]

    init?(group: BrowserSplitLayout, profileID: UUID, state: BrowserState) {
        guard state.spaces.contains(where: { $0.id == group.spaceID && $0.profileID == profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == profileID }),
              SidebarSplitItems.groups(in: state, spaceID: group.spaceID).contains(group) else { return nil }
        let children = group.tabIDs.compactMap { id in state.tabs.first { $0.id == id } }
        guard children.count == group.tabIDs.count,
              ((children.allSatisfy({ $0.profileID == profileID && $0.spaceID == group.spaceID
                  && $0.kind != .favorite && $0.archivedAt == nil })) || SidebarSplitItems.isFavorite(group, in: state, profileID: profileID)) else { return nil }
        self.group = group; self.profileID = profileID; self.children = children
    }

    var isFavorite: Bool { children.allSatisfy { $0.kind == .favorite } }
    func isVisible(in spaceID: UUID, state: BrowserState) -> Bool {
        state.spaces.contains { $0.id == spaceID && $0.profileID == profileID } && (group.spaceID == spaceID || isFavorite)
    }

    func matches(_ state: BrowserState) -> Bool {
        guard state.spaces.contains(where: { $0.id == group.spaceID && $0.profileID == profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == profileID }),
              state.splitLayouts.contains(group) else { return false }
        return children.allSatisfy { original in
            state.tabs.contains { current in SidebarTabTitle.sameItemForEditing(current, original) }
        }
    }

    static func current(state: BrowserState, spaceID: UUID, profileID: UUID,
                        selectedTabIDs: [UUID]) -> Self? {
        guard selectedTabIDs.count > 1,
              let group = SidebarSplitItems.groups(in: state, spaceID: spaceID).first(where: { $0.tabIDs == selectedTabIDs }) else { return nil }
        return Self(group: group, profileID: profileID, state: state)
    }

    enum EditError: LocalizedError {
        case unavailable
        var errorDescription: String? { "This Split View changed while its name was being edited. Please try again." }
    }
}

/// A committed container-name change, shared by the originating window's Undo
/// and Redo. Layout/member changes are not name edits; same-profile moves retain
/// the original ID. A different shared name or deleted/replaced owner refuses.
struct SidebarSplitTitleChange: Equatable {
    let containerID: UUID
    let profileID: UUID
    let previousTitle: String?
    let title: String?
    var actionName: String { "Rename Item" }

    func target(in state: BrowserState, undo: Bool) -> BrowserSplitLayout? {
        guard previousTitle != title, state.profiles.contains(where: { $0.id == profileID }),
              let group = state.splitLayouts.first(where: { $0.id == containerID }),
              group.customTitle == (undo ? title : previousTitle),
              state.spaces.contains(where: { $0.id == group.spaceID && $0.profileID == profileID }),
              SidebarSplitTitleEdit(group: group, profileID: profileID, state: state) != nil else { return nil }
        return group
    }
}

/// Only fields owned by this operation participate in its inverse. In particular,
/// undoing an icon choice does not overwrite a later independent title edit.
struct SidebarSplitAppearanceChange: Equatable {
    let containerID: UUID
    let profileID: UUID
    let previousTitle: String?
    let title: String?
    let previousIcon: SidebarGroupIcon?
    let icon: SidebarGroupIcon?
    let resetsTitle: Bool
    ///
    ///
    var actionName: String { resetsTitle ? "Reset Name and Icon" : "Customize Tab" }
    func target(in state: BrowserState, undo: Bool) -> BrowserSplitLayout? {
        guard let group = state.splitLayouts.first(where: { $0.id == containerID }),
              group.customIcon == (undo ? icon : previousIcon),
              !resetsTitle || group.customTitle == (undo ? title : previousTitle),
              SidebarSplitTitleEdit(group: group, profileID: profileID, state: state) != nil else { return nil }
        return group
    }
}

///
///
/// `JSONEncoder.encode`; Parc previously encoded the whole `BrowserState` on
/// main after every `changed()`. Bytes stay ISO-8601, pretty-printed, sorted
/// keys; 0o600 and same-directory `rename(2)` remain. Work is FIFO on one
/// serial queue so a failed later write cannot drop an earlier in-flight
/// persist. When encoded bytes equal the last successful write, the atomic
/// replace is skipped (true identical-byte no-op); encode of that identical
/// snapshot may still run off the caller. `allowSkip` Equatable short-circuit
/// is only for the coalesced debounce so unchanged title/URL ticks avoid
/// encode entirely; explicit `save()` / profile-settings commits always encode
/// and only skip when the pretty/sorted bytes already match disk.
///
/// Visits are kept in `BrowserHistoryFile` beside the session and written only
/// when they change: title, selection and activity writes no longer re-encode
/// a history that holds up to `BrowserHistoryOrder.capacity` visits.
private final class SessionFileWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.parc.session-save", qos: .utility)
    private var lastWritten: BrowserState?
    /// Last successfully replaced pretty/sorted payload. Touched only on `queue`.
    private var lastWrittenBytes: Data?
    /// Visits last written to the history file, and the records it holds.
    /// Touched only on `queue`.
    private var lastWrittenHistory: [BrowserHistoryEntry]?
    private var historyRecords = 0
    private var historyPreserved = false

    /// Stops this session from writing the history file (see the store's load).
    func preserveHistoryFile() { queue.sync { historyPreserved = true } }

    func write(_ snapshot: BrowserState, to url: URL, wait: Bool, allowSkip: Bool,
               completion: @escaping (Error?) -> Void) {
        // Always `async` onto the save queue. `DispatchQueue.sync` may run the
        // block inline on the calling/MainActor thread; settings commits and
        // explicit `save()` need the pretty/sorted encode and atomic replace
        // off that stack even when the caller must still wait for durability.
        let work = {
            do {
                try self.encodeAndReplace(snapshot, to: url, allowSkip: allowSkip)
                completion(nil)
            } catch {
                completion(error)
            }
        }
        if wait {
            let group = DispatchGroup()
            group.enter()
            queue.async {
                work()
                group.leave()
            }
            group.wait()
        } else {
            queue.async(execute: work)
        }
    }

    private func encodeAndReplace(_ snapshot: BrowserState, to url: URL, allowSkip: Bool) throws {
        if allowSkip, lastWritten == snapshot { return }
        try persistHistory(snapshot.history,
                           at: url.deletingLastPathComponent().appendingPathComponent(BrowserHistoryFile.name))
        var session = snapshot
        session.history = []
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        // Skip only when the same pretty/sorted bytes are still on disk. A
        // missing session.json must recreate even if the in-memory payload
        // matches the last successful replace.
        if lastWrittenBytes == data, FileManager.default.fileExists(atPath: url.path) {
            lastWritten = snapshot
            return
        }
        do { try Self.replaceAtomically(data, at: url) } catch {
            // The history file may already hold this snapshot's visits; a
            // rolled-back model must not be skipped as already written.
            lastWritten = nil
            throw error
        }
        lastWrittenBytes = data
        lastWritten = snapshot
    }

    private func persistHistory(_ history: [BrowserHistoryEntry], at url: URL) throws {
        guard !historyPreserved else { return }
        let exists = FileManager.default.fileExists(atPath: url.path)
        guard exists || !history.isEmpty else { return }
        if exists, let previous = lastWrittenHistory {
            if previous == history { return }
            if let records = BrowserHistoryFile.appended(from: previous, to: history),
               historyRecords + records.count <= history.count + BrowserHistoryFile.compactionSlack {
                if !records.isEmpty {
                    do {
                        let handle = try FileHandle(forWritingTo: url)
                        defer { try? handle.close() }
                        try handle.seekToEnd()
                        try handle.write(contentsOf: try BrowserHistoryFile.encode(records))
                    } catch {
                        // A partial append ends in a torn line; the next write
                        // replaces the whole file instead of appending after it.
                        lastWrittenHistory = nil
                        throw error
                    }
                    historyRecords += records.count
                }
                lastWrittenHistory = history
                return
            }
        }
        try Self.replaceAtomically(try BrowserHistoryFile.encode(history), at: url, prefix: ".history-")
        historyRecords = history.count
        lastWrittenHistory = history
    }

    private static func replaceAtomically(_ data: Data, at url: URL, prefix: String = ".session-") throws {
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(prefix + UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: data,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard Darwin.rename(temporary.path, url.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}
