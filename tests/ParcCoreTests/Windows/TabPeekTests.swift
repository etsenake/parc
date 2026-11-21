import Foundation
import Testing
@testable import ParcCore

private final class FakePage {
    let identifier: String
    init(_ identifier: String) { self.identifier = identifier }
}

private struct FakeWindow {
    var pane: FakePage?
    var card: FakePage?
    var cardShown = false
    var exits = 0
    var created = 0

    mutating func apply(_ effects: [TabPeekSession.Effect]) {
        for effect in effects {
            switch effect {
            case .createPage:
                #expect(pane == nil && card == nil, "a page is created only for a tab that has none")
                created += 1
                pane = FakePage("created-\(created)")
            case .presentPage(let id):
                #expect(pane?.identifier == id && card == nil, "the card takes the tab's own page \(id)")
                card = pane; pane = nil; cardShown = true
            case .returnPage(let id):
                #expect(card?.identifier == id && pane == nil, "the tab gets back the page \(id) from the card")
                pane = card; card = nil
            case .exit:
                #expect(cardShown, "only a shown card plays the dismissal motion")
                exits += 1
            case .finish:
                #expect(card == nil, "a card is never removed while it still holds the tab's page")
                cardShown = false
            }
        }
    }
}

struct TabPeekTests {
    private static let id = UUID()

    private static func plan(_ edit: (inout TabPeekCandidate) -> Void) -> Result<TabPeekPlan, TabPeekRefusal> {
        var candidate = TabPeekCandidate(tabID: id, page: .live("page-a"))
        edit(&candidate)
        return TabPeekAdmission.plan(candidate)
    }

    @Test func aLiveTabPresentsItsOwnPage() {
        #expect(Self.plan { _ in } == .success(.present("page-a")))
    }

    @Test func anUnloadedTabLoadsStraightIntoThePeek() {
        #expect(Self.plan { $0.page = .unloaded(loadable: true); $0.holder = .nobody } == .success(.load))
    }

    @Test func anUnloadedTabClaimedHereLoadsToo() {
        #expect(Self.plan { $0.page = .unloaded(loadable: true) } == .success(.load))
    }

    @Test func aTabWithNoAddressCannotLoad() {
        #expect(Self.plan { $0.page = .unloaded(loadable: false) } == .failure(.unloadable))
    }

    @Test func aPageStillBeingCreatedIsLeftAlone() {
        #expect(Self.plan { $0.page = .creating } == .failure(.busy))
    }

    @Test func aFailedPageOpensNormallyNotInPeek() {
        #expect(Self.plan { $0.page = .failed } == .failure(.failed))
    }

    @Test func aClosedPageCannotBeShown() {
        #expect(Self.plan { $0.page = .closed } == .failure(.closed))
    }

    @Test func aPageInAnotherWindowMovesHereThroughTheTransferFirst() {
        #expect(Self.plan { $0.holder = .elsewhere(movable: true) } == .success(.moveHere))
    }

    @Test func aPageAnotherWindowCannotGiveUpIsRefused() {
        #expect(Self.plan { $0.holder = .elsewhere(movable: false) } == .failure(.heldElsewhere))
    }

    @Test func aTabAlreadyOnScreenIsNotPeeked() {
        #expect(Self.plan { $0.onScreen = true } == .failure(.onScreen))
    }

    @Test func aClosingOrMovingTabIsRefused() {
        #expect(Self.plan { $0.busy = true } == .failure(.busy))
    }

    @Test func notesAndEaselsAreNotWebPages() {
        #expect(Self.plan { $0.document = true } == .failure(.document))
    }

    @Test func aTabFromAnotherSpaceIsRefused() {
        #expect(Self.plan { $0.inActiveSpace = false } == .failure(.space))
    }

    @Test func aTabFromAnotherProfileIsRefused() {
        #expect(Self.plan { $0.profileMatches = false } == .failure(.profile))
    }

    @Test func thereMustBeAPageToFloatOver() {
        #expect(Self.plan { $0.parentCanHost = false } == .failure(.parent))
    }

    @Test func aBusyWindowRefuses() {
        #expect(Self.plan { $0.windowAdmits = false } == .failure(.window))
    }

    @Test func askingAgainForTheShownTabIsANoOp() {
        let id = Self.id
        #expect(Self.plan { $0.windowAdmits = false; $0.shown = .tab(id, canClose: false) } == .success(.alreadyShown))
    }

    @Test func aShownPeekIsReplaced() {
        #expect(Self.plan { $0.shown = .peek(canClose: true) } == .success(.replaceShown))
    }

    @Test func anotherTabsPeekIsReplaced() {
        #expect(Self.plan { $0.shown = .tab(UUID(), canClose: true) } == .success(.replaceShown))
    }

    @Test func aPeekThatCannotCloseNowKeepsItsPlace() {
        #expect(Self.plan { $0.shown = .peek(canClose: false) } == .failure(.peekBusy))
    }

    @Test func aShownPeekIsNeverClosedForATabThatCannotOpenAnyway() {
        #expect(Self.plan { $0.shown = .peek(canClose: true); $0.page = .closed } == .failure(.closed))
    }

    @Test func theMenuOffersOpenInPeekForALiveTab() {
        #expect(TabPeekAdmission.offers(TabPeekCandidate(tabID: Self.id, page: .live("page-a"))))
    }

    @Test func theMenuDoesNotOfferTheTabAlreadyInPeek() {
        var offered = TabPeekCandidate(tabID: Self.id, page: .live("page-a"))
        offered.shown = .tab(Self.id, canClose: true)
        #expect(!TabPeekAdmission.offers(offered))
    }

    @Test func theMenuDoesNotOfferARefusedTab() {
        var offered = TabPeekCandidate(tabID: Self.id, page: .live("page-a"))
        offered.onScreen = true
        #expect(!TabPeekAdmission.offers(offered))
    }

    @Test(arguments: 0..<3)
    func onlyPresentAndLoadStartASession(_ index: Int) {
        let plans: [TabPeekPlan] = [.moveHere, .replaceShown, .alreadyShown]
        #expect(TabPeekSession(tabID: Self.id, plan: plans[index]) == nil)
    }

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

    private static func liveSession() throws -> (page: FakePage, window: FakeWindow, session: TabPeekSession) {
        let original = FakePage("page-a")
        var window = FakeWindow(pane: original)
        let session = try #require(TabPeekSession(tabID: UUID(), plan: .present(original.identifier)))
        window.apply(session.opening)
        return (original, window, session)
    }

    @Test func theCardShowsTheVerySamePageObject() throws {
        let s = try Self.liveSession()
        #expect(s.window.card === s.page)
        #expect(s.window.pane == nil)
    }

    @Test func openingALiveTabLoadsNothing() throws {
        let s = try Self.liveSession()
        #expect(s.session.holdsPage)
        #expect(s.session.loads == 0)
    }

    @Test func closingThePeekHandsTheSamePageBackToItsTab() throws {
        var s = try Self.liveSession()
        s.window.apply(s.session.returnRequested())
        #expect(s.window.pane === s.page)
        #expect(s.window.card == nil)
        #expect(!s.window.cardShown)
    }

    @Test func theRoundTripNeverLoadsOrCreatesAPage() throws {
        var s = try Self.liveSession()
        s.window.apply(s.session.returnRequested())
        #expect(s.session.loads == 0)
        #expect(s.window.created == 0)
    }

    @Test func aFinishedSessionIgnoresLateRequests() throws {
        var s = try Self.liveSession()
        s.window.apply(s.session.returnRequested())
        #expect(s.session.returnRequested().isEmpty)
        #expect(s.session.promote().isEmpty)
        #expect(s.session.pageReady("page-a").isEmpty)
    }

    @Test func aShownTabPeekPresentsItsPageAsAPeek() throws {
        let s = try Self.liveSession()
        #expect(s.session.holdsPage)
    }

    @Test func thePageReturnsBeforeTheCardPlaysItsExit() throws {
        var s = try Self.liveSession()
        #expect(s.session.resolve(.promote) == [.returnPage("page-a"), .exit])
    }

    @Test func anExpandedTabPeekStopsPresentingItsPageInTheSameStep() throws {
        var s = try Self.liveSession()
        _ = s.session.resolve(.promote)
        #expect(!s.session.holdsPage)
    }

    @Test func theTabShowsItsPageWhileTheEmptyCardExits() throws {
        var s = try Self.liveSession()
        s.window.apply(s.session.resolve(.promote))
        #expect(s.window.pane === s.page)
        #expect(s.window.cardShown)
        #expect(s.window.exits == 1)
    }

    @Test func aPromotingSessionCannotHandThePageBackTwice() throws {
        var s = try Self.liveSession()
        _ = s.session.resolve(.promote)
        #expect(s.session.returnRequested().isEmpty)
        #expect(s.session.resolve(.putBack).isEmpty)
    }

    @Test func theExitsEndRemovesTheCard() throws {
        var s = try Self.liveSession()
        s.window.apply(s.session.resolve(.promote))
        s.window.apply(s.session.exitFinished())
        #expect(!s.window.cardShown)
        #expect(s.session.phase == .finished)
    }

    @Test func aLateExitTimerDoesNothing() throws {
        var s = try Self.liveSession()
        s.window.apply(s.session.resolve(.promote))
        _ = s.session.exitFinished()
        #expect(s.session.exitFinished().isEmpty)
    }

    @Test func promotionNeverReloads() throws {
        var s = try Self.liveSession()
        s.window.apply(s.session.resolve(.promote))
        #expect(s.window.created == 0)
        #expect(s.session.loads == 0)
    }

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
        var s = try Self.liveSession()
        s.window.apply(s.session.resolve(.keep))
        #expect(s.window.card === s.page)
    }

    @Test func aForcedReturnPutsThePageBackWithoutAMotion() throws {
        var s = try Self.liveSession()
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

    private static func refusal(_ edit: (inout TabPeekSplitFacts) -> Void) -> TabPeekSplitRefusal? {
        var facts = TabPeekSplitFacts()
        edit(&facts)
        return TabPeekSplit.refusal(facts)
    }

    @Test func aTabBackedPeekOverASinglePageOffersSplitView() {
        #expect(Self.refusal { _ in } == nil)
    }

    @Test func aPeekOverAThreePageSplitStillOffersSplitView() {
        #expect(Self.refusal { $0.panes = 3 } == nil)
    }

    @Test func fourPagesIsAsFullAsSplitViewGets() {
        #expect(Self.refusal { $0.panes = 4 } == .full)
    }

    @Test func aFullSplitSaysSoEvenWhileTheWindowIsBusy() {
        #expect(Self.refusal { $0.panes = 4; $0.windowReady = false } == .full)
    }

    @Test func aPeekThatIsNotTheWindowsLivePeekCannotSplit() {
        #expect(Self.refusal { $0.peekInteractive = false } == .unavailable)
    }

    @Test func aTabThatIsClosingMovingOrGoneCannotJoinTheSplit() {
        #expect(Self.refusal { $0.tabUsable = false } == .unavailable)
    }

    @Test func thePageUnderneathMustBeOnScreenToSplitWith() {
        #expect(Self.refusal { $0.parentSelected = false } == .unavailable)
    }

    @Test func aPopupFullScreenPageOrOpenLibraryRefuses() {
        #expect(Self.refusal { $0.windowReady = false } == .unavailable)
    }

    @Test func aPeekThatCannotActIsUnavailableBeforeItIsFull() {
        #expect(Self.refusal { $0.peekInteractive = false; $0.panes = 4 } == .unavailable)
    }

    @Test func theFullTooltipSaysWhy() {
        #expect(TabPeekSplitRefusal.full.toolTip.contains("four pages"))
    }

    @Test func eachRefusalHasItsOwnTooltip() {
        #expect(!TabPeekSplitRefusal.unavailable.toolTip.isEmpty)
        #expect(TabPeekSplitRefusal.unavailable.toolTip != TabPeekSplitRefusal.full.toolTip)
    }

    @Test func theShownPeekClosesFirst() {
        let candidate = TabPeekCandidate(tabID: Self.id, page: .live("page-a"), shown: .peek(canClose: true))
        #expect(TabPeekAdmission.plan(candidate) == .success(.replaceShown))
    }

    @Test func onceItIsGoneTheTabsPageOpensInTheSinglePeek() {
        let candidate = TabPeekCandidate(tabID: Self.id, page: .live("page-a"), shown: .none)
        #expect(TabPeekAdmission.plan(candidate) == .success(.present("page-a")))
    }

    @Test func anotherTabsPeekReturnsFirst() {
        let candidate = TabPeekCandidate(tabID: Self.id, page: .unloaded(loadable: true), shown: .tab(UUID(), canClose: true))
        #expect(TabPeekAdmission.plan(candidate) == .success(.replaceShown))
    }
}
