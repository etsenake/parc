import AppKit
import ParcTestSupport
import Testing
@testable import Parc
@testable import ParcCore

struct ResidentTests {
    private typealias Layout = CommandBarResidentLayout

    @Test(arguments: [
        (false, 0, 0, 64.0), (false, 9, 0, 64), (true, 0, 0, 126), (true, 1, 0, 126),
        (true, 3, 0, 226), (true, 5, 0, 326), (true, 6, 0, 326), (true, 12, 0, 326),
        (true, 2, 40, 216), (false, 0, 40, 104),
    ])
    func resultRowsGrowTheBarDownToItsLimit(expanded: Bool, rows: Int, banner: Int, expected: Double) {
        #expect(Layout.height(expanded: expanded, rows: rows, banner: CGFloat(banner)) == CGFloat(expected))
    }

    @Test(arguments: [(1200.0, 500.0, 126.0, 765.0, 126.0), (520, 500, 126, 520, 126),
                      (765, 200, 326, 765, 200), (765, 40, 326, 765, 64)])
    func theCardStaysCenteredAtTheTopOfItsSlot(width: Double, height: Double, requested: Double,
                                              fittedWidth: Double, fittedHeight: Double) {
        let slot = CGRect(x: 100, y: 50, width: width, height: height)
        let frame = Layout.surfaceFrame(in: slot, height: requested)
        #expect(frame.maxY == slot.maxY)
        #expect(frame.midX == slot.midX)
        #expect(frame.width == CGFloat(fittedWidth))
        #expect(frame.height == CGFloat(fittedHeight))
    }

    @Test(arguments: [("", false, false, true), ("a", false, false, false), ("", true, false, false),
                      ("", false, true, false)])
    func onlyAnOrdinaryEmptyQueryRests(query: String, scoped: Bool, unavailable: Bool, expected: Bool) {
        #expect(Layout.rests(query: query, scoped: scoped, scopeInvalidated: unavailable) == expected)
    }

    @Test(arguments: [
        (0, false, false, true, false, false, false), (0, false, false, false, false, false, false),
        (1, false, false, false, false, false, true), (0, true, false, true, false, false, true),
        (0, false, true, true, false, false, false), (0, false, true, false, false, false, true),
        (0, false, true, true, false, true, true), (3, false, true, true, false, false, true),
        (0, false, false, true, true, false, true),
    ])
    func expansionFollowsTheResultsAndScope(rows: Int, actions: Bool, website: Bool, empty: Bool,
                                             unavailable: Bool, error: Bool, expected: Bool) {
        #expect(Layout.expands(resultCount: rows, actionsScope: actions, websiteScoped: website, inputIsEmpty: empty,
                               scopeInvalidated: unavailable, hasError: error) == expected)
    }

    @Test func theRestingCardUsesItsOwnSkipToken() {
        #expect(Layout.restingToken != CommandBarOpenResultsSkip.sidebarBrowsingToken)
    }

    static let responses: [(CommandBarLifetime.Event, CommandBarLifetime.Response, CommandBarLifetime.Response)] = [
        (.resignedKey(ownAlert: false), .keep, .dismiss), (.resignedKey(ownAlert: true), .keep, .keep),
        (.focusMoved, .keep, .dismiss), (.closing, .dismiss, .dismiss),
        (.miniaturizing, .keep, .dismiss), (.sheetBegan(ownAlert: false), .retireScopeMenu, .dismiss),
        (.sheetBegan(ownAlert: true), .keep, .keep), (.securityChanged, .retireScopeMenu, .dismiss),
        (.appDeactivated, .keep, .dismiss), (.resized, .reposition, .reposition), (.moved, .reposition, .reposition),
        (.ownerInvalid, .keep, .dismiss), (.escape(scoped: true), .leaveScope, .leaveScope),
        (.escape(scoped: false), .reset, .dismissRestoringFocus), (.scopeExitFailed, .reset, .dismissRestoringFocus),
        (.submitted, .resetForAction, .dismissRestoringFocus),
    ]

    @Test(arguments: responses)
    func theResidentBarKeepsItsOwnLifetime(event: CommandBarLifetime.Event, resident: CommandBarLifetime.Response,
                                            palette: CommandBarLifetime.Response) {
        #expect(CommandBarLifetime.response(to: event, resident: true) == resident)
    }

    @Test(arguments: responses)
    func thePaletteKeepsItsOwnLifetime(event: CommandBarLifetime.Event, resident: CommandBarLifetime.Response,
                                        palette: CommandBarLifetime.Response) {
        #expect(CommandBarLifetime.response(to: event, resident: false) == palette)
    }

    @Test(arguments: [(400.0, true), (340.0, false), (200.0, false)])
    @MainActor func onlyTheResidentCardInterceptsThePointer(y: Double, intercepts: Bool) throws {
        let window = CommandBarTestSupport.borderlessWindow(width: 765, height: 420)
        let slot = try #require(window.contentView)
        let defaults = try #require(TestDefaults("Parc.ResidentTests."))
        let shortcuts = KeyboardShortcuts(mainMenu: { nil }, observesKeyboardLayout: false)
        let bar = CommandBar(parent: window, tabs: [], history: [], currentURL: nil, profilePath: "", page: nil,
                             resident: true, shortcuts: shortcuts, privacyDefaults: defaults,
                             makeOmnibox: { _, _, _ in nil }, loadFavicon: { _, _, _ in })
        bar.presentResident(in: slot)
        defer { bar.dismiss(restoreFocus: false) }
        let host = try #require(slot.subviews.last)
        #expect((host.hitTest(NSPoint(x: 380, y: y)) != nil) == intercepts)
    }
}
