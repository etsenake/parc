import Foundation
import Testing
@testable import ParcCore

private final class FakePage {}

struct PeekBackdropTests {
    static func backdrop(tab: UUID?, open: Bool = true, page: Bool = false, startPage: Bool = false, space: UUID) -> PeekBackdrop {
        PeekBackdrop(currentTabID: tab, tabIsOpen: open, hasLivePage: page, showsStartPage: startPage, activeSpaceID: space)
    }

    static func shownOver(_ backdrop: PeekBackdrop, tab: UUID?, startPage: Bool, space: UUID) -> Bool {
        guard case .overWindow(let host)? = backdrop.archivePreviewRoute else { return false }
        return PeekBackdrop.hostID(currentTabID: tab, showsStartPage: startPage, activeSpaceID: space) == host
    }
    @Test static func loadedWebPage() {
        let space = UUID(), tab = UUID()
        let behind = backdrop(tab: tab, page: true, space: space)
        #expect(behind == .webPage(tabID: tab), "a live web page is the backdrop")
        #expect(behind.archivePreviewRoute == .fromPage, "a loaded web tab keeps opening the preview from its page, as today")
        let page = FakePage(), replacement = FakePage()
        #expect(PeekBackdrop.peekStays(parent: page, hostPage: page), "a Peek stays over its own parent page")
        #expect(!PeekBackdrop.peekStays(parent: page, hostPage: replacement), "a Peek never shows over a page that replaced its parent")
        #expect(!PeekBackdrop.peekStays(parent: page, hostPage: nil), "a Peek whose parent page went away isn't shown")
    }

    @Test static func unloadedWebTab() {
        let space = UUID(), tab = UUID()
        let opening = backdrop(tab: tab, space: space)
        #expect(opening == .pagelessTab(tabID: tab), "a web tab whose page is still opening, blank or failed has no page yet")
        #expect(opening.archivePreviewRoute == .overWindow(hostID: tab), "the window hosts the preview, owned by that tab")
        #expect(shownOver(opening, tab: tab, startPage: false, space: space), "the preview is that tab's shown Peek")
        let arrived = FakePage()
        #expect(PeekBackdrop.peekStays(parent: nil, hostPage: nil), "the tab-owned preview shows while the tab has no page")
        #expect(PeekBackdrop.peekStays(parent: nil, hostPage: arrived),
               "the tab-owned preview stays shown the moment the tab's page arrives, until it adopts that page as its parent")
        #expect(PeekBackdrop.peekStays(parent: arrived, hostPage: arrived), "once adopted, it is an ordinary Peek over that page")
        #expect(!shownOver(opening, tab: UUID(), startPage: false, space: space), "switching tabs hides the tab-owned preview")
    }

    @Test static func documents() {
        let space = UUID(), note = UUID(), easel = UUID()
        let overNote = backdrop(tab: note, space: space)
        #expect(overNote.archivePreviewRoute == .overWindow(hostID: note), "the window hosts the preview over a Note")
        #expect(shownOver(overNote, tab: note, startPage: false, space: space), "the Note's preview is the window's shown Peek")
        let overEasel = backdrop(tab: easel, space: space)
        #expect(overEasel.archivePreviewRoute == .overWindow(hostID: easel), "the window hosts the preview over an Easel")
        #expect(shownOver(overEasel, tab: easel, startPage: false, space: space), "the Easel's preview is the window's shown Peek")
        #expect(!shownOver(overNote, tab: easel, startPage: false, space: space),
               "switching to another document hides the first document's preview")
        let web = UUID()
        #expect(!shownOver(overNote, tab: web, startPage: false, space: space),
               "focusing a split's web pane hides the preview owned by the focused Note")
    }

    @Test static func startPageAndEmptyWindow() {
        let space = UUID(), other = UUID()
        let start = backdrop(tab: nil, startPage: true, space: space)
        #expect(start == .startPage(spaceID: space), "an empty Space shows its start page")
        #expect(start.archivePreviewRoute == .overWindow(hostID: space), "the window hosts the preview over the start page")
        #expect(shownOver(start, tab: nil, startPage: true, space: space), "the start page's preview is the shown Peek")
        #expect(!shownOver(start, tab: nil, startPage: true, space: other),
               "another Space's start page doesn't show this Space's preview")
        #expect(!shownOver(start, tab: UUID(), startPage: false, space: space), "selecting a tab hides the start-page preview")
        let window = UUID()
        let emptyWindow = backdrop(tab: nil, startPage: true, space: window)
        #expect(emptyWindow.archivePreviewRoute == .overWindow(hostID: window), "an empty window hosts the preview over its start page")
        #expect(shownOver(emptyWindow, tab: nil, startPage: true, space: window), "the empty window's preview is the shown Peek")
    }

    @Test static func refusals() {
        let space = UUID(), tab = UUID()
        #expect(backdrop(tab: tab, open: false, space: space).archivePreviewRoute == nil, "a closing or archived tab can't host")
        #expect(backdrop(tab: tab, open: false, page: true, space: space).archivePreviewRoute == nil,
               "a closing tab can't host even with a live page")
        #expect(backdrop(tab: nil, space: space).archivePreviewRoute == nil, "no tab and no start page, such as creating a Space")
        #expect(PeekBackdrop.hostID(currentTabID: nil, showsStartPage: false, activeSpaceID: space) == nil,
               "without a tab or start page no Peek is shown")
        #expect(PeekBackdrop.hostID(currentTabID: tab, showsStartPage: true, activeSpaceID: space) == tab,
               "a selected tab always wins over the Space")
    }
}
