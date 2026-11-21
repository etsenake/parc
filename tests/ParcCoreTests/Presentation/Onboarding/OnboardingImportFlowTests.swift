import Foundation
import Testing
@testable import ParcCore

struct OnboardingImportFlowTests {
    typealias Stage = OnboardingDraft.Stage

    @Test func theContinuedImportAppendsANewPersistedTagWithoutRenumberingSavedDrafts() {
        #expect(Stage.continuedImport.rawValue == 11)
        #expect(!Stage.continuedImport.isWelcome)
        #expect(Stage.theme.rawValue == 4 && Stage.favorites.rawValue == 5 && Stage.bookmarks.rawValue == 6)
    }

    @Test func favoritesFollowsTheBrowserChoiceAndTheRestOfARunningImportFollowsFavorites() {
        #expect(Stage.setupOrder(includingAdBlockers: false, continuingImport: true)
            == [.bookmarks, .favorites, .continuedImport, .theme, .windowFrame, .defaultBrowser, .ready])
        #expect(Stage.setupOrder == [.bookmarks, .favorites, .theme, .windowFrame, .defaultBrowser, .ready])
    }

    @Test func choosingABrowserIsTheFirstCountedStepAndLeadsStraightToFavorites() {
        let draft = PresentationOnboardingFixture.draft(stage: .bookmarks)
        #expect(draft.nextStage() == .favorites)
        #expect(draft.nextStage(continuingImport: true) == .favorites)
        #expect(draft.previousStage() == nil)
        #expect(draft.displayedStepNumber() == 1)
        #expect(draft.displayedSetupCount() == 6)
    }

    @Test func favoritesGoesOnToARunningImportsPagesOrStraightToThemeOnceNothingIsLeft() {
        let draft = PresentationOnboardingFixture.draft(stage: .favorites)
        #expect(draft.nextStage(continuingImport: true) == .continuedImport)
        #expect(draft.nextStage() == .theme)
        #expect(draft.previousStage() == .bookmarks)
        #expect(draft.displayedStepNumber() == 2)
    }

    @Test func theImportsRemainingPagesSitBetweenFavoritesAndThemeEachWithANumberOfItsOwn() {
        var draft = PresentationOnboardingFixture.draft(stage: .continuedImport)
        draft.recordImportPage(.bookmarks)
        #expect(draft.nextStage() == .theme)
        #expect(draft.nextStage(continuingImport: true) == .theme)
        #expect(draft.previousStage() == .favorites)
        #expect(draft.displayedStepNumber() == 3)
        #expect(draft.displayedSetupCount() == 7)
        #expect(draft.visibleSetupOrder().firstIndex(of: .continuedImport) == 2)
    }

    @Test func withoutTheAdBlockerStepTheImportsPagesKeepTheirNumbersInASmallerTotal() {
        var draft = PresentationOnboardingFixture.draft(stage: .continuedImport)
        draft.recordImportPage(.bookmarks)
        draft.importedAdBlockers = [.init(identifier: OnboardingAdBlocker.uBlockOrigin, displayName: "uBlock Origin")]
        #expect(draft.displayedStepNumber() == 3)
        #expect(draft.displayedSetupCount() == 6)
    }

    @Test func onceTheImportIsDoneThemeFollowsItsPagesAndBackReturnsToFavorites() {
        var draft = PresentationOnboardingFixture.draft(stage: .continuedImport)
        draft.recordImportPage(.bookmarks)
        draft.stage = .theme
        #expect(draft.previousStage() == .favorites)
        #expect(draft.displayedStepNumber() == 4)
    }

    @Test(arguments: [(Stage.bookmarks, Stage.favorites, OnboardingExperience.TransitionDirection.forward),
                      (.favorites, .bookmarks, .back), (.favorites, .continuedImport, .forward),
                      (.continuedImport, .favorites, .back), (.continuedImport, .theme, .forward),
                      (.theme, .favorites, .back)])
    func importNavigationSlidesInTheDirectionOfTheStageOrder(move: (Stage, Stage, OnboardingExperience.TransitionDirection)) {
        #expect(OnboardingExperience.direction(from: move.0, to: move.1) == move.2)
    }

    @Test func leavingFavoritesWhileAnImportStillHasPagesResumesAtTheImportNotPastIt() {
        let draft = PresentationOnboardingFixture.draft(stage: .favorites)
        #expect(draft.savedForResume(importInProgress: true).stage == .bookmarks)
        #expect(draft.savedForResume(importInProgress: false).stage == .favorites)
    }

    @Test func theImportsRemainingPagesAlwaysResumeFromTheImport() {
        let draft = PresentationOnboardingFixture.draft(stage: .continuedImport)
        #expect(draft.savedForResume(importInProgress: false).stage == .bookmarks)
    }

    @Test func laterStepsResumeWhereTheyWere() {
        let draft = PresentationOnboardingFixture.draft(stage: .theme)
        #expect(draft.savedForResume(importInProgress: true).stage == .theme)
    }

    @Test @MainActor func aSavedContinuedImportStageReopensAtTheImport() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        var draft = try fixture.loadDraft()
        draft.stage = .continuedImport
        try draft.save(directory: fixture.root)
        #expect(try fixture.loadDraft().stage == .bookmarks)
    }

    @Test func startingTheImportMovesOnToFavoritesAtOnceEvenWhenItFinishesReadingStraightAway() {
        let change = OnboardingExperience.importChange
        #expect(change(.bookmarks, false, false, false) == .show)
        #expect(change(.bookmarks, true, false, false) == .showFavorites)
        #expect(change(.bookmarks, true, false, true) == .showFavorites)
    }

    @Test func afterBackFromFavoritesTheBrowserChoiceStaysPutAndFinishedResultsWaitBehindIt() {
        let change = OnboardingExperience.importChange
        #expect(change(.bookmarks, true, true, false) == .showInPlace)
        #expect(change(.bookmarks, true, true, true) == .returnToSource)
    }

    @Test func theImportRunsOutOfSightDuringFavoritesAndShowsItsPagesAgainAfterwards() {
        let change = OnboardingExperience.importChange
        #expect(change(.favorites, true, true, true) == .hold)
        #expect(change(.favorites, true, false, false) == .hold)
        #expect(change(.continuedImport, true, true, true) == .show)
        #expect(change(.theme, false, true, false) == .hold)
    }

    @Test func backFollowsTheNewOrder() {
        let back = OnboardingExperience.importBack
        #expect(back(.bookmarks, true, true) == .importPage)
        #expect(back(.favorites, true, true) == .importSource)
        #expect(back(.continuedImport, true, true) == .favorites)
        #expect(back(.continuedImport, true, false) == .importPage)
    }

    @Test func withoutARunningImportBackUsesTheOrdinaryStepOrder() {
        let back = OnboardingExperience.importBack
        #expect(back(.favorites, false, true) == .previousStage)
        #expect(back(.theme, false, true) == .previousStage)
    }

    @Test func nextOnTheBrowserChoiceStartsTheImportReturnsToFavoritesOnceStartedOrSkipsTheImport() {
        let next = OnboardingExperience.importNext
        #expect(next(.bookmarks, true, false, false) == .importPage)
        #expect(next(.bookmarks, true, true, false) == .favorites)
        #expect(next(.bookmarks, true, true, true) == .importPage)
    }

    @Test func theImportsOwnPagesKeepTheirNextAndFavoritesAlwaysUsesTheStepOrder() {
        let next = OnboardingExperience.importNext
        #expect(next(.continuedImport, true, true, false) == .importPage)
        #expect(next(.favorites, true, true, false) == .nextStage)
        #expect(next(.bookmarks, false, false, false) == .nextStage)
    }
}
