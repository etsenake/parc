import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteVisitStoreNoteChangesTests {
    @MainActor private struct OpenNotes {
        let store: BrowserStore
        let shown: UUID
        let ahead: UUID

        func openShown(_ url: URL) {
            store.openDocumentOverPage(shown, page: .note(url), title: "Readme")
        }

        func openAhead(_ url: URL) {
            store.openDocumentOverPage(ahead, page: .note(url), title: "Readme")
            store.stepNoteVisit(ahead, forward: false)
        }

        func rename(_ source: URL, in folder: URL) throws -> URL {
            let renamed = folder.appendingPathComponent("Guide.md")
            try FileManager.default.moveItem(at: source, to: renamed)
            store.updateNoteFile(from: source, to: renamed, title: "Guide")
            return renamed
        }
    }

    private func openTabs(in fixture: NoteVisitTestsSupport.Fixture) throws -> OpenNotes {
        let directory = fixture.directory
        let store = try BrowserStore(directory: directory.appendingPathComponent("files"))
        let shown = store.open("https://example.test/shown")
        store.updateTab(shown, title: "Shown", url: "https://example.test/shown")
        let ahead = store.open("https://example.test/ahead")
        store.updateTab(ahead, title: "Ahead", url: "https://example.test/ahead")
        return OpenNotes(store: store, shown: shown, ahead: ahead)
    }

    @Test func oneStoreTabCanOpenANoteOverItsPage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try openTabs(in: fixture)
        let store = tabs.store
        let shown = tabs.shown
        let readme = fixture.readme
        #expect(store.openDocumentOverPage(shown, page: .note(readme), title: "Readme"), "shown")
    }

    @Test func anotherStoreTabCanKeepTheSameNoteAhead() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try openTabs(in: fixture)
        tabs.openShown(fixture.readme)
        let store = tabs.store
        let ahead = tabs.ahead
        let readme = fixture.readme
        #expect(store.openDocumentOverPage(ahead, page: .note(readme), title: "Readme") && store.stepNoteVisit(ahead, forward: false), "ahead")
    }

    @Test func theStoreFollowsARenamedNoteWhileItIsShown() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try openTabs(in: fixture)
        tabs.openShown(fixture.readme)
        tabs.openAhead(fixture.readme)
        let renamed = try tabs.rename(fixture.readme, in: fixture.notes)
        let store = tabs.store
        let shown = tabs.shown
        #expect(store.state.tab(shown)?.url == renamed.absoluteString && store.state.tab(shown)?.title == "Guide"
                   && store.state.tab(shown)?.noteVisit?.note.url == renamed.absoluteString, "A rename follows the shown note")
    }

    @Test func renamingANoteAheadLeavesThePagesAddressAlone() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try openTabs(in: fixture)
        tabs.openShown(fixture.readme)
        tabs.openAhead(fixture.readme)
        let renamed = try tabs.rename(fixture.readme, in: fixture.notes)
        let store = tabs.store
        let ahead = tabs.ahead
        #expect(store.state.tab(ahead)?.noteVisit?.note == .init(url: renamed.absoluteString, title: "Guide")
                   && store.state.tab(ahead)?.url == "https://example.test/ahead", "A rename follows a note waiting ahead")
    }

    @Test func storeForwardReachesARenamedNote() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try openTabs(in: fixture)
        tabs.openShown(fixture.readme)
        tabs.openAhead(fixture.readme)
        let renamed = try tabs.rename(fixture.readme, in: fixture.notes)
        let store = tabs.store
        let ahead = tabs.ahead
        #expect(store.stepNoteVisit(ahead, forward: true) && store.state.tab(ahead)?.url == renamed.absoluteString, "Forward lands on the renamed file")
    }

    @Test func deletingAFileMovesTheNoteToTrash() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try openTabs(in: fixture)
        tabs.openShown(fixture.readme)
        tabs.openAhead(fixture.readme)
        let renamed = try tabs.rename(fixture.readme, in: fixture.notes)
        let store = tabs.store
        var finished: Error??
        store.deleteLocalDocument(.note(renamed), profileID: store.activeSpace.profileID, ownerValid: { true },
                                  completion: { finished = .some($0) })
        #expect(finished != nil && finished! == nil, "The note moves to the Trash")
    }

    @Test func deletingANoteClosesItsStandaloneTab() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try openTabs(in: fixture)
        tabs.openShown(fixture.readme)
        tabs.openAhead(fixture.readme)
        let renamed = try tabs.rename(fixture.readme, in: fixture.notes)
        let store = tabs.store
        let plain = try #require(store.openNote(url: renamed, title: "Guide"), "plain note tab")
        store.deleteLocalDocument(.note(renamed), profileID: store.activeSpace.profileID, ownerValid: { true },
                                  deleteDocument: {}, completion: { _ in })
        #expect(!store.state.containsTab(plain), "The plain note tab goes with it")
    }

    @Test func deletingTheShownNoteReturnsItsTabToThePage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try openTabs(in: fixture)
        tabs.openShown(fixture.readme)
        tabs.openAhead(fixture.readme)
        let renamed = try tabs.rename(fixture.readme, in: fixture.notes)
        let store = tabs.store
        let shown = tabs.shown
        store.deleteLocalDocument(.note(renamed), profileID: store.activeSpace.profileID, ownerValid: { true },
                                  deleteDocument: {}, completion: { _ in })
        let back = try #require(store.state.tab(shown), "shown after delete")
        #expect(back.noteVisit == nil && back.url == "https://example.test/shown" && back.title == "Shown", "A page showing the deleted note goes back to its page instead of closing")
    }

    @Test func deletingTheNoteAheadClearsTheStoreForwardEntry() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try openTabs(in: fixture)
        tabs.openShown(fixture.readme)
        tabs.openAhead(fixture.readme)
        let renamed = try tabs.rename(fixture.readme, in: fixture.notes)
        let store = tabs.store
        let ahead = tabs.ahead
        store.deleteLocalDocument(.note(renamed), profileID: store.activeSpace.profileID, ownerValid: { true },
                                  deleteDocument: {}, completion: { _ in })
        #expect(store.state.tab(ahead)?.noteVisit == nil && store.state.tab(ahead)?.url == "https://example.test/ahead", "A page with the deleted note ahead just loses Forward")
    }
}
