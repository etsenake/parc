import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreSpaceBookmarksTests {
    private static let bookmarks: [(title: String, url: String)] = [
        ("Already saved", "https://saved.example.org/start"),
        ("Research & notes", "https://new.example.org/research?q=stars#notes"),
        ("Duplicate in the same import", "https://new.example.org/research?q=stars#notes"),
        ("", "http://plain.example.org/reference"),
        ("Script", "javascript:alert(1)"),
        ("Data", "data:text/html,hello"),
        ("Local file", "file:///tmp/private.html"),
        ("Mail", "mailto:someone@example.org"),
        ("Internal", "about:blank"),
        ("Relative", "/not-an-absolute-web-address")
    ]

    @MainActor
    private static func withExistingSplit(_ body: (BrowserStore, BrowserState) throws -> Void) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let existing = store.open("https://saved.example.org/start", kind: .pinned)
            store.updateTab(existing, title: "Current page", url: "https://saved.example.org/other")
            let current = store.open("https://current.example.org")
            store.updateTab(current, title: "Current", url: "https://current.example.org/article")
            store.setSplit([existing, current])
            try body(store, store.state)
        }
    }

    @Test @MainActor static func bookmarkImportCreatesOnlyDistinctWebDestinationsInTheActiveSpace() throws {
        try withExistingSplit { store, original in
            store.importBookmarks(bookmarks)
            let imported = store.state.tabs.filter { candidate in !original.tabs.contains { $0.id == candidate.id } }
            #expect(imported.count == 2, "Import must deduplicate saved destinations and batch duplicates, admitting only HTTP(S) bookmarks")
            #expect(imported.allSatisfy { $0.kind == .pinned && $0.archivedAt == nil && $0.folderID == nil }, "Imported bookmarks must become live saved destinations in the pinned section")
            #expect(imported.allSatisfy { $0.spaceID == store.activeSpaceID && $0.profileID == store.activeSpace.profileID }, "Imported bookmarks must belong to the active Space and its profile")
            #expect(imported.first?.savedTitle == "Research & notes"
                       && imported.first?.savedURL == "https://new.example.org/research?q=stars#notes", "Import must preserve supplied bookmark titles, query strings, and fragments")
            #expect(imported.last?.savedTitle == "plain.example.org", "An empty bookmark title must fall back to its host")
        }
    }

    @Test @MainActor static func bookmarkImportLeavesExistingTabsSelectionAndHistoryUntouched() throws {
        try withExistingSplit { store, original in
            store.importBookmarks(bookmarks)
            #expect(store.state.selectedTabIDs == original.selectedTabIDs, "Import must preserve the current tab and split selection")
            #expect(store.state.history == original.history, "Importing bookmarks must not create navigation history")
            #expect(Array(store.state.tabs.prefix(original.tabs.count)) == original.tabs, "Import must not navigate, retitle, or otherwise mutate existing tabs")
        }
    }

    @Test @MainActor static func importingTheSameBookmarksAgainIsIdempotent() throws {
        try withExistingSplit { store, original in
            store.importBookmarks(bookmarks)
            let firstImport = store.state.tabs
            store.importBookmarks(bookmarks)
            #expect(store.state.tabs == firstImport, "Importing the same bookmark file again must be idempotent")
            #expect(store.state.history == original.history && store.state.selectedTabIDs == original.selectedTabIDs, "A repeated import must also preserve history and selection")
        }
    }

    @Test @MainActor static func bookmarkImportIntoAnEmptySessionDoesNotNavigate() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            store.importBookmarks([("First bookmark", "https://first.example.org")])
            #expect(store.state.selectedTabIDs.isEmpty, "Import into an empty session must not select or open the imported bookmark")
            #expect(store.state.history.isEmpty, "Import into an empty session must not create browsing history")
        }
    }
}
