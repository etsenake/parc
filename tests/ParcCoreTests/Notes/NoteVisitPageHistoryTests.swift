import Foundation
import Testing
@testable import ParcCore

struct NoteVisitPageHistoryTests {
    private func shownNote(_ document: TabNoteVisit.Entry) -> TabNoteVisit {
        let a = NoteVisitTestsSupport.entry("a")
        var visit = TabNoteVisit.page(a.url, title: a.title, history: NoteVisitTestsSupport.history(["a"], current: 0))
        visit.push(document)
        return visit
    }

    struct InvalidHistory: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let history: TabNoteVisit.PageHistory
    }

    private static let invalidHistories = [
        InvalidHistory(testDescription: "duplicate page IDs", history: NoteVisitTestsSupport.history(["a", "a"], current: 0)),
        InvalidHistory(testDescription: "empty entries", history: NoteVisitTestsSupport.history([], current: 0)),
        InvalidHistory(testDescription: "empty page ID", history: .init(entries: [.init(id: "", url: "x", title: "")], current: 0)),
        InvalidHistory(testDescription: "current entry out of bounds", history: NoteVisitTestsSupport.history(["a"], current: 3)),
    ]

    @Test(arguments: invalidHistories) func unreadableHistoryReportsAreIgnored(_ example: InvalidHistory) throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let document = TabNoteVisit.Entry(url: fixture.readme.absoluteString, title: "Readme")
        var visit = shownNote(document)
        let synced = visit.sync(example.history)
        #expect(!synced)
    }

    @Test func aHiddenPageNavigationAddsAPageAfterTheShownDocument() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let doc = TabNoteVisit.Entry(url: readme.absoluteString, title: "Readme")
        var underneath = shownNote(doc)
        #expect(underneath.sync(NoteVisitTestsSupport.history(["a", "x"], current: 1)) && underneath.current == doc
                   && underneath.steps.compactMap(\.page) == [NoteVisitTestsSupport.entry("a"), NoteVisitTestsSupport.entry("x")] && underneath.pageID == "x", "The page moving on behind a document keeps the document and puts the new page after it")
    }

    @Test func theHiddenPageTitleUpdatesItsCurrentHistoryEntry() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let doc = TabNoteVisit.Entry(url: readme.absoluteString, title: "Readme")
        var underneath = shownNote(doc)
        _ = underneath.sync(NoteVisitTestsSupport.history(["a", "x"], current: 1))
        #expect(underneath.followPage(url: nil, title: "Moved on") && underneath.steps[2].title == "Moved on", "Title updates from the hidden page reach the entry it's on")
    }

    @Test func theShownDocumentStaysOverTheReplacementPage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let doc = TabNoteVisit.Entry(url: readme.absoluteString, title: "Readme")
        var replaced = shownNote(doc)
        #expect(replaced.sync(NoteVisitTestsSupport.history(["z"], current: 0)) && replaced.current == doc && replaced.pageUnderShown.id == "z", "A shown document whose page entry was replaced stays, over the page's current entry")
    }

    @Test func pruningAnOldPageAlsoPrunesItsDocuments() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let doc = TabNoteVisit.Entry(url: readme.absoluteString, title: "Readme")
        var pruned = TabNoteVisit.page(NoteVisitTestsSupport.entry("a").url, title: "A", history: NoteVisitTestsSupport.history(["a"], current: 0))
        pruned.push(doc); _ = pruned.leave(); pruned.sync(NoteVisitTestsSupport.history(["a", "b"], current: 1))
        pruned.push(.init(url: InternalPage.easel(UUID()).urlString, title: "Board")); _ = pruned.leave()
        pruned.sync(NoteVisitTestsSupport.history(["a", "b", "c"], current: 2))
        #expect(pruned.sync(NoteVisitTestsSupport.history(["b", "c"], current: 1)) && pruned.documents.count == 1 && pruned.steps.first == .page(NoteVisitTestsSupport.entry("b")), "When Chromium forgets its oldest page, the documents over it go too")
    }

    @Test func aPendingAddressKeepsTheDocumentBehindIt() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let doc = TabNoteVisit.Entry(url: readme.absoluteString, title: "Readme")
        var waiting = shownNote(doc)
        #expect(waiting.leave() && waiting.sync(NoteVisitTestsSupport.history(["a"], current: 0, navigating: true)) == false && waiting.leaving, "A typed address still loading keeps the document right behind it")
    }

    @Test func anUncommittedAddressRestoresThePageWithTheDocumentAhead() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let doc = TabNoteVisit.Entry(url: readme.absoluteString, title: "Readme")
        var waiting = shownNote(doc)
        _ = waiting.leave()
        _ = waiting.sync(NoteVisitTestsSupport.history(["a"], current: 0, navigating: true))
        #expect(waiting.sync(NoteVisitTestsSupport.history(["a"], current: 0)) && !waiting.leaving && waiting.shownPage == NoteVisitTestsSupport.entry("a")
                   && waiting.ahead == [.document(doc)], "A typed address that never commits leaves the page showing, with the document ahead")
    }

    @Test func legacyDocumentHistoryAttachesToTheFirstReportedPage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let doc = TabNoteVisit.Entry(url: readme.absoluteString, title: "Readme")
        var legacy = TabNoteVisit(page: .init(url: "https://example.test/old", title: "Old"), documents: [doc], position: 0)
        #expect(!legacy.tracksPageHistory && legacy.sync(NoteVisitTestsSupport.history(["p", "q"], current: 1))
                   && legacy.steps == [.page(NoteVisitTestsSupport.entry("p")), .page(NoteVisitTestsSupport.entry("q")), .document(doc)] && legacy.tracksPageHistory, "A stack saved before page tracking attaches to the page's current entry on its first report")
    }

    @Test func aPendingNavigationSurvivesEncoding() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        var restart = NoteVisitTestsSupport.webTab()
        restart.openDocumentVisit(.note(readme), title: "Readme", history: NoteVisitTestsSupport.history(["a"], current: 0))
        _ = restart.leaveNoteVisit(for: "https://example.test/typed")
        let saved = try JSONDecoder().decode(BrowserTab.self, from: JSONEncoder().encode(restart))
        #expect(saved.noteVisit?.leaving == true && saved.noteVisit == restart.noteVisit, "A typed address that hadn't committed yet is remembered across a restart")
    }

    @Test func trackedHistoryLimitsDocumentsAndKeepsTheFirstPage() {
        var bounded = TabNoteVisit.page(NoteVisitTestsSupport.entry("a").url, title: "A", history: NoteVisitTestsSupport.history(["a"], current: 0))
        for _ in 0..<(TabNoteVisit.limit + 5) { bounded.push(.init(url: InternalPage.easel(UUID()).urlString, title: "Board")) }
        #expect(bounded.documents.count == TabNoteVisit.limit && bounded.steps.first?.page == NoteVisitTestsSupport.entry("a"), "The newest 50 documents are kept and the first page stays")
    }
}
