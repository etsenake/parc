import Testing
@testable import Parc
@testable import ParcCommandBar

struct NativeHoldTests {
    private func answered() -> CommandBarNativeHold {
        var hold = CommandBarNativeHold()
        _ = hold.accept(input: "n", isError: false)
        return hold
    }

    private func waiting() -> CommandBarNativeHold {
        var hold = answered()
        _ = hold.edit("ne", canHold: true, scoped: false)
        return hold
    }

    @Test func typingWithoutAnAnswerPresentsImmediately() {
        var hold = CommandBarNativeHold()
        #expect(hold.edit("n", canHold: true, scoped: false) == .present)
        #expect(!hold.isHolding)
    }

    @Test func theFirstAnswerBelongsToTheField() {
        var hold = CommandBarNativeHold()
        _ = hold.edit("n", canHold: true, scoped: false)
        let accepted = hold.accept(input: "n", isError: false)
        #expect(accepted)
        #expect(hold.nativeRowsAnswer("n"))
    }

    @Test func typingKeepsThePreviousAnswerUntilTheNextOneArrives() {
        var hold = answered()
        #expect(hold.edit("ne", canHold: true, scoped: false) == .hold)
        #expect(!hold.nativeRowsAnswer("ne"))
    }

    @Test(arguments: [(false, true), (true, false)])
    func submissionRefreshesOnlyAnImplicitSelection(explicit: Bool, refreshes: Bool) {
        #expect(waiting().presentsBeforeSubmitting(explicitSelection: explicit) == refreshes)
    }

    @Test func anOlderAnswerDoesNotEndTheHold() {
        var hold = waiting()
        let accepted = hold.accept(input: "n", isError: false)
        #expect(!accepted)
        #expect(hold.isHolding)
    }

    @Test func anAnswerForTheCurrentQueryEndsTheHold() {
        var hold = waiting()
        let accepted = hold.accept(input: "ne", isError: false)
        #expect(accepted)
        #expect(hold.nativeRowsAnswer("ne"))
        #expect(!hold.presentsBeforeSubmitting(explicitSelection: false))
    }

    @Test func repeatingAnAnsweredQueryKeepsItsRows() {
        var hold = answered()
        #expect(hold.edit("n", canHold: true, scoped: false) == .answered)
    }

    @Test func clearingAnOrdinaryQueryPresentsLocalRowsImmediately() {
        var hold = answered()
        #expect(hold.edit("", canHold: true, scoped: false) == .present)
    }

    @Test func anAnsweredEmptyScopeKeepsItsRows() {
        var hold = CommandBarNativeHold()
        _ = hold.accept(input: "", isError: false)
        #expect(hold.edit("", canHold: true, scoped: true) == .answered)
    }

    @Test func typingInAScopeKeepsThePreviousAnswer() {
        var hold = CommandBarNativeHold()
        _ = hold.accept(input: "", isError: false)
        #expect(hold.edit("wiki", canHold: true, scoped: true) == .hold)
    }

    @Test func anErrorEndsTheHoldEvenWhenItsInputIsMissing() {
        var hold = waiting()
        let accepted = hold.accept(input: "", isError: true)
        #expect(accepted)
        #expect(!hold.isHolding)
    }

    @Test func typingAfterAnErrorPresentsImmediately() {
        var hold = waiting()
        _ = hold.accept(input: "", isError: true)
        #expect(hold.edit("new", canHold: true, scoped: false) == .present)
    }

    @Test func anUnavailableSessionDropsTheOldAnswer() {
        var hold = answered()
        #expect(hold.edit("ne", canHold: false, scoped: false) == .present)
        #expect(!hold.nativeRowsAnswer("n"))
    }
}
