import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteVisitStoreEaselTests {
    @MainActor private struct Tabs {
        let store: BrowserStore
        let id: UUID
        let shown: UUID
        let ahead: UUID

        var easel: String { InternalPage.easel(id).urlString }

        func openShown() {
            store.openDocumentOverPage(shown, page: .easel(id), title: "Board")
        }

        func openAhead() {
            store.openDocumentOverPage(ahead, page: .easel(id), title: "Board")
            store.stepNoteVisit(ahead, forward: false)
        }

        func rename() {
            store.updateEaselTitle(id: id, profileID: store.activeSpace.profileID, title: "Plans")
        }

        func delete() {
            store.deleteLocalDocument(.easel(id), profileID: store.activeSpace.profileID, ownerValid: { true },
                                      deleteDocument: {}, completion: { _ in })
        }
    }

    private func makeTabs(_ fixture: NoteVisitTestsSupport.Fixture) throws -> Tabs {
        let store = try BrowserStore(directory: fixture.directory.appendingPathComponent("easels"))
        let shown = store.open("https://example.test/shown")
        store.updateTab(shown, title: "Shown", url: "https://example.test/shown")
        let ahead = store.open("https://example.test/ahead")
        store.updateTab(ahead, title: "Ahead", url: "https://example.test/ahead")
        return Tabs(store: store, id: UUID(), shown: shown, ahead: ahead)
    }

    private func restart(_ fixture: NoteVisitTestsSupport.Fixture) throws -> Tabs {
        let tabs = try makeTabs(fixture)
        tabs.openShown()
        tabs.openAhead()
        tabs.rename()
        try tabs.store.save()
        let store = try BrowserStore(directory: fixture.directory.appendingPathComponent("easels"))
        return Tabs(store: store, id: tabs.id, shown: tabs.shown, ahead: tabs.ahead)
    }

    @Test func anEaselOpensOverItsPageWithoutCreatingATab() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try makeTabs(fixture)
        let store = tabs.store
        let shown = tabs.shown
        let id = tabs.id
        let easel = tabs.easel
        let priorTabCount = store.state.tabs.count
        #expect(store.openDocumentOverPage(shown, page: .easel(id), title: "Board"), "An Easel opens in the page's tab")
        #expect(store.state.tabs.count == priorTabCount && store.state.tab(shown)?.url == easel, "No new tab; the tab shows the Easel")
    }

    @Test func storeBackFromAnEaselShowsThePage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try makeTabs(fixture)
        let store = tabs.store
        let ahead = tabs.ahead
        let id = tabs.id
        #expect(store.openDocumentOverPage(ahead, page: .easel(id), title: "Board") && store.stepNoteVisit(ahead, forward: false), "Back from an Easel shows the page")
    }

    @Test func renamingTheShownEaselUpdatesItsTabAndHistory() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try makeTabs(fixture)
        let store = tabs.store
        let shown = tabs.shown
        tabs.openShown()
        tabs.openAhead()
        tabs.rename()
        #expect(store.state.tab(shown)?.title == "Plans" && store.state.tab(shown)?.noteVisit?.note.title == "Plans", "Renaming the Easel renames the shown step")
    }

    @Test func renamingAnEaselAheadKeepsThePagesTitle() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try makeTabs(fixture)
        let store = tabs.store
        let ahead = tabs.ahead
        tabs.openShown()
        tabs.openAhead()
        tabs.rename()
        #expect(store.state.tab(ahead)?.noteVisit?.note.title == "Plans" && store.state.tab(ahead)?.title == "Ahead", "and the step waiting ahead, without touching the page")
    }

    @Test func openingTheSameEaselElsewhereCreatesAStandaloneTab() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try makeTabs(fixture)
        let store = tabs.store
        let shown = tabs.shown
        let ahead = tabs.ahead
        let id = tabs.id
        tabs.openShown()
        tabs.openAhead()
        tabs.rename()
        let separate = try #require(store.openEasel(id: id, title: "Plans"), "separate Easel tab")
        #expect(separate != shown && separate != ahead, "Opening the Easel elsewhere gets its own tab")
    }

    @Test func restartRestoresTheEaselShownOverItsPage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try restart(fixture)
        let store = tabs.store
        let shown = tabs.shown
        let easel = tabs.easel
        #expect(store.state.tab(shown)?.url == easel && store.state.tab(shown)?.showsNoteOverPage == true, "After a restart the tab still shows the Easel over its page")
    }

    @Test func restartRestoresTheEaselThatIsAhead() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try restart(fixture)
        let store = tabs.store
        let ahead = tabs.ahead
        #expect(store.state.tab(ahead)?.hasVisitStepAhead == true, "and the other tab still has it ahead")
    }

    @Test func backFromAnEaselAfterRestartRestoresThePage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try restart(fixture)
        let store = tabs.store
        let shown = tabs.shown
        #expect(store.stepNoteVisit(shown, forward: false) && store.state.tab(shown)?.url == "https://example.test/shown", "Back after a restart puts the page back")
    }

    @Test func forwardCanReturnToTheEaselAfterRestart() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try restart(fixture)
        let store = tabs.store
        let shown = tabs.shown
        store.stepNoteVisit(shown, forward: false)
        #expect(store.stepNoteVisit(shown, forward: true), "Forward again")
    }

    @Test func deletingAnEaselCompletesSuccessfully() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try restart(fixture)
        let store = tabs.store
        let id = tabs.id
        var finished: Error??
        store.deleteLocalDocument(.easel(id), profileID: store.activeSpace.profileID, ownerValid: { true },
                                  deleteDocument: {}, completion: { finished = .some($0) })
        #expect(finished != nil && finished! == nil, "The Easel is deleted")
    }

    @Test func deletingTheShownEaselRestoresItsPage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try restart(fixture)
        let store = tabs.store
        let shown = tabs.shown
        tabs.delete()
        #expect(store.state.tab(shown)?.noteVisit == nil && store.state.tab(shown)?.url == "https://example.test/shown", "A page showing the deleted Easel goes back to its page instead of closing")
    }

    @Test func deletingTheEaselAheadClearsForward() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let tabs = try restart(fixture)
        let store = tabs.store
        let ahead = tabs.ahead
        tabs.delete()
        #expect(store.state.tab(ahead)?.noteVisit == nil && store.state.tab(ahead)?.url == "https://example.test/ahead", "A page with the deleted Easel ahead just loses Forward")
    }
}
