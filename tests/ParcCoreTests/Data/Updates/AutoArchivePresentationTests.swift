import Foundation
import Testing
@testable import ParcCore

@MainActor
struct AutoArchivePresentationTests {
    final class Clock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    @MainActor final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Parc-AutoArchive-Presentation-" + UUID().uuidString)
        let clock = Clock()
        let store: BrowserStore
        var now: Date { clock.now }
        var file: URL { directory.appendingPathComponent("session.json") }

        init() throws {
            let clock = clock
            store = try BrowserStore(directory: directory, now: { clock.now })
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        var draft: OnboardingDraft {
            OnboardingDraft(spaceID: store.activeSpaceID, spaceName: store.activeSpace.name,
                            theme: store.activeSpace.theme, favoriteURLs: [])
        }

        func armEducation() throws {
            _ = try store.changeAutoArchiveInterval(.twelveHours, for: store.activeSpace.profileID)
            try store.completeOnboarding(draft)
        }

        func advance() { clock.now.addTimeInterval(12 * 3600 + 1) }
    }

    @Test func anAbsentKeyDoesNotInventNewUserEligibility() throws {
        let fixture = try Fixture()
        #expect(!fixture.store.state.autoArchiveEducationEligible)
    }

    @Test func oneProfileHasNoScopeSheet() throws {
        let fixture = try Fixture()
        let change = try fixture.store.changeAutoArchiveInterval(.twentyFourHours, for: fixture.store.activeSpace.profileID)
        #expect(change == nil)
    }

    @Test func onlyTheOriginalSelectedProfileChangesBeforeTheScopeDecisionAndItIsSavedDurably() throws {
        let fixture = try Fixture()
        let store = fixture.store
        let first = store.activeSpace.profileID
        _ = try store.changeAutoArchiveInterval(.twentyFourHours, for: first)
        let second = store.createProfile(name: "Work")
        _ = try #require(try store.changeAutoArchiveInterval(.sevenDays, for: first))
        #expect(store.autoArchiveInterval(for: first) == .sevenDays && store.autoArchiveInterval(for: second) == .twentyFourHours)
        #expect(try BrowserStore(directory: fixture.directory).autoArchiveInterval(for: first) == .sevenDays)
    }

    @Test func allProfilesCommitsTheReviewedSetAndTheMissingProfileFallback() throws {
        let fixture = try Fixture()
        let store = fixture.store
        let first = store.activeSpace.profileID
        _ = try store.changeAutoArchiveInterval(.twentyFourHours, for: first)
        _ = store.createProfile(name: "Work")
        let change = try #require(try store.changeAutoArchiveInterval(.sevenDays, for: first))
        try store.applyAutoArchiveIntervalToAllProfiles(change)
        #expect(store.state.profiles.allSatisfy { $0.autoArchiveHours == 168 })
        #expect(store.state.autoArchiveDefaultHours == 168)
    }

    struct Applied {
        let first: UUID
        let second: UUID
    }

    func appliedToAll(_ fixture: Fixture) throws -> Applied {
        let store = fixture.store
        let first = store.activeSpace.profileID
        _ = try store.changeAutoArchiveInterval(.twentyFourHours, for: first)
        let second = store.createProfile(name: "Work")
        let change = try #require(try store.changeAutoArchiveInterval(.sevenDays, for: first))
        try store.applyAutoArchiveIntervalToAllProfiles(change)
        return Applied(first: first, second: second)
    }

    @Test func anUnchangedIntervalDoesNotOpenASheet() throws {
        let fixture = try Fixture()
        let applied = try appliedToAll(fixture)
        let change = try fixture.store.changeAutoArchiveInterval(.sevenDays, for: applied.second)
        #expect(change == nil)
    }

    @Test func aNewProfileUsesTheExplicitGlobalDefaultAndARetainedAllCallbackCannotAddALaterProfile() throws {
        let fixture = try Fixture()
        let store = fixture.store
        let applied = try appliedToAll(fixture)
        let stale = try #require(try store.changeAutoArchiveInterval(.thirtyDays, for: applied.second))
        let later = store.createProfile(name: "Created later")
        #expect(store.autoArchiveInterval(for: later) == .sevenDays)
        #expect(throws: (any Error).self) { try store.applyAutoArchiveIntervalToAllProfiles(stale) }
        #expect(store.autoArchiveInterval(for: applied.first) == .sevenDays)
    }

    @Test func aRenamedProfileRejectsARetainedAllCallback() throws {
        let fixture = try Fixture()
        let store = fixture.store
        let applied = try appliedToAll(fixture)
        let renamed = try #require(try store.changeAutoArchiveInterval(.twentyFourHours, for: applied.second))
        try store.saveProfileName(applied.second, expectedName: "Work", name: "Renamed")
        #expect(throws: (any Error).self) { try store.applyAutoArchiveIntervalToAllProfiles(renamed) }
    }

    @Test func aFailedAtomicSavePreservesEveryPublishedInterval() throws {
        let fixture = try Fixture()
        let store = fixture.store
        let applied = try appliedToAll(fixture)
        let before = store.state
        try FileManager.default.removeItem(at: fixture.file)
        try FileManager.default.createDirectory(at: fixture.file, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try store.changeAutoArchiveInterval(.twelveHours, for: applied.second) }
        #expect(store.state == before)
    }

    @Test func convergingToASharedIntervalNeedsNoScopeSheet() throws {
        let fixture = try Fixture()
        let store = fixture.store
        let applied = try appliedToAll(fixture)
        _ = try #require(try store.changeAutoArchiveInterval(.twentyFourHours, for: applied.second))
        let change = try store.changeAutoArchiveInterval(.sevenDays, for: applied.second)
        #expect(change == nil)
    }

    @Test func firstLocalSetupArmsAccountFreeNewUserEducation() throws {
        let fixture = try Fixture()
        _ = try appliedToAll(fixture)
        #expect(fixture.store.setAutoArchiveInterval(.twelveHours, for: fixture.store.activeSpace.profileID))
        try fixture.store.completeOnboarding(fixture.draft)
        #expect(fixture.store.state.autoArchiveEducationEligible)
        let archived = fixture.store.archiveExpiredTabs()
        #expect(archived.isEmpty && !fixture.store.autoArchiveEducationPending)
    }

    func armed() throws -> Fixture {
        let fixture = try Fixture()
        _ = try appliedToAll(fixture)
        _ = fixture.store.setAutoArchiveInterval(.twelveHours, for: fixture.store.activeSpace.profileID)
        try fixture.store.completeOnboarding(fixture.draft)
        _ = fixture.store.archiveExpiredTabs()
        return fixture
    }

    @Test func nativeRefusalCannotConsumeEducationOrReportCleanedTabs() throws {
        let fixture = try armed()
        let store = fixture.store
        _ = store.open("https://old.example")
        _ = store.open("https://selected.example")
        fixture.advance()
        store.requestPageRetirement = { _, _, complete in complete(false) }
        var refused: [UUID] = []
        store.archiveExpiredTabs(protectedTabIDs: []) { refused = $0 }
        #expect(refused.isEmpty && !store.autoArchiveEducationPending && store.state.autoArchiveEducationEligible)
    }

    @Test func anotherBannerInTheSharedSlotLeavesEducationArmed() throws {
        let fixture = try armed()
        let store = fixture.store
        let old = store.open("https://old.example")
        _ = store.open("https://selected.example")
        fixture.advance()
        store.sidebarBannerOccupied = { true }
        let archived = store.archiveExpiredTabs()
        #expect(archived == [old] && !store.autoArchiveEducationPending && store.state.autoArchiveEducationEligible)
    }

    @Test func anAcceptedActualAutomaticCloseProducesEducationAndConsumesEligibilityBeforePresentation() throws {
        let fixture = try armed()
        let store = fixture.store
        let next = store.open("https://later.example")
        _ = store.open("https://selected-again.example")
        fixture.advance()
        #expect(store.archiveExpiredTabs().contains(next))
        #expect(store.autoArchiveEducationPending && !store.state.autoArchiveEducationEligible)
    }

    @Test func explicitDismissalClearsTheSharedTransientBannerAndLaterClosesDoNotRepeatIt() throws {
        let fixture = try armed()
        let store = fixture.store
        _ = store.open("https://later.example")
        _ = store.open("https://selected-again.example")
        fixture.advance()
        _ = store.archiveExpiredTabs()
        store.dismissAutoArchiveEducation()
        #expect(!store.autoArchiveEducationPending)
        _ = store.open("https://next.example")
        fixture.advance()
        _ = store.archiveExpiredTabs()
        #expect(!store.autoArchiveEducationPending)
    }

    @Test func theConsumedMarkerSurvivesReloadAndReplayingSetupCannotRearmIt() throws {
        let fixture = try armed()
        let store = fixture.store
        _ = store.open("https://later.example")
        _ = store.open("https://selected-again.example")
        fixture.advance()
        _ = store.archiveExpiredTabs()
        try store.save()
        let now = fixture.now
        let restarted = try BrowserStore(directory: fixture.directory, now: { now })
        #expect(!restarted.state.autoArchiveEducationEligible && !restarted.autoArchiveEducationPending)
        try restarted.completeOnboarding(fixture.draft)
        #expect(!restarted.state.autoArchiveEducationEligible)
    }

    @Test func aCustomIntervalDisarmsTheRecoveredFixedTwelveHourEducation() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let custom = try BrowserStore(directory: directory)
            try custom.completeOnboarding(.init(spaceID: custom.activeSpaceID, spaceName: custom.activeSpace.name,
                                                theme: custom.activeSpace.theme, favoriteURLs: []))
            _ = try custom.changeAutoArchiveInterval(.twentyFourHours, for: custom.activeSpace.profileID)
            #expect(!custom.state.autoArchiveEducationEligible)
        }
    }
}
