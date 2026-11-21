import Foundation
import Testing
@testable import ParcCore

struct SplitLinkSnapshotTests {
    let space = UUID()
    let profile = UUID()
    let parent = UUID()
    let neighbor = UUID()
    let third = UUID()
    let url = URL(string: "https://example.com/original")!

    var snapshot: SplitLinkSnapshot {
        SplitLinkSnapshot(spaceID: space, profileID: profile, selection: [parent, neighbor], focusedID: parent,
                          sourceURL: url, generation: 7)
    }

    func accepts(spaceID: UUID? = nil, profileID: UUID? = nil, selection: [UUID]? = nil, focusedID: UUID?? = nil,
                 sourceURL: URL?? = nil, generation: UInt64 = 7) -> Bool {
        snapshot.accepts(spaceID: spaceID ?? space, profileID: profileID ?? profile,
                         selection: selection ?? [parent, neighbor], focusedID: focusedID ?? parent,
                         sourceURL: sourceURL ?? url, generation: generation)
    }

    func clickPane(showing page: UUID, current: UUID? = nil, rendered: [UUID]? = nil, covered: Set<UUID> = [],
                   noCurrent: Bool = false) -> UUID? {
        LinkClickPane.id(selection: [parent, neighbor, third], current: noCurrent ? nil : (current ?? parent),
                         rendered: rendered ?? [parent, neighbor, third],
                         covered: { covered.contains($0) }, shows: { $0 == page })
    }

    @Test func theOriginalOwnerAndPanesRemainValid() {
        #expect(accepts())
    }

    @Test func aSpaceChangeRetiresTheLease() {
        #expect(!accepts(spaceID: UUID()))
    }

    @Test func aProfileChangeRetiresTheLease() {
        #expect(!accepts(profileID: UUID()))
    }

    @Test func aPaneOrderChangeRetiresTheLease() {
        #expect(!accepts(selection: [neighbor, parent]))
    }

    @Test func aFocusChangeRetiresTheLease() {
        #expect(!accepts(focusedID: neighbor))
    }

    @Test func missingFocusCannotRetarget() {
        #expect(!accepts(focusedID: .some(nil)))
    }

    @Test func aSourceURLChangeRetiresTheLease() {
        #expect(!accepts(sourceURL: URL(string: "https://example.com/other")))
    }

    @Test func aRemovedParentCannotReceiveAPane() {
        #expect(!accepts(selection: [neighbor]))
    }

    @Test func aChangedAndRestoredSelectionRemainsStale() {
        #expect(!accepts(generation: 8))
    }

    @Test func theFocusedPaneAnswersForItsOwnPage() {
        #expect(clickPane(showing: parent) == parent)
    }

    @Test func aClickInAnUnfocusedPaneActsOnThatPane() {
        #expect(clickPane(showing: neighbor) == neighbor)
    }

    @Test func aPaneThatIsNotOnScreenCannotTakeTheClick() {
        #expect(clickPane(showing: neighbor, rendered: [parent]) == nil)
    }

    @Test func theFocusedPaneAnswersEvenBeforeItIsLaidOut() {
        #expect(clickPane(showing: parent, rendered: []) == parent)
    }

    @Test func aPeekOverThePaneTakesTheClickInstead() {
        #expect(clickPane(showing: neighbor, covered: [neighbor]) == nil)
    }

    @Test func anotherPanesHiddenPeekLeavesThisPanesClicksAlone() {
        #expect(clickPane(showing: neighbor, covered: [parent]) == neighbor)
    }

    @Test func aPageOutsideTheSelectionNeverActsAsAPane() {
        #expect(clickPane(showing: UUID()) == nil)
    }

    @Test func aClickStillFindsItsPaneWithoutAFocusedOne() {
        #expect(clickPane(showing: third, noCurrent: true) == third)
    }
}
