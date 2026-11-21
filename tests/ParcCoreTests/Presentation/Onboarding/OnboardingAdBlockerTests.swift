import Foundation
import Testing
@testable import ParcCore

struct OnboardingAdBlockerTests {
    typealias Choice = OnboardingDraft.AdBlockerChoice
    typealias Stage = OnboardingDraft.Stage

    let ublock = OnboardingDraft.ImportedAdBlocker(identifier: "cjpalhdlnbpafiamejdnhcphjbkeiagm", displayName: "uBlock Origin")
    let setupProfile = UUID()
    let sideProfile = UUID()

    var adGuard: OnboardingDraft.ImportedAdBlocker {
        .init(identifier: "bgnkhhnnamicmpeenaelnjfhikgbkllg", displayName: "AdGuard AdBlocker",
              profileIDs: [setupProfile, sideProfile])
    }

    @MainActor func saved(_ fixture: PresentationOnboardingFixture, stage: Stage = .windowFrame,
               _ change: (inout OnboardingDraft) -> Void) throws -> OnboardingDraft {
        var draft = try fixture.pendingDraft()
        draft.stage = stage
        change(&draft)
        try draft.save(directory: fixture.root)
        return try fixture.loadDraft()
    }

    @Test func withNoAdBlockerImportedTheYesNoStepIsIncluded() {
        let blocked = PresentationOnboardingFixture.draft(stage: .windowFrame)
        #expect(blocked.nextStage() == .adBlockers)
        #expect(blocked.displayedSetupCount() == 6)
    }

    @Test func uBlockOriginAloneIsTheDefaultChoiceSoTheStepIsOmitted() {
        var blocked = PresentationOnboardingFixture.draft(stage: .windowFrame)
        blocked.importedAdBlockers = [ublock]
        #expect(blocked.nextStage() == .defaultBrowser)
        #expect(!blocked.visibleSetupOrder().contains(.adBlockers))
        #expect(blocked.displayedSetupCount() == 5)
    }

    @Test func anyOtherImportedBlockerContinuesIntoTheSetupStep() {
        var blocked = PresentationOnboardingFixture.draft(stage: .windowFrame)
        blocked.importedAdBlockers = [ublock, adGuard]
        blocked.adBlockerChoice = .keep(ublock.identifier)
        #expect(blocked.nextStage() == .adBlockers)
        #expect(blocked.visibleSetupOrder().contains(.adBlockers))
    }

    @Test func adBlockerSetupContinuesToDefaultBrowserAndReturnsToTheFrameStep() {
        var blocked = PresentationOnboardingFixture.draft(stage: .adBlockers)
        blocked.importedAdBlockers = [ublock, adGuard]
        #expect(blocked.nextStage() == .defaultBrowser)
        #expect(blocked.previousStage() == .windowFrame)
    }

    @Test func backFromDefaultBrowserReturnsToAdBlockersWhileTheyRemainIncluded() {
        var blocked = PresentationOnboardingFixture.draft(stage: .defaultBrowser)
        blocked.importedAdBlockers = [ublock, adGuard]
        #expect(blocked.previousStage() == .adBlockers)
    }

    @Test func aBlockerSetOfOnlyUBlockOriginOmitsTheStepWithoutChangingTheRemainingOrder() {
        var blocked = PresentationOnboardingFixture.draft(stage: .defaultBrowser)
        blocked.importedAdBlockers = [ublock]
        #expect(blocked.previousStage() == .windowFrame)
        #expect(!blocked.visibleSetupOrder().contains(.adBlockers))
    }

    @Test func theCurrentAdBlockerStepIsRetainedUntilNextOrBackLeavesIt() {
        var blocked = PresentationOnboardingFixture.draft(stage: .adBlockers)
        blocked.importedAdBlockers = [ublock]
        #expect(blocked.visibleSetupOrder().contains(.adBlockers))
        #expect(blocked.nextStage() == .defaultBrowser)
    }

    @Test @MainActor func importedBlockersTheirProfilesAndThePendingKeepChoiceResume() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        let resumed = try saved(fixture) {
            $0.importedAdBlockers = [ublock, adGuard]
            $0.adBlockerChoice = .keep(ublock.identifier)
        }
        #expect(resumed.importedAdBlockers == [ublock, adGuard])
        #expect(resumed.adBlockerChoice == .keep(ublock.identifier))
    }

    @Test @MainActor func unknownExtensionIDsCannotInventTheStepOrKeepChoice() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        let filtered = try saved(fixture) {
            $0.importedAdBlockers = [ublock, adGuard, .init(identifier: "not-a-known-blocker", displayName: "Unknown")]
            $0.adBlockerChoice = .keep("not-a-known-blocker")
        }
        #expect(filtered.importedAdBlockers == [ublock, adGuard])
        #expect(filtered.adBlockerChoice == nil)
    }

    @Test @MainActor func dontBlockAdsSurvivesRestartUntilSetupFinishes() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        let none = try saved(fixture) {
            $0.importedAdBlockers = [ublock]
            $0.adBlockerChoice = Choice.none
        }
        #expect(none.adBlockerChoice == Choice.none)
    }

    @Test @MainActor func yesBelongsOnlyToTheLayoutShownWhenNothingWasImported() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        let misplaced = try saved(fixture) {
            $0.importedAdBlockers = [ublock]
            $0.adBlockerChoice = .uBlock
        }
        #expect(misplaced.adBlockerChoice == nil)
    }

    @Test @MainActor func yesSurvivesRestart() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        let yes = try saved(fixture) {
            $0.importedAdBlockers = []
            $0.adBlockerChoice = .uBlock
        }
        #expect(yes.adBlockerChoice == .uBlock)
    }

    @Test @MainActor func draftsSavedBeforeProfilesWereRecordedStillDecode() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        _ = try saved(fixture) { $0.importedAdBlockers = [] }
        try fixture.rewriteDraft {
            $0["importedAdBlockers"] = [["identifier": ublock.identifier, "displayName": ublock.displayName]]
            $0["adBlockerChoice"] = ["keep": ["_0": ublock.identifier]]
        }
        let older = try fixture.loadDraft()
        #expect(older.importedAdBlockers == [ublock])
        #expect(older.importedAdBlockers[0].profileIDs == nil)
        #expect(older.adBlockerChoice == .keep(ublock.identifier))
    }

    @Test func theStepOpensOnYesOrTheFirstImportedBlockerAndKeepsAChoiceThatStillHasItsRow() {
        #expect(Choice.settled(nil, for: []) == .uBlock)
        #expect(Choice.settled(Choice.none, for: []) == Choice.none)
        #expect(Choice.settled(.keep(ublock.identifier), for: []) == .uBlock)
        #expect(Choice.settled(nil, for: [ublock, adGuard]) == .keep(ublock.identifier))
        #expect(Choice.settled(.uBlock, for: [ublock, adGuard]) == .keep(ublock.identifier))
        #expect(Choice.settled(.keep(adGuard.identifier), for: [ublock, adGuard]) == .keep(adGuard.identifier))
        #expect(Choice.settled(Choice.none, for: [ublock, adGuard]) == Choice.none)
    }

    @Test func dontBlockAdsRemovesEveryImportedBlockerFromEachProfileItWentInto() {
        var placed = ublock
        placed.profileIDs = [setupProfile]
        #expect(Choice.none.plan(for: [placed, adGuard], setupProfileID: setupProfile)
            == .init(removals: [setupProfile: [ublock.identifier, adGuard.identifier], sideProfile: [adGuard.identifier]],
                     installProfileID: nil))
    }

    @Test func keepingOneBlockerRemovesTheOthersInEachProfile() {
        var placed = ublock
        placed.profileIDs = [setupProfile]
        #expect(Choice.keep(ublock.identifier).plan(for: [placed, adGuard], setupProfileID: setupProfile)
            == .init(removals: [setupProfile: [adGuard.identifier], sideProfile: [adGuard.identifier]], installProfileID: nil))
        #expect(Choice.keep(adGuard.identifier).plan(for: [placed, adGuard], setupProfileID: setupProfile)
            == .init(removals: [setupProfile: [ublock.identifier]], installProfileID: nil))
    }

    @Test func yesInstallsUBlockIntoTheSetupSpacesProfileAndNoChangesNothing() {
        #expect(Choice.uBlock.plan(for: [], setupProfileID: setupProfile)
            == .init(removals: [:], installProfileID: setupProfile))
        #expect(Choice.none.plan(for: [], setupProfileID: setupProfile) == .init(removals: [:], installProfileID: nil))
    }

    @Test func useAllImportedAdBlockersLeavesEveryOneInstalled() {
        var placed = ublock
        placed.profileIDs = [setupProfile]
        #expect(Choice.keepAll.plan(for: [placed, adGuard], setupProfileID: setupProfile)
            == .init(removals: [:], installProfileID: nil))
        #expect(Choice.keepAll.plan(for: [], setupProfileID: setupProfile) == .init(removals: [:], installProfileID: nil))
    }

    @Test @MainActor func keepAllSurvivesRestartAndReturningToTheStepSelectsItsFirstRowAgain() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        let kept = try saved(fixture) {
            $0.importedAdBlockers = [ublock, adGuard]
            $0.adBlockerChoice = .keepAll
        }
        #expect(kept.adBlockerChoice == .keepAll)
        #expect(Choice.settled(.keepAll, for: [ublock, adGuard]) == .keep(ublock.identifier))
    }

    @Test @MainActor func aChoiceMadeAtTheStepStandsAfterRestartEvenIfItsKeptBlockerLaterFailed() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        let after = try saved(fixture, stage: .defaultBrowser) {
            $0.importedAdBlockers = [ublock]
            $0.adBlockerChoice = .keep(adGuard.identifier)
        }
        #expect(after.adBlockerChoice == .keep(adGuard.identifier))
    }

    @Test func keepingABlockerWhoseDownloadLaterFailedStillRemovesTheOthers() {
        var placed = ublock
        placed.profileIDs = [setupProfile]
        #expect(Choice.keep("pkehgijcmpdhfbdbbnkijodmdjhbjlgp").plan(for: [placed, adGuard], setupProfileID: setupProfile)
            == .init(removals: [setupProfile: [ublock.identifier, adGuard.identifier], sideProfile: [adGuard.identifier]],
                     installProfileID: nil))
    }

    @Test func anOlderDraftsBlockerWithoutProfilesIsRemovedFromTheSetupSpacesProfile() {
        #expect(Choice.none.plan(for: [ublock], setupProfileID: setupProfile)
            == .init(removals: [setupProfile: [ublock.identifier]], installProfileID: nil))
    }
}
