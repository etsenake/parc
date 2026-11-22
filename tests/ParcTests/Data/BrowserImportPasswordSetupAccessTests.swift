import AppKit
import ParcCore
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import Parc

extension BrowserImportPasswordTestsSupport {
    @MainActor
    struct BrowserImportPasswordSetupAccessTests {
        private var restricted: PCNativeImportProfileResult {
            ImportFixture.profiles([ImportFixture.profile("Locked", [], .restricted)], .restricted)
        }

        private func access(_ scene: BrowserImportScene, safari: Bool = true) throws -> BrowserImportCoordinator {
            let safariSource = try scene.safari(), other = try scene.impostor()
            let coordinator = scene.coordinator(onboarding: true)
            scene.discovered(coordinator, [safariSource, other])
            coordinator.selectSourceInline(safari ? safariSource : other)
            scene.engine.profiles.removeFirst().complete(restricted)
            coordinator.continueSourceInline()
            return coordinator
        }

        private func passwordsLater(_ scene: BrowserImportScene) throws -> BrowserImportCoordinator {
            let coordinator = try access(scene)
            coordinator.skipInSetup()
            scene.engine.profiles.removeFirst().complete(restricted)
            return coordinator
        }

        @Test func safariAccessOffersBackAndDoThisLater() throws {
            try BrowserImportScene.run { scene in
                let coordinator = try access(scene)
                #expect(coordinator.stage == .safariAccess && coordinator.setupSkipTitle == "Do this later" && coordinator.canGoBackInSetup)
            }
        }

        @Test func backStopsTheAccessCheckAndKeepsSafariChosen() throws {
            try BrowserImportScene.run { scene in
                let coordinator = try access(scene)
                coordinator.continueSafariWithoutRestarting()
                let pending = scene.engine.profiles.removeFirst()
                coordinator.goBackInSetup()
                #expect(coordinator.stage == .profiles && coordinator.source?.identifier == "fresh Safari lease")
                #expect(coordinator.canContinueSourceInline && ImportFixture.cancelled(pending.lease))
                pending.complete(ImportFixture.profiles([ImportFixture.profile("Safari", [.history, .bookmarks])]))
                #expect(coordinator.stage == .profiles)
            }
        }

        @Test func continuingAfterCancellingTheAccessCheckOffersItAgain() throws {
            try BrowserImportScene.run { scene in
                let coordinator = try access(scene)
                coordinator.continueSafariWithoutRestarting()
                let pending = scene.engine.profiles.removeFirst()
                coordinator.goBackInSetup()
                pending.complete(ImportFixture.profiles([ImportFixture.profile("Safari", [.history, .bookmarks])]))
                coordinator.continueSourceInline()
                #expect(coordinator.stage == .safariAccess)
            }
        }

        @Test func doThisLaterOnSafariStillOffersItsPasswordFileAsTheOnlyPage() throws {
            try BrowserImportScene.run { scene in
                let coordinator = try passwordsLater(scene)
                #expect(coordinator.stage == .safariPasswords && coordinator.passwordDestination == scene.destination)
                #expect(coordinator.setupPage == .passwordFile && coordinator.setupPagesAhead.isEmpty)
                coordinator.goBackInSetup()
                #expect(coordinator.stage == .safariAccess && coordinator.passwordDestination == nil)
            }
        }

        @Test func thatPasswordPageCountsAsStartedAndFavoritesBackReturnsToAccess() throws {
            try BrowserImportScene.run { scene in
                let coordinator = try passwordsLater(scene)
                #expect(coordinator.hasStartedImportInSetup && coordinator.setupBackReturnsToSource)
                #expect(coordinator.returnToSourceInSetup() && coordinator.stage == .safariAccess)
                #expect(!coordinator.hasStartedImportInSetup && coordinator.passwordDestination == nil)
            }
        }

        @Test(arguments: [true, false])
        func anotherBrowserWithNothingReadableEndsTheImport(_ later: Bool) throws {
            try BrowserImportScene.run { scene in
                let coordinator = try access(scene, safari: false)
                if later { coordinator.skipInSetup() } else { coordinator.continueSafariWithoutRestarting() }
                scene.engine.profiles.removeFirst().complete(restricted)
                #expect(coordinator.stage == .finished && scene.engine.passwordRequests.isEmpty && scene.engine.imports == 0)
            }
        }

        @Test func setupLeavesItsImportStepOutWhenNoBrowserIsFound() throws {
            try BrowserImportScene.run { scene in
                let coordinator = scene.coordinator(onboarding: true)
                scene.discovered(coordinator, [])
                #expect(coordinator.stage == .finished && coordinator.foundNoSources)
            }
        }
    }
}
