import Combine
import Foundation
import Testing
@testable import ParcCore
@testable import ParcLibrary

@MainActor
struct DocumentsLibraryCatalogTests {
    static let root = "/Users/parc-sample/Documents/Parc Notes/"

    func note(_ title: String, _ day: Double, icon: String? = nil, snippet: String? = nil) -> NoteReference {
        var reference = NoteReference(url: URL(fileURLWithPath: Self.root + "\(title).md"), title: title,
                                      icon: icon, modifiedAt: Date(timeIntervalSince1970: day * 86_400))
        reference.snippet = snippet
        return reference
    }

    @MainActor struct Samples {
        let trip: NoteReference
        let groceries: NoteReference
        let journal: NoteReference
        let easel: EaselSummary
        let items: [DocumentsLibraryItem]
    }

    func samples() -> Samples {
        let trip = note("Trip to Lisbon", 5, icon: "🧳", snippet: "Pack the passport.\n\n  Book   the tram.")
        let groceries = note("Groceries", 9, icon: "Attachments/cart.png", snippet: "Pastéis de nata, coffee")
        let journal = note("Journal", 7, icon: "❤️", snippet: String(repeating: "word ", count: 80))
        let easel = EaselSummary(id: UUID(), title: "Moodboard", modifiedAt: Date(timeIntervalSince1970: 8 * 86_400), itemCount: 3)
        let blank = EaselSummary(id: UUID(), title: "  ", modifiedAt: Date(timeIntervalSince1970: 1), itemCount: 0)
        return Samples(trip: trip, groceries: groceries, journal: journal, easel: easel,
                       items: DocumentsLibraryCatalog.items(notes: [trip, groceries, journal], easels: [easel, blank]))
    }

    @Test func notesAndEaselsShareOneCatalog() {
        #expect(samples().items.count == 5)
    }

    @Test func aNoteKeepsItsFile() {
        let samples = samples()
        #expect(samples.items[0].noteURL == samples.trip.url)
        #expect(samples.items[0].isNote)
        #expect(samples.items[0].easelID == nil)
    }

    @Test func anEaselKeepsItsIdentity() {
        let samples = samples()
        #expect(samples.items[3].easelID == samples.easel.id)
        #expect(!samples.items[3].isNote)
    }

    @Test func anEmojiIconShowsOnTheCard() {
        #expect(samples().items[0].emoji == "🧳")
    }

    @Test func anImageIconDoesNotPoseAsAnEmoji() {
        #expect(samples().items[1].emoji == nil)
    }

    @Test func aTextStyleEmojiWithItsSelectorStillCounts() {
        #expect(samples().items[2].emoji == "❤️")
    }

    @Test(arguments: [("A", nil), ("1", nil), ("🇵🇹", "🇵🇹")] as [(String, String?)])
    func lettersAndDigitsAreNotIconsButFlagsAre(icon: String, expected: String?) {
        #expect(DocumentsLibraryCatalog.emoji(icon) == expected)
    }

    @Test func thePreviewIsOneTidyLine() {
        #expect(samples().items[0].preview == "Pack the passport. Book the tram.")
    }

    @Test func longPreviewsEndInAnEllipsis() {
        let preview = samples().items[2].preview
        #expect(preview.count == DocumentsLibraryCatalog.previewLimit)
        #expect(preview.hasSuffix("…"))
    }

    @Test func aBlankEaselTitleReadsUntitledEasel() {
        #expect(samples().items[4].title == "Untitled Easel")
    }

    @Test func eachCardKnowsWhatItIs() {
        let items = samples().items
        #expect(items[3].detail == "Easel · 3 objects")
        #expect(items[0].detail == "Note")
    }

    @Test func noSearchListsNewestFirst() {
        let all = DocumentsLibraryCatalog.visible(samples().items, query: "  ")
        #expect(all.map(\.title) == ["Groceries", "Moodboard", "Journal", "Trip to Lisbon", "Untitled Easel"])
    }

    @Test(arguments: [
        ("lisbon", ["Trip to Lisbon"]),
        ("PASTEIS", ["Groceries"]),
        ("passport tram", ["Trip to Lisbon"]),
        ("passport opera", []),
        ("easel", ["Untitled Easel", "Moodboard"]),
    ] as [(String, [String])])
    func aSearchMatchesTitlesAndPreviewsIgnoringCaseAndAccents(query: String, titles: [String]) {
        #expect(DocumentsLibraryCatalog.visible(samples().items, query: query).map(\.title) == titles)
    }

    @Test func bodyMatchesFromTheNoteSearchCount() {
        let found = DocumentsLibraryCatalog.visible(samples().items, query: "sardines",
                                                    noteMatches: [URL(fileURLWithPath: "/Users/parc-sample/Documents/./Parc Notes/Journal.md")])
        #expect(found.map(\.title) == ["Journal"])
    }

    @Test func titleMatchesComeBeforeBodyMatches() {
        let samples = samples()
        let ranked = DocumentsLibraryCatalog.visible(samples.items, query: "jour", noteMatches: [samples.groceries.url])
        #expect(ranked.map(\.title) == ["Journal", "Groceries"])
    }

    func reference(_ path: String) -> NoteReference {
        NoteReference(url: URL(fileURLWithPath: Self.root + path), title: (path as NSString).lastPathComponent, modifiedAt: Date())
    }

    var scopedNotes: [NoteReference] {
        ["Inbox.md", "Trips/Lisbon.md", "Trips/Food/Pastries.md", "Tripsy.md", "Work/Plan.md"].map(reference)
    }

    @Test func aFolderScopeKeepsTheNotesInsideItAndItsSubfoldersNotLookalikeNames() {
        let trips = URL(fileURLWithPath: Self.root + "Trips", isDirectory: true)
        #expect(DocumentsLibraryCatalog.scoped(scopedNotes, to: trips).map(\.title) == ["Lisbon.md", "Pastries.md"])
    }

    @Test func noScopeKeepsEveryNote() {
        #expect(DocumentsLibraryCatalog.scoped(scopedNotes, to: nil).count == scopedNotes.count)
    }

    @Test func aTrailingSlashMeansTheSameFolder() {
        #expect(DocumentsLibraryCatalog.scoped(scopedNotes, to: URL(fileURLWithPath: Self.root + "Trips/")).map(\.title) == ["Lisbon.md", "Pastries.md"])
    }

    @Test func anEmptyFolderSaysSo() {
        #expect(DocumentsLibraryCatalog.emptyMessage(query: "", scoped: true) == "No notes in this folder yet.")
    }

    @Test func aSearchInAFolderStillSaysNothingMatched() {
        #expect(DocumentsLibraryCatalog.emptyMessage(query: "x", scoped: true) == DocumentsLibraryCatalog.noMatchesText)
    }

    @Test func anEmptyLibrarySaysWhatLandsHere() {
        #expect(DocumentsLibraryCatalog.emptyMessage(query: "") == "Your local Easels and Notes will appear here.")
    }

    @Test func anEmptySearchSaysSo() {
        #expect(DocumentsLibraryCatalog.emptyMessage(query: "zzz") == "Nothing matches that. Try fewer words?")
    }

    @Test(arguments: [
        (-30.0, "Just now"), (20, "Just now"), (60, "1 minute ago"), (3 * 3_600, "3 hours ago"), (30 * 3_600, "Yesterday"),
        (3 * 86_400, "3 days ago"), (15 * 86_400, "2 weeks ago"), (70 * 86_400, "2 months ago"), (800 * 86_400, "2 years ago"),
    ] as [(TimeInterval, String)])
    func editedTimesReadInPlainWords(seconds: TimeInterval, text: String) {
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        #expect(DocumentsLibraryCatalog.edited(now.addingTimeInterval(-seconds), now: now) == text)
    }

    @Test func aStaleRenameSaysWhatHappened() {
        #expect(DocumentsLibraryRenameError.changed.localizedDescription == "This changed in another window. Give it another try.")
    }
}

@MainActor
final class DocumentsLibraryCatalogIndexTests {
    let jobs: NoteFileDeferredJobs
    let files: NoteFiles
    let folder: NoteEditorTemporaryFolder
    let library: NoteLibrary

    init() throws {
        let jobs = NoteFileDeferredJobs()
        self.jobs = jobs
        files = NoteEditorFiles.make(clock: NoteEditorManualClock(), worker: NoteFileWorker(deferred: jobs))
        folder = try NoteEditorTemporaryFolder("library-catalog")
        let filler = String(repeating: "Socks, chargers and a spare umbrella for the drizzle. ", count: 40)
        try folder.write("\(filler)\n\nDon't forget the sardine tin opener.\n", to: "Packing.md")
        library = files.library(folder: folder.url)
    }

    func inputs() -> DocumentsLibraryInputs? {
        try? DocumentsLibraryCatalog.inputs(library: library, easels: { [] }, pending: false, query: "  sardine ", searchLimit: 100)
    }

    func coldInputs() throws -> DocumentsLibraryInputs {
        _ = try library.notes()
        jobs.runAll()
        return try #require(inputs())
    }

    @Test func aReadableFolderGivesTheFirstSnapshotWithSummaries() throws {
        let before = try coldInputs()
        #expect(before.notes.first?.snippet?.hasPrefix("Socks, chargers") == true)
    }

    @Test func aColdIndexHasNoBodyMatchesYet() throws {
        let before = try coldInputs()
        #expect(before.query == "sardine")
        #expect(before.noteMatches.isEmpty)
        #expect(DocumentsLibraryCatalog.visible(before).isEmpty)
    }

    @Test func theIndexFinishingChangesTheInputsSoTheLibraryReloads() throws {
        let before = try coldInputs()
        jobs.runAll()
        #expect(try #require(inputs()) != before)
    }

    @Test func theBodyWordFindsItsNoteOnceTheIndexIsReady() throws {
        _ = try coldInputs()
        jobs.runAll()
        let after = try #require(inputs())
        #expect(DocumentsLibraryCatalog.visible(after).map(\.title) == ["Packing"])
    }

    @Test func aQuietChangeAfterTheIndexIsReadyIsSkipped() throws {
        _ = try coldInputs()
        jobs.runAll()
        let after = try #require(inputs())
        #expect(inputs() == after)
    }

    @Test func theIndexFinishingAnnouncesAChange() throws {
        _ = try coldInputs()
        var changed = false
        let watch = library.changes.sink { changed = true }
        defer { watch.cancel() }
        jobs.runAll()
        #expect(changed)
    }
}
