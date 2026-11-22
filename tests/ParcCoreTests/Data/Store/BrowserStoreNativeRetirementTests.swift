import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreNativeRetirementTests {
    @MainActor
    private static func withOverduePages(
        _ body: (BrowserStore, UUID, UUID) throws -> Void
    ) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let first = store.open("https://example.org/first-old-page")
            let second = store.open("https://example.org/second-old-page")
            _ = store.open("https://example.org/current-page")
            _ = store.archiveExpiredTabs()
            now.addTimeInterval(13 * 60 * 60)
            try body(store, first, second)
        }
    }

    @Test @MainActor static func addingProtectionInAnotherWindowCancelsTheWholeArchiveBeforeUnload() throws {
        try withOverduePages { store, first, second in
            var requests: [(Set<UUID>, () -> Bool, (Bool) -> Void)] = []
            var results: [[UUID]] = []
            var currentProtection = Set<UUID>()
            var unloads = 0
            store.requestPageRetirement = { ids, validate, completion in requests.append((ids, validate, completion)) }
            store.archiveExpiredTabs(protectedTabIDs: [], currentProtection: { currentProtection }) { results.append($0) }
            #expect(requests[0].0.isSuperset(of: [first, second]), "The native archive preflight must cover both overdue pages")
            currentProtection.insert(first)
            let permitted = requests[0].1()
            if permitted { unloads += requests[0].0.count }
            requests[0].2(permitted)
            #expect(!permitted && unloads == 0 && results == [[]], "Protection added in another window must cancel the whole group before any native unload")
            #expect([first, second].allSatisfy { id in store.state.tabs.contains { $0.id == id && $0.archivedAt == nil } }, "A cancelled archive group must preserve every saved live page")
        }
    }

    @Test @MainActor static func selectingOneOverduePageCancelsTheWholeArchiveBeforeUnload() throws {
        try withOverduePages { store, first, second in
            var requests: [(Set<UUID>, () -> Bool, (Bool) -> Void)] = []
            var results: [[UUID]] = []
            store.requestPageRetirement = { ids, validate, completion in requests.append((ids, validate, completion)) }
            store.archiveExpiredTabs(protectedTabIDs: []) { results.append($0) }
            store.selectTab(first)
            #expect(!requests[0].1(), "Selecting an overdue tab while consent is pending must refuse before unload")
            requests[0].2(false)
            let retained = try BrowserStoreTestsSupport.tab(second, in: store)
            #expect(results == [[]] && retained.archivedAt == nil, "Selecting one member cancels the complete automatic archive transaction")
        }
    }

    @Test @MainActor static func changingArchivePolicyWhileConsentIsPendingCancelsTheArchive() throws {
        try withOverduePages { store, _, _ in
            var requests: [(Set<UUID>, () -> Bool, (Bool) -> Void)] = []
            var results: [[UUID]] = []
            store.requestPageRetirement = { ids, validate, completion in requests.append((ids, validate, completion)) }
            store.archiveExpiredTabs(protectedTabIDs: []) { results.append($0) }
            _ = store.setAutoArchiveInterval(.thirtyDays, for: store.activeSpace.profileID)
            #expect(!requests[0].1(), "Changing archive policy during approval must preserve actual pages")
            requests[0].2(false)
            #expect(results == [[]] && store.retiringTabIDs.isEmpty, "Policy cancellation must finish once and clear reservations")
        }
    }

    @Test @MainActor static func reenteringFromNativeProtectionLetsTheReplacementRetirementWin() throws {
        try withOverduePages { store, first, second in
            var requests: [(Set<UUID>, () -> Bool, (Bool) -> Void)] = []
            var results: [[UUID]] = []
            store.requestPageRetirement = { ids, validate, completion in requests.append((ids, validate, completion)) }
            var replaceDuringValidation = false
            store.archiveExpiredTabs(protectedTabIDs: [], currentProtection: {
                if replaceDuringValidation {
                    replaceDuringValidation = false
                    store.closeTab(first)
                }
                return []
            }) { results.append($0) }
            replaceDuringValidation = true
            #expect(!requests[0].1() && requests.count == 2, "Native protection callback reentry must invalidate an older transaction before unload")
            requests[0].2(false)
            #expect(store.retiringTabIDs == [first] && results.count == 1, "Reentrant replacement must keep its own page reservation when the archive is cancelled")
            #expect(requests[1].1(), "The reentrant close retains its own pre-unload validation")
            requests[1].2(true)
            let retired = try BrowserStoreTestsSupport.tab(first, in: store)
            let retained = try BrowserStoreTestsSupport.tab(second, in: store)
            #expect(retired.archivedAt != nil && retained.archivedAt == nil, "Only the replacement manual close may retire a page after cancelling the older group")
        }
    }

    @Test @MainActor static func newPagesInvalidateAProfileReassignmentBeforeUnload() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/original-profile")
            let originalProfile = store.activeSpace.profileID
            let spaceID = store.activeSpaceID
            let otherProfile = store.createProfile(name: "Second profile")
            var requests: [(() -> Bool, (Bool) -> Void)] = []
            store.requestPageRetirement = { _, validate, completion in requests.append((validate, completion)) }
            store.assignProfile(otherProfile, toSpace: spaceID)
            let added = store.open("https://example.org/created-during-consent")
            #expect(!requests[0].0(), "A newly created page must invalidate the profile-wide preflight before any page unloads")
            requests[0].1(false)
            #expect(store.activeSpace.profileID == originalProfile && [id, added].allSatisfy { id in
                store.state.tabs.contains { $0.id == id && $0.profileID == originalProfile && $0.archivedAt == nil }
            }, "Cancelled reassignment must preserve all original page ownership")
        }
    }

    @Test @MainActor static func aRemovedDestinationInvalidatesTheMoveBeforeUnload() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/original-profile")
            let originalProfile = store.activeSpace.profileID
            let spaceID = store.activeSpaceID
            let otherProfile = store.createProfile(name: "Second profile")
            var requests: [(() -> Bool, (Bool) -> Void)] = []
            store.requestPageRetirement = { _, validate, completion in requests.append((validate, completion)) }
            let destination = store.createSpace(name: "Destination")
            store.assignProfile(otherProfile, toSpace: destination)
            let folder = store.createFolder(name: "Destination folder")
            store.moveTab(id, toSpace: destination, folderID: folder)
            let moveRequest = requests.last!
            let deletion = FolderRemovalTarget(folderID: folder, spaceID: destination, profileID: store.activeSpace.profileID, state: store.state)!
            store.deleteFolder(deletion, shouldCommit: { true }) { _ in }
            #expect(!moveRequest.0(), "A removed move destination must be rejected before native page unload")
            moveRequest.1(false)
            #expect(try (try BrowserStoreTestsSupport.tab(id, in: store)).spaceID == spaceID && (try BrowserStoreTestsSupport.tab(id, in: store)).profileID == originalProfile, "Invalid move destination must preserve the original page and profile")
        }
    }
}
