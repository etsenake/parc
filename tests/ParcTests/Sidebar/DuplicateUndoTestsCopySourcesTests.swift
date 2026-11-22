import AppKit
import Testing
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct DuplicateUndoTestsCopySourcesTests {
    private typealias Dup = DuplicateUndoTestsSupport.Dup

    private func pinToFolder(_ d: Dup) throws -> (CommandBarFolderCopy, FolderUndoManager, BrowserState) {
        let source = CommandBarFolderMoveSource(items: [.tab(d.loose.id)], spaceID: d.space.id, profileID: d.profile.id, state: d.store.state)!
        let move = CommandBarFolderMove.snapshot(source: source, state: d.store.state).first { $0.folder.folderID == d.target.id }!
        let before = d.store.state
        let pinnedCopy = try d.store.copyCommandBarItemsToFolder(move, destinations: [d.loose.id: d.loose.savedURL])!
        let record = SidebarCopyUndo(actionName: SidebarCopyUndo.folderCopyName, roots: pinnedCopy.roots, spaceID: d.space.id, profileID: d.profile.id,
                                     documents: [], openTabIDs: pinnedCopy.openTabIDs, state: d.store.state)!
        let manager = FolderUndoManager()
        manager.appendSidebarCopy(record, store: d.store, canUse: { _, _ in true }, remove: d.remover,
                                  didRestore: { _ in }, onError: { _ in })
        return (pinnedCopy, manager, before)
    }

    @Test func pinToFolderCopiesNameTheirOwnStep() throws {
        let d = try Dup()
        let (_, manager, _) = try pinToFolder(d)
        #expect(manager.undoMenuItemTitle == "Undo Copy to Folder")
    }

    @Test func undoTakesTheFolderCopyBackOutOfTheDestinationFolder() throws {
        let d = try Dup()
        let (copy, manager, before) = try pinToFolder(d)
        manager.undo()
        #expect(d.store.state.tabs.allSatisfy { !copy.tabIDs.contains($0.id) })
        #expect(d.layout(d.store.state) == d.layout(before))
    }

    @Test func redoPutsTheFolderCopyBackAtTheEndOfTheDestinationFolder() throws {
        let d = try Dup()
        let (copy, manager, _) = try pinToFolder(d)
        manager.undo()
        manager.redo()
        #expect(SidebarHierarchy.children(in: d.targetLocation, state: d.store.state) == copy.roots)
    }

    @Test func aCopyThatIsAlreadyClosingBlocksUndo() throws {
        let d = try Dup()
        let (copy, manager, _) = try pinToFolder(d)
        var retiring: ((Bool) -> Void)?
        d.store.requestPageRetirement = { _, _, done in retiring = done }
        d.store.closeTabs([copy.tabIDs[0]]) { _ in }
        #expect(!manager.canUndo)
        retiring?(false)
        #expect(manager.canUndo)
    }

    @Test func anOptionDragCopyRegistersUndoCopy() throws {
        let d = try Dup()
        let anchor = SidebarHierarchy.children(in: d.targetLocation, state: d.store.state).first
        let (_, manager, _) = try d.dragCopy([.tab(d.keep.id), .folder(d.second.id)], to: d.targetLocation, before: anchor)
        #expect(manager.undoMenuItemTitle == "Undo Copy")
    }

    @Test func anOptionDragCopyKeepsItsEaselAliasReferences() throws {
        let d = try Dup()
        let anchor = SidebarHierarchy.children(in: d.targetLocation, state: d.store.state).first
        let (_, _, record) = try d.dragCopy([.tab(d.keep.id), .folder(d.second.id)], to: d.targetLocation, before: anchor)
        #expect(record.documentReferences.count == 2)
        #expect(record.documentsAreAvailable)
    }

    @Test func undoCopyRemovesTheDraggedCopiesAndLeavesTheOriginalsAndFolderUntouched() throws {
        let d = try Dup()
        let before = d.store.state
        let anchor = SidebarHierarchy.children(in: d.targetLocation, state: d.store.state).first
        let (_, manager, _) = try d.dragCopy([.tab(d.keep.id), .folder(d.second.id)], to: d.targetLocation, before: anchor)
        manager.undo()
        #expect(d.layout(d.store.state) == d.layout(before))
        #expect(d.store.state.tabs == before.tabs)
        #expect(d.store.state.folders == before.folders)
        #expect(manager.redoMenuItemTitle == "Redo Copy")
    }

    @Test func redoCopyPutsTheCopiesBackAtTheDropSpot() throws {
        let d = try Dup()
        let anchor = SidebarHierarchy.children(in: d.targetLocation, state: d.store.state).first
        let (dragged, manager, _) = try d.dragCopy([.tab(d.keep.id), .folder(d.second.id)], to: d.targetLocation, before: anchor)
        let draggedLayout = d.layout(d.store.state)
        manager.undo()
        manager.redo()
        #expect(d.layout(d.store.state) == draggedLayout)
        #expect(Array(SidebarHierarchy.children(in: d.targetLocation, state: d.store.state).prefix(2)) == dragged.roots)
    }

    @Test func copyingAndUndoingNeverTouchTheSharedDocuments() throws {
        let d = try Dup()
        let (_, manager, _) = try d.dragCopy([.tab(d.keep.id), .folder(d.second.id)], to: d.targetLocation)
        manager.undo()
        #expect(try Data(contentsOf: d.noteFile) == d.noteBytes)
        let loaded = try d.easels.load(d.easel.document.id)
        #expect(loaded === d.easel)
    }

    @Test func aWholeSplitOptionDragCopyCanBeUndone() throws {
        let d = try Dup()
        let (copy, manager, _) = try d.dragCopy([.split(d.split.id)], to: d.pinned, before: .tab(d.keep.id))
        guard case .split(let id)? = copy.roots.first else { Issue.record("split drag copy"); return }
        #expect(SidebarHierarchy.children(in: d.pinned, state: d.store.state).first == .split(id))
        #expect(manager.canUndo)
    }

    @Test func undoRemovesTheCopiedSplitWhole() throws {
        let d = try Dup()
        let before = d.store.state
        let (_, manager, _) = try d.dragCopy([.split(d.split.id)], to: d.pinned, before: .tab(d.keep.id))
        manager.undo()
        #expect(d.store.state.splitLayouts == before.splitLayouts)
        #expect(d.layout(d.store.state) == d.layout(before))
    }

    @Test func redoBringsTheCopiedSplitBackWithTheSameIdentity() throws {
        let d = try Dup()
        let (copy, manager, _) = try d.dragCopy([.split(d.split.id)], to: d.pinned, before: .tab(d.keep.id))
        guard case .split(let id)? = copy.roots.first else { Issue.record("split drag copy"); return }
        manager.undo()
        manager.redo()
        #expect(d.store.state.splitLayouts.contains { $0.id == id })
        #expect(SidebarHierarchy.children(in: d.pinned, state: d.store.state).first == .split(id))
    }
}
