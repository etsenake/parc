import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteVisitStoreInterleavingTests {
    @MainActor private struct TrackedTab {
        let store: BrowserStore
        let id: UUID
        let board: UUID
        let readme: URL
        let b = NoteVisitTestsSupport.entry("b")

        func openNote() {
            store.openDocumentOverPage(id, page: .note(readme), title: "Readme", history: NoteVisitTestsSupport.history(["a"], current: 0))
        }

        func typeSecondPageAddress() {
            store.updateTab(id, url: b.url)
        }

        func commitSecondPage() {
            store.syncPageHistory(id, history: NoteVisitTestsSupport.history(["a", "b"], current: 1))
        }

        func titleSecondPage() {
            store.updateTab(id, title: "B, titled")
        }

        var titledHistory: TabNoteVisit.PageHistory {
            var history = NoteVisitTestsSupport.history(["a", "b"], current: 1)
            history.entries[1].title = "B, titled"
            return history
        }

        func openBoard() {
            store.openDocumentOverPage(id, page: .easel(board), title: "Board", history: titledHistory)
        }
    }

    private func trackedTab(_ fixture: NoteVisitTestsSupport.Fixture) throws -> TrackedTab {
        let store = try BrowserStore(directory: fixture.directory.appendingPathComponent("interleaved"))
        let a = NoteVisitTestsSupport.entry("a")
        let id = store.open(a.url)
        store.updateTab(id, title: a.title, url: a.url)
        return TrackedTab(store: store, id: id, board: UUID(), readme: fixture.readme)
    }

    private func restart(_ fixture: NoteVisitTestsSupport.Fixture) throws -> TrackedTab {
        let route = try trackedTab(fixture)
        route.openNote()
        route.typeSecondPageAddress()
        route.commitSecondPage()
        route.titleSecondPage()
        route.openBoard()
        route.store.stepNoteVisit(route.id, by: -2)
        try route.store.save()
        let store = try BrowserStore(directory: fixture.directory.appendingPathComponent("interleaved"))
        return TrackedTab(store: store, id: route.id, board: route.board, readme: route.readme)
    }

    @Test func aStoreNoteCanOpenOverATrackedPage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try trackedTab(fixture)
        let store = route.store, id = route.id
        let readme = fixture.readme
        #expect(store.openDocumentOverPage(id, page: .note(readme), title: "Readme", history: NoteVisitTestsSupport.history(["a"], current: 0)), "A note opens over the page, anchored to its history entry")
    }

    @Test func typingAnAddressOverANoteKeepsItBehindThePendingPage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try trackedTab(fixture)
        let store = route.store, id = route.id
        route.openNote()
        route.typeSecondPageAddress()
        let b = route.b
        let typed = try #require(store.state.tab(id), "typed")
        #expect(typed.url == b.url && typed.noteVisit?.leaving == true && typed.noteVisit?.documents.count == 1, "Typing an address over a note keeps the note behind the new page")
    }

    @Test func theNewPageCommitsAfterTheNote() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try trackedTab(fixture)
        let store = route.store, id = route.id
        route.openNote()
        route.typeSecondPageAddress()
        route.commitSecondPage()
        let b = route.b
        #expect(store.state.tab(id)?.noteVisit?.shownPage == b, "The new page joins the history after the note")
    }

    @Test func theStoreRemembersThePageTitleInItsHistoryStep() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try trackedTab(fixture)
        let store = route.store, id = route.id
        route.openNote()
        route.typeSecondPageAddress()
        route.commitSecondPage()
        route.titleSecondPage()
        #expect(store.state.tab(id)?.noteVisit?.shownPage?.title == "B, titled", "The page's title is remembered for its step")
    }

    @Test func anEaselCanOpenOverTheSecondPage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try trackedTab(fixture)
        let store = route.store, id = route.id
        route.openNote()
        route.typeSecondPageAddress()
        route.commitSecondPage()
        route.titleSecondPage()
        let board = route.board, titled = route.titledHistory
        #expect(store.openDocumentOverPage(id, page: .easel(board), title: "Board", history: titled), "An Easel over the second page")
    }

    @Test func storeBackCanJumpAcrossAPageToTheNote() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try trackedTab(fixture)
        let store = route.store, id = route.id
        route.openNote()
        route.typeSecondPageAddress()
        route.commitSecondPage()
        route.titleSecondPage()
        route.openBoard()
        let readme = fixture.readme
        #expect(store.stepNoteVisit(id, by: -2) && store.state.tab(id)?.url == readme.absoluteString, "Back across the page lands on the note")
    }

    @Test func theStoreRestoresInterleavedHistoryAndItsCurrentStep() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try restart(fixture)
        let store = route.store, id = route.id
        let readme = fixture.readme
        let restored = try #require(store.state.tab(id)?.noteVisit, "restored")
        #expect(restored.steps.compactMap(\.page).map(\.id) == ["a", "b"] && restored.current?.url == readme.absoluteString
                   && restored.position == 1, "A restart restores the whole history and where the tab stood")
    }

    @Test func storeForwardAfterRestartReachesTheEaselOverTheSecondPage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try restart(fixture)
        let store = route.store, id = route.id
        let board = route.board
        #expect(store.stepNoteVisit(id, by: 2) && store.state.tab(id)?.url == InternalPage.easel(board).urlString, "Forward after a restart reaches the Easel over the second page")
    }

    @Test func storeBackShowsTheSecondPageWithItsOwnTitle() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try restart(fixture)
        let store = route.store, id = route.id
        store.stepNoteVisit(id, by: 2)
        #expect(store.stepNoteVisit(id, by: -1) && store.state.tab(id)?.url == "https://example.test/b"
                   && store.state.tab(id)?.title == "B, titled", "Back from it shows the second page under its own title")
    }

    @Test func aPageNavigationWaitsForTheHistoryReport() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try restart(fixture)
        let store = route.store, id = route.id
        store.stepNoteVisit(id, by: 2)
        store.stepNoteVisit(id, by: -1)
        store.updateTab(id, url: "https://example.test/link")
        #expect(store.state.tab(id)?.noteVisit != nil, "A page's own navigation waits for its history report")
    }

    @Test func followingAWebLinkDropsTheEaselThatWasAhead() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try restart(fixture)
        let store = route.store, id = route.id
        store.stepNoteVisit(id, by: 2)
        store.stepNoteVisit(id, by: -1)
        let readme = fixture.readme
        store.updateTab(id, url: "https://example.test/link")
        store.syncPageHistory(id, history: NoteVisitTestsSupport.history(["a", "b", "link"], current: 2))
        let followed = try #require(store.state.tab(id)?.noteVisit, "followed")
        #expect(followed.documents.map(\.url) == [readme.absoluteString] && followed.shownPage?.id == "link", "A link followed from the page drops the Easel that was ahead of it, like web history")
    }
}
