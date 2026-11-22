import Foundation
import Testing
@testable import ParcCore

@MainActor
struct WindowPresentationSelectionTests {
    private typealias World = WindowPresentationTestsSupport.World
    private typealias Engine = WindowPresentationTestsSupport.Engine

    @Test func eachWindowRestoresItsOwnSplitFocusSpaceAndSelection() {
        let w = World()
        let first = w.restoredFirst()
        var second = WindowPresentation(state: w.shared, ready: true, restoredRecord: w.secondRecord)
        second.reconcile(w.shared, available: { _ in true })
        #expect(first.activeSpaceID == w.firstSpace.id && first.selectedTabIDs == [w.a.id, w.c.id] && first.preferredFocusedTabID == w.c.id)
        #expect(second.activeSpaceID == w.otherSpace.id && second.selectedTabIDs == [w.b.id])
    }

    @Test func aBackgroundSplitChildPreservesTheOriginalPanesAndFocusThroughReconciliation() {
        var w = World()
        var splitAdoption = w.restoredFirst()
        let original = splitAdoption.sessionSelection
        let child = w.tab(w.firstSpace)
        w.shared.tabs.append(child)
        splitAdoption.recordCreation(child.id, state: w.shared)
        splitAdoption.adopt(child.id, state: w.shared, foreground: false)
        splitAdoption.reconcile(w.shared, available: { _ in true })
        #expect(splitAdoption.sessionSelection == original)
        #expect(splitAdoption.selectedTabIDs == [w.a.id, w.c.id] && splitAdoption.preferredFocusedTabID == w.c.id)
    }

    @Test func aRefusedSplitAdoptedInTheBackgroundKeepsTheOriginalSelection() {
        var w = World()
        var refused = w.restoredFirst()
        let original = refused.sessionSelection
        let child = w.tab(w.firstSpace)
        w.shared.tabs.append(child)
        refused.recordCreation(child.id, state: w.shared)
        refused.adopt(child.id, state: w.shared, foreground: false)
        #expect(refused.sessionSelection == original)
    }

    @Test func removingANonfocusedPaneChangesTheSessionSnapshot() {
        let w = World()
        var source = w.restoredFirst()
        let before = source.sessionSelection
        source.remove(w.a.id)
        #expect(source.preferredFocusedTabID == w.c.id && source.sessionSelection != before)
    }

    @Test func theFirstBackgroundAdoptionChangesTheSessionSnapshot() {
        let w = World()
        var shell = WindowPresentation(state: w.shared, ready: false)
        let before = shell.sessionSelection
        shell.adopt(w.a.id, state: w.shared, foreground: false)
        #expect(shell.isReady && shell.sessionSelection != before)
    }

    @Test func aMissingSpaceFallsBackWithoutAdoptingAnotherWindowsSelection() {
        let w = World()
        var retired = w.secondRecord
        retired.focusedSpaceID = UUID()
        var fallback = WindowPresentation(state: w.shared, ready: true, restoredRecord: retired)
        fallback.reconcile(w.shared, available: { _ in true })
        #expect(fallback.activeSpaceID == w.firstSpace.id && fallback.selectedTabIDs.isEmpty)
    }

    @Test func aPartiallySavedPresentationDoesNotBorrowTheSharedSelection() {
        let w = World()
        var incomplete = w.firstRecord
        incomplete.selectedTabIDs = nil
        let incompleteWindow = WindowPresentation(state: w.shared, ready: true, restoredRecord: incomplete)
        #expect(incompleteWindow.activeSpaceID == w.firstSpace.id && incompleteWindow.selectedTabIDs.isEmpty)
        incomplete = w.firstRecord
        incomplete.focusedSpaceID = nil
        let missingOwner = WindowPresentation(state: w.shared, ready: true, restoredRecord: incomplete)
        #expect(missingOwner.activeSpaceID == w.firstSpace.id && missingOwner.selectedTabIDs.isEmpty)
    }

    @Test func anUnavailablePaneIsNotStolenFromAnotherOwner() {
        let w = World()
        var denied = WindowPresentation(state: w.shared, ready: true, restoredRecord: w.firstRecord)
        let id = w.c.id
        denied.reconcile(w.shared, available: { $0 != id })
        #expect(denied.selectedTabIDs == [w.a.id] && denied.preferredFocusedTabID == w.a.id)
    }

    @Test func anUnreadyShellDoesNotReviveASavedPage() {
        let w = World()
        let pending = WindowPresentation(state: w.shared, ready: false, restoredRecord: w.firstRecord)
        #expect(!pending.isReady && pending.selectedTabIDs.isEmpty)
    }

    @Test func reconcilingAPreflightKeepsItEmptyInItsOwnSpace() {
        let w = World()
        let ownership = NativePageOwnership(), windowB = UUID()
        var preflight = WindowPresentation(state: w.shared, ready: false, preferredProfileID: w.otherProfile.id)
        preflight.reconcile(w.shared, available: { ownership.canUse($0, owner: windowB) })
        #expect(!preflight.isReady && preflight.selectedTabIDs.isEmpty)
        #expect(preflight.activeSpaceID == w.otherSpace.id)
    }

    @Test func aCapturedCommandCannotMakeAPreflightAdoptTheSharedSelection() {
        var w = World()
        let ownership = NativePageOwnership(), windowB = UUID()
        var preflight = WindowPresentation(state: w.shared, ready: false, preferredProfileID: w.otherProfile.id)
        preflight.reconcile(w.shared, available: { ownership.canUse($0, owner: windowB) })
        w.shared.selectedTabIDs = [w.c.id]
        preflight.captureCommand(w.shared, available: { ownership.canUse($0, owner: windowB) })
        #expect(!preflight.isReady && preflight.projected(w.shared).selectedTabIDs.isEmpty)
    }

    @Test func adoptingTheFirstPageMakesAPreflightReadyWithoutChangingSharedSelection() {
        var w = World()
        let ownership = NativePageOwnership(), windowB = UUID()
        var preflight = WindowPresentation(state: w.shared, ready: false, preferredProfileID: w.otherProfile.id)
        preflight.reconcile(w.shared, available: { ownership.canUse($0, owner: windowB) })
        w.shared.selectedTabIDs = [w.c.id]
        preflight.captureCommand(w.shared, available: { ownership.canUse($0, owner: windowB) })
        #expect(ownership.claim(w.b.id, owner: windowB, page: "post-popup-page"))
        preflight.adopt(w.b.id, state: w.shared, foreground: true)
        #expect(preflight.isReady && preflight.selectedTabIDs == [w.b.id])
        #expect(preflight.activeSpaceID == w.otherSpace.id)
        #expect(w.shared.selectedTabIDs == [w.c.id])
    }

    @Test func metadataPublicationCannotReplaceAnotherWindowsSelectedPageButStillRefreshes() {
        var w = World()
        let ownership = NativePageOwnership(), windowA = UUID()
        var left = WindowPresentation(state: w.shared, ready: true)
        #expect(ownership.claim(w.a.id, owner: windowA, page: "real-opener-page"))
        w.shared.selectedTabIDs = [w.c.id]
        w.shared.tabs[0].title = "Changed by live page"
        left.reconcile(w.shared, available: { ownership.canUse($0, owner: windowA) })
        #expect(left.selectedTabIDs == [w.a.id])
        #expect(left.projected(w.shared).tabs[0].title == "Changed by live page")
    }

    enum ShellAddress: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case blank = "about:blank"
        case empty = ""
        case easel = "parc://easel/"

        var testDescription: String {
            switch self {
            case .blank: "Blank page"
            case .empty: "Empty address"
            case .easel: "Easel"
            }
        }

        var url: String { self == .easel ? rawValue + UUID().uuidString : rawValue }
    }

    @Test(arguments: ShellAddress.allCases)
    func aShellPageWithoutANativeWrapperIsLocal(_ address: ShellAddress) {
        let w = World()
        var state = w.shared
        state.tabs[0].url = address.url
        let window = WindowPresentation(state: state, ready: true)
        #expect(window.isLocalSelection(w.a.id, state: state, hasNativeWrapper: false))
    }

    @Test func aBlankPageWithANativeWrapperIsNotLocal() {
        let w = World()
        var state = w.shared
        state.tabs[0].url = "about:blank"
        let window = WindowPresentation(state: state, ready: true)
        #expect(!window.isLocalSelection(w.a.id, state: state, hasNativeWrapper: true))
    }

    @Test func anOrdinaryWebPageWithoutANativeWrapperIsNotLocal() {
        let w = World()
        let window = WindowPresentation(state: w.shared, ready: true)
        #expect(!window.isLocalSelection(w.a.id, state: w.shared, hasNativeWrapper: false))
    }

    @Test func aSelectedShellPageDoesNotCountAsAnEmptyLocalSelection() {
        let w = World()
        var state = w.shared
        state.tabs[0].url = "parc://easel/" + UUID().uuidString
        let window = WindowPresentation(state: state, ready: true)
        #expect(!window.isLocalSelection(nil, state: state, hasNativeWrapper: false))
    }

    @Test func aReadyWindowWithoutAPageHasAnEmptyLocalSelection() {
        let w = World()
        var state = w.shared
        state.tabs[0].url = "parc://easel/" + UUID().uuidString
        var window = WindowPresentation(state: state, ready: true)
        window.remove(w.a.id)
        window.remove(w.c.id)
        #expect(window.isLocalSelection(nil, state: state, hasNativeWrapper: false))
    }

    @Test func aPreflightDoesNotHaveAnEmptyLocalSelection() {
        let w = World()
        var state = w.shared
        state.tabs[0].url = "parc://easel/" + UUID().uuidString
        let window = WindowPresentation(state: state, ready: false)
        #expect(!window.isLocalSelection(nil, state: state, hasNativeWrapper: false))
    }

    @Test func theEngineCanSelectAnExistingSplitMemberWithoutReplacingTheSplit() {
        var e = Engine()
        let r1 = e.window.selectExistingTab(e.w.c.id, state: e.state, available: e.availableA)
        #expect(r1)
        #expect(e.window.selectedTabIDs == [e.w.a.id, e.w.c.id])
    }

    @Test func reselectingTheSameSplitMemberLeavesTheSplitInPlace() {
        var e = Engine()
        _ = e.window.selectExistingTab(e.w.c.id, state: e.state, available: e.availableA)
        let r2 = e.window.selectExistingTab(e.w.c.id, state: e.state, available: e.availableA)
        #expect(r2)
        #expect(e.window.selectedTabIDs == [e.w.a.id, e.w.c.id])
    }

    @Test func theEngineRefusesAPageHeldByAnotherWindow() {
        var e = Engine()
        #expect(e.ownership.claim(e.w.b.id, owner: UUID(), page: "elsewhere"))
        let r3 = e.window.selectExistingTab(e.w.b.id, state: e.state, available: e.availableA)
        #expect(!r3)
        #expect(e.window.activeSpaceID == e.w.firstSpace.id && e.window.selectedTabIDs == [e.w.a.id, e.w.c.id])
    }

    @Test func theEngineRefusesAnUnknownPage() {
        var e = Engine()
        let r4 = e.window.selectExistingTab(UUID(), state: e.state, available: e.availableA)
        #expect(!r4)
    }

    @Test func anUnavailablePageCannotAlterAPreflightWindowOrReplaceFirstPageAdoption() {
        let e = Engine()
        var preflight = WindowPresentation(state: e.state, ready: false, preferredProfileID: e.w.otherProfile.id)
        let r5 = preflight.selectExistingTab(e.w.a.id, state: e.state, available: { _ in false })
        #expect(!r5)
        var notReady = WindowPresentation(state: e.state, ready: false)
        #expect(!notReady.selectExistingTab(e.w.a.id, state: e.state, available: e.availableA) && !notReady.isReady)
    }

    @Test func anArchivedPageCallbackIsRefusedWithoutPruningTheCurrentPresentation() {
        var e = Engine()
        var archived = e.state
        archived.tabs[2].archivedAt = Date()
        let r6 = e.window.selectExistingTab(e.w.c.id, state: archived, available: e.availableA)
        #expect(!r6)
        #expect(e.window.selectedTabIDs == [e.w.a.id, e.w.c.id])
    }

    @Test func selectingASameProfileFavoriteKeepsTheCurrentSpace() {
        var e = Engine()
        e.window.selectSpace(e.w.siblingSpace.id, state: e.state, available: e.availableA)
        let r7 = e.window.selectExistingTab(e.favorite.id, state: e.state, available: e.availableA)
        #expect(r7)
        #expect(e.window.activeSpaceID == e.w.siblingSpace.id && e.window.selectedTabIDs == [e.favorite.id])
    }

    @Test func selectingAnOrdinaryPageSwitchesToItsSpaceWithoutEditingTabRecords() {
        var e = Engine()
        let originalTabs = e.state.tabs
        e.window.selectSpace(e.w.siblingSpace.id, state: e.state, available: e.availableA)
        _ = e.window.selectExistingTab(e.favorite.id, state: e.state, available: e.availableA)
        let r8 = e.window.selectExistingTab(e.w.c.id, state: e.state, available: e.availableA)
        #expect(r8)
        #expect(e.window.activeSpaceID == e.w.firstSpace.id && e.window.selectedTabIDs == [e.w.c.id])
        #expect(e.state.tabs == originalTabs)
    }

    @Test func anAdoptedFavoriteStaysInTheDestinationWindowsCurrentSpace() {
        let e = Engine()
        var destination = WindowPresentation(state: e.state, ready: true)
        destination.selectSpace(e.w.siblingSpace.id, state: e.state, available: e.availableA)
        destination.adopt(e.favorite.id, state: e.state, foreground: true)
        #expect(destination.activeSpaceID == e.w.siblingSpace.id && destination.selectedTabIDs == [e.favorite.id])
    }

    @Test func aFavoriteMovedForAnOptionReleaseKeepsTheDestinationsPanesUntilPlacement() {
        let e = Engine()
        var optionState = e.state
        optionState.selectedTabIDs = [e.w.a.id]
        var destination = WindowPresentation(state: optionState, ready: true)
        destination.adopt(e.favorite.id, state: optionState, foreground: false)
        #expect(destination.activeSpaceID == e.w.firstSpace.id && destination.selectedTabIDs == [e.w.a.id])
    }
}
