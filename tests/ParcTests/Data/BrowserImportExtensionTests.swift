import AppKit
import ParcCore
import ParcEngine
import Testing
@testable import Parc
@testable import ParcOnboarding

@MainActor @Suite(.serialized)
struct BrowserImportExtensionTests {
    private let known: PCNativeImportExtension
    private let unknown: PCNativeImportExtension
    private let profile: PCNativeImportProfile

    init() {
        known = ImportFixture.extensionItem(OnboardingAdBlocker.uBlockOrigin, "uBlock Origin")
        unknown = ImportFixture.extensionItem()
        profile = ImportFixture.profile("Extensions", [.history, .extensions], extensions: [known, unknown])
    }

    private func failure(_ scene: BrowserImportScene, _ item: PCNativeImportExtension,
                         _ restriction: PCNativeExtensionRestriction = .none) -> PCImportedExtensionFailure {
        ImportFixture.failure(item.displayName, identifier: item.identifier, path: scene.originalPath, restriction: restriction)
    }

    private func imported(_ scene: BrowserImportScene, _ item: PCNativeImportExtension) -> ImportedExtensionFailures.Failure {
        .init(name: item.displayName, target: "import " + scene.destination.profileID.uuidString + " " + item.identifier)
    }

    private func installing(_ scene: BrowserImportScene, data: PCNativeImportOutcome = .completed) throws
        -> (BrowserImportCoordinator, BrowserImportEngineFake.ExtensionInstall) {
        let coordinator = scene.started(try scene.impostor(), [profile], onboarding: true)
        scene.engine.finishBrowser(data)
        let install = try #require(scene.engine.extensionInstalls.last)
        scene.engine.extensionInstalls.removeLast()
        return (coordinator, install)
    }

    private func downloading(_ scene: BrowserImportScene) throws
        -> (BrowserImportCoordinator, BrowserImportEngineFake.ExtensionInstall) {
        let (coordinator, install) = try installing(scene)
        install.complete(ImportFixture.extensionResult(.completed, installed: [unknown.identifier],
                                                       installing: [known.identifier]), [])
        return (coordinator, install)
    }

    private func retryItem(_ scene: BrowserImportScene, _ identifier: String, _ name: String) -> ImportedExtensionRetries.Item {
        .init(source: profile, identifier: identifier, name: name, destination: scene.destination, native: scene.engine)
    }

    @Test func extensionsWaitUntilTheProfileDataHasImported() throws {
        try BrowserImportScene.run { scene in
            _ = scene.started(try scene.impostor(), [profile], onboarding: true)
            #expect(scene.engine.browserRequests.last?.categories.contains(.extensions) == false)
            #expect(scene.engine.extensionInstalls.isEmpty)
        }
    }

    @Test func everyExtensionInstallsEvenWhenOtherDataFailed() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, install) = try installing(scene, data: .failed)
            #expect(install.requests.count == 1)
            let request = try #require(install.requests.first)
            #expect(ImportFixture.requestSource(request) === profile)
            #expect(ImportFixture.requestIDs(request) == [known.identifier, unknown.identifier])
            #expect(ImportFixture.requestPath(request) == scene.originalPath)
            #expect(coordinator.stage == .finished && coordinator.hasBackgroundWork)
        }
    }

    @Test func failedExtensionsAreListedAndNeverReachTheAdBlockerStep() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, install) = try installing(scene, data: .failed)
            install.complete(ImportFixture.extensionResult(.failed), [failure(scene, known), failure(scene, unknown)])
            #expect(coordinator.stage == .finished && coordinator.importedAdBlockers.isEmpty)
            #expect(coordinator.warnings.contains("uBlock Origin couldn’t be added."))
            #expect(coordinator.warnings.contains("Extension couldn’t be added."))
        }
    }

    @Test func aFailedImportFilesItsDataNoticeBeforeEachRetryableExtensionNotice() throws {
        try BrowserImportScene.run { scene in
            let (_, install) = try installing(scene, data: .failed)
            var announced: [String] = []
            ImportedBrowserDataFailures.present = { announced.append("data") }
            ImportedExtensionFailures.present = { announced.append("extension") }
            install.complete(ImportFixture.extensionResult(.failed), [failure(scene, known), failure(scene, unknown)])
            ImportedBrowserDataFailures.present = nil; ImportedExtensionFailures.present = nil
            let notice = ImportedExtensionFailures.take()
            #expect(announced == ["data", "extension", "extension"])
            #expect(ImportedBrowserDataFailures.take() == .failed)
            #expect(notice?.failures == [imported(scene, known), imported(scene, unknown)] && notice?.canRetry == true)
        }
    }

    @Test func stopDuringARunningDownloadEndsAtOnceWithoutFailures() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, install) = try installing(scene)
            coordinator.stopImport()
            #expect(!ImportFixture.cancelled(install.lease))
            install.complete(ImportFixture.extensionResult(.cancelled, installing: [known.identifier]), [])
            #expect(coordinator.stage == .finished && !coordinator.hasBackgroundWork)
            #expect(!coordinator.warnings.contains { $0.hasSuffix("couldn’t be added.") })
        }
    }

    @Test func resultsArriveWhileADownloadRunsAndOnlyKnownAdBlockersCarryOn() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, _) = try downloading(scene)
            #expect(coordinator.stage == .finished)
            #expect(coordinator.importedAdBlockers == [.init(identifier: known.identifier, displayName: known.displayName,
                                                             profileIDs: [scene.destination.profileID])])
        }
    }

    @Test func aLaterFailureIsRecordedOnceAndDropsTheAdBlocker() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, install) = try downloading(scene)
            install.background([failure(scene, known)])
            #expect(coordinator.warnings.filter { $0 == "uBlock Origin couldn’t be added." }.count == 1)
            #expect(ImportedExtensionFailures.pending.contains(imported(scene, known)))
            #expect(coordinator.importedAdBlockers.isEmpty && ImportedExtensionFailures.failedIdentifiers.contains(known.identifier))
            var repeated = 0
            ImportedExtensionFailures.present = { repeated += 1 }
            install.background([failure(scene, known)])
            #expect(coordinator.warnings.filter { $0 == "uBlock Origin couldn’t be added." }.count == 1 && repeated == 0)
        }
    }

    @Test func anOlderEngineReportingOnlyNamesGetsPlainNoticesWithoutRetry() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, install) = try installing(scene)
            install.complete(ImportFixture.extensionResult(.partial, installing: [unknown.identifier]),
                             [ImportFixture.failure(known.displayName)])
            let named = ImportedExtensionFailures.take()
            #expect(coordinator.warnings.contains("uBlock Origin couldn’t be added.") && coordinator.importedAdBlockers.isEmpty)
            #expect(named?.failures.map(\.name) == ["uBlock Origin"] && named?.failures.first?.profile == nil)
            #expect(named?.canRetry == false)
            install.background([ImportFixture.failure(unknown.displayName)])
            let late = ImportedExtensionFailures.take()
            #expect(ImportedExtensionFailures.failedIdentifiers.contains(unknown.identifier))
            #expect(late?.failures.map(\.name) == ["Extension"] && late?.canRetry == false)
        }
    }

    @Test func anInstallThatCannotBeginListsEveryExtensionForRetryLater() throws {
        try BrowserImportScene.run { scene in
            let coordinator = scene.started(try scene.impostor(), [profile], onboarding: true)
            scene.engine.rejectsExtensionInstall = true
            scene.engine.finishBrowser()
            #expect(coordinator.stage == .finished)
            #expect(coordinator.warnings.contains("uBlock Origin couldn’t be added.")
                    && coordinator.warnings.contains("Extension couldn’t be added."))
            coordinator.cancel()
            let unstarted = ImportedExtensionFailures.take()
            #expect(unstarted?.failures == [imported(scene, known), imported(scene, unknown)] && unstarted?.canRetry == true)
            #expect(ImportedBrowserDataFailures.take() == nil)
        }
    }

    @Test func aFailureAfterTheImportClosedWaitsOnceForAWindowWithRetry() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, install) = try downloading(scene)
            coordinator.cancel()
            var presented = 0
            ImportedExtensionFailures.present = { presented += 1 }
            install.background([failure(scene, known)])
            let late = ImportedExtensionFailures.take()
            #expect(late?.failures == [imported(scene, known)] && late?.canRetry == true && presented == 1)
        }
    }

    @Test func retryInstallsJustThatExtensionFromTheSameSourceIntoTheSameProfile() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, install) = try downloading(scene)
            coordinator.cancel()
            install.background([failure(scene, known)])
            let before = scene.engine.extensionInstalls.count
            ImportedExtensionFailures.take()?.retry()
            #expect(scene.engine.extensionInstalls.count == before + 1)
            let again = try #require(scene.engine.extensionInstalls.last)
            let request = try #require(again.requests.first)
            #expect(again.requests.count == 1 && ImportFixture.requestSource(request) === profile)
            #expect(ImportFixture.requestIDs(request) == [known.identifier] && ImportFixture.requestPath(request) == scene.originalPath)
        }
    }

    @Test func aRetryThatFailsAgainCanBeRetriedAgain() throws {
        try BrowserImportScene.run { scene in
            ImportedExtensionRetries.record(retryItem(scene, known.identifier, known.displayName), store: scene.store)
            ImportedExtensionFailures.take()?.retry()
            scene.engine.extensionInstalls.removeLast().complete(ImportFixture.extensionResult(.failed), [failure(scene, known)])
            let still = ImportedExtensionFailures.take()
            #expect(still?.failures == [imported(scene, known)] && still?.canRetry == true)
        }
    }

    @Test func anAdministratorBlockComesBackSayingSoWithoutRetry() throws {
        try BrowserImportScene.run { scene in
            ImportedExtensionRetries.record(retryItem(scene, known.identifier, known.displayName), store: scene.store)
            ImportedExtensionFailures.take()?.retry()
            scene.engine.extensionInstalls.removeLast().complete(ImportFixture.extensionResult(.failed),
                                                                 [failure(scene, known, .administrator)])
            var blocked = imported(scene, known)
            blocked.reason = .administrator
            let refused = ImportedExtensionFailures.take()
            #expect(refused?.failures == [blocked] && refused?.canRetry == false)
        }
    }

    @Test func aFailureThatCanNeverWorkNeverCarriesRetry() throws {
        try BrowserImportScene.run { scene in
            var blocked = imported(scene, known)
            blocked.reason = .administrator
            var retried = false
            ImportedExtensionFailures.record(blocked) { retried = true }
            let notice = ImportedExtensionFailures.take()
            notice?.retry()
            #expect(notice?.canRetry == false && !retried)
        }
    }

    @Test func aRetryTheEngineCannotBeginComesStraightBack() throws {
        try BrowserImportScene.run { scene in
            ImportedExtensionRetries.record(retryItem(scene, known.identifier, known.displayName), store: scene.store)
            scene.engine.rejectsExtensionInstall = true
            ImportedExtensionFailures.take()?.retry()
            #expect(ImportedExtensionFailures.take()?.failures == [imported(scene, known)])
        }
    }

    @Test func aSetupImportFinishingAfterReplayFollowsItsOwnSetupChoice() throws {
        try BrowserImportScene.run { scene in
            let (_, install) = try downloading(scene)
            SetupExtensionChanges.apply(.none, to: [], in: scene.destination, store: scene.store, native: scene.engine)
            SetupExtensionChanges.beginSetupRun()
            install.background([failure(scene, known), failure(scene, unknown)])
            let afterReplay = ImportedExtensionFailures.take()
            #expect(afterReplay?.failures == [imported(scene, unknown)] && afterReplay?.canRetry == true)
            #expect(ImportedExtensionFailures.take() == nil)
        }
    }

    @Test func removalFailuresWaitBesideAddFailuresEachNamedOnce() throws {
        try BrowserImportScene.run { _ in
            var presented = 0
            ImportedExtensionFailures.present = { presented += 1 }
            let adBlock = ImportedExtensionFailures.Failure(change: .removal, name: "AdBlock")
            let ghostery = ImportedExtensionFailures.Failure(change: .removal, name: "Ghostery")
            ImportedExtensionFailures.record(.init(name: "uBlock Origin"))
            ImportedExtensionFailures.record(adBlock)
            ImportedExtensionFailures.record(adBlock)
            ImportedExtensionFailures.record(ghostery)
            #expect(ImportedExtensionFailures.pending == [.init(name: "uBlock Origin"), adBlock, ghostery] && presented == 4)
            let shown = ImportedExtensionFailures.take()
            #expect(shown?.failures == [.init(name: "uBlock Origin"), adBlock, ghostery] && shown?.canRetry == false)
            #expect(ImportedExtensionFailures.pending.isEmpty)
        }
    }

    @Test func aNoticeNoWindowCouldShowComesBackFirstWithoutRepeats() throws {
        try BrowserImportScene.run { _ in
            let ghostery = ImportedExtensionFailures.Failure(change: .removal, name: "Ghostery")
            ImportedExtensionFailures.record(.init(name: "uBlock Origin"))
            ImportedExtensionFailures.record(ghostery)
            let shown = try #require(ImportedExtensionFailures.take())
            ImportedExtensionFailures.record(.init(name: "iCloud Passwords"))
            ImportedExtensionFailures.record(ghostery)
            ImportedExtensionFailures.restore(shown)
            #expect(ImportedExtensionFailures.take()?.failures == [.init(name: "uBlock Origin"), ghostery, .init(name: "iCloud Passwords")])
        }
    }

    @Test func plainFailuresComeFirstThenOneRetryableNoticeKeepingProfilesApart() throws {
        try BrowserImportScene.run { _ in
            let atWork = ImportedExtensionFailures.Failure(change: .removal, name: "AdBlock", profile: "Work")
            let atSchool = ImportedExtensionFailures.Failure(change: .removal, name: "AdBlock", profile: "School")
            ImportedExtensionFailures.record(atWork) {}
            ImportedExtensionFailures.record(atSchool) {}
            ImportedExtensionFailures.record(.init(name: "Grammarly"))
            let plain = ImportedExtensionFailures.take()
            #expect(plain?.failures == [.init(name: "Grammarly")] && plain?.canRetry == false)
            let retryable = ImportedExtensionFailures.take()
            #expect(retryable?.failures == [atWork, atSchool] && retryable?.canRetry == true)
            #expect(ImportedExtensionFailures.take() == nil)
        }
    }

    @Test func aRestoredNoticeKeepsItsRetriesUsingTheNewestForARepeat() throws {
        try BrowserImportScene.run { _ in
            var retried: [String] = []
            let atWork = ImportedExtensionFailures.Failure(change: .removal, name: "AdBlock", profile: "Work")
            let atSchool = ImportedExtensionFailures.Failure(change: .removal, name: "AdBlock", profile: "School")
            ImportedExtensionFailures.record(atWork) { retried.append("Work") }
            ImportedExtensionFailures.record(atSchool) { retried.append("School") }
            let retryable = try #require(ImportedExtensionFailures.take())
            ImportedExtensionFailures.record(atWork) { retried.append("Work again") }
            ImportedExtensionFailures.restore(retryable)
            ImportedExtensionFailures.take()?.retry()
            #expect(retried == ["Work again", "School"] && ImportedExtensionFailures.pending.isEmpty)
        }
    }
}
