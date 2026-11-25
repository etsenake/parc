import Foundation

package enum LevelDBReader {
    static let maximumFileSize = 64 * 1024 * 1024
    static let maximumTotalSize = 512 * 1024 * 1024
    static let maximumKeys = 200_000
    static let logBlockSize = 32 * 1024
    static let maximumBlockSize = 4 * 1024 * 1024
    static let maximumDecodedBytesPerScan = 256 * 1024 * 1024
    static let maximumKeySize = 64 * 1024
    static let maximumBlockEntries = 65_536
    static let maximumBlockKeyBytes = 16 * 1024 * 1024
    static let workspacePrefix = "ParcLevelDB-"
    static let staleWorkspaceAge: TimeInterval = 60 * 60
    static let tableMagic: UInt64 = 0xdb47_7524_8b80_fb57

    package static func read(directory: URL, keyPrefix: [UInt8] = []) throws -> [[UInt8]: [UInt8]] {
        let files = FileManager.default
        removeStaleWorkspaces(in: files.temporaryDirectory)
        var isDirectory: ObjCBool = false
        guard files.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else { return [:] }
        let workspace = files.temporaryDirectory.appendingPathComponent("\(workspacePrefix)\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: workspace) }
        var values: [[UInt8]: [UInt8]] = [:]
        for attempt in 0..<3 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.2) }
            let copy = workspace.appendingPathComponent("\(attempt)", isDirectory: true)
            try files.createDirectory(at: copy, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try copyStore(from: directory, to: copy)
            let result = scan(copy, keyPrefix: keyPrefix)
            try? files.removeItem(at: copy)
            values = result.values
            if result.complete { break }
        }
        return values
    }

    static func removeStaleWorkspaces(in folder: URL, now: Date = Date()) {
        let files = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let entries = try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: []) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix(workspacePrefix) {
            guard let values = try? entry.resourceValues(forKeys: Set(keys)), values.isDirectory == true, values.isSymbolicLink != true,
                  let modified = values.contentModificationDate, now.timeIntervalSince(modified) > staleWorkspaceAge else { continue }
            try? files.removeItem(at: entry)
        }
    }

    enum StoreFile: Equatable {
        case current
        case manifest
        case table(UInt64)
        case log(UInt64)

        init?(name: String) {
            if name == "CURRENT" {
                self = .current
                return
            }
            if name.hasPrefix("MANIFEST-"), Self.isNumber(name.dropFirst(9)) {
                self = .manifest
                return
            }
            let parts = name.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 2, Self.isNumber(parts[0]), let number = UInt64(parts[0]) else { return nil }
            switch parts[1] {
            case "ldb", "sst": self = .table(number)
            case "log": self = .log(number)
            default: return nil
            }
        }

        static func isNumber(_ text: Substring) -> Bool {
            !text.isEmpty && text.utf8.allSatisfy { (48...57).contains($0) }
        }

        var copyOrder: Int {
            switch self {
            case .current: 0
            case .manifest: 1
            case .table: 2
            case .log: 3
            }
        }
    }

    static func copyStore(from source: URL, to destination: URL) throws {
        let files = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        let entries = try files.contentsOfDirectory(at: source, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            .compactMap { url in StoreFile(name: url.lastPathComponent).map { (url: url, kind: $0) } }
            .sorted { ($0.kind.copyOrder, $0.url.lastPathComponent) < ($1.kind.copyOrder, $1.url.lastPathComponent) }
        var total = 0
        for entry in entries {
            guard let values = try? entry.url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let size = values.fileSize, size <= maximumFileSize, size <= maximumTotalSize - total,
                  (try? files.copyItem(at: entry.url, to: destination.appendingPathComponent(entry.url.lastPathComponent))) != nil
            else { continue }
            total += size
        }
    }

    static func scan(_ folder: URL, keyPrefix: [UInt8]) -> (values: [[UInt8]: [UInt8]], complete: Bool) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var tables: [UInt64: String] = [:]
        var logs: [UInt64: String] = [:]
        for name in names {
            switch StoreFile(name: name) {
            case .table(let number)?: tables[number] = name
            case .log(let number)?: logs[number] = name
            default: break
            }
        }
        var complete = true
        switch manifest(in: folder) {
        case .absent:
            break
        case .unreadable:
            complete = false
        case .found(let manifest):
            complete = manifest.tables.isSubset(of: Set(tables.keys))
            tables = tables.filter { manifest.tables.contains($0.key) }
            if let logNumber = manifest.logNumber {
                logs = logs.filter { $0.key >= logNumber || $0.key == manifest.previousLogNumber }
            }
        }
        var collector = Collector(prefix: keyPrefix)
        var budget = maximumDecodedBytesPerScan
        for (_, name) in tables.sorted(by: { $0.key < $1.key }) {
            guard budget > 0, let bytes = load(folder.appendingPathComponent(name)) else { continue }
            readTable(bytes, into: &collector, budget: &budget)
        }
        for (_, name) in logs.sorted(by: { $0.key < $1.key }) {
            guard let bytes = load(folder.appendingPathComponent(name)) else { continue }
            for record in logRecords(bytes) { applyBatch(record, into: &collector) }
        }
        return (collector.values, complete)
    }

    static func load(_ url: URL) -> [UInt8]? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size <= maximumFileSize,
              let data = try? Data(contentsOf: url) else { return nil }
        return [UInt8](data)
    }

    struct Collector {
        let prefix: [UInt8]
        var latest: [[UInt8]: (sequence: UInt64, value: [UInt8]?)] = [:]

        mutating func offer(key: ArraySlice<UInt8>, sequence: UInt64, value: @autoclosure () -> [UInt8]?) {
            guard key.starts(with: prefix) else { return }
            let key = Array(key)
            if let existing = latest[key] {
                guard sequence >= existing.sequence else { return }
            } else {
                guard latest.count < LevelDBReader.maximumKeys else { return }
            }
            latest[key] = (sequence, value())
        }

        var values: [[UInt8]: [UInt8]] { latest.compactMapValues { $0.value } }
    }

    struct FileKey: Hashable {
        let level: UInt64
        let number: UInt64
    }

    struct Manifest {
        var tables: Set<UInt64> = []
        var logNumber: UInt64?
        var previousLogNumber: UInt64?
    }

    enum ManifestState {
        case absent
        case unreadable
        case found(Manifest)
    }

    struct VersionEdit {
        var added: [FileKey] = []
        var deleted: [FileKey] = []
        var logNumber: UInt64?
        var previousLogNumber: UInt64?
    }

    static func manifest(in folder: URL) -> ManifestState {
        let current = folder.appendingPathComponent("CURRENT")
        guard FileManager.default.fileExists(atPath: current.path) else { return .absent }
        guard let text = load(current) else { return .unreadable }
        let name = String(decoding: text, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard StoreFile(name: name) == .manifest, let bytes = load(folder.appendingPathComponent(name)) else { return .unreadable }
        var live = Set<FileKey>()
        var manifest = Manifest()
        var applied = false
        for record in logRecords(bytes) {
            guard let edit = versionEdit(record) else { continue }
            applied = true
            live.subtract(edit.deleted)
            live.formUnion(edit.added)
            if let number = edit.logNumber { manifest.logNumber = number }
            if let number = edit.previousLogNumber { manifest.previousLogNumber = number }
        }
        guard applied else { return .unreadable }
        manifest.tables = Set(live.map(\.number))
        return .found(manifest)
    }

    static func versionEdit(_ record: [UInt8]) -> VersionEdit? {
        var cursor = ByteCursor(record)
        var edit = VersionEdit()
        while !cursor.isAtEnd {
            guard let tag = cursor.varint(maximumBytes: 5) else { return nil }
            switch tag {
            case 1:
                guard cursor.lengthPrefixedRange() != nil else { return nil }
            case 2:
                guard let number = cursor.varint() else { return nil }
                edit.logNumber = number
            case 3, 4:
                guard cursor.varint() != nil else { return nil }
            case 5:
                guard cursor.varint(maximumBytes: 5) != nil, cursor.lengthPrefixedRange() != nil else { return nil }
            case 6:
                guard let level = cursor.varint(maximumBytes: 5), let number = cursor.varint() else { return nil }
                edit.deleted.append(FileKey(level: level, number: number))
            case 7:
                guard let level = cursor.varint(maximumBytes: 5), let number = cursor.varint(), cursor.varint() != nil,
                      cursor.lengthPrefixedRange() != nil, cursor.lengthPrefixedRange() != nil else { return nil }
                edit.added.append(FileKey(level: level, number: number))
            case 9:
                guard let number = cursor.varint() else { return nil }
                edit.previousLogNumber = number
            default:
                return nil
            }
        }
        return edit
    }

    static func logRecords(_ file: [UInt8]) -> [[UInt8]] {
        var records: [[UInt8]] = []
        var fragments: [UInt8]?
        var blockStart = 0
        while blockStart < file.count {
            let blockEnd = min(blockStart + logBlockSize, file.count)
            var offset = blockStart
            while blockEnd - offset >= 7 {
                let length = Int(file[offset + 4]) | Int(file[offset + 5]) << 8
                let type = file[offset + 6]
                let body = offset + 7
                guard length <= blockEnd - body, type != 0 || length != 0 else {
                    fragments = nil
                    break
                }
                let payload = file[body..<(body + length)]
                switch type {
                case 1:
                    fragments = nil
                    records.append(Array(payload))
                case 2:
                    fragments = Array(payload)
                case 3:
                    fragments?.append(contentsOf: payload)
                case 4:
                    if var whole = fragments {
                        whole.append(contentsOf: payload)
                        records.append(whole)
                    }
                    fragments = nil
                default:
                    fragments = nil
                }
                offset = body + length
            }
            blockStart += logBlockSize
        }
        return records
    }

    static func applyBatch(_ record: [UInt8], into collector: inout Collector) {
        var cursor = ByteCursor(record)
        guard let sequence = cursor.fixed64(), let count = cursor.fixed32() else { return }
        var operations: [(key: Range<Int>, value: Range<Int>?)] = []
        while !cursor.isAtEnd {
            guard operations.count < Int(count), let tag = cursor.byte(), let key = cursor.lengthPrefixedRange() else { return }
            switch tag {
            case 1:
                guard let value = cursor.lengthPrefixedRange() else { return }
                operations.append((key, value))
            case 0:
                operations.append((key, nil))
            default:
                return
            }
        }
        guard operations.count == Int(count) else { return }
        for (index, operation) in operations.enumerated() {
            collector.offer(key: record[operation.key], sequence: sequence &+ UInt64(index),
                            value: operation.value.map { Array(record[$0]) })
        }
    }

    static func readTable(_ file: [UInt8], into collector: inout Collector, budget: inout Int) {
        guard file.count >= 48, ByteCursor.fixed64(file, at: file.count - 8) == tableMagic else { return }
        var footer = ByteCursor(file, from: file.count - 48, to: file.count - 8)
        guard blockHandle(&footer) != nil, let indexHandle = blockHandle(&footer),
              let index = block(file, indexHandle, budget: &budget), let indexEntries = blockEntries(index) else { return }
        var visited: Set<Int> = [indexHandle.lowerBound]
        for indexEntry in indexEntries {
            var cursor = ByteCursor(index, from: indexEntry.value.lowerBound, to: indexEntry.value.upperBound)
            guard budget > 0, let handle = blockHandle(&cursor), visited.insert(handle.lowerBound).inserted,
                  let data = block(file, handle, budget: &budget), let entries = blockEntries(data) else { continue }
            for entry in entries where entry.key.count >= 8 {
                let trailer = ByteCursor.fixed64(entry.key, at: entry.key.count - 8)
                let kind = trailer & 0xff
                guard kind <= 1 else { continue }
                collector.offer(key: entry.key[..<(entry.key.count - 8)], sequence: trailer >> 8,
                                value: kind == 1 ? Array(data[entry.value]) : nil)
            }
        }
    }

    static func blockHandle(_ cursor: inout ByteCursor) -> Range<Int>? {
        guard let offset = cursor.varint().flatMap({ Int(exactly: $0) }), let size = cursor.varint().flatMap({ Int(exactly: $0) }),
              size <= Int.max - offset else { return nil }
        return offset..<(offset + size)
    }

    static func block(_ file: [UInt8], _ handle: Range<Int>, budget: inout Int) -> [UInt8]? {
        guard file.count >= 5, handle.upperBound <= file.count - 5 else { return nil }
        let limit = min(maximumBlockSize, max(0, budget))
        let contents: [UInt8]?
        switch file[handle.upperBound] {
        case 0:
            contents = handle.count <= limit ? Array(file[handle]) : nil
        case 1:
            contents = handle.count <= limit + limit / 6 + 32 ? Snappy.decompress(Array(file[handle]), maximumLength: limit) : nil
        default:
            contents = nil
        }
        guard let contents else { return nil }
        budget -= contents.count
        return contents
    }

    static func blockEntries(_ block: [UInt8]) -> [(key: [UInt8], value: Range<Int>)]? {
        guard block.count >= 4 else { return nil }
        let restartCount = Int(ByteCursor.fixed32(block, at: block.count - 4))
        guard restartCount >= 1, restartCount <= (block.count - 4) / 4 else { return nil }
        let limit = block.count - 4 - 4 * restartCount
        let restarts = (0..<restartCount).map { Int(ByteCursor.fixed32(block, at: limit + 4 * $0)) }
        guard restarts[0] == 0 else { return nil }
        var entries: [(key: [UInt8], value: Range<Int>)] = []
        var keyBytes = 0
        for (position, start) in restarts.enumerated() {
            let end = position + 1 < restarts.count ? restarts[position + 1] : limit
            guard start <= end, end <= limit else { return entries }
            var cursor = ByteCursor(block, from: start, to: end)
            var key: [UInt8] = []
            while !cursor.isAtEnd {
                guard let shared = cursor.varint(maximumBytes: 5).flatMap({ Int(exactly: $0) }), shared <= key.count,
                      let unshared = cursor.varint(maximumBytes: 5).flatMap({ Int(exactly: $0) }),
                      let valueLength = cursor.varint(maximumBytes: 5).flatMap({ Int(exactly: $0) }),
                      unshared <= maximumKeySize - shared, entries.count < maximumBlockEntries,
                      shared + unshared <= maximumBlockKeyBytes - keyBytes,
                      let suffix = cursor.take(unshared), let value = cursor.take(valueLength) else { return entries }
                keyBytes += shared + unshared
                key.removeLast(key.count - shared)
                key.append(contentsOf: block[suffix])
                entries.append((key, value))
            }
        }
        return entries
    }
}
