import Foundation
import Testing
@testable import ParcCore

@MainActor
struct OnboardingDraftTests {
    typealias Stage = OnboardingDraft.Stage

    @Test func freshSetupPreservesTheOriginalTwoInitiallySelectedAppsAndOrder() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        let draft = try fixture.loadDraft()
        #expect(draft.selectedFavorites.map(\.url) == ["https://youtube.com", "https://calendar.google.com"])
    }

    @Test func theSetupGridIsTheNineItemSubsetNotAllTopApps() {
        #expect(OnboardingDraft.favoriteChoices.map(\.id) ==
            ["twitter", "gmail", "gcal", "spotify", "youtube", "notion", "slack", "figma", "outlook"])
    }

    @Test func theStageAndPendingImportedValuesResumeExactly() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        let draft = try fixture.pendingDraft()
        try draft.save(directory: fixture.root)
        let resumed = try fixture.loadDraft()
        #expect(resumed == draft)
        #expect(resumed.iCloudPasswordsProfileID == fixture.store.activeSpace.profileID)
    }

    @Test func aDraftNeverCommitsSetupOrOpensTabs() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        try fixture.pendingDraft().save(directory: fixture.root)
        #expect(!fixture.store.state.settings.onboardingComplete)
        #expect(fixture.store.state.tabs.isEmpty)
    }

    @Test func oldIntroductionDraftsResumeAtRealImportSetupWithoutChangingSystemDefaults() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        try fixture.pendingDraft().save(directory: fixture.root)
        try fixture.rewriteDraft {
            for key in ["defaultBrowserChoice", "iCloudPasswordsProfileID", "favoriteOrder", "importedAdBlockers", "adBlockerChoice"] {
                $0.removeValue(forKey: key)
            }
            $0["stage"] = 3
        }
        let migrated = try fixture.loadDraft()
        #expect(migrated.stage == .bookmarks && migrated.wantsDefaultBrowser)
        #expect(migrated.iCloudPasswordsProfileID == nil)
        #expect(migrated.selectedFavorites.map(\.url) == [OnboardingDraft.favoriteChoices[0].url])
    }

    @Test func existingThemeDraftsDoNotDecodeAsAnotherScreen() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        try fixture.pendingDraft().save(directory: fixture.root)
        try fixture.rewriteDraft { $0["stage"] = 4 }
        #expect(try fixture.loadDraft().stage == .theme)
    }

    @Test func anExplicitNoToDefaultBrowserSurvivesRestartWithoutBlockingSetup() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        var draft = try fixture.pendingDraft()
        draft.stage = .defaultBrowser
        draft.defaultBrowserChoice = false
        try draft.save(directory: fixture.root)
        let optedOut = try fixture.loadDraft()
        #expect(!optedOut.wantsDefaultBrowser)
        #expect(optedOut.stage.next == .ready)
    }

    @Test func setupNavigationDoesNotUsePersistedIntegerArithmeticOrReplayTheWelcomeOnBack() {
        #expect(Stage.sellCompleted.next == .bookmarks)
        #expect(Stage.bookmarks.previous == nil)
        #expect(Stage.favorites.previous == .bookmarks)
        #expect(Stage.theme.next == .windowFrame)
        #expect(Stage.windowFrame.next == .defaultBrowser)
        #expect(Stage.windowFrame.previous == .theme)
        #expect(Stage.defaultBrowser.previous == .windowFrame)
        #expect(Stage.ready.next == nil)
    }

    @Test func theFrameStepFollowsThemeAndAdBlockersSitBetweenItAndDefaultBrowser() {
        #expect(Stage.setupOrder == [.bookmarks, .favorites, .theme, .windowFrame, .defaultBrowser, .ready])
        #expect(Stage.setupOrder(includingAdBlockers: true) ==
            [.bookmarks, .favorites, .theme, .windowFrame, .adBlockers, .defaultBrowser, .ready])
    }

    @Test func theFrameStepAppendsANewPersistedTagWithoutRenumberingSavedDrafts() {
        #expect(Stage.adBlockers.rawValue == 9)
        #expect(Stage.windowFrame.rawValue == 10)
        #expect(Stage.theme.rawValue == 4)
        #expect(Stage.defaultBrowser.rawValue == 8)
        #expect(!Stage.windowFrame.isWelcome)
    }

    @Test func themeContinuesToTheFrameStepWhichStartsFromTheSavedThickness() {
        var framed = PresentationOnboardingFixture.draft(stage: .theme)
        #expect(framed.nextStage() == .windowFrame)
        #expect(framed.windowFrameThickness == nil)
        #expect(framed.windowFrameValue(saved: 10) == 10)
        #expect(framed.windowFrameValue(saved: 6) == 6)
        framed.stage = .windowFrame
        framed.importedAdBlockers = [.init(identifier: OnboardingAdBlocker.uBlockOrigin, displayName: "uBlock Origin")]
        #expect(framed.nextStage() == .defaultBrowser)
        #expect(framed.previousStage() == .theme)
        #expect(framed.visibleSetupOrder().firstIndex(of: .windowFrame) == 3)
        #expect(framed.displayedSetupCount() == 5)
    }

    @Test func theAdBlockerStepFollowsTheFrameStepWhenShown() {
        var framed = PresentationOnboardingFixture.draft(stage: .windowFrame)
        framed.importedAdBlockers = []
        #expect(framed.nextStage() == .adBlockers)
    }

    @Test func aChosenThicknessAndTheFrameStageResumeAfterRestart() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        var framed = try fixture.pendingDraft()
        framed.stage = .windowFrame
        framed.chooseWindowFrame(4)
        try framed.save(directory: fixture.root)
        let resumed = try fixture.loadDraft()
        #expect(resumed.stage == .windowFrame)
        #expect(resumed.windowFrameThickness == 4)
        #expect(resumed.windowFrameValue(saved: 10) == 4)
    }

    @Test func aChosenThicknessStaysInsideTheRange() {
        var framed = PresentationOnboardingFixture.draft(stage: .windowFrame)
        framed.chooseWindowFrame(40)
        #expect(framed.windowFrameThickness == 13)
    }

    @Test func skipKeepsWhateverThicknessIsAlreadySaved() {
        var framed = PresentationOnboardingFixture.draft(stage: .windowFrame)
        framed.chooseWindowFrame(40)
        framed.skipWindowFrame()
        #expect(framed.windowFrameThickness == nil)
        #expect(framed.windowFrameValue(saved: 7) == 7)
    }

    @Test func anOutOfRangeSavedThicknessIsDroppedRatherThanApplied() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        var framed = try fixture.pendingDraft()
        framed.stage = .windowFrame
        framed.chooseWindowFrame(4)
        try framed.save(directory: fixture.root)
        try fixture.rewriteDraft { $0["windowFrameThickness"] = 99 }
        #expect(try fixture.loadDraft().windowFrameThickness == nil)
    }

    @Test func draftsSavedBeforeTheFrameStepDecodeWithoutAChosenThickness() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        var framed = try fixture.pendingDraft()
        framed.stage = .windowFrame
        framed.chooseWindowFrame(4)
        try framed.save(directory: fixture.root)
        try fixture.rewriteDraft { $0.removeValue(forKey: "windowFrameThickness") }
        let older = try fixture.loadDraft()
        #expect(older.windowFrameThickness == nil)
        #expect(older.stage == .windowFrame)
    }

    @Test func completingSetupCommitsTheSelectionAndRejectsDuplicateAndInvalidImports() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        var draft = try fixture.pendingDraft()
        let profiles = fixture.store.state.profiles
        draft.stage = .ready
        try fixture.store.completeOnboarding(draft)
        let committed = fixture.store.state
        #expect(committed.settings.onboardingComplete)
        #expect(fixture.store.activeSpace.name == "Personal")
        #expect(fixture.store.favorites.count == 1)
        #expect(fixture.store.pinnedTabs.count == 1)
        #expect(committed.profiles == profiles)
    }

    @Test func retryingCompletionDoesNotDuplicateSetup() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        var draft = try fixture.pendingDraft()
        draft.stage = .ready
        try fixture.store.completeOnboarding(draft)
        let committed = fixture.store.state
        try fixture.store.completeOnboarding(draft)
        #expect(fixture.store.state == committed)
    }

    @Test func completionAndTheSelectedSetupPersistTogether() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        var draft = try fixture.pendingDraft()
        let profiles = fixture.store.state.profiles
        draft.stage = .ready
        try fixture.store.completeOnboarding(draft)
        let reopened = try BrowserStore(directory: fixture.root)
        #expect(reopened.state.settings.onboardingComplete)
        #expect(reopened.activeSpace.name == "Personal")
        #expect(reopened.favorites.count == 1)
        #expect(reopened.pinnedTabs.count == 1)
        #expect(reopened.state.profiles == profiles)
    }

    @Test func aFailedAtomicWriteRollsBackAllSetup() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        let failureRoot = fixture.subdirectory("write-failure")
        let store = try BrowserStore(directory: failureRoot)
        var failing = try OnboardingDraft.load(directory: failureRoot, space: store.activeSpace)
        failing.spaceName = "Must not commit"
        failing.favoriteURLs = [OnboardingDraft.favoriteChoices[1].url]
        let previous = store.state
        try FileManager.default.createDirectory(at: failureRoot.appendingPathComponent("session.json"),
                                                withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try store.completeOnboarding(failing) }
        #expect(store.state == previous)
    }
}
