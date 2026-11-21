import Foundation
import Testing
@testable import ParcCore

struct BrowserImportSelectionTests {
    let one = BrowserImportBookmark(id: "one", title: "Same title", url: "https://example.test/one", children: [])
    let two = BrowserImportBookmark(id: "two", title: "Same title", url: "https://example.test/one", children: [])
    let loose = BrowserImportBookmark(id: "loose", title: "Loose", url: "https://example.test/loose", children: [])

    var folder: BrowserImportBookmark {
        let nested = BrowserImportBookmark(id: "nested", title: "Nested", url: nil, children: [two])
        return BrowserImportBookmark(id: "folder", title: "Work", url: nil, children: [one, nested])
    }

    func selection() throws -> BrowserImportSelection {
        try BrowserImportSelection(roots: [folder, loose])
    }

    @Test func sameTitleAndSameURLOriginalsRemainIndependentlySelectable() throws {
        let actual = try selection().selectedPageCount
        #expect(actual == 3)
    }

    @Test func togglingTheOriginalFolderDeselectsEveryDescendant() throws {
        var selection = try selection()
        selection.toggle("folder")
        #expect(selection.selected == ["loose"])
    }

    @Test func selectingADescendantPreservesOnlyItsOriginalAncestorChain() throws {
        var selection = try selection()
        selection.toggle("folder")
        selection.toggle("two")
        #expect(selection.includedRoots.first?.children.first?.children.first?.id == "two")
    }

    @Test func expansionIsIndependentOfSelectionAndAURLIsNeverAFolder() throws {
        var selection = try selection()
        selection.toggleExpanded("folder")
        #expect(selection.expanded.contains("folder"))
        selection.toggleExpanded("loose")
        #expect(!selection.expanded.contains("loose"))
    }

    @Test func aStaleIdentifierCannotSelectAReplacement() throws {
        var selection = try selection()
        selection.toggle("folder")
        selection.toggle("two")
        selection.toggle("missing")
        #expect(selection.selected == ["two", "loose"])
        #expect(!selection.allSelected)
    }

    @Test func selectAllRestoresCollapsedDescendantsWithoutMergingEqualOnes() throws {
        var selection = try selection()
        selection.toggle("folder")
        selection.toggle("two")
        selection.toggleExpanded("folder")
        selection.toggleAll()
        #expect(selection.allSelected && selection.selectedPageCount == 3)
        #expect(selection.expanded == ["folder"])
    }

    @Test func clearingSelectionRemovesEverythingWithoutCollapsingTheTree() throws {
        var selection = try selection()
        selection.toggle("folder")
        selection.toggle("two")
        selection.toggleExpanded("folder")
        selection.toggleAll()
        selection.toggleAll()
        #expect(selection.selected.isEmpty && selection.includedRoots.isEmpty)
        #expect(selection.expanded == ["folder"])
    }

    @Test func anEmptySourceDoesNotBecomeASelectedPhantomRoot() throws {
        var empty = try BrowserImportSelection(roots: [])
        empty.toggleAll()
        #expect(!empty.allSelected && empty.selected.isEmpty)
    }

    @Test func setupStartsWithEveryBookmarkTickedAndTheTopFolderOpen() throws {
        let pages = (0..<8).map { index in
            BrowserImportBookmark(id: "rank-\(index)", title: "Page \(index)",
                                  url: "https://example.test/page-\(index)", children: [])
        }
        let folder = BrowserImportBookmark(id: "ranked-folder", title: "Bookmarks", url: nil, children: pages)
        let setup = try BrowserImportSelection(roots: [folder], expandsTopFolders: true)
        #expect(setup.allSelected && setup.selectedPageCount == 8)
        #expect(setup.expanded == ["ranked-folder"])
    }

    @Test func duplicateNativeIdentifiersFail() {
        #expect(throws: (any Error).self) { try BrowserImportSelection(roots: [one, one]) }
    }

    @Test func mixedURLAndContainerNodesFail() {
        #expect(throws: (any Error).self) {
            try BrowserImportSelection(roots: [.init(id: "bad", title: "Bad", url: one.url, children: [two])])
        }
    }
}
