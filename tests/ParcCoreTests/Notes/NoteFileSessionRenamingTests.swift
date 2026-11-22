import Combine
import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteFileSessionRenamingTests {
    private let fixture = NoteFileSessionTestsSupport.Fixture()

    @Test func aSymlinkOpensTheRealFile() throws {
        let target = fixture.file("target.md", "Target\n")
        let link = fixture.folder.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(try fixture.files.open(link).url == target)
    }

    @Test func savingThroughASymlinkKeepsTheLinkAndWritesTheTarget() throws {
        let target = fixture.file("target.md", "Target\n")
        let link = fixture.folder.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let linked = try fixture.files.open(link)
        fixture.setText(linked, "Through the link")
        try linked.flush()
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
        #expect(NoteFileTestSupport.read(target).contains("Through the link"))
    }

    @Test func renamesAreSanitizedAndKeepTheExtension() throws {
        let session = try fixture.open("Draft.md", "Words\n")
        let original = session.url
        let renamed = try session.rename(to: "  Plans/ideas: 2027 ")
        #expect(renamed.lastPathComponent == "Plans-ideas- 2027.md")
        #expect(!NoteFilePaths.itemExists(original) && NoteFilePaths.itemExists(renamed))
    }

    @Test func aRenameMovesTheSessionToItsNewRegistryKey() throws {
        let session = try fixture.open("Draft.md", "Words\n")
        let original = session.url
        let renamed = try session.rename(to: "Plans")
        #expect(session.url == renamed)
        #expect(fixture.files.session(for: renamed) === session && fixture.files.session(for: original) == nil)
    }

    @Test func aRenameUpdatesTheEnvironmentDocumentURL() throws {
        let session = try fixture.open("Draft.md", "Words\n")
        let renamed = try session.rename(to: "Plans")
        #expect(session.environment.documentURL == renamed)
    }

    @Test func listenersHearAboutARename() throws {
        let session = try fixture.open("Draft.md", "Words\n")
        var moves: [URL] = []
        let watch = session.urlChanges.sink { moves.append($0) }
        defer { watch.cancel() }
        let renamed = try session.rename(to: "Plans")
        #expect(moves == [renamed])
    }

    @Test func aRenameOntoATakenNameIsRefusedAndChangesNothing() throws {
        let session = try fixture.open("Draft.md", "Words\n")
        fixture.file("Taken.md", "Other\n")
        #expect(throws: NoteFileError.nameTaken("Taken")) { _ = try session.rename(to: "Taken") }
        #expect(session.url.lastPathComponent == "Draft.md")
    }

    @Test func caseOnlyRenamesWork() throws {
        let session = try fixture.open("Plans.md", "Words\n")
        #expect(try session.rename(to: "plans").lastPathComponent == "plans.md")
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path).contains("plans.md"))
    }

    @Test func renamesCannotHideTheFile() throws {
        #expect(try fixture.open("Draft.md", "Words\n").rename(to: "...secret").lastPathComponent == "secret.md")
    }

    @Test func anEmptyTitleBecomesAFreshUntitled() throws {
        let session = try fixture.open("Draft.md", "Words\n")
        fixture.file("Untitled.md", "")
        #expect(try session.rename(to: "   ").lastPathComponent == "Untitled 2.md")
    }

    @Test func anUntitledNoteStaysPutWhenClearedAgain() throws {
        let session = try fixture.open("Draft.md", "Words\n")
        let untitled = try session.rename(to: "")
        #expect(try session.rename(to: "") == untitled)
    }

    @Test func longTitlesAreTruncatedToFit() throws {
        let long = try fixture.open("Draft.md", "Words\n").rename(to: String(repeating: "长", count: 200))
        #expect(long.lastPathComponent.utf8.count <= 255 && NoteFilePaths.itemExists(long))
    }

    @Test func savingAfterARenameWritesTheRenamedFile() throws {
        let session = try fixture.open("Draft.md", "Words\n")
        let original = session.url
        let renamed = try session.rename(to: "Plans")
        fixture.setText(session, "Saved after renames")
        try session.flush()
        #expect(NoteFileTestSupport.read(renamed).contains("Saved after renames"))
        #expect(!NoteFilePaths.itemExists(original))
    }
}
