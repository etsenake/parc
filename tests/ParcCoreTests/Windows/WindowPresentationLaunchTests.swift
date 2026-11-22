import Foundation
import Testing
@testable import ParcCore

struct WindowPresentationLaunchTests {
    @Test func launchWaitsForOriginalWindowRestoration() {
        var launch = WindowRestorationLaunch()
        launch.deferDockReopen()
        launch.finishLaunch()
        #expect(!launch.canPresent && !launch.takeDockReopen())
    }

    @Test func aDeferredDockRequestDrainsOnceAfterRestoration() {
        var launch = WindowRestorationLaunch()
        launch.deferDockReopen()
        launch.finishLaunch()
        launch.finishRestoration()
        #expect(launch.canPresent && launch.takeDockReopen() && !launch.takeDockReopen())
    }

    struct LaunchCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let previousRunning: Bool?
        let build: String
        let restoresEveryWindow: Bool
    }

    @Test(arguments: [
        LaunchCase(testDescription: "Clean relaunch", previousRunning: false, build: "a", restoresEveryWindow: false),
        LaunchCase(testDescription: "New build", previousRunning: false, build: "b", restoresEveryWindow: true),
        LaunchCase(testDescription: "Unclean run", previousRunning: true, build: "a", restoresEveryWindow: true),
        LaunchCase(testDescription: "No previous launch", previousRunning: nil, build: "a", restoresEveryWindow: false),
    ])
    func thePreviousLaunchDeterminesHowManyWindowsRestore(_ launch: LaunchCase) {
        let previous = launch.previousRunning.map { LaunchContinuity(running: $0, build: "a") }
        #expect(LaunchContinuity.restoresEveryWindow(previous: previous, build: launch.build) == launch.restoresEveryWindow)
    }

    @Test func theLaunchContinuityMarkerRoundTrips() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-launch-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        LaunchContinuity(running: true, build: "a").write(in: root)
        #expect(LaunchContinuity.read(in: root) == LaunchContinuity(running: true, build: "a"))
    }

    struct RestorationCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let isFirst: Bool
        let everyWindow: Bool
        let accepted: Bool
    }

    @Test(arguments: [
        RestorationCase(testDescription: "First window on relaunch", isFirst: true, everyWindow: false, accepted: true),
        RestorationCase(testDescription: "Later window on relaunch", isFirst: false, everyWindow: false, accepted: false),
        RestorationCase(testDescription: "Later window after update or crash", isFirst: false, everyWindow: true, accepted: true),
    ])
    func theRestorationPolicyAdmitsTheRightSavedWindow(_ window: RestorationCase) {
        let first = UUID()
        let restored = window.isFirst ? first : UUID()
        #expect(LaunchContinuity.accepts(restored, launchWindowID: first, everyWindow: window.everyWindow) == window.accepted)
    }

    enum UnmatchedWindow: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case unidentified = "No window identity"
        case identified = "A window identity with no saved first window"

        var testDescription: String { rawValue }
    }

    @Test(arguments: UnmatchedWindow.allCases)
    func ordinaryRestorationNeedsAFirstWindowIdentity(_ window: UnmatchedWindow) {
        #expect(!LaunchContinuity.accepts(window == .identified ? UUID() : nil, launchWindowID: nil, everyWindow: false))
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

    struct ReadinessCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let engineReady: Bool
        let terminating: Bool
        let deferred: Bool
    }

    @Test(arguments: [
        ReadinessCase(testDescription: "Quit pending", engineReady: true, terminating: true, deferred: true),
        ReadinessCase(testDescription: "Engine still starting", engineReady: false, terminating: false, deferred: true),
        ReadinessCase(testDescription: "Ready engine and no pending quit", engineReady: true, terminating: false, deferred: false),
    ])
    func originalWindowRequestsWaitUntilLaunchCanProceed(_ window: ReadinessCase) {
        #expect(WindowRestorationLaunch.shouldDeferWindow(engineReady: window.engineReady, terminating: window.terminating) == window.deferred)
    }

    struct LaunchOwnerCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let mainStore: Bool
        let popup: Bool
        let ready: Bool
        let eligible: Bool
    }

    @Test(arguments: [
        LaunchOwnerCase(testDescription: "Ready regular window", mainStore: true, popup: false, ready: true, eligible: true),
        LaunchOwnerCase(testDescription: "Popup", mainStore: true, popup: true, ready: true, eligible: false),
        LaunchOwnerCase(testDescription: "Different store", mainStore: false, popup: false, ready: true, eligible: false),
        LaunchOwnerCase(testDescription: "Window still starting", mainStore: true, popup: false, ready: false, eligible: false),
    ])
    func onlyAReadyRegularMainStoreWindowCanOwnLaunch(_ window: LaunchOwnerCase) {
        #expect(WindowRestorationLaunch.isRegularLaunchOwner(mainStore: window.mainStore, popup: window.popup, ready: window.ready) == window.eligible)
    }

    struct OwnerPriorityCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let keyOrMain: [Bool]
        let lastActiveIndex: Int?
        let expected: Int?
    }

    @Test(arguments: [
        OwnerPriorityCase(testDescription: "Key or main beats last active", keyOrMain: [false, true, false], lastActiveIndex: 0, expected: 1),
        OwnerPriorityCase(testDescription: "Last active beats last available", keyOrMain: [false, false, false], lastActiveIndex: 0, expected: 0),
        OwnerPriorityCase(testDescription: "Last available takes launch", keyOrMain: [false, false], lastActiveIndex: nil, expected: 1),
        OwnerPriorityCase(testDescription: "No available owner", keyOrMain: [], lastActiveIndex: nil, expected: nil),
    ])
    func launchUsesTheHighestPriorityOwner(_ owners: OwnerPriorityCase) {
        #expect(WindowRestorationLaunch.preferredOwner(keyOrMain: owners.keyOrMain, lastActiveIndex: owners.lastActiveIndex) == owners.expected)
    }

    struct FallbackCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let hasRestoredOwner: Bool
        let hasOtherLaunchOwner: Bool
        let shouldRestore: Bool
    }

    @Test(arguments: [
        FallbackCase(testDescription: "No launch owner", hasRestoredOwner: false, hasOtherLaunchOwner: false, shouldRestore: true),
        FallbackCase(testDescription: "Another launch owner", hasRestoredOwner: false, hasOtherLaunchOwner: true, shouldRestore: false),
        FallbackCase(testDescription: "A restored owner", hasRestoredOwner: true, hasOtherLaunchOwner: true, shouldRestore: false),
    ])
    func theSavedFallbackRestoresOnlyWithoutALaunchOwner(_ launch: FallbackCase) {
        #expect(WindowRestorationLaunch.shouldRestoreFallback(
            hasRestoredOwner: launch.hasRestoredOwner, hasOtherLaunchOwner: launch.hasOtherLaunchOwner
        ) == launch.shouldRestore)
    }

    @Test func deferredActionsWaitForTheInitialOwner() {
        var gate = WindowRestorationLaunch()
        gate.deferAction(.newWindow)
        gate.deferAction(.blankWindow)
        gate.deferAction(.newWindow)
        #expect(gate.nextAction(initialBrowserOpened: false, terminating: false) == nil)
    }

    @Test func deferredActionsWaitThroughQuit() {
        var gate = WindowRestorationLaunch()
        gate.deferAction(.newWindow)
        gate.deferAction(.blankWindow)
        gate.deferAction(.newWindow)
        gate.finishRestoration()
        gate.finishLaunch()
        #expect(gate.nextAction(initialBrowserOpened: true, terminating: true) == nil)
    }

    @Test func deferredActionsDrainInTheirOriginalOrder() {
        var gate = WindowRestorationLaunch()
        gate.deferAction(.newWindow)
        gate.deferAction(.blankWindow)
        gate.deferAction(.newWindow)
        gate.finishRestoration()
        gate.finishLaunch()
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
}
