import AppKit
import Foundation
import Testing
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct ClosedTabsUndoFailureTests {
    private func failing() throws -> (ClosedTabsUndoSupport.ClearFixture, FolderUndoManager, Set<UUID>) {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        let live = f.todayIDs(f.here)
        _ = f.store.setWindowPresentation(spaceID: f.there.id, selectedTabIDs: [])
        let record = f.autoClear(f.here)
        let window = FolderUndoManager()
        #expect(f.register(record, in: window))
        return (f, window, live)
    }

    private func breakDisk(_ f: ClosedTabsUndoSupport.ClearFixture) throws -> Data {
        let bytes = try Data(contentsOf: f.sessionURL)
        try FileManager.default.removeItem(at: f.sessionURL)
        try FileManager.default.createDirectory(at: f.sessionURL, withIntermediateDirectories: false)
        return bytes
    }

    private func repair(_ f: ClosedTabsUndoSupport.ClearFixture, _ bytes: Data) throws {
        try FileManager.default.removeItem(at: f.sessionURL)
        try bytes.write(to: f.sessionURL)
    }

    @Test func aFailedWriteKeepsTheClearArchivedAndUndoRetryable() throws {
        let (f, window, _) = try failing()
        _ = try breakDisk(f)
        let archivedBefore = f.store.state
        window.undo()
        #expect(f.consent.errors.count == 1 && f.store.state == archivedBefore && window.canUndo)
    }

    @Test func retryRestores() throws {
        let (f, window, live) = try failing()
        let bytes = try breakDisk(f)
        window.undo()
        try repair(f, bytes)
        window.undo()
        #expect(f.todayIDs(f.here) == live && window.canRedo)
    }

    @Test func archivingTheRestoredTabsByHandRetiresTheRedo() throws {
        let (f, window, live) = try failing()
        window.undo()
        f.store.closeTabs(live, reason: .manual, shouldCommit: { true })
        #expect(!window.canRedo && !window.canUndo)
    }

    @Test func clearingTheOtherSpaceRegistersUndo() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        _ = f.store.setWindowPresentation(spaceID: f.there.id, selectedTabIDs: [])
        let record = f.autoClear(f.there)
        let busy = FolderUndoManager()
        #expect(f.register(record, in: busy))
    }

    @Test func redoingTheOtherSpacesClearWaitsForPageConsent() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        _ = f.store.setWindowPresentation(spaceID: f.there.id, selectedTabIDs: [])
        let record = f.autoClear(f.there)
        let busy = FolderUndoManager()
        _ = f.register(record, in: busy)
        f.consent.autoApprove = false
        busy.undo()
        busy.redo()
        #expect(busy.isBusy && busy.isRedoing)
    }

    @Test func approvingRedoReturnsTheOtherSpacesClearToUndo() throws {
        let f = try ClosedTabsUndoSupport.ClearFixture()
        _ = f.store.setWindowPresentation(spaceID: f.there.id, selectedTabIDs: [])
        let record = f.autoClear(f.there)
        let busy = FolderUndoManager()
        _ = f.register(record, in: busy)
        f.consent.autoApprove = false
        busy.undo()
        busy.redo()
        f.consent.approve()
        #expect(!busy.isBusy && busy.canUndo)
    }
}
