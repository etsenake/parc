import AppKit
import Foundation
import Testing
@testable import ParcCore
@testable import ParcEasels

@MainActor
struct EaselInlineTextReadableTests {
    @Test func aStrayObjectReplacementCharacterDoesNotChangeTheLookOfTheInlineAfterIt() throws {
        let small = NSFont.systemFont(ofSize: 10), large = NSFont.systemFont(ofSize: 24)
        let value = NSMutableAttributedString(string: "a\u{FFFC}", attributes: [.font: small])
        value.append(EaselInlineText.character(.equation("x"), attributes: [.font: large]))
        let readable = EaselInlineText.readable(value)
        #expect(readable.string.hasPrefix("a") && !readable.string.contains("\u{FFFC}"))
        let last = readable.length - 1
        let font = try #require(readable.attribute(.font, at: last, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == 24)
        let first = try #require(readable.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(first.pointSize == 10)
    }
}
