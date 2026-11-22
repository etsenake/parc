import Combine
import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreNativeFolderUndoTests {
    @Test @MainActor static func deletionUndoRecordsTheOriginalPaneAndEmptyDescendant() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let outer = store.createFolder(name: "Outer")
            _ = store.createFolder(name: "Before", parentID: outer)
            let root = store.createFolder(name: "Deleted", parentID: outer)
            _ = store.createFolder(name: "After", parentID: outer)
            let nested = store.createFolder(name: "Nested", parentID: root)
            let empty = store.createFolder(name: "Empty", parentID: nested)
            let a = store.open("https://a.test"), b = store.open("https://b.test")
            try BrowserStoreTestsSupport.savedSplit(store, [a, b], in: .init(spaceID: space, folderID: nested, section: .pinned))
            store.selectTab(a)
            _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.25, 0.75])
            let split = store.activeSplitLayout!, originals = store.state
            let target = FolderRemovalTarget(folderID: root, spaceID: space, profileID: profile, state: originals)!
            let selection = FolderRemovalSelection.resolve(target: target, state: originals,
                selected: [a, b], focused: b, available: { _ in true })!
            var record: FolderDeletionUndo?
            store.deleteFolder(target, selection: selection, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
            let undo = record!
            #expect(undo.focusedTabID == b && undo.groups == [split], "Undo binds original focused pane and split provenance")
            #expect(undo.folders.map(\.id).contains(empty) && store.canUndoFolderDeletion(undo), "Nested empty folder is part of ordinary undo, without folder archive entities")
        }
    }

    @Test @MainActor static func undoRestoresTheOriginalTreeAndKeepsLaterEdits() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let outer = store.createFolder(name: "Outer")
            let beforeSibling = store.createFolder(name: "Before", parentID: outer)
            let root = store.createFolder(name: "Deleted", parentID: outer)
            let afterSibling = store.createFolder(name: "After", parentID: outer)
            let nested = store.createFolder(name: "Nested", parentID: root)
            _ = store.createFolder(name: "Empty", parentID: nested)
            let a = store.open("https://a.test"), b = store.open("https://b.test")
            try BrowserStoreTestsSupport.savedSplit(store, [a, b], in: .init(spaceID: space, folderID: nested, section: .pinned))
            store.selectTab(a)
            _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.25, 0.75])
            let split = store.activeSplitLayout!, originals = store.state
            let target = FolderRemovalTarget(folderID: root, spaceID: space, profileID: profile, state: originals)!
            let selection = FolderRemovalSelection.resolve(target: target, state: originals,
                selected: [a, b], focused: b, available: { _ in true })!
            var record: FolderDeletionUndo?
            store.deleteFolder(target, selection: selection, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
            let undo = record!
            let newSibling = store.createFolder(name: "New", parentID: outer)
            store.renameFolder(beforeSibling, name: "Keep current edit")
            let outside = store.open("https://outside.test", kind: .today)
            let outsideRecord = store.state.tabs.first { $0.id == outside }!
            let beforeUndo = store.state
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            #expect(try store.undoFolderDeletion(undo, shouldCommit: { true }), "Undo restores exact original group")
            #expect(publications == 1, "Undo publishes one durable targeted transaction")
            #expect(store.state.tabs.first { $0.id == a } == originals.tabs.first { $0.id == a }
                && store.state.tabs.first { $0.id == b } == originals.tabs.first { $0.id == b }, "Original tab identities/content return from unchanged archive afterimages")
            #expect(store.state.splitLayouts.contains(split), "Original split ID, pane order and geometry return")
            #expect(store.state.folders.filter { target.folderIDs.contains($0.id) } == originals.folders.filter { target.folderIDs.contains($0.id) }, "Nested names, parents and expansion return intact")
            #expect(store.state.tabs.first { $0.id == outside } == outsideRecord
                && store.state.folders.first { $0.id == beforeSibling }?.name == "Keep current edit", "Unrelated additions and edits survive Undo")
            let container = SidebarContainerLocation(spaceID: space, folderID: outer, section: .pinned)
            #expect(SidebarHierarchy.children(in: container, state: store.state) == [.folder(beforeSibling), .folder(root), .folder(afterSibling), .folder(newSibling)], "Original sibling anchors restore location without rolling back new siblings")
            #expect(store.state.selectedTabIDs == beforeUndo.selectedTabIDs, "Store Undo does not select pages in other physical windows")
            observation.cancel()
        }
    }

    @Test @MainActor static func aFolderDeletionUndoCanBeConsumedOnlyOnce() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let outer = store.createFolder(name: "Outer")
            _ = store.createFolder(name: "Before", parentID: outer)
            let root = store.createFolder(name: "Deleted", parentID: outer)
            _ = store.createFolder(name: "After", parentID: outer)
            let nested = store.createFolder(name: "Nested", parentID: root)
            _ = store.createFolder(name: "Empty", parentID: nested)
            let a = store.open("https://a.test"), b = store.open("https://b.test")
            try BrowserStoreTestsSupport.savedSplit(store, [a, b], in: .init(spaceID: space, folderID: nested, section: .pinned))
            store.selectTab(a)
            _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.25, 0.75])
            let originals = store.state
            let target = FolderRemovalTarget(folderID: root, spaceID: space, profileID: profile, state: originals)!
            let selection = FolderRemovalSelection.resolve(target: target, state: originals,
                selected: [a, b], focused: b, available: { _ in true })!
            var record: FolderDeletionUndo?
            store.deleteFolder(target, selection: selection, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
            let undo = record!
            try #require(try store.undoFolderDeletion(undo, shouldCommit: { true }))
            #expect(try !store.canUndoFolderDeletion(undo) && !(try store.undoFolderDeletion(undo, shouldCommit: { true })), "Consumed afterimage cannot duplicate original identities")
        }
    }

    @Test @MainActor static func restoredFolderRecordsAndSplitGeometrySurviveRestart() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let outer = store.createFolder(name: "Outer")
            _ = store.createFolder(name: "Before", parentID: outer)
            let root = store.createFolder(name: "Deleted", parentID: outer)
            _ = store.createFolder(name: "After", parentID: outer)
            let nested = store.createFolder(name: "Nested", parentID: root)
            _ = store.createFolder(name: "Empty", parentID: nested)
            let a = store.open("https://a.test"), b = store.open("https://b.test")
            try BrowserStoreTestsSupport.savedSplit(store, [a, b], in: .init(spaceID: space, folderID: nested, section: .pinned))
            store.selectTab(a)
            _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.25, 0.75])
            let originals = store.state
            let target = FolderRemovalTarget(folderID: root, spaceID: space, profileID: profile, state: originals)!
            let selection = FolderRemovalSelection.resolve(target: target, state: originals,
                selected: [a, b], focused: b, available: { _ in true })!
            var record: FolderDeletionUndo?
            store.deleteFolder(target, selection: selection, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
            let undo = record!
            try #require(try store.undoFolderDeletion(undo, shouldCommit: { true }))
            let loaded = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            #expect(loaded.state.tabs == store.state.tabs && loaded.state.folders == store.state.folders
                && loaded.state.splitLayouts == store.state.splitLayouts, "Restored originals persist together")
        }
    }

    @Test @MainActor static func aCancelledFolderDeletionDoesNotRegisterUndo() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let root = store.createFolder(name: "Cancelled")
            let target = try #require(FolderRemovalTarget(folderID: root, spaceID: space, profileID: profile, state: store.state))
            var record: FolderDeletionUndo?, result: Result<Bool, Error>?
            store.deleteFolder(target, shouldCommit: { false }, didCommit: { record = $0 }) { result = $0 }
            #expect(try record == nil && (try result?.get()) == false, "Cancelled delete cannot register Undo")
        }
    }

    @Test @MainActor static func refusingFolderUndoLeavesItRetryableWithoutChangingTheSession() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let root = store.createFolder(name: "Retry")
            let a = store.open("https://retry.test", kind: .pinned)
            store.moveTab(a, toSpace: space, folderID: root)
            let target = FolderRemovalTarget(folderID: root, spaceID: space, profileID: profile, state: store.state)!
            var record: FolderDeletionUndo?
            store.deleteFolder(target, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
            let undo = record!, archived = store.state
            #expect(try !store.undoFolderDeletion(undo, shouldCommit: { false }), "Original-window refusal leaves Undo retryable")
            #expect(store.state == archived, "Refused Undo changes no saved state")
        }
    }

    @Test @MainActor static func folderRedoTargetsCurrentOriginalPagesButRefusesNewDescendants() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let root = store.createFolder(name: "Retry")
            let a = store.open("https://retry.test", kind: .pinned)
            store.moveTab(a, toSpace: space, folderID: root)
            let target = FolderRemovalTarget(folderID: root, spaceID: space, profileID: profile, state: store.state)!
            var record: FolderDeletionUndo?
            store.deleteFolder(target, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
            let undo = try #require(record)
            #expect(try store.undoFolderDeletion(undo, shouldCommit: { true }), "Undo restores exact original group")
            store.updateTab(a, title: "New actual title")
            #expect(undo.redoTarget(in: store.state) != nil, "Redo closes current original members after normal title/navigation updates")
            let extra = store.open("https://extra.test", kind: .pinned)
            store.moveTab(extra, toSpace: space, folderID: root)
            #expect(undo.redoTarget(in: store.state) == nil, "Redo never closes newly added descendants")
        }
    }

    @Test @MainActor static func aFailedFolderUndoLeavesTheArchiveAndRetryCapability() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let root = store.createFolder(name: "Retry")
            let a = store.open("https://retry.test", kind: .pinned)
            store.moveTab(a, toSpace: space, folderID: root)
            let target = FolderRemovalTarget(folderID: root, spaceID: space, profileID: profile, state: store.state)!
            var record: FolderDeletionUndo?
            store.deleteFolder(target, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
            let undo = record!, archived = store.state
            try FileManager.default.removeItem(at: directory.appendingPathComponent("session.json"))
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("session.json"), withIntermediateDirectories: false)
            var failed = false
            do { _ = try store.undoFolderDeletion(undo, shouldCommit: { true }) } catch { failed = true }
            #expect(failed && store.state == archived && store.canUndoFolderDeletion(undo), "Failed durable Undo keeps exact archived state and retry capability")
            try FileManager.default.removeItem(at: directory.appendingPathComponent("session.json")); try store.save()
        }
    }

    @Test @MainActor static func restoringAnArchivedTabIndependentlyInvalidatesItsFolderUndo() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let root = store.createFolder(name: "Retry")
            let a = store.open("https://retry.test", kind: .pinned)
            store.moveTab(a, toSpace: space, folderID: root)
            let target = FolderRemovalTarget(folderID: root, spaceID: space, profileID: profile, state: store.state)!
            var record: FolderDeletionUndo?
            store.deleteFolder(target, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
            let undo = try #require(record)
            _ = store.restoreArchivedTab(a, profileID: profile, destination: .previousSpace(fallbackSpaceID: space))
            #expect(!store.canUndoFolderDeletion(undo), "Independent archive restoration invalidates old group")
            #expect(try !store.undoFolderDeletion(undo, shouldCommit: { true }), "Stale Undo cannot resurrect a folder around an independently restored tab")
        }
    }

    @Test @MainActor static func undoRestoresAnEmptyFoldersOriginalIdentity() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            var record: FolderDeletionUndo?
            let empty = store.createFolder(name: "Empty")
            let emptyTarget = FolderRemovalTarget(folderID: empty, spaceID: space, profileID: profile, state: store.state)!
            store.deleteFolder(emptyTarget, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
            #expect(try store.undoFolderDeletion(record!, shouldCommit: { true }), "Empty ordinary folder Undo is supported")
            #expect(store.state.folders.contains { $0.id == empty }, "Empty folder retains original identity")
        }
    }
}
