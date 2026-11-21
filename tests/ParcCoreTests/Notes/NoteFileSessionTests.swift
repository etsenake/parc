import Combine
import Foundation
import Testing
@testable import ParcCore

extension NoteProcessWide {
@MainActor final class NoteFileSessionTests {
    init() {
        NoteFileSession.clock = clock
        NoteFileSession.worker = .inline
        NoteLibrary.clock = clock
        NoteLibrary.worker = .inline
        folder = NoteFileTestSupport.makeFolder("sessions")
    }

    deinit {
        NoteFileTestSupport.remove(folder)
    }

    let clock = NoteManualClock()

    var folder: URL!

    @discardableResult
    func file(_ name: String, _ text: String) -> URL {
        NoteFileTestSupport.write(text, to: folder.appendingPathComponent(name))
    }

    func setText(_ session: NoteFileSession, block index: Int = 0, _ text: String) {
        let id = session.page.page.blocks[index].id
        session.page.edit("Typing", kind: .text) { $0.update(id) { $0.text = NoteText(text) } }
    }

    func appendBlock(_ session: NoteFileSession, _ text: String) {
        session.page.edit("Add") { $0.blocks.append(.paragraph(NoteText(text))) }
    }

    func texts(_ session: NoteFileSession) -> [String] { session.page.page.blocks.map(\.text.string) }

    @Test func richTextIsntANote() throws {
        #expect(throws: NoteFileError.notANote, "rich text isn't a note") { _ = try NoteFileSession.open(file("doc.rtf", "{\\rtf1}")) }
        #expect(throws: NoteFileError.missing, "missing files say so") {
            _ = try NoteFileSession.open(folder.appendingPathComponent("nowhere.md"))
        }
        let huge = folder.appendingPathComponent("huge.txt")
        FileManager.default.createFile(atPath: huge.path, contents: nil)
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(NoteFileText.maximumSize + 1))
        try handle.close()
        #expect(throws: NoteFileError.tooLarge, "giant files are refused") { _ = try NoteFileSession.open(huge) }
        try FileManager.default.removeItem(at: huge)
        #expect(throws: NoteFileError.unreadable("It doesn’t look like text."), "binary files are refused") {
            _ = try NoteFileSession.open(NoteFileTestSupport.write(Data([0x00, 0x01, 0x02, 0xFF, 0x00, 0x7F, 0x13]), to: folder.appendingPathComponent("bin.md")))
        }

        let url = file("Shared.md", "Hello\n")
        let first = try NoteFileSession.open(url)
        let viaVar = URL(fileURLWithPath: url.path.replacingOccurrences(of: "/private/var/", with: "/var/"))
        let again = try NoteFileSession.open(viaVar)
        #expect(again === first, "every path to a file shares one session")
        #expect(NoteFileSession.session(for: viaVar) === first, "lookups canonicalize too")
        #expect(first.title == "Shared", "the title is the file name")
        #expect(first.state == .saved, "a fresh session is saved")
        #expect(first.environment is NoteFileEnvironment, "the environment is a real file environment")
        #expect(first.environment.documentURL == url, "the environment knows the note")

        let archive = folder.appendingPathComponent("Archive.md", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        #expect(throws: NoteFileError.notANote, "a folder named like a note isn't opened as one") { _ = try NoteFileSession.open(archive) }

        let shelf = folder.appendingPathComponent("Shelf", isDirectory: true)
        let book = file("Shelf/Book.md", "Words\n")
        let alias = folder.appendingPathComponent("Shelf Alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: shelf)
        let original = try NoteFileSession.open(book)
        let viaAlias = try NoteFileSession.open(alias.appendingPathComponent("Book.md"))
        #expect(viaAlias === original, "a symlinked folder shares the session")
        let viaData = try NoteFileSession.open(URL(fileURLWithPath: "/System/Volumes/Data" + book.path))
        #expect(viaData === original, "so does the firmlinked Data volume path")
        guard pathconf(folder.path, _PC_CASE_SENSITIVE) == 0 else { return }
        let shouted = shelf.appendingPathComponent("BOOK.md")
        let viaCase = try NoteFileSession.open(shouted)
        #expect(viaCase === original, "a different case shares the session")
        try FileManager.default.removeItem(at: book)
        original.checkDisk()
        #expect(NoteFileSession.session(for: shouted) === original, "a deleted note is still found by any spelling")
        let reopened = try NoteFileSession.open(alias.appendingPathComponent("book.md"))
        #expect(reopened === original, "and reopening finds it instead of failing")
    }

    @Test func encodingsAndLineEndings() throws {
        let crlf = file("windows.txt", "one\r\ntwo")
        let session = try NoteFileSession.open(crlf)
        #expect(texts(session) == ["one", "two"], "CRLF splits into lines")
        setText(session, block: 1, "deux")
        try session.flush()
        #expect(NoteFileTestSupport.read(crlf) == "one\r\ndeux", "CRLF and the missing final newline are kept")

        let wide = folder.appendingPathComponent("wide.txt")
        NoteFileTestSupport.write(Data([0xFF, 0xFE] + Array("añ\nb\n".data(using: .utf16LittleEndian)!)), to: wide)
        let utf16 = try NoteFileSession.open(wide)
        #expect(texts(utf16) == ["añ", "b"], "UTF-16 opens")
        setText(utf16, block: 1, "bé")
        try utf16.flush()
        #expect(NoteFileTestSupport.bytes(wide) == [0xFF, 0xFE] + Array("añ\nbé\n".data(using: .utf16LittleEndian)!), "UTF-16 with its BOM is written back")

        let marked = NoteFileTestSupport.write(Data([0xEF, 0xBB, 0xBF] + Array("x\n".utf8)), to: folder.appendingPathComponent("bom.txt"))
        let bom = try NoteFileSession.open(marked)
        setText(bom, "y")
        try bom.flush()
        #expect(NoteFileTestSupport.bytes(marked) == [0xEF, 0xBB, 0xBF] + Array("y\n".utf8), "the UTF-8 BOM is kept")

        let old = NoteFileTestSupport.write(Data([0x63, 0x61, 0x66, 0xE9, 0x0A]), to: folder.appendingPathComponent("legacy.txt"))
        let legacy = try NoteFileSession.open(old)
        #expect(texts(legacy) == ["café"], "legacy text opens")
        setText(legacy, "café!")
        try legacy.flush()
        #expect(NoteFileTestSupport.bytes(old) == [0x63, 0x61, 0x66, 0xE9, 0x21, 0x0A], "legacy text stays in its encoding")
        setText(legacy, "café 🙂")
        try legacy.flush()
        #expect(NoteFileTestSupport.read(old) == "café 🙂\n", "text the old encoding can't hold upgrades to UTF-8")
        #expect(legacy.format.encoding == .utf8, "the session remembers the upgrade")
    }

    @Test func plainTextTrailingNewline() throws {
        let url = file("lines.txt", "a\nb\n")
        let session = try NoteFileSession.open(url)
        #expect(texts(session) == ["a", "b"], "the final newline isn't a phantom empty line")
        appendBlock(session, "c")
        try session.flush()
        #expect(NoteFileTestSupport.read(url) == "a\nb\nc\n", "the final newline is kept")
    }

    @Test func neverRewritesUneditedFiles() throws {
        let original = "#   Readme\n* messy   list\n\n\n\nTrailing spaces   \n"
        let url = file("README.md", original)
        let stamp = Date(timeIntervalSince1970: 1_500_000_000)
        NoteFileTestSupport.setModified(url, stamp)
        let inode = NoteFileTestSupport.inode(url)
        let session = try NoteFileSession.open(url)
        session.retain()
        session.page.setSelection(.caret(NotePosition(session.page.page.blocks[0].id, 2)))
        clock.advance(10)
        try session.flush()
        #expect(session.state == .saved, "selection changes aren't edits")
        setText(session, "changed")
        #expect(session.state == .unsaved, "an edit is unsaved")
        session.page.undo()
        clock.advance(10)
        try NoteFileSession.flushAll()
        session.release()
        #expect(NoteFileTestSupport.read(url) == original, "an unedited file is never normalized")
        #expect(NoteFileTestSupport.modified(url) == stamp, "an unedited file isn't even touched")
        #expect(NoteFileTestSupport.inode(url) == inode, "an unedited file isn't replaced")
        #expect(NoteFileSession.session(for: url) == nil, "the last release drops the session")
    }

    @Test func debounceAndFlush() throws {
        let url = file("typing.txt", "start\n")
        let session = try NoteFileSession.open(url)
        var states: [NoteFileSaveState] = []
        let watch = session.$state.sink { states.append($0) }
        setText(session, "s1")
        clock.advance(0.3)
        setText(session, "s2")
        clock.advance(0.5)
        #expect(NoteFileTestSupport.read(url) == "start\n", "typing keeps pushing the autosave back")
        #expect(session.state == .unsaved, "still unsaved while typing")
        clock.advance(0.2)
        #expect(NoteFileTestSupport.read(url) == "s2\n", "a pause in typing saves")
        #expect(session.state == .saved, "saved after the autosave")
        #expect(states.contains(.saving), "saving is announced")

        for step in 0..<12 {
            setText(session, "burst \(step)")
            clock.advance(0.5)
            if NoteFileTestSupport.read(url).hasPrefix("burst") { break }
        }
        #expect(NoteFileTestSupport.read(url).hasPrefix("burst"), "non-stop typing still saves within a few seconds")

        setText(session, "flushed")
        try session.flush()
        #expect(NoteFileTestSupport.read(url) == "flushed\n", "flush writes right away")
        #expect(session.state == .saved, "flush leaves it saved")
        #expect(!clock.hasPending || { clock.advance(5); return NoteFileTestSupport.read(url) == "flushed\n" }(), "nothing stale fires later")
        watch.cancel()
    }

    @Test func permissionsAndSymlinks() throws {
        let url = file("private.txt", "secret\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let session = try NoteFileSession.open(url)
        setText(session, "still secret")
        try session.flush()
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600, "saving keeps permissions")

        let target = file("target.md", "Target\n")
        let link = folder.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let linked = try NoteFileSession.open(link)
        #expect(linked.url == target, "symlinks open the real file")
        setText(linked, "Through the link")
        try linked.flush()
        #expect((try FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == target.path, "the symlink survives saving")
        #expect(NoteFileTestSupport.read(target).contains("Through the link"), "the real file is saved")
    }

    @Test func renamesAreSanitizedAndKeepTheExtension() throws {
        let url = file("Draft.md", "Words\n")
        let session = try NoteFileSession.open(url)
        var moves: [URL] = []
        let watch = session.urlChanges.sink { moves.append($0) }
        let renamed = try session.rename(to: "  Plans/ideas: 2027 ")
        #expect(renamed.lastPathComponent == "Plans-ideas- 2027.md", "renames are sanitized and keep the extension")
        #expect(!NoteFilePaths.itemExists(url) && NoteFilePaths.itemExists(renamed), "the file moved")
        #expect(session.url == renamed, "the session follows")
        #expect(moves == [renamed], "listeners hear about the move")
        #expect(NoteFileSession.session(for: renamed) === session && NoteFileSession.session(for: url) == nil, "the registry follows")
        #expect(session.environment.documentURL == renamed, "the environment follows")

        file("Taken.md", "Other\n")
        #expect(throws: NoteFileError.nameTaken("Taken"), "collisions are refused") { _ = try session.rename(to: "Taken") }
        #expect(session.url == renamed, "a refused rename changes nothing")

        let cased = try session.rename(to: "plans-ideas- 2027")
        #expect(cased.lastPathComponent == "plans-ideas- 2027.md", "case-only renames work")
        let listing = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(listing.contains("plans-ideas- 2027.md"), "the new case is on disk")

        let dotted = try session.rename(to: "...secret")
        #expect(dotted.lastPathComponent == "secret.md", "renames can't hide the file")
        file("Untitled.md", "")
        let untitled = try session.rename(to: "   ")
        #expect(untitled.lastPathComponent == "Untitled 2.md", "an empty title becomes a fresh Untitled")
        #expect((try session.rename(to: "")) == untitled, "an untitled note stays put when cleared again")
        let long = try session.rename(to: String(repeating: "长", count: 200))
        #expect(long.lastPathComponent.utf8.count <= 255 && NoteFilePaths.itemExists(long), "long titles are truncated to fit")
        setText(session, "Saved after renames")
        try session.flush()
        #expect(NoteFileTestSupport.read(long).contains("Saved after renames"), "saving goes to the renamed file")
        #expect(!NoteFilePaths.itemExists(untitled), "the old name isn't recreated")
        watch.cancel()
    }

    @Test func outsideEditWithoutLocalChanges() throws {
        let url = file("outside.txt", "one\ntwo\nthree\n")
        let session = try NoteFileSession.open(url)
        let two = session.page.page.blocks[1].id
        session.page.setSelection(.caret(NotePosition(two, 2)))
        NoteFileTestSupport.write("zero\none\ntwo\nthree\n", to: url)
        let before = NoteFileTestSupport.modified(url)
        session.checkDisk()
        #expect(texts(session) == ["zero", "one", "two", "three"], "outside edits reload")
        #expect(session.page.selection == .caret(NotePosition(two, 2)), "the caret stays near where it was")
        #expect(session.state == .saved, "a reload is saved")
        clock.advance(10)
        #expect(NoteFileTestSupport.modified(url) == before, "a reload doesn't write back")
        #expect(!session.page.canUndo, "a clean reload starts a fresh history")
        session.checkDisk()
        #expect(texts(session) == ["zero", "one", "two", "three"], "checking an unchanged file changes nothing")
    }

    @Test func outsideEditWithLocalChanges() throws {
        let url = file("conflict.txt", "base\n")
        let session = try NoteFileSession.open(url)
        setText(session, "mine")
        NoteFileTestSupport.write("theirs\n", to: url)
        session.checkDisk()
        #expect(session.state == .conflict, "local and outside edits conflict")
        #expect(session.conflictingText == "theirs", "their text is available")
        #expect(texts(session) == ["mine"], "my text stays on screen")
        clock.advance(30)
        #expect(NoteFileTestSupport.read(url) == "theirs\n", "autosave never overwrites during a conflict")
        #expect(throws: NoteFileError.conflict, "flush refuses to pick a side") { try session.flush() }
        setText(session, "mine, still typing")
        clock.advance(30)
        #expect(NoteFileTestSupport.read(url) == "theirs\n", "typing during a conflict doesn't overwrite either")
        session.resolveConflict(keepMine: true)
        #expect(NoteFileTestSupport.read(url) == "mine, still typing\n", "keeping mine overwrites")
        #expect(session.state == .saved, "resolved and saved")

        setText(session, "mine again")
        NoteFileTestSupport.write("theirs again\n", to: url)
        session.checkDisk()
        #expect(session.state == .conflict, "a second conflict")
        session.resolveConflict(keepMine: false)
        #expect(texts(session) == ["theirs again"], "taking theirs reloads")
        #expect(session.state == .saved, "taking theirs is saved")
        #expect(NoteFileTestSupport.read(url) == "theirs again\n", "taking theirs leaves the file alone")
        session.page.undo()
        #expect(texts(session) == ["mine again"], "undo brings my version back")
        clock.advance(1)
        #expect(NoteFileTestSupport.read(url) == "mine again\n", "and saves it like any edit")

        setText(session, "converged")
        NoteFileTestSupport.write("converged\n", to: url)
        session.checkDisk()
        #expect(session.state == .saved, "identical outside text isn't a conflict")
    }

    @Test func saveNoticesUnseenOutsideEdits() throws {
        let url = file("race.txt", "start\n")
        let session = try NoteFileSession.open(url)
        setText(session, "local")
        NoteFileTestSupport.write("sneaky\n", to: url)
        clock.advance(1)
        #expect(NoteFileTestSupport.read(url) == "sneaky\n", "saving won't clobber an edit it hadn't seen yet")
        #expect(session.state == .conflict, "it becomes a conflict instead")
        session.resolveConflict(keepMine: false)
        #expect(texts(session) == ["sneaky"], "and can be resolved")
    }

    @Test func deletionAndRecreation() throws {
        let url = file("doomed.txt", "keep me\n")
        let session = try NoteFileSession.open(url)
        try FileManager.default.removeItem(at: url)
        session.checkDisk()
        #expect(session.state == .missing, "deletion is noticed")
        #expect(texts(session) == ["keep me"], "the text stays in memory")
        try session.flush()
        clock.advance(5)
        #expect(!NoteFilePaths.itemExists(url), "an untouched missing note isn't recreated")
        setText(session, "brought back")
        clock.advance(1)
        #expect(NoteFileTestSupport.read(url) == "brought back\n", "editing recreates the file")
        #expect(session.state == .saved, "and it's saved again")

        try FileManager.default.removeItem(at: url)
        session.checkDisk()
        NoteFileTestSupport.write("reborn elsewhere\n", to: url)
        session.checkDisk()
        #expect(texts(session) == ["reborn elsewhere"], "a file that reappears is picked up")
        #expect(session.state == .saved, "and is saved")
    }

    @Test func puttingItBack() throws {
        let untouched = file("Boomerang.md", "# Still here\nkeep me\n")
        let session = try NoteFileSession.open(untouched)
        session.retain()
        try FileManager.default.removeItem(at: untouched)
        session.checkDisk()
        #expect(session.state == .missing, "a deleted note with nothing unsaved shows as missing")
        try session.restore()
        #expect(NoteFileTestSupport.read(untouched) == "# Still here\nkeep me\n", "putting it back rewrites the file just as it was")
        #expect(session.state == .saved, "and it's saved")
        #expect(!session.isMissing, "and no longer missing")
        NoteFileTestSupport.write("# Still here\nedited in another app\n", to: untouched)
        session.handle(.changed)
        clock.advance(1)
        #expect(texts(session) == ["Still here", "edited in another app"], "and the file is watched again")
        session.release()

        let edited = file("Edited.txt", "base\n")
        let editing = try NoteFileSession.open(edited)
        setText(editing, "unsaved words")
        try FileManager.default.removeItem(at: edited)
        editing.checkDisk()
        clock.advance(5)
        #expect(editing.state == .missing, "a note deleted under unsaved edits shows as missing")
        try editing.restore()
        #expect(NoteFileTestSupport.read(edited) == "unsaved words\n", "putting it back keeps the unsaved edits")
        #expect(editing.state == .saved, "and saves them")
        #expect(!editing.hasUnsavedChanges, "leaving nothing unsaved")

        let shelf = folder.appendingPathComponent("Shelf", isDirectory: true)
        let nested = NoteFileTestSupport.write("On the shelf\n", to: shelf.appendingPathComponent("Deep/Book.md"))
        let orphan = try NoteFileSession.open(nested)
        try FileManager.default.removeItem(at: shelf)
        orphan.checkDisk()
        #expect(orphan.state == .missing, "a note whose folder vanished shows as missing")
        try orphan.restore()
        #expect(NoteFileTestSupport.read(nested) == "On the shelf\n", "putting it back rebuilds the missing folders too")
        #expect(orphan.state == .saved, "and it's saved")

        let taken = file("Taken.md", "mine\n")
        let squatted = try NoteFileSession.open(taken)
        try FileManager.default.removeItem(at: taken)
        squatted.checkDisk()
        NoteFileTestSupport.write("someone else's\n", to: taken)
        #expect(throws: NoteFileError.occupied("Taken.md"), "a different file in the old spot stops it") { try squatted.restore() }
        #expect(NoteFileTestSupport.read(taken) == "someone else's\n", "and stays untouched")
        #expect(texts(squatted) == ["mine"], "while the page keeps its words")
        #expect(squatted.state == .missing, "and still offers to put it back")
        #expect(NoteFileError.occupied("Taken.md").localizedDescription == "Something else is already called “Taken.md” there. Move or rename it, then try again.", "the error says what's wrong")
        try FileManager.default.removeItem(at: taken)
        try FileManager.default.createDirectory(at: taken, withIntermediateDirectories: false)
        #expect(throws: NoteFileError.occupied("Taken.md"), "so does a folder in its place") { try squatted.restore() }
        try FileManager.default.removeItem(at: taken)
        NoteFileTestSupport.write("mine\n", to: taken)
        let twin = NoteFileStamp(path: taken.path)
        try squatted.restore()
        #expect(squatted.state == .saved, "an identical file in the old spot is simply picked back up")
        #expect(NoteFileStamp(path: taken.path) == twin, "without rewriting it")
    }

    @Test func movesAndTrash() throws {
        let url = file("wanderer.md", "Roaming\n")
        let session = try NoteFileSession.open(url)
        var moves: [URL] = []
        let watch = session.urlChanges.sink { moves.append($0) }
        let sub = folder.appendingPathComponent("Moved", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let destination = sub.appendingPathComponent("wanderer.md")
        try FileManager.default.moveItem(at: url, to: destination)
        session.handle(.relocated(destination.path))
        clock.advance(1)
        #expect(session.url == destination, "an outside move is followed")
        #expect(moves == [destination], "listeners hear about outside moves")
        #expect(NoteFileSession.session(for: destination) === session, "the registry follows outside moves")

        let renamed = sub.appendingPathComponent("Renamed in Finder.md")
        try FileManager.default.moveItem(at: destination, to: renamed)
        session.handle(.moved(renamed))
        #expect(session.title == "Renamed in Finder", "presenter moves rename the note")

        let trash = folder.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let trashed = trash.appendingPathComponent("Renamed in Finder.md")
        try FileManager.default.moveItem(at: renamed, to: trashed)
        session.handle(.moved(trashed))
        #expect(session.state == .missing, "moving to the Trash counts as deletion")
        #expect(session.url == renamed, "the note doesn't follow into the Trash")
        watch.cancel()

        let doomed = file("Trash me.md", "bye\n")
        let open = try NoteFileSession.open(doomed)
        setText(open, "last words")
        let previousMover = NoteFileIO.trashMover
        NoteFileIO.trashMover = { url in
            let target = trash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
        defer { NoteFileIO.trashMover = previousMover }
        try NoteLibrary.trash(doomed)
        #expect(NoteFileTestSupport.read(trash.appendingPathComponent("Trash me.md")) == "last words\n", "trashing saves the latest text first")
        #expect(open.state == .missing, "the open note knows it's gone")
        clock.advance(5)
        #expect(!NoteFilePaths.itemExists(doomed), "a trashed note isn't recreated")
    }

    @Test func retainAndRelease() throws {
        let a = try NoteFileSession.open(file("a.txt", "a\n"))
        let b = try NoteFileSession.open(file("b.txt", "b\n"))
        a.retain()
        a.retain()
        setText(a, "a2")
        setText(b, "b2")
        try NoteFileSession.flushAll()
        #expect(NoteFileTestSupport.read(a.url) == "a2\n", "flushAll saves every session")
        #expect(NoteFileTestSupport.read(b.url) == "b2\n", "flushAll saves every session")
        setText(a, "a3")
        a.release()
        #expect(NoteFileSession.session(for: a.url) === a, "one editor still holds it")
        a.release()
        #expect(NoteFileTestSupport.read(a.url) == "a3\n", "the last release flushes")
        #expect(NoteFileSession.session(for: a.url) == nil, "and drops the session")
        let reopened = try NoteFileSession.open(a.url)
        #expect(reopened !== a, "reopening makes a fresh session")
        #expect(texts(reopened) == ["a3"], "with the saved text")

        setText(a, "edited after the last release")
        clock.advance(1)
        #expect(NoteFileTestSupport.read(a.url) == "edited after the last release\n", "a late edit on a released session still saves")
        #expect(NoteFileSession.session(for: a.url) === reopened, "without stealing the newer session's spot")

        let lonely = try NoteFileSession.open(file("lonely.txt", "x\n"))
        lonely.retain()
        lonely.release()
        setText(lonely, "revived")
        #expect(NoteFileSession.session(for: lonely.url) === lonely, "a revived session registers again when nobody else has the file")
        clock.advance(1)
        #expect(NoteFileTestSupport.read(lonely.url) == "revived\n", "and saves")

        let stuck = try NoteFileSession.open(file("stuck.txt", "x\n"))
        stuck.retain()
        setText(stuck, "mine")
        NoteFileTestSupport.write("theirs\n", to: stuck.url)
        stuck.checkDisk()
        stuck.release()
        #expect(NoteFileSession.session(for: stuck.url) === stuck, "a conflicted session stays alive rather than lose text")
        stuck.resolveConflict(keepMine: true)
    }

    @Test func theCopyGetsAFreshName() throws {
        let url = file("Turn me.txt", "Line one\nLine two\n")
        file("Turn me.md", "existing")
        let session = try NoteFileSession.open(url)
        let copy = try session.saveMarkdownCopy()
        #expect(copy.lastPathComponent == "Turn me 2.md", "the copy gets a fresh name")
        #expect(NoteFileTestSupport.read(copy).contains("Line one") && NoteFileTestSupport.read(copy).hasSuffix("\n"), "the copy holds the text")
        #expect(NoteFileTestSupport.read(url) == "Line one\nLine two\n", "the text file is untouched")
    }

    func reload(_ session: NoteFileSession) {
        session.handle(.changed)
        clock.advance(1)
    }

    func watchedFile() throws -> (URL, NoteFileSession) {
        let url = file("watched.txt", "before\n")
        let session = try NoteFileSession.open(url)
        session.retain()
        return (url, session)
    }

    @Test func anOutsideEditIsNoticedAndReloaded() throws {
        let (url, session) = try watchedFile()
        defer { session.release() }
        try Data("after\n".utf8).write(to: url, options: .atomic)
        reload(session)
        #expect(texts(session) == ["after"])
    }

    @Test func aPlainWriteAfterAnAtomicReplaceIsNoticedToo() throws {
        let (url, session) = try watchedFile()
        defer { session.release() }
        try Data("after\n".utf8).write(to: url, options: .atomic)
        reload(session)
        NoteFileTestSupport.write("plain write\n", to: url)
        reload(session)
        #expect(texts(session) == ["plain write"])
    }

    @Test func myOwnSavesDoNotBounceBackAsOutsideEdits() throws {
        let (_, session) = try watchedFile()
        defer { session.release() }
        setText(session, "typed")
        clock.advance(1)
        reload(session)
        #expect(texts(session) == ["typed"])
        #expect(session.state == .saved)
    }

    @Test func aDeletionIsNoticed() throws {
        let (url, session) = try watchedFile()
        defer { session.release() }
        try FileManager.default.removeItem(at: url)
        session.handle(.deleted)
        clock.advance(1)
        #expect(session.state == .missing)
    }

    @Test func aFileRecreatedBySomeoneElseIsPickedUp() throws {
        let (url, session) = try watchedFile()
        defer { session.release() }
        try FileManager.default.removeItem(at: url)
        session.handle(.deleted)
        clock.advance(1)
        NoteFileTestSupport.write("back again\n", to: url)
        reload(session)
        #expect(texts(session) == ["back again"])
        #expect(session.state == .saved)
    }

    @Test func deletionKeepsUnsavedEdits() throws {
        let url = file("evicted.txt", "base\n")
        let session = try NoteFileSession.open(url)
        setText(session, "mine")
        try FileManager.default.removeItem(at: url)
        session.checkDisk()
        #expect(session.state == .missing, "a file that vanishes under unsaved edits shows as missing")
        #expect(texts(session) == ["mine"], "the unsaved edits stay")
        clock.advance(5)
        #expect(!NoteFilePaths.itemExists(url), "autosave doesn't bring back a file that vanished under unsaved edits")
        NoteFileTestSupport.write("base\n", to: url)
        session.checkDisk()
        #expect(texts(session) == ["mine"], "a file that comes back as it was keeps the unsaved edits")
        clock.advance(1)
        #expect(NoteFileTestSupport.read(url) == "mine\n", "and saves them on top")
        #expect(session.state == .saved, "then it's saved")

        setText(session, "mine again")
        try FileManager.default.removeItem(at: url)
        session.checkDisk()
        NoteFileTestSupport.write("someone else's\n", to: url)
        session.checkDisk()
        #expect(session.state == .conflict, "a file that comes back different while edits are unsaved is a conflict")
        #expect(texts(session) == ["mine again"], "the edits survive it")
        #expect(session.conflictingText == "someone else's", "and the returning text is on offer")
        clock.advance(5)
        #expect(NoteFileTestSupport.read(url) == "someone else's\n", "nothing gets overwritten")
        session.resolveConflict(keepMine: true)
        #expect(NoteFileTestSupport.read(url) == "mine again\n", "keeping mine writes it")

        setText(session, "typed after")
        try FileManager.default.removeItem(at: url)
        session.checkDisk()
        try session.flush()
        #expect(NoteFileTestSupport.read(url) == "typed after\n", "an explicit flush puts unsaved edits back rather than lose them")
    }

    @Test func savesFollowMoves() throws {
        let url = file("Racer.md", "Original\n")
        let session = try NoteFileSession.open(url)
        setText(session, "Edited on the way")
        let destination = folder.appendingPathComponent("Racer moved.md")
        try FileManager.default.moveItem(at: url, to: destination)
        clock.advance(1)
        #expect(!NoteFilePaths.itemExists(url), "an autosave racing a move doesn't recreate the old name")
        #expect(session.url == destination, "the session follows the file instead")
        clock.advance(1)
        #expect(NoteFileTestSupport.read(destination).contains("Edited on the way"), "and saves there")
        #expect(session.state == .saved, "saved in its new home")

        setText(session, "Last words before the Trash")
        let trash = folder.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: destination, to: trash.appendingPathComponent("Racer moved.md"))
        clock.advance(5)
        #expect(!NoteFilePaths.itemExists(destination), "an autosave racing a move to the Trash doesn't recreate the file")
        #expect(session.state == .missing, "the note knows it's gone")
        #expect(texts(session) == ["Last words before the Trash"], "and keeps the words")

        let flushed = file("Flushed.md", "Before\n")
        let other = try NoteFileSession.open(flushed)
        setText(other, "After")
        let elsewhere = folder.appendingPathComponent("Flushed elsewhere.md")
        try FileManager.default.moveItem(at: flushed, to: elsewhere)
        try other.flush()
        #expect(!NoteFilePaths.itemExists(flushed), "a flush racing a move doesn't recreate the old name either")
        #expect(NoteFileTestSupport.read(elsewhere).contains("After"), "it writes where the file went")
        #expect(other.url == elsewhere, "and follows it")
    }

    final class PendingHops: @unchecked Sendable {
        private let lock = NSLock()
        private var hops: [() -> Void] = []

        func add(_ hop: @escaping () -> Void) { lock.withLock { hops.append(hop) } }

        func runAll() {
            while let next = lock.withLock({ hops.isEmpty ? nil : hops.removeFirst() }) { next() }
        }
    }

    func askToSave(_ session: NoteFileSession, hops: PendingHops) throws -> (answered: Bool, error: Error?) {
        let presenter = try #require(session.presenter, "an open note has a presenter")
        let reply = NoteLockedBox<Error?>()
        presenter.savePresentedItemChanges? { error in reply.set(.some(error)) }
        hops.runAll()
        return (reply.value != nil, reply.value ?? nil)
    }

    func busyNote(_ text: String = "Fresh words") throws -> (URL, NoteFileSession, PendingHops) {
        let hops = PendingHops()
        NoteFileSession.hopToMain = { hops.add($0) }
        let url = file("Shared draft.md", "Old words\n")
        let session = try NoteFileSession.open(url)
        session.retain()
        setText(session, text)
        return (url, session, hops)
    }

    @Test func aSaveRequestIsAnswered() throws {
        let (_, session, hops) = try busyNote()
        defer { session.release(); NoteFileSession.hopToMain = { DispatchQueue.main.async(execute: $0) } }
        let busy = try askToSave(session, hops: hops)
        #expect(busy.answered)
        #expect(busy.error == nil)
    }

    @Test func aSaveRequestReallySavesAndTheNoteKnowsIt() throws {
        let (url, session, hops) = try busyNote("Saved while busy")
        defer { session.release(); NoteFileSession.hopToMain = { DispatchQueue.main.async(execute: $0) } }
        _ = try askToSave(session, hops: hops)
        #expect(NoteFileTestSupport.read(url) == "Saved while busy\n")
        #expect(session.state == .saved)
    }

    @Test func aSavedRequestLeavesTheAutosaveNothingToDo() throws {
        let (url, session, hops) = try busyNote()
        defer { session.release(); NoteFileSession.hopToMain = { DispatchQueue.main.async(execute: $0) } }
        _ = try askToSave(session, hops: hops)
        clock.advance(1)
        #expect(NoteFileTestSupport.read(url) == "Fresh words\n")
    }

    func refusedSave() throws -> (URL, NoteFileSession, (answered: Bool, error: Error?)) {
        let (url, session, hops) = try busyNote("Mine")
        NoteFileTestSupport.write("Theirs\n", to: url)
        return (url, session, try askToSave(session, hops: hops))
    }

    @Test func aSaveThatCannotHappenIsStillAnswered() throws {
        let (_, session, refused) = try refusedSave()
        defer { session.resolveConflict(keepMine: false); session.release(); NoteFileSession.hopToMain = { DispatchQueue.main.async(execute: $0) } }
        #expect(refused.answered)
    }

    @Test func itAnswersWithTheReasonInsteadOfAFakeSuccess() throws {
        let (_, session, refused) = try refusedSave()
        defer { session.resolveConflict(keepMine: false); session.release(); NoteFileSession.hopToMain = { DispatchQueue.main.async(execute: $0) } }
        #expect(refused.error as? NoteFileError == .conflict)
    }

    @Test func theirWordsStayPutAndTheNoteShowsTheConflict() throws {
        let (url, session, _) = try refusedSave()
        defer { session.resolveConflict(keepMine: false); session.release(); NoteFileSession.hopToMain = { DispatchQueue.main.async(execute: $0) } }
        #expect(NoteFileTestSupport.read(url) == "Theirs\n")
        #expect(session.state == .conflict)
    }

    @Test func presentersComeAndGo() throws {
        let url = file("Visitor.txt", "hi\n")
        let session = try NoteFileSession.open(url)
        session.retain()
        #expect(NoteFileTestSupport.isPresented(url), "an open note presents its file")
        session.release()
        #expect(!NoteFileTestSupport.isPresented(url), "the last release stops presenting it")
        setText(session, "back for more")
        #expect(NoteFileTestSupport.isPresented(url), "a late edit presents it again while it saves")
        clock.advance(1)
        #expect(NoteFileTestSupport.read(url) == "back for more\n", "the late edit saves")
        #expect(!NoteFileTestSupport.isPresented(url), "and the revived session lets go once it's saved")
    }

    @Test func unattendedSessionsRecover() throws {
        let locked = folder.appendingPathComponent("Locked", isDirectory: true)
        let url = file("Locked/Stubborn.txt", "start\n")
        let session = try NoteFileSession.open(url)
        session.retain()
        setText(session, "kept safe")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        #expect(throws: NoteFileError.unsaved(["Stubborn"]), "quitting names the note that can't be saved") { try NoteFileSession.flushAll() }
        #expect(NoteFileError.unsaved(["Stubborn"]).localizedDescription == "Parc couldn’t save “Stubborn” yet. Open it to sort things out.", "in words people can act on")
        session.release()
        #expect(NoteFileSession.session(for: url) === session, "a session that can't save yet stays alive")
        if case .failed = session.state {} else { Issue.record("it says the save failed, not \(session.state)"); return }
        clock.advance(1.5)
        #expect(NoteFileTestSupport.read(url) == "start\n", "the folder is still locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        clock.advance(5)
        #expect(NoteFileTestSupport.read(url) == "kept safe\n", "it keeps retrying on its own and saves once it can")
        #expect(NoteFileSession.session(for: url) == nil, "then it lets go")
        #expect(!NoteFileTestSupport.isPresented(url), "and stops presenting the file")
    }

    @Test func quitKeepsUnattendedConflicts() throws {
        let url = file("Contested.md", "Base\n")
        let session = try NoteFileSession.open(url)
        session.retain()
        setText(session, "My take")
        NoteFileTestSupport.write("Their take\n", to: url)
        session.checkDisk()
        session.release()
        #expect(NoteFileSession.session(for: url) === session, "an unresolved conflict waits for the next editor")
        let again = try NoteFileSession.open(url)
        #expect(again === session && again.state == .conflict, "which sees the conflict")
        try NoteFileSession.flushAll()
        let copy = folder.appendingPathComponent("Contested (your version).md")
        #expect(NoteFileTestSupport.read(copy).contains("My take"), "at quit, an unattended conflict keeps my words in a copy")
        #expect(NoteFileTestSupport.read(url) == "Their take\n", "and leaves theirs alone")
        #expect(NoteFileSession.session(for: url) == nil, "so quitting isn't blocked forever")
        #expect(!NoteFileTestSupport.isPresented(url), "and the session is fully closed")
    }

    @Test func anInPlaceWriteAfterTheFileSteppedOutAndBackIsStillNoticed() throws {
        let url = file("gap.txt", "one\n")
        let session = try NoteFileSession.open(url)
        session.retain()
        defer { session.release() }
        let parked = folder.appendingPathComponent("gap parked.txt")
        #expect(rename(url.path, parked.path) == 0)
        #expect(rename(parked.path, url.path) == 0)
        session.checkDisk()
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("two, written in place\n".utf8))
        try handle.close()
        session.handle(.changed)
        clock.advance(1)
        #expect(texts(session) == ["two, written in place"])
    }

    struct Stamped {
        let url: URL
        let read: NoteFileStamp
    }

    func stampedFile() throws -> Stamped {
        let url = file("stamped.txt", "first version\n")
        let read = try #require(NoteFileStamp(path: url.path), "the file has a stamp")
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("second, longer version\n".utf8))
        try handle.close()
        return Stamped(url: url, read: read)
    }

    func listen(_ url: URL, seen: NoteFileSighting) -> [NoteFileWatchEvent] {
        let heard = NoteLockedBox<[NoteFileWatchEvent]>()
        heard.set([])
        let watcher = NoteFileWatcher(url: url, events: { event in heard.set((heard.value ?? []) + [event]) }, saveRequest: { $0(nil) })
        watcher.start(seen: seen)
        _ = watcher.movedPath()
        watcher.stop()
        return heard.value ?? []
    }

    @Test func aWatcherArmedAfterAReadNoticesTheFileMovedOnSinceThatRead() throws {
        let stamped = try stampedFile()
        #expect(listen(stamped.url, seen: .file(stamped.read)).contains(.changed))
    }

    @Test func aWatcherStaysQuietWhenNothingMovedOn() throws {
        let stamped = try stampedFile()
        let current = try #require(NoteFileStamp(path: stamped.url.path), "the file still has a stamp")
        #expect(listen(stamped.url, seen: .file(current)).isEmpty)
    }

    @Test func aFileThatVanishedSinceTheReadIsNoticedToo() throws {
        let stamped = try stampedFile()
        let current = try #require(NoteFileStamp(path: stamped.url.path), "the file still has a stamp")
        try FileManager.default.removeItem(at: stamped.url)
        #expect(listen(stamped.url, seen: .file(current)).contains(.changed))
    }

}
}
