import AppKit
@testable import ParcCore
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import Parc

extension BrowserImportPasswordTestsSupport {
    @MainActor
    struct BrowserImportPasswordSetupSequenceTests {
        @Test func importingAdmitsTheOriginalSourceThroughTheCoordinator() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene)
                #expect(coordinator.stage == .importing)
            }
        }

        @Test func setupShowsBookmarksBeforePasswordGuidanceWithoutImportingEither() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene)
                let tabs = scene.store.state.tabs
                fixture.read(scene, [fixture.selected, fixture.omitted])
                #expect(coordinator.stage == .bookmarks && !coordinator.canImportPasswordFile)
                #expect(scene.store.state.tabs == tabs && scene.engine.passwordRequests.isEmpty)
                coordinator.continueAfterPasswords()
                #expect(coordinator.stage == .bookmarks && coordinator.bookmarkPages[0].selection.allSelected)
            }
        }

        @Test func acceptingBookmarksAdvancesToPasswordsKeepingTheOriginalDestination() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene)
                fixture.read(scene, [fixture.selected, fixture.omitted])
                coordinator.toggleBookmark(pageID: coordinator.bookmarkPages[0].id, id: fixture.omitted.identifier)
                scene.store.selectSpace(scene.store.createSpace(name: "Another active window"))
                coordinator.commitBookmarks()
                #expect(coordinator.stage == .safariPasswords && coordinator.bookmarkPages[0].committed)
                #expect(scene.engine.browserCompletions.isEmpty && coordinator.hasBackgroundWork)
                let imported = fixture.tabs(scene, fixture.selected)
                #expect(imported.count == 1 && imported.first?.spaceID == scene.destination.spaceID
                        && imported.first?.profileID == scene.destination.profileID)
                #expect(fixture.tabs(scene, fixture.omitted).isEmpty)
                #expect(coordinator.passwordDestination == scene.destination && coordinator.canImportPasswordFile)
            }
        }

        @Test func aRepeatedBookmarkActionCannotDuplicateOrSkipPasswords() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene)
                fixture.read(scene, [fixture.selected])
                coordinator.commitBookmarks()
                let accepted = scene.store.state.tabs
                coordinator.commitBookmarks()
                #expect(scene.store.state.tabs == accepted && coordinator.stage == .safariPasswords)
            }
        }

        @Test func skippingOptionalPasswordsFinishesAndStartsHistory() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene)
                fixture.read(scene, [fixture.selected])
                coordinator.commitBookmarks()
                let accepted = scene.store.state.tabs
                coordinator.continueAfterPasswords()
                #expect(coordinator.stage == .finished && scene.store.state.tabs == accepted && scene.engine.passwordRequests.isEmpty)
                #expect(scene.engine.browserCompletions.count == 1)
            }
        }

        @Test func noNativeBookmarksMeansNoEmptySelectionStep() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene)
                fixture.read(scene, [])
                #expect(coordinator.stage == .safariPasswords && coordinator.bookmarkPages.isEmpty)
            }
        }

        @Test func theMenuWizardAsksForPasswordsBeforeItsBookmarks() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene, onboarding: false)
                fixture.read(scene, [fixture.selected])
                #expect(coordinator.stage == .safariPasswords)
                coordinator.continueAfterPasswords()
                #expect(coordinator.stage == .bookmarks)
            }
        }

        @Test(arguments: [PCNativeImportOutcome.completed, .cancelled])
        func stoppingKeepsReturnedBookmarksWithoutAnotherOptionalStep(_ outcome: PCNativeImportOutcome) throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene)
                coordinator.stopImport()
                fixture.read(scene, [fixture.selected], outcome: outcome)
                #expect(coordinator.stage == .bookmarks)
                coordinator.toggleBookmark(pageID: coordinator.bookmarkPages[0].id, id: nil)
                coordinator.commitBookmarks()
                #expect(coordinator.stage == .finished && coordinator.passwordDestination == nil)
            }
        }

        @Test func theICloudChoiceFollowsBookmarksAndStartsOnTheExtensionWithoutAcceptingIt() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene, iCloud: true)
                fixture.read(scene, [fixture.selected])
                #expect(coordinator.stage == .bookmarks && coordinator.acceptedICloudPasswordsDestination == nil)
                coordinator.commitBookmarks()
                #expect(coordinator.stage == .passwordChoice && coordinator.canChoosePasswordMethod)
                #expect(coordinator.wantsICloudPasswords && !coordinator.canImportPasswordFile)
                coordinator.choosePasswordMethod(installExtension: true)
                #expect(coordinator.wantsICloudPasswords && coordinator.acceptedICloudPasswordsDestination == nil)
            }
        }

        @Test func staleFileActionsCannotActBehindTheMethodChooser() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene, iCloud: true)
                fixture.read(scene, [fixture.selected])
                coordinator.commitBookmarks()
                coordinator.importPasswordFile(fixture.file)
                #expect(scene.engine.passwordRequests.isEmpty)
                coordinator.continueAfterPasswords()
                #expect(coordinator.stage == .passwordChoice)
            }
        }

        @Test func nextAcceptsICloudForTheCapturedDestinationOnce() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene, iCloud: true)
                fixture.read(scene, [fixture.selected])
                scene.store.selectSpace(scene.store.createSpace(name: "Another active window"))
                coordinator.commitBookmarks()
                coordinator.continuePasswordChoice()
                #expect(coordinator.stage == .finished && coordinator.acceptedICloudPasswordsDestination == scene.destination)
                #expect(scene.engine.browserCompletions.count == 1)
                #expect(coordinator.passwordDestination == nil && !coordinator.canImportPasswordFile)
                coordinator.choosePasswordMethod(installExtension: false); coordinator.continuePasswordChoice()
                #expect(coordinator.acceptedICloudPasswordsDestination == scene.destination)
                coordinator.cancel()
                #expect(coordinator.acceptedICloudPasswordsDestination == nil)
            }
        }

        @Test func changingBackToManualReachesTheFileWithoutAcceptingTheExtension() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene, iCloud: true)
                fixture.read(scene, [])
                coordinator.choosePasswordMethod(installExtension: true); coordinator.choosePasswordMethod(installExtension: false)
                coordinator.continuePasswordChoice()
                #expect(coordinator.stage == .safariPasswords && coordinator.canImportPasswordFile)
                #expect(coordinator.acceptedICloudPasswordsDestination == nil)
                coordinator.continueAfterPasswords()
                #expect(coordinator.stage == .finished && coordinator.acceptedICloudPasswordsDestination == nil)
            }
        }

        @Test func theMenuWizardKeepsItsOwnButtonsWhenICloudIsAvailable() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene, onboarding: false, iCloud: true)
                fixture.read(scene, [])
                #expect(coordinator.stage == .safariPasswords && !coordinator.canChoosePasswordMethod)
                #expect(coordinator.setupSkipTitle == nil && !coordinator.canGoBackInSetup)
            }
        }

        @Test func skipOnBookmarksGoesOnToPasswordsWithoutAddingBookmarks() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene)
                fixture.read(scene, [fixture.selected, fixture.omitted])
                #expect(coordinator.setupSkipTitle == "Skip for now" && coordinator.canGoBackInSetup)
                let tabs = scene.store.state.tabs
                coordinator.skipInSetup()
                #expect(coordinator.stage == .safariPasswords && scene.store.state.tabs == tabs)
                #expect(coordinator.setupSkipTitle == "Do this later" && !coordinator.canContinueSetupPasswords)
            }
        }
    }
}
