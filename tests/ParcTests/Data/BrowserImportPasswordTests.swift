import AppKit
import ParcCore
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import Parc

@MainActor @Suite(.serialized)
struct BrowserImportPasswordTests {
    private let file = URL(fileURLWithPath: "/fixture/Passwords.csv")
    private let profile = ImportFixture.profile("Safari", [.history], .complete)

    private func passwords(_ scene: BrowserImportScene, source: PCNativeImportSource? = nil) throws -> BrowserImportCoordinator {
        scene.started(try source ?? scene.safari(), [profile])
    }

    private func submitted(_ scene: BrowserImportScene) throws
        -> (BrowserImportCoordinator, BrowserImportEngineFake.PasswordRequest) {
        let coordinator = try passwords(scene)
        coordinator.importPasswordFile(file)
        return (coordinator, scene.engine.passwordRequests.removeFirst())
    }

    private func confirmed(_ scene: BrowserImportScene) throws
        -> (BrowserImportCoordinator, BrowserImportEngineFake.PasswordRequest) {
        let (coordinator, request) = try submitted(scene)
        request.complete(ImportFixture.password(.completed, imported: 3, existing: 2, canRemove: true))
        return (coordinator, request)
    }

    @Test func anUnrelatedSourceImportsWithoutThePasswordStage() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try passwords(scene, source: try scene.impostor())
            #expect(coordinator.stage == .finished && coordinator.passwordDestination == nil)
        }
    }

    @Test func aRetiredOwnerCannotEnterTheFileStep() throws {
        try BrowserImportScene.run { scene in
            let coordinator = scene.chosen(try scene.safari(), profiles: ImportFixture.profiles([profile]))
            scene.current = false
            coordinator.continueSourceInline()
            #expect(coordinator.stage == .profiles && coordinator.passwordDestination == nil)
        }
    }

    @Test func safariGoesStraightToItsPasswordStageWithoutWritingOrImporting() throws {
        try BrowserImportScene.run { scene in
            let before = scene.store.state
            let coordinator = try passwords(scene)
            #expect(coordinator.stage == .safariPasswords && coordinator.canImportPasswordFile)
            #expect(scene.store.state.profiles == before.profiles && scene.store.state.spaces == before.spaces)
            #expect(coordinator.passwordDestination?.profileID == scene.destination.profileID)
            #expect(scene.engine.imports == 0 && scene.engine.passwordRequests.isEmpty)
        }
    }

    @Test(arguments: [URL(string: "https://example.invalid/passwords.csv")!, URL(fileURLWithPath: "/fixture/passwords.txt")])
    func remoteAddressesAndNonCSVFilesNeverReachTheReader(_ url: URL) throws {
        try BrowserImportScene.run { scene in
            let coordinator = try passwords(scene)
            coordinator.importPasswordFile(url)
            #expect(scene.engine.passwordRequests.isEmpty && coordinator.passwordError != nil)
        }
    }

    @Test func theFileGoesOnlyToTheOriginalProfileAndWindow() throws {
        try BrowserImportScene.run { scene in
            let (_, request) = try submitted(scene)
            #expect(request.url == file && request.window === scene.window && request.path == scene.originalPath)
        }
    }

    @Test func anAcceptedSessionOwnsAdmissionUntilItCompletes() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, _) = try submitted(scene)
            #expect(coordinator.importingPasswords && !coordinator.canImportPasswordFile)
            coordinator.importPasswordFile(file); coordinator.continueAfterPasswords()
            #expect(scene.engine.passwordRequests.isEmpty && coordinator.stage == .safariPasswords)
        }
    }

    @Test func stopRequestsCancellationAndKeepsConfirmedCountsWithoutRemoval() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, request) = try submitted(scene)
            coordinator.stopPasswordImport()
            #expect(ImportFixture.cancelled(request.lease) && coordinator.importingPasswords)
            request.complete(ImportFixture.password(.cancelled, imported: 1))
            #expect(!coordinator.importingPasswords && coordinator.passwordResult?.importedCount == 1)
            #expect(!coordinator.canRemovePasswordFile)
        }
    }

    @Test func aNewSubmissionRevokesTheOldLeaseAndIgnoresItsResult() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, request) = try submitted(scene)
            request.complete(ImportFixture.password(.cancelled, imported: 1))
            coordinator.importPasswordFile(file)
            #expect(ImportFixture.cancelled(request.lease) && scene.engine.passwordRequests.count == 1)
            request.complete(ImportFixture.password(.completed, imported: 900, canRemove: true))
            #expect(coordinator.importingPasswords && coordinator.passwordResult == nil)
        }
    }

    @Test func aPartialImportKeepsTheSourceFile() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, request) = try submitted(scene)
            request.complete(ImportFixture.password(.partial, imported: 2, invalid: 1))
            #expect(!coordinator.canRemovePasswordFile && coordinator.passwordResult?.invalidCount == 1)
            coordinator.removePasswordFile()
            #expect(ImportTestRemovalCount(request.lease) == 0)
        }
    }

    @Test func confirmedSuccessPermitsOneExplicitRemovalThatMustFinishFirst() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, request) = try confirmed(scene)
            #expect(coordinator.canRemovePasswordFile && ImportTestRemovalCount(request.lease) == 0)
            coordinator.removePasswordFile(); coordinator.removePasswordFile()
            #expect(ImportTestRemovalCount(request.lease) == 1 && coordinator.removingPasswordFile)
            coordinator.continueAfterPasswords()
            #expect(coordinator.stage == .safariPasswords)
        }
    }

    @Test func aFailedRemovalNeverClaimsSuccessAndCanBeRetried() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, request) = try confirmed(scene)
            coordinator.removePasswordFile()
            ImportTestCompleteRemoval(request.lease, at: 0, error: NSError(domain: "fixture", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The original file changed."]))
            #expect(!coordinator.passwordFileRemoved && coordinator.passwordError == "The original file changed.")
            coordinator.removePasswordFile()
            #expect(ImportTestRemovalCount(request.lease) == 2)
            ImportTestCompleteRemoval(request.lease, at: 1, error: nil)
            #expect(coordinator.passwordFileRemoved && !coordinator.canRemovePasswordFile)
        }
    }

    @Test func continueRevokesTheFileLeaseAndLateCallbacksCannotReopen() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, request) = try confirmed(scene)
            coordinator.continueAfterPasswords()
            #expect(coordinator.stage == .finished && ImportFixture.cancelled(request.lease) && coordinator.passwordRequestID == nil)
            request.complete(ImportFixture.password(.failed))
            #expect(coordinator.stage == .finished)
        }
    }

    @Test func anImmediateNativeRefusalLeavesTheStageActionable() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try passwords(scene)
            scene.engine.rejectsPasswordImport = true
            coordinator.importPasswordFile(file)
            #expect(!coordinator.importingPasswords && coordinator.passwordError != nil && coordinator.canImportPasswordFile)
        }
    }

    @Test func lostOwnershipCannotPublishAResultAndCloseRejectsLateCompletion() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, losing) = try submitted(scene)
            scene.current = false
            losing.complete(ImportFixture.password(.completed, imported: 3, canRemove: true))
            #expect(coordinator.passwordResult == nil && !coordinator.canRemovePasswordFile)
            coordinator.cancel(); scene.current = true
            losing.complete(ImportFixture.password(.completed, imported: 3, canRemove: true))
            #expect(ImportFixture.cancelled(losing.lease) && coordinator.stage == .finished && coordinator.passwordResult == nil)
        }
    }

    @Test func skipReadsNoFileAndLeavesTheSidebarAlone() throws {
        try BrowserImportScene.run { scene in
            let before = scene.store.state
            let coordinator = try passwords(scene)
            coordinator.continueAfterPasswords()
            #expect(coordinator.stage == .finished && scene.engine.passwordRequests.isEmpty)
            #expect(scene.store.state.profiles == before.profiles && scene.store.state.spaces == before.spaces
                    && scene.store.state.tabs == before.tabs)
        }
    }

    @Test func safariHistoryWaitsForThePasswordFileThenRunsInTheBackground() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try passwords(scene)
            #expect(coordinator.stage == .safariPasswords && coordinator.hasBackgroundWork && scene.engine.browserCompletions.isEmpty)
            coordinator.importPasswordFile(file)
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
        try BrowserImportScene.run { scene in
            let (closing, midFile) = try submitted(scene)
            closing.detach(onAdBlockers: nil)
            #expect(scene.engine.browserCompletions.isEmpty)
            midFile.complete(ImportFixture.password(.cancelled))
            #expect(scene.engine.browserCompletions.count == 1 && closing.hasBackgroundWork)
        }
    }

    @Test func aNewImportWaitsForTheLastOneAndThenStartsByItself() throws {
        try BrowserImportScene.run { scene in
            let (closing, midFile) = try submitted(scene)
            closing.detach(onAdBlockers: nil)
            midFile.complete(ImportFixture.password(.cancelled))
            let following = try passwords(scene)
            #expect(following.stage == .importing && scene.engine.browserCompletions.count == 1)
            scene.engine.finishBrowser()
            #expect(!closing.hasBackgroundWork)
            #expect(following.stage == .safariPasswords && following.passwordDestination?.profileID == scene.destination.profileID)
        }
    }

    @Test func aStoppedWaitingImportEndsAtOnceAndNeverStartsLater() throws {
        try BrowserImportScene.run { scene in
            let (closing, midFile) = try submitted(scene)
            closing.detach(onAdBlockers: nil)
            midFile.complete(ImportFixture.password(.cancelled))
            let abandoned = try passwords(scene)
            abandoned.stopImport()
            #expect(abandoned.stage == .finished)
            scene.engine.finishBrowser()
            #expect(abandoned.stage == .finished && scene.engine.browserCompletions.isEmpty && scene.engine.passwordRequests.isEmpty)
        }
    }
}

@MainActor @Suite(.serialized)
struct BrowserImportSetupOrderTests {
    private let selected = ImportFixture.bookmark("selected", title: "Keep", url: "https://example.org/setup-keep")
    private let omitted = ImportFixture.bookmark("omitted", title: "Leave", url: "https://example.org/setup-leave")
    private let file = URL(fileURLWithPath: "/fixture/Passwords.csv")

    private func start(_ scene: BrowserImportScene, onboarding: Bool = true, iCloud: Bool = false) throws -> BrowserImportCoordinator {
        let profile = ImportFixture.profile("Safari setup", [.history, .bookmarks])
        return scene.started(try scene.safari(), [profile], onboarding: onboarding, iCloud: iCloud)
    }

    private func read(_ scene: BrowserImportScene, _ bookmarks: [PCNativeImportedBookmark],
                      outcome: PCNativeImportOutcome = .completed) {
        scene.engine.finishBrowser(outcome, bookmarks: bookmarks)
        scene.engine.finishAllBrowser()
    }

    private func tabs(_ scene: BrowserImportScene, _ bookmark: PCNativeImportedBookmark) -> [BrowserTab] {
        scene.store.state.tabs.filter { $0.url == bookmark.url?.absoluteString }
    }

    private func readAndSkipped(_ scene: BrowserImportScene) throws -> BrowserImportCoordinator {
        let coordinator = try start(scene)
        read(scene, [selected, omitted])
        coordinator.skipInSetup()
        return coordinator
    }

    private func addedWithPasswords(_ scene: BrowserImportScene) throws -> BrowserImportCoordinator {
        let coordinator = try readAndSkipped(scene)
        coordinator.goBackInSetup()
        coordinator.commitBookmarks()
        coordinator.importPasswordFile(file)
        scene.engine.passwordRequests.removeFirst().complete(ImportFixture.password(.completed, imported: 2))
        coordinator.goBackInSetup()
        return coordinator
    }

    @Test func importingAdmitsTheOriginalSourceThroughTheCoordinator() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene)
            #expect(coordinator.stage == .importing)
        }
    }

    @Test func setupShowsBookmarksBeforePasswordGuidanceWithoutImportingEither() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene)
            let tabs = scene.store.state.tabs
            read(scene, [selected, omitted])
            #expect(coordinator.stage == .bookmarks && !coordinator.canImportPasswordFile)
            #expect(scene.store.state.tabs == tabs && scene.engine.passwordRequests.isEmpty)
            coordinator.continueAfterPasswords()
            #expect(coordinator.stage == .bookmarks && coordinator.bookmarkPages[0].selection.allSelected)
        }
    }

    @Test func acceptingBookmarksAdvancesToPasswordsKeepingTheOriginalDestination() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene)
            read(scene, [selected, omitted])
            coordinator.toggleBookmark(pageID: coordinator.bookmarkPages[0].id, id: omitted.identifier)
            scene.store.selectSpace(scene.store.createSpace(name: "Another active window"))
            coordinator.commitBookmarks()
            #expect(coordinator.stage == .safariPasswords && coordinator.bookmarkPages[0].committed)
            #expect(scene.engine.browserCompletions.isEmpty && coordinator.hasBackgroundWork)
            let imported = tabs(scene, selected)
            #expect(imported.count == 1 && imported.first?.spaceID == scene.destination.spaceID
                    && imported.first?.profileID == scene.destination.profileID)
            #expect(tabs(scene, omitted).isEmpty)
            #expect(coordinator.passwordDestination == scene.destination && coordinator.canImportPasswordFile)
        }
    }

    @Test func aRepeatedBookmarkActionCannotDuplicateOrSkipPasswords() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene)
            read(scene, [selected])
            coordinator.commitBookmarks()
            let accepted = scene.store.state.tabs
            coordinator.commitBookmarks()
            #expect(scene.store.state.tabs == accepted && coordinator.stage == .safariPasswords)
        }
    }

    @Test func skippingOptionalPasswordsFinishesAndStartsHistory() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene)
            read(scene, [selected])
            coordinator.commitBookmarks()
            let accepted = scene.store.state.tabs
            coordinator.continueAfterPasswords()
            #expect(coordinator.stage == .finished && scene.store.state.tabs == accepted && scene.engine.passwordRequests.isEmpty)
            #expect(scene.engine.browserCompletions.count == 1)
        }
    }

    @Test func noNativeBookmarksMeansNoEmptySelectionStep() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene)
            read(scene, [])
            #expect(coordinator.stage == .safariPasswords && coordinator.bookmarkPages.isEmpty)
        }
    }

    @Test func theMenuWizardAsksForPasswordsBeforeItsBookmarks() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene, onboarding: false)
            read(scene, [selected])
            #expect(coordinator.stage == .safariPasswords)
            coordinator.continueAfterPasswords()
            #expect(coordinator.stage == .bookmarks)
        }
    }

    @Test(arguments: [PCNativeImportOutcome.completed, .cancelled])
    func stoppingKeepsReturnedBookmarksWithoutAnotherOptionalStep(_ outcome: PCNativeImportOutcome) throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene)
            coordinator.stopImport()
            read(scene, [selected], outcome: outcome)
            #expect(coordinator.stage == .bookmarks)
            coordinator.toggleBookmark(pageID: coordinator.bookmarkPages[0].id, id: nil)
            coordinator.commitBookmarks()
            #expect(coordinator.stage == .finished && coordinator.passwordDestination == nil)
        }
    }

    @Test func theICloudChoiceFollowsBookmarksAndStartsOnTheExtensionWithoutAcceptingIt() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene, iCloud: true)
            read(scene, [selected])
            #expect(coordinator.stage == .bookmarks && coordinator.acceptedICloudPasswordsDestination == nil)
            coordinator.commitBookmarks()
            #expect(coordinator.stage == .passwordChoice && coordinator.canChoosePasswordMethod)
            #expect(coordinator.wantsICloudPasswords && !coordinator.canImportPasswordFile)
            coordinator.choosePasswordMethod(installExtension: true)
            #expect(coordinator.wantsICloudPasswords && coordinator.acceptedICloudPasswordsDestination == nil)
        }
    }

    @Test func staleFileActionsCannotActBehindTheMethodChooser() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene, iCloud: true)
            read(scene, [selected])
            coordinator.commitBookmarks()
            coordinator.importPasswordFile(file)
            #expect(scene.engine.passwordRequests.isEmpty)
            coordinator.continueAfterPasswords()
            #expect(coordinator.stage == .passwordChoice)
        }
    }

    @Test func nextAcceptsICloudForTheCapturedDestinationOnce() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene, iCloud: true)
            read(scene, [selected])
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
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene, iCloud: true)
            read(scene, [])
            coordinator.choosePasswordMethod(installExtension: true); coordinator.choosePasswordMethod(installExtension: false)
            coordinator.continuePasswordChoice()
            #expect(coordinator.stage == .safariPasswords && coordinator.canImportPasswordFile)
            #expect(coordinator.acceptedICloudPasswordsDestination == nil)
            coordinator.continueAfterPasswords()
            #expect(coordinator.stage == .finished && coordinator.acceptedICloudPasswordsDestination == nil)
        }
    }

    @Test func theMenuWizardKeepsItsOwnButtonsWhenICloudIsAvailable() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene, onboarding: false, iCloud: true)
            read(scene, [])
            #expect(coordinator.stage == .safariPasswords && !coordinator.canChoosePasswordMethod)
            #expect(coordinator.setupSkipTitle == nil && !coordinator.canGoBackInSetup)
        }
    }

    @Test func skipOnBookmarksGoesOnToPasswordsWithoutAddingBookmarks() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene)
            read(scene, [selected, omitted])
            #expect(coordinator.setupSkipTitle == "Skip for now" && coordinator.canGoBackInSetup)
            let tabs = scene.store.state.tabs
            coordinator.skipInSetup()
            #expect(coordinator.stage == .safariPasswords && scene.store.state.tabs == tabs)
            #expect(coordinator.setupSkipTitle == "Do this later" && !coordinator.canContinueSetupPasswords)
        }
    }

    @Test func whileAFileImportsDoThisLaterWaitsAndBackIsHidden() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try readAndSkipped(scene)
            coordinator.importPasswordFile(file)
            #expect(coordinator.setupSkipTitle == "Do this later" && !coordinator.canSkipInSetup && !coordinator.canGoBackInSetup)
            scene.engine.passwordRequests.removeFirst().complete(ImportFixture.password(.failed))
            #expect(!coordinator.canContinueSetupPasswords && coordinator.setupSkipTitle == "Do this later")
        }
    }

    @Test func backFromPasswordsOffersSkippedBookmarksAgainAndAddsThemOnce() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try readAndSkipped(scene)
            coordinator.goBackInSetup()
            #expect(coordinator.stage == .bookmarks && !coordinator.bookmarkPages[0].skipped && !coordinator.bookmarkPages[0].committed)
            let kept = tabs(scene, selected).count
            coordinator.commitBookmarks()
            #expect(coordinator.stage == .safariPasswords && tabs(scene, selected).count == kept + 1)
        }
    }

    @Test func onceAFileImportsNextIsEnabledAndDoThisLaterGoes() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try readAndSkipped(scene)
            coordinator.importPasswordFile(file)
            scene.engine.passwordRequests.removeFirst().complete(ImportFixture.password(.completed, imported: 2))
            #expect(coordinator.canContinueSetupPasswords && coordinator.setupSkipTitle == nil)
        }
    }

    @Test func backShowsAddedBookmarksStillTickedAndEditableWithoutChangingTabs() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try addedWithPasswords(scene)
            let tabs = scene.store.state.tabs
            #expect(coordinator.stage == .bookmarks && coordinator.bookmarkPages[0].committed)
            let accepted = coordinator.bookmarkPages[0]
            #expect(coordinator.canChooseBookmarks(accepted) && accepted.selection.selected == [selected.identifier, omitted.identifier])
            coordinator.toggleBookmark(pageID: accepted.id, id: omitted.identifier)
            #expect(scene.store.state.tabs == tabs)
        }
    }

    @Test func nextRemovesOnlyTheUntickedBookmarkAndRetickingAddsItOnce() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try addedWithPasswords(scene)
            let pageID = coordinator.bookmarkPages[0].id, before = scene.store.state.tabs.count
            let kept = try #require(tabs(scene, selected).first)
            coordinator.toggleBookmark(pageID: pageID, id: omitted.identifier)
            coordinator.commitBookmarks()
            #expect(coordinator.stage == .safariPasswords && coordinator.canContinueSetupPasswords)
            #expect(tabs(scene, omitted).isEmpty && tabs(scene, selected) == [kept] && scene.store.state.tabs.count == before - 1)
            coordinator.goBackInSetup()
            coordinator.toggleBookmark(pageID: pageID, id: omitted.identifier)
            coordinator.commitBookmarks()
            #expect(tabs(scene, omitted).count == 1 && tabs(scene, selected) == [kept] && scene.store.state.tabs.count == before)
        }
    }

    @Test func skipOnAnAddedPageKeepsWhatItAddedAndBackShowsThoseTicks() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try addedWithPasswords(scene)
            let pageID = coordinator.bookmarkPages[0].id, added = scene.store.state.tabs
            coordinator.toggleBookmark(pageID: pageID, id: selected.identifier)
            coordinator.skipInSetup()
            #expect(coordinator.stage == .safariPasswords && coordinator.canContinueSetupPasswords && scene.store.state.tabs == added)
            coordinator.goBackInSetup()
            #expect(coordinator.bookmarkPages[0].selection.selected == [selected.identifier, omitted.identifier])
        }
    }

    @Test func backAndNextLoopsAddNothingTwice() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try addedWithPasswords(scene)
            let added = scene.store.state.tabs
            for _ in 0..<3 { coordinator.commitBookmarks(); coordinator.goBackInSetup() }
            #expect(scene.store.state.tabs == added && coordinator.stage == .bookmarks)
        }
    }

    @Test func aFailedSaveKeepsThePreviousSetAndNextAfterwardsAppliesTheEditOnce() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try addedWithPasswords(scene)
            let pageID = coordinator.bookmarkPages[0].id, added = scene.store.state.tabs
            coordinator.toggleBookmark(pageID: pageID, id: selected.identifier)
            let session = scene.store.directory.appendingPathComponent("session.json")
            let backup = scene.store.directory.appendingPathComponent("prior-session.json")
            try FileManager.default.moveItem(at: session, to: backup)
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
            coordinator.commitBookmarks()
            #expect(coordinator.stage == .bookmarks && coordinator.error != nil && scene.store.state.tabs == added)
            #expect(coordinator.bookmarkPages[0].selection.selected == [omitted.identifier])
            try FileManager.default.removeItem(at: session)
            try FileManager.default.moveItem(at: backup, to: session)
            coordinator.commitBookmarks()
            #expect(coordinator.stage == .safariPasswords && tabs(scene, selected).isEmpty && tabs(scene, omitted).count == 1)
        }
    }

    @Test func goingForwardAgainKeepsImportedPasswordsAndNextFinishes() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try addedWithPasswords(scene)
            let added = scene.store.state.tabs
            coordinator.skipInSetup()
            #expect(coordinator.stage == .safariPasswords && coordinator.canContinueSetupPasswords && scene.store.state.tabs == added)
            coordinator.skipInSetup()
            #expect(coordinator.stage == .safariPasswords)
            coordinator.continueAfterPasswords()
            #expect(coordinator.stage == .finished)
        }
    }

    @Test func backFromTheFileReturnsToTheChoiceAndSkipThereFinishesWithNothing() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene, iCloud: true)
            read(scene, [])
            #expect(coordinator.stage == .passwordChoice && coordinator.setupSkipTitle == "Skip for now")
            coordinator.choosePasswordMethod(installExtension: false); coordinator.continuePasswordChoice()
            coordinator.goBackInSetup()
            #expect(coordinator.stage == .passwordChoice && !coordinator.wantsICloudPasswords)
            coordinator.choosePasswordMethod(installExtension: true)
            coordinator.skipInSetup()
            #expect(coordinator.stage == .finished && coordinator.acceptedICloudPasswordsDestination == nil
                    && coordinator.passwordDestination == nil)
        }
    }

    @Test func backFromBookmarksParksThemBehindTheCardsAndNextReturnsWithoutImporting() throws {
        try BrowserImportScene.run { scene in
            let safari = try scene.safari()
            let coordinator = scene.started(safari, [ImportFixture.profile("Safari setup", [.history, .bookmarks])], onboarding: true)
            let imports = scene.engine.imports
            read(scene, [selected])
            let afterRead = scene.engine.imports
            coordinator.goBackInSetup()
            #expect(coordinator.stage == .profiles && coordinator.parkedStage == .bookmarks && coordinator.source === safari)
            #expect(coordinator.canContinueSourceInline && !coordinator.canGoBackInSetup && coordinator.setupSkipTitle == nil)
            coordinator.selectSourceInline(safari); coordinator.clearSourceInline()
            #expect(coordinator.source === safari && coordinator.parkedStage == .bookmarks)
            coordinator.continueSourceInline()
            #expect(coordinator.stage == .bookmarks && coordinator.bookmarkPages.count == 1 && scene.engine.imports == afterRead)
            #expect(imports == 1)
        }
    }

    @Test func aRunningImportStaysRunningWhenSteppingBack() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene, iCloud: true)
            #expect(coordinator.hasStartedImportInSetup && !coordinator.isRestingInSetup && coordinator.setupBackReturnsToSource)
            #expect(!coordinator.returnToSourceInSetup() && coordinator.stage == .importing)
        }
    }

    @Test func backFromFavoritesKeepsResultsAndComingForwardDoesNotImportTwice() throws {
        try BrowserImportScene.run { scene in
            let safari = try scene.safari()
            let coordinator = scene.started(safari, [ImportFixture.profile("Safari setup", [.history, .bookmarks])],
                                            onboarding: true, iCloud: true)
            read(scene, [selected])
            #expect(coordinator.stage == .bookmarks && coordinator.isRestingInSetup && coordinator.setupBackReturnsToSource)
            let imports = scene.engine.imports
            #expect(coordinator.returnToSourceInSetup() && coordinator.stage == .profiles && coordinator.parkedStage == .bookmarks)
            #expect(coordinator.source === safari && coordinator.hasStartedImportInSetup && !coordinator.isRestingInSetup)
            coordinator.continueSourceInline()
            #expect(coordinator.stage == .bookmarks && coordinator.bookmarkPages.count == 1 && scene.engine.imports == imports)
        }
    }

    @Test func theWaitingPasswordChoiceComesBackAsItWasLeft() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene, iCloud: true)
            read(scene, [selected])
            coordinator.commitBookmarks()
            #expect(coordinator.stage == .passwordChoice && !coordinator.setupBackReturnsToSource)
            coordinator.choosePasswordMethod(installExtension: false)
            #expect(coordinator.returnToSourceInSetup() && coordinator.parkedStage == .passwordChoice)
            coordinator.continueSourceInline()
            #expect(coordinator.stage == .passwordChoice && !coordinator.wantsICloudPasswords)
            coordinator.continuePasswordChoice()
            #expect(coordinator.stage == .safariPasswords && !coordinator.setupBackReturnsToSource)
        }
    }

    @Test func aPasswordFileStillImportingKeepsItsPageAndAFinishedOneWaitsBehindTheCards() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene)
            read(scene, [])
            #expect(coordinator.stage == .safariPasswords && coordinator.setupBackReturnsToSource && coordinator.isRestingInSetup)
            coordinator.importPasswordFile(file)
            let request = scene.engine.passwordRequests.removeFirst()
            #expect(!coordinator.returnToSourceInSetup() && coordinator.stage == .safariPasswords && coordinator.parkedStage == nil)
            request.complete(ImportFixture.password(.completed, imported: 1))
            #expect(coordinator.returnToSourceInSetup() && coordinator.parkedStage == .safariPasswords)
            #expect(coordinator.passwordImportCompleted)
            coordinator.continueSourceInline()
            #expect(coordinator.stage == .safariPasswords && coordinator.canContinueSetupPasswords)
        }
    }

    @Test func setupCountsTheImportPagesStillAheadThroughTheICloudChoice() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene, iCloud: true)
            #expect(coordinator.setupPage == .progress && coordinator.setupPagesAhead == [.bookmarks, .passwordChoice])
            read(scene, [selected])
            #expect(coordinator.setupPage == .bookmarks && coordinator.setupPagesAhead == [.passwordChoice])
            coordinator.commitBookmarks()
            #expect(coordinator.setupPage == .passwordChoice && coordinator.setupPagesAhead.isEmpty)
            coordinator.choosePasswordMethod(installExtension: false)
            #expect(coordinator.setupPagesAhead == [.passwordFile])
            coordinator.continuePasswordChoice()
            #expect(coordinator.setupPage == .passwordFile && coordinator.setupPagesAhead.isEmpty)
            coordinator.goBackInSetup(); coordinator.goBackInSetup()
            #expect(coordinator.setupPage == .bookmarks && coordinator.setupPagesAhead == [.passwordChoice, .passwordFile])
            #expect(coordinator.returnToSourceInSetup() && coordinator.setupPage == .bookmarks
                    && coordinator.setupPagesAhead == [.passwordChoice, .passwordFile])
        }
    }

    @Test func withoutApplesHelperSafariExpectsBookmarksAndThePasswordFile() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene)
            #expect(coordinator.setupPagesAhead == [.bookmarks, .passwordFile])
            read(scene, [])
            #expect(coordinator.setupPage == .passwordFile && coordinator.setupPagesAhead.isEmpty)
        }
    }

    @Test func stopImportKeepsReadBookmarksAndDropsThePasswordPage() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene)
            coordinator.stopImport()
            read(scene, [selected], outcome: .cancelled)
            #expect(coordinator.setupPage == .bookmarks && coordinator.setupPagesAhead.isEmpty)
        }
    }
}

@MainActor @Suite(.serialized)
struct BrowserImportSetupAccessTests {
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

    @Test func backStopsTheAccessCheckAndKeepsSafariChosen() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try access(scene)
            #expect(coordinator.stage == .safariAccess && coordinator.setupSkipTitle == "Do this later" && coordinator.canGoBackInSetup)
            coordinator.continueSafariWithoutRestarting()
            let pending = scene.engine.profiles.removeFirst()
            coordinator.goBackInSetup()
            #expect(coordinator.stage == .profiles && coordinator.source?.identifier == "fresh Safari lease")
            #expect(coordinator.canContinueSourceInline && ImportFixture.cancelled(pending.lease))
            pending.complete(ImportFixture.profiles([ImportFixture.profile("Safari", [.history, .bookmarks])]))
            #expect(coordinator.stage == .profiles)
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
