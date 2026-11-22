import Foundation
import Testing
@testable import ParcCore

@MainActor
struct WindowPresentationPlaceholdersTests {
    private typealias World = WindowPresentationTestsSupport.World

    @MainActor private struct Frozen {
        let w = World()
        var state = BrowserState.initial()
        let space: BrowserSpace
        let other: BrowserSpace
        let x: BrowserTab
        let y: BrowserTab
        let z: BrowserTab
        let moves = NativePageOwnership()
        let sourceWindow = UUID()
        let selectingWindow = UUID()
        var source: WindowPresentation

        init() {
            space = state.spaces[0]
            other = BrowserSpace(id: UUID(), name: "Second", symbol: "circle", color: "112233", profileID: space.profileID)
            state.spaces.append(other)
            x = World.tab(space)
            y = World.tab(space)
            z = World.tab(space)
            state.tabs = [x, y, z, World.tab(other)]
            state.selectedTabIDs = [x.id]
            source = WindowPresentation(state: state, ready: true)
            _ = moves.claim(x.id, owner: sourceWindow, page: "frozen-x")
        }

        func usable(_ id: UUID) -> Bool { moves.canUse(id, owner: sourceWindow) }

        func move(_ id: UUID, from: UUID, to: UUID) -> Bool {
            guard let reservation = moves.reserveTransfer(id, page: "frozen-x", from: from, to: to) else { return false }
            return moves.finishTransfer(reservation, moved: true)
        }
    }

    @Test func aMovedAwayPageLeavesAPlaceholderThatIsNeitherSavedNorFocused() {
        var f = Frozen()
        let r9 = f.source.leavePlaceholder(f.x.id, state: f.state)
        #expect(r9)
        #expect(f.move(f.x.id, from: f.sourceWindow, to: f.selectingWindow))
        f.source.reconcile(f.state, available: f.usable)
        #expect(f.source.selectedTabIDs.isEmpty && f.source.displayedTabIDs == [f.x.id] && f.source.displayedPlaceholders == [f.x.id])
        #expect(f.source.allPlaceholders == [f.x.id])
        #expect(f.source.sessionSelection.tabIDs.isEmpty && f.source.preferredFocusedTabID == nil)
    }

    @Test func aPlaceholderHidesInAnotherSpaceAndReturnsWithTheSpace() {
        var f = Frozen()
        _ = f.source.leavePlaceholder(f.x.id, state: f.state)
        _ = f.move(f.x.id, from: f.sourceWindow, to: f.selectingWindow)
        f.source.reconcile(f.state, available: f.usable)
        f.source.selectSpace(f.other.id, state: f.state, available: f.usable)
        #expect(f.source.displayedPlaceholders.isEmpty && f.source.showsPlaceholder(f.x.id))
        f.source.selectSpace(f.space.id, state: f.state, available: f.usable)
        #expect(f.source.displayedTabIDs == [f.x.id] && f.source.displayedPlaceholders == [f.x.id])
    }

    @Test func aReturnedPageRejoinsTheSelectionInItsSlot() {
        var f = Frozen()
        _ = f.source.leavePlaceholder(f.x.id, state: f.state)
        _ = f.move(f.x.id, from: f.sourceWindow, to: f.selectingWindow)
        f.source.reconcile(f.state, available: f.usable)
        #expect(f.move(f.x.id, from: f.selectingWindow, to: f.sourceWindow))
        f.source.reconcile(f.state, available: f.usable)
        #expect(f.source.selectedTabIDs == [f.x.id] && f.source.displayedPlaceholders.isEmpty && !f.source.showsPlaceholder(f.x.id))
    }

    private func splitFrozen() -> (Frozen, BrowserSplitLayout) {
        var f = Frozen()
        let layout = BrowserSplitLayout(spaceID: f.space.id, tabIDs: [f.x.id, f.y.id], orientation: .vertical, widthFactors: [0.25, 0.75])
        f.state.splitLayouts = [layout]
        f.state.selectedTabIDs = [f.x.id, f.y.id]
        f.source = WindowPresentation(state: f.state, ready: true)
        f.source.recordFocusedTab(f.x.id)
        return (f, layout)
    }

    @Test func aSplitPanesPlaceholderKeepsItsGeometryAndMovesFocusToTheLivePane() {
        var (f, layout) = splitFrozen()
        #expect(f.move(f.x.id, from: f.sourceWindow, to: f.selectingWindow))
        f.source.leavePlaceholder(f.x.id, state: f.state)
        f.source.reconcile(f.state, available: f.usable)
        #expect(f.source.selectedTabIDs == [f.y.id] && f.source.displayedTabIDs == [f.x.id, f.y.id])
        #expect(f.source.displayedSplitLayout == layout && f.source.preferredFocusedTabID == f.y.id)
    }

    @Test func returningAPlaceholderPaneRestoresTheSplitSelectionAndGeometry() {
        var (f, layout) = splitFrozen()
        #expect(f.move(f.x.id, from: f.sourceWindow, to: f.selectingWindow))
        f.source.leavePlaceholder(f.x.id, state: f.state)
        f.source.reconcile(f.state, available: f.usable)
        #expect(f.move(f.x.id, from: f.selectingWindow, to: f.sourceWindow))
        f.source.reconcile(f.state, available: f.usable)
        #expect(f.source.selectedTabIDs == [f.x.id, f.y.id] && f.source.splitLayout == layout)
    }

    @Test func closingTheLivePaneLeavesThePlaceholderAlone() {
        var (f, _) = splitFrozen()
        #expect(f.move(f.x.id, from: f.sourceWindow, to: f.selectingWindow))
        f.source.leavePlaceholder(f.x.id, state: f.state)
        var closedPartner = f.state
        closedPartner.tabs.removeAll { $0.id == f.y.id }
        closedPartner.splitLayouts = []
        f.source.reconcile(closedPartner, available: f.usable)
        #expect(f.source.selectedTabIDs.isEmpty && f.source.displayedTabIDs == [f.x.id] && f.source.displayedSplitLayout == nil)
    }

    @Test func selectingAnotherTabReplacesTheRemainingPlaceholder() {
        var (f, _) = splitFrozen()
        #expect(f.move(f.x.id, from: f.sourceWindow, to: f.selectingWindow))
        f.source.leavePlaceholder(f.x.id, state: f.state)
        var closedPartner = f.state
        closedPartner.tabs.removeAll { $0.id == f.y.id }
        closedPartner.splitLayouts = []
        f.source.reconcile(closedPartner, available: f.usable)
        var replaced = closedPartner
        replaced.selectedTabIDs = [f.z.id]
        f.source.captureCommand(replaced, available: f.usable)
        #expect(f.source.selectedTabIDs == [f.z.id] && f.source.displayedTabIDs == [f.z.id] && !f.source.showsPlaceholder(f.x.id))
    }

    @Test func archivingAPageRemovesItsPlaceholder() {
        let (f, _) = splitFrozen()
        var archivedSource = WindowPresentation(state: f.state, ready: true)
        archivedSource.leavePlaceholder(f.x.id, state: f.state)
        var archivedState = f.state
        archivedState.tabs[archivedState.tabs.firstIndex { $0.id == f.x.id }!].archivedAt = Date()
        archivedSource.reconcile(archivedState, available: f.usable)
        #expect(!archivedSource.showsPlaceholder(f.x.id) && archivedSource.displayedTabIDs == [f.y.id])
    }

    @Test func anUnshownPageDoesNotLeaveAPlaceholder() {
        let (f, _) = splitFrozen()
        var unselected = WindowPresentation(state: f.state, ready: true)
        #expect(!unselected.leavePlaceholder(f.z.id, state: f.state) && unselected.displayedPlaceholders.isEmpty)
    }

    @Test func onlyThePanesHeldElsewhereMoveAndABusyPaneRefusesTheWholeSelection() {
        let x = UUID(), y = UUID()
        #expect(PageReparenting.pagesToMove([x, y], usableHere: { $0 == y }, movable: { _ in true }) == [x])
        #expect(PageReparenting.pagesToMove([x, y], usableHere: { _ in false }, movable: { $0 == x }) == nil)
        #expect(PageReparenting.pagesToMove([x], usableHere: { _ in true }, movable: { _ in false }) == [])
    }

    @Test func aReturnedPageGoesToTheRightPlaceholderWindow() {
        let source = UUID(), selecting = UUID()
        let now = Date(), older = now.addingTimeInterval(-60)
        let windows = [
            PageReparenting.Candidate(windowID: source, displaysPlaceholder: true, showsPlaceholder: true, lastActive: older),
            PageReparenting.Candidate(windowID: selecting, displaysPlaceholder: false, showsPlaceholder: true, lastActive: now),
        ]
        #expect(PageReparenting.returnDestination(windows, trigger: .deselected) == source)
        #expect(PageReparenting.returnDestination(windows, trigger: .ownerClosing) == selecting)
        #expect(PageReparenting.returnDestination([], trigger: .ownerClosing) == nil)
        #expect(PageReparenting.returnDestinations(windows, trigger: .ownerClosing) == [selecting, source])
    }

    @Test func aReturnPassesOverARefusingWindow() {
        let source = UUID(), selecting = UUID()
        let now = Date(), older = now.addingTimeInterval(-60)
        var refusing = [
            PageReparenting.Candidate(windowID: source, displaysPlaceholder: true, showsPlaceholder: true, lastActive: older),
            PageReparenting.Candidate(windowID: selecting, displaysPlaceholder: false, showsPlaceholder: true, lastActive: now),
        ]
        refusing[1].canReceive = false
        #expect(PageReparenting.returnDestination(refusing, trigger: .ownerClosing) == source)
    }

    @Test func aReturnIsBlockedWhenEveryPlaceholderWindowRefuses() {
        let source = UUID(), selecting = UUID()
        let now = Date(), older = now.addingTimeInterval(-60)
        var refusing = [
            PageReparenting.Candidate(windowID: source, displaysPlaceholder: true, showsPlaceholder: true, lastActive: older),
            PageReparenting.Candidate(windowID: selecting, displaysPlaceholder: false, showsPlaceholder: true, lastActive: now),
        ]
        refusing[1].canReceive = false
        refusing[0].canReceive = false
        #expect(PageReparenting.returnDestination(refusing, trigger: .ownerClosing) == nil)
        #expect(PageReparenting.unstartedReturn(refusing) == .blocked)
    }

    @Test func anUnstartedReturnWaitsForAWindowToShowItsPlaceholderOrNoLongerApplies() {
        let id = UUID()
        let now = Date()
        let elsewhere = [PageReparenting.Candidate(windowID: id, displaysPlaceholder: false, showsPlaceholder: true, lastActive: now)]
        #expect(PageReparenting.returnDestination(elsewhere, trigger: .deselected) == nil)
        #expect(PageReparenting.unstartedReturn(elsewhere) == .blocked)
        #expect(PageReparenting.unstartedReturn([]) == .unneeded)
        let gone = [PageReparenting.Candidate(windowID: id, displaysPlaceholder: false, showsPlaceholder: false, lastActive: now)]
        #expect(PageReparenting.unstartedReturn(gone) == .unneeded)
    }

    @Test func aWindowKnowsWhenItStillShowsAPlaceholderSoItIsNotRetiredAsEmpty() {
        let f = Frozen()
        var keeping = WindowPresentation(state: f.state, ready: true)
        #expect(!keeping.hasPlaceholders)
        keeping.leavePlaceholder(f.x.id, state: f.state)
        #expect(keeping.hasPlaceholders)
    }

    struct RowActionCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let closing: Bool
        let busy: Bool
        let usableHere: Bool
        let heldElsewhere: Bool
        let expected: PageReparenting.RowAction?
    }

    @Test(arguments: [
        RowActionCase(testDescription: "Select a transferred page", closing: false, busy: false, usableHere: false, heldElsewhere: true, expected: .moveHere),
        RowActionCase(testDescription: "Close a transferred page", closing: true, busy: false, usableHere: false, heldElsewhere: true, expected: .moveHereThenClose),
        RowActionCase(testDescription: "Select a local page", closing: false, busy: false, usableHere: true, heldElsewhere: false, expected: .here),
        RowActionCase(testDescription: "Close a local page", closing: true, busy: false, usableHere: true, heldElsewhere: false, expected: .here),
        RowActionCase(testDescription: "Select while busy", closing: false, busy: true, usableHere: false, heldElsewhere: true, expected: nil),
        RowActionCase(testDescription: "Close while busy", closing: true, busy: true, usableHere: true, heldElsewhere: false, expected: nil),
        RowActionCase(testDescription: "No available page", closing: false, busy: false, usableHere: false, heldElsewhere: false, expected: nil),
    ])
    func sidebarActionsUseThePagesAvailableOwner(_ action: RowActionCase) {
        #expect(PageReparenting.rowAction(
            closing: action.closing, busy: action.busy, usableHere: action.usableHere, heldElsewhere: action.heldElsewhere
        ) == action.expected)
    }
}
