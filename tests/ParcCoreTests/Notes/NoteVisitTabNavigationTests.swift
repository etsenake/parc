import Foundation
import Testing
@testable import ParcCore

struct NoteVisitTabNavigationTests {
    @Test func aPageCanShowANoteOverIt() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        var tab = NoteVisitTestsSupport.webTab()
        let openedNote = tab.openNoteVisit(url: readme, title: "")
        #expect(openedNote, "A page can open a note over itself")
        #expect(tab.url == readme.absoluteString && tab.title == "Readme", "The tab's address and title follow the note")
        #expect(tab.savedURL == tab.url && tab.savedTitle == "Readme", "A Today tab's saved address follows what shows")
        #expect(tab.showsNoteOverPage && !tab.hasVisitStepAhead, "The note shows on top of the page")
        #expect(tab.noteVisit?.page == .init(url: "https://example.test/docs", title: "Docs"), "The page entry remembers where it was")
    }

    @Test func aShownNoteHasNoForwardStep() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        var tab = NoteVisitTestsSupport.webTab()
        tab.openNoteVisit(url: readme, title: "")
        let forwardWasRefused = !tab.stepForwardToNote()
        #expect(forwardWasRefused, "Forward does nothing while the note shows")
    }

    @Test func backShowsThePageAndKeepsTheNoteAhead() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        var tab = NoteVisitTestsSupport.webTab()
        tab.openNoteVisit(url: readme, title: "")
        let movedBack = tab.stepBackFromNote()
        #expect(movedBack, "Back leaves the note")
        #expect(tab.url == "https://example.test/docs" && tab.title == "Docs", "Back shows the page's address and title")
        #expect(tab.hasVisitStepAhead && !tab.showsNoteOverPage, "The note waits ahead after Back")
    }

    @Test func backFromThePageLeavesBackToItsOwnHistory() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        var tab = NoteVisitTestsSupport.webTab()
        tab.openNoteVisit(url: readme, title: "")
        tab.stepBackFromNote()
        let backWasRefused = !tab.stepBackFromNote()
        #expect(backWasRefused, "Back from the page is the page's own business")
    }

    @Test func forwardToTheNoteKeepsTheLatestPageTitle() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        var tab = NoteVisitTestsSupport.webTab()
        tab.openNoteVisit(url: readme, title: "")
        tab.stepBackFromNote()
        tab.title = "Docs, updated"
        let movedForward = tab.stepForwardToNote()
        #expect(movedForward, "Forward returns to the note")
        #expect(tab.url == readme.absoluteString && tab.title == "Readme", "Forward shows the note again")
        #expect(tab.noteVisit?.page.title == "Docs, updated", "Forward takes the page's latest title along")
    }

    @Test func theHiddenPageCanMoveWithoutChangingTheShownNote() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        var tab = NoteVisitTestsSupport.webTab()
        tab.openNoteVisit(url: readme, title: "")
        let updatedHiddenPage = tab.followPageUnderNote(url: "https://example.test/docs#intro", title: nil)
        #expect(updatedHiddenPage, "The hidden page can still move")
        #expect(tab.url == readme.absoluteString, "A hidden page's moves never change what the tab shows")
    }

    @Test func anEmptyUpdateDoesNotChangeTheHiddenPage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        var tab = NoteVisitTestsSupport.webTab()
        tab.openNoteVisit(url: readme, title: "")
        let updateWasRefused = !tab.followPageUnderNote(url: nil, title: "")
        #expect(updateWasRefused, "Empty updates change nothing")
    }

    @Test func backShowsWhereTheHiddenPageMoved() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        var tab = NoteVisitTestsSupport.webTab()
        tab.openNoteVisit(url: readme, title: "")
        tab.followPageUnderNote(url: "https://example.test/docs#intro", title: nil)
        #expect(tab.stepBackFromNote() && tab.url == "https://example.test/docs#intro", "Back lands on the page where it moved")
    }

    @Test func openingANoteKeepsAPinnedTabsHomeAddress() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        var pinned = NoteVisitTestsSupport.webTab(kind: .pinned)
        pinned.savedURL = "https://example.test/"
        let openedNote = pinned.openNoteVisit(url: readme, title: "Readme")
        #expect(openedNote, "Pinned pages open notes too")
        #expect(pinned.savedURL == "https://example.test/", "A pinned tab keeps its home address")
    }

    @Test func aBlankTabCannotOpenANoteVisit() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        var blank = NoteVisitTestsSupport.webTab("about:blank", title: "New tab")
        let openingWasRefused = !blank.openNoteVisit(url: readme, title: "Readme")
        #expect(openingWasRefused, "A blank tab has no page to go back to")
    }

    @Test func aStandaloneNoteCannotStackAnotherNote() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        var note = NoteVisitTestsSupport.webTab(readme.absoluteString, title: "Readme")
        let openingWasRefused = !note.openNoteVisit(url: readme, title: "Readme")
        #expect(openingWasRefused, "A note tab doesn't stack notes")
    }

    @Test func anArchivedTabCannotOpenANoteVisit() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        var archived = NoteVisitTestsSupport.webTab()
        archived.archivedAt = Date()
        let openingWasRefused = !archived.openNoteVisit(url: readme, title: "Readme")
        #expect(openingWasRefused, "Archived tabs don't open notes")
    }

    @Test func aRemoteFileCannotOpenAsANoteVisit() {
        var web = NoteVisitTestsSupport.webTab()
        let openingWasRefused = !web.openNoteVisit(url: URL(string: "https://example.test/readme.md")!, title: "x")
        #expect(openingWasRefused, "Only local note files count")
    }

    @Test func forgettingTheShownNoteReturnsToThePage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        var forgotten = NoteVisitTestsSupport.webTab()
        forgotten.openNoteVisit(url: readme, title: "Readme")
        let matcher = InternalPage.note(readme).matcher()
        let forgotNote = forgotten.forgetNote(matching: matcher)
        #expect(forgotNote, "A deleted note leaves the tab")
        #expect(forgotten.noteVisit == nil && forgotten.url == "https://example.test/docs", "Forgetting a shown note goes back to the page")
    }

    @Test func forgettingANoteAheadDropsItsForwardEntry() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let matcher = InternalPage.note(readme).matcher()
        var ahead = NoteVisitTestsSupport.webTab()
        ahead.openNoteVisit(url: readme, title: "Readme"); ahead.stepBackFromNote()
        #expect(ahead.forgetNote(matching: matcher) && ahead.noteVisit == nil && ahead.url == "https://example.test/docs", "Forgetting a note ahead just drops the Forward entry")
    }

    @Test func forgettingANoteTwiceHasNoEffect() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let readme = fixture.readme
        let matcher = InternalPage.note(readme).matcher()
        var ahead = NoteVisitTestsSupport.webTab()
        ahead.openNoteVisit(url: readme, title: "Readme"); ahead.stepBackFromNote()
        ahead.forgetNote(matching: matcher)
        let forgettingWasRefused = !ahead.forgetNote(matching: matcher)
        #expect(forgettingWasRefused, "Nothing left to forget")
    }
}
