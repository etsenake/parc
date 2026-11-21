import Testing
@testable import ParcCore

struct PopupTabHandoffTests {
    typealias Window = PopupTabHandoff.Candidate<Int>
    typealias Choice = PopupTabHandoff.Choice<Int>

    let open = Window(id: 1)
    let blocked = Window(id: 2, admitsHidden: false)
    let minimized = Window(id: 3, isMinimized: true, admitsHidden: false)
    let minimizedUnderSheet = Window(id: 4, isMinimized: true, admitsHidden: false, canRestore: false)
    let otherProfile = Window(id: 5, acceptsTabs: false)
    let privateWindow = Window(id: 6, isPrivate: true, sharesSession: false)
    let otherSession = Window(id: 7, sharesSession: false)

    func choose(private source: Bool = false, _ windows: [Window]) -> Choice {
        PopupTabHandoff.choose(sourceIsPrivate: source, candidates: windows)
    }

    func arrival(source: Bool = true, destination: Bool = true, minimized: Bool = false, admits: Bool = true,
                 wait: Bool = true) -> PopupTabHandoff.Arrival {
        PopupTabHandoff.arrival(sourceCurrent: source, destinationCurrent: destination, isMinimized: minimized,
                                admitsHidden: admits, mayAwaitRestore: wait)
    }

    @Test func anAdmittedMainWindowTakesThePopupsRequest() {
        #expect(choose([open]) == .existing(1))
    }

    @Test func aMainWindowUnderASheetDialogOrSecurityPromptSendsTheRequestToAFreshWindow() {
        #expect(choose([blocked]) == .freshWindow)
    }

    @Test func aBlockedWindowGivesWayToAnotherWindowThatCanTakeTheRequest() {
        #expect(choose([open, blocked]) == .existing(1))
        #expect(choose([blocked, open]) == .existing(1))
    }

    @Test func withTwoAdmittedWindowsTheMostRecentOneIsUsed() {
        #expect(choose([open, Window(id: 8)]) == .existing(8))
    }

    @Test func noMainWindowOpensAFreshOne() {
        #expect(choose([]) == .freshWindow)
    }

    @Test func aWindowOnAnotherProfileOrOutsideThePopupsSessionNeverTakesTheRequest() {
        #expect(choose([otherProfile]) == .freshWindow)
        #expect(choose([otherSession]) == .freshWindow)
    }

    @Test func anOrdinaryMinimizedWindowIsRestoredButOneHoldingASheetIsNot() {
        #expect(choose([minimized]) == .existing(3))
        #expect(choose([minimizedUnderSheet]) == .freshWindow)
    }

    @Test func windowOrderStillDecidesBetweenAMinimizedAndAVisibleWindow() {
        #expect(choose([minimized, open]) == .existing(1))
    }

    @Test func aNormalPopupNeverHandsOffToAPrivateWindow() {
        #expect(choose([open, privateWindow]) == .existing(1))
    }

    @Test func aPrivatePopupAlwaysGetsANewPrivateWindow() {
        #expect(choose(private: true, [open]) == .freshWindow)
        #expect(choose(private: true, [Window(id: 9, isPrivate: true)]) == .freshWindow)
        #expect(choose(private: true, []) == .freshWindow)
    }

    @Test func aWindowStillAdmittedAfterComingForwardReceivesTheTabOrAddress() {
        #expect(arrival() == .deliver)
    }

    @Test func aWindowThatBecameBlockedOrChangedDuringTheHandoffFallsBackToAFreshWindow() {
        #expect(arrival(admits: false) == .freshWindow)
        #expect(arrival(destination: false) == .freshWindow)
    }

    @Test func aPopupWhoseOriginalPageWentAwayDeliversNothing() {
        #expect(arrival(source: false) == .abandon)
        #expect(arrival(source: false, admits: false) == .abandon)
    }

    @Test func aWindowStillRestoringIsWaitedForUnlessItNeverFinished() {
        #expect(arrival(minimized: true, admits: false) == .awaitRestore)
        #expect(arrival(minimized: true, admits: false, wait: false) == .freshWindow)
    }
}
