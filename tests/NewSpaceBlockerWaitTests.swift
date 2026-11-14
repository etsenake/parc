import Foundation

@main struct NewSpaceBlockerWaitTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); checks += 1
    }
    static func main() {
        typealias Wait = NewSpaceBlockerWait
        check(Wait.next(peek: .awaitingConfirmation, confirmationShown: true, attemptsLeft: 0) == .waitForConfirmation, "A Peek asking for confirmation keeps New Space waiting without using attempts")
        check(Wait.next(peek: .awaitingConfirmation, confirmationShown: false, attemptsLeft: 40) == .waitForConfirmation, "A fresh confirmation is waited on")
        check(Wait.next(peek: .open, confirmationShown: true, attemptsLeft: 40) == .giveUp, "A Peek that stopped asking without closing means the person declined")
        check(Wait.next(peek: .closing, confirmationShown: true, attemptsLeft: 40) == .retry, "A confirmed Peek that is closing lets New Space continue")
        check(Wait.next(peek: .none, confirmationShown: true, attemptsLeft: 40) == .retry, "Once the Peek is gone New Space continues into the form")
        check(Wait.next(peek: .open, confirmationShown: false, attemptsLeft: 5) == .retry, "Other blockers keep retrying")
        check(Wait.next(peek: .none, confirmationShown: false, attemptsLeft: 0) == .giveUp, "Retries stay bounded")
        check(Wait.next(peek: .closing, confirmationShown: true, attemptsLeft: 0) == .giveUp, "A confirmed close still respects the retry bound")
        check(Wait.press(peek: .awaitingConfirmation, waitActive: true) == .bringForward, "Pressing New Space again while Hang up is showing never hangs up the call or starts a second wait")
        check(Wait.press(peek: .awaitingConfirmation, waitActive: false) == .waitWithoutDismissing, "A Hang up prompt already showing is waited on without asking the Peek to close again")
        check(Wait.press(peek: .open, waitActive: true) == .dismissAndWait, "Without a pending Hang up, New Space asks blockers to close and waits")
        check(Wait.press(peek: .none, waitActive: false) == .dismissAndWait, "With nothing in the way New Space starts normally")
        print("NewSpaceBlockerWaitTests: \(checks) assertions passed")
    }
}
