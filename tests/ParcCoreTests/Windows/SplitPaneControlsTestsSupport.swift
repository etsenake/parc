import Foundation
import Testing
@testable import ParcCore

enum SplitPaneControlsTestsSupport {
    @MainActor final class Fixture {
        let root: URL
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store: BrowserStore
        let saved: UUID, folder: UUID
        let a: UUID, b: UUID, c: UUID
        let original: BrowserSplitLayout
        let tabs: [BrowserTab]
        let archive: [UUID]
        let url = URL(string: "https://four.invalid/post-result")!

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-pane-controls-" + UUID().uuidString)
            let now = now
            let store = try BrowserStore(directory: root, now: { now })
            let saved = store.open("https://one.invalid", kind: .pinned)
            let folder = store.createFolder(name: "Original parent")
            store.moveTab(saved, toSpace: store.activeSpaceID, folderID: folder)
            let a = store.open("https://one.invalid/today")
            let b = store.open("https://two.invalid"), c = store.open("https://three.invalid")
            store.setSplit([a, b, c])
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 2, 3])
            self.store = store
            self.saved = saved; self.folder = folder
            self.a = a; self.b = b; self.c = c
            original = store.activeSplitLayout!
            tabs = store.state.tabs
            archive = store.state.recentlyClosedIDs
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func moved() -> BrowserSplitLayout {
            _ = store.moveSplitPane(b, offset: 1, expected: original)
            return store.activeSplitLayout!
        }

        func creation() -> TabCreationProvenance {
            TabCreationProvenance(referrerID: nil, activeTabID: b, profileID: store.activeSpace.profileID, state: store.state)
        }

        func insertFour(operation: SplitPaneOperation = .addAbove) throws -> (id: UUID, draft: SplitPaneInsertion) {
            let draft = try #require(SplitPaneInsertion(paneID: b, operation: operation, state: store.state))
            let id = UUID()
            _ = store.insertSplitPane(draft, tabID: id, navigationURL: url, creation: creation(), savedHomeIDs: [:], documents: [:])
            return (id, draft)
        }

        func insertPinned() throws -> (home: UUID, newID: UUID) {
            store.selectTab(saved)
            let draft = try #require(SplitPaneInsertion(paneID: saved, operation: .addAfter, state: store.state))
            let newID = UUID(), home = UUID()
            _ = store.insertSplitPane(draft, tabID: newID, navigationURL: url, creation: nil, savedHomeIDs: [saved: home], documents: [:])
            return (home, newID)
        }

        func breakStorage() throws {
            try FileManager.default.removeItem(at: root)
            try Data().write(to: root)
        }

        func restoreStorage() throws {
            try FileManager.default.removeItem(at: root)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
    }
}
