import Foundation

@main @MainActor
struct ProfileRemovalTests {
    struct Failure: Error { let message: String }
    static var assertions = 0
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        assertions += 1
        if try !condition() { throw Failure(message: message) }
    }
    static func rejects(_ operation: () throws -> Void) throws {
        do { try operation() } catch { assertions += 1; return }
        throw Failure(message: "Expected rejection")
    }
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Parc-Profile-Removal-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("session.json")
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        var seed = BrowserState.initial()
        let originalProfile = seed.profiles[0].id, spaceID = seed.activeSpaceID
        let deleting = UUID()
        seed.profiles.append(BrowserProfile(id: deleting, name: "Work"))
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
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(seed).write(to: file)
        let store = try BrowserStore(directory: directory)
        let archivedID = seed.tabs[2].id
        let preview = store.acquireArchivePreview(id: archivedID, profileID: deleting)!
        try rejects { _ = try store.stageProfileRemoval(deleting, expectedName: "Work") }
        try rejects { _ = try store.stageUnusedProfileRemovals([seed.profiles[1]]) }
        try expect(store.state.profileRemovals.isEmpty, "Preview lease prevents single and bulk staging")
        store.releaseArchivePreview(preview)
        try expect(store.defaultProfileID == originalProfile, "Legacy default resolves to the original Profile")
        try store.saveProfileName(originalProfile, expectedName: "Default", name: "Renamed Default")
        try rejects { _ = try store.profileRemovalSummary(originalProfile) }
        try rejects { _ = try store.validateProfileRemoval(deleting, expectedName: "Other") }
        let summary = try store.validateProfileRemoval(deleting, expectedName: "Work")
        try expect(summary.savedTabCount == 2 && summary.historyEntryCount == 1, "Confirmation reports actual source records")
        var originalOwner: ProfileWriteReservation? = store.reserveProfileWrite(deleting)!
        var pendingWrite: CheckedContinuation<Void, Never>?
        let write = Task { [reservation = originalOwner!] in await reservation.perform {
            await withCheckedContinuation { pendingWrite = $0 }
            return 1
        } }
        originalOwner = nil
        while pendingWrite == nil { await Task.yield() }
        try rejects { _ = try store.stageProfileRemoval(deleting, expectedName: "Work") }
        pendingWrite?.resume(); let written = await write.value
        try expect(written == 1, "Completed write releases its reservation")
        let failing = store.reserveProfileWrite(deleting)!
        var writeFailed = false
        do { try await failing.perform { throw Failure(message: "injected write failure") } }
        catch { writeFailed = true }
        try expect(writeFailed, "Write failure is propagated after releasing its reservation")
        try expect(store.reserveProfileWrite(UUID()) == nil, "Unknown parent cannot reserve a write")
        var deferredAssignmentGate: (() -> Bool)?
        var deferredAssignmentCompletion: ((Bool) -> Void)?
        store.requestPageRetirement = { _, gate, completion in
            deferredAssignmentGate = gate
            deferredAssignmentCompletion = completion
        }
        store.assignProfile(deleting, toSpace: spaceID)
        try expect(deferredAssignmentGate != nil, "Assignment waits for native retirement approval")
        let record = try store.stageProfileRemoval(deleting, expectedName: "Work")
        try expect(store.state.profiles.contains { $0.id == deleting }, "Staging cannot publish deletion")
        try expect(store.isProfileRemovalPending(deleting), "Staging blocks reuse")
        try expect(store.reserveProfileWrite(deleting) == nil, "Staged removal refuses a new Library write")
        try expect(deferredAssignmentGate?() == false, "Pending removal revokes a preexisting reassignment before native close")
        deferredAssignmentCompletion?(false)
        store.requestPageRetirement = nil
        try rejects { _ = try store.stageProfileRemoval(deleting, expectedName: "Work") }
        store.assignProfile(deleting, toSpace: spaceID)
        try expect(store.state.spaces[0].profileID == originalProfile, "Pending profile cannot be reassigned")
        try rejects { try store.saveProfileName(deleting, expectedName: "Work", name: "Other") }
        let restarted = try BrowserStore(directory: directory)
        try expect(restarted.state.profileRemovals == [record] && restarted.isProfileRemovalPending(deleting), "Pending operation survives restart")
        try restarted.cancelProfileRemoval(record)
        try expect(!restarted.isProfileRemovalPending(deleting) && restarted.state.tabs.count == 3, "Cancellation preserves records")
        let retry = try restarted.stageProfileRemoval(deleting, expectedName: "Work")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        try rejects { try restarted.finishProfileRemoval(retry) }
        try expect(restarted.isProfileRemovalPending(deleting) && restarted.state.profiles.count == 2,
                   "Final write failure retains durable transaction and blocked profile")
        try FileManager.default.removeItem(at: file)
        try restarted.finishProfileRemoval(retry)
        try expect(restarted.state.profiles.map(\.id) == [originalProfile], "Completion removes only selected profile")
        try expect(restarted.state.tabs.map(\.id) == [seed.tabs[0].id] && restarted.state.spaces == seed.spaces,
                   "Completion preserves other tabs and every Space")
        try expect(restarted.state.history.count == 1 && restarted.state.history[0].profileID == originalProfile,
                   "Completion removes only source history")
        try expect(restarted.state.downloads.isEmpty && FileManager.default.fileExists(atPath: download.path),
                   "Download files survive metadata removal")
        try expect(restarted.state.settings.settingsProfileID == originalProfile && restarted.state.profileRemovals.isEmpty,
                   "Completion repairs Settings selection and clears transaction")
        let final = try BrowserStore(directory: directory)
        try expect(final.state.profiles.count == 1 && final.defaultProfileID == originalProfile, "Removing another Profile keeps Default in place")
        let firstUnused = final.createProfile(name: "Personal")
        let secondUnused = final.createProfile(name: "Research")
        let reviewed = final.unusedProfilesForRemoval
        try expect(reviewed.map(\.id) == [firstUnused, secondUnused], "Bulk candidates exclude the Default while a Space uses it")
        try rejects { _ = try final.stageUnusedProfileRemovals([]) }
        try rejects { _ = try final.stageUnusedProfileRemovals([reviewed[0], reviewed[0]]) }
        try rejects { _ = try final.stageUnusedProfileRemovals([final.state.profiles[0]]) }
        try final.saveProfileName(secondUnused, expectedName: "Research", name: "Reference")
        try rejects { _ = try final.stageUnusedProfileRemovals(reviewed) }
        try expect(final.state.profileRemovals.isEmpty, "One stale name rejects every new target before staging")
        let currentReview = final.unusedProfilesForRemoval
        let bulkWrite = final.reserveProfileWrite(firstUnused)!
        try rejects { _ = try final.stageUnusedProfileRemovals(currentReview) }
        try expect(final.state.profileRemovals.isEmpty, "A reserved write refuses the whole bulk removal")
        bulkWrite.finish(); bulkWrite.finish()
        let newAfterReview = final.createProfile(name: "Created after review")
        try final.saveSettingsSelection(pane: "Profiles", profileID: firstUnused)
        let beforeBulk = final.state
        let savedBeforeBulk = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        try rejects { _ = try final.stageUnusedProfileRemovals(currentReview) }
        try expect(final.state == beforeBulk && final.state.profileRemovals.isEmpty,
                   "Failed bulk staging publishes no partial authorization or removal")
        try FileManager.default.removeItem(at: file)
        try savedBeforeBulk.write(to: file)
        let bulk = try final.stageUnusedProfileRemovals(currentReview)
        try expect(bulk.map(\.profileID) == [firstUnused, secondUnused] && Set(bulk.map(\.id)).count == 2,
                   "Bulk staging binds separate operation UUIDs to the reviewed identities")
        try expect(final.state.profiles.count == 4 && !final.isProfileRemovalPending(newAfterReview),
                   "Staging deletes nothing and never includes a newly created profile")
        try expect(final.unusedProfilesForRemoval.map(\.id) == [newAfterReview], "Pending removals are not offered a second time")
        let bulkRestart = try BrowserStore(directory: directory)
        try expect(bulkRestart.state.profileRemovals == bulk, "The entire authorization set survives restart")
        try bulkRestart.finishProfileRemoval(bulk[0])
        try expect(bulkRestart.state.profileRemovals == [bulk[1]] && bulkRestart.isProfileRemovalPending(secondUnused),
                   "One completed receipt leaves the other original operation recoverable")
        try bulkRestart.cancelProfileRemoval(bulk[1])
        try expect(bulkRestart.state.profiles.map(\.id) == [originalProfile, secondUnused, newAfterReview],
                   "Independent cancellation preserves the unsuccessful and unreviewed profiles")
        let legacy = try JSONDecoder().decode(ProfileRemovalRecord.self, from: Data(
            #"{"id":"\#(UUID().uuidString)","profileID":"\#(secondUnused.uuidString)","profileName":"Research"}"#.utf8))
        try expect(legacy.fallbackProfileID == nil && bulkRestart.fallbackProfileID(for: legacy) == originalProfile,
                   "Records saved before fallbacks were recorded use the Default Profile")
        let space = bulkRestart.state.activeSpaceID
        bulkRestart.assignProfile(secondUnused, toSpace: space)
        try expect(bulkRestart.state.spaces.allSatisfy { $0.profileID == secondUnused }, "Default loses its last Space")
        try bulkRestart.saveSettingsSelection(pane: "Profiles", profileID: originalProfile)
        let defaultSummary = try bulkRestart.validateProfileRemoval(originalProfile, expectedName: "Renamed Default")
        try expect(defaultSummary.profile.id == originalProfile, "The Default Profile is deletable once unused")
        let defaultRecord = try bulkRestart.stageProfileRemoval(originalProfile, expectedName: "Renamed Default")
        try expect(defaultRecord.fallbackProfileID == secondUnused && bulkRestart.defaultProfileID == secondUnused
                   && bulkRestart.state.settings.settingsProfileID == secondUnused,
                   "Staging records the surviving Profile and moves Default and Settings to it in the same save")
        let pendingRestart = try BrowserStore(directory: directory)
        try expect(pendingRestart.state.profileRemovals == [defaultRecord] && pendingRestart.defaultProfileID == secondUnused,
                   "A pending Default removal survives restart with its recorded survivor")
        try pendingRestart.finishProfileRemoval(defaultRecord)
        try expect(!pendingRestart.state.profiles.contains { $0.id == originalProfile } && pendingRestart.defaultProfileID == secondUnused,
                   "Completing the removal leaves the survivor as Default")
        try expect(try BrowserStore(directory: directory).defaultProfileID == secondUnused, "The new Default survives reload")
        print("Profile removal model: \(assertions) assertions passed")
    }
}
