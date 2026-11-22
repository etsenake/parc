import Foundation
import Testing
@testable import ParcCore

struct NoteVisitDocumentStackChangesTests {
    @Test func renamingAMiddleDocumentKeepsTheShownDocument() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try NoteVisitTestsSupport.stack(in: fixture)
        var renamed = stack.tab
        let board = stack.board
        let b = stack.easelURL, c = stack.guideURL
        #expect(renamed.followNoteRename(from: InternalPage.easel(board).matcher(), to: b, title: "Plans")
                   && renamed.noteVisit?.documents[1].title == "Plans" && renamed.url == c, "A rename reaches a step in the middle")
    }

    @Test func backShowsARenamedDocumentByItsNewName() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try NoteVisitTestsSupport.stack(in: fixture)
        var renamed = stack.tab
        let board = stack.board
        renamed.followNoteRename(from: InternalPage.easel(board).matcher(), to: stack.easelURL, title: "Plans")
        #expect(renamed.stepBackFromNote() && renamed.title == "Plans", "and Back shows it by its new name")
    }

    @Test func deletingAMiddleDocumentKeepsTheShownDocument() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try NoteVisitTestsSupport.stack(in: fixture)
        var renamed = stack.tab
        let board = stack.board
        let docsAt = { (tab: BrowserTab) in tab.noteVisit?.documents.map(\.url) ?? [] }
        let a = stack.noteURL, c = stack.guideURL
        #expect(renamed.forgetNote(matching: InternalPage.easel(board).matcher()) && docsAt(renamed) == [a, c]
                   && renamed.url == c, "Deleting a step in the middle keeps the shown one")
    }

    @Test func backSkipsADeletedDocument() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try NoteVisitTestsSupport.stack(in: fixture)
        var renamed = stack.tab
        let board = stack.board
        renamed.forgetNote(matching: InternalPage.easel(board).matcher())
        let a = stack.noteURL
        #expect(renamed.stepBackFromNote() && renamed.url == a, "Back skips the deleted step")
    }

    @Test func deletingTheShownDocumentShowsItsNearestPredecessor() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try NoteVisitTestsSupport.stack(in: fixture)
        var renamed = stack.tab
        let board = stack.board
        renamed.forgetNote(matching: InternalPage.easel(board).matcher())
        let docsAt = { (tab: BrowserTab) in tab.noteVisit?.documents.map(\.url) ?? [] }
        let a = stack.noteURL, guide = stack.guide
        #expect(renamed.forgetNote(matching: InternalPage.note(guide).matcher()) && renamed.url == a && renamed.title == "Readme"
                   && docsAt(renamed) == [a], "Deleting the shown step shows the nearest one behind it")
    }

    @Test func deletingTheSeparatingDocumentCoalescesAdjacentDuplicates() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let board = UUID(), a = readme.absoluteString
        let docsAt = { (tab: BrowserTab) in tab.noteVisit?.documents.map(\.url) ?? [] }
        var repeated = NoteVisitTestsSupport.webTab()
        repeated.openNoteVisit(url: readme, title: "Readme"); repeated.openDocumentVisit(.easel(board), title: "Board")
        repeated.openNoteVisit(url: readme, title: "Readme")
        #expect(repeated.forgetNote(matching: InternalPage.easel(board).matcher()) && docsAt(repeated) == [a]
                   && repeated.noteVisit?.position == 1 && repeated.url == a, "Steps left side by side on one document merge")
    }

    @Test func deletingADocumentAheadKeepsThePageAndOtherForwardSteps() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let board = UUID()
        let b = InternalPage.easel(board).urlString
        let page = "https://example.test/docs"
        var aheadOnly = NoteVisitTestsSupport.webTab()
        aheadOnly.openNoteVisit(url: readme, title: "Readme"); aheadOnly.openDocumentVisit(.easel(board), title: "Board")
        aheadOnly.stepNoteVisit(by: -2)
        #expect(aheadOnly.forgetNote(matching: InternalPage.note(readme).matcher()) && aheadOnly.url == page
                   && aheadOnly.noteVisit?.ahead.map(\.url) == [b], "Deleting a step ahead leaves the page and the rest of Forward")
    }
}
