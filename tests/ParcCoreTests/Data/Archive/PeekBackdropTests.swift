import Foundation
import Testing
@testable import ParcCore

struct PeekBackdropTests {
    final class FakePage {}

    func backdrop(tab: UUID?, open: Bool = true, page: Bool = false, startPage: Bool = false, space: UUID) -> PeekBackdrop {
        PeekBackdrop(currentTabID: tab, tabIsOpen: open, hasLivePage: page, showsStartPage: startPage, activeSpaceID: space)
    }

    func shownOver(_ backdrop: PeekBackdrop, tab: UUID?, startPage: Bool, space: UUID) -> Bool {
        guard case .overWindow(let host)? = backdrop.archivePreviewRoute else { return false }
        return PeekBackdrop.hostID(currentTabID: tab, showsStartPage: startPage, activeSpaceID: space) == host
    }

    @Test func aLiveWebPageIsTheBackdropAndKeepsOpeningThePreviewFromItsPage() {
        let space = UUID()
        let tab = UUID()
        let behind = backdrop(tab: tab, page: true, space: space)
        #expect(behind == .webPage(tabID: tab))
        #expect(behind.archivePreviewRoute == .fromPage)
    }

    @Test func aPeekStaysOverItsOwnParentPageOnly() {
        let page = FakePage()
        let replacement = FakePage()
        #expect(PeekBackdrop.peekStays(parent: page, hostPage: page))
        #expect(!PeekBackdrop.peekStays(parent: page, hostPage: replacement))
        #expect(!PeekBackdrop.peekStays(parent: page, hostPage: nil))
    }

    @Test func aWebTabWhosePageIsStillOpeningHasNoPageYetAndTheWindowHostsThePreview() {
        let space = UUID()
        let tab = UUID()
        let opening = backdrop(tab: tab, space: space)
        #expect(opening == .pagelessTab(tabID: tab))
        #expect(opening.archivePreviewRoute == .overWindow(hostID: tab))
        #expect(shownOver(opening, tab: tab, startPage: false, space: space))
    }

    @Test func theTabOwnedPreviewStaysShownWhenThePageArrivesUntilItAdoptsThePage() {
        let arrived = FakePage()
        #expect(PeekBackdrop.peekStays(parent: nil, hostPage: nil))
        #expect(PeekBackdrop.peekStays(parent: nil, hostPage: arrived))
        #expect(PeekBackdrop.peekStays(parent: arrived, hostPage: arrived))
    }

    @Test func switchingTabsHidesTheTabOwnedPreview() {
        let space = UUID()
        let opening = backdrop(tab: UUID(), space: space)
        #expect(!shownOver(opening, tab: UUID(), startPage: false, space: space))
    }

    @Test func theWindowHostsThePreviewOverANoteAndOverAnEasel() {
        let space = UUID()
        let note = UUID()
        let easel = UUID()
        let overNote = backdrop(tab: note, space: space)
        #expect(overNote.archivePreviewRoute == .overWindow(hostID: note))
        #expect(shownOver(overNote, tab: note, startPage: false, space: space))
        let overEasel = backdrop(tab: easel, space: space)
        #expect(overEasel.archivePreviewRoute == .overWindow(hostID: easel))
        #expect(shownOver(overEasel, tab: easel, startPage: false, space: space))
    }

    @Test func switchingToAnotherDocumentHidesTheFirstDocumentsPreview() {
        let space = UUID()
        let overNote = backdrop(tab: UUID(), space: space)
        let easel = UUID()
        #expect(!shownOver(overNote, tab: easel, startPage: false, space: space))
    }

    @Test func focusingASplitsWebPaneHidesThePreviewOwnedByTheFocusedNote() {
        let space = UUID()
        let overNote = backdrop(tab: UUID(), space: space)
        let web = UUID()
        #expect(!shownOver(overNote, tab: web, startPage: false, space: space))
    }

    @Test func anEmptySpacesStartPageHostsThePreviewForThatSpaceOnly() {
        let space = UUID()
        let other = UUID()
        let start = backdrop(tab: nil, startPage: true, space: space)
        #expect(start == .startPage(spaceID: space))
        #expect(start.archivePreviewRoute == .overWindow(hostID: space))
        #expect(shownOver(start, tab: nil, startPage: true, space: space))
        #expect(!shownOver(start, tab: nil, startPage: true, space: other))
        #expect(!shownOver(start, tab: UUID(), startPage: false, space: space))
    }

    @Test func anEmptyWindowHostsThePreviewOverItsStartPage() {
        let window = UUID()
        let emptyWindow = backdrop(tab: nil, startPage: true, space: window)
        #expect(emptyWindow.archivePreviewRoute == .overWindow(hostID: window))
        #expect(shownOver(emptyWindow, tab: nil, startPage: true, space: window))
    }

    @Test func aClosingTabCannotHostEvenWithALivePage() {
        let space = UUID()
        let tab = UUID()
        #expect(backdrop(tab: tab, open: false, space: space).archivePreviewRoute == nil)
        #expect(backdrop(tab: tab, open: false, page: true, space: space).archivePreviewRoute == nil)
    }

    @Test func noTabAndNoStartPageHasNoHost() {
        let space = UUID()
        #expect(backdrop(tab: nil, space: space).archivePreviewRoute == nil)
        #expect(PeekBackdrop.hostID(currentTabID: nil, showsStartPage: false, activeSpaceID: space) == nil)
    }

    @Test func aSelectedTabAlwaysWinsOverTheSpace() {
        let space = UUID()
        let tab = UUID()
        #expect(PeekBackdrop.hostID(currentTabID: tab, showsStartPage: true, activeSpaceID: space) == tab)
    }
}
