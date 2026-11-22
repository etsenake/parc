import Foundation
import Testing
@testable import ParcCore

struct NoteVisitDocumentStackTests {
    @Test func openingDocumentsBuildsAStackOverThePage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let notes = fixture.notes
        let readme = fixture.readme
        let board = UUID()
        let guide = notes.appendingPathComponent("Chapter.md")
        try Data("# Chapter\n".utf8).write(to: guide)
        let a = readme.absoluteString, b = InternalPage.easel(board).urlString, c = guide.absoluteString
        var tab = NoteVisitTestsSupport.webTab()
        #expect(tab.openNoteVisit(url: readme, title: "Readme") && tab.openDocumentVisit(.easel(board), title: "Board")
                   && tab.openNoteVisit(url: guide, title: "Chapter"), "page → note → Easel → note opens in one tab")
        #expect(tab.url == c && tab.noteVisit?.documents.map(\.url) == [a, b, c], "Every document is its own step")
    }

    @Test func theStackListsEarlierStepsNearestFirst() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try NoteVisitTestsSupport.stack(in: fixture)
        let tab = stack.tab
        let a = stack.noteURL, b = stack.easelURL
        let page = "https://example.test/docs"
        #expect(tab.noteVisit?.behind.map(\.url) == [b, a, page] && tab.noteVisit?.ahead.isEmpty == true, "The steps behind run nearest first down to the page")
    }

    @Test func backWalksEveryDocumentInReverseOrder() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try NoteVisitTestsSupport.stack(in: fixture)
        var tab = stack.tab
        let a = stack.noteURL, b = stack.easelURL
        let page = "https://example.test/docs"
        for expected in [b, a, page] {
            #expect(tab.stepBackFromNote() && tab.url == expected, "Back walks every step in order")
        }
    }

    @Test func backFromTheFirstPageLeavesAllDocumentsAhead() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try NoteVisitTestsSupport.stack(in: fixture)
        var tab = stack.tab
        let a = stack.noteURL, b = stack.easelURL, c = stack.guideURL
        tab.stepNoteVisit(by: -3)
        #expect(!tab.stepBackFromNote() && tab.noteVisit?.ahead.map(\.url) == [a, b, c], "The page's own Back takes over")
    }

    @Test func forwardWalksEveryDocumentInOrder() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try NoteVisitTestsSupport.stack(in: fixture)
        var tab = stack.tab
        let a = stack.noteURL, b = stack.easelURL, c = stack.guideURL
        tab.stepNoteVisit(by: -3)
        for expected in [a, b, c] {
            #expect(tab.stepForwardToNote() && tab.url == expected, "Forward retraces them")
        }
    }

    @Test func theNewestDocumentHasNoForwardStep() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try NoteVisitTestsSupport.stack(in: fixture)
        var tab = stack.tab
        let forwardWasRefused = !tab.stepForwardToNote()
        #expect(forwardWasRefused, "Nothing past the newest step")
    }

    @Test func historyCanJumpSeveralDocumentStepsAtOnce() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try NoteVisitTestsSupport.stack(in: fixture)
        var tab = stack.tab
        let b = stack.easelURL
        let page = "https://example.test/docs"
        #expect(tab.stepNoteVisit(by: -3) && tab.url == page && tab.stepNoteVisit(by: 2) && tab.url == b, "A history list or swipe can jump several steps at once")
    }

    @Test func anInvalidHistoryJumpLeavesTheShownDocumentAlone() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try NoteVisitTestsSupport.stack(in: fixture)
        var tab = stack.tab
        let b = stack.easelURL
        tab.stepBackFromNote()
        #expect(!tab.stepNoteVisit(by: 2) && !tab.stepNoteVisit(by: -3) && !tab.stepNoteVisit(by: 0) && tab.url == b, "Jumps past either end change nothing")
    }

    @Test func openingADocumentFromTheMiddleTruncatesForwardAndKeepsTheLatestTitle() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try NoteVisitTestsSupport.stack(in: fixture)
        var tab = stack.tab
        let a = stack.noteURL, b = stack.easelURL
        let sketch = UUID()
        tab.stepBackFromNote()
        tab.title = "Board, renamed in place"
        let openedDocument = tab.openDocumentVisit(.easel(sketch), title: "Sketch")
        #expect(openedDocument, "A document opened mid-stack")
        #expect(tab.noteVisit?.documents.map(\.url) == [a, b, InternalPage.easel(sketch).urlString], "truncates the steps ahead, like any navigation")
        #expect(tab.noteVisit?.documents[1].title == "Board, renamed in place", "The step it left keeps its latest title")
    }

    @Test func openingTheShownDocumentAgainUpdatesItsTitleWithoutAddingAStep() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try NoteVisitTestsSupport.stack(in: fixture)
        var tab = stack.tab
        let sketch = UUID()
        tab.stepBackFromNote()
        tab.title = "Board, renamed in place"
        tab.openDocumentVisit(.easel(sketch), title: "Sketch")
        #expect(tab.openDocumentVisit(.easel(sketch), title: "Sketch 2") && tab.noteVisit?.documents.count == 3
                   && tab.title == "Sketch 2", "Opening the shown document again adds no step")
    }

    @Test func theDocumentLimitRemovesTheOldestSteps() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let a = readme.absoluteString
        var long = NoteVisitTestsSupport.webTab()
        long.openNoteVisit(url: readme, title: "Readme")
        for _ in 0..<(TabNoteVisit.limit + 9) { long.openDocumentVisit(.easel(UUID()), title: "Board") }
        #expect(long.noteVisit?.documents.count == TabNoteVisit.limit && long.noteVisit?.position == TabNoteVisit.limit, "A tab keeps the newest 50 document steps, as Chromium keeps 50 page entries")
        #expect(long.noteVisit?.documents.first?.url != a, "The oldest steps go first")
    }

    @Test func backFromTheOldestKeptDocumentCanStillShowThePage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let page = "https://example.test/docs"
        var long = NoteVisitTestsSupport.webTab()
        long.openNoteVisit(url: readme, title: "Readme")
        for _ in 0..<(TabNoteVisit.limit + 9) { long.openDocumentVisit(.easel(UUID()), title: "Board") }
        #expect(long.stepNoteVisit(by: -TabNoteVisit.limit) && long.url == page, "Back from the oldest kept step is still the page")
    }
}
