import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

struct PendingSplitPaneSidebarTests {
    typealias Rule = PendingSplitPaneSidebarRule

    @Test(arguments: [SidebarPresentation.locked, .floating, .hidden])
    func withoutAPendingPaneEveryPresentationIsAsAsked(requested: SidebarPresentation) {
        #expect(Rule.presentation(for: requested, pendingPane: false) == requested)
    }

    @Test func hidingWhileAPaneIsPendingFloatsTheSidebar() {
        #expect(Rule.presentation(for: .hidden, pendingPane: true) == .floating)
    }

    @Test func lockingWhileAPaneIsPendingStillLocks() {
        #expect(Rule.presentation(for: .locked, pendingPane: true) == .locked)
    }

    @Test func revealingWhileAPaneIsPendingFloats() {
        #expect(Rule.presentation(for: .floating, pendingPane: true) == .floating)
    }

    @Test(arguments: [false, true])
    func aPendingPaneFloatsAHiddenSidebarOnAnyRender(heldBefore: Bool) {
        #expect(Rule.refresh(.hidden, pendingPane: true, heldBefore: heldBefore) == .float)
    }

    @Test func aFloatingSidebarStaysWhileThePaneIsPending() {
        #expect(Rule.refresh(.floating, pendingPane: true, heldBefore: true) == .keep)
    }

    @Test(arguments: [false, true])
    func aLockedSidebarIsUntouched(pending: Bool) {
        #expect(Rule.refresh(.locked, pendingPane: pending, heldBefore: !pending) == .keep)
    }

    @Test func endingThePaneHandsTheFloatingSidebarBackToTheHoverRule() {
        #expect(Rule.refresh(.floating, pendingPane: false, heldBefore: true) == .applyHover)
    }

    @Test func anOrdinaryHoverFloatingSidebarIsNotRedecidedByARender() {
        #expect(Rule.refresh(.floating, pendingPane: false, heldBefore: false) == .keep)
    }

    @Test func aHiddenSidebarStaysHiddenOncePaneEnds() {
        #expect(Rule.refresh(.hidden, pendingPane: false, heldBefore: true) == .keep)
    }

    private func holds(pending: Bool = false, space: Bool = false, popup: Bool = false, library: Bool = false) -> Bool {
        Rule.holdsSidebar(pendingSplitPane: pending, creatingSpace: space, popup: popup, library: library)
    }

    @Test func anEmptySpaceLeavesTheSidebarToCommandS() {
        #expect(!holds())
        #expect(Rule.presentation(for: .hidden, pendingPane: holds()) == .hidden)
    }

    @Test func aPendingAddSplitPaneHoldsTheSidebar() {
        #expect(holds(pending: true))
        #expect(Rule.presentation(for: .hidden, pendingPane: holds(pending: true)) == .floating)
    }

    @Test(arguments: [(true, false, false), (false, true, false), (false, false, true)])
    func aPendingPaneIsLeftAloneInTheLibraryAPopupOrSpaceCreation(library: Bool, popup: Bool, space: Bool) {
        #expect(!holds(pending: true, space: space, popup: popup, library: library))
    }

    @Test func closingTheLastTabLeavesAHiddenOrDockedSidebarAsItWas() {
        #expect(Rule.refresh(.hidden, pendingPane: holds(), heldBefore: false) == .keep)
        #expect(Rule.refresh(.locked, pendingPane: holds(), heldBefore: false) == .keep)
    }

    @Test func fillingOrCancellingThePaneHandsTheFloatingSidebarBackToTheHoverRule() {
        #expect(Rule.refresh(.floating, pendingPane: holds(), heldBefore: true) == .applyHover)
    }
}

struct SidebarHoverHandOffTests {
    private func decide(stored: Bool = true, _ presentation: SidebarHoverZones.Presentation = .floating, info: SidebarHoverInfo = SidebarHoverInfo(),
                        key: Bool = true, owner: Bool = false, interaction: Bool = false) -> SidebarHoverPresentationRule.Decision {
        SidebarHoverPresentationRule.decide(stored: stored, presentation: presentation, info: info, fullscreen: false, includesTopLeft: true,
                                            isKeyWindow: key, ownerDefers: owner, interactionDefers: interaction)
    }

    @Test func thePointerLeavingDismissesAFloatingSidebar() {
        #expect(decide().action == .dismiss)
    }

    @Test func theWindowResigningKeyDismissesAFloatingSidebar() {
        #expect(decide(key: false).action == .dismiss)
    }

    @Test func anInteractionGuardOutsideTheKeyWindowDismissesAFloatingSidebar() {
        #expect(decide(key: false, interaction: true).action == .dismiss)
    }

    @Test func aClickInTheWindowOutsideTheSidebarDismissesAFloatingSidebar() {
        var pressed = SidebarHoverInfo()
        pressed[.window] = .inside
        #expect(decide(info: pressed).action == .dismiss)
    }

    @Test func thereIsNoHoverRevealWithoutAnActivation() {
        #expect(decide(.hidden, key: true).action == .keep)
    }

    @Test func thePointerStillOnTheSidebarKeepsIt() {
        var inSidebar = SidebarHoverInfo()
        inSidebar[.sidebar] = .inside
        #expect(decide(stored: true, info: inSidebar).action == .keep)
    }

    @Test func thePointerElsewhereHidesAHiddenSidebar() {
        #expect(decide(stored: true).action == .dismiss)
        #expect(PendingSplitPaneSidebarRule.presentation(for: .hidden, pendingPane: false) == .hidden)
    }
}
