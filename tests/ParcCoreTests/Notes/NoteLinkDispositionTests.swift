import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteLinkDispositionTests {
    @Test func anInPlaceClickOpensOverThePage() throws {
        #expect(NoteLinkDisposition.inPlace.routes(inRegularWindow: true) == [.overPage, .foregroundTab], "an in-place click opens over the page and only falls back to a foreground tab")
        #expect(NoteLinkDisposition.foregroundTab.routes(inRegularWindow: true) == [.foregroundTab], "a foreground new-tab click never turns into the source page")
        #expect(NoteLinkDisposition.backgroundTab.routes(inRegularWindow: true) == [.backgroundTab], "a background new-tab click stays in the background")
        #expect(NoteLinkDisposition.newWindow.routes(inRegularWindow: true) == [.newWindow], "a new-window click gets its own window")
        for disposition in NoteLinkDisposition.allCases where disposition != .inPlace {
            #expect(!disposition.routes(inRegularWindow: true).contains(.overPage), "only an in-place click may cover the source page")
        }
    }

    @Test func privateAndPopupWindows() throws {
        for disposition in NoteLinkDisposition.allCases {
            #expect(disposition.routes(inRegularWindow: false) == [.regularWindow], "private and popup windows hand every note link to a regular window")
        }
    }
}
