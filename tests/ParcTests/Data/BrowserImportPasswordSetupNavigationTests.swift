import AppKit
import ParcCore
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import ParcOnboarding

extension BrowserImportPasswordTestsSupport {
    @MainActor
    struct BrowserImportPasswordSetupNavigationTests {
        @Test func whileAFileImportsDoThisLaterWaitsAndBackIsHidden() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.readAndSkipped(scene)
                coordinator.importPasswordFile(fixture.file)
                #expect(coordinator.setupSkipTitle == "Do this later" && !coordinator.canSkipInSetup && !coordinator.canGoBackInSetup)
                scene.engine.passwordRequests.removeFirst().complete(ImportFixture.password(.failed))
                #expect(!coordinator.canContinueSetupPasswords && coordinator.setupSkipTitle == "Do this later")
            }
        }

        @Test func backFromPasswordsOffersSkippedBookmarksAgainAndAddsThemOnce() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.readAndSkipped(scene)
                coordinator.goBackInSetup()
                #expect(coordinator.stage == .bookmarks && !coordinator.bookmarkPages[0].skipped && !coordinator.bookmarkPages[0].committed)
                let kept = fixture.tabs(scene, fixture.selected).count
                coordinator.commitBookmarks()
                #expect(coordinator.stage == .safariPasswords && fixture.tabs(scene, fixture.selected).count == kept + 1)
            }
        }

        @Test func onceAFileImportsNextIsEnabledAndDoThisLaterGoes() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.readAndSkipped(scene)
                coordinator.importPasswordFile(fixture.file)
                scene.engine.passwordRequests.removeFirst().complete(ImportFixture.password(.completed, imported: 2))
                #expect(coordinator.canContinueSetupPasswords && coordinator.setupSkipTitle == nil)
            }
        }

        @Test func backShowsAddedBookmarksStillTickedAndEditableWithoutChangingTabs() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.addedWithPasswords(scene)
                let tabs = scene.store.state.tabs
                #expect(coordinator.stage == .bookmarks && coordinator.bookmarkPages[0].committed)
                let accepted = coordinator.bookmarkPages[0]
                #expect(coordinator.canChooseBookmarks(accepted) && accepted.selection.selected == [fixture.selected.identifier, fixture.omitted.identifier])
                coordinator.toggleBookmark(pageID: accepted.id, id: fixture.omitted.identifier)
                #expect(scene.store.state.tabs == tabs)
            }
        }

        @Test func nextRemovesOnlyTheUntickedBookmark() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.addedWithPasswords(scene)
                let pageID = coordinator.bookmarkPages[0].id, before = scene.store.state.tabs.count
                let kept = try #require(fixture.tabs(scene, fixture.selected).first)
                coordinator.toggleBookmark(pageID: pageID, id: fixture.omitted.identifier)
                coordinator.commitBookmarks()
                #expect(coordinator.stage == .safariPasswords && coordinator.canContinueSetupPasswords)
                #expect(fixture.tabs(scene, fixture.omitted).isEmpty && fixture.tabs(scene, fixture.selected) == [kept] && scene.store.state.tabs.count == before - 1)
            }
        }

        @Test func retickingARemovedBookmarkAddsItOnce() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.addedWithPasswords(scene)
                let pageID = coordinator.bookmarkPages[0].id, before = scene.store.state.tabs.count
                let kept = try #require(fixture.tabs(scene, fixture.selected).first)
                coordinator.toggleBookmark(pageID: pageID, id: fixture.omitted.identifier)
                coordinator.commitBookmarks()
                coordinator.goBackInSetup()
                coordinator.toggleBookmark(pageID: pageID, id: fixture.omitted.identifier)
                coordinator.commitBookmarks()
                #expect(fixture.tabs(scene, fixture.omitted).count == 1 && fixture.tabs(scene, fixture.selected) == [kept] && scene.store.state.tabs.count == before)
            }
        }

        @Test func skipOnAnAddedPageKeepsWhatItAddedAndBackShowsThoseTicks() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.addedWithPasswords(scene)
                let pageID = coordinator.bookmarkPages[0].id, added = scene.store.state.tabs
                coordinator.toggleBookmark(pageID: pageID, id: fixture.selected.identifier)
                coordinator.skipInSetup()
                #expect(coordinator.stage == .safariPasswords && coordinator.canContinueSetupPasswords && scene.store.state.tabs == added)
                coordinator.goBackInSetup()
                #expect(coordinator.bookmarkPages[0].selection.selected == [fixture.selected.identifier, fixture.omitted.identifier])
            }
        }

        @Test func backAndNextLoopsAddNothingTwice() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.addedWithPasswords(scene)
                let added = scene.store.state.tabs
                for _ in 0..<3 { coordinator.commitBookmarks(); coordinator.goBackInSetup() }
                #expect(scene.store.state.tabs == added && coordinator.stage == .bookmarks)
            }
        }

        @Test func aFailedBookmarkSaveKeepsThePreviousSetAndPendingEdit() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.addedWithPasswords(scene)
                let pageID = coordinator.bookmarkPages[0].id, added = scene.store.state.tabs
                coordinator.toggleBookmark(pageID: pageID, id: fixture.selected.identifier)
                let session = scene.store.directory.appendingPathComponent("session.json")
                let backup = scene.store.directory.appendingPathComponent("prior-session.json")
                try FileManager.default.moveItem(at: session, to: backup)
                try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
                coordinator.commitBookmarks()
                #expect(coordinator.stage == .bookmarks && coordinator.error != nil && scene.store.state.tabs == added)
                #expect(coordinator.bookmarkPages[0].selection.selected == [fixture.omitted.identifier])
            }
        }

        @Test func retryingABookmarkSaveAppliesThePendingEditOnce() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.addedWithPasswords(scene)
                let pageID = coordinator.bookmarkPages[0].id
                coordinator.toggleBookmark(pageID: pageID, id: fixture.selected.identifier)
                let session = scene.store.directory.appendingPathComponent("session.json")
                let backup = scene.store.directory.appendingPathComponent("prior-session.json")
                try FileManager.default.moveItem(at: session, to: backup)
                try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
                coordinator.commitBookmarks()
                try FileManager.default.removeItem(at: session)
                try FileManager.default.moveItem(at: backup, to: session)
                coordinator.commitBookmarks()
                #expect(coordinator.stage == .safariPasswords && fixture.tabs(scene, fixture.selected).isEmpty && fixture.tabs(scene, fixture.omitted).count == 1)
            }
        }

        @Test func skippingBookmarksAgainKeepsImportedPasswords() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.addedWithPasswords(scene)
                let added = scene.store.state.tabs
                coordinator.skipInSetup()
                #expect(coordinator.stage == .safariPasswords && coordinator.canContinueSetupPasswords && scene.store.state.tabs == added)
            }
        }

        @Test func aCompletedPasswordPageNeedsNextToFinish() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.addedWithPasswords(scene)
                coordinator.skipInSetup()
                coordinator.skipInSetup()
                #expect(coordinator.stage == .safariPasswords)
                coordinator.continueAfterPasswords()
                #expect(coordinator.stage == .finished)
            }
        }

        @Test func backFromThePasswordFileReturnsToTheMethodChoice() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene, iCloud: true)
                fixture.read(scene, [])
                #expect(coordinator.stage == .passwordChoice && coordinator.setupSkipTitle == "Skip for now")
                coordinator.choosePasswordMethod(installExtension: false); coordinator.continuePasswordChoice()
                coordinator.goBackInSetup()
                #expect(coordinator.stage == .passwordChoice && !coordinator.wantsICloudPasswords)
            }
        }

        @Test func skippingThePasswordMethodAfterGoingBackFinishesWithoutImporting() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene, iCloud: true)
                fixture.read(scene, [])
                coordinator.choosePasswordMethod(installExtension: false); coordinator.continuePasswordChoice()
                coordinator.goBackInSetup()
                coordinator.choosePasswordMethod(installExtension: true)
                coordinator.skipInSetup()
                #expect(coordinator.stage == .finished && coordinator.acceptedICloudPasswordsDestination == nil
                        && coordinator.passwordDestination == nil)
            }
        }

        @Test func backFromBookmarksParksThemBehindTheCardsAndNextReturnsWithoutImporting() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let safari = try scene.safari()
                let coordinator = scene.started(safari, [ImportFixture.profile("Safari setup", [.history, .bookmarks])], onboarding: true)
                let imports = scene.engine.imports
                fixture.read(scene, [fixture.selected])
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
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene, iCloud: true)
                #expect(coordinator.hasStartedImportInSetup && !coordinator.isRestingInSetup && coordinator.setupBackReturnsToSource)
                #expect(!coordinator.returnToSourceInSetup() && coordinator.stage == .importing)
            }
        }

        @Test func backFromFavoritesKeepsResultsAndComingForwardDoesNotImportTwice() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let safari = try scene.safari()
                let coordinator = scene.started(safari, [ImportFixture.profile("Safari setup", [.history, .bookmarks])],
                                                onboarding: true, iCloud: true)
                fixture.read(scene, [fixture.selected])
                #expect(coordinator.stage == .bookmarks && coordinator.isRestingInSetup && coordinator.setupBackReturnsToSource)
                let imports = scene.engine.imports
                #expect(coordinator.returnToSourceInSetup() && coordinator.stage == .profiles && coordinator.parkedStage == .bookmarks)
                #expect(coordinator.source === safari && coordinator.hasStartedImportInSetup && !coordinator.isRestingInSetup)
                coordinator.continueSourceInline()
                #expect(coordinator.stage == .bookmarks && coordinator.bookmarkPages.count == 1 && scene.engine.imports == imports)
            }
        }

        @Test func theWaitingPasswordChoiceComesBackAsItWasLeft() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene, iCloud: true)
                fixture.read(scene, [fixture.selected])
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

        @Test func aPasswordFileStillImportingKeepsItsPage() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene)
                fixture.read(scene, [])
                #expect(coordinator.stage == .safariPasswords && coordinator.setupBackReturnsToSource && coordinator.isRestingInSetup)
                coordinator.importPasswordFile(fixture.file)
                #expect(!coordinator.returnToSourceInSetup() && coordinator.stage == .safariPasswords && coordinator.parkedStage == nil)
            }
        }

        @Test func aFinishedPasswordFileWaitsBehindTheSetupCards() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene)
                fixture.read(scene, [])
                coordinator.importPasswordFile(fixture.file)
                let request = scene.engine.passwordRequests.removeFirst()
                request.complete(ImportFixture.password(.completed, imported: 1))
                #expect(coordinator.returnToSourceInSetup() && coordinator.parkedStage == .safariPasswords)
                #expect(coordinator.passwordImportCompleted)
                coordinator.continueSourceInline()
                #expect(coordinator.stage == .safariPasswords && coordinator.canContinueSetupPasswords)
            }
        }

        @Test func setupCountsTheImportPagesStillAheadThroughTheICloudChoice() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene, iCloud: true)
                #expect(coordinator.setupPage == .progress && coordinator.setupPagesAhead == [.bookmarks, .passwordChoice])
                fixture.read(scene, [fixture.selected])
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
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene)
                #expect(coordinator.setupPagesAhead == [.bookmarks, .passwordFile])
                fixture.read(scene, [])
                #expect(coordinator.setupPage == .passwordFile && coordinator.setupPagesAhead.isEmpty)
            }
        }

        @Test func stopImportKeepsReadBookmarksAndDropsThePasswordPage() throws {
            let fixture = SetupFixture()
            try BrowserImportScene.run { scene in
                let coordinator = try fixture.start(scene)
                coordinator.stopImport()
                fixture.read(scene, [fixture.selected], outcome: .cancelled)
                #expect(coordinator.setupPage == .bookmarks && coordinator.setupPagesAhead.isEmpty)
            }
        }
    }
}
