import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

// IDs stand for physical windows; the ordered list contains private, popup,
// closing or otherwise excluded windows as well as eligible browser windows.
let excluded = "excluded", front = "front", back = "back"
check(LinkRoutingUnavailableSpace.firstEligibleWindow(
    ordered: [excluded, front, back], eligible: [front, back]) == front,
    "skip excluded windows and choose the frontmost eligible window")
check(LinkRoutingUnavailableSpace.firstEligibleWindow(
    ordered: [back, excluded, front], eligible: [front, back]) == back,
    "system order, not creation or eligibility order, controls selection")
check(LinkRoutingUnavailableSpace.firstEligibleWindow(
    ordered: [excluded], eligible: [front]) == nil,
    "an eligible but unordered window is not selected")
check(LinkRoutingUnavailableSpace.firstEligibleWindow(
    ordered: [front], eligible: Set<String>()) == nil,
    "no eligible window requires new-window fallback")

let first = UUID(), lastFocused = UUID(), removed = UUID()
check(LinkRoutingUnavailableSpace.newWindowSpace(lastFocused: lastFocused, available: [first, lastFocused]) == lastFocused,
    "retain a still-available last focused Space")
check(LinkRoutingUnavailableSpace.newWindowSpace(lastFocused: removed, available: [first, lastFocused]) == first,
    "a deleted last focused Space falls back to the first available Space")
check(LinkRoutingUnavailableSpace.newWindowSpace(lastFocused: nil, available: [first]) == first,
    "missing recency falls back to the first available Space")
check(LinkRoutingUnavailableSpace.newWindowSpace(lastFocused: lastFocused, available: []) == nil,
    "an empty collection cannot fabricate a Space")
print("Passed 8 inert unavailable-Space policy checks; no browser execution.")
