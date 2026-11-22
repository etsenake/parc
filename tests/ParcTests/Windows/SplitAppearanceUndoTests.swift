import AppKit
import CoreText
import Testing
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SplitAppearanceUndoTests {
    private final class Availability {
        var available = true
        var errors = 0
    }

    @Test func aCommittedIconRegistersNativeUndo() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let undo = FolderUndoManager()
        let state = Availability()
        let change = try #require(try f.store.saveSplitAppearance(f.target(), icon: .symbol("heart")))
        #expect(undo.appendSplitAppearance(change, store: f.store, available: { state.available }, onError: { _ in state.errors += 1 }))
        #expect(undo.undoMenuItemTitle == "Undo Customize Tab")
    }

    @Test func aWindowInterruptionDisablesTheOriginalUndo() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let undo = FolderUndoManager()
        let state = Availability()
        let change = try #require(try f.store.saveSplitAppearance(f.target(), icon: .symbol("heart")))
        _ = undo.appendSplitAppearance(change, store: f.store, available: { state.available }, onError: { _ in state.errors += 1 })
        state.available = false
        #expect(!undo.canUndo)
    }

    @Test func nativeUndoRemovesTheOriginalIcon() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let undo = FolderUndoManager()
        let state = Availability()
        let change = try #require(try f.store.saveSplitAppearance(f.target(), icon: .symbol("heart")))
        _ = undo.appendSplitAppearance(change, store: f.store, available: { state.available }, onError: { _ in state.errors += 1 })
        undo.undo()
        #expect(f.target().group.customIcon == nil)
        #expect(undo.redoMenuItemTitle == "Redo Customize Tab")
    }

    @Test func nativeRedoRestoresTheOriginalIcon() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let undo = FolderUndoManager()
        let state = Availability()
        let change = try #require(try f.store.saveSplitAppearance(f.target(), icon: .symbol("heart")))
        _ = undo.appendSplitAppearance(change, store: f.store, available: { state.available }, onError: { _ in state.errors += 1 })
        undo.undo()
        undo.redo()
        #expect(f.target().group.customIcon == .symbol("heart"))
    }

    private func chronology(_ f: SplitAppearanceSupport.SplitFixture, _ undo: FolderUndoManager, _ state: Availability) throws {
        let icon = try #require(try f.store.saveSplitAppearance(f.target(), icon: .symbol("heart")))
        _ = undo.appendSplitAppearance(icon, store: f.store, available: { state.available }, onError: { _ in state.errors += 1 })
        _ = try f.store.saveSidebarSplitTitle(f.target(), title: "Other")
        let reset = try #require(try f.store.saveSplitAppearance(f.target(), icon: nil, reset: true))
        #expect(undo.appendSplitAppearance(reset, store: f.store, available: { state.available }, onError: { _ in state.errors += 1 }))
    }

    @Test func aCommittedResetJoinsTheSameNativeChronology() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let undo = FolderUndoManager()
        try chronology(f, undo, Availability())
        #expect(undo.undoMenuItemTitle == "Undo Reset Name and Icon")
    }

    @Test func theNativeResetInverseRestoresBothOriginalFields() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let undo = FolderUndoManager()
        try chronology(f, undo, Availability())
        undo.undo()
        #expect(f.target().group.customIcon == .symbol("heart"))
        #expect(f.target().group.customTitle == "Other")
    }

    @Test func theEarlierIconInverseFollowsResetWithoutFlatteningTheTitle() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let undo = FolderUndoManager()
        try chronology(f, undo, Availability())
        undo.undo()
        undo.undo()
        #expect(f.target().group.customIcon == nil)
        #expect(f.target().group.customTitle == "Other")
    }

    @Test func nativeRedoCompletesTheSameResetChronology() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let undo = FolderUndoManager()
        let state = Availability()
        try chronology(f, undo, state)
        undo.undo()
        undo.undo()
        undo.redo()
        undo.redo()
        #expect(f.target().group.customIcon == nil)
        #expect(f.target().group.customTitle == nil)
        #expect(state.errors == 0)
    }
}
