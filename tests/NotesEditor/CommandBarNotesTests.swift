import Foundation

@main @MainActor
struct CommandBarNotesTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func waitForSummaries(in library: NoteLibrary, until ready: ([NoteReference]) -> Bool) {
        let deadline = Date().addingTimeInterval(10)
        while !ready((try? library.notes()) ?? []) && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    static func main() {
        NoteLibrary.worker = NoteFileWorker(label: "org.parc.tests.command-bar-notes")
        let url = URL(fileURLWithPath: "/Users/parc-sample/Documents/Parc Notes/Trip ideas.md")
        let reference = NoteReference(url: url, title: "Trip ideas", icon: "🧳", modifiedAt: Date(timeIntervalSince1970: 1))
        let document = CommandBarDocument(note: reference)
        expect(document.kind == .note && document.title == "Trip ideas" && document.url == url, "a note file becomes a note result")
        expect(document.icon == "🧳", "an emoji icon comes along")
        expect(document.key == CommandBarDocument.noteKey(url), "the result's key is the file's key")
        let pictured = CommandBarDocument(note: NoteReference(url: url, title: "Trip ideas", icon: "Attachments/cover.png", modifiedAt: .distantPast))
        expect(pictured.icon == nil, "an image icon isn't passed off as an emoji")
        expect(CommandBarNotes.contentMatches("passport", in: nil).isEmpty, "no library, no body matches")
        let library = NoteLibrary.shared(folder: FileManager.default.temporaryDirectory.appendingPathComponent("parc-command-bar-notes-" + UUID().uuidString))
        expect(CommandBarNotes.contentMatches("  pa ", in: library).isEmpty, "a two-letter query doesn't dig through note bodies")
        expect(CommandBarNotes.documents(in: library, openTabURLs: []).isEmpty, "an empty folder lists no notes")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("parc-command-bar-notes-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let packing = folder.appendingPathComponent("Packing.md"), groceries = folder.appendingPathComponent("Groceries.md")
        try? Data("---\nicon: 🧳\n---\nRemember the passport and the tram card.\n".utf8).write(to: packing)
        try? Data("Oat milk, pastéis de nata.\n".utf8).write(to: groceries)
        let filled = NoteLibrary.shared(folder: folder)
        waitForSummaries(in: filled) { notes in notes.count == 2 && notes.contains { $0.icon == "🧳" } }
        let listed = CommandBarNotes.documents(in: filled, openTabURLs: [])
        expect(Set(listed.map(\.title)) == ["Packing", "Groceries"], "a folder's notes are listed")
        expect(listed.first { $0.title == "Packing" }?.icon == "🧳", "once the library's first snapshot lands, icons come along")
        expect(listed.allSatisfy { $0.kind == .note && $0.url != nil }, "every listed note opens by file")
        let open = CommandBarNotes.documents(in: filled, openTabURLs: [URL(fileURLWithPath: folder.path + "/./Packing.md")])
        expect(open.map(\.title) == ["Groceries"], "a note already open in a tab shows as its tab instead")
        let deadline = Date().addingTimeInterval(10)
        var found = CommandBarNotes.contentMatches("passport", in: filled)
        while found.isEmpty && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            found = CommandBarNotes.contentMatches("passport", in: filled)
        }
        expect(found.map(\.title) == ["Packing"], "a word from a note's body finds it")
        expect(found.first?.key == CommandBarDocument.noteKey(packing), "a body match shares the note's key")
        expect(CommandBarNotes.refreshedMatches(for: "passport", replacing: [], in: filled) == found,
               "once the index is ready, an empty search comes back with fresh matches")
        expect(CommandBarNotes.refreshedMatches(for: "passport", replacing: found, in: filled) == nil,
               "matches that didn't change leave the results alone")

        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent("parc-command-bar-elsewhere-" + UUID().uuidString + ".md")
        try? Data("Ferry times to the islands.\n".utf8).write(to: elsewhere)
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        guard let session = try? NoteFileSession.open(elsewhere) else { failTest("a note outside the folder opens") }
        let outside = CommandBarNotes.contentMatches("ferry", in: filled, openNotes: [elsewhere, packing])
        expect(outside.map(\.title) == [session.title], "a note open in a tab outside the folder is found by its text")
        expect(outside.first?.key == CommandBarDocument.noteKey(elsewhere), "it shares its tab's key")
        expect(CommandBarNotes.contentMatches("ferry", in: filled).isEmpty, "without its tab, a note outside the folder stays out")
        expect(CommandBarNotes.contentMatches("ferry", in: nil, openNotes: [elsewhere]).map(\.title) == [session.title],
               "open notes are searched even with no folder library")
        print("CommandBarNotesTests passed")
    }
}
