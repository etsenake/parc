import Foundation

package enum SidebarDocumentKind: Hashable, Sendable {
    case note(URL)
    case easel(UUID)

    package init?(url: URL) {
        if url.isFileURL {
            guard NoteFileKind(url: url) != nil else { return nil }
            self = .note(url.standardizedFileURL)
            return
        }
        guard url.scheme?.lowercased() == "parc", url.host?.lowercased() == "easel", url.query == nil, url.fragment == nil,
              url.path.hasPrefix("/"), let id = UUID(uuidString: String(url.path.dropFirst())) else { return nil }
        self = .easel(id)
    }

    package var cacheKey: String {
        switch self {
        case .note(let url): return "note:" + url.standardizedFileURL.path
        case .easel(let id): return "easel:" + id.uuidString.lowercased()
        }
    }

    package var isNote: Bool { if case .note = self { return true }; return false }
}

package enum SidebarDocumentAvailability: Equatable, Sendable {
    case available
    case missing
}

package struct SidebarDocumentContent: Equatable, Sendable {
    package var availability: SidebarDocumentAvailability = .available
    package var snippet = ""
    package var objectCount: Int?

    package init(availability: SidebarDocumentAvailability = .available, snippet: String = "", objectCount: Int? = nil) {
        self.availability = availability
        self.snippet = snippet
        self.objectCount = objectCount
    }
}

package enum SidebarDocumentButton: Equatable, Sendable {
    case peek, copyLink, split
}

package enum SidebarDocumentPreviewText {
    package static func kindName(_ kind: SidebarDocumentKind) -> String { kind.isNote ? "Note" : "Easel" }

    package static func missing(_ kind: SidebarDocumentKind) -> String {
        kind.isNote ? "This note moved or was deleted" : "This Easel was deleted"
    }

    package static func objects(_ count: Int) -> String {
        switch count {
        case 0: return "No objects yet"
        case 1: return "1 object"
        default: return "\(count) objects"
        }
    }

    package static func subtitle(_ kind: SidebarDocumentKind, content: SidebarDocumentContent) -> String {
        guard content.availability == .available, let count = content.objectCount, !kind.isNote else { return kindName(kind) }
        return kindName(kind) + " · " + objects(count)
    }

    package static func body(_ kind: SidebarDocumentKind, content: SidebarDocumentContent) -> String {
        if content.availability == .missing { return missing(kind) }
        let snippet = content.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        if !snippet.isEmpty { return snippet }
        if kind.isNote { return "Empty note" }
        return objects(content.objectCount ?? 0)
    }
}

package enum SidebarDocumentPreviewButtons {
    package static func buttons(availability: SidebarDocumentAvailability, peekAdmitsDocuments: Bool) -> [SidebarDocumentButton] {
        guard availability == .available else { return [] }
        return (peekAdmitsDocuments ? [.peek] : []) + [.copyLink, .split]
    }
}

package struct SidebarThumbnailCache<Image, Revision: Hashable> {
    package struct Key: Hashable {
        package let document: String
        package let appearance: String

        package init(document: String, appearance: String) {
            self.document = document
            self.appearance = appearance
        }
    }

    private struct Entry {
        var image: Image
        var revision: Revision

        package init(image: Image, revision: Revision) {
            self.image = image
            self.revision = revision
        }
    }

    package let capacity: Int
    package let interval: TimeInterval
    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []
    private var renderedAt: [Key: Date] = [:]

    package init(capacity: Int = 48, interval: TimeInterval = 1) {
        self.capacity = max(1, capacity)
        self.interval = max(0, interval)
    }

    package var count: Int { entries.count }

    package func fresh(_ key: Key, revision: Revision) -> Image? {
        guard let entry = entries[key], entry.revision == revision else { return nil }
        return entry.image
    }

    package func latest(_ key: Key) -> Image? { entries[key]?.image }

    package mutating func store(_ image: Image, for key: Key, revision: Revision, now: Date) {
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

    package mutating func touch(_ key: Key) {
        guard entries[key] != nil, order.last != key else { return }
        order.removeAll { $0 == key }
        order.append(key)
    }

    package mutating func invalidate(document: String) {
        let keys = entries.keys.filter { $0.document == document }
        for key in keys { entries.removeValue(forKey: key) }
        order.removeAll { $0.document == document }
    }

    package mutating func removeAll() {
        entries.removeAll(); order.removeAll(); renderedAt.removeAll()
    }

    package func renderDelay(_ key: Key, now: Date) -> TimeInterval {
        guard let last = renderedAt[key] else { return 0 }
        let elapsed = now.timeIntervalSince(last)
        guard elapsed >= 0 else { return interval }
        return max(0, interval - elapsed)
    }
}
