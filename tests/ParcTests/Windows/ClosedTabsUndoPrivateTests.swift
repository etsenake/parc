import AppKit
import Foundation
import Testing
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct ClosedTabsUndoPrivateTests {
    @MainActor private struct Rig {
        let root: URL
        let consent = ClosedTabsUndoSupport.Consent()
        let store: BrowserStore
        let p1: UUID, p2: UUID, p3: UUID
        let space: UUID, profile: UUID
        let location: SidebarContainerLocation
        let order: [SidebarItemReference]
        let records: [BrowserTab]

        @MainActor init() throws {
            root = try ClosedTabsUndoSupport.temporaryRoot()
            let parent = BrowserProfile(id: UUID(), name: "Original")
            store = BrowserStore(privateParentProfileID: parent.id, engineProfilePath: root.appendingPathComponent("otr").path,
                                 directory: root, settings: BrowserState.initial().settings)
            consent.attach(store)
            consent.autoApprove = true
            p3 = store.openResolvedURL(URL(string: "https://three.invalid/")!)
            p2 = store.openResolvedURL(URL(string: "https://two.invalid/")!)
            p1 = store.openResolvedURL(URL(string: "https://one.invalid/")!)
            space = store.activeSpaceID
            profile = store.activeSpace.profileID
            location = SidebarContainerLocation(spaceID: space, folderID: nil, section: .today)
            order = SidebarHierarchy.children(in: location, state: store.state)
            records = store.state.tabs
        }

        @MainActor func closeOne() -> ClosedTabsUndo? {
            var record: ClosedTabsUndo?
            store.closeTabs([p2], didCommit: { before in
                record = ClosedTabsUndo(prompt: .archive, ids: [p2], spaceID: space, profileID: profile,
                                        focusedTabID: nil, before: before, after: store.state)
            }, shouldCommit: { true })
            return record
        }
    }

    @Test func theFixtureHasThreePrivateTabs() throws {
        let rig = try Rig()
        defer { try? FileManager.default.removeItem(at: rig.root) }
        #expect(rig.order == [.tab(rig.p1), .tab(rig.p2), .tab(rig.p3)])
    }

    @Test func aPrivateCloseRemovesTheTabAndRecordsIt() throws {
        let rig = try Rig()
        defer { try? FileManager.default.removeItem(at: rig.root) }
        let record = rig.closeOne()
        #expect(!rig.store.state.tabs.contains { $0.id == rig.p2 } && record?.actionName == "Archive Tab" && record?.archivedTabs.isEmpty == true)
    }

    @Test func aPrivateCloseAddsUndoArchiveTab() throws {
        let rig = try Rig()
        defer { try? FileManager.default.removeItem(at: rig.root) }
        let record = try #require(rig.closeOne())
        let window = FolderUndoManager()
        #expect(rig.consent.register(record, in: window, on: rig.store) && window.undoMenuItemTitle == "Undo Archive Tab")
    }

    @Test func undoPutsAPrivateTabBackInPlace() throws {
        let rig = try Rig()
        defer { try? FileManager.default.removeItem(at: rig.root) }
        let record = try #require(rig.closeOne())
        let window = FolderUndoManager()
        _ = rig.consent.register(record, in: window, on: rig.store)
        window.undo()
        #expect(rig.store.state.tabs.first { $0.id == rig.p2 } == rig.records.first { $0.id == rig.p2 })
        #expect(SidebarHierarchy.children(in: rig.location, state: rig.store.state) == rig.order)
    }

    @Test func redoRemovesItAgain() throws {
        let rig = try Rig()
        defer { try? FileManager.default.removeItem(at: rig.root) }
        let record = try #require(rig.closeOne())
        let window = FolderUndoManager()
        _ = rig.consent.register(record, in: window, on: rig.store)
        window.undo()
        window.redo()
        #expect(!rig.store.state.tabs.contains { $0.id == rig.p2 } && window.canUndo)
    }

    @Test func aPrivateClearRemovesEveryTab() throws {
        let rig = try Rig()
        defer { try? FileManager.default.removeItem(at: rig.root) }
        var privateClear: ClosedTabsUndo?
        rig.store.closeTabs([rig.p1, rig.p2, rig.p3], reason: .clearButton, didCommit: { before in
            privateClear = ClosedTabsUndo(prompt: .clear, ids: [rig.p1, rig.p2, rig.p3], spaceID: rig.space, profileID: rig.profile,
                                          focusedTabID: nil, before: before, after: rig.store.state)
        }, shouldCommit: { true })
        #expect(rig.store.state.tabs.isEmpty && privateClear?.actionName == "Clear Tabs")
    }

    @Test func aPrivateClearRegistersUndo() throws {
        let rig = try Rig()
        defer { try? FileManager.default.removeItem(at: rig.root) }
        var privateClear: ClosedTabsUndo?
        rig.store.closeTabs([rig.p1, rig.p2, rig.p3], reason: .clearButton, didCommit: { before in
            privateClear = ClosedTabsUndo(prompt: .clear, ids: [rig.p1, rig.p2, rig.p3], spaceID: rig.space, profileID: rig.profile,
                                          focusedTabID: nil, before: before, after: rig.store.state)
        }, shouldCommit: { true })
        let window = FolderUndoManager()
        #expect(rig.consent.register(try #require(privateClear), in: window, on: rig.store))
    }

    @Test func undoRestoresEveryPrivatelyClearedTabInOrder() throws {
        let rig = try Rig()
        defer { try? FileManager.default.removeItem(at: rig.root) }
        var privateClear: ClosedTabsUndo?
        rig.store.closeTabs([rig.p1, rig.p2, rig.p3], reason: .clearButton, didCommit: { before in
            privateClear = ClosedTabsUndo(prompt: .clear, ids: [rig.p1, rig.p2, rig.p3], spaceID: rig.space, profileID: rig.profile,
                                          focusedTabID: nil, before: before, after: rig.store.state)
        }, shouldCommit: { true })
        let window = FolderUndoManager()
        _ = rig.consent.register(try #require(privateClear), in: window, on: rig.store)
        window.undo()
        #expect(SidebarHierarchy.children(in: rig.location, state: rig.store.state) == rig.order)
    }
}
