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
            try expect(PaneDocumentRoute.routes(paneCount: 1, paneHoldsWebPage: page) == [.newTab],
                       "outside a split, a note or Easel keeps opening as its own tab")
        }
    }

    static func splitPanes() throws {
        for count in 2...4 {
            try expect(PaneDocumentRoute.routes(paneCount: count, paneHoldsWebPage: true) == [.overPage, .newTab],
                       "a note or Easel opens over a pane's web page so Back returns to it, and never replaces the page when it can't")
            try expect(PaneDocumentRoute.routes(paneCount: count, paneHoldsWebPage: false) == [.replacePane],
                       "a note or Easel takes a pane showing a note, Easel or empty page with no page behind it")
        }
    }
}
