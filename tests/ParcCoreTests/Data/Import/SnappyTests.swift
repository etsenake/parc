import Foundation
import Testing
@testable import ParcCore

struct SnappyTests {
    static func text(_ value: String) -> [UInt8] { Array(value.utf8) }

    static func sample(_ count: Int) -> [UInt8] { (0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) } }

    @Test func anEmptyStreamDecodesToNothing() {
        #expect(Snappy.decompress([0]) == [])
    }

    @Test func aShortLiteralKeepsItsBytes() {
        #expect(Snappy.decompress([5, 0x10] + Self.text("hello")) == Self.text("hello"))
    }

    @Test func everyLiteralLengthFormDecodes() {
        let hundred = Self.sample(100)
        #expect(Snappy.decompress([100, 0xf0, 99] + hundred) == hundred)
        let threeHundred = Self.sample(300)
        #expect(Snappy.decompress([0xac, 0x02, 0xf4, 0x2b, 0x01] + threeHundred) == threeHundred)
        let seventy = Self.sample(70)
        #expect(Snappy.decompress([70, 0xf8, 69, 0, 0] + seventy) == seventy)
        #expect(Snappy.decompress([70, 0xfc, 69, 0, 0, 0] + seventy) == seventy)
    }

    @Test func aOneByteOffsetCopyRepeatsEarlierBytes() {
        #expect(Snappy.decompress([12, 0x0c] + Self.text("abcd") + [0x11, 0x04]) == Self.text("abcdabcdabcd"))
    }

    @Test func aOneByteOffsetCopyUsesTheHighOffsetBitsFromTheTag() {
        let literal = Self.sample(300)
        let stream: [UInt8] = [0xb7, 0x02, 0xf4, 0x2b, 0x01] + literal + [0x3d, 0x2c]
        #expect(Snappy.decompress(stream) == literal + literal[0..<11])
    }

    @Test func aTwoByteOffsetCopyMayOverlapItsOwnOutput() {
        #expect(Snappy.decompress([8, 0x04] + Self.text("ab") + [0x16, 0x02, 0x00]) == Self.text("abababab"))
        let expected = Array(repeating: Self.text("xyz"), count: 23).flatMap { $0 }[0..<67]
        #expect(Snappy.decompress([67, 0x08] + Self.text("xyz") + [0xfe, 0x03, 0x00]) == Array(expected))
    }

    @Test func aFourByteOffsetCopyDecodes() {
        #expect(Snappy.decompress([6, 0x08] + Self.text("xyz") + [0x0b, 0x03, 0x00, 0x00, 0x00]) == Self.text("xyzxyz"))
    }

    @Test func brokenStreamsAreRejected() {
        #expect(Snappy.decompress([6, 0x04] + Self.text("ab") + [0x01, 0x00]) == nil)
        #expect(Snappy.decompress([5, 0x04] + Self.text("ab") + [0x0a, 0x05, 0x00]) == nil)
        #expect(Snappy.decompress([9, 0x04] + Self.text("ab")) == nil)
        #expect(Snappy.decompress([1, 0x04] + Self.text("ab")) == nil)
        #expect(Snappy.decompress([5, 0x10] + Self.text("he")) == nil)
        #expect(Snappy.decompress([3, 0x08] + Self.text("xyz") + [0x0b, 0x03, 0x00]) == nil)
        #expect(Snappy.decompress([0x80]) == nil)
        #expect(Snappy.decompress([100, 0xf0, 99] + Self.sample(100), maximumLength: 10) == nil)
    }
}
