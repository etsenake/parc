import Foundation

@main
struct WindowPresentationTests {
    @MainActor
    static func main() throws {
        var assertions = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            assertions += 1
            precondition(value(), message)
        }
        var launch = WindowRestorationLaunch()
        launch.deferDockReopen()
        launch.finishLaunch()
        expect(!launch.canPresent && !launch.takeDockReopen(), "launch waits for original window restoration")
        launch.finishRestoration()
        expect(launch.canPresent && launch.takeDockReopen() && !launch.takeDockReopen(),
               "deferred Dock request drains once after both launch phases")
        let clean = LaunchContinuity(running: false, build: "a")
        expect(!LaunchContinuity.restoresEveryWindow(previous: clean, build: "a"), "a clean relaunch restores one window")
        expect(LaunchContinuity.restoresEveryWindow(previous: clean, build: "b"), "a new build restores every window")
        expect(LaunchContinuity.restoresEveryWindow(previous: LaunchContinuity(running: true, build: "a"), build: "a"),
               "a run that never ended cleanly restores every window")
        expect(!LaunchContinuity.restoresEveryWindow(previous: nil, build: "a"), "a first launch restores one window")
        let continuityRoot = FileManager.default.temporaryDirectory.appendingPathComponent("parc-launch-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: continuityRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: continuityRoot) }
        LaunchContinuity(running: true, build: "a").write(in: continuityRoot)
        expect(LaunchContinuity.read(in: continuityRoot) == LaunchContinuity(running: true, build: "a"), "the marker round-trips")
        let first = UUID(), second = UUID()
        expect(LaunchContinuity.accepts(first, launchWindowID: first, everyWindow: false)
               && !LaunchContinuity.accepts(second, launchWindowID: first, everyWindow: false)
               && LaunchContinuity.accepts(second, launchWindowID: first, everyWindow: true),
               "a normal relaunch restores only the first saved window; an update or a crash restores every one")
        expect(!LaunchContinuity.accepts(nil, launchWindowID: nil, everyWindow: false)
               && !LaunchContinuity.accepts(first, launchWindowID: nil, everyWindow: false),
               "with no first window identity AppKit restores nothing and the launch fallback reopens it")
        var earlyRestoration = WindowRestorationLaunch()
        earlyRestoration.finishRestoration()
        expect(!earlyRestoration.canPresent, "early AppKit completion waits for application readiness")
        earlyRestoration.finishLaunch()
        expect(earlyRestoration.canPresent, "launch opens after either ordering of the two phases")
        expect(!launch.mayPresent(terminating: true) && launch.mayPresent(terminating: false),
               "completed launch waits through quit and resumes when quit is declined")
        expect(!launch.mayPresent(terminating: false, cancelled: true),
               "shutdown cancellation prevents reentrant AppKit completion from presenting")
        expect(WindowRestorationLaunch.shouldDeferWindow(engineReady: true, terminating: true)
               && WindowRestorationLaunch.shouldDeferWindow(engineReady: false, terminating: false)
               && !WindowRestorationLaunch.shouldDeferWindow(engineReady: true, terminating: false),
               "original window requests wait for engine readiness and a pending quit decision")
        expect(WindowRestorationLaunch.isRegularLaunchOwner(mainStore: true, popup: false, ready: true)
               && !WindowRestorationLaunch.isRegularLaunchOwner(mainStore: true, popup: true, ready: true)
               && !WindowRestorationLaunch.isRegularLaunchOwner(mainStore: false, popup: false, ready: true)
               && !WindowRestorationLaunch.isRegularLaunchOwner(mainStore: true, popup: false, ready: false),
               "only a ready regular main-store window can own initial launch")
        expect(WindowRestorationLaunch.preferredOwner(keyOrMain: [false, true, false], lastActiveIndex: 0) == 1
               && WindowRestorationLaunch.preferredOwner(keyOrMain: [false, false, false], lastActiveIndex: 0) == 0
               && WindowRestorationLaunch.preferredOwner(keyOrMain: [false, false], lastActiveIndex: nil) == 1
               && WindowRestorationLaunch.preferredOwner(keyOrMain: [], lastActiveIndex: nil) == nil,
               "regular key or main owner takes priority, then last active and last available")
        expect(WindowRestorationLaunch.shouldRestoreFallback(hasRestoredOwner: false, hasOtherLaunchOwner: false),
               "an early download-only owner still permits the saved fallback")
        expect(!WindowRestorationLaunch.shouldRestoreFallback(hasRestoredOwner: false, hasOtherLaunchOwner: true),
               "the onboarding-prepared browser remains the original launch owner")
        expect(!WindowRestorationLaunch.shouldRestoreFallback(hasRestoredOwner: true, hasOtherLaunchOwner: true),
               "AppKit-restored owners do not cause duplicate fallback windows")
        var actionGate = WindowRestorationLaunch()
        actionGate.deferAction(.newWindow); actionGate.deferAction(.blankWindow); actionGate.deferAction(.newWindow)
        expect(actionGate.nextAction(initialBrowserOpened: false, terminating: false) == nil,
               "explicit window requests wait for the initial owner")
        actionGate.finishRestoration(); actionGate.finishLaunch()
        expect(actionGate.nextAction(initialBrowserOpened: true, terminating: true) == nil,
               "quit cannot discard deferred requests")
        expect(actionGate.nextAction(initialBrowserOpened: true, terminating: false) == .newWindow,
               "first admitted request remains at the head until delivered")
        actionGate.completeAction()
        expect(actionGate.nextAction(initialBrowserOpened: true, terminating: false) == .blankWindow,
               "Blank Window keeps its original order and command-bar distinction")
        actionGate.completeAction()
        expect(actionGate.nextAction(initialBrowserOpened: true, terminating: false) == .newWindow,
               "repeated requests remain distinct")
        let noteSpace = UUID(), noteProfile = UUID()
        actionGate.completeAction(); actionGate.deferAction(.newNote(spaceID: noteSpace, profileID: noteProfile))
        expect(actionGate.nextAction(initialBrowserOpened: true, terminating: false) == .newNote(spaceID: noteSpace, profileID: noteProfile)
               && actionGate.nextAction(initialBrowserOpened: true, terminating: false) == .newNote(spaceID: noteSpace, profileID: noteProfile),
               "a blocked original-owner Note request remains queued")
        actionGate.completeAction()
        expect(actionGate.nextAction(initialBrowserOpened: true, terminating: false) == nil,
               "delivered requests are consumed once")
        var shared = BrowserState.initial()
        let firstSpace = shared.spaces[0]
        let otherProfile = BrowserProfile(id: UUID(), name: "Other profile")
        let otherSpace = BrowserSpace(id: UUID(), name: "Other Space", symbol: "circle", color: "112233", profileID: otherProfile.id)
        let siblingSpace = BrowserSpace(id: UUID(), name: "Same profile", symbol: "circle", color: "112233", profileID: firstSpace.profileID)
        shared.profiles.append(otherProfile)
        shared.spaces += [otherSpace, siblingSpace]
        func tab(_ space: BrowserSpace, kind: TabKind = .today) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID,
                       url: "https://example.test/result", title: "Result", kind: kind,
                       createdAt: Date(), lastAccessed: Date(), savedURL: "https://example.test/", savedTitle: "Saved")
        }
        let a = tab(firstSpace), b = tab(otherSpace), c = tab(firstSpace), pin = tab(firstSpace, kind: .pinned)
        shared.tabs = [a, b, c, pin]
        shared.selectedTabIDs = [a.id]
        shared.selectionBySpace[otherSpace.id.uuidString] = [b.id]
        let firstRecord = BrowserWindowRecord(sidebarWidth: 230, id: UUID(), focusedSpaceID: firstSpace.id,
                                              selectedTabIDs: [a.id, c.id], focusedTabID: c.id)
        let secondRecord = BrowserWindowRecord(sidebarWidth: 250, id: UUID(), focusedSpaceID: otherSpace.id,
                                               selectedTabIDs: [b.id], focusedTabID: b.id)
        var restoredFirst = WindowPresentation(state: shared, ready: true, restoredRecord: firstRecord)
        var restoredSecond = WindowPresentation(state: shared, ready: true, restoredRecord: secondRecord)
        restoredFirst.reconcile(shared, available: { _ in true }); restoredSecond.reconcile(shared, available: { _ in true })
        expect(restoredFirst.activeSpaceID == firstSpace.id && restoredFirst.selectedTabIDs == [a.id, c.id]
               && restoredFirst.preferredFocusedTabID == c.id, "first window restores its own split and focused pane")
        expect(restoredSecond.activeSpaceID == otherSpace.id && restoredSecond.selectedTabIDs == [b.id],
               "second window restores its own Space and selection")
        var splitAdoption = restoredFirst
        let originalSelection = splitAdoption.sessionSelection
        let child = tab(firstSpace)
        shared.tabs.append(child)
        splitAdoption.recordCreation(child.id, state: shared)
        splitAdoption.adopt(child.id, state: shared, foreground: false)
        splitAdoption.reconcile(shared, available: { _ in true })
        expect(splitAdoption.sessionSelection == originalSelection &&
               splitAdoption.selectedTabIDs == [a.id, c.id] &&
               splitAdoption.preferredFocusedTabID == c.id,
               "background split child preserves original panes and focus through reconciliation")
        var refusedSplit = restoredFirst
        refusedSplit.recordCreation(child.id, state: shared)
        refusedSplit.adopt(child.id, state: shared, foreground: false)
        expect(refusedSplit.sessionSelection == originalSelection,
               "refused split adopted in background keeps the original selection")
        var transferSource = restoredFirst
        let beforeRemoval = transferSource.sessionSelection
        transferSource.remove(a.id)
        expect(transferSource.preferredFocusedTabID == c.id && transferSource.sessionSelection != beforeRemoval,
               "removing a nonfocused pane changes the session snapshot")
        var transferShell = WindowPresentation(state: shared, ready: false)
        let beforeAdoption = transferShell.sessionSelection
        transferShell.adopt(a.id, state: shared, foreground: false)
        expect(transferShell.isReady && transferShell.sessionSelection != beforeAdoption,
               "first background adoption changes the session snapshot")
        var retiredSpace = secondRecord; retiredSpace.focusedSpaceID = UUID()
        var fallback = WindowPresentation(state: shared, ready: true, restoredRecord: retiredSpace)
        fallback.reconcile(shared, available: { _ in true })
        expect(fallback.activeSpaceID == firstSpace.id && fallback.selectedTabIDs.isEmpty,
               "a missing Space falls back without adopting another window's selection")
        var incomplete = firstRecord; incomplete.selectedTabIDs = nil
        let incompleteWindow = WindowPresentation(state: shared, ready: true, restoredRecord: incomplete)
        expect(incompleteWindow.activeSpaceID == firstSpace.id && incompleteWindow.selectedTabIDs.isEmpty,
               "a partially saved presentation does not borrow the shared selection")
        incomplete = firstRecord; incomplete.focusedSpaceID = nil
        let missingOwner = WindowPresentation(state: shared, ready: true, restoredRecord: incomplete)
        expect(missingOwner.activeSpaceID == firstSpace.id && missingOwner.selectedTabIDs.isEmpty,
               "a missing Space identity cannot route saved panes into another window")
        var denied = WindowPresentation(state: shared, ready: true, restoredRecord: firstRecord)
        denied.reconcile(shared, available: { $0 != c.id })
        expect(denied.selectedTabIDs == [a.id] && denied.preferredFocusedTabID == a.id,
               "an unavailable pane is not stolen from another owner")
        let pending = WindowPresentation(state: shared, ready: false, restoredRecord: firstRecord)
        expect(!pending.isReady && pending.selectedTabIDs.isEmpty, "an unready shell does not revive a saved page")
        let ownership = NativePageOwnership(), windowA = UUID(), windowB = UUID()
        func availableA(_ id: UUID) -> Bool { ownership.canUse(id, owner: windowA) }
        func availableB(_ id: UUID) -> Bool { ownership.canUse(id, owner: windowB) }
        var left = WindowPresentation(state: shared, ready: true)
        expect(ownership.claim(a.id, owner: windowA, page: "real-opener-page"), "claim original actual page")
        var preflight = WindowPresentation(state: shared, ready: false, preferredProfileID: otherProfile.id)
        preflight.reconcile(shared, available: availableB)
        expect(!preflight.isReady && preflight.selectedTabIDs.isEmpty, "initial Combine state must not render a preflight page")
        expect(preflight.activeSpaceID == otherSpace.id, "preflight uses incoming profile")
        shared.selectedTabIDs = [c.id]
        shared.tabs[0].title = "Changed by live page"
        preflight.captureCommand(shared, available: availableB)
        expect(!preflight.isReady && preflight.projected(shared).selectedTabIDs.isEmpty, "publication cannot activate preflight")
        left.reconcile(shared, available: availableA)
        expect(left.selectedTabIDs == [a.id], "metadata publication cannot replace another physical window's selected page")
        expect(left.projected(shared).tabs[0].title == "Changed by live page", "shared metadata still refreshes")
        expect(ownership.claim(b.id, owner: windowB, page: "post-popup-page"), "claim actual incoming popup")
        preflight.adopt(b.id, state: shared, foreground: true)
        expect(preflight.isReady && preflight.selectedTabIDs == [b.id], "actual adopted page activates shell")
        expect(preflight.activeSpaceID == otherSpace.id, "adoption selects compatible Space")
        expect(shared.selectedTabIDs == [c.id], "adoption does not rewrite shared selection")

        var engineState = shared
        engineState.activeSpaceID = firstSpace.id
        engineState.selectedTabIDs = [a.id, c.id]
        let favorite = tab(firstSpace, kind: .favorite)
        engineState.tabs.append(favorite)
        var engineWindow = WindowPresentation(state: engineState, ready: true)
        let originalTabs = engineState.tabs
        var localState = engineState
        localState.tabs[0].url = "about:blank"
        var localWindow = WindowPresentation(state: localState, ready: true)
        expect(localWindow.isLocalSelection(a.id, state: localState, hasNativeWrapper: false), "ready Start selection explicitly deselects the native Browser")
        expect(!localWindow.isLocalSelection(a.id, state: localState, hasNativeWrapper: true), "a still-creating or live web wrapper is not a Start deselection")
        localState.tabs[0].url = ""
        expect(localWindow.isLocalSelection(a.id, state: localState, hasNativeWrapper: false), "a saved blank tab is local")
        localState.tabs[0].url = "parc://easel/" + UUID().uuidString
        expect(localWindow.isLocalSelection(a.id, state: localState, hasNativeWrapper: false), "Easel selection explicitly deselects the native Browser")
        expect(!engineWindow.isLocalSelection(a.id, state: engineState, hasNativeWrapper: false), "missing web wrapper must not fabricate a local deselection")
        expect(!localWindow.isLocalSelection(nil, state: localState, hasNativeWrapper: false), "missing focused identity does not erase a nonempty selection")
        localWindow.remove(a.id); localWindow.remove(c.id)
        expect(localWindow.isLocalSelection(nil, state: localState, hasNativeWrapper: false), "ready empty window explicitly deselects the native Browser")
        let localPreflight = WindowPresentation(state: localState, ready: false)
        expect(!localPreflight.isLocalSelection(nil, state: localState, hasNativeWrapper: false), "initial preflight does not send a native deselection")
        expect(engineWindow.selectExistingTab(c.id, state: engineState, available: availableA), "engine can focus an existing split member")
        expect(engineWindow.selectedTabIDs == [a.id, c.id], "engine selection retains split order and membership")
        expect(engineWindow.selectExistingTab(c.id, state: engineState, available: availableA), "repeated current selection is idempotent")
        expect(engineWindow.selectedTabIDs == [a.id, c.id], "repeated selection does not collapse the split")
        expect(!engineWindow.selectExistingTab(b.id, state: engineState, available: availableA), "another window's live page is not selected")
        expect(engineWindow.activeSpaceID == firstSpace.id && engineWindow.selectedTabIDs == [a.id, c.id], "refused ownership leaves presentation intact")
        expect(!engineWindow.selectExistingTab(UUID(), state: engineState, available: availableA), "unknown native page cannot create a model record")
        expect(!preflight.selectExistingTab(a.id, state: engineState, available: { _ in false }), "unavailable page cannot alter a preflight window")
        var notReady = WindowPresentation(state: engineState, ready: false)
        expect(!notReady.selectExistingTab(a.id, state: engineState, available: availableA) && !notReady.isReady, "selection cannot replace real first-page adoption")
        var archived = engineState
        archived.tabs[2].archivedAt = Date()
        expect(!engineWindow.selectExistingTab(c.id, state: archived, available: availableA), "archived page callback is refused")
        expect(engineWindow.selectedTabIDs == [a.id, c.id], "stale archived callback cannot partially prune current presentation")
        engineWindow.selectSpace(siblingSpace.id, state: engineState, available: availableA)
        expect(engineWindow.selectExistingTab(favorite.id, state: engineState, available: availableA), "same-profile favorite can be selected in the current Space")
        expect(engineWindow.activeSpaceID == siblingSpace.id && engineWindow.selectedTabIDs == [favorite.id], "favorite does not jump back to its original Space")
        expect(engineWindow.selectExistingTab(c.id, state: engineState, available: availableA), "existing ordinary page can select its own Space")
        expect(engineWindow.activeSpaceID == firstSpace.id && engineWindow.selectedTabIDs == [c.id], "non-split target becomes the single current page")
        expect(engineState.tabs == originalTabs, "presentation selection does not navigate, duplicate or edit tab records")
        var transferDestination = WindowPresentation(state: engineState, ready: true)
        transferDestination.selectSpace(siblingSpace.id, state: engineState, available: availableA)
        transferDestination.adopt(favorite.id, state: engineState, foreground: true)
        expect(transferDestination.activeSpaceID == siblingSpace.id && transferDestination.selectedTabIDs == [favorite.id],
               "an adopted Favorite stays in the destination window's current Space")
        var optionState = engineState
        optionState.selectedTabIDs = [a.id]
        var optionDestination = WindowPresentation(state: optionState, ready: true)
        optionDestination.adopt(favorite.id, state: optionState, foreground: false)
        expect(optionDestination.activeSpaceID == firstSpace.id && optionDestination.selectedTabIDs == [a.id],
               "a Favorite moved for an Option release keeps the destination's panes until placement")

        var continuityState = engineState
        continuityState.selectedTabIDs = [a.id, c.id, pin.id]
        continuityState.selectionBySpace[firstSpace.id.uuidString] = continuityState.selectedTabIDs
        let originalLayout = BrowserSplitLayout(spaceID: firstSpace.id,
            tabIDs: [a.id, c.id, pin.id], orientation: .vertical, widthFactors: [0.2, 0.3, 0.5])
        continuityState.splitLayouts = [originalLayout]
        var returning = WindowPresentation(state: continuityState, ready: true)
        returning.recordFocusedTab(c.id)
        returning.selectSpace(siblingSpace.id, state: continuityState, available: { _ in true })
        continuityState.selectedTabIDs = [pin.id]
        returning.reconcile(continuityState, available: { _ in true })
        returning.selectSpace(firstSpace.id, state: continuityState, available: { _ in true })
        expect(returning.selectedTabIDs == [a.id, c.id, pin.id], "another window's publication does not replace remembered split")
        expect(returning.preferredFocusedTabID == c.id, "Space return restores the actual previously focused pane")
        expect(returning.splitLayout == originalLayout, "Space return preserves complete split geometry")
        returning.selectSpace(siblingSpace.id, state: continuityState, available: { _ in true })
        continuityState.tabs.removeAll { $0.id == c.id }
        returning.selectSpace(firstSpace.id, state: continuityState, available: { _ in true })
        expect(returning.selectedTabIDs == [a.id, pin.id] && returning.preferredFocusedTabID == a.id,
               "closed focused pane falls back to the first surviving original member")
        let projected = returning.splitLayout!
        expect(projected.orientation == .vertical && projected.tabIDs == [a.id, pin.id], "surviving panes keep orientation and order")
        expect(abs(projected.widthFactors[0] - 2.0 / 7.0) < 0.000001 && abs(projected.widthFactors[1] - 5.0 / 7.0) < 0.000001,
               "surviving pane widths preserve their original ratio")
        returning.recordFocusedTab(pin.id)
        continuityState.tabs.append(c)
        returning.reconcile(continuityState, available: { _ in true })
        expect(returning.preferredFocusedTabID == pin.id && !returning.selectedTabIDs.contains(c.id),
               "a formerly unavailable page cannot regain focus or membership over a newer user choice")
        returning.selectSpace(siblingSpace.id, state: continuityState, available: { _ in true })
        returning.selectSpace(firstSpace.id, state: continuityState, available: { _ in false })
        expect(returning.selectedTabIDs.isEmpty && returning.preferredFocusedTabID == nil && returning.splitLayout == nil,
               "no available original pages retains empty selection without creating a replacement")

        left.reconcile(shared, available: availableA)
        expect(left.selectedTabIDs == [a.id], "popup publication never copies popup into opener window")
        expect(!ownership.canUse(b.id, owner: windowA), "cross-window selection refuses owned page")
        expect(!ownership.claim(b.id, owner: windowA), "cross-window claim cannot steal WebContents")
        expect(!ownership.canAdopt("post-popup-page"), "same native page cannot create a second model record")
        expect(!ownership.claim(c.id, owner: windowA, page: "post-popup-page"), "another model ID cannot alias the same native page")
        expect(!ownership.claim(b.id, owner: windowB, page: "duplicate-popup-page"), "one model ID cannot claim a second live native page even in its own window")
        expect(ownership.canAdopt("duplicate-popup-page"), "refused duplicate claim leaves the other native page unclaimed")
        expect(ownership.claim(b.id, owner: windowB, page: "post-popup-page"), "repeated exact ownership claim remains idempotent")
        expect(ownership.owner(of: b.id) == windowB && ownership.owner(of: b.id) == ownership.claimSnapshot(b.id).owner
               && ownership.owner(of: c.id) == nil, "owner(of:) names the claiming window, as the full claim does")
        ownership.release(b.id, owner: windowA)
        expect(!ownership.canUse(b.id, owner: windowA), "wrong owner cannot release page")

        var extra = WindowPresentation(state: left.projected(shared), ready: true)
        extra.reconcile(shared, available: availableB)
        expect(extra.selectedTabIDs.isEmpty, "new window does not reload already-owned saved selection")
        let background = tab(otherSpace)
        shared.tabs.append(background)
        preflight.adopt(background.id, state: shared, foreground: false)
        expect(preflight.selectedTabIDs == [b.id], "background adoption retains current physical-window selection")
        var backgroundPreflight = WindowPresentation(state: shared, ready: false, preferredProfileID: otherProfile.id)
        backgroundPreflight.adopt(background.id, state: shared, foreground: false)
        expect(backgroundPreflight.isReady && backgroundPreflight.selectedTabIDs == [background.id], "first real page makes preflight usable even for background disposition")

        left.selectSpace(siblingSpace.id, state: shared, available: availableA)
        expect(left.selectedTabIDs.isEmpty, "unvisited Space has no implicit globally-selected tab")
        left.selectSpace(firstSpace.id, state: shared, available: availableA)
        expect(left.selectedTabIDs == [a.id], "local per-Space selection survives another window's changes")
        expect(preflight.activeSpaceID == otherSpace.id && preflight.selectedTabIDs == [b.id], "Space switching does not switch another profile's window")
        shared.activeSpaceID = firstSpace.id
        shared.selectedTabIDs = [a.id, c.id, b.id, a.id]
        left.captureCommand(shared, available: availableA)
        expect(left.selectedTabIDs == [a.id, c.id], "split capture removes duplicate, foreign owner and foreign profile")
        left.remove(a.id)
        expect(left.selectedTabIDs == [c.id], "closed split pane preserves other live pane identity")
        expect(BrowserSplitLayout.focusSuccessor([a.id, pin.id], removedAt: 1) == pin.id
               && BrowserSplitLayout.focusSuccessor([a.id, c.id], removedAt: 2) == c.id
               && BrowserSplitLayout.focusSuccessor([a.id], removedAt: nil) == a.id
               && BrowserSplitLayout.focusSuccessor([], removedAt: 0) == nil,
               "focus successor keeps the removed index, else the new last")
        shared.selectedTabIDs = [a.id, c.id, pin.id]
        left.captureCommand(shared, available: availableA)
        left.recordFocusedTab(c.id); left.remove(c.id)
        expect(left.selectedTabIDs == [a.id, pin.id] && left.preferredFocusedTabID == pin.id,
               "closing the focused middle pane focuses the pane that takes its place")
        left.recordFocusedTab(pin.id); left.remove(pin.id)
        expect(left.selectedTabIDs == [a.id] && left.preferredFocusedTabID == a.id,
               "closing the focused last pane focuses the new last pane")
        shared.selectedTabIDs = [pin.id]
        left.captureCommand(shared, available: availableA)
        left.remove(pin.id)
        left.reconcile(shared, available: availableA)
        expect(left.selectedTabIDs.isEmpty, "last saved tab closes to Start, never immediately recreates itself")
        shared.selectedTabIDs = [c.id]
        left.captureCommand(shared, available: availableA)
        shared.tabs[2].archivedAt = Date()
        left.reconcile(shared, available: availableA)
        expect(left.selectedTabIDs.isEmpty, "shared retirement removes actual local selection")
        ownership.releaseAll(owner: windowB)
        expect(ownership.canUse(b.id, owner: windowA) && ownership.canAdopt("post-popup-page"), "completed owner teardown releases page claims")
        expect(!ownership.canUse(a.id, owner: windowB), "another window's teardown preserves opener claim")
        ownership.release(a.id, owner: windowA)
        expect(ownership.canUse(a.id, owner: windowB), "actual page close permits later saved-URL reopening")

        let moves = NativePageOwnership(), origin = UUID(), target = UUID(), third = UUID()
        expect(moves.claim(a.id, owner: origin, page: "same-live-page"), "seed exact source pair")
        expect(moves.reserveTransfer(a.id, page: "wrong-page", from: origin, to: target) == nil, "wrong page cannot reserve")
        expect(moves.reserveTransfer(a.id, page: "same-live-page", from: target, to: origin) == nil, "wrong owner cannot reserve")
        expect(moves.reserveTransfer(a.id, page: "same-live-page", from: origin, to: origin) == nil, "same owner is not a transfer")
        let firstMove = moves.reserveTransfer(a.id, page: "same-live-page", from: origin, to: target)!
        expect(moves.isCurrent(firstMove), "reservation captures exact live owner")
        expect(!moves.claim(a.id, owner: origin, page: "same-live-page"), "creation cannot overwrite pending transfer")
        expect(!moves.claim(a.id, owner: target, page: "same-live-page"), "destination cannot claim before native success")
        expect(!moves.canUse(a.id, owner: third) && !moves.canAdopt("same-live-page"), "third window cannot recreate reserved page")
        expect(moves.reserveTransfer(a.id, page: "same-live-page", from: origin, to: third) == nil, "only one native transfer may own a claim")
        expect(moves.finishTransfer(firstMove, moved: false), "refusal settles reservation")
        expect(moves.canUse(a.id, owner: origin) && !moves.canUse(a.id, owner: target), "refusal retains original owner")
        expect(!moves.finishTransfer(firstMove, moved: true), "late completion cannot move a canceled reservation")
        let secondMove = moves.reserveTransfer(a.id, page: "same-live-page", from: origin, to: target)!
        expect(!moves.finishTransfer(firstMove, moved: true) && moves.isCurrent(secondMove), "stale result cannot consume replacement reservation")
        expect(moves.finishTransfer(secondMove, moved: true), "genuine success commits exact page owner")
        expect(moves.canUse(a.id, owner: target) && !moves.canUse(a.id, owner: origin), "old owner cannot render transferred page")
        expect(!moves.canAdopt("same-live-page"), "successful transfer never creates another page record")
        expect(!moves.claim(c.id, owner: target, page: "same-live-page"), "moved page cannot alias a new model ID")
        let returnMove = moves.reserveTransfer(a.id, page: "same-live-page", from: target, to: origin)!
        moves.release(a.id, owner: target)
        expect(!moves.isCurrent(returnMove) && !moves.finishTransfer(returnMove, moved: true), "independent real-page close invalidates reservation")
        expect(moves.canAdopt("same-live-page"), "completed real close frees its old identity")
        expect(moves.claim(a.id, owner: origin, page: "replacement-page"), "later actual creation can claim saved tab")
        expect(!moves.finishTransfer(returnMove, moved: true), "stale close/move cannot change replacement page")
        let teardownMove = moves.reserveTransfer(a.id, page: "replacement-page", from: origin, to: target)!
        moves.releaseAll(owner: target)
        expect(!moves.isCurrent(teardownMove) && moves.canUse(a.id, owner: origin), "destination teardown cancels reservation without stealing source")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-window-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let original = store.open("https://example.test/original")
        var persistedWindow = WindowPresentation(state: store.state, ready: true)
        let adopted = store.adoptNativePage(url: URL(string: "https://example.test/post-result"), title: "POST result",
            profilePath: store.independentEngineProfilePath(for: store.activeSpace.profileID),
            preferredSpaceID: store.activeSpaceID, select: false)!
        persistedWindow.reconcile(store.state) { _ in true }
        expect(persistedWindow.selectedTabIDs == [original], "real store adoption preserves original window selection")
        expect(store.state.tabs.count == 2 && store.state.selectedTabIDs == [original], "real adoption records incoming page once without selecting")
        let restored = BrowserSplitLayout(spaceID: store.activeSpaceID, tabIDs: [original, adopted],
            orientation: .vertical, widthFactors: [0.25, 0.75])
        expect(store.setWindowPresentation(spaceID: store.activeSpaceID, selectedTabIDs: restored.tabIDs, splitLayout: restored),
               "real store accepts original selection and split geometry together")
        expect(store.state.selectedTabIDs == restored.tabIDs && store.activeSplitLayout == restored,
               "published return selection retains its exact validated layout")
        var wrongSpaceLayout = restored
        wrongSpaceLayout.spaceID = UUID()
        expect(!store.setWindowPresentation(spaceID: store.activeSpaceID, selectedTabIDs: [original], splitLayout: wrongSpaceLayout),
               "foreign layout cannot partially publish a different selection")
        expect(store.state.selectedTabIDs == restored.tabIDs && store.activeSplitLayout == restored,
               "refused return transaction preserves original selection and geometry")
        try store.save()
        let loaded = try BrowserStore(directory: directory)
        expect(loaded.state.tabs.filter { $0.id == adopted }.count == 1, "adopted metadata persists exactly once")
        let startTab = store.open("about:blank")
        var addressWindow = WindowPresentation(state: store.state, ready: true)
        expect(addressWindow.isLocalSelection(startTab, state: store.state, hasNativeWrapper: false), "address command starts from a shell-local blank tab")
        let startCount = store.state.tabs.count
        store.navigate(startTab, input: "https://example.test/from-start")
        addressWindow.captureCommand(store.state) { _ in true }
        expect(addressWindow.selectedTabIDs == [startTab] && store.state.tabs.count == startCount, "Start address command retains the exact saved tab")
        expect(!addressWindow.isLocalSelection(startTab, state: store.state, hasNativeWrapper: false), "Start-to-web waits for its new wrapper instead of deselecting")
        let easelTab = store.openEasel(id: UUID(), title: "Address test")!
        addressWindow.captureCommand(store.state) { _ in true }
        expect(addressWindow.isLocalSelection(easelTab, state: store.state, hasNativeWrapper: false), "address command starts from a shell-local Easel")
        let easelCount = store.state.tabs.count
        store.navigate(easelTab, input: "https://example.test/from-easel")
        addressWindow.captureCommand(store.state) { _ in true }
        expect(addressWindow.selectedTabIDs == [easelTab] && store.state.tabs.count == easelCount, "Easel address command retains the exact saved tab")
        expect(!addressWindow.isLocalSelection(easelTab, state: store.state, hasNativeWrapper: false), "Easel-to-web waits for actual native readiness")
        expect(persistedWindow.selectedTabIDs == [original], "another physical window is not selected by the address command")
        var deletionState = shared
        deletionState.tabs = [a, b, c, pin]
        deletionState.activeSpaceID = firstSpace.id
        deletionState.selectedTabIDs = [a.id]
        deletionState.selectionBySpace[firstSpace.id.uuidString] = [a.id]
        var deleteOrigin = WindowPresentation(state: deletionState, ready: true)
        var deletePeer = WindowPresentation(state: deletionState, ready: true)
        let removal = FolderRemovalSelection(spaceID: firstSpace.id, profileID: firstSpace.profileID,
            original: [a.id], originalFocus: a.id, tabIDs: [c.id], focusedTabID: c.id)
        deletionState.tabs[deletionState.tabs.firstIndex { $0.id == a.id }!].archivedAt = Date()
        deletionState.selectedTabIDs = [c.id]
        deleteOrigin.reconcile(deletionState) { _ in true }
        deletePeer.reconcile(deletionState) { _ in true }
        expect(deleteOrigin.finishFolderRemoval(removal, state: deletionState, available: { _ in true }),
            "original window accepts its completed close decision after shared reconciliation")
        expect(deleteOrigin.selectedTabIDs == [c.id] && deleteOrigin.preferredFocusedTabID == c.id,
            "original replacement and native focus identity advance together")
        expect(deletePeer.selectedTabIDs.isEmpty, "another window only drops closed pages and never adopts the origin's choice")
        var movedOrigin = deletePeer
        movedOrigin.selectSpace(otherSpace.id, state: deletionState) { _ in true }
        expect(!movedOrigin.finishFolderRemoval(removal, state: deletionState, available: { _ in true }),
            "a newer Space choice rejects delayed folder focus")
        var transferredOrigin = deletePeer
        expect(!transferredOrigin.finishFolderRemoval(removal, state: deletionState, available: { $0 != c.id }),
            "a replacement acquired by another physical window cannot be claimed")
        var newerOrigin = deletePeer
        _ = newerOrigin.selectExistingTab(pin.id, state: deletionState) { _ in true }
        expect(!newerOrigin.finishFolderRemoval(removal, state: deletionState, available: { _ in true })
            && newerOrigin.selectedTabIDs == [pin.id], "newer original-window selection wins over delayed completion")
        var retiredProfile = deletionState
        retiredProfile.spaces[retiredProfile.spaces.firstIndex { $0.id == firstSpace.id }!].profileID = otherProfile.id
        expect(!deletePeer.finishFolderRemoval(removal, state: retiredProfile, available: { _ in true }),
            "changed destination Profile invalidates the old decision")
        let undoFolder = store.createFolder(name: "Undo source")
        let undoA = store.open("https://undo-a.test")
        let undoB = store.open("https://undo-b.test")
        let undoSpace = store.activeSpaceID, undoProfile = store.activeSpace.profileID
        store.selectTab(undoA); store.selectTab(undoB, extendingSplit: true)
        let undoGroup = store.activeSplitLayout!
        _ = try store.moveSidebarItem(.split(undoGroup.id), to: .init(spaceID: undoSpace, folderID: undoFolder, section: .pinned),
            before: nil, expected: SidebarHierarchySnapshot(state: store.state, spaceID: undoSpace, profileID: undoProfile)!)
        store.selectTab(undoA)
        _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.3, 0.7])
        let undoTarget = FolderRemovalTarget(folderID: undoFolder, spaceID: undoSpace, profileID: undoProfile, state: store.state)!
        let undoSelection = FolderRemovalSelection.resolve(target: undoTarget, state: store.state,
            selected: [undoA, undoB], focused: undoB, available: { _ in true })!
        var undoOrigin = WindowPresentation(state: store.state, ready: true)
        var undoPeer = WindowPresentation(state: store.state, ready: true)
        var undoRecord: FolderDeletionUndo?
        store.deleteFolder(undoTarget, selection: undoSelection, shouldCommit: { true }, didCommit: { undoRecord = $0 }) { _ in }
        undoOrigin.reconcile(store.state) { _ in true }; undoPeer.reconcile(store.state) { _ in true }
        let undoCommitted = try store.undoFolderDeletion(undoRecord!, shouldCommit: { true })
        expect(undoCommitted, "Undo saved transaction commits")
        undoPeer.reconcile(store.state) { _ in true }
        expect(undoPeer.selectedTabIDs.isEmpty, "Shared restoration never selects a page in a second window")
        expect(!undoOrigin.finishFolderUndo(undoRecord!, state: store.state, available: { $0 != undoA }), "Undo cannot take a restored split member owned elsewhere")
        expect(undoOrigin.finishFolderUndo(undoRecord!, state: store.state, available: { _ in true }), "Only original Undo window selects recorded focused group")
        expect(undoOrigin.selectedTabIDs == [undoA, undoB] && undoOrigin.preferredFocusedTabID == undoB,
            "Original split and focused second pane return together")
        expect(undoOrigin.splitLayout?.orientation == .vertical && undoOrigin.splitLayout?.widthFactors == [0.3, 0.7], "Undo focus preserves actual split geometry")
        let backgroundUndoTarget = FolderRemovalTarget(folderID: undoFolder, spaceID: undoSpace, profileID: undoProfile, state: store.state)!
        store.deleteFolder(backgroundUndoTarget, shouldCommit: { true }, didCommit: { undoRecord = $0 }) { _ in }
        _ = try store.undoFolderDeletion(undoRecord!, shouldCommit: { true })
        expect(!undoPeer.finishFolderUndo(undoRecord!, state: store.state, available: { _ in true }), "Background folder Undo does not invent an active item")

        var frozenState = BrowserState.initial()
        let frozenSpace = frozenState.spaces[0]
        let otherFrozenSpace = BrowserSpace(id: UUID(), name: "Second", symbol: "circle", color: "112233", profileID: frozenSpace.profileID)
        frozenState.spaces.append(otherFrozenSpace)
        let x = tab(frozenSpace), y = tab(frozenSpace), z = tab(frozenSpace), w = tab(otherFrozenSpace)
        frozenState.tabs = [x, y, z, w]
        frozenState.selectedTabIDs = [x.id]
        let pageMoves = NativePageOwnership(), sourceWindow = UUID(), selectingWindow = UUID()
        func usableBySource(_ id: UUID) -> Bool { pageMoves.canUse(id, owner: sourceWindow) }
        var source = WindowPresentation(state: frozenState, ready: true)
        expect(pageMoves.claim(x.id, owner: sourceWindow, page: "frozen-x"), "source owns the page before the move")
        expect(source.leavePlaceholder(x.id, state: frozenState), "a selected page that moves away leaves a placeholder")
        let transfer = pageMoves.reserveTransfer(x.id, page: "frozen-x", from: sourceWindow, to: selectingWindow)!
        expect(pageMoves.finishTransfer(transfer, moved: true), "the page now belongs to the selecting window")
        source.reconcile(frozenState, available: usableBySource)
        expect(source.selectedTabIDs.isEmpty && source.displayedTabIDs == [x.id] && source.displayedPlaceholders == [x.id],
               "the row and address clear while the pane stays as a placeholder")
        expect(source.allPlaceholders == [x.id], "the window lists every tab it shows as a placeholder, in any Space")
        expect(source.sessionSelection.tabIDs.isEmpty && source.preferredFocusedTabID == nil,
               "a placeholder is neither saved nor focused")
        source.selectSpace(otherFrozenSpace.id, state: frozenState, available: usableBySource)
        expect(source.displayedPlaceholders.isEmpty && source.showsPlaceholder(x.id), "another Space hides but keeps the placeholder")
        source.selectSpace(frozenSpace.id, state: frozenState, available: usableBySource)
        expect(source.displayedTabIDs == [x.id] && source.displayedPlaceholders == [x.id], "returning to the Space shows the frozen pane again")
        let back = pageMoves.reserveTransfer(x.id, page: "frozen-x", from: selectingWindow, to: sourceWindow)!
        expect(pageMoves.finishTransfer(back, moved: true), "the page returns")
        source.reconcile(frozenState, available: usableBySource)
        expect(source.selectedTabIDs == [x.id] && source.displayedPlaceholders.isEmpty && !source.showsPlaceholder(x.id),
               "a returned page rejoins the selection in its slot")

        let frozenLayout = BrowserSplitLayout(spaceID: frozenSpace.id, tabIDs: [x.id, y.id], orientation: .vertical, widthFactors: [0.25, 0.75])
        frozenState.splitLayouts = [frozenLayout]
        frozenState.selectedTabIDs = [x.id, y.id]
        var splitSource = WindowPresentation(state: frozenState, ready: true)
        splitSource.recordFocusedTab(x.id)
        let away = pageMoves.reserveTransfer(x.id, page: "frozen-x", from: sourceWindow, to: selectingWindow)!
        expect(pageMoves.finishTransfer(away, moved: true), "the split pane's page moves away")
        splitSource.leavePlaceholder(x.id, state: frozenState)
        splitSource.reconcile(frozenState, available: usableBySource)
        expect(splitSource.selectedTabIDs == [y.id] && splitSource.displayedTabIDs == [x.id, y.id],
               "the live pane stays selected beside the placeholder")
        expect(splitSource.displayedSplitLayout == frozenLayout && splitSource.preferredFocusedTabID == y.id,
               "the placeholder keeps the split's geometry and focus moves to the live pane")
        let returnToSplit = pageMoves.reserveTransfer(x.id, page: "frozen-x", from: selectingWindow, to: sourceWindow)!
        expect(pageMoves.finishTransfer(returnToSplit, moved: true), "the split pane's page returns")
        splitSource.reconcile(frozenState, available: usableBySource)
        expect(splitSource.selectedTabIDs == [x.id, y.id] && splitSource.splitLayout == frozenLayout,
               "the returned pane rejoins its split with its geometry")
        let againAway = pageMoves.reserveTransfer(x.id, page: "frozen-x", from: sourceWindow, to: selectingWindow)!
        expect(pageMoves.finishTransfer(againAway, moved: true), "the page leaves again")
        splitSource.leavePlaceholder(x.id, state: frozenState)
        var closedPartner = frozenState
        closedPartner.tabs.removeAll { $0.id == y.id }
        closedPartner.splitLayouts = []
        splitSource.reconcile(closedPartner, available: usableBySource)
        expect(splitSource.selectedTabIDs.isEmpty && splitSource.displayedTabIDs == [x.id] && splitSource.displayedSplitLayout == nil,
               "closing the live pane leaves the placeholder alone")
        var replaced = closedPartner
        replaced.selectedTabIDs = [z.id]
        splitSource.captureCommand(replaced, available: usableBySource)
        expect(splitSource.selectedTabIDs == [z.id] && splitSource.displayedTabIDs == [z.id] && !splitSource.showsPlaceholder(x.id),
               "selecting another tab here replaces the placeholder")
        var archivedSource = WindowPresentation(state: frozenState, ready: true)
        archivedSource.leavePlaceholder(x.id, state: frozenState)
        var archivedState = frozenState
        archivedState.tabs[archivedState.tabs.firstIndex { $0.id == x.id }!].archivedAt = Date()
        archivedSource.reconcile(archivedState, available: usableBySource)
        expect(!archivedSource.showsPlaceholder(x.id) && archivedSource.displayedTabIDs == [y.id], "an archived page leaves no placeholder")
        var unselected = WindowPresentation(state: frozenState, ready: true)
        expect(!unselected.leavePlaceholder(z.id, state: frozenState) && unselected.displayedPlaceholders.isEmpty,
               "a page this window did not show leaves no placeholder")

        expect(PageReparenting.pagesToMove([x.id, y.id], usableHere: { $0 == y.id }, movable: { _ in true }) == [x.id],
               "only the panes held elsewhere move")
        expect(PageReparenting.pagesToMove([x.id, y.id], usableHere: { _ in false }, movable: { $0 == x.id }) == nil,
               "a busy pane refuses the whole selection")
        expect(PageReparenting.pagesToMove([x.id], usableHere: { _ in true }, movable: { _ in false }) == [],
               "a usable selection moves nothing")
        let now = Date(), older = now.addingTimeInterval(-60)
        let windowsWithPlaceholders = [
            PageReparenting.Candidate(windowID: sourceWindow, displaysPlaceholder: true, showsPlaceholder: true, lastActive: older),
            PageReparenting.Candidate(windowID: selectingWindow, displaysPlaceholder: false, showsPlaceholder: true, lastActive: now),
        ]
        expect(PageReparenting.returnDestination(windowsWithPlaceholders, trigger: .deselected) == sourceWindow,
               "a deselected page returns to a window showing it now")
        expect(PageReparenting.returnDestination(windowsWithPlaceholders, trigger: .ownerClosing) == selectingWindow,
               "a closing owner's page goes to the most recently active window keeping its placeholder")
        expect(PageReparenting.returnDestination([], trigger: .ownerClosing) == nil, "no placeholder means no destination")
        expect(PageReparenting.returnDestinations(windowsWithPlaceholders, trigger: .ownerClosing) == [selectingWindow, sourceWindow],
               "a closing owner's page tries each window keeping its placeholder, most recent first, until one takes it")
        var refusing = windowsWithPlaceholders
        refusing[1].canReceive = false
        expect(PageReparenting.returnDestination(refusing, trigger: .ownerClosing) == sourceWindow,
               "a closing owner's page passes over a window that would refuse it for the next most recent")
        refusing[0].canReceive = false
        expect(PageReparenting.returnDestination(refusing, trigger: .ownerClosing) == nil,
               "with every placeholder window refusing, the page closes with its window")
        expect(PageReparenting.unstartedReturn(refusing) == .blocked,
               "a return every placeholder window refuses now waits for one of them")
        let elsewhere = [PageReparenting.Candidate(windowID: sourceWindow, displaysPlaceholder: false, showsPlaceholder: true, lastActive: now)]
        expect(PageReparenting.returnDestination(elsewhere, trigger: .deselected) == nil
               && PageReparenting.unstartedReturn(elsewhere) == .blocked,
               "a placeholder in a Space its window isn't showing holds the return until that window shows it")
        expect(PageReparenting.unstartedReturn([]) == .unneeded,
               "with no window keeping the placeholder, the return no longer applies")
        let gone = [PageReparenting.Candidate(windowID: sourceWindow, displaysPlaceholder: false, showsPlaceholder: false, lastActive: now)]
        expect(PageReparenting.unstartedReturn(gone) == .unneeded, "a window whose placeholder is gone waits for nothing")
        var keeping = WindowPresentation(state: frozenState, ready: true)
        expect(!keeping.hasPlaceholders, "a window showing its own pages has no placeholder")
        keeping.leavePlaceholder(x.id, state: frozenState)
        expect(keeping.hasPlaceholders, "a window knows when it still shows a placeholder, so it isn't retired as empty")

        expect(PageReparenting.rowAction(closing: false, busy: false, usableHere: false, heldElsewhere: true) == .moveHere,
               "a row for another window's tab activates by moving its page here")
        expect(PageReparenting.rowAction(closing: true, busy: false, usableHere: false, heldElsewhere: true) == .moveHereThenClose,
               "a row's Close for another window's tab moves it here, then closes it in this window")
        expect(PageReparenting.rowAction(closing: false, busy: false, usableHere: true, heldElsewhere: false) == .here
               && PageReparenting.rowAction(closing: true, busy: false, usableHere: true, heldElsewhere: false) == .here,
               "a row for this window's tab acts here")
        expect(PageReparenting.rowAction(closing: false, busy: true, usableHere: false, heldElsewhere: true) == nil
               && PageReparenting.rowAction(closing: true, busy: true, usableHere: true, heldElsewhere: false) == nil,
               "a tab closing, moving or retiring takes no row action")
        expect(PageReparenting.rowAction(closing: false, busy: false, usableHere: false, heldElsewhere: false) == nil,
               "a tab no window can give here takes no row action")

        var closeState = BrowserState.initial()
        let closeSpace = closeState.spaces[0]
        let held = tab(closeSpace), mine = tab(closeSpace)
        closeState.tabs = [held, mine]
        closeState.selectedTabIDs = [held.id]
        let closeMoves = NativePageOwnership(), holderWindow = UUID(), viewerWindow = UUID(), bystanderWindow = UUID()
        func usable(by window: UUID) -> (UUID) -> Bool { { closeMoves.canUse($0, owner: window) } }
        func move(from source: UUID, to destination: UUID) -> Bool {
            guard let reservation = closeMoves.reserveTransfer(held.id, page: "close-held", from: source, to: destination) else { return false }
            return closeMoves.finishTransfer(reservation, moved: true)
        }
        var holder = WindowPresentation(state: closeState, ready: true)
        var viewer = WindowPresentation(state: closeState, ready: true)
        expect(closeMoves.claim(held.id, owner: viewerWindow, page: "close-held") && viewer.leavePlaceholder(held.id, state: closeState)
               && move(from: viewerWindow, to: holderWindow), "the page moves to the window that selected it")
        viewer.reconcile(closeState, available: usable(by: viewerWindow))
        holder.reconcile(closeState, available: usable(by: holderWindow))
        let viewerBefore = (viewer.selectedTabIDs, viewer.displayedTabIDs, viewer.displayedPlaceholders)
        expect(viewerBefore.0.isEmpty && viewerBefore.2 == [held.id], "the window it left shows its placeholder, with no row selected")
        expect(move(from: holderWindow, to: viewerWindow) && holder.leavePlaceholder(held.id, state: closeState),
               "closing it from the placeholder window first moves the page there")
        viewer.adopt(held.id, state: closeState, foreground: false)
        viewer.reconcile(closeState, available: usable(by: viewerWindow))
        holder.reconcile(closeState, available: usable(by: holderWindow))
        expect(viewer.selectedTabIDs == [held.id] && viewer.displayedPlaceholders.isEmpty,
               "while it waits to close, the page fills its old placeholder, so keeping it after a refused close would select it")
        expect(move(from: viewerWindow, to: holderWindow) && viewer.leavePlaceholder(held.id, state: closeState),
               "a close that can't begin hands the page back to the window it came from")
        holder.adopt(held.id, state: closeState, foreground: false)
        holder.reconcile(closeState, available: usable(by: holderWindow))
        viewer.reconcile(closeState, available: usable(by: viewerWindow))
        expect(viewer.selectedTabIDs == viewerBefore.0 && viewer.displayedTabIDs == viewerBefore.1
               && viewer.displayedPlaceholders == viewerBefore.2,
               "the closing window is left exactly as before, placeholder and all, with nothing newly selected")
        expect(holder.selectedTabIDs == [held.id] && holder.displayedPlaceholders.isEmpty, "the window it came from shows it live again")
        closeState.selectedTabIDs = [mine.id]
        var bystander = WindowPresentation(state: closeState, ready: true)
        expect(move(from: holderWindow, to: bystanderWindow) && holder.leavePlaceholder(held.id, state: closeState),
               "closing it from a window that wasn't showing it moves the page there too")
        bystander.adopt(held.id, state: closeState, foreground: false)
        bystander.reconcile(closeState, available: usable(by: bystanderWindow))
        expect(bystander.selectedTabIDs == [mine.id] && !bystander.displayedTabIDs.contains(held.id),
               "a page moved here only to close arrives in the background")
        expect(move(from: bystanderWindow, to: holderWindow) && !bystander.leavePlaceholder(held.id, state: closeState),
               "handing it back leaves nothing behind in a window that never showed it")
        holder.adopt(held.id, state: closeState, foreground: false)
        holder.reconcile(closeState, available: usable(by: holderWindow))
        bystander.reconcile(closeState, available: usable(by: bystanderWindow))
        expect(bystander.selectedTabIDs == [mine.id] && !bystander.hasPlaceholders && holder.selectedTabIDs == [held.id],
               "the person's selection stays as it was and the page is back where it came from")
        expect(PageReparenting.closeRefusal(unsavedNotes: false, reason: nil) == nil,
               "with nothing known to stop the close, the page may move here to close")
        expect(PageReparenting.closeRefusal(unsavedNotes: false, reason: "A page is still opening.") == .explain("A page is still opening."),
               "a close stopped by a page still opening gives that reason")
        if case .explain(let message) = PageReparenting.closeRefusal(unsavedNotes: true, reason: "A page is still opening.") {
            expect(message.contains("Note"), "a Note that couldn't save says so, since its own notice is inside the Note")
        } else { expect(false, "a Note that couldn't save explains itself") }
        print("WindowPresentationTests: \(assertions) assertions passed")
    }
}
