import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteFileSessionConflictsTests {
    private let fixture = NoteFileSessionTestsSupport.Fixture()

    @Test func outsideEditsReload() throws {
        let session = try fixture.open("outside.txt", "one\ntwo\n")
        NoteFileTestSupport.write("zero\none\ntwo\n", to: session.url)
        session.checkDisk()
        #expect(fixture.texts(session) == ["zero", "one", "two"])
        #expect(session.state == .saved)
    }

    @Test func theCaretStaysNearWhereItWasAcrossAReload() throws {
        let session = try fixture.open("outside.txt", "one\ntwo\n")
        let two = session.page.page.blocks[1].id
        session.page.setSelection(.caret(NotePosition(two, 2)))
        NoteFileTestSupport.write("zero\none\ntwo\n", to: session.url)
        session.checkDisk()
        #expect(session.page.selection == .caret(NotePosition(two, 2)))
    }

    @Test func aReloadIsNotWrittenBack() throws {
        let session = try fixture.open("outside.txt", "one\n")
        NoteFileTestSupport.write("zero\none\n", to: session.url)
        let before = NoteFileTestSupport.modified(session.url)
        session.checkDisk()
        fixture.clock.advance(10)
        #expect(NoteFileTestSupport.modified(session.url) == before)
    }

    @Test func aCleanReloadStartsAFreshHistory() throws {
        let session = try fixture.open("outside.txt", "one\n")
        NoteFileTestSupport.write("zero\none\n", to: session.url)
        session.checkDisk()
        #expect(!session.page.canUndo)
    }

    @Test func checkingAnUnchangedFileChangesNothing() throws {
        let session = try fixture.open("outside.txt", "one\n")
        session.checkDisk()
        #expect(fixture.texts(session) == ["one"])
        #expect(session.state == .saved)
    }

    @Test func localAndOutsideEditsConflict() throws {
        let (_, session) = try fixture.conflicted()
        #expect(session.state == .conflict)
        #expect(session.conflictingText == "theirs")
        #expect(fixture.texts(session) == ["mine"])
    }

    @Test func autosaveNeverOverwritesDuringAConflict() throws {
        let (url, session) = try fixture.conflicted()
        fixture.setText(session, "mine, still typing")
        fixture.clock.advance(30)
        #expect(NoteFileTestSupport.read(url) == "theirs\n")
    }

    @Test func flushRefusesToPickASideInAConflict() throws {
        let (_, session) = try fixture.conflicted()
        #expect(throws: NoteFileError.conflict) { try session.flush() }
    }

    @Test func keepingMineOverwrites() throws {
        let (url, session) = try fixture.conflicted()
        session.resolveConflict(keepMine: true)
        #expect(NoteFileTestSupport.read(url) == "mine\n")
        #expect(session.state == .saved)
    }

    @Test func takingTheirsReloadsAndLeavesTheFileAlone() throws {
        let (url, session) = try fixture.conflicted()
        session.resolveConflict(keepMine: false)
        #expect(fixture.texts(session) == ["theirs"])
        #expect(session.state == .saved)
        #expect(NoteFileTestSupport.read(url) == "theirs\n")
    }

    @Test func undoAfterTakingTheirsRestoresTheLocalText() throws {
        let (_, session) = try fixture.conflicted()
        session.resolveConflict(keepMine: false)
        session.page.undo()
        #expect(fixture.texts(session) == ["mine"])
    }

    @Test func undoAfterTakingTheirsAutosavesTheLocalText() throws {
        let (url, session) = try fixture.conflicted()
        session.resolveConflict(keepMine: false)
        session.page.undo()
        fixture.clock.advance(1)
        #expect(NoteFileTestSupport.read(url) == "mine\n")
    }

    @Test func identicalOutsideTextIsNotAConflict() throws {
        let session = try fixture.open("conflict.txt", "base\n")
        fixture.setText(session, "converged")
        NoteFileTestSupport.write("converged\n", to: session.url)
        session.checkDisk()
        #expect(session.state == .saved)
    }

    @Test func aSaveDoesNotClobberAnOutsideEditItHadNotSeen() throws {
        let session = try fixture.open("race.txt", "start\n")
        fixture.setText(session, "local")
        NoteFileTestSupport.write("sneaky\n", to: session.url)
        fixture.clock.advance(1)
        #expect(NoteFileTestSupport.read(session.url) == "sneaky\n")
        #expect(session.state == .conflict)
    }
}
