import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteFileSessionRetentionTests {
    private let fixture = NoteFileSessionTestsSupport.Fixture()

    @Test func flushAllSavesEverySession() throws {
        let a = try fixture.open("a.txt", "a\n")
        let b = try fixture.open("b.txt", "b\n")
        fixture.setText(a, "a2")
        fixture.setText(b, "b2")
        try fixture.files.flushAll()
        #expect(NoteFileTestSupport.read(a.url) == "a2\n")
        #expect(NoteFileTestSupport.read(b.url) == "b2\n")
    }

    @Test func aSessionStaysWhileAnEditorStillHoldsIt() throws {
        let a = try fixture.open("a.txt", "a\n")
        a.retain()
        a.retain()
        a.release()
        #expect(fixture.files.session(for: a.url) === a)
    }

    @Test func theLastReleaseFlushesAndDropsTheSession() throws {
        let a = try fixture.open("a.txt", "a\n")
        a.retain()
        fixture.setText(a, "a3")
        a.release()
        #expect(NoteFileTestSupport.read(a.url) == "a3\n")
        #expect(fixture.files.session(for: a.url) == nil)
    }

    @Test func reopeningAfterTheLastReleaseMakesAFreshSessionWithTheSavedText() throws {
        let a = try fixture.open("a.txt", "a\n")
        a.retain()
        fixture.setText(a, "a3")
        a.release()
        let reopened = try fixture.files.open(a.url)
        #expect(reopened !== a)
        #expect(fixture.texts(reopened) == ["a3"])
    }

    @Test func aLateEditOnAReleasedSessionSavesWithoutStealingTheNewerSessionsSpot() throws {
        let a = try fixture.open("a.txt", "a\n")
        a.retain()
        a.release()
        let reopened = try fixture.files.open(a.url)
        fixture.setText(a, "edited after the last release")
        fixture.clock.advance(1)
        #expect(NoteFileTestSupport.read(a.url) == "edited after the last release\n")
        #expect(fixture.files.session(for: a.url) === reopened)
    }

    @Test func editingAReleasedSessionRegistersItAgain() throws {
        let lonely = try fixture.open("lonely.txt", "x\n")
        lonely.retain()
        lonely.release()
        fixture.setText(lonely, "revived")
        #expect(fixture.files.session(for: lonely.url) === lonely)
    }

    @Test func editingAReleasedSessionSavesItsText() throws {
        let lonely = try fixture.open("lonely.txt", "x\n")
        lonely.retain()
        lonely.release()
        fixture.setText(lonely, "revived")
        fixture.clock.advance(1)
        #expect(NoteFileTestSupport.read(lonely.url) == "revived\n")
    }

    @Test func aConflictedSessionStaysAliveAfterItsLastRelease() throws {
        let (url, session) = try fixture.conflicted("stuck.txt")
        session.retain()
        session.release()
        #expect(fixture.files.session(for: url) === session)
    }

    @Test func aMarkdownCopyGetsAFreshNameAndHoldsTheText() throws {
        fixture.file("Turn me.md", "existing")
        let copy = try fixture.open("Turn me.txt", "Line one\nLine two\n").saveMarkdownCopy()
        #expect(copy.lastPathComponent == "Turn me 2.md")
        #expect(NoteFileTestSupport.read(copy).contains("Line one") && NoteFileTestSupport.read(copy).hasSuffix("\n"))
    }

    @Test func savingAMarkdownCopyLeavesTheTextFileUntouched() throws {
        let session = try fixture.open("Turn me.txt", "Line one\nLine two\n")
        _ = try session.saveMarkdownCopy()
        #expect(NoteFileTestSupport.read(session.url) == "Line one\nLine two\n")
    }
}
