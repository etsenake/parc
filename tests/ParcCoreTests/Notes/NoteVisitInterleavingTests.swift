import Foundation
import Testing
@testable import ParcCore

struct NoteVisitInterleavingTests {
    private struct Route {
        let a = NoteVisitTestsSupport.entry("a")
        let b = NoteVisitTestsSupport.entry("b")
        let c = NoteVisitTestsSupport.entry("c")
        let board = UUID()
        let readme: URL
        let guide: URL

        init(_ fixture: NoteVisitTestsSupport.Fixture) throws {
            readme = fixture.readme
            guide = fixture.notes.appendingPathComponent("Interleaved.md")
            try Data("# Interleaved\n".utf8).write(to: guide)
        }

        var note: String { readme.absoluteString }
        var easel: String { InternalPage.easel(board).urlString }
        var second: String { guide.absoluteString }

        func showingBoard() -> BrowserTab {
            var tab = NoteVisitTestsSupport.webTab(a.url, title: a.title)
            tab.openDocumentVisit(.note(readme), title: "Readme", history: NoteVisitTestsSupport.history(["a"], current: 0))
            tab.openDocumentVisit(.easel(board), title: "Board", history: NoteVisitTestsSupport.history(["a"], current: 0))
            return tab
        }

        func leavingBoard() -> BrowserTab {
            var tab = showingBoard()
            _ = tab.leaveNoteVisit(for: b.url)
            tab.url = b.url
            tab.title = b.title
            return tab
        }

        func showingSecondPage() -> BrowserTab {
            var tab = leavingBoard()
            tab.syncPageHistory(NoteVisitTestsSupport.history(["a", "b"], current: 1))
            return tab
        }

        func showingSecondNote() -> BrowserTab {
            var tab = showingSecondPage()
            tab.openDocumentVisit(.note(guide), title: "Interleaved", history: NoteVisitTestsSupport.history(["a", "b"], current: 1))
            return tab
        }

        func leavingSecondNote() -> BrowserTab {
            var tab = showingSecondNote()
            _ = tab.leaveNoteVisit(for: c.url)
            tab.url = c.url
            tab.title = c.title
            return tab
        }

        func showingFinalPage() -> BrowserTab {
            var tab = leavingSecondNote()
            tab.syncPageHistory(NoteVisitTestsSupport.history(["a", "b", "c"], current: 2))
            return tab
        }

        func showingFirstNote() -> BrowserTab {
            var tab = showingFinalPage()
            tab.stepNoteVisit(by: -4)
            return tab
        }
    }

    @Test func aNoteAndEaselOpenOverTheFirstTrackedPage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try Route(fixture)
        let readme = route.readme, board = route.board, a = route.a
        var tab = NoteVisitTestsSupport.webTab(a.url, title: a.title)
        #expect(tab.openDocumentVisit(.note(readme), title: "Readme", history: NoteVisitTestsSupport.history(["a"], current: 0))
                   && tab.openDocumentVisit(.easel(board), title: "Board", history: NoteVisitTestsSupport.history(["a"], current: 0)), "web A → note → Easel")
    }

    @Test func typingAnAddressLeavesTheEaselBehindThePendingPage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try Route(fixture)
        var tab = route.showingBoard()
        let b = route.b, easel = route.easel
        let leftDocument = tab.leaveNoteVisit(for: b.url)
        #expect(leftDocument, "Typing an address over the Easel leaves it for the page")
        tab.url = b.url; tab.title = b.title
        #expect(tab.noteVisit?.leaving == true && tab.noteVisit?.behind.first == .document(.init(url: easel, title: "Board"))
                   && tab.hasVisitStepBehind && !tab.hasVisitStepAhead, "While the new page loads, the Easel waits right behind it and nothing is ahead")
    }

    @Test func theNextPageCanCommitAfterLeavingAnEasel() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try Route(fixture)
        var tab = route.leavingBoard()
        let syncedHistory = tab.syncPageHistory(NoteVisitTestsSupport.history(["a", "b"], current: 1))
        #expect(syncedHistory, "The new page commits")
    }

    @Test func anotherNoteCanOpenOverTheNextPage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try Route(fixture)
        var tab = route.showingSecondPage()
        let guide = route.guide
        let openedDocument = tab.openDocumentVisit(.note(guide), title: "Interleaved", history: NoteVisitTestsSupport.history(["a", "b"], current: 1))
        #expect(openedDocument, "→ web B → note")
    }

    @Test func typingAnAddressLeavesTheSecondNote() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try Route(fixture)
        var tab = route.showingSecondNote()
        let c = route.c
        let leftDocument = tab.leaveNoteVisit(for: c.url)
        #expect(leftDocument, "and another typed address")
    }

    @Test func theLastPageCanCommitAfterLeavingASecondNote() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try Route(fixture)
        var tab = route.leavingSecondNote()
        let syncedHistory = tab.syncPageHistory(NoteVisitTestsSupport.history(["a", "b", "c"], current: 2))
        #expect(syncedHistory, "→ web C")
    }

    @Test func interleavedHistoryKeepsAllStepsInVisitOrder() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try Route(fixture)
        let tab = route.showingFinalPage()
        let a = route.a, b = route.b, c = route.c
        let note = route.note, easel = route.easel, second = route.second
        let steps: [TabNoteVisit.Step] = [.page(a), .document(.init(url: note, title: "Readme")), .document(.init(url: easel, title: "Board")),
                                          .page(b), .document(.init(url: second, title: "Interleaved")), .page(c)]
        #expect(tab.noteVisit?.steps == steps && tab.noteVisit?.shownPage == c && !tab.showsNoteOverPage, "Every page and document sits in one history, in the order it was visited")
    }

    @Test func backWalksInterleavedStepsAndRestoresTheirUnderlyingPages() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try Route(fixture)
        var tab = route.showingFinalPage()
        let a = route.a, b = route.b
        let note = route.note, easel = route.easel, second = route.second
        let back: [(String, String)] = [(second, "b"), (b.url, "b"), (easel, "a"), (note, "a"), (a.url, "a")]
        for (url, page) in back {
            let anchor = tab.noteVisit?.anchor(afterMovingBy: -1)
            #expect(anchor?.id == page && tab.stepBackFromNote() && tab.url == url && tab.noteVisit?.pageUnderShown.id == page, "Back walks every step in reverse, with the page underneath at the entry it was opened over")
        }
    }

    @Test func backPastTheFirstInterleavedPageUsesPageHistory() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try Route(fixture)
        var tab = route.showingFinalPage()
        tab.stepNoteVisit(by: -5)
        #expect(!tab.stepBackFromNote() && tab.noteVisit?.step(-1) == nil, "Back past the first page is the page's own history")
    }

    @Test func forwardRetracesInterleavedStepsAndTheirAnchors() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try Route(fixture)
        var tab = route.showingFinalPage()
        tab.stepNoteVisit(by: -5)
        let b = route.b, c = route.c
        let note = route.note, easel = route.easel, second = route.second
        for (url, page) in [(note, "a"), (easel, "a"), (b.url, "b"), (second, "b"), (c.url, "c")] {
            #expect(tab.noteVisit?.anchor(afterMovingBy: 1)?.id == page && tab.stepForwardToNote() && tab.url == url, "Forward retraces them")
        }
    }

    @Test func theNewestInterleavedPageHasNoForwardStep() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try Route(fixture)
        var tab = route.showingFinalPage()
        let forwardWasRefused = !tab.stepForwardToNote()
        #expect(forwardWasRefused, "Nothing past the newest page")
    }

    @Test func aHistoryJumpCrossesBothDocumentsAndPages() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try Route(fixture)
        var tab = route.showingFinalPage()
        let b = route.b, note = route.note
        #expect(tab.stepNoteVisit(by: -2) && tab.url == b.url && tab.stepNoteVisit(by: -2) && tab.url == note, "A list or swipe jumps across pages and documents")
    }

    @Test func interleavedHistorySurvivesTabEncoding() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try Route(fixture)
        let tab = route.showingFirstNote()
        let note = route.note
        let encoded = try JSONDecoder().decode(BrowserTab.self, from: JSONEncoder().encode(tab))
        #expect(encoded.noteVisit?.steps == tab.noteVisit?.steps && encoded.noteVisit?.position == tab.noteVisit?.position
                   && encoded.url == note, "The interleaved history survives a restart")
    }

    @Test func openingADocumentMidHistoryDropsLaterPagesAndDocuments() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try Route(fixture)
        let tab = route.showingFirstNote()
        let a = route.a
        var mid = tab
        let openedDocument = mid.openDocumentVisit(.easel(UUID()), title: "Fresh", history: NoteVisitTestsSupport.history(["a", "b", "c"], current: 0))
        #expect(openedDocument, "A document opened from the middle")
        #expect(mid.noteVisit?.steps.count == 3 && mid.noteVisit?.steps.compactMap(\.page) == [a] && !mid.hasVisitStepAhead, "drops every later page and document, like any new navigation")
    }

    @Test func renamingADocumentUpdatesItsStepOnADifferentPage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try Route(fixture)
        let tab = route.showingFirstNote()
        let guide = route.guide, second = route.second
        var renamed = tab
        #expect(renamed.followNoteRename(from: InternalPage.note(guide).matcher(), to: second, title: "Renamed")
                   && renamed.noteVisit?.steps[4] == .document(.init(url: second, title: "Renamed")), "A rename reaches a document in another page's run")
    }

    @Test func deletingTheShownEaselShowsTheNoteBehindIt() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try Route(fixture)
        let tab = route.showingFirstNote()
        let board = route.board, note = route.note
        var trashed = tab
        trashed.stepNoteVisit(by: 1)
        #expect(trashed.forgetNote(matching: InternalPage.easel(board).matcher()) && trashed.url == note
                   && trashed.noteVisit?.steps.count == 5, "Trashing the shown Easel shows the note behind it")
    }

    @Test func deletingTheLastDocumentOverAPageRestoresThePage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try Route(fixture)
        let tab = route.showingFirstNote()
        let board = route.board, a = route.a, b = route.b, readme = route.readme
        var trashed = tab
        trashed.stepNoteVisit(by: 1)
        trashed.forgetNote(matching: InternalPage.easel(board).matcher())
        #expect(trashed.forgetNote(matching: InternalPage.note(readme).matcher()) && trashed.url == a.url
                   && trashed.noteVisit?.shownPage == a && trashed.noteVisit?.ahead.first == .page(b), "Trashing the last document over a page shows that page, with the rest still ahead")
    }

    @Test func aLinkFollowedFromThePageDropsTheDocumentAhead() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let route = try Route(fixture)
        let a = route.a, readme = route.readme
        var leftover = NoteVisitTestsSupport.webTab(a.url, title: a.title)
        leftover.openDocumentVisit(.note(readme), title: "Readme", history: NoteVisitTestsSupport.history(["a"], current: 0))
        leftover.stepBackFromNote()
        #expect(leftover.syncPageHistory(NoteVisitTestsSupport.history(["a", "x"], current: 1)) && leftover.noteVisit == nil, "A link followed on the page drops the document ahead of it, and the visit with it")
    }
}
