import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteVisitStoreNavigationTests {
    @Test func aSameTabNoteVisitKeepsTheExistingTabSelected() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let directory = fixture.directory
        let readme = fixture.readme
        let store = try BrowserStore(directory: directory.appendingPathComponent("store"))
        let page = store.open("https://example.test/docs")
        store.updateTab(page, title: "Docs", url: "https://example.test/docs")
        _ = store.open("https://example.test/other")
        store.selectTab(page)
        let tabs = store.state.tabs.count
        #expect(store.openDocumentOverPage(page, page: .note(readme), title: ""), "A same-tab click opens the note in the page's tab")
        #expect(store.state.tabs.count == tabs && store.state.selectedTabIDs == [page], "No new tab, and the tab stays selected")
        let shown = try #require(store.state.tab(page), "tab")
        #expect(shown.url == readme.absoluteString && shown.title == "Readme" && shown.showsNoteOverPage, "The tab shows the note")
    }

    @Test func openingTheSameNoteElsewhereCreatesAnOrdinaryNoteTab() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let directory = fixture.directory
        let readme = fixture.readme
        let store = try BrowserStore(directory: directory.appendingPathComponent("store"))
        let page = store.open("https://example.test/docs")
        store.updateTab(page, title: "Docs", url: "https://example.test/docs")
        store.openDocumentOverPage(page, page: .note(readme), title: "")
        #expect(store.openNote(url: readme, title: "Readme") != page, "Opening the note elsewhere gets its own tab, not the page's")
        let separate = store.state.tabs.first { $0.url == readme.absoluteString && $0.id != page }
        #expect(separate != nil && separate?.noteVisit == nil, "The separate note tab is an ordinary note tab")
    }

    @Test func theStoreTracksAHiddenPageWithoutChangingTheShownNote() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let directory = fixture.directory
        let readme = fixture.readme
        let store = try BrowserStore(directory: directory.appendingPathComponent("store"))
        let page = store.open("https://example.test/docs")
        store.updateTab(page, title: "Docs", url: "https://example.test/docs")
        store.openDocumentOverPage(page, page: .note(readme), title: "")
        store.updatePageUnderNote(page, title: "Docs — Section", url: "https://example.test/docs#section")
        let followed = try #require(store.state.tab(page), "followed")
        #expect(followed.url == readme.absoluteString && followed.noteVisit?.page.url == "https://example.test/docs#section", "The hidden page's address is remembered without changing the tab")
    }

    @Test func storeBackRestoresThePageTitleAndAddressAndKeepsTheNoteAhead() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let directory = fixture.directory
        let readme = fixture.readme
        let store = try BrowserStore(directory: directory.appendingPathComponent("store"))
        let page = store.open("https://example.test/docs")
        store.updateTab(page, title: "Docs", url: "https://example.test/docs")
        store.openDocumentOverPage(page, page: .note(readme), title: "")
        store.updatePageUnderNote(page, title: "Docs — Section", url: "https://example.test/docs#section")
        #expect(store.stepNoteVisit(page, forward: false), "Back shows the page")
        let back = try #require(store.state.tab(page), "back")
        #expect(back.url == "https://example.test/docs#section" && back.title == "Docs — Section" && back.hasVisitStepAhead, "Back puts the page's address and title on the tab and keeps the note ahead")
    }

    @Test func aSecondStoreBackIsLeftToThePage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let directory = fixture.directory
        let readme = fixture.readme
        let store = try BrowserStore(directory: directory.appendingPathComponent("store"))
        let page = store.open("https://example.test/docs")
        store.updateTab(page, title: "Docs", url: "https://example.test/docs")
        store.openDocumentOverPage(page, page: .note(readme), title: "")
        store.stepNoteVisit(page, forward: false)
        #expect(!store.stepNoteVisit(page, forward: false), "A second Back is the page's own")
    }

    @Test func retitlingThePageKeepsTheForwardEntry() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let directory = fixture.directory
        let readme = fixture.readme
        let store = try BrowserStore(directory: directory.appendingPathComponent("store"))
        let page = store.open("https://example.test/docs")
        store.updateTab(page, title: "Docs", url: "https://example.test/docs")
        store.openDocumentOverPage(page, page: .note(readme), title: "")
        store.stepNoteVisit(page, forward: false)
        store.updateTab(page, title: "Docs, retitled")
        #expect(store.state.tab(page)?.hasVisitStepAhead == true, "A title change keeps the Forward entry")
    }

    @Test func storeForwardShowsTheNoteAgain() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let directory = fixture.directory
        let readme = fixture.readme
        let store = try BrowserStore(directory: directory.appendingPathComponent("store"))
        let page = store.open("https://example.test/docs")
        store.updateTab(page, title: "Docs", url: "https://example.test/docs")
        store.openDocumentOverPage(page, page: .note(readme), title: "")
        store.stepNoteVisit(page, forward: false)
        #expect(store.stepNoteVisit(page, forward: true), "Forward shows the note again")
        #expect(store.state.tab(page)?.url == readme.absoluteString, "Forward puts the note back on the tab")
    }

    @Test func aNewPageNavigationDropsTheForwardNote() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let directory = fixture.directory
        let readme = fixture.readme
        let store = try BrowserStore(directory: directory.appendingPathComponent("store"))
        let page = store.open("https://example.test/docs")
        store.updateTab(page, title: "Docs", url: "https://example.test/docs")
        store.openDocumentOverPage(page, page: .note(readme), title: "")
        store.stepNoteVisit(page, forward: false)
        store.stepNoteVisit(page, forward: true)
        #expect(store.stepNoteVisit(page, forward: false), "And Back again")
        store.updateTab(page, url: "https://example.test/elsewhere")
        let moved = try #require(store.state.tab(page), "moved")
        #expect(moved.noteVisit == nil && moved.url == "https://example.test/elsewhere", "A new page navigation drops the Forward note")
        #expect(!store.stepNoteVisit(page, forward: true), "Forward has nothing to show after that")
    }

    @Test func typingAnAddressOverTheNoteLeavesIt() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let directory = fixture.directory
        let readme = fixture.readme
        let store = try BrowserStore(directory: directory.appendingPathComponent("store"))
        let page = store.open("https://example.test/docs")
        store.updateTab(page, title: "Docs", url: "https://example.test/docs")
        #expect(store.openDocumentOverPage(page, page: .note(readme), title: "Readme"), "Open the note again")
        store.updateTab(page, url: "https://example.test/typed")
        let typed = try #require(store.state.tab(page), "typed")
        #expect(typed.noteVisit == nil && typed.url == "https://example.test/typed", "Typing an address over the note leaves it")
    }

    @Test func theStoreRefusesRemoteNotes() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let directory = fixture.directory
        let store = try BrowserStore(directory: directory.appendingPathComponent("store"))
        let other = store.open("https://example.test/other")
        #expect(!store.openDocumentOverPage(other, page: .note(URL(string: "https://example.test/a.md")!), title: "a"), "Remote files aren't notes")
    }

    @Test func anUnknownTabCannotOpenADocument() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let directory = fixture.directory
        let readme = fixture.readme
        let store = try BrowserStore(directory: directory.appendingPathComponent("store"))
        #expect(!store.openDocumentOverPage(UUID(), page: .note(readme), title: "Readme"), "Unknown tabs open nothing")
    }

    @Test func anArchivedTabCannotOpenADocument() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let directory = fixture.directory
        let readme = fixture.readme
        let store = try BrowserStore(directory: directory.appendingPathComponent("store"))
        let archived = store.open("https://example.test/archived")
        store.closeTab(archived)
        #expect(!store.openDocumentOverPage(archived, page: .note(readme), title: "Readme"), "Archived tabs open nothing")
    }

    @Test func openingANoteChangesTheChromeLayout() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let directory = fixture.directory
        let readme = fixture.readme
        let store = try BrowserStore(directory: directory.appendingPathComponent("store"))
        let page = store.open("https://example.test/docs")
        store.updateTab(page, title: "Docs", url: "https://example.test/docs")
        let state = store.state
        var next = state
        let nextIndex = try #require(next.tabs.firstIndex { $0.id == page }, "index")
        next.tabs[nextIndex].openNoteVisit(url: readme, title: "Readme")
        #expect(!next.preservesChromeLayout(relativeTo: state), "Showing a note over a page redraws the window")
    }

    @Test func anOrdinaryTitleChangePreservesTheChromeLayout() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let directory = fixture.directory
        let store = try BrowserStore(directory: directory.appendingPathComponent("store"))
        let page = store.open("https://example.test/docs")
        store.updateTab(page, title: "Docs", url: "https://example.test/docs")
        let state = store.state
        let nextIndex = try #require(state.tabs.firstIndex { $0.id == page }, "index")
        var titled = state
        titled.tabs[nextIndex].title = "Something else"
        #expect(titled.preservesChromeLayout(relativeTo: state), "A plain title change still takes the quick path")
    }
}
