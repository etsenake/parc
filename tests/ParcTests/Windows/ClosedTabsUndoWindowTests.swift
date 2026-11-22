import AppKit
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct ClosedTabsUndoWindowTests {
    @Test func aCommittedClearRegistersOnTheWindowsUndoAndTheEditMenuReadsUndoClearTabs() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let record = f.approvedClear()
        let window = FolderUndoManager()
        #expect(f.register(record, in: window))
        #expect(window.canUndo && window.undoMenuItemTitle == "Undo Clear Tabs")
    }

    @Test func aBusyWindowOwnerDisablesUndo() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let (_, window) = f.registeredClear()
        f.consent.usable = false
        #expect(!window.canUndo)
    }

    @Test func undoReturnsWhenTheWindowOwnerIsAvailable() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let (_, window) = f.registeredClear()
        f.consent.usable = false
        f.consent.usable = true
        #expect(window.canUndo)
    }

    @Test func undoCommitsAndRestoresTheExactPreClearRecordsAndSplit() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let (_, window) = f.registeredClear()
        window.undo()
        let restored = f.store.state
        #expect(f.consent.undone == 1 && !window.isBusy && f.consent.errors.isEmpty)
        #expect(f.initial.tabs.filter { f.hereIDs.contains($0.id) }.allSatisfy { restored.tabs.contains($0) })
        #expect(restored.splitLayouts == [f.split])
        #expect(SidebarHierarchy.children(in: f.today, state: restored) == SidebarHierarchy.children(in: f.today, state: f.initial))
    }

    @Test func undoRestoresIntoTheClearedSpaceWithoutSelecting() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let (_, window) = f.registeredClear()
        let beforeUndo = f.store.state
        window.undo()
        let restored = f.store.state
        #expect(restored.activeSpaceID == f.there.id && restored.selectedTabIDs == beforeUndo.selectedTabIDs
                && restored.selectionBySpace == beforeUndo.selectionBySpace)
    }

    @Test func undoTouchesOnlyTheClearedTabs() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let (_, window) = f.registeredClear()
        let beforeUndo = f.store.state
        window.undo()
        let restored = f.store.state
        #expect(restored.recentlyClosedIDs.allSatisfy { !f.hereIDs.contains($0) } && restored.tabs.contains(f.earlier))
        #expect(restored.tabs.filter { !f.hereIDs.contains($0.id) } == beforeUndo.tabs.filter { !f.hereIDs.contains($0.id) })
        #expect(restored.folders == beforeUndo.folders)
    }

    @Test func undoIsOnDiskBeforeItPublishes() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let (_, window) = f.registeredClear()
        window.undo()
        let reloaded = try BrowserStore(directory: f.root)
        let restored = f.store.state
        #expect(reloaded.state.tabs == restored.tabs && reloaded.state.splitLayouts == restored.splitLayouts
                && reloaded.state.sidebarItemOrder == restored.sidebarItemOrder)
    }

    @Test func undoExpiresTheClearsReopenSteps() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        var closedItems = WindowClosedItems()
        let intent = try #require(ClosedItemIntent(ids: f.hereIDs, state: f.initial, spaceID: f.here.id, profileID: f.profile.id, focusedTabID: f.first.id))
        let (_, window) = f.registeredClear()
        closedItems.record(intent, in: f.store.state)
        window.undo()
        #expect(closedItems.nextStep(in: f.store.state, restorable: { _ in false }) == nil)
    }

    @Test func redoClearTabsFollowsUndo() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let (_, window) = f.registeredClear()
        window.undo()
        #expect(window.canRedo && !window.canUndo && window.redoMenuItemTitle == "Redo Clear Tabs")
    }

    @Test func redoWaitsForFreshPageConsent() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let (_, window) = f.registeredClear()
        window.undo()
        let restored = f.store.state
        window.redo()
        #expect(window.isBusy && f.store.state == restored)
    }

    @Test func aRefusedRedoKeepsTheTabsAndTheRedo() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let (_, window) = f.registeredClear()
        window.undo()
        let restored = f.store.state
        window.redo()
        f.consent.finish?(false)
        #expect(!window.isBusy && window.canRedo && f.store.state == restored)
        #expect(f.consent.redoCurrent?() == true)
    }

    @Test func redoArchivesAgainAsAManualCloseAndLeavesAnotherSpacesSelectionAlone() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let (_, window) = f.registeredClear()
        window.undo()
        let restored = f.store.state
        window.redo()
        f.consent.approve()
        let redone = f.store.state
        #expect(f.hereIDs.allSatisfy { id in redone.tabs.first { $0.id == id }?.archiveProvenance?.reason == .manual })
        #expect(redone.splitLayouts.isEmpty && redone.activeSpaceID == f.there.id && redone.selectedTabIDs == restored.selectedTabIDs)
    }

    @Test func redoReturnsTheGroupToUndo() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let (_, window) = f.registeredClear()
        window.undo()
        window.redo()
        f.consent.approve()
        #expect(window.canUndo && !window.canRedo && window.undoMenuItemTitle == "Undo Clear Tabs")
    }

    @Test func undoAfterRedoRestoresTheRedoneClose() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let (_, window) = f.registeredClear()
        window.undo()
        window.redo()
        f.consent.approve()
        window.undo()
        #expect(f.initial.tabs.filter { f.hereIDs.contains($0.id) }.allSatisfy { f.store.state.tabs.contains($0) })
        #expect(f.store.state.splitLayouts == [f.split])
        #expect(SidebarHierarchy.children(in: f.today, state: f.store.state) == SidebarHierarchy.children(in: f.today, state: f.initial))
    }

    @Test func clearsInBothSpacesRegisterUndo() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let hereRecord = f.autoClear(f.here)
        f.goToThere()
        let thereRecord = f.autoClear(f.there)
        let stack = FolderUndoManager()
        #expect(f.register(hereRecord, in: stack) && f.register(thereRecord, in: stack))
    }

    @Test func theLaterClearUndoesFirstAndItsSpacesOrderReturns() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let hereRecord = f.autoClear(f.here)
        f.goToThere()
        let thereRecord = f.autoClear(f.there)
        let stack = FolderUndoManager()
        _ = f.register(hereRecord, in: stack) && f.register(thereRecord, in: stack)
        stack.undo()
        #expect(f.todayIDs(f.there) == [f.elsewhere.id, f.elsewhereToo.id] && f.todayIDs(f.here).isEmpty)
        #expect(SidebarHierarchy.children(in: f.thereToday, state: f.store.state) == SidebarHierarchy.children(in: f.thereToday, state: f.initial))
    }

    @Test func theSecondUndoRestoresTheEarlierClear() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let hereRecord = f.autoClear(f.here)
        f.goToThere()
        let thereRecord = f.autoClear(f.there)
        let stack = FolderUndoManager()
        _ = f.register(hereRecord, in: stack)
        _ = f.register(thereRecord, in: stack)
        stack.undo()
        stack.undo()
        #expect(f.todayIDs(f.here) == f.hereIDs && f.store.state.splitLayouts == [f.split])
    }

    @Test func bothWindowsRegisterTheirOwnClear() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let windowA = f.autoClear(f.here)
        let windowB = f.autoClear(f.there)
        let firstWindow = FolderUndoManager(), secondWindow = FolderUndoManager()
        #expect(f.register(windowA, in: firstWindow) && f.register(windowB, in: secondWindow))
    }

    @Test func undoInOneWindowLeavesTheOtherWindowsClear() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let windowA = f.autoClear(f.here)
        let windowB = f.autoClear(f.there)
        let firstWindow = FolderUndoManager(), secondWindow = FolderUndoManager()
        _ = f.register(windowA, in: firstWindow) && f.register(windowB, in: secondWindow)
        firstWindow.undo()
        #expect(f.todayIDs(f.here) == f.hereIDs && f.todayIDs(f.there).isEmpty && secondWindow.canUndo && !firstWindow.canUndo)
    }

    @Test func undoInTheSecondWindowRestoresItsOwnClear() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let windowA = f.autoClear(f.here)
        let windowB = f.autoClear(f.there)
        let firstWindow = FolderUndoManager(), secondWindow = FolderUndoManager()
        _ = f.register(windowA, in: firstWindow) && f.register(windowB, in: secondWindow)
        firstWindow.undo()
        secondWindow.undo()
        #expect(f.todayIDs(f.there) == [f.elsewhere.id, f.elsewhereToo.id])
    }
}
