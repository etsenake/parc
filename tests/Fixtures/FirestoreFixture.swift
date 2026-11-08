import Foundation

/// Writes a synthetic Firestore offline cache: one LevelDB write-ahead log of
/// `firestore.client.MaybeDocument` records, enough for the cache reader.
enum FirestoreFixture {
    static func varint(_ value: UInt64) -> [UInt8] {
        var value = value, result: [UInt8] = []
        while value >= 0x80 { result.append(UInt8(value & 0x7f) | 0x80); value >>= 7 }
        return result + [UInt8(value)]
    }
    static func bytes(_ number: UInt64, _ payload: [UInt8]) -> [UInt8] { varint(number << 3 | 2) + varint(UInt64(payload.count)) + payload }
    static func number(_ number: UInt64, _ value: UInt64) -> [UInt8] { varint(number << 3) + varint(value) }
    static func timestamp(_ date: Date) -> [UInt8] {
        let seconds = floor(date.timeIntervalSince1970)
        return number(1, UInt64(seconds)) + number(2, UInt64(((date.timeIntervalSince1970 - seconds) * 1e9).rounded()))
    }
    static func entry(_ key: String, _ value: FirestoreCache.Value) -> [UInt8] { bytes(1, Array(key.utf8)) + bytes(2, encode(value)) }
    static func encode(_ value: FirestoreCache.Value) -> [UInt8] {
        switch value {
        case .null: return number(11, 0)
        case .bool(let flag): return number(1, flag ? 1 : 0)
        case .integer(let integer): return number(2, UInt64(bitPattern: integer))
        case .double(let double):
            var bits = double.bitPattern.littleEndian
            return varint(3 << 3 | 1) + withUnsafeBytes(of: &bits) { Array($0) }
        case .timestamp(let date): return bytes(10, timestamp(date))
        case .string(let text): return bytes(17, Array(text.utf8))
        case .bytes(let data): return bytes(18, Array(data))
        case .reference(let path): return bytes(5, Array(path.utf8))
        case .array(let values): return bytes(9, values.flatMap { bytes(1, encode($0)) })
        case .map(let fields): return bytes(6, fields.sorted { $0.key < $1.key }.flatMap { bytes(1, entry($0.key, $0.value)) })
        }
    }
    static func document(_ path: String, _ fields: [String: FirestoreCache.Value], updated: Date) -> [UInt8] {
        let name = "projects/test/databases/(default)/documents/" + path
        let body = bytes(1, Array(name.utf8)) + fields.sorted { $0.key < $1.key }.flatMap { bytes(2, entry($0.key, $0.value)) }
            + bytes(4, timestamp(updated))
        return bytes(2, body)
    }
    /// One write batch per call, each a FULL log record in its own 32 KiB block.
    /// Keys are placed in the document table unless they start with "raw:".
    /// LevelDB's masked CRC-32C of a fragment's type and payload.
    static func checksum(_ type: UInt8, _ payload: [UInt8]) -> [UInt8] {
        let crc = FirestoreCache.crc32c([type] + payload)
        let masked = ((crc >> 15) | (crc << 17)) &+ 0xa282ead8
        return withUnsafeBytes(of: masked.littleEndian) { Array($0) }
    }
    static func fragment(_ type: UInt8, _ payload: [UInt8], corrupt: Bool = false) -> [UInt8] {
        var sum = checksum(type, payload)
        if corrupt { sum[0] ^= 0xff }
        return sum + [UInt8(payload.count & 0xff), UInt8(payload.count >> 8), type] + payload
    }
    static func log(_ batches: [(sequence: UInt64, records: [(key: String, value: [UInt8]?)])]) -> Data {
        var data = Data()
        for batch in batches {
            let body = self.batch(batch.sequence, batch.records)
            precondition(body.count <= 32768 - 7)
            data.append(contentsOf: fragment(1, body))
            data.append(Data(count: (32768 - data.count % 32768) % 32768))
        }
        return data
    }
    static func batch(_ sequence: UInt64, _ records: [(key: String, value: [UInt8]?)]) -> [UInt8] {
        var body = withUnsafeBytes(of: sequence.littleEndian) { Array($0) }
        body += withUnsafeBytes(of: UInt32(records.count).littleEndian) { Array($0) }
        for record in records {
            // "raw:" keys stand for another Firestore table.
            let key = record.key.hasPrefix("raw:") ? Array(record.key.dropFirst(4).utf8)
                : Array(FirestoreCache.documentTable) + Array(record.key.utf8)
            body += [record.value == nil ? 0 : 1] + varint(UInt64(key.count)) + key
            if let value = record.value { body += varint(UInt64(value.count)) + value }
        }
        return body
    }
}
