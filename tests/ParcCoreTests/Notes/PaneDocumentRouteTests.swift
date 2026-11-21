import Foundation
import Testing
@testable import ParcCore

@MainActor struct PaneDocumentRouteTests {
    @Test func singlePane() throws {
        for page in [true, false] {
            #expect(PaneDocumentRoute.routes(paneCount: 1, paneHoldsWebPage: page) == [.newTab], "outside a split, a note or Easel keeps opening as its own tab")
        }
    }

    @Test func stackedPanes() throws {
        var tab = BrowserTab(id: UUID(), spaceID: UUID(), profileID: UUID(), url: "https://example.test/", title: "Page",
                             kind: .today, createdAt: Date(), lastAccessed: Date(),
                             savedURL: "https://example.test/", savedTitle: "Page")
        for title in ["One", "Two", "Three"] {
            let hoisted17 = tab.openDocumentVisit(.easel(UUID()), title: title)
            #expect(hoisted17, "a pane over a page stacks another document")
            #expect(PaneDocumentRoute.routes(paneCount: 2, paneHoldsWebPage: tab.showsNoteOverPage) == [.overPage, .newTab], "at every depth the pane still holds its page, so the next document stacks on top")
        }
        #expect(tab.stepNoteVisit(by: -3) && !tab.showsNoteOverPage && tab.hasVisitStepAhead, "Back through every document returns the pane to its page")
    }

    @Test func splitPanes() throws {
        for count in 2...4 {
            #expect(PaneDocumentRoute.routes(paneCount: count, paneHoldsWebPage: true) == [.overPage, .newTab], "a note or Easel opens over a pane's web page so Back returns to it, and never replaces the page when it can't")
            #expect(PaneDocumentRoute.routes(paneCount: count, paneHoldsWebPage: false) == [.replacePane], "a note or Easel takes a pane showing a note, Easel or empty page with no page behind it")
        }
    }
}
