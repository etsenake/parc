import AppKit
import ParcCore
import ParcEngine
import Testing
@testable import ParcOnboarding

@MainActor @Suite(.serialized)
struct BrowserImportFirefoxTests {
    private let file = URL(fileURLWithPath: "/fixture/passwords.csv")

    private func profile(_ identifier: String = "default-release") -> PCNativeImportProfile {
        ImportFixture.profile(identifier, [.history, .bookmarks], name: "Firefox")
    }

    private func start(_ scene: BrowserImportScene, onboarding: Bool, source: PCNativeImportSource? = nil) -> BrowserImportCoordinator {
        scene.started(source ?? scene.firefox(), [profile()], onboarding: onboarding, iCloud: true)
    }

    private func bookmark(_ name: String) -> PCNativeImportedBookmark {
        ImportFixture.bookmark(name, title: name, url: "https://example.org/" + name)
    }

    private func atPasswords(_ scene: BrowserImportScene) -> BrowserImportCoordinator {
        let coordinator = start(scene, onboarding: true)
        scene.engine.finishBrowser(bookmarks: [bookmark("kept")])
        coordinator.commitBookmarks()
        return coordinator
    }

    private func waitingOnChrome(_ scene: BrowserImportScene) throws -> (BrowserImportCoordinator, BrowserImportCoordinator) {
        let chrome = try scene.chrome(), firefox = scene.firefox()
        let earlier = start(scene, onboarding: true, source: chrome)
        scene.engine.finishBrowser(bookmarks: [bookmark("chrome")])
        _ = earlier.returnToSourceInSetup()
        earlier.onChange = nil; earlier.detach(onAdBlockers: nil)
        let switched = scene.coordinator(onboarding: true, iCloud: true)
        scene.discovered(switched, [chrome, firefox])
        switched.selectSourceInline(firefox)
        scene.engine.profiles.removeFirst().complete(ImportFixture.profiles([profile("switched-release")]))
        switched.continueSourceInline()
        return (earlier, switched)
    }

    @Test func firefoxAndZenAreRecognisedForTheirPasswordFileWithoutAKeychainNote() throws {
        try BrowserImportScene.run { scene in
            #expect(BrowserImportCoordinator.passwordExport(for: scene.firefox()) == .firefox)
            #expect(BrowserImportCoordinator.passwordExport(for: scene.zen()) == .zen)
            #expect(BrowserPasswordExport.zen.wrongFileMessage == "Choose the passwords.csv file exported by Zen.")
            #expect(BrowserImportCoordinator.keychainNote(for: scene.zen()) == nil)
            #expect(BrowserImportCoordinator.keychainNote(for: scene.firefox()) == nil)
        }
    }

    @Test(arguments: [false, true])
    func setupExpectsTheBookmarksAndPasswordFilePages(_ zen: Bool) throws {
        try BrowserImportScene.run { scene in
            let coordinator = start(scene, onboarding: true, source: zen ? scene.zen() : scene.firefox())
            #expect(coordinator.setupPage == .progress && coordinator.setupPagesAhead == [.bookmarks, .passwordFile])
        }
    }

    @Test func setupShowsBookmarksFirstAndHoldsTheOriginalProfileForThePasswordFile() throws {
        try BrowserImportScene.run { scene in
            let coordinator = start(scene, onboarding: true)
            scene.engine.finishBrowser(bookmarks: [bookmark("kept")])
            #expect(coordinator.setupPage == .bookmarks && coordinator.setupPagesAhead == [.passwordFile])
            #expect(coordinator.stage == .bookmarks && coordinator.passwordDestination == scene.destination)
        }
    }

    @Test func firefoxGoesStraightToItsOwnPasswordFileWhileHistoryWaits() throws {
        try BrowserImportScene.run { scene in
            let coordinator = atPasswords(scene)
            #expect(coordinator.stage == .safariPasswords && !coordinator.offersICloudPasswordChoice && !coordinator.wantsICloudPasswords)
            #expect(coordinator.passwordExport == .firefox && coordinator.canImportPasswordFile)
            #expect(coordinator.message == "Import your exported Firefox passwords.")
            #expect(coordinator.hasBackgroundWork && scene.engine.browserCompletions.isEmpty)
        }
    }

    @Test func aWrongFileIsRefusedWithFirefoxsOwnFileName() throws {
        try BrowserImportScene.run { scene in
            let coordinator = atPasswords(scene)
            coordinator.importPasswordFile(URL(fileURLWithPath: "/fixture/passwords.txt"))
            #expect(scene.engine.passwordRequests.isEmpty)
            #expect(coordinator.passwordError == "Choose the passwords.csv file exported by Firefox.")
        }
    }

    @Test func backFromThePasswordFileReturnsToBookmarksAndAcceptingReturnsAgain() throws {
        try BrowserImportScene.run { scene in
            let coordinator = atPasswords(scene)
            coordinator.goBackInSetup()
            #expect(coordinator.stage == .bookmarks)
            coordinator.commitBookmarks()
            #expect(coordinator.stage == .safariPasswords)
        }
    }

    @Test func firefoxsExportGoesToTheOriginalProfileAndThenHistoryStarts() throws {
        try BrowserImportScene.run { scene in
            let coordinator = atPasswords(scene)
            coordinator.importPasswordFile(file)
            let request = scene.engine.passwordRequests.removeFirst()
            #expect(request.url == file && request.path == scene.originalPath)
            request.complete(ImportFixture.password(.completed, imported: 4, canRemove: true))
            #expect(coordinator.canContinueSetupPasswords && coordinator.canRemovePasswordFile)
            coordinator.continueAfterPasswords()
            #expect(coordinator.stage == .finished && scene.engine.browserCompletions.count == 1)
        }
    }

    @Test func withoutBookmarksThePasswordFileIsTheOnlyPageAndBackParksIt() throws {
        try BrowserImportScene.run { scene in
            let coordinator = start(scene, onboarding: true)
            scene.engine.finishBrowser()
            #expect(coordinator.stage == .safariPasswords && coordinator.setupBackReturnsToSource)
            #expect(coordinator.setupPage == .passwordFile && coordinator.setupPagesAhead.isEmpty)
            coordinator.goBackInSetup()
            #expect(coordinator.stage == .profiles && coordinator.parkedStage == .safariPasswords)
            coordinator.continueSourceInline()
            #expect(coordinator.stage == .safariPasswords && coordinator.parkedStage == nil)
        }
    }

    @Test func theMenuImportOffersThePasswordFileAndSkippingReadsNone() throws {
        try BrowserImportScene.run { scene in
            let coordinator = start(scene, onboarding: false)
            scene.engine.finishBrowser()
            #expect(coordinator.stage == .safariPasswords && !coordinator.canChoosePasswordMethod)
            coordinator.continueAfterPasswords()
            #expect(coordinator.stage == .finished && scene.engine.passwordRequests.isEmpty)
        }
    }

    @Test func theMenuImportAsksForThePasswordFileBeforeBookmarks() throws {
        try BrowserImportScene.run { scene in
            let coordinator = start(scene, onboarding: false)
            scene.engine.finishBrowser(bookmarks: [bookmark("menu")])
            #expect(coordinator.stage == .safariPasswords)
            coordinator.continueAfterPasswords()
            #expect(coordinator.stage == .bookmarks)
        }
    }

    @Test func lockedFirefoxFilesStillOfferThePasswordFileAfterTheAccessPage() throws {
        try BrowserImportScene.run { scene in
            let unreadable = ImportFixture.profiles([ImportFixture.profile("locked", [], .restricted)], .restricted)
            let coordinator = scene.chosen(scene.firefox(), profiles: unreadable, onboarding: true, iCloud: true)
            coordinator.continueSourceInline()
            #expect(coordinator.stage == .safariAccess)
            coordinator.continueSafariWithoutRestarting()
            scene.engine.profiles.removeFirst().complete(unreadable)
            #expect(coordinator.stage == .safariPasswords && coordinator.passwordDestination == scene.destination)
            #expect(!coordinator.offersICloudPasswordChoice)
            coordinator.goBackInSetup()
            #expect(coordinator.stage == .safariAccess)
        }
    }

    @Test func chromesHistoryKeepsImportingBehindItsParkedBookmarks() throws {
        try BrowserImportScene.run { scene in
            let earlier = start(scene, onboarding: true, source: try scene.chrome())
            #expect(earlier.setupPagesAhead == [.bookmarks])
            scene.engine.finishBrowser(bookmarks: [bookmark("chrome")])
            #expect(earlier.stage == .bookmarks && earlier.hasBackgroundWork && scene.engine.browserCompletions.count == 1)
            #expect(earlier.returnToSourceInSetup() && earlier.parkedStage == .bookmarks)
        }
    }

    @Test func firefoxWaitsForChromeAndThenStartsWithThePagesItCounted() throws {
        try BrowserImportScene.run { scene in
            let (earlier, switched) = try waitingOnChrome(scene)
            #expect(switched.stage == .importing && switched.message == "Finishing your last import…")
            #expect(scene.engine.browserCompletions.count == 1)
            #expect(switched.setupPage == .progress && switched.setupPagesAhead == [.bookmarks, .passwordFile])
            scene.engine.finishBrowser()
            #expect(!earlier.hasBackgroundWork && switched.stage == .importing && switched.message != "Finishing your last import…")
            #expect(scene.engine.browserCompletions.count == 1)
            #expect(switched.setupPage == .progress && switched.setupPagesAhead == [.bookmarks, .passwordFile])
            scene.engine.finishBrowser(bookmarks: [bookmark("switched")])
            #expect(switched.setupPage == .bookmarks && switched.setupPagesAhead == [.passwordFile])
        }
    }

    @Test func aStoppedWaitingImportDropsItsPagesAndNeverStarts() throws {
        try BrowserImportScene.run { scene in
            let (earlier, stopped) = try waitingOnChrome(scene)
            stopped.stopImport()
            #expect(stopped.stage == .finished && stopped.setupPage == nil && stopped.setupPagesAhead.isEmpty)
            scene.engine.finishBrowser()
            #expect(!earlier.hasBackgroundWork && stopped.stage == .finished && scene.engine.browserCompletions.isEmpty)
        }
    }
}
