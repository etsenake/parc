import Foundation

@main @MainActor
struct PaneDocumentRouteTests {
    static var assertions = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        assertions += 1
        if try !value() { failTest(message) }
    }

    static func main() {
        exitOnFailure {
            try singlePane()
            try splitPanes()
            print("PaneDocumentRoute: \(assertions) assertions passed")
        }
    }

    static func singlePane() throws {
        for page in [true, false] {
            for note in [true, false] {
                try expect(PaneDocumentRoute.routes(paneCount: 1, paneShowsWebPage: page, isNote: note) == [.newTab],
                           "outside a split, a document keeps opening as its own tab")
            }
        }
    }

    static func splitPanes() throws {
        for count in 2...4 {
            try expect(PaneDocumentRoute.routes(paneCount: count, paneShowsWebPage: true, isNote: true) == [.overPage, .newTab],
                       "a note opens over a pane's web page so Back returns to it, and never replaces the page when it can't")
            try expect(PaneDocumentRoute.routes(paneCount: count, paneShowsWebPage: true, isNote: false) == [.replacePane],
                       "an Easel takes a web page's pane like typing its address")
            try expect(PaneDocumentRoute.routes(paneCount: count, paneShowsWebPage: false, isNote: true) == [.replacePane],
                       "a note takes a pane showing a note, Easel or empty page")
            try expect(PaneDocumentRoute.routes(paneCount: count, paneShowsWebPage: false, isNote: false) == [.replacePane],
                       "an Easel takes a pane showing a note, Easel or empty page")
        }
    }
}
