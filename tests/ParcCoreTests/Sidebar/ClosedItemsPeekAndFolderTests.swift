import Combine
import Foundation
import Testing
@testable import ParcCore

extension ClosedItemsTestsSupport {
    @MainActor
    struct ClosedItemsPeekAndFolderTests {
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

        @Test func aLocalFilePeekCannotReopen() throws {
            let f = try Fixture(now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let parent = f.store.open("https://parent.invalid")
            let local = ClosedPeekRecord(id: UUID(), url: URL(string: "file:///tmp/peek")!, parentTabID: parent, profileID: f.profile)
            #expect(!local.isValid(in: f.store.state))
        }

        @Test func aPeekOnAProfileBeingRemovedCannotReopen() throws {
            let f = try Fixture(now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let parent = f.store.open("https://parent.invalid")
            let peek = ClosedPeekRecord(id: UUID(), url: URL(string: "https://peek.invalid/current")!, parentTabID: parent, profileID: f.profile)
            var removing = f.store.state
            removing.profileRemovals.append(ProfileRemovalRecord(id: UUID(), profileID: f.profile, profileName: "Removing"))
            #expect(!peek.isValid(in: removing))
        }

        @Test func onlyTheExactPeekStepConsumesTheCacheEntry() throws {
            let f = try Fixture(now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let cache = ClosedWindow()
            let parent = f.store.open("https://parent.invalid")
            let peek = ClosedPeekRecord(id: UUID(), url: URL(string: "https://peek.invalid/current")!, parentTabID: parent, profileID: f.profile)
            cache.recordPeek(peek, in: f.store.state)
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
    }
}
