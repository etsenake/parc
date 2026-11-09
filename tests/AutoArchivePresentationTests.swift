import Foundation

/// Real file-backed model transactions; no window, native engine or browser.
@main @MainActor
struct AutoArchivePresentationTests {
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
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Parc-AutoArchive-Presentation-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try BrowserStore(directory: directory, now: { now })
        try expect(!store.state.autoArchiveEducationEligible, "An absent key does not invent new-user eligibility")
        let first = store.activeSpace.profileID
        try expect(try store.changeAutoArchiveInterval(.twentyFourHours, for: first) == nil, "One Profile has no scope sheet")
        let second = store.createProfile(name: "Work")
        let change = try store.changeAutoArchiveInterval(.sevenDays, for: first)!
        try expect(store.autoArchiveInterval(for: first) == .sevenDays && store.autoArchiveInterval(for: second) == .twentyFourHours,
                   "Only the original selected Profile changes before the scope decision")
        let reopened = try BrowserStore(directory: directory)
        try expect(reopened.autoArchiveInterval(for: first) == .sevenDays, "Current Profile is durably saved before the sheet")
        try store.applyAutoArchiveIntervalToAllProfiles(change)
        try expect(store.state.profiles.allSatisfy { $0.autoArchiveHours == 168 }, "All Profiles commits the reviewed set")
        try expect(store.state.autoArchiveDefaultHours == 168, "All Profiles updates the missing-Profile fallback too")
        try expect(try store.changeAutoArchiveInterval(.sevenDays, for: second) == nil, "Unchanged interval does not open a sheet")
        let stale = try store.changeAutoArchiveInterval(.thirtyDays, for: second)!
        let later = store.createProfile(name: "Created later")
        try expect(store.autoArchiveInterval(for: later) == .sevenDays, "A new Profile uses the explicit global default")
        try rejects { try store.applyAutoArchiveIntervalToAllProfiles(stale) }
        try expect(store.autoArchiveInterval(for: first) == .sevenDays, "A retained All callback cannot add a later Profile")
        let renamed = try store.changeAutoArchiveInterval(.twentyFourHours, for: second)!
        try store.saveProfileName(second, expectedName: "Work", name: "Renamed")
        try rejects { try store.applyAutoArchiveIntervalToAllProfiles(renamed) }
        let file = directory.appendingPathComponent("session.json")
        let before = store.state
        let bytes = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        try rejects { _ = try store.changeAutoArchiveInterval(.twelveHours, for: second) }
        try expect(store.state == before, "Failed atomic save preserves every published interval")
        try FileManager.default.removeItem(at: file); try bytes.write(to: file)
        try expect(try store.changeAutoArchiveInterval(.sevenDays, for: second) == nil, "Converging to a shared interval needs no scope sheet")
        try expect(store.setAutoArchiveInterval(.twelveHours, for: first), "Restore short interval for education boundary")
        let draft = OnboardingDraft(spaceID: store.activeSpaceID, spaceName: store.activeSpace.name,
                                    theme: store.activeSpace.theme, favoriteURLs: [])
        try store.completeOnboarding(draft)
        try expect(store.state.autoArchiveEducationEligible, "First local setup arms account-free new-user education")
        try expect(store.archiveExpiredTabs().isEmpty && !store.autoArchiveEducationPending,
                   "Initializing the start gate cannot claim archival or show education")
        let old = store.open("https://old.example")
        _ = store.open("https://selected.example")
        now.addTimeInterval(12 * 3600 + 1)
        store.requestPageRetirement = { _, _, complete in complete(false) }
        var refused: [UUID] = []
        store.archiveExpiredTabs(protectedTabIDs: []) { refused = $0 }
        try expect(refused.isEmpty && !store.autoArchiveEducationPending && store.state.autoArchiveEducationEligible,
                   "Native refusal cannot consume education or report cleaned tabs")
        store.requestPageRetirement = nil
        store.sidebarBannerOccupied = { true }
        try expect(store.archiveExpiredTabs() == [old] && !store.autoArchiveEducationPending && store.state.autoArchiveEducationEligible,
                   "Another banner in the shared slot leaves education armed")
        store.sidebarBannerOccupied = { false }
        let next = store.open("https://later.example")
        _ = store.open("https://selected-again.example")
        now.addTimeInterval(12 * 3600 + 1)
        try expect(store.archiveExpiredTabs().contains(next), "An accepted actual automatic close produces education")
        try expect(store.autoArchiveEducationPending && !store.state.autoArchiveEducationEligible, "Eligibility is consumed before presentation")
        store.dismissAutoArchiveEducation()
        try expect(!store.autoArchiveEducationPending, "Explicit dismissal clears the shared transient banner")
        _ = store.open("https://next.example")
        now.addTimeInterval(12 * 3600 + 1)
        _ = store.archiveExpiredTabs()
        try expect(!store.autoArchiveEducationPending, "Later automatic closes do not repeat one-time education")
        try store.save()
        let restarted = try BrowserStore(directory: directory, now: { now })
        try expect(!restarted.state.autoArchiveEducationEligible && !restarted.autoArchiveEducationPending,
                   "The consumed marker survives reload while transient presentation does not")
        try restarted.completeOnboarding(draft)
        try expect(!restarted.state.autoArchiveEducationEligible, "Replaying setup cannot rearm consumed education")
        let custom = try BrowserStore(directory: directory.appendingPathComponent("custom"))
        try custom.completeOnboarding(.init(spaceID: custom.activeSpaceID, spaceName: custom.activeSpace.name,
                                            theme: custom.activeSpace.theme, favoriteURLs: []))
        _ = try custom.changeAutoArchiveInterval(.twentyFourHours, for: custom.activeSpace.profileID)
        try expect(!custom.state.autoArchiveEducationEligible, "Custom interval disarms the recovered fixed-12-hour education")
        print("Automatic archive presentation: \(assertions) assertions passed")
    }
}
