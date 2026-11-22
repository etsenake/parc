import Foundation
import Testing
@testable import ParcCore

@MainActor
struct WindowPresentationContinuityTests {
    private typealias World = WindowPresentationTestsSupport.World
    private typealias Engine = WindowPresentationTestsSupport.Engine

    @MainActor private struct Continuity {
        let e = Engine()
        var state: BrowserState
        let layout: BrowserSplitLayout
        var returning: WindowPresentation

        init() {
            state = e.state
            state.selectedTabIDs = [e.w.a.id, e.w.c.id, e.w.pin.id]
            state.selectionBySpace[e.w.firstSpace.id.uuidString] = state.selectedTabIDs
            layout = BrowserSplitLayout(spaceID: e.w.firstSpace.id, tabIDs: [e.w.a.id, e.w.c.id, e.w.pin.id],
                                        orientation: .vertical, widthFactors: [0.2, 0.3, 0.5])
            state.splitLayouts = [layout]
            returning = WindowPresentation(state: state, ready: true)
            returning.recordFocusedTab(e.w.c.id)
            returning.selectSpace(e.w.siblingSpace.id, state: state, available: { _ in true })
            state.selectedTabIDs = [e.w.pin.id]
            returning.reconcile(state, available: { _ in true })
            returning.selectSpace(e.w.firstSpace.id, state: state, available: { _ in true })
        }
    }

    @Test func returningToASpaceRestoresTheRememberedSplitItsFocusAndItsGeometry() {
        let k = Continuity()
        #expect(k.returning.selectedTabIDs == [k.e.w.a.id, k.e.w.c.id, k.e.w.pin.id])
        #expect(k.returning.preferredFocusedTabID == k.e.w.c.id)
        #expect(k.returning.splitLayout == k.layout)
    }

    @Test func aClosedFocusedPaneFallsBackToTheFirstSurvivorAndKeepsOrientationOrderAndRatio() throws {
        var k = Continuity()
        let w = k.e.w
        k.returning.selectSpace(w.siblingSpace.id, state: k.state, available: { _ in true })
        k.state.tabs.removeAll { $0.id == w.c.id }
        k.returning.selectSpace(w.firstSpace.id, state: k.state, available: { _ in true })
        #expect(k.returning.selectedTabIDs == [w.a.id, w.pin.id] && k.returning.preferredFocusedTabID == w.a.id)
        let projected = try #require(k.returning.splitLayout)
        #expect(projected.orientation == .vertical && projected.tabIDs == [w.a.id, w.pin.id])
        #expect(abs(projected.widthFactors[0] - 2.0 / 7.0) < 0.000001 && abs(projected.widthFactors[1] - 5.0 / 7.0) < 0.000001)
    }

    @Test func aFormerlyUnavailablePageCannotRegainFocusOverANewerUserChoice() {
        var k = Continuity()
        let w = k.e.w
        k.returning.selectSpace(w.siblingSpace.id, state: k.state, available: { _ in true })
        k.state.tabs.removeAll { $0.id == w.c.id }
        k.returning.selectSpace(w.firstSpace.id, state: k.state, available: { _ in true })
        k.returning.recordFocusedTab(w.pin.id)
        k.state.tabs.append(w.c)
        k.returning.reconcile(k.state, available: { _ in true })
        #expect(k.returning.preferredFocusedTabID == w.pin.id && !k.returning.selectedTabIDs.contains(w.c.id))
    }

    @Test func noAvailableOriginalPagesRetainsAnEmptySelectionWithoutCreatingAReplacement() {
        var k = Continuity()
        let w = k.e.w
        k.returning.selectSpace(w.siblingSpace.id, state: k.state, available: { _ in true })
        k.returning.selectSpace(w.firstSpace.id, state: k.state, available: { _ in false })
        #expect(k.returning.selectedTabIDs.isEmpty && k.returning.preferredFocusedTabID == nil && k.returning.splitLayout == nil)
    }

    @Test func popupPublicationNeverCopiesThePopupIntoTheOpenerWindow() {
        let w = World()
        let ownership = NativePageOwnership(), windowA = UUID(), windowB = UUID()
        var left = WindowPresentation(state: w.shared, ready: true)
        #expect(ownership.claim(w.a.id, owner: windowA, page: "real-opener-page"))
        #expect(ownership.claim(w.b.id, owner: windowB, page: "post-popup-page"))
        left.reconcile(w.shared, available: { ownership.canUse($0, owner: windowA) })
        #expect(left.selectedTabIDs == [w.a.id])
    }

    @Test func anotherWindowCannotUseOrClaimAnOwnedTab() {
        let w = World()
        let ownership = NativePageOwnership(), windowA = UUID(), windowB = UUID()
        #expect(ownership.claim(w.b.id, owner: windowB, page: "post-popup-page"))
        #expect(!ownership.canUse(w.b.id, owner: windowA))
        #expect(!ownership.claim(w.b.id, owner: windowA))
    }

    @Test func anAlreadyOwnedPageCannotBeAdoptedOrClaimedUnderAnotherTab() {
        let w = World()
        let ownership = NativePageOwnership(), windowA = UUID(), windowB = UUID()
        #expect(ownership.claim(w.b.id, owner: windowB, page: "post-popup-page"))
        #expect(!ownership.canAdopt("post-popup-page"))
        #expect(!ownership.claim(w.c.id, owner: windowA, page: "post-popup-page"))
    }

    @Test func aTabCannotClaimADifferentPageWhileItsOriginalIsOwned() {
        let w = World()
        let ownership = NativePageOwnership(), windowB = UUID()
        #expect(ownership.claim(w.b.id, owner: windowB, page: "post-popup-page"))
        #expect(!ownership.claim(w.b.id, owner: windowB, page: "duplicate-popup-page"))
        #expect(ownership.canAdopt("duplicate-popup-page"))
    }

    @Test func anIdenticalPageClaimKeepsItsOwnerAndSnapshot() {
        let w = World()
        let ownership = NativePageOwnership(), windowB = UUID()
        #expect(ownership.claim(w.b.id, owner: windowB, page: "post-popup-page"))
        #expect(ownership.claim(w.b.id, owner: windowB, page: "post-popup-page"))
        #expect(ownership.owner(of: w.b.id) == windowB && ownership.owner(of: w.b.id) == ownership.claimSnapshot(w.b.id).owner
                && ownership.owner(of: w.c.id) == nil)
    }

    @Test func anUnrelatedWindowCannotReleaseAnOwnedPage() {
        let w = World()
        let ownership = NativePageOwnership(), windowA = UUID(), windowB = UUID()
        #expect(ownership.claim(w.b.id, owner: windowB, page: "post-popup-page"))
        ownership.release(w.b.id, owner: windowA)
        #expect(!ownership.canUse(w.b.id, owner: windowA))
    }

    @Test func windowTeardownReleasesOnlyItsOwnClaims() {
        let w = World()
        let ownership = NativePageOwnership(), windowA = UUID(), windowB = UUID()
        #expect(ownership.claim(w.a.id, owner: windowA, page: "real-opener-page"))
        #expect(ownership.claim(w.b.id, owner: windowB, page: "post-popup-page"))
        ownership.releaseAll(owner: windowB)
        #expect(ownership.canUse(w.b.id, owner: windowA) && ownership.canAdopt("post-popup-page"))
        #expect(!ownership.canUse(w.a.id, owner: windowB))
    }

    @Test func anActualPageCloseAllowsAnotherWindowToReopenIt() {
        let w = World()
        let ownership = NativePageOwnership(), windowA = UUID(), windowB = UUID()
        #expect(ownership.claim(w.a.id, owner: windowA, page: "real-opener-page"))
        ownership.release(w.a.id, owner: windowA)
        #expect(ownership.canUse(w.a.id, owner: windowB))
    }

    @Test func aNewWindowDoesNotReloadAnAlreadyOwnedSavedSelection() {
        let w = World()
        let ownership = NativePageOwnership(), windowA = UUID(), windowB = UUID()
        let left = WindowPresentation(state: w.shared, ready: true)
        #expect(ownership.claim(w.a.id, owner: windowA, page: "real-opener-page"))
        var extra = WindowPresentation(state: left.projected(w.shared), ready: true)
        extra.reconcile(w.shared, available: { ownership.canUse($0, owner: windowB) })
        #expect(extra.selectedTabIDs.isEmpty)
    }

    @Test func backgroundAdoptionKeepsTheCurrentSelection() {
        var w = World()
        var preflight = WindowPresentation(state: w.shared, ready: true, preferredProfileID: w.otherProfile.id)
        preflight.adopt(w.b.id, state: w.shared, foreground: true)
        let background = w.tab(w.otherSpace)
        w.shared.tabs.append(background)
        preflight.adopt(background.id, state: w.shared, foreground: false)
        #expect(preflight.selectedTabIDs == [w.b.id])
    }

    @Test func aBackgroundAdoptionCanSupplyAPreflightsFirstPage() {
        var w = World()
        let background = w.tab(w.otherSpace)
        w.shared.tabs.append(background)
        var backgroundPreflight = WindowPresentation(state: w.shared, ready: false, preferredProfileID: w.otherProfile.id)
        backgroundPreflight.adopt(background.id, state: w.shared, foreground: false)
        #expect(backgroundPreflight.isReady && backgroundPreflight.selectedTabIDs == [background.id])
    }

    @Test func spaceSelectionIsLocalPerWindowAndNeverSwitchesAnotherProfilesWindow() {
        let w = World()
        let ownership = NativePageOwnership(), windowA = UUID()
        var left = WindowPresentation(state: w.shared, ready: true)
        var preflight = WindowPresentation(state: w.shared, ready: true, preferredProfileID: w.otherProfile.id)
        preflight.adopt(w.b.id, state: w.shared, foreground: true)
        #expect(ownership.claim(w.a.id, owner: windowA, page: "real-opener-page"))
        let available: (UUID) -> Bool = { ownership.canUse($0, owner: windowA) }
        left.reconcile(w.shared, available: available)
        left.selectSpace(w.siblingSpace.id, state: w.shared, available: available)
        #expect(left.selectedTabIDs.isEmpty)
        left.selectSpace(w.firstSpace.id, state: w.shared, available: available)
        #expect(left.selectedTabIDs == [w.a.id])
        #expect(preflight.activeSpaceID == w.otherSpace.id && preflight.selectedTabIDs == [w.b.id])
    }
}
