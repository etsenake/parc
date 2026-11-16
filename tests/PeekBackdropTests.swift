import Foundation

@main struct PeekBackdropTests {
    static var checks = 0
    static func expect(_ value: Bool, _ message: String) {
        checks += 1
        precondition(value, message)
    }

    static func backdrop(tab: UUID?, open: Bool = true, document: Bool = false, wrapper: Bool = false, page: Bool = false,
                         startPage: Bool = false, space: UUID) -> PeekBackdrop {
        PeekBackdrop(currentTabID: tab, tabIsOpen: open, isDocument: document, hasPageWrapper: wrapper, hasLivePage: page,
                     showsStartPage: startPage, activeSpaceID: space)
    }

    static func shownOver(_ backdrop: PeekBackdrop, tab: UUID?, startPage: Bool, space: UUID) -> Bool {
        guard case .overWindow(let host)? = backdrop.archivePreviewRoute else { return false }
        return PeekBackdrop.hostID(currentTabID: tab, showsStartPage: startPage, activeSpaceID: space) == host
    }

    static func main() {
        webPage()
        documents()
        startPageAndEmptyWindow()
        refusals()
        print("PeekBackdropTests: \(checks) checks passed")
    }

    static func webPage() {
        let space = UUID(), tab = UUID()
        let behind = backdrop(tab: tab, wrapper: true, page: true, space: space)
        expect(behind == .webPage(tabID: tab), "a live web page is the backdrop")
        expect(behind.archivePreviewRoute == .fromPage, "a web page behind keeps opening the preview from that page")
    }

    static func documents() {
        let space = UUID(), note = UUID(), easel = UUID()
        let overNote = backdrop(tab: note, document: true, space: space)
        expect(overNote.archivePreviewRoute == .overWindow(hostID: note), "the window hosts the preview over a Note")
        expect(shownOver(overNote, tab: note, startPage: false, space: space), "the Note's preview is the window's shown Peek")
        let overEasel = backdrop(tab: easel, document: true, space: space)
        expect(overEasel.archivePreviewRoute == .overWindow(hostID: easel), "the window hosts the preview over an Easel")
        expect(shownOver(overEasel, tab: easel, startPage: false, space: space), "the Easel's preview is the window's shown Peek")
        expect(!shownOver(overNote, tab: easel, startPage: false, space: space),
               "switching to another document hides the first document's preview")
        let web = UUID()
        let splitFocusedOnNote = backdrop(tab: note, document: true, space: space)
        expect(splitFocusedOnNote.archivePreviewRoute == .overWindow(hostID: note),
               "a split whose focused pane is a Note hosts the preview over that pane")
        expect(!shownOver(splitFocusedOnNote, tab: web, startPage: false, space: space),
               "focusing the split's web pane hides the Note-hosted preview")
    }

    static func startPageAndEmptyWindow() {
        let space = UUID(), other = UUID()
        let start = backdrop(tab: nil, startPage: true, space: space)
        expect(start == .startPage(spaceID: space), "an empty Space shows its start page")
        expect(start.archivePreviewRoute == .overWindow(hostID: space), "the window hosts the preview over the start page")
        expect(shownOver(start, tab: nil, startPage: true, space: space), "the start page's preview is the shown Peek")
        expect(!shownOver(start, tab: nil, startPage: true, space: other),
               "another Space's start page doesn't show this Space's preview")
        expect(!shownOver(start, tab: UUID(), startPage: false, space: space), "selecting a tab hides the start-page preview")
        let window = UUID()
        let emptyWindow = backdrop(tab: nil, startPage: true, space: window)
        expect(emptyWindow.archivePreviewRoute == .overWindow(hostID: window), "an empty window hosts the preview over its start page")
        expect(shownOver(emptyWindow, tab: nil, startPage: true, space: window), "the empty window's preview is the shown Peek")
    }

    static func refusals() {
        let space = UUID(), tab = UUID()
        expect(backdrop(tab: tab, wrapper: true, space: space).archivePreviewRoute == nil,
               "a web tab whose page isn't live yet can't host, since the page would later hide the preview")
        expect(backdrop(tab: tab, space: space).archivePreviewRoute == nil, "a web tab with no page at all can't host")
        expect(backdrop(tab: tab, document: true, wrapper: true, space: space).archivePreviewRoute == nil,
               "a document that somehow holds a page wrapper isn't treated as pageless")
        expect(backdrop(tab: tab, open: false, document: true, space: space).archivePreviewRoute == nil,
               "a closing or archived tab can't host")
        expect(backdrop(tab: nil, space: space).archivePreviewRoute == nil, "no tab and no start page, such as creating a Space")
        expect(PeekBackdrop.hostID(currentTabID: nil, showsStartPage: false, activeSpaceID: space) == nil,
               "without a tab or start page no Peek is shown")
        expect(PeekBackdrop.hostID(currentTabID: tab, showsStartPage: true, activeSpaceID: space) == tab,
               "a selected tab always wins over the Space")
    }
}
