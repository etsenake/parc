import AppKit
import ParcCore
import ParcEngine
import Testing
@testable import Parc

@MainActor @Suite(.serialized)
struct BrowserImportDiscoveryTests {
    private let partial = ImportFixture.profile("partial", [.bookmarks], .restricted)
    private let complete = ImportFixture.profile("complete", [.history, .bookmarks], .complete)
    private var restricted: PCNativeImportProfileResult { ImportFixture.profiles([partial], .restricted) }
    private var granted: PCNativeImportProfileResult { ImportFixture.profiles([complete], .complete) }

    private func safariAccess(_ scene: BrowserImportScene) throws -> BrowserImportCoordinator {
        let coordinator = scene.coordinator()
        coordinator.discover(resumingSourceBundleID: "com.apple.Safari")
        scene.engine.sources.removeFirst().complete([try scene.safari()])
        scene.engine.profiles.removeFirst().complete(restricted)
        return coordinator
    }

    private func ready(_ scene: BrowserImportScene) throws -> BrowserImportCoordinator {
        let coordinator = try safariAccess(scene)
        coordinator.refreshSafariAccess()
        scene.engine.profiles.removeFirst().complete(granted)
        return coordinator
    }

    @Test func resumingCancelsOrdinaryDiscoveryAndIgnoresItsLateSources() throws {
        try BrowserImportScene.run { scene in
            let coordinator = scene.coordinator()
            let safari = try scene.safari(), impostor = try scene.impostor()
            coordinator.discover()
            let old = scene.engine.sources.removeFirst()
            coordinator.discover(resumingSourceBundleID: "com.apple.Safari")
            #expect(ImportFixture.cancelled(old.lease))
            old.complete([impostor])
            #expect(coordinator.stage == .loading && coordinator.sources.isEmpty)
            scene.engine.sources.removeFirst().complete([impostor, safari])
            #expect(scene.engine.profiles.first?.source === safari)
        }
    }

    @Test func restrictedSafariOpensAccessGuidanceThatCannotRestart() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try safariAccess(scene)
            #expect(coordinator.stage == .safariAccess)
            #expect(!coordinator.safariAccessReady && !coordinator.beginSafariRestart())
        }
    }

    @Test func repeatedAccessPollingKeepsOneDiscoveryOutstanding() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try safariAccess(scene)
            coordinator.refreshSafariAccess(); coordinator.refreshSafariAccess()
            #expect(scene.engine.profiles.count == 1)
        }
    }

    enum AccessResult: CaseIterable { case partialAggregate, noHistory, failed, granted }

    @Test(arguments: AccessResult.allCases)
    func onlyCompleteReadableHistoryMakesRestartReady(_ kind: AccessResult) throws {
        try BrowserImportScene.run { scene in
            let coordinator = try safariAccess(scene)
            coordinator.refreshSafariAccess()
            let result: PCNativeImportProfileResult = switch kind {
            case .partialAggregate: ImportFixture.profiles([complete], .restricted)
            case .noHistory: ImportFixture.profiles([partial], .complete)
            case .failed: ImportFixture.profiles([complete], .complete, error: NSError(domain: "fixture", code: 1))
            case .granted: granted
            }
            scene.engine.profiles.removeFirst().complete(result)
            #expect(coordinator.safariAccessReady == (kind == .granted))
            #expect(coordinator.stage == .safariAccess)
        }
    }

    @Test func readySafariStartsOneRestartThatOwnsTheStage() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try ready(scene)
            #expect(coordinator.beginSafariRestart())
            #expect(!coordinator.beginSafariRestart())
            coordinator.refreshSafariAccess(); coordinator.continueSafariWithoutRestarting()
            #expect(scene.engine.profiles.isEmpty && coordinator.restarting)
        }
    }

    @Test func refusedShutdownRestoresGuidanceAndPollingKeepsItsMessage() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try ready(scene)
            _ = coordinator.beginSafariRestart()
            coordinator.safariRestartFailed("Quit was cancelled.")
            #expect(!coordinator.restarting && coordinator.safariAccessError == "Quit was cancelled.")
            coordinator.refreshSafariAccess()
            scene.engine.profiles.removeFirst().complete(granted)
            #expect(coordinator.safariAccessError == "Quit was cancelled.")
        }
    }

    @Test func continueJoinsTheCurrentDiscoveryAndReturnsToTheReadableProfile() throws {
        try BrowserImportScene.run { scene in
            let original = scene.store.state
            let coordinator = try ready(scene)
            _ = coordinator.beginSafariRestart()
            coordinator.safariRestartFailed("Quit was cancelled.")
            coordinator.refreshSafariAccess()
            let continuation = scene.engine.profiles.removeFirst()
            coordinator.continueSafariWithoutRestarting()
            #expect(coordinator.continueAfterSafariRefresh && scene.engine.profiles.isEmpty)
            continuation.complete(restricted)
            #expect(coordinator.stage == .profiles && coordinator.selectedProfiles == [partial.identifier])
            #expect(coordinator.safariAccessError == nil && !coordinator.restarting)
            #expect(coordinator.canContinueSourceInline)
            #expect(scene.engine.imports == 0)
            #expect(scene.store.state.profiles == original.profiles && scene.store.state.spaces == original.spaces
                    && scene.store.state.tabs == original.tabs)
        }
    }

    @Test func missingSafariReturnsToTheInstalledSourceChooser() throws {
        try BrowserImportScene.run { scene in
            let coordinator = scene.coordinator()
            coordinator.discover(resumingSourceBundleID: "com.apple.Safari")
            scene.engine.sources.removeFirst().complete([try scene.impostor()])
            #expect(coordinator.stage == .sources && coordinator.source == nil && coordinator.error != nil)
            #expect(scene.engine.profiles.isEmpty)
        }
    }

    @Test func restrictedChromiumFamilySourcesUseFullDiskAccessGuidance() throws {
        try BrowserImportScene.run { scene in
            let impostor = try scene.impostor()
            let coordinator = scene.chosen(impostor, profiles: restricted)
            #expect(coordinator.stage == .safariAccess)
        }
    }

    @Test func sourcesListArcThenChromeThenOthersInDiscoveryOrder() throws {
        try BrowserImportScene.run { scene in
            let safari = try scene.safari(), chrome = try scene.chrome(), impostor = try scene.impostor(), arc = scene.arc()
            let coordinator = scene.coordinator()
            scene.discovered(coordinator, [safari, chrome, impostor, arc])
            #expect(coordinator.sources.map(\.identifier) == [arc, chrome, safari, impostor].map(\.identifier))
        }
    }

    @Test func restrictedChromeOpensFullDiskAccessWithItsProfileSelected() throws {
        try BrowserImportScene.run { scene in
            let coordinator = scene.chosen(try scene.chrome(), profiles: restricted)
            #expect(coordinator.stage == .safariAccess && coordinator.selectedProfiles == [partial.identifier])
        }
    }

    @Test func setupKeepsRestrictedChromeInlineUntilNextOpensFullDiskAccess() throws {
        try BrowserImportScene.run { scene in
            let unread = ImportFixture.profile("Default", [], .restricted)
            let coordinator = scene.chosen(try scene.chrome(), profiles: ImportFixture.profiles([unread], .restricted), onboarding: true)
            #expect(coordinator.stage == .profiles && coordinator.canContinueSourceInline
                    && coordinator.selectedProfiles == [unread.identifier])
            coordinator.continueSourceInline()
            #expect(coordinator.stage == .safariAccess)
        }
    }

    @Test func restartAfterFullDiskAccessResumesChromeRatherThanSafari() throws {
        try BrowserImportScene.run { scene in
            let chrome = try scene.chrome()
            let coordinator = scene.coordinator(onboarding: true)
            coordinator.discover(resumingSourceBundleID: "com.google.Chrome")
            scene.engine.sources.removeFirst().complete([try scene.safari(), chrome])
            #expect(scene.engine.profiles.first?.source === chrome)
        }
    }

    @Test func rediscoveryDiscardsEveryOldSourceAndProfileToken() throws {
        try BrowserImportScene.run { scene in
            let coordinator = scene.chosen(try scene.impostor(), profiles: granted)
            coordinator.discover(resumingSourceBundleID: "com.apple.Safari")
            scene.engine.sources.removeFirst().complete([])
            #expect(coordinator.source == nil && coordinator.profiles.isEmpty && coordinator.selectedProfiles.isEmpty)
        }
    }

    @Test func lostOriginalOwnerRejectsDiscoveryAndRestart() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try safariAccess(scene)
            coordinator.refreshSafariAccess()
            let stale = scene.engine.profiles.removeFirst()
            scene.current = false
            stale.complete(granted)
            #expect(!coordinator.safariAccessReady && !coordinator.beginSafariRestart())
        }
    }

    @Test func cancellationRevokesDiscoveryAndLateCallbacksCannotResurrectIt() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try safariAccess(scene)
            coordinator.refreshSafariAccess()
            let stale = scene.engine.profiles.removeFirst()
            coordinator.cancel()
            #expect(ImportFixture.cancelled(stale.lease) && coordinator.stage == .finished)
            stale.complete(granted)
            #expect(coordinator.stage == .finished && !coordinator.safariAccessReady)
        }
    }

    @Test func continuingWithNoReadableDataShowsTheFailureWithoutImporting() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try safariAccess(scene)
            coordinator.continueSafariWithoutRestarting()
            scene.engine.profiles.removeFirst().complete(ImportFixture.profiles([], .restricted,
                error: NSError(domain: "fixture", code: 2)))
            #expect(coordinator.stage == .profiles && !coordinator.canContinueSourceInline && coordinator.error != nil)
            #expect(scene.engine.imports == 0)
        }
    }

    @Test func setupNeverImportsBeforeOrDuringSourceDiscovery() throws {
        try BrowserImportScene.run { scene in
            let impostor = try scene.impostor()
            let coordinator = scene.coordinator()
            coordinator.startInOriginalDestination()
            #expect(scene.engine.imports == 0)
            scene.discovered(coordinator, [impostor])
            coordinator.select(impostor); coordinator.loadProfiles()
            scene.engine.profiles.removeFirst().complete(granted)
            #expect(scene.engine.imports == 0)
        }
    }

    @Test func retiredSetupOwnerCannotSubmitAnImport() throws {
        try BrowserImportScene.run { scene in
            let coordinator = scene.chosen(try scene.impostor(), profiles: granted)
            scene.current = false
            coordinator.startInOriginalDestination()
            #expect(scene.engine.imports == 0)
        }
    }

    @Test func explicitImportTargetsTheOriginalDestinationAndWindowOnce() throws {
        try BrowserImportScene.run { scene in
            let coordinator = scene.chosen(try scene.impostor(), profiles: granted)
            let otherSpace = scene.store.createSpace(name: "Other window")
            let otherProfile = scene.store.createProfile(name: "Other Profile")
            scene.store.assignProfile(otherProfile, toSpace: otherSpace)
            scene.store.selectSpace(otherSpace)
            let before = scene.store.state
            coordinator.startInOriginalDestination()
            #expect(scene.engine.imports == 1 && coordinator.stage == .importing)
            let request = try #require(scene.engine.browserRequests.last)
            #expect(request.profile === complete && request.window === scene.window)
            #expect(request.path == scene.originalPath)
            #expect(request.skipExistingCookies && !request.categories.contains(.extensions))
            #expect(scene.store.state.profiles == before.profiles && scene.store.state.spaces == before.spaces)
            coordinator.startInOriginalDestination()
            #expect(scene.engine.imports == 1)
        }
    }

    @Test func lateNativeCompletionCannotReopenAClosedSetup() throws {
        try BrowserImportScene.run { scene in
            let coordinator = scene.chosen(try scene.impostor(), profiles: granted)
            coordinator.startInOriginalDestination()
            let completion = scene.engine.browserCompletions.removeFirst()
            coordinator.cancel()
            completion(ImportFixture.result(.completed))
            #expect(coordinator.stage == .finished && coordinator.bookmarkPages.isEmpty)
        }
    }

    @Test func initialDiscoveryIsNotInlineProfileLoading() throws {
        try BrowserImportScene.run { scene in
            let coordinator = scene.coordinator(onboarding: true)
            coordinator.discover()
            #expect(!coordinator.isChoosingSourceInline)
        }
    }

    @Test func inlineSelectionWaitsForProfilesWithoutRepeatingDiscovery() throws {
        try BrowserImportScene.run { scene in
            let impostor = try scene.impostor()
            let coordinator = scene.coordinator(onboarding: true)
            scene.discovered(coordinator, [impostor, try scene.safari()])
            coordinator.selectSourceInline(impostor)
            #expect(coordinator.isChoosingSourceInline && !coordinator.canContinueSourceInline)
            coordinator.selectSourceInline(impostor)
            #expect(scene.engine.profiles.count == 1)
        }
    }

    @Test func switchingBrowserCancelsTheOldLeaseAndIgnoresItsResult() throws {
        try BrowserImportScene.run { scene in
            let impostor = try scene.impostor(), safari = try scene.safari()
            let coordinator = scene.coordinator(onboarding: true)
            scene.discovered(coordinator, [impostor, safari])
            coordinator.selectSourceInline(impostor)
            let replaced = scene.engine.profiles.removeFirst()
            coordinator.selectSourceInline(safari)
            #expect(ImportFixture.cancelled(replaced.lease))
            replaced.complete(granted)
            #expect(coordinator.profiles.isEmpty && coordinator.source === safari)
        }
    }

    @Test func restrictedSafariStaysInlineUntilNextAndBackKeepsItChosen() throws {
        try BrowserImportScene.run { scene in
            let safari = try scene.safari()
            let coordinator = scene.chosen(safari, profiles: restricted, onboarding: true)
            #expect(coordinator.stage == .profiles && coordinator.isChoosingSourceInline && coordinator.canContinueSourceInline)
            coordinator.continueSourceInline()
            #expect(coordinator.stage == .safariAccess && !coordinator.isChoosingSourceInline)
            coordinator.goBackInSetup()
            #expect(coordinator.isChoosingSourceInline && coordinator.canContinueSourceInline && coordinator.source === safari)
            #expect(!coordinator.safariAccessReady)
        }
    }

    @Test func nextOnSetupAccessImportsWhatIsReadable() throws {
        try BrowserImportScene.run { scene in
            let coordinator = scene.chosen(try scene.safari(), profiles: restricted, onboarding: true)
            coordinator.continueSourceInline()
            coordinator.continueSafariWithoutRestarting()
            scene.engine.profiles.removeFirst().complete(restricted)
            #expect(scene.engine.imports == 1 && scene.engine.browserRequests.last?.profile === partial)
        }
    }

    @Test func startingFreshRevokesPendingBrowserDiscovery() throws {
        try BrowserImportScene.run { scene in
            let impostor = try scene.impostor()
            let coordinator = scene.coordinator(onboarding: true)
            scene.discovered(coordinator, [impostor])
            coordinator.selectSourceInline(impostor)
            let abandoned = scene.engine.profiles.removeFirst()
            coordinator.clearSourceInline()
            #expect(ImportFixture.cancelled(abandoned.lease) && coordinator.stage == .sources && coordinator.source == nil)
            abandoned.complete(granted)
            #expect(coordinator.profiles.isEmpty && !coordinator.canContinueSourceInline)
        }
    }

    @Test func profileDiscoveryTakesEveryReadableProfile() throws {
        try BrowserImportScene.run { scene in
            let first = ImportFixture.profile("First", [.history, .extensions], extensions: [ImportFixture.extensionItem()])
            let second = ImportFixture.profile("Second", [.bookmarks])
            let coordinator = scene.chosen(try scene.impostor(), profiles: ImportFixture.profiles([first, second]), onboarding: true)
            #expect(coordinator.selectedProfiles == [first.identifier, second.identifier])
        }
    }

    @Test func retiredSetupRejectsInlineImport() throws {
        try BrowserImportScene.run { scene in
            let coordinator = scene.chosen(try scene.impostor(), profiles: granted, onboarding: true)
            scene.current = false
            coordinator.continueSourceInline()
            #expect(scene.engine.imports == 0)
        }
    }

    @Test func nextReadsTheBookmarkProfileFirstIntoAParcProfileOfItsName() throws {
        try BrowserImportScene.run { scene in
            let first = ImportFixture.profile("First", [.history, .extensions], extensions: [ImportFixture.extensionItem()])
            let second = ImportFixture.profile("Second", [.bookmarks])
            let coordinator = scene.chosen(try scene.impostor(), profiles: ImportFixture.profiles([first, second]), onboarding: true)
            coordinator.continueSourceInline()
            let request = try #require(scene.engine.browserRequests.last)
            #expect(scene.engine.imports == 1 && request.profile === second && request.categories == [.bookmarks])
            let secondDestination = try #require(scene.store.state.profiles.first { $0.name == "Second" })
            #expect(request.window === scene.window && request.path == scene.path(secondDestination.id))
        }
    }

    @Test func inlineSourceControlsCannotReplaceAnAcceptedImport() throws {
        try BrowserImportScene.run { scene in
            let impostor = try scene.impostor(), safari = try scene.safari()
            let coordinator = scene.coordinator(onboarding: true)
            scene.discovered(coordinator, [impostor, safari])
            coordinator.selectSourceInline(impostor)
            scene.engine.profiles.removeFirst().complete(granted)
            coordinator.continueSourceInline()
            coordinator.selectSourceInline(safari); coordinator.clearSourceInline()
            #expect(coordinator.stage == .importing && coordinator.source === impostor)
        }
    }

    @Test func aCancelledInlineOwnerStaysRetiredAfterNativeCompletion() throws {
        try BrowserImportScene.run { scene in
            let coordinator = scene.chosen(try scene.impostor(), profiles: granted, onboarding: true)
            coordinator.continueSourceInline()
            coordinator.cancel()
            scene.engine.finishBrowser()
            #expect(coordinator.stage == .finished)
        }
    }

    @Test(arguments: [("com.apple.Safari", true), ("test.not-safari", false)])
    func sourceAttributionReadsTheApplicationBundle(_ bundleID: String, _ expected: Bool) throws {
        try BrowserImportScene.run { scene in
            let source = ImportFixture.source("Safari", try scene.app("Browser", bundleID))
            #expect(BrowserImportCoordinator.isSafari(source) == expected)
            #expect((BrowserImportCoordinator.keychainNote(for: source) == nil) == expected)
        }
    }
}
