import Foundation

@main
struct RecentTabSwitcherTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        var assertions = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            assertions += 1; precondition(value(), message)
        }
        let ids = (0..<12).map(String.init)
        var state = RecentTabSwitcherSelection(itemIDs: ids, currentID: "0", forward: true)
        expect(Array(state.displayedIDs) == Array(ids.prefix(5)), "Ordinary display contains five items")
        expect(state.itemIDs == Array(ids.prefix(6)), "One additional genuine candidate is retained for close")
        expect(state.focusedIndex == 1, "Forward begins after the current item")
        var visited = Set<Int>()
        for _ in 0..<15 { state.focus(state.focusedIndex + 1); visited.insert(state.focusedIndex) }
        expect(visited == Set(0..<5), "Repeated cycling reaches every displayed item and never the reserve")
        state.focus(-1)
        expect(state.focusedIndex == 4, "Reverse wraps to the last displayed item")
        state.didClose("4", availableIDs: ids.filter { $0 != "4" })
        expect(Array(state.displayedIDs) == ["0", "1", "2", "3", "5"], "Confirmed close promotes the reserve")
        expect(state.itemIDs.last == "6" && state.focusedIndex == 4, "Replacement keeps the focused position and a fresh reserve")
        state.didClose("5", availableIDs: ids.filter { !["4", "5"].contains($0) })
        expect(Array(state.displayedIDs) == ["0", "1", "2", "3", "6"], "Repeated confirmed close advances without resurrecting prior items")
        state.didClose("6", availableIDs: ["3", "2", "1", "0", "7", "8"])
        expect(Array(state.displayedIDs) == ["0", "1", "2", "3", "7"], "Live MRU refresh cannot reorder surviving preview cards")
        state.didClose("7", availableIDs: ["0", "1"])
        expect(state.focusedIndex == 1 && Array(state.displayedIDs) == ["0", "1"], "Removed or unavailable candidates shrink and clamp focus")
        state.didClose("1", availableIDs: ["0"])
        expect(state.focusedIndex == 0 && state.itemIDs == ["0"], "Last surviving item remains selectable")
        state.didClose("0", availableIDs: [])
        state.focus(-1)
        expect(state.itemIDs.isEmpty && state.focusedIndex == 0, "Empty close outcome stays empty without division by zero")
        let reverse = RecentTabSwitcherSelection(itemIDs: ids, currentID: "0", forward: false)
        expect(reverse.focusedIndex == 4, "Initial reverse excludes the hidden sixth item")
        let emptyWindow = RecentTabSwitcherSelection(itemIDs: ids, currentID: nil, forward: true)
        expect(emptyWindow.focusedIndex == 0, "An empty original window begins at the first available item")
        let repeated = RecentTabSwitcherSelection(itemIDs: ["a", "a", "b"], currentID: "a", forward: true)
        expect(repeated.itemIDs == ["a", "b"] && repeated.focusedIndex == 1, "Repeated identity cannot produce duplicate cards")
        let shift: UInt = 0x2_0000, control: UInt = 0x4_0000, option: UInt = 0x8_0000, command: UInt = 0x10_0000
        let capsLock: UInt = 0x1_0000, function: UInt = 0x80_0000
        let input = RecentTabSwitcherInput(next: control, previous: control | shift)
        expect(input.isHolding(control) && input.isHolding(shift), "Monitor starts while any binding modifier is down")
        expect(!input.isHolding(0) && !input.isHolding(option | capsLock), "No binding modifier completes immediately")
        expect(input.continues(control) && input.continues(control | shift), "Shift may be added or released mid-hold")
        expect(input.continues(control | capsLock | function), "Caps Lock and fn are outside the comparison mask")
        expect(!input.continues(control | option) && !input.continues(control | command), "Another modifier commits")
        expect(!input.continues(shift) && !input.continues(0), "Releasing the held binding commits")
        let custom = RecentTabSwitcherInput(next: option, previous: nil)
        expect(custom.continues(option) && custom.continues(control) && !custom.continues(option | shift),
               "Disabled Previous contributes nothing; the Control alternate always continues")
        expect(input.keyDown(matchesNext: true, matchesPrevious: false, keyCode: 48, flags: control) == .forward, "Next cycles forward")
        expect(input.keyDown(matchesNext: false, matchesPrevious: true, keyCode: 48, flags: control | shift) == .backward, "Previous reverses")
        expect(input.keyDown(matchesNext: false, matchesPrevious: false, keyCode: 50, flags: control) == .backward, "Control-backtick alternate reverses")
        expect(input.keyDown(matchesNext: false, matchesPrevious: false, keyCode: 50, flags: control | shift) == .consume, "Alternate needs exactly Control")
        expect(input.keyDown(matchesNext: false, matchesPrevious: false, keyCode: 123, flags: control) == .backward, "Left reverses")
        expect(input.keyDown(matchesNext: false, matchesPrevious: false, keyCode: 124, flags: control) == .forward, "Right advances")
        expect(input.keyDown(matchesNext: false, matchesPrevious: false, keyCode: 53, flags: control) == .cancel, "Escape cancels")
        expect(input.keyDown(matchesNext: false, matchesPrevious: false, keyCode: 13, flags: control) == .close, "W closes the focused item")
        expect(input.keyDown(matchesNext: false, matchesPrevious: false, keyCode: 0, flags: control) == .consume, "Unrelated keys are consumed, not forwarded")
        expect(input.keyDown(matchesNext: true, matchesPrevious: false, keyCode: 123, flags: control) == .forward, "A binding wins over the arrow table")
        print("RecentTabSwitcher: \(assertions) assertions passed")
    }
}
