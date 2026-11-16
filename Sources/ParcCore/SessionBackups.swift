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

        func removes(_ backup: Backup) -> Bool {
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

    static func name(for date: Date) -> String {
        "session-" + date.formatted(stamp) + ".json"
    }

    static func date(fromName name: String) -> Date? {
        guard name.hasPrefix("session-"), name.hasSuffix(".json") else { return nil }
        return try? Date(String(name.dropFirst("session-".count).dropLast(".json".count)), strategy: stamp)
    }

    static func list(in directory: URL) -> [Backup] {
        let folder = folder(in: directory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.compactMap { name in
            date(fromName: name).map { Backup(url: folder.appendingPathComponent(name), date: $0) }
        }.sorted { $0.date > $1.date }
    }

    static func retained(_ backups: [Backup], calendar: Calendar) -> Set<URL> {
        let newest = backups.sorted { $0.date > $1.date }
        var keep = Set(newest.prefix(recentCount).map(\.url))
        var earliest: [Date: Backup] = [:]
        for backup in newest { earliest[calendar.startOfDay(for: backup.date)] = backup }
        for day in earliest.keys.sorted(by: >).prefix(dailyCount) {
            if let backup = earliest[day] { keep.insert(backup.url) }
        }
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
            lastBackup = Self.list(in: directory).first { $0.date <= date }?.date
            lastBackupKnown = true
        }
        if let lastBackup, lastBackup <= date, date.timeIntervalSince(lastBackup) < Self.interval { return }
        lastBackup = date
        try? backUp(state, at: date)
    }

    func backUp(_ state: BrowserState, at date: Date) throws {
        let data = try Self.encoded(state)
        _ = try BrowserStore.savedSession(from: data)
        if let newest = Self.list(in: directory).first, (try? Data(contentsOf: newest.url)) == data {
            lastBackup = date; lastBackupKnown = true
            return
        }
        try Self.write(data, to: Self.folder(in: directory).appendingPathComponent(Self.name(for: date)))
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
        for backup in list(in: directory) where pruning.removes(backup) {
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
