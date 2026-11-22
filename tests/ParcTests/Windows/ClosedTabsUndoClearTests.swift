import AppKit
import Foundation
import Testing
@testable import ParcCore
@testable import ParcKit
@testable import ParcSidebar

@MainActor
struct ClosedTabsUndoClearTests {
    @Test func clearWaitsForPageConsentWithoutMutation() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        f.clear(f.here)
        #expect(f.committed == nil && f.record == nil && f.store.state == f.initial)
    }

    @Test func refusedConsentClearsNothingAndRecordsNoUndo() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        f.clear(f.here)
        f.consent.finish?(false)
        #expect(f.committed == false && f.record == nil && f.store.state == f.initial)
    }

    @Test func originalPagesAdmitTheClear() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        f.clear(f.here)
        #expect(f.consent.authorize?() == true)
    }

    @Test func clearArchivesEveryTodayTabWithTheClearButtonReason() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        _ = f.approvedClear()
        #expect(f.committed == true)
        #expect(f.store.state.tabs.filter { f.hereIDs.contains($0.id) }.allSatisfy {
            $0.archivedAt != nil && $0.archiveProvenance?.reason == .clearButton
        })
    }

    @Test func theSplitArchivesAsOneItemAndLeavesTheSidebar() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        _ = f.approvedClear()
        let cleared = f.store.state
        let leftProvenance = cleared.tabs.first { $0.id == f.left.id }?.archiveProvenance
        #expect(leftProvenance?.groupID != nil && leftProvenance?.groupID == cleared.tabs.first { $0.id == f.right.id }?.archiveProvenance?.groupID)
        #expect(leftProvenance?.split == f.split && cleared.splitLayouts.isEmpty)
    }

    @Test func clearSelectsTheNextItemHereThePinnedTabAsAnyCloseDoes() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        _ = f.approvedClear()
        let cleared = f.store.state
        let pinnedNow = try #require(cleared.tabs.first { $0.id == f.pinned.id })
        var stamped = f.pinned
        stamped.lastAccessed = pinnedNow.lastAccessed
        stamped.isUnread = pinnedNow.isUnread
        #expect(cleared.selectedTabIDs == [f.pinned.id] && pinnedNow == stamped)
    }

    @Test func pinnedItemsFoldersTheOtherSpaceAndTheEarlierArchiveAreUntouched() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        _ = f.approvedClear()
        let cleared = f.store.state
        #expect([f.filed, f.elsewhere, f.elsewhereToo, f.earlier].allSatisfy { cleared.tabs.contains($0) } && cleared.folders == [f.folder])
        #expect(cleared.sidebarItemOrder[f.pinnedList.key] == f.initial.sidebarItemOrder[f.pinnedList.key])
    }

    @Test func theTodayListIsEmptyAfterClear() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        _ = f.approvedClear()
        #expect(SidebarHierarchy.children(in: f.today, state: f.store.state).isEmpty)
    }

    @Test func theRecordHoldsTheOriginalsTheSplitAndTheTodayOrder() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let record = f.approvedClear()
        #expect(record.actionName == "Clear Tabs" && record.tabs.count == 4 && record.groups == [f.split])
        #expect(record.order == SidebarHierarchy.children(in: f.today, state: f.initial))
    }

    @Test func aCloseThatTookNothingOutOfTheSidebarHasNoUndo() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        #expect(ClosedTabsUndo(prompt: .clear, ids: [f.first.id], spaceID: f.here.id, profileID: f.profile.id, focusedTabID: nil,
                               before: f.initial, after: f.initial) == nil)
    }

    @Test func oneTabNamesClearTab() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        var lone = f.initial
        lone.tabs.removeAll { $0.id == f.right.id || $0.id == f.left.id || $0.id == f.last.id }
        lone.splitLayouts = []
        var loneCleared = lone
        loneCleared.tabs[loneCleared.tabs.firstIndex { $0.id == f.first.id }!].archivedAt = Date()
        #expect(ClosedTabsUndo(prompt: .clear, ids: [f.first.id], spaceID: f.here.id, profileID: f.profile.id, focusedTabID: nil,
                               before: lone, after: loneCleared)?.actionName == "Clear Tab")
    }

    @Test func theToastReadsClearedTabsUseCommandZToUndo() {
        let content = ParcToastContent.clearedTabs
        #expect(content.body == .shortcut(leading: "Cleared Tabs! Use", shortcut: "⌘Z", trailing: "to undo."))
        #expect(content.accessibilityText == "Cleared Tabs! Use ⌘Z to undo." && content.showsShortcut)
    }

    @Test func clearAlsoLeavesReopenClosedTabSteps() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        var closedItems = WindowClosedItems()
        let intent = try #require(ClosedItemIntent(ids: f.hereIDs, state: f.initial, spaceID: f.here.id, profileID: f.profile.id, focusedTabID: f.first.id))
        _ = f.approvedClear()
        closedItems.record(intent, in: f.store.state)
        #expect(closedItems.nextStep(in: f.store.state, restorable: { _ in false }) != nil)
    }

    @Test func everyRestoredTabIsARedoTarget() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let record = f.approvedClear()
        let window = FolderUndoManager()
        _ = f.register(record, in: window)
        window.undo()
        #expect(record.redoIDs(in: f.store.state) == f.hereIDs)
    }
}
