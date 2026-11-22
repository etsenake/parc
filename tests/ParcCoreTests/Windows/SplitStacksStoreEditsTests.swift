import Foundation
import Testing
@testable import ParcCore

struct SplitStacksStoreEditsTests {
    private typealias Fixture = SplitStacksTestsSupport.Fixture

    @MainActor @Test func aStackedSplitLoadsAndStaysTheActiveSplit() throws {
        let f = try Fixture("edits")
        #expect(f.store.activeSplitLayout == f.layout)
    }

    @MainActor @Test func movingAlongTheMainRowCommits() throws {
        let f = try Fixture("edits")
        #expect(f.store.moveSplitPane(f.a, offset: 1, expected: f.store.activeSplitLayout!))
    }

    @MainActor @Test func movingALonePaneMovesItsSlotPastTheWholeStack() throws {
        let f = try Fixture("edits")
        _ = f.store.moveSplitPane(f.a, offset: 1, expected: f.store.activeSplitLayout!)
        #expect(f.store.state.selectedTabIDs == [f.b, f.c, f.a])
        #expect(f.store.activeSplitLayout?.stacks?.slotSizes == [2, 1])
    }

    @MainActor @Test func theFirstSlotCannotMoveEarlier() throws {
        let f = try Fixture("edits")
        #expect(!f.store.moveSplitPane(f.a, offset: -1, expected: f.store.activeSplitLayout!))
    }

    @MainActor @Test func movingAcrossReordersTheStackAndTheSelection() throws {
        let f = try Fixture("edits")
        #expect(f.store.moveSplitPaneWithinStack(f.c, offset: -1, expected: f.store.activeSplitLayout!))
        #expect(f.store.state.selectedTabIDs == [f.a, f.c, f.b])
    }

    @MainActor @Test func aLonePaneHasNoStackToMoveIn() throws {
        let f = try Fixture("edits")
        #expect(!f.store.moveSplitPaneWithinStack(f.a, offset: -1, expected: f.store.activeSplitLayout!))
    }

    @MainActor @Test func convertCommitsAndKeepsTheStacksPerpendicular() throws {
        let f = try Fixture("edits")
        let before = f.store.activeSplitLayout!
        #expect(f.store.flipSplitOrientation(expected: before))
        #expect(f.store.activeSplitLayout?.orientation == .vertical)
        #expect(f.store.activeSplitLayout?.stacks == before.stacks)
    }

    @MainActor @Test func theOrientationCommandKeepsTheStacks() throws {
        let f = try Fixture("edits")
        let before = f.store.activeSplitLayout!
        #expect(f.store.setSplitLayout(orientation: .vertical, widthFactors: before.widthFactors))
        #expect(f.store.activeSplitLayout?.orientation == .vertical)
        #expect(f.store.activeSplitLayout?.stacks == before.stacks)
    }

    @MainActor @Test func aFlatResizeCannotFlattenAStackedSplit() throws {
        let f = try Fixture("edits")
        let current = f.store.activeSplitLayout!
        #expect(!f.store.resizeSplit(expected: current, widthFactors: [0.2, 0.3, 0.5]))
        #expect(f.store.activeSplitLayout == current)
    }

    @MainActor @Test func expandCommitsOnBothLevels() throws {
        let f = try Fixture("edits")
        let current = f.store.activeSplitLayout!
        #expect(f.store.resizeSplit(expected: current, resized: current.expanded(focusing: f.b)!))
        #expect(f.store.activeSplitLayout!.stacks!.slotFactors[1] > 0.999)
        #expect(f.store.activeSplitLayout!.stacks!.stackFactors[1][0] > 0.999)
    }

    @MainActor @Test func makeAllEqualCommits() throws {
        let f = try Fixture("edits")
        let current = f.store.activeSplitLayout!
        #expect(f.store.resizeSplit(expected: current, resized: current.equalized()!))
        #expect(f.store.activeSplitLayout?.stacks?.slotFactors == [0.5, 0.5])
        #expect(f.store.activeSplitLayout?.stacks?.stackFactors == [[1], [0.5, 0.5]])
    }

    @MainActor @Test func aStackDividerResizeCommits() throws {
        let f = try Fixture("edits")
        let current = f.store.activeSplitLayout!
        #expect(f.store.resizeSplit(expected: current, resized: current.resizingDivider(0, inSlot: 1, leadingShare: 0.25)!))
        #expect(f.store.activeSplitLayout?.stacks?.stackFactors[1] == [0.25, 0.75])
    }

    @MainActor @Test func aResizeCannotChangeOrientation() throws {
        let f = try Fixture("edits")
        let current = f.store.activeSplitLayout!
        #expect(!f.store.resizeSplit(expected: current, resized: current.transposed()))
    }

    @MainActor @Test func aResizeCannotChangePanesOrSlots() throws {
        let f = try Fixture("edits")
        let current = f.store.activeSplitLayout!
        #expect(!f.store.resizeSplit(expected: current, resized: current.movingSlot(of: f.a, by: 1)!))
    }

    @MainActor @Test func addLeftAndAddRightOnAStackedPaneAddAFullLengthSlotBesideItsWholeStack() throws {
        let f = try Fixture("edits")
        let addRight = SplitPaneInsertion(paneID: f.c, operation: .addAfter, state: f.store.state)
        let addLeft = SplitPaneInsertion(paneID: f.b, operation: .addBefore, state: f.store.state)
        #expect(addRight?.index == 3)
        #expect(addRight?.target == .insert(3))
        #expect(addLeft?.index == 1)
    }

    @MainActor private func splitThisPane(_ f: Fixture) throws -> (insertion: SplitPaneInsertion, id: UUID) {
        let insertion = try #require(SplitPaneInsertion(paneID: f.a, stackingAfter: true, state: f.store.state))
        let id = UUID()
        _ = f.store.insertSplitPane(insertion, tabID: id, navigationURL: URL(string: "https://new.test/"), creation: nil, savedHomeIDs: [:], documents: [:])
        return (insertion, id)
    }

    @MainActor @Test func splitThisPaneTargetsThePanesStack() throws {
        let f = try Fixture("edits")
        let insertion = try #require(SplitPaneInsertion(paneID: f.a, stackingAfter: true, state: f.store.state))
        #expect(insertion.target == .stack(0, after: true))
        #expect(insertion.index == 1)
        #expect(insertion.orientation == .horizontal)
    }

    @MainActor @Test func splitThisPaneCommitsANewPaneThatJoinsTheLonePanesSlotAsANewStack() throws {
        let f = try Fixture("edits")
        let s = try splitThisPane(f)
        #expect(f.store.state.selectedTabIDs == [f.a, s.id, f.b, f.c])
        #expect(f.store.activeSplitLayout?.stacks?.slotSizes == [2, 2])
    }

    @MainActor @Test func splitThisPaneRefusesAtFourPanes() throws {
        let f = try Fixture("edits")
        _ = try splitThisPane(f)
        #expect(SplitPaneInsertion(paneID: f.a, stackingAfter: true, state: f.store.state) == nil)
    }

    @MainActor @Test func todaysAddStillRefusesAtFourPanes() throws {
        let f = try Fixture("edits")
        _ = try splitThisPane(f)
        #expect(SplitPaneInsertion(paneID: f.a, operation: .addAfter, state: f.store.state) == nil)
    }

    @MainActor @Test func separateCommitsOnAStackedPane() throws {
        let f = try Fixture("edits")
        let s = try splitThisPane(f)
        #expect(f.store.separateTabFromSplit(s.id, expected: f.store.activeSplitLayout!, focusedID: s.id))
    }

    @MainActor @Test func separatingCollapsesThatStackBackToOnePane() throws {
        let f = try Fixture("edits")
        let s = try splitThisPane(f)
        _ = f.store.separateTabFromSplit(s.id, expected: f.store.activeSplitLayout!, focusedID: s.id)
        #expect(f.store.state.selectedTabIDs == [s.id])
        #expect(f.store.state.splitLayouts.first?.tabIDs == [f.a, f.b, f.c])
        #expect(f.store.state.splitLayouts.first?.stacks?.slotSizes == [1, 2])
    }
}
