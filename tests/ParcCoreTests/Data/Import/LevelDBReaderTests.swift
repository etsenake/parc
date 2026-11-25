import Foundation
import Testing
@testable import ParcCore

enum LevelDBFixture {
    typealias Entry = (key: [UInt8], value: [UInt8])

    struct TableBlock {
        var entries: [Entry]
        var compressed = false
        var stored: [UInt8]?
    }

    static func varint(_ value: Int) -> [UInt8] { varint(UInt64(value)) }

    static func varint(_ value: UInt64) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        while value >= 0x80 {
            bytes.append(UInt8(value & 0x7f) | 0x80)
            value >>= 7
        }
        bytes.append(UInt8(value))
        return bytes
    }

    static func fixed32(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: value >> UInt32(8 * $0)) }
    }

    static func fixed64(_ value: UInt64) -> [UInt8] {
        (0..<8).map { UInt8(truncatingIfNeeded: value >> UInt64(8 * $0)) }
    }

    static func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    static func lengthPrefixed(_ bytes: [UInt8]) -> [UInt8] { varint(bytes.count) + bytes }

    static func internalKey(_ key: String, _ sequence: UInt64, deleted: Bool = false) -> [UInt8] {
        bytes(key) + fixed64(sequence << 8 | (deleted ? 0 : 1))
    }

    static func block(_ entries: [Entry], restartInterval: Int = 2) -> [UInt8] {
        var output: [UInt8] = []
        var restarts: [UInt32] = []
        var previous: [UInt8] = []
        for (index, entry) in entries.enumerated() {
            var shared = 0
            if index % restartInterval == 0 {
                restarts.append(UInt32(output.count))
            } else {
                shared = zip(previous, entry.key).prefix(while: { $0.0 == $0.1 }).count
            }
            output += varint(shared)
            output += varint(entry.key.count - shared)
            output += varint(entry.value.count)
            output += entry.key[shared...]
            output += entry.value
            previous = entry.key
        }
        if restarts.isEmpty { restarts = [0] }
        for restart in restarts { output += fixed32(restart) }
        output += fixed32(UInt32(restarts.count))
        return output
    }

    static func snappyLiteral(_ bytes: [UInt8]) -> [UInt8] {
        var output = varint(bytes.count)
        var offset = 0
        while offset < bytes.count {
            let length = min(65_536, bytes.count - offset)
            output.append(61 << 2)
            output.append(UInt8((length - 1) & 0xff))
            output.append(UInt8((length - 1) >> 8))
            output += bytes[offset..<(offset + length)]
            offset += length
        }
        return output
    }

    static func table(_ blocks: [TableBlock]) -> [UInt8] {
        var file: [UInt8] = []
        var index: [Entry] = []
        for tableBlock in blocks {
            let raw = block(tableBlock.entries)
            let stored = tableBlock.stored ?? (tableBlock.compressed ? snappyLiteral(raw) : raw)
            let handle = varint(file.count) + varint(stored.count)
            file += stored
            file += [tableBlock.compressed ? 1 : 0, 0xde, 0xad, 0xbe, 0xef]
            index.append((tableBlock.entries.last?.key ?? [], handle))
        }
        return assemble(file, index: index)
    }

    static func assemble(_ data: [UInt8], index: [Entry]) -> [UInt8] {
        var file = data
        let metaindex = block([])
        let metaHandle = varint(file.count) + varint(metaindex.count)
        file += metaindex
        file += [0, 0, 0, 0, 0]
        let indexBlock = block(index, restartInterval: 1)
        let indexHandle = varint(file.count) + varint(indexBlock.count)
        file += indexBlock
        file += [0, 0, 0, 0, 0]
        var footer = metaHandle + indexHandle
        footer += [UInt8](repeating: 0, count: 40 - footer.count)
        file += footer
        file += fixed64(0xdb47_7524_8b80_fb57)
        return file
    }

    static func log(_ records: [[UInt8]]) -> [UInt8] {
        let blockSize = 32_768
        var output: [UInt8] = []
        for record in records {
            var offset = 0
            var begin = true
            while true {
                let leftover = blockSize - output.count % blockSize
                if leftover < 7 {
                    output += [UInt8](repeating: 0, count: leftover)
                    continue
                }
                let length = min(leftover - 7, record.count - offset)
                let end = offset + length == record.count
                let type: UInt8 = begin && end ? 1 : begin ? 2 : end ? 4 : 3
                output += [0x12, 0x34, 0x56, 0x78, UInt8(length & 0xff), UInt8(length >> 8), type]
                output += record[offset..<(offset + length)]
                offset += length
                begin = false
                if end { break }
            }
        }
        return output
    }

    static func batch(sequence: UInt64, _ operations: [(key: String, value: [UInt8]?)]) -> [UInt8] {
        var output = fixed64(sequence) + fixed32(UInt32(operations.count))
        for operation in operations {
            if let value = operation.value {
                output += [1] + lengthPrefixed(bytes(operation.key)) + lengthPrefixed(value)
            } else {
                output += [0] + lengthPrefixed(bytes(operation.key))
            }
        }
        return output
    }

    static func edit(logNumber: UInt64? = nil, added: [(level: Int, number: UInt64)] = [],
                     deleted: [(level: Int, number: UInt64)] = []) -> [UInt8] {
        var output = varint(1) + lengthPrefixed(bytes("leveldb.BytewiseComparator"))
        if let logNumber { output += varint(2) + varint(logNumber) }
        output += varint(3) + varint(100)
        output += varint(4) + varint(99)
        for file in deleted { output += varint(6) + varint(file.level) + varint(file.number) }
        for file in added {
            output += varint(7) + varint(file.level) + varint(file.number) + varint(4096)
            output += lengthPrefixed(internalKey("a", 1)) + lengthPrefixed(internalKey("z", 1))
        }
        return output
    }

    static func write(to directory: URL, edits: [[UInt8]]?, tables: [UInt64: [UInt8]] = [:], logs: [UInt64: [UInt8]] = [:]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let edits {
            try Data("MANIFEST-000001\n".utf8).write(to: directory.appendingPathComponent("CURRENT"))
            try Data(log(edits)).write(to: directory.appendingPathComponent("MANIFEST-000001"))
        }
        try Data().write(to: directory.appendingPathComponent("LOCK"))
        try Data("leveldb log noise".utf8).write(to: directory.appendingPathComponent("LOG"))
        for (number, contents) in tables {
            try Data(contents).write(to: directory.appendingPathComponent(String(format: "%06llu.ldb", number)))
        }
        for (number, contents) in logs {
            try Data(contents).write(to: directory.appendingPathComponent(String(format: "%06llu.log", number)))
        }
    }
}

struct LevelDBReaderTests {
    typealias F = LevelDBFixture

    static let big = (0..<40_000).map { UInt8(truncatingIfNeeded: $0 &* 7) }

    func writeStore(to directory: URL) throws {
        let live = F.table([
            F.TableBlock(entries: [
                (F.internalKey("alpha", 1), F.bytes("one")),
                (F.internalKey("alphabet", 2), F.bytes("two")),
                (F.internalKey("alphanumeric", 3), F.bytes("three")),
                (F.internalKey("alphanumerical", 4), F.bytes("four")),
            ]),
            F.TableBlock(entries: [
                (F.internalKey("beta", 5), F.bytes("old beta")),
                (F.internalKey("gamma", 6), F.bytes("gamma")),
                (F.internalKey("zeta", 8, deleted: true), []),
                (F.internalKey("zeta", 7), F.bytes("zeta")),
            ], compressed: true),
        ])
        let obsolete = F.table([F.TableBlock(entries: [(F.internalKey("ghost", 9), F.bytes("boo"))])])
        let staleLog = F.log([F.batch(sequence: 9, [("phantom", F.bytes("boo"))])])
        var liveLog = F.log([
            F.batch(sequence: 10, [("beta", F.bytes("new beta")), ("gamma", nil)]),
            F.batch(sequence: 12, [("big", Self.big), ("alpha", F.bytes("uno"))]),
        ])
        liveLog += [0x01, 0x02, 0x03]
        try F.write(to: directory,
                    edits: [F.edit(logNumber: 2, added: [(0, 3)]), F.edit(logNumber: 7, added: [(1, 5)], deleted: [(0, 3)])],
                    tables: [3: obsolete, 5: live], logs: [2: staleLog, 7: liveLog])
    }

    @Test func theNewestLiveValueWinsAcrossTablesAndTheLog() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            try writeStore(to: directory)
            let values = try LevelDBReader.read(directory: directory)
            #expect(values == [
                F.bytes("alpha"): F.bytes("uno"),
                F.bytes("alphabet"): F.bytes("two"),
                F.bytes("alphanumeric"): F.bytes("three"),
                F.bytes("alphanumerical"): F.bytes("four"),
                F.bytes("beta"): F.bytes("new beta"),
                F.bytes("big"): Self.big,
            ])
        }
    }

    @Test func aKeyPrefixKeepsOnlyMatchingKeys() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            try writeStore(to: directory)
            let values = try LevelDBReader.read(directory: directory, keyPrefix: F.bytes("alphan"))
            #expect(values == [F.bytes("alphanumeric"): F.bytes("three"), F.bytes("alphanumerical"): F.bytes("four")])
        }
    }

    @Test func aBrokenCompressedBlockIsSkippedAndTheRestStillReads() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let table = F.table([
                F.TableBlock(entries: [(F.internalKey("kept", 1), F.bytes("yes"))]),
                F.TableBlock(entries: [(F.internalKey("lost", 2), F.bytes("no"))], compressed: true, stored: [0x40, 0xf0]),
                F.TableBlock(entries: [(F.internalKey("tail", 3), F.bytes("also"))], compressed: true),
            ])
            try F.write(to: directory, edits: [F.edit(logNumber: 6, added: [(0, 4)])], tables: [4: table])
            let values = try LevelDBReader.read(directory: directory)
            #expect(values == [F.bytes("kept"): F.bytes("yes"), F.bytes("tail"): F.bytes("also")])
        }
    }

    @Test func aStoreWithoutAManifestReadsEveryFile() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let table = F.table([F.TableBlock(entries: [(F.internalKey("one", 1), F.bytes("1")), (F.internalKey("two", 2), F.bytes("2"))])])
            let log = F.log([F.batch(sequence: 3, [("two", nil), ("three", F.bytes("3"))])])
            try F.write(to: directory, edits: nil, tables: [8: table], logs: [9: log])
            let values = try LevelDBReader.read(directory: directory)
            #expect(values == [F.bytes("one"): F.bytes("1"), F.bytes("three"): F.bytes("3")])
        }
    }

    @Test func aBlockListedManyTimesInTheIndexIsDecodedOnceWithinTheBudget() {
        let raw = F.block([(F.internalKey("only", 1), F.bytes("once"))])
        let stored = F.snappyLiteral(raw)
        let handle = F.varint(0) + F.varint(stored.count)
        let index = (0..<5_000).map { (key: F.bytes(String(format: "k%05d", $0)), value: handle) }
        let file = F.assemble(stored + [1, 0xde, 0xad, 0xbe, 0xef], index: index)
        let indexSize = F.block(index, restartInterval: 1).count
        var collector = LevelDBReader.Collector(prefix: [])
        var budget = LevelDBReader.maximumDecodedBytesPerScan
        LevelDBReader.readTable(file, into: &collector, budget: &budget)
        #expect(collector.values == [F.bytes("only"): F.bytes("once")])
        #expect(LevelDBReader.maximumDecodedBytesPerScan - budget == indexSize + raw.count)
    }

    @Test func aBlockBeyondTheRemainingScanBudgetIsNotDecoded() {
        let raw = F.block([(F.internalKey("late", 1), F.bytes("value"))])
        let table = F.table([F.TableBlock(entries: [(F.internalKey("late", 1), F.bytes("value"))], compressed: true)])
        let indexSize = F.block([(F.internalKey("late", 1), F.varint(0) + F.varint(F.snappyLiteral(raw).count))], restartInterval: 1).count
        var collector = LevelDBReader.Collector(prefix: [])
        var budget = indexSize + raw.count - 1
        LevelDBReader.readTable(table, into: &collector, budget: &budget)
        #expect(collector.values.isEmpty)
        #expect(budget == raw.count - 1)
    }

    @Test func aBlockLargerThanFourMebibytesIsSkipped() {
        let huge = [UInt8](repeating: 7, count: LevelDBReader.maximumBlockSize)
        let table = F.table([
            F.TableBlock(entries: [(F.internalKey("small", 1), F.bytes("kept"))], compressed: true),
            F.TableBlock(entries: [(F.internalKey("packed", 2), huge)], compressed: true),
            F.TableBlock(entries: [(F.internalKey("plain", 3), huge)]),
        ])
        var collector = LevelDBReader.Collector(prefix: [])
        var budget = LevelDBReader.maximumDecodedBytesPerScan
        LevelDBReader.readTable(table, into: &collector, budget: &budget)
        #expect(collector.values == [F.bytes("small"): F.bytes("kept")])
        #expect(LevelDBReader.maximumDecodedBytesPerScan - budget < 1024)
    }

    @Test func aKeyLongerThanSixtyFourKibibytesEndsTheBlock() {
        let longest = [UInt8](repeating: 0x61, count: LevelDBReader.maximumKeySize)
        let accepted = LevelDBReader.blockEntries(F.block([(F.bytes("a"), F.bytes("1")), (longest, F.bytes("2"))], restartInterval: 1))
        #expect(accepted?.map(\.key) == [F.bytes("a"), longest])
        let block = F.block([(F.bytes("a"), F.bytes("1")), (longest + [0x62], F.bytes("2")), (F.bytes("z"), F.bytes("3"))], restartInterval: 1)
        #expect(LevelDBReader.blockEntries(block)?.map(\.key) == [F.bytes("a")])
    }

    @Test func aBlockStopsAtTheEntryLimit() {
        let entries = (0..<(LevelDBReader.maximumBlockEntries + 10)).map { (key: F.bytes(String(format: "%06d", $0)), value: [UInt8]()) }
        let read = LevelDBReader.blockEntries(F.block(entries, restartInterval: 16))
        #expect(read?.count == LevelDBReader.maximumBlockEntries)
        #expect(read?.last?.key == entries[LevelDBReader.maximumBlockEntries - 1].key)
    }

    @Test func sharedPrefixKeysStopAtTheBlockKeyBudget() {
        let prefix = [UInt8](repeating: 0x70, count: 60 * 1024)
        let entries = (0..<300).map { (key: prefix + [UInt8($0 >> 8), UInt8($0 & 0xff)], value: [UInt8]()) }
        let block = F.block(entries, restartInterval: 1_000_000)
        #expect(block.count < 64 * 1024)
        let read = LevelDBReader.blockEntries(block) ?? []
        #expect(read.count == LevelDBReader.maximumBlockKeyBytes / (prefix.count + 2))
        #expect(read.reduce(0) { $0 + $1.key.count } <= LevelDBReader.maximumBlockKeyBytes)
        #expect(read.map(\.key) == entries.prefix(read.count).map(\.key))
    }

    @Test func workspacesOlderThanAnHourAreRemovedAndFreshOnesStay() throws {
        try DataFixtures.withTemporaryDirectory { folder in
            let files = FileManager.default
            let stale = folder.appendingPathComponent("ParcLevelDB-stale")
            let fresh = folder.appendingPathComponent("ParcLevelDB-fresh")
            let unrelated = folder.appendingPathComponent("Unrelated-old")
            for url in [stale, fresh, unrelated] {
                try files.createDirectory(at: url, withIntermediateDirectories: true)
                try Data("x".utf8).write(to: url.appendingPathComponent("0"))
            }
            let old = Date().addingTimeInterval(-2 * 60 * 60)
            try files.setAttributes([.modificationDate: old], ofItemAtPath: stale.path)
            try files.setAttributes([.modificationDate: old], ofItemAtPath: unrelated.path)
            LevelDBReader.removeStaleWorkspaces(in: folder)
            #expect(!files.fileExists(atPath: stale.path))
            #expect(files.fileExists(atPath: fresh.path))
            #expect(files.fileExists(atPath: unrelated.path))
        }
    }

    @Test func aMissingFolderReadsAsEmpty() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let values = try LevelDBReader.read(directory: directory.appendingPathComponent("LevelDB"))
            #expect(values.isEmpty)
        }
    }
}
