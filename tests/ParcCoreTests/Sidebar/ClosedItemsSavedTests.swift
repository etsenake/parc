import Combine
import Foundation
import Testing
@testable import ParcCore

extension ClosedItemsTestsSupport {
    @MainActor
    struct ClosedItemsSavedTests {
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

        @Test func equalSavedCloseDatesUseStableModelOrder() throws {
            let b = try Bulk()
            let store = b.f.store
            let equal = ClosedWindow()
            let now = b.clock.now
            equal.recordSelection([b.recent], focusedTabID: b.recent, state: store.state, at: now)
            equal.recordSelection([b.oldest], focusedTabID: b.oldest, state: store.state, at: now)
            let tied = b.f.intent([b.oldest, b.recent])
            store.closeTabs([b.oldest, b.recent])
            equal.record(tied, in: store.state)
            #expect(equal.next(in: store.state)?.tabIDs == [b.oldest])
        }

        @Test func missingSavedCloseDatesFallBackToStableModelOrder() throws {
            let b = try Bulk()
            let store = b.f.store
            let unseen = ClosedWindow()
            let tied = b.f.intent([b.oldest, b.recent])
            store.closeTabs([b.oldest, b.recent])
            unseen.record(tied, in: store.state)
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

        @Test func aFailedBulkReopenKeepsItsRecordAndTheOriginalSelection() throws {
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
        }

        @Test func retryingABulkReopenCommitsTheOriginalRecordBeforeConsumption() throws {
            let b = try Bulk()
            let store = b.f.store
            let bulk = b.f.intent([b.oldest, b.recent, b.newestShared])
            store.closeTabs([b.oldest, b.recent, b.newestShared])
            b.first.record(bulk, in: store.state)
            let retry = try #require(b.first.next(in: store.state))
            try store.save()
            let file = b.f.directory.appendingPathComponent("session.json"), backup = b.f.directory.appendingPathComponent("backup.json")
            try FileManager.default.moveItem(at: file, to: backup)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            _ = try? store.restoreClosedItem(retry)
            try FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: backup, to: file)
            #expect(try store.restoreClosedItem(retry))
            #expect(b.first.consume(retry))
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

        @Test func aCommittedOriginalSavedSplitKeepsItsGroupFocusAndGeometry() throws {
            let t = try TypedSplit()
            let (closed, _) = try committedClose(t)
            let store = t.b.f.store
            #expect(closed.tabIDs == [t.n, t.e])
            #expect(closed.split == t.split)
            #expect(closed.focusedTabID == t.e)
            #expect(store.state.splitLayouts.filter { $0.id == t.split.id } == [t.split])
        }

        @Test func resizingASavedSplitExpiresItsCloseRecord() throws {
            let t = try TypedSplit()
            let (closed, _) = try committedClose(t)
            let store = t.b.f.store
            var invalid = store.state
            invalid.splitLayouts[invalid.splitLayouts.firstIndex { $0.id == t.split.id }!].widthFactors = [0.5, 0.5]
            #expect(!closed.isValid(in: invalid))
        }

        @Test func dissolvingASavedSplitExpiresItsCloseRecord() throws {
            let t = try TypedSplit()
            let (closed, _) = try committedClose(t)
            let store = t.b.f.store
            var invalid = store.state
            invalid.splitLayouts.removeAll { $0.id == t.split.id }
            #expect(!closed.isValid(in: invalid))
        }

        @Test func aDissolvedSavedSplitDoesNotBecomeASingleton() throws {
            let t = try TypedSplit()
            _ = try committedClose(t)
            let store = t.b.f.store
            var invalid = store.state
            invalid.splitLayouts.removeAll { $0.id == t.split.id }
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
}
