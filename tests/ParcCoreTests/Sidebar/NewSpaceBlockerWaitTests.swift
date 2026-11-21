import Testing
@testable import ParcCore

struct NewSpaceBlockerWaitTests {
    typealias Wait = NewSpaceBlockerWait

    @Test func aPeekAskingForConfirmationKeepsNewSpaceWaitingWithoutUsingAttempts() {
        #expect(Wait.next(peek: .awaitingConfirmation, confirmationShown: true, attemptsLeft: 0) == .waitForConfirmation)
    }

    @Test func aFreshConfirmationIsWaitedOn() {
        #expect(Wait.next(peek: .awaitingConfirmation, confirmationShown: false, attemptsLeft: 40) == .waitForConfirmation)
    }

    @Test func aPeekThatStoppedAskingWithoutClosingMeansThePersonDeclined() {
        #expect(Wait.next(peek: .open, confirmationShown: true, attemptsLeft: 40) == .giveUp)
    }

    @Test func aConfirmedPeekThatIsClosingLetsNewSpaceContinue() {
        #expect(Wait.next(peek: .closing, confirmationShown: true, attemptsLeft: 40) == .retry)
    }

    @Test func oncePeekIsGoneNewSpaceContinuesIntoTheForm() {
        #expect(Wait.next(peek: .none, confirmationShown: true, attemptsLeft: 40) == .retry)
    }

    @Test func otherBlockersKeepRetrying() {
        #expect(Wait.next(peek: .open, confirmationShown: false, attemptsLeft: 5) == .retry)
    }

    @Test func retriesStayBounded() {
        #expect(Wait.next(peek: .none, confirmationShown: false, attemptsLeft: 0) == .giveUp)
    }

    @Test func aConfirmedCloseStillRespectsTheRetryBound() {
        #expect(Wait.next(peek: .closing, confirmationShown: true, attemptsLeft: 0) == .giveUp)
    }

    @Test func pressingNewSpaceAgainWhileHangUpIsShowingBringsTheWaitForward() {
        #expect(Wait.press(peek: .awaitingConfirmation, waitActive: true) == .bringForward)
    }

    @Test func aHangUpPromptAlreadyShowingIsWaitedOnWithoutAskingThePeekToCloseAgain() {
        #expect(Wait.press(peek: .awaitingConfirmation, waitActive: false) == .waitWithoutDismissing)
    }

    @Test func withoutAPendingHangUpNewSpaceAsksBlockersToCloseAndWaits() {
        #expect(Wait.press(peek: .open, waitActive: true) == .dismissAndWait)
    }

    @Test func withNothingInTheWayNewSpaceStartsNormally() {
        #expect(Wait.press(peek: .none, waitActive: false) == .dismissAndWait)
    }
}
