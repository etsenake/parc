import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreSpaceFolderMoveTests {
    @Test @MainActor static func placingATabInAFolderPinsIt() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstSpace = store.activeSpaceID
            let parent = store.createFolder(name: "Parent")
            let child = store.createFolder(name: "Child", parentID: parent)
            let first = store.open("https://one.example.org")
            let second = store.open("https://two.example.org")
            store.moveTab(first, toSpace: firstSpace, folderID: child)
            store.moveTab(second, toSpace: firstSpace, folderID: child)
            #expect(try BrowserStoreTestsSupport.tab(first, in: store).kind == .pinned, "Placing a tab in a folder must pin it")
        }
    }

    @Test @MainActor static func reorderingFolderSiblingsKeepsTheirRequestedOrder() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstSpace = store.activeSpaceID
            let parent = store.createFolder(name: "Parent")
            let child = store.createFolder(name: "Child", parentID: parent)
            let first = store.open("https://one.example.org")
            let second = store.open("https://two.example.org")
            store.moveTab(first, toSpace: firstSpace, folderID: child)
            store.moveTab(second, toSpace: firstSpace, folderID: child)
            try #require(try BrowserStoreTestsSupport.tab(first, in: store).kind == .pinned, "Placing a tab in a folder must pin it")
            store.reorderTab(second, before: first)
            #expect(store.pinnedTabs.map(\.id) == [second, first], "Reordering folder siblings must preserve the requested order")
        }
    }

    @Test @MainActor static func deletingANestedFolderArchivesItsOriginalTabs() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstSpace = store.activeSpaceID
            let parent = store.createFolder(name: "Parent")
            let child = store.createFolder(name: "Child", parentID: parent)
            let first = store.open("https://one.example.org")
            store.moveTab(first, toSpace: firstSpace, folderID: child)
            let deletion = FolderRemovalTarget(folderID: child, spaceID: firstSpace, profileID: store.activeSpace.profileID, state: store.state)!
            var deleted = false
            store.deleteFolder(deletion, shouldCommit: { true }) { deleted = (try? $0.get()) == true }
            #expect(try deleted && (try BrowserStoreTestsSupport.tab(first, in: store)).archivedAt != nil && !store.state.folders.contains { $0.id == child }, "Deleting a nested folder archives its tabs instead of reparenting live pages")
        }
    }

    @Test @MainActor static func putBackRebuildsADeletedNestedFolderUnderItsOriginalParent() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstSpace = store.activeSpaceID
            let parent = store.createFolder(name: "Parent")
            let child = store.createFolder(name: "Child", parentID: parent)
            let first = store.open("https://one.example.org")
            store.moveTab(first, toSpace: firstSpace, folderID: child)
            let deletion = FolderRemovalTarget(folderID: child, spaceID: firstSpace, profileID: store.activeSpace.profileID, state: store.state)!
            var deleted = false
            store.deleteFolder(deletion, shouldCommit: { true }) { deleted = (try? $0.get()) == true }
            try #require(try deleted && (try BrowserStoreTestsSupport.tab(first, in: store)).archivedAt != nil && !store.state.folders.contains { $0.id == child }, "Deleting a nested folder archives its tabs instead of reparenting live pages")
            _ = store.restoreArchivedTab(first, profileID: store.activeSpace.profileID, destination: .previousSpace(fallbackSpaceID: firstSpace))
            #expect(try BrowserStoreTestsSupport.tab(first, in: store).folderID == child && store.state.folders.first { $0.id == child }?.parentID == parent, "Put Back rebuilds a deleted nested folder inside its surviving parent")
        }
    }

    @Test @MainActor static func archivingATabLeavesItsFolderInPlace() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstSpace = store.activeSpaceID
            let parent = store.createFolder(name: "Parent")
            let kept = store.open("https://kept.example.org")
            store.moveTab(kept, toSpace: firstSpace, folderID: parent)
            let archiveKept = FolderRemovalTarget(items: [.tab(kept)], spaceID: firstSpace, profileID: store.activeSpace.profileID, state: store.state)!
            store.deleteFolder(archiveKept, shouldCommit: { true }) { _ in }
            #expect(try BrowserStoreTestsSupport.tab(kept, in: store).archivedAt != nil && store.state.folders.contains { $0.id == parent }, "Archiving a tab leaves its folder in place")
        }
    }

    @Test @MainActor static func putBackReturnsATabToItsSurvivingFolder() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstSpace = store.activeSpaceID
            let parent = store.createFolder(name: "Parent")
            let kept = store.open("https://kept.example.org")
            store.moveTab(kept, toSpace: firstSpace, folderID: parent)
            let archiveKept = FolderRemovalTarget(items: [.tab(kept)], spaceID: firstSpace, profileID: store.activeSpace.profileID, state: store.state)!
            store.deleteFolder(archiveKept, shouldCommit: { true }) { _ in }
            try #require(try BrowserStoreTestsSupport.tab(kept, in: store).archivedAt != nil && store.state.folders.contains { $0.id == parent }, "Archiving a tab leaves its folder in place")
            _ = store.restoreArchivedTab(kept, profileID: store.activeSpace.profileID, destination: .previousSpace(fallbackSpaceID: firstSpace))
            #expect(try BrowserStoreTestsSupport.tab(kept, in: store).archivedAt == nil && (try BrowserStoreTestsSupport.tab(kept, in: store)).folderID == parent, "Put Back returns a tab archived from a folder to that folder")
        }
    }

    @Test @MainActor static func aTabCannotMoveIntoAFolderFromAnotherSpace() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstSpace = store.activeSpaceID
            let first = store.open("https://one.example.org")
            _ = store.createSpace(name: "Other")
            let foreignFolder = store.createFolder(name: "Other folder")
            let before = try BrowserStoreTestsSupport.tab(first, in: store)
            store.moveTab(first, toSpace: firstSpace, folderID: foreignFolder)
            #expect(try BrowserStoreTestsSupport.tab(first, in: store) == before, "A tab must reject a folder belonging to another Space")
        }
    }

    @Test @MainActor static func aTabCanMoveIntoItsDestinationSpacesFolder() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstSpace = store.activeSpaceID
            let first = store.open("https://one.example.org")
            let otherSpace = store.createSpace(name: "Other")
            let foreignFolder = store.createFolder(name: "Other folder")
            let before = try BrowserStoreTestsSupport.tab(first, in: store)
            store.moveTab(first, toSpace: firstSpace, folderID: foreignFolder)
            try #require(try BrowserStoreTestsSupport.tab(first, in: store) == before, "A tab must reject a folder belonging to another Space")
            store.moveTab(first, toSpace: otherSpace, folderID: foreignFolder)
            #expect(try BrowserStoreTestsSupport.tab(first, in: store).folderID == foreignFolder, "A valid cross-Space folder move must succeed")
        }
    }

    @Test @MainActor static func aNewFolderCannotHaveAParentFromAnotherSpace() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let parent = store.createFolder(name: "Parent")
            _ = store.createSpace(name: "Other")
            let foreignParent = store.createFolder(name: "Invalid parent", parentID: parent)
            #expect(store.folders.first { $0.id == foreignParent }?.parentID == nil, "Folder creation must not retain a parent from a different Space")
        }
    }

    @Test @MainActor static func unpinningATabDetachesItFromItsFolder() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstSpace = store.activeSpaceID
            let parent = store.createFolder(name: "Parent")
            let child = store.createFolder(name: "Child", parentID: parent)
            let first = store.open("https://one.example.org")
            store.moveTab(first, toSpace: firstSpace, folderID: child)
            store.setKind(first, .today)
            #expect(try BrowserStoreTestsSupport.tab(first, in: store).folderID == nil, "Unpinning must detach the tab from its folder")
            try BrowserStoreTestsSupport.expectValidSelection(store)
        }
    }

    enum SidebarMoveDamage: CaseIterable {
        case ancestorCycle, selfParent, selfRelative, missingSibling, todayFolder, foreignSpace, missingFolder
    }

    @Test(arguments: SidebarMoveDamage.allCases) @MainActor static func invalidSidebarMovesLeaveTheHierarchyUnchanged(_ damage: SidebarMoveDamage) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID
            let parent = store.createFolder(name: "Parent")
            let child = store.createFolder(name: "Child", parentID: parent)
            let pinned = store.open("https://pin.example.org", kind: .pinned)
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let move: (item: SidebarItemReference, destination: SidebarContainerLocation, before: SidebarItemReference?)
            switch damage {
            case .ancestorCycle:
                move = (.folder(parent), .init(spaceID: space, folderID: child, section: .pinned), nil)
            case .selfParent:
                move = (.folder(parent), .init(spaceID: space, folderID: parent, section: .pinned), nil)
            case .selfRelative:
                move = (.folder(parent), root, .folder(parent))
            case .missingSibling:
                move = (.folder(parent), root, .tab(UUID()))
            case .todayFolder:
                move = (.folder(parent), .init(spaceID: space, folderID: nil, section: .today), nil)
            case .foreignSpace:
                move = (.tab(pinned), .init(spaceID: UUID(), folderID: nil, section: .pinned), nil)
            case .missingFolder:
                move = (.tab(pinned), .init(spaceID: space, folderID: UUID(), section: .pinned), nil)
            }
            let original = store.state
            let snapshot = try #require(SidebarHierarchySnapshot(state: original, spaceID: space,
                profileID: store.activeSpace.profileID))
            #expect(!(try store.moveSidebarItem(move.item, to: move.destination, before: move.before, expected: snapshot)))
            #expect(store.state == original)
        }
    }

    @Test @MainActor static func hierarchySnapshotsRequireValidRelationshipsAndProfileOwnership() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let parent = store.createFolder(name: "Parent")
            var corrupted = store.state
            let index = corrupted.folders.firstIndex { $0.id == parent }!
            corrupted.folders[index].parentID = parent
            #expect(SidebarHierarchySnapshot(state: corrupted, spaceID: space, profileID: profile) == nil, "A malformed hierarchy cannot mint a capability")
            #expect(SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: UUID()) == nil, "Wrong-profile snapshots fail before preparing a move")
        }
    }

    @Test @MainActor static func aFailedSidebarMoveSaveDoesNotPublish() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let parent = store.createFolder(name: "Parent")
            let nested = store.createFolder(name: "Nested", parentID: parent)
            let peer = store.createFolder(name: "Peer")
            @MainActor func snapshot() -> SidebarHierarchySnapshot { SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)! }
            _ = try store.moveSidebarItem(.folder(nested), to: root, before: .folder(peer), expected: snapshot())
            let stable = store.state, snap = snapshot()
            let session = directory.appendingPathComponent("session.json"), backup = directory.appendingPathComponent("saved.json")
            try FileManager.default.moveItem(at: session, to: backup)
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
            var failed = false
            do { _ = try store.moveSidebarItem(.folder(peer), to: root, before: .folder(nested), expected: snap) } catch { failed = true }
            #expect(failed && store.state == stable, "A failed disk commit cannot publish the move")
            try FileManager.default.removeItem(at: session); try FileManager.default.moveItem(at: backup, to: session)
        }
    }

    @Test @MainActor static func movingAnOrdinarySplitToTodayAppliesToEveryOriginalMember() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let first = store.open("https://one.example.org")
            let second = store.open("https://two.example.org")
            try BrowserStoreTestsSupport.savedSplit(store, [first, second], in: .init(spaceID: space, folderID: nil, section: .pinned))
            @MainActor func snapshot() -> SidebarHierarchySnapshot { SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)! }
            let unsaved = store.open("https://split-today.example.org")
            store.selectTab(first); store.selectTab(unsaved, extendingSplit: true)
            let mixedGroup = store.activeSplitLayout!
            let originalIDs = Set(store.state.tabs.map(\.id))
            #expect(try store.moveSidebarItem(.split(mixedGroup.id),
                to: .init(spaceID: space, folderID: nil, section: .today), before: nil,
                expected: snapshot()), "A whole ordinary split moves even when its children retain different saved sections")
            #expect(store.activeSplitLayout == mixedGroup && Set(store.state.tabs.map(\.id)) == originalIDs, "Mixed-section move preserves the original group and every tab identity")
            #expect(store.state.tabs.filter { mixedGroup.tabIDs.contains($0.id) }.allSatisfy {
                $0.kind == .today && $0.folderID == nil
            }, "The explicit destination applies to every original member in one transaction")
        }
    }
}
