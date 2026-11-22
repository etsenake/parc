import AppKit
import ParcCore
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import ParcOnboarding

extension BrowserImportPasswordTestsSupport {
    @MainActor
    struct BrowserImportPasswordHistoryTests {
        @Test func safariHistoryWaitsForThePasswordFileThenRunsInTheBackground() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.passwords(scene)
                #expect(coordinator.stage == .safariPasswords && coordinator.hasBackgroundWork && scene.engine.browserCompletions.isEmpty)
                coordinator.importPasswordFile(fixture.file)
                let request = scene.engine.passwordRequests.removeFirst()
                #expect(request.path == scene.originalPath && scene.engine.browserCompletions.isEmpty)
                request.complete(ImportFixture.password(.completed, imported: 3))
                coordinator.continueAfterPasswords()
                #expect(coordinator.stage == .finished && coordinator.hasBackgroundWork && scene.engine.browserCompletions.count == 1)
                #expect(scene.engine.browserRequests.last?.skipExistingCookies == true)
                scene.engine.finishBrowser()
                #expect(!coordinator.hasBackgroundWork && scene.engine.passwordRequests.isEmpty)
            }
        }

        @Test func closingMidFileStillBringsHistoryInOnceTheFileEnds() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let (closing, midFile) = try fixture.submitted(scene)
                closing.detach(onAdBlockers: nil)
                #expect(scene.engine.browserCompletions.isEmpty)
                midFile.complete(ImportFixture.password(.cancelled))
                #expect(scene.engine.browserCompletions.count == 1 && closing.hasBackgroundWork)
            }
        }

        @Test func aNewImportWaitsForTheLastImport() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let (closing, midFile) = try fixture.submitted(scene)
                closing.detach(onAdBlockers: nil)
                midFile.complete(ImportFixture.password(.cancelled))
                let following = try fixture.passwords(scene)
                #expect(following.stage == .importing && scene.engine.browserCompletions.count == 1)
                scene.engine.finishBrowser()
            }
        }

        @Test func aWaitingImportStartsWhenThePreviousOneFinishes() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let (closing, midFile) = try fixture.submitted(scene)
                closing.detach(onAdBlockers: nil)
                midFile.complete(ImportFixture.password(.cancelled))
                let following = try fixture.passwords(scene)
                scene.engine.finishBrowser()
                #expect(!closing.hasBackgroundWork)
                #expect(following.stage == .safariPasswords && following.passwordDestination?.profileID == scene.destination.profileID)
            }
        }

        @Test func stoppingAWaitingImportFinishesItImmediately() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let (closing, midFile) = try fixture.submitted(scene)
                closing.detach(onAdBlockers: nil)
                midFile.complete(ImportFixture.password(.cancelled))
                let abandoned = try fixture.passwords(scene)
                abandoned.stopImport()
                #expect(abandoned.stage == .finished)
                scene.engine.finishBrowser()
            }
        }

        @Test func aStoppedWaitingImportNeverStartsLater() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let (closing, midFile) = try fixture.submitted(scene)
                closing.detach(onAdBlockers: nil)
                midFile.complete(ImportFixture.password(.cancelled))
                let abandoned = try fixture.passwords(scene)
                abandoned.stopImport()
                scene.engine.finishBrowser()
                #expect(abandoned.stage == .finished && scene.engine.browserCompletions.isEmpty && scene.engine.passwordRequests.isEmpty)
            }
        }
    }
}
