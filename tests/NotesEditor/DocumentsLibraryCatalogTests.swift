import Combine
import Foundation

@main @MainActor
struct DocumentsLibraryCatalogTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func note(_ title: String, _ day: Double, icon: String? = nil, snippet: String? = nil) -> NoteReference {
        var reference = NoteReference(url: URL(fileURLWithPath: "/Users/parc-sample/Documents/Parc Notes/\(title).md"), title: title,
                                      icon: icon, modifiedAt: Date(timeIntervalSince1970: day * 86_400))
        reference.snippet = snippet
        return reference
    }

    static func indexReadyChangesTheInputs() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("parc-library-catalog-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let filler = String(repeating: "Socks, chargers and a spare umbrella for the drizzle. ", count: 40)
        try? Data("\(filler)\n\nDon't forget the sardine tin opener.\n".utf8).write(to: folder.appendingPathComponent("Packing.md"))
        NoteLibrary.worker = NoteFileWorker(label: "org.parc.tests.library-catalog")
        let library = NoteLibrary.shared(folder: folder)
        let listed = Date().addingTimeInterval(10)
        while ((try? library.notes()) ?? []).first?.snippet?.isEmpty != false && Date() < listed {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        func inputs() -> DocumentsLibraryInputs? {
            try? DocumentsLibraryCatalog.inputs(library: library, easels: { [] }, pending: false, query: "  sardine ", searchLimit: 100)
        }
        guard let before = inputs() else { failTest("a readable folder gives catalog inputs") }
        expect(before.notes.first?.snippet?.hasPrefix("Socks, chargers") == true, "the first listing snapshot is in, summaries and all")
        expect(before.query == "sardine" && before.noteMatches.isEmpty, "a cold index has no body matches yet")
        expect(DocumentsLibraryCatalog.visible(before).isEmpty, "so the body word finds nothing at first")
        var changed = false
        let watch = library.changes.sink { changed = true }
        defer { watch.cancel() }
        var after = before
        let deadline = Date().addingTimeInterval(10)
        while after.noteMatches.isEmpty && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            guard changed else { continue }
            changed = false
            after = inputs() ?? before
        }
        expect(after != before, "the index finishing changes the inputs, so the Library reloads instead of skipping")
        expect(DocumentsLibraryCatalog.visible(after).map(\.title) == ["Packing"], "and the body word now finds its note")
        expect(inputs() == after, "a quiet change after that is skipped")
    }

    static func folderScopes() {
        let root = "/Users/parc-sample/Documents/Parc Notes/"
        func at(_ path: String) -> NoteReference {
            NoteReference(url: URL(fileURLWithPath: root + path), title: (path as NSString).lastPathComponent, modifiedAt: Date())
        }
        let notes = [at("Inbox.md"), at("Trips/Lisbon.md"), at("Trips/Food/Pastries.md"), at("Tripsy.md"), at("Work/Plan.md")]
        let trips = URL(fileURLWithPath: root + "Trips", isDirectory: true)
        expect(DocumentsLibraryCatalog.scoped(notes, to: trips).map(\.title) == ["Lisbon.md", "Pastries.md"],
               "a folder scope keeps the notes inside it and its subfolders, not lookalike names")
        expect(DocumentsLibraryCatalog.scoped(notes, to: nil).count == notes.count, "no scope keeps every note")
        expect(DocumentsLibraryCatalog.scoped(notes, to: URL(fileURLWithPath: root + "Trips/")).count == 2, "a trailing slash means the same folder")
        expect(DocumentsLibraryCatalog.emptyMessage(query: "", scoped: true) == "No notes in this folder yet.", "an empty folder says so")
        expect(DocumentsLibraryCatalog.emptyMessage(query: "x", scoped: true) == DocumentsLibraryCatalog.noMatchesText, "a search still says nothing matched")
    }

    static func main() {
        let trip = note("Trip to Lisbon", 5, icon: "🧳", snippet: "Pack the passport.\n\n  Book   the tram.")
        let groceries = note("Groceries", 9, icon: "Attachments/cart.png", snippet: "Pastéis de nata, coffee")
        let journal = note("Journal", 7, icon: "❤️", snippet: String(repeating: "word ", count: 80))
        let easel = EaselSummary(id: UUID(), title: "Moodboard", modifiedAt: Date(timeIntervalSince1970: 8 * 86_400), itemCount: 3)
        let blank = EaselSummary(id: UUID(), title: "  ", modifiedAt: Date(timeIntervalSince1970: 1), itemCount: 0)
        let items = DocumentsLibraryCatalog.items(notes: [trip, groceries, journal], easels: [easel, blank])
        folderScopes()

        expect(items.count == 5, "notes and Easels share one catalog")
        expect(items[0].noteURL == trip.url && items[0].isNote && items[0].easelID == nil, "a note keeps its file")
        expect(items[3].easelID == easel.id && !items[3].isNote, "an Easel keeps its identity")
        expect(items[0].emoji == "🧳", "an emoji icon shows on the card")
        expect(items[1].emoji == nil, "an image icon doesn't pose as an emoji")
        expect(items[2].emoji == "❤️", "a text-style emoji with its selector still counts")
        expect(DocumentsLibraryCatalog.emoji("A") == nil && DocumentsLibraryCatalog.emoji("1") == nil && DocumentsLibraryCatalog.emoji("🇵🇹") == "🇵🇹",
               "letters and digits aren't icons, flags are")
        expect(items[0].preview == "Pack the passport. Book the tram.", "the preview is one tidy line")
        expect(items[2].preview.count == DocumentsLibraryCatalog.previewLimit && items[2].preview.hasSuffix("…"), "long previews end in an ellipsis")
        expect(items[4].title == "Untitled Easel", "a blank Easel title reads Untitled Easel")
        expect(items[3].detail == "Easel · 3 objects" && items[0].detail == "Note", "each card knows what it is")

        let all = DocumentsLibraryCatalog.visible(items, query: "  ")
        expect(all.map(\.title) == ["Groceries", "Moodboard", "Journal", "Trip to Lisbon", "Untitled Easel"], "no search lists newest first")

        expect(DocumentsLibraryCatalog.visible(items, query: "lisbon").map(\.title) == ["Trip to Lisbon"], "titles match")
        expect(DocumentsLibraryCatalog.visible(items, query: "PASTEIS").map(\.title) == ["Groceries"], "previews match, ignoring case and accents")
        expect(DocumentsLibraryCatalog.visible(items, query: "passport tram").map(\.title) == ["Trip to Lisbon"], "every word has to match")
        expect(DocumentsLibraryCatalog.visible(items, query: "passport opera").isEmpty, "a missing word rules a card out")
        expect(DocumentsLibraryCatalog.visible(items, query: "easel").map(\.title) == ["Untitled Easel", "Moodboard"], "Easels answer to Easel, title matches first")

        let deep = DocumentsLibraryCatalog.visible(items, query: "sardines", noteMatches: [URL(fileURLWithPath: "/Users/parc-sample/Documents/./Parc Notes/Journal.md")])
        expect(deep.map(\.title) == ["Journal"], "body matches from the note search count")
        let ranked = DocumentsLibraryCatalog.visible(items, query: "jour", noteMatches: [groceries.url])
        expect(ranked.map(\.title) == ["Journal", "Groceries"], "title matches come before body matches")

        expect(DocumentsLibraryCatalog.emptyMessage(query: "") == "Your local Easels and Notes will appear here.", "an empty Library says what lands here")
        expect(DocumentsLibraryCatalog.emptyMessage(query: "zzz") == "Nothing matches that. Try fewer words?", "an empty search says so")
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        let ages: [(TimeInterval, String)] = [(-30, "Just now"), (20, "Just now"), (60, "1 minute ago"), (3 * 3_600, "3 hours ago"),
                                              (30 * 3_600, "Yesterday"), (3 * 86_400, "3 days ago"), (15 * 86_400, "2 weeks ago"),
                                              (70 * 86_400, "2 months ago"), (800 * 86_400, "2 years ago")]
        for (seconds, text) in ages {
            expect(DocumentsLibraryCatalog.edited(now.addingTimeInterval(-seconds), now: now) == text, "edited \(seconds)s ago reads \(text)")
        }
        expect(DocumentsLibraryRenameError.changed.localizedDescription == "This changed in another window. Give it another try.",
               "a stale rename says what happened")
        indexReadyChangesTheInputs()
        print("DocumentsLibraryCatalogTests passed")
    }
}
