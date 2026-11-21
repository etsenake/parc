import Testing
@testable import ParcCore

struct RecentTabSwitcherTests {
    let ids = (0..<12).map(String.init)
    let shift: UInt = 0x2_0000
    let control: UInt = 0x4_0000
    let option: UInt = 0x8_0000
    let command: UInt = 0x10_0000
    let capsLock: UInt = 0x1_0000
    let function: UInt = 0x80_0000

    var input: RecentTabSwitcherInput {
        RecentTabSwitcherInput(next: control, previous: control | shift)
    }

    func key(_ code: UInt16, next: Bool = false, previous: Bool = false, flags: UInt? = nil) -> RecentTabSwitcherInput.KeyAction {
        input.keyDown(matchesNext: next, matchesPrevious: previous, keyCode: code, flags: flags ?? control)
    }

    @Test func ordinaryDisplayContainsFiveItemsAndRetainsOneReserveForClose() {
        let state = RecentTabSwitcherSelection(itemIDs: ids, currentID: "0", forward: true)
        #expect(Array(state.displayedIDs) == Array(ids.prefix(5)))
        #expect(state.itemIDs == Array(ids.prefix(6)))
    }

    @Test func forwardBeginsAfterTheCurrentItem() {
        let state = RecentTabSwitcherSelection(itemIDs: ids, currentID: "0", forward: true)
        #expect(state.focusedIndex == 1)
    }

    @Test func repeatedCyclingReachesEveryDisplayedItemAndNeverTheReserve() {
        var state = RecentTabSwitcherSelection(itemIDs: ids, currentID: "0", forward: true)
        var visited = Set<Int>()
        for _ in 0..<15 {
            state.focus(state.focusedIndex + 1)
            visited.insert(state.focusedIndex)
        }
        #expect(visited == Set(0..<5))
    }

    @Test func reverseWrapsToTheLastDisplayedItem() {
        var state = RecentTabSwitcherSelection(itemIDs: ids, currentID: "0", forward: true)
        state.focus(-1)
        #expect(state.focusedIndex == 4)
    }

    @Test func aConfirmedClosePromotesTheReserveAndKeepsTheFocusedPosition() {
        var state = RecentTabSwitcherSelection(itemIDs: ids, currentID: "0", forward: true)
        state.focus(-1)
        state.didClose("4", availableIDs: ids.filter { $0 != "4" })
        #expect(Array(state.displayedIDs) == ["0", "1", "2", "3", "5"])
        #expect(state.itemIDs.last == "6" && state.focusedIndex == 4)
    }

    @Test func aRepeatedConfirmedCloseAdvancesWithoutResurrectingPriorItems() {
        var state = RecentTabSwitcherSelection(itemIDs: ids, currentID: "0", forward: true)
        state.focus(-1)
        state.didClose("4", availableIDs: ids.filter { $0 != "4" })
        state.didClose("5", availableIDs: ids.filter { !["4", "5"].contains($0) })
        #expect(Array(state.displayedIDs) == ["0", "1", "2", "3", "6"])
    }

    @Test func aLiveRecencyRefreshCannotReorderSurvivingPreviewCards() {
        var state = RecentTabSwitcherSelection(itemIDs: ids, currentID: "0", forward: true)
        state.focus(-1)
        state.didClose("4", availableIDs: ids.filter { $0 != "4" })
        state.didClose("5", availableIDs: ids.filter { !["4", "5"].contains($0) })
        state.didClose("6", availableIDs: ["3", "2", "1", "0", "7", "8"])
        #expect(Array(state.displayedIDs) == ["0", "1", "2", "3", "7"])
    }

    @Test func removedOrUnavailableCandidatesShrinkTheCardsAndClampFocus() {
        var state = RecentTabSwitcherSelection(itemIDs: ids, currentID: "0", forward: true)
        state.focus(-1)
        state.didClose("4", availableIDs: ids.filter { $0 != "4" })
        state.didClose("5", availableIDs: ids.filter { !["4", "5"].contains($0) })
        state.didClose("6", availableIDs: ["3", "2", "1", "0", "7", "8"])
        state.didClose("7", availableIDs: ["0", "1"])
        #expect(state.focusedIndex == 1 && Array(state.displayedIDs) == ["0", "1"])
    }

    @Test func theLastSurvivingItemRemainsSelectable() {
        var state = RecentTabSwitcherSelection(itemIDs: ["0", "1"], currentID: "0", forward: true)
        state.didClose("1", availableIDs: ["0"])
        #expect(state.focusedIndex == 0 && state.itemIDs == ["0"])
    }

    @Test func anEmptyCloseOutcomeStaysEmptyWithoutDividingByZero() {
        var state = RecentTabSwitcherSelection(itemIDs: ["0"], currentID: "0", forward: true)
        state.didClose("0", availableIDs: [])
        state.focus(-1)
        #expect(state.itemIDs.isEmpty && state.focusedIndex == 0)
    }

    @Test func initialReverseExcludesTheHiddenSixthItem() {
        let state = RecentTabSwitcherSelection(itemIDs: ids, currentID: "0", forward: false)
        #expect(state.focusedIndex == 4)
    }

    @Test func anEmptyOriginalWindowBeginsAtTheFirstAvailableItem() {
        let state = RecentTabSwitcherSelection(itemIDs: ids, currentID: nil, forward: true)
        #expect(state.focusedIndex == 0)
    }

    @Test func aRepeatedIdentityCannotProduceDuplicateCards() {
        let state = RecentTabSwitcherSelection(itemIDs: ["a", "a", "b"], currentID: "a", forward: true)
        #expect(state.itemIDs == ["a", "b"] && state.focusedIndex == 1)
    }

    @Test func theMonitorStartsWhileAnyBindingModifierIsDown() {
        #expect(input.isHolding(control) && input.isHolding(shift))
    }

    @Test func noBindingModifierCompletesImmediately() {
        #expect(!input.isHolding(0) && !input.isHolding(option | capsLock))
    }

    @Test func shiftMayBeAddedOrReleasedMidHold() {
        #expect(input.continues(control) && input.continues(control | shift))
    }

    @Test func capsLockAndFunctionAreOutsideTheComparisonMask() {
        #expect(input.continues(control | capsLock | function))
    }

    @Test func anotherModifierCommits() {
        #expect(!input.continues(control | option) && !input.continues(control | command))
    }

    @Test func releasingTheHeldBindingCommits() {
        #expect(!input.continues(shift) && !input.continues(0))
    }

    @Test func aDisabledPreviousContributesNothingAndTheControlAlternateAlwaysContinues() {
        let custom = RecentTabSwitcherInput(next: option, previous: nil)
        #expect(custom.continues(option) && custom.continues(control) && !custom.continues(option | shift))
    }

    @Test func nextCyclesForwardAndPreviousReverses() {
        #expect(key(48, next: true) == .forward)
        #expect(key(48, previous: true, flags: control | shift) == .backward)
    }

    @Test func theControlBacktickAlternateReversesButNeedsExactlyControl() {
        #expect(key(50) == .backward)
        #expect(key(50, flags: control | shift) == .consume)
    }

    @Test func arrowKeysMoveTheFocus() {
        #expect(key(123) == .backward)
        #expect(key(124) == .forward)
    }

    @Test func escapeCancelsAndWClosesTheFocusedItem() {
        #expect(key(53) == .cancel)
        #expect(key(13) == .close)
    }

    @Test func unrelatedKeysAreConsumedNotForwarded() {
        #expect(key(0) == .consume)
    }

    @Test func aBindingWinsOverTheArrowTable() {
        #expect(key(123, next: true) == .forward)
    }
}
