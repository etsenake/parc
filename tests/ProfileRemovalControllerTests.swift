import Foundation

@main @MainActor struct ProfileRemovalControllerTests {
    struct Failure: Error { let message: String }
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        assertions += 1
        if !condition() { throw Failure(message: message) }
    }
    static func rejects(_ operation: () throws -> Void) throws {
        do { try operation() } catch { assertions += 1; return }
        throw Failure(message: "Expected refusal before native dispatch")
    }
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Parc-Profile-Controller-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let originalDefault = store.defaultProfileID
        let first = store.createProfile(name: "First")
        let second = store.createProfile(name: "Second")
        let third = store.createProfile(name: "Third")
        let reviewed = store.unusedProfilesForRemoval
        let controller = ProfileRemovalController()
        controller.configure(store: store)
        var everyTargetWasStaged = true
        PCNativeBrowserApplication.willPrepare = {
            everyTargetWasStaged = everyTargetWasStaged && [first, second, third].allSatisfy(store.isProfileRemovalPending)
        }
        try controller.removeUnusedProfiles(reviewed)
        PCNativeBrowserApplication.willPrepare = nil
        try expect(everyTargetWasStaged && PCNativeBrowserApplication.preparations.count == 3,
                   "All authorizations precede the first native preparation")
        let originalRecords = store.state.profileRemovals
        try rejects { try controller.removeUnusedProfiles(reviewed) }
        try expect(PCNativeBrowserApplication.preparations.count == 3, "Repeated submit cannot duplicate running operations")
        let firstLease = PCNativeBrowserApplication.prepare(0)
        controller.cancel(profileID: first)
        try expect(!firstLease.cancelled && store.isProfileRemovalPending(first), "Committed operation survives closing the sheet")
        PCNativeBrowserApplication.preparations[1].completion(nil, ProfileRemovalError.unavailable)
        try expect(!store.isProfileRemovalPending(second) && store.state.profiles.contains { $0.id == second },
                   "One preparation failure releases only its own app record")
        controller.cancel(profileID: third)
        let cancelledLease = PCNativeBrowserApplication.prepare(2)
        try expect(cancelledLease.cancelled && cancelledLease.completion == nil && !store.isProfileRemovalPending(third),
                   "Cancellation while preparation is outstanding releases the arriving lease without commit")
        firstLease.completion?(.removed, nil)
        try expect(!store.state.profiles.contains { $0.id == first } && store.state.profiles.count == 3,
                   "Success removes only the exact completed profile")
        let unreviewed = store.createProfile(name: "New after confirmation")
        try controller.removeUnusedProfiles(reviewed)
        try expect(PCNativeBrowserApplication.preparations.count == 5 && !store.isProfileRemovalPending(unreviewed),
                   "Retry skips completed targets and cannot expand to newly unused profiles")
        let secondRecord = store.state.profileRemovals.first { $0.profileID == second }!
        try expect(secondRecord.id != originalRecords.first { $0.profileID == second }!.id,
                   "A safely failed attempt receives a new authorization")
        let secondLease = PCNativeBrowserApplication.prepare(3)
        let thirdLease = PCNativeBrowserApplication.prepare(4)
        secondLease.completion?(.pending, ProfileRemovalError.incompleteOperation)
        thirdLease.completion?(.removed, nil)
        controller.cancel(profileID: second)
        try expect(store.state.profileRemovals == [secondRecord] && !secondLease.cancelled,
                   "Partial completion keeps the exact incomplete journal blocked")
        try controller.removeUnusedProfiles(reviewed)
        try expect(PCNativeBrowserApplication.preparations.count == 5 && PCNativeBrowserApplication.recoveries.count == 1,
                   "Retry recovers a committed operation instead of preparing a second deletion")
        let recovery = PCNativeBrowserApplication.recoveries[0]
        try expect(recovery.operation == secondRecord.id.uuidString && recovery.path == secondLease.profilePath,
                   "Recovery preserves exact native path and operation identity")
        recovery.completion(.removed, nil)
        try expect(store.state.profiles.map(\.id) == [originalDefault, unreviewed] && store.state.profileRemovals.isEmpty,
                   "Mixed outcomes converge without touching Default or a new profile")
        let assigned = store.createProfile(name: "Assigned after review")
        let staleReview = store.unusedProfilesForRemoval
        store.assignProfile(assigned, toSpace: store.state.activeSpaceID)
        try rejects { try controller.removeUnusedProfiles(staleReview) }
        try expect(PCNativeBrowserApplication.preparations.count == 5 && !store.isProfileRemovalPending(unreviewed),
                   "A newly assigned target prevents every new removal before native dispatch")
        let single = store.createProfile(name: "Single")
        controller.remove(profileID: single, expectedName: "Single")
        try expect(PCNativeBrowserApplication.preparations.count == 6 && controller.status(for: single)?.running == true,
                   "Confirming one profile stages and prepares it without a typed name")
        PCNativeBrowserApplication.preparations[5].completion(nil, ProfileRemovalError.unavailable)
        try expect(controller.claimFailure(for: single)?.error != nil && controller.claimFailure(for: single) == nil
                   && !store.isProfileRemovalPending(single),
                   "A refused preparation hands its error to one presenter and keeps the profile")
        controller.remove(profileID: single, expectedName: "Single")
        PCNativeBrowserApplication.prepare(6).completion?(.pending, ProfileRemovalError.incompleteOperation)
        try expect(controller.claimFailure(for: single)?.error != nil && store.isProfileRemovalPending(single),
                   "An incomplete removal stays pending with a reportable error")
        controller.remove(profileID: single, expectedName: "Single")
        try expect(PCNativeBrowserApplication.recoveries.count == 2 && PCNativeBrowserApplication.preparations.count == 7,
                   "Retrying a pending removal recovers its journal without confirming again")
        PCNativeBrowserApplication.recoveries[1].completion(.removed, nil)
        try expect(!store.state.profiles.contains { $0.id == single } && controller.status(for: single) == nil,
                   "Recovered removal finishes silently")
        let defaultPath = store.independentEngineProfilePath(for: originalDefault)
        let survivorPath = store.independentEngineProfilePath(for: assigned)
        let native = PCNativeBrowserApplication.self
        try expect(native.preparations.prefix(5).allSatisfy { $0.protectedPath == defaultPath }
                   && native.preparations.dropFirst(5).allSatisfy { $0.protectedPath == survivorPath },
                   "Preparation protects the surviving Profile recorded at staging")
        try expect(native.recoveries[0].protectedPath == defaultPath && native.recoveries[1].protectedPath == survivorPath,
                   "Recovery passes the same protected Profile the journal recorded")
        controller.remove(profileID: originalDefault, expectedName: "Default")
        try expect(native.preparations.count == 8 && native.preparations[7].protectedPath == survivorPath
                   && store.defaultProfileID == assigned, "The unused Default Profile removes like any other")
        native.prepare(7).completion?(.removed, nil)
        try expect(store.state.profiles.map(\.id) == [unreviewed, assigned] && store.defaultProfileID == assigned,
                   "Removing the Default leaves the survivor as Default")
        print("Profile removal controller: \(assertions) assertions passed (isolated native-boundary doubles)")
    }
}
