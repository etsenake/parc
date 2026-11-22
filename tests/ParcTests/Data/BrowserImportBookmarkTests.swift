import AppKit
@testable import ParcCore
import ParcEngine
import Testing
@testable import Parc

@MainActor @Suite(.serialized)
struct BrowserImportBookmarkTests {
    private nonisolated static let date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    private let profile = ImportFixture.profile("Chosen profile", [.bookmarks])

    private func reading(_ scene: BrowserImportScene) throws -> (BrowserImportCoordinator, UUID) {
        let coordinator = scene.started(try scene.impostor(), [profile], onboarding: true)
        let folder = ImportFixture.bookmark("folder", title: "Reading", children: [
            ImportFixture.bookmark("first", title: "Same title", url: "https://example.org/first"),
            ImportFixture.bookmark("second", title: "Same title", url: "https://example.org/second")])
        scene.engine.finishBrowser(bookmarks: [folder])
        return (coordinator, try #require(coordinator.bookmarkPages.first).id)
    }

    @Test func nativeBookmarksReachTheBookmarkStageAllTickedUnderTheirProfileName() throws {
        try BrowserImportScene.run(now: { Self.date }) { scene in
            let (coordinator, _) = try reading(scene)
            #expect(coordinator.stage == .bookmarks && coordinator.bookmarkPages.count == 1)
            let page = coordinator.bookmarkPages[0]
            #expect(page.selection.allSelected && page.selection.selected == ["folder", "first", "second"])
            #expect(page.sourceName == profile.displayName)
        }
    }

    @Test func expansionTogglesIndependentlyOfSelection() throws {
        try BrowserImportScene.run(now: { Self.date }) { scene in
            let (coordinator, pageID) = try reading(scene)
            let initial = coordinator.bookmarkPages[0].selection.selected
            coordinator.toggleBookmark(pageID: pageID, id: "folder", expansion: true)
            #expect(coordinator.bookmarkPages[0].selection.expanded.isEmpty)
            coordinator.toggleBookmark(pageID: pageID, id: "folder", expansion: true)
            #expect(coordinator.bookmarkPages[0].selection.expanded == ["folder"])
            #expect(coordinator.bookmarkPages[0].selection.selected == initial)
        }
    }

    @Test func folderSelectionCoversItsSubtreeAndLeavesExpansionAlone() throws {
        try BrowserImportScene.run(now: { Self.date }) { scene in
            let (coordinator, pageID) = try reading(scene)
            coordinator.toggleBookmark(pageID: pageID, id: "folder")
            #expect(coordinator.bookmarkPages[0].selection.selected.isEmpty)
            #expect(coordinator.bookmarkPages[0].selection.expanded == ["folder"])
            coordinator.toggleBookmark(pageID: pageID, id: "second")
            #expect(coordinator.bookmarkPages[0].selection.selected == ["second"])
        }
    }

    @Test func staleOrVirtualRootControlsCannotChangeTheTree() throws {
        try BrowserImportScene.run(now: { Self.date }) { scene in
            let (coordinator, pageID) = try reading(scene)
            coordinator.toggleBookmark(pageID: pageID, id: "folder")
            coordinator.toggleBookmark(pageID: pageID, id: "second")
            coordinator.toggleBookmark(pageID: UUID(), id: nil)
            #expect(coordinator.bookmarkPages[0].selection.selected == ["second"])
            coordinator.toggleBookmark(pageID: pageID, id: nil, expansion: true)
            #expect(coordinator.bookmarkPages[0].selection.selected == ["second"])
        }
    }

    @Test func retiringTheOriginalOwnerRejectsSelectionAndCommit() throws {
        try BrowserImportScene.run(now: { Self.date }) { scene in
            let (coordinator, pageID) = try reading(scene)
            coordinator.toggleBookmark(pageID: pageID, id: "folder")
            coordinator.toggleBookmark(pageID: pageID, id: "second")
            scene.current = false
            coordinator.toggleBookmark(pageID: pageID, id: nil)
            coordinator.toggleBookmark(page: 0, id: "folder", expansion: true)
            coordinator.commitBookmarks()
            #expect(coordinator.bookmarkPages[0].selection.selected == ["second"])
            #expect(coordinator.bookmarkPages[0].selection.expanded == ["folder"])
            #expect(coordinator.stage == .bookmarks && !coordinator.bookmarkPages[0].committed)
        }
    }

    @Test func selectAllTogglesEveryDescendant() throws {
        try BrowserImportScene.run(now: { Self.date }) { scene in
            let (coordinator, pageID) = try reading(scene)
            coordinator.toggleBookmark(pageID: pageID, id: "folder")
            coordinator.toggleBookmark(pageID: pageID, id: nil)
            #expect(coordinator.bookmarkPages[0].selection.selected == ["folder", "first", "second"])
            coordinator.toggleBookmark(pageID: pageID, id: nil)
            #expect(coordinator.bookmarkPages[0].selection.selected.isEmpty)
        }
    }

    @Test func acceptanceCommitsTheSelectedTreeIntoTheOriginalSpace() throws {
        try BrowserImportScene.run(now: { Self.date }) { scene in
            let (coordinator, pageID) = try reading(scene)
            coordinator.toggleBookmark(pageID: pageID, id: "folder")
            coordinator.toggleBookmark(pageID: pageID, id: "second")
            scene.store.selectSpace(scene.store.createSpace(name: "Other window"))
            coordinator.commitBookmarks()
            #expect(coordinator.stage == .finished && coordinator.bookmarkPages[0].committed)
            let imported = scene.store.state.tabs.filter { $0.url == "https://example.org/second" }
            #expect(imported.count == 1 && imported.first?.spaceID == scene.destination.spaceID
                    && imported.first?.profileID == scene.destination.profileID)
            #expect(!scene.store.state.tabs.contains { $0.url == "https://example.org/first" })
            let folderID = try #require(imported.first?.folderID)
            #expect(scene.store.state.folders.contains { $0.id == folderID && $0.name == "Reading" })
        }
    }

    @Test func repeatedAcceptanceAndObsoleteControlsChangeNothing() throws {
        try BrowserImportScene.run(now: { Self.date }) { scene in
            let (coordinator, pageID) = try reading(scene)
            coordinator.toggleBookmark(pageID: pageID, id: "folder")
            coordinator.toggleBookmark(pageID: pageID, id: "second")
            coordinator.commitBookmarks()
            let tabs = scene.store.state.tabs, folders = scene.store.state.folders
            coordinator.commitBookmarks(); coordinator.toggleBookmark(pageID: pageID, id: nil)
            #expect(scene.store.state.tabs == tabs && scene.store.state.folders == folders)
            #expect(coordinator.bookmarkPages[0].selection.selected == ["second"])
        }
    }

    @Test func acceptedBookmarksPersistThroughTheStore() throws {
        try BrowserImportScene.run(now: { Self.date }) { scene in
            let (coordinator, pageID) = try reading(scene)
            coordinator.toggleBookmark(pageID: pageID, id: "folder")
            coordinator.toggleBookmark(pageID: pageID, id: "second")
            coordinator.commitBookmarks()
            let restored = try BrowserStore(directory: scene.store.directory, now: { Self.date })
            #expect(restored.state.tabs == scene.store.state.tabs && restored.state.folders == scene.store.state.folders)
        }
    }
}
