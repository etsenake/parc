import Foundation
import Testing
@testable import Parc
@testable import ParcCore
import ParcEngine

@MainActor
struct ProfileRemovalControllerTests {
    @MainActor
    private final class Lease: ProfileRemovalLease {
        let operationID: String
        let profilePath: String
        var cancelled = false
        var completion: ((PCNativeProfileRemovalState, Error?) -> Void)?

        init(path: String, operation: String) {
            profilePath = path
            operationID = operation
        }

        func cancel() { cancelled = true }

        func commit(revalidate: @escaping () -> Bool,
                    completion: @escaping (PCNativeProfileRemovalState, Error?) -> Void) {
            if revalidate() { self.completion = completion }
            else { completion(.failed, ProfileRemovalError.unavailable) }
        }
    }

    @MainActor
    private final class NativeDouble {
        struct Preparation {
            let path: String
            let protectedPath: String
            let operation: String
            let completion: @Sendable (ProfileRemovalLease?, Error?) -> Void
        }

        struct Recovery {
            let path: String
            let protectedPath: String
            let operation: String
            let completion: @Sendable (PCNativeProfileRemovalState, Error?) -> Void
        }

        var preparations: [Preparation] = []
        var recoveries: [Recovery] = []
        var willPrepare: (() -> Void)?

        var boundary: ProfileRemovalNative {
            ProfileRemovalNative(
                prepare: { [self] path, protectedPath, operation, completion in
                    willPrepare?()
                    preparations.append(Preparation(path: path, protectedPath: protectedPath, operation: operation,
                                                    completion: completion))
                },
                recover: { [self] path, protectedPath, operation, completion in
                    recoveries.append(Recovery(path: path, protectedPath: protectedPath, operation: operation,
                                               completion: completion))
                })
        }

        func lease(_ index: Int) -> Lease {
            let request = preparations[index]
            let lease = Lease(path: request.path, operation: request.operation)
            request.completion(lease, nil)
            return lease
        }
    }

    @MainActor
    private final class Fixture {
        let directory: URL
        let store: BrowserStore
        let controller = ProfileRemovalController(noteFolders: IsolatedNoteFiles.make().folders)
        let native = NativeDouble()
        let originalDefault: UUID
        var first = UUID(), second = UUID(), third = UUID()
        var reviewed: [BrowserProfile] = []

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("Parc-Profile-Controller-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            store = try BrowserStore(directory: directory)
            originalDefault = store.defaultProfileID
            controller.native = native.boundary
            controller.configure(store: store)
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }

        func addThreeUnusedProfiles() {
            first = store.createProfile(name: "First")
            second = store.createProfile(name: "Second")
            third = store.createProfile(name: "Third")
            reviewed = store.unusedProfilesForRemoval
        }

        func submitReviewed() throws {
            try controller.removeUnusedProfiles(reviewed)
        }

        func removalRecord(for profileID: UUID) -> ProfileRemovalRecord? {
            store.state.profileRemovals.first { $0.profileID == profileID }
        }

        func runMixedFirstAttempt() throws -> (firstLease: Lease, unreviewed: UUID) {
            addThreeUnusedProfiles()
            try submitReviewed()
            let firstLease = native.lease(0)
            native.preparations[1].completion(nil, ProfileRemovalError.unavailable)
            controller.cancel(profileID: third)
            _ = native.lease(2)
            firstLease.completion?(.removed, nil)
            let unreviewed = store.createProfile(name: "New after confirmation")
            return (firstLease, unreviewed)
        }

        func runSecondAttempt() throws -> (secondLease: Lease, secondRecord: ProfileRemovalRecord, unreviewed: UUID) {
            let unreviewed = try runMixedFirstAttempt().unreviewed
            try submitReviewed()
            let secondRecord = removalRecord(for: second)!
            let secondLease = native.lease(3)
            let thirdLease = native.lease(4)
            secondLease.completion?(.pending, ProfileRemovalError.incompleteOperation)
            thirdLease.completion?(.removed, nil)
            controller.cancel(profileID: second)
            return (secondLease, secondRecord, unreviewed)
        }

        func removeSingleProfile() -> UUID {
            let single = store.createProfile(name: "Single")
            controller.remove(profileID: single, expectedName: "Single")
            return single
        }
    }

    private static func rejects(_ operation: () throws -> Void) -> Bool {
        do { try operation() } catch { return true }
        return false
    }

    @Test func everyAuthorizationPrecedesTheFirstNativePreparation() throws {
        let fixture = try Fixture()
        fixture.addThreeUnusedProfiles()
        var everyTargetWasStaged = true
        fixture.native.willPrepare = {
            everyTargetWasStaged = everyTargetWasStaged
                && [fixture.first, fixture.second, fixture.third].allSatisfy(fixture.store.isProfileRemovalPending)
        }
        try fixture.submitReviewed()
        #expect(everyTargetWasStaged)
        #expect(fixture.native.preparations.count == 3)
    }

    @Test func aRepeatedSubmitCannotDuplicateRunningOperations() throws {
        let fixture = try Fixture()
        fixture.addThreeUnusedProfiles()
        try fixture.submitReviewed()
        #expect(Self.rejects { try fixture.submitReviewed() })
        #expect(fixture.native.preparations.count == 3)
    }

    @Test func aCommittedOperationSurvivesClosingTheSheet() throws {
        let fixture = try Fixture()
        fixture.addThreeUnusedProfiles()
        try fixture.submitReviewed()
        let lease = fixture.native.lease(0)
        fixture.controller.cancel(profileID: fixture.first)
        #expect(!lease.cancelled)
        #expect(fixture.store.isProfileRemovalPending(fixture.first))
    }

    @Test func onePreparationFailureReleasesOnlyItsOwnRecord() throws {
        let fixture = try Fixture()
        fixture.addThreeUnusedProfiles()
        try fixture.submitReviewed()
        fixture.native.preparations[1].completion(nil, ProfileRemovalError.unavailable)
        #expect(!fixture.store.isProfileRemovalPending(fixture.second))
        #expect(fixture.store.state.profiles.contains { $0.id == fixture.second })
        #expect(fixture.store.isProfileRemovalPending(fixture.first))
    }

    @Test func cancellationWhilePreparationIsOutstandingReleasesTheArrivingLease() throws {
        let fixture = try Fixture()
        fixture.addThreeUnusedProfiles()
        try fixture.submitReviewed()
        fixture.controller.cancel(profileID: fixture.third)
        let lease = fixture.native.lease(2)
        #expect(lease.cancelled)
        #expect(lease.completion == nil)
        #expect(!fixture.store.isProfileRemovalPending(fixture.third))
    }

    @Test func successRemovesOnlyTheExactCompletedProfile() throws {
        let fixture = try Fixture()
        fixture.addThreeUnusedProfiles()
        try fixture.submitReviewed()
        fixture.native.lease(0).completion?(.removed, nil)
        #expect(!fixture.store.state.profiles.contains { $0.id == fixture.first })
        #expect(fixture.store.state.profiles.count == 3)
    }

    @Test func aRetrySkipsCompletedTargetsAndNeverExpandsToNewlyUnusedProfiles() throws {
        let fixture = try Fixture()
        let unreviewed = try fixture.runMixedFirstAttempt().unreviewed
        try fixture.submitReviewed()
        #expect(fixture.native.preparations.count == 5)
        #expect(!fixture.store.isProfileRemovalPending(unreviewed))
    }

    @Test func aSafelyFailedAttemptReceivesANewAuthorization() throws {
        let fixture = try Fixture()
        _ = try fixture.runMixedFirstAttempt()
        try fixture.submitReviewed()
        let retried = try #require(fixture.removalRecord(for: fixture.second))
        #expect(fixture.native.preparations[3].operation == retried.id.uuidString)
        #expect(fixture.native.preparations[1].operation != retried.id.uuidString)
    }

    @Test func partialCompletionKeepsTheExactIncompleteJournalBlocked() throws {
        let fixture = try Fixture()
        let attempt = try fixture.runSecondAttempt()
        #expect(fixture.store.state.profileRemovals == [attempt.secondRecord])
        #expect(!attempt.secondLease.cancelled)
    }

    @Test func aRetryRecoversACommittedOperationInsteadOfPreparingASecondDeletion() throws {
        let fixture = try Fixture()
        _ = try fixture.runSecondAttempt()
        try fixture.submitReviewed()
        #expect(fixture.native.preparations.count == 5)
        #expect(fixture.native.recoveries.count == 1)
    }

    @Test func recoveryPreservesTheExactNativePathAndOperationIdentity() throws {
        let fixture = try Fixture()
        let attempt = try fixture.runSecondAttempt()
        try fixture.submitReviewed()
        let recovery = fixture.native.recoveries[0]
        #expect(recovery.operation == attempt.secondRecord.id.uuidString)
        #expect(recovery.path == attempt.secondLease.profilePath)
    }

    @Test func mixedOutcomesConvergeWithoutTouchingDefaultOrANewProfile() throws {
        let fixture = try Fixture()
        let attempt = try fixture.runSecondAttempt()
        try fixture.submitReviewed()
        fixture.native.recoveries[0].completion(.removed, nil)
        #expect(fixture.store.state.profiles.map(\.id) == [fixture.originalDefault, attempt.unreviewed])
        #expect(fixture.store.state.profileRemovals.isEmpty)
    }

    @Test func aNewlyAssignedTargetPreventsEveryNewRemovalBeforeNativeDispatch() throws {
        let fixture = try Fixture()
        let assigned = fixture.store.createProfile(name: "Assigned after review")
        let staleReview = fixture.store.unusedProfilesForRemoval
        fixture.store.assignProfile(assigned, toSpace: fixture.store.state.activeSpaceID)
        #expect(Self.rejects { try fixture.controller.removeUnusedProfiles(staleReview) })
        #expect(fixture.native.preparations.isEmpty)
    }

    @Test func confirmingOneProfileStagesAndPreparesItWithoutATypedName() throws {
        let fixture = try Fixture()
        let single = fixture.removeSingleProfile()
        #expect(fixture.native.preparations.count == 1)
        #expect(fixture.controller.status(for: single)?.running == true)
    }

    @Test func aRefusedPreparationHandsItsErrorToOnePresenterAndKeepsTheProfile() throws {
        let fixture = try Fixture()
        let single = fixture.removeSingleProfile()
        fixture.native.preparations[0].completion(nil, ProfileRemovalError.unavailable)
        #expect(fixture.controller.claimFailure(for: single)?.error != nil)
        #expect(fixture.controller.claimFailure(for: single) == nil)
        #expect(!fixture.store.isProfileRemovalPending(single))
    }

    @Test func anIncompleteRemovalStaysPendingWithAReportableError() throws {
        let fixture = try Fixture()
        let single = fixture.removeSingleProfile()
        fixture.native.lease(0).completion?(.pending, ProfileRemovalError.incompleteOperation)
        #expect(fixture.controller.claimFailure(for: single)?.error != nil)
        #expect(fixture.store.isProfileRemovalPending(single))
    }

    @Test func retryingAPendingRemovalRecoversItsJournalWithoutConfirmingAgain() throws {
        let fixture = try Fixture()
        let single = fixture.removeSingleProfile()
        fixture.native.lease(0).completion?(.pending, ProfileRemovalError.incompleteOperation)
        fixture.controller.remove(profileID: single, expectedName: "Single")
        #expect(fixture.native.recoveries.count == 1)
        #expect(fixture.native.preparations.count == 1)
    }

    @Test func aRecoveredRemovalFinishesSilently() throws {
        let fixture = try Fixture()
        let single = fixture.removeSingleProfile()
        fixture.native.lease(0).completion?(.pending, ProfileRemovalError.incompleteOperation)
        fixture.controller.remove(profileID: single, expectedName: "Single")
        fixture.native.recoveries[0].completion(.removed, nil)
        #expect(!fixture.store.state.profiles.contains { $0.id == single })
        #expect(fixture.controller.status(for: single) == nil)
    }

    @Test func preparationProtectsTheDefaultProfileWhenAnotherIsRemoved() throws {
        let fixture = try Fixture()
        fixture.addThreeUnusedProfiles()
        try fixture.submitReviewed()
        let defaultPath = fixture.store.independentEngineProfilePath(for: fixture.originalDefault)
        #expect(fixture.native.preparations.allSatisfy { $0.protectedPath == defaultPath })
    }

    @Test func recoveryPassesTheSameProtectedProfileTheJournalRecorded() throws {
        let fixture = try Fixture()
        let single = fixture.removeSingleProfile()
        fixture.native.lease(0).completion?(.pending, ProfileRemovalError.incompleteOperation)
        fixture.controller.remove(profileID: single, expectedName: "Single")
        let defaultPath = fixture.store.independentEngineProfilePath(for: fixture.originalDefault)
        #expect(fixture.native.recoveries[0].protectedPath == defaultPath)
    }

    @Test func anUnusedDefaultProfileRemovesLikeAnyOtherAndProtectsTheSurvivor() throws {
        let fixture = try Fixture()
        let survivor = fixture.store.createProfile(name: "Assigned")
        fixture.store.assignProfile(survivor, toSpace: fixture.store.state.activeSpaceID)
        fixture.controller.remove(profileID: fixture.originalDefault, expectedName: "Default")
        #expect(fixture.native.preparations.count == 1)
        #expect(fixture.native.preparations[0].protectedPath == fixture.store.independentEngineProfilePath(for: survivor))
        #expect(fixture.store.defaultProfileID == survivor)
    }

    @Test func removingTheDefaultLeavesTheSurvivorAsDefault() throws {
        let fixture = try Fixture()
        let survivor = fixture.store.createProfile(name: "Assigned")
        fixture.store.assignProfile(survivor, toSpace: fixture.store.state.activeSpaceID)
        fixture.controller.remove(profileID: fixture.originalDefault, expectedName: "Default")
        fixture.native.lease(0).completion?(.removed, nil)
        #expect(fixture.store.state.profiles.map(\.id) == [survivor])
        #expect(fixture.store.defaultProfileID == survivor)
    }
}
