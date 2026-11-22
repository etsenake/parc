import AppKit
import ParcCore
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import Parc
@testable import ParcOnboarding

extension BrowserImportPasswordTestsSupport {
    @MainActor
    struct BrowserImportPasswordFileTests {
        @Test func anUnrelatedSourceImportsWithoutThePasswordStage() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.passwords(scene, source: try scene.impostor())
                #expect(coordinator.stage == .finished && coordinator.passwordDestination == nil)
            }
        }

        @Test func aRetiredOwnerCannotEnterTheFileStep() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let coordinator = scene.chosen(try scene.safari(), profiles: ImportFixture.profiles([fixture.profile]))
                scene.current = false
                coordinator.continueSourceInline()
                #expect(coordinator.stage == .profiles && coordinator.passwordDestination == nil)
            }
        }

        @Test func safariGoesStraightToItsPasswordStageWithoutWritingOrImporting() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let before = scene.store.state
                let coordinator = try fixture.passwords(scene)
                #expect(coordinator.stage == .safariPasswords && coordinator.canImportPasswordFile)
                #expect(scene.store.state.profiles == before.profiles && scene.store.state.spaces == before.spaces)
                #expect(coordinator.passwordDestination?.profileID == scene.destination.profileID)
                #expect(scene.engine.imports == 0 && scene.engine.passwordRequests.isEmpty)
            }
        }

        @Test(arguments: [URL(string: "https://example.invalid/passwords.csv")!, URL(fileURLWithPath: "/fixture/passwords.txt")])
        func remoteAddressesAndNonCSVFilesNeverReachTheReader(_ url: URL) throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.passwords(scene)
                coordinator.importPasswordFile(url)
                #expect(scene.engine.passwordRequests.isEmpty && coordinator.passwordError != nil)
            }
        }

        @Test func theFileGoesOnlyToTheOriginalProfileAndWindow() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let (_, request) = try fixture.submitted(scene)
                #expect(request.url == fixture.file && request.window === scene.window && request.path == scene.originalPath)
            }
        }

        @Test func anAcceptedSessionOwnsAdmissionUntilItCompletes() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let (coordinator, _) = try fixture.submitted(scene)
                #expect(coordinator.importingPasswords && !coordinator.canImportPasswordFile)
                coordinator.importPasswordFile(fixture.file); coordinator.continueAfterPasswords()
                #expect(scene.engine.passwordRequests.isEmpty && coordinator.stage == .safariPasswords)
            }
        }

        @Test func stoppingAPasswordImportRequestsCancellation() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let (coordinator, request) = try fixture.submitted(scene)
                coordinator.stopPasswordImport()
                #expect(ImportFixture.cancelled(request.lease) && coordinator.importingPasswords)
            }
        }

        @Test func aCancelledPasswordImportKeepsConfirmedCountsWithoutOfferingRemoval() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let (coordinator, request) = try fixture.submitted(scene)
                coordinator.stopPasswordImport()
                request.complete(ImportFixture.password(.cancelled, imported: 1))
                #expect(!coordinator.importingPasswords && coordinator.passwordResult?.importedCount == 1)
                #expect(!coordinator.canRemovePasswordFile)
            }
        }

        @Test func aNewPasswordSubmissionRevokesTheOldLease() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let (coordinator, request) = try fixture.submitted(scene)
                request.complete(ImportFixture.password(.cancelled, imported: 1))
                coordinator.importPasswordFile(fixture.file)
                #expect(ImportFixture.cancelled(request.lease) && scene.engine.passwordRequests.count == 1)
            }
        }

        @Test func aNewPasswordSubmissionIgnoresTheOldResult() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let (coordinator, request) = try fixture.submitted(scene)
                request.complete(ImportFixture.password(.cancelled, imported: 1))
                coordinator.importPasswordFile(fixture.file)
                request.complete(ImportFixture.password(.completed, imported: 900, canRemove: true))
                #expect(coordinator.importingPasswords && coordinator.passwordResult == nil)
            }
        }

        @Test func aPartialImportKeepsTheSourceFile() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let (coordinator, request) = try fixture.submitted(scene)
                request.complete(ImportFixture.password(.partial, imported: 2, invalid: 1))
                #expect(!coordinator.canRemovePasswordFile && coordinator.passwordResult?.invalidCount == 1)
                coordinator.removePasswordFile()
                #expect(ImportTestRemovalCount(request.lease) == 0)
            }
        }

        @Test func confirmedSuccessPermitsOneExplicitRemovalThatMustFinishFirst() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let (coordinator, request) = try fixture.confirmed(scene)
                #expect(coordinator.canRemovePasswordFile && ImportTestRemovalCount(request.lease) == 0)
                coordinator.removePasswordFile(); coordinator.removePasswordFile()
                #expect(ImportTestRemovalCount(request.lease) == 1 && coordinator.removingPasswordFile)
                coordinator.continueAfterPasswords()
                #expect(coordinator.stage == .safariPasswords)
            }
        }

        @Test func aFailedPasswordFileRemovalShowsTheError() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let (coordinator, request) = try fixture.confirmed(scene)
                coordinator.removePasswordFile()
                ImportTestCompleteRemoval(request.lease, at: 0, error: NSError(domain: "fixture", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "The original file changed."]))
                #expect(!coordinator.passwordFileRemoved && coordinator.passwordError == "The original file changed.")
            }
        }

        @Test func aFailedPasswordFileRemovalCanBeRetried() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let (coordinator, request) = try fixture.confirmed(scene)
                coordinator.removePasswordFile()
                ImportTestCompleteRemoval(request.lease, at: 0, error: NSError(domain: "fixture", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "The original file changed."]))
                coordinator.removePasswordFile()
                #expect(ImportTestRemovalCount(request.lease) == 2)
                ImportTestCompleteRemoval(request.lease, at: 1, error: nil)
                #expect(coordinator.passwordFileRemoved && !coordinator.canRemovePasswordFile)
            }
        }

        @Test func continuingAfterPasswordsRevokesTheFileLease() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let (coordinator, request) = try fixture.confirmed(scene)
                coordinator.continueAfterPasswords()
                #expect(coordinator.stage == .finished && ImportFixture.cancelled(request.lease) && coordinator.passwordRequestID == nil)
            }
        }

        @Test func aLateFileResultCannotReopenAFinishedImport() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let (coordinator, request) = try fixture.confirmed(scene)
                coordinator.continueAfterPasswords()
                request.complete(ImportFixture.password(.failed))
                #expect(coordinator.stage == .finished)
            }
        }

        @Test func anImmediateNativeRefusalLeavesTheStageActionable() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.passwords(scene)
                scene.engine.rejectsPasswordImport = true
                coordinator.importPasswordFile(fixture.file)
                #expect(!coordinator.importingPasswords && coordinator.passwordError != nil && coordinator.canImportPasswordFile)
            }
        }

        @Test func aFormerPasswordImportOwnerCannotPublishAResult() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let (coordinator, losing) = try fixture.submitted(scene)
                scene.current = false
                losing.complete(ImportFixture.password(.completed, imported: 3, canRemove: true))
                #expect(coordinator.passwordResult == nil && !coordinator.canRemovePasswordFile)
            }
        }

        @Test func closingAPasswordImportRejectsLateCompletion() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let (coordinator, losing) = try fixture.submitted(scene)
                coordinator.cancel(); scene.current = true
                losing.complete(ImportFixture.password(.completed, imported: 3, canRemove: true))
                #expect(ImportFixture.cancelled(losing.lease) && coordinator.stage == .finished && coordinator.passwordResult == nil)
            }
        }

        @Test func skipReadsNoFileAndLeavesTheSidebarAlone() throws {
            let fixture = PasswordFixture()
            try BrowserImportScene.run { scene in
                let before = scene.store.state
                let coordinator = try fixture.passwords(scene)
                coordinator.continueAfterPasswords()
                #expect(coordinator.stage == .finished && scene.engine.passwordRequests.isEmpty)
                #expect(scene.store.state.profiles == before.profiles && scene.store.state.spaces == before.spaces
                        && scene.store.state.tabs == before.tabs)
            }
        }
    }
}
