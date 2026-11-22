import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteVisitStorePersistenceTests {
    private struct SavedTabs {
        let store: BrowserStore
        let page: UUID
        let archived: UUID
    }

    private func restart(_ fixture: NoteVisitTestsSupport.Fixture) throws -> SavedTabs {
        let readme = fixture.readme
        let directory = fixture.directory
        let location = directory.appendingPathComponent("restart")
        let page: UUID, archived: UUID
        do {
            let store = try BrowserStore(directory: location)
            page = store.open("https://example.test/docs")
            store.updateTab(page, title: "Docs", url: "https://example.test/docs")
            store.openDocumentOverPage(page, page: .note(readme), title: "Readme")
            archived = store.open("https://example.test/archived")
            store.updateTab(archived, title: "Archived", url: "https://example.test/archived")
            store.openDocumentOverPage(archived, page: .note(readme), title: "Readme")
            store.closeTab(archived)
            try store.save()
        }
        let restored = try BrowserStore(directory: location)
        return SavedTabs(store: restored, page: page, archived: archived)
    }

    @Test func aNoteCanOpenOverThePageBeforeSaving() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let directory = fixture.directory
        let readme = fixture.readme
        let store = try BrowserStore(directory: directory.appendingPathComponent("store"))
        let page = store.open("https://example.test/docs")
        store.updateTab(page, title: "Docs", url: "https://example.test/docs")
        #expect(store.openDocumentOverPage(page, page: .note(readme), title: "Readme"), "open")
    }

    @Test func aNoteVisitCanOpenBeforeItsTabIsArchived() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let directory = fixture.directory
        let readme = fixture.readme
        let store = try BrowserStore(directory: directory.appendingPathComponent("store"))
        let archived = store.open("https://example.test/archived")
        #expect(store.openDocumentOverPage(archived, page: .note(readme), title: "Readme"), "open archived")
    }

    @Test func reopeningTheStoreRestoresTheShownNoteAndUnderlyingPage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let saved = try restart(fixture)
        let restored = saved.store
        let page = saved.page
        let readme = fixture.readme
        let tab = try #require(restored.state.tab(page), "restored tab")
        #expect(tab.url == readme.absoluteString && tab.showsNoteOverPage, "After a restart the tab still shows the note")
        #expect(tab.noteVisit?.page.url == "https://example.test/docs", "and remembers the page to go Back to")
    }

    @Test func backAfterRestartRestoresThePagesAddress() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let saved = try restart(fixture)
        let restored = saved.store
        let page = saved.page
        #expect(restored.stepNoteVisit(page, forward: false) && restored.state.tab(page)?.url == "https://example.test/docs", "Back after a restart puts the page's address back, ready to load")
    }

    @Test func reopeningTheStoreRestoresAnArchivedTabShowingANote() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let saved = try restart(fixture)
        let restored = saved.store
        let archived = saved.archived
        let readme = fixture.readme
        let gone = try #require(restored.state.tab(archived), "archived tab")
        #expect(gone.archivedAt != nil && gone.showsNoteOverPage && gone.url == readme.absoluteString, "An archived tab keeps showing its note, with the page behind it")
    }

    @Test func anArchivedNoteVisitCannotGoBackAfterRestart() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let saved = try restart(fixture)
        let restored = saved.store
        let archived = saved.archived
        #expect(!restored.stepNoteVisit(archived, forward: false), "Archived tabs don't step")
    }
}
