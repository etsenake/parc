import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct FavoriteRenameUndoTests {
    @Test(arguments: [false, true])
    @MainActor func undoAndRedoKeepTheOriginalFavorite(redo: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let id = store.openResolvedURL(URL(string: "https://example.test/original")!)
        store.setKind(id, .favorite)
        let original = try #require(store.state.tab(id))
        let change = try #require(try store.saveFavoriteTitle(original, title: "Research 🪐"))
        let undo = FolderUndoManager()
        let appended = undo.appendTabTitleChange(change, store: store, available: { true }, onError: { Issue.record($0) })
        try #require(appended)
        undo.undo()
        if redo { undo.redo() }
        #expect(store.state.tab(id)?.customTitle == (redo ? "Research 🪐" : nil))
        #expect(store.state.tab(id)?.url == original.url)
    }
}
