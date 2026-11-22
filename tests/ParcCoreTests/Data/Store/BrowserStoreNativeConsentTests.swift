import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreNativeConsentTests {
    @Test @MainActor static func cancellingNativeRetirementRestoresTheLiveRecord() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/form")
            let original = try BrowserStoreTestsSupport.tab(id, in: store)
            store.closeTab(id)
            let expected = try BrowserStoreTestsSupport.tab(id, in: store)
            #expect(store.restoreLiveTab(original, replacing: expected), "Cancelled native retirement must restore its exact saved record")
            #expect(try BrowserStoreTestsSupport.tab(id, in: store) == original && !store.state.recentlyClosedIDs.contains(id), "A cancelled close must not leave its live page in Archive or Recently Closed")
        }
    }

    @Test @MainActor static func aStaleRetirementCancellationCannotOverwriteNewerEdits() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/form")
            let original = try BrowserStoreTestsSupport.tab(id, in: store)
            store.closeTab(id)
            let earlier = try BrowserStoreTestsSupport.tab(id, in: store)
            store.updateTab(id, title: "Newer edit")
            let edited = store.state
            #expect(!store.restoreLiveTab(original, replacing: earlier), "A stale cancellation must not overwrite later edits")
            #expect(store.state == edited, "Rejected rollback must preserve all newer state")
        }
    }

    @Test @MainActor static func aPendingNativeCloseCannotPersistAnArchive() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/unsaved-form")
            let original = try BrowserStoreTestsSupport.tab(id, in: store)
            var decisions: [(Set<UUID>, (Bool) -> Void)] = []
            store.requestPageRetirement = { ids, validate, callback in decisions.append((ids, { callback($0 && validate()) })) }
            store.closeTab(id)
            #expect(try BrowserStoreTestsSupport.tab(id, in: store) == original, "Requesting native close must leave the saved tab unchanged")
            #expect(store.retiringTabIDs == [id] && decisions.count == 1 && decisions[0].0 == [id], "Retirement must identify exactly the page that needs approval")
            try store.save()
            let pending = try BrowserStore(directory: directory)
            #expect(try BrowserStoreTestsSupport.tab(id, in: pending).archivedAt == nil, "Saving during beforeunload must not persist an unapproved archive")
        }
    }

    @Test @MainActor static func refusingNativeCloseClearsTheReservationWithoutChangingTheTab() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/unsaved-form")
            let original = try BrowserStoreTestsSupport.tab(id, in: store)
            var decisions: [(Set<UUID>, (Bool) -> Void)] = []
            store.requestPageRetirement = { ids, validate, callback in decisions.append((ids, { callback($0 && validate()) })) }
            store.closeTab(id)
            decisions.removeFirst().1(false)
            #expect(try BrowserStoreTestsSupport.tab(id, in: store) == original && store.retiringTabIDs.isEmpty, "Cancelling close must retain the record and clear pending retirement")
        }
    }

    @Test @MainActor static func acceptingNativeCloseArchivesTheTab() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/unsaved-form")
            var decisions: [(Set<UUID>, (Bool) -> Void)] = []
            store.requestPageRetirement = { ids, validate, callback in decisions.append((ids, { callback($0 && validate()) })) }
            store.closeTab(id)
            decisions.removeFirst().1(true)
            #expect(try BrowserStoreTestsSupport.tab(id, in: store).archivedAt != nil, "Accepted actual close may archive the saved Today tab")
        }
    }

    @Test @MainActor static func nativeRemovalWaitsForConsentAndPreservesThePageOnRefusal() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/unsaved-form")
            var decisions: [(Set<UUID>, (Bool) -> Void)] = []
            store.requestPageRetirement = { ids, validate, callback in decisions.append((ids, { callback($0 && validate()) })) }
            store.removeTab(id)
            #expect(store.state.tabs.contains(where: { $0.id == id }), "Removing a record must also wait for native page approval")
            decisions.removeFirst().1(false)
            #expect(store.state.tabs.contains(where: { $0.id == id }), "Cancelling removal must preserve the saved page")
        }
    }

    @Test @MainActor static func aCrossProfileMoveWaitsForConsentAndStaysPutOnRefusal() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/unsaved-form")
            let original = try BrowserStoreTestsSupport.tab(id, in: store)
            var decisions: [(Set<UUID>, (Bool) -> Void)] = []
            store.requestPageRetirement = { ids, validate, callback in decisions.append((ids, { callback($0 && validate()) })) }
            let secondSpace = store.createSpace(name: "Other")
            let otherProfile = store.createProfile(name: "Other profile")
            store.assignProfile(otherProfile, toSpace: secondSpace)
            if !decisions.isEmpty { decisions.removeFirst().1(true) }
            store.moveTab(id, toSpace: secondSpace)
            #expect(try BrowserStoreTestsSupport.tab(id, in: store).profileID == original.profileID, "A profile-changing move must not retarget a live document before consent")
            decisions.removeFirst().1(false)
            #expect(try BrowserStoreTestsSupport.tab(id, in: store).spaceID == original.spaceID, "A cancelled profile-changing move must retain the source Space")
        }
    }

    @Test @MainActor static func reassigningASpaceProfileCommitsOnlyAfterNativeConsent() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/unsaved-form")
            let original = try BrowserStoreTestsSupport.tab(id, in: store)
            var decisions: [(Set<UUID>, (Bool) -> Void)] = []
            store.requestPageRetirement = { ids, validate, callback in decisions.append((ids, { callback($0 && validate()) })) }
            let otherProfile = store.createProfile(name: "Other profile")
            store.assignProfile(otherProfile, toSpace: original.spaceID)
            #expect(store.state.spaces.first(where: { $0.id == original.spaceID })?.profileID == original.profileID, "Space profile reassignment must wait before changing its profile")
            decisions.removeFirst().1(true)
            #expect(try BrowserStoreTestsSupport.tab(id, in: store).profileID == otherProfile, "Accepted profile retirement may update saved page ownership")
        }
    }

    @Test @MainActor static func nativeCompletionWithoutValidationCannotArchiveThePage() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/approval-boundary")
            var requests: [(() -> Bool, (Bool) -> Void)] = []
            var results: [Bool] = []
            store.requestPageRetirement = { _, validate, completion in requests.append((validate, completion)) }
            store.closeTabs([id]) { results.append($0) }
            requests[0].1(true)
            #expect(try results == [false] && (try BrowserStoreTestsSupport.tab(id, in: store)).archivedAt == nil, "A native completion that skips pre-unload validation must not mutate saved pages")
            #expect(!requests[0].0(), "Completed retirement validators must never authorize later unload")
        }
    }

    @Test @MainActor static func preUnloadValidationIsSingleUseAndDoesNotArchiveThePage() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/approval-boundary")
            var requests: [(() -> Bool, (Bool) -> Void)] = []
            var results: [Bool] = []
            store.requestPageRetirement = { _, validate, completion in requests.append((validate, completion)) }
            store.closeTabs([id]) { results.append($0) }
            #expect(requests[0].0(), "Current retirement must validate immediately before actual unload")
            #expect(!requests[0].0(), "Pre-unload approval must be single-use")
            #expect((try BrowserStoreTestsSupport.tab(id, in: store)).archivedAt == nil && results.isEmpty, "Validation alone is not evidence that the native page was destroyed")
        }
    }

    @Test @MainActor static func anApprovedCloseCannotBeSupersededAndCommitsOnlyOnce() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/approval-boundary")
            var requests: [(() -> Bool, (Bool) -> Void)] = []
            var results: [Bool] = []
            store.requestPageRetirement = { _, validate, completion in requests.append((validate, completion)) }
            store.closeTabs([id]) { results.append($0) }
            try #require(requests[0].0())
            store.closeTabs([id]) { results.append($0) }
            #expect(requests.count == 1 && results == [false], "A second close must not supersede a transaction already unloading its actual page")
            requests[0].1(true)
            #expect(try results == [false, true] && (try BrowserStoreTestsSupport.tab(id, in: store)).archivedAt != nil, "The validated transaction commits after the real close completion")
            requests[0].1(false)
            requests[0].1(true)
            #expect(results == [false, true] && store.retiringTabIDs.isEmpty, "Repeated native replies must not repeat model publication or completion")
        }
    }

    @Test @MainActor static func staleNativeRetirementRepliesCannotRevokeTheReplacement() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/replaced-close")
            var requests: [(() -> Bool, (Bool) -> Void)] = []
            var results: [Bool] = []
            store.requestPageRetirement = { _, validate, completion in requests.append((validate, completion)) }
            store.closeTabs([id]) { results.append($0) }
            store.removeTab(id)
            #expect(!requests[0].0(), "A superseded preflight must refuse before unloading the page")
            requests[0].1(false)
            #expect(store.retiringTabIDs == [id] && results == [false], "A stale refusal must preserve the newer retirement reservation")
            #expect(requests[1].0(), "The replacement operation must retain its own approval")
            requests[1].1(true)
            #expect(!store.state.tabs.contains { $0.id == id } && store.retiringTabIDs.isEmpty, "Only the current approved operation may remove the page record")
        }
    }
}
