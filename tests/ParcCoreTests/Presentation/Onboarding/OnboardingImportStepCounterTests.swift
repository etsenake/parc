import Foundation
import Testing
@testable import ParcCore

struct OnboardingImportStepCounterTests {
    typealias Stage = OnboardingDraft.Stage
    typealias Page = OnboardingDraft.ImportPage

    func fresh() -> OnboardingDraft {
        OnboardingDraft(spaceID: UUID(), spaceName: "Setup", theme: SpaceTheme())
    }

    private func show(_ draft: inout OnboardingDraft, _ stage: Stage, _ current: Page? = nil, ahead: [Page] = [],
              started: Bool = true) -> String {
        draft.stage = stage
        if stage == .continuedImport, let current { draft.recordImportPage(current) }
        let steps = stage == .bookmarks && !started ? 0 : draft.importSteps(current: current, ahead: ahead)
        return "\(draft.displayedStepNumber(importSteps: steps)) of \(draft.displayedSetupCount(importSteps: steps))"
    }

    private func walk(_ draft: inout OnboardingDraft) -> [String] {
        [Stage.theme, .windowFrame, .adBlockers, .defaultBrowser].map { show(&draft, $0) }
    }

    @Test func noBrowserFoundOrASkippedImportCountsOnlyTheStepsEveryoneSees() {
        var skipped = fresh()
        #expect(show(&skipped, .bookmarks, started: false) == "1 of 6")
        #expect(show(&skipped, .favorites) == "2 of 6")
        #expect(walk(&skipped) == ["3 of 6", "4 of 6", "5 of 6", "6 of 6"])
    }

    @Test func onceAChromiumImportStartsFavoritesCountsTheBookmarksPageItIsReading() {
        var chrome = fresh()
        #expect(show(&chrome, .bookmarks, started: false) == "1 of 6")
        #expect(show(&chrome, .favorites, .progress, ahead: [.bookmarks]) == "2 of 7")
    }

    @Test func theBookmarksPageTakesTheNextNumberAndEveryLaterStepMovesAlongByOne() {
        var chrome = fresh()
        _ = show(&chrome, .favorites, .progress, ahead: [.bookmarks])
        #expect(show(&chrome, .continuedImport, .bookmarks) == "3 of 7")
        #expect(walk(&chrome) == ["4 of 7", "5 of 7", "6 of 7", "7 of 7"])
    }

    @Test func backFromThemeToFavoritesKeepsTheTotalAndThemeKeepsItsNumberGoingForward() {
        var chrome = fresh()
        _ = show(&chrome, .favorites, .progress, ahead: [.bookmarks])
        _ = show(&chrome, .continuedImport, .bookmarks)
        _ = walk(&chrome)
        #expect(show(&chrome, .favorites) == "2 of 7")
        #expect(show(&chrome, .theme) == "4 of 7")
    }

    @Test func anImportStillReadingAfterFavoritesShowsItsProgressPageAsAStepOfItsOwn() {
        var slow = fresh()
        #expect(show(&slow, .favorites, .progress, ahead: [.bookmarks]) == "2 of 7")
        #expect(show(&slow, .continuedImport, .progress, ahead: [.bookmarks]) == "3 of 8")
        #expect(show(&slow, .continuedImport, .bookmarks) == "4 of 8")
        #expect(show(&slow, .theme) == "5 of 8")
    }

    @Test func backFromBookmarksToFavoritesKeepsTheProgressPageCountedAndBookmarksKeepsItsNumber() {
        var slow = fresh()
        _ = show(&slow, .favorites, .progress, ahead: [.bookmarks])
        _ = show(&slow, .continuedImport, .progress, ahead: [.bookmarks])
        _ = show(&slow, .continuedImport, .bookmarks)
        _ = show(&slow, .theme)
        #expect(show(&slow, .favorites, .bookmarks) == "2 of 8")
        #expect(show(&slow, .continuedImport, .bookmarks) == "4 of 8")
    }

    @Test func backFromTheProgressPageKeepsItsStepAndTheFinishedReadingsBookmarksComeAfterIt() {
        var reading = fresh()
        _ = show(&reading, .continuedImport, .progress, ahead: [.bookmarks, .passwordFile])
        #expect(show(&reading, .favorites, .bookmarks, ahead: [.passwordFile]) == "2 of 9")
        #expect(show(&reading, .continuedImport, .bookmarks, ahead: [.passwordFile]) == "4 of 9")
    }

    @Test func safariCountsItsBookmarksAndItsPasswordChoiceWhichStartsOnTheExtension() {
        var safari = fresh()
        #expect(show(&safari, .favorites, .progress, ahead: [.bookmarks, .passwordChoice]) == "2 of 8")
        #expect(show(&safari, .continuedImport, .bookmarks, ahead: [.passwordChoice]) == "3 of 8")
        #expect(show(&safari, .continuedImport, .passwordChoice) == "4 of 8")
    }

    func safariAtThePasswordChoice() -> OnboardingDraft {
        var safari = fresh()
        _ = show(&safari, .favorites, .progress, ahead: [.bookmarks, .passwordChoice])
        _ = show(&safari, .continuedImport, .bookmarks, ahead: [.passwordChoice])
        _ = show(&safari, .continuedImport, .passwordChoice)
        return safari
    }

    @Test func choosingManualImportAddsTheFilePageAndBackKeepsItCountedWhileItIsStillComing() {
        var safari = safariAtThePasswordChoice()
        #expect(show(&safari, .continuedImport, .passwordFile) == "5 of 9")
        #expect(show(&safari, .continuedImport, .passwordChoice, ahead: [.passwordFile]) == "4 of 9")
        #expect(show(&safari, .continuedImport, .bookmarks, ahead: [.passwordChoice, .passwordFile]) == "3 of 9")
    }

    @Test func choosingTheExtensionAfterAllDropsTheFilePageBackedOutOfOnceSetupMovesOn() {
        var safari = safariAtThePasswordChoice()
        _ = show(&safari, .continuedImport, .passwordFile)
        #expect(show(&safari, .continuedImport, .passwordChoice, ahead: [.passwordFile]) == "4 of 9")
        #expect(safari.importPages == [.bookmarks, .passwordChoice])
        #expect(show(&safari, .theme) == "5 of 8")
    }

    @Test func firefoxAndZenCountBookmarksAndTheirPasswordFile() {
        var firefox = fresh()
        #expect(show(&firefox, .favorites, .progress, ahead: [.bookmarks, .passwordFile]) == "2 of 8")
        #expect(show(&firefox, .continuedImport, .bookmarks, ahead: [.passwordFile]) == "3 of 8")
        #expect(show(&firefox, .continuedImport, .passwordFile) == "4 of 8")
        #expect(show(&firefox, .theme) == "5 of 8")
    }

    @Test func withNoBookmarksFoundTheTotalLosesThatPageAsThePasswordFileAppears() {
        var empty = fresh()
        #expect(show(&empty, .favorites, .progress, ahead: [.bookmarks, .passwordFile]) == "2 of 8")
        #expect(show(&empty, .continuedImport, .passwordFile) == "3 of 7")
        #expect(show(&empty, .theme) == "4 of 7")
    }

    @Test func anImportThatFinishedWithNothingLeftDuringFavoritesLeavesOnlyTheUsualSteps() {
        var finished = fresh()
        #expect(show(&finished, .favorites, .progress, ahead: [.bookmarks]) == "2 of 7")
        #expect(show(&finished, .theme) == "3 of 6")
    }

    @Test func anImportThatFailsOnItsProgressPageKeepsThatPageAndMovesOnToTheme() {
        var failed = fresh()
        #expect(show(&failed, .continuedImport, .progress, ahead: [.bookmarks, .passwordFile]) == "3 of 9")
        #expect(show(&failed, .theme) == "4 of 7")
    }

    @Test func stopImportDropsThePasswordPageAndKeepsTheBookmarksAlreadyRead() {
        var stopped = fresh()
        #expect(show(&stopped, .continuedImport, .progress, ahead: [.bookmarks, .passwordFile]) == "3 of 9")
        #expect(show(&stopped, .continuedImport, .bookmarks) == "4 of 8")
    }

    @Test func safarisExportFileCountsItsBookmarksThenAProgressPageIfItsPasswordsAreStillGoingIn() {
        var export = fresh()
        #expect(show(&export, .favorites, .bookmarks) == "2 of 7")
        #expect(show(&export, .continuedImport, .bookmarks) == "3 of 7")
        #expect(show(&export, .continuedImport, .progress) == "4 of 8")
        #expect(show(&export, .theme) == "5 of 8")
    }

    @Test func anExportWithOnlyPasswordsCountsAProgressPageOnlyOnceItShows() {
        var exportBusy = fresh()
        #expect(show(&exportBusy, .favorites, .progress) == "2 of 6")
        #expect(show(&exportBusy, .continuedImport, .progress) == "3 of 7")
        #expect(show(&exportBusy, .theme) == "4 of 7")
    }

    @Test func safarisDoThisLaterCountsItsWaitingPasswordPageWhichBackToTheAccessPagePutsAway() {
        var later = fresh()
        #expect(show(&later, .favorites, .passwordFile) == "2 of 7")
        #expect(show(&later, .bookmarks, started: false) == "1 of 6")
    }

    @Test func puttingAccessOffAgainBringsThePasswordPageBackIntoTheCount() {
        var later = fresh()
        _ = show(&later, .favorites, .passwordFile)
        _ = show(&later, .bookmarks, started: false)
        #expect(show(&later, .favorites, .passwordFile) == "2 of 7")
        #expect(show(&later, .continuedImport, .passwordFile) == "3 of 7")
        #expect(show(&later, .theme) == "4 of 7")
    }

    @Test func aPageShownAgainInPlaceIsNotCountedTwiceButASecondProgressPageLaterOnIs() {
        var pages = fresh()
        pages.recordImportPage(.progress); pages.recordImportPage(.progress); pages.recordImportPage(.bookmarks)
        pages.recordImportPage(.progress)
        #expect(pages.importPages == [.progress, .bookmarks, .progress])
    }

    @Test func goingBackToAPageCutsOffThePagesAfterIt() {
        var pages = fresh()
        pages.importPages = [.bookmarks, .passwordChoice, .passwordFile]
        pages.recordImportPage(.bookmarks)
        #expect(pages.importPages == [.bookmarks])
    }

    @Test func awayFromTheImportsPagesAWaitingPageCountsUnlessItIsAnUnshownProgressPageOrAlreadyCounted() {
        var pages = fresh()
        pages.importPages = [.bookmarks]
        #expect(pages.importSteps(current: .progress, ahead: []) == 1)
        #expect(pages.importSteps(current: .bookmarks, ahead: [.passwordFile]) == 2)
        #expect(pages.importSteps(current: .passwordChoice, ahead: [.passwordFile]) == 3)
    }

    @Test func favoritesAndLaterStepsHoldTheirCounterWhileTheImportMovesOnOutOfSight() {
        let page = OnboardingExperience.CounterPage.init
        #expect(page(.favorites, .progress, true) == page(.favorites, .bookmarks, false))
        #expect(page(.theme, nil, false) == page(.theme, .bookmarks, true))
    }

    @Test func theCounterSettlesAgainWhenAnImportPageChangesOrAnotherBrowserDiscardsTheImport() {
        let page = OnboardingExperience.CounterPage.init
        #expect(page(.continuedImport, .progress, true) != page(.continuedImport, .bookmarks, true))
        #expect(page(.bookmarks, .progress, true) != page(.bookmarks, .progress, false))
        #expect(page(.bookmarks, .progress, true) == page(.bookmarks, .bookmarks, true))
    }

    @MainActor func resumedAfterTheImport(_ fixture: PresentationOnboardingFixture) throws -> OnboardingDraft {
        var resumed = try fixture.loadDraft()
        _ = show(&resumed, .favorites, .progress, ahead: [.bookmarks])
        _ = show(&resumed, .continuedImport, .bookmarks)
        resumed.stage = .theme
        return resumed
    }

    @Test @MainActor func aSetupResumedAfterTheImportKeepsItsPagesInTheCount() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        let resumed = try resumedAfterTheImport(fixture)
        try resumed.save(directory: fixture.root)
        var reopened = try fixture.loadDraft()
        #expect(reopened.importPages == [.bookmarks])
        #expect(show(&reopened, .theme) == "4 of 7")
    }

    @Test @MainActor func aSetupResumedAtTheImportStartsItsCountAfresh() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        var resumed = try resumedAfterTheImport(fixture)
        resumed.stage = .continuedImport
        let atImport = resumed.savedForResume(importInProgress: true)
        #expect(atImport.stage == .bookmarks)
        #expect(atImport.importPages.isEmpty)
    }

    @Test @MainActor func draftsWithoutImportPagesSaveNothingNew() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        var resumed = try resumedAfterTheImport(fixture)
        resumed.stage = .continuedImport
        try resumed.savedForResume(importInProgress: true).save(directory: fixture.root)
        let json = try String(contentsOf: fixture.draftFile, encoding: .utf8)
        #expect(!json.contains("importPages"))
    }

    @Test @MainActor func aSavedDraftAtTheBrowserChoiceNeverCarriesAnOldImportsPages() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        try fixture.loadDraft().save(directory: fixture.root)
        try fixture.rewriteDraft {
            $0["stage"] = Stage.bookmarks.rawValue
            $0["importPages"] = ["bookmarks"]
        }
        #expect(try fixture.loadDraft().importPages.isEmpty)
    }

    @Test @MainActor func aPageNameFromANewerParcIsLeftOutRatherThanBreakingTheDraft() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        try fixture.loadDraft().save(directory: fixture.root)
        try fixture.rewriteDraft {
            $0["stage"] = Stage.theme.rawValue
            $0["importPages"] = ["bookmarks", "somethingNewer"]
        }
        #expect(try fixture.loadDraft().importPages == [.bookmarks])
    }

    @Test @MainActor func anImpossibleNumberOfImportPagesIsADamagedDraft() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        try fixture.loadDraft().save(directory: fixture.root)
        try fixture.rewriteDraft {
            $0["stage"] = Stage.theme.rawValue
            $0["importPages"] = Array(repeating: "progress", count: 9)
        }
        #expect((try? fixture.loadDraft()) == nil)
    }

    @Test @MainActor func replaysAccessRestartBeginsTheImportsCountAfreshToo() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        var resumed = try resumedAfterTheImport(fixture)
        resumed.stage = .theme
        try resumed.save(directory: fixture.root, fileName: OnboardingDraft.replayRestartFileName)
        let replay = OnboardingDraft.takeReplayRestart(directory: fixture.root, space: fixture.store.activeSpace)
        #expect(replay?.stage == .bookmarks)
        #expect(replay?.importPages.isEmpty == true)
    }

    @Test func leavingOutTheAdBlockerStepKeepsTheImportsPagesCounted() {
        var uBlock = fresh()
        _ = show(&uBlock, .continuedImport, .bookmarks)
        uBlock.importedAdBlockers = [.init(identifier: OnboardingAdBlocker.uBlockOrigin, displayName: "uBlock Origin")]
        #expect(show(&uBlock, .theme) == "4 of 6")
        #expect(show(&uBlock, .defaultBrowser) == "6 of 6")
    }
}
