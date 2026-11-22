import Foundation
import Testing
@testable import ParcCore

struct TabPeekLoadingAndDepartureTests {
    private typealias FakePage = TabPeekTestsSupport.FakePage
    private typealias FakeWindow = TabPeekTestsSupport.FakeWindow

    private static func loadingSession() throws -> (window: FakeWindow, session: TabPeekSession) {
        var window = FakeWindow()
        let session = try #require(TabPeekSession(tabID: UUID(), plan: .load))
        window.apply(session.opening)
        return (window, session)
    }

    @Test func theTabsPageIsCreatedOnceWhenLoading() throws {
        let s = try Self.loadingSession()
        #expect(s.window.created == 1)
        #expect(s.session.loads == 1)
        #expect(!s.window.cardShown)
    }

    @Test func nothingReturnsBeforeThePageExists() throws {
        var s = try Self.loadingSession()
        #expect(s.session.returnRequested().isEmpty)
        #expect(s.session.promote().isEmpty)
    }

    @Test func theNewPageGoesStraightIntoTheCard() throws {
        var s = try Self.loadingSession()
        let created = try #require(s.window.pane)
        s.window.apply(s.session.pageReady(created.identifier))
        #expect(s.window.card === created)
        #expect(s.window.cardShown)
    }

    @Test func aSecondReadySignalIsIgnored() throws {
        var s = try Self.loadingSession()
        let created = try #require(s.window.pane)
        s.window.apply(s.session.pageReady(created.identifier))
        #expect(s.session.pageReady("page-z").isEmpty)
    }

    @Test func theLoadedPageStaysTheTabsPageAfterwards() throws {
        var s = try Self.loadingSession()
        let created = try #require(s.window.pane)
        s.window.apply(s.session.pageReady(created.identifier))
        s.window.apply(s.session.returnRequested())
        #expect(s.window.pane === created)
        #expect(s.window.created == 1)
    }

    @Test func leavingBeforeThePageIsReadyAbandonsThePeekAndLeavesThePageWithItsTab() throws {
        var s = try Self.loadingSession()
        #expect(s.session.resolve(.putBack).isEmpty)
        #expect(s.session.phase == .finished)
    }

    @Test func aPageThatArrivesAfterAbandonmentNeverOpensACard() throws {
        var s = try Self.loadingSession()
        _ = s.session.resolve(.putBack)
        #expect(s.session.pageReady("created-1").isEmpty)
        #expect(s.window.pane != nil)
        #expect(!s.window.cardShown)
    }

    @Test func openingTheTabNormallyWhileItLoadsJustShowsItInItsTab() throws {
        var selected = try #require(TabPeekSession(tabID: UUID(), plan: .load))
        #expect(selected.resolve(.promote).isEmpty)
        #expect(selected.phase == .finished)
    }

    @Test func keepChangesNothing() throws {
        var s = try TabPeekTestsSupport.liveSession()
        s.window.apply(s.session.resolve(.keep))
        #expect(s.window.card === s.page)
    }

    @Test func aForcedReturnPutsThePageBackWithoutAMotion() throws {
        var s = try TabPeekTestsSupport.liveSession()
        s.window.apply(s.session.resolve(.putBack))
        #expect(s.window.pane === s.page)
        #expect(!s.window.cardShown)
        #expect(s.window.exits == 0)
    }

    @Test func aPageThatClosedInTheCardJustRemovesTheCard() throws {
        var closing = FakeWindow(pane: FakePage("page-b"))
        var closed = try #require(TabPeekSession(tabID: UUID(), plan: .present("page-b")))
        closing.apply(closed.opening)
        closing.card = nil
        closing.apply(closed.resolve(.drop))
        #expect(!closing.cardShown)
        #expect(closing.pane == nil)
        #expect(closed.pageClosed().isEmpty)
    }

    private static func shownSession() throws -> (session: TabPeekSession, window: FakeWindow) {
        var window = FakeWindow(pane: FakePage("page-a"))
        let session = try #require(TabPeekSession(tabID: UUID(), plan: .present("page-a")))
        window.apply(session.opening)
        return (session, window)
    }

    @Test func aShownCardsHandBackReturnsThePage() throws {
        var control = try Self.shownSession()
        #expect(!control.session.returnRequested().isEmpty)
    }

    enum Departure: CaseIterable, Sendable, CustomTestStringConvertible {
        case handBack, forcedReturn, pageClosing, pageDropping, openingTab

        var testDescription: String {
            switch self {
            case .handBack: return "its hand-back"
            case .forcedReturn: return "a forced return"
            case .pageClosing: return "its page closing"
            case .pageDropping: return "its page dropping out of the card"
            case .openingTab: return "opening its tab"
            }
        }

        var emptiesCard: Bool { self == .pageClosing || self == .pageDropping }

        func leave(_ session: inout TabPeekSession) -> [TabPeekSession.Effect] {
            switch self {
            case .handBack: return session.returnRequested()
            case .forcedReturn: return session.resolve(.putBack)
            case .pageClosing: return session.pageClosed()
            case .pageDropping: return session.resolve(.drop)
            case .openingTab: return session.resolve(.promote)
            }
        }
    }

    private static func departed(_ way: Departure) throws -> (session: TabPeekSession, window: FakeWindow, effects: [TabPeekSession.Effect]) {
        var (session, window) = try shownSession()
        if way.emptiesCard { window.card = nil }
        let effects = way.leave(&session)
        window.apply(effects)
        return (session, window, effects)
    }

    @Test(arguments: Departure.allCases)
    func leavingEndsTheShownSession(_ way: Departure) throws {
        #expect(!(try Self.departed(way)).session.holdsPage)
    }

    @Test(arguments: Departure.allCases)
    func leavingRemovesTheCardOrPlaysItsExitInTheSameStep(_ way: Departure) throws {
        let effects = try Self.departed(way).effects
        #expect(effects.contains(.finish) || effects.contains(.exit))
    }

    @Test(arguments: Departure.allCases)
    func leavingNeverLeavesThePageInTheCard(_ way: Departure) throws {
        #expect(try Self.departed(way).window.card == nil)
    }

    @Test(arguments: Departure.allCases)
    func aLateHandBackAfterLeavingHasNothingToReturn(_ way: Departure) throws {
        var d = try Self.departed(way)
        #expect(d.session.returnRequested().isEmpty)
    }

    @Test(arguments: Departure.allCases)
    func theCardIsGoneOnceAnyExitEnds(_ way: Departure) throws {
        var d = try Self.departed(way)
        d.window.apply(d.session.exitFinished())
        #expect(!d.window.cardShown)
    }
}
