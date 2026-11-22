import Combine
import Foundation
import Testing
@testable import ParcCore

@MainActor
struct BrowserStoreArchiveActivityTests {
    @Test static func visibleActivityKeepsAnInactiveTabFromExpiringImmediately() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.setAutoArchiveInterval(.twentyFourHours, for: store.activeSpace.profileID)
            store.archiveExpiredTabs()
            let viewed = store.open("https://viewed.example")
            now.addTimeInterval(48 * 3600)
            store.refreshVisibleTabs([viewed, UUID()])
            let lastViewed = now
            _ = store.open("https://next.example")
            #expect(try store.archiveExpiredTabs().isEmpty && (try BrowserStoreTestsSupport.tab(viewed, in: store)).lastAccessed == lastViewed, "Periodic visible-page refresh must prevent a long-viewed page from expiring immediately after switching away")
        }
    }

    @Test static func theInactivityThresholdMustBeStrictlyExceeded() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.setAutoArchiveInterval(.twentyFourHours, for: store.activeSpace.profileID)
            store.archiveExpiredTabs()
            let viewed = store.open("https://viewed.example")
            now.addTimeInterval(48 * 3600)
            store.refreshVisibleTabs([viewed, UUID()])
            let lastViewed = now
            _ = store.open("https://next.example")
            try #require(try store.archiveExpiredTabs().isEmpty && (try BrowserStoreTestsSupport.tab(viewed, in: store)).lastAccessed == lastViewed, "Periodic visible-page refresh must prevent a long-viewed page from expiring immediately after switching away")
            now.addTimeInterval(24 * 3600)
            #expect(store.archiveExpiredTabs().isEmpty, "A tab at exactly the configured inactivity threshold must remain")
            now.addTimeInterval(1)
            #expect(store.archiveExpiredTabs() == [viewed], "A formerly visible page must expire after a full interval without another refresh")
        }
    }

    @Test static func restoringAnAutomaticallyArchivedTabSelectsItAndRestartsItsTimer() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.setAutoArchiveInterval(.twentyFourHours, for: store.activeSpace.profileID)
            store.archiveExpiredTabs()
            let viewed = store.open("https://viewed.example")
            now.addTimeInterval(48 * 3600)
            store.refreshVisibleTabs([viewed, UUID()])
            let lastViewed = now
            let next = store.open("https://next.example")
            try #require(try store.archiveExpiredTabs().isEmpty && (try BrowserStoreTestsSupport.tab(viewed, in: store)).lastAccessed == lastViewed, "Periodic visible-page refresh must prevent a long-viewed page from expiring immediately after switching away")
            now.addTimeInterval(24 * 3600)
            try #require(store.archiveExpiredTabs().isEmpty, "A tab at exactly the configured inactivity threshold must remain")
            now.addTimeInterval(1)
            try #require(store.archiveExpiredTabs() == [viewed], "A formerly visible page must expire after a full interval without another refresh")
            store.restoreArchivedTab(viewed, destination: .previousSpace(fallbackSpaceID: nil))
            #expect(try store.selectedTabID == viewed && (try BrowserStoreTestsSupport.tab(viewed, in: store)).lastAccessed == now, "Restoring an automatically archived page must reset its activity and select it")
            store.selectTab(next)
            now.addTimeInterval(12 * 3600)
            #expect(store.archiveExpiredTabs().isEmpty, "A restored page must get a fresh full inactivity interval")
        }
    }

    @Test static func visibleActivityPersistsWithoutPublishing() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.archiveExpiredTabs()
            let viewed = store.open("https://activity-only.example")
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }
            let revision = store.stateRevision
            now.addTimeInterval(60)
            store.refreshVisibleTabs([viewed])
            #expect(publications == 0 && store.stateRevision == revision, "Activity-only lastAccessed stamps must not publish BrowserState or bump stateRevision")
            #expect((try BrowserStoreTestsSupport.tab(viewed, in: store)).lastAccessed == now, "In-memory lastAccessed must still advance for archive eligibility")
            try store.save()
            let reopened = try BrowserStore(directory: directory, now: { now })
            #expect((try BrowserStoreTestsSupport.tab(viewed, in: reopened)).lastAccessed == now, "Activity-only stamps must still persist into the session file")
            let afterPublish = publications
            now.addTimeInterval(1)
            store.selectTab(viewed)
            #expect(publications > afterPublish, "A real selection publish must still emit after an activity-only stamp")
            #expect((try BrowserStoreTestsSupport.tab(viewed, in: store)).lastAccessed == now, "Publishing after an activity overlay must keep the stamped access date")
        }
    }

    @Test static func openingATabSelectsItInOnePublication() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 2_000_000_000) })
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }

            let first = store.openResolvedURL(URL(string: "https://batch.example/a")!, kind: .today)
            #expect(publications == 1, "Opening a URL publishes once after append+place+select")
            #expect(store.state.selectedTabIDs == [first], "Open selects the new tab")
        }
    }

    @Test static func openingASecondTabAlsoPublishesOnce() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 2_000_000_000) })
            _ = store.openResolvedURL(URL(string: "https://batch.example/a")!, kind: .today)
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }

            _ = store.openResolvedURL(URL(string: "https://batch.example/b")!, kind: .today)
            #expect(publications == 1, "A second open also publishes once")
        }
    }

    @Test static func formingASplitPublishesOneActivation() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 2_000_000_000) })
            let first = store.openResolvedURL(URL(string: "https://batch.example/a")!, kind: .today)
            let second = store.openResolvedURL(URL(string: "https://batch.example/b")!, kind: .today)
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }
            store.setSplit([first, second])
            #expect(publications == 1, "Forming a split publishes once after activate+stamp")
            #expect(store.state.selectedTabIDs == [first, second] && store.activeSplitLayout?.tabIDs == [first, second], "Split end state matches a single activation")
        }
    }

    @Test static func closingASplitPublishesOnceAndKeepsTheFocusedPane() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 2_000_000_000) })
            let first = store.openResolvedURL(URL(string: "https://batch.example/a")!, kind: .today)
            let second = store.openResolvedURL(URL(string: "https://batch.example/b")!, kind: .today)
            store.setSplit([first, second])
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }
            store.closeSplit()
            #expect(publications == 1, "Closing a split publishes once after dissolve+stamp")
            #expect(store.state.selectedTabIDs == [first] && store.activeSplitLayout == nil, "Close-split end state keeps the focused pane alone")
        }
    }

    @Test static func creatingASpacePublishesItsSelectionOnce() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 2_000_000_000) })
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }

            let space = store.createSpace(name: "Batched")
            #expect(publications == 1, "Creating a Space publishes once after append+select")
            #expect(store.activeSpaceID == space, "Create selects the new Space")
        }
    }

    @Test static func removingATabPublishesItsRemovalOnce() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 2_000_000_000) })
            let other = store.openResolvedURL(URL(string: "https://batch.example/c")!, kind: .today)
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }

            store.removeTab(other)
            #expect(publications == 1, "Removing a tab publishes once after normalize+stamp")
            #expect(!store.state.tabs.contains { $0.id == other }, "Removed tab is gone from the model")
        }
    }

    @Test static func identicalStateAssignDoesNotPublish() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_100)
            let store = try BrowserStore(directory: directory, now: { now })
            store.archiveExpiredTabs()
            let id = store.open("https://identical-assign.example")
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }
            store.updateTab(id, title: "Once", url: "https://identical-assign.example/once")
            #expect(publications == 1, "Distinct metadata publishes once; changed() does not republish")
            let revision = store.stateRevision
            now.addTimeInterval(60)
            store.refreshVisibleTabs([id])
            #expect(publications == 1 && store.stateRevision == revision, "Activity overlay must still avoid publish after an identical-assign gate")
            store.selectTab(id)
            #expect(publications == 1 && store.stateRevision == revision, "Identical selectTab assign must not fan out @Published observers")
            #expect((try BrowserStoreTestsSupport.tab(id, in: store)).lastAccessed == now, "Activity overlay must remain readable across identical assigns")
        }
    }

    @Test static func unreadAndNativeProtectionGates() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.archiveExpiredTabs()
            let unread = store.open("https://unread.example")
            let protected = store.open("https://media-or-edit.example")
            let ordinary = store.open("https://ordinary.example")
            let selected = store.open("https://selected.example")
            var fixture = store.state
            fixture.tabs[fixture.tabs.firstIndex { $0.id == unread }!].isUnread = true
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(fixture).write(to: directory.appendingPathComponent("session.json"))
            now.addTimeInterval(13 * 3600)
            let loaded = try BrowserStore(directory: directory, now: { now })
            #expect(loaded.archiveExpiredTabs(protectedTabIDs: [protected]) == [ordinary], "Unread pages, native-protected or unknown-content pages, and current selection must survive an otherwise eligible sweep")
            loaded.refreshVisibleTabs([unread])
            #expect(try BrowserStoreTestsSupport.tab(unread, in: loaded).isUnread, "The timer must not invent an unread-clear action; explicit selection owns it")
            loaded.selectTab(unread)
            #expect(!(try BrowserStoreTestsSupport.tab(unread, in: loaded).isUnread), "Selecting a page must clear persisted unread state")
            loaded.selectTab(selected)
            try loaded.save()
            let restored = try BrowserStore(directory: directory, now: { now })
            #expect(!(try BrowserStoreTestsSupport.tab(unread, in: restored).isUnread), "Read state must survive restart")
            now.addTimeInterval(12 * 3600 + 1)
            let expired = Set(restored.archiveExpiredTabs())
            #expect(expired == [unread, protected], "Read and formerly protected pages must become eligible once no protection remains and activity is old")
        }
    }
}
