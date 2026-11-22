import Foundation
import Testing
@testable import ParcCore

struct NoteVisitEaselNavigationTests {
    @Test func aPageCanShowAnEaselOverIt() {
        let id = UUID()
        let easel = InternalPage.easel(id).urlString
        var tab = NoteVisitTestsSupport.webTab()
        let openedDocument = tab.openDocumentVisit(.easel(id), title: " Board ")
        #expect(openedDocument, "A page can open an Easel over itself")
        #expect(tab.url == easel && tab.title == "Board" && tab.showsNoteOverPage, "The tab shows the Easel on top of the page")
        #expect(tab.noteVisit?.document == .easel(id) && tab.noteVisit?.noteFile == nil, "The step holds the Easel, not a note")
    }

    @Test func backFromAnEaselShowsItsPage() {
        let id = UUID()
        var tab = NoteVisitTestsSupport.webTab()
        tab.openDocumentVisit(.easel(id), title: " Board ")
        #expect(tab.stepBackFromNote() && tab.url == "https://example.test/docs" && tab.hasVisitStepAhead, "Back shows the page")
    }

    @Test func forwardShowsTheEaselAgain() {
        let id = UUID()
        let easel = InternalPage.easel(id).urlString
        var tab = NoteVisitTestsSupport.webTab()
        tab.openDocumentVisit(.easel(id), title: " Board ")
        tab.stepBackFromNote()
        #expect(tab.stepForwardToNote() && tab.url == easel, "Forward returns to the Easel")
    }

    @Test func anUntitledEaselGetsItsDefaultName() {
        let id = UUID()
        var untitled = NoteVisitTestsSupport.webTab()
        #expect(untitled.openDocumentVisit(.easel(id), title: "") && untitled.title == "Untitled Easel", "An untitled Easel gets its usual name")
    }

    @Test func openingAnEaselOverANoteAddsAStep() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let id = UUID()
        let easel = InternalPage.easel(id).urlString
        var mixed = NoteVisitTestsSupport.webTab()
        mixed.openNoteVisit(url: readme, title: "Readme")
        let openedDocument = mixed.openDocumentVisit(.easel(id), title: "Board")
        #expect(openedDocument, "An Easel opened over a note is one more step")
        #expect(mixed.url == easel && mixed.noteVisit?.page.url == "https://example.test/docs", "The page stays behind it")
    }

    @Test func backFromAnEaselOverANoteShowsTheNote() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let id = UUID()
        var mixed = NoteVisitTestsSupport.webTab()
        mixed.openNoteVisit(url: readme, title: "Readme")
        mixed.openDocumentVisit(.easel(id), title: "Board")
        #expect(mixed.stepBackFromNote() && mixed.url == readme.absoluteString, "Back from the Easel shows the note")
    }

    @Test func backThroughTheNoteShowsTheOriginalPage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let id = UUID()
        var mixed = NoteVisitTestsSupport.webTab()
        mixed.openNoteVisit(url: readme, title: "Readme")
        mixed.openDocumentVisit(.easel(id), title: "Board")
        mixed.stepBackFromNote()
        #expect(mixed.stepBackFromNote() && mixed.url == "https://example.test/docs", "Back from the note shows the page")
    }

    @Test func forwardThroughTheNoteShowsTheEasel() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let id = UUID()
        let easel = InternalPage.easel(id).urlString
        var mixed = NoteVisitTestsSupport.webTab()
        mixed.openNoteVisit(url: readme, title: "Readme")
        mixed.openDocumentVisit(.easel(id), title: "Board")
        mixed.stepBackFromNote()
        mixed.stepBackFromNote()
        #expect(mixed.stepForwardToNote() && mixed.stepForwardToNote() && mixed.url == easel, "Forward walks to the Easel")
    }

    @Test func backTwiceWalksFromTheEaselThroughTheNote() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let id = UUID()
        var mixed = NoteVisitTestsSupport.webTab()
        mixed.openNoteVisit(url: readme, title: "Readme")
        mixed.openDocumentVisit(.easel(id), title: "Board")
        #expect(mixed.stepBackFromNote() && mixed.stepBackFromNote(), "Back to the page")
    }

    @Test func openingADocumentFromThePageReplacesForwardHistory() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let id = UUID()
        let other = UUID()
        var mixed = NoteVisitTestsSupport.webTab()
        mixed.openNoteVisit(url: readme, title: "Readme")
        mixed.openDocumentVisit(.easel(id), title: "Board")
        mixed.stepBackFromNote()
        mixed.stepBackFromNote()
        #expect(mixed.openDocumentVisit(.easel(other), title: "Other") && mixed.noteVisit?.document == .easel(other)
                   && mixed.noteVisit?.documents.count == 1, "A new document from the page replaces the steps ahead, like a new navigation")
    }

    @Test func forwardStopsAtTheReplacementDocument() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let id = UUID()
        let other = UUID()
        var mixed = NoteVisitTestsSupport.webTab()
        mixed.openNoteVisit(url: readme, title: "Readme")
        mixed.openDocumentVisit(.easel(id), title: "Board")
        mixed.stepBackFromNote()
        mixed.stepBackFromNote()
        mixed.openDocumentVisit(.easel(other), title: "Other")
        #expect(mixed.stepBackFromNote() && mixed.stepForwardToNote() && mixed.url == InternalPage.easel(other).urlString
                   && !mixed.stepForwardToNote(), "Forward reaches the newest document and nothing past it")
    }

    @Test func aStandaloneEaselCannotStackADocument() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let id = UUID()
        let easel = InternalPage.easel(id).urlString
        var easelTab = NoteVisitTestsSupport.webTab(easel, title: "Board")
        let openingWasRefused = !easelTab.openDocumentVisit(.note(readme), title: "Readme")
        #expect(openingWasRefused, "An Easel tab with no page behind it stacks nothing")
    }

    @Test func renamingAnEaselRenamesItsHistoryStep() {
        let other = UUID()
        var follow = NoteVisitTestsSupport.webTab()
        follow.openDocumentVisit(.easel(other), title: "Other")
        #expect(follow.followNoteRename(from: InternalPage.easel(other).matcher(), to: InternalPage.easel(other).urlString, title: "Renamed")
                   && follow.noteVisit?.note.title == "Renamed", "A renamed Easel renames its step")
    }

    @Test func forgettingTheShownEaselReturnsToItsPage() {
        let other = UUID()
        var follow = NoteVisitTestsSupport.webTab()
        follow.openDocumentVisit(.easel(other), title: "Other")
        #expect(follow.forgetNote(matching: InternalPage.easel(other).matcher()) && follow.noteVisit == nil
                   && follow.url == "https://example.test/docs", "A deleted Easel sends the tab back to its page")
    }
}
