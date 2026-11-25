import Foundation

struct ByteCursor {
    let bytes: [UInt8]
    let end: Int
    private(set) var offset: Int

    init(_ bytes: [UInt8], from start: Int = 0, to end: Int? = nil) {
        self.bytes = bytes
        self.end = max(0, min(end ?? bytes.count, bytes.count))
        offset = max(0, min(start, self.end))
    }

    var isAtEnd: Bool { offset >= end }
    var remaining: Int { end - offset }

    mutating func byte() -> UInt8? {
        guard offset < end else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func varint(maximumBytes: Int = 10) -> UInt64? {
        var value: UInt64 = 0
        for index in 0..<maximumBytes {
            guard let byte = byte() else { return nil }
            value |= UInt64(byte & 0x7f) << UInt64(7 * index)
            if byte < 0x80 { return value }
        }
        return nil
    }

    mutating func count() -> Int? {
        guard let value = varint(maximumBytes: 5), let count = Int(exactly: value), count <= remaining else { return nil }
        return count
    }

    mutating func take(_ count: Int) -> Range<Int>? {
        guard count >= 0, count <= remaining else { return nil }
        defer { offset += count }
        return offset..<(offset + count)
    }

    mutating func lengthPrefixedRange() -> Range<Int>? {
        guard let count = count() else { return nil }
        return take(count)
    }

    mutating func lengthPrefixed() -> [UInt8]? {
        lengthPrefixedRange().map { Array(bytes[$0]) }
    }

    mutating func fixed32() -> UInt32? {
        guard let range = take(4) else { return nil }
        return Self.fixed32(bytes, at: range.lowerBound)
    }

    mutating func fixed64() -> UInt64? {
        guard let range = take(8) else { return nil }
        return Self.fixed64(bytes, at: range.lowerBound)
    }

    static func fixed32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for index in 0..<4 { value |= UInt32(bytes[offset + index]) << UInt32(8 * index) }
        return value
    }

    static func fixed64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 { value |= UInt64(bytes[offset + index]) << UInt64(8 * index) }
        return value
    }
}

package struct ProtobufReader {
    package enum Value: Equatable {
        case varint(UInt64)
        case fixed64(UInt64)
        case bytes([UInt8])
        case fixed32(UInt32)
    }

    package let fields: [(number: Int, value: Value)]

    package init?(_ bytes: [UInt8]) {
        var cursor = ByteCursor(bytes)
        var fields: [(number: Int, value: Value)] = []
        while !cursor.isAtEnd {
            guard let key = cursor.varint(), let number = Int(exactly: key >> 3), (1...0x1fff_ffff).contains(number) else { return nil }
            switch key & 7 {
            case 0:
                guard let value = cursor.varint() else { return nil }
                fields.append((number, .varint(value)))
            case 1:
                guard let value = cursor.fixed64() else { return nil }
                fields.append((number, .fixed64(value)))
            case 2:
                guard let value = cursor.lengthPrefixed() else { return nil }
                fields.append((number, .bytes(value)))
            case 5:
                guard let value = cursor.fixed32() else { return nil }
                fields.append((number, .fixed32(value)))
            default:
                return nil
            }
        }
        self.fields = fields
    }

    package func varint(_ number: Int) -> UInt64? {
        guard let field = fields.last(where: { $0.number == number }), case .varint(let value) = field.value else { return nil }
        return value
    }

    package func int64(_ number: Int) -> Int64? {
        varint(number).map { Int64(bitPattern: $0) }
    }

    package func bool(_ number: Int) -> Bool? {
        varint(number).map { $0 != 0 }
    }

    package func bytes(_ number: Int) -> [UInt8]? {
        guard let field = fields.last(where: { $0.number == number }), case .bytes(let value) = field.value else { return nil }
        return value
    }

    package func string(_ number: Int) -> String? {
        bytes(number).map { String(decoding: $0, as: UTF8.self) }
    }

    package func message(_ number: Int) -> ProtobufReader? {
        var combined: [UInt8] = []
        var found = false
        for field in fields where field.number == number {
            guard case .bytes(let value) = field.value else { continue }
            combined.append(contentsOf: value)
            found = true
        }
        return found ? ProtobufReader(combined) : nil
    }
}
