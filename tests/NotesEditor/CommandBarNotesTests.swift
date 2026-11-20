import Foundation

@main @MainActor
struct CommandBarNotesTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func main() {
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
        print("CommandBarNotesTests passed")
    }
}
