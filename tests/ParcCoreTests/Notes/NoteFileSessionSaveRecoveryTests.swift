import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteFileSessionSaveRecoveryTests {
    private let fixture = NoteFileSessionTestsSupport.Fixture()

    private func evicted() throws -> NoteFileSession {
        let session = try fixture.open("evicted.txt", "base\n")
        fixture.setText(session, "mine")
        try FileManager.default.removeItem(at: session.url)
        session.checkDisk()
        return session
    }

    @Test func aFileThatVanishesUnderUnsavedEditsKeepsItsTextInMemory() throws {
        let session = try evicted()
        #expect(session.state == .missing)
        #expect(fixture.texts(session) == ["mine"])
    }

    @Test func autosaveLeavesAVanishedFileMissing() throws {
        let session = try evicted()
        fixture.clock.advance(5)
        #expect(!NoteFilePaths.itemExists(session.url))
    }

    @Test func aFileThatReturnsAsItWasKeepsUnsavedEdits() throws {
        let session = try evicted()
        NoteFileTestSupport.write("base\n", to: session.url)
        session.checkDisk()
        #expect(fixture.texts(session) == ["mine"])
    }

    @Test func aFileThatReturnsAsItWasCanAutosaveTheEdits() throws {
        let session = try evicted()
        NoteFileTestSupport.write("base\n", to: session.url)
        session.checkDisk()
        fixture.clock.advance(1)
        #expect(NoteFileTestSupport.read(session.url) == "mine\n")
        #expect(session.state == .saved)
    }

    @Test func aDifferentFileReturningConflictsWithUnsavedEdits() throws {
        let session = try evicted()
        NoteFileTestSupport.write("someone else's\n", to: session.url)
        session.checkDisk()
        #expect(session.state == .conflict)
        #expect(fixture.texts(session) == ["mine"])
        #expect(session.conflictingText == "someone else's")
    }

    @Test func autosaveDoesNotOverwriteADifferentFileThatReturns() throws {
        let session = try evicted()
        NoteFileTestSupport.write("someone else's\n", to: session.url)
        session.checkDisk()
        fixture.clock.advance(5)
        #expect(NoteFileTestSupport.read(session.url) == "someone else's\n")
    }

    @Test func anExplicitFlushPutsUnsavedEditsBack() throws {
        let session = try evicted()
        try session.flush()
        #expect(NoteFileTestSupport.read(session.url) == "mine\n")
    }

    @Test func anAutosaveRacingAMoveFollowsTheFile() throws {
        let session = try fixture.open("Racer.md", "Original\n")
        let original = session.url
        fixture.setText(session, "Edited on the way")
        let destination = fixture.folder.appendingPathComponent("Racer moved.md")
        try FileManager.default.moveItem(at: original, to: destination)
        fixture.clock.advance(2)
        #expect(!NoteFilePaths.itemExists(original))
        #expect(session.url == destination)
        #expect(NoteFileTestSupport.read(destination).contains("Edited on the way"))
        #expect(session.state == .saved)
    }

    @Test func anAutosaveRacingAMoveToTheTrashDoesNotRecreateTheFile() throws {
        let session = try fixture.open("Racer.md", "Original\n")
        let original = session.url
        fixture.setText(session, "Last words before the Trash")
        try FileManager.default.moveItem(at: original, to: try fixture.trashFolder().appendingPathComponent("Racer.md"))
        fixture.clock.advance(5)
        #expect(!NoteFilePaths.itemExists(original))
        #expect(session.state == .missing)
        #expect(fixture.texts(session) == ["Last words before the Trash"])
    }

    @Test func aFlushRacingAMoveWritesWhereTheFileWent() throws {
        let session = try fixture.open("Flushed.md", "Before\n")
        let original = session.url
        fixture.setText(session, "After")
        let elsewhere = fixture.folder.appendingPathComponent("Flushed elsewhere.md")
        try FileManager.default.moveItem(at: original, to: elsewhere)
        try session.flush()
        #expect(!NoteFilePaths.itemExists(original))
        #expect(NoteFileTestSupport.read(elsewhere).contains("After"))
        #expect(session.url == elsewhere)
    }

    private func stubborn() throws -> (URL, URL, NoteFileSession) {
        let locked = fixture.folder.appendingPathComponent("Locked", isDirectory: true)
        let session = try fixture.open("Locked/Stubborn.txt", "start\n")
        session.retain()
        fixture.setText(session, "kept safe")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        return (locked, session.url, session)
    }

    private func unlock(_ locked: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
    }

    private func contested() throws -> (URL, NoteFileSession) {
        let url = fixture.file("Contested.md", "Base\n")
        let session = try fixture.files.open(url)
        session.retain()
        fixture.setText(session, "My take")
        NoteFileTestSupport.write("Their take\n", to: url)
        session.checkDisk()
        session.release()
        return (url, session)
    }

    @Test func flushAllNamesTheNoteThatCannotBeSaved() throws {
        let (locked, _, session) = try stubborn()
        defer { unlock(locked); session.release() }
        #expect(throws: NoteFileError.unsaved(["Stubborn"])) { try self.fixture.files.flushAll() }
    }

    @Test func aSessionThatCannotSaveStaysAliveAndSaysTheSaveFailed() throws {
        let (locked, url, session) = try stubborn()
        defer { unlock(locked) }
        session.release()
        #expect(fixture.files.session(for: url) === session)
        guard case .failed = session.state else {
            Issue.record("expected a failed save, got \(session.state)")
            return
        }
    }

    @Test func anUnattendedNoteCannotSaveWhileItsFolderIsLocked() throws {
        let (locked, url, session) = try stubborn()
        defer { unlock(locked) }
        session.release()
        fixture.clock.advance(1.5)
        #expect(NoteFileTestSupport.read(url) == "start\n")
    }

    @Test func anUnattendedNoteSavesAndClosesOnceItsFolderIsUnlocked() throws {
        let (locked, url, session) = try stubborn()
        defer { unlock(locked) }
        session.release()
        fixture.clock.advance(1.5)
        unlock(locked)
        fixture.clock.advance(5)
        #expect(NoteFileTestSupport.read(url) == "kept safe\n")
        #expect(fixture.files.session(for: url) == nil)
        #expect(!NoteFileTestSupport.isPresented(url))
    }

    @Test func anUnresolvedConflictWaitsForTheNextEditor() throws {
        let (url, session) = try contested()
        let again = try fixture.files.open(url)
        #expect(again === session && again.state == .conflict)
    }

    @Test func atQuitAnUnattendedConflictKeepsMyWordsInACopyAndCloses() throws {
        let (url, _) = try contested()
        try fixture.files.flushAll()
        #expect(NoteFileTestSupport.read(fixture.folder.appendingPathComponent("Contested (your version).md")).contains("My take"))
        #expect(NoteFileTestSupport.read(url) == "Their take\n")
        #expect(fixture.files.session(for: url) == nil)
        #expect(!NoteFileTestSupport.isPresented(url))
    }
}
