import Foundation
import Darwin
import Combine

package enum TabKind: String, Codable, CaseIterable { case favorite, pinned, today }

package enum AutoArchiveInterval: Double, CaseIterable {
    case never = 0, oneHour = 1, sixHours = 6, twelveHours = 12
    case twentyFourHours = 24, sevenDays = 168, thirtyDays = 720

    package static let settingsChoices: [Self] = [.twelveHours, .twentyFourHours, .sevenDays, .thirtyDays]
    package var seconds: TimeInterval? { self == .never ? nil : rawValue * 3600 }
    package var durationTitle: String { self == .twelveHours ? "12 hours" : title }
    package var title: String {
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

package struct BrowserProfile: Codable, Identifiable, Equatable {
    package var id: UUID
    package var name: String
    package var autoArchiveHours: Double = AutoArchiveInterval.twelveHours.rawValue

    package init(id: UUID, name: String, autoArchiveHours: Double = AutoArchiveInterval.twelveHours.rawValue) {
        self.id = id
        self.name = name
        self.autoArchiveHours = autoArchiveHours
    }
}

package struct AutoArchiveProfileChange: Equatable {
    package let profileID: UUID
    package let profiles: [BrowserProfile]
    package let interval: AutoArchiveInterval
    package var profileName: String { profiles.first { $0.id == profileID }?.name ?? "" }
}

package struct BrowserSpace: Codable, Identifiable, Equatable {
    package var id: UUID
    package var title: String?
    private var placeholderName = "Space"
    package var name: String {
        get { title ?? placeholderName }
        set { title = newValue.isEmpty ? nil : newValue }
    }
    private var migratesLegacyTitle = false
    package var symbol: String
    package var customIcon: SidebarGroupIcon? = nil
    package var theme: SpaceTheme
    package var profileID: UUID
    package var autoArchiveHours: Double?
    package var pinnedCollapsed = false

    package init(id: UUID, name: String, symbol: String, color: String, profileID: UUID) {
        self.id = id; self.title = name.isEmpty ? nil : name
        self.symbol = symbol; self.profileID = profileID
        theme = .singleColor(ThemeColor(hex: color) ?? ThemeColor(hex: "B9B5D4")!)
    }

    private enum CodingKeys: String, CodingKey { case id, name, title, symbol, customIcon, theme, color, profileID, autoArchiveHours, pinnedCollapsed }
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        let legacyName = try c.decode(String.self, forKey: .name)
        placeholderName = legacyName
        migratesLegacyTitle = !c.contains(.title)
        title = migratesLegacyTitle ? legacyName : try c.decodeIfPresent(String.self, forKey: .title)
        symbol = try c.decode(String.self, forKey: .symbol)
        customIcon = SidebarGroupIcon.decodeIfValid(c, forKey: .customIcon)
        profileID = try c.decode(UUID.self, forKey: .profileID)
        autoArchiveHours = (try? c.decodeIfPresent(Double.self, forKey: .autoArchiveHours))
            .flatMap { $0 }.flatMap { AutoArchiveInterval(rawValue: $0)?.rawValue }
        pinnedCollapsed = (try? c.decodeIfPresent(Bool.self, forKey: .pinnedCollapsed)) ?? false
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
    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(title, forKey: .title)
        try c.encode(symbol, forKey: .symbol); try c.encode(profileID, forKey: .profileID)
        try c.encode(theme, forKey: .theme)
        try c.encodeIfPresent(customIcon, forKey: .customIcon)
        try c.encodeIfPresent(autoArchiveHours, forKey: .autoArchiveHours)
        if pinnedCollapsed { try c.encode(true, forKey: .pinnedCollapsed) }
    }
    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.name == rhs.name
            && lhs.symbol == rhs.symbol && lhs.customIcon == rhs.customIcon
            && lhs.theme == rhs.theme && lhs.profileID == rhs.profileID
            && lhs.autoArchiveHours == rhs.autoArchiveHours && lhs.pinnedCollapsed == rhs.pinnedCollapsed
    }
    package mutating func updateDisplayName(position: Int) {
        let placeholder = "Space \(position + 1)"
        if migratesLegacyTitle {
            if name == placeholder || name.isEmpty { title = nil }
            migratesLegacyTitle = false
        }
        placeholderName = placeholder
    }
}

package enum ArchiveRestoreDestination {
    case putBack(currentSpaceID: UUID, requestedSpaceID: UUID?)
    case previousSpace(fallbackSpaceID: UUID?)
}

package enum ArchiveReason: String, Codable {
    case automatic, manual, clearButton, clearTabGroup, session
    package var isManual: Bool { self != .automatic }
}

package struct ArchiveProvenance: Codable, Equatable {
    package var reason: ArchiveReason
    package var spaceID: UUID
    package var spaceName: String
    package var groupID: UUID?
    package var split: BrowserSplitLayout?
    package var folderPath: ArchivedFolderPath?
}

extension ArchiveProvenance {
    private enum CodingKeys: String, CodingKey { case reason, spaceID, spaceName, groupID, split, folderPath }
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reason = try c.decode(ArchiveReason.self, forKey: .reason)
        spaceID = try c.decode(UUID.self, forKey: .spaceID)
        spaceName = try c.decode(String.self, forKey: .spaceName)
        groupID = try c.decodeIfPresent(UUID.self, forKey: .groupID)
        split = try c.decodeIfPresent(BrowserSplitLayout.self, forKey: .split)
        folderPath = ((try? c.decodeIfPresent(ArchivedFolderPath.self, forKey: .folderPath)) ?? nil).flatMap { $0.isValid ? $0 : nil }
    }
}

package struct ArchivedFolder: Codable, Equatable {
    package var id: UUID
    package var name: String
    package var isExpanded: Bool
    package var customIcon: SidebarGroupIcon?
    package var siblings: [SidebarItemReference]
}

extension ArchivedFolder {
    private enum CodingKeys: String, CodingKey { case id, name, isExpanded, customIcon, siblings }
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isExpanded = try c.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? true
        customIcon = SidebarGroupIcon.decodeIfValid(c, forKey: .customIcon)
        siblings = try c.decodeIfPresent([SidebarItemReference].self, forKey: .siblings) ?? []
    }
}

package struct ArchivedFolderPath: Codable, Equatable {
    package var parentID: UUID?
    package var folders: [ArchivedFolder]
    package var siblings: [SidebarItemReference]

    package var isValid: Bool {
        let ids = folders.map(\.id)
        return !ids.isEmpty && Set(ids).count == ids.count && parentID.map { !ids.contains($0) } ?? true
    }

    package func rebuilding(in state: inout BrowserState, spaceID: UUID) -> UUID? {
        func exists(_ id: UUID) -> Bool { state.folders.contains { $0.id == id && $0.spaceID == spaceID } }
        let reused = folders.lastIndex { exists($0.id) }
        var parent = reused.map { folders[$0].id } ?? parentID.flatMap { exists($0) ? $0 : nil }
        for folder in folders[(reused.map { $0 + 1 } ?? 0)...] {
            guard !state.folders.contains(where: { $0.id == folder.id }) else { break }
            state.folders.append(BrowserFolder(id: folder.id, spaceID: spaceID, name: folder.name, parentID: parent,
                                               isExpanded: folder.isExpanded, customIcon: folder.customIcon))
            SidebarHierarchy.placing(.folder(folder.id), in: .init(spaceID: spaceID, folderID: parent, section: .pinned),
                                     following: folder.siblings, state: &state)
            parent = folder.id
        }
        return parent
    }
}

extension BrowserTab {
    package var withoutFolderPlacement: BrowserTab {
        var entry = self
        entry.folderID = nil
        entry.archiveProvenance?.folderPath = nil
        return entry
    }
    package var archivedWithoutFolderPlacement: BrowserTab { archivedAt == nil ? self : withoutFolderPlacement }
}

package struct ArchivedFolderPathRecorder {
    package let state: BrowserState
    package let deleted: Set<UUID>
    private var chains: [UUID: ArchivedFolderPath?] = [:]
    private var orders: [String: [SidebarItemReference]] = [:]

    package init(state: BrowserState, deleted: Set<UUID>) {
        self.state = state; self.deleted = deleted
    }

    package mutating func path(for tab: BrowserTab) -> ArchivedFolderPath? {
        if let folderID = tab.folderID {
            guard deleted.contains(folderID), var path = chain(to: folderID),
                  let folder = state.folders.first(where: { $0.id == folderID }) else { return nil }
            path.siblings = order(in: .init(spaceID: folder.spaceID, folderID: folderID, section: .pinned))
            return path
        }
        guard let existing = tab.archiveProvenance?.folderPath, let anchor = existing.parentID,
              deleted.contains(anchor), let outer = chain(to: anchor) else { return nil }
        let path = ArchivedFolderPath(parentID: outer.parentID, folders: outer.folders + existing.folders, siblings: existing.siblings)
        return path.isValid ? path : nil
    }

    private mutating func chain(to folderID: UUID) -> ArchivedFolderPath? {
        if let known = chains[folderID] { return known }
        var folders: [ArchivedFolder] = [], current: UUID? = folderID, visited = Set<UUID>(), valid = true
        while let id = current, deleted.contains(id) {
            guard visited.insert(id).inserted, let folder = state.folders.first(where: { $0.id == id }) else { valid = false; break }
            let container = SidebarContainerLocation(spaceID: folder.spaceID, folderID: folder.parentID, section: .pinned)
            folders.insert(ArchivedFolder(id: id, name: folder.name, isExpanded: folder.isExpanded,
                                          customIcon: folder.customIcon, siblings: order(in: container)), at: 0)
            current = folder.parentID
        }
        let path = valid && !folders.isEmpty ? ArchivedFolderPath(parentID: current, folders: folders, siblings: []) : nil
        chains.updateValue(path, forKey: folderID)
        return path
    }

    private mutating func order(in location: SidebarContainerLocation) -> [SidebarItemReference] {
        if let known = orders[location.key] { return known }
        let items = SidebarHierarchy.children(in: location, state: state).map { SidebarHierarchy.storedReference($0, state: state) }
        orders[location.key] = items
        return items
    }
}

package struct BrowserArchivedItem: Identifiable {
    package var tabs: [BrowserTab]
    package var id: UUID { tabs[0].id }
    package var archivedAt: Date { tabs[0].archivedAt! }
    package var provenance: ArchiveProvenance? { tabs[0].archiveProvenance }
    package var title: String { tabs.map { $0.title.isEmpty ? $0.url : $0.title }.joined(separator: " · ") }
    package var urls: [String] { tabs.map(\.url) }
}

package struct ArchivePreviewLease: Equatable {
    package let token: UUID
    package let profileID: UUID
    package let tabs: [BrowserTab]

    package init(token: UUID, profileID: UUID, tabs: [BrowserTab]) {
        self.token = token
        self.profileID = profileID
        self.tabs = tabs
    }
}

package struct BrowserTab: Codable, Identifiable, Equatable {
    package var id: UUID
    package var spaceID: UUID
    package var profileID: UUID
    package var url: String
    package var title: String
    package var kind: TabKind
    package var folderID: UUID?
    package var createdAt: Date
    package var lastAccessed: Date
    package var archivedAt: Date?
    package var savedURL: String
    package var savedTitle: String
    package var customTitle: String? = nil
    package var isMuted: Bool = false
    package var isUnread: Bool = false
    package var archiveProvenance: ArchiveProvenance? = nil
    package var referrerID: UUID? = nil
    package var activeTabBeforeCreationID: UUID? = nil
    package var noteVisit: TabNoteVisit? = nil

    package init(id: UUID, spaceID: UUID, profileID: UUID, url: String, title: String, kind: TabKind, folderID: UUID? = nil, createdAt: Date, lastAccessed: Date, archivedAt: Date? = nil, savedURL: String, savedTitle: String, customTitle: String? = nil, isMuted: Bool = false, isUnread: Bool = false, archiveProvenance: ArchiveProvenance? = nil, referrerID: UUID? = nil, activeTabBeforeCreationID: UUID? = nil, noteVisit: TabNoteVisit? = nil) {
        self.id = id
        self.spaceID = spaceID
        self.profileID = profileID
        self.url = url
        self.title = title
        self.kind = kind
        self.folderID = folderID
        self.createdAt = createdAt
        self.lastAccessed = lastAccessed
        self.archivedAt = archivedAt
        self.savedURL = savedURL
        self.savedTitle = savedTitle
        self.customTitle = customTitle
        self.isMuted = isMuted
        self.isUnread = isUnread
        self.archiveProvenance = archiveProvenance
        self.referrerID = referrerID
        self.activeTabBeforeCreationID = activeTabBeforeCreationID
        self.noteVisit = noteVisit
    }
}

package enum SavedTabURLComparison {
    package static func isAway(current: URL?, saved: URL?) -> Bool {
        guard let current, let saved, current != saved else { return false }
        return normalized(current) != normalized(saved)
    }

    package static func key(_ string: String) -> String {
        URL(string: string).map { normalized($0).absoluteString } ?? string
    }

    private static func normalized(_ original: URL) -> URL {
        guard var parts = URLComponents(string: original.absoluteString.lowercased()) else { return original }
        let originalPath = parts.path
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
            if items.isEmpty || kept.count != items.count { parts.queryItems = kept.isEmpty ? nil : kept }
        }
        return parts.url ?? original
    }
}

extension BrowserTab {
    package var resetDestination: URL? {
        guard archivedAt == nil, kind != .today,
              !InternalPage.isInternal(url), !InternalPage.isInternal(savedURL),
              let destination = URL(string: savedURL), destination.scheme != nil,
              SavedTabURLComparison.isAway(current: URL(string: url), saved: destination) else { return nil }
        return destination
    }

    private enum CodingKeys: String, CodingKey {
        case id, spaceID, profileID, url, title, kind, folderID, createdAt, lastAccessed,
             archivedAt, savedURL, savedTitle, customTitle, isMuted, isUnread, archiveProvenance, referrerID, activeTabBeforeCreationID,
             noteVisit
    }
    package init(from decoder: Decoder) throws {
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
        isUnread = try values.decodeIfPresent(Bool.self, forKey: .isUnread) ?? false
        archiveProvenance = try values.decodeIfPresent(ArchiveProvenance.self, forKey: .archiveProvenance)
        referrerID = try values.decodeIfPresent(UUID.self, forKey: .referrerID)
        activeTabBeforeCreationID = try values.decodeIfPresent(UUID.self, forKey: .activeTabBeforeCreationID)
        noteVisit = try? values.decodeIfPresent(TabNoteVisit.self, forKey: .noteVisit)
    }
}

package struct TabCreationProvenance: Equatable {
    package let referrerID: UUID?
    package let activeTabBeforeCreationID: UUID?
    package init(referrerID: UUID?, activeTabID: UUID?, profileID: UUID, state: BrowserState) {
        func original(_ id: UUID?) -> UUID? {
            id.flatMap { value in state.containsTab(value, where: { $0.profileID == profileID && $0.archivedAt == nil }) ? value : nil }
        }
        self.referrerID = original(referrerID)
        activeTabBeforeCreationID = self.referrerID ?? original(activeTabID)
    }
    package init(routedFrom source: UUID?, openedLink: Bool, profileID: UUID, state: BrowserState) {
        self.init(referrerID: openedLink ? nil : source, activeTabID: source, profileID: profileID, state: state)
    }
    package func validated(profileID: UUID, state: BrowserState) -> Self {
        Self(referrerID: referrerID, activeTabID: activeTabBeforeCreationID, profileID: profileID, state: state)
    }
}

package enum TodayInsertion: Equatable {
    case automatic
    case top
}

package struct BrowserFolder: Codable, Identifiable, Equatable {
    package var id: UUID
    package var spaceID: UUID
    package var name: String
    package var parentID: UUID?
    package var isExpanded: Bool = true
    package var customIcon: SidebarGroupIcon? = nil

    package init(id: UUID, spaceID: UUID, name: String, parentID: UUID? = nil, isExpanded: Bool = true, customIcon: SidebarGroupIcon? = nil) {
        self.id = id
        self.spaceID = spaceID
        self.name = name
        self.parentID = parentID
        self.isExpanded = isExpanded
        self.customIcon = customIcon
    }
}

extension BrowserFolder {
    private enum CodingKeys: String, CodingKey { case id, spaceID, name, parentID, isExpanded, customIcon }
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        spaceID = try c.decode(UUID.self, forKey: .spaceID)
        name = try c.decode(String.self, forKey: .name)
        parentID = try c.decodeIfPresent(UUID.self, forKey: .parentID)
        isExpanded = try c.decode(Bool.self, forKey: .isExpanded)
        customIcon = SidebarGroupIcon.decodeIfValid(c, forKey: .customIcon)
    }
    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(spaceID, forKey: .spaceID)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(parentID, forKey: .parentID)
        try c.encode(isExpanded, forKey: .isExpanded)
        try c.encodeIfPresent(customIcon, forKey: .customIcon)
    }
}

package struct BrowserHistoryEntry: Codable, Identifiable, Equatable {
    package var id: UUID
    package var url: String
    package var title: String
    package var visitedAt: Date
    package var profileID: UUID

    package init(id: UUID, url: String, title: String, visitedAt: Date, profileID: UUID) {
        self.id = id
        self.url = url
        self.title = title
        self.visitedAt = visitedAt
        self.profileID = profileID
    }
}

package enum BrowserHistoryFile {
    package static let name = "history.jsonl"
    package static let compactionSlack = 5_000

    package static func encode(_ visits: some Sequence<BrowserHistoryEntry>) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = Data()
        for visit in visits {
            data.append(try encoder.encode(visit))
            data.append(UInt8(ascii: "\n"))
        }
        return data
    }

    package static func decode(_ data: Data) -> [BrowserHistoryEntry] {
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

    package static func appended(from previous: [BrowserHistoryEntry],
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

package enum BrowserHistoryOrder {
    package static let capacity = 20_000

    package static func isStrictlyChronological(_ history: [BrowserHistoryEntry]) -> Bool {
        guard history.count > 1 else { return true }
        var previous = history[0].visitedAt
        for index in 1..<history.count {
            let date = history[index].visitedAt
            if date <= previous { return false }
            previous = date
        }
        return true
    }

    package static func newestFirst(_ history: [BrowserHistoryEntry]) -> [BrowserHistoryEntry] {
        if isStrictlyChronological(history) { return Array(history.reversed()) }
        return history.sorted { $0.visitedAt > $1.visitedAt }
    }
}

package struct ChromiumHistoryDeletion {
    package var profilePath: String?
    package var all: Bool
    package var range: ClosedRange<Date>?
    package var rangeURLs: Set<String>?
    package var urls: Set<String>?
    package var hosts: Set<String>

    package init(userInfo: [AnyHashable: Any]) {
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

    package func removes(_ visit: BrowserHistoryEntry) -> Bool {
        if all { return true }
        if let range, range.contains(visit.visitedAt), rangeURLs?.contains(visit.url) ?? true { return true }
        if let urls { return urls.contains(visit.url) }
        return range == nil && URL(string: visit.url)?.host.map(hosts.contains) == true
    }
}

package enum BrowserDownloadStatus: String, Codable, CaseIterable {
    case pending, downloading, paused, completed, cancelled, failed

    package static func inferred(isComplete: Bool, isCancelled: Bool, isFailed: Bool = false,
                         isPaused: Bool = false, receivedBytes: Int64) -> Self {
        if isComplete { return .completed }
        if isCancelled { return .cancelled }
        if isFailed { return .failed }
        if isPaused { return .paused }
        return receivedBytes > 0 ? .downloading : .pending
    }
}

package struct BrowserDownload: Codable, Identifiable, Equatable {
    package var id: String
    package var name: String
    package var path: String
    package var receivedBytes: Int64
    package var totalBytes: Int64
    package var status: BrowserDownloadStatus
    package var profileID: UUID? = nil
    package var nativeID: String? = nil
    package var errorCode: Int? = nil
    package var requiresReview = false
    package var sourceURL: String?
    package var startedAt: Date?
    package var canPause = false
    package var canResume = false
    package var canCancel = false
    package var canReview = false
    package var canRetry = false
    package var nativeIdentity: String?
    package var privateContextID: String?
    package var canOpen = false
    package var canReveal = false
    package var canRemove = false
    package var canCopyFile = false
    package var canToggleOpen = false
    package var openWhenComplete = false
    package var fileMissing = false
    package var statusText = ""
    package var sourceDomain: String?
    package var mimeType: String?
    package var timeRemaining: TimeInterval?
    package var isComplete: Bool { status == .completed }
    package var isCancelled: Bool { status == .cancelled }

    package init(id: String, name: String, path: String, receivedBytes: Int64, totalBytes: Int64,
         status: BrowserDownloadStatus) {
        self.id = id
        self.name = name
        self.path = path
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
        self.status = status
    }

    package static func snapshot(_ values: [String: Any], id: String, nativeID: String,
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

    package init(from decoder: Decoder) throws {
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
        status = try values.decodeIfPresent(BrowserDownloadStatus.self, forKey: .status)
            ?? .inferred(isComplete: values.decodeIfPresent(Bool.self, forKey: .isComplete) ?? false,
                         isCancelled: values.decodeIfPresent(Bool.self, forKey: .isCancelled) ?? false,
                         receivedBytes: receivedBytes)
    }

    package func encode(to encoder: Encoder) throws {
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
        try values.encode(isComplete, forKey: .isComplete)
        try values.encode(isCancelled, forKey: .isCancelled)
    }
}

package struct BrowserSettings: Codable, Equatable {
    package var sidebarWidth: Double = 228
    package var searchEngine: String = "https://duckduckgo.com/?q="
    package var restoreSession: Bool = true
    package var onboardingComplete: Bool = false
    package var settingsPane: String?
    package var settingsProfileID: UUID?
    package var defaultProfileID: UUID?
    package var modalEnabled: Bool?
    package var disableShiftClickToOpenLinksInModal: Bool?
    package var automaticPeekEnabled: Bool {
        get { modalEnabled ?? true }
        set { modalEnabled = newValue }
    }
    package var shiftPeekEnabled: Bool {
        get { !(disableShiftClickToOpenLinksInModal ?? false) }
        set { disableShiftClickToOpenLinksInModal = !newValue }
    }
    package var topAppsEmptyStateDismissedForProfiles: [UUID]?
    package func favoritesEmptyStateDismissed(for profileID: UUID) -> Bool {
        topAppsEmptyStateDismissedForProfiles?.contains(profileID) == true
    }
    package var showSpaceHeaderOnSingleUnnamedSpaces: Bool?
    package var shouldBypassConfirmInterProfileMoveDialog: Bool?

    package init(sidebarWidth: Double = 228, searchEngine: String = "https://duckduckgo.com/?q=", restoreSession: Bool = true, onboardingComplete: Bool = false, settingsPane: String? = nil, settingsProfileID: UUID? = nil, defaultProfileID: UUID? = nil, modalEnabled: Bool? = nil, disableShiftClickToOpenLinksInModal: Bool? = nil, topAppsEmptyStateDismissedForProfiles: [UUID]? = nil, showSpaceHeaderOnSingleUnnamedSpaces: Bool? = nil, shouldBypassConfirmInterProfileMoveDialog: Bool? = nil) {
        self.sidebarWidth = sidebarWidth
        self.searchEngine = searchEngine
        self.restoreSession = restoreSession
        self.onboardingComplete = onboardingComplete
        self.settingsPane = settingsPane
        self.settingsProfileID = settingsProfileID
        self.defaultProfileID = defaultProfileID
        self.modalEnabled = modalEnabled
        self.disableShiftClickToOpenLinksInModal = disableShiftClickToOpenLinksInModal
        self.topAppsEmptyStateDismissedForProfiles = topAppsEmptyStateDismissedForProfiles
        self.showSpaceHeaderOnSingleUnnamedSpaces = showSpaceHeaderOnSingleUnnamedSpaces
        self.shouldBypassConfirmInterProfileMoveDialog = shouldBypassConfirmInterProfileMoveDialog
    }
}

package enum SplitOrientation: String, Codable, CaseIterable { case horizontal, vertical }

package enum SidebarIconType: String, Codable, CaseIterable {
    case star, bookmark, heart, flag, flash, triangle, medical, notifications, bulb, shapes
    case grid, apps, layers, server, albums, copy, folder, fileTrayFull, calendar, mail
    case checkbox, document, book, chatBubbleEllipses, people, terminal, construction, square, egg, ellipse
    case moon, sunny, planet, leaf, cloud, paw, bag, gift, bed, restaurant
    case barbell, airplane, musicalNote, colorPallete, video, bandage, code, baseball, cloudOutline, map
    case bonfire, pizza, skull, receipt, thumbsUp, train, rss, github, linear, figma
    case search

    package static let tabAndSpacePicker = Array(allCases.prefix(56))
    package static let folderPicker: [SidebarIconType] = [.star, .bookmark, .heart, .flash, .triangle, .medical,
        .notifications, .bulb, .chatBubbleEllipses, .people, .construction, .egg, .ellipse, .moon, .planet,
        .leaf, .cloud, .paw, .restaurant, .airplane, .musicalNote, .video, .code, .skull]
}

package enum SidebarGroupIcon: Codable, Equatable {
    case emoji(String)
    case icon(SidebarIconType)
    case symbol(String)

    package var isValid: Bool {
        switch self {
        case .emoji(let value): return value.count == 1 && value.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F || $0.value > 0x1F000 }
        case .icon: return true
        case .symbol(let value): return Self.storedSymbols.contains(value)
        }
    }
    package static let storedSymbols: Set<String> = ["square.grid.2x2", "star", "heart", "bookmark", "briefcase", "house",
        "globe", "book", "music.note", "camera", "gamecontroller", "paintbrush", "leaf", "sun.max", "moon", "bolt",
        "flame", "flag", "gift", "graduationcap", "lightbulb", "paperplane", "puzzlepiece", "sparkles"]

    package static func decodeIfValid<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, forKey key: Key) -> SidebarGroupIcon? {
        guard let icon = try? container.decodeIfPresent(SidebarGroupIcon.self, forKey: key), icon.isValid else { return nil }
        return icon
    }
}

package struct BrowserSplitLayout: Codable, Equatable, Identifiable {
    package static func focusSuccessor(_ remaining: [UUID], removedAt index: Int?) -> UUID? {
        guard !remaining.isEmpty else { return nil }
        return remaining[min(max(index ?? 0, 0), remaining.count - 1)]
    }
    package var id: UUID = UUID()
    package var sidebarAnchorID: UUID? = nil
    package var customTitle: String? = nil
    package var customIcon: SidebarGroupIcon? = nil
    package var spaceID: UUID
    package var tabIDs: [UUID]
    package var orientation: SplitOrientation = .horizontal
    package var widthFactors: [Double]
    package var stacks: BrowserSplitStacks?

    private enum CodingKeys: String, CodingKey {
        case id, sidebarAnchorID, customTitle, customIcon, spaceID, tabIDs, orientation, widthFactors, stacks
    }
    package init(sidebarAnchorID: UUID? = nil, customTitle: String? = nil, customIcon: SidebarGroupIcon? = nil, spaceID: UUID,
         tabIDs: [UUID], orientation: SplitOrientation = .horizontal, widthFactors: [Double]) {
        self.init(id: UUID(), sidebarAnchorID: sidebarAnchorID, customTitle: customTitle, customIcon: customIcon,
                  spaceID: spaceID, tabIDs: tabIDs, orientation: orientation, widthFactors: widthFactors, stacks: nil)
    }
    package init(id: UUID, sidebarAnchorID: UUID? = nil, customTitle: String? = nil, customIcon: SidebarGroupIcon? = nil, spaceID: UUID,
         tabIDs: [UUID], orientation: SplitOrientation = .horizontal, widthFactors: [Double], stacks: BrowserSplitStacks?) {
        self.id = id; self.sidebarAnchorID = sidebarAnchorID ?? tabIDs.first
        self.customTitle = customTitle; self.customIcon = customIcon
        self.spaceID = spaceID; self.tabIDs = tabIDs
        self.orientation = orientation; self.widthFactors = widthFactors
        self.stacks = stacks
    }
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        spaceID = try c.decode(UUID.self, forKey: .spaceID)
        tabIDs = try c.decode([UUID].self, forKey: .tabIDs)
        sidebarAnchorID = try c.decodeIfPresent(UUID.self, forKey: .sidebarAnchorID) ?? tabIDs.first
        customTitle = try c.decodeIfPresent(String.self, forKey: .customTitle)
        customIcon = SidebarGroupIcon.decodeIfValid(c, forKey: .customIcon)
        orientation = try c.decodeIfPresent(SplitOrientation.self, forKey: .orientation) ?? .horizontal
        widthFactors = try c.decode([Double].self, forKey: .widthFactors)
        stacks = ((try? c.decodeIfPresent(BrowserSplitStacks.self, forKey: .stacks)) ?? nil)?.validated(paneCount: tabIDs.count)
        if let stacks { widthFactors = stacks.flattenedFactors }
    }

    package static func normalized(_ factors: [Double], count: Int) -> [Double]? {
        guard (2...4).contains(count), factors.count == count,
              factors.allSatisfy({ $0.isFinite && $0 > 0 }), let largest = factors.max() else { return nil }
        let scaled = factors.map { $0 / largest }
        let sum = scaled.reduce(0, +)
        let result = scaled.map { $0 / sum }
        guard result.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        return result
    }

    package func expandedFactors(focusing id: UUID) -> [Double]? {
        guard tabIDs.contains(id) else { return nil }
        return Self.normalized(tabIDs.map { $0 == id ? 1 : 1e-9 }, count: tabIDs.count)
    }
}

package struct BrowserSplitStacks: Codable, Equatable {
    package var slotSizes: [Int]
    package var slotFactors: [Double]
    package var stackFactors: [[Double]]

    package init(slotSizes: [Int], slotFactors: [Double], stackFactors: [[Double]]) {
        self.slotSizes = slotSizes
        self.slotFactors = slotFactors
        self.stackFactors = stackFactors
    }

    package var flattenedFactors: [Double] {
        zip(slotFactors, stackFactors).flatMap { slot, stack in stack.map { slot * $0 } }
    }

    package func validated(paneCount: Int) -> BrowserSplitStacks? {
        guard (2...3).contains(slotSizes.count), slotFactors.count == slotSizes.count,
              stackFactors.count == slotSizes.count, slotSizes.allSatisfy({ (1...3).contains($0) }),
              slotSizes.contains(where: { $0 > 1 }), slotSizes.reduce(0, +) == paneCount, paneCount <= 4,
              zip(slotSizes, stackFactors).allSatisfy({ $0 == $1.count }),
              let slots = BrowserSplitLayout.settled(slotFactors) else { return nil }
        var stacks: [[Double]] = []
        for factors in stackFactors {
            guard let settled = BrowserSplitLayout.settled(factors) else { return nil }
            stacks.append(settled)
        }
        let result = BrowserSplitStacks(slotSizes: slotSizes, slotFactors: slots, stackFactors: stacks)
        let row = result.flattenedFactors
        guard BrowserSplitLayout.normalized(row, count: paneCount) != nil, abs(row.reduce(0, +) - 1) < 1e-9 else { return nil }
        return result
    }
}

package struct BrowserSplitSlot: Equatable {
    package var tabIDs: [UUID]
    package var factor: Double
    package var stackFactors: [Double]
}

extension BrowserSplitLayout {
    package static func settled(_ factors: [Double]) -> [Double]? {
        guard !factors.isEmpty, factors.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        if factors.count == 1 { return [1] }
        if abs(factors.reduce(0, +) - 1) <= 1e-12 { return factors }
        return normalized(factors, count: factors.count)
    }

    private static func settledOrEqual(_ factors: [Double]) -> [Double] {
        settled(factors) ?? Array(repeating: 1 / Double(max(factors.count, 1)), count: factors.count)
    }

    package static func shape(orientation: SplitOrientation, sizes: [Int], factors: [Double], stackFactors: [[Double]])
        -> (orientation: SplitOrientation, widthFactors: [Double], stacks: BrowserSplitStacks?) {
        if sizes.count == 1, sizes[0] > 1, let stack = stackFactors.first {
            return (orientation == .horizontal ? .vertical : .horizontal, settledOrEqual(stack), nil)
        }
        let main = settledOrEqual(factors)
        guard sizes.contains(where: { $0 > 1 }) else { return (orientation, main, nil) }
        let stacks = BrowserSplitStacks(slotSizes: sizes, slotFactors: main,
            stackFactors: zip(sizes, stackFactors).map { size, stack in size == 1 ? [1] : settledOrEqual(stack) })
        return (orientation, stacks.flattenedFactors, stacks)
    }

    package var slots: [BrowserSplitSlot] {
        guard let stacks = stacks?.validated(paneCount: tabIDs.count) else {
            return tabIDs.indices.map { index in
                BrowserSplitSlot(tabIDs: [tabIDs[index]],
                    factor: widthFactors.indices.contains(index) ? widthFactors[index] : 1 / Double(tabIDs.count),
                    stackFactors: [1])
            }
        }
        var result: [BrowserSplitSlot] = [], start = 0
        for (slot, size) in stacks.slotSizes.enumerated() {
            result.append(BrowserSplitSlot(tabIDs: Array(tabIDs[start..<start + size]),
                                           factor: stacks.slotFactors[slot], stackFactors: stacks.stackFactors[slot]))
            start += size
        }
        return result
    }

    package var slotBoundaries: [Int] {
        slots.reduce(into: [0]) { boundaries, slot in boundaries.append(boundaries[boundaries.count - 1] + slot.tabIDs.count) }
    }

    package func position(of id: UUID) -> (slot: Int, index: Int)? {
        for (slot, item) in slots.enumerated() {
            if let index = item.tabIDs.firstIndex(of: id) { return (slot, index) }
        }
        return nil
    }

    package func slotRange(_ slot: Int) -> Range<Int>? {
        let boundaries = slotBoundaries
        guard slot >= 0, slot < boundaries.count - 1 else { return nil }
        return boundaries[slot]..<boundaries[slot + 1]
    }

    package func paneID(slot: Int, index: Int) -> UUID? {
        let all = slots
        guard all.indices.contains(slot), all[slot].tabIDs.indices.contains(index) else { return nil }
        return all[slot].tabIDs[index]
    }

    package func mainRowInsertionIndex(after id: UUID) -> Int? {
        position(of: id).flatMap { slotRange($0.slot)?.upperBound }
    }

    package mutating func arrange(_ slots: [BrowserSplitSlot]) {
        let kept = slots.filter { !$0.tabIDs.isEmpty }
        let shaped = Self.shape(orientation: orientation, sizes: kept.map(\.tabIDs.count),
                                factors: kept.map(\.factor), stackFactors: kept.map(\.stackFactors))
        tabIDs = kept.flatMap(\.tabIDs)
        orientation = shaped.orientation
        widthFactors = shaped.widthFactors
        stacks = shaped.stacks
    }

    package mutating func restack(from previous: BrowserSplitLayout) {
        let old = previous.slots
        guard previous.stacks != nil, !old.isEmpty else { return }
        var home: [UUID: (slot: Int, share: Double)] = [:]
        for (slot, item) in old.enumerated() {
            for (index, id) in item.tabIDs.enumerated() { home[id] = (slot, item.stackFactors[index]) }
        }
        var runs: [(source: Int?, slot: BrowserSplitSlot)] = []
        for id in tabIDs {
            guard let place = home[id] else {
                runs.append((nil, BrowserSplitSlot(tabIDs: [id], factor: 1 / Double(old.count), stackFactors: [1])))
                continue
            }
            if let last = runs.last, last.source == place.slot {
                runs[runs.count - 1].slot.tabIDs.append(id)
                runs[runs.count - 1].slot.stackFactors.append(place.share)
            } else {
                runs.append((place.slot, BrowserSplitSlot(tabIDs: [id], factor: 0, stackFactors: [place.share])))
            }
        }
        var covered: [Int: Double] = [:]
        for run in runs { if let source = run.source { covered[source, default: 0] += run.slot.stackFactors.reduce(0, +) } }
        for index in runs.indices {
            guard let source = runs[index].source, let total = covered[source], total > 0 else { continue }
            runs[index].slot.factor = old[source].factor * runs[index].slot.stackFactors.reduce(0, +) / total
        }
        arrange(runs.map(\.slot))
    }

    package mutating func removePane(at position: Int) {
        guard stacks != nil else {
            tabIDs.remove(at: position); widthFactors.remove(at: position)
            return
        }
        let previous = self
        tabIDs.remove(at: position)
        restack(from: previous)
    }

    package func insertingIntoStack(_ id: UUID, besidePaneAt position: Int, after: Bool) -> BrowserSplitLayout? {
        guard (2...3).contains(tabIDs.count), tabIDs.indices.contains(position), !tabIDs.contains(id),
              let place = self.position(of: tabIDs[position]) else { return nil }
        var slots = self.slots
        let at = place.index + (after ? 1 : 0)
        slots[place.slot].stackFactors.insert(1 / Double(slots[place.slot].tabIDs.count), at: at)
        slots[place.slot].tabIDs.insert(id, at: at)
        var result = self
        result.arrange(slots)
        return result
    }

    package func movingSlot(of id: UUID, by offset: Int) -> BrowserSplitLayout? {
        var slots = self.slots
        guard offset == -1 || offset == 1, let place = position(of: id),
              slots.indices.contains(place.slot + offset) else { return nil }
        slots.swapAt(place.slot, place.slot + offset)
        var result = self
        result.arrange(slots)
        return result
    }

    package func movingWithinStack(_ id: UUID, by offset: Int) -> BrowserSplitLayout? {
        var slots = self.slots
        guard offset == -1 || offset == 1, let place = position(of: id), slots[place.slot].tabIDs.count > 1,
              slots[place.slot].tabIDs.indices.contains(place.index + offset) else { return nil }
        slots[place.slot].tabIDs.swapAt(place.index, place.index + offset)
        slots[place.slot].stackFactors.swapAt(place.index, place.index + offset)
        var result = self
        result.arrange(slots)
        return result
    }

    package func transposed() -> BrowserSplitLayout {
        var result = self
        result.orientation = orientation == .horizontal ? .vertical : .horizontal
        return result
    }

    package func expanded(focusing id: UUID) -> BrowserSplitLayout? {
        var slots = self.slots
        guard tabIDs.count > 1, let place = position(of: id) else { return nil }
        for slot in slots.indices { slots[slot].factor = slot == place.slot ? 1 : 1e-9 }
        if slots[place.slot].tabIDs.count > 1 {
            slots[place.slot].stackFactors = slots[place.slot].tabIDs.indices.map { $0 == place.index ? 1 : 1e-9 }
        }
        var result = self
        result.arrange(slots)
        return result
    }

    package func equalized() -> BrowserSplitLayout? {
        var slots = self.slots
        guard tabIDs.count > 1 else { return nil }
        for slot in slots.indices {
            slots[slot].factor = 1
            slots[slot].stackFactors = Array(repeating: 1, count: slots[slot].tabIDs.count)
        }
        var result = self
        result.arrange(slots)
        return result
    }

    package func resizingSlots(_ factors: [Double]) -> BrowserSplitLayout? {
        var slots = self.slots
        guard factors.count == slots.count, Self.normalized(factors, count: factors.count) != nil else { return nil }
        for slot in slots.indices { slots[slot].factor = factors[slot] }
        var result = self
        result.arrange(slots)
        return result
    }

    package func resizingStack(_ slot: Int, factors: [Double]) -> BrowserSplitLayout? {
        var slots = self.slots
        guard slots.indices.contains(slot), slots[slot].tabIDs.count > 1, factors.count == slots[slot].tabIDs.count,
              Self.normalized(factors, count: factors.count) != nil else { return nil }
        slots[slot].stackFactors = factors
        var result = self
        result.arrange(slots)
        return result
    }

    package func resizingDivider(_ divider: Int, inSlot slot: Int?, leadingShare: Double) -> BrowserSplitLayout? {
        guard leadingShare.isFinite, leadingShare > 0, leadingShare < 1 else { return nil }
        let all = slots
        var factors: [Double]
        if let slot {
            guard all.indices.contains(slot), let stack = Self.settled(all[slot].stackFactors) else { return nil }
            factors = stack
        } else {
            guard let main = Self.settled(all.map(\.factor)) else { return nil }
            factors = main
        }
        guard divider >= 0, divider < factors.count - 1 else { return nil }
        let pair = factors[divider] + factors[divider + 1]
        factors[divider] = pair * leadingShare
        factors[divider + 1] = pair - factors[divider]
        if let slot { return resizingStack(slot, factors: factors) }
        return resizingSlots(factors)
    }
}

package struct BrowserState: Codable, Equatable {
    package var version: Int = 1
    package var profiles: [BrowserProfile]
    package var spaces: [BrowserSpace]
    package var tabs: [BrowserTab] = [] { didSet { tabLookup = BrowserTabLookupSlot() } }
    package var folders: [BrowserFolder] = []
    package var activeSpaceID: UUID
    package var selectedTabIDs: [UUID] = []
    package var selectionBySpace: [String: [UUID]] = [:]
    package var splitLayouts: [BrowserSplitLayout] = []
    package var sidebarItemOrder: [String: [SidebarItemReference]] = [:]
    package var autoArchiveStartedAt: Date?
    package var autoArchiveDefaultHours = AutoArchiveInterval.twelveHours.rawValue
    package var autoArchiveEducationEligible = false
    package var history: [BrowserHistoryEntry] = []
    package var downloads: [BrowserDownload] = []
    package var recentlyClosedIDs: [UUID] = []
    package var settings = BrowserSettings()
    package var profileRemovals: [ProfileRemovalRecord] = []
    package var arcImportedSpaces: [String: UUID] = [:]
    package var windows: [BrowserWindowRecord] = []
    package var spaceSharingVersion = SpaceSharing.version
    package var tabLookup = BrowserTabLookupSlot()

    package init(version: Int = 1, profiles: [BrowserProfile], spaces: [BrowserSpace], tabs: [BrowserTab] = [], folders: [BrowserFolder] = [], activeSpaceID: UUID, selectedTabIDs: [UUID] = [], selectionBySpace: [String: [UUID]] = [:], splitLayouts: [BrowserSplitLayout] = [], sidebarItemOrder: [String: [SidebarItemReference]] = [:], autoArchiveStartedAt: Date? = nil, autoArchiveDefaultHours: Double = AutoArchiveInterval.twelveHours.rawValue, autoArchiveEducationEligible: Bool = false, history: [BrowserHistoryEntry] = [], downloads: [BrowserDownload] = [], recentlyClosedIDs: [UUID] = [], settings: BrowserSettings = BrowserSettings(), profileRemovals: [ProfileRemovalRecord] = [], arcImportedSpaces: [String: UUID] = [:], windows: [BrowserWindowRecord] = [], spaceSharingVersion: Int = SpaceSharing.version, tabLookup: BrowserTabLookupSlot = BrowserTabLookupSlot()) {
        self.version = version
        self.profiles = profiles
        self.spaces = spaces
        self.tabs = tabs
        self.folders = folders
        self.activeSpaceID = activeSpaceID
        self.selectedTabIDs = selectedTabIDs
        self.selectionBySpace = selectionBySpace
        self.splitLayouts = splitLayouts
        self.sidebarItemOrder = sidebarItemOrder
        self.autoArchiveStartedAt = autoArchiveStartedAt
        self.autoArchiveDefaultHours = autoArchiveDefaultHours
        self.autoArchiveEducationEligible = autoArchiveEducationEligible
        self.history = history
        self.downloads = downloads
        self.recentlyClosedIDs = recentlyClosedIDs
        self.settings = settings
        self.profileRemovals = profileRemovals
        self.arcImportedSpaces = arcImportedSpaces
        self.windows = windows
        self.spaceSharingVersion = spaceSharingVersion
        self.tabLookup = tabLookup
    }

    package static func initial() -> Self {
        let profile = BrowserProfile(id: UUID(), name: "Default")
        var space = BrowserSpace(id: UUID(), name: "", symbol: "circle.fill", color: "B9B5D4", profileID: profile.id)
        space.updateDisplayName(position: 0)
        space.autoArchiveHours = profile.autoArchiveHours
        return Self(profiles: [profile], spaces: [space], activeSpaceID: space.id)
    }

    package func preservesSidebarOutline(relativeTo previous: BrowserState) -> Bool {
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

    package func preservesChromeLayout(relativeTo previous: BrowserState) -> Bool {
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
                    && current.noteVisit?.position == prior.noteVisit?.position
                    && current.noteVisit?.leaving == prior.noteVisit?.leaving
                    && current.noteVisit?.steps.count == prior.noteVisit?.steps.count
                    && current.noteVisit?.documents.count == prior.noteVisit?.documents.count
            }
    }

    package static func isBlankPage(_ url: String) -> Bool {
        url.isEmpty || url == "about:blank"
    }
}

extension BrowserState {
    private enum CodingKeys: String, CodingKey {
        case version, profiles, spaces, tabs, folders, activeSpaceID, selectedTabIDs,
             selectionBySpace, splitLayouts, sidebarItemOrder, autoArchiveStartedAt, autoArchiveDefaultHours, autoArchiveEducationEligible, history, downloads, recentlyClosedIDs, settings, profileRemovals, arcImportedSpaces, windows, spaceSharingVersion
    }
    private enum LegacySplitKeys: String, CodingKey { case splitWidthFactors }

    package init(from decoder: Decoder) throws {
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
        spaceSharingVersion = try values.decodeIfPresent(Int.self, forKey: .spaceSharingVersion) ?? 0
        if let saved = try values.decodeIfPresent([BrowserSplitLayout].self, forKey: .splitLayouts) {
            splitLayouts = saved
        } else {
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

package struct BrowserWindowRecord: Codable, Equatable {
    package var sidebarWidth: Double
    package var itemLastActiveDates: [UUID: Date]
    package var id: UUID?
    package var focusedSpaceID: UUID?
    package var selectedTabIDs: [UUID]?
    package var focusedTabID: UUID?
    package var sidebarHidden: Bool?
    package var stayOnTop: Bool
    package var peekedFolders: [UUID: [SidebarItemReference]]?
    package var frame: SavedWindowFrame?
    private enum CodingKeys: String, CodingKey {
        case sidebarWidth, itemLastActiveDates, id, focusedSpaceID, selectedTabIDs, focusedTabID, sidebarHidden, stayOnTop, peekedFolders, frame
    }

    package init(sidebarWidth: Double, itemLastActiveDates: [UUID: Date] = [:], id: UUID? = nil,
         focusedSpaceID: UUID? = nil, selectedTabIDs: [UUID]? = nil, focusedTabID: UUID? = nil,
         sidebarHidden: Bool? = nil, stayOnTop: Bool = false, peekedFolders: [UUID: [SidebarItemReference]]? = nil,
         frame: SavedWindowFrame? = nil) {
        self.sidebarWidth = sidebarWidth
        self.itemLastActiveDates = itemLastActiveDates
        self.id = id; self.focusedSpaceID = focusedSpaceID; self.selectedTabIDs = selectedTabIDs
        self.focusedTabID = focusedTabID; self.sidebarHidden = sidebarHidden
        self.stayOnTop = stayOnTop
        self.peekedFolders = peekedFolders
        self.frame = frame
    }
    package init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sidebarWidth = try values.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? 228
        id = try values.decodeIfPresent(UUID.self, forKey: .id)
        focusedSpaceID = try values.decodeIfPresent(UUID.self, forKey: .focusedSpaceID)
        selectedTabIDs = try values.decodeIfPresent([UUID].self, forKey: .selectedTabIDs)
        focusedTabID = try values.decodeIfPresent(UUID.self, forKey: .focusedTabID)
        sidebarHidden = try values.decodeIfPresent(Bool.self, forKey: .sidebarHidden)
        stayOnTop = try values.decodeIfPresent(Bool.self, forKey: .stayOnTop) ?? false
        peekedFolders = try? values.decodeIfPresent([UUID: [SidebarItemReference]].self, forKey: .peekedFolders)
        frame = (try? values.decodeIfPresent(SavedWindowFrame.self, forKey: .frame)) ?? nil
        if let intervals = try? values.decode([UUID: Double].self, forKey: .itemLastActiveDates) {
            itemLastActiveDates = intervals.mapValues { Date(timeIntervalSinceReferenceDate: $0) }
        } else {
            itemLastActiveDates = try values.decodeIfPresent([UUID: Date].self, forKey: .itemLastActiveDates) ?? [:]
        }
    }
    package func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(sidebarWidth, forKey: .sidebarWidth)
        try values.encodeIfPresent(id, forKey: .id)
        try values.encodeIfPresent(focusedSpaceID, forKey: .focusedSpaceID)
        try values.encodeIfPresent(selectedTabIDs, forKey: .selectedTabIDs)
        try values.encodeIfPresent(focusedTabID, forKey: .focusedTabID)
        try values.encodeIfPresent(sidebarHidden, forKey: .sidebarHidden)
        try values.encode(stayOnTop, forKey: .stayOnTop)
        try values.encodeIfPresent(peekedFolders, forKey: .peekedFolders)
        try values.encodeIfPresent(frame, forKey: .frame)
        try values.encode(itemLastActiveDates.mapValues(\.timeIntervalSinceReferenceDate), forKey: .itemLastActiveDates)
    }

    package static func preservingUnrestored(live: [Self], unrestored: [Self]) -> [Self] {
        let liveIDs = Set(live.compactMap(\.id))
        return live + unrestored.filter { $0.id.map { !liveIDs.contains($0) } ?? true }
    }

    package static func sessionOrder(holdsFrameAutosave: [Bool], frontToBack: [Int?]) -> [Int] {
        func rank(_ index: Int) -> Int { holdsFrameAutosave[index] ? -1 : frontToBack[index] ?? .max }
        return holdsFrameAutosave.indices.sorted { (rank($0), $0) < (rank($1), $1) }
    }
}

package enum SidebarItemReference: Codable, Hashable {
    case tab(UUID), folder(UUID), split(UUID)
}

package struct SidebarContainerLocation: Equatable {
    package let spaceID: UUID
    package let folderID: UUID?
    package let section: TabKind
    package var profileID: UUID? = nil

    package init(spaceID: UUID, folderID: UUID?, section: TabKind, profileID: UUID? = nil) {
        self.spaceID = spaceID
        self.folderID = folderID
        self.section = section
        self.profileID = profileID
    }
    package var key: String {
        if section == .favorite, let profileID { return "favorites:" + profileID.uuidString }
        return spaceID.uuidString + ":" + (folderID?.uuidString ?? section.rawValue)
    }
}

package struct SidebarHierarchySnapshot: Equatable {
    package struct Placement: Equatable {
        package let id: UUID, profileID: UUID, spaceID: UUID
        package let kind: TabKind
        package let folderID: UUID?
    }
    package let spaceID: UUID, profileID: UUID
    package let includesFavorites: Bool
    package let tabs: [Placement]
    package let folders: [BrowserFolder]
    package let groups: [BrowserSplitLayout]
    package let order: [String: [SidebarItemReference]]

    package init?(state: BrowserState, spaceID: UUID, profileID: UUID, includesFavorites: Bool = false) {
        guard state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }),
              state.profiles.contains(where: { $0.id == profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == profileID }) else { return nil }
        self.spaceID = spaceID; self.profileID = profileID; self.includesFavorites = includesFavorites
        tabs = state.openTabs(where: { ($0.kind == .favorite
            ? includesFavorites && $0.profileID == profileID : $0.spaceID == spaceID) })
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

package enum SidebarHierarchy {
    package static func location(of item: SidebarItemReference, state: BrowserState, spaceID: UUID) -> SidebarContainerLocation? {
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
              let tab = state.tab(id, where: { $0.archivedAt == nil && $0.profileID == profileID
                  && ($0.kind == .favorite || $0.spaceID == spaceID) }) else { return nil }
        return tabLocation(of: tab, spaceID: spaceID, profileID: profileID)
    }
    private static func tabLocation(of tab: BrowserTab, spaceID: UUID, profileID: UUID) -> SidebarContainerLocation? {
        if tab.kind == .favorite {
            guard tab.folderID == nil else { return nil }
            return .init(spaceID: spaceID, folderID: nil, section: .favorite, profileID: profileID)
        }
        return .init(spaceID: spaceID, folderID: tab.folderID, section: tab.folderID == nil ? tab.kind : .pinned)
    }
    package static func children(in location: SidebarContainerLocation, state: BrowserState) -> [SidebarItemReference] {
        guard let profileID = state.spaces.first(where: { $0.id == location.spaceID })?.profileID,
              location.section != .favorite || (location.folderID == nil && location.profileID == profileID) else { return [] }
        let groups = SidebarSplitItems.groups(in: state, spaceID: location.spaceID)
        var legacy: [SidebarItemReference] = []
        for tab in state.openTabs where tab.profileID == profileID && (location.section == .favorite ? tab.kind == .favorite : tab.spaceID == location.spaceID && tab.kind != .favorite) {
            let item: SidebarItemReference
            if let group = groups.first(where: { $0.tabIDs.contains(tab.id) }) {
                guard group.sidebarAnchorID == tab.id else { continue }
                item = .split(group.id)
            } else { item = .tab(tab.id) }
            if tabLocation(of: tab, spaceID: location.spaceID, profileID: profileID) == location { legacy.append(item) }
        }
        if location.section == .pinned {
            legacy += state.folders.filter { $0.spaceID == location.spaceID && $0.parentID == location.folderID }.map { .folder($0.id) }
        }
        let stored = (state.sidebarItemOrder[location.key] ?? []).map { item -> SidebarItemReference in
            if case .tab(let id) = item, let group = groups.first(where: { $0.sidebarAnchorID == id }) { return .split(group.id) }
            return item
        }
        var seen = Set<SidebarItemReference>()
        let present = Set(legacy)
        return (stored + legacy).filter { present.contains($0) && seen.insert($0).inserted }
    }
    package static func childrenByContainer(spaceID: UUID, state: BrowserState) -> [String: [SidebarItemReference]] {
        guard let profileID = state.spaces.first(where: { $0.id == spaceID })?.profileID else { return [:] }
        let groups = SidebarSplitItems.groups(in: state, spaceID: spaceID)
        var legacy: [String: [SidebarItemReference]] = [:]
        for tab in state.openTabs where tab.profileID == profileID && tab.spaceID == spaceID && tab.kind != .favorite {
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
    package static func placingCreatedTab(_ id: UUID, insertion: TodayInsertion, in state: inout BrowserState) {
        guard let tab = state.tab(id, where: { $0.archivedAt == nil
                  && $0.kind == .today && $0.folderID == nil }) else { return }
        let location = SidebarContainerLocation(spaceID: tab.spaceID, folderID: nil, section: .today)
        var items = children(in: location, state: state)
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
                return snapshot.tab(other)?.referrerID != referrer
            } ?? items.endIndex
        }
        items.insert(.tab(id), at: index)
        state.sidebarItemOrder[location.key] = items.map { storedReference($0, state: state) }
    }
    package static func storedReference(_ item: SidebarItemReference, state: BrowserState) -> SidebarItemReference {
        if case .split(let id) = item, let anchor = state.splitLayouts.first(where: { $0.id == id })?.sidebarAnchorID { return .tab(anchor) }
        return item
    }
    package static func placing(_ item: SidebarItemReference, in location: SidebarContainerLocation,
                        following recorded: [SidebarItemReference], state: inout BrowserState) {
        let snapshot = state
        var siblings = children(in: location, state: snapshot).map { storedReference($0, state: snapshot) }.filter { $0 != item }
        var index = siblings.count
        if let position = recorded.firstIndex(of: item) {
            let following = recorded[(position + 1)...].first(where: siblings.contains)
            let preceding = recorded[..<position].last(where: siblings.contains)
            index = following.flatMap { siblings.firstIndex(of: $0) }
                ?? preceding.flatMap { siblings.firstIndex(of: $0).map { $0 + 1 } }
                ?? min(position, siblings.count)
        }
        siblings.insert(item, at: index)
        state.sidebarItemOrder[location.key] = siblings
    }
    package static func tabIDs(in item: SidebarItemReference, state: BrowserState, spaceID: UUID) -> [UUID] {
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
    package static func moving(_ item: SidebarItemReference, to destination: SidebarContainerLocation,
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


package struct SidebarDocumentReference {
    package let page: InternalPage
    package let profileID: UUID
    private let validate: @MainActor () throws -> Void
    package init(page: InternalPage, profileID: UUID, validate: @escaping @MainActor () throws -> Void) {
        self.page = page; self.profileID = profileID; self.validate = validate
    }
    @MainActor package func isCurrent() -> Bool { do { try validate(); return true } catch { return false } }
    @MainActor package static func validates(_ originals: [BrowserTab], references: [UUID: Self]) -> Bool {
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

package struct SidebarCopySources {
    package var destinations: [UUID: String] = [:]
    package var documents: [UUID: SidebarDocumentReference] = [:]

    package init(destinations: [UUID: String] = [:], documents: [UUID: SidebarDocumentReference] = [:]) {
        self.destinations = destinations
        self.documents = documents
    }

    @MainActor package func validates(_ originals: [BrowserTab]) -> Bool {
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

package struct SidebarDuplicateTarget: Equatable {
    package let source: CommandBarFolderMoveSource
    package let folderIDs: [UUID]
    package let tabs: [BrowserTab]
    package let groups: [BrowserSplitLayout]
    package var roots: [SidebarItemReference] { source.roots }
    package var hierarchy: SidebarHierarchySnapshot { source.hierarchy }

    package init?(items: [SidebarItemReference], spaceID: UUID, profileID: UUID, state: BrowserState) {
        guard items.allSatisfy({ SidebarHierarchy.location(of: $0, state: state, spaceID: spaceID) != nil }),
              let source = CommandBarFolderMoveSource(items: items, spaceID: spaceID, profileID: profileID, state: state) else { return nil }
        let tabs = source.tabIDs.compactMap { id in state.tab(id) }
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
              Set(state.openTabs(where: { $0.folderID.map(folders.contains) == true }).map(\.id)).isSubset(of: Set(source.tabIDs)) else { return nil }
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

package struct FolderDuplicateTarget: Equatable {
    package let folderID: UUID
    package let collection: SidebarDuplicateTarget
    package var hierarchy: SidebarHierarchySnapshot { collection.hierarchy }
    package var folderIDs: [UUID] { collection.folderIDs }
    package var tabs: [BrowserTab] { collection.tabs }
    package var groups: [BrowserSplitLayout] { collection.groups }

    package init?(folderID: UUID, spaceID: UUID, profileID: UUID, state: BrowserState) {
        guard let collection = SidebarDuplicateTarget(items: [.folder(folderID)], spaceID: spaceID, profileID: profileID, state: state) else { return nil }
        self.folderID = folderID; self.collection = collection
    }

    package static func validSource(_ value: String) -> Bool {
        InternalPage(urlString: value) != nil || validDestination(value)
    }
    package static func validDestination(_ value: String) -> Bool {
        guard !InternalPage.isInternal(value), let url = URL(string: value),
              let scheme = url.scheme, !scheme.isEmpty else { return false }
        return true
    }
}

package struct SidebarDuplicateResult {
    package let roots: [SidebarItemReference]
    package let tabIDs: [UUID]
    package let openTabIDs: [UUID]

    package init(roots: [SidebarItemReference], tabIDs: [UUID], openTabIDs: [UUID]) {
        self.roots = roots
        self.tabIDs = tabIDs
        self.openTabIDs = openTabIDs
    }
}

package struct SidebarItemsCopy: Equatable {
    package let collection: SidebarMoveCollection
    package let groups: [BrowserSplitLayout]
    package var roots: [SidebarItemReference] { collection.roots }
    package var tabs: [BrowserTab] { collection.tabs }
    package var folderIDs: [UUID] { collection.folderIDs }
    package var source: SidebarHierarchySnapshot { collection.hierarchy }
    package var wholeSplits: Bool { roots.allSatisfy { if case .split = $0 { return true } else { return false } } }

    package init?(items: [SidebarItemReference], spaceID: UUID, profileID: UUID, state: BrowserState) {
        guard let collection = SidebarMoveCollection(items: items, spaceID: spaceID, profileID: profileID, state: state),
              collection.tabs.count == collection.tabIDs.count,
              collection.tabs.allSatisfy({
                  $0.archivedAt == nil && ($0.folderID == nil || $0.kind == .pinned) && FolderDuplicateTarget.validSource($0.savedURL)
              }) else { return nil }
        let ids = Set(collection.tabIDs)
        let groups = collection.hierarchy.groups.filter { !$0.tabIDs.allSatisfy { !ids.contains($0) } }
        guard groups.allSatisfy({ group in
            group.tabIDs.allSatisfy(ids.contains) && group.sidebarAnchorID.map(group.tabIDs.contains) == true
        }) else { return nil }
        self.collection = collection; self.groups = groups
    }

    package func matchesPlacement(of other: SidebarItemsCopy) -> Bool {
        func placement(_ tab: BrowserTab) -> [String] {
            [tab.id.uuidString, tab.profileID.uuidString, tab.spaceID.uuidString, tab.kind.rawValue, tab.folderID?.uuidString ?? ""]
        }
        func parents(_ copy: SidebarItemsCopy) -> [UUID?] {
            copy.folderIDs.map { id in copy.source.folders.first { $0.id == id }?.parentID }
        }
        return roots == other.roots && groups == other.groups && collection.tabIDs == other.collection.tabIDs
            && folderIDs == other.folderIDs && parents(self) == parents(other)
            && source.spaceID == other.source.spaceID && source.profileID == other.source.profileID
            && tabs.map(placement) == other.tabs.map(placement)
    }
}

package struct FolderDuplicateResult {
    package let folderID: UUID
    package let tabIDs: [UUID]
    package let openTabIDs: [UUID]
}

package struct FolderRemovalTarget: Equatable {
    package let roots: [SidebarItemReference]
    package let name: String
    package let hierarchy: SidebarHierarchySnapshot
    package let folderIDs: [UUID]
    package let tabs: [BrowserTab]
    package let groups: [BrowserSplitLayout]

    package init?(folderID: UUID, spaceID: UUID, profileID: UUID, state: BrowserState) {
        self.init(items: [.folder(folderID)], spaceID: spaceID, profileID: profileID, state: state)
    }

    package init?(items: [SidebarItemReference], spaceID: UUID, profileID: UUID, includesFavorites: Bool = false, state: BrowserState) {
        guard let hierarchy = SidebarHierarchySnapshot(state: state, spaceID: spaceID, profileID: profileID,
                                                       includesFavorites: includesFavorites),
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
        let tabs = tabIDs.compactMap { id in state.tab(id) }
        guard tabs.count == tabIDs.count, tabs.allSatisfy({
            ($0.kind == .favorite ? includesFavorites && $0.folderID == nil : $0.spaceID == spaceID)
                && $0.profileID == profileID && $0.archivedAt == nil
                && ($0.folderID == nil || $0.kind == .pinned)
                && FolderDuplicateTarget.validSource($0.savedURL)
        }), Set(state.openTabs(where: { $0.folderID.map(folders.contains) == true }).map(\.id)).isSubset(of: Set(tabIDs)) else { return nil }
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

    package func refreshed(in state: BrowserState) -> FolderRemovalTarget? {
        FolderRemovalTarget(items: roots, spaceID: hierarchy.spaceID, profileID: hierarchy.profileID,
                            includesFavorites: hierarchy.includesFavorites, state: state)
    }
}

package struct SidebarKeyboardCloseTarget: Equatable {
    package let items: FolderRemovalTarget
    package let archivesItems: Bool

    package init?(items: [SidebarItemReference], spaceID: UUID, profileID: UUID, state: BrowserState) {
        guard let target = FolderRemovalTarget(items: items, spaceID: spaceID,
                                               profileID: profileID, state: state) else { return nil }
        self.items = target
        archivesItems = target.roots.contains {
            SidebarHierarchy.location(of: $0, state: state, spaceID: spaceID)?.section == .today
        }
    }

    package var requiresConfirmation: Bool { archivesItems && !items.folderIDs.isEmpty }

    package var holdsOnlyEmptyFolders: Bool {
        items.tabs.isEmpty && items.roots.allSatisfy { if case .folder = $0 { return true }; return false }
    }
}

package struct FolderDeletionUndo: SidebarItemsRecord {
    package let id = UUID()
    package let roots: [SidebarItemReference]
    package let spaceID: UUID, profileID: UUID
    package let folders: [BrowserFolder]
    package let tabs: [BrowserTab]
    package let archivedTabs: [BrowserTab]
    package let documentReferences: [UUID: SidebarDocumentReference]
    package let groups: [BrowserSplitLayout]
    package struct Location {
        package let container: SidebarContainerLocation
        package let siblings: [SidebarItemReference]

        package init(container: SidebarContainerLocation, siblings: [SidebarItemReference]) {
            self.container = container
            self.siblings = siblings
        }
    }
    package let locations: [Location]
    package let childOrder: [String: [SidebarItemReference]]
    package struct Detached {
        package let original: BrowserTab
        package let archived: BrowserTab
    }
    package let detachedArchive: [Detached]
    package let focusedTabID: UUID?

    package var actionName: String { tabs.count == 1 ? "Archive Tab" : "Archive Tabs" }

    @MainActor package var documentsAreAvailable: Bool {
        SidebarDocumentReference.validates(tabs, references: documentReferences)
    }

    fileprivate init(target: FolderRemovalTarget, selection: FolderRemovalSelection?,
                     documents: [UUID: SidebarDocumentReference], before: BrowserState, after: BrowserState) {
        documentReferences = documents
        roots = target.roots
        spaceID = target.hierarchy.spaceID; profileID = target.hierarchy.profileID
        folders = target.hierarchy.folders.filter { target.folderIDs.contains($0.id) }
        tabs = target.tabs; groups = target.groups
        archivedTabs = target.tabs.compactMap { original in after.tab(original.id) }
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
        let targetIDs = Set(target.tabs.map(\.id))
        let changed = Dictionary(after.tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        detachedArchive = before.archivedTabs(where: { !targetIDs.contains($0.id) }).compactMap { original in
            changed[original.id].flatMap { $0 == original ? nil : Detached(original: original, archived: $0) }
        }
        focusedTabID = selection?.originalFocus.flatMap { focus in target.tabs.contains { $0.id == focus } ? focus : nil }
    }

    package func redoTarget(in state: BrowserState) -> FolderRemovalTarget? { matchingTarget(in: state) }
}

package protocol SidebarItemsRecord {
    var roots: [SidebarItemReference] { get }
    var spaceID: UUID { get }
    var profileID: UUID { get }
    var folders: [BrowserFolder] { get }
    var tabs: [BrowserTab] { get }
    var groups: [BrowserSplitLayout] { get }
    var locations: [FolderDeletionUndo.Location] { get }
    var includesFavorites: Bool { get }
}

extension SidebarItemsRecord {
    package var includesFavorites: Bool { false }

    package func matchingTarget(in state: BrowserState) -> FolderRemovalTarget? {
        guard let target = FolderRemovalTarget(items: roots, spaceID: spaceID, profileID: profileID,
                                               includesFavorites: includesFavorites, state: state),
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

    package func reinsertingRoots(current state: BrowserState, into next: inout BrowserState) -> Bool {
        for location in locations {
            var siblings = SidebarHierarchy.children(in: location.container, state: state)
            for root in location.siblings where roots.contains(root) {
                guard let position = location.siblings.firstIndex(of: root), !siblings.contains(root) else { return false }
                let following = location.siblings.dropFirst(position + 1).first { siblings.contains($0) }
                let preceding = location.siblings.prefix(position).reversed().first { siblings.contains($0) }
                let insertion = following.flatMap { siblings.firstIndex(of: $0) }
                    ?? preceding.flatMap { siblings.firstIndex(of: $0).map { $0 + 1 } }
                    ?? min(position, siblings.count)
                siblings.insert(root, at: insertion)
            }
            if location.container.section == .favorite, siblings.count > 12 { return false }
            next.sidebarItemOrder[location.container.key] = siblings.map { item in
                if case .split(let id) = item, let anchor = next.splitLayouts.first(where: { $0.id == id })?.sidebarAnchorID { return .tab(anchor) }
                return item
            }
        }
        return true
    }
}

package struct SidebarCopyUndo: SidebarItemsRecord {
    package static let duplicateName = "Duplicate"
    package static let folderCopyName = "Copy to Folder"
    package static let dragCopyName = "Copy"
    package let actionName: String
    package let roots: [SidebarItemReference]
    package let spaceID: UUID, profileID: UUID
    package let includesFavorites: Bool
    package let folders: [BrowserFolder]
    package let tabs: [BrowserTab]
    package let groups: [BrowserSplitLayout]
    package let locations: [FolderDeletionUndo.Location]
    package let childOrder: [String: [SidebarItemReference]]
    package let detachedArchive: [BrowserTab]
    package let documentReferences: [UUID: SidebarDocumentReference]
    package let openTabIDs: [UUID]

    package init?(actionName: String, roots: [SidebarItemReference], spaceID: UUID, profileID: UUID,
          documents: [SidebarDocumentReference], openTabIDs: [UUID], state: BrowserState) {
        let includesFavorites = roots.contains { SidebarHierarchy.location(of: $0, state: state, spaceID: spaceID)?.section == .favorite }
        guard let target = FolderRemovalTarget(items: roots, spaceID: spaceID, profileID: profileID,
                                               includesFavorites: includesFavorites, state: state),
              target.roots == roots else { return nil }
        self.actionName = actionName; self.roots = roots
        self.spaceID = spaceID; self.profileID = profileID; self.includesFavorites = includesFavorites
        folders = target.hierarchy.folders.filter { target.folderIDs.contains($0.id) }
        tabs = target.tabs; groups = target.groups
        var seen = Set<String>()
        locations = roots.compactMap { root in
            guard let container = SidebarHierarchy.location(of: root, state: state, spaceID: spaceID),
                  seen.insert(container.key).inserted else { return nil }
            return .init(container: container, siblings: SidebarHierarchy.children(in: container, state: state))
        }
        childOrder = Dictionary(uniqueKeysWithValues: target.folderIDs.map { id in
            let location = SidebarContainerLocation(spaceID: spaceID, folderID: id, section: .pinned)
            return (location.key, SidebarHierarchy.children(in: location, state: state).map { item in
                if case .split(let id) = item, let anchor = target.groups.first(where: { $0.id == id })?.sidebarAnchorID { return .tab(anchor) }
                return item
            })
        })
        detachedArchive = state.tabs.filter { $0.archivedAt != nil && $0.folderID.map(target.folderIDs.contains) == true }
        documentReferences = Dictionary(uniqueKeysWithValues: target.tabs.compactMap { tab in
            guard let page = InternalPage(urlString: tab.savedURL),
                  let reference = documents.first(where: { $0.page == page && $0.profileID == tab.profileID }) else { return nil }
            return (tab.id, reference)
        })
        self.openTabIDs = openTabIDs
    }

    package func refreshed(in state: BrowserState) -> SidebarCopyUndo? {
        SidebarCopyUndo(actionName: actionName, roots: roots, spaceID: spaceID, profileID: profileID,
                        documents: Array(documentReferences.values), openTabIDs: openTabIDs, state: state)
    }

    @MainActor package var documentsAreAvailable: Bool {
        SidebarDocumentReference.validates(tabs, references: documentReferences)
    }
}

extension FolderRemovalSelection {
    package func isCurrent(for target: FolderRemovalTarget, in state: BrowserState) -> Bool {
        Self.resolve(target: target, state: state, spaceID: spaceID, selected: original, focused: originalFocus,
                     referrerPool: referrerPool, previouslySelectedItemID: previouslySelectedItemID,
                     available: { tabIDs.contains($0) }) == self
    }
}

package struct ClosedTabsUndo {
    package enum Prompt {
        case clear, archive
        package func name(count: Int) -> String {
            switch self {
            case .clear: return count == 1 ? "Clear Tab" : "Clear Tabs"
            case .archive: return count == 1 ? "Archive Tab" : "Archive Tabs"
            }
        }
    }
    package let prompt: Prompt
    package let spaceID: UUID, profileID: UUID
    package let tabs: [BrowserTab]
    package let archivedTabs: [BrowserTab]
    package let groups: [BrowserSplitLayout]
    package let memberships: [UUID: ClosedSplitMembership]
    package let order: [SidebarItemReference]
    package let focusedTabID: UUID?

    package var actionName: String { prompt.name(count: itemCount(of: Set(tabs.map(\.id)))) }
    package func itemCount(of ids: Set<UUID>) -> Int {
        let closed = Set(tabs.map(\.id))
        let removed = groups.filter { group in
            group.tabIDs.allSatisfy(closed.contains)
                || memberships.values.contains { $0.layout.id == group.id && $0.dissolved }
        }
        return ids.count + removed.filter { !Set($0.tabIDs).isDisjoint(with: ids) }.count
    }
    package func reopenedIDs(_ reopened: ClosedItemRecord) -> Set<UUID> {
        Set(reopened.tabs.filter { tab in archivedTabs.contains {
            $0.id == tab.id && $0.archivedAt == tab.archivedAt && $0.archiveProvenance == tab.archiveProvenance
        } }.map(\.id))
    }
    private var removesTabs: Bool { archivedTabs.isEmpty }
    private var location: SidebarContainerLocation { .init(spaceID: spaceID, folderID: nil, section: .today) }

    package init?(prompt: Prompt, ids: Set<UUID>, spaceID: UUID, profileID: UUID, focusedTabID: UUID?,
          before: BrowserState, after: BrowserState) {
        let candidates = before.openTabs(where: { ids.contains($0.id) && $0.kind == .today && $0.folderID == nil && $0.spaceID == spaceID && $0.profileID == profileID })
        let archived = candidates.compactMap { original in after.tab(original.id, where: { $0.archivedAt != nil }) }
        let originals = archived.isEmpty
            ? candidates.filter { original in !after.containsTab(original.id) }
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

    package func restorableIDs(in state: BrowserState) -> Set<UUID> {
        if removesTabs { return Set(tabs.filter { original in !state.containsTab(original.id) }.map(\.id)) }
        return Set(archivedTabs.filter { recorded in state.tabs.contains { current in
            current.id == recorded.id && current.profileID == recorded.profileID
                && current.spaceID == recorded.spaceID && current.createdAt == recorded.createdAt
                && current.archivedAt == recorded.archivedAt && current.archiveProvenance == recorded.archiveProvenance
        } }.map(\.id))
    }

    package func redoIDs(in state: BrowserState) -> Set<UUID> {
        Set(tabs.filter { original in state.containsTab(original.id, where: { $0.archivedAt == nil && $0.kind == .today && $0.folderID == nil
                && $0.spaceID == spaceID && $0.profileID == profileID }) }.map(\.id))
    }

    package func restoring(_ state: BrowserState, regroupable: (UUID) -> Bool = { _ in true }) -> BrowserState? {
        let ids = restorableIDs(in: state)
        guard !ids.isEmpty else { return nil }
        var next = state
        for original in tabs where ids.contains(original.id) {
            guard let index = next.tabIndex(original.id) else {
                next.tabs.append(original); continue
            }
            next.tabs[index].archivedAt = original.archivedAt
            next.tabs[index].archiveProvenance = original.archiveProvenance
            next.tabs[index].kind = original.kind
            next.tabs[index].folderID = original.folderID
        }
        next.recentlyClosedIDs.removeAll { ids.contains($0) }
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
            if let anchor = membership.layout.sidebarAnchorID, group.tabIDs.contains(anchor) { group.sidebarAnchorID = anchor }
            next.splitLayouts.removeAll { $0.id == group.id }
            next.splitLayouts.append(group)
            rejoined.formUnion(group.tabIDs.filter(ids.contains)); rejoinedGroups.insert(group.id)
        }
        var entries: [SidebarItemReference] = []
        for item in order {
            guard case .split(let id) = item, let group = groups.first(where: { $0.id == id }) else { entries.append(item); continue }
            if regrouped.contains(id) { entries.append(item); continue }
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

package struct FolderRemovalSelection: Equatable {
    package let spaceID: UUID, profileID: UUID
    package let original: [UUID]
    package let originalFocus: UUID?
    package let tabIDs: [UUID]
    package let focusedTabID: UUID?
    package let removed: Set<UUID>
    package let referrerPool: Set<UUID>
    package let previouslySelectedItemID: UUID?
    package let replacementSpaceID: UUID

    package init(spaceID: UUID, profileID: UUID, original: [UUID], originalFocus: UUID?,
         tabIDs: [UUID], focusedTabID: UUID?, removed: Set<UUID> = [], referrerPool: Set<UUID> = [],
         previouslySelectedItemID: UUID? = nil, replacementSpaceID: UUID? = nil) {
        self.spaceID = spaceID; self.profileID = profileID; self.original = original
        self.originalFocus = originalFocus; self.tabIDs = tabIDs; self.focusedTabID = focusedTabID
        self.removed = removed; self.referrerPool = referrerPool
        self.previouslySelectedItemID = previouslySelectedItemID
        self.replacementSpaceID = replacementSpaceID ?? spaceID
    }

    package static func resolve(target: FolderRemovalTarget, state: BrowserState, spaceID: UUID? = nil,
                        selected: [UUID], focused: UUID?, referrerPool: Set<UUID> = [],
                        previouslySelectedItemID: UUID? = nil, available: (UUID) -> Bool) -> Self? {
        let space = spaceID ?? target.hierarchy.spaceID, profile = target.hierarchy.profileID
        guard space == target.hierarchy.spaceID || target.hierarchy.includesFavorites,
              target.refreshed(in: state) == target else { return nil }
        return resolve(removing: Set(target.tabs.map(\.id)), spaceID: space,
            profileID: profile, state: state, selected: selected, focused: focused, referrerPool: referrerPool,
            previouslySelectedItemID: previouslySelectedItemID, available: available)
    }

    package static func resolve(removing removed: Set<UUID>, spaceID space: UUID,
                        profileID profile: UUID, state: BrowserState,
                        selected: [UUID], focused: UUID?, referrerPool: Set<UUID> = [],
                        previouslySelectedItemID: UUID? = nil, available: (UUID) -> Bool) -> Self? {
        guard state.spaces.contains(where: { $0.id == space && $0.profileID == profile }),
              selected.count <= 4, Set(selected).count == selected.count,
              selected.allSatisfy({ id in state.containsTab(id, where: { $0.archivedAt == nil && $0.profileID == profile
                      && ($0.spaceID == space || $0.kind == .favorite) }) }), focused == nil || selected.contains(focused!) else { return nil }
        let survivors = selected.filter { !removed.contains($0) }
        func decision(_ ids: [UUID], focus: UUID?, replacementSpaceID: UUID? = nil) -> Self {
            .init(spaceID: space, profileID: profile, original: selected,
                  originalFocus: focused, tabIDs: ids, focusedTabID: focus, removed: removed, referrerPool: referrerPool,
                  previouslySelectedItemID: previouslySelectedItemID, replacementSpaceID: replacementSpaceID)
        }
        if !survivors.isEmpty || selected.isEmpty {
            guard survivors.allSatisfy(available) else { return nil }
            return decision(survivors, focus: focused.flatMap { survivors.contains($0) ? $0 : nil }
                ?? BrowserSplitLayout.focusSuccessor(survivors, removedAt: focused.flatMap { selected.firstIndex(of: $0) }))
        }
        let current = focused ?? selected.first
        struct Item { let ids: [UUID]; let accessed: Date }
        var ordered: [Item] = [], visited = Set<UUID>(), assigned = Set<UUID>()
        let tabs = Dictionary(uniqueKeysWithValues: state.openTabs(where: { $0.spaceID == space && $0.profileID == profile && $0.kind != .favorite }).map { ($0.id, $0) })
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
        collect(nil, section: .pinned); collect(nil, section: .today)
        func eligible(_ item: Item) -> Bool {
            item.ids.allSatisfy { !removed.contains($0) && available($0) }
        }
        let candidates = ordered.filter { eligible($0) || current.map($0.ids.contains) == true }
        if let current, let index = candidates.firstIndex(where: { $0.ids.contains(current) }) {
            for neighbor in [index - 1, index + 1] where candidates.indices.contains(neighbor) {
                let item = candidates[neighbor]
                if item.ids.count == 1, let id = item.ids.first,
                   tabs[id]?.referrerID == current, eligible(item) {
                    return decision(item.ids, focus: id)
                }
            }
            if referrerPool.contains(current), let referrer = tabs[current]?.referrerID {
                for item in candidates.dropFirst(index + 1) where item.ids.count == 1 {
                    if let id = item.ids.first, referrerPool.contains(id),
                       tabs[id]?.referrerID == referrer, eligible(item) {
                        return decision(item.ids, focus: id)
                    }
                }
            }
        }
        if let current, let previous = state.tab(current)?.activeTabBeforeCreationID,
           referrerPool.contains(previous), !removed.contains(previous), available(previous),
           let tab = state.tab(previous, where: { $0.archivedAt == nil
               && $0.profileID == profile && ($0.kind == .favorite || $0.spaceID == space) }) {
            if tab.kind == .favorite { return decision([previous], focus: previous) }
            if let item = ordered.first(where: { $0.ids.contains(previous) }), eligible(item) {
                return decision(item.ids, focus: previous)
            }
        }
        if let current, let previous = previouslySelectedItemID, previous != current,
           let source = state.tab(current, where: { $0.archivedAt == nil && $0.profileID == profile }),
           let tab = state.tab(previous, where: { $0.archivedAt == nil && $0.profileID == profile }),
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
                   !removed.contains(id) && available(id) && state.containsTab(id, where: { $0.archivedAt == nil && $0.profileID == profile
                           && $0.spaceID == destination && $0.kind == tab.kind && $0.folderID == tab.folderID })
               }) {
                return decision(group.tabIDs, focus: previous, replacementSpaceID: destination)
            }
        }
        if let current, let index = candidates.firstIndex(where: { $0.ids.contains(current) }) {
            for neighbor in [index - 1, index + 1] where candidates.indices.contains(neighbor) {
                let item = candidates[neighbor]
                if eligible(item) { return decision(item.ids, focus: item.ids.first) }
            }
        }
        let fallback = ordered.enumerated().filter { eligible($0.element) }.sorted {
            if $0.element.accessed != $1.element.accessed { return $0.element.accessed > $1.element.accessed }
            return $0.offset < $1.offset
        }.first?.element.ids ?? []
        return decision(fallback, focus: fallback.first)
    }
}


package struct SidebarItemSelection: Equatable {
    package private(set) var items: [SidebarItemReference] = []
    package private(set) var singleItem: SidebarItemReference?
    package private(set) var anchor: SidebarItemReference?
    package private(set) var focus: SidebarItemReference?

    package init(items: [SidebarItemReference] = [], singleItem: SidebarItemReference? = nil, anchor: SidebarItemReference? = nil, focus: SidebarItemReference? = nil) {
        self.items = items
        self.singleItem = singleItem
        self.anchor = anchor
        self.focus = focus
    }
    package mutating func clear() { items = []; singleItem = nil; anchor = nil; focus = nil }
    package func copyTargets(order: [SidebarItemReference], active: SidebarItemReference?) -> [SidebarItemReference]? {
        if !items.isEmpty { return items }
        guard let item = singleItem ?? active, order.contains(item) else { return nil }
        return [item]
    }
    package mutating func selectAll(order: [SidebarItemReference], active: SidebarItemReference?) {
        var seen = Set<SidebarItemReference>()
        let visible = order.filter { seen.insert($0).inserted }
        reconcile(order: visible)
        items = visible.count > 1 ? visible : []
        singleItem = visible.count == 1 ? visible.first : nil
        anchor = visible.first
        focus = focus.flatMap { visible.contains($0) ? $0 : nil }
            ?? active.flatMap { visible.contains($0) ? $0 : nil } ?? visible.first
    }
    package mutating func reconcile(order: [SidebarItemReference]) {
        let allowed = Set(order)
        items.removeAll { !allowed.contains($0) }
        if let singleItem, !allowed.contains(singleItem) { self.singleItem = nil }
        if let anchor, !allowed.contains(anchor) { self.anchor = nil }
        if let focus, !allowed.contains(focus) { self.focus = nil }
        if items.count < 2 { items = [] }
    }
    package mutating func select(_ item: SidebarItemReference, order: [SidebarItemReference],
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
        if proposed.count > 1, let active, order.contains(active) { proposed.append(active) }
        let selected = Set(proposed)
        items = order.filter { selected.contains($0) }
        singleItem = items.count == 1 ? items.first : (items.isEmpty ? visibleActive : nil)
        if items.count < 2 { items = [] }
        focus = item
    }
    package mutating func reconcile(order: [SidebarItemReference], active: SidebarItemReference?) {
        reconcile(order: order)
        guard !items.isEmpty, let active, order.contains(active), !items.contains(active) else { return }
        var seen = Set<SidebarItemReference>()
        let chosen = Set(items + [active])
        items = order.filter { chosen.contains($0) && seen.insert($0).inserted }
    }
    package func shown(active: SidebarItemReference?) -> [SidebarItemReference] {
        if !items.isEmpty { return items }
        return [singleItem ?? active].compactMap { $0 }
    }
    @discardableResult
    package mutating func assign(_ requested: [SidebarItemReference], order: [SidebarItemReference],
                         active: SidebarItemReference?) -> Bool {
        var seen = Set<SidebarItemReference>()
        let visible = order.filter { seen.insert($0).inserted }
        let wanted = Set(requested)
        let picked = visible.filter(wanted.contains)
        guard !picked.isEmpty || requested.isEmpty else { return false }
        let visibleActive = active.flatMap { visible.contains($0) ? $0 : nil }
        let previous = Set(items.isEmpty ? [singleItem ?? visibleActive].compactMap { $0 } : items)
        reconcile(order: visible)
        guard picked.count > 1 else {
            guard let item = picked.first else {
                if !items.isEmpty || (singleItem != nil && singleItem != visibleActive) { clear() }
                return true
            }
            items = []; singleItem = item; anchor = item; focus = item
            return true
        }
        let chosen = wanted.union([visibleActive].compactMap { $0 })
        items = visible.filter(chosen.contains)
        singleItem = nil
        focus = picked.last { !previous.contains($0) } ?? focus.flatMap { chosen.contains($0) ? $0 : nil } ?? picked.last
        anchor = focus
        return true
    }
}

extension SidebarHierarchy {
    package static func roots(_ items: [SidebarItemReference], state: BrowserState, spaceID: UUID) -> [SidebarItemReference]? {
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
    package static func moving(_ items: [SidebarItemReference], to destination: SidebarContainerLocation,
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

package enum BrowserInternalURL {
    package static func publicString(_ input: String) -> String {
        guard var value = URLComponents(string: input),
              value.scheme?.lowercased() == "chrome", value.host?.isEmpty == false,
              !["easel", "note"].contains(value.host?.lowercased() ?? "") else { return input }
        value.scheme = "parc"
        return value.string ?? input
    }
    package static func isWebUI(_ url: URL) -> Bool {
        ["parc", "chrome"].contains(url.scheme?.lowercased() ?? "") &&
            url.host?.isEmpty == false && !InternalPage.isInternal(url.absoluteString)
    }
}

package enum InternalPage: Equatable {
    case easel(UUID), note(URL)
    package init?(urlString: String) {
        if let file = Self.noteFile(urlString) { self = .note(file); return }
        guard let value = URLComponents(string: urlString), value.scheme?.lowercased() == "parc",
              value.host?.lowercased() == "easel", value.user == nil, value.password == nil,
              value.port == nil, value.query == nil, value.fragment.map({ UUID(uuidString: $0) != nil }) ?? true,
              value.path.hasPrefix("/"), let id = UUID(uuidString: String(value.path.dropFirst())) else { return nil }
        self = .easel(id)
    }
    package static func noteFile(_ input: String) -> URL? {
        URL(string: input).flatMap(noteFile)
    }
    package static func noteFile(_ url: URL) -> URL? {
        guard url.isFileURL, NoteFileKind(url: url) != nil, url.user == nil, url.port == nil,
              [nil, "", "localhost"].contains(url.host?.lowercased()) else { return nil }
        let path = url.standardizedFileURL.path
        guard path.hasPrefix("/"), path.count > 1 else { return nil }
        return URL(fileURLWithPath: path, isDirectory: false)
    }
    package static func == (lhs: InternalPage, rhs: InternalPage) -> Bool {
        switch (lhs, rhs) {
        case let (.easel(left), .easel(right)): return left == right
        case let (.note(left), .note(right)): return NoteFilePaths.sameItem(noteFile(left) ?? left, noteFile(right) ?? right)
        default: return false
        }
    }
    package var urlString: String {
        switch self {
        case .easel(let id): return "parc://easel/" + id.uuidString.lowercased()
        case .note(let url): return (Self.noteFile(url) ?? url).absoluteString
        }
    }
    package var easelID: UUID? { if case let .easel(id) = self { return id }; return nil }
    package var noteURL: URL? { if case let .note(url) = self { return Self.noteFile(url) ?? url }; return nil }
    package var canonical: InternalPage {
        guard let url = noteURL else { return self }
        return .note(NoteFilePaths.canonical(url))
    }
    package func matcher() -> (String) -> Bool {
        guard let url = noteURL else { return { InternalPage(urlString: $0) == self } }
        let identity = NoteFileIdentity(url)
        return { InternalPage(urlString: $0)?.noteURL.map(identity.matches) ?? false }
    }
    package var untitledTitle: String { noteURL != nil ? "Untitled" : "Untitled Easel" }
    package static let noteFallbackSymbol = "parc.note"
    package static let easelFallbackSymbol = "parc.easel"
    package var sidebarFallbackSymbol: String {
        switch self {
        case .note: return Self.noteFallbackSymbol
        case .easel: return Self.easelFallbackSymbol
        }
    }
    package static func sidebarFallbackSymbol(urlString: String) -> String {
        InternalPage(urlString: urlString)?.sidebarFallbackSymbol ?? "globe"
    }
    package static func isInternal(_ input: String) -> Bool {
        if noteFile(input) != nil { return true }
        guard let value = URLComponents(string: input) else { return false }
        return value.scheme?.lowercased() == "parc" && ["easel", "note"].contains(value.host?.lowercased() ?? "")
    }
    package static func isRetiredNoteAddress(_ input: String) -> Bool {
        guard let value = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return value.scheme?.lowercased() == "parc" && value.host?.lowercased() == "note"
    }
    package static func noteTitle(_ title: String, file: URL) -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let stem = file.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return stem.isEmpty ? "Untitled" : stem
    }
}

package enum WhatsNewPage {
    package static let address = "parc://whats-new/"

    package static func address(range: String?) -> String { address + (range.map { "#" + $0 } ?? "") }

    package static func isBundledFile(_ address: String, running: URL = Bundle.main.bundleURL) -> Bool {
        guard let url = URL(string: address), url.isFileURL else { return false }
        let file = url.standardizedFileURL
        guard file.pathComponents.suffix(3) == ["Contents", "Resources", "WhatsNew.html"] else { return false }
        let app = file.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return app.path == running.standardizedFileURL.path || Bundle(url: app)?.bundleIdentifier == "org.parc.Browser"
    }

    package static func relocated(_ address: String, running: URL = Bundle.main.bundleURL) -> String {
        guard isBundledFile(address, running: running), let url = URL(string: address) else { return address }
        return Self.address(range: url.fragment)
    }
}

package enum NavigationInput {
    package static func resolve(_ input: String, searchEngine: String = "https://duckduckgo.com/?q=") -> URL? {
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

package struct SpaceThemeChange: Equatable {
    package let spaceID: UUID
    package let profileID: UUID
    package let previousTheme: SpaceTheme
    package let theme: SpaceTheme
    package var actionName: String { "Update Theme" }

    package init(spaceID: UUID, profileID: UUID, previousTheme: SpaceTheme, theme: SpaceTheme) {
        self.spaceID = spaceID
        self.profileID = profileID
        self.previousTheme = previousTheme
        self.theme = theme
    }

    package func target(in state: BrowserState, undo: Bool) -> BrowserSpace? {
        guard state.profiles.contains(where: { $0.id == profileID }) else { return nil }
        return state.spaces.first {
            $0.id == spaceID && $0.profileID == profileID && $0.theme == (undo ? theme : previousTheme)
        }
    }
}

@MainActor
package final class BrowserStore: ObservableObject {
    @Published private var publishedState: BrowserState = .initial() {
        didSet { stateRevision &+= 1 }
    }
    private var activityOnlyState: BrowserState?
    package private(set) var state: BrowserState {
        get { activityOnlyState ?? publishedState }
        set {
            let current = activityOnlyState ?? publishedState
            guard newValue != current else { return }
            activityOnlyState = nil
            publishedState = newValue.attachingTabLookup(after: current)
            if !themePreviews.isEmpty {
                themePreviews = themePreviews.filter { id, entry in
                    newValue.spaces.contains { $0.id == id && $0.theme == entry.preview }
                }
            }
        }
    }
    private var themePreviews: [UUID: (saved: SpaceTheme, preview: SpaceTheme)] = [:]
    package var statePublisher: Published<BrowserState>.Publisher { $publishedState }
    package private(set) var stateRevision: UInt64 = 0
    package private(set) var historyRevision: UInt64 = 0
    package private(set) var historyRemovalRevision: UInt64 = 0
    private var historyRemovalLog: [(revision: UInt64, profileID: UUID, urls: Set<String>?)] = []
    private static let historyRemovalLogLimit = 32
    private static let historyRemovalURLLimit = 1_000
    @Published package private(set) var persistenceError: String?
    @Published package private(set) var autoArchiveEducationPending = false
    @Published package private(set) var transientDownloads: [BrowserDownload] = []
    package var downloadItems: [BrowserDownload] {
        let profiles = Set(state.profiles.map(\.id))
        return state.downloads + transientDownloads.filter { $0.profileID.map(profiles.contains) == true }
    }
    package var downloadState: BrowserState {
        var snapshot = state; snapshot.downloads = downloadItems; return snapshot
    }
    package lazy var linkRouting = LinkRoutingStore(directory: directory)
    package let directory: URL
    package let privateParentProfileID: UUID?
    private let privateEnginePath: String?
    package var isEphemeral: Bool { privateEnginePath != nil }
    private let clock: () -> Date
    private var pendingSave: DispatchWorkItem?
    package var scheduleDeferredSave: (TimeInterval, DispatchWorkItem) -> Void = { delay, task in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }
    private var pendingSaveSnapshot: BrowserState?
    private let sessionWriter = SessionFileWriter()
    package var closedPageHistory = ClosedPageHistory<AnyObject>()
    package let placeholderImages = PagePlaceholderImages()
    package lazy var tabHistory: TabHistoryArchive? = isEphemeral ? nil
        : TabHistoryArchive(directory: directory.appendingPathComponent("Tab History", isDirectory: true))
    package private(set) var windowRecords: [BrowserWindowRecord] = []
    package var requestPageRetirement: ((Set<UUID>, @escaping () -> Bool, @escaping (Bool) -> Void) -> Void)?
    package var sidebarBannerOccupied: () -> Bool = { false }
    private var profileWriteReservations: [UUID: UUID] = [:]
    package func reserveProfileWrite(_ profileID: UUID) -> ProfileWriteReservation? {
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
    package var retiringTabIDs: Set<UUID> { Set(retirementRequests.keys).union(exclusiveRetirementIDs) }
    private var stateURL: URL { directory.appendingPathComponent("session.json") }

    package init(directory: URL, now: @escaping () -> Date = Date.init, keepsBackups: Bool = false) throws {
        self.directory = directory
        privateParentProfileID = nil; privateEnginePath = nil
        self.clock = now
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        if keepsBackups { sessionWriter.keepBackups(SessionBackups(directory: directory)) }
        let file = directory.appendingPathComponent("session.json")
        if FileManager.default.fileExists(atPath: file.path) {
            let bytes: Data
            var decoded: BrowserState
            do {
                bytes = try Data(contentsOf: file)
                decoded = try Self.savedSession(from: bytes)
            } catch {
                throw SessionFileUnreadable(underlying: error)
            }
            windowRecords = decoded.windows; decoded.windows = []
            let historyFile = directory.appendingPathComponent(BrowserHistoryFile.name)
            if FileManager.default.fileExists(atPath: historyFile.path) {
                let bytes = try? Data(contentsOf: historyFile)
                let saved = bytes.map(BrowserHistoryFile.decode) ?? []
                if bytes == nil || (saved.isEmpty && bytes?.isEmpty == false) { sessionWriter.preserveHistoryFile() }
                let filed = Set(saved.map(\.id))
                var merged = saved + decoded.history.filter { !filed.contains($0.id) }
                if merged.count > BrowserHistoryOrder.capacity {
                    merged.removeFirst(merged.count - BrowserHistoryOrder.capacity)
                }
                decoded.history = merged
            }
            let legacyLayouts = (try? JSONSerialization.jsonObject(with: bytes) as? [String: Any])?["splitLayouts"] as? [[String: Any]]
            let needsGroupIdentityMigration = legacyLayouts?.contains { $0["id"] == nil || $0["sidebarAnchorID"] == nil } == true
            var loaded = decoded
            for i in loaded.tabs.indices {
                loaded.tabs[i].url = BrowserInternalURL.publicString(WhatsNewPage.relocated(loaded.tabs[i].url))
                loaded.tabs[i].savedURL = BrowserInternalURL.publicString(WhatsNewPage.relocated(loaded.tabs[i].savedURL))
            }
            for i in loaded.history.indices {
                loaded.history[i].url = BrowserInternalURL.publicString(loaded.history[i].url)
            }
            state = loaded
            _ = state.upgradeSpaceSharing()
            let legacyFallback = defaultProfileID
            for index in state.profileRemovals.indices where state.profileRemovals[index].fallbackProfileID == nil {
                state.profileRemovals[index].fallbackProfileID = legacyFallback
            }
            if state.settings.restoreSession {
                normalizeSelection()
                state = SplitMembership.resolvingSharedLegacyFavorites(state)
                reconcileSplitLayouts()
                migrateLegacySplitContainers()
                if needsGroupIdentityMigration || state != decoded { try save() }
            } else {
                beginFreshSession()
                state = SplitMembership.resolvingSharedLegacyFavorites(state)
                reconcileSplitLayouts()
                migrateLegacySplitContainers()
                if state != decoded { try save() }
            }
            linkRouting.convertProfileDestinations(spaces: state.spaces.map { LinkRoutingSpace(id: $0.id, profileID: $0.profileID) })
            if keepsBackups { sessionWriter.backUpIfDue(persisted(state), at: clock()) }
        } else {
            state = .initial()
        }
    }

    package init(privateParentProfileID: UUID, engineProfilePath: String, directory: URL,
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

    package var activeSpaceID: UUID { state.activeSpaceID }
    package var activeSpace: BrowserSpace { state.spaces.first { $0.id == activeSpaceID } ?? state.spaces[0] }
    package var selectedTabID: UUID? { state.selectedTabIDs.first }
    package var activeSplitLayout: BrowserSplitLayout? {
        SidebarSplitItems.groups(in: state, spaceID: activeSpaceID).first { $0.tabIDs == state.selectedTabIDs }
    }
    package var visibleTabs: [BrowserTab] { state.openTabs(where: { ($0.kind == .favorite ? $0.profileID == activeSpace.profileID : $0.spaceID == activeSpaceID) }) }
    package var favorites: [BrowserTab] { visibleTabs.filter { $0.kind == .favorite } }
    package var pinnedTabs: [BrowserTab] { visibleTabs.filter { $0.kind == .pinned } }
    package var todayTabs: [BrowserTab] { visibleTabs.filter { $0.kind == .today } }
    package var folders: [BrowserFolder] { state.folders.filter { $0.spaceID == activeSpaceID } }
    package var archivedTabs: [BrowserTab] { state.archivedTabs(where: { $0.profileID == activeSpace.profileID }).sorted { $0.archivedAt! > $1.archivedAt! } }

    package func archivedItems(profileID: UUID) -> [BrowserArchivedItem] {
        let tabs = state.archivedTabs(where: { $0.profileID == profileID })
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
        for tab in state.openTabs where ids.contains(tab.id) {
            result[tab.id] = ArchiveProvenance(reason: reason, spaceID: tab.spaceID,
                spaceName: state.spaces.first { $0.id == tab.spaceID }?.name ?? "Space")
        }
        for layout in state.splitLayouts where layout.tabIDs.allSatisfy({ ids.contains($0) }) {
            guard layout.tabIDs.allSatisfy({ id in state.containsTab(id, where: { $0.kind == .today && $0.archivedAt == nil }) }),
                  layout.tabIDs.allSatisfy({ result[$0]?.groupID == nil }) else { continue }
            let group = UUID()
            for id in layout.tabIDs { result[id]?.groupID = group; result[id]?.split = layout }
        }
        return result
    }

    package static let archiveRetention: TimeInterval = 60 * 24 * 60 * 60
    package func cleanExpiredArchive(now: Date? = nil) {
        let cutoff = (now ?? clock()).addingTimeInterval(-Self.archiveRetention)
        let ids = Set(state.tabs.filter { $0.archivedAt.map { $0 <= cutoff } ?? false }.map(\.id))
        deleteArchivedTabs(ids)
    }

    package func acquireArchivePreview(id: UUID, profileID: UUID) -> ArchivePreviewLease? {
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

    package func archivePreviewIsValid(_ lease: ArchivePreviewLease) -> Bool {
        guard archivePreviewLeases[lease.token] == lease, !isProfileRemovalPending(lease.profileID),
              state.profiles.contains(where: { $0.id == lease.profileID }),
              let first = lease.tabs.first,
              let current = archivedItems(profileID: lease.profileID).first(where: { $0.id == first.id }),
              current.tabs.count == lease.tabs.count else { return false }
        return zip(current.tabs, lease.tabs).allSatisfy { current, original in
            current.id == original.id && current.profileID == original.profileID
                && current.spaceID == original.spaceID && current.createdAt == original.createdAt
                && current.archivedAt == original.archivedAt
                && current.withoutFolderPlacement.archiveProvenance == original.withoutFolderPlacement.archiveProvenance
        }
    }

    package func releaseArchivePreview(_ lease: ArchivePreviewLease) {
        if archivePreviewLeases[lease.token] == lease { archivePreviewLeases.removeValue(forKey: lease.token) }
    }

    package func archivePreviewLeases(intersecting ids: Set<UUID>) -> [ArchivePreviewLease] {
        archivePreviewLeases.values.filter { !ids.isDisjoint(with: Set($0.tabs.map(\.id))) }
    }

    private func archivePreviewOverlaps(_ ids: Set<UUID>) -> Bool {
        !archivePreviewLeases(intersecting: ids).isEmpty
    }

    package func deleteArchivedTabs(_ ids: Set<UUID>, profileID: UUID? = nil, forgettingBackups: Bool = false) {
        let originals = state.archivedTabs(where: { ids.contains($0.id) && (profileID == nil || $0.profileID == profileID) })
        guard !originals.isEmpty else { return }
        let removing = Set(originals.map(\.id))
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
                return self.archivedItems(profileID: first.profileID).contains {
                    $0.tabs.map(\.withoutFolderPlacement) == tabs.map(\.withoutFolderPlacement)
                }
            }
        }
        withRetiredPages(retiring, shouldCommit: current, exclusive: true) { [weak self] in
            guard let self, current(), !self.archivePreviewOverlaps(retiring) else { return }
            var next = self.state
            next.tabs.removeAll { removing.contains($0.id) }
            next.recentlyClosedIDs.removeAll { removing.contains($0) }
            self.state = next
            self.changed()
            if forgettingBackups { self.forgetBackups(.all) }
        }
    }

    package func clearArchive(profileID: UUID) {
        let ids = Set(state.archivedTabs(where: { $0.profileID == profileID }).map(\.id))
        guard !ids.isEmpty else { forgetBackups(.all); return }
        deleteArchivedTabs(ids, profileID: profileID, forgettingBackups: true)
    }

    package func profilePath(for tab: BrowserTab) -> String {
        directory.appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(tab.profileID.uuidString, isDirectory: true).path
    }

    package var independentEngineRoot: URL {
        directory.appendingPathComponent("Chromium-v1", isDirectory: true)
    }

    package func independentEngineProfilePath(for profileID: UUID) -> String {
        if let privateEnginePath { return privateEnginePath }
        return independentEngineRoot.appendingPathComponent(profileID.uuidString, isDirectory: true).path
    }

    package func profileID(forEnginePath path: String) -> UUID? {
        let supplied = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
        return state.profiles.first {
            URL(fileURLWithPath: independentEngineProfilePath(for: $0.id), isDirectory: true).standardizedFileURL.path == supplied
        }?.id
    }

    package func adoptNativePage(url: URL?, title: String, profilePath: String,
                         preferredSpaceID: UUID, select: Bool, creation: TabCreationProvenance? = nil,
                         insertion: TodayInsertion = .automatic) -> UUID? {
        guard let profileID = profileID(forEnginePath: profilePath),
              let space = state.spaces.first(where: { $0.id == preferredSpaceID && $0.profileID == profileID })
                ?? state.spaces.first(where: { $0.profileID == profileID }) else { return nil }
        let creation = creation?.validated(profileID: profileID, state: state)
        let id = UUID()
        let destination = BrowserInternalURL.publicString(url?.absoluteString ?? "about:blank")
        let name = title.isEmpty ? (url?.host ?? "New Tab") : title
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

    @discardableResult
    package func restoreLiveTab(_ original: BrowserTab, replacing expected: BrowserTab?) -> Bool {
        guard state.tab(original.id) == expected,
              original.archivedAt == nil,
              state.profiles.contains(where: { $0.id == original.profileID }),
              state.spaces.contains(where: { $0.id == original.spaceID && $0.profileID == original.profileID }) else { return false }
        if let index = state.tabIndex(original.id) { state.tabs[index] = original }
        else { state.tabs.append(original) }
        state.recentlyClosedIDs.removeAll { $0 == original.id }
        reconcileSplitLayouts()
        changed()
        return true
    }

    package func easelsDirectory(for profileID: UUID) -> URL {
        directory.appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(profileID.uuidString, isDirectory: true)
            .appendingPathComponent("Easels", isDirectory: true)
    }
    package var activeEaselsDirectory: URL { easelsDirectory(for: activeSpace.profileID) }

    package func capturesDirectory(for profileID: UUID) -> URL {
        directory.appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(profileID.uuidString, isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
    }

    @discardableResult
    package func openNote(url: URL, title: String, inSplit: Bool = false, inBackground: Bool = false,
                  creation: TabCreationProvenance? = nil) -> UUID? {
        guard !isEphemeral, let file = InternalPage.noteFile(url), !isProfileRemovalPending(activeSpace.profileID),
              !inSplit || (!inBackground && !state.selectedTabIDs.isEmpty && state.selectedTabIDs.count < 4) else { return nil }
        let original = state.selectedTabIDs, page = InternalPage.note(file)
        let name = InternalPage.noteTitle(title, file: file)
        if let index = localDocumentTabIndex(page, profileID: activeSpace.profileID) {
            let existing = state.tabs[index]
            guard !inSplit || existing.spaceID == activeSpaceID else { return nil }
            let id = presentLocalDocument(at: index, page: page, title: name)
            if inSplit { setSplit(original + [id]) } else if inBackground { changed() } else { selectTab(id) }
            return id
        }
        let id = UUID()
        let creation = creation?.validated(profileID: activeSpace.profileID, state: state)
        var next = state
        next.tabs.append(BrowserTab(id: id, spaceID: activeSpaceID, profileID: activeSpace.profileID,
            url: page.urlString, title: name, kind: .today, createdAt: clock(), lastAccessed: clock(),
            savedURL: page.urlString, savedTitle: name, referrerID: creation?.referrerID,
            activeTabBeforeCreationID: creation?.activeTabBeforeCreationID))
        if inSplit {
            state = next
            setSplit(original + [id], adding: id)
        } else if inBackground {
            SidebarHierarchy.placingCreatedTab(id, insertion: .automatic, in: &next)
            state = next
            changed()
        } else {
            SidebarHierarchy.placingCreatedTab(id, insertion: .automatic, in: &next)
            next.selectedTabIDs = [id]
            next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
            state = next
            changed(selectionAlreadyStamped: true)
        }
        return id
    }
    @discardableResult
    package func openDocumentOverPage(_ id: UUID, page: InternalPage, title: String,
                              history: TabNoteVisit.PageHistory? = nil) -> Bool {
        guard !isEphemeral, !retiringTabIDs.contains(id), let index = state.tabIndex(id, where: { $0.archivedAt == nil }),
              !isProfileRemovalPending(state.tabs[index].profileID) else { return false }
        var next = state
        guard next.tabs[index].openDocumentVisit(page, title: title, history: history) else { return false }
        next.tabs[index].lastAccessed = clock()
        state = next
        changed()
        return true
    }

    @discardableResult
    package func stepNoteVisit(_ id: UUID, forward: Bool) -> Bool {
        stepNoteVisit(id, by: forward ? 1 : -1)
    }

    @discardableResult
    package func stepNoteVisit(_ id: UUID, by offset: Int) -> Bool {
        guard !retiringTabIDs.contains(id), let index = state.tabIndex(id, where: { $0.archivedAt == nil }) else { return false }
        var next = state
        guard next.tabs[index].stepNoteVisit(by: offset) else { return false }
        next.tabs[index].lastAccessed = clock()
        state = next
        changed()
        return true
    }

    package func updatePageUnderNote(_ id: UUID, title: String? = nil, url: String? = nil) {
        guard let index = state.tabIndex(id) else { return }
        var next = state
        guard next.tabs[index].followPageUnderNote(url: url, title: title) else { return }
        state = next
        changed()
    }

    package func syncPageHistory(_ id: UUID, history: TabNoteVisit.PageHistory) {
        guard let index = state.tabIndex(id, where: { $0.archivedAt == nil }), state.tabs[index].noteVisit != nil else { return }
        var next = state
        guard next.tabs[index].syncPageHistory(history) else { return }
        state = next
        changed()
    }

    package func updateNoteFile(from old: URL, to new: URL, title: String) {
        guard let source = InternalPage.noteFile(old), let destination = InternalPage.noteFile(new) else { return }
        let from = InternalPage.note(source).matcher(), to = InternalPage.note(destination).canonical
        let name = InternalPage.noteTitle(title, file: destination)
        var next = state, didChange = false
        for index in next.tabs.indices {
            if next.tabs[index].followNoteRename(from: from, to: to.urlString, title: name) { didChange = true }
            if from(next.tabs[index].url) {
                if next.tabs[index].url != to.urlString { next.tabs[index].url = to.urlString; didChange = true }
                if next.tabs[index].title != name { next.tabs[index].title = name; didChange = true }
            }
            if from(next.tabs[index].savedURL) {
                if next.tabs[index].savedURL != to.urlString { next.tabs[index].savedURL = to.urlString; didChange = true }
                if next.tabs[index].savedTitle != name { next.tabs[index].savedTitle = name; didChange = true }
            }
        }
        if didChange { state = next; changed() }
    }
    package func deleteLocalDocument(_ page: InternalPage, profileID: UUID,
                             ownerValid: @escaping () -> Bool,
                             deleteDocument: (() throws -> Void)? = nil,
                             completion: @escaping (Error?) -> Void) {
        let file = page.noteURL, names = page.matcher()
        func references(_ tab: BrowserTab) -> Bool {
            tab.noteVisit == nil && (file != nil || tab.profileID == profileID) && (names(tab.url) || names(tab.savedURL))
        }
        func owners(_ state: BrowserState) -> [UUID] {
            file == nil ? [profileID] : state.profiles.map(\.id).filter { owner in state.tabs.contains { $0.profileID == owner && references($0) } }
        }
        let profiles = owners(state)
        guard !isEphemeral, state.profiles.contains(where: { $0.id == profileID }),
              !isProfileRemovalPending(profileID), !profiles.contains(where: isProfileRemovalPending) else {
            completion(CocoaError(.userCancelled)); return
        }
        let originals = state.tabs.filter(references)
        let ids = Set(originals.map(\.id))
        let archiveGroups = profiles.flatMap { archivedItems(profileID: $0) }.filter { !ids.isDisjoint(with: Set($0.tabs.map(\.id))) }.map(\.tabs)
        let retiring = ids.union(archiveGroups.flatMap { $0.map(\.id) })
        guard retiring.isDisjoint(with: retiringTabIDs) else { completion(CocoaError(.userCancelled)); return }
        let removeDocument = deleteDocument ?? { if let file { try FileManager.default.trashItem(at: file, resultingItemURL: nil) } }
        func current() -> Bool {
            ownerValid() && !self.isProfileRemovalPending(profileID)
                && self.state.profiles.contains(where: { $0.id == profileID })
                && owners(self.state) == profiles && !profiles.contains(where: self.isProfileRemovalPending)
                && self.state.tabs.filter(references)
                    .map(\.archivedWithoutFolderPlacement) == originals.map(\.archivedWithoutFolderPlacement)
                && archiveGroups.allSatisfy { group in profiles.flatMap { self.archivedItems(profileID: $0) }.contains {
                    $0.tabs.map(\.withoutFolderPlacement) == group.map(\.withoutFolderPlacement)
                } }
        }
        withRetiredPages(retiring, shouldCommit: current, onRefusal: { completion(CocoaError(.userCancelled)) }, exclusive: true) { [weak self] in
            guard let self, current(), !self.archivePreviewOverlaps(retiring) else { completion(CocoaError(.userCancelled)); return }
            do {
                var next = self.state
                next.tabs.removeAll { ids.contains($0.id) }; next.selectedTabIDs.removeAll { ids.contains($0) }
                for index in next.tabs.indices where file != nil || next.tabs[index].profileID == profileID {
                    next.tabs[index].forgetNote(matching: names)
                }
                next.recentlyClosedIDs.removeAll { ids.contains($0) }
                next.splitLayouts = next.splitLayouts.compactMap { original in
                    var layout = original
                    let positions = layout.tabIDs.indices.filter { !ids.contains(layout.tabIDs[$0]) }
                    let weights = positions.map { layout.widthFactors[$0] }
                    guard let factors = BrowserSplitLayout.normalized(weights, count: positions.count) else { return nil }
                    layout.tabIDs = positions.map { original.tabIDs[$0] }; layout.widthFactors = factors
                    layout.restack(from: original)
                    if layout.sidebarAnchorID.map({ layout.tabIDs.contains($0) }) != true { layout.sidebarAnchorID = layout.tabIDs.first }
                    return layout
                }
                try self.commitProfileSettings(next)
                try removeDocument(); completion(nil)
            } catch { completion(error) }
        }
    }

    @discardableResult
    package func openEasel(id documentID: UUID, title: String, inSplit: Bool = false, inBackground: Bool = false,
                   creation: TabCreationProvenance? = nil) -> UUID? {
        guard !inSplit || (!isEphemeral && !isProfileRemovalPending(activeSpace.profileID) && !inBackground
              && !state.selectedTabIDs.isEmpty && state.selectedTabIDs.count < 4) else { return nil }
        let original = state.selectedTabIDs, page = InternalPage.easel(documentID)
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = name.isEmpty ? "Untitled Easel" : name
        if let index = localDocumentTabIndex(page, profileID: activeSpace.profileID) {
            let existing = state.tabs[index]
            guard !inSplit || existing.spaceID == activeSpaceID else { return nil }
            let id = presentLocalDocument(at: index, page: page, title: title)
            if inSplit { setSplit(original + [id]) } else if inBackground { changed() } else { selectTab(id) }
            return id
        }
        let id = UUID()
        let creation = creation?.validated(profileID: activeSpace.profileID, state: state)
        var next = state
        next.tabs.append(BrowserTab(id: id, spaceID: activeSpaceID, profileID: activeSpace.profileID,
                                     url: page.urlString, title: title, kind: .today,
                                     createdAt: clock(), lastAccessed: clock(),
                                     savedURL: page.urlString, savedTitle: title, referrerID: creation?.referrerID,
                                     activeTabBeforeCreationID: creation?.activeTabBeforeCreationID))
        if inSplit {
            state = next
            setSplit(original + [id], adding: id)
        } else if inBackground {
            SidebarHierarchy.placingCreatedTab(id, insertion: .automatic, in: &next)
            state = next
            changed()
        } else {
            SidebarHierarchy.placingCreatedTab(id, insertion: .automatic, in: &next)
            next.selectedTabIDs = [id]
            next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
            state = next
            changed(selectionAlreadyStamped: true)
        }
        return id
    }

    private func localDocumentTabIndex(_ page: InternalPage, profileID: UUID) -> Int? {
        let names = page.matcher()
        let matches = state.tabs.indices.filter { index in
            let tab = state.tabs[index]
            return tab.profileID == profileID && tab.noteVisit == nil
                && !retiringTabIDs.contains(tab.id)
                && !archivePreviewOverlaps([tab.id])
                && (names(tab.url) || names(tab.savedURL))
        }
        return matches.first { state.tabs[$0].archivedAt == nil } ?? matches.first
    }

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

    package func updateEaselTitle(id documentID: UUID, profileID: UUID, title: String) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var didChange = false
        let page = InternalPage.easel(documentID)
        for index in state.tabs.indices where state.tabs[index].profileID == profileID {
            if state.tabs[index].followNoteRename(from: page.matcher(), to: page.urlString, title: name) { didChange = true }
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
    package func open(_ input: String, kind: TabKind = .today, creation: TabCreationProvenance? = nil) -> UUID {
        let resolved = NavigationInput.resolve(input, searchEngine: state.settings.searchEngine) ?? URL(string: "about:blank")!
        return openResolvedURL(resolved, kind: kind, creation: creation)
    }

    @discardableResult
    package func openResolvedURL(_ url: URL, id: UUID = UUID(), kind: TabKind = .today, creation: TabCreationProvenance? = nil) -> UUID {
        let creation = creation?.validated(profileID: activeSpace.profileID, state: state)
        let resolved = BrowserInternalURL.publicString(url.absoluteString)
        let title = url.isFileURL ? url.lastPathComponent : url.host ?? "New Tab"
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

    @discardableResult
    package func insertCommandBarBackground(tabID: UUID, url: URL, spaceID: UUID,
                                    profileID: UUID, expectedSelection: [UUID], creation: TabCreationProvenance? = nil) -> Bool {
        guard activeSpaceID == spaceID, activeSpace.profileID == profileID,
              state.selectedTabIDs == expectedSelection, !isProfileRemovalPending(profileID),
              !state.containsTab(tabID),
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

    @discardableResult
    package func commandBarSplitHomes(after focusedID: UUID, expectedSelection: [UUID], tabID: UUID, isNew: Bool) -> [BrowserTab]? {
        guard let index = expectedSelection.firstIndex(of: focusedID), expectedSelection.count < 4,
              !expectedSelection.contains(tabID) else { return nil }
        var ids = expectedSelection
        let previous = activeSplitLayout.flatMap { $0.tabIDs == expectedSelection ? $0 : nil }
        ids.insert(tabID, at: previous?.mainRowInsertionIndex(after: focusedID) ?? index + 1)
        return SplitMembership.savedHomeSources(joining: ids, existing: previous, added: isNew ? tabID : nil, state: state)
    }

    package func insertCommandBarSplit(after focusedID: UUID, expectedSelection: [UUID],
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
        var savedHomeIDs = savedHomeIDs, validatedBeforeMove = false
        if newURL == nil, let foreign = state.tab(tabID, where: { $0.archivedAt == nil
            && $0.kind != .favorite && $0.profileID == activeSpace.profileID && $0.spaceID != activeSpaceID }) {
            if let documents {
                let previous = activeSplitLayout.flatMap { $0.tabIDs == expectedSelection ? $0 : nil }
                var planned = expectedSelection
                planned.insert(tabID, at: previous?.mainRowInsertionIndex(after: focusedID) ?? index + 1)
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
            guard !state.containsTab(tabID) else { return false }
            let title = url.host ?? "New Tab", resolved = BrowserInternalURL.publicString(url.absoluteString)
            next.tabs.append(BrowserTab(id: tabID, spaceID: activeSpaceID,
                profileID: activeSpace.profileID, url: resolved, title: title, kind: .today,
                createdAt: clock(), lastAccessed: clock(), savedURL: resolved, savedTitle: title,
                referrerID: creation?.referrerID, activeTabBeforeCreationID: creation?.activeTabBeforeCreationID))
            SidebarHierarchy.placingCreatedTab(tabID, insertion: .automatic, in: &next)
        } else {
            guard next.containsTab(tabID, where: { $0.archivedAt == nil
                && ($0.kind == .favorite ? $0.profileID == activeSpace.profileID : $0.spaceID == activeSpaceID) }) else { return false }
        }
        var ids = expectedSelection
        let previous = activeSplitLayout.flatMap { $0.tabIDs == expectedSelection ? $0 : nil }
        ids.insert(tabID, at: previous?.mainRowInsertionIndex(after: focusedID) ?? index + 1)
        let factors = ids.map { id in
            previous.flatMap { layout in
                layout.tabIDs.firstIndex(of: id).map { layout.widthFactors[$0] }
            } ?? (1.0 / Double(expectedSelection.count))
        }
        var group = BrowserSplitLayout(id: previous?.id ?? UUID(), sidebarAnchorID: previous?.sidebarAnchorID, customTitle: previous?.customTitle, customIcon: previous?.customIcon,
            spaceID: previous?.spaceID ?? activeSpaceID, tabIDs: ids, orientation: previous?.orientation ?? .horizontal,
            widthFactors: BrowserSplitLayout.normalized(factors, count: ids.count)!, stacks: nil)
        if let previous { group.restack(from: previous) }
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
        next.splitLayouts = Self.reconciledSplitLayouts(in: next, activeSpaceID: activeSpaceID)
        state = next
        changed(selectionAlreadyStamped: true)
        return true
    }

    package func commitFavoriteSplit(_ request: FavoriteSplitRequest) throws -> UUID? {
        guard !isEphemeral, let next = request.applying(to: state, retiring: retiringTabIDs, now: clock()) else { return nil }
        try commitProfileSettings(next)
        return request.targetID
    }

    package func navigate(_ id: UUID, input: String) {
        guard let url = NavigationInput.resolve(input, searchEngine: state.settings.searchEngine) else { return }
        guard let tab = state.tab(id) else { return }
        if !InternalPage.isInternal(tab.url), InternalPage.isInternal(url.absoluteString) {
            withRetiredPages([id]) { [weak self] in self?.updateTab(id, url: url.absoluteString) }
        } else { updateTab(id, url: url.absoluteString) }
    }

    package func updateTab(_ id: UUID, title: String? = nil, url: String? = nil) {
        guard let index = state.tabIndex(id) else { return }
        let current = state.tabs[index]
        let nextTitle = title.flatMap { $0.isEmpty ? nil : $0 } ?? current.title
        let nextURL = url.map(BrowserInternalURL.publicString) ?? current.url
        let nextSavedURL = current.kind == .today ? nextURL : current.savedURL
        let nextSavedTitle = current.kind == .today ? nextTitle : current.savedTitle
        var historyTitle: String?
        var appendHistory = false
        let nextVisit = Self.followingNoteVisit(current, url: url == nil ? nil : nextURL, title: nextTitle)
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
           historyTitle == nil, !appendHistory, nextVisit == current.noteVisit {
            return
        }
        var next = state
        next.tabs[index].noteVisit = nextVisit
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

    private static func followingNoteVisit(_ tab: BrowserTab, url: String?, title: String) -> TabNoteVisit? {
        guard var visit = tab.noteVisit else { return nil }
        if let url, url != tab.url {
            guard visit.tracksPageHistory, !InternalPage.isInternal(url) else { return nil }
            if visit.showsNote { return InternalPage.isInternal(tab.url) && visit.leave() ? visit : nil }
            return visit
        }
        if visit.shownPage != nil, !InternalPage.isInternal(tab.url) { visit.syncShown(url: tab.url, title: title) }
        return visit
    }

    package func splitExtensionHomes(_ id: UUID) -> [BrowserTab] {
        guard !state.selectedTabIDs.contains(id), state.selectedTabIDs.count < 4 else { return [] }
        let ids = state.selectedTabIDs + [id]
        let previous = activeSplitLayout.flatMap { old in ids.contains(where: { old.tabIDs.contains($0) }) ? old : nil }
        return SplitMembership.savedHomeSources(joining: ids, existing: previous, added: nil, state: state)
    }

    package func selectTab(_ id: UUID, extendingSplit: Bool = false, savedHomeIDs: [UUID: UUID] = [:],
                   documents: [UUID: SidebarDocumentReference]? = nil) {
        guard let index = state.tabIndex(id, where: { $0.archivedAt == nil }) else { return }
        if extendingSplit, let documents, !SidebarDocumentReference.validates(splitExtensionHomes(id), references: documents) { return }
        let tab = state.tabs[index]
        if tab.kind != .favorite && tab.spaceID != activeSpaceID { selectSpace(tab.spaceID) }
        if tab.profileID != activeSpace.profileID {
            guard let compatible = state.spaces.first(where: { $0.profileID == tab.profileID }) else { return }
            selectSpace(compatible.id)
        }
        guard let index = state.tabIndex(id, where: { $0.archivedAt == nil }) else { return }
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

    package func selectSpace(_ id: UUID) {
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

    @discardableResult
    package func setWindowPresentation(spaceID: UUID, selectedTabIDs: [UUID],
                               splitLayout: BrowserSplitLayout? = nil) -> Bool {
        guard let space = state.spaces.first(where: { $0.id == spaceID }) else { return false }
        let available = Set(state.openTabs(where: { $0.profileID == space.profileID && ($0.kind == .favorite || $0.spaceID == spaceID) }).map(\.id))
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
            layout.stacks = layout.stacks?.validated(paneCount: selected.count)
            if let stacks = layout.stacks { layout.widthFactors = stacks.flattenedFactors }
            if let original = SidebarSplitItems.groups(in: state, spaceID: spaceID).first(where: { $0.id == layout.id && $0.tabIDs == selected }) {
                layout.customTitle = original.customTitle
                layout.customIcon = original.customIcon
                layout.spaceID = original.spaceID
                next.splitLayouts.removeAll { $0.id == original.id }
                next.splitLayouts.append(layout)
            } else {
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

    package func closeTab(_ id: UUID) {
        closeTabs([id])
    }

    package func closeTabs(_ ids: Set<UUID>, reason: ArchiveReason = .manual, completion: ((Bool) -> Void)? = nil) {
        closeTabs(ids, reason: reason, shouldCommit: { true }, completion: completion)
    }

    package func closeTabs(_ ids: Set<UUID>, reason: ArchiveReason = .manual,
                   selection: FolderRemovalSelection? = nil,
                   didCommit: ((BrowserState) -> Void)? = nil,
                   shouldCommit: @escaping () -> Bool, completion: ((Bool) -> Void)? = nil) {
        let liveIDs = Set(state.openTabs(where: { ids.contains($0.id) }).map(\.id))
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
        let closing = state.openTabs(where: { ids.contains($0.id) }).map(\.id)
        guard !closing.isEmpty else { return }
        let provenance = archiveProvenance(for: Set(closing), reason: reason)
        var next = state
        let oldVisible = visibleTabs.map(\.id)
        let now = clock()
        let retainedSavedGroups = Set(state.splitLayouts.filter { group in
            !isEphemeral && group.tabIDs.allSatisfy { id in
                ids.contains(id) && state.containsTab(id, where: { $0.kind != .today && $0.archivedAt == nil })
            }
        }.map(\.id))
        let displayedGroupID = SidebarSplitItems.groups(in: state, spaceID: activeSpaceID)
            .first { $0.tabIDs == state.selectedTabIDs }?.id
        for id in closing {
            tabHistory?.remove(id)
            guard let index = next.tabIndex(id) else { continue }
            if let layoutIndex = next.splitLayouts.firstIndex(where: { $0.id == displayedGroupID && $0.tabIDs == next.selectedTabIDs && !retainedSavedGroups.contains($0.id) }),
               let pane = next.splitLayouts[layoutIndex].tabIDs.firstIndex(of: id) {
                var layout = next.splitLayouts.remove(at: layoutIndex)
                layout.removePane(at: pane)
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
                next.tabs[index].url = next.tabs[index].savedURL
                next.tabs[index].title = next.tabs[index].savedTitle
            }
            next.selectedTabIDs.removeAll { $0 == id }
        }
        for index in next.splitLayouts.indices where !retainedSavedGroups.contains(next.splitLayouts[index].id) {
            var layout = next.splitLayouts[index]
            guard state.splitLayouts.contains(where: { $0.id == layout.id && !Set($0.tabIDs).isDisjoint(with: closing) }) else { continue }
            if layout.widthFactors.count == layout.tabIDs.count {
                for pane in layout.tabIDs.indices.reversed() where closing.contains(layout.tabIDs[pane])
                    && !next.containsTab(layout.tabIDs[pane], where: { $0.archivedAt == nil }) {
                    layout.removePane(at: pane)
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
            let available = Set(next.openTabs(where: { ($0.kind == .favorite
                ? $0.profileID == activeSpace.profileID : $0.spaceID == activeSpaceID) }).map(\.id))
            next.selectedTabIDs = Array(candidates.filter { available.contains($0) && !ids.contains($0) }.prefix(1))
        }
        let selectedProfile = next.spaces.first { $0.id == next.activeSpaceID }?.profileID
        let available = Set(next.openTabs(where: { ($0.kind == .favorite
            ? $0.profileID == selectedProfile : $0.spaceID == next.activeSpaceID) }).map(\.id))
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
        SplitMembership.preservingSlots(before: state, after: &next)
        state = next
        changed(selectionAlreadyStamped: selection != nil)
    }

    package func removeTab(_ id: UUID) {
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

    @discardableResult
    package func restoreClosedItem(_ record: ClosedItemRecord,
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
            next.splitLayouts.append(split)
        }
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
    package func restoreArchivedTab(_ id: UUID, profileID requestedProfile: UUID? = nil,
                            destination target: ArchiveRestoreDestination) -> [UUID] {
        restoreArchivedTab(id, profileID: requestedProfile, destination: target, preview: nil)
    }

    package func restoreArchivePreview(_ lease: ArchivePreviewLease, destination: ArchiveRestoreDestination) -> [UUID] {
        guard archivePreviewIsValid(lease), let first = lease.tabs.first else { return [] }
        return restoreArchivedTab(first.id, profileID: lease.profileID, destination: destination, preview: lease)
    }

    private func restoreArchivedTab(_ id: UUID, profileID requestedProfile: UUID?,
                                    destination target: ArchiveRestoreDestination, preview: ArchivePreviewLease?) -> [UUID] {
        guard let original = state.tab(id, where: { $0.archivedAt != nil }),
              requestedProfile == nil || original.profileID == requestedProfile,
              let item = archivedItems(profileID: original.profileID).first(where: { $0.tabs.contains { $0.id == id } }) else { return [] }
        let preferred: UUID?, fallback: UUID?
        switch target {
        case let .putBack(currentSpaceID, requestedSpaceID):
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
        let originalSpace = original.kind == .pinned && (item.provenance?.spaceID ?? original.spaceID) == destination.id
        var folderID = originalSpace
            ? original.folderID.flatMap { id in next.folders.contains { $0.id == id && $0.spaceID == destination.id } ? id : nil }
            : nil
        let path = originalSpace && folderID == nil ? item.provenance?.folderPath : nil
        if let path { folderID = path.rebuilding(in: &next, spaceID: destination.id) }
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
        if let path, let folderID, folderID == path.folders.last?.id {
            let anchor = ids.count > 1 ? item.provenance?.split?.sidebarAnchorID ?? ids[0] : ids[0]
            SidebarHierarchy.placing(.tab(anchor), in: .init(spaceID: destination.id, folderID: folderID, section: .pinned),
                                     following: path.siblings, state: &next)
        }
        if let preview {
            exclusiveRetirementIDs.formUnion(ids)
            releaseArchivePreview(preview)
        }
        state = next
        if preview != nil { exclusiveRetirementIDs.subtract(ids) }
        changed()
        return ids
    }

    package func resetDormantSavedTab(_ expected: BrowserTab) {
        guard let index = state.tabIndex(expected.id),
              state.tabs[index] == expected, expected.resetDestination != nil,
              !retiringTabIDs.contains(expected.id) else { return }
        tabHistory?.remove(expected.id)
        state.tabs[index].url = expected.savedURL
        state.tabs[index].title = expected.savedTitle
        changed()
    }

    @discardableResult
    package func replaceSavedHome(_ expected: BrowserTab, url: String, title: String) -> Bool {
        let url = BrowserInternalURL.publicString(url)
        guard let index = state.tabIndex(expected.id),
              state.tabs[index] == expected, expected.resetDestination != nil,
              !retiringTabIDs.contains(expected.id), !isProfileRemovalPending(expected.profileID),
              !InternalPage.isInternal(url), let page = URL(string: url), page.scheme != nil else { return false }
        state.tabs[index].savedURL = url
        state.tabs[index].savedTitle = title.isEmpty ? (page.host ?? url) : title
        changed()
        return true
    }

    @discardableResult
    package func separateFromPinnedTab(_ expected: BrowserTab, todayID: UUID, title: String) -> Bool {
        guard let index = state.tabIndex(expected.id),
              state.tabs[index] == expected, expected.kind == .pinned, expected.resetDestination != nil,
              !retiringTabIDs.contains(expected.id), !state.containsTab(todayID),
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

    private func admittingNewSplit(_ layout: BrowserSplitLayout, in base: BrowserState) -> BrowserState? {
        var homeIDs: [UUID: UUID] = [:]
        for home in SplitMembership.savedHomeSources(joining: layout.tabIDs, existing: nil, added: nil, state: base) {
            homeIDs[home.id] = UUID()
        }
        return SplitMembership.admitting(layout, existing: nil, added: nil, state: base,
                                         spaceID: base.activeSpaceID, homeIDs: homeIDs, now: clock())
    }

    package func setKind(_ id: UUID, _ kind: TabKind) {
        guard !retiringTabIDs.contains(id), let tab = state.tab(id, where: { $0.archivedAt == nil }) else { return }
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
            guard let index = state.tabIndex(member, where: { $0.archivedAt == nil }) else { continue }
            let previousKind = state.tabs[index].kind
            if let destination { state.tabs[index].spaceID = destination }
            state.tabs[index].kind = kind
            state.tabs[index].archivedAt = nil
            state.tabs[index].archiveProvenance = nil
            if kind != .pinned { state.tabs[index].folderID = nil }
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

    package func moveTab(_ id: UUID, toSpace spaceID: UUID, folderID: UUID? = nil) {
        guard let tab = state.tab(id),
              let space = state.spaces.first(where: { $0.id == spaceID }) else { return }
        if let folderID, !state.folders.contains(where: { $0.id == folderID && $0.spaceID == spaceID }) { return }
        if tab.profileID != space.profileID {
            withRetiredPages([id], shouldCommit: { [weak self] in
                guard let self,
                      let current = self.state.tab(id),
                      current.profileID == tab.profileID, current.spaceID == tab.spaceID,
                      self.state.spaces.first(where: { $0.id == spaceID })?.profileID == space.profileID else { return false }
                return folderID == nil || self.state.folders.contains { $0.id == folderID && $0.spaceID == spaceID }
            }) { [weak self] in self?.finishMovingTab(id, toSpace: spaceID, folderID: folderID) }
        } else { finishMovingTab(id, toSpace: spaceID, folderID: folderID) }
    }

    private func finishMovingTab(_ id: UUID, toSpace spaceID: UUID, folderID: UUID?) {
        guard let index = state.tabIndex(id),
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

    package func reorderTab(_ id: UUID, before otherID: UUID?) {
        guard id != otherID, let index = state.tabIndex(id) else { return }
        let item = state.tabs[index]
        if let otherID, let target = state.tab(otherID),
           (target.kind != item.kind || target.spaceID != item.spaceID || target.folderID != item.folderID) { return }
        state.tabs.remove(at: index)
        let position = otherID.flatMap { id in state.tabIndex(id) } ?? state.tabs.count
        state.tabs.insert(item, at: position)
        changed()
    }

    @discardableResult
    package func createSpace(name: String, color: String = "B9B5D4") -> UUID {
        var space = BrowserSpace(id: UUID(), name: name,
                                 symbol: "circle.fill", color: color, profileID: activeSpace.profileID)
        space.updateDisplayName(position: state.spaces.count)
        space.autoArchiveHours = state.resolvedAutoArchiveHours(forSpace: activeSpaceID)
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

    @discardableResult
    package func createSpace(name: String, sharing: SpaceDataSharing, newProfileID: UUID = UUID()) throws -> UUID {
        guard !isEphemeral else { throw ProfileSettingsError.unavailable }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = state
        let profileID: UUID
        switch sharing {
        case .share(let spaceID):
            guard let space = state.spaces.first(where: { $0.id == spaceID }), !isProfileRemovalPending(space.profileID) else {
                throw ProfileSettingsError.unavailable
            }
            profileID = space.profileID
        case .separate:
            guard !trimmed.isEmpty, !state.profiles.contains(where: { $0.id == newProfileID }) else { throw ProfileSettingsError.unavailable }
            profileID = newProfileID
            next.profiles.append(BrowserProfile(id: profileID, name: trimmed,
                autoArchiveHours: state.resolvedAutoArchiveHours(forSpace: activeSpaceID)))
        }
        var space = BrowserSpace(id: UUID(), name: trimmed, symbol: "circle.fill", color: "B9B5D4", profileID: profileID)
        space.theme = savedTheme(of: activeSpace)
        space.autoArchiveHours = state.resolvedAutoArchiveHours(forSpace: activeSpaceID)
        space.updateDisplayName(position: next.spaces.count)
        next.spaces.append(space)
        next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
        next.activeSpaceID = space.id
        next.selectedTabIDs = next.selectionBySpace[space.id.uuidString] ?? []
        normalizeSelection(in: &next)
        stampSelection(in: &next)
        next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
        try commitProfileSettings(next)
        return space.id
    }

    package func renameSpace(_ id: UUID, name: String) {
        guard !name.isEmpty, let index = state.spaces.firstIndex(where: { $0.id == id }) else { return }
        state.spaces[index].title = name
        state.spaces[index].updateDisplayName(position: index)
        changed()
    }

    package func saveSpaceTitle(_ expected: BrowserSpace, title: String?) throws {
        guard !isEphemeral, !isProfileRemovalPending(expected.profileID),
              let index = state.spaces.firstIndex(where: { $0.id == expected.id && $0.profileID == expected.profileID }),
              state.spaces[index].title == expected.title else { throw CocoaError(.userCancelled) }
        var next = state
        next.spaces[index].title = title.flatMap { $0.isEmpty ? nil : $0 }
        next.spaces[index].updateDisplayName(position: index)
        if next != state { try commitProfileSettings(next) }
    }

    package func saveSpaceIcon(_ expected: BrowserSpace, icon: SidebarGroupIcon?) throws {
        guard !isEphemeral, icon?.isValid != false, !isProfileRemovalPending(expected.profileID),
              let index = state.spaces.firstIndex(where: { $0.id == expected.id && $0.profileID == expected.profileID }),
              state.spaces[index].customIcon == expected.customIcon else { throw CocoaError(.userCancelled) }
        var next = state
        next.spaces[index].customIcon = icon
        if next != state { try commitProfileSettings(next) }
    }

    package func deleteSpace(_ target: SpaceDeletionTarget, documents: [UUID: SidebarDocumentReference],
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
    package func canUndoSpaceDeletion(_ undo: SpaceDeletionUndo) -> Bool { undo.restoring(in: state) != nil }
    @discardableResult package func undoSpaceDeletion(_ undo: SpaceDeletionUndo, shouldCommit: () -> Bool) throws -> Bool {
        guard !isEphemeral, undo.documentsAreAvailable, undo.target.tabIDs.isDisjoint(with: retiringTabIDs),
              shouldCommit(), undo.documentsAreAvailable, undo.target.tabIDs.isDisjoint(with: retiringTabIDs),
              let next = undo.restoring(in: state) else { return false }
        try commitProfileSettings(next); return true
    }

    @discardableResult package func reorderSpace(_ id: UUID, before: UUID?, expectedOrder: [UUID]) throws -> Bool {
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
    package func setSpaceTheme(_ id: UUID, theme: SpaceTheme) -> Bool {
        guard theme.isValid, let index = state.spaces.firstIndex(where: { $0.id == id }) else { return false }
        themePreviews[id] = nil
        guard state.spaces[index].theme != theme else { return true }
        state.spaces[index].theme = theme
        changed()
        return true
    }

    @discardableResult
    package func previewSpaceTheme(_ id: UUID, theme: SpaceTheme) -> Bool {
        guard theme.isValid, let index = state.spaces.firstIndex(where: { $0.id == id }) else { return false }
        themePreviews[id] = (themePreviews[id]?.saved ?? state.spaces[index].theme, theme)
        if state.spaces[index].theme != theme { state.spaces[index].theme = theme }
        return true
    }

    package func endSpaceThemePreview(_ id: UUID) {
        guard let entry = themePreviews.removeValue(forKey: id),
              let index = state.spaces.firstIndex(where: { $0.id == id }),
              state.spaces[index].theme == entry.preview else { return }
        state.spaces[index].theme = entry.saved
        changed()
    }

    package func savedTheme(of space: BrowserSpace) -> SpaceTheme {
        themePreviews[space.id]?.saved ?? space.theme
    }

    private func commitSpaceTheme(_ next: BrowserState, spaceID: UUID) throws {
        let preview = themePreviews.removeValue(forKey: spaceID)
        do { try commitProfileSettings(next) } catch { themePreviews[spaceID] = preview; throw error }
    }

    @discardableResult
    package func saveSpaceTheme(spaceID: UUID, profileID: UUID, previous: SpaceTheme,
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

    package func canApplySpaceThemeChange(_ change: SpaceThemeChange, undo: Bool) -> Bool {
        !isEphemeral && !isProfileRemovalPending(change.profileID)
            && change.target(in: state, undo: undo) != nil
    }

    @discardableResult
    package func applySpaceThemeChange(_ change: SpaceThemeChange, undo: Bool) throws -> Bool {
        guard canApplySpaceThemeChange(change, undo: undo),
              let index = state.spaces.firstIndex(where: { $0.id == change.spaceID }) else { return false }
        var next = state
        next.spaces[index].theme = undo ? change.previousTheme : change.theme
        try commitSpaceTheme(next, spaceID: change.spaceID)
        return true
    }

    @discardableResult
    package func saveSidebarTitle(_ expected: BrowserTab, title: String) throws -> SidebarTabTitleChange? {
        guard !isProfileRemovalPending(expected.profileID), !retiringTabIDs.contains(expected.id),
              let index = state.tabIndex(expected.id),
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

    @discardableResult
    package func saveFavoriteTitle(_ expected: BrowserTab, title: String) throws -> SidebarTabTitleChange? {
        guard !title.isEmpty, !isEphemeral, expected.kind == .favorite,
              state.profiles.contains(where: { $0.id == expected.profileID }),
              !isProfileRemovalPending(expected.profileID), !retiringTabIDs.contains(expected.id),
              let index = state.tabIndex(expected.id),
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

    package func canApplyTabTitleChange(_ change: SidebarTabTitleChange, undo: Bool) -> Bool {
        !isProfileRemovalPending(change.profileID) && !retiringTabIDs.contains(change.tabID) &&
            change.target(in: state, undo: undo) != nil
    }

    @discardableResult
    package func applyTabTitleChange(_ change: SidebarTabTitleChange, undo: Bool) throws -> Bool {
        guard canApplyTabTitleChange(change, undo: undo),
              let index = state.tabIndex(change.tabID) else { return false }
        var next = state
        next.tabs[index].customTitle = undo ? change.previousTitle : change.title
        try commitProfileSettings(next)
        return true
    }

    @discardableResult
    package func saveSidebarSplitTitle(_ expected: SidebarSplitTitleEdit, title: String) throws -> SidebarSplitTitleChange? {
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
    package func saveSplitAppearance(_ expected: SidebarSplitTitleEdit, icon: SidebarGroupIcon?, reset: Bool = false) throws -> SidebarSplitAppearanceChange? {
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

    package func canApplySplitAppearance(_ change: SidebarSplitAppearanceChange, undo: Bool) -> Bool {
        guard let group = change.target(in: state, undo: undo) else { return false }
        return Set(group.tabIDs).isDisjoint(with: retiringTabIDs)
    }
    @discardableResult
    package func applySplitAppearance(_ change: SidebarSplitAppearanceChange, undo: Bool) throws -> Bool {
        guard canApplySplitAppearance(change, undo: undo),
              let index = state.splitLayouts.firstIndex(where: { $0.id == change.containerID }) else { return false }
        var next = state
        next.splitLayouts[index].customIcon = undo ? change.previousIcon : change.icon
        if change.resetsTitle { next.splitLayouts[index].customTitle = undo ? change.previousTitle : change.title }
        try commitProfileSettings(next)
        return true
    }

    package func canApplySplitTitleChange(_ change: SidebarSplitTitleChange, undo: Bool) -> Bool {
        guard !isProfileRemovalPending(change.profileID), let group = change.target(in: state, undo: undo) else { return false }
        return Set(group.tabIDs).isDisjoint(with: retiringTabIDs)
    }

    @discardableResult
    package func applySplitTitleChange(_ change: SidebarSplitTitleChange, undo: Bool) throws -> Bool {
        guard canApplySplitTitleChange(change, undo: undo),
              let index = state.splitLayouts.firstIndex(where: { $0.id == change.containerID }) else { return false }
        var next = state
        next.splitLayouts[index].customTitle = undo ? change.previousTitle : change.title
        try commitProfileSettings(next)
        return true
    }

    package func renameProfile(_ id: UUID, name: String) {
        guard !isProfileRemovalPending(id) else { return }
        guard !name.isEmpty, let index = state.profiles.firstIndex(where: { $0.id == id }) else { return }
        state.profiles[index].name = name
        changed()
    }

    package func saveProfileName(_ id: UUID, expectedName: String, name: String) throws {
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

    package func saveSettingsSelection(pane: String, profileID: UUID?) throws {
        guard profileID == nil || state.profiles.contains(where: { $0.id == profileID }) else {
            throw ProfileSettingsError.unavailable
        }
        var next = state
        next.settings.settingsPane = pane
        next.settings.settingsProfileID = profileID
        guard next != state else { return }
        try commitProfileSettings(next)
    }

    package func saveRestoreSession(_ enabled: Bool) throws {
        var next = state
        next.settings.restoreSession = enabled
        guard next != state else { return }
        try commitProfileSettings(next)
    }

    package func saveSidebarWidth(_ width: Double) throws {
        guard width.isFinite else { throw ProfileSettingsError.invalidSidebarWidth }
        var next = state
        next.settings.sidebarWidth = min(500, max(164, width))
        guard next != state else { return }
        try commitProfileSettings(next)
    }

    package func settingsPageSpace(profileID: UUID?, originatingSpaceID: UUID?) -> BrowserSpace? {
        guard let profileID, !isEphemeral, !isProfileRemovalPending(profileID),
              state.profiles.contains(where: { $0.id == profileID }) else { return nil }
        return state.spaces.first { $0.id == originatingSpaceID && $0.profileID == profileID }
            ?? state.spaces.first { $0.profileID == profileID }
    }

    private func hasArchiveActivity(_ profileID: UUID) -> Bool {
        archivePreviewLeases.values.contains { $0.profileID == profileID }
            || state.tabs.contains { $0.profileID == profileID && retiringTabIDs.contains($0.id) }
    }

    package func stageProfileRemoval(_ profileID: UUID, expectedName: String) throws -> ProfileRemovalRecord {
        let summary = try validateProfileRemoval(profileID, expectedName: expectedName)
        guard !hasProfileWrite(profileID), !hasArchiveActivity(profileID) else { throw ProfileRemovalError.activeDocumentWrite }
        guard let survivor = survivingProfileID(excluding: [profileID]) else { throw ProfileRemovalError.unavailable }
        let record = ProfileRemovalRecord(id: UUID(), profileID: profileID, profileName: summary.profile.name,
                                          fallbackProfileID: survivor)
        var next = state
        handOff(from: [profileID], to: survivor, in: &next)
        next.profileRemovals.append(record)
        try commitProfileSettings(next)
        return record
    }

    package func stageUnusedProfileRemovals(_ profiles: [BrowserProfile]) throws -> [ProfileRemovalRecord] {
        try validateUnusedProfileRemoval(profiles)
        guard profiles.allSatisfy({ !hasProfileWrite($0.id) && !hasArchiveActivity($0.id) }) else { throw ProfileRemovalError.activeDocumentWrite }
        let removed = Set(profiles.map(\.id))
        guard let survivor = survivingProfileID(excluding: removed) else { throw ProfileRemovalError.unavailable }
        let records = profiles.map { ProfileRemovalRecord(id: UUID(), profileID: $0.id, profileName: $0.name, fallbackProfileID: survivor) }
        var next = state
        handOff(from: removed, to: survivor, in: &next)
        next.profileRemovals.append(contentsOf: records)
        try commitProfileSettings(next)
        return records
    }

    private func handOff(from removed: Set<UUID>, to survivor: UUID, in next: inout BrowserState) {
        next.settings.defaultProfileID = removed.contains(defaultProfileID) ? survivor : defaultProfileID
        if let selected = next.settings.settingsProfileID, removed.contains(selected) { next.settings.settingsProfileID = survivor }
    }

    package func cancelProfileRemoval(_ record: ProfileRemovalRecord) throws {
        guard state.profileRemovals.contains(record) else { throw ProfileRemovalError.unavailable }
        var next = state
        next.profileRemovals.removeAll { $0.id == record.id }
        try commitProfileSettings(next)
    }

    package func finishProfileRemoval(_ record: ProfileRemovalRecord) throws {
        guard state.profileRemovals.contains(record),
              state.profiles.contains(where: { $0.id == record.profileID }) else {
            throw ProfileRemovalError.unavailable
        }
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
        let fallback = fallbackProfileID(for: record)
        let keeps: (UUID) -> Bool = { id in
            next.profiles.contains { $0.id == id } && next.spaces.contains { $0.profileID == id }
                && !next.profileRemovals.contains { $0.profileID == id }
        }
        let survivor = keeps(fallback) ? fallback
            : next.spaces.map(\.profileID).first(where: keeps) ?? next.profiles.first?.id
        if next.settings.defaultProfileID == record.profileID { next.settings.defaultProfileID = survivor }
        if next.settings.settingsProfileID == record.profileID { next.settings.settingsProfileID = survivor }
        next.settings.topAppsEmptyStateDismissedForProfiles?.removeAll { $0 == record.profileID }
        try commitProfileSettings(next)
        forgetBackups(.profile(record.profileID))
        if historyChanged { historyRevision &+= 1; recordHistoryRemoval(profileID: record.profileID, urls: nil) }
    }

    package func commitProfileSettings(_ next: BrowserState) throws {
        if isEphemeral { state = next; return }
        do {
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
    package func createProfile(name: String) -> UUID {
        let profile = BrowserProfile(id: UUID(), name: name.isEmpty ? "Profile" : name,
                                     autoArchiveHours: state.autoArchiveDefaultHours)
        state.profiles.append(profile)
        changed()
        return profile.id
    }

    @discardableResult
    package func createProfilePersisted(name: String) throws -> UUID {
        guard !isEphemeral else { throw CocoaError(.userCancelled) }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw CocoaError(.userCancelled) }
        let profile = BrowserProfile(id: UUID(), name: name, autoArchiveHours: state.autoArchiveDefaultHours)
        var next = state; next.profiles.append(profile)
        try commitProfileSettings(next); return profile.id
    }

    package func assignProfile(_ profileID: UUID, toSpace spaceID: UUID, creating newProfile: BrowserProfile? = nil,
                       shouldCommit: @escaping () -> Bool = { true },
                       completion: @escaping (Result<Bool, Error>) -> Void = { _ in }) {
        guard let assignment = profileAssignment(profileID, toSpace: spaceID, creating: newProfile) else { completion(.success(false)); return }
        moveAcrossProfiles(assignment.tabIDs, proposal: { shouldCommit() ? assignment.proposal($0) : nil }, completion: completion)
    }

    package func profileAssignment(_ profileID: UUID, toSpace spaceID: UUID, creating newProfile: BrowserProfile? = nil)
        -> (tabIDs: Set<UUID>, proposal: (BrowserState) -> BrowserState?)? {
        func including(_ state: BrowserState) -> BrowserState? {
            guard let newProfile else { return state }
            guard newProfile.id == profileID, !state.profiles.contains(where: { $0.id == profileID }) else { return nil }
            var next = state; next.profiles.append(newProfile); return next
        }
        guard !isEphemeral, let space = state.spaces.first(where: { $0.id == spaceID }), let available = including(state),
              InterProfileMove.profilesAvailable(space.profileID, profileID, in: available) else { return nil }
        let ids = Set(state.openTabs(where: { $0.spaceID == spaceID && $0.kind != .favorite }).map(\.id))
        return (ids, { original in
            guard let current = including(original),
                  InterProfileMove.profilesAvailable(space.profileID, profileID, in: current),
                  let index = current.spaces.firstIndex(where: { $0.id == spaceID && $0.profileID == space.profileID }),
                  Set(current.openTabs(where: { $0.spaceID == spaceID && $0.kind != .favorite }).map(\.id)) == ids else { return nil }
            var next = current
            if let keeper = next.spaces.first(where: { $0.id != spaceID && $0.profileID == space.profileID }) {
                for i in next.splitLayouts.indices where next.splitLayouts[i].spaceID == spaceID
                    && SidebarSplitItems.isFavorite(next.splitLayouts[i], in: current, profileID: space.profileID) {
                    next.splitLayouts[i].spaceID = keeper.id
                }
            }
            next.spaces[index].profileID = profileID
            for i in next.tabs.indices where ids.contains(next.tabs[i].id) { next.tabs[i].profileID = profileID }
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
        })
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
            if current && approved && allowed { commit() }
            else { onRefusal?() }
            if exclusive {
                if approved { self.committingRetirementIDs.subtract(ids) }
                self.exclusiveRetirementIDs.subtract(ids)
            }
        }
    }

    @discardableResult
    package func createFolder(name: String, parentID: UUID? = nil) -> UUID {
        let id = UUID()
        let parent = parentID.flatMap { parent in folders.contains { $0.id == parent } ? parent : nil }
        state.folders.append(BrowserFolder(id: id, spaceID: activeSpaceID, name: name.isEmpty ? SidebarFolderFromItems.defaultName : name, parentID: parent))
        changed()
        return id
    }

    @discardableResult
    package func createFolder(name: String, in expected: BrowserSpace, parent: BrowserFolder? = nil) throws -> UUID? {
        guard !isEphemeral, state.spaces.contains(where: { $0.id == expected.id && $0.profileID == expected.profileID }),
              !isProfileRemovalPending(expected.profileID),
              parent.map({ $0.spaceID == expected.id && state.folders.contains($0) }) ?? true else { return nil }
        let folder = BrowserFolder(id: UUID(), spaceID: expected.id, name: name.isEmpty ? SidebarFolderFromItems.defaultName : name, parentID: parent?.id)
        var next = state; next.folders.append(folder)
        try commitProfileSettings(next); return folder.id
    }

    @discardableResult
    package func convertSpaceToFolder(_ conversion: SpaceFolderConversion) throws -> SpaceFolderUndo? {
        guard !isEphemeral, !conversion.crossesProfiles, conversion.tabIDs.isDisjoint(with: retiringTabIDs),
              SidebarDocumentReference.validates(conversion.target.tabs, references: conversion.documents),
              let (next, undo) = conversion.applying(to: state) else { return nil }
        try commitProfileSettings(next); return undo
    }
    @discardableResult
    package func undoSpaceFolderConversion(_ undo: SpaceFolderUndo) throws -> Bool {
        guard !isEphemeral, undo.conversion.tabIDs.isDisjoint(with: retiringTabIDs), undo.documentsAreAvailable,
              let next = undo.restoring(in: state) else { return false }
        try commitProfileSettings(next); return true
    }

    @discardableResult
    package func renameFolder(_ expected: BrowserFolder, profileID: UUID, name: String) throws -> Bool {
        guard !isEphemeral, !name.isEmpty, !isProfileRemovalPending(profileID),
              state.spaces.contains(where: { $0.id == expected.spaceID && $0.profileID == profileID }),
              let index = state.folders.firstIndex(where: { $0.id == expected.id }),
              state.folders[index].spaceID == expected.spaceID,
              state.folders[index].parentID == expected.parentID,
              state.folders[index].name == expected.name else { return false }
        var next = state; next.folders[index].name = name
        try commitProfileSettings(next); return true
    }

    @discardableResult
    package func setFolderIcon(_ icon: SidebarGroupIcon?, expected: BrowserFolder, profileID: UUID) throws -> Bool {
        guard !isEphemeral, icon?.isValid ?? true, !isProfileRemovalPending(profileID),
              state.spaces.contains(where: { $0.id == expected.spaceID && $0.profileID == profileID }),
              let index = state.folders.firstIndex(where: { $0.id == expected.id }),
              state.folders[index].spaceID == expected.spaceID else { return false }
        guard state.folders[index].customIcon != icon else { return true }
        var next = state; next.folders[index].customIcon = icon
        try commitProfileSettings(next); return true
    }

    package func renameFolder(_ id: UUID, name: String) {
        guard !name.isEmpty, let index = state.folders.firstIndex(where: { $0.id == id }) else { return }
        state.folders[index].name = name
        changed()
    }

    package func toggleFolder(_ id: UUID) {
        guard let index = state.folders.firstIndex(where: { $0.id == id }) else { return }
        state.folders[index].isExpanded.toggle()
        changed()
    }

    @discardableResult
    package func setFolderExpanded(_ expanded: Bool, expected: BrowserFolder, profileID: UUID) throws -> Bool {
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

    @discardableResult
    package func setFoldersExpanded(_ expanded: Bool, in spaceID: UUID, profileID: UUID,
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
        try commitProfileSettings(next)
        return true
    }

    @discardableResult
    package func revealSidebarItem(_ reveal: SidebarItemReveal) throws -> Bool {
        guard !isEphemeral, let next = reveal.applying(to: state) else { return false }
        if next != state { try commitProfileSettings(next) }
        return true
    }

    @discardableResult
    package func moveSidebarItem(_ item: SidebarItemReference, to destination: SidebarContainerLocation,
                         before: SidebarItemReference?, expected: SidebarHierarchySnapshot) throws -> Bool {
        let ids = SidebarHierarchy.tabIDs(in: item, state: state, spaceID: expected.spaceID)
        guard ids.allSatisfy({ !retiringTabIDs.contains($0) }),
              let next = SidebarHierarchy.moving(item, to: destination, before: before, expected: expected, state: state) else { return false }
        if next != state { try commitProfileSettings(next) }
        return true
    }

    @discardableResult
    package func moveSidebarItems(_ items: [SidebarItemReference], to destination: SidebarContainerLocation,
                          before: SidebarItemReference?, expected: SidebarHierarchySnapshot) throws -> Bool {
        let ids = items.flatMap { SidebarHierarchy.tabIDs(in: $0, state: state, spaceID: expected.spaceID) }
        guard ids.allSatisfy({ !retiringTabIDs.contains($0) }),
              let next = SidebarHierarchy.moving(items, to: destination, before: before, expected: expected, state: state) else { return false }
        if next != state { try commitProfileSettings(next) }
        return true
    }


    @discardableResult
    package func createSpaceAndMoveSidebarItems(_ draft: SidebarNewSpaceDraft) throws -> UUID? {
        guard !isEphemeral, !draft.movesItemsAcrossProfiles, !draft.tabIDs.contains(where: { retiringTabIDs.contains($0) }),
              let next = draft.applying(to: state) else { return nil }
        try commitProfileSettings(next)
        return draft.spaceID
    }

    @discardableResult
    package func turnFolderIntoSpace(_ draft: SidebarNewSpaceDraft, folder expected: BrowserFolder) throws -> UUID? {
        let contents = SidebarContainerLocation(spaceID: expected.spaceID, folderID: expected.id, section: .pinned)
        guard !isEphemeral, !draft.movesItemsAcrossProfiles, !draft.tabIDs.contains(where: { retiringTabIDs.contains($0) }),
              state.folders.contains(expected), expected.spaceID == draft.source.spaceID,
              let staged = draft.applying(to: state),
              let location = SidebarHierarchy.location(of: .folder(expected.id), state: staged, spaceID: expected.spaceID),
              SidebarHierarchy.children(in: contents, state: staged).isEmpty else { return nil }
        var next = staged
        next.folders.removeAll { $0.id == expected.id }
        for index in next.tabs.indices where next.tabs[index].folderID == expected.id { next.tabs[index].folderID = nil }
        next.sidebarItemOrder[location.key]?.removeAll { $0 == .folder(expected.id) }
        next.sidebarItemOrder.removeValue(forKey: contents.key)
        try commitProfileSettings(next)
        return draft.spaceID
    }

    @discardableResult
    package func moveSidebarItemsAcrossSpaces(_ move: SidebarSpaceMove) throws -> Bool {
        guard !isEphemeral, !move.crossesProfiles, move.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }),
              let next = move.applying(to: state) else { return false }
        try commitProfileSettings(next)
        return true
    }

    @discardableResult
    package func commitSidebarWindowMove(_ move: SidebarWindowMove) throws -> Bool {
        guard !isEphemeral, !move.crossesProfiles, move.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }),
              let next = move.applying(to: state) else { return false }
        if next != state { try commitProfileSettings(next) }
        return true
    }

    package func moveAcrossProfiles(_ ids: Set<UUID>, proposal: @escaping (BrowserState) -> BrowserState?,
                            completion: @escaping (Result<Bool, Error>) -> Void) {
        func admitted(_ state: BrowserState) -> (next: BrowserState, from: UUID, to: UUID, documents: [InternalPage])? {
            guard let next = proposal(state),
                  let from = InterProfileMove.sourceProfile(of: Array(ids), in: state),
                  let to = InterProfileMove.sourceProfile(of: Array(ids), in: next), from != to,
                  let documents = InterProfileMove.documents(moving: ids, after: next),
                  documents.isEmpty || relocateLocalDocuments != nil else { return nil }
            return (next, from, to, documents)
        }
        if ids.isEmpty {
            guard !isEphemeral, let next = proposal(state) else { completion(.success(false)); return }
            do { try commitProfileSettings(next); completion(.success(true)) } catch { completion(.failure(error)) }
            return
        }
        guard !isEphemeral, ids.isDisjoint(with: retiringTabIDs),
              ids.allSatisfy({ id in state.tab(id).map(InterProfileMove.admits) == true }),
              admitted(state) != nil else { completion(.success(false)); return }
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

    package var relocateLocalDocuments: ((Set<UUID>, [InternalPage], UUID, UUID) throws -> () -> Void)?
    package var prepareLocalDocumentRelocation: ((Set<UUID>) -> (() -> Bool)?)?

    @discardableResult
    package func commitForeignSplitDrop(_ ids: Set<UUID>, proposal: (BrowserState) -> BrowserState?) throws -> Bool {
        guard !isEphemeral, !ids.isEmpty, ids.isDisjoint(with: retiringTabIDs), let next = proposal(state),
              ids.allSatisfy({ id in state.tab(id)?.profileID == next.tabs.first { $0.id == id }?.profileID }) else { return false }
        try commitProfileSettings(next)
        return true
    }

    package var bypassesInterProfileMoveConfirmation: Bool { state.settings.shouldBypassConfirmInterProfileMoveDialog ?? false }

    package func rememberInterProfileMoveChoice() {
        updateSettings { $0.shouldBypassConfirmInterProfileMoveDialog = true }
    }

    @discardableResult
    package func performCommandBarFolderMove(_ move: CommandBarFolderMove) throws -> Bool {
        guard !isEphemeral, move.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }),
              let next = move.applying(to: state) else { return false }
        if next != state { try commitProfileSettings(next) }
        return true
    }

    @discardableResult
    package func performFavoriteAction(_ action: CommandBarFavoriteAction) throws -> Bool {
        guard !isEphemeral, action.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }),
              let next = action.applying(to: state) else { return false }
        try commitProfileSettings(next)
        return true
    }

    package func copyCommandBarItemsToFolder(_ move: CommandBarFolderMove,
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

    package func duplicateFolder(_ target: FolderDuplicateTarget,
                         destinations: [UUID: String],
                         documents: [UUID: SidebarDocumentReference] = [:],
                         creation: TabCreationProvenance? = nil) throws -> FolderDuplicateResult? {
        guard let copied = try duplicateSidebarItems(target.collection, destinations: destinations, documents: documents, creation: creation),
              let first = copied.roots.first, case .folder(let id) = first else { return nil }
        return FolderDuplicateResult(folderID: id, tabIDs: copied.tabIDs, openTabIDs: copied.openTabIDs)
    }

    package func duplicateSidebarItems(_ target: SidebarDuplicateTarget,
                         destinations: [UUID: String],
                         documents: [UUID: SidebarDocumentReference] = [:],
                         creation: TabCreationProvenance? = nil) throws -> SidebarDuplicateResult? {
        let expected = target.hierarchy
        guard !isEphemeral, SidebarDuplicateTarget(items: target.roots, spaceID: expected.spaceID,
                profileID: expected.profileID, state: state) == target,
              SidebarCopySources(destinations: destinations, documents: documents).validates(target.tabs),
              target.tabs.allSatisfy({ !retiringTabIDs.contains($0.id) }),
              let copied = adjacentCopies(roots: target.roots, folderIDs: target.folderIDs, tabs: target.tabs,
                  groups: target.groups, spaceID: expected.spaceID, profileID: expected.profileID,
                  destinations: destinations, creation: creation, opensEverySplit: true) else { return nil }
        try commitProfileSettings(copied.state)
        return copied.result
    }

    private func adjacentCopies(roots: [SidebarItemReference], folderIDs: [UUID], tabs: [BrowserTab],
                                groups: [BrowserSplitLayout], spaceID: UUID, profileID: UUID,
                                destinations: [UUID: String], creation: TabCreationProvenance?,
                                opensEverySplit: Bool) -> (state: BrowserState, result: SidebarDuplicateResult)? {
        let previous = creation?.validated(profileID: profileID, state: state).activeTabBeforeCreationID
        let folderMap = Dictionary(uniqueKeysWithValues: folderIDs.map { ($0, UUID()) })
        let tabMap = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, UUID()) })
        let groupMap = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, UUID()) })
        var next = state
        let now = clock()
        for id in folderIDs {
            guard var copy = state.folders.first(where: { $0.id == id }), let newID = folderMap[id] else { return nil }
            copy.id = newID
            if let parent = copy.parentID, let newParent = folderMap[parent] { copy.parentID = newParent }
            next.folders.append(copy)
        }
        for original in tabs {
            guard let id = tabMap[original.id], let url = destinations[original.id] else { return nil }
            var copy = original
            copy.id = id
            copy.referrerID = nil; copy.activeTabBeforeCreationID = previous
            if let parent = original.folderID, let folder = folderMap[parent] { copy.folderID = folder }
            copy.url = url; copy.savedURL = url
            copy.title = original.savedTitle; copy.savedTitle = original.savedTitle
            copy.createdAt = now; copy.lastAccessed = now
            copy.isUnread = true; copy.archiveProvenance = nil
            next.tabs.append(copy)
        }
        for group in groups {
            guard let id = groupMap[group.id], let anchor = group.sidebarAnchorID,
                  let newAnchor = tabMap[anchor] else { return nil }
            let children = group.tabIDs.compactMap { tabMap[$0] }
            guard children.count == group.tabIDs.count else { return nil }
            next.splitLayouts.append(BrowserSplitLayout(id: id, sidebarAnchorID: newAnchor, customTitle: group.customTitle, customIcon: group.customIcon,
                spaceID: group.spaceID, tabIDs: children, orientation: group.orientation, widthFactors: group.widthFactors,
                stacks: group.stacks))
        }
        for id in folderIDs {
            let sourceLocation = SidebarContainerLocation(spaceID: spaceID, folderID: id, section: .pinned)
            let destination = SidebarContainerLocation(spaceID: spaceID, folderID: folderMap[id]!, section: .pinned)
            let children = SidebarHierarchy.children(in: sourceLocation, state: state)
            var copied: [SidebarItemReference] = []
            for child in children {
                switch child {
                case .folder(let id): guard let mapped = folderMap[id] else { return nil }; copied.append(.folder(mapped))
                case .tab(let id): guard let mapped = tabMap[id] else { return nil }; copied.append(.tab(mapped))
                case .split(let id):
                    guard let anchor = groups.first(where: { $0.id == id })?.sidebarAnchorID,
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
        var siblingsByKey: [String: [SidebarItemReference]] = [:]
        var copiedRoots: [SidebarItemReference] = [], eager: [UUID] = []
        func requestOpen(_ item: SidebarItemReference, shouldOpen: Bool) {
            switch item {
            case .tab(let id):
                if shouldOpen,
                   tabs.first(where: { $0.id == id }).map({ InternalPage(urlString: $0.savedURL) == nil }) == true,
                   let copied = tabMap[id] { eager.append(copied) }
            case .folder(let id):
                for child in SidebarHierarchy.children(in: .init(spaceID: spaceID, folderID: id, section: .pinned), state: state) {
                    requestOpen(child, shouldOpen: false)
                }
            case .split(let id):
                for child in groups.first(where: { $0.id == id })?.tabIDs ?? [] {
                    requestOpen(.tab(child), shouldOpen: opensEverySplit || shouldOpen)
                }
            }
        }
        for (index, root) in roots.enumerated() {
            guard let source = SidebarHierarchy.location(of: root, state: state, spaceID: spaceID),
                  let copy = mapped(root) else { return nil }
            var siblings = siblingsByKey[source.key] ?? SidebarHierarchy.children(in: source, state: state)
            guard let position = siblings.firstIndex(of: root) else { return nil }
            siblings.insert(copy, at: position + 1); siblingsByKey[source.key] = siblings
            copiedRoots.append(copy)
            requestOpen(root, shouldOpen: index < 5)
        }
        for (key, siblings) in siblingsByKey { next.sidebarItemOrder[key] = siblings.map(stored) }
        return (next, SidebarDuplicateResult(roots: copiedRoots, tabIDs: tabs.compactMap { tabMap[$0.id] }, openTabIDs: eager))
    }

    package func copySidebarItems(_ copy: SidebarItemsCopy, to destination: SidebarContainerLocation,
                          before: SidebarItemReference?, destinations: [UUID: String],
                          documents: [UUID: SidebarDocumentReference] = [:],
                          creation: TabCreationProvenance? = nil) throws -> SidebarDuplicateResult? {
        guard let placed = placedItemsCopy(copy, to: destination, before: before, destinations: destinations,
                                           documents: documents, creation: creation) else { return nil }
        try commitProfileSettings(placed.state)
        return placed.result
    }

    package func copySidebarSplitsReloadingOriginals(_ copy: SidebarItemsCopy, to destination: SidebarContainerLocation,
                                             before: SidebarItemReference?, destinations: [UUID: String],
                                             documents: [UUID: SidebarDocumentReference] = [:],
                                             creation: TabCreationProvenance? = nil,
                                             completion: @escaping (Result<SidebarDuplicateResult?, Error>) -> Void) {
        let originals = Set(copy.tabs.map(\.id))
        func placed(holding: Bool) -> (state: BrowserState, result: SidebarDuplicateResult)? {
            placedItemsCopy(copy, to: destination, before: before, destinations: destinations,
                            documents: documents, creation: creation, holdingRetirement: holding)
        }
        guard copy.wholeSplits, placed(holding: false) != nil else { completion(.success(nil)); return }
        withRetiredPages(originals, shouldCommit: { placed(holding: true) != nil },
                         onRefusal: { completion(.success(nil)) }) { [weak self] in
            guard let self, let value = placed(holding: false) else { completion(.success(nil)); return }
            do { try self.commitProfileSettings(value.state); completion(.success(value.result)) }
            catch { completion(.failure(error)) }
        }
    }

    package func canCopySidebarItems(_ copy: SidebarItemsCopy, to destination: SidebarContainerLocation,
                             before: SidebarItemReference?, destinations: [UUID: String],
                             documents: [UUID: SidebarDocumentReference] = [:]) -> Bool {
        placedItemsCopy(copy, to: destination, before: before, destinations: destinations,
                        documents: documents, creation: nil) != nil
    }

    private func placedItemsCopy(_ original: SidebarItemsCopy, to destination: SidebarContainerLocation,
                                 before: SidebarItemReference?, destinations: [UUID: String],
                                 documents: [UUID: SidebarDocumentReference],
                                 creation: TabCreationProvenance?,
                                 holdingRetirement: Bool = false) -> (state: BrowserState, result: SidebarDuplicateResult)? {
        let source = original.source
        guard !isEphemeral,
              let copy = SidebarItemsCopy(items: original.roots, spaceID: source.spaceID, profileID: source.profileID, state: state),
              copy.matchesPlacement(of: original),
              SidebarCopySources(destinations: destinations, documents: documents).validates(copy.tabs),
              holdingRetirement || copy.tabs.allSatisfy({ !retiringTabIDs.contains($0.id) }),
              let destinationProfile = state.spaces.first(where: { $0.id == destination.spaceID })?.profileID,
              destination.profileID == nil || destination.profileID == destinationProfile else { return nil }
        guard destinationProfile == source.profileID
                || (copy.wholeSplits && copy.tabs.allSatisfy({ InternalPage(urlString: $0.savedURL)?.easelID == nil })) else { return nil }
        guard let copied = adjacentCopies(roots: copy.roots, folderIDs: copy.folderIDs, tabs: copy.tabs, groups: copy.groups,
                  spaceID: source.spaceID, profileID: source.profileID, destinations: destinations,
                  creation: creation, opensEverySplit: false),
              let move = SidebarWindowMove(items: copied.result.roots, sourceSpaceID: source.spaceID, profileID: source.profileID,
                  destinationProfileID: destinationProfile, to: destination, before: before, state: copied.state),
              let placed = move.applying(to: copied.state) else { return nil }
        return (placed, copied.result)
    }

    package func deleteFolder(_ target: FolderRemovalTarget, selection: FolderRemovalSelection? = nil,
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
            return selection?.isCurrent(for: target, in: self.state) ?? true
        }
        guard current(), ids.isDisjoint(with: retiringTabIDs) else { completion(.success(false)); return }
        withRetiredPages(ids, shouldCommit: {
            guard current(), shouldCommit() else { return false }
            return current()
        }, onRefusal: { completion(.success(false)) }) { [weak self] in
            guard let self, current() else { completion(.success(false)); return }
            var next = self.state
            let now = self.clock()
            var provenance = Dictionary(uniqueKeysWithValues: target.tabs.map { tab in
                (tab.id, ArchiveProvenance(reason: .manual, spaceID: tab.spaceID,
                    spaceName: next.spaces.first { $0.id == tab.spaceID }?.name ?? "Space"))
            })
            for split in target.groups where split.tabIDs.allSatisfy({ provenance[$0]?.groupID == nil }) {
                let group = UUID()
                for id in split.tabIDs { provenance[id]?.groupID = group; provenance[id]?.split = split }
            }
            var paths = ArchivedFolderPathRecorder(state: self.state, deleted: Set(target.folderIDs))
            for index in next.tabs.indices {
                let tab = next.tabs[index]
                if ids.contains(tab.id) {
                    next.tabs[index].archivedAt = now
                    next.tabs[index].archiveProvenance = provenance[tab.id]
                    next.tabs[index].archiveProvenance?.folderPath = paths.path(for: tab)
                } else if tab.archivedAt != nil, tab.archiveProvenance != nil, let path = paths.path(for: tab) {
                    next.tabs[index].archiveProvenance?.folderPath = path
                }
            }
            next.recentlyClosedIDs.removeAll { ids.contains($0) }
            next.recentlyClosedIDs += target.tabs.map(\.id)
            self.detachSidebarItems(target, selection: selection, from: &next)
            do {
                let undo = FolderDeletionUndo(target: target, selection: selection, documents: documents, before: self.state, after: next)
                try self.commitProfileSettings(next)
                didCommit?(undo)
                completion(.success(true))
            } catch { completion(.failure(error)) }
        }
    }

    package func canUndoFolderDeletion(_ undo: FolderDeletionUndo) -> Bool {
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
                  && state.tab(archived.id) == archived }),
              undo.locations.allSatisfy({ location in
                  location.container.folderID == nil || state.folders.contains(where: {
                      $0.id == location.container.folderID && $0.spaceID == undo.spaceID
                  })
              }) else { return false }
        return true
    }

    @discardableResult
    package func undoFolderDeletion(_ undo: FolderDeletionUndo, shouldCommit: () -> Bool) throws -> Bool {
        let ids = Set(undo.tabs.map(\.id))
        guard canUndoFolderDeletion(undo), undo.documentsAreAvailable, ids.isDisjoint(with: retiringTabIDs), !archivePreviewOverlaps(ids),
              shouldCommit(), canUndoFolderDeletion(undo), undo.documentsAreAvailable,
              ids.isDisjoint(with: retiringTabIDs), !archivePreviewOverlaps(ids) else { return false }
        var next = state
        next.folders += undo.folders
        for original in undo.tabs {
            guard let index = next.tabIndex(original.id) else { return false }
            next.tabs[index] = original
        }
        for entry in undo.detachedArchive {
            if let index = next.tabIndex(entry.archived.id, where: { $0 == entry.archived }) { next.tabs[index] = entry.original }
        }
        next.splitLayouts += undo.groups
        next.recentlyClosedIDs.removeAll { ids.contains($0) }
        for (key, order) in undo.childOrder { next.sidebarItemOrder[key] = order }
        guard undo.reinsertingRoots(current: state, into: &next) else { return false }
        try commitProfileSettings(next)
        return true
    }

    package func removeSidebarCopy(_ undo: SidebarCopyUndo, target: FolderRemovalTarget,
                           selection: FolderRemovalSelection? = nil,
                           shouldCommit: @escaping () -> Bool,
                           didCommit: ((SidebarCopyUndo) -> Void)? = nil,
                           completion: @escaping (Result<Bool, Error>) -> Void) {
        let ids = Set(target.tabs.map(\.id))
        let current: () -> Bool = { [weak self] in
            guard let self, !self.isProfileRemovalPending(undo.profileID),
                  undo.matchingTarget(in: self.state) == target else { return false }
            return selection?.isCurrent(for: target, in: self.state) ?? true
        }
        guard !isEphemeral, current(), ids.isDisjoint(with: retiringTabIDs) else { completion(.success(false)); return }
        withRetiredPages(ids, shouldCommit: {
            guard current(), shouldCommit() else { return false }
            return current()
        }, onRefusal: { completion(.success(false)) }) { [weak self] in
            guard let self, current(), let refreshed = undo.refreshed(in: self.state) else { completion(.success(false)); return }
            var next = self.state
            next.tabs.removeAll { ids.contains($0.id) }
            next.recentlyClosedIDs.removeAll { ids.contains($0) }
            self.detachSidebarItems(target, selection: selection, from: &next)
            do {
                try self.commitProfileSettings(next)
                didCommit?(refreshed)
                completion(.success(true))
            } catch { completion(.failure(error)) }
        }
    }

    package func canRestoreSidebarCopy(_ undo: SidebarCopyUndo) -> Bool {
        let folderIDs = Set(undo.folders.map(\.id)), ids = Set(undo.tabs.map(\.id)), groupIDs = Set(undo.groups.map(\.id))
        return !isEphemeral && !isProfileRemovalPending(undo.profileID)
            && state.profiles.contains(where: { $0.id == undo.profileID })
            && state.spaces.contains(where: { $0.id == undo.spaceID && $0.profileID == undo.profileID })
            && folderIDs.count == undo.folders.count && ids.count == undo.tabs.count && groupIDs.count == undo.groups.count
            && state.folders.allSatisfy({ !folderIDs.contains($0.id) })
            && state.tabs.allSatisfy({ !ids.contains($0.id) })
            && state.splitLayouts.allSatisfy({ group in !groupIDs.contains(group.id) && group.tabIDs.allSatisfy { !ids.contains($0) } })
            && undo.locations.allSatisfy({ location in
                location.container.folderID == nil || state.folders.contains(where: {
                    $0.id == location.container.folderID && $0.spaceID == undo.spaceID
                })
            })
            && undo.locations.allSatisfy({ location in
                location.container.section != .favorite
                    || SidebarHierarchy.children(in: location.container, state: state).count
                        + location.siblings.filter(undo.roots.contains).count <= 12
            })
    }

    @discardableResult
    package func restoreSidebarCopy(_ undo: SidebarCopyUndo, shouldCommit: () -> Bool) throws -> Bool {
        let ids = Set(undo.tabs.map(\.id))
        guard canRestoreSidebarCopy(undo), undo.documentsAreAvailable, ids.isDisjoint(with: retiringTabIDs),
              shouldCommit(), canRestoreSidebarCopy(undo), undo.documentsAreAvailable,
              ids.isDisjoint(with: retiringTabIDs) else { return false }
        var next = state
        next.folders += undo.folders
        next.tabs += undo.tabs
        for original in undo.detachedArchive {
            var expected = original; expected.folderID = nil
            if let index = next.tabs.firstIndex(where: { $0 == expected }) { next.tabs[index].folderID = original.folderID }
        }
        next.splitLayouts += undo.groups
        for (key, order) in undo.childOrder { next.sidebarItemOrder[key] = order }
        guard undo.reinsertingRoots(current: state, into: &next) else { return false }
        try commitProfileSettings(next)
        return true
    }

    private func detachSidebarItems(_ target: FolderRemovalTarget, selection: FolderRemovalSelection?,
                                    from next: inout BrowserState) {
        let ids = Set(target.tabs.map(\.id)), spaceID = target.hierarchy.spaceID
        for index in next.tabs.indices where next.tabs[index].folderID.map(target.folderIDs.contains) == true {
            next.tabs[index].folderID = nil
        }
        next.folders.removeAll { target.folderIDs.contains($0.id) }
        next.splitLayouts.removeAll { !$0.tabIDs.allSatisfy { !ids.contains($0) } }
        next.selectedTabIDs.removeAll { ids.contains($0) }
        for key in Array(next.selectionBySpace.keys) { next.selectionBySpace[key]?.removeAll { ids.contains($0) } }
        if let selection {
            next.selectionBySpace[selection.replacementSpaceID.uuidString] = selection.tabIDs
            if next.activeSpaceID == selection.spaceID && state.selectedTabIDs == selection.original {
                next.activeSpaceID = selection.replacementSpaceID
                next.selectedTabIDs = selection.tabIDs
            }
        }
        let deletedContainers = Set(target.folderIDs.map {
            SidebarContainerLocation(spaceID: spaceID, folderID: $0, section: .pinned).key
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
    }

    package func canUndoClosedTabs(_ undo: ClosedTabsUndo) -> Bool {
        !isProfileRemovalPending(undo.profileID)
            && state.profiles.contains(where: { $0.id == undo.profileID })
            && state.spaces.contains(where: { $0.id == undo.spaceID && $0.profileID == undo.profileID })
            && !undo.restorableIDs(in: state).isEmpty
    }

    @discardableResult
    package func undoClosedTabs(_ undo: ClosedTabsUndo, regroupable: (UUID) -> Bool = { _ in true },
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

    package func setSplit(_ ids: [UUID], adding added: UUID? = nil) {
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
    package func setSplitLayout(orientation: SplitOrientation, widthFactors: [Double]) -> Bool {
        guard let factors = BrowserSplitLayout.normalized(widthFactors, count: state.selectedTabIDs.count) else { return false }
        let stacks = activeSplitLayout?.stacks
        let layout = BrowserSplitLayout(id: activeSplitLayout?.id ?? UUID(), sidebarAnchorID: activeSplitLayout?.sidebarAnchorID, customTitle: activeSplitLayout?.customTitle, customIcon: activeSplitLayout?.customIcon, spaceID: activeSplitLayout?.spaceID ?? activeSpaceID, tabIDs: state.selectedTabIDs,
                                        orientation: orientation, widthFactors: stacks?.flattenedFactors ?? factors, stacks: stacks)
        if let index = state.splitLayouts.firstIndex(where: { $0.id == layout.id }) {
            if state.splitLayouts[index] == layout { return true }
            state.splitLayouts[index] = layout
        } else {
            guard let next = admittingNewSplit(layout, in: state) else { return false }
            state = next
        }
        changed()
        return true
    }

    @discardableResult
    package func createFolder(containing items: [SidebarItemReference], folderID: UUID,
                      expected: SidebarHierarchySnapshot) throws -> SidebarFolderFromItems? {
        guard !isEphemeral, !isProfileRemovalPending(expected.profileID),
              let (receipt, next) = SidebarFolderFromItems.make(items: items, folderID: folderID, expected: expected, state: state),
              receipt.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }) else { return nil }
        try commitProfileSettings(next)
        return receipt
    }

    @discardableResult
    package func revertFolderCreation(_ receipt: SidebarFolderFromItems, undo: Bool) throws -> SidebarFolderFromItems? {
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

    @discardableResult
    package func flipSplitOrientation(expected: BrowserSplitLayout) -> Bool {
        guard !isProfileRemovalPending(activeSpace.profileID),
              SidebarSplitItems.groups(in: state, spaceID: activeSpaceID).contains(expected),
              let index = state.splitLayouts.firstIndex(of: expected),
              expected.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }) else { return false }
        var next = state
        next.splitLayouts[index] = expected.transposed()
        do { try commitProfileSettings(next); return true }
        catch { return false }
    }

    @discardableResult
    package func separateAllTabsFromSplit(expected: BrowserSplitLayout, focusedID: UUID?) -> Bool {
        guard !isProfileRemovalPending(activeSpace.profileID),
              SidebarSplitItems.groups(in: state, spaceID: activeSpaceID).contains(expected),
              let index = state.splitLayouts.firstIndex(of: expected),
              expected.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }) else { return false }
        var next = state
        next.splitLayouts.remove(at: index)
        SplitMembership.preservingSlots(before: state, after: &next)
        if next.selectedTabIDs == expected.tabIDs, let first = expected.tabIDs.first {
            let kept = focusedID.flatMap { expected.tabIDs.contains($0) ? $0 : nil } ?? first
            next.selectedTabIDs = [kept]
            next.selectionBySpace[activeSpaceID.uuidString] = [kept]
            if let tab = next.tabIndex(kept) {
                next.tabs[tab].lastAccessed = clock(); next.tabs[tab].isUnread = false
            }
        }
        do { try commitProfileSettings(next); return true }
        catch { return false }
    }

    @discardableResult
    package func resizeSplit(expected: BrowserSplitLayout, widthFactors: [Double]) -> Bool {
        guard activeSplitLayout == expected, state.selectedTabIDs == expected.tabIDs,
              !isProfileRemovalPending(activeSpace.profileID),
              SidebarSplitItems.groups(in: state, spaceID: activeSpaceID).contains(expected),
              expected.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }), expected.stacks == nil,
              let factors = BrowserSplitLayout.normalized(widthFactors, count: expected.tabIDs.count),
              let index = state.splitLayouts.firstIndex(of: expected) else { return false }
        var next = state
        next.splitLayouts[index].widthFactors = factors
        do { try commitProfileSettings(next); return true }
        catch { return false }
    }

    @discardableResult
    package func resizeSplit(expected: BrowserSplitLayout, resized: BrowserSplitLayout) -> Bool {
        var unchanged = resized
        unchanged.widthFactors = expected.widthFactors; unchanged.stacks = expected.stacks
        guard unchanged == expected, resized.stacks?.slotSizes == expected.stacks?.slotSizes,
              let index = editableSplitIndex(expected),
              let factors = BrowserSplitLayout.normalized(resized.widthFactors, count: resized.tabIDs.count) else { return false }
        var layout = resized
        if let stacks = resized.stacks {
            guard let settled = stacks.validated(paneCount: resized.tabIDs.count) else { return false }
            layout.stacks = settled; layout.widthFactors = settled.flattenedFactors
        } else { layout.widthFactors = factors }
        guard layout != expected else { return true }
        var next = state
        next.splitLayouts[index] = layout
        do { try commitProfileSettings(next); return true }
        catch { return false }
    }

    @discardableResult
    package func moveSplitPaneWithinStack(_ id: UUID, offset: Int, expected: BrowserSplitLayout) -> Bool {
        guard let index = editableSplitIndex(expected), let layout = expected.movingWithinStack(id, by: offset) else { return false }
        var next = state
        next.splitLayouts[index] = layout
        next.selectedTabIDs = layout.tabIDs
        next.selectionBySpace[activeSpaceID.uuidString] = layout.tabIDs
        do { try commitProfileSettings(next); return true } catch { return false }
    }

    private func editableSplitIndex(_ expected: BrowserSplitLayout) -> Int? {
        guard activeSplitLayout == expected, state.selectedTabIDs == expected.tabIDs,
              !isProfileRemovalPending(activeSpace.profileID),
              SidebarSplitItems.groups(in: state, spaceID: activeSpaceID).contains(expected),
              expected.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }) else { return nil }
        return state.splitLayouts.firstIndex(of: expected)
    }

    @discardableResult
    package func moveSplitPane(_ id: UUID, offset: Int, expected: BrowserSplitLayout) -> Bool {
        guard (offset == -1 || offset == 1), activeSplitLayout == expected,
              state.selectedTabIDs == expected.tabIDs,
              !isProfileRemovalPending(activeSpace.profileID),
              SidebarSplitItems.groups(in: state, spaceID: activeSpaceID).contains(expected),
              expected.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }),
              let index = expected.tabIDs.firstIndex(of: id),
              let stored = state.splitLayouts.firstIndex(of: expected) else { return false }
        var next = state, layout = expected
        if expected.stacks != nil {
            guard let moved = expected.movingSlot(of: id, by: offset) else { return false }
            layout = moved
        } else {
            guard expected.tabIDs.indices.contains(index + offset) else { return false }
            layout.tabIDs.swapAt(index, index + offset)
            layout.widthFactors.swapAt(index, index + offset)
        }
        next.splitLayouts[stored] = layout
        next.selectedTabIDs = layout.tabIDs
        next.selectionBySpace[activeSpaceID.uuidString] = layout.tabIDs
        do { try commitProfileSettings(next); return true } catch { return false }
    }

    @discardableResult
    package func insertSplitPane(_ request: SplitPaneInsertion, tabID: UUID, navigationURL: URL?,
                         creation: TabCreationProvenance?, savedHomeIDs: [UUID: UUID],
                         documents: [UUID: SidebarDocumentReference],
                         localPage: InternalPage? = nil, localTitle: String? = nil) -> Bool {
        var savedHomeIDs = savedHomeIDs
        let foreign = state.containsTab(tabID, where: { $0.spaceID != request.spaceID && $0.kind != .favorite })
        let foreignHomeID = foreign ? savedHomeIDs.removeValue(forKey: tabID) : nil
        guard (request.selection + [tabID] + Array(savedHomeIDs.values) + [foreignHomeID].compactMap { $0 })
                .allSatisfy({ !retiringTabIDs.contains($0) }),
              let current = request.preparedState(state, tabID: tabID, navigationURL: navigationURL,
                  localPage: localPage, localTitle: localTitle, now: clock(), creation: creation),
              let homes = OriginalSplitDrop.savedHomes(source: tabID, state: current,
                  selection: request.selection, layout: request.layout, target: request.target,
                  orientation: request.orientation, spaceID: request.spaceID),
              SidebarDocumentReference.validates(homes, references: documents),
              let prepared = foreign ? SplitCrossSpaceAdd.relocated(current, source: tabID, into: request.spaceID,
                  profileID: request.profileID, pane: request.paneID, homeID: foreignHomeID, now: clock()) : current,
              let next = OriginalSplitDrop.proposal(source: tabID, state: prepared,
                  selection: request.selection, layout: request.layout, target: request.target,
                  orientation: request.orientation, spaceID: request.spaceID, profileID: request.profileID,
                  now: clock(), savedHomeIDs: savedHomeIDs, creation: creation) else { return false }
        do { try commitProfileSettings(next); return true } catch { return false }
    }

    package func closeSplit() {
        let originalID = activeSplitLayout?.id, before = state
        var next = state
        next.splitLayouts.removeAll { $0.id == originalID }
        SplitMembership.preservingSlots(before: before, after: &next)
        next.selectedTabIDs = Array(next.selectedTabIDs.prefix(1))
        stampSelection(in: &next)
        next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
        state = next
        changed(selectionAlreadyStamped: true)
    }
    @discardableResult
    package func separateSplitPane(_ id: UUID) -> Bool {
        guard let group = activeSplitLayout else { return false }
        return separateTabFromSplit(id, expected: group, focusedID: id)
    }

    @discardableResult
    package func separateTabFromSplit(_ id: UUID, expected: BrowserSplitLayout, focusedID: UUID? = nil) -> Bool {
        guard !isProfileRemovalPending(activeSpace.profileID),
              SidebarSplitItems.groups(in: state, spaceID: activeSpaceID).contains(expected), expected.tabIDs.contains(id),
              let index = state.splitLayouts.firstIndex(of: expected),
              expected.tabIDs.allSatisfy({ !retiringTabIDs.contains($0) }),
              focusedID.map({ state.selectedTabIDs.contains($0) }) ?? true else { return false }
        var next = state, remaining = expected
        let position = remaining.tabIDs.firstIndex(of: id)!
        remaining.removePane(at: position)
        if let weights = BrowserSplitLayout.normalized(remaining.widthFactors, count: remaining.tabIDs.count) {
            remaining.widthFactors = weights
            if remaining.sidebarAnchorID == id { remaining.sidebarAnchorID = remaining.tabIDs.first }
            next.splitLayouts[index] = remaining
        } else { next.splitLayouts.remove(at: index) }
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
                factors = previous.widthFactors
            } else {
                factors = ids.map { id in
                    previous.tabIDs.firstIndex(of: id).map { previous.widthFactors[$0] }
                        ?? (1.0 / Double(previous.tabIDs.count))
                }
            }
        }
        let retained = previous.flatMap { old in ids.contains(where: { old.tabIDs.contains($0) }) ? old : nil }
        var group = BrowserSplitLayout(id: retained?.id ?? UUID(), sidebarAnchorID: retained?.sidebarAnchorID, customTitle: retained?.customTitle, customIcon: retained?.customIcon, spaceID: retained?.spaceID ?? spaceID, tabIDs: ids,
            orientation: orientation, widthFactors: BrowserSplitLayout.normalized(factors, count: ids.count)!, stacks: nil)
        if let retained { group.restack(from: retained) }
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
        layout.removePane(at: pane)
        state.splitLayouts.append(layout)
    }

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
            next.selectedTabIDs = visible.first { $0.tabIDs.contains(first) }?.tabIDs ?? [first]
        } else {
            _ = activateSplit(next.selectedTabIDs, into: &next)
            reconcileSplitLayouts(into: &next)
        }
    }

    package static func reconciledSplitLayouts(in state: BrowserState, activeSpaceID: UUID) -> [BrowserSplitLayout] {
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
            let favoriteProfile = layout.tabIDs.first.flatMap { id in state.tab(id)?.profileID }
                .flatMap { id in SidebarSplitItems.isFavorite(layout, in: state, profileID: id) ? id : nil }
            let ownerProfile = favoriteProfile ?? space.profileID
            var seen = Set<UUID>()
            let positions = layout.tabIDs.indices.filter { index in
                let id = layout.tabIDs[index]
                guard seen.insert(id).inserted, let tab = state.tab(id, where: { $0.archivedAt == nil
                    && $0.profileID == ownerProfile && ($0.kind == .favorite || $0.spaceID == space.id) }) else { return false }
                return tab.kind == .favorite ? !(favorites[ownerProfile] ?? []).contains(id) : !(assigned[space.id] ?? []).contains(id)
            }
            let ids = positions.map { layout.tabIDs[$0] }
            let weights = positions.map { layout.widthFactors[$0] }
            guard let factors = BrowserSplitLayout.normalized(weights, count: ids.count) else { continue }
            let original = layout
            layout.tabIDs = ids
            if layout.sidebarAnchorID.map({ ids.contains($0) }) != true { layout.sidebarAnchorID = ids.first }
            if weights.count != layout.widthFactors.count || abs(weights.reduce(0, +) - 1) > 1e-12 {
                layout.widthFactors = factors
            }
            if let stacks = original.stacks {
                if stacks.validated(paneCount: original.tabIDs.count) == nil {
                    layout.stacks = nil
                } else if ids != original.tabIDs {
                    layout.restack(from: original)
                }
            }
            if layouts.contains(where: { $0.id == layout.id }) { layout.id = UUID() }
            for id in ids {
                if state.containsTab(id, where: { $0.kind == .favorite }) {
                    favorites[ownerProfile, default: []].insert(id)
                } else { assigned[space.id, default: []].insert(id) }
            }
            layouts.append(layout)
        }
        layouts.reverse()
        return layouts
    }

    package func dropExternalURLIntoSplit(_ url: URL, tabID: UUID, spaceID: UUID, profileID: UUID,
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
    package func dropTabIntoSplit(_ id: UUID, expectedSelection: [UUID], expectedLayout: BrowserSplitLayout?,
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

    package func autoArchiveInterval(for profileID: UUID) -> AutoArchiveInterval? {
        state.profiles.first { $0.id == profileID }.flatMap { AutoArchiveInterval(rawValue: $0.autoArchiveHours) }
    }

    @discardableResult
    package func setAutoArchiveInterval(_ interval: AutoArchiveInterval, for profileID: UUID) -> Bool {
        do { _ = try changeAutoArchiveInterval(interval, for: profileID); return true }
        catch { return false }
    }

    @discardableResult
    package func changeAutoArchiveInterval(_ interval: AutoArchiveInterval, for profileID: UUID) throws -> AutoArchiveProfileChange? {
        guard !isProfileRemovalPending(profileID),
              let index = state.profiles.firstIndex(where: { $0.id == profileID }) else {
            throw ProfileSettingsError.unavailable
        }
        guard state.profiles[index].autoArchiveHours != interval.rawValue
                || state.spaces.contains(where: { $0.profileID == profileID && $0.autoArchiveHours != interval.rawValue }) else { return nil }
        var next = state
        next.profiles[index].autoArchiveHours = interval.rawValue
        for i in next.spaces.indices where next.spaces[i].profileID == profileID { next.spaces[i].autoArchiveHours = interval.rawValue }
        if Set(next.profiles.map(\.autoArchiveHours)).count == 1 {
            next.autoArchiveDefaultHours = interval.rawValue
        }
        next.autoArchiveEducationEligible = false
        try commitProfileSettings(next)
        guard state.profiles.count > 1, Set(state.profiles.map(\.autoArchiveHours)).count > 1,
              !state.profiles.contains(where: { isProfileRemovalPending($0.id) }) else { return nil }
        return AutoArchiveProfileChange(profileID: profileID, profiles: state.profiles, interval: interval)
    }

    package func applyAutoArchiveIntervalToAllProfiles(_ change: AutoArchiveProfileChange) throws {
        guard state.profiles == change.profiles,
              state.profiles.contains(where: { $0.id == change.profileID }),
              !state.profiles.contains(where: { isProfileRemovalPending($0.id) }) else {
            throw ProfileSettingsError.unavailable
        }
        var next = state
        for index in next.profiles.indices { next.profiles[index].autoArchiveHours = change.interval.rawValue }
        for index in next.spaces.indices { next.spaces[index].autoArchiveHours = change.interval.rawValue }
        next.autoArchiveDefaultHours = change.interval.rawValue
        next.autoArchiveEducationEligible = false
        try commitProfileSettings(next)
    }

    package func dismissAutoArchiveEducation() {
        autoArchiveEducationPending = false
    }

    package func updateWindowRecords(_ records: [BrowserWindowRecord]) {
        guard !isEphemeral, records != windowRecords else { return }
        windowRecords = records
        scheduleSave()
    }

    package func updateSettings(_ mutation: (inout BrowserSettings) -> Void) {
        var updated = state.settings
        mutation(&updated)
        updated.sidebarWidth = min(500, max(164, updated.sidebarWidth))
        guard updated != state.settings else { return }
        state.settings = updated
        changed()
    }

    package func dismissFavoritesEmptyState(profileID: UUID) {
        guard state.profiles.contains(where: { $0.id == profileID }),
              !state.settings.favoritesEmptyStateDismissed(for: profileID) else { return }
        updateSettings { $0.topAppsEmptyStateDismissedForProfiles = ($0.topAppsEmptyStateDismissedForProfiles ?? []) + [profileID] }
    }

    package func toggleSpaceHeaderOnSingleUnnamedSpaces() {
        updateSettings { $0.showSpaceHeaderOnSingleUnnamedSpaces = !($0.showSpaceHeaderOnSingleUnnamedSpaces ?? false) }
    }

    package func refreshVisibleTabs(_ ids: Set<UUID>) {
        let now = clock()
        var next = state, didChange = false
        for index in next.tabs.indices where ids.contains(next.tabs[index].id) && next.tabs[index].archivedAt == nil {
            if next.tabs[index].lastAccessed != now {
                next.tabs[index].lastAccessed = now
                didChange = true
            }
        }
        guard didChange else { return }
        activityOnlyState = next.attachingTabLookup(after: state)
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
    package func archiveExpiredTabs(protectedTabIDs: Set<UUID> = []) -> [UUID] {
        guard requestPageRetirement == nil else {
            archiveExpiredTabs(protectedTabIDs: protectedTabIDs, completion: { _ in })
            return []
        }
        return finishArchiving(Set(expiredArchiveItems(protectedTabIDs: protectedTabIDs).flatMap(\.tabIDs)))
    }

    package func archiveExpiredTabs(protectedTabIDs: Set<UUID>,
                            currentProtection: (() -> Set<UUID>)? = nil,
                            completion: @escaping ([UUID]) -> Void) {
        let originalItems = expiredArchiveItems(protectedTabIDs: protectedTabIDs.union(currentProtection?() ?? []))
        let candidates = Set(originalItems.flatMap(\.tabIDs))
        guard !candidates.isEmpty else { completion([]); return }
        withRetiredPages(candidates, shouldCommit: { [weak self] in
            guard let self else { return false }
            let protected = protectedTabIDs.union(currentProtection?() ?? [])
            let current = self.expiredArchiveItems(protectedTabIDs: protected)
            return originalItems.allSatisfy { current.contains($0) }
        }, onRefusal: { completion([]) }) { [weak self] in
            guard let self else { completion([]); return }
            completion(self.finishArchiving(candidates))
        }
    }

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
            state.autoArchiveStartedAt = now
            changed()
            return []
        }
        let excluded = protectedTabIDs.union(state.selectedTabIDs)
        var candidates: [AutomaticArchiveItem] = []
        for space in state.spaces {
            guard !isProfileRemovalPending(space.profileID),
                  let threshold = autoArchiveInterval(forSpace: space.id)?.seconds,
                  now.timeIntervalSince(startedAt) > threshold else { continue }
            let location = SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .today)
            for item in SidebarHierarchy.children(in: location, state: state) {
                let ids = SidebarHierarchy.tabIDs(in: item, state: state, spaceID: space.id)
                let tabs = ids.compactMap { id in state.tab(id) }
                guard !ids.isEmpty, tabs.count == ids.count, tabs.allSatisfy({ tab in
                    tab.kind == .today && tab.folderID == nil && tab.archivedAt == nil
                        && tab.profileID == space.profileID && tab.spaceID == space.id
                        && !tab.isUnread && !excluded.contains(tab.id)
                        && now.timeIntervalSince(tab.lastAccessed) > threshold
                        && (!InternalPage.isInternal(tab.url) || InternalPage(urlString: tab.url) != nil)
                }) else { continue }
                let split: BrowserSplitLayout?
                switch item {
                case .tab:
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
        if !isEphemeral && next.autoArchiveEducationEligible && !sidebarBannerOccupied() {
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

    package func reconcileDownloads(profileID: UUID, nativeIDs: Set<String>) {
        guard state.profiles.contains(where: { $0.id == profileID }) else { return }
        let retained = state.downloads.filter { item in
            guard item.profileID == profileID, let nativeID = item.nativeID else { return true }
            return nativeIDs.contains(nativeID)
        }
        guard retained != state.downloads else { return }
        state.downloads = retained; changed()
    }

    package func recordTransientDownload(_ values: [String: Any], contextID: String) {
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
    package func reconcileTransientDownloads(contextID: String, nativeIDs: Set<String>) {
        transientDownloads.removeAll {
            $0.privateContextID == contextID && !($0.nativeID.map(nativeIDs.contains) ?? false)
        }
    }
    package func retireTransientDownloads(contextID: String) {
        transientDownloads.removeAll { $0.privateContextID == contextID }
    }

    package func recordPrivateDownload(_ values: [String: Any]) {
        guard isEphemeral, values["offTheRecord"] as? Bool == true,
              let path = values["profilePath"] as? String,
              path == privateEnginePath else { return }
        recordDownload(values)
    }
    package func clearPrivateDownloads() {
        guard isEphemeral, !state.downloads.isEmpty else { return }
        state.downloads.removeAll(); changed()
    }
    package func recordDownload(_ values: [String: Any]) {
        guard isEphemeral || values["offTheRecord"] as? Bool != true else { return }
        guard let rawID = values["id"] else { return }
        let nativeID = String(describing: rawID)
        let profileID: UUID?
        if let path = values["profilePath"] as? String {
            guard let id = self.profileID(forEnginePath: path) else { return }
            profileID = id
        } else { profileID = nil }
        let id = profileID.map { $0.uuidString + ":" + nativeID } ?? nativeID
        if values["removed"] as? Bool == true {
            state.downloads.removeAll { $0.id == id }; changed(); return
        }
        let value = BrowserDownload.snapshot(values, id: id, nativeID: nativeID, profileID: profileID)
        if let index = state.downloads.firstIndex(where: { $0.id == id }) { state.downloads[index] = value }
        else { state.downloads.append(value) }
        changed()
    }

    package func completeOnboarding(_ draft: OnboardingDraft) throws {
        guard !state.settings.onboardingComplete else { return }
        try commitOnboardingSetup(draft, replay: false)
    }

    package func applyOnboardingReplay(_ draft: OnboardingDraft) throws {
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
        if !name.isEmpty, !replay || name != (draft.replayBaseName ?? space.name) {
            state.spaces[index].title = name; state.spaces[index].updateDisplayName(position: index)
        }
        state.spaces[index].theme = replay && draft.theme == (draft.replayBaseTheme ?? saved) ? saved : draft.theme
        if !replay { state.activeSpaceID = space.id }
        var favorites = Set(state.openTabs(where: { $0.profileID == space.profileID && $0.kind == .favorite }).map { SavedTabURLComparison.key(OnboardingDraft.favoriteKey($0.savedURL)) })
        var pinned = Set(state.openTabs(where: { $0.spaceID == space.id && $0.kind == .pinned }).map(\.savedURL))
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
            state.autoArchiveEducationEligible = true
        }
        do { try save() }
        catch { state = previous; themePreviews = previousPreviews; throw error }
        changed()
    }

    @discardableResult
    package func commitImportedBookmarks(_ roots: [BrowserImportBookmark], destination: BrowserImportDestination) throws -> BrowserImportPlacement {
        try commitImportedBookmarks([(roots, destination, BrowserImportPlacement())])[0]
    }

    package func commitImportedBookmarks(_ pages: [(roots: [BrowserImportBookmark], destination: BrowserImportDestination,
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

    package func importArcSidebar(_ arc: ArcSidebarImport, profiles: [(key: ArcSidebarImport.ProfileKey, name: String)],
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

    package func createImportDestination(name: String, basedOn original: BrowserImportDestination) throws -> BrowserImportDestination {
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
        space.pinnedCollapsed = false
        state.profiles.append(profile); state.spaces.append(space)
        do { try save() } catch { state = previous; throw error }
        changed()
        return BrowserImportDestination(spaceID: space.id, profileID: profile.id)
    }

    package func prepareImportDestination(_ target: BrowserImportProfileTarget,
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
        space.profileID = profile.id; space.pinnedCollapsed = false
        state.spaces.append(space)
        do { try save() } catch { state = previous; throw error }
        changed()
        return BrowserImportDestination(spaceID: space.id, profileID: profile.id)
    }

    package func importBookmarks(_ items: [(title: String, url: String)]) {
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

    package func clearHistory() { clearHistory(profileID: activeSpace.profileID) }
    package func clearHistory(profileID: UUID) {
        state.history.removeAll { $0.profileID == profileID }
        tabHistory?.removeAll()
        historyRevision &+= 1; recordHistoryRemoval(profileID: profileID, urls: nil)
        changed()
    }
    package func deleteHistory(_ ids: Set<UUID>, profileID: UUID) {
        var removed: [UUID: Set<String>] = [:]
        state.history.removeAll { visit in
            guard ids.contains(visit.id) && visit.profileID == profileID else { return false }
            removed[visit.profileID, default: []].insert(visit.url); return true
        }
        tabHistory?.removeAll()
        historyRevision &+= 1; recordHistoryRemovals(removed)
        changed()
    }
    package func forgetHistory(_ deletion: ChromiumHistoryDeletion) {
        let profileID = deletion.profilePath.flatMap(profileID(forEnginePath:))
        guard deletion.profilePath == nil || profileID != nil else { return }
        if let pruning = SessionBackups.Pruning(deletion) { forgetBackups(pruning) }
        var removed: [UUID: Set<String>] = [:]
        state.history.removeAll { visit in
            guard (profileID == nil || visit.profileID == profileID) && deletion.removes(visit) else { return false }
            removed[visit.profileID, default: []].insert(visit.url); return true
        }
        guard !removed.isEmpty else { return }
        historyRevision &+= 1; recordHistoryRemovals(removed, everything: deletion.all)
        changed()
    }
    private func recordHistoryRemovals(_ removed: [UUID: Set<String>], everything: Bool = false) {
        for (profileID, urls) in removed {
            if everything { recordHistoryRemoval(profileID: profileID, urls: nil); continue }
            let remaining = Set(state.history.lazy.filter { $0.profileID == profileID && urls.contains($0.url) }.map(\.url))
            let gone = urls.subtracting(remaining)
            if !gone.isEmpty { recordHistoryRemoval(profileID: profileID, urls: gone) }
        }
    }
    private func recordHistoryRemoval(profileID: UUID, urls: Set<String>?) {
        historyRemovalRevision &+= 1
        historyRemovalLog.append((historyRemovalRevision, profileID,
                                  urls.flatMap { $0.count > Self.historyRemovalURLLimit ? nil : $0 }))
        if historyRemovalLog.count > Self.historyRemovalLogLimit {
            historyRemovalLog.removeFirst(historyRemovalLog.count - Self.historyRemovalLogLimit)
        }
    }
    package func removedHistoryURLs(profileID: UUID, after revision: UInt64) -> Set<String>? {
        guard revision < historyRemovalRevision else { return [] }
        guard let oldest = historyRemovalLog.first, oldest.revision <= revision &+ 1 else { return nil }
        var urls = Set<String>()
        for entry in historyRemovalLog where entry.revision > revision && entry.profileID == profileID {
            guard let removed = entry.urls else { return nil }
            urls.formUnion(removed)
        }
        return urls
    }

    package func save() throws {
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
        var next = state
        let selectedBeforeReconcile = next.selectedTabIDs
        reconcileSplitLayouts(into: &next)
        if !selectionAlreadyStamped || next.selectedTabIDs != selectedBeforeReconcile {
            let key = next.activeSpaceID.uuidString
            if next.selectionBySpace[key] != next.selectedTabIDs {
                next.selectionBySpace[key] = next.selectedTabIDs
            }
        }
        if next != state { state = next }
        scheduleSave()
    }

    package func flushPendingWrites() { sessionWriter.drain() }

    private func scheduleSave() {
        guard !isEphemeral else { return }
        let snapshot = persisted(state)
        if pendingSave != nil, pendingSaveSnapshot == snapshot { return }
        pendingSave?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSave = nil
            self.pendingSaveSnapshot = nil
            try? self.persistSnapshot(self.persisted(self.state), wait: false)
        }
        pendingSave = task
        pendingSaveSnapshot = snapshot
        scheduleDeferredSave(0.25, task)
    }

    private func persistSnapshot(_ snapshot: BrowserState, wait: Bool) throws {
        guard !isEphemeral else { return }
        let url = stateURL, date = clock()
        if wait {
            var caught: Error?
            sessionWriter.write(snapshot, to: url, at: date, wait: true, allowSkip: false) { caught = $0 }
            if let caught { throw caught }
            return
        }
        sessionWriter.write(snapshot, to: url, at: date, wait: false, allowSkip: true) { [weak self] error in
            DispatchQueue.main.async { self?.reportPersistence(error) }
        }
    }

    private func forgetBackups(_ pruning: SessionBackups.Pruning) {
        guard !isEphemeral else { return }
        sessionWriter.forgetBackups(pruning, in: directory, current: persisted(state), at: clock())
    }

    private func reportPersistence(_ error: Error?) {
        let message = error?.localizedDescription
        if persistenceError != message { persistenceError = message }
    }

    private func beginFreshSession() {
        let closedAt = clock()
        let provenance = archiveProvenance(for: Set(state.openTabs(where: { $0.kind == .today }).map(\.id)), reason: .session)
        var next = state
        for index in next.tabs.indices where next.tabs[index].archivedAt == nil {
            if next.tabs[index].kind == .today {
                let id = next.tabs[index].id
                next.tabs[index].archiveProvenance = provenance[id]
                next.tabs[index].archivedAt = closedAt
                next.recentlyClosedIDs.removeAll { $0 == id }
                next.recentlyClosedIDs.append(id)
            } else {
                next.tabs[index].url = next.tabs[index].savedURL
                next.tabs[index].title = next.tabs[index].savedTitle
            }
        }
        next.selectedTabIDs = []
        next.selectionBySpace = [:]
        next.splitLayouts = []
        state = next
    }

    private func normalizeSelection(selectFallback: Bool = true) {
        var next = state
        normalizeSelection(in: &next, selectFallback: selectFallback)
        state = next
    }

    private func normalizeSelection(in next: inout BrowserState, selectFallback: Bool = true) {
        let spaceID = next.activeSpaceID
        let space = next.spaces.first { $0.id == spaceID } ?? next.spaces[0]
        let visible = next.openTabs(where: { ($0.kind == .favorite ? $0.profileID == space.profileID : $0.spaceID == spaceID) })
        let available = Set(visible.map(\.id))
        var seen = Set<UUID>()
        next.selectedTabIDs = Array(next.selectedTabIDs.filter { available.contains($0) && seen.insert($0).inserted }.prefix(4))
        if selectFallback && next.selectedTabIDs.isEmpty { next.selectedTabIDs = Array(visible.suffix(1).map(\.id)) }
    }

    package nonisolated static func validateSaved(_ state: BrowserState) throws {
        if let id = state.settings.defaultProfileID, !state.profiles.contains(where: { $0.id == id }) {
            throw CocoaError(.fileReadCorruptFile)
        }
        var removalIDs = Set<UUID>(), removalProfiles = Set<UUID>()
        for record in state.profileRemovals {
            guard removalIDs.insert(record.id).inserted, removalProfiles.insert(record.profileID).inserted,
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
                  layout.tabIDs.allSatisfy({ id in state.containsTab(id, where: { $0.archivedAt == nil
                      && (($0.profileID == space.profileID && ($0.kind == .favorite || $0.spaceID == space.id))
                          || SidebarSplitItems.isFavorite(layout, in: state, profileID: $0.profileID)) }) })
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


package enum ProfileSettingsError: LocalizedError {
    case invalidSidebarWidth
    case emptyName, unavailable, nameChanged
    package var errorDescription: String? {
        switch self {
        case .invalidSidebarWidth: return "Choose a valid sidebar width."
        case .emptyName: return "Enter a name for this profile."
        case .unavailable: return "This profile is no longer available."
        case .nameChanged: return "This profile was renamed in another window. Cancel and reopen Rename to use its current name."
        }
    }
}


package enum SplitDropTarget: Equatable {
    case insert(Int)
    case replace(Int)
    case stack(Int, after: Bool)

    package var isStack: Bool {
        if case .stack = self { return true }
        return false
    }
}

package enum ExternalSplitDrop {
    package static func url(_ string: String) -> URL? {
        guard !string.isEmpty, string == string.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), url.host?.isEmpty == false,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    package static func savedHomeSource(state: BrowserState, selection: [UUID],
                                layout: BrowserSplitLayout?, target: SplitDropTarget) -> BrowserTab? {
        guard layout == nil, selection.count == 1, case .insert = target else { return nil }
        return state.tab(selection[0], where: { ($0.kind == .favorite || $0.kind == .pinned) })
    }

    package static func proposal(url: URL, tabID: UUID, state: BrowserState,
                         spaceID: UUID, profileID: UUID, selection: [UUID],
                         layout: BrowserSplitLayout?, target: SplitDropTarget,
                         orientation: SplitOrientation, creation: TabCreationProvenance?,
                         now: Date, savedHomeID: UUID? = nil) -> BrowserState? {
        guard Self.url(url.absoluteString) == url, state.activeSpaceID == spaceID,
              state.profiles.contains(where: { $0.id == profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == profileID }),
              state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }),
              state.selectedTabIDs == selection, !state.containsTab(tabID),
              !selection.isEmpty else { return nil }
        let originals = selection.compactMap { id in state.tab(id, where: { $0.archivedAt == nil
            && $0.profileID == profileID && ($0.kind == .favorite || $0.spaceID == spaceID) }) }
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


package enum SplitDropTransaction {
    package static func make(source: UUID, selection: [UUID], layout: BrowserSplitLayout?,
                     target: SplitDropTarget, orientation: SplitOrientation,
                     spaceID: UUID) -> BrowserSplitLayout? {
        guard !selection.isEmpty, selection.count <= 4, Set(selection).count == selection.count, !selection.contains(source),
              layout == nil || (layout?.spaceID == spaceID && layout?.tabIDs == selection),
              selection.count == 1 || layout != nil,
              layout == nil || BrowserSplitLayout.normalized(layout!.widthFactors, count: selection.count) != nil else { return nil }
        if let layout, layout.stacks != nil || target.isStack {
            return stacked(source: source, selection: selection, layout: layout, target: target,
                           orientation: orientation, spaceID: spaceID)
        }
        var ids = selection
        switch target {
        case .insert(let index):
            guard (0...ids.count).contains(index), ids.count < 4 else { return nil }
            ids.insert(source, at: index)
        case .replace(let index):
            guard ids.indices.contains(index) else { return nil }
            ids[index] = source
        case .stack:
            return nil
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
            spaceID: spaceID, tabIDs: ids, orientation: orientation, widthFactors: factors, stacks: nil)
    }

    private static func stacked(source: UUID, selection: [UUID], layout: BrowserSplitLayout,
                                target: SplitDropTarget, orientation: SplitOrientation, spaceID: UUID) -> BrowserSplitLayout? {
        var group = layout
        switch target {
        case .stack(let index, let after):
            guard let inserted = layout.insertingIntoStack(source, besidePaneAt: index, after: after) else { return nil }
            group = inserted
        case .insert(let index):
            guard orientation == layout.orientation, selection.count < 4, layout.slotBoundaries.contains(index) else { return nil }
            group.tabIDs.insert(source, at: index)
            group.restack(from: layout)
        case .replace(let index):
            guard orientation == layout.orientation, selection.indices.contains(index) else { return nil }
            group.tabIDs[index] = source
        }
        group.spaceID = spaceID
        if group.sidebarAnchorID.map(group.tabIDs.contains) != true { group.sidebarAnchorID = group.tabIDs.first }
        return group
    }
}

package enum SidebarSplitItems {
    package static func isFavorite(_ group: BrowserSplitLayout, in state: BrowserState, profileID: UUID) -> Bool {
        group.tabIDs.count > 1 && group.tabIDs.allSatisfy { id in
            state.containsTab(id, where: { $0.archivedAt == nil && $0.profileID == profileID && $0.kind == .favorite && $0.folderID == nil })
        }
    }
    package static func groups(in state: BrowserState, spaceID: UUID) -> [BrowserSplitLayout] {
        guard let space = state.spaces.first(where: { $0.id == spaceID }) else { return [] }
        return state.splitLayouts.filter { group in
            (group.spaceID == spaceID || isFavorite(group, in: state, profileID: space.profileID)) && group.tabIDs.count > 1 && group.tabIDs.allSatisfy { id in
                state.containsTab(id, where: { $0.archivedAt == nil && $0.profileID == space.profileID
                    && ($0.kind == .favorite || $0.spaceID == spaceID) })
            }
        }
    }
}

extension BrowserStore {
    package struct ApplicationContext: Equatable {
        package let profileID: UUID
        package let spaceID: UUID?
    }

    package func applicationContext(from source: BrowserStore, spaceID: UUID) -> ApplicationContext? {
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

package enum SidebarTabTitle {
    package static func currentRenameTab(state: BrowserState, spaceID: UUID, profileID: UUID,
                                 selectedTabIDs: [UUID]) -> BrowserTab? {
        guard selectedTabIDs.count == 1, let id = selectedTabIDs.first,
              state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }),
              !state.splitLayouts.contains(where: { $0.spaceID == spaceID && $0.tabIDs.contains(id) }),
              let tab = state.tab(id, where: { $0.spaceID == spaceID
                  && $0.profileID == profileID && $0.archivedAt == nil }),
              tab.kind != .favorite, !InternalPage.isInternal(tab.url) else { return nil }
        return tab
    }

    package enum EditError: LocalizedError {
        case unavailable
        package var errorDescription: String? { "This tab changed while its name was being edited. Please try again." }
    }

    package static func isRenameable(_ tab: BrowserTab) -> Bool {
        tab.kind != .favorite && !InternalPage.isInternal(tab.url)
    }

    package static func customValue(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    package static func display(_ tab: BrowserTab) -> String {
        if let custom = tab.customTitle { return custom }
        if let saved = customValue(tab.savedTitle), saved != "about:blank" { return saved }
        return tab.savedURL.isEmpty || tab.savedURL == "about:blank" ? "New tab" : tab.savedURL
    }

    package static func sameItemForEditing(_ current: BrowserTab, _ original: BrowserTab) -> Bool {
        current.id == original.id && current.spaceID == original.spaceID &&
            current.profileID == original.profileID && current.kind == original.kind &&
            current.folderID == original.folderID && current.archivedAt == nil &&
            original.archivedAt == nil && current.customTitle == original.customTitle &&
            (current.kind == .today || current.savedURL == original.savedURL)
    }
}

package struct SidebarTabTitleChange: Equatable {
    package let tabID: UUID
    package let profileID: UUID
    package let previousTitle: String?
    package let title: String?
    package var actionName: String { "Rename Item" }

    package init(tabID: UUID, profileID: UUID, previousTitle: String?, title: String?) {
        self.tabID = tabID
        self.profileID = profileID
        self.previousTitle = previousTitle
        self.title = title
    }

    package func target(in state: BrowserState, undo: Bool) -> BrowserTab? {
        guard previousTitle != title, state.profiles.contains(where: { $0.id == profileID }),
              let tab = state.tab(tabID, where: { $0.profileID == profileID }),
              tab.archivedAt == nil, tab.customTitle == (undo ? title : previousTitle) else { return nil }
        return tab
    }
}

package struct SidebarSplitTitleEdit: Equatable {
    package let group: BrowserSplitLayout
    package let profileID: UUID
    package let children: [BrowserTab]

    package init?(group: BrowserSplitLayout, profileID: UUID, state: BrowserState) {
        guard state.spaces.contains(where: { $0.id == group.spaceID && $0.profileID == profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == profileID }),
              SidebarSplitItems.groups(in: state, spaceID: group.spaceID).contains(group) else { return nil }
        let children = group.tabIDs.compactMap { id in state.tab(id) }
        guard children.count == group.tabIDs.count,
              ((children.allSatisfy({ $0.profileID == profileID && $0.spaceID == group.spaceID
                  && $0.kind != .favorite && $0.archivedAt == nil })) || SidebarSplitItems.isFavorite(group, in: state, profileID: profileID)) else { return nil }
        self.group = group; self.profileID = profileID; self.children = children
    }

    package var isFavorite: Bool { children.allSatisfy { $0.kind == .favorite } }
    package func isVisible(in spaceID: UUID, state: BrowserState) -> Bool {
        state.spaces.contains { $0.id == spaceID && $0.profileID == profileID } && (group.spaceID == spaceID || isFavorite)
    }

    package func matches(_ state: BrowserState) -> Bool {
        guard state.spaces.contains(where: { $0.id == group.spaceID && $0.profileID == profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == profileID }),
              state.splitLayouts.contains(group) else { return false }
        return children.allSatisfy { original in
            state.tabs.contains { current in SidebarTabTitle.sameItemForEditing(current, original) }
        }
    }

    package static func current(state: BrowserState, spaceID: UUID, profileID: UUID,
                        selectedTabIDs: [UUID]) -> Self? {
        guard selectedTabIDs.count > 1,
              let group = SidebarSplitItems.groups(in: state, spaceID: spaceID).first(where: { $0.tabIDs == selectedTabIDs }) else { return nil }
        return Self(group: group, profileID: profileID, state: state)
    }

    package enum EditError: LocalizedError {
        case unavailable
        package var errorDescription: String? { "This Split View changed while its name was being edited. Please try again." }
    }
}

package struct SidebarSplitTitleChange: Equatable {
    package let containerID: UUID
    package let profileID: UUID
    package let previousTitle: String?
    package let title: String?
    package var actionName: String { "Rename Item" }

    package init(containerID: UUID, profileID: UUID, previousTitle: String?, title: String?) {
        self.containerID = containerID
        self.profileID = profileID
        self.previousTitle = previousTitle
        self.title = title
    }

    package func target(in state: BrowserState, undo: Bool) -> BrowserSplitLayout? {
        guard previousTitle != title, state.profiles.contains(where: { $0.id == profileID }),
              let group = state.splitLayouts.first(where: { $0.id == containerID }),
              group.customTitle == (undo ? title : previousTitle),
              state.spaces.contains(where: { $0.id == group.spaceID && $0.profileID == profileID }),
              SidebarSplitTitleEdit(group: group, profileID: profileID, state: state) != nil else { return nil }
        return group
    }
}

package struct SidebarSplitAppearanceChange: Equatable {
    package let containerID: UUID
    package let profileID: UUID
    package let previousTitle: String?
    package let title: String?
    package let previousIcon: SidebarGroupIcon?
    package let icon: SidebarGroupIcon?
    package let resetsTitle: Bool
    package var actionName: String { resetsTitle ? "Reset Name and Icon" : "Customize Tab" }

    package init(containerID: UUID, profileID: UUID, previousTitle: String?, title: String?, previousIcon: SidebarGroupIcon?, icon: SidebarGroupIcon?, resetsTitle: Bool) {
        self.containerID = containerID
        self.profileID = profileID
        self.previousTitle = previousTitle
        self.title = title
        self.previousIcon = previousIcon
        self.icon = icon
        self.resetsTitle = resetsTitle
    }
    package func target(in state: BrowserState, undo: Bool) -> BrowserSplitLayout? {
        guard let group = state.splitLayouts.first(where: { $0.id == containerID }),
              group.customIcon == (undo ? icon : previousIcon),
              !resetsTitle || group.customTitle == (undo ? title : previousTitle),
              SidebarSplitTitleEdit(group: group, profileID: profileID, state: state) != nil else { return nil }
        return group
    }
}

private final class SessionFileWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.parc.session-save", qos: .utility)
    private var lastWritten: BrowserState?
    private var lastWrittenBytes: Data?
    private var lastWrittenHistory: [BrowserHistoryEntry]?
    private var historyRecords = 0
    private var historyPreserved = false
    private var backups: SessionBackups?

    func drain() { queue.sync {} }
    func preserveHistoryFile() { queue.sync { historyPreserved = true } }
    func keepBackups(_ value: SessionBackups) { queue.sync { backups = value } }
    func backUpIfDue(_ snapshot: BrowserState, at date: Date) {
        queue.async { self.backups?.backUpIfDue(snapshot, at: date) }
    }
    func forgetBackups(_ pruning: SessionBackups.Pruning, in directory: URL, current: BrowserState, at date: Date) {
        queue.sync {
            guard let pruning = pruning.excluding(try? SessionBackups.encoded(current)) else { return }
            if let backups { backups.forget(pruning) } else { SessionBackups.prune(pruning, in: directory) }
        }
        backUpIfDue(current, at: date)
    }

    func write(_ snapshot: BrowserState, to url: URL, at date: Date, wait: Bool, allowSkip: Bool,
               completion: @escaping (Error?) -> Void) {
        let work = {
            do {
                try self.encodeAndReplace(snapshot, to: url, at: date, allowSkip: allowSkip)
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

    private func encodeAndReplace(_ snapshot: BrowserState, to url: URL, at date: Date, allowSkip: Bool) throws {
        if allowSkip, lastWritten == snapshot { return }
        try persistHistory(snapshot.history,
                           at: url.deletingLastPathComponent().appendingPathComponent(BrowserHistoryFile.name))
        var session = snapshot
        session.history = []
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        if lastWrittenBytes != data || !FileManager.default.fileExists(atPath: url.path) {
            do { try Self.replaceAtomically(data, at: url) } catch {
                lastWritten = nil
                throw error
            }
            lastWrittenBytes = data
        }
        lastWritten = snapshot
        backups?.backUpIfDue(session, at: date)
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
