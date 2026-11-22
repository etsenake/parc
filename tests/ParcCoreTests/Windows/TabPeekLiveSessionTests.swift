import Foundation
import Testing
@testable import ParcCore

struct TabPeekLiveSessionTests {
    private static func resolve(_ edit: (inout TabPeekHoldFacts) -> Void) -> TabPeekResolution {
        var facts = TabPeekHoldFacts()
        edit(&facts)
        return TabPeekHold.resolve(facts)
    }

    @Test func aSteadyPeekStays() {
        #expect(Self.resolve { _ in } == .keep)
    }

    @Test func openingTheTabNormallyPromotesThePeek() {
        #expect(Self.resolve { $0.tabDisplayed = true } == .promote)
    }

    @Test func leavingThePageUnderneathPutsTheTabsPageBack() {
        #expect(Self.resolve { $0.parentCurrent = false } == .putBack)
    }

    @Test func aTabThatIsClosingOrMovingGetsItsPageBackFirst() {
        #expect(Self.resolve { $0.tabUsable = false } == .putBack)
    }

    @Test func anUnusableTabIsNeverPromoted() {
        #expect(Self.resolve { $0.tabUsable = false; $0.tabDisplayed = true } == .putBack)
    }

    @Test func aClosingWindowPutsThePageBack() {
        #expect(Self.resolve { $0.windowOpen = false; $0.tabDisplayed = true } == .putBack)
    }

    @Test func aPageThatLeftTheCardIsNeverPulledBackByThePeek() {
        #expect(Self.resolve { $0.pageInCard = false; $0.windowOpen = false } == .drop)
    }

    @Test func theCardShowsTheVerySamePageObject() throws {
        let s = try TabPeekTestsSupport.liveSession()
        #expect(s.window.card === s.page)
        #expect(s.window.pane == nil)
    }

    @Test func openingALiveTabLoadsNothing() throws {
        let s = try TabPeekTestsSupport.liveSession()
        #expect(s.session.holdsPage)
        #expect(s.session.loads == 0)
    }

    @Test func closingThePeekHandsTheSamePageBackToItsTab() throws {
        var s = try TabPeekTestsSupport.liveSession()
        s.window.apply(s.session.returnRequested())
        #expect(s.window.pane === s.page)
        #expect(s.window.card == nil)
        #expect(!s.window.cardShown)
    }

    @Test func theRoundTripNeverLoadsOrCreatesAPage() throws {
        var s = try TabPeekTestsSupport.liveSession()
        s.window.apply(s.session.returnRequested())
        #expect(s.session.loads == 0)
        #expect(s.window.created == 0)
    }

    enum LateRequest: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case handBack = "Return to the tab"
        case promote = "Promote to the tab"
        case pageReady = "Page is ready"

        var testDescription: String { rawValue }

        func apply(to session: inout TabPeekSession) -> [TabPeekSession.Effect] {
            switch self {
            case .handBack: session.returnRequested()
            case .promote: session.promote()
            case .pageReady: session.pageReady("page-a")
            }
        }
    }

    @Test(arguments: LateRequest.allCases)
    func aFinishedSessionIgnoresLateRequests(_ request: LateRequest) throws {
        var s = try TabPeekTestsSupport.liveSession()
        s.window.apply(s.session.returnRequested())
        #expect(request.apply(to: &s.session).isEmpty)
    }

    @Test func aShownTabPeekPresentsItsPageAsAPeek() throws {
        let s = try TabPeekTestsSupport.liveSession()
        #expect(s.session.holdsPage)
    }

    @Test func thePageReturnsBeforeTheCardPlaysItsExit() throws {
        var s = try TabPeekTestsSupport.liveSession()
        #expect(s.session.resolve(.promote) == [.returnPage("page-a"), .exit])
    }

    @Test func anExpandedTabPeekStopsPresentingItsPageInTheSameStep() throws {
        var s = try TabPeekTestsSupport.liveSession()
        _ = s.session.resolve(.promote)
        #expect(!s.session.holdsPage)
    }

    @Test func theTabShowsItsPageWhileTheEmptyCardExits() throws {
        var s = try TabPeekTestsSupport.liveSession()
        s.window.apply(s.session.resolve(.promote))
        #expect(s.window.pane === s.page)
        #expect(s.window.cardShown)
        #expect(s.window.exits == 1)
    }

    @Test func aPromotingSessionCannotHandThePageBackTwice() throws {
        var s = try TabPeekTestsSupport.liveSession()
        _ = s.session.resolve(.promote)
        #expect(s.session.returnRequested().isEmpty)
        #expect(s.session.resolve(.putBack).isEmpty)
    }

    @Test func theExitsEndRemovesTheCard() throws {
        var s = try TabPeekTestsSupport.liveSession()
        s.window.apply(s.session.resolve(.promote))
        s.window.apply(s.session.exitFinished())
        #expect(!s.window.cardShown)
        #expect(s.session.phase == .finished)
    }

    @Test func aLateExitTimerDoesNothing() throws {
        var s = try TabPeekTestsSupport.liveSession()
        s.window.apply(s.session.resolve(.promote))
        _ = s.session.exitFinished()
        #expect(s.session.exitFinished().isEmpty)
    }

    @Test func promotionNeverReloads() throws {
        var s = try TabPeekTestsSupport.liveSession()
        s.window.apply(s.session.resolve(.promote))
        #expect(s.window.created == 0)
        #expect(s.session.loads == 0)
    }
}
