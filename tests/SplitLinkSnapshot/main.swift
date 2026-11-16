import Foundation

let space = UUID(), profile = UUID(), parent = UUID(), neighbor = UUID()
let url = URL(string: "https://example.com/original")!
let snapshot = SplitLinkSnapshot(spaceID: space, profileID: profile,
    selection: [parent, neighbor], focusedID: parent, sourceURL: url, generation: 7)
func check(_ value: Bool, _ message: String) { precondition(value, message) }
check(snapshot.accepts(spaceID: space, profileID: profile, selection: [parent, neighbor], focusedID: parent, sourceURL: url, generation: 7), "original owner and panes remain valid")
check(!snapshot.accepts(spaceID: UUID(), profileID: profile, selection: [parent, neighbor], focusedID: parent, sourceURL: url, generation: 7), "Space change retires the lease")
check(!snapshot.accepts(spaceID: space, profileID: UUID(), selection: [parent, neighbor], focusedID: parent, sourceURL: url, generation: 7), "Profile change retires the lease")
check(!snapshot.accepts(spaceID: space, profileID: profile, selection: [neighbor, parent], focusedID: parent, sourceURL: url, generation: 7), "pane order change retires the lease")
check(!snapshot.accepts(spaceID: space, profileID: profile, selection: [parent, neighbor], focusedID: neighbor, sourceURL: url, generation: 7), "focus change retires the lease")
check(!snapshot.accepts(spaceID: space, profileID: profile, selection: [parent, neighbor], focusedID: nil, sourceURL: url, generation: 7), "missing focus cannot retarget")
check(!snapshot.accepts(spaceID: space, profileID: profile, selection: [parent, neighbor], focusedID: parent, sourceURL: URL(string: "https://example.com/other"), generation: 7), "source URL change retires the lease")
check(!snapshot.accepts(spaceID: space, profileID: profile, selection: [neighbor], focusedID: parent, sourceURL: url, generation: 7), "removed parent cannot receive a pane")
check(!snapshot.accepts(spaceID: space, profileID: profile, selection: [parent, neighbor], focusedID: parent, sourceURL: url, generation: 8), "a changed-and-restored selection remains stale")
let third = UUID(), hovered = UUID()
let panes = [parent, neighbor, third]
func clickPane(showing page: UUID, current: UUID? = parent, rendered: [UUID] = [parent, neighbor, third],
               covered: Set<UUID> = []) -> UUID? {
    LinkClickPane.id(selection: panes, current: current, rendered: rendered,
                     covered: { covered.contains($0) }, shows: { $0 == page })
}
check(clickPane(showing: parent) == parent, "the focused pane answers for its own page")
check(clickPane(showing: neighbor) == neighbor, "a click in an unfocused pane acts on that pane, which it focuses first")
check(clickPane(showing: neighbor, rendered: [parent]) == nil, "a pane that isn't on screen can't take the click")
check(clickPane(showing: parent, rendered: []) == parent, "the focused pane answers even before it is laid out")
check(clickPane(showing: neighbor, covered: [neighbor]) == nil, "a Peek over the pane takes the click instead")
check(clickPane(showing: neighbor, covered: [parent]) == neighbor, "another pane's hidden Peek leaves this pane's clicks alone")
check(clickPane(showing: hovered) == nil, "a page outside the selection never acts as a pane")
check(clickPane(showing: third, current: nil) == third, "a click still finds its pane without a focused one")
print("Passed 17 inert split-link lease and click-pane checks; no browser execution.")
