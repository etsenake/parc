import Combine
import Foundation

@main @MainActor
struct NoteFileSessionTests {
    static let clock = ManualNoteClock()
    static var folder: URL!

    static func main() {
        exitOnFailure {
            NoteFileSession.clock = clock
            NoteFileSession.worker = .inline
            NoteLibrary.clock = clock
            NoteLibrary.worker = .inline
            folder = NoteFileTestSupport.makeFolder("sessions")
            defer { NoteFileTestSupport.remove(folder) }
            try openingRules()
            try encodingsAndLineEndings()
            try plainTextTrailingNewline()
            try neverRewritesUneditedFiles()
            try debounceAndFlush()
            try permissionsAndSymlinks()
            try renaming()
            try outsideEditWithoutLocalChanges()
            try outsideEditWithLocalChanges()
            try saveNoticesUnseenOutsideEdits()
            try deletionAndRecreation()
            try movesAndTrash()
            try retainAndRelease()
            try markdownCopy()
            try liveWatcher()
            print("NoteFileSessionTests passed")
        }
    }

    @discardableResult
    static func file(_ name: String, _ text: String) -> URL {
        NoteFileTestSupport.write(text, to: folder.appendingPathComponent(name))
    }

    static func setText(_ session: NoteFileSession, block index: Int = 0, _ text: String) {
        let id = session.page.page.blocks[index].id
        session.page.edit("Typing", kind: .text) { $0.update(id) { $0.text = NoteText(text) } }
    }

    static func appendBlock(_ session: NoteFileSession, _ text: String) {
        session.page.edit("Add") { $0.blocks.append(.paragraph(NoteText(text))) }
    }

    static func texts(_ session: NoteFileSession) -> [String] { session.page.page.blocks.map(\.text.string) }

    static func openingRules() throws {
        expectThrows(NoteFileError.notANote, "rich text isn't a note") { _ = try NoteFileSession.open(file("doc.rtf", "{\\rtf1}")) }
        expectThrows(NoteFileError.missing, "missing files say so") {
            _ = try NoteFileSession.open(folder.appendingPathComponent("nowhere.md"))
        }
        let huge = folder.appendingPathComponent("huge.txt")
        FileManager.default.createFile(atPath: huge.path, contents: nil)
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(NoteFileText.maximumSize + 1))
        try handle.close()
        expectThrows(NoteFileError.tooLarge, "giant files are refused") { _ = try NoteFileSession.open(huge) }
        try FileManager.default.removeItem(at: huge)
        expectThrows(NoteFileError.unreadable("It doesn’t look like text."), "binary files are refused") {
            _ = try NoteFileSession.open(NoteFileTestSupport.write(Data([0x00, 0x01, 0x02, 0xFF, 0x00, 0x7F, 0x13]), to: folder.appendingPathComponent("bin.md")))
        }

        let url = file("Shared.md", "Hello\n")
        let first = try NoteFileSession.open(url)
        let viaVar = URL(fileURLWithPath: url.path.replacingOccurrences(of: "/private/var/", with: "/var/"))
        let again = try NoteFileSession.open(viaVar)
        expect(again === first, "every path to a file shares one session")
        expect(NoteFileSession.session(for: viaVar) === first, "lookups canonicalize too")
        expectEqual(first.title, "Shared", "the title is the file name")
        expectEqual(first.state, .saved, "a fresh session is saved")
        expect(first.environment is NoteFileEnvironment, "the environment is a real file environment")
        expectEqual(first.environment.documentURL, url, "the environment knows the note")
    }

    static func encodingsAndLineEndings() throws {
        let crlf = file("windows.txt", "one\r\ntwo")
        let session = try NoteFileSession.open(crlf)
        expectEqual(texts(session), ["one", "two"], "CRLF splits into lines")
        setText(session, block: 1, "deux")
        try session.flush()
        expectEqual(NoteFileTestSupport.read(crlf), "one\r\ndeux", "CRLF and the missing final newline are kept")

        let wide = folder.appendingPathComponent("wide.txt")
        NoteFileTestSupport.write(Data([0xFF, 0xFE] + Array("añ\nb\n".data(using: .utf16LittleEndian)!)), to: wide)
        let utf16 = try NoteFileSession.open(wide)
        expectEqual(texts(utf16), ["añ", "b"], "UTF-16 opens")
        setText(utf16, block: 1, "bé")
        try utf16.flush()
        expectEqual(NoteFileTestSupport.bytes(wide), [0xFF, 0xFE] + Array("añ\nbé\n".data(using: .utf16LittleEndian)!), "UTF-16 with its BOM is written back")

        let marked = NoteFileTestSupport.write(Data([0xEF, 0xBB, 0xBF] + Array("x\n".utf8)), to: folder.appendingPathComponent("bom.txt"))
        let bom = try NoteFileSession.open(marked)
        setText(bom, "y")
        try bom.flush()
        expectEqual(NoteFileTestSupport.bytes(marked), [0xEF, 0xBB, 0xBF] + Array("y\n".utf8), "the UTF-8 BOM is kept")

        let old = NoteFileTestSupport.write(Data([0x63, 0x61, 0x66, 0xE9, 0x0A]), to: folder.appendingPathComponent("legacy.txt"))
        let legacy = try NoteFileSession.open(old)
        expectEqual(texts(legacy), ["café"], "legacy text opens")
        setText(legacy, "café!")
        try legacy.flush()
        expectEqual(NoteFileTestSupport.bytes(old), [0x63, 0x61, 0x66, 0xE9, 0x21, 0x0A], "legacy text stays in its encoding")
        setText(legacy, "café 🙂")
        try legacy.flush()
        expectEqual(NoteFileTestSupport.read(old), "café 🙂\n", "text the old encoding can't hold upgrades to UTF-8")
        expectEqual(legacy.format.encoding, .utf8, "the session remembers the upgrade")
    }

    static func plainTextTrailingNewline() throws {
        let url = file("lines.txt", "a\nb\n")
        let session = try NoteFileSession.open(url)
        expectEqual(texts(session), ["a", "b"], "the final newline isn't a phantom empty line")
        appendBlock(session, "c")
        try session.flush()
        expectEqual(NoteFileTestSupport.read(url), "a\nb\nc\n", "the final newline is kept")
    }

    static func neverRewritesUneditedFiles() throws {
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
        expectEqual(session.state, .saved, "selection changes aren't edits")
        setText(session, "changed")
        expectEqual(session.state, .unsaved, "an edit is unsaved")
        session.page.undo()
        clock.advance(10)
        try NoteFileSession.flushAll()
        session.release()
        expectEqual(NoteFileTestSupport.read(url), original, "an unedited file is never normalized")
        expectEqual(NoteFileTestSupport.modified(url), stamp, "an unedited file isn't even touched")
        expectEqual(NoteFileTestSupport.inode(url), inode, "an unedited file isn't replaced")
        expect(NoteFileSession.session(for: url) == nil, "the last release drops the session")
    }

    static func debounceAndFlush() throws {
        let url = file("typing.txt", "start\n")
        let session = try NoteFileSession.open(url)
        var states: [NoteFileSaveState] = []
        let watch = session.$state.sink { states.append($0) }
        setText(session, "s1")
        clock.advance(0.3)
        setText(session, "s2")
        clock.advance(0.5)
        expectEqual(NoteFileTestSupport.read(url), "start\n", "typing keeps pushing the autosave back")
        expectEqual(session.state, .unsaved, "still unsaved while typing")
        clock.advance(0.2)
        expectEqual(NoteFileTestSupport.read(url), "s2\n", "a pause in typing saves")
        expectEqual(session.state, .saved, "saved after the autosave")
        expect(states.contains(.saving), "saving is announced")

        for step in 0..<12 {
            setText(session, "burst \(step)")
            clock.advance(0.5)
            if NoteFileTestSupport.read(url).hasPrefix("burst") { break }
        }
        expect(NoteFileTestSupport.read(url).hasPrefix("burst"), "non-stop typing still saves within a few seconds")

        setText(session, "flushed")
        try session.flush()
        expectEqual(NoteFileTestSupport.read(url), "flushed\n", "flush writes right away")
        expectEqual(session.state, .saved, "flush leaves it saved")
        expect(!clock.hasPending || { clock.advance(5); return NoteFileTestSupport.read(url) == "flushed\n" }(), "nothing stale fires later")
        watch.cancel()
    }

    static func permissionsAndSymlinks() throws {
        let url = file("private.txt", "secret\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let session = try NoteFileSession.open(url)
        setText(session, "still secret")
        try session.flush()
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        expectEqual(mode, 0o600, "saving keeps permissions")

        let target = file("target.md", "Target\n")
        let link = folder.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let linked = try NoteFileSession.open(link)
        expectEqual(linked.url, target, "symlinks open the real file")
        setText(linked, "Through the link")
        try linked.flush()
        expectEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path, "the symlink survives saving")
        expect(NoteFileTestSupport.read(target).contains("Through the link"), "the real file is saved")
    }

    static func renaming() throws {
        let url = file("Draft.md", "Words\n")
        let session = try NoteFileSession.open(url)
        var moves: [URL] = []
        let watch = session.urlChanges.sink { moves.append($0) }
        let renamed = try session.rename(to: "  Plans/ideas: 2027 ")
        expectEqual(renamed.lastPathComponent, "Plans-ideas- 2027.md", "renames are sanitized and keep the extension")
        expect(!NoteFilePaths.itemExists(url) && NoteFilePaths.itemExists(renamed), "the file moved")
        expectEqual(session.url, renamed, "the session follows")
        expectEqual(moves, [renamed], "listeners hear about the move")
        expect(NoteFileSession.session(for: renamed) === session && NoteFileSession.session(for: url) == nil, "the registry follows")
        expectEqual(session.environment.documentURL, renamed, "the environment follows")

        file("Taken.md", "Other\n")
        expectThrows(NoteFileError.nameTaken("Taken"), "collisions are refused") { _ = try session.rename(to: "Taken") }
        expectEqual(session.url, renamed, "a refused rename changes nothing")

        let cased = try session.rename(to: "plans-ideas- 2027")
        expectEqual(cased.lastPathComponent, "plans-ideas- 2027.md", "case-only renames work")
        let listing = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        expect(listing.contains("plans-ideas- 2027.md"), "the new case is on disk")

        let dotted = try session.rename(to: "...secret")
        expectEqual(dotted.lastPathComponent, "secret.md", "renames can't hide the file")
        file("Untitled.md", "")
        let untitled = try session.rename(to: "   ")
        expectEqual(untitled.lastPathComponent, "Untitled 2.md", "an empty title becomes a fresh Untitled")
        expectEqual(try session.rename(to: ""), untitled, "an untitled note stays put when cleared again")
        let long = try session.rename(to: String(repeating: "长", count: 200))
        expect(long.lastPathComponent.utf8.count <= 255 && NoteFilePaths.itemExists(long), "long titles are truncated to fit")
        setText(session, "Saved after renames")
        try session.flush()
        expect(NoteFileTestSupport.read(long).contains("Saved after renames"), "saving goes to the renamed file")
        expect(!NoteFilePaths.itemExists(untitled), "the old name isn't recreated")
        watch.cancel()
    }

    static func outsideEditWithoutLocalChanges() throws {
        let url = file("outside.txt", "one\ntwo\nthree\n")
        let session = try NoteFileSession.open(url)
        let two = session.page.page.blocks[1].id
        session.page.setSelection(.caret(NotePosition(two, 2)))
        NoteFileTestSupport.write("zero\none\ntwo\nthree\n", to: url)
        let before = NoteFileTestSupport.modified(url)
        session.checkDisk()
        expectEqual(texts(session), ["zero", "one", "two", "three"], "outside edits reload")
        expectEqual(session.page.selection, .caret(NotePosition(two, 2)), "the caret stays near where it was")
        expectEqual(session.state, .saved, "a reload is saved")
        clock.advance(10)
        expectEqual(NoteFileTestSupport.modified(url), before, "a reload doesn't write back")
        expect(!session.page.canUndo, "a clean reload starts a fresh history")
        session.checkDisk()
        expectEqual(texts(session), ["zero", "one", "two", "three"], "checking an unchanged file changes nothing")
    }

    static func outsideEditWithLocalChanges() throws {
        let url = file("conflict.txt", "base\n")
        let session = try NoteFileSession.open(url)
        setText(session, "mine")
        NoteFileTestSupport.write("theirs\n", to: url)
        session.checkDisk()
        expectEqual(session.state, .conflict, "local and outside edits conflict")
        expectEqual(session.conflictingText, "theirs", "their text is available")
        expectEqual(texts(session), ["mine"], "my text stays on screen")
        clock.advance(30)
        expectEqual(NoteFileTestSupport.read(url), "theirs\n", "autosave never overwrites during a conflict")
        expectThrows(NoteFileError.conflict, "flush refuses to pick a side") { try session.flush() }
        setText(session, "mine, still typing")
        clock.advance(30)
        expectEqual(NoteFileTestSupport.read(url), "theirs\n", "typing during a conflict doesn't overwrite either")
        session.resolveConflict(keepMine: true)
        expectEqual(NoteFileTestSupport.read(url), "mine, still typing\n", "keeping mine overwrites")
        expectEqual(session.state, .saved, "resolved and saved")

        setText(session, "mine again")
        NoteFileTestSupport.write("theirs again\n", to: url)
        session.checkDisk()
        expectEqual(session.state, .conflict, "a second conflict")
        session.resolveConflict(keepMine: false)
        expectEqual(texts(session), ["theirs again"], "taking theirs reloads")
        expectEqual(session.state, .saved, "taking theirs is saved")
        expectEqual(NoteFileTestSupport.read(url), "theirs again\n", "taking theirs leaves the file alone")
        session.page.undo()
        expectEqual(texts(session), ["mine again"], "undo brings my version back")
        clock.advance(1)
        expectEqual(NoteFileTestSupport.read(url), "mine again\n", "and saves it like any edit")

        setText(session, "converged")
        NoteFileTestSupport.write("converged\n", to: url)
        session.checkDisk()
        expectEqual(session.state, .saved, "identical outside text isn't a conflict")
    }

    static func saveNoticesUnseenOutsideEdits() throws {
        let url = file("race.txt", "start\n")
        let session = try NoteFileSession.open(url)
        setText(session, "local")
        NoteFileTestSupport.write("sneaky\n", to: url)
        clock.advance(1)
        expectEqual(NoteFileTestSupport.read(url), "sneaky\n", "saving won't clobber an edit it hadn't seen yet")
        expectEqual(session.state, .conflict, "it becomes a conflict instead")
        session.resolveConflict(keepMine: false)
        expectEqual(texts(session), ["sneaky"], "and can be resolved")
    }

    static func deletionAndRecreation() throws {
        let url = file("doomed.txt", "keep me\n")
        let session = try NoteFileSession.open(url)
        try FileManager.default.removeItem(at: url)
        session.checkDisk()
        expectEqual(session.state, .missing, "deletion is noticed")
        expectEqual(texts(session), ["keep me"], "the text stays in memory")
        try session.flush()
        clock.advance(5)
        expect(!NoteFilePaths.itemExists(url), "an untouched missing note isn't recreated")
        setText(session, "brought back")
        clock.advance(1)
        expectEqual(NoteFileTestSupport.read(url), "brought back\n", "editing recreates the file")
        expectEqual(session.state, .saved, "and it's saved again")

        try FileManager.default.removeItem(at: url)
        session.checkDisk()
        NoteFileTestSupport.write("reborn elsewhere\n", to: url)
        session.checkDisk()
        expectEqual(texts(session), ["reborn elsewhere"], "a file that reappears is picked up")
        expectEqual(session.state, .saved, "and is saved")
    }

    static func movesAndTrash() throws {
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
        expectEqual(session.url, destination, "an outside move is followed")
        expectEqual(moves, [destination], "listeners hear about outside moves")
        expect(NoteFileSession.session(for: destination) === session, "the registry follows outside moves")

        let renamed = sub.appendingPathComponent("Renamed in Finder.md")
        try FileManager.default.moveItem(at: destination, to: renamed)
        session.handle(.moved(renamed))
        expectEqual(session.title, "Renamed in Finder", "presenter moves rename the note")

        let trash = folder.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let trashed = trash.appendingPathComponent("Renamed in Finder.md")
        try FileManager.default.moveItem(at: renamed, to: trashed)
        session.handle(.moved(trashed))
        expectEqual(session.state, .missing, "moving to the Trash counts as deletion")
        expectEqual(session.url, renamed, "the note doesn't follow into the Trash")
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
        expectEqual(NoteFileTestSupport.read(trash.appendingPathComponent("Trash me.md")), "last words\n", "trashing saves the latest text first")
        expectEqual(open.state, .missing, "the open note knows it's gone")
        clock.advance(5)
        expect(!NoteFilePaths.itemExists(doomed), "a trashed note isn't recreated")
    }

    static func retainAndRelease() throws {
        let a = try NoteFileSession.open(file("a.txt", "a\n"))
        let b = try NoteFileSession.open(file("b.txt", "b\n"))
        a.retain()
        a.retain()
        setText(a, "a2")
        setText(b, "b2")
        try NoteFileSession.flushAll()
        expectEqual(NoteFileTestSupport.read(a.url), "a2\n", "flushAll saves every session")
        expectEqual(NoteFileTestSupport.read(b.url), "b2\n", "flushAll saves every session")
        setText(a, "a3")
        a.release()
        expect(NoteFileSession.session(for: a.url) === a, "one editor still holds it")
        a.release()
        expectEqual(NoteFileTestSupport.read(a.url), "a3\n", "the last release flushes")
        expect(NoteFileSession.session(for: a.url) == nil, "and drops the session")
        let reopened = try NoteFileSession.open(a.url)
        expect(reopened !== a, "reopening makes a fresh session")
        expectEqual(texts(reopened), ["a3"], "with the saved text")

        let stuck = try NoteFileSession.open(file("stuck.txt", "x\n"))
        stuck.retain()
        setText(stuck, "mine")
        NoteFileTestSupport.write("theirs\n", to: stuck.url)
        stuck.checkDisk()
        stuck.release()
        expect(NoteFileSession.session(for: stuck.url) === stuck, "a conflicted session stays alive rather than lose text")
        stuck.resolveConflict(keepMine: true)
    }

    static func markdownCopy() throws {
        let url = file("Turn me.txt", "Line one\nLine two\n")
        file("Turn me.md", "existing")
        let session = try NoteFileSession.open(url)
        let copy = try session.saveMarkdownCopy()
        expectEqual(copy.lastPathComponent, "Turn me 2.md", "the copy gets a fresh name")
        expect(NoteFileTestSupport.read(copy).contains("Line one") && NoteFileTestSupport.read(copy).hasSuffix("\n"), "the copy holds the text")
        expectEqual(NoteFileTestSupport.read(url), "Line one\nLine two\n", "the text file is untouched")
    }

    static func liveWatcher() throws {
        let url = file("watched.txt", "before\n")
        let session = try NoteFileSession.open(url)
        session.retain()
        DispatchQueue.global().async {
            var error: NSError?
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &error) { target in
                try? Data("after\n".utf8).write(to: target, options: .atomic)
            }
        }
        let noticed = NoteFileTestSupport.spin(timeout: 10) {
            clock.advance(1)
            return texts(session) == ["after"]
        }
        expect(noticed, "a real outside edit is noticed and reloaded")
        NoteFileTestSupport.write("plain write\n", to: url)
        let rearmed = NoteFileTestSupport.spin(timeout: 10) {
            clock.advance(1)
            return texts(session) == ["plain write"]
        }
        expect(rearmed, "the watcher re-arms after an atomic replace")
        setText(session, "typed")
        clock.advance(1)
        let quiet = NoteFileTestSupport.spin(timeout: 0.5) { false }
        clock.advance(1)
        expect(!quiet && texts(session) == ["typed"] && session.state == .saved, "my own saves don't bounce back as outside edits")
        try FileManager.default.removeItem(at: url)
        let gone = NoteFileTestSupport.spin(timeout: 10) {
            clock.advance(1)
            return session.state == .missing
        }
        expect(gone, "a real deletion is noticed, state \(session.state), file there: \(NoteFilePaths.itemExists(url))")
        NoteFileTestSupport.write("back again\n", to: url)
        let returned = NoteFileTestSupport.spin(timeout: 10) {
            clock.advance(1)
            return texts(session) == ["back again"] && session.state == .saved
        }
        expect(returned, "a file recreated by someone else is picked up")
        session.release()
    }
}
