import Combine
import Foundation
import Testing
@testable import ParcCore

struct NoteDefaultFolderTests {
    @Test func theDefaultFolderIsParcNotesInsideDocuments() {
        let folder = NoteLibrary.defaultFolder
        #expect(folder.lastPathComponent == "Parc Notes")
        #expect(folder.deletingLastPathComponent().lastPathComponent == "Documents")
    }
}

@MainActor final class NoteFileLibraryTests {
    let clock = NoteManualClock()
    let folder = NoteFileTestSupport.makeFolder("library")
    lazy var files = NoteFileTestSupport.files(clock: clock)

    deinit {
        NoteFileTestSupport.remove(folder)
    }

    final class HeardCount {
        var value = 0
    }

    func fresh() -> (URL, NoteLibrary) {
        let root = folder.appendingPathComponent("Fresh", isDirectory: true)
        return (root, files.library(folder: root))
    }

    func titles(_ library: NoteLibrary) -> [String] { ((try? library.notes()) ?? []).map(\.title) }

    @Test func everyPathToAFolderSharesOneLibrary() {
        let (root, library) = fresh()
        #expect(files.library(folder: URL(fileURLWithPath: root.path.replacingOccurrences(of: "/private/var/", with: "/var/"))) === library)
    }

    @Test func eachFileEnvironmentKeepsItsOwnLibraries() {
        let (root, library) = fresh()
        #expect(NoteFileTestSupport.files(clock: clock).library(folder: root) !== library)
    }

    @Test func aMissingFolderListsNothing() throws {
        #expect(try fresh().1.notes() == [])
    }

    @Test func theFirstNoteIsAnEmptyUntitledInANewFolder() throws {
        let (root, library) = fresh()
        let first = try library.createNote()
        #expect(first.lastPathComponent == "Untitled.md")
        #expect(NoteFilePaths.isDirectory(root))
        #expect(NoteFileTestSupport.bytes(first) == [])
    }

    @Test(arguments: [(nil, ["Untitled.md", "Untitled 2.md"]), ("", ["Untitled.md", "Untitled 2.md"]),
                      ("Ideas/Plans", ["Ideas-Plans.md", "Ideas-Plans 2.md"])] as [(String?, [String])])
    func newNoteNamesAreTidiedAndCountUp(title: String?, expected: [String]) throws {
        let library = fresh().1
        let made = try (0..<2).map { _ in try library.createNote(title: title).lastPathComponent }
        #expect(made == expected)
    }

    @Test func creatingANoteAnnouncesAChange() throws {
        let library = fresh().1
        let heard = HeardCount()
        let watch = library.changes.sink { heard.value += 1 }
        defer { watch.cancel() }
        _ = try library.createNote()
        #expect(heard.value > 0)
    }

    @Test func newNotesAreListedRightAway() throws {
        let library = fresh().1
        _ = try library.notes()
        _ = try library.createNote()
        _ = try library.createNote(title: "Plans")
        #expect(try library.notes().count == 2)
    }

    @Test func aNewMarkdownNoteGetsTheEnvironmentsCover() throws {
        files.newNoteCover = { NoteNewCover(data: Data([1, 2, 3]), fileExtension: "png", suggestedName: "Cover") }
        let made = try fresh().1.createNote()
        #expect(NoteFileTestSupport.read(made).contains("Attachments/Cover.png"))
    }

    func listing() throws -> (URL, NoteLibrary) {
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
        return (root, files.library(folder: root))
    }

    @Test func notesAreListedNewestFirstSkippingHiddenAttachmentAndPackageFolders() throws {
        #expect(try listing().1.notes().map(\.title) == ["Nested", "Rocket", "Plain"])
    }

    @Test func iconsComeFromFrontMatter() throws {
        #expect(try listing().1.notes()[1].icon == "🚀")
    }

    @Test func snippetsArePlainText() throws {
        let notes = try listing().1.notes()
        #expect(notes[1].snippet == "Launch Count down from ten.")
        #expect(notes[2].snippet == "Just words and more words")
    }

    @Test func nestedNotesCarryTheirFullURLAndDate() throws {
        let (root, library) = try listing()
        let nested = try library.notes()[0]
        #expect(nested.url == root.appendingPathComponent("Projects/Deep/Nested.markdown"))
        #expect(nested.modifiedAt == Date(timeIntervalSince1970: 1_700_000_000 - 5))
    }

    @Test func snippetsCanBeFetchedPerNoteInsideOrOutsideTheListing() throws {
        let (root, library) = try listing()
        _ = try library.notes()
        let outside = NoteFileTestSupport.write("# Elsewhere\nhello", to: folder.appendingPathComponent("Outside.md"))
        #expect(library.snippet(for: root.appendingPathComponent("Plain.txt")) == "Just words and more words")
        #expect(library.snippet(for: outside) == "Elsewhere hello")
    }

    func searchable() -> (URL, NoteLibrary) {
        let root = folder.appendingPathComponent("Search", isDirectory: true)
        let notes: [(String, String, TimeInterval)] = [
            ("Garden.md", "tomatoes and basil\n", 50), ("Garden planning.md", "seeds\n", 40), ("Kitchen garden.md", "herbs\n", 30),
            ("Café menu.md", "croissant\n", 20), ("Groceries.md", "remember the garden hose and basil\n", 10), ("Notes on gardening.md", "soil\n", 60),
        ]
        for (name, text, age) in notes {
            let url = NoteFileTestSupport.write(text, to: root.appendingPathComponent(name))
            NoteFileTestSupport.setModified(url, Date(timeIntervalSince1970: 1_700_000_000 - age))
        }
        return (root, files.library(folder: root))
    }

    @Test(arguments: [
        ("garden", 10, ["Garden", "Garden planning", "Kitchen garden", "Notes on gardening", "Groceries"]),
        ("GARDEN", 2, ["Garden", "Garden planning"]),
        ("cafe", 10, ["Café menu"]),
        ("basil hose", 10, ["Groceries"]),
        ("garden basil", 10, ["Garden", "Groceries"]),
        ("", 3, ["Groceries", "Café menu", "Kitchen garden"]),
        ("zucchini", 10, []),
        ("garden", 0, []),
    ])
    func searchRanksExactThenPrefixThenWordThenBody(query: String, limit: Int, expected: [String]) {
        #expect(searchable().1.search(query, limit: limit).map(\.title) == expected)
    }

    @Test func editedContentsAreReindexedAndOldContentsForgotten() {
        let (root, library) = searchable()
        _ = library.search("garden", limit: 10)
        NoteFileTestSupport.write("zucchini only\n", to: root.appendingPathComponent("Groceries.md"))
        library.refresh()
        clock.advance(1)
        #expect(library.search("zucchini", limit: 10).map(\.title) == ["Groceries"])
        #expect(library.search("hose", limit: 10) == [])
    }

    func contained() -> (URL, NoteLibrary) {
        let root = folder.appendingPathComponent("Contain", isDirectory: true)
        return (root, files.library(folder: root))
    }

    @Test(arguments: [("a.md", true), ("x/y/z.md", true)])
    func notesUnderTheFolderAreInside(path: String, inside: Bool) {
        let (root, library) = contained()
        #expect(library.contains(root.appendingPathComponent(path)) == inside)
    }

    @Test func theFolderItselfIsNotInside() {
        let (root, library) = contained()
        #expect(!library.contains(root))
    }

    @Test func neighboursWithASharedPrefixAreNotInside() {
        #expect(!contained().1.contains(folder.appendingPathComponent("ContainMore/a.md")))
    }

    @Test func webURLsAreNotInside() {
        #expect(!contained().1.contains(URL(string: "https://example.com/a.md")!))
    }

    @Test func theDeepestLibraryWins() {
        let (root, library) = contained()
        let nested = files.library(folder: root.appendingPathComponent("x", isDirectory: true))
        #expect(files.library(for: root.appendingPathComponent("x/y/z.md")) === nested)
        #expect(files.library(for: root.appendingPathComponent("b.md")) === library)
    }

    @Test func notesOutsideLibrariesShareAShallowFolderLibrary() {
        let loose = files.library(for: folder.appendingPathComponent("Loose/note.md"))
        #expect(!loose.isRecursive && loose.folder.lastPathComponent == "Loose")
        #expect(files.library(for: folder.appendingPathComponent("Loose/other.md")) === loose)
        #expect(!loose.contains(folder.appendingPathComponent("Loose/deeper/n.md")))
    }

    func renamable() throws -> (URL, NoteLibrary, URL) {
        let root = folder.appendingPathComponent("Rename", isDirectory: true)
        let library = files.library(folder: root)
        let note = try library.createNote(title: "Old name")
        _ = try library.createNote(title: "Taken")
        return (root, library, note)
    }

    @Test func renamingWithoutASessionSanitizesAndMovesTheFile() throws {
        let (_, _, note) = try renamable()
        let renamed = try files.rename(note, to: "New: name")
        #expect(renamed.lastPathComponent == "New- name.md")
        #expect(NoteFilePaths.itemExists(renamed) && !NoteFilePaths.itemExists(note))
    }

    @Test func renamingOntoATakenNameIsRefused() throws {
        let (_, _, note) = try renamable()
        #expect(throws: NoteFileError.nameTaken("Taken")) { _ = try self.files.rename(note, to: "Taken") }
    }

    @Test func renamingToTheSameNameIsANoOp() throws {
        let (_, _, note) = try renamable()
        #expect(try files.rename(note, to: "Old name") == note)
    }

    @Test func theListingFollowsARename() throws {
        let (_, library, note) = try renamable()
        _ = try files.rename(note, to: "New: name")
        #expect(try library.notes().map(\.title).sorted() == ["New- name", "Taken"])
    }

    @Test func renamesRouteThroughAnOpenSession() throws {
        let (_, _, note) = try renamable()
        let session = try files.open(note)
        var moves: [URL] = []
        let watch = session.urlChanges.sink { moves.append($0) }
        defer { watch.cancel() }
        let renamed = try files.rename(note, to: "Through the session")
        #expect(session.url == renamed)
        #expect(moves == [renamed])
    }

    @Test func missingNotesCannotBeRenamed() throws {
        let (root, _, _) = try renamable()
        #expect(throws: NoteFileError.missing) { _ = try self.files.rename(root.appendingPathComponent("Ghost.md"), to: "Boo") }
    }

    struct Watched {
        let root: URL
        let library: NoteLibrary
        let heard: HeardCount
        let watch: AnyCancellable
    }

    func watchedLibrary() throws -> Watched {
        let root = folder.appendingPathComponent("Watched", isDirectory: true)
        let library = files.library(folder: root)
        _ = try library.createNote(title: "Existing")
        _ = try library.notes()
        let heard = HeardCount()
        let watch = library.changes.sink { heard.value += 1 }
        return Watched(root: root, library: library, heard: heard, watch: watch)
    }

    func folderChanged(_ watched: Watched) {
        watched.library.refresh()
        clock.advance(0.5)
    }

    @Test func filesMadeOutsideParcAreNoticed() throws {
        let watched = try watchedLibrary()
        NoteFileTestSupport.write("made in Finder\n", to: watched.root.appendingPathComponent("Outside.md"))
        folderChanged(watched)
        #expect(titles(watched.library).contains("Outside"))
        #expect(watched.heard.value > 0)
    }

    @Test func outsideRenamesAreNoticed() throws {
        let watched = try watchedLibrary()
        NoteFileTestSupport.write("made in Finder\n", to: watched.root.appendingPathComponent("Outside.md"))
        folderChanged(watched)
        watched.heard.value = 0
        try FileManager.default.moveItem(at: watched.root.appendingPathComponent("Outside.md"), to: watched.root.appendingPathComponent("Moved.md"))
        folderChanged(watched)
        #expect(titles(watched.library).contains("Moved"))
        #expect(!titles(watched.library).contains("Outside"))
        #expect(watched.heard.value > 0)
    }

    @Test func outsideDeletionsAreNoticed() throws {
        let watched = try watchedLibrary()
        NoteFileTestSupport.write("made in Finder\n", to: watched.root.appendingPathComponent("Outside.md"))
        folderChanged(watched)
        try FileManager.default.removeItem(at: watched.root.appendingPathComponent("Outside.md"))
        folderChanged(watched)
        #expect(titles(watched.library) == ["Existing"])
    }

    @Test func outsideEditsAreReindexedForSearch() throws {
        let watched = try watchedLibrary()
        NoteFileTestSupport.write("now mentions pineapples\n", to: watched.root.appendingPathComponent("Existing.md"))
        folderChanged(watched)
        #expect(watched.library.search("pineapples", limit: 5).map(\.title) == ["Existing"])
    }

    func quarterPlan(_ watched: Watched) -> URL {
        let quarter = watched.root.appendingPathComponent("Q3.2026", isDirectory: true)
        NoteFileTestSupport.write("quarterly plans\n", to: quarter.appendingPathComponent("Plan.md"))
        folderChanged(watched)
        return quarter
    }

    func planFolder(_ library: NoteLibrary) -> String? {
        (try? library.notes())?.first { $0.title == "Plan" }?.url.deletingLastPathComponent().lastPathComponent
    }

    @Test func notesInAFolderWithADotInItsNameAreListed() throws {
        let watched = try watchedLibrary()
        _ = quarterPlan(watched)
        #expect(planFolder(watched.library) == "Q3.2026")
    }

    @Test func renamingThatFolderIsNoticedDotAndAll() throws {
        let watched = try watchedLibrary()
        let quarter = quarterPlan(watched)
        try FileManager.default.moveItem(at: quarter, to: watched.root.appendingPathComponent("Q4.2026", isDirectory: true))
        folderChanged(watched)
        #expect(planFolder(watched.library) == "Q4.2026")
    }

    @Test func trashingTheFolderIsNoticedToo() throws {
        let watched = try watchedLibrary()
        let quarter = quarterPlan(watched)
        let trash = folder.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: quarter, to: trash.appendingPathComponent("Q3.2026", isDirectory: true))
        folderChanged(watched)
        #expect(planFolder(watched.library) == nil)
    }

    struct Refreshing {
        let root: URL
        let jobs: NoteFileDeferredJobs
        let files: NoteFiles
        let library: NoteLibrary
    }

    func refreshingLibrary(trash bin: URL? = nil) -> Refreshing {
        let root = folder.appendingPathComponent("Busy", isDirectory: true)
        NoteFileTestSupport.write("first body\n", to: root.appendingPathComponent("First.md"))
        NoteFileTestSupport.write("tucked away\n", to: root.appendingPathComponent("Drawer/Nested.md"))
        let jobs = NoteFileDeferredJobs()
        let files = NoteFileTestSupport.files(clock: clock, worker: NoteFileWorker(deferred: jobs), trashMover: { url in
            guard let bin else { throw NoteRealTrashRefused() }
            let target = bin.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        })
        return Refreshing(root: root, jobs: jobs, files: files, library: files.library(folder: root))
    }

    @Test func aNeverListedFolderNamesItsTopLevelNotesStraightAway() throws {
        let first = try refreshingLibrary().library.notes()
        #expect(first.map(\.title) == ["First"])
        #expect(first.first?.snippet == "")
    }

    @Test func aRefreshInFlightLeavesTheLastListingInPlace() throws {
        let busy = refreshingLibrary()
        _ = try busy.library.notes()
        NoteFileTestSupport.write("second body\n", to: busy.root.appendingPathComponent("Second.md"))
        busy.library.refresh()
        clock.advance(1)
        #expect(try busy.library.notes().map(\.title) == ["First"])
        #expect(busy.library.search("second", limit: 5) == [])
    }

    @Test func aNoteParcMakesShowsUpAtOnce() throws {
        let busy = refreshingLibrary()
        _ = try busy.library.notes()
        _ = try busy.library.createNote(title: "Made meanwhile")
        #expect(try busy.library.notes().map(\.title).sorted() == ["First", "Made meanwhile"])
    }

    func settled(_ busy: Refreshing) throws -> (HeardCount, AnyCancellable, URL) {
        _ = try busy.library.notes()
        NoteFileTestSupport.write("second body\n", to: busy.root.appendingPathComponent("Second.md"))
        busy.library.refresh()
        clock.advance(1)
        let made = try busy.library.createNote(title: "Made meanwhile")
        let heard = HeardCount()
        let watch = busy.library.changes.sink { heard.value += 1 }
        busy.jobs.runAll()
        return (heard, watch, made)
    }

    @Test func theFullListingAndSummariesArriveFromTheWorkerAndAnnounceThemselves() throws {
        let busy = refreshingLibrary()
        let (heard, watch, _) = try settled(busy)
        defer { watch.cancel() }
        let notes = try busy.library.notes()
        #expect(notes.map(\.title).sorted() == ["First", "Made meanwhile", "Nested", "Second"])
        #expect(notes.first { $0.title == "First" }?.snippet == "first body")
        #expect(heard.value > 0)
    }

    @Test func searchCatchesUpOnceTheWorkerHasReadTheNewNote() throws {
        let busy = refreshingLibrary()
        let (_, watch, _) = try settled(busy)
        defer { watch.cancel() }
        #expect(busy.library.search("second body", limit: 5) == [])
        busy.jobs.runAll()
        #expect(busy.library.search("second body", limit: 5).map(\.title) == ["Second"])
    }

    @Test func aNoteParcTrashesLeavesAtOnce() throws {
        let bin = folder.appendingPathComponent("Bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let busy = refreshingLibrary(trash: bin)
        let (_, watch, made) = try settled(busy)
        defer { watch.cancel() }
        try busy.files.trash(made)
        #expect(try busy.library.notes().allSatisfy { $0.title != "Made meanwhile" })
        #expect(NoteFilePaths.itemExists(bin.appendingPathComponent("Made meanwhile.md")))
    }
}
