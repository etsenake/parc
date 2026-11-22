import AppKit
@testable import ParcCore
import ParcEngine
import Testing
@testable import Parc
@testable import ParcOnboarding

@MainActor @Suite(.serialized)
struct SetupExtensionChangesTests {
    private struct Refusal: Error {}
    private static let adBlock = "gighmmpiobklfepjocnamgkkbiglidom", chromeAdBlock = "cfhdojbkjhnklbpkdaibdccddilifddb"
    private static let ghostery = "mlomiejdfkolichcflejclcbmpeaniij"
    private static let names = [adBlock: "AdBlock", chromeAdBlock: "AdBlock", ghostery: "Ghostery"]
    private let source = ImportFixture.profile("Setup import", [.extensions])

    private func shown(_ notice: ImportedExtensionFailures.Notice?) -> [String] {
        notice?.failures.map { $0.name + ($0.profile.map { " @ " + $0 } ?? "") } ?? []
    }

    private func next(_ scene: BrowserImportScene) -> BrowserImportEngineFake.SetupChange {
        scene.engine.setupChanges.removeFirst()
    }

    private func item(_ scene: BrowserImportScene, _ identifier: String, _ name: String,
                      fromMenu: Bool = false) -> ImportedExtensionRetries.Item {
        .init(source: source, identifier: identifier, name: name, destination: scene.destination,
              setupRun: fromMenu ? nil : SetupExtensionChanges.setupRun, native: scene.engine)
    }

    private func addICloud(_ scene: BrowserImportScene, admitted: @escaping @MainActor () -> Bool) {
        SetupExtensionChanges.addICloudPasswords(to: scene.destination, store: scene.store, connects: admitted, native: scene.engine)
    }

    private func home(_ scene: BrowserImportScene) -> String {
        scene.store.state.profiles.first { $0.id == scene.destination.profileID }?.name ?? ""
    }

    @Test func aRefusingICloudHelperInstallsNothingAndOffersNoRetry() throws {
        try BrowserImportScene.run { scene in
            addICloud(scene) { false }
            let refused = ImportedExtensionFailures.take()
            #expect(scene.engine.setupChanges.isEmpty && shown(refused) == ["iCloud Passwords"] && refused?.canRetry == false)
        }
    }

    @Test func anAdmittedICloudInstallGoesToTheChosenProfileAndSucceedsQuietly() throws {
        try BrowserImportScene.run { scene in
            addICloud(scene) { true }
            let install = next(scene)
            #expect(install.kind == "iCloud Passwords" && install.path == scene.originalPath)
            install.complete(nil)
            #expect(ImportedExtensionFailures.pending.isEmpty)
        }
    }

    @Test func aFailedICloudInstallRetriesOnceAndRetriesAgainAfterAnotherFailure() throws {
        try BrowserImportScene.run { scene in
            addICloud(scene) { true }
            next(scene).complete(Refusal())
            let failed = ImportedExtensionFailures.take()
            #expect(shown(failed) == ["iCloud Passwords"] && failed?.canRetry == true)
            failed?.retry()
            let retried = next(scene)
            #expect(retried.kind == "iCloud Passwords" && scene.engine.setupChanges.isEmpty)
            retried.complete(Refusal())
            #expect(ImportedExtensionFailures.take()?.canRetry == true)
        }
    }

    @Test func retryAfterTheICloudHelperStartsRefusingInstallsNothing() throws {
        try BrowserImportScene.run { scene in
            var admitted = true
            addICloud(scene) { admitted }
            next(scene).complete(Refusal())
            admitted = false
            ImportedExtensionFailures.take()?.retry()
            let refused = ImportedExtensionFailures.take()
            #expect(scene.engine.setupChanges.isEmpty && shown(refused) == ["iCloud Passwords"] && refused?.canRetry == false)
        }
    }

    @Test func importAndSetupFailuresOfOneNameStaySeparateAndOnlySetupRetries() throws {
        try BrowserImportScene.run { scene in
            ImportedExtensionFailures.record(.init(name: "uBlock Origin Lite"))
            SetupExtensionChanges.addAdBlocker(to: scene.destination, store: scene.store, native: scene.engine)
            next(scene).complete(Refusal())
            let imported = ImportedExtensionFailures.take(), blocker = ImportedExtensionFailures.take()
            #expect(shown(imported) == ["uBlock Origin Lite"] && imported?.canRetry == false)
            #expect(shown(blocker) == ["uBlock Origin Lite"] && blocker?.canRetry == true)
            blocker?.retry()
            #expect(next(scene).kind == "uBlock Origin")
        }
    }

    @Test func eachBlockerIsRemovedFromEachExistingProfileOnItsOwn() throws {
        try BrowserImportScene.run { scene in
            let work = scene.store.createProfile(name: "Work")
            SetupExtensionChanges.removeAdBlockers([scene.destination.profileID: [Self.adBlock, Self.chromeAdBlock],
                work: [Self.chromeAdBlock, Self.ghostery], UUID(): [Self.adBlock]], names: Self.names,
                store: scene.store, native: scene.engine)
            let removals = scene.engine.setupChanges
            #expect(removals.map(\.kind) == ["remove", "remove", "remove", "remove"])
            #expect(removals.map(\.identifiers) == [[Self.chromeAdBlock], [Self.adBlock], [Self.chromeAdBlock], [Self.ghostery]])
            #expect(removals.map(\.path) == [scene.destination.profileID, scene.destination.profileID, work, work].map(scene.path))
        }
    }

    @Test func failedRemovalsNameEachProfileAtFailureTimeAndRetryEveryCopy() throws {
        try BrowserImportScene.run { scene in
            let work = scene.store.createProfile(name: "Work")
            SetupExtensionChanges.removeAdBlockers([scene.destination.profileID: [Self.adBlock, Self.chromeAdBlock],
                work: [Self.chromeAdBlock, Self.ghostery]], names: Self.names, store: scene.store, native: scene.engine)
            let removals = scene.engine.setupChanges
            scene.engine.setupChanges = []
            scene.store.renameProfile(work, name: "Office")
            removals.forEach { $0.complete(Refusal()) }
            let stayed = ImportedExtensionFailures.take()
            #expect(shown(stayed) == ["AdBlock @ " + home(scene), "AdBlock @ " + home(scene), "AdBlock @ Office", "Ghostery"])
            #expect(stayed?.canRetry == true && ImportedExtensionFailures.take() == nil)
            stayed?.retry()
            #expect(scene.engine.setupChanges.map(\.identifiers)
                    == [[Self.chromeAdBlock], [Self.adBlock], [Self.chromeAdBlock], [Self.ghostery]])
            scene.engine.setupChanges.forEach { $0.complete(nil) }
            #expect(ImportedExtensionFailures.pending.isEmpty)
        }
    }

    @Test func twoCopiesOfOneBlockerInOneProfileDoNotNameIt() throws {
        try BrowserImportScene.run { scene in
            let work = scene.store.createProfile(name: "Work")
            SetupExtensionChanges.removeAdBlockers([work: [Self.adBlock, Self.chromeAdBlock]], names: Self.names,
                                                   store: scene.store, native: scene.engine)
            scene.engine.setupChanges.forEach { $0.complete(Refusal()) }
            #expect(shown(ImportedExtensionFailures.take()) == ["AdBlock", "AdBlock"])
        }
    }

    @Test func changesAnotherAppOrTheAdministratorRulesOutSaySoWithoutRetry() throws {
        try BrowserImportScene.run { scene in
            let work = scene.store.createProfile(name: "Work")
            SetupExtensionChanges.removeAdBlockers([work: [Self.ghostery]], names: Self.names, store: scene.store, native: scene.engine)
            next(scene).complete(RestrictedExtensionError(restriction: .otherApp))
            SetupExtensionChanges.addAdBlocker(to: scene.destination, store: scene.store, native: scene.engine)
            next(scene).complete(RestrictedExtensionError(restriction: .administrator))
            SetupExtensionChanges.addAdBlocker(to: scene.destination, store: scene.store, native: scene.engine)
            next(scene).complete(Refusal())
            let kept = ImportedExtensionFailures.take(), blocked = ImportedExtensionFailures.take()
            let retryable = ImportedExtensionFailures.take()
            #expect(kept?.failures.map(\.reason) == [.otherApp] && kept?.failures.map(\.change) == [.removal])
            #expect(kept?.canRetry == false)
            #expect(blocked?.failures.map(\.reason) == [.administrator] && blocked?.canRetry == false)
            #expect(shown(retryable) == ["uBlock Origin Lite"] && retryable?.canRetry == true)
            #expect(ImportedExtensionFailures.take() == nil)
        }
    }

    @Test func keepingOneBlockerRemovesTheOtherAndDropsItsWaitingNotice() throws {
        try BrowserImportScene.run { scene in
            let uBlock = OnboardingAdBlocker.uBlockOrigin
            ImportedExtensionRetries.record(item(scene, uBlock, "uBlock Origin"), store: scene.store)
            ImportedExtensionRetries.record(item(scene, Self.adBlock, "AdBlock"), store: scene.store)
            SetupExtensionChanges.apply(.keep(uBlock), to: [.init(identifier: uBlock, displayName: "uBlock Origin"),
                                                            .init(identifier: Self.ghostery, displayName: "Ghostery")],
                                        in: scene.destination, store: scene.store, native: scene.engine)
            let removal = next(scene)
            #expect(removal.kind == "remove" && removal.identifiers == [Self.ghostery] && scene.engine.setupChanges.isEmpty)
            removal.complete(nil)
            let wanted = ImportedExtensionFailures.take()
            #expect(shown(wanted) == ["uBlock Origin"] && wanted?.canRetry == true && ImportedExtensionFailures.take() == nil)
        }
    }

    @Test func retryNeverReAddsABlockerSetupRemovedOrLeftOut() throws {
        try BrowserImportScene.run { scene in
            let uBlock = OnboardingAdBlocker.uBlockOrigin
            SetupExtensionChanges.apply(.keep(uBlock), to: [], in: scene.destination, store: scene.store, native: scene.engine)
            ImportedExtensionRetries.retry(item(scene, Self.adBlock, "AdBlock"), store: scene.store)
            ImportedExtensionRetries.retry(item(scene, Self.ghostery, "Ghostery"), store: scene.store)
            #expect(scene.engine.extensionInstalls.isEmpty)
        }
    }

    @Test func retryingTheKeptBlockerInstallsJustThatOne() throws {
        try BrowserImportScene.run { scene in
            let uBlock = OnboardingAdBlocker.uBlockOrigin
            ImportedExtensionRetries.record(item(scene, uBlock, "uBlock Origin"), store: scene.store)
            SetupExtensionChanges.apply(.keep(uBlock), to: [], in: scene.destination, store: scene.store, native: scene.engine)
            ImportedExtensionFailures.take()?.retry()
            let retry = try #require(scene.engine.extensionInstalls.last)
            scene.engine.extensionInstalls.removeLast()
            #expect(retry.requests.map(ImportFixture.requestIDs) == [[uBlock]])
            retry.complete(ImportFixture.extensionResult(.completed, installed: [uBlock]), [])
            #expect(ImportedExtensionFailures.pending.isEmpty && scene.engine.extensionInstalls.isEmpty)
        }
    }

    @Test func aLateFailureForALeftOutBlockerIsNotAnnounced() throws {
        try BrowserImportScene.run { scene in
            SetupExtensionChanges.apply(.keep(OnboardingAdBlocker.uBlockOrigin), to: [], in: scene.destination,
                                        store: scene.store, native: scene.engine)
            ImportedExtensionRetries.record(item(scene, Self.adBlock, "AdBlock"), store: scene.store)
            #expect(ImportedExtensionFailures.pending.isEmpty)
        }
    }

    @Test func aBlockerFromALaterMenuImportKeepsItsRetry() throws {
        try BrowserImportScene.run { scene in
            SetupExtensionChanges.apply(.keep(OnboardingAdBlocker.uBlockOrigin), to: [], in: scene.destination,
                                        store: scene.store, native: scene.engine)
            ImportedExtensionRetries.record(item(scene, Self.adBlock, "AdBlock", fromMenu: true), store: scene.store)
            let fromMenu = ImportedExtensionFailures.take()
            fromMenu?.retry()
            #expect(shown(fromMenu) == ["AdBlock"] && fromMenu?.canRetry == true && scene.engine.extensionInstalls.count == 1)
        }
    }

    @Test func afterDecliningAdBlockingNoImportedBlockerComesBack() throws {
        try BrowserImportScene.run { scene in
            SetupExtensionChanges.apply(.none, to: [], in: scene.destination, store: scene.store, native: scene.engine)
            ImportedExtensionRetries.record(item(scene, OnboardingAdBlocker.uBlockOrigin, "uBlock Origin"), store: scene.store)
            #expect(ImportedExtensionFailures.pending.isEmpty && scene.engine.setupChanges.isEmpty)
        }
    }

    @Test func afterSetupAddsUBlockOnlyAnImportedUBlockKeepsItsNotice() throws {
        try BrowserImportScene.run { scene in
            SetupExtensionChanges.apply(.uBlock, to: [], in: scene.destination, store: scene.store, native: scene.engine)
            let install = next(scene)
            ImportedExtensionRetries.record(item(scene, Self.adBlock, "AdBlock"), store: scene.store)
            ImportedExtensionRetries.record(item(scene, OnboardingAdBlocker.uBlockOrigin, "uBlock Origin"), store: scene.store)
            #expect(install.kind == "uBlock Origin" && shown(ImportedExtensionFailures.take()) == ["uBlock Origin"])
            #expect(ImportedExtensionFailures.take() == nil)
        }
    }

    @Test func aMenuFailureSurvivesALaterSetupChoiceWithItsRetry() throws {
        try BrowserImportScene.run { scene in
            SetupExtensionChanges.apply(.keepAll, to: [], in: scene.destination, store: scene.store, native: scene.engine)
            ImportedExtensionRetries.record(item(scene, Self.adBlock, "AdBlock"), store: scene.store)
            ImportedExtensionRetries.record(item(scene, Self.adBlock, "AdBlock", fromMenu: true), store: scene.store)
            SetupExtensionChanges.apply(.none, to: [], in: scene.destination, store: scene.store, native: scene.engine)
            let reclaimed = ImportedExtensionFailures.take()
            reclaimed?.retry()
            #expect(shown(reclaimed) == ["AdBlock"] && reclaimed?.canRetry == true && scene.engine.extensionInstalls.count == 1)
        }
    }

    @Test func usingEveryImportedBlockerKeepsEveryRetry() throws {
        try BrowserImportScene.run { scene in
            SetupExtensionChanges.apply(.keepAll, to: [], in: scene.destination, store: scene.store, native: scene.engine)
            ImportedExtensionRetries.record(item(scene, Self.adBlock, "AdBlock"), store: scene.store)
            #expect(shown(ImportedExtensionFailures.take()) == ["AdBlock"])
        }
    }

    @Test func aLateFailureFromTheSetupBeforeAReplayFollowsThatSetupsChoice() throws {
        try BrowserImportScene.run { scene in
            let uBlock = OnboardingAdBlocker.uBlockOrigin
            let earlierKept = item(scene, uBlock, "uBlock Origin"), earlierLeftOut = item(scene, Self.adBlock, "AdBlock")
            SetupExtensionChanges.apply(.keep(uBlock), to: [], in: scene.destination, store: scene.store, native: scene.engine)
            SetupExtensionChanges.beginSetupRun()
            ImportedExtensionRetries.record(earlierLeftOut, store: scene.store)
            ImportedExtensionRetries.record(earlierKept, store: scene.store)
            let lateKept = ImportedExtensionFailures.take()
            #expect(scene.engine.setupChanges.isEmpty && shown(lateKept) == ["uBlock Origin"] && lateKept?.canRetry == true)
            #expect(ImportedExtensionFailures.take() == nil)
            ImportedExtensionRetries.retry(earlierLeftOut, store: scene.store)
            #expect(scene.engine.extensionInstalls.isEmpty)
            lateKept?.retry()
            #expect(scene.engine.extensionInstalls.map { $0.requests.map(ImportFixture.requestIDs) } == [[[uBlock]]])
        }
    }

    @Test func theReplaysOwnFailuresKeepRetryUntilItsChoice() throws {
        try BrowserImportScene.run { scene in
            SetupExtensionChanges.apply(.keep(OnboardingAdBlocker.uBlockOrigin), to: [], in: scene.destination,
                                        store: scene.store, native: scene.engine)
            SetupExtensionChanges.beginSetupRun()
            ImportedExtensionRetries.record(item(scene, Self.adBlock, "AdBlock"), store: scene.store)
            let replayFailure = ImportedExtensionFailures.take()
            #expect(shown(replayFailure) == ["AdBlock"] && replayFailure?.canRetry == true)
        }
    }

    @Test func retryLeavesAloneAProfileOnItsWayOut() throws {
        try BrowserImportScene.run { scene in
            let lab = scene.store.createProfile(name: "Lab")
            SetupExtensionChanges.removeAdBlocker(Self.adBlock, named: "AdBlock", from: lab, namingProfile: false,
                                                  store: scene.store, native: scene.engine)
            next(scene).complete(Refusal())
            let leaving = ImportedExtensionFailures.take()
            _ = try scene.store.stageProfileRemoval(lab, expectedName: "Lab")
            leaving?.retry()
            #expect(leaving?.canRetry == true && scene.engine.setupChanges.isEmpty)
        }
    }

    @Test func profilesThatAreGoneOrLeavingAreLeftAlone() throws {
        try BrowserImportScene.run { scene in
            let work = scene.store.createProfile(name: "Work")
            let gone = scene.store.createProfile(name: "Gone")
            _ = try scene.store.stageProfileRemoval(gone, expectedName: "Gone")
            #expect(SetupExtensionChanges.removableProfiles([scene.destination.profileID, gone, UUID(), work], in: scene.store.state)
                    == [scene.destination.profileID, work])
            SetupExtensionChanges.removeAdBlocker(Self.adBlock, named: "AdBlock", from: gone, namingProfile: false,
                                                  store: scene.store, native: scene.engine)
            #expect(scene.engine.setupChanges.isEmpty)
        }
    }
}
