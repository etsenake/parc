import CryptoKit
import Foundation

final class TabHistoryArchive {
    struct Record: Codable, Equatable {
        var url: String
        var profileID: UUID
        var navigation: Data
    }

    let directory: URL
    private let queue = DispatchQueue(label: "org.parc.tab-history", qos: .utility)
    private var written: [UUID: SHA256.Digest] = [:]
    private var paged: Set<UUID> = []

    init(directory: URL) { self.directory = directory }

    func takeLaunchNavigation(for id: UUID, url: String, profileID: UUID) -> Data? {
        takeLaunchNavigation(for: id, urls: [url], profileID: profileID)
    }

    func takeLaunchNavigation(for id: UUID, urls: Set<String>, profileID: UUID) -> Data? {
        guard paged.insert(id).inserted else { return nil }
        let file = file(id)
        guard let record = queue.sync(execute: { Self.read(file) }),
              urls.contains(record.url), record.profileID == profileID else { return nil }
        return record.navigation
    }

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

    func remove(_ id: UUID) {
        written.removeValue(forKey: id)
        let file = file(id)
        queue.async { try? FileManager.default.removeItem(at: file) }
    }

    func removeAll() { prune(keeping: []) }

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
