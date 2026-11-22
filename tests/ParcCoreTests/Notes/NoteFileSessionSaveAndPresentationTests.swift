import Combine
import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteFileSessionSaveAndPresentationTests {
    private let fixture = NoteFileSessionTestsSupport.Fixture()

    @Test func selectionChangesAreNotEdits() throws {
        let session = try fixture.open("README.md", "# Readme\n")
        session.page.setSelection(.caret(NotePosition(session.page.page.blocks[0].id, 2)))
        #expect(session.state == .saved)
    }

    @Test func anEditIsUnsavedUntilTheAutosave() throws {
        let session = try fixture.open("README.md", "# Readme\n")
        fixture.setText(session, "changed")
        #expect(session.state == .unsaved)
    }

    @Test func anUneditedFileIsNeverTouched() throws {
        let original = "#   Readme\n* messy   list\n\n\n\nTrailing spaces   \n"
        let url = fixture.file("README.md", original)
        let stamp = Date(timeIntervalSince1970: 1_500_000_000)
        NoteFileTestSupport.setModified(url, stamp)
        let inode = NoteFileTestSupport.inode(url)
        let session = try fixture.files.open(url)
        session.retain()
        fixture.setText(session, "changed")
        session.page.undo()
        fixture.clock.advance(10)
        try fixture.files.flushAll()
        session.release()
        #expect(NoteFileTestSupport.read(url) == original)
        #expect(NoteFileTestSupport.modified(url) == stamp)
        #expect(NoteFileTestSupport.inode(url) == inode)
    }

    @Test func typingKeepsPushingTheAutosaveBack() throws {
        let session = try fixture.open("typing.txt", "start\n")
        fixture.setText(session, "s1")
        fixture.clock.advance(0.3)
        fixture.setText(session, "s2")
        fixture.clock.advance(0.5)
        #expect(NoteFileTestSupport.read(session.url) == "start\n")
        #expect(session.state == .unsaved)
    }

    @Test func aPauseInTypingSaves() throws {
        let session = try fixture.open("typing.txt", "start\n")
        fixture.setText(session, "s2")
        fixture.clock.advance(0.6)
        #expect(NoteFileTestSupport.read(session.url) == "s2\n")
        #expect(session.state == .saved)
    }

    @Test func savingIsAnnounced() throws {
        let session = try fixture.open("typing.txt", "start\n")
        var states: [NoteFileSaveState] = []
        let watch = session.$state.sink { states.append($0) }
        defer { watch.cancel() }
        fixture.setText(session, "s2")
        fixture.clock.advance(0.6)
        #expect(states.contains(.saving))
    }

    @Test func nonStopTypingStillSavesWithinTheLongestWait() throws {
        let session = try fixture.open("typing.txt", "start\n")
        for step in 0..<11 {
            fixture.setText(session, "burst \(step)")
            fixture.clock.advance(0.5)
        }
        #expect(NoteFileTestSupport.read(session.url).hasPrefix("burst"))
    }

    @Test func flushWritesRightAway() throws {
        let session = try fixture.open("typing.txt", "start\n")
        fixture.setText(session, "flushed")
        try session.flush()
        #expect(NoteFileTestSupport.read(session.url) == "flushed\n")
        #expect(session.state == .saved)
    }

    @Test func nothingStaleFiresAfterAFlush() throws {
        let session = try fixture.open("typing.txt", "start\n")
        fixture.setText(session, "flushed")
        try session.flush()
        #expect(!fixture.clock.hasPending)
    }

    @Test func savingKeepsPermissions() throws {
        let url = fixture.file("private.txt", "secret\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let session = try fixture.files.open(url)
        fixture.setText(session, "still secret")
        try session.flush()
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o600)
    }

    private func busyNote(_ text: String = "Fresh words") throws -> (URL, NoteFileSession) {
        let url = fixture.file("Shared draft.md", "Old words\n")
        let session = try fixture.files.open(url)
        session.retain()
        fixture.setText(session, text)
        return (url, session)
    }

    private func refusedSave() throws -> (URL, NoteFileSession, (answered: Bool, error: Error?)) {
        let (url, session) = try busyNote("Mine")
        NoteFileTestSupport.write("Theirs\n", to: url)
        return (url, session, try fixture.askToSave(session))
    }

    @Test func aSaveRequestIsAnswered() throws {
        let (_, session) = try busyNote()
        defer { session.release() }
        let busy = try fixture.askToSave(session)
        #expect(busy.answered)
        #expect(busy.error == nil)
    }

    @Test func aSaveRequestReallySavesAndTheNoteKnowsIt() throws {
        let (url, session) = try busyNote("Saved while busy")
        defer { session.release() }
        _ = try fixture.askToSave(session)
        #expect(NoteFileTestSupport.read(url) == "Saved while busy\n")
        #expect(session.state == .saved)
    }

    @Test func aSavedRequestLeavesTheAutosaveNothingToDo() throws {
        let (url, session) = try busyNote()
        defer { session.release() }
        _ = try fixture.askToSave(session)
        fixture.clock.advance(1)
        #expect(NoteFileTestSupport.read(url) == "Fresh words\n")
        #expect(session.state == .saved)
    }

    @Test func aSaveThatCannotHappenIsStillAnswered() throws {
        let (_, session, refused) = try refusedSave()
        defer { session.resolveConflict(keepMine: false); session.release() }
        #expect(refused.answered)
    }

    @Test func aRefusedSaveAnswersWithTheReasonInsteadOfAFakeSuccess() throws {
        let (_, session, refused) = try refusedSave()
        defer { session.resolveConflict(keepMine: false); session.release() }
        #expect(refused.error as? NoteFileError == .conflict)
    }

    @Test func aRefusedSaveLeavesTheirWordsAndShowsTheConflict() throws {
        let (url, session, _) = try refusedSave()
        defer { session.resolveConflict(keepMine: false); session.release() }
        #expect(NoteFileTestSupport.read(url) == "Theirs\n")
        #expect(session.state == .conflict)
    }

    @Test func anOpenNotePresentsItsFile() throws {
        let session = try fixture.open("Visitor.txt", "hi\n")
        session.retain()
        defer { session.release() }
        #expect(NoteFileTestSupport.isPresented(session.url))
    }

    @Test func theLastReleaseStopsPresentingTheFile() throws {
        let session = try fixture.open("Visitor.txt", "hi\n")
        session.retain()
        session.release()
        #expect(!NoteFileTestSupport.isPresented(session.url))
    }

    @Test func editingAfterReleasePresentsTheFileAgain() throws {
        let session = try fixture.open("Visitor.txt", "hi\n")
        session.retain()
        session.release()
        fixture.setText(session, "back for more")
        #expect(NoteFileTestSupport.isPresented(session.url))
    }

    @Test func savingALateEditStopsPresentingTheFile() throws {
        let session = try fixture.open("Visitor.txt", "hi\n")
        session.retain()
        session.release()
        fixture.setText(session, "back for more")
        fixture.clock.advance(1)
        #expect(NoteFileTestSupport.read(session.url) == "back for more\n")
        #expect(!NoteFileTestSupport.isPresented(session.url))
    }
}
