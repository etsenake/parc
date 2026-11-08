import Foundation

/// A read-only reader for Google Firestore's offline cache: the LevelDB files
/// of one database, as copied to a private folder. It returns the newest
/// cached version of each document; it never opens LevelDB itself, writes,
/// or contacts any server.
enum FirestoreCache {
    indirect enum Value: Equatable {
        case null
        case bool(Bool)
        case integer(Int64)
        case double(Double)
        case timestamp(Date)
        case string(String)
        case bytes(Data)
        case reference(String)
        case array([Value])
        case map([String: Value])

        subscript(key: String) -> Value? { if case .map(let fields) = self { return fields[key] } else { return nil } }
        var string: String? { if case .string(let value) = self { return value } else { return nil } }
        var array: [Value]? { if case .array(let value) = self { return value } else { return nil } }
        var integer: Int64? {
            switch self {
            case .integer(let value): return value
            case .double(let value) where value.isFinite && abs(value) < 9e18: return Int64(value)
            default: return nil
            }
        }
        var date: Date? {
            switch self {
            case .timestamp(let value): return value
            case .double(let value) where value.isFinite: return Date(timeIntervalSince1970: value > 1e11 ? value / 1000 : value)
            case .integer(let value): return Date(timeIntervalSince1970: value > 100_000_000_000 ? Double(value) / 1000 : Double(value))
            default: return nil
            }
        }
    }
    struct Document: Equatable {
        /// The path after `/documents/`, such as `documents/<id>`.
        let path: String
        let fields: [String: Value]
        let updated: Date?
    }
    enum Failure: Error { case corrupt }

    static let maximumFileBytes = 256 * 1024 * 1024
    /// Keys of Firestore's `remote_document` table: the ordered-code string
    /// label, the table name and its terminator. Only these hold documents.
    static let documentTable = Data([0x85]) + Data("remote_document".utf8) + Data([0x00, 0x01])
    private static let documentTableEnd = Data([0x85]) + Data("remote_document".utf8) + Data([0x00, 0x02])
    static let maximumBlockBytes = 64 * 1024 * 1024

    /// Every document in the copied database folder whose path starts with
    /// `collection/`, newest cached version each.
    static func documents(in directory: URL, collection: String) throws -> [Document] {
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        var newest: [Data: (sequence: UInt64, value: Data?)] = [:]
        func record(_ key: Data, _ sequence: UInt64, _ value: Data?) {
            guard key.starts(with: documentTable) else { return }
            if let current = newest[key], current.sequence >= sequence { return }
            newest[key] = (sequence, value)
        }
        for file in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, (values.fileSize ?? .max) <= maximumFileBytes else { continue }
            switch file.pathExtension {
            case "ldb", "sst": try? table(Data(contentsOf: file), record)
            case "log": try? log(Data(contentsOf: file), record)
            default: continue
            }
        }
        var documents: [String: Document] = [:]
        let marker = "/documents/" + collection + "/"
        for (_, entry) in newest {
            guard let value = entry.value, let document = try? maybeDocument(value),
                  let range = document.path.range(of: marker) else { continue }
            let path = collection + "/" + document.path[range.upperBound...]
            let found = Document(path: path, fields: document.fields, updated: document.updated)
            if let existing = documents[path], (existing.updated ?? .distantPast) >= (found.updated ?? .distantPast) { continue }
            documents[path] = found
        }
        return documents.values.sorted { $0.path < $1.path }
    }

    // MARK: LevelDB

    private struct Reader {
        let data: Data
        var offset: Int
        init(_ data: Data, offset: Int = 0) { self.data = data; self.offset = offset }
        var atEnd: Bool { offset >= data.count }
        mutating func byte() throws -> UInt8 {
            guard offset < data.count else { throw Failure.corrupt }
            defer { offset += 1 }
            return data[data.startIndex + offset]
        }
        mutating func varint() throws -> UInt64 {
            var result: UInt64 = 0, shift: UInt64 = 0
            while true {
                let next = try byte()
                guard shift < 64 else { throw Failure.corrupt }
                result |= UInt64(next & 0x7f) << shift
                if next & 0x80 == 0 { return result }
                shift += 7
            }
        }
        /// A varint used as a length or offset, refused past `Int`.
        mutating func length() throws -> Int {
            guard let value = Int(exactly: try varint()) else { throw Failure.corrupt }
            return value
        }
        mutating func fixed32() throws -> UInt32 {
            var value: UInt32 = 0
            for index in 0..<4 { value |= UInt32(try byte()) << (8 * UInt32(index)) }
            return value
        }
        mutating func fixed64() throws -> UInt64 {
            var value: UInt64 = 0
            for index in 0..<8 { value |= UInt64(try byte()) << (8 * UInt64(index)) }
            return value
        }
        mutating func bytes(_ count: Int) throws -> Data {
            guard count >= 0, count <= data.count - offset else { throw Failure.corrupt }
            defer { offset += count }
            let start = data.startIndex + offset
            return data.subdata(in: start..<(start + count))
        }
    }

    /// Write-ahead log: 32 KiB blocks of checksummed fragments holding write
    ///
    /// writing when the copy was made) ends the record it belongs to.
    private static func log(_ data: Data, _ record: (Data, UInt64, Data?) -> Void) throws {
        var offset = 0, pending: Data?
        while offset + 7 <= data.count {
            let blockLeft = 32768 - offset % 32768
            if blockLeft < 7 { offset += blockLeft; continue }
            var header = Reader(data, offset: offset)
            let checksum = try header.fixed32()
            let length = Int(try header.byte()) | Int(try header.byte()) << 8
            let type = try header.byte()
            if type == 0 && length == 0 { offset += blockLeft; continue }
            guard length <= blockLeft - 7, length <= data.count - offset - 7 else { break }
            let fragment = data.subdata(in: (data.startIndex + offset + 7)..<(data.startIndex + offset + 7 + length))
            offset += 7 + length
            guard unmasked(checksum) == crc32c([type] + fragment) else { pending = nil; continue }
            switch type {
            case 1: try? batch(fragment, record); pending = nil
            case 2: pending = fragment
            case 3: pending?.append(fragment)
            case 4:
                if var whole = pending { whole.append(fragment); try? batch(whole, record) }
                pending = nil
            default: pending = nil
            }
        }
    }

    private static func unmasked(_ value: UInt32) -> UInt32 {
        let rotated = value &- 0xa282ead8
        return (rotated >> 17) | (rotated << 15)
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? (value >> 1) ^ 0x82f63b78 : value >> 1 }
        return value
    }

    static func crc32c<S: Sequence>(_ bytes: S) -> UInt32 where S.Element == UInt8 {
        ~bytes.reduce(~UInt32(0)) { crcTable[Int(($0 ^ UInt32($1)) & 0xff)] ^ ($0 >> 8) }
    }

    private static func batch(_ data: Data, _ record: (Data, UInt64, Data?) -> Void) throws {
        var reader = Reader(data)
        let sequence = try reader.fixed64(), count = try reader.fixed32()
        for index in 0..<UInt64(count) {
            let tag = try reader.byte()
            let key = try reader.bytes(try reader.length())
            switch tag {
            case 1: record(key, sequence &+ index, try reader.bytes(try reader.length()))
            case 0: record(key, sequence &+ index, nil)
            default: throw Failure.corrupt
            }
        }
    }

    /// Sorted table: footer → index block → data blocks of internal keys.
    private static func table(_ data: Data, _ record: (Data, UInt64, Data?) -> Void) throws {
        guard data.count >= 48 else { throw Failure.corrupt }
        var footer = Reader(data, offset: data.count - 48)
        _ = (try footer.varint(), try footer.varint())
        let indexOffset = try footer.length(), indexSize = try footer.length()
        var magic = Reader(data, offset: data.count - 8)
        guard try magic.fixed64() == 0xdb4775248b80fb57 else { throw Failure.corrupt }
        // A block holds the keys after the previous index key up to its own;
        // only blocks that can hold the document table are read.
        var previous = Data()
        for (separator, handle) in try block(data, offset: indexOffset, size: indexSize) {
            let upper = separator.count >= 8 ? separator.prefix(separator.count - 8) : separator
            defer { previous = Data(upper) }
            guard !upper.lexicographicallyPrecedes(documentTable), previous.lexicographicallyPrecedes(documentTableEnd) else { continue }
            var position = Reader(handle)
            let offset = try position.length(), size = try position.length()
            guard let entries = try? block(data, offset: offset, size: size) else { continue }
            for (internalKey, value) in entries where internalKey.count >= 8 {
                var trailer = Reader(internalKey, offset: internalKey.count - 8)
                let packed = try trailer.fixed64()
                let key = internalKey.prefix(internalKey.count - 8)
                record(Data(key), packed >> 8, packed & 0xff == 1 ? value : nil)
            }
        }
    }

    private static func block(_ data: Data, offset: Int, size: Int) throws -> [(Data, Data)] {
        guard offset >= 0, size >= 4, size <= maximumBlockBytes, size <= data.count - 5, offset <= data.count - 5 - size else {
            throw Failure.corrupt
        }
        let raw = data.subdata(in: (data.startIndex + offset)..<(data.startIndex + offset + size))
        let contents: Data
        switch data[data.startIndex + offset + size] {
        case 0: contents = raw
        case 1: contents = try snappy(raw)
        default: throw Failure.corrupt
        }
        guard contents.count >= 4 else { throw Failure.corrupt }
        var tail = Reader(contents, offset: contents.count - 4)
        let restarts = Int(try tail.fixed32())
        let limit = contents.count - 4 - restarts * 4
        guard restarts >= 0, limit >= 0 else { throw Failure.corrupt }
        var reader = Reader(contents.prefix(limit)), key = Data(), result: [(Data, Data)] = []
        while !reader.atEnd {
            let shared = try reader.length(), unshared = try reader.length(), length = try reader.length()
            guard shared <= key.count else { throw Failure.corrupt }
            key = key.prefix(shared) + (try reader.bytes(unshared))
            result.append((Data(key), try reader.bytes(length)))
        }
        return result
    }

    static func snappy(_ data: Data) throws -> Data {
        var reader = Reader(data)
        let length = try reader.length()
        guard length <= maximumBlockBytes else { throw Failure.corrupt }
        var output = [UInt8](), source = [UInt8](data)
        output.reserveCapacity(length)
        var position = reader.offset
        while position < source.count {
            let tag = source[position]; position += 1
            switch tag & 3 {
            case 0:
                var count = Int(tag >> 2)
                if count >= 60 {
                    let extra = count - 59
                    guard position + extra <= source.count else { throw Failure.corrupt }
                    count = 0
                    for index in 0..<extra { count |= Int(source[position + index]) << (8 * index) }
                    position += extra
                }
                count += 1
                guard position + count <= source.count else { throw Failure.corrupt }
                output.append(contentsOf: source[position..<(position + count)]); position += count
            default:
                let count: Int, distance: Int
                switch tag & 3 {
                case 1:
                    guard position < source.count else { throw Failure.corrupt }
                    count = 4 + Int((tag >> 2) & 7); distance = Int(tag >> 5) << 8 | Int(source[position]); position += 1
                case 2:
                    guard position + 2 <= source.count else { throw Failure.corrupt }
                    count = 1 + Int(tag >> 2); distance = Int(source[position]) | Int(source[position + 1]) << 8; position += 2
                default:
                    guard position + 4 <= source.count else { throw Failure.corrupt }
                    count = 1 + Int(tag >> 2)
                    distance = (0..<4).reduce(0) { $0 | Int(source[position + $1]) << (8 * $1) }; position += 4
                }
                guard distance > 0, distance <= output.count, output.count + count <= length else { throw Failure.corrupt }
                let start = output.count - distance
                for index in 0..<count { output.append(output[start + index]) }
            }
            guard output.count <= length else { throw Failure.corrupt }
        }
        guard output.count == length else { throw Failure.corrupt }
        return Data(output)
    }

    // MARK: Protocol buffers

    private struct Field { let number: UInt64; let wire: UInt64; let varint: UInt64; let bytes: Data }

    private static func fields(_ data: Data) throws -> [Field] {
        var reader = Reader(data), result: [Field] = []
        while !reader.atEnd {
            let key = try reader.varint(), number = key >> 3, wire = key & 7
            guard number > 0 else { throw Failure.corrupt }
            switch wire {
            case 0: result.append(Field(number: number, wire: 0, varint: try reader.varint(), bytes: Data()))
            case 1: result.append(Field(number: number, wire: 1, varint: try reader.fixed64(), bytes: Data()))
            case 2: result.append(Field(number: number, wire: 2, varint: 0, bytes: try reader.bytes(try reader.length())))
            case 5: result.append(Field(number: number, wire: 5, varint: UInt64(try reader.fixed32()), bytes: Data()))
            default: throw Failure.corrupt
            }
        }
        return result
    }

    /// `firestore.client.MaybeDocument` field 2: `google.firestore.v1.Document`.
    private static func maybeDocument(_ data: Data) throws -> (path: String, fields: [String: Value], updated: Date?) {
        guard let document = try fields(data).first(where: { $0.number == 2 && $0.wire == 2 }) else { throw Failure.corrupt }
        var path: String?, values: [String: Value] = [:], updated: Date?
        for field in try fields(document.bytes) {
            switch (field.number, field.wire) {
            case (1, 2): path = String(data: field.bytes, encoding: .utf8)
            case (2, 2): let (key, value) = try entry(field.bytes, depth: 0); values[key] = value
            case (4, 2): updated = try timestamp(field.bytes)
            default: continue
            }
        }
        guard let path, path.contains("/documents/") else { throw Failure.corrupt }
        return (path, values, updated)
    }

    private static func entry(_ data: Data, depth: Int) throws -> (String, Value) {
        var key = "", value = Value.null
        for field in try fields(data) {
            if field.number == 1, field.wire == 2 { key = String(decoding: field.bytes, as: UTF8.self) }
            if field.number == 2, field.wire == 2 { value = try self.value(field.bytes, depth: depth + 1) }
        }
        return (key, value)
    }

    private static func timestamp(_ data: Data) throws -> Date {
        var seconds: Int64 = 0, nanos: Int64 = 0
        for field in try fields(data) where field.wire == 0 {
            if field.number == 1 { seconds = Int64(bitPattern: field.varint) }
            if field.number == 2 { nanos = Int64(bitPattern: field.varint) }
        }
        return Date(timeIntervalSince1970: Double(seconds) + Double(nanos) / 1e9)
    }

    /// `google.firestore.v1.Value`.
    private static func value(_ data: Data, depth: Int) throws -> Value {
        guard depth < 64 else { throw Failure.corrupt }
        for field in try fields(data) {
            switch (field.number, field.wire) {
            case (11, 0): return .null
            case (1, 0): return .bool(field.varint != 0)
            case (2, 0): return .integer(Int64(bitPattern: field.varint))
            case (3, 1): return .double(Double(bitPattern: field.varint))
            case (10, 2): return .timestamp(try timestamp(field.bytes))
            case (17, 2): return .string(String(decoding: field.bytes, as: UTF8.self))
            case (18, 2): return .bytes(field.bytes)
            case (5, 2): return .reference(String(decoding: field.bytes, as: UTF8.self))
            case (9, 2): return .array(try fields(field.bytes).filter { $0.number == 1 && $0.wire == 2 }.map { try value($0.bytes, depth: depth + 1) })
            case (6, 2):
                var map: [String: Value] = [:]
                for item in try fields(field.bytes) where item.number == 1 && item.wire == 2 {
                    let (key, value) = try entry(item.bytes, depth: depth + 1); map[key] = value
                }
                return .map(map)
            default: continue
            }
        }
        return .null
    }
}
