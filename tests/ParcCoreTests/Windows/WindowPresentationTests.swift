import Foundation
import Testing
@testable import ParcCore

@MainActor
struct WindowPresentationTests {
    struct World {
        var shared = BrowserState.initial()
        let firstSpace: BrowserSpace
        let otherProfile: BrowserProfile
        let otherSpace: BrowserSpace
        let siblingSpace: BrowserSpace
        let a: BrowserTab
        let b: BrowserTab
        let c: BrowserTab
        let pin: BrowserTab
        let firstRecord: BrowserWindowRecord
        let secondRecord: BrowserWindowRecord

        init() {
            firstSpace = shared.spaces[0]
            otherProfile = BrowserProfile(id: UUID(), name: "Other profile")
            otherSpace = BrowserSpace(id: UUID(), name: "Other Space", symbol: "circle", color: "112233", profileID: otherProfile.id)
            siblingSpace = BrowserSpace(id: UUID(), name: "Same profile", symbol: "circle", color: "112233", profileID: firstSpace.profileID)
            shared.profiles.append(otherProfile)
            shared.spaces += [otherSpace, siblingSpace]
            a = Self.tab(firstSpace)
            b = Self.tab(otherSpace)
            c = Self.tab(firstSpace)
            pin = Self.tab(firstSpace, kind: .pinned)
            shared.tabs = [a, b, c, pin]
            shared.selectedTabIDs = [a.id]
            shared.selectionBySpace[otherSpace.id.uuidString] = [b.id]
            firstRecord = BrowserWindowRecord(sidebarWidth: 230, id: UUID(), focusedSpaceID: firstSpace.id,
                                              selectedTabIDs: [a.id, c.id], focusedTabID: c.id)
            secondRecord = BrowserWindowRecord(sidebarWidth: 250, id: UUID(), focusedSpaceID: otherSpace.id,
                                               selectedTabIDs: [b.id], focusedTabID: b.id)
        }

        static func tab(_ space: BrowserSpace, kind: TabKind = .today) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID,
                       url: "https://example.test/result", title: "Result", kind: kind,
                       createdAt: Date(), lastAccessed: Date(), savedURL: "https://example.test/", savedTitle: "Saved")
        }

        func tab(_ space: BrowserSpace, kind: TabKind = .today) -> BrowserTab { Self.tab(space, kind: kind) }

        func restoredFirst() -> WindowPresentation {
            var window = WindowPresentation(state: shared, ready: true, restoredRecord: firstRecord)
            window.reconcile(shared, available: { _ in true })
            return window
        }
    }

    @Test func launchWaitsForOriginalWindowRestorationThenDrainsADeferredDockRequestOnce() {
        var launch = WindowRestorationLaunch()
        launch.deferDockReopen()
        launch.finishLaunch()
        #expect(!launch.canPresent && !launch.takeDockReopen())
        launch.finishRestoration()
        #expect(launch.canPresent && launch.takeDockReopen() && !launch.takeDockReopen())
    }

    @Test func aCleanRelaunchRestoresOneWindowAndANewBuildOrUncleanRunRestoresEveryWindow() {
        let clean = LaunchContinuity(running: false, build: "a")
        #expect(!LaunchContinuity.restoresEveryWindow(previous: clean, build: "a"))
        #expect(LaunchContinuity.restoresEveryWindow(previous: clean, build: "b"))
        #expect(LaunchContinuity.restoresEveryWindow(previous: LaunchContinuity(running: true, build: "a"), build: "a"))
        #expect(!LaunchContinuity.restoresEveryWindow(previous: nil, build: "a"))
    }

    @Test func theLaunchContinuityMarkerRoundTrips() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-launch-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        LaunchContinuity(running: true, build: "a").write(in: root)
        #expect(LaunchContinuity.read(in: root) == LaunchContinuity(running: true, build: "a"))
    }

    @Test func aNormalRelaunchRestoresOnlyTheFirstSavedWindowAndAnUpdateOrCrashRestoresEveryOne() {
        let first = UUID(), second = UUID()
        #expect(LaunchContinuity.accepts(first, launchWindowID: first, everyWindow: false))
        #expect(!LaunchContinuity.accepts(second, launchWindowID: first, everyWindow: false))
        #expect(LaunchContinuity.accepts(second, launchWindowID: first, everyWindow: true))
    }

    @Test func withNoFirstWindowIdentityAppKitRestoresNothingAndTheFallbackReopensIt() {
        #expect(!LaunchContinuity.accepts(nil, launchWindowID: nil, everyWindow: false))
        #expect(!LaunchContinuity.accepts(UUID(), launchWindowID: nil, everyWindow: false))
    }

    @Test func launchOpensAfterEitherOrderingOfTheTwoPhases() {
        var early = WindowRestorationLaunch()
        early.finishRestoration()
        #expect(!early.canPresent)
        early.finishLaunch()
        #expect(early.canPresent)
    }

    @Test func aCompletedLaunchWaitsThroughQuitAndResumesWhenQuitIsDeclined() {
        var launch = WindowRestorationLaunch()
        launch.finishLaunch()
        launch.finishRestoration()
        #expect(!launch.mayPresent(terminating: true) && launch.mayPresent(terminating: false))
        #expect(!launch.mayPresent(terminating: false, cancelled: true))
    }

    @Test func originalWindowRequestsWaitForEngineReadinessAndAPendingQuitDecision() {
        #expect(WindowRestorationLaunch.shouldDeferWindow(engineReady: true, terminating: true))
        #expect(WindowRestorationLaunch.shouldDeferWindow(engineReady: false, terminating: false))
        #expect(!WindowRestorationLaunch.shouldDeferWindow(engineReady: true, terminating: false))
    }

    @Test func onlyAReadyRegularMainStoreWindowCanOwnInitialLaunch() {
        #expect(WindowRestorationLaunch.isRegularLaunchOwner(mainStore: true, popup: false, ready: true))
        #expect(!WindowRestorationLaunch.isRegularLaunchOwner(mainStore: true, popup: true, ready: true))
        #expect(!WindowRestorationLaunch.isRegularLaunchOwner(mainStore: false, popup: false, ready: true))
        #expect(!WindowRestorationLaunch.isRegularLaunchOwner(mainStore: true, popup: false, ready: false))
    }

    @Test func aRegularKeyOrMainOwnerTakesPriorityThenLastActiveThenLastAvailable() {
        #expect(WindowRestorationLaunch.preferredOwner(keyOrMain: [false, true, false], lastActiveIndex: 0) == 1)
        #expect(WindowRestorationLaunch.preferredOwner(keyOrMain: [false, false, false], lastActiveIndex: 0) == 0)
        #expect(WindowRestorationLaunch.preferredOwner(keyOrMain: [false, false], lastActiveIndex: nil) == 1)
        #expect(WindowRestorationLaunch.preferredOwner(keyOrMain: [], lastActiveIndex: nil) == nil)
    }

    @Test func theSavedFallbackIsRestoredOnlyWhenNoOtherOwnerHoldsTheLaunch() {
        #expect(WindowRestorationLaunch.shouldRestoreFallback(hasRestoredOwner: false, hasOtherLaunchOwner: false))
        #expect(!WindowRestorationLaunch.shouldRestoreFallback(hasRestoredOwner: false, hasOtherLaunchOwner: true))
        #expect(!WindowRestorationLaunch.shouldRestoreFallback(hasRestoredOwner: true, hasOtherLaunchOwner: true))
    }

    @Test func deferredWindowActionsWaitForTheInitialOwnerAndKeepTheirOrder() {
        var gate = WindowRestorationLaunch()
        gate.deferAction(.newWindow)
        gate.deferAction(.blankWindow)
        gate.deferAction(.newWindow)
        #expect(gate.nextAction(initialBrowserOpened: false, terminating: false) == nil)
        gate.finishRestoration()
        gate.finishLaunch()
        #expect(gate.nextAction(initialBrowserOpened: true, terminating: true) == nil)
        #expect(gate.nextAction(initialBrowserOpened: true, terminating: false) == .newWindow)
        gate.completeAction()
        #expect(gate.nextAction(initialBrowserOpened: true, terminating: false) == .blankWindow)
        gate.completeAction()
        #expect(gate.nextAction(initialBrowserOpened: true, terminating: false) == .newWindow)
        gate.completeAction()
        #expect(gate.nextAction(initialBrowserOpened: true, terminating: false) == nil)
    }

    @Test func aBlockedOriginalOwnerNoteRequestStaysQueuedUntilDelivered() {
        var gate = WindowRestorationLaunch()
        gate.finishRestoration()
        gate.finishLaunch()
        let space = UUID(), profile = UUID()
        gate.deferAction(.newNote(spaceID: space, profileID: profile))
        let expected = WindowRestorationLaunch.Action.newNote(spaceID: space, profileID: profile)
        #expect(gate.nextAction(initialBrowserOpened: true, terminating: false) == expected)
        #expect(gate.nextAction(initialBrowserOpened: true, terminating: false) == expected)
        gate.completeAction()
        #expect(gate.nextAction(initialBrowserOpened: true, terminating: false) == nil)
    }

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

    @Test func aPreflightWindowRendersNoPageUntilItAdoptsAnActualOne() {
        var w = World()
        let ownership = NativePageOwnership(), windowB = UUID()
        var preflight = WindowPresentation(state: w.shared, ready: false, preferredProfileID: w.otherProfile.id)
        preflight.reconcile(w.shared, available: { ownership.canUse($0, owner: windowB) })
        #expect(!preflight.isReady && preflight.selectedTabIDs.isEmpty)
        #expect(preflight.activeSpaceID == w.otherSpace.id)
        w.shared.selectedTabIDs = [w.c.id]
        preflight.captureCommand(w.shared, available: { ownership.canUse($0, owner: windowB) })
        #expect(!preflight.isReady && preflight.projected(w.shared).selectedTabIDs.isEmpty)
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

    @Test func aLocalSelectionIsAShellOnlyPageWithoutANativeWrapper() {
        var w = World()
        let engineWindow = WindowPresentation(state: w.shared, ready: true)
        var local = w.shared
        local.tabs[0].url = "about:blank"
        var localWindow = WindowPresentation(state: local, ready: true)
        #expect(localWindow.isLocalSelection(w.a.id, state: local, hasNativeWrapper: false))
        #expect(!localWindow.isLocalSelection(w.a.id, state: local, hasNativeWrapper: true))
        local.tabs[0].url = ""
        #expect(localWindow.isLocalSelection(w.a.id, state: local, hasNativeWrapper: false))
        local.tabs[0].url = "parc://easel/" + UUID().uuidString
        #expect(localWindow.isLocalSelection(w.a.id, state: local, hasNativeWrapper: false))
        #expect(!engineWindow.isLocalSelection(w.a.id, state: w.shared, hasNativeWrapper: false))
        #expect(!localWindow.isLocalSelection(nil, state: local, hasNativeWrapper: false))
        localWindow.remove(w.a.id)
        localWindow.remove(w.c.id)
        #expect(localWindow.isLocalSelection(nil, state: local, hasNativeWrapper: false))
        let preflight = WindowPresentation(state: local, ready: false)
        #expect(!preflight.isLocalSelection(nil, state: local, hasNativeWrapper: false))
        w.shared.tabs[0].url = "https://example.test/result"
    }

    @MainActor struct Engine {
        var w = World()
        var state: BrowserState
        let favorite: BrowserTab
        let ownership = NativePageOwnership()
        let windowA = UUID()
        var window: WindowPresentation

        init() {
            state = w.shared
            state.activeSpaceID = w.firstSpace.id
            state.selectedTabIDs = [w.a.id, w.c.id]
            favorite = w.tab(w.firstSpace, kind: .favorite)
            state.tabs.append(favorite)
            window = WindowPresentation(state: state, ready: true)
        }

        func availableA(_ id: UUID) -> Bool { ownership.canUse(id, owner: windowA) }
    }

    @Test func theEngineCanFocusAnExistingSplitMemberAndRepeatedSelectionIsIdempotent() {
        var e = Engine()
        let r1 = e.window.selectExistingTab(e.w.c.id, state: e.state, available: e.availableA)
        #expect(r1)
        #expect(e.window.selectedTabIDs == [e.w.a.id, e.w.c.id])
        let r2 = e.window.selectExistingTab(e.w.c.id, state: e.state, available: e.availableA)
        #expect(r2)
        #expect(e.window.selectedTabIDs == [e.w.a.id, e.w.c.id])
    }

    @Test func theEngineRefusesPagesAnotherWindowHoldsAndUnknownPages() {
        var e = Engine()
        #expect(e.ownership.claim(e.w.b.id, owner: UUID(), page: "elsewhere"))
        let r3 = e.window.selectExistingTab(e.w.b.id, state: e.state, available: e.availableA)
        #expect(!r3)
        #expect(e.window.activeSpaceID == e.w.firstSpace.id && e.window.selectedTabIDs == [e.w.a.id, e.w.c.id])
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

    @Test func aSameProfileFavoriteIsSelectedInTheCurrentSpaceAndOrdinaryPagesSelectTheirOwnSpace() {
        var e = Engine()
        let originalTabs = e.state.tabs
        e.window.selectSpace(e.w.siblingSpace.id, state: e.state, available: e.availableA)
        let r7 = e.window.selectExistingTab(e.favorite.id, state: e.state, available: e.availableA)
        #expect(r7)
        #expect(e.window.activeSpaceID == e.w.siblingSpace.id && e.window.selectedTabIDs == [e.favorite.id])
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

    @MainActor struct Continuity {
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

    @Test func nativePageOwnershipRefusesCrossWindowUseStealingAndAliasing() {
        let w = World()
        let ownership = NativePageOwnership(), windowA = UUID(), windowB = UUID()
        #expect(ownership.claim(w.b.id, owner: windowB, page: "post-popup-page"))
        #expect(!ownership.canUse(w.b.id, owner: windowA))
        #expect(!ownership.claim(w.b.id, owner: windowA))
        #expect(!ownership.canAdopt("post-popup-page"))
        #expect(!ownership.claim(w.c.id, owner: windowA, page: "post-popup-page"))
        #expect(!ownership.claim(w.b.id, owner: windowB, page: "duplicate-popup-page"))
        #expect(ownership.canAdopt("duplicate-popup-page"))
        #expect(ownership.claim(w.b.id, owner: windowB, page: "post-popup-page"))
        #expect(ownership.owner(of: w.b.id) == windowB && ownership.owner(of: w.b.id) == ownership.claimSnapshot(w.b.id).owner
                && ownership.owner(of: w.c.id) == nil)
        ownership.release(w.b.id, owner: windowA)
        #expect(!ownership.canUse(w.b.id, owner: windowA))
    }

    @Test func teardownReleasesAWindowsClaimsAndAnActualCloseAllowsReopening() {
        let w = World()
        let ownership = NativePageOwnership(), windowA = UUID(), windowB = UUID()
        #expect(ownership.claim(w.a.id, owner: windowA, page: "real-opener-page"))
        #expect(ownership.claim(w.b.id, owner: windowB, page: "post-popup-page"))
        ownership.releaseAll(owner: windowB)
        #expect(ownership.canUse(w.b.id, owner: windowA) && ownership.canAdopt("post-popup-page"))
        #expect(!ownership.canUse(w.a.id, owner: windowB))
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

    @Test func backgroundAdoptionKeepsTheCurrentSelectionButTheFirstRealPageMakesAPreflightUsable() {
        var w = World()
        var preflight = WindowPresentation(state: w.shared, ready: true, preferredProfileID: w.otherProfile.id)
        preflight.adopt(w.b.id, state: w.shared, foreground: true)
        let background = w.tab(w.otherSpace)
        w.shared.tabs.append(background)
        preflight.adopt(background.id, state: w.shared, foreground: false)
        #expect(preflight.selectedTabIDs == [w.b.id])
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

    @MainActor struct Split {
        var w = World()
        let ownership = NativePageOwnership()
        let windowA = UUID()
        var left: WindowPresentation

        init() {
            left = WindowPresentation(state: w.shared, ready: true)
            _ = ownership.claim(w.a.id, owner: windowA, page: "real-opener-page")
            left.reconcile(w.shared, available: availableA)
        }

        func availableA(_ id: UUID) -> Bool { ownership.canUse(id, owner: windowA) }
    }

    @Test func splitCaptureRemovesDuplicateForeignOwnerAndForeignProfilePages() {
        var s = Split()
        s.w.shared.activeSpaceID = s.w.firstSpace.id
        s.w.shared.selectedTabIDs = [s.w.a.id, s.w.c.id, s.w.b.id, s.w.a.id]
        s.left.captureCommand(s.w.shared, available: s.availableA)
        #expect(s.left.selectedTabIDs == [s.w.a.id, s.w.c.id])
        s.left.remove(s.w.a.id)
        #expect(s.left.selectedTabIDs == [s.w.c.id])
    }

    @Test func theFocusSuccessorKeepsTheRemovedIndexElseTheNewLast() {
        let a = UUID(), c = UUID(), pin = UUID()
        #expect(BrowserSplitLayout.focusSuccessor([a, pin], removedAt: 1) == pin)
        #expect(BrowserSplitLayout.focusSuccessor([a, c], removedAt: 2) == c)
        #expect(BrowserSplitLayout.focusSuccessor([a], removedAt: nil) == a)
        #expect(BrowserSplitLayout.focusSuccessor([], removedAt: 0) == nil)
    }

    @Test func closingTheFocusedMiddleOrLastPaneFocusesTheNextOneInPlace() {
        var s = Split()
        s.w.shared.selectedTabIDs = [s.w.a.id, s.w.c.id, s.w.pin.id]
        s.left.captureCommand(s.w.shared, available: s.availableA)
        s.left.recordFocusedTab(s.w.c.id)
        s.left.remove(s.w.c.id)
        #expect(s.left.selectedTabIDs == [s.w.a.id, s.w.pin.id] && s.left.preferredFocusedTabID == s.w.pin.id)
        s.left.recordFocusedTab(s.w.pin.id)
        s.left.remove(s.w.pin.id)
        #expect(s.left.selectedTabIDs == [s.w.a.id] && s.left.preferredFocusedTabID == s.w.a.id)
    }

    @Test func theLastSavedTabClosesToStartAndNeverRecreatesItself() {
        var s = Split()
        s.w.shared.selectedTabIDs = [s.w.pin.id]
        s.left.captureCommand(s.w.shared, available: s.availableA)
        s.left.remove(s.w.pin.id)
        s.left.reconcile(s.w.shared, available: s.availableA)
        #expect(s.left.selectedTabIDs.isEmpty)
    }

    @Test func sharedRetirementRemovesTheActualLocalSelection() {
        var s = Split()
        s.w.shared.selectedTabIDs = [s.w.c.id]
        s.left.captureCommand(s.w.shared, available: s.availableA)
        s.w.shared.tabs[2].archivedAt = Date()
        s.left.reconcile(s.w.shared, available: s.availableA)
        #expect(s.left.selectedTabIDs.isEmpty)
    }

    @Test func aPageTransferReservationCapturesTheExactLiveOwnerAndRefusesWrongRequests() throws {
        let w = World()
        let moves = NativePageOwnership(), origin = UUID(), target = UUID(), third = UUID()
        #expect(moves.claim(w.a.id, owner: origin, page: "same-live-page"))
        #expect(moves.reserveTransfer(w.a.id, page: "wrong-page", from: origin, to: target) == nil)
        #expect(moves.reserveTransfer(w.a.id, page: "same-live-page", from: target, to: origin) == nil)
        #expect(moves.reserveTransfer(w.a.id, page: "same-live-page", from: origin, to: origin) == nil)
        let firstMove = try #require(moves.reserveTransfer(w.a.id, page: "same-live-page", from: origin, to: target))
        #expect(moves.isCurrent(firstMove))
        #expect(!moves.claim(w.a.id, owner: origin, page: "same-live-page"))
        #expect(!moves.claim(w.a.id, owner: target, page: "same-live-page"))
        #expect(!moves.canUse(w.a.id, owner: third) && !moves.canAdopt("same-live-page"))
        #expect(moves.reserveTransfer(w.a.id, page: "same-live-page", from: origin, to: third) == nil)
    }

    @Test func aRefusedTransferRetainsTheOriginalOwnerAndAStaleResultCannotConsumeAReplacement() throws {
        let w = World()
        let moves = NativePageOwnership(), origin = UUID(), target = UUID()
        #expect(moves.claim(w.a.id, owner: origin, page: "same-live-page"))
        let firstMove = try #require(moves.reserveTransfer(w.a.id, page: "same-live-page", from: origin, to: target))
        #expect(moves.finishTransfer(firstMove, moved: false))
        #expect(moves.canUse(w.a.id, owner: origin) && !moves.canUse(w.a.id, owner: target))
        #expect(!moves.finishTransfer(firstMove, moved: true))
        let secondMove = try #require(moves.reserveTransfer(w.a.id, page: "same-live-page", from: origin, to: target))
        #expect(!moves.finishTransfer(firstMove, moved: true) && moves.isCurrent(secondMove))
        #expect(moves.finishTransfer(secondMove, moved: true))
        #expect(moves.canUse(w.a.id, owner: target) && !moves.canUse(w.a.id, owner: origin))
        #expect(!moves.canAdopt("same-live-page"))
        #expect(!moves.claim(w.c.id, owner: target, page: "same-live-page"))
    }

    @Test func anIndependentRealPageCloseInvalidatesAReservationAndFreesItsIdentity() throws {
        let w = World()
        let moves = NativePageOwnership(), origin = UUID(), target = UUID()
        #expect(moves.claim(w.a.id, owner: origin, page: "same-live-page"))
        let first = try #require(moves.reserveTransfer(w.a.id, page: "same-live-page", from: origin, to: target))
        #expect(moves.finishTransfer(first, moved: true))
        let returnMove = try #require(moves.reserveTransfer(w.a.id, page: "same-live-page", from: target, to: origin))
        moves.release(w.a.id, owner: target)
        #expect(!moves.isCurrent(returnMove) && !moves.finishTransfer(returnMove, moved: true))
        #expect(moves.canAdopt("same-live-page"))
        #expect(moves.claim(w.a.id, owner: origin, page: "replacement-page"))
        #expect(!moves.finishTransfer(returnMove, moved: true))
        let teardown = try #require(moves.reserveTransfer(w.a.id, page: "replacement-page", from: origin, to: target))
        moves.releaseAll(owner: target)
        #expect(!moves.isCurrent(teardown) && moves.canUse(w.a.id, owner: origin))
    }

    @MainActor final class StoreFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-window-test-" + UUID().uuidString)
        let store: BrowserStore
        let original: UUID

        init() throws {
            store = try BrowserStore(directory: directory)
            original = store.open("https://example.test/original")
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func adopt() -> UUID {
            store.adoptNativePage(url: URL(string: "https://example.test/post-result"), title: "POST result",
                                  profilePath: store.independentEngineProfilePath(for: store.activeSpace.profileID),
                                  preferredSpaceID: store.activeSpaceID, select: false)!
        }
    }

    @Test func realStoreAdoptionPreservesTheOriginalWindowSelectionAndRecordsThePageOnce() throws {
        let s = try StoreFixture()
        var window = WindowPresentation(state: s.store.state, ready: true)
        let adopted = s.adopt()
        window.reconcile(s.store.state) { _ in true }
        #expect(window.selectedTabIDs == [s.original])
        #expect(s.store.state.tabs.count == 2 && s.store.state.selectedTabIDs == [s.original])
        try s.store.save()
        let loaded = try BrowserStore(directory: s.directory)
        #expect(loaded.state.tabs.filter { $0.id == adopted }.count == 1)
    }

    @Test func theStoreAcceptsOriginalSelectionAndSplitGeometryTogetherAndRefusesAForeignLayout() throws {
        let s = try StoreFixture()
        let adopted = s.adopt()
        let restored = BrowserSplitLayout(spaceID: s.store.activeSpaceID, tabIDs: [s.original, adopted],
                                          orientation: .vertical, widthFactors: [0.25, 0.75])
        #expect(s.store.setWindowPresentation(spaceID: s.store.activeSpaceID, selectedTabIDs: restored.tabIDs, splitLayout: restored))
        #expect(s.store.state.selectedTabIDs == restored.tabIDs && s.store.activeSplitLayout == restored)
        var wrongSpaceLayout = restored
        wrongSpaceLayout.spaceID = UUID()
        #expect(!s.store.setWindowPresentation(spaceID: s.store.activeSpaceID, selectedTabIDs: [s.original], splitLayout: wrongSpaceLayout))
        #expect(s.store.state.selectedTabIDs == restored.tabIDs && s.store.activeSplitLayout == restored)
    }

    @Test func anAddressCommandFromStartKeepsTheExactSavedTabAndWaitsForItsWrapper() throws {
        let s = try StoreFixture()
        let persisted = WindowPresentation(state: s.store.state, ready: true)
        let startTab = s.store.open("about:blank")
        var addressWindow = WindowPresentation(state: s.store.state, ready: true)
        #expect(addressWindow.isLocalSelection(startTab, state: s.store.state, hasNativeWrapper: false))
        let startCount = s.store.state.tabs.count
        s.store.navigate(startTab, input: "https://example.test/from-start")
        addressWindow.captureCommand(s.store.state) { _ in true }
        #expect(addressWindow.selectedTabIDs == [startTab] && s.store.state.tabs.count == startCount)
        #expect(!addressWindow.isLocalSelection(startTab, state: s.store.state, hasNativeWrapper: false))
        #expect(persisted.selectedTabIDs == [s.original])
    }

    @Test func anAddressCommandFromAnEaselKeepsTheExactSavedTabAndWaitsForNativeReadiness() throws {
        let s = try StoreFixture()
        var addressWindow = WindowPresentation(state: s.store.state, ready: true)
        let easelTab = try #require(s.store.openEasel(id: UUID(), title: "Address test"))
        addressWindow.captureCommand(s.store.state) { _ in true }
        #expect(addressWindow.isLocalSelection(easelTab, state: s.store.state, hasNativeWrapper: false))
        let count = s.store.state.tabs.count
        s.store.navigate(easelTab, input: "https://example.test/from-easel")
        addressWindow.captureCommand(s.store.state) { _ in true }
        #expect(addressWindow.selectedTabIDs == [easelTab] && s.store.state.tabs.count == count)
        #expect(!addressWindow.isLocalSelection(easelTab, state: s.store.state, hasNativeWrapper: false))
    }

    @MainActor struct Deletion {
        let w = World()
        var state: BrowserState
        let removal: FolderRemovalSelection
        var origin: WindowPresentation
        var peer: WindowPresentation

        init() {
            state = w.shared
            state.tabs = [w.a, w.b, w.c, w.pin]
            state.activeSpaceID = w.firstSpace.id
            state.selectedTabIDs = [w.a.id]
            state.selectionBySpace[w.firstSpace.id.uuidString] = [w.a.id]
            origin = WindowPresentation(state: state, ready: true)
            peer = WindowPresentation(state: state, ready: true)
            removal = FolderRemovalSelection(spaceID: w.firstSpace.id, profileID: w.firstSpace.profileID,
                original: [w.a.id], originalFocus: w.a.id, tabIDs: [w.c.id], focusedTabID: w.c.id)
            state.tabs[state.tabs.firstIndex { $0.id == w.a.id }!].archivedAt = Date()
            state.selectedTabIDs = [w.c.id]
            origin.reconcile(state) { _ in true }
            peer.reconcile(state) { _ in true }
        }
    }

    @Test func theOriginalWindowAcceptsItsCompletedCloseDecisionAndAnotherWindowNeverAdoptsIt() {
        var d = Deletion()
        let finished = d.origin.finishFolderRemoval(d.removal, state: d.state, available: { _ in true })
        #expect(finished)
        #expect(d.origin.selectedTabIDs == [d.w.c.id] && d.origin.preferredFocusedTabID == d.w.c.id)
        #expect(d.peer.selectedTabIDs.isEmpty)
    }

    @Test func aNewerSpaceChoiceOrAnAcquiredReplacementRejectsDelayedFolderFocus() {
        let d = Deletion()
        var moved = d.peer
        moved.selectSpace(d.w.otherSpace.id, state: d.state) { _ in true }
        let movedFinished = moved.finishFolderRemoval(d.removal, state: d.state, available: { _ in true })
        #expect(!movedFinished)
        var transferred = d.peer
        let id = d.w.c.id
        let transferFinished = transferred.finishFolderRemoval(d.removal, state: d.state, available: { $0 != id })
        #expect(!transferFinished)
    }

    @Test func aNewerSelectionInTheOriginalWindowWinsOverDelayedCompletion() {
        let d = Deletion()
        var newer = d.peer
        _ = newer.selectExistingTab(d.w.pin.id, state: d.state) { _ in true }
        let finished = newer.finishFolderRemoval(d.removal, state: d.state, available: { _ in true })
        #expect(!finished && newer.selectedTabIDs == [d.w.pin.id])
    }

    @Test func aChangedDestinationProfileInvalidatesTheOldDecision() {
        var d = Deletion()
        var retired = d.state
        retired.spaces[retired.spaces.firstIndex { $0.id == d.w.firstSpace.id }!].profileID = d.w.otherProfile.id
        let finished = d.peer.finishFolderRemoval(d.removal, state: retired, available: { _ in true })
        #expect(!finished)
    }

    @Test func undoingAFolderDeletionRestoresTheOriginalSplitAndFocusOnlyInTheOriginalWindow() throws {
        let s = try StoreFixture()
        let store = s.store
        let folder = store.createFolder(name: "Undo source")
        let undoA = store.open("https://undo-a.test")
        let undoB = store.open("https://undo-b.test")
        let space = store.activeSpaceID, profile = store.activeSpace.profileID
        store.selectTab(undoA)
        store.selectTab(undoB, extendingSplit: true)
        let group = try #require(store.activeSplitLayout)
        _ = try store.moveSidebarItem(.split(group.id), to: .init(spaceID: space, folderID: folder, section: .pinned), before: nil,
                                      expected: SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)!)
        store.selectTab(undoA)
        _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.3, 0.7])
        let target = try #require(FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: store.state))
        let selection = try #require(FolderRemovalSelection.resolve(target: target, state: store.state,
            selected: [undoA, undoB], focused: undoB, available: { _ in true }))
        var origin = WindowPresentation(state: store.state, ready: true)
        var peer = WindowPresentation(state: store.state, ready: true)
        var record: FolderDeletionUndo?
        store.deleteFolder(target, selection: selection, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
        origin.reconcile(store.state) { _ in true }
        peer.reconcile(store.state) { _ in true }
        let undo = try #require(record)
        #expect(try store.undoFolderDeletion(undo, shouldCommit: { true }))
        peer.reconcile(store.state) { _ in true }
        #expect(peer.selectedTabIDs.isEmpty)
        let blocked = origin.finishFolderUndo(undo, state: store.state, available: { $0 != undoA })
        #expect(!blocked)
        let finished = origin.finishFolderUndo(undo, state: store.state, available: { _ in true })
        #expect(finished)
        #expect(origin.selectedTabIDs == [undoA, undoB] && origin.preferredFocusedTabID == undoB)
        #expect(origin.splitLayout?.orientation == .vertical && origin.splitLayout?.widthFactors == [0.3, 0.7])
        let again = try #require(FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: store.state))
        store.deleteFolder(again, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
        let secondUndo = try #require(record)
        _ = try store.undoFolderDeletion(secondUndo, shouldCommit: { true })
        let background = peer.finishFolderUndo(secondUndo, state: store.state, available: { _ in true })
        #expect(!background)
    }

    @MainActor struct Frozen {
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

    func splitFrozen() -> (Frozen, BrowserSplitLayout) {
        var f = Frozen()
        let layout = BrowserSplitLayout(spaceID: f.space.id, tabIDs: [f.x.id, f.y.id], orientation: .vertical, widthFactors: [0.25, 0.75])
        f.state.splitLayouts = [layout]
        f.state.selectedTabIDs = [f.x.id, f.y.id]
        f.source = WindowPresentation(state: f.state, ready: true)
        f.source.recordFocusedTab(f.x.id)
        return (f, layout)
    }

    @Test func aSplitPanesPlaceholderKeepsTheSplitGeometryAndMovesFocusToTheLivePane() {
        var (f, layout) = splitFrozen()
        #expect(f.move(f.x.id, from: f.sourceWindow, to: f.selectingWindow))
        f.source.leavePlaceholder(f.x.id, state: f.state)
        f.source.reconcile(f.state, available: f.usable)
        #expect(f.source.selectedTabIDs == [f.y.id] && f.source.displayedTabIDs == [f.x.id, f.y.id])
        #expect(f.source.displayedSplitLayout == layout && f.source.preferredFocusedTabID == f.y.id)
        #expect(f.move(f.x.id, from: f.selectingWindow, to: f.sourceWindow))
        f.source.reconcile(f.state, available: f.usable)
        #expect(f.source.selectedTabIDs == [f.x.id, f.y.id] && f.source.splitLayout == layout)
    }

    @Test func closingTheLivePaneLeavesThePlaceholderAloneAndSelectingAnotherTabReplacesIt() {
        var (f, _) = splitFrozen()
        #expect(f.move(f.x.id, from: f.sourceWindow, to: f.selectingWindow))
        f.source.leavePlaceholder(f.x.id, state: f.state)
        var closedPartner = f.state
        closedPartner.tabs.removeAll { $0.id == f.y.id }
        closedPartner.splitLayouts = []
        f.source.reconcile(closedPartner, available: f.usable)
        #expect(f.source.selectedTabIDs.isEmpty && f.source.displayedTabIDs == [f.x.id] && f.source.displayedSplitLayout == nil)
        var replaced = closedPartner
        replaced.selectedTabIDs = [f.z.id]
        f.source.captureCommand(replaced, available: f.usable)
        #expect(f.source.selectedTabIDs == [f.z.id] && f.source.displayedTabIDs == [f.z.id] && !f.source.showsPlaceholder(f.x.id))
    }

    @Test func anArchivedPageLeavesNoPlaceholderAndAnUnshownPageNeverGetsOne() {
        let (f, _) = splitFrozen()
        var archivedSource = WindowPresentation(state: f.state, ready: true)
        archivedSource.leavePlaceholder(f.x.id, state: f.state)
        var archivedState = f.state
        archivedState.tabs[archivedState.tabs.firstIndex { $0.id == f.x.id }!].archivedAt = Date()
        archivedSource.reconcile(archivedState, available: f.usable)
        #expect(!archivedSource.showsPlaceholder(f.x.id) && archivedSource.displayedTabIDs == [f.y.id])
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

    @Test func aReturnPassesOverRefusingWindowsAndBlocksWhenEveryPlaceholderWindowRefuses() {
        let source = UUID(), selecting = UUID()
        let now = Date(), older = now.addingTimeInterval(-60)
        var refusing = [
            PageReparenting.Candidate(windowID: source, displaysPlaceholder: true, showsPlaceholder: true, lastActive: older),
            PageReparenting.Candidate(windowID: selecting, displaysPlaceholder: false, showsPlaceholder: true, lastActive: now),
        ]
        refusing[1].canReceive = false
        #expect(PageReparenting.returnDestination(refusing, trigger: .ownerClosing) == source)
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

    @Test func rowActionsMoveAnotherWindowsPageHereOrActInPlaceAndRefuseWhenBusyOrUnavailable() {
        #expect(PageReparenting.rowAction(closing: false, busy: false, usableHere: false, heldElsewhere: true) == .moveHere)
        #expect(PageReparenting.rowAction(closing: true, busy: false, usableHere: false, heldElsewhere: true) == .moveHereThenClose)
        #expect(PageReparenting.rowAction(closing: false, busy: false, usableHere: true, heldElsewhere: false) == .here)
        #expect(PageReparenting.rowAction(closing: true, busy: false, usableHere: true, heldElsewhere: false) == .here)
        #expect(PageReparenting.rowAction(closing: false, busy: true, usableHere: false, heldElsewhere: true) == nil)
        #expect(PageReparenting.rowAction(closing: true, busy: true, usableHere: true, heldElsewhere: false) == nil)
        #expect(PageReparenting.rowAction(closing: false, busy: false, usableHere: false, heldElsewhere: false) == nil)
    }

    @MainActor struct CloseMove {
        var state = BrowserState.initial()
        let held: BrowserTab
        let mine: BrowserTab
        let moves = NativePageOwnership()
        let holderWindow = UUID()
        let viewerWindow = UUID()
        let bystanderWindow = UUID()
        var holder: WindowPresentation
        var viewer: WindowPresentation

        init() {
            let space = state.spaces[0]
            held = World.tab(space)
            mine = World.tab(space)
            state.tabs = [held, mine]
            state.selectedTabIDs = [held.id]
            holder = WindowPresentation(state: state, ready: true)
            viewer = WindowPresentation(state: state, ready: true)
        }

        func usable(by window: UUID) -> (UUID) -> Bool { { moves.canUse($0, owner: window) } }

        func move(from source: UUID, to destination: UUID) -> Bool {
            guard let reservation = moves.reserveTransfer(held.id, page: "close-held", from: source, to: destination) else { return false }
            return moves.finishTransfer(reservation, moved: true)
        }

        mutating func holderTakesThePage() -> Bool {
            let claimed = moves.claim(held.id, owner: viewerWindow, page: "close-held")
            let left = viewer.leavePlaceholder(held.id, state: state)
            let moved = move(from: viewerWindow, to: holderWindow)
            viewer.reconcile(state, available: usable(by: viewerWindow))
            holder.reconcile(state, available: usable(by: holderWindow))
            return claimed && left && moved
        }
    }

    @Test func theWindowAPageLeftShowsItsPlaceholderWithNoRowSelected() {
        var m = CloseMove()
        let taken = m.holderTakesThePage()
        #expect(taken)
        #expect(m.viewer.selectedTabIDs.isEmpty && m.viewer.displayedPlaceholders == [m.held.id])
    }

    @Test func closingFromThePlaceholderWindowMovesThePageThereAndAClosedThatCannotBeginHandsItBack() {
        var m = CloseMove()
        let taken = m.holderTakesThePage()
        #expect(taken)
        let before = (m.viewer.selectedTabIDs, m.viewer.displayedTabIDs, m.viewer.displayedPlaceholders)
        let movedBack = m.move(from: m.holderWindow, to: m.viewerWindow)
        let left = m.holder.leavePlaceholder(m.held.id, state: m.state)
        #expect(movedBack && left)
        m.viewer.adopt(m.held.id, state: m.state, foreground: false)
        m.viewer.reconcile(m.state, available: m.usable(by: m.viewerWindow))
        m.holder.reconcile(m.state, available: m.usable(by: m.holderWindow))
        #expect(m.viewer.selectedTabIDs == [m.held.id] && m.viewer.displayedPlaceholders.isEmpty)
        let handedBack = m.move(from: m.viewerWindow, to: m.holderWindow)
        let viewerLeft = m.viewer.leavePlaceholder(m.held.id, state: m.state)
        #expect(handedBack && viewerLeft)
        m.holder.adopt(m.held.id, state: m.state, foreground: false)
        m.holder.reconcile(m.state, available: m.usable(by: m.holderWindow))
        m.viewer.reconcile(m.state, available: m.usable(by: m.viewerWindow))
        #expect(m.viewer.selectedTabIDs == before.0 && m.viewer.displayedTabIDs == before.1 && m.viewer.displayedPlaceholders == before.2)
        #expect(m.holder.selectedTabIDs == [m.held.id] && m.holder.displayedPlaceholders.isEmpty)
    }

    @Test func aPageMovedToABystanderOnlyToCloseArrivesInTheBackgroundAndLeavesNothingBehind() {
        var m = CloseMove()
        let taken = m.holderTakesThePage()
        #expect(taken)
        m.state.selectedTabIDs = [m.mine.id]
        var bystander = WindowPresentation(state: m.state, ready: true)
        let moved = m.move(from: m.holderWindow, to: m.bystanderWindow)
        let left = m.holder.leavePlaceholder(m.held.id, state: m.state)
        #expect(moved && left)
        bystander.adopt(m.held.id, state: m.state, foreground: false)
        bystander.reconcile(m.state, available: m.usable(by: m.bystanderWindow))
        #expect(bystander.selectedTabIDs == [m.mine.id] && !bystander.displayedTabIDs.contains(m.held.id))
        let back = m.move(from: m.bystanderWindow, to: m.holderWindow)
        let bystanderLeft = bystander.leavePlaceholder(m.held.id, state: m.state)
        #expect(back && !bystanderLeft)
        m.holder.adopt(m.held.id, state: m.state, foreground: false)
        m.holder.reconcile(m.state, available: m.usable(by: m.holderWindow))
        bystander.reconcile(m.state, available: m.usable(by: m.bystanderWindow))
        #expect(bystander.selectedTabIDs == [m.mine.id] && !bystander.hasPlaceholders && m.holder.selectedTabIDs == [m.held.id])
    }

    @Test func closeRefusalExplainsAStoppedCloseAndAnUnsavedNote() {
        #expect(PageReparenting.closeRefusal(unsavedNotes: false, reason: nil) == nil)
        #expect(PageReparenting.closeRefusal(unsavedNotes: false, reason: "A page is still opening.") == .explain("A page is still opening."))
        if case .explain(let message) = PageReparenting.closeRefusal(unsavedNotes: true, reason: "A page is still opening.") {
            #expect(message.contains("Note"))
        } else {
            Issue.record("a Note that couldn't save explains itself")
        }
    }
}
