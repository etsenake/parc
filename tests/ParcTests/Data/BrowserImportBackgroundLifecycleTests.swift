import AppKit
import ParcCore
import ParcEngine
import Testing
@testable import Parc

@MainActor
@Suite(.serialized)
struct BrowserImportBackgroundLifecycleTests {
    private let blocker: PCNativeImportExtension

    private let broken: PCNativeImportExtension

    private let first: PCNativeImportProfile

    init() {
        blocker = ImportFixture.extensionItem(OnboardingAdBlocker.uBlockOrigin, "uBlock Origin")
        broken = ImportFixture.extensionItem("broken", "Broken")
        first = ImportFixture.profile("background default", [.bookmarks, .history, .extensions], directory: "Default",
                                      extensions: [blocker, broken])
    }

    private let second = ImportFixture.profile("background second", [.bookmarks, .history], name: "Other")

    private var bookmarked: PCNativeImportResult { ImportFixture.result(.completed, bookmarks: [ImportFixture.bookmark()]) }

    private func readingBoth(_ scene: BrowserImportScene) throws -> BrowserImportCoordinator {
        let coordinator = scene.started(try scene.impostor(), [first, second], onboarding: true)
        scene.engine.browserCompletions.removeFirst()(bookmarked)
        scene.engine.browserCompletions.removeFirst()(bookmarked)
        return coordinator
    }

    @Test func bookmarksStartFirstAndOtherDestinationsWaitForTheirTurn() throws {
        try BrowserImportScene.run { scene in
            _ = scene.started(try scene.impostor(), [first, second], onboarding: true)
            #expect(scene.engine.browserRequests.first?.categories == [.bookmarks])
            #expect(!scene.store.state.profiles.contains { $0.name == "Other" })
        }
    }

    @Test func everyBookmarkPassPrecedesBackgroundData() throws {
        try BrowserImportScene.run { scene in
            _ = scene.started(try scene.impostor(), [first, second], onboarding: true)
            scene.engine.browserCompletions.removeFirst()(bookmarked)
            #expect(scene.engine.browserRequests.count == 2 && scene.engine.browserRequests.last?.categories == [.bookmarks])
        }
    }

    @Test func resultsAppearWhileBothProfilesImportIntoDistinctPaths() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try readingBoth(scene)
            let requests = Array(scene.engine.browserRequests.suffix(2))
            #expect(coordinator.stage == .bookmarks && coordinator.hasBackgroundWork)
            #expect(scene.engine.browserCompletions.count == 2)
            #expect(requests.allSatisfy { $0.categories == [.history] } && requests[0].path != requests[1].path)
        }
    }

    private final class DetachedImport {
        weak var coordinator: BrowserImportCoordinator?
        var changes = 0
        var delivered: [OnboardingDraft.ImportedAdBlocker] = []
    }

    private func detachImport(in scene: BrowserImportScene) throws -> DetachedImport {
        let detached = DetachedImport()
        var window: NSWindow? = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        var current = true
        var coordinator: BrowserImportCoordinator? = BrowserImportCoordinator(store: scene.store,
            destination: scene.destination, window: window!, onboarding: true, supportsICloudPasswords: false,
            native: scene.engine, ownerIsCurrent: { current })
        detached.coordinator = coordinator
        let impostor = try scene.impostor()
        scene.discovered(coordinator!, [impostor])
        coordinator!.selectSourceInline(impostor)
        scene.engine.profiles.removeFirst().complete(ImportFixture.profiles([first, second]))
        coordinator!.continueSourceInline()
        scene.engine.browserCompletions.removeFirst()(bookmarked)
        scene.engine.browserCompletions.removeFirst()(bookmarked)
        coordinator!.onChange = { detached.changes += 1 }
        coordinator!.detach { detached.delivered = $0 }
        current = false
        window = nil
        coordinator = nil
        return detached
    }

    private func failSecondProfile(in scene: BrowserImportScene) {
        scene.engine.browserCompletions.remove(at: 1)(
            ImportFixture.result(.failed, warnings: ["Some data was unavailable."]))
    }

    private func beginDetachedInstall(in scene: BrowserImportScene) throws -> BrowserImportEngineFake.ExtensionInstall {
        failSecondProfile(in: scene)
        scene.engine.browserCompletions.removeFirst()(ImportFixture.result(.completed))
        return try #require(scene.engine.extensionInstalls.first)
    }

    private func finishDetachedInstall(_ install: BrowserImportEngineFake.ExtensionInstall, in scene: BrowserImportScene) {
        install.complete(ImportFixture.extensionResult(.partial, installed: [blocker.identifier]),
                         [ImportFixture.failure(broken.displayName, identifier: broken.identifier, path: scene.originalPath)])
    }

    @Test func detachedImportIsRetainedWhileProfilesStillHaveWork() throws {
        try BrowserImportScene.run { scene in
            let detached = try detachImport(in: scene)
            #expect(detached.coordinator != nil)
            failSecondProfile(in: scene)
            #expect(scene.engine.extensionInstalls.isEmpty && detached.coordinator?.hasBackgroundWork == true)
            scene.engine.browserCompletions.removeFirst()(ImportFixture.result(.completed))
            finishDetachedInstall(try #require(scene.engine.extensionInstalls.first), in: scene)
        }
    }

    @Test func detachedImportKeepsItsCoordinatorWithoutUpdatingTheFormerOwnerUntilExtensionsFinish() throws {
        try BrowserImportScene.run { scene in
            let detached = try detachImport(in: scene)
            let install = try beginDetachedInstall(in: scene)
            #expect(detached.coordinator?.hasBackgroundWork == true && detached.changes == 0)
            finishDetachedInstall(install, in: scene)
            #expect(detached.coordinator == nil)
        }
    }

    @Test func detachedImportPublishesTheBrowserDataFailureAfterExtensionsFinish() throws {
        try BrowserImportScene.run { scene in
            _ = try detachImport(in: scene)
            let install = try beginDetachedInstall(in: scene)
            #expect(ImportedBrowserDataFailures.pending == nil)
            finishDetachedInstall(install, in: scene)
            #expect(ImportedBrowserDataFailures.take() == .partial)
        }
    }

    @Test func detachedImportDeliversInstalledAdBlockersToItsCompletion() throws {
        try BrowserImportScene.run { scene in
            let detached = try detachImport(in: scene)
            let install = try beginDetachedInstall(in: scene)
            finishDetachedInstall(install, in: scene)
            #expect(detached.delivered == [.init(identifier: blocker.identifier, displayName: blocker.displayName,
                                                profileIDs: [scene.destination.profileID])])
        }
    }

    @Test func detachedImportReportsRetryableExtensionFailuresBothDuringAndAfterInstall() throws {
        try BrowserImportScene.run { scene in
            _ = try detachImport(in: scene)
            let install = try beginDetachedInstall(in: scene)
            finishDetachedInstall(install, in: scene)
            let notice = ImportedExtensionFailures.take()
            #expect(notice?.failures == [.init(name: broken.displayName,
                target: "import " + scene.destination.profileID.uuidString + " " + broken.identifier)])
            #expect(notice?.canRetry == true)
            install.background([ImportFixture.failure(blocker.displayName, identifier: blocker.identifier, path: scene.originalPath)])
            let late = ImportedExtensionFailures.take()
            #expect(late?.failures == [.init(name: blocker.displayName,
                target: "import " + scene.destination.profileID.uuidString + " " + blocker.identifier)])
            #expect(late?.canRetry == true)
        }
    }

    @Test func stoppingAfterAProfileFailedReportsAPartialImportOnce() throws {
        try BrowserImportScene.run { scene in
            let failing = ImportFixture.profile("stop failing", [.bookmarks], directory: "Default")
            let later = ImportFixture.profile("stop later", [.bookmarks], name: "Later")
            let coordinator = scene.started(try scene.impostor(), [failing, later], onboarding: true)
            scene.engine.finishBrowser(.failed)
            #expect(ImportedBrowserDataFailures.pending == nil)
            coordinator.stopImport()
            scene.engine.finishBrowser(.cancelled)
            #expect(coordinator.stage == .finished && ImportedBrowserDataFailures.take() == .partial)
            coordinator.cancel()
            #expect(ImportedBrowserDataFailures.take() == nil)
        }
    }
}
