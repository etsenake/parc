import Foundation
import Testing
@testable import ParcCore

struct NoteFileCodecNamingTests {
    struct Title: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let title: String
        let expected: String
    }

    private static let titles = [
        Title(testDescription: "slashes and colons are swapped out", title: "  Plans/ideas: 2027  ", expected: "Plans-ideas- 2027"),
        Title(testDescription: "leading dots go", title: "..hidden", expected: "hidden"),
        Title(testDescription: "dots and spaces at the front go", title: ". . .dots", expected: "dots"),
        Title(testDescription: "newlines and tabs become spaces, controls vanish", title: "line\none\ttab\u{0007}", expected: "line one tab"),
        Title(testDescription: "whitespace-only names are empty", title: "   ", expected: ""),
        Title(testDescription: "emoji sequences survive", title: "👩‍💻 Work", expected: "👩‍💻 Work"),
    ]

    @Test(arguments: titles) func titlesAreSanitizedForFileNames(_ example: Title) {
        #expect(NoteFileNaming.sanitizedTitle(example.title) == example.expected)
    }

    @Test func longFileNamesAreTruncatedWithoutLosingTheirExtension() {
        let long = String(repeating: "é", count: 300)
        let name = NoteFileNaming.fileName(base: long, pathExtension: "md")
        #expect(name.utf8.count <= NoteFileNaming.maximumComponentBytes, "long names fit in 255 bytes")
        #expect(name.hasSuffix(".md"), "the extension survives truncation")
    }

    @Test func aNumberedSuffixFitsInTheTruncatedName() {
        let long = String(repeating: "é", count: 300)
        #expect(NoteFileNaming.fileName(base: long, pathExtension: "md", suffix: " 12").hasSuffix("é 12.md"), "suffixes fit too")
    }

    @Test func untitledNamesMatchOnlyTheUntitledPattern() {
        #expect(NoteFileNaming.isUntitled("Untitled") && NoteFileNaming.isUntitled("Untitled 12"), "untitled names are spotted")
        #expect(!NoteFileNaming.isUntitled("Untitled plan") && !NoteFileNaming.isUntitled("Untitled "), "other names aren't untitled")
    }

    @Test func extensionsLoseTheirDotAndNormalizeToLowercase() {
        #expect(NoteFileNaming.sanitizedExtension(".PNG") == "png", "extensions are tidied")
    }

    @Test func uniqueNamesCountUp() {
        let folder = URL(fileURLWithPath: "/notes", isDirectory: true)
        let taken: Set<String> = ["/notes/Untitled.md", "/notes/Untitled 2.md"]
        #expect(NoteFileNaming.uniqueURL(in: folder, base: "Untitled", pathExtension: "md") { taken.contains($0.path) }.path == "/notes/Untitled 3.md", "unique names count up")
    }

    @Test func pastedImagesGetDatedNames() {
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour, components.minute, components.second) = (2026, 11, 20, 14, 3, 22)
        let date = Calendar(identifier: .gregorian).date(from: components)!
        #expect(NoteFileNaming.pastedBaseName(at: date, isImage: true) == "Pasted image 2026-11-20 at 14.03.22", "pasted images get dated names")
    }

    @Test func pastedFilesGetDatedNames() {
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour, components.minute, components.second) = (2026, 11, 20, 14, 3, 22)
        let date = Calendar(identifier: .gregorian).date(from: components)!
        #expect(NoteFileNaming.pastedBaseName(at: date, isImage: false) == "Pasted file 2026-11-20 at 14.03.22", "pasted files too")
    }
}
