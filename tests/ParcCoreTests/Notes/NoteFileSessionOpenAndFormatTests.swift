import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteFileSessionOpenAndFormatTests {
    private let fixture = NoteFileSessionTestsSupport.Fixture()

    @Test func richTextIsNotANote() {
        #expect(throws: NoteFileError.notANote) { _ = try self.fixture.open("doc.rtf", "{\\rtf1}") }
    }

    @Test func aMissingFileSaysSo() {
        #expect(throws: NoteFileError.missing) { _ = try self.fixture.files.open(self.fixture.folder.appendingPathComponent("nowhere.md")) }
    }

    @Test func aGiantFileIsRefused() throws {
        let huge = fixture.folder.appendingPathComponent("huge.txt")
        FileManager.default.createFile(atPath: huge.path, contents: nil)
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(NoteFileText.maximumSize + 1))
        try handle.close()
        #expect(throws: NoteFileError.tooLarge) { _ = try self.fixture.files.open(huge) }
    }

    @Test func aBinaryFileIsRefused() {
        let binary = NoteFileTestSupport.write(Data([0x00, 0x01, 0x02, 0xFF, 0x00, 0x7F, 0x13]), to: fixture.folder.appendingPathComponent("bin.md"))
        #expect(throws: NoteFileError.unreadable("It doesn’t look like text.")) { _ = try self.fixture.files.open(binary) }
    }

    @Test func aFolderNamedLikeANoteIsNotOpened() throws {
        let archive = fixture.folder.appendingPathComponent("Archive.md", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        #expect(throws: NoteFileError.notANote) { _ = try self.fixture.files.open(archive) }
    }

    @Test func openingAnAlternatePathReusesTheSession() throws {
        let url = fixture.file("Shared.md", "Hello\n")
        let first = try fixture.files.open(url)
        let viaVar = URL(fileURLWithPath: url.path.replacingOccurrences(of: "/private/var/", with: "/var/"))
        #expect(try fixture.files.open(viaVar) === first)
    }

    @Test func lookingUpAnAlternatePathFindsTheSession() throws {
        let url = fixture.file("Shared.md", "Hello\n")
        let first = try fixture.files.open(url)
        let viaVar = URL(fileURLWithPath: url.path.replacingOccurrences(of: "/private/var/", with: "/var/"))
        #expect(fixture.files.session(for: viaVar) === first)
    }

    @Test func eachFileEnvironmentKeepsItsOwnSessions() throws {
        let url = fixture.file("Shared.md", "Hello\n")
        let elsewhere = NoteFileTestSupport.files(clock: fixture.clock)
        #expect(try elsewhere.open(url) !== fixture.files.open(url))
    }

    @Test func theTitleIsTheFileName() throws {
        #expect(try fixture.open("Shared.md", "Hello\n").title == "Shared")
    }

    @Test func aFreshSessionIsSaved() throws {
        #expect(try fixture.open("Shared.md", "Hello\n").state == .saved)
    }

    @Test func theEnvironmentIsAFileEnvironmentForTheNote() throws {
        let url = fixture.file("Shared.md", "Hello\n")
        let session = try fixture.files.open(url)
        let environment = try #require(session.environment as? NoteFileEnvironment)
        #expect(environment.documentURL == url)
        #expect(environment.files === fixture.files)
    }

    @Test func aSymlinkedFolderSharesTheSession() throws {
        let book = fixture.file("Shelf/Book.md", "Words\n")
        let alias = fixture.folder.appendingPathComponent("Shelf Alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.folder.appendingPathComponent("Shelf", isDirectory: true))
        #expect(try fixture.files.open(alias.appendingPathComponent("Book.md")) === fixture.files.open(book))
    }

    @Test func theFirmlinkedDataVolumePathSharesTheSession() throws {
        let book = fixture.file("Shelf/Book.md", "Words\n")
        #expect(try fixture.files.open(URL(fileURLWithPath: "/System/Volumes/Data" + book.path)) === fixture.files.open(book))
    }

    @Test(.enabled(if: pathconf(FileManager.default.temporaryDirectory.path, _PC_CASE_SENSITIVE) == 0))
    func aDifferentCaseSharesTheSession() throws {
        let book = fixture.file("Shelf/Book.md", "Words\n")
        #expect(try fixture.files.open(fixture.folder.appendingPathComponent("Shelf/BOOK.md")) === fixture.files.open(book))
    }

    @Test(.enabled(if: pathconf(FileManager.default.temporaryDirectory.path, _PC_CASE_SENSITIVE) == 0))
    func aDeletedNoteCanStillBeFoundByAnotherSpelling() throws {
        let book = fixture.file("Shelf/Book.md", "Words\n")
        let original = try fixture.files.open(book)
        try FileManager.default.removeItem(at: book)
        original.checkDisk()
        #expect(fixture.files.session(for: fixture.folder.appendingPathComponent("Shelf/BOOK.md")) === original)
    }

    @Test(.enabled(if: pathconf(FileManager.default.temporaryDirectory.path, _PC_CASE_SENSITIVE) == 0))
    func aDeletedNoteCanStillBeOpenedByAnotherSpelling() throws {
        let book = fixture.file("Shelf/Book.md", "Words\n")
        let original = try fixture.files.open(book)
        try FileManager.default.removeItem(at: book)
        original.checkDisk()
        #expect(try fixture.files.open(fixture.folder.appendingPathComponent("Shelf/book.md")) === original)
    }

    @Test func openingCRLFTextMakesOneBlockPerLine() throws {
        let session = try fixture.open("windows.txt", "one\r\ntwo")
        #expect(fixture.texts(session) == ["one", "two"])
    }

    @Test func savingPreservesCRLFWithoutAddingAFinalNewline() throws {
        let session = try fixture.open("windows.txt", "one\r\ntwo")
        fixture.setText(session, block: 1, "deux")
        try session.flush()
        #expect(NoteFileTestSupport.read(session.url) == "one\r\ndeux")
    }

    @Test func openingUTF16TextReadsItsLines() throws {
        let wide = NoteFileTestSupport.write(Data([0xFF, 0xFE] + Array("añ\nb\n".data(using: .utf16LittleEndian)!)), to: fixture.folder.appendingPathComponent("wide.txt"))
        let session = try fixture.files.open(wide)
        #expect(fixture.texts(session) == ["añ", "b"])
    }

    @Test func savingPreservesUTF16WithItsByteOrderMark() throws {
        let wide = NoteFileTestSupport.write(Data([0xFF, 0xFE] + Array("añ\nb\n".data(using: .utf16LittleEndian)!)), to: fixture.folder.appendingPathComponent("wide.txt"))
        let session = try fixture.files.open(wide)
        fixture.setText(session, block: 1, "bé")
        try session.flush()
        #expect(NoteFileTestSupport.bytes(wide) == [0xFF, 0xFE] + Array("añ\nbé\n".data(using: .utf16LittleEndian)!))
    }

    @Test func theUTF8BOMIsKept() throws {
        let marked = NoteFileTestSupport.write(Data([0xEF, 0xBB, 0xBF] + Array("x\n".utf8)), to: fixture.folder.appendingPathComponent("bom.txt"))
        let session = try fixture.files.open(marked)
        fixture.setText(session, "y")
        try session.flush()
        #expect(NoteFileTestSupport.bytes(marked) == [0xEF, 0xBB, 0xBF] + Array("y\n".utf8))
    }

    @Test func openingLegacyTextDecodesItsAccents() throws {
        let old = NoteFileTestSupport.write(Data([0x63, 0x61, 0x66, 0xE9, 0x0A]), to: fixture.folder.appendingPathComponent("legacy.txt"))
        let session = try fixture.files.open(old)
        #expect(fixture.texts(session) == ["café"])
    }

    @Test func savingRepresentableLegacyTextPreservesItsEncoding() throws {
        let old = NoteFileTestSupport.write(Data([0x63, 0x61, 0x66, 0xE9, 0x0A]), to: fixture.folder.appendingPathComponent("legacy.txt"))
        let session = try fixture.files.open(old)
        fixture.setText(session, "café!")
        try session.flush()
        #expect(NoteFileTestSupport.bytes(old) == [0x63, 0x61, 0x66, 0xE9, 0x21, 0x0A])
    }

    @Test func textTheLegacyEncodingCannotHoldUpgradesToUTF8() throws {
        let old = NoteFileTestSupport.write(Data([0x63, 0x61, 0x66, 0xE9, 0x0A]), to: fixture.folder.appendingPathComponent("legacy.txt"))
        let session = try fixture.files.open(old)
        fixture.setText(session, "café 🙂")
        try session.flush()
        #expect(NoteFileTestSupport.read(old) == "café 🙂\n")
        #expect(session.format.encoding == .utf8)
    }

    @Test func aFinalNewlineIsNotAPhantomEmptyLine() throws {
        #expect(fixture.texts(try fixture.open("lines.txt", "a\nb\n")) == ["a", "b"])
    }

    @Test func savingKeepsTheFinalNewline() throws {
        let session = try fixture.open("lines.txt", "a\nb\n")
        session.page.edit("Add") { $0.blocks.append(.paragraph(NoteText("c"))) }
        try session.flush()
        #expect(NoteFileTestSupport.read(session.url) == "a\nb\nc\n")
    }
}
