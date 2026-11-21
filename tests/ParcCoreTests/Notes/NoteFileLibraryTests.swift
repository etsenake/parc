import Combine
import Foundation
import Testing
@testable import ParcCore

extension NoteProcessWide {
@MainActor final class NoteFileLibraryTests {
    init() {
        NoteFileSession.clock = clock
        NoteFileSession.worker = .inline
        NoteLibrary.clock = clock
        NoteLibrary.worker = .inline
        folder = NoteFileTestSupport.makeFolder("library")
        #expect(NoteLibrary.defaultFolder.lastPathComponent == "Parc Notes", "the default folder is Parc Notes")
        #expect(NoteLibrary.defaultFolder.deletingLastPathComponent().lastPathComponent == "Documents", "inside Documents")
    }

    deinit {
        NoteFileTestSupport.remove(folder)
    }

    let clock = NoteManualClock()

    var folder: URL!

    @Test func oneLibraryPerFolder() throws {
        let root = folder.appendingPathComponent("Fresh", isDirectory: true)
        let library = NoteLibrary.shared(folder: root)
        #expect(NoteLibrary.shared(folder: URL(fileURLWithPath: root.path.replacingOccurrences(of: "/private/var/", with: "/var/"))) === library, "one library per folder")
        #expect((try library.notes()) == [], "a missing folder lists nothing")
        var heard = 0
        let watch = library.changes.sink { heard += 1 }
        let first = try library.createNote()
        #expect(first.lastPathComponent == "Untitled.md", "the first note is Untitled")
        #expect(NoteFilePaths.isDirectory(root), "creating a note creates the folder")
        #expect(NoteFileTestSupport.bytes(first) == [], "new notes are empty")
        #expect((try library.createNote().lastPathComponent) == "Untitled 2.md", "the next one counts up")
        #expect((try library.createNote(title: "").lastPathComponent) == "Untitled 3.md", "empty titles are untitled")
        #expect((try library.createNote(title: "Ideas/Plans").lastPathComponent) == "Ideas-Plans.md", "titles are sanitized")
        #expect((try library.createNote(title: "Ideas/Plans").lastPathComponent) == "Ideas-Plans 2.md", "taken titles count up")
        #expect(heard >= 5, "creating notes announces changes")
        #expect((try library.notes().count) == 5, "new notes are listed right away")
        watch.cancel()
    }

    @Test func notesAreListedNewestFirstSkippingHiddenAttachment() throws {
        let root = folder.appendingPathComponent("Listing", isDirectory: true)
        func note(_ path: String, _ text: String, age: TimeInterval) {
            let url = NoteFileTestSupport.write(text, to: root.appendingPathComponent(path))
            NoteFileTestSupport.setModified(url, Date(timeIntervalSince1970: 1_700_000_000 - age))
        }
        note("Rocket.md", "---\nicon: \"🚀\"\n---\n# Launch\nCount **down** from ten.\n", age: 10)
        note("Plain.txt", "Just words\nand more words\n", age: 20)
        note("Projects/Deep/Nested.markdown", "nested body\n", age: 5)
        note("Attachments/Skipped.md", "attachment folder\n", age: 0)
        note(".hidden/Secret.md", "hidden folder\n", age: 0)
        note(".dotfile.md", "hidden file\n", age: 0)
        note("Bundle.textbundle/text.md", "package\n", age: 0)
        note("image.png", "not a note", age: 0)
        note("node_modules/pkg/README.md", "dependency\n", age: 0)
        let library = NoteLibrary.shared(folder: root)
        let notes = try library.notes()
        #expect(notes.map(\.title) == ["Nested", "Rocket", "Plain"], "notes are listed newest first, skipping hidden, attachment and package folders")
        #expect(notes[1].icon == "🚀", "icons come from front matter")
        #expect(notes[1].snippet == "Launch Count down from ten.", "snippets are plain text")
        #expect(notes[2].snippet == "Just words and more words", "text snippets keep the words")
        #expect(notes[0].url == root.appendingPathComponent("Projects/Deep/Nested.markdown"), "nested notes carry their full URL")
        #expect(notes[0].modifiedAt == Date(timeIntervalSince1970: 1_700_000_000 - 5), "modified dates are reported")
        #expect(library.snippet(for: root.appendingPathComponent("Plain.txt")) == "Just words and more words", "snippets can be fetched per note")
        let outside = NoteFileTestSupport.write("# Elsewhere\nhello", to: folder.appendingPathComponent("Outside.md"))
        #expect(library.snippet(for: outside) == "Elsewhere hello", "snippets work for notes outside the listing too")
    }

    @Test func exactPrefixWordThenBodyMatches() throws {
        let root = folder.appendingPathComponent("Search", isDirectory: true)
        func note(_ name: String, _ text: String, age: TimeInterval) {
            let url = NoteFileTestSupport.write(text, to: root.appendingPathComponent(name))
            NoteFileTestSupport.setModified(url, Date(timeIntervalSince1970: 1_700_000_000 - age))
        }
        note("Garden.md", "tomatoes and basil\n", age: 50)
        note("Garden planning.md", "seeds\n", age: 40)
        note("Kitchen garden.md", "herbs\n", age: 30)
        note("Café menu.md", "croissant\n", age: 20)
        note("Groceries.md", "remember the garden hose and basil\n", age: 10)
        note("Notes on gardening.md", "soil\n", age: 60)
        let library = NoteLibrary.shared(folder: root)
        #expect(library.search("garden", limit: 10).map(\.title) == ["Garden", "Garden planning", "Kitchen garden", "Notes on gardening", "Groceries"], "exact, prefix, word, then body matches")
        #expect(library.search("GARDEN", limit: 2).map(\.title) == ["Garden", "Garden planning"], "case doesn't matter and limits apply")
        #expect(library.search("cafe", limit: 10).map(\.title) == ["Café menu"], "accents don't matter")
        #expect(library.search("basil hose", limit: 10).map(\.title) == ["Groceries"], "every word has to match somewhere")
        #expect(library.search("garden basil", limit: 10).map(\.title) == ["Garden", "Groceries"], "words can split across title and body")
        #expect(library.search("", limit: 3).map(\.title) == ["Groceries", "Café menu", "Kitchen garden"], "an empty search shows the newest")
        #expect(library.search("zucchini", limit: 10) == [], "no match, no results")
        #expect(library.search("garden", limit: 0) == [], "a zero limit finds nothing")

        note("Groceries.md", "zucchini only\n", age: 5)
        library.refresh()
        clock.advance(1)
        #expect(library.search("zucchini", limit: 10).map(\.title) == ["Groceries"], "edited contents are re-indexed")
        #expect(library.search("hose", limit: 10) == [], "old contents are forgotten")
    }

    @Test func directChildrenAreInside() throws {
        let root = folder.appendingPathComponent("Contain", isDirectory: true)
        let library = NoteLibrary.shared(folder: root)
        #expect(library.contains(root.appendingPathComponent("a.md")), "direct children are inside")
        #expect(library.contains(root.appendingPathComponent("x/y/z.md")), "nested notes are inside")
        #expect(!library.contains(root), "the folder itself isn't inside")
        #expect(!library.contains(folder.appendingPathComponent("ContainMore/a.md")), "neighbours with a shared prefix aren't inside")
        #expect(!library.contains(URL(string: "https://example.com/a.md")!), "web URLs aren't inside")
        let nested = NoteLibrary.shared(folder: root.appendingPathComponent("x", isDirectory: true))
        #expect(NoteLibrary.library(for: root.appendingPathComponent("x/y/z.md")) === nested, "the deepest library wins")
        #expect(NoteLibrary.library(for: root.appendingPathComponent("b.md")) === library, "otherwise the containing library")
        let loose = NoteLibrary.library(for: folder.appendingPathComponent("Loose/note.md"))
        #expect(!loose.isRecursive && loose.folder.lastPathComponent == "Loose", "notes outside libraries get a shallow folder library")
        #expect(NoteLibrary.library(for: folder.appendingPathComponent("Loose/other.md")) === loose, "shallow libraries are shared")
        #expect(!loose.contains(folder.appendingPathComponent("Loose/deeper/n.md")), "shallow libraries stay shallow")
    }

    @Test func renamingWithoutASessionSanitizesToo() throws {
        let root = folder.appendingPathComponent("Rename", isDirectory: true)
        let library = NoteLibrary.shared(folder: root)
        let note = try library.createNote(title: "Old name")
        _ = try library.createNote(title: "Taken")
        let renamed = try NoteLibrary.rename(note, to: "New: name")
        #expect(renamed.lastPathComponent == "New- name.md", "renaming without a session sanitizes too")
        #expect(NoteFilePaths.itemExists(renamed) && !NoteFilePaths.itemExists(note), "the file moved")
        #expect(throws: NoteFileError.nameTaken("Taken"), "collisions are refused") { _ = try NoteLibrary.rename(renamed, to: "Taken") }
        #expect((try NoteLibrary.rename(renamed, to: "New- name")) == renamed, "renaming to the same name is a no-op")
        #expect((try library.notes().map(\.title).sorted()) == ["New- name", "Taken"], "the listing follows")

        let session = try NoteFileSession.open(renamed)
        var moves: [URL] = []
        let watch = session.urlChanges.sink { moves.append($0) }
        let viaSession = try NoteLibrary.rename(renamed, to: "Through the session")
        #expect(session.url == viaSession, "renames route through an open session")
        #expect(moves == [viaSession], "so the editor hears about it")
        #expect(throws: NoteFileError.missing, "missing notes can't be renamed") {
            _ = try NoteLibrary.rename(root.appendingPathComponent("Ghost.md"), to: "Boo")
        }
        watch.cancel()
    }

    @Test func filesMadeOutsideParcAreNoticed() async throws {
        let root = folder.appendingPathComponent("Watched", isDirectory: true)
        let library = NoteLibrary.shared(folder: root)
        _ = try library.createNote(title: "Existing")
        _ = try library.notes()
        var heard = 0
        let watch = library.changes.sink { heard += 1 }
        NoteFileTestSupport.write("made in Finder\n", to: root.appendingPathComponent("Outside.md"))
        let created = await NoteFileTestSupport.spin(timeout: 10) {
            clock.advance(0.5)
            return (try? library.notes().map(\.title).contains("Outside")) == true && heard > 0
        }
        #expect(created, "files made outside Parc are noticed")
        heard = 0
        try FileManager.default.moveItem(at: root.appendingPathComponent("Outside.md"), to: root.appendingPathComponent("Moved.md"))
        let moved = await NoteFileTestSupport.spin(timeout: 10) {
            clock.advance(0.5)
            return (try? library.notes().map(\.title)).map { $0.contains("Moved") && !$0.contains("Outside") } == true
        }
        #expect(moved && heard > 0, "outside renames are noticed")
        try FileManager.default.removeItem(at: root.appendingPathComponent("Moved.md"))
        let removed = await NoteFileTestSupport.spin(timeout: 10) {
            clock.advance(0.5)
            return (try? library.notes().map(\.title)) == ["Existing"]
        }
        #expect(removed, "outside deletions are noticed")
        NoteFileTestSupport.write("now mentions pineapples\n", to: root.appendingPathComponent("Existing.md"))
        let indexed = await NoteFileTestSupport.spin(timeout: 10) {
            clock.advance(0.5)
            return library.search("pineapples", limit: 5).map(\.title) == ["Existing"]
        }
        #expect(indexed, "outside edits are re-indexed for search")

        let quarter = root.appendingPathComponent("Q3.2026", isDirectory: true)
        NoteFileTestSupport.write("quarterly plans\n", to: quarter.appendingPathComponent("Plan.md"))
        func planFolder() -> String? {
            (try? library.notes())?.first { $0.title == "Plan" }?.url.deletingLastPathComponent().lastPathComponent
        }
        let listed = await NoteFileTestSupport.spin(timeout: 10) {
            clock.advance(0.5)
            return planFolder() == "Q3.2026"
        }
        #expect(listed, "notes in a folder with a dot in its name are listed")
        try FileManager.default.moveItem(at: quarter, to: root.appendingPathComponent("Q4.2026", isDirectory: true))
        let renamed = await NoteFileTestSupport.spin(timeout: 10) {
            clock.advance(0.5)
            return planFolder() == "Q4.2026"
        }
        #expect(renamed, "renaming that folder is noticed, dot and all")
        let trash = folder.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: root.appendingPathComponent("Q4.2026", isDirectory: true),
                                         to: trash.appendingPathComponent("Q4.2026", isDirectory: true))
        let trashed = await NoteFileTestSupport.spin(timeout: 10) {
            clock.advance(0.5)
            return planFolder() == nil
        }
        #expect(trashed, "and so is trashing it")
        watch.cancel()
    }

    @Test func refreshingOffTheMainThread() async throws {
        let root = folder.appendingPathComponent("Busy", isDirectory: true)
        NoteFileTestSupport.write("first body\n", to: root.appendingPathComponent("First.md"))
        NoteFileTestSupport.write("tucked away\n", to: root.appendingPathComponent("Drawer/Nested.md"))
        let worker = NoteFileWorker(label: "org.parc.tests.library")
        NoteLibrary.worker = worker
        defer { NoteLibrary.worker = .inline }
        let gate = DispatchSemaphore(value: 0)
        worker.perform({ () -> Bool in
            gate.wait()
            return true
        }) { _ in }
        let library = NoteLibrary.shared(folder: root)
        let started = Date()
        let first = try library.notes()
        #expect(first.map(\.title) == ["First"], "a never-listed folder names its top-level notes straight away")
        #expect(first.first?.snippet == "", "while summaries wait for the worker")
        NoteFileTestSupport.write("second body\n", to: root.appendingPathComponent("Second.md"))
        library.refresh()
        clock.advance(1)
        #expect((try library.notes().map(\.title)) == ["First"], "a refresh in flight leaves the last listing in place")
        #expect(library.search("second", limit: 5) == [], "and search answers from it too")
        #expect(Date().timeIntervalSince(started) < 0.5, "without waiting on the disk")
        let made = try library.createNote(title: "Made meanwhile")
        #expect((try library.notes().map(\.title).sorted()) == ["First", "Made meanwhile"], "a note Parc makes shows up at once")
        var heard = 0
        let watch = library.changes.sink { heard += 1 }
        gate.signal()
        let refreshed = await NoteFileTestSupport.spin(timeout: 10) {
            let notes = (try? library.notes()) ?? []
            return notes.map(\.title).sorted() == ["First", "Made meanwhile", "Nested", "Second"]
                && notes.first { $0.title == "First" }?.snippet == "first body"
        }
        #expect(refreshed && heard > 0, "the full listing and summaries arrive from the worker and announce themselves")
        let found = await NoteFileTestSupport.spin(timeout: 10) { library.search("second body", limit: 5).map(\.title) == ["Second"] }
        #expect(found, "and search catches up once the worker has read the new note")
        let bin = folder.appendingPathComponent("Bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let previousMover = NoteFileIO.trashMover
        NoteFileIO.trashMover = { url in
            let target = bin.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
        defer { NoteFileIO.trashMover = previousMover }
        try NoteLibrary.trash(made)
        let remaining = try library.notes()
        #expect(remaining.allSatisfy { $0.title != "Made meanwhile" }, "a note Parc trashes leaves at once")
        watch.cancel()
    }
}
}
