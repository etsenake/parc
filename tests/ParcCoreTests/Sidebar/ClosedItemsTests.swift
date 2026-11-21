import Combine
import Foundation
import Testing
@testable import ParcCore

@MainActor
struct ClosedItemsTests {
    final class ClosedWindow {
        var items: WindowClosedItems

        init(_ items: WindowClosedItems = WindowClosedItems()) { self.items = items }
        convenience init(itemLastActiveDates: [UUID: Date]) { self.init(WindowClosedItems(itemLastActiveDates: itemLastActiveDates)) }

        var itemLastActiveDates: [UUID: Date] { items.itemLastActiveDates }
        func copy() -> ClosedWindow { ClosedWindow(items) }
        func record(_ intent: ClosedItemIntent, in state: BrowserState) { items.record(intent, in: state) }
        func recordSelection(_ ids: [UUID], focusedTabID: UUID?, state: BrowserState, at date: Date) {
            items.recordSelection(ids, focusedTabID: focusedTabID, state: state, at: date)
        }
        func recordPeek(_ peek: ClosedPeekRecord, in state: BrowserState) { items.recordPeek(peek, in: state) }
        func recordFolderDeletion(_ undo: FolderDeletionUndo) { items.recordFolderDeletion(undo) }
        func selected(_ ids: [UUID]) { items.selected(ids) }
        func next(in state: BrowserState) -> ClosedItemRecord? { items.next(in: state) }
        func nextStep(in state: BrowserState, restorable: (FolderDeletionUndo) -> Bool) -> ClosedItemStep? {
            items.nextStep(in: state, restorable: restorable)
        }
        func consume(_ record: ClosedItemRecord) -> Bool { items.consume(record) }
        func consume(stepID: UUID) -> Bool { items.consume(stepID: stepID) }
    }

    @MainActor final class Fixture {
        let directory: URL
        let store: BrowserStore
        let space: UUID
        let profile: UUID
        let first = ClosedWindow()
        let second = ClosedWindow()
        let cache = ClosedWindow()

        init(now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) }) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-reopen-component-" + UUID().uuidString)
            store = try BrowserStore(directory: directory, now: now)
            space = store.activeSpaceID
            profile = store.activeSpace.profileID
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func intent(_ ids: Set<UUID>, focus: UUID? = nil) -> ClosedItemIntent {
            ClosedItemIntent(ids: ids, state: store.state, spaceID: space, profileID: profile, focusedTabID: focus)!
        }

        func close(_ ids: Set<UUID>, focus: UUID? = nil) -> ClosedItemIntent {
            let intent = intent(ids, focus: focus)
            store.closeTabs(ids)
            return intent
        }

        func closeIntoCache(_ ids: Set<UUID>, focus: UUID? = nil) {
            let intent = intent(ids, focus: focus)
            store.closeTabs(ids)
            cache.record(intent, in: store.state)
        }
    }

    @Test func theOriginalWindowRecordsAManualCloseAndOtherWindowsNeverScanSharedHistory() throws {
        let f = try Fixture()
        let a = f.store.open("https://a.test")
        f.first.record(f.close([a]), in: f.store.state)
        #expect(f.first.next(in: f.store.state)?.tabIDs == [a])
        #expect(f.second.next(in: f.store.state) == nil)
    }

    @Test func aSavedCloseWinsOverAnOlderArchiveAndUsesTheOriginalSavedDestination() throws {
        let f = try Fixture()
        let first = ClosedWindow()
        let a = f.store.open("https://a.test")
        first.record(f.close([a]), in: f.store.state)
        let pin = f.store.open("https://saved.test", kind: .pinned)
        f.store.updateTab(pin, title: "Navigated", url: "https://saved.test/next")
        first.record(f.close([pin]), in: f.store.state)
        let saved = try #require(first.next(in: f.store.state))
        #expect(saved.kind == .saved)
        #expect(saved.tabIDs == [pin])
        #expect(saved.tabs[0].url == saved.tabs[0].savedURL)
    }

    @Test func aSavedReopenSelectsTheExactIDAndConsumesItsSlotOnce() throws {
        let f = try Fixture()
        let first = ClosedWindow()
        let a = f.store.open("https://a.test")
        first.record(f.close([a]), in: f.store.state)
        let pin = f.store.open("https://saved.test", kind: .pinned)
        f.store.updateTab(pin, title: "Navigated", url: "https://saved.test/next")
        first.record(f.close([pin]), in: f.store.state)
        let saved = try #require(first.next(in: f.store.state))
        #expect(try f.store.restoreClosedItem(saved))
        #expect(f.store.selectedTabID == pin)
        #expect(first.consume(saved))
        #expect(!first.consume(saved))
        #expect(first.next(in: f.store.state)?.tabIDs == [a])
    }

    @Test func anOlderArchiveRestoresAndConsumesOnceWithoutAClonedIdentity() throws {
        let f = try Fixture()
        let first = ClosedWindow()
        let a = f.store.open("https://a.test")
        first.record(f.close([a]), in: f.store.state)
        let prior = try #require(first.next(in: f.store.state))
        #expect(try f.store.restoreClosedItem(prior))
        #expect(first.consume(prior))
        #expect(first.next(in: f.store.state) == nil)
        #expect(f.store.state.tabs.filter { $0.id == a }.count == 1)
    }

    @Test func anExplicitSavedRevisitConsumesPriorityAndAnArchiveCommitClearsOlderSavedPriority() throws {
        let f = try Fixture()
        let first = ClosedWindow()
        let pin = f.store.open("https://saved.test", kind: .pinned)
        let b = f.store.open("https://b.test")
        first.record(f.close([pin]), in: f.store.state)
        let priorSaved = try #require(first.next(in: f.store.state))
        first.selected([pin])
        #expect(first.next(in: f.store.state) == nil)
        first.record(f.close([pin]), in: f.store.state)
        first.record(f.close([b]), in: f.store.state)
        #expect(first.next(in: f.store.state)?.tabIDs == [b])
        #expect(!first.consume(priorSaved))
    }

    @Test func aCompleteOriginalSplitIsOneStepWithItsFocusAndRestoresAtomically() throws {
        let f = try Fixture()
        let first = ClosedWindow()
        let c = f.store.open("https://c.test"), d = f.store.open("https://d.test")
        f.store.setSplit([c, d])
        let layout = try #require(f.store.state.splitLayouts.first { $0.tabIDs == [c, d] })
        first.record(f.close([c, d], focus: d), in: f.store.state)
        let group = try #require(first.next(in: f.store.state))
        #expect(group.tabIDs == [c, d])
        #expect(group.split == layout)
        #expect(group.focusedTabID == d)
        #expect(try f.store.restoreClosedItem(group))
        #expect(f.store.state.selectedTabIDs == [c, d])
        #expect(f.store.state.splitLayouts.contains(layout))
        #expect(first.consume(group))
        #expect(!group.isValid(in: f.store.state))
    }

    @Test func aMultiItemGroupPopsTheLastStableStepAndKeepsTheEarlierOne() throws {
        let f = try Fixture()
        let first = ClosedWindow(), second = ClosedWindow()
        let b = f.store.open("https://b.test")
        first.record(f.close([b]), in: f.store.state)
        let e = f.store.open("https://e.test"), g = f.store.open("https://f.test")
        second.record(f.close([e, g]), in: f.store.state)
        let last = try #require(second.next(in: f.store.state))
        #expect(last.tabIDs == [g])
        _ = try f.store.restoreClosedItem(last)
        _ = second.consume(last)
        #expect(second.next(in: f.store.state)?.tabIDs == [e])
        #expect(first.next(in: f.store.state)?.tabIDs == [b])
    }

    @Test func aRefusedBeforeUnloadPreservesTheModelAndCannotForgeACloseRecord() throws {
        let f = try Fixture()
        let second = ClosedWindow()
        let c = f.store.open("https://c.test")
        let e = f.store.open("https://e.test")
        second.record(f.close([e]), in: f.store.state)
        let before = f.store.state
        let pending = ClosedItemIntent(ids: [c], state: f.store.state, spaceID: f.space, profileID: f.profile, focusedTabID: c)!
        var reply: ((Bool) -> Void)?
        f.store.requestPageRetirement = { _, _, done in reply = done }
        var committed = false
        f.store.closeTabs([c]) { allowed in committed = allowed }
        #expect(f.store.retiringTabIDs.contains(c))
        #expect(f.store.state == before)
        reply?(false)
        #expect(!committed)
        #expect(f.store.state == before)
        second.record(pending, in: f.store.state)
        #expect(second.next(in: f.store.state)?.tabIDs == [e])
    }

    struct Corruption {
        let record: ClosedItemRecord
        let tab: UUID
        let other: UUID
    }

    func archivedRecord(_ f: Fixture) throws -> Corruption {
        let second = ClosedWindow()
        let e = f.store.open("https://e.test"), c = f.store.open("https://c.test")
        second.record(f.close([e]), in: f.store.state)
        return Corruption(record: try #require(second.next(in: f.store.state)), tab: e, other: c)
    }

    @Test func aMissingOriginalSpaceInvalidatesInsteadOfBorrowingAnotherProfile() throws {
        let f = try Fixture()
        let c = try archivedRecord(f)
        var corrupt = f.store.state
        corrupt.spaces.removeAll { $0.id == f.space }
        #expect(!c.record.isValid(in: corrupt))
    }

    @Test func profileReassignmentAndChangedAfterimagesInvalidateTheOriginalToken() throws {
        let f = try Fixture()
        let c = try archivedRecord(f)
        var corrupt = f.store.state
        corrupt.tabs[corrupt.tabs.firstIndex { $0.id == c.tab }!].profileID = UUID()
        #expect(!c.record.isValid(in: corrupt))
        corrupt = f.store.state
        corrupt.tabs[corrupt.tabs.firstIndex { $0.id == c.tab }!].url += "/changed"
        #expect(!c.record.isValid(in: corrupt))
    }

    @Test func anUnknownCloseTargetNeverEntersTheCache() throws {
        let f = try Fixture()
        #expect(ClosedItemIntent(ids: [UUID()], state: f.store.state, spaceID: f.space, profileID: f.profile, focusedTabID: nil) == nil)
    }

    @Test func anOldRecordCannotBreakASurvivingOrNewlyGroupedItem() throws {
        let f = try Fixture()
        let c = try archivedRecord(f)
        var corrupt = f.store.state
        corrupt.splitLayouts.append(BrowserSplitLayout(spaceID: f.space, tabIDs: [c.tab, c.other], orientation: .horizontal, widthFactors: [0.5, 0.5]))
        #expect(!c.record.isValid(in: corrupt))
    }

    @Test func aSaveRefusalLeavesTheArchivedStateUntouchedAndRetryCommitsTheSameRecord() throws {
        let f = try Fixture()
        let second = ClosedWindow()
        let e = f.store.open("https://e.test")
        second.record(f.close([e]), in: f.store.state)
        let record = try #require(second.next(in: f.store.state))
        let stable = f.store.state
        try f.store.save()
        let file = f.directory.appendingPathComponent("session.json"), backup = f.directory.appendingPathComponent("backup.json")
        try FileManager.default.moveItem(at: file, to: backup)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try f.store.restoreClosedItem(record) }
        #expect(f.store.state == stable)
        #expect(second.next(in: f.store.state)?.id == record.id)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: backup, to: file)
        #expect(try f.store.restoreClosedItem(record))
        #expect(second.consume(record))
        let reloaded = try BrowserStore(directory: f.directory)
        #expect(reloaded.state.tabs.first { $0.id == e }?.archivedAt == nil)
        let freshWindow = ClosedWindow()
        #expect(freshWindow.next(in: reloaded.state) == nil)
    }

    @Test func theLatestSavedCloseReplacesTheSingleSlotAndExpiredTargetsFallThrough() throws {
        let f = try Fixture()
        let first = ClosedWindow()
        let b = f.store.open("https://b.test")
        first.record(f.close([b]), in: f.store.state)
        let pin = f.store.open("https://saved.test", kind: .pinned)
        first.record(f.close([pin]), in: f.store.state)
        let p2 = f.store.open("https://other-saved.test", kind: .favorite)
        first.record(f.close([p2]), in: f.store.state)
        #expect(first.next(in: f.store.state)?.tabIDs == [p2])
        f.store.removeTab(p2)
        #expect(first.next(in: f.store.state)?.tabIDs == [b])
        f.store.deleteArchivedTabs([b])
        #expect(first.next(in: f.store.state) == nil)
    }

    struct ArchiveRetirement {
        let f: Fixture
        let a: UUID, b: UUID
        let record: ClosedItemRecord
        let item: BrowserArchivedItem
        let lease: ArchivePreviewLease
        let now = Date(timeIntervalSince1970: 1_900_000_000)

        @MainActor init() throws {
            let now = self.now
            f = try Fixture(now: { now })
            a = f.store.open("https://a.invalid")
            b = f.store.open("https://b.invalid")
            f.store.setSplit([a, b])
            let intent = f.intent([a, b], focus: a)
            f.store.closeTabs([a, b])
            let closed = ClosedWindow()
            closed.record(intent, in: f.store.state)
            record = closed.next(in: f.store.state)!
            let aID = a
            let found = f.store.archivedItems(profileID: f.profile).first { $0.tabs.contains { $0.id == aID } }!
            item = found
            lease = f.store.acquireArchivePreview(id: found.id, profileID: f.profile)!
        }
    }

    @Test func aLeasedGroupCannotBeStolenByASecondPreviewRestoreOrReopen() throws {
        let r = try ArchiveRetirement()
        let store = r.f.store
        #expect(store.acquireArchivePreview(id: r.item.id, profileID: r.f.profile) == nil)
        #expect(store.restoreArchivedTab(r.a, profileID: r.f.profile, destination: .previousSpace(fallbackSpaceID: r.f.space)).isEmpty)
        #expect(try !store.restoreClosedItem(r.record))
        store.updateTab(r.a, title: "New title")
        #expect(store.archivePreviewIsValid(r.lease))
    }

    @Test func archiveRetirementReservesTheWholeGroupHonorsLeasesAndRefusesStaleMutations() throws {
        let r = try ArchiveRetirement()
        let store = r.f.store, space = r.f.space, profile = r.f.profile, item = r.item
        var requests: [(Set<UUID>, () -> Bool, (Bool) -> Void)] = []
        store.requestPageRetirement = { requests.append(($0, $1, $2)) }
        store.deleteArchivedTabs([r.a], profileID: profile)
        #expect(requests.count == 1)
        #expect(requests[0].0 == [r.a, r.b])
        #expect(store.archivePreviewIsValid(r.lease))
        #expect(store.restoreArchivePreview(r.lease, destination: .previousSpace(fallbackSpaceID: space)).isEmpty)
        store.deleteArchivedTabs([r.b], profileID: profile)
        store.removeTab(r.a)
        #expect(requests.count == 1)
        requests[0].2(false)
        #expect(store.state.tabs.contains { $0.id == r.a })
        #expect(store.archivePreviewIsValid(r.lease))
        store.deleteArchivedTabs([r.a], profileID: profile)
        #expect(requests[1].1())
        requests[1].2(true)
        #expect(store.state.tabs.contains { $0.id == r.a })
        #expect(store.archivePreviewIsValid(r.lease))
        store.deleteArchivedTabs([r.a], profileID: profile)
        #expect(requests[2].1())
        store.releaseArchivePreview(r.lease)
        var deletionReentry: ArchivePreviewLease?
        let deleteObserver = store.statePublisher.dropFirst().sink { _ in deletionReentry = store.acquireArchivePreview(id: item.id, profileID: profile) }
        requests[2].2(true)
        deleteObserver.cancel()
        #expect(deletionReentry == nil)
        #expect(!store.state.tabs.contains { $0.id == r.a })
        #expect(store.state.tabs.contains { $0.id == r.b })
        requests[0].2(true)
        #expect(store.state.tabs.contains { $0.id == r.b })
        let remaining = try #require(store.archivedItems(profileID: profile).first { $0.tabs.contains { $0.id == r.b } })
        let second = try #require(store.acquireArchivePreview(id: remaining.id, profileID: profile))
        store.deleteArchivedTabs([r.b])
        store.updateTab(r.b, title: "Edited during consent")
        #expect(!requests[3].1())
        requests[3].2(false)
        #expect(store.state.tabs.contains { $0.id == r.b })
        #expect(store.archivePreviewIsValid(second))
        var promotionReentry: ArchivePreviewLease?
        let remainingID = remaining.id
        let promotionObserver = store.statePublisher.dropFirst().sink { _ in promotionReentry = store.acquireArchivePreview(id: remainingID, profileID: profile) }
        #expect(store.restoreArchivePreview(second, destination: .previousSpace(fallbackSpaceID: space)) == [r.b])
        promotionObserver.cancel()
        #expect(promotionReentry == nil)
        #expect(!store.archivePreviewIsValid(second))
    }

    @Test func withoutANativeOwnerClearAndExpiryKeepTheirSynchronousBehaviorAndRefusedExpiryRetainsTheRecord() throws {
        let r = try ArchiveRetirement()
        let store = r.f.store, profile = r.f.profile, now = r.now
        store.releaseArchivePreview(r.lease)
        store.closeTabs([r.b])
        store.clearArchive(profileID: profile)
        #expect(!store.state.tabs.contains { $0.id == r.b })
        let expiring = store.open("https://expired.invalid")
        store.closeTabs([expiring])
        var requests: [(Set<UUID>, () -> Bool, (Bool) -> Void)] = []
        store.requestPageRetirement = { requests.append(($0, $1, $2)) }
        store.cleanExpiredArchive(now: now.addingTimeInterval(BrowserStore.archiveRetention))
        #expect(requests.count == 1)
        #expect(requests[0].0 == [expiring])
        requests[0].2(false)
        #expect(store.state.tabs.contains { $0.id == expiring })
        store.requestPageRetirement = nil
        store.cleanExpiredArchive(now: now.addingTimeInterval(BrowserStore.archiveRetention))
        #expect(!store.state.tabs.contains { $0.id == expiring })
    }

    @Test func openingAnEaselNeverResurrectsItsLeasedArchiveIdentityAndAnUnreleasedPreviewRefusesDocumentDeletion() throws {
        let f = try Fixture(now: { Date(timeIntervalSince1970: 1_900_000_000) })
        let store = f.store
        let document = UUID()
        let easel = store.openResolvedURL(URL(string: InternalPage.easel(document).urlString)!)
        store.closeTabs([easel])
        let documentLease = try #require(store.acquireArchivePreview(id: easel, profileID: f.profile))
        let other = try #require(store.openEasel(id: document, title: "Board"))
        #expect(other != easel)
        #expect(store.archivePreviewIsValid(documentLease))
        var requests: [(Set<UUID>, () -> Bool, (Bool) -> Void)] = []
        store.requestPageRetirement = { requests.append(($0, $1, $2)) }
        var deleted = false, completed: Error?
        store.deleteLocalDocument(.easel(document), profileID: f.profile, ownerValid: { true }, deleteDocument: { deleted = true }, completion: { completed = $0 })
        #expect(requests.count == 1)
        #expect(requests[0].0 == [easel, other])
        #expect(requests[0].1())
        requests[0].2(true)
        #expect(!deleted)
        #expect(completed != nil)
        #expect(store.state.tabs.contains { $0.id == easel })
        store.releaseArchivePreview(documentLease)
    }

    @Test func aDismissedPeekIsTheTopStepRecordingItsParentAndCurrentURL() throws {
        let f = try Fixture(now: { Date(timeIntervalSince1970: 1_900_000_000) })
        let cache = ClosedWindow()
        let parent = f.store.open("https://parent.invalid")
        let peek = ClosedPeekRecord(id: UUID(), url: URL(string: "https://peek.invalid/current")!, parentTabID: parent, profileID: f.profile)
        cache.recordPeek(peek, in: f.store.state)
        guard case .peek(let restored)? = cache.nextStep(in: f.store.state, restorable: { f.store.canUndoFolderDeletion($0) }) else {
            Issue.record("dismissed Peek must be the top step")
            return
        }
        #expect(restored == peek)
        #expect(cache.next(in: f.store.state) == nil)
    }

    @Test func onlyAnHTTPPeekOnAProfileNotBeingRemovedCanReopenAndOnlyTheExactStepConsumes() throws {
        let f = try Fixture(now: { Date(timeIntervalSince1970: 1_900_000_000) })
        let cache = ClosedWindow()
        let parent = f.store.open("https://parent.invalid")
        let peek = ClosedPeekRecord(id: UUID(), url: URL(string: "https://peek.invalid/current")!, parentTabID: parent, profileID: f.profile)
        cache.recordPeek(peek, in: f.store.state)
        let local = ClosedPeekRecord(id: UUID(), url: URL(string: "file:///tmp/peek")!, parentTabID: parent, profileID: f.profile)
        #expect(!local.isValid(in: f.store.state))
        var removing = f.store.state
        removing.profileRemovals.append(ProfileRemovalRecord(id: UUID(), profileID: f.profile, profileName: "Removing"))
        #expect(!peek.isValid(in: removing))
        #expect(!cache.consume(stepID: UUID()))
        #expect(cache.consume(stepID: peek.id))
        #expect(cache.nextStep(in: f.store.state, restorable: { f.store.canUndoFolderDeletion($0) }) == nil)
    }

    @Test func aSavedSlotPrecedesALaterPeekAndThePeekRemainsAfterTheSavedReopen() throws {
        let f = try Fixture(now: { Date(timeIntervalSince1970: 1_900_000_000) })
        let cache = ClosedWindow()
        let parent = f.store.open("https://parent.invalid")
        let peek = ClosedPeekRecord(id: UUID(), url: URL(string: "https://peek.invalid/current")!, parentTabID: parent, profileID: f.profile)
        let pinned = f.store.open("https://saved.invalid", kind: .pinned)
        let savedIntent = f.intent([pinned], focus: pinned)
        f.store.closeTabs([pinned])
        cache.record(savedIntent, in: f.store.state)
        cache.recordPeek(peek, in: f.store.state)
        guard case .items(let saved)? = cache.nextStep(in: f.store.state, restorable: { f.store.canUndoFolderDeletion($0) }), saved.kind == .saved else {
            Issue.record("saved slot must precede a later Peek")
            return
        }
        #expect(cache.consume(saved))
        guard case .peek? = cache.nextStep(in: f.store.state, restorable: { f.store.canUndoFolderDeletion($0) }) else {
            Issue.record("Peek step must remain after saved Reopen")
            return
        }
    }

    @Test func anArchivedPeekParentExpiresItsStepAndTheOlderCloseRemainsReachable() throws {
        let f = try Fixture(now: { Date(timeIntervalSince1970: 1_900_000_000) })
        let cache = ClosedWindow()
        let parent = f.store.open("https://parent.invalid")
        let peek = ClosedPeekRecord(id: UUID(), url: URL(string: "https://peek.invalid/current")!, parentTabID: parent, profileID: f.profile)
        let older = f.store.open("https://older.invalid")
        let olderIntent = f.intent([older], focus: older)
        f.store.closeTabs([older])
        cache.record(olderIntent, in: f.store.state)
        cache.recordPeek(peek, in: f.store.state)
        f.store.closeTabs([parent])
        guard case .items(let survivor)? = cache.nextStep(in: f.store.state, restorable: { f.store.canUndoFolderDeletion($0) }), survivor.tabIDs == [older] else {
            Issue.record("an archived Peek parent must expire its step")
            return
        }
        #expect(try f.store.restoreClosedItem(survivor))
        #expect(cache.consume(survivor))
    }

    struct FolderSteps {
        let f: Fixture
        let folder: UUID
        let inner: UUID, second: UUID
        let collapsed: BrowserFolder
        let cache = ClosedWindow()

        @MainActor init() throws {
            f = try Fixture(now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let store = f.store
            folder = store.createFolder(name: "Reading")
            inner = store.open("https://inner.invalid")
            second = store.open("https://second.invalid")
            store.moveTab(inner, toSpace: f.space, folderID: folder)
            store.moveTab(second, toSpace: f.space, folderID: folder)
            let folderID = folder
            let expanded = store.state.folders.first { $0.id == folderID }!
            _ = try store.setFolderExpanded(false, expected: expanded, profileID: f.profile)
            collapsed = store.state.folders.first { $0.id == folderID }!
        }

        @MainActor func delete(_ id: UUID) -> FolderDeletionUndo? {
            guard let target = FolderRemovalTarget(folderID: id, spaceID: f.space, profileID: f.profile, state: f.store.state) else { return nil }
            var undo: FolderDeletionUndo?
            f.store.deleteFolder(target, shouldCommit: { true }, didCommit: { undo = $0 }) { _ in }
            return undo
        }

        @MainActor func top() -> ClosedItemStep? {
            let store = f.store
            return cache.nextStep(in: store.state, restorable: { store.canUndoFolderDeletion($0) })
        }
    }

    @Test func aFolderDeleteReplacesSavedPriorityAsTheTopStepAndReopenRestoresItThroughItsOriginalTransaction() throws {
        let s = try FolderSteps()
        let pin = s.f.store.open("https://priority.invalid", kind: .pinned)
        let pinIntent = s.f.intent([pin], focus: pin)
        s.f.store.closeTabs([pin])
        s.cache.record(pinIntent, in: s.f.store.state)
        let deleted = try #require(s.delete(s.folder))
        s.cache.recordFolderDeletion(deleted)
        guard case .folder(let step)? = s.top(), step.id == deleted.id else {
            Issue.record("a folder Delete must replace saved priority as the top step")
            return
        }
        #expect(try s.f.store.undoFolderDeletion(step, shouldCommit: { true }))
        #expect(s.cache.consume(stepID: step.id))
        let folderID = s.folder
        #expect(s.f.store.state.folders.first { $0.id == folderID } == s.collapsed)
        #expect(s.f.store.state.tabs.filter { [s.inner, s.second].contains($0.id) }.allSatisfy { $0.archivedAt == nil && $0.folderID == folderID })
        #expect(s.top() == nil)
    }

    @Test func anExpandedFolderReturnsExpandedAndADeletionAlreadyRestoredByUndoExpiresItsReopenStep() throws {
        let s = try FolderSteps()
        let folderID = s.folder
        #expect(try s.f.store.setFolderExpanded(true, expected: s.collapsed, profileID: s.f.profile))
        let again = try #require(s.delete(folderID))
        s.cache.recordFolderDeletion(again)
        #expect(try s.f.store.undoFolderDeletion(again, shouldCommit: { true }))
        #expect(s.f.store.state.folders.first { $0.id == folderID }?.isExpanded == true)
        #expect(s.top() == nil)
    }

    struct SplitSteps {
        let f: Fixture
        let cache = ClosedWindow()

        @MainActor init() throws {
            f = try Fixture(now: { Date(timeIntervalSince1970: 1_900_000_000) })
        }

        func approx(_ left: [Double]?, _ right: [Double]) -> Bool {
            guard let left, left.count == right.count else { return false }
            return zip(left, right).allSatisfy { abs($0 - $1) < 1e-9 }
        }

        @MainActor func split(_ ids: [UUID], _ orientation: SplitOrientation, _ factors: [Double]) -> BrowserSplitLayout {
            f.store.setSplit(ids)
            _ = f.store.setSplitLayout(orientation: orientation, widthFactors: factors)
            return f.store.state.splitLayouts.first { $0.tabIDs == ids }!
        }

        @MainActor func close(_ ids: Set<UUID>, focus: UUID? = nil) {
            let intent = ClosedItemIntent(ids: ids, state: f.store.state, spaceID: f.space, profileID: f.profile, focusedTabID: focus)!
            f.store.closeTabs(ids)
            cache.record(intent, in: f.store.state)
        }

        @MainActor func group(_ id: UUID) -> BrowserSplitLayout? { f.store.state.splitLayouts.first { $0.id == id } }

        @MainActor func reopen(_ expected: [UUID], regroupable: (UUID) -> Bool = { _ in true }) throws {
            let record = try #require(cache.next(in: f.store.state))
            #expect(record.tabIDs == expected)
            #expect(try f.store.restoreClosedItem(record, regroupable: regroupable))
            #expect(cache.consume(record))
        }

        @MainActor func open(_ name: String) -> UUID { f.store.open("https://\(name).invalid") }
    }

    @Test func closingOneOfThreePanesKeepsTheOriginalContainerAndReopenRejoinsItAtItsIndexAndShare() throws {
        let s = try SplitSteps()
        let a = s.open("a"), b = s.open("b"), c = s.open("c")
        let three = s.split([a, b, c], .vertical, [0.2, 0.3, 0.5])
        s.close([b], focus: b)
        #expect(s.group(three.id)?.tabIDs == [a, c])
        let middle = s.cache.next(in: s.f.store.state)?.membership
        #expect(middle?.layout.id == three.id)
        #expect(middle?.layout.tabIDs == [a, b, c])
        #expect(middle?.index == 1)
        #expect(middle?.dissolved == false)
        try s.reopen([b])
        #expect(s.group(three.id)?.tabIDs == [a, b, c])
        #expect(s.group(three.id)?.orientation == .vertical)
        #expect(s.approx(s.group(three.id)?.widthFactors, [0.2, 0.3, 0.5]))
        #expect(s.f.store.state.selectedTabIDs == [a, b, c])
        #expect(s.f.store.state.splitLayouts.filter { $0.tabIDs.contains(b) }.count == 1)
    }

    @Test func closingOneOfTwoPanesDissolvesTheContainerAndReopenRegroupsItWithItsIdentityAndAnchor() throws {
        let s = try SplitSteps()
        let d = s.open("d"), e = s.open("e")
        let pair = s.split([d, e], .vertical, [0.25, 0.75])
        s.close([d], focus: d)
        #expect(s.group(pair.id) == nil)
        #expect(s.cache.next(in: s.f.store.state)?.membership?.dissolved == true)
        try s.reopen([d])
        #expect(s.group(pair.id)?.tabIDs == [d, e])
        #expect(s.group(pair.id)?.orientation == .vertical)
        #expect(s.approx(s.group(pair.id)?.widthFactors, [0.25, 0.75]))
        #expect(s.group(pair.id)?.sidebarAnchorID == pair.sidebarAnchorID)
        #expect(s.f.store.state.selectedTabIDs == [d, e])
        let disk = try BrowserStore(directory: s.f.directory)
        #expect(disk.state.splitLayouts.contains { $0.id == pair.id && $0.tabIDs == [d, e] })
    }

    @Test func twoOfFourPanesClosedReopenAtTheirAdjustedIndexesAndRestoreOrderAndRatios() throws {
        let s = try SplitSteps()
        let f = s.open("f"), g = s.open("g"), h = s.open("h"), i = s.open("i")
        let four = s.split([f, g, h, i], .horizontal, [0.1, 0.2, 0.3, 0.4])
        s.close([g, h], focus: h)
        #expect(s.group(four.id)?.tabIDs == [f, i])
        try s.reopen([h])
        #expect(s.group(four.id)?.tabIDs == [f, h, i])
        try s.reopen([g])
        #expect(s.group(four.id)?.tabIDs == [f, g, h, i])
        #expect(s.approx(s.group(four.id)?.widthFactors, [0.1, 0.2, 0.3, 0.4]))
    }

    @Test func twoOfThreeClosedTogetherDissolveAndRegroupWithTheSurvivorThenRejoin() throws {
        let s = try SplitSteps()
        let j = s.open("j"), k = s.open("k"), l = s.open("l")
        let trio = s.split([j, k, l], .horizontal, [0.5, 0.25, 0.25])
        s.close([k, l], focus: l)
        #expect(s.group(trio.id) == nil)
        try s.reopen([l])
        #expect(s.group(trio.id)?.tabIDs == [j, l])
        #expect(s.approx(s.group(trio.id)?.widthFactors, [2.0 / 3, 1.0 / 3]))
        try s.reopen([k])
        #expect(s.group(trio.id)?.tabIDs == [j, k, l])
        #expect(s.approx(s.group(trio.id)?.widthFactors, [0.5, 0.25, 0.25]))
    }

    @Test func aRefusedSurvivorLeavesThePaneAlone() throws {
        let s = try SplitSteps()
        let m = s.open("m"), n = s.open("n")
        let owned = s.split([m, n], .horizontal, [0.5, 0.5])
        s.close([n], focus: n)
        try s.reopen([n], regroupable: { $0 != m })
        #expect(s.group(owned.id) == nil)
        #expect(s.f.store.state.selectedTabIDs == [n])
    }

    @Test func aSurvivorShownInAnotherWindowRejoinsTheSplitWithItsGeometry() throws {
        let s = try SplitSteps()
        let shownElsewhere = NativePageOwnership(), thisWindow = UUID(), otherWindow = UUID()
        let survivor = s.open("survivor"), returning = s.open("returning")
        let shared = s.split([survivor, returning], .vertical, [0.4, 0.6])
        s.close([returning], focus: returning)
        #expect(shownElsewhere.claim(survivor, owner: otherWindow, page: "survivor-page"))
        try s.reopen([returning], regroupable: { id in
            shownElsewhere.canUse(id, owner: thisWindow) || (shownElsewhere.isClaimed(id) && shownElsewhere.claimSnapshot(id).transfer == nil)
        })
        #expect(s.group(shared.id)?.tabIDs == [survivor, returning])
        #expect(s.approx(s.group(shared.id)?.widthFactors, [0.4, 0.6]))
    }

    @Test func regroupingNeverStealsAPaneFromANewerGroup() throws {
        let s = try SplitSteps()
        let o = s.open("o"), p = s.open("p"), q = s.open("q")
        let left = s.split([o, p], .horizontal, [0.5, 0.5])
        s.close([p], focus: p)
        let other = s.split([o, q], .horizontal, [0.4, 0.6])
        try s.reopen([p])
        #expect(s.group(left.id) == nil)
        #expect(s.group(other.id)?.tabIDs == [o, q])
        #expect(s.f.store.state.selectedTabIDs == [p])
    }

    @Test func aGroupedSurvivorSkipsRegroupingEvenForTwoUngroupedReturningPanes() throws {
        let s = try SplitSteps()
        let o1 = s.open("o1"), o2 = s.open("o2"), o3 = s.open("o3"), o4 = s.open("o4")
        let skippedTrio = s.split([o1, o2, o3], .horizontal, [1, 1, 1])
        s.close([o2, o3], focus: o3)
        let elsewhere = s.split([o1, o4], .horizontal, [0.5, 0.5])
        try s.reopen([o3])
        #expect(s.group(skippedTrio.id) == nil)
        #expect(s.f.store.state.selectedTabIDs == [o3])
        try s.reopen([o2])
        #expect(s.group(skippedTrio.id) == nil)
        #expect(s.f.store.state.selectedTabIDs == [o2])
        #expect(s.group(elsewhere.id)?.tabIDs == [o1, o4])
    }

    @Test func aFourPaneContainerRefusesInsertionAndThePaneReturnsAlone() throws {
        let s = try SplitSteps()
        let r = s.open("r"), sPane = s.open("s"), t = s.open("t"), u = s.open("u"), v = s.open("v")
        let full = s.split([r, sPane, t], .horizontal, [1, 1, 1])
        s.close([sPane], focus: sPane)
        s.f.store.setSplit([r, t, u, v])
        #expect(s.group(full.id)?.tabIDs == [r, t, u, v])
        try s.reopen([sPane])
        #expect(s.group(full.id)?.tabIDs == [r, t, u, v])
        #expect(s.f.store.state.selectedTabIDs == [sPane])
    }

    @Test func fewerThanTwoExistingOriginalChildrenReturnsThePaneAlone() throws {
        let s = try SplitSteps()
        let w = s.open("w"), x = s.open("x")
        let lone = s.split([w, x], .horizontal, [0.5, 0.5])
        s.close([x], focus: x)
        s.close([w], focus: w)
        let skipped = try #require(s.cache.next(in: s.f.store.state))
        #expect(skipped.tabIDs == [w])
        #expect(skipped.membership == nil)
        #expect(s.cache.consume(skipped))
        try s.reopen([x])
        #expect(s.group(lone.id) == nil)
        #expect(s.f.store.state.selectedTabIDs == [x])
    }

    @Test func aChangedContainerRecordsNoRegroupingAndTheExactAfterimageRecordsTheOriginalIndex() throws {
        let s = try SplitSteps()
        let y = s.open("y"), z = s.open("z"), zz = s.open("zz")
        let checked = s.split([y, z, zz], .horizontal, [1, 1, 1])
        let intent = ClosedItemIntent(ids: [z], state: s.f.store.state, spaceID: s.f.space, profileID: s.f.profile, focusedTabID: z)!
        s.f.store.closeTabs([z])
        var replaced = s.f.store.state
        replaced.splitLayouts[replaced.splitLayouts.firstIndex { $0.id == checked.id }!].id = UUID()
        #expect(intent.membership(of: z, in: replaced) == nil)
        #expect(intent.membership(of: z, in: s.f.store.state)?.index == 1)
    }

    @Test func anyReopenOrderRebuildsTheOriginalPaneOrderAndRatiosOfAReorderedContainer() throws {
        let s = try SplitSteps()
        let p1 = s.open("p1"), p2 = s.open("p2"), p3 = s.open("p3")
        let reordered = s.split([p1, p3, p2], .horizontal, [0.5, 0.2, 0.3])
        s.close([p3, p2], focus: p2)
        #expect(s.group(reordered.id) == nil)
        try s.reopen([p3])
        #expect(s.group(reordered.id)?.tabIDs == [p1, p3])
        try s.reopen([p2])
        #expect(s.group(reordered.id)?.tabIDs == [p1, p3, p2])
        #expect(s.approx(s.group(reordered.id)?.widthFactors, [0.5, 0.2, 0.3]))
    }

    final class Clock {
        var now = Date(timeIntervalSince1970: 2_000_000_000)
    }

    struct Bulk {
        let clock = Clock()
        let f: Fixture
        let oldest: UUID, recent: UUID, newestShared: UUID, today: UUID
        let first = ClosedWindow()
        let second = ClosedWindow()
        let archived: ClosedItemIntent

        @MainActor init() throws {
            let clock = self.clock
            f = try Fixture(now: { clock.now })
            let store = f.store
            oldest = store.open("https://first.invalid", kind: .pinned)
            recent = store.open("https://recent.invalid", kind: .pinned)
            newestShared = store.open("https://shared.invalid", kind: .pinned)
            today = store.open("https://archive.invalid")
            archived = f.intent([today])
            store.closeTabs([today])
            first.record(archived, in: store.state)
            let now = clock.now
            first.recordSelection([oldest], focusedTabID: oldest, state: store.state, at: now.addingTimeInterval(0.1))
            first.recordSelection([recent], focusedTabID: recent, state: store.state, at: now.addingTimeInterval(0.2))
            second.recordSelection([newestShared], focusedTabID: newestShared, state: store.state, at: now + 1)
            clock.now += 1
            store.selectTab(newestShared)
        }
    }

    @Test func theRealSessionStoreRetainsSameSecondSavedItemRecency() throws {
        let b = try Bulk()
        let store = b.f.store
        store.updateWindowRecords([BrowserWindowRecord(sidebarWidth: 228, itemLastActiveDates: b.first.itemLastActiveDates)])
        try store.save()
        let restoredRecord = try BrowserStore(directory: b.f.directory).windowRecords[0]
        let restored = ClosedWindow(itemLastActiveDates: restoredRecord.itemLastActiveDates)
        let bulk = b.f.intent([b.oldest, b.recent, b.newestShared])
        store.closeTabs([b.oldest, b.recent, b.newestShared])
        restored.record(bulk, in: store.state)
        #expect(restored.next(in: store.state)?.tabIDs == [b.recent])
    }

    @Test func bulkSavedCloseChoosesThisWindowsMostRecentOriginalAndAnotherWindowKeepsItsOwnRecency() throws {
        let b = try Bulk()
        let store = b.f.store
        let bulk = b.f.intent([b.oldest, b.recent, b.newestShared])
        store.closeTabs([b.oldest, b.recent, b.newestShared])
        b.first.record(bulk, in: store.state)
        b.second.record(bulk, in: store.state)
        let selected = try #require(b.first.next(in: store.state))
        #expect(selected.tabIDs == [b.recent])
        #expect(b.second.next(in: store.state)?.tabIDs == [b.newestShared])
        #expect(try store.restoreClosedItem(selected))
        #expect(b.first.consume(selected))
        #expect(b.first.next(in: store.state)?.tabIDs == [b.today])
    }

    @Test func equalDatesUseTheStableModelOrderAdaptationAndMissingDatesAreDistantPast() throws {
        let b = try Bulk()
        let store = b.f.store
        let equal = ClosedWindow(), unseen = ClosedWindow()
        let now = b.clock.now
        equal.recordSelection([b.recent], focusedTabID: b.recent, state: store.state, at: now)
        equal.recordSelection([b.oldest], focusedTabID: b.oldest, state: store.state, at: now)
        let tied = b.f.intent([b.oldest, b.recent])
        store.closeTabs([b.oldest, b.recent])
        equal.record(tied, in: store.state)
        unseen.record(tied, in: store.state)
        #expect(equal.next(in: store.state)?.tabIDs == [b.oldest])
        #expect(unseen.next(in: store.state)?.tabIDs == [b.oldest])
    }

    @Test func aBulkSavedRecordKeepsItsOriginalProfileIdentityAndExpiredSlotsResumeTodayHistory() throws {
        let b = try Bulk()
        let store = b.f.store
        let bulk = b.f.intent([b.oldest, b.recent, b.newestShared])
        store.closeTabs([b.oldest, b.recent, b.newestShared])
        b.first.record(bulk, in: store.state)
        let retry = try #require(b.first.next(in: store.state))
        var changed = store.state
        changed.tabs[changed.tabs.firstIndex { $0.id == b.recent }!].profileID = UUID()
        #expect(!retry.isValid(in: changed))
        changed = store.state
        changed.tabs.removeAll { $0.id == b.recent }
        #expect(!retry.isValid(in: changed))
        let expired = b.first.copy()
        #expect(expired.next(in: changed)?.tabIDs == [b.today])
    }

    @Test func aBulkWinnerSaveRefusalPublishesNoSelectionAndRetryCommitsBeforeConsumption() throws {
        let b = try Bulk()
        let store = b.f.store
        let bulk = b.f.intent([b.oldest, b.recent, b.newestShared])
        store.closeTabs([b.oldest, b.recent, b.newestShared])
        b.first.record(bulk, in: store.state)
        let retry = try #require(b.first.next(in: store.state))
        let before = store.state
        try store.save()
        let file = b.f.directory.appendingPathComponent("session.json"), backup = b.f.directory.appendingPathComponent("backup.json")
        try FileManager.default.moveItem(at: file, to: backup)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try store.restoreClosedItem(retry) }
        #expect(store.state == before)
        #expect(b.first.next(in: store.state)?.id == retry.id)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: backup, to: file)
        #expect(try store.restoreClosedItem(retry))
        #expect(b.first.consume(retry))
    }

    struct TypedSplit {
        let b: Bulk
        let notePath: URL
        let easels: EaselStore
        let easel: EaselSession
        let easelPath: URL
        let noteBytes: Data, easelBytes: Data
        let n: UUID, e: UUID
        let split: BrowserSplitLayout
        let cache = ClosedWindow()
        let groupIntent: ClosedItemIntent

        @MainActor init() throws {
            b = try Bulk()
            let store = b.f.store
            notePath = store.directory.appendingPathComponent("Parc Notes/Shared Note.md")
            try FileManager.default.createDirectory(at: notePath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("Shared body\n".utf8).write(to: notePath)
            easels = try EaselStore(directory: store.easelsDirectory(for: b.f.profile))
            easel = try easels.create(title: "Shared Easel")
            easelPath = easels.directory.appendingPathComponent("documents/" + easel.document.id.uuidString.lowercased() + ".json")
            noteBytes = try Data(contentsOf: notePath)
            easelBytes = try Data(contentsOf: easelPath)
            n = store.openNote(url: notePath, title: "Shared Note")!
            e = store.openEasel(id: easel.document.id, title: easel.document.title)!
            store.setKind(n, .today)
            store.setKind(e, .today)
            store.setSplit([n, e])
            _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.3, 0.7])
            let nID = n, eID = e
            let todaySplit = store.state.splitLayouts.first { $0.tabIDs == [nID, eID] }!
            let pinnedRoot = SidebarContainerLocation(spaceID: store.activeSpaceID, folderID: nil, section: .pinned)
            _ = try store.moveSidebarItem(.split(todaySplit.id), to: pinnedRoot, before: nil,
                expected: SidebarHierarchySnapshot(state: store.state, spaceID: store.activeSpaceID, profileID: b.f.profile)!)
            split = store.state.splitLayouts.first { $0.tabIDs == [nID, eID] }!
            let now = b.clock.now
            cache.recordSelection([b.oldest], focusedTabID: b.oldest, state: store.state, at: now)
            cache.recordSelection([n, e], focusedTabID: e, state: store.state, at: now + 1)
            groupIntent = b.f.intent([n, e, b.oldest], focus: e)
        }
    }

    @Test func aSavedSplitAndOtherRootsShareOneExactRetirementRequestAndPendingConsentPublishesNothing() throws {
        let t = try TypedSplit()
        let store = t.b.f.store
        let cache = t.cache
        var done: ((Bool) -> Void)?, validate: (() -> Bool)?, committed = false, original = true
        var requested = Set<UUID>()
        store.requestPageRetirement = { ids, check, reply in requested = ids; validate = check; done = reply }
        store.closeTabs([t.n, t.e, t.b.oldest], shouldCommit: { original }) { allowed in
            committed = allowed
            if allowed { cache.record(t.groupIntent, in: store.state) }
        }
        #expect(requested == Set([t.n, t.e, t.b.oldest]))
        #expect(cache.next(in: store.state) == nil)
        original = false
        #expect(validate?() == false)
        done?(true)
        #expect(!committed)
        #expect(cache.next(in: store.state) == nil)
    }

    func committedClose(_ t: TypedSplit) throws -> (ClosedItemRecord, ClosedWindow) {
        let store = t.b.f.store
        let cache = t.cache
        var done: ((Bool) -> Void)?, validate: (() -> Bool)?
        store.requestPageRetirement = { _, check, reply in validate = check; done = reply }
        let groupIntent = t.groupIntent
        store.closeTabs([t.n, t.e, t.b.oldest], shouldCommit: { true }) { allowed in
            if allowed { cache.record(groupIntent, in: store.state) }
        }
        #expect(validate?() == true)
        done?(true)
        store.requestPageRetirement = nil
        return (try #require(cache.next(in: store.state)), cache)
    }

    @Test func aCommittedOriginalSavedSplitKeepsItsGroupFocusAndGeometry() throws {
        let t = try TypedSplit()
        let (closed, _) = try committedClose(t)
        let store = t.b.f.store
        #expect(closed.tabIDs == [t.n, t.e])
        #expect(closed.split == t.split)
        #expect(closed.focusedTabID == t.e)
        #expect(store.state.splitLayouts.filter { $0.id == t.split.id } == [t.split])
    }

    @Test func aChangedOrDissolvedSplitExpiresTheSavedCapabilityAndCannotDegradeIntoASingleton() throws {
        let t = try TypedSplit()
        let (closed, _) = try committedClose(t)
        let store = t.b.f.store
        var invalid = store.state
        invalid.splitLayouts[invalid.splitLayouts.firstIndex { $0.id == t.split.id }!].widthFactors = [0.5, 0.5]
        #expect(!closed.isValid(in: invalid))
        invalid = store.state
        invalid.splitLayouts.removeAll { $0.id == t.split.id }
        #expect(!closed.isValid(in: invalid))
        let noChangedGroup = ClosedWindow()
        noChangedGroup.recordSelection([t.n, t.e], focusedTabID: t.e, state: store.state, at: t.b.clock.now + 1)
        noChangedGroup.record(t.groupIntent, in: invalid)
        #expect(noChangedGroup.next(in: invalid) == nil)
    }

    @Test func visitingAnyRetainedGroupChildConsumesSavedPriority() throws {
        let t = try TypedSplit()
        let (_, cache) = try committedClose(t)
        let revisit = cache.copy()
        revisit.selected([t.n])
        #expect(revisit.next(in: t.b.f.store.state) == nil)
    }

    @Test func aWholeSavedSplitRestoresDurablySelectsOriginalChildrenAndConsumesOnce() throws {
        let t = try TypedSplit()
        let (closed, cache) = try committedClose(t)
        let store = t.b.f.store
        #expect(try store.restoreClosedItem(closed))
        #expect(store.state.selectedTabIDs == [t.n, t.e])
        #expect(store.state.splitLayouts.filter { $0.id == t.split.id } == [t.split])
        #expect(cache.consume(closed))
        #expect(cache.next(in: store.state) == nil)
        let disk = try BrowserStore(directory: t.b.f.directory)
        #expect(disk.state.splitLayouts.filter { $0.id == t.split.id } == [t.split])
    }

    @Test func savedTypedRestorationNeverChangesDocumentBytesAndReopensOriginalDocumentIDs() throws {
        let t = try TypedSplit()
        let (closed, _) = try committedClose(t)
        let store = t.b.f.store
        _ = try store.restoreClosedItem(closed)
        #expect(try Data(contentsOf: t.notePath) == t.noteBytes)
        #expect(try Data(contentsOf: t.easelPath) == t.easelBytes)
        #expect(try t.easels.load(t.easel.document.id) === t.easel)
        #expect(store.state.tabs.first { $0.id == t.n }?.url == InternalPage.note(t.notePath).urlString)
        #expect(store.state.tabs.first { $0.id == t.e }?.url == InternalPage.easel(t.easel.document.id).urlString)
    }
}
