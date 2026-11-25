import Foundation

struct ChromiumPickle {
    private let bytes: [UInt8]
    private var offset: Int

    init(_ payload: [UInt8]) {
        var start = payload.count
        if payload.count >= 4 {
            let size = Int(ChromiumBytes.uint32(payload, at: 0))
            if size <= payload.count {
                let header = payload.count - size
                if header >= 4, header % 4 == 0 { start = header }
            }
        }
        bytes = payload
        offset = start
    }

    private mutating func take(_ count: Int) -> ArraySlice<UInt8>? {
        guard count >= 0, count <= bytes.count - offset else {
            offset = bytes.count
            return nil
        }
        let slice = bytes[offset..<(offset + count)]
        let aligned = (count + 3) & ~3
        offset += min(aligned, bytes.count - offset)
        return slice
    }

    mutating func int32() -> Int32? {
        take(4).map { Int32(bitPattern: ChromiumBytes.uint32($0, at: $0.startIndex)) }
    }

    mutating func uint32() -> UInt32? {
        take(4).map { ChromiumBytes.uint32($0, at: $0.startIndex) }
    }

    mutating func int64() -> Int64? {
        take(8).map { Int64(bitPattern: ChromiumBytes.uint64($0, at: $0.startIndex)) }
    }

    mutating func uint64() -> UInt64? {
        take(8).map { ChromiumBytes.uint64($0, at: $0.startIndex) }
    }

    mutating func double() -> Double? {
        uint64().map(Double.init(bitPattern:))
    }

    mutating func bool() -> Bool? {
        take(1).map { $0.first != 0 }
    }

    mutating func token() -> ChromiumToken? {
        guard let high = uint64(), let low = uint64() else { return nil }
        return ChromiumToken(high: high, low: low)
    }

    mutating func string() -> String? {
        guard let length = int32(), length >= 0, let slice = take(Int(length)) else {
            offset = bytes.count
            return nil
        }
        return String(decoding: slice, as: UTF8.self)
    }

    mutating func string16() -> String? {
        guard let length = int32(), length >= 0, let slice = take(Int(length) * 2) else {
            offset = bytes.count
            return nil
        }
        let units = stride(from: slice.startIndex, to: slice.endIndex, by: 2).map {
            UInt16(slice[$0]) | UInt16(slice[$0 + 1]) << 8
        }
        return String(decoding: units, as: UTF16.self)
    }
}

enum ChromiumBytes {
    static func uint16<C: RandomAccessCollection>(_ bytes: C, at index: C.Index) -> UInt16 where C.Element == UInt8 {
        UInt16(bytes[index]) | UInt16(bytes[bytes.index(index, offsetBy: 1)]) << 8
    }

    static func uint32<C: RandomAccessCollection>(_ bytes: C, at index: C.Index) -> UInt32 where C.Element == UInt8 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[bytes.index(index, offsetBy: $1)]) << (8 * UInt32($1)) }
    }

    static func uint64<C: RandomAccessCollection>(_ bytes: C, at index: C.Index) -> UInt64 where C.Element == UInt8 {
        (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[bytes.index(index, offsetBy: $1)]) << (8 * UInt64($1)) }
    }

    static func int32(_ bytes: [UInt8], at index: Int) -> Int32 {
        Int32(bitPattern: uint32(bytes, at: index))
    }

    static func int64(_ bytes: [UInt8], at index: Int) -> Int64 {
        Int64(bitPattern: uint64(bytes, at: index))
    }
}
