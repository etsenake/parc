import Foundation

struct SessionFileUnreadable: LocalizedError {
    let underlying: Error
    var errorDescription: String? { underlying.localizedDescription }
}

extension BrowserStore {
    nonisolated static func savedSession(from bytes: Data) throws -> BrowserState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BrowserState.self, from: bytes)
        guard decoded.version == 1, !decoded.spaces.isEmpty, !decoded.profiles.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try validateSaved(decoded)
        return decoded
    }
}

final class SessionBackups {
    struct Backup: Equatable {
        let url: URL
        let date: Date
        var sequence = 0

        func isNewer(than other: Backup) -> Bool {
            (sequence, date) > (other.sequence, other.date)
        }
    }

    struct Restorable {
        let backup: Backup
        let data: Data
    }

    enum Pruning: Equatable {
        case all
        case since(Date)
        case addresses([[String]])
        case profile(UUID)

        init?(_ deletion: ChromiumHistoryDeletion) {
            if deletion.all { self = .all; return }
            if deletion.range != nil, let addresses = deletion.rangeURLs, !addresses.isEmpty {
                self = .addresses(Self.values(addresses)); return
            }
            if let range = deletion.range { self = .since(range.lowerBound); return }
            if let addresses = deletion.urls {
                guard !addresses.isEmpty else { return nil }
                self = .addresses(Self.values(addresses)); return
            }
            guard !deletion.hosts.isEmpty else { return nil }
            self = .addresses(deletion.hosts.sorted().map { ["//" + $0, "\\/\\/" + $0] })
        }

        private static func values(_ addresses: Set<String>) -> [[String]] {
            addresses.sorted().map { ["\"" + $0 + "\"", "\"" + $0.replacingOccurrences(of: "/", with: "\\/") + "\""] }
        }

        func excluding(_ current: Data?) -> Self? {
            guard case .addresses(let items) = self, let current else { return self }
            let remaining = items.filter { !Self.found($0, in: current) }
            return remaining.isEmpty ? nil : .addresses(remaining)
        }

        func removed(from backups: [Backup]) -> [Backup] {
            guard case .since = self else { return backups.filter(removes) }
            let written = backups.sorted { $1.isNewer(than: $0) }
            var laterMinimum = Array(repeating: Date.distantFuture, count: written.count)
            for index in written.indices.dropLast().reversed() {
                laterMinimum[index] = min(laterMinimum[index + 1], written[index + 1].date)
            }
            var earlierMaximum = Date.distantPast
            var removed: [Backup] = []
            for (index, backup) in written.enumerated() {
                let outOfOrder = earlierMaximum > backup.date || laterMinimum[index] < backup.date
                if outOfOrder || removes(backup) { removed.append(backup) }
                earlierMaximum = max(earlierMaximum, backup.date)
            }
            return removed
        }

        private func removes(_ backup: Backup) -> Bool {
            switch self {
            case .all: return true
            case .since(let start): return backup.date.timeIntervalSince(start) > -1
            case .addresses(let items):
                guard let data = try? Data(contentsOf: backup.url) else { return true }
                return items.contains { Self.found($0, in: data) }
            case .profile(let id):
                guard let data = try? Data(contentsOf: backup.url) else { return true }
                return Self.found([id.uuidString, id.uuidString.lowercased()], in: data)
            }
        }

        private static func found(_ spellings: [String], in data: Data) -> Bool {
            spellings.contains { data.range(of: Data($0.utf8)) != nil }
        }
    }

    static let folderName = "Sidebar Backups"
    static let interval: TimeInterval = 60 * 60
    static let recentCount = 6
    static let dailyCount = 7
    private static let stamp = Date.ISO8601FormatStyle(timeZone: TimeZone(identifier: "UTC")!)
        .year().month().day().dateSeparator(.omitted)
        .time(includingFractionalSeconds: false).timeSeparator(.omitted)

    let directory: URL
    let calendar: Calendar
    private var lastBackup: Date?
    private var lastBackupKnown = false

    init(directory: URL, calendar: Calendar = .current) {
        self.directory = directory
        self.calendar = calendar
    }

    static func folder(in directory: URL) -> URL {
        directory.appendingPathComponent(folderName, isDirectory: true)
    }

    static func name(for date: Date, sequence: Int) -> String {
        "session-" + date.formatted(stamp) + "-\(sequence).json"
    }

    static func backup(named name: String, in folder: URL) -> Backup? {
        guard name.hasPrefix("session-"), name.hasSuffix(".json") else { return nil }
        let fields = name.dropFirst("session-".count).dropLast(".json".count)
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let date = try? Date(String(fields[0]), strategy: stamp) else { return nil }
        let url = folder.appendingPathComponent(name)
        guard fields.count == 2 else { return Backup(url: url, date: date) }
        guard let sequence = Int(fields[1]), (1...Int(Int32.max)).contains(sequence) else { return nil }
        return Backup(url: url, date: date, sequence: sequence)
    }

    static func list(in directory: URL) -> [Backup] {
        let folder = folder(in: directory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.compactMap { backup(named: $0, in: folder) }.sorted { $0.isNewer(than: $1) }
    }

    static func retained(_ backups: [Backup], calendar: Calendar) -> Set<URL> {
        let newest = backups.sorted { $0.isNewer(than: $1) }
        var keep = Set(newest.prefix(recentCount).map(\.url))
        var days: [(day: Date, first: Backup)] = []
        for backup in newest {
            let day = calendar.startOfDay(for: backup.date)
            if days.last?.day == day { days[days.count - 1].first = backup } else { days.append((day, backup)) }
        }
        keep.formUnion(days.prefix(dailyCount).map(\.first.url))
        return keep
    }

    static func encoded(_ state: BrowserState) throws -> Data {
        var copy = state
        copy.history = []
        copy.downloads = []
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(copy)
    }

    func backUpIfDue(_ state: BrowserState, at date: Date) {
        if !lastBackupKnown {
            lastBackup = Self.list(in: directory).first?.date
            lastBackupKnown = true
        }
        if let lastBackup, lastBackup <= date, date.timeIntervalSince(lastBackup) < Self.interval { return }
        lastBackup = date
        try? backUp(state, at: date)
    }

    func backUp(_ state: BrowserState, at date: Date) throws {
        let data = try Self.encoded(state)
        _ = try BrowserStore.savedSession(from: data)
        let newest = Self.list(in: directory).first
        if let newest, (try? Data(contentsOf: newest.url)) == data {
            lastBackup = date; lastBackupKnown = true
            return
        }
        let name = Self.name(for: date, sequence: (newest?.sequence ?? 0) + 1)
        try Self.write(data, to: Self.folder(in: directory).appendingPathComponent(name))
        lastBackup = date; lastBackupKnown = true
        let backups = Self.list(in: directory)
        let keep = Self.retained(backups, calendar: calendar)
        for backup in backups where !keep.contains(backup.url) {
            try? FileManager.default.removeItem(at: backup.url)
        }
    }

    func forget(_ pruning: Pruning) {
        Self.prune(pruning, in: directory)
        lastBackupKnown = false
    }

    static func prune(_ pruning: Pruning, in directory: URL) {
        for backup in pruning.removed(from: list(in: directory)) {
            try? FileManager.default.removeItem(at: backup.url)
        }
        removeLeftovers(in: folder(in: directory), prefixes: [".backup-"])
        removeLeftovers(in: directory, prefixes: [".session-", ".history-", ".restore-"])
    }

    private static func removeLeftovers(in folder: URL, prefixes: [String]) {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        where name.hasSuffix(".json") && prefixes.contains(where: { name.hasPrefix($0) }) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    static func restorable(in directory: URL) -> [Restorable] {
        list(in: directory).compactMap { backup in
            guard let data = try? Data(contentsOf: backup.url),
                  (try? BrowserStore.savedSession(from: data)) != nil else { return nil }
            return Restorable(backup: backup, data: data)
        }
    }

    @discardableResult
    static func restore(_ data: Data, in directory: URL, at date: Date) throws -> URL? {
        let fileManager = FileManager.default
        let session = directory.appendingPathComponent("session.json")
        let temporary = directory.appendingPathComponent(".restore-" + UUID().uuidString + ".json")
        defer { try? fileManager.removeItem(at: temporary) }
        guard fileManager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var aside: URL?
        var moved = false
        if (try? fileManager.attributesOfItem(atPath: session.path)) != nil {
            let target = setAsideURL(in: directory, at: date)
            do { try fileManager.linkItem(at: session, to: target) } catch {
                do { try fileManager.copyItem(at: session, to: target) }
                catch { try fileManager.moveItem(at: session, to: target); moved = true }
            }
            aside = target
        }
        guard Darwin.rename(temporary.path, session.path) == 0 else {
            let error = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            if moved, let aside { try? fileManager.moveItem(at: aside, to: session) }
            throw error
        }
        return aside
    }

    static func setAsideURL(in directory: URL, at date: Date) -> URL {
        let base = "session-unreadable-" + date.formatted(stamp)
        var candidate = directory.appendingPathComponent(base + ".json")
        var suffix = 2
        while (try? FileManager.default.attributesOfItem(atPath: candidate.path)) != nil {
            candidate = directory.appendingPathComponent(base + "-\(suffix).json")
            suffix += 1
        }
        return candidate
    }

    private static func write(_ data: Data, to url: URL) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let temporary = folder.appendingPathComponent(".backup-" + UUID().uuidString + ".json")
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
