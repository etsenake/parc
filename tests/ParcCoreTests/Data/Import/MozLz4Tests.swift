import Foundation
import Testing
@testable import ParcCore

struct MozLz4Tests {
    private static func header(size: Int) -> Data {
        Data("mozLz40\0".utf8) + Data((0..<4).map { UInt8((size >> (8 * $0)) & 0xFF) })
    }

    private static func literalBlock(_ literals: Data) -> Data {
        let count = literals.count
        guard count >= 15 else { return Data([UInt8(count << 4)]) + literals }
        var block = Data([0xF0])
        var rest = count - 15
        while rest >= 255 {
            block.append(0xFF)
            rest -= 255
        }
        block.append(UInt8(rest))
        return block + literals
    }

    @Test func aShortLiteralOnlyBlockDecodes() throws {
        let payload = Data(#"{"a":1}"#.utf8)
        let file = Self.header(size: payload.count) + Data([0x70]) + payload
        #expect(try MozLz4.decode(file) == payload)
    }

    @Test(arguments: [15, 16, 269, 270, 271, 600])
    func aLongLiteralRunUsesExtraLengthBytes(_ count: Int) throws {
        let payload = Data((0..<count).map { UInt8(0x41 + $0 % 26) })
        let block = Self.literalBlock(payload)
        #expect(block.first == 0xF0)
        #expect(block.count == payload.count + 2 + (count - 15) / 255)
        #expect(try MozLz4.decode(Self.header(size: count) + block) == payload)
    }

    @Test func anOverlappingMatchCopiesEarlierBytes() throws {
        let block = Data([0x44]) + Data("abcd".utf8) + Data([0x04, 0x00]) + Data([0x50]) + Data("WXYZ!".utf8)
        let expected = Data("abcdabcdabcdWXYZ!".utf8)
        #expect(try MozLz4.decode(Self.header(size: expected.count) + block) == expected)
    }

    @Test func encodingThenDecodingGivesTheSameBytes() throws {
        let payload = Data(String(repeating: #"{"tabs":[{"url":"https://example.com/"}]}"#, count: 200).utf8)
        let encoded = MozLz4.encode(payload)
        #expect(encoded.prefix(8) == Data("mozLz40\0".utf8))
        #expect(encoded.count < payload.count)
        #expect(try MozLz4.decode(encoded) == payload)
    }

    @Test func emptyContentRoundTrips() throws {
        let encoded = MozLz4.encode(Data())
        #expect(encoded == Self.header(size: 0))
        #expect(try MozLz4.decode(encoded) == Data())
    }

    @Test func anEncryptedFileIsRecognized() {
        let file = Data("mozEnc0\0".utf8) + Data([0x10, 0, 0, 0]) + Data(repeating: 0xAB, count: 32)
        #expect(throws: MozLz4.Failure.encrypted) { try MozLz4.decode(file) }
    }

    @Test func aFileWithoutTheMagicIsRefused() {
        #expect(throws: MozLz4.Failure.notMozLz4) { try MozLz4.decode(Data("not a mozlz4 file".utf8)) }
        #expect(throws: MozLz4.Failure.notMozLz4) { try MozLz4.decode(Data("mozLz40".utf8)) }
    }

    @Test func aTruncatedBlockIsCorrupt() {
        let payload = Data((0..<300).map { UInt8(0x61 + $0 % 26) })
        let file = Self.header(size: payload.count) + Self.literalBlock(payload)
        #expect(throws: MozLz4.Failure.corrupt) { try MozLz4.decode(file.prefix(file.count / 2)) }
        #expect(throws: MozLz4.Failure.corrupt) { try MozLz4.decode(Self.header(size: payload.count)) }
    }

    @Test func aHeaderPromisingMoreThanTheBlockHoldsIsCorrupt() {
        let payload = Data(#"{"a":1}"#.utf8)
        #expect(throws: MozLz4.Failure.corrupt) {
            try MozLz4.decode(Self.header(size: payload.count + 5) + Self.literalBlock(payload))
        }
    }

    @Test func anOversizedHeaderIsRefused() {
        let file = Data("mozLz40\0".utf8) + Data([0xFF, 0xFF, 0xFF, 0x7F]) + Data([0x10, 0x41])
        #expect(throws: MozLz4.Failure.tooLarge) { try MozLz4.decode(file) }
    }
}
