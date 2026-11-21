import Foundation

enum SidebarDocumentKind: Hashable, Sendable {
    case note(URL)
    case easel(UUID)

    init?(url: URL) {
        if url.isFileURL {
            guard NoteFileKind(url: url) != nil else { return nil }
            self = .note(url.standardizedFileURL)
            return
        }
        guard url.scheme?.lowercased() == "parc", url.host?.lowercased() == "easel", url.query == nil, url.fragment == nil,
              url.path.hasPrefix("/"), let id = UUID(uuidString: String(url.path.dropFirst())) else { return nil }
        self = .easel(id)
    }

    var cacheKey: String {
        switch self {
        case .note(let url): return "note:" + url.standardizedFileURL.path
        case .easel(let id): return "easel:" + id.uuidString.lowercased()
        }
    }

    var isNote: Bool { if case .note = self { return true }; return false }
}

enum SidebarDocumentAvailability: Equatable, Sendable {
    case available
    case missing
}

struct SidebarDocumentContent: Equatable, Sendable {
    var availability: SidebarDocumentAvailability = .available
    var snippet = ""
    var objectCount: Int?
}

enum SidebarDocumentButton: Equatable, Sendable {
    case peek, copyLink, split
}

enum SidebarDocumentPreviewText {
    static func kindName(_ kind: SidebarDocumentKind) -> String { kind.isNote ? "Note" : "Easel" }

    static func missing(_ kind: SidebarDocumentKind) -> String {
        kind.isNote ? "This note moved or was deleted" : "This Easel was deleted"
    }

    static func objects(_ count: Int) -> String {
        switch count {
        case 0: return "No objects yet"
        case 1: return "1 object"
        default: return "\(count) objects"
        }
    }

    static func subtitle(_ kind: SidebarDocumentKind, content: SidebarDocumentContent) -> String {
        guard content.availability == .available, let count = content.objectCount, !kind.isNote else { return kindName(kind) }
        return kindName(kind) + " · " + objects(count)
    }

    static func body(_ kind: SidebarDocumentKind, content: SidebarDocumentContent) -> String {
        if content.availability == .missing { return missing(kind) }
        let snippet = content.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        if !snippet.isEmpty { return snippet }
        if kind.isNote { return "Empty note" }
        return objects(content.objectCount ?? 0)
    }
}

enum SidebarDocumentPreviewButtons {
    static func buttons(availability: SidebarDocumentAvailability, peekAdmitsDocuments: Bool) -> [SidebarDocumentButton] {
        guard availability == .available else { return [] }
        return (peekAdmitsDocuments ? [.peek] : []) + [.copyLink, .split]
    }
}

struct SidebarThumbnailCache<Image, Revision: Hashable> {
    struct Key: Hashable {
        let document: String
        let appearance: String
    }

    private struct Entry {
        var image: Image
        var revision: Revision
    }

    let capacity: Int
    let interval: TimeInterval
    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []
    private var renderedAt: [Key: Date] = [:]

    init(capacity: Int = 48, interval: TimeInterval = 1) {
        self.capacity = max(1, capacity)
        self.interval = max(0, interval)
    }

    var count: Int { entries.count }

    func fresh(_ key: Key, revision: Revision) -> Image? {
        guard let entry = entries[key], entry.revision == revision else { return nil }
        return entry.image
    }

    func latest(_ key: Key) -> Image? { entries[key]?.image }

    mutating func store(_ image: Image, for key: Key, revision: Revision, now: Date) {
        entries[key] = Entry(image: image, revision: revision)
        renderedAt[key] = now
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity {
            let evicted = order.removeFirst()
            entries.removeValue(forKey: evicted)
            renderedAt.removeValue(forKey: evicted)
        }
    }

    mutating func touch(_ key: Key) {
        guard entries[key] != nil, order.last != key else { return }
        order.removeAll { $0 == key }
        order.append(key)
    }

    mutating func invalidate(document: String) {
        let keys = entries.keys.filter { $0.document == document }
        for key in keys { entries.removeValue(forKey: key) }
        order.removeAll { $0.document == document }
    }

    mutating func removeAll() {
        entries.removeAll(); order.removeAll(); renderedAt.removeAll()
    }

    func renderDelay(_ key: Key, now: Date) -> TimeInterval {
        guard let last = renderedAt[key] else { return 0 }
        let elapsed = now.timeIntervalSince(last)
        guard elapsed >= 0 else { return interval }
        return max(0, interval - elapsed)
    }
}
