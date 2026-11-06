import CryptoKit
import Foundation

/// Each tab's back/forward entries on disk, so a relaunch or a crash brings a
/// tab back on the page it was on, with the pages behind it and their scroll
///
/// the engine's archive of a page's navigation entries (Chromium's own session
/// pickles); this keeps one file per tab with the address and Profile they
/// were captured at. A record is offered once per launch, to the tab's first
/// page, and only while the tab is still at that address in that Profile. A
/// tab's own close or reset drops its record, and any history deletion drops
/// every record, so an unloaded tab brings back neither stale nor deleted
/// pages. Private stores have no archive, and
/// the engine archives no private page.
final class TabHistoryArchive {
    struct Record: Codable, Equatable {
        var url: String
        var profileID: UUID
        var navigation: Data
    }

    let directory: URL
    private let queue = DispatchQueue(label: "org.parc.tab-history", qos: .utility)
    /// A digest of the last record handed to the writer for each tab.
    private var written: [UUID: SHA256.Digest] = [:]
    /// Tabs that have had a page this launch; their live captures own the record.
    private var paged: Set<UUID> = []

    init(directory: URL) { self.directory = directory }

    /// The archived entries for the tab's first page this launch, if the tab
    /// is still where they were captured. Later pages for the tab get nil.
    /// Reads after every queued write and deletion, so a record just dropped
    /// by a close or a history deletion is never offered.
    func takeLaunchNavigation(for id: UUID, url: String, profileID: UUID) -> Data? {
        guard paged.insert(id).inserted else { return nil }
        let file = file(id)
        guard let record = queue.sync(execute: { Self.read(file) }),
              record.url == url, record.profileID == profileID else { return nil }
        return record.navigation
    }

    /// A page now exists for the tab, however it was created.
    func pageCreated(_ id: UUID) { paged.insert(id) }

    func store(_ record: Record, for id: UUID) {
        guard let data = try? PropertyListEncoder.binary.encode(record) else { return }
        let digest = SHA256.hash(data: data)
        guard written[id] != digest else { return }
        written[id] = digest
        let directory = directory, file = file(id)
        queue.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            try? data.write(to: file, options: .atomic)
        }
    }

    /// Drops one tab's record: its own close or reset starts it afresh.
    func remove(_ id: UUID) {
        written.removeValue(forKey: id)
        let file = file(id)
        queue.async { try? FileManager.default.removeItem(at: file) }
    }

    /// Drops every record, for a history deletion, so no unloaded tab brings
    /// deleted pages back. Live pages keep their own back/forward lists, as
    /// they do in a session, and write them again on their next capture.
    func removeAll() { prune(keeping: []) }

    /// Deletes the records of tabs that are gone: archived, deleted or in a
    /// removed Profile.
    func prune(keeping live: Set<UUID>) {
        written = written.filter { live.contains($0.key) }
        let directory = directory
        queue.async {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for name in names {
                guard let id = UUID(uuidString: name), !live.contains(id) else { continue }
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }

    /// Returns once every queued write and deletion is on disk.
    func flush() { queue.sync {} }

    private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString) }

    private static func read(_ file: URL) -> Record? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? PropertyListDecoder().decode(Record.self, from: data)
    }
}

private extension PropertyListEncoder {
    static var binary: PropertyListEncoder {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }
}
