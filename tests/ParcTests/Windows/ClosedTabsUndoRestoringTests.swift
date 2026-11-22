import AppKit
import Foundation
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct ClosedTabsUndoRestoringTests {
    private func cleared() throws -> (ClosedTabsUndoSupport.ClearFixture, ClosedTabsUndo, BrowserState) {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let record = f.approvedClear()
        return (f, record, f.store.state)
    }

    @Test func anArchivedTabEditedSinceComesBackWithItsEdits() throws {
        let (f, record, cleared) = try cleared()
        var edited = cleared
        if let index = edited.tabs.firstIndex(where: { $0.id == f.first.id }) {
            edited.tabs[index].title = "Edited in the Library"
            edited.tabs[index].url = "https://edited.invalid/"
        }
        let editedBack = try #require(record.restoring(edited)?.tabs.first { $0.id == f.first.id })
        #expect(record.restorableIDs(in: edited).contains(f.first.id) && editedBack.title == "Edited in the Library")
        #expect(editedBack.url == "https://edited.invalid/" && editedBack.archivedAt == nil && editedBack.archiveProvenance == nil
                && editedBack.kind == .today)
    }

    @Test func aTabArchivedAgainSinceIsNotThisClears() throws {
        let (f, record, cleared) = try cleared()
        var rearchived = cleared
        if let index = rearchived.tabs.firstIndex(where: { $0.id == f.first.id }) {
            rearchived.tabs[index].archivedAt = Date(timeIntervalSince1970: 2_000_000_000)
        }
        #expect(!record.restorableIDs(in: rearchived).contains(f.first.id))
    }

    @Test func aSplitThatCannotRegroupReturnsItsRemainingPaneAloneInPlace() throws {
        let (f, record, cleared) = try cleared()
        var halfGone = cleared
        halfGone.tabs.removeAll { $0.id == f.right.id }
        let alone = try #require(record.restoring(halfGone))
        #expect(alone.splitLayouts.isEmpty)
        #expect(SidebarHierarchy.children(in: f.today, state: alone) == [.tab(f.last.id), .tab(f.left.id), .tab(f.first.id)])
    }

    @Test func restoredItemsTakeTheirPlacesAroundATabOpenedSince() throws {
        let (f, record, cleared) = try cleared()
        var joined = cleared
        let later = ClosedTabsUndoSupport.makeTab("Later", f.here, profile: f.profile)
        joined.tabs.append(later)
        joined.sidebarItemOrder[f.today.key] = [.tab(later.id)]
        let survivor = try #require(record.restoring(joined))
        #expect(SidebarHierarchy.children(in: f.today, state: survivor) == [.tab(f.last.id), .split(f.split.id), .tab(f.first.id), .tab(later.id)])
    }

    private struct Partial {
        let f: ClosedTabsUndoSupport.ClearFixture
        let record: ClosedTabsUndo
        let reopened: Set<UUID>
        let deleted: UUID
        let window: FolderUndoManager
    }

    private func partial() throws -> Partial {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        f.consent.autoApprove = true
        let intent = try #require(ClosedItemIntent(ids: f.hereIDs, state: f.store.state, spaceID: f.here.id, profileID: f.profile.id, focusedTabID: nil))
        f.clear(f.here)
        let record = try #require(f.record)
        var reopen = WindowClosedItems()
        reopen.record(intent, in: f.store.state)
        guard case .items(let step)? = reopen.nextStep(in: f.store.state, restorable: { _ in false }) else {
            throw CloseUndoFailure("Expected Reopen step")
        }
        #expect(try f.store.restoreClosedItem(step))
        let reopened = Set(step.tabIDs)
        let deleted = try #require([f.first.id, f.last.id].first { !reopened.contains($0) })
        f.store.deleteArchivedTabs([deleted])
        let window = FolderUndoManager()
        #expect(f.register(record, in: window) && window.canUndo)
        f.consent.lastOperation?.didReopen(step)
        return Partial(f: f, record: record, reopened: reopened, deleted: deleted, window: window)
    }

    private struct CloseUndoFailure: Error { let message: String; init(_ message: String) { self.message = message } }

    @Test func oneClearedTabIsDeletedFromTheArchive() throws {
        let p = try partial()
        #expect(!p.f.store.state.tabs.contains { $0.id == p.deleted })
    }

    @Test func undoRestoresTheTabsStillArchivedAsClearedAndLeavesReopenedAndDeletedAsTheyWere() throws {
        let p = try partial()
        let reopenedRecords = p.f.store.state.tabs.filter { p.reopened.contains($0.id) }
        p.window.undo()
        let remaining = p.f.hereIDs.subtracting(p.reopened).subtracting([p.deleted])
        #expect(remaining.allSatisfy { id in p.f.store.state.tabs.contains(p.f.initial.tabs.first { $0.id == id }!) })
        #expect(reopenedRecords.allSatisfy { p.f.store.state.tabs.contains($0) } && !p.f.store.state.tabs.contains { $0.id == p.deleted })
    }

    @Test func eachLiveTodayTabAppearsOnce() throws {
        let p = try partial()
        p.window.undo()
        let f = p.f
        let order = SidebarHierarchy.children(in: f.today, state: f.store.state)
        #expect(Set(order).count == order.count)
        #expect(order.flatMap { SidebarHierarchy.tabIDs(in: $0, state: f.store.state, spaceID: f.here.id) }.count == f.todayIDs(f.here).count)
    }

    @Test func redoIsNamedByTheGroupsRemainingItems() throws {
        let p = try partial()
        p.window.undo()
        #expect(p.window.redoMenuItemTitle == "Redo " + ClosedTabsUndo.Prompt.clear.name(count: p.record.itemCount(of: p.f.hereIDs.subtracting(p.reopened))))
    }

    @Test func redoArchivesOnlyWhatUndoRestoredAndTheRedoneCloseIsNamedByItsOwnItems() throws {
        let p = try partial()
        p.window.undo()
        p.window.redo()
        let f = p.f
        let remaining = f.hereIDs.subtracting(p.reopened).subtracting([p.deleted])
        #expect(p.reopened.allSatisfy { id in f.store.state.tabs.contains { $0.id == id && $0.archivedAt == nil } }
                && remaining.allSatisfy { id in f.store.state.tabs.contains { $0.id == id && $0.archivedAt != nil } })
        #expect(p.window.undoMenuItemTitle == "Undo " + ClosedTabsUndo.Prompt.clear.name(
            count: remaining.count + (remaining.isSuperset(of: [f.left.id, f.right.id]) ? 1 : 0)))
    }

    @Test func undoAfterThatRedoRestoresTheSameTabs() throws {
        let p = try partial()
        p.window.undo()
        p.window.redo()
        p.window.undo()
        let remaining = p.f.hereIDs.subtracting(p.reopened).subtracting([p.deleted])
        #expect(remaining.isSubset(of: p.f.todayIDs(p.f.here)))
    }

    @Test func redoNeverArchivesATabPinnedSince() throws {
        let p = try partial()
        p.window.undo()
        var moved = p.f.store.state
        let remaining = p.f.hereIDs.subtracting(p.reopened).subtracting([p.deleted])
        if let index = moved.tabs.firstIndex(where: { $0.id == remaining.first }) { moved.tabs[index].kind = .pinned }
        #expect(!p.record.redoIDs(in: moved).contains(remaining.first ?? UUID()))
    }

    private func putBack() throws -> (ClosedTabsUndoSupport.ClearFixture, FolderUndoManager, Set<UUID>, UUID) {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let live = f.todayIDs(f.here)
        let record = f.autoClear(f.here)
        let window = FolderUndoManager()
        #expect(f.register(record, in: window))
        let returned = try #require([f.first.id, f.last.id].first { live.contains($0) })
        #expect(!f.store.restoreArchivedTab(returned, destination: .putBack(currentSpaceID: f.here.id, requestedSpaceID: f.here.id)).isEmpty
                && f.store.state.tabs.contains { $0.id == returned && $0.archivedAt == nil })
        return (f, window, live, returned)
    }

    @Test func undoRestoresTheRestAfterAPutBack() throws {
        let (f, window, live, _) = try putBack()
        window.undo()
        #expect(f.todayIDs(f.here) == live)
    }

    @Test func redoArchivesThePutBackTabAgain() throws {
        let (f, window, live, _) = try putBack()
        window.undo()
        window.redo()
        #expect(live.allSatisfy { id in f.store.state.tabs.contains { $0.id == id && $0.archivedAt != nil } })
    }

    @Test func undoRestoresThemAllAgain() throws {
        let (f, window, live, _) = try putBack()
        window.undo()
        window.redo()
        window.undo()
        #expect(f.todayIDs(f.here) == live)
    }
}
