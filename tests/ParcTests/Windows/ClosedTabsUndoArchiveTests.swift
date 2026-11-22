import AppKit
import Foundation
import Testing
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct ClosedTabsUndoArchiveTests {
    @Test func theFixtureHasASplitBetweenTodayTabs() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        #expect(f.original == [.tab(f.t1.id), .split(f.duo.id), .tab(f.t2.id), .tab(f.t3.id)])
    }

    @Test func commandWOnTheFocusedTabIsOneArchiveTabGroupThatRemembersItsFocus() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        let focusedClose = try #require(f.close([f.t2.id], focused: f.t2.id))
        #expect(focusedClose.prompt == .archive && focusedClose.actionName == "Archive Tab" && focusedClose.focusedTabID == f.t2.id)
        #expect(f.store.state.tabs.first { $0.id == f.t2.id }?.archiveProvenance?.reason == .manual)
        #expect(f.register(focusedClose).undoMenuItemTitle == "Undo Archive Tab")
    }

    @Test func undoReturnsTheTabToItsPlaceAndTheStoreLeavesSelectionToTheWindow() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        let focusedClose = try #require(f.close([f.t2.id], focused: f.t2.id))
        let window = f.register(focusedClose)
        let selectedAfterClose = f.store.state.selectedTabIDs
        window.undo()
        #expect(f.order == f.original && f.store.state.tabs.contains(f.t2))
        #expect(f.store.state.selectedTabIDs == selectedAfterClose)
    }

    @Test func theWindowSelectsTheTabThatWasFocusedWhenItClosed() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        let focusedClose = try #require(f.close([f.t2.id], focused: f.t2.id))
        var presented = WindowPresentation(state: f.store.state, ready: true)
        f.register(focusedClose).undo()
        let finished = presented.finishClosedTabsUndo(focusedClose, state: f.store.state, available: { _ in true })
        #expect(finished && presented.selectedTabIDs == [f.t2.id])
    }

    @Test func undoAnArchiveOffersRedoArchiveTab() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        let focusedClose = try #require(f.close([f.t2.id], focused: f.t2.id))
        let window = f.register(focusedClose)
        window.undo()
        #expect(window.redoMenuItemTitle == "Redo Archive Tab")
    }

    @Test func redoRearchivesTheTabAndReturnsTheGroupToUndo() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        let focusedClose = try #require(f.close([f.t2.id], focused: f.t2.id))
        let window = f.register(focusedClose)
        window.undo()
        window.redo()
        #expect(f.store.state.tabs.first { $0.id == f.t2.id }?.archivedAt != nil && window.undoMenuItemTitle == "Undo Archive Tab")
    }

    @Test func closingABackgroundTabRecordsNoFocus() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        f.select([f.t1.id])
        let background = try #require(f.close([f.t3.id], focused: f.t1.id))
        #expect(background.focusedTabID == nil)
    }

    @Test func undoingABackgroundCloseLeavesSelectionAlone() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        f.select([f.t1.id])
        let background = try #require(f.close([f.t3.id], focused: f.t1.id))
        var unfocused = WindowPresentation(state: f.store.state, ready: true)
        f.register(background).undo()
        let selected = unfocused.finishClosedTabsUndo(background, state: f.store.state, available: { _ in true })
        #expect(f.order == f.original && !selected && unfocused.selectedTabIDs == [f.t1.id])
    }

    @Test func closingAPinnedTabOnlyUnloadsItSoItRegistersNoUndo() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        #expect(f.close([f.keep.id], focused: f.keep.id) == nil && f.store.state.tabs.contains { $0.id == f.keep.id && $0.archivedAt == nil })
    }

    @Test func aPaneWhoseCloseDissolvesItsSplitNamesTheSplitTooAndTheOtherPaneKeepsTheSlot() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        let paneClose = try #require(f.close([f.s1.id], focused: nil))
        #expect(paneClose.actionName == "Archive Tabs" && !f.store.state.splitLayouts.contains { $0.id == f.duo.id })
        #expect(f.order == [.tab(f.t1.id), .tab(f.s2.id), .tab(f.t2.id), .tab(f.t3.id)])
    }

    @Test func undoRegroupsTheSplitInItsSlot() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        let paneClose = try #require(f.close([f.s1.id], focused: nil))
        f.register(paneClose).undo()
        #expect(f.store.state.splitLayouts == [f.duo] && f.order == f.original)
    }

    @Test func aPinnedNoteOnlyUnloadsInItsFolderSoItRegistersNoUndoEither() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        #expect(f.close([f.note.id], focused: f.note.id) == nil)
        #expect(f.store.state.tabs.contains { $0.id == f.note.id && $0.archivedAt == nil && $0.kind == .pinned })
        #expect(SidebarHierarchy.children(in: f.shelfBox, state: f.store.state) == [.tab(f.note.id), .tab(f.shelved.id)])
    }

    @Test func theLaterArchiveSitsAboveTheClear() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        f.select([f.t2.id])
        let clearedAgain = try #require(f.close([f.t1.id, f.t3.id, f.s1.id, f.s2.id], focused: nil, prompt: .clear))
        let lastClose = try #require(f.close([f.t2.id], focused: f.t2.id))
        let ordered = f.register(clearedAgain)
        _ = f.register(lastClose, in: ordered)
        #expect(ordered.undoMenuItemTitle == "Undo Archive Tab")
    }

    @Test func theFirstUndoRestoresTheArchiveAndOffersTheClear() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        f.select([f.t2.id])
        let clearedAgain = try #require(f.close([f.t1.id, f.t3.id, f.s1.id, f.s2.id], focused: nil, prompt: .clear))
        let lastClose = try #require(f.close([f.t2.id], focused: f.t2.id))
        let ordered = f.register(clearedAgain)
        _ = f.register(lastClose, in: ordered)
        ordered.undo()
        #expect(f.store.state.tabs.contains { $0.id == f.t2.id && $0.archivedAt == nil }
                && f.store.state.tabs.first { $0.id == f.t1.id }?.archivedAt != nil && ordered.undoMenuItemTitle == "Undo Clear Tabs")
    }

    @Test func theNextUndoRestoresTheEarlierClear() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        f.select([f.t2.id])
        let clearedAgain = try #require(f.close([f.t1.id, f.t3.id, f.s1.id, f.s2.id], focused: nil, prompt: .clear))
        let lastClose = try #require(f.close([f.t2.id], focused: f.t2.id))
        let ordered = f.register(clearedAgain)
        _ = f.register(lastClose, in: ordered)
        ordered.undo()
        ordered.undo()
        #expect(f.order == f.original)
    }

    @Test func aMixedCloseArchivesOnlyTheTodayTab() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        let mixedClose = try #require(f.close([f.keep.id, f.t3.id], focused: nil))
        #expect(mixedClose.tabs.map(\.id) == [f.t3.id] && mixedClose.actionName == "Archive Tab")
        #expect(f.store.state.tabs.contains { $0.id == f.keep.id && $0.archivedAt == nil && $0.kind == .pinned })
    }

    @Test func undoingAMixedCloseRestoresTheTodayTabAndLeavesThePin() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        let mixedClose = try #require(f.close([f.keep.id, f.t3.id], focused: nil))
        f.register(mixedClose).undo()
        #expect(f.store.state.tabs.contains { $0.id == f.t3.id && $0.archivedAt == nil }
                && f.store.state.tabs.contains { $0.id == f.keep.id && $0.archivedAt == nil && $0.kind == .pinned })
    }

    @Test func clearRemembersTheFocusedTodayTab() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        f.select([f.t2.id])
        let todayLive = Set(f.store.state.tabs.filter { $0.archivedAt == nil && $0.kind == .today && $0.spaceID == f.work.id }.map(\.id))
        let focusedClear = try #require(f.close(todayLive, focused: f.t2.id, prompt: .clear))
        #expect(todayLive.contains(f.t2.id) && focusedClear.prompt == .clear && focusedClear.focusedTabID == f.t2.id)
    }

    @Test func undoClearSelectsThePreviouslyFocusedTodayTab() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        f.select([f.t2.id])
        let todayLive = Set(f.store.state.tabs.filter { $0.archivedAt == nil && $0.kind == .today && $0.spaceID == f.work.id }.map(\.id))
        let focusedClear = try #require(f.close(todayLive, focused: f.t2.id, prompt: .clear))
        var afterClear = WindowPresentation(state: f.store.state, ready: true)
        f.register(focusedClear).undo()
        let finished = afterClear.finishClosedTabsUndo(focusedClear, state: f.store.state, available: { _ in true })
        #expect(finished && afterClear.selectedTabIDs == [f.t2.id])
    }

    @Test func undoRestoresTheClearedArchiveOrder() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        let cleanAll = try #require(f.close([f.t1.id, f.t3.id, f.s1.id, f.s2.id, f.t2.id], focused: nil, prompt: .clear))
        f.register(cleanAll).undo()
        #expect(f.order == f.original)
    }

    @Test func redoStaysInProgressUntilConsent() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        let deferred = FolderUndoManager()
        let first = try #require(f.close([f.t1.id], focused: nil))
        _ = f.register(first, in: deferred)
        deferred.undo()
        f.consent.autoApprove = false
        deferred.redo()
        #expect(deferred.isRedoing)
    }

    @Test func aNewUndoGroupWaitsWithoutAToastDuringRedo() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        let deferred = FolderUndoManager()
        let first = try #require(f.close([f.t1.id], focused: nil))
        _ = f.register(first, in: deferred)
        deferred.undo()
        f.consent.autoApprove = false
        deferred.redo()
        f.consent.autoApprove = true
        let meanwhile = try #require(f.close([f.t3.id], focused: nil))
        #expect(!f.consent.register(meanwhile, in: deferred, on: f.store) && f.consent.lastOperation == nil)
    }

    @Test func aWaitingUndoGroupRegistersWhenRedoFinishes() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        let deferred = FolderUndoManager()
        let first = try #require(f.close([f.t1.id], focused: nil))
        _ = f.register(first, in: deferred)
        deferred.undo()
        f.consent.autoApprove = false
        deferred.redo()
        f.consent.autoApprove = true
        let meanwhile = try #require(f.close([f.t3.id], focused: nil))
        _ = f.consent.register(meanwhile, in: deferred, on: f.store)
        f.consent.approve()
        #expect(f.consent.lastOperation != nil && !deferred.isBusy)
    }

    @Test func theRedoneCloseUndoesBeforeTheCloseThatCommittedDuringIt() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        let deferred = FolderUndoManager()
        let first = try #require(f.close([f.t1.id], focused: nil))
        _ = f.register(first, in: deferred)
        deferred.undo()
        f.consent.autoApprove = false
        deferred.redo()
        f.consent.autoApprove = true
        let meanwhile = try #require(f.close([f.t3.id], focused: nil))
        _ = f.consent.register(meanwhile, in: deferred, on: f.store)
        f.consent.approve()
        deferred.undo()
        #expect(f.store.state.tabs.contains { $0.id == f.t1.id && $0.archivedAt == nil } && f.store.state.tabs.first { $0.id == f.t3.id }?.archivedAt != nil)
    }

    @Test func theNextUndoRestoresTheCloseThatCommittedDuringRedo() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        let deferred = FolderUndoManager()
        let first = try #require(f.close([f.t1.id], focused: nil))
        _ = f.register(first, in: deferred)
        deferred.undo()
        f.consent.autoApprove = false
        deferred.redo()
        f.consent.autoApprove = true
        let meanwhile = try #require(f.close([f.t3.id], focused: nil))
        _ = f.consent.register(meanwhile, in: deferred, on: f.store)
        f.consent.approve()
        deferred.undo()
        deferred.undo()
        #expect(f.order == f.original)
    }

    @Test func aRefusedRedoLetsTheWaitingGroupIn() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        let window = FolderUndoManager()
        let second = try #require(f.close([f.t1.id], focused: nil))
        _ = f.register(second, in: window)
        window.undo()
        f.consent.autoApprove = false
        window.redo()
        f.consent.autoApprove = true
        let meanwhile = try #require(f.close([f.t3.id], focused: nil))
        _ = f.consent.register(meanwhile, in: window, on: f.store)
        f.consent.finish?(false)
        #expect(!window.isBusy && !window.canRedo && window.canUndo)
    }

    @Test func undoRestoresTheWaitingGroupAfterRedoIsRefused() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        let window = FolderUndoManager()
        let second = try #require(f.close([f.t1.id], focused: nil))
        _ = f.register(second, in: window)
        window.undo()
        f.consent.autoApprove = false
        window.redo()
        f.consent.autoApprove = true
        let meanwhile = try #require(f.close([f.t3.id], focused: nil))
        _ = f.consent.register(meanwhile, in: window, on: f.store)
        f.consent.finish?(false)
        window.undo()
        #expect(f.order == f.original)
    }
}
