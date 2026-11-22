import Foundation
import Testing
@testable import ParcCore

struct NoteFileCodecEncodingTests {
    private func roundTrip(_ bytes: [UInt8], kind: NoteFileKind = .plainText) throws -> NoteFileContents {
        guard let contents = NoteFileText.decode(Data(bytes), kind: kind) else { throw NoteTestFailure("could not decode \(bytes)") }
        let encoded = NoteFileText.encode(contents.text, format: contents.format)
        #expect([UInt8](encoded.data) == bytes, "encoding writes the same bytes back")
        #expect(encoded.format == contents.format, "the format survives a round trip")
        return contents
    }

    struct LineEnding: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let text: String
        let expected: NoteFileLineEnding?
    }

    private static let lineEndings = [
        LineEnding(testDescription: "LF", text: "a\nb\n", expected: .lf),
        LineEnding(testDescription: "CRLF", text: "a\r\nb\r\n", expected: .crlf),
        LineEnding(testDescription: "CR", text: "a\rb\r", expected: .cr),
        LineEnding(testDescription: "majority ending", text: "a\r\nb\r\nc\n", expected: .crlf),
        LineEnding(testDescription: "no break", text: "one line", expected: nil),
    ]

    struct PlainText: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let text: String
    }

    private static let plainTexts = [
        PlainText(testDescription: "LF with final newline", text: "a\nb\n"),
        PlainText(testDescription: "no final newline", text: "a\nb"),
        PlainText(testDescription: "trailing blank line", text: "a\n\n"),
        PlainText(testDescription: "just a newline", text: "\n"),
        PlainText(testDescription: "empty file", text: ""),
        PlainText(testDescription: "CRLF with final newline", text: "a\r\nb\r\n"),
        PlainText(testDescription: "CRLF with trailing blank line", text: "x\r\n\r\n"),
        PlainText(testDescription: "tabs and trailing spaces", text: "tabs\tand  spaces  \n"),
    ]

    @Test func utf8DecodesAndRoundTrips() throws {
        let plain = try roundTrip(Array("café\n".utf8))
        #expect(plain.text == "café\n", "UTF-8 decodes")
        #expect(plain.format == NoteFileFormat(encoding: .utf8, byteOrderMark: false, lineEnding: .lf, endsWithNewline: true), "UTF-8 format")
    }

    @Test func utf8ByteOrderMarksAreRememberedAndExcludedFromText() throws {
        let marked = try roundTrip([0xEF, 0xBB, 0xBF] + Array("hi".utf8))
        #expect(marked.text == "hi", "the UTF-8 BOM isn't part of the text")
        #expect(marked.format.byteOrderMark && marked.format.encoding == .utf8, "the UTF-8 BOM is remembered")
    }

    @Test func utf16LittleEndianWithAMarkDecodesAndRoundTrips() throws {
        let little = try roundTrip([0xFF, 0xFE] + Array("añ\r\n".data(using: .utf16LittleEndian)!))
        #expect(little.text == "añ\r\n", "UTF-16 LE with a BOM decodes")
        #expect(little.format.encoding == .utf16LittleEndian && little.format.byteOrderMark, "UTF-16 LE is remembered")
        #expect(little.format.lineEnding == .crlf, "UTF-16 CRLF is detected")
    }

    @Test func utf16BigEndianWithAMarkDecodesAndRoundTrips() throws {
        let big = try roundTrip([0xFE, 0xFF] + Array("✓ ok".data(using: .utf16BigEndian)!))
        #expect(big.text == "✓ ok", "UTF-16 BE with a BOM decodes")
        #expect(big.format.encoding == .utf16BigEndian, "UTF-16 BE is remembered")
    }

    @Test func utf32LittleEndianWithAMarkDecodesAndRoundTrips() throws {
        let wide = try roundTrip([0xFF, 0xFE, 0x00, 0x00] + Array("🙂".data(using: .utf32LittleEndian)!))
        #expect(wide.text == "🙂", "UTF-32 LE with a BOM decodes")
    }

    @Test func unmarkedUtf16LittleEndianIsDetectedAndStaysUnmarked() throws {
        let unmarked = try roundTrip(Array("hello there\n".data(using: .utf16LittleEndian)!))
        #expect(unmarked.text == "hello there\n", "unmarked UTF-16 LE is sniffed")
        #expect(unmarked.format.encoding == .utf16LittleEndian && !unmarked.format.byteOrderMark, "unmarked UTF-16 stays unmarked")
    }

    @Test func windowsLatin1IsTheLegacyFallback() throws {
        let legacy = try roundTrip([0x63, 0x61, 0x66, 0xE9, 0x20, 0x93, 0x71, 0x94])
        #expect(legacy.text == "café “q”", "Windows Latin 1 is the legacy fallback")
        #expect(legacy.format.encoding == .windowsCP1252, "the legacy encoding is remembered")
    }

    @Test func unmappedWindowsLatin1BytesFallBackToISOLatin1() throws {
        let latin = try roundTrip([0x41, 0x81, 0x42])
        #expect(latin.format.encoding == .isoLatin1, "bytes CP1252 can't map fall back to ISO Latin 1")
        #expect(latin.text.unicodeScalars.map(\.value) == [0x41, 0x81, 0x42], "ISO Latin 1 keeps every byte")
    }

    @Test func binaryDataIsRefused() {
        #expect(NoteFileText.decode(Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x1A, 0x00, 0x00, 0x7F, 0x00]), kind: .markdown) == nil, "binary data isn't text")
    }

    @Test func anEmptyMarkdownFileDecodesWithAFinalNewlinePolicy() {
        let empty = NoteFileText.decode(Data(), kind: .markdown)
        #expect(empty?.text == "", "an empty file decodes")
        #expect(empty?.format.endsWithNewline == true, "an empty Markdown file will end with a newline once written")
    }

    @Test func anEmptyPlainTextFileStaysBare() {
        #expect(NoteFileText.decode(Data(), kind: .plainText)?.format.endsWithNewline == false, "an empty text file stays bare")
    }

    @Test func unrepresentableLegacyTextUpgradesLosslesslyToUtf8() throws {
        let legacy = try roundTrip([0x63, 0x61, 0x66, 0xE9, 0x20, 0x93, 0x71, 0x94])
        var upgraded = legacy.format
        let encoded = NoteFileText.encode("café 🙂", format: upgraded)
        upgraded = encoded.format
        #expect(upgraded.encoding == .utf8, "text the legacy encoding can't hold upgrades to UTF-8")
        #expect(String(decoding: encoded.data, as: UTF8.self) == "café 🙂", "nothing is lost in the upgrade")
    }

    @Test(arguments: lineEndings) func lineEndingDetectionReportsThePredominantEnding(_ example: LineEnding) {
        #expect(NoteFileText.lineEnding(of: example.text) == example.expected)
    }

    @Test func mixedLineEndingsNormalizeToLf() {
        #expect(NoteFileText.normalizedLineEndings("a\r\nb\rc\n") == "a\nb\nc\n", "everything normalizes to LF")
    }

    @Test(arguments: plainTexts) func plainTextRoundTripsExactly(_ example: PlainText) {
        let text = example.text
        let contents = NoteFileText.decode(Data(text.utf8), kind: .plainText)!
        let editable = NoteFileText.editableText(contents, kind: .plainText)
        let page = NotePlainText.parse(editable)
        let written = NoteFileText.fileText(NotePlainText.serialize(page), format: contents.format, kind: .plainText)
        #expect(written == text, "plain text round-trips exactly")
    }

    @Test func theFinalNewlineDoesNotMakeAnEditableParagraph() {
        let contents = NoteFileText.decode(Data("a\nb\n".utf8), kind: .plainText)!
        #expect(NoteFileText.editableText(contents, kind: .plainText) == "a\nb", "the final newline isn't an empty paragraph")
    }

    @Test func markdownUsesTheFileLineEndingsAndOneFinalNewline() {
        let crlf = NoteFileFormat(encoding: .utf8, byteOrderMark: false, lineEnding: .crlf, endsWithNewline: true)
        #expect(NoteFileText.fileText("# Hi\n\nThere\n\n\n", format: crlf, kind: .markdown) == "# Hi\r\n\r\nThere\r\n", "Markdown keeps one final newline and the file's line endings")
    }

    @Test func markdownPreservesTheAbsenceOfAFinalNewline() {
        let crlf = NoteFileFormat(encoding: .utf8, byteOrderMark: false, lineEnding: .crlf, endsWithNewline: true)
        var bare = crlf
        bare.endsWithNewline = false
        #expect(NoteFileText.fileText("# Hi\n", format: bare, kind: .markdown) == "# Hi", "a file without a final newline stays that way")
    }

    @Test func emptyMarkdownWritesAnEmptyFile() {
        #expect(NoteFileText.fileText("\n\n", format: .standard, kind: .markdown) == "", "an empty page writes an empty file")
    }
}
