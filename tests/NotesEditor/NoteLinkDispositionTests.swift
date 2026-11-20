import Foundation

@main @MainActor
struct NoteLinkDispositionTests {
    static var assertions = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        assertions += 1
        if try !value() { failTest(message) }
    }

    static func main() {
        exitOnFailure {
            try regularWindows()
            try privateAndPopupWindows()
            print("NoteLinkDisposition: \(assertions) assertions passed")
        }
    }

    static func regularWindows() throws {
        try expect(NoteLinkDisposition.inPlace.routes(inRegularWindow: true) == [.overPage, .foregroundTab],
                   "an in-place click opens over the page and only falls back to a foreground tab")
        try expect(NoteLinkDisposition.foregroundTab.routes(inRegularWindow: true) == [.foregroundTab],
                   "a foreground new-tab click never turns into the source page")
        try expect(NoteLinkDisposition.backgroundTab.routes(inRegularWindow: true) == [.backgroundTab],
                   "a background new-tab click stays in the background")
        try expect(NoteLinkDisposition.newWindow.routes(inRegularWindow: true) == [.newWindow],
                   "a new-window click gets its own window")
        for disposition in NoteLinkDisposition.allCases where disposition != .inPlace {
            try expect(!disposition.routes(inRegularWindow: true).contains(.overPage),
                       "only an in-place click may cover the source page")
        }
    }

    static func privateAndPopupWindows() throws {
        for disposition in NoteLinkDisposition.allCases {
            try expect(disposition.routes(inRegularWindow: false) == [.regularWindow],
                       "private and popup windows hand every note link to a regular window")
        }
    }
}
