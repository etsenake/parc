import Foundation
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcCommandBar

struct CommandBarNoteDocumentTests {
    let sampleURL = URL(fileURLWithPath: "/Users/parc-sample/Documents/Parc Notes/Trip ideas.md")

    func tripIdeas(icon: String? = "🧳") -> CommandBarDocument {
        CommandBarDocument(note: NoteReference(url: sampleURL, title: "Trip ideas", icon: icon, modifiedAt: Date(timeIntervalSince1970: 1)))
    }

    @Test func aNoteFileBecomesANoteResult() {
        let document = tripIdeas()
        #expect(document.kind == .note)
        #expect(document.title == "Trip ideas")
        #expect(document.url == sampleURL)
    }

    @Test func anEmojiIconComesAlong() {
        #expect(tripIdeas().icon == "🧳")
    }

    @Test func theResultsKeyIsTheFilesKey() {
        #expect(tripIdeas().key == CommandBarDocument.noteKey(sampleURL))
    }

    @Test func anImageIconIsNotPassedOffAsAnEmoji() {
        #expect(tripIdeas(icon: "Attachments/cover.png").icon == nil)
    }
}

@MainActor
final class CommandBarNotesTests {
    let files = NoteEditorFiles.make(clock: NoteEditorManualClock())
    let folder: NoteEditorTemporaryFolder

    init() throws {
        folder = try NoteEditorTemporaryFolder("command-bar-notes")
    }

    func filledLibrary() throws -> (library: NoteLibrary, packing: URL) {
        let packing = try folder.write("---\nicon: 🧳\n---\nRemember the passport and the tram card.\n", to: "Packing.md")
        try folder.write("Oat milk, pastéis de nata.\n", to: "Groceries.md")
        return (files.library(folder: folder.url), packing)
    }

    @Test func noLibraryMeansNoBodyMatches() {
        #expect(CommandBarNotes.contentMatches("passport", in: nil).isEmpty)
    }

    @Test func aTwoLetterQueryDoesNotDigThroughNoteBodies() throws {
        let (library, _) = try filledLibrary()
        #expect(CommandBarNotes.contentMatches("  pa ", in: library).isEmpty)
    }

    @Test func anEmptyFolderListsNoNotes() {
        let library = files.library(folder: folder.url)
        #expect(CommandBarNotes.documents(in: library, openTabURLs: []).isEmpty)
    }

    @Test func aFoldersNotesAreListed() throws {
        let (library, _) = try filledLibrary()
        #expect(Set(CommandBarNotes.documents(in: library, openTabURLs: []).map(\.title)) == ["Packing", "Groceries"])
    }

    @Test func listedNotesCarryTheirIcons() throws {
        let (library, _) = try filledLibrary()
        #expect(CommandBarNotes.documents(in: library, openTabURLs: []).first { $0.title == "Packing" }?.icon == "🧳")
    }

    @Test func everyListedNoteOpensByFile() throws {
        let (library, _) = try filledLibrary()
        #expect(CommandBarNotes.documents(in: library, openTabURLs: []).allSatisfy { $0.kind == .note && $0.url != nil })
    }

    @Test func aNoteAlreadyOpenInATabShowsAsItsTabInstead() throws {
        let (library, _) = try filledLibrary()
        let open = CommandBarNotes.documents(in: library, openTabURLs: [URL(fileURLWithPath: folder.url.path + "/./Packing.md")])
        #expect(open.map(\.title) == ["Groceries"])
    }

    @Test func aWordFromANotesBodyFindsIt() throws {
        let (library, _) = try filledLibrary()
        #expect(CommandBarNotes.contentMatches("passport", in: library).map(\.title) == ["Packing"])
    }

    @Test func aBodyMatchSharesTheNotesKey() throws {
        let (library, packing) = try filledLibrary()
        #expect(CommandBarNotes.contentMatches("passport", in: library).first?.key == CommandBarDocument.noteKey(packing))
    }

    @Test func onceTheIndexIsReadyAnEmptySearchComesBackWithFreshMatches() throws {
        let (library, _) = try filledLibrary()
        let found = CommandBarNotes.contentMatches("passport", in: library)
        #expect(CommandBarNotes.refreshedMatches(for: "passport", replacing: [], in: library) == found)
    }

    @Test func matchesThatDidNotChangeLeaveTheResultsAlone() throws {
        let (library, _) = try filledLibrary()
        let found = CommandBarNotes.contentMatches("passport", in: library)
        #expect(CommandBarNotes.refreshedMatches(for: "passport", replacing: found, in: library) == nil)
    }

    struct OutsideNote {
        let folder: NoteEditorTemporaryFolder
        let url: URL
        let session: NoteFileSession
    }

    func outsideNote() throws -> OutsideNote {
        let other = try NoteEditorTemporaryFolder("command-bar-elsewhere")
        let url = try other.write("Ferry times to the islands.\n", to: "Ferries.md")
        return OutsideNote(folder: other, url: url, session: try files.open(url))
    }

    @Test func aNoteOpenInATabOutsideTheFolderIsFoundByItsText() throws {
        let (library, packing) = try filledLibrary()
        let outside = try outsideNote()
        let found = CommandBarNotes.contentMatches("ferry", in: library, openNotes: [outside.url, packing])
        #expect(found.map(\.title) == [outside.session.title])
        #expect(found.first?.key == CommandBarDocument.noteKey(outside.url))
        withExtendedLifetime(outside) {}
    }

    @Test func withoutItsTabANoteOutsideTheFolderStaysOut() throws {
        let (library, _) = try filledLibrary()
        let outside = try outsideNote()
        #expect(CommandBarNotes.contentMatches("ferry", in: library).isEmpty)
        withExtendedLifetime(outside) {}
    }

    @Test func openNotesAreSearchedEvenWithNoFolderLibrary() throws {
        let outside = try outsideNote()
        #expect(CommandBarNotes.contentMatches("ferry", in: nil, openNotes: [outside.url], files: files).map(\.title) == [outside.session.title])
        withExtendedLifetime(outside) {}
    }
}
