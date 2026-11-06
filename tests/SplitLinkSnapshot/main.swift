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
print("Passed 9 inert split-link lease checks; no browser execution.")
