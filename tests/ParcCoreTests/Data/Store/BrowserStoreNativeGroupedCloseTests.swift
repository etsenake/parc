import Combine
import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreNativeGroupedCloseTests {
    @Test @MainActor static func aWindowCommandUsesOnlyItsOwnSelectionAndPreservesTheOutgoingWindow() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let firstSpace = store.activeSpaceID
            let first = store.open("https://example.org/window-one")
            let cached = store.open("https://example.org/cached-other-window")
            let cachedBefore = try BrowserStoreTestsSupport.tab(cached, in: store)
            let secondSpace = store.createSpace(name: "Second window")
            let other = store.open("https://example.org/window-two")
            var snapshots: [BrowserState] = []
            let subscription = store.statePublisher.sink { snapshots.append($0) }
            defer { subscription.cancel() }
            now.addTimeInterval(60)
            #expect(store.setWindowPresentation(spaceID: firstSpace, selectedTabIDs: [first, first, other, UUID()]), "A known window Space must provide its command context")
            #expect(store.selectedTabID == first && store.state.selectedTabIDs == [first], "Window context must deduplicate and exclude pages outside its Space")
            #expect(try BrowserStoreTestsSupport.tab(cached, in: store) == cachedBefore, "Switching window context must not stamp another window's cached selection")
            #expect(try BrowserStoreTestsSupport.tab(first, in: store).lastAccessed == now, "Only the initiating window's supplied selection gets an activity stamp")
            #expect(snapshots.dropFirst().allSatisfy { $0.activeSpaceID == firstSpace && $0.selectedTabIDs == [first] }, "Window context publication must keep Space and page selection consistent")
            #expect(store.state.selectionBySpace[secondSpace.uuidString] == [other], "Switching command context must retain the outgoing saved selection")
        }
    }

    @Test @MainActor static func anEmptyWindowSelectionDoesNotRestoreItsCachedPage() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstSpace = store.activeSpaceID
            _ = store.open("https://example.org/window-one")
            _ = store.createSpace(name: "Second window")
            store.setWindowPresentation(spaceID: firstSpace, selectedTabIDs: [])
            #expect(store.state.selectedTabIDs.isEmpty, "An intentionally empty native window must not restore a cached fallback page")
        }
    }

    @Test @MainActor static func anUnknownWindowSpaceLeavesTheSessionUntouched() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://example.org/window-one")
            let before = store.state
            #expect(!store.setWindowPresentation(spaceID: UUID(), selectedTabIDs: [first]) && store.state == before, "An invalid window Space must leave the model unchanged")
        }
    }

    @Test @MainActor static func pendingGroupedCloseSavesAllPagesUntilConsent() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://example.org/first-form")
            let second = store.open("https://example.org/second-form")
            _ = store.open("https://example.org/keep")
            store.selectTab(first)
            let ids: Set<UUID> = [first, second]
            var decisions: [(Set<UUID>, (Bool) -> Void)] = []
            var results: [Bool] = []
            store.requestPageRetirement = { requested, validate, callback in decisions.append((requested, { callback($0 && validate()) })) }
            store.closeTabs(ids) { results.append($0) }
            #expect(decisions.count == 1 && decisions[0].0 == ids && store.retiringTabIDs == ids, "Grouped close must reserve all records in one native retirement request")
            #expect(results.isEmpty && ids.allSatisfy { id in store.state.tabs.contains { $0.id == id && $0.archivedAt == nil } }, "No group member may archive before the aggregate decision")
            try store.save()
            let pending = try BrowserStore(directory: directory)
            #expect(ids.allSatisfy { id in pending.state.tabs.contains { $0.id == id && $0.archivedAt == nil } }, "Saving a pending group must retain every page")
        }
    }

    @Test @MainActor static func refusedGroupedClosePublishesNothing() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://example.org/first-form")
            let second = store.open("https://example.org/second-form")
            _ = store.open("https://example.org/keep")
            store.selectTab(first)
            let ids: Set<UUID> = [first, second]
            var decisions: [(Set<UUID>, (Bool) -> Void)] = []
            var results: [Bool] = []
            var snapshots: [BrowserState] = []
            let subscription = store.statePublisher.sink { snapshots.append($0) }
            defer { subscription.cancel() }
            store.requestPageRetirement = { requested, validate, callback in decisions.append((requested, { callback($0 && validate()) })) }
            store.closeTabs(ids) { results.append($0) }
            decisions.removeFirst().1(false)
            #expect(results == [false] && store.retiringTabIDs.isEmpty && snapshots.count == 1, "A refused group must report once and publish no partial closure")
        }
    }

    @Test @MainActor static func approvedGroupedCloseArchivesAllPagesInOnePublication() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://example.org/first-form")
            let second = store.open("https://example.org/second-form")
            let survivor = store.open("https://example.org/keep")
            store.selectTab(first)
            let ids: Set<UUID> = [first, second]
            var decisions: [(Set<UUID>, (Bool) -> Void)] = []
            var results: [Bool] = []
            var snapshots: [BrowserState] = []
            let subscription = store.statePublisher.sink { snapshots.append($0) }
            defer { subscription.cancel() }
            store.requestPageRetirement = { requested, validate, callback in decisions.append((requested, { callback($0 && validate()) })) }
            store.closeTabs(ids) { results.append($0) }
            decisions.removeFirst().1(true)
            #expect(results == [true] && store.retiringTabIDs.isEmpty, "An approved group must finish only after the native aggregate result")
            #expect(ids.allSatisfy { id in store.state.tabs.contains { $0.id == id && $0.archivedAt != nil } }, "Approved group must archive every requested Today tab")
            #expect(snapshots.dropFirst().allSatisfy { snapshot in
                ids.allSatisfy { id in snapshot.tabs.contains { $0.id == id && $0.archivedAt != nil } }
            }, "Subscribers must never observe one group member closed and another still live")
            #expect(store.selectedTabID == survivor && store.state.recentlyClosedIDs.suffix(2) == [first, second], "Grouped fallback must exclude all retired pages and preserve close history order")
        }
    }

    @Test @MainActor static func anEmptyCloseGroupSucceedsWithoutNativeRetirement() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            var requests = 0
            var results: [Bool] = []
            store.requestPageRetirement = { _, _, _ in requests += 1 }
            store.closeTabs([]) { results.append($0) }
            #expect(results == [true] && requests == 0)
        }
    }

    @Test @MainActor static func automaticArchiveWaitsForNativeConsentAndHonorsRefusal() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let id = store.open("https://example.org/old-form")
            _ = store.open("https://example.org/selected")
            _ = store.archiveExpiredTabs()
            now.addTimeInterval(13 * 60 * 60)
            var decisions: [(Bool) -> Void] = []
            var results: [[UUID]] = []
            store.requestPageRetirement = { _, validate, completion in decisions.append { completion($0 && validate()) } }
            store.archiveExpiredTabs(protectedTabIDs: []) { results.append($0) }
            #expect(try BrowserStoreTestsSupport.tab(id, in: store).archivedAt == nil && results.isEmpty, "Automatic archive must wait for the live page's result")
            decisions.removeFirst()(false)
            #expect(try results == [[]] && (try BrowserStoreTestsSupport.tab(id, in: store)).archivedAt == nil, "Cancelled automatic retirement must report no archive and retain the tab")
        }
    }

    @Test @MainActor static func selectingAnOverdueTabDuringConsentProtectsIt() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let id = store.open("https://example.org/old-form")
            _ = store.open("https://example.org/selected")
            _ = store.archiveExpiredTabs()
            now.addTimeInterval(13 * 60 * 60)
            var decisions: [(Bool) -> Void] = []
            var results: [[UUID]] = []
            store.requestPageRetirement = { _, validate, completion in decisions.append { completion($0 && validate()) } }
            store.archiveExpiredTabs(protectedTabIDs: []) { results.append($0) }
            store.selectTab(id)
            decisions.removeFirst()(true)
            #expect(try results.last == [] && (try BrowserStoreTestsSupport.tab(id, in: store)).archivedAt == nil, "A tab selected during consent must be revalidated and remain unarchived")
        }
    }
}
