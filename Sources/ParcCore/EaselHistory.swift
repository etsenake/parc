import Foundation
import Combine

package struct EaselVersion: Identifiable, Hashable {
    package var id: String
    package var savedAt: Date
    package var itemCount: Int

    package init(id: String, savedAt: Date, itemCount: Int) {
        self.id = id
        self.savedAt = savedAt
        self.itemCount = itemCount
    }
}

struct EaselHistoryPolicy: Equatable {
    var minimumInterval: TimeInterval = 300
    var idleDelay: TimeInterval = 120
    var maximumVersions = 40
    var maximumBytes = 96 * 1024 * 1024
    init(minimumInterval: TimeInterval = 300, idleDelay: TimeInterval = 120, maximumVersions: Int = 40, maximumBytes: Int = 96 * 1024 * 1024) {
        self.minimumInterval = minimumInterval
        self.idleDelay = idleDelay
        self.maximumVersions = maximumVersions
        self.maximumBytes = maximumBytes
    }

    func shouldRecord(lastRecordedAt: Date?, now: Date) -> Bool {
        guard let lastRecordedAt else { return true }
        return now.timeIntervalSince(lastRecordedAt) >= minimumInterval
    }

    func expired(_ versions: [(version: EaselVersion, bytes: Int)]) -> [EaselVersion] {
        var kept = 0, bytes = 0
        var removed: [EaselVersion] = []
        for entry in versions.sorted(by: { $0.version.savedAt == $1.version.savedAt ? $0.version.id > $1.version.id : $0.version.savedAt > $1.version.savedAt }) {
            if kept < maximumVersions, kept == 0 || bytes + entry.bytes <= maximumBytes {
                kept += 1
                bytes += entry.bytes
            } else {
                removed.append(entry.version)
            }
        }
        return removed
    }
}

@MainActor
package final class EaselHistory {
    nonisolated static let maximumDocumentBytes = 8 * 1024 * 1024
    let directory: URL
    var policy = EaselHistoryPolicy()
    private var lastRecordedAt: [UUID: Date] = [:]
    private var lastRecorded: [UUID: EaselDocument] = [:]
    private var lastSeen: [UUID: EaselDocument] = [:]
    private var idleTimers: [UUID: Timer] = [:]
    private var followers: [UUID: AnyCancellable] = [:]
    private let writer = DispatchQueue(label: "org.parc.easel-history", qos: .utility)

    init(directory: URL) {
        self.directory = directory.standardizedFileURL
    }

    func folder(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    nonisolated static let maximumSavedSeconds = 1e13

    nonisolated static func fileName(savedAt: Date, itemCount: Int) -> String {
        let millis = Int64((min(max(0, savedAt.timeIntervalSince1970), maximumSavedSeconds) * 1000).rounded())
        return "v-\(millis)-\(max(0, itemCount)).json"
    }

    nonisolated static func parse(_ name: String) -> (savedAt: Date, itemCount: Int)? {
        guard name.hasPrefix("v-"), name.hasSuffix(".json"), name.utf8.count <= 64 else { return nil }
        let parts = name.dropFirst(2).dropLast(5).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let millis = Int64(parts[0]), let count = Int(parts[1]), millis >= 0, count >= 0 else { return nil }
        return (Date(timeIntervalSince1970: Double(millis) / 1000), count)
    }

    func follow(_ document: EaselDocument, changes: AnyPublisher<EaselDocument, Never>) {
        let id = document.id
        lastSeen[id] = document
        followers[id] = changes.sink { [weak self] next in
            MainActor.assumeIsolated {
                guard let self, let previous = self.lastSeen[id], previous != next else { return }
                self.lastSeen[id] = next
                self.documentDidChange(from: previous, to: next, now: next.modifiedAt)
            }
        }
    }

    package func versions(of id: UUID) -> [EaselVersion] {
        writer.sync {}
        return Self.listing(folder(for: id)).map(\.version)
    }

    package func document(_ version: EaselVersion, of id: UUID) throws -> EaselDocument {
        guard Self.parse(version.id) != nil, !version.id.contains("/") else { throw EaselStoreError.unsafePath }
        writer.sync {}
        let url = folder(for: id).appendingPathComponent(version.id)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw EaselStoreError.unsafePath }
        guard (values.fileSize ?? Int.max) <= Self.maximumDocumentBytes else { throw EaselStoreError.documentTooLarge }
        let document = try JSONDecoder().decode(EaselDocument.self, from: Data(contentsOf: url))
        guard document.id == id else { throw EaselStoreError.invalidDocument("the version belongs to another Easel") }
        return EaselStore.repairingStackOrder(EaselStore.repairingDuplicateIDs(document))
    }

    func documentDidChange(from previous: EaselDocument, to next: EaselDocument, now: Date) {
        if lastRecordedAt[next.id] == nil {
            record(previous, savedAt: previous.modifiedAt)
            lastRecordedAt[next.id] = now
        } else if policy.shouldRecord(lastRecordedAt: lastRecordedAt[next.id], now: now) {
            record(next, savedAt: now)
            lastRecordedAt[next.id] = now
        }
        scheduleIdle(next)
    }

    @discardableResult
    package func record(_ document: EaselDocument, savedAt: Date, wait: Bool = false) -> Bool {
        let comparable = Self.comparable(document)
        if lastRecorded[document.id] == nil, let newest = versions(of: document.id).first,
           let stored = try? self.document(newest, of: document.id) {
            lastRecorded[document.id] = Self.comparable(stored)
        }
        guard lastRecorded[document.id] != comparable else { return false }
        lastRecorded[document.id] = comparable
        let folder = folder(for: document.id), root = directory, policy = policy
        let name = Self.fileName(savedAt: savedAt, itemCount: document.items.count)
        let work: @Sendable () -> Void = { Self.write(document, name: name, folder: folder, root: root, policy: policy) }
        if wait { writer.sync(execute: work) } else { writer.async(execute: work) }
        return true
    }

    func removeAll(for id: UUID) {
        idleTimers.removeValue(forKey: id)?.invalidate()
        followers.removeValue(forKey: id)
        lastRecordedAt.removeValue(forKey: id)
        lastRecorded.removeValue(forKey: id)
        lastSeen.removeValue(forKey: id)
        let folder = folder(for: id)
        writer.sync {
            guard (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return }
            try? FileManager.default.removeItem(at: folder)
        }
    }

    package func flush() {
        writer.sync {}
    }

    private func scheduleIdle(_ document: EaselDocument) {
        idleTimers[document.id]?.invalidate()
        let id = document.id
        let timer = Timer(timeInterval: policy.idleDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.idleTimers.removeValue(forKey: id)
                let latest = self.lastSeen[id] ?? document
                if self.record(latest, savedAt: latest.modifiedAt) { self.lastRecordedAt[id] = latest.modifiedAt }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimers[id] = timer
    }

    private static func comparable(_ document: EaselDocument) -> EaselDocument {
        var copy = document
        copy.modifiedAt = Date(timeIntervalSinceReferenceDate: 0)
        return copy
    }

    nonisolated private static func listing(_ folder: URL) -> [(version: EaselVersion, bytes: Int)] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                                                     options: [.skipsHiddenFiles]) else { return [] }
        return urls.compactMap { url -> (version: EaselVersion, bytes: Int)? in
            guard let parsed = parse(url.lastPathComponent),
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true else { return nil }
            return (EaselVersion(id: url.lastPathComponent, savedAt: parsed.savedAt, itemCount: parsed.itemCount), values.fileSize ?? 0)
        }.sorted { $0.version.savedAt == $1.version.savedAt ? $0.version.id > $1.version.id : $0.version.savedAt > $1.version.savedAt }
    }

    nonisolated private static func write(_ document: EaselDocument, name: String, folder: URL, root: URL, policy: EaselHistoryPolicy) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(document), data.count <= maximumDocumentBytes else { return }
        do {
            for url in [root, folder] {
                if !FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                }
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { return }
            }
            let target = folder.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: target.path) else { return }
            try data.write(to: target, options: .atomic)
            for version in policy.expired(listing(folder)) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(version.id))
            }
        } catch {}
    }
}

@MainActor
package enum EaselHistories {
    private static var byStore: [String: EaselHistory] = [:]
    private static var byDocument: [UUID: String] = [:]

    package static func attach(to store: EaselStore) {
        let key = store.directory.path
        let history = byStore[key] ?? EaselHistory(directory: store.directory.appendingPathComponent("history", isDirectory: true))
        byStore[key] = history
        store.onSessionCreated = { session in
            byDocument[session.document.id] = key
            history.follow(session.document, changes: session.$document.eraseToAnyPublisher())
        }
        store.onDocumentRemoved = { id in
            history.removeAll(for: id)
            byDocument.removeValue(forKey: id)
        }
    }

    package static func history(for id: UUID) -> EaselHistory? {
        byDocument[id].flatMap { byStore[$0] }
    }
}
