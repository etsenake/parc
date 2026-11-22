import Foundation
import Testing
@testable import ParcCore

struct SplitSeparateAllFoldersTests {
    private typealias Fixture = SplitSeparateAllTestsSupport.Fixture

    @MainActor private struct Folders {
        let home: UUID, other: UUID, profile: UUID
        let p1: UUID, p2: UUID
        let outer: UUID
        let group: BrowserSplitLayout
        let snapshot: SidebarHierarchySnapshot

        init(_ store: BrowserStore) throws {
            let home = store.activeSpaceID
            let other = store.createSpace(name: "Other")
            store.selectSpace(home)
            let p1 = store.open("https://p1.invalid"), p2 = store.open("https://p2.invalid")
            let outer = store.createFolder(name: "Outer")
            store.setSplit([p1, p2])
            let group = store.activeSplitLayout!
            let profile = store.activeSpace.profileID
            let intoOuter = SidebarHierarchySnapshot(state: store.state, spaceID: home, profileID: profile, includesFavorites: true)!
            try #require(try store.moveSidebarItem(.split(group.id), to: SidebarContainerLocation(spaceID: home, folderID: outer, section: .pinned),
                                                   before: nil, expected: intoOuter))
            store.toggleFolder(outer)
            store.selectSpace(other)
            snapshot = SidebarHierarchySnapshot(state: store.state, spaceID: home, profileID: profile, includesFavorites: true)!
            self.home = home; self.other = other
            self.p1 = p1; self.p2 = p2; self.outer = outer; self.group = group; self.profile = profile
        }

        func make(_ store: BrowserStore, id: UUID = UUID()) throws -> SidebarFolderFromItems? {
            try store.createFolder(containing: [.split(group.id)], folderID: id, expected: snapshot)
        }
    }

    @MainActor @Test func theFolderTakesTheDefaultNameInsideTheSplitsParentFolder() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        let id = UUID()
        #expect(try s.make(f.store, id: id) != nil)
        let made = f.store.state.folders.first { $0.id == id }
        #expect(made?.name == SidebarFolderFromItems.defaultName)
        #expect(made?.parentID == s.outer)
        #expect(made?.spaceID == s.home)
    }

    @MainActor @Test func aCollapsedAncestorExpands() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        _ = try s.make(f.store)
        #expect(f.store.state.folders.first { $0.id == s.outer }?.isExpanded == true)
    }

    @MainActor @Test func theFolderIsMadeInTheWindowsSpaceWhileAnotherSpaceIsActive() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        _ = try s.make(f.store)
        #expect(f.store.activeSpaceID == s.other)
    }

    @MainActor @Test func theWholeSplitMovesIntoTheFolderAndStaysASplit() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        let id = UUID()
        _ = try s.make(f.store, id: id)
        #expect([s.p1, s.p2].allSatisfy { tab in f.store.state.tabs.first { $0.id == tab }?.folderID == id })
        #expect(f.store.state.splitLayouts.contains { $0.id == s.group.id && $0.tabIDs == [s.p1, s.p2] })
    }

    @MainActor @Test func theFolderHoldsTheSplit() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        let id = UUID()
        _ = try s.make(f.store, id: id)
        #expect(SidebarHierarchy.children(in: SidebarContainerLocation(spaceID: s.home, folderID: id, section: .pinned),
                                          state: f.store.state) == [.split(s.group.id)])
    }

    @MainActor @Test func aStaleHierarchyRefusesToMakeAFolder() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        _ = try s.make(f.store)
        #expect(try s.make(f.store) == nil)
    }

    @MainActor @Test func theFolderAndMovePersist() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        let id = UUID()
        _ = try s.make(f.store, id: id)
        #expect(try f.reopened().state.folders.contains { $0.id == id })
    }

    @MainActor private func undone(_ f: Fixture, _ s: Folders) throws -> (made: UUID, before: BrowserState, receipt: SidebarFolderFromItems, undo: SidebarFolderFromItems) {
        let before = f.store.state, id = UUID()
        let receipt = try #require(try s.make(f.store, id: id))
        f.store.renameFolder(s.outer, name: "Renamed outer")
        f.store.updateTab(s.p1, title: "Changed title")
        f.store.renameFolder(id, name: "Named by the prompt")
        let undo = try #require(try f.store.revertFolderCreation(receipt, undo: true))
        return (id, before, receipt, undo)
    }

    @MainActor @Test func undoRemovesTheFolderAndRestoresPlacement() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        let r = try undone(f, s)
        #expect(!f.store.state.folders.contains { $0.id == r.made })
        #expect(f.store.state.sidebarItemOrder == r.before.sidebarItemOrder)
        #expect([s.p1, s.p2].allSatisfy { tab in f.store.state.tabs.first { $0.id == tab }?.folderID == s.outer })
    }

    @MainActor @Test func undoKeepsUnrelatedEdits() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        _ = try undone(f, s)
        #expect(f.store.state.tabs.first { $0.id == s.p1 }?.title == "Changed title")
        #expect(f.store.state.folders.first { $0.id == s.outer }?.name == "Renamed outer")
    }

    @MainActor @Test func undoAppliesOnce() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        let r = try undone(f, s)
        #expect(try f.store.revertFolderCreation(r.undo, undo: true) == nil)
    }

    @MainActor @Test func redoRecreatesTheSameFolderWithTheNameEnteredAfterCreation() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        let r = try undone(f, s)
        #expect(try f.store.revertFolderCreation(r.undo, undo: false) != nil)
        #expect(f.store.state.folders.first { $0.id == r.made }?.name == "Named by the prompt")
    }

    @MainActor @Test func aTodayItemsFolderIsMadeInThePinnedRoot() throws {
        let f = try Fixture()
        let home = f.store.activeSpaceID
        let item = f.store.open("https://loose.invalid")
        f.store.setSplit([item])
        let profile = f.store.activeSpace.profileID
        let snapshot = try #require(SidebarHierarchySnapshot(state: f.store.state, spaceID: home, profileID: profile, includesFavorites: true))
        let folder = UUID()
        #expect(try f.store.createFolder(containing: [.tab(item)], folderID: folder, expected: snapshot) != nil)
        #expect(f.store.state.folders.first { $0.id == folder }?.parentID == nil)
        #expect(f.store.state.tabs.first { $0.id == item }?.folderID == folder)
    }
}
