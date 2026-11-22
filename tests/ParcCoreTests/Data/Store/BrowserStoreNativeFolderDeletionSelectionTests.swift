import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreNativeFolderDeletionSelectionTests {
    @MainActor
    private static func withFolderAndItsNeighbors(
        _ body: (BrowserStore, FolderRemovalTarget, UUID, UUID, UUID) throws -> Void
    ) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let left = store.open("https://left.example", kind: .pinned)
            let folder = store.createFolder(name: "Delete")
            let current = store.open("https://current.example", kind: .pinned)
            store.moveTab(current, toSpace: space, folderID: folder)
            let right = store.open("https://right.example", kind: .pinned)
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            _ = try store.moveSidebarItem(.folder(folder), to: root, before: .tab(right),
                expected: SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)!)
            store.selectTab(current)
            let target = FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: store.state)!
            try body(store, target, left, current, right)
        }
    }

    @Test @MainActor static func folderDeletionFallsBackToTheNearestAvailableOriginalItem() throws {
        try withFolderAndItsNeighbors { store, target, left, current, right in
            @MainActor func resolve(_ selected: [UUID], _ focus: UUID?, unavailable: Set<UUID> = []) -> FolderRemovalSelection? {
                FolderRemovalSelection.resolve(target: target, state: store.state, selected: selected,
                    focused: focus, available: { !unavailable.contains($0) })
            }
            let previous = resolve([current], current)!
            #expect(previous.tabIDs == [left] && previous.focusedTabID == left, "Folder close prefers the original previous item over the newer next item")
            let following = resolve([current], current, unavailable: [left])!
            #expect(following.tabIDs == [right], "Next original item is used when the previous page is owned elsewhere")
            let empty = resolve([current], current, unavailable: [left, right])!
            #expect(empty.tabIDs.isEmpty && empty.focusedTabID == nil, "No available original item yields a genuine empty selection")
        }
    }

    @Test @MainActor static func folderDeletionPreservesOnlyAvailableOriginalSelections() throws {
        try withFolderAndItsNeighbors { store, target, _, current, right in
            @MainActor func resolve(_ selected: [UUID], _ focus: UUID?, unavailable: Set<UUID> = []) -> FolderRemovalSelection? {
                FolderRemovalSelection.resolve(target: target, state: store.state, selected: selected,
                    focused: focus, available: { !unavailable.contains($0) })
            }
            let background = resolve([right], right)!
            #expect(background.tabIDs == [right] && background.focusedTabID == right, "Deleting a background folder retains the original active page")
            #expect(resolve([], nil)?.tabIDs.isEmpty == true, "An unselected original window stays unselected")
            #expect(resolve([current, right], right)?.tabIDs == [right], "An original surviving pane is kept without selecting an unrelated neighbor")
            #expect(resolve([current, right], current)?.focusedTabID == right, "Retired focus falls to the original surviving pane")
            #expect(resolve([current, right], right, unavailable: [right]) == nil, "A surviving page transferred elsewhere refuses the captured decision")
            #expect(resolve([current], right) == nil && resolve([current, current], current) == nil, "Foreign focus and duplicate selection IDs refuse")
        }
    }

    @Test @MainActor static func collapsingAFolderDoesNotChangeItsDeletionFallback() throws {
        try withFolderAndItsNeighbors { store, target, left, current, _ in
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let folder = try #require(target.folderIDs.first)
            var collapsed = store.state
            collapsed.folders[collapsed.folders.firstIndex { $0.id == folder }!].isExpanded = false
            let collapsedTarget = FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: collapsed)!
            #expect(FolderRemovalSelection.resolve(target: collapsedTarget, state: collapsed,
                selected: [current], focused: current, available: { _ in true })?.tabIDs == [left], "Original close anchor survives collapsed folder disclosure")
        }
    }

    @Test @MainActor static func refusingFolderDeletionKeepsTheFolderAndTheOriginalSelection() throws {
        try withFolderAndItsNeighbors { store, target, left, current, _ in
            let folder = try #require(target.folderIDs.first)
            let previous = try #require(FolderRemovalSelection.resolve(target: target, state: store.state,
                selected: [current], focused: current, available: { _ in true }))
            var gate: (() -> Bool)?, done: ((Bool) -> Void)?
            store.requestPageRetirement = { _, validator, completion in gate = validator; done = completion }
            store.deleteFolder(target, selection: previous, shouldCommit: { false }) { _ in }
            #expect(gate?() == false, "Original-window refusal stops selection and deletion together")
            done?(false)
            #expect(store.state.selectedTabIDs == [current] && store.folders.contains { $0.id == folder }, "Refused consent preserves original current item and folder")
            #expect(previous.tabIDs == [left])
        }
    }

    @Test @MainActor static func confirmedFolderDeletionPersistsTheCapturedReplacementSelection() throws {
        try withFolderAndItsNeighbors { store, target, left, current, _ in
            let folder = try #require(target.folderIDs.first)
            let space = store.activeSpaceID
            @MainActor func resolve(_ selected: [UUID], _ focus: UUID?, unavailable: Set<UUID> = []) -> FolderRemovalSelection? {
                FolderRemovalSelection.resolve(target: target, state: store.state, selected: selected,
                    focused: focus, available: { !unavailable.contains($0) })
            }
            let previous = resolve([current], current)!
            var gate: (() -> Bool)?, done: ((Bool) -> Void)?
            store.requestPageRetirement = { _, validator, completion in gate = validator; done = completion }
            var result: Result<Bool, Error>?
            store.deleteFolder(target, selection: previous, shouldCommit: { true }) { result = $0 }
            #expect(store.state.selectedTabIDs == [current], "Pending consent does not select the replacement early")
            #expect(gate?() == true, "Confirmed immutable decision passes native retirement")
            done?(true)
            #expect((try? result?.get()) == true && store.state.selectedTabIDs == [left], "One commit removes the folder and selects its captured replacement")
            #expect(store.state.selectionBySpace[space.uuidString] == [left], "Same-Space restart selection commits with folder deletion")
            let loaded = try BrowserStore(directory: store.directory)
            #expect(loaded.state.selectedTabIDs == [left] && !loaded.folders.contains { $0.id == folder }, "Disk reload sees deletion and replacement together")
        }
    }

    @Test @MainActor static func folderDeletionTreatsTheAdjacentSplitAsOneFallbackItem() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let a = store.open("https://a.example")
            let b = store.open("https://b.example")
            try BrowserStoreTestsSupport.savedSplit(store, [a, b], in: .init(spaceID: space, folderID: nil, section: .pinned))
            store.selectTab(a); _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.4, 0.6])
            let split = store.activeSplitLayout!
            let folder = store.createFolder(name: "Delete")
            let current = store.open("https://current.example", kind: .pinned)
            store.moveTab(current, toSpace: space, folderID: folder)
            let target = FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: store.state)!
            let choice = FolderRemovalSelection.resolve(target: target, state: store.state,
                selected: [current], focused: current, available: { _ in true })!
            #expect(choice.tabIDs == split.tabIDs, "An adjacent split is selected as its original complete item")
            #expect(FolderRemovalSelection.resolve(target: target, state: store.state,
                selected: [current], focused: current, available: { $0 != b })?.tabIDs.isEmpty == true, "One unavailable split child excludes the entire group")
            var changed = store.state
            changed.tabs[changed.tabs.firstIndex { $0.id == a }!].profileID = UUID()
            #expect(FolderRemovalSelection.resolve(target: target, state: changed,
                selected: [current], focused: current, available: { _ in true }) == nil, "A replacement changing profile invalidates the original hierarchy")
        }
    }

    @Test @MainActor static func anUnknownReplacementCannotCommitFolderDeletion() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let folder = store.createFolder(name: "Delete")
            let current = store.open("https://current.example", kind: .pinned)
            store.moveTab(current, toSpace: space, folderID: folder)
            let target = FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: store.state)!
            let selection = FolderRemovalSelection(spaceID: space, profileID: profile, original: [current],
                originalFocus: current, tabIDs: [UUID()], focusedTabID: nil)
            var result: Result<Bool, Error>?
            store.deleteFolder(target, selection: selection, shouldCommit: { true }) { result = $0 }
            #expect((try? result?.get()) == false && store.folders.contains { $0.id == folder }, "Unknown replacement cannot commit deletion")
        }
    }
}
