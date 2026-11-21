import Foundation
import Testing
@testable import ParcCore

@MainActor
struct ProfileRemovalTests {
    struct InjectedFailure: Error {}

    @MainActor final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Parc-Profile-Removal-" + UUID().uuidString)
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let seed: BrowserState
        let originalProfile: UUID
        let spaceID: UUID
        let deleting = UUID()
        let download: BrowserDownload
        let store: BrowserStore
        var file: URL { directory.appendingPathComponent("session.json") }

        init() throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            var seed = BrowserState.initial()
            let originalProfile = seed.profiles[0].id
            let spaceID = seed.activeSpaceID
            seed.profiles.append(BrowserProfile(id: deleting, name: "Work"))
            let now = now
            seed.tabs = [
                BrowserTab(id: UUID(), spaceID: spaceID, profileID: originalProfile, url: "https://example.org", title: "Keep", kind: .today, createdAt: now, lastAccessed: now, savedURL: "https://example.org", savedTitle: "Keep"),
                BrowserTab(id: UUID(), spaceID: spaceID, profileID: deleting, url: "https://example.net", title: "Favorite", kind: .favorite, createdAt: now, lastAccessed: now, savedURL: "https://example.net", savedTitle: "Favorite"),
                BrowserTab(id: UUID(), spaceID: spaceID, profileID: deleting, url: "https://example.com", title: "Archive", kind: .today, createdAt: now, lastAccessed: now, archivedAt: now, savedURL: "https://example.com", savedTitle: "Archive")]
            seed.selectedTabIDs = [seed.tabs[0].id]
            seed.history = [BrowserHistoryEntry(id: UUID(), url: "https://example.net", title: "Removed", visitedAt: now, profileID: deleting),
                            BrowserHistoryEntry(id: UUID(), url: "https://example.org", title: "Keep", visitedAt: now, profileID: originalProfile)]
            var download = BrowserDownload(id: "download", name: "file.txt", path: directory.appendingPathComponent("file.txt").path,
                                           receivedBytes: 1, totalBytes: 1, status: .completed)
            download.profileID = deleting
            seed.downloads = [download]
            seed.settings.settingsProfileID = deleting
            try Data("x".utf8).write(to: URL(fileURLWithPath: download.path))
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(seed).write(to: directory.appendingPathComponent("session.json"))
            self.seed = seed
            self.originalProfile = originalProfile
            self.spaceID = spaceID
            self.download = download
            store = try BrowserStore(directory: directory)
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func refuseWrites() throws {
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        }

        func completeDeleting() throws -> BrowserStore {
            let record = try store.stageProfileRemoval(deleting, expectedName: "Work")
            let restarted = try BrowserStore(directory: directory)
            try restarted.finishProfileRemoval(record)
            return restarted
        }
    }

    @Test func aPreviewLeasePreventsSingleAndBulkStaging() throws {
        let fixture = try Fixture()
        let store = fixture.store
        let preview = try #require(store.acquireArchivePreview(id: fixture.seed.tabs[2].id, profileID: fixture.deleting))
        #expect(throws: (any Error).self) { try store.stageProfileRemoval(fixture.deleting, expectedName: "Work") }
        #expect(throws: (any Error).self) { try store.stageUnusedProfileRemovals([fixture.seed.profiles[1]]) }
        #expect(store.state.profileRemovals.isEmpty)
        store.releaseArchivePreview(preview)
    }

    @Test func theLegacyDefaultResolvesToTheOriginalProfile() throws {
        let fixture = try Fixture()
        #expect(fixture.store.defaultProfileID == fixture.originalProfile)
    }

    @Test func theDefaultProfileHasNoRemovalSummaryWhileInUseAndAStaleNameIsRejected() throws {
        let fixture = try Fixture()
        let store = fixture.store
        try store.saveProfileName(fixture.originalProfile, expectedName: "Default", name: "Renamed Default")
        #expect(throws: (any Error).self) { try store.profileRemovalSummary(fixture.originalProfile) }
        #expect(throws: (any Error).self) { try store.validateProfileRemoval(fixture.deleting, expectedName: "Other") }
    }

    @Test func confirmationReportsTheActualSourceRecords() throws {
        let fixture = try Fixture()
        let summary = try fixture.store.validateProfileRemoval(fixture.deleting, expectedName: "Work")
        #expect(summary.savedTabCount == 2 && summary.historyEntryCount == 1)
    }

    @Test func aPendingWriteBlocksRemovalStaging() async throws {
        let fixture = try Fixture()
        let store = fixture.store
        let reservation = try #require(store.reserveProfileWrite(fixture.deleting))

        _ = await reservation.perform {
            #expect(throws: (any Error).self) { try store.stageProfileRemoval(fixture.deleting, expectedName: "Work") }
        }
    }

    @Test func aCompletedWriteReleasesItsReservation() async throws {
        let fixture = try Fixture()
        let store = fixture.store
        let reservation = try #require(store.reserveProfileWrite(fixture.deleting))

        await reservation.perform {}
        let staged = try store.stageProfileRemoval(fixture.deleting, expectedName: "Work")
        #expect(staged.profileID == fixture.deleting)
    }

    @Test func aWriteFailureIsPropagatedAfterReleasingItsReservation() async throws {
        let fixture = try Fixture()
        let failing = try #require(fixture.store.reserveProfileWrite(fixture.deleting))
        var writeFailed = false
        do { try await failing.perform { throw InjectedFailure() } } catch { writeFailed = true }
        #expect(writeFailed)
    }

    @Test func anUnknownParentCannotReserveAWrite() throws {
        let fixture = try Fixture()
        #expect(fixture.store.reserveProfileWrite(UUID()) == nil)
    }

    @Test func assignmentWaitsForNativeRetirementApproval() throws {
        let fixture = try Fixture()
        var gate: (() -> Bool)?
        fixture.store.requestPageRetirement = { _, approve, _ in gate = approve }
        fixture.store.assignProfile(fixture.deleting, toSpace: fixture.spaceID)
        #expect(gate != nil)
    }

    @Test func stagingCannotPublishDeletionAndBlocksReuseAndNewLibraryWrites() throws {
        let fixture = try Fixture()
        let store = fixture.store
        _ = try store.stageProfileRemoval(fixture.deleting, expectedName: "Work")
        #expect(store.state.profiles.contains { $0.id == fixture.deleting })
        #expect(store.isProfileRemovalPending(fixture.deleting))
        #expect(store.reserveProfileWrite(fixture.deleting) == nil)
    }

    @Test func aPendingRemovalRevokesAPreexistingReassignmentBeforeNativeClose() throws {
        let fixture = try Fixture()
        let store = fixture.store
        var gate: (() -> Bool)?
        var completion: ((Bool) -> Void)?
        store.requestPageRetirement = { _, approve, finish in
            gate = approve
            completion = finish
        }
        store.assignProfile(fixture.deleting, toSpace: fixture.spaceID)
        _ = try store.stageProfileRemoval(fixture.deleting, expectedName: "Work")
        #expect(gate?() == false)
        completion?(false)
    }

    @Test func aPendingProfileCannotBeReassignedRestagedOrRenamed() throws {
        let fixture = try Fixture()
        let store = fixture.store
        _ = try store.stageProfileRemoval(fixture.deleting, expectedName: "Work")
        #expect(throws: (any Error).self) { try store.stageProfileRemoval(fixture.deleting, expectedName: "Work") }
        store.assignProfile(fixture.deleting, toSpace: fixture.spaceID)
        #expect(store.state.spaces[0].profileID == fixture.originalProfile)
        #expect(throws: (any Error).self) { try store.saveProfileName(fixture.deleting, expectedName: "Work", name: "Other") }
    }

    @Test func aPendingOperationSurvivesRestartAndCancellationPreservesRecords() throws {
        let fixture = try Fixture()
        let record = try fixture.store.stageProfileRemoval(fixture.deleting, expectedName: "Work")
        let restarted = try BrowserStore(directory: fixture.directory)
        #expect(restarted.state.profileRemovals == [record] && restarted.isProfileRemovalPending(fixture.deleting))
        try restarted.cancelProfileRemoval(record)
        #expect(!restarted.isProfileRemovalPending(fixture.deleting) && restarted.state.tabs.count == 3)
    }

    @Test func aFinalWriteFailureRetainsTheDurableTransactionAndBlockedProfile() throws {
        let fixture = try Fixture()
        let record = try fixture.store.stageProfileRemoval(fixture.deleting, expectedName: "Work")
        let restarted = try BrowserStore(directory: fixture.directory)
        try fixture.refuseWrites()
        #expect(throws: (any Error).self) { try restarted.finishProfileRemoval(record) }
        #expect(restarted.isProfileRemovalPending(fixture.deleting) && restarted.state.profiles.count == 2)
        try FileManager.default.removeItem(at: fixture.file)
        try restarted.finishProfileRemoval(record)
        #expect(restarted.state.profiles.map(\.id) == [fixture.originalProfile])
    }

    @Test func completionRemovesOnlyTheSelectedProfileAndPreservesOtherTabsAndEverySpace() throws {
        let fixture = try Fixture()
        let restarted = try fixture.completeDeleting()
        #expect(restarted.state.profiles.map(\.id) == [fixture.originalProfile])
        #expect(restarted.state.tabs.map(\.id) == [fixture.seed.tabs[0].id] && restarted.state.spaces == fixture.seed.spaces)
    }

    @Test func completionRemovesOnlySourceHistoryAndKeepsDownloadFiles() throws {
        let fixture = try Fixture()
        let restarted = try fixture.completeDeleting()
        #expect(restarted.state.history.count == 1 && restarted.state.history[0].profileID == fixture.originalProfile)
        #expect(restarted.state.downloads.isEmpty && FileManager.default.fileExists(atPath: fixture.download.path))
    }

    @Test func completionRepairsTheSettingsSelectionAndClearsTheTransaction() throws {
        let fixture = try Fixture()
        let restarted = try fixture.completeDeleting()
        #expect(restarted.state.settings.settingsProfileID == fixture.originalProfile && restarted.state.profileRemovals.isEmpty)
    }

    @Test func removingAnotherProfileKeepsTheDefaultInPlace() throws {
        let fixture = try Fixture()
        _ = try fixture.completeDeleting()
        let final = try BrowserStore(directory: fixture.directory)
        #expect(final.state.profiles.count == 1 && final.defaultProfileID == fixture.originalProfile)
    }

    struct Bulk {
        let final: BrowserStore
        let first: UUID
        let second: UUID
        let reviewed: [BrowserProfile]
    }

    func withBulk(_ body: (Fixture, Bulk) throws -> Void) throws {
        let fixture = try Fixture()
        _ = try fixture.completeDeleting()
        let final = try BrowserStore(directory: fixture.directory)
        let first = final.createProfile(name: "Personal")
        let second = final.createProfile(name: "Research")
        try body(fixture, Bulk(final: final, first: first, second: second, reviewed: final.unusedProfilesForRemoval))
    }

    @Test func bulkCandidatesExcludeTheDefaultWhileASpaceUsesIt() throws {
        try withBulk { _, bulk in
            #expect(bulk.reviewed.map(\.id) == [bulk.first, bulk.second])
        }
    }

    @Test func bulkStagingRejectsEmptyDuplicateAndDefaultTargets() throws {
        try withBulk { _, bulk in
            #expect(throws: (any Error).self) { try bulk.final.stageUnusedProfileRemovals([]) }
            #expect(throws: (any Error).self) { try bulk.final.stageUnusedProfileRemovals([bulk.reviewed[0], bulk.reviewed[0]]) }
            #expect(throws: (any Error).self) { try bulk.final.stageUnusedProfileRemovals([bulk.final.state.profiles[0]]) }
        }
    }

    @Test func oneStaleNameRejectsEveryNewTargetBeforeStaging() throws {
        try withBulk { _, bulk in
            try bulk.final.saveProfileName(bulk.second, expectedName: "Research", name: "Reference")
            #expect(throws: (any Error).self) { try bulk.final.stageUnusedProfileRemovals(bulk.reviewed) }
            #expect(bulk.final.state.profileRemovals.isEmpty)
        }
    }

    @Test func aReservedWriteRefusesTheWholeBulkRemoval() throws {
        try withBulk { _, bulk in
            let reservation = try #require(bulk.final.reserveProfileWrite(bulk.first))
            #expect(throws: (any Error).self) { try bulk.final.stageUnusedProfileRemovals(bulk.reviewed) }
            #expect(bulk.final.state.profileRemovals.isEmpty)
            reservation.finish()
            reservation.finish()
        }
    }

    @Test func failedBulkStagingPublishesNoPartialAuthorizationOrRemoval() throws {
        try withBulk { fixture, bulk in
            _ = bulk.final.createProfile(name: "Created after review")
            try bulk.final.saveSettingsSelection(pane: "Profiles", profileID: bulk.first)
            let before = bulk.final.state
            try fixture.refuseWrites()
            #expect(throws: (any Error).self) { try bulk.final.stageUnusedProfileRemovals(bulk.reviewed) }
            #expect(bulk.final.state == before && bulk.final.state.profileRemovals.isEmpty)
        }
    }

    struct Staged {
        let records: [ProfileRemovalRecord]
        let newAfterReview: UUID
    }

    func withStagedBulk(_ body: (Fixture, Bulk, Staged) throws -> Void) throws {
        try withBulk { fixture, bulk in
            let newAfterReview = bulk.final.createProfile(name: "Created after review")
            try bulk.final.saveSettingsSelection(pane: "Profiles", profileID: bulk.first)
            let records = try bulk.final.stageUnusedProfileRemovals(bulk.reviewed)
            try body(fixture, bulk, Staged(records: records, newAfterReview: newAfterReview))
        }
    }

    @Test func bulkStagingBindsSeparateOperationIDsToTheReviewedIdentitiesAndDeletesNothing() throws {
        try withStagedBulk { _, bulk, staged in
            #expect(staged.records.map(\.profileID) == [bulk.first, bulk.second] && Set(staged.records.map(\.id)).count == 2)
            #expect(bulk.final.state.profiles.count == 4 && !bulk.final.isProfileRemovalPending(staged.newAfterReview))
        }
    }

    @Test func pendingRemovalsAreNotOfferedASecondTime() throws {
        try withStagedBulk { _, bulk, staged in
            #expect(bulk.final.unusedProfilesForRemoval.map(\.id) == [staged.newAfterReview])
        }
    }

    @Test func theEntireAuthorizationSetSurvivesRestart() throws {
        try withStagedBulk { fixture, _, staged in
            let actual1 = try BrowserStore(directory: fixture.directory).state.profileRemovals
            #expect(actual1 == staged.records)
        }
    }

    @Test func oneCompletedReceiptLeavesTheOtherOriginalOperationRecoverable() throws {
        try withStagedBulk { fixture, bulk, staged in
            let restarted = try BrowserStore(directory: fixture.directory)
            try restarted.finishProfileRemoval(staged.records[0])
            #expect(restarted.state.profileRemovals == [staged.records[1]] && restarted.isProfileRemovalPending(bulk.second))
        }
    }

    @Test func independentCancellationPreservesTheUnsuccessfulAndUnreviewedProfiles() throws {
        try withStagedBulk { fixture, bulk, staged in
            let restarted = try BrowserStore(directory: fixture.directory)
            try restarted.finishProfileRemoval(staged.records[0])
            try restarted.cancelProfileRemoval(staged.records[1])
            #expect(restarted.state.profiles.map(\.id) == [fixture.originalProfile, bulk.second, staged.newAfterReview])
        }
    }

    @Test func recordsSavedBeforeFallbacksWereRecordedUseTheDefaultProfile() throws {
        try withBulk { fixture, bulk in
            let legacy = try JSONDecoder().decode(ProfileRemovalRecord.self, from: Data(
                #"{"id":"\#(UUID().uuidString)","profileID":"\#(bulk.second.uuidString)","profileName":"Research"}"#.utf8))
            #expect(legacy.fallbackProfileID == nil && bulk.final.fallbackProfileID(for: legacy) == fixture.originalProfile)
        }
    }

    struct DefaultRemoval {
        let store: BrowserStore
        let survivor: UUID
        let record: ProfileRemovalRecord
    }

    func withDefaultStaged(_ body: (Fixture, DefaultRemoval) throws -> Void) throws {
        try withBulk { fixture, bulk in
            try bulk.final.saveProfileName(fixture.originalProfile, expectedName: "Default", name: "Renamed Default")
            bulk.final.assignProfile(bulk.second, toSpace: bulk.final.state.activeSpaceID)
            try bulk.final.saveSettingsSelection(pane: "Profiles", profileID: fixture.originalProfile)
            let record = try bulk.final.stageProfileRemoval(fixture.originalProfile, expectedName: "Renamed Default")
            try body(fixture, DefaultRemoval(store: bulk.final, survivor: bulk.second, record: record))
        }
    }

    @Test func theDefaultProfileIsDeletableOnceUnused() throws {
        try withBulk { fixture, bulk in
            try bulk.final.saveProfileName(fixture.originalProfile, expectedName: "Default", name: "Renamed Default")
            bulk.final.assignProfile(bulk.second, toSpace: bulk.final.state.activeSpaceID)
            #expect(bulk.final.state.spaces.allSatisfy { $0.profileID == bulk.second })
            try bulk.final.saveSettingsSelection(pane: "Profiles", profileID: fixture.originalProfile)
            let summary = try bulk.final.validateProfileRemoval(fixture.originalProfile, expectedName: "Renamed Default")
            #expect(summary.profile.id == fixture.originalProfile)
        }
    }

    @Test func stagingTheDefaultRecordsTheSurvivorAndMovesDefaultAndSettingsInTheSameSave() throws {
        try withDefaultStaged { _, removal in
            #expect(removal.record.fallbackProfileID == removal.survivor && removal.store.defaultProfileID == removal.survivor
                    && removal.store.state.settings.settingsProfileID == removal.survivor)
        }
    }

    @Test func aPendingDefaultRemovalSurvivesRestartWithItsRecordedSurvivor() throws {
        try withDefaultStaged { fixture, removal in
            let pending = try BrowserStore(directory: fixture.directory)
            #expect(pending.state.profileRemovals == [removal.record] && pending.defaultProfileID == removal.survivor)
        }
    }

    @Test func completingTheDefaultRemovalLeavesTheSurvivorAsDefaultAndItSurvivesReload() throws {
        try withDefaultStaged { fixture, removal in
            let pending = try BrowserStore(directory: fixture.directory)
            try pending.finishProfileRemoval(removal.record)
            #expect(!pending.state.profiles.contains { $0.id == fixture.originalProfile } && pending.defaultProfileID == removal.survivor)
            let actual2 = try BrowserStore(directory: fixture.directory).defaultProfileID
            #expect(actual2 == removal.survivor)
        }
    }
}
