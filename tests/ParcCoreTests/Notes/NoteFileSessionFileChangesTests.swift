import Combine
import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteFileSessionFileChangesTests {
    private let fixture = NoteFileSessionTestsSupport.Fixture()

    private func squatted() throws -> (URL, NoteFileSession) {
        let taken = fixture.file("Taken.md", "mine\n")
        let session = try fixture.files.open(taken)
        try FileManager.default.removeItem(at: taken)
        session.checkDisk()
        return (taken, session)
    }

    @Test func aDeletionIsNoticedAndTheTextStaysInMemory() throws {
        let session = try fixture.open("doomed.txt", "keep me\n")
        try FileManager.default.removeItem(at: session.url)
        session.checkDisk()
        #expect(session.state == .missing)
        #expect(fixture.texts(session) == ["keep me"])
    }

    @Test func anUntouchedMissingNoteIsNotRecreated() throws {
        let session = try fixture.open("doomed.txt", "keep me\n")
        try FileManager.default.removeItem(at: session.url)
        session.checkDisk()
        try session.flush()
        fixture.clock.advance(5)
        #expect(!NoteFilePaths.itemExists(session.url))
    }

    @Test func editingAMissingNoteRecreatesIt() throws {
        let session = try fixture.open("doomed.txt", "keep me\n")
        try FileManager.default.removeItem(at: session.url)
        session.checkDisk()
        fixture.setText(session, "brought back")
        fixture.clock.advance(1)
        #expect(NoteFileTestSupport.read(session.url) == "brought back\n")
        #expect(session.state == .saved)
    }

    @Test func aFileThatReappearsIsPickedUp() throws {
        let session = try fixture.open("doomed.txt", "keep me\n")
        try FileManager.default.removeItem(at: session.url)
        session.checkDisk()
        NoteFileTestSupport.write("reborn elsewhere\n", to: session.url)
        session.checkDisk()
        #expect(fixture.texts(session) == ["reborn elsewhere"])
        #expect(session.state == .saved)
    }

    @Test func puttingBackAnUntouchedNoteRewritesItJustAsItWas() throws {
        let url = fixture.file("Boomerang.md", "# Still here\nkeep me\n")
        let session = try fixture.files.open(url)
        try FileManager.default.removeItem(at: url)
        session.checkDisk()
        try session.restore()
        #expect(NoteFileTestSupport.read(url) == "# Still here\nkeep me\n")
        #expect(session.state == .saved && !session.isMissing)
    }

    @Test func aPutBackNoteIsWatchedAgain() throws {
        let url = fixture.file("Boomerang.md", "# Still here\nkeep me\n")
        let session = try fixture.files.open(url)
        session.retain()
        defer { session.release() }
        try FileManager.default.removeItem(at: url)
        session.checkDisk()
        try session.restore()
        NoteFileTestSupport.write("# Still here\nedited in another app\n", to: url)
        fixture.reload(session)
        #expect(fixture.texts(session) == ["Still here", "edited in another app"])
    }

    @Test func puttingBackKeepsUnsavedEdits() throws {
        let session = try fixture.open("Edited.txt", "base\n")
        fixture.setText(session, "unsaved words")
        try FileManager.default.removeItem(at: session.url)
        session.checkDisk()
        fixture.clock.advance(5)
        try session.restore()
        #expect(NoteFileTestSupport.read(session.url) == "unsaved words\n")
        #expect(session.state == .saved && !session.hasUnsavedChanges)
    }

    @Test func puttingBackRebuildsMissingFolders() throws {
        let nested = fixture.file("Shelf/Deep/Book.md", "On the shelf\n")
        let session = try fixture.files.open(nested)
        try FileManager.default.removeItem(at: fixture.folder.appendingPathComponent("Shelf"))
        session.checkDisk()
        try session.restore()
        #expect(NoteFileTestSupport.read(nested) == "On the shelf\n")
        #expect(session.state == .saved)
    }

    @Test func aDifferentFileInTheOldSpotStopsPuttingItBack() throws {
        let (taken, session) = try squatted()
        NoteFileTestSupport.write("someone else's\n", to: taken)
        #expect(throws: NoteFileError.occupied("Taken.md")) { try session.restore() }
        #expect(NoteFileTestSupport.read(taken) == "someone else's\n")
        #expect(fixture.texts(session) == ["mine"])
        #expect(session.state == .missing)
    }

    @Test func aFolderInTheOldSpotStopsPuttingItBack() throws {
        let (taken, session) = try squatted()
        try FileManager.default.createDirectory(at: taken, withIntermediateDirectories: false)
        #expect(throws: NoteFileError.occupied("Taken.md")) { try session.restore() }
    }

    @Test func anIdenticalFileInTheOldSpotIsPickedBackUpWithoutRewriting() throws {
        let (taken, session) = try squatted()
        NoteFileTestSupport.write("mine\n", to: taken)
        let twin = NoteFileStamp(path: taken.path)
        try session.restore()
        #expect(session.state == .saved)
        #expect(NoteFileStamp(path: taken.path) == twin)
    }

    private func trashing() throws -> (URL, NoteFileSession, NoteFiles) {
        let trash = try fixture.trashFolder()
        let files = NoteFileTestSupport.files(clock: fixture.clock, trashMover: { url in
            let target = trash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        })
        let doomed = fixture.file("Trash me.md", "bye\n")
        let session = try files.open(doomed)
        fixture.setText(session, "last words")
        try files.trash(doomed)
        return (trash, session, files)
    }

    @Test func anOutsideMoveIsFollowed() throws {
        let session = try fixture.open("wanderer.md", "Roaming\n")
        var moves: [URL] = []
        let watch = session.urlChanges.sink { moves.append($0) }
        defer { watch.cancel() }
        let destination = fixture.folder.appendingPathComponent("Moved/wanderer.md")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: session.url, to: destination)
        session.handle(.relocated(destination.path))
        fixture.clock.advance(1)
        #expect(session.url == destination)
        #expect(moves == [destination])
        #expect(fixture.files.session(for: destination) === session)
    }

    @Test func aPresenterMoveRenamesTheNote() throws {
        let session = try fixture.open("wanderer.md", "Roaming\n")
        let renamed = fixture.folder.appendingPathComponent("Renamed in Finder.md")
        try FileManager.default.moveItem(at: session.url, to: renamed)
        session.handle(.moved(renamed))
        #expect(session.title == "Renamed in Finder")
    }

    @Test func movingToTheTrashCountsAsDeletion() throws {
        let session = try fixture.open("wanderer.md", "Roaming\n")
        let original = session.url
        let trashed = try fixture.trashFolder().appendingPathComponent("wanderer.md")
        try FileManager.default.moveItem(at: original, to: trashed)
        session.handle(.moved(trashed))
        #expect(session.state == .missing)
        #expect(session.url == original)
    }

    @Test func trashingSavesTheLatestTextFirst() throws {
        let (trash, _, _) = try trashing()
        #expect(NoteFileTestSupport.read(trash.appendingPathComponent("Trash me.md")) == "last words\n")
    }

    @Test func trashingAnOpenNoteMarksItMissing() throws {
        let (_, session, _) = try trashing()
        #expect(session.state == .missing)
    }

    @Test func aTrashedOpenNoteIsNotRecreatedByAutosave() throws {
        let (_, session, _) = try trashing()
        fixture.clock.advance(5)
        #expect(!NoteFilePaths.itemExists(session.url))
    }
}
