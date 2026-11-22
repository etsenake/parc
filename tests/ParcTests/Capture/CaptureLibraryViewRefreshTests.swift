import AppKit
import Combine
import os
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcLibrary

extension CaptureLibraryViewTestsSupport {
    struct CaptureLibraryViewRefreshTests {
        @MainActor private func failFileAction(_ fixture: Fixture) async throws {
            fixture.select(0)
            try FileManager.default.removeItem(at: fixture.file(0))
            fixture.press(51, [])
            await fixture.finish()
        }

        @MainActor private final class ItemRequests: NSObject, NSCollectionViewDataSource {
            let source: NSCollectionViewDataSource
            var requested: [IndexPath] = []

            init(_ grid: NSCollectionView) throws {
                source = try #require(grid.dataSource)
                super.init()
                grid.dataSource = self
            }

            func collectionView(_ grid: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
                source.collectionView(grid, numberOfItemsInSection: section)
            }
            func collectionView(_ grid: NSCollectionView, itemForRepresentedObjectAt path: IndexPath) -> NSCollectionViewItem {
                requested.append(path)
                return source.collectionView(grid, itemForRepresentedObjectAt: path)
            }
        }

        @MainActor @Test func aFailedFileActionKeepsItsErrorAfterTheGridRefreshes() async throws {
            let fixture = try await Fixture(files: 2, missingFolder: true)
            defer { fixture.teardown() }
            let notice = try #require(fixture.status)
            try await failFileAction(fixture)
            let error = try #require(fixture.status)
            #expect(error != notice && !fixture.media.isLoading && fixture.count == 1)
        }

        @MainActor @Test func theNextSearchClearsTheFileActionErrorAndRestoresTheFolderNotice() async throws {
            let fixture = try await Fixture(files: 1, missingFolder: true)
            defer { fixture.teardown() }
            let notice = try #require(fixture.status)
            try await failFileAction(fixture)
            try #require(fixture.status != nil && fixture.status != notice)
            fixture.query("")
            #expect(fixture.status == notice)
        }

        @MainActor @Test func leavingMediaClearsAStaleFileActionError() async throws {
            let fixture = try await Fixture(files: 1)
            defer { fixture.teardown() }
            try await failFileAction(fixture)
            try #require(fixture.status != nil)
            fixture.window.contentView = nil
            #expect(fixture.status == nil)
        }

        @MainActor @Test func aFolderToggleThatCannotBeSavedKeepsItsFilesAndShowsTheError() async throws {
            let fixture = try await Fixture(files: 1, persistentFolders: true)
            defer { fixture.teardown() }
            try FileManager.default.createDirectory(at: fixture.preferences.appendingPathComponent("MediaFolders.json"),
                                                    withIntermediateDirectories: true)
            let menu = try #require(fixture.view.keyboardMenu(foldersOnly: true)?.menu)
            let item = try #require(menu.items.first?.submenu?.item(withTitle: "Stop Showing This Folder"))
            try #require(item.target as? MenuAction).invoke()
            await fixture.finish()
            #expect(fixture.status != nil && !fixture.media.isLoading && fixture.title(0) == "fixture-00.png")
        }

        @MainActor @Test func anUnchangedRefreshShowsLoadingWithoutApplyingPendingSearchText() async throws {
            let fixture = try await Fixture(files: 1, captures: 1)
            defer { fixture.teardown() }
            fixture.search.stringValue = "unapplied"
            fixture.media.refresh()
            #expect(fixture.media.isLoading)
            await fixture.finish()
            #expect(!fixture.media.isLoading && fixture.count == 2)
        }

        @MainActor @Test func regainingFolderAccessClearsTheNoticeWithoutRebuildingTheGrid() async throws {
            let fixture = try await Fixture(files: 1, missingFolder: true)
            defer { fixture.teardown() }
            try #require(fixture.status != nil)
            fixture.search.stringValue = "unapplied"
            try FileManager.default.createDirectory(at: fixture.root.appendingPathComponent("Missing"), withIntermediateDirectories: true)
            fixture.media.refresh()
            await fixture.finish()
            #expect(fixture.status == nil && fixture.count == 1)
        }

        @MainActor @Test func aFileArrivalAppliesThePendingSearch() async throws {
            let fixture = try await Fixture(files: 1, captures: 1)
            defer { fixture.teardown() }
            fixture.search.stringValue = "unapplied"
            let arrival = fixture.folder.appendingPathComponent("arrival.png")
            try Fixture.png().write(to: arrival)
            try await fixture.changes(arrival)
            #expect(fixture.count == 0)
        }

        @MainActor @Test func clearingTheArrivalSearchRevealsBothFilesAndTheCapture() async throws {
            let fixture = try await Fixture(files: 1, captures: 1)
            defer { fixture.teardown() }
            fixture.search.stringValue = "unapplied"
            let arrival = fixture.folder.appendingPathComponent("arrival.png")
            try Fixture.png().write(to: arrival)
            try await fixture.changes(arrival)
            fixture.query("")
            #expect(fixture.count == 3)
        }

        @MainActor @Test func aNewFileSlidesIntoAScrolledGridWithoutLosingItsSelectionOrScrollPosition() async throws {
            let fixture = try await Fixture(files: 24, width: 400)
            defer { fixture.teardown() }
            let requests = try ItemRequests(fixture.grid)
            fixture.grid.reloadData()
            fixture.view.layoutSubtreeIfNeeded()
            let clip = try #require(fixture.grid.enclosingScrollView?.contentView)
            fixture.grid.scrollToItems(at: [IndexPath(item: 4, section: 0)], scrollPosition: .top)
            fixture.view.layoutSubtreeIfNeeded()
            fixture.select(7)
            let origin = clip.bounds.origin
            try #require(origin.y > 0)
            let arrival = fixture.folder.appendingPathComponent("arrival.png")
            try Fixture.png().write(to: arrival)
            requests.requested.removeAll()
            try await fixture.changes(arrival)
            #expect(fixture.count == 25 && clip.bounds.origin == origin)
            #expect(fixture.grid.selectionIndexPaths == [IndexPath(item: 8, section: 0)])
            #expect(fixture.title(8) == "fixture-07.png")
            #expect(!requests.requested.contains(IndexPath(item: 8, section: 0)))
        }

        @MainActor @Test func insertingAheadOfAHoveredTileKeepsTheHighlightUnderThePointer() async throws {
            let fixture = try await Fixture(files: 6)
            defer { fixture.teardown() }
            let hovered = try #require(fixture.tile(1))
            fixture.window.pointer = hovered.convert(NSPoint(x: hovered.bounds.midX, y: hovered.bounds.midY), to: nil)
            hovered.resamplePointer()
            try #require(litFrameMatches(hovered, lit: true))
            let arrival = fixture.folder.appendingPathComponent("arrival.png")
            try Fixture.png().write(to: arrival)
            try await fixture.changes(arrival)
            #expect(fixture.title(2) == "fixture-01.png")
            #expect(litFrameMatches(try #require(fixture.tile(2)), lit: false))
            #expect(litFrameMatches(try #require(fixture.tile(1)), lit: true))
        }

        @MainActor @Test func editingTheSelectedFileMovesItsSelectionToItsNewPosition() async throws {
            let fixture = try await Fixture(files: 5)
            defer { fixture.teardown() }
            let requests = try ItemRequests(fixture.grid)
            fixture.grid.reloadData()
            fixture.view.layoutSubtreeIfNeeded()
            fixture.select(3)
            let file = fixture.file(3)
            try Fixture.png(32, 8).write(to: file)
            requests.requested.removeAll()
            try await fixture.changes(file)
            #expect(fixture.title(0) == file.lastPathComponent && fixture.count == 5)
            #expect(fixture.grid.selectionIndexPaths == [IndexPath(item: 0, section: 0)])
            #expect(!requests.requested.contains(IndexPath(item: 4, section: 0)))
        }

        @MainActor @Test func renamingAFileReplacesOnlyItsTile() async throws {
            let fixture = try await Fixture(files: 4)
            defer { fixture.teardown() }
            let requests = try ItemRequests(fixture.grid)
            fixture.grid.reloadData()
            fixture.view.layoutSubtreeIfNeeded()
            let old = fixture.file(1), renamed = fixture.folder.appendingPathComponent("renamed.png")
            try FileManager.default.moveItem(at: old, to: renamed)
            requests.requested.removeAll()
            try await fixture.changes(old, renamed)
            #expect(fixture.count == 4 && fixture.title(1) == "renamed.png")
            #expect(requests.requested == [IndexPath(item: 1, section: 0)])
        }

        @MainActor @Test func iCloudEvictionReconfiguresOnlyTheAffectedTile() async throws {
            let fixture = try await Fixture(files: 4, synced: true)
            defer { fixture.teardown() }
            let requests = try ItemRequests(fixture.grid)
            fixture.grid.reloadData()
            fixture.view.layoutSubtreeIfNeeded()
            let file = fixture.file(1)
            requests.requested.removeAll()
            await fixture.evict(file)
            #expect(fixture.media.items.first { $0.url == file }?.isLocal == false)
            #expect(fixture.count == 4 && fixture.title(1) == file.lastPathComponent)
            #expect(requests.requested == [IndexPath(item: 1, section: 0)])
        }

        @MainActor @Test func removingTheSelectedFileDropsOnlyItsTileAndClearsSelection() async throws {
            let fixture = try await Fixture(files: 4)
            defer { fixture.teardown() }
            let requests = try ItemRequests(fixture.grid)
            fixture.grid.reloadData()
            fixture.view.layoutSubtreeIfNeeded()
            fixture.select(1)
            let file = fixture.file(1)
            try FileManager.default.removeItem(at: file)
            requests.requested.removeAll()
            try await fixture.changes(file)
            #expect(fixture.count == 3 && fixture.title(1) == "fixture-02.png")
            #expect(fixture.grid.selectionIndexPaths.isEmpty && !requests.requested.contains(IndexPath(item: 0, section: 0)))
        }

        @MainActor @Test func captureMembershipPopulatesTheCollection() async throws {
            let fixture = try await Fixture(captures: 1)
            defer { fixture.teardown() }
            #expect(fixture.grid.numberOfItems(inSection: 0) == 1)
        }

        @MainActor @Test func aSearchFilterForcesTheGridToReloadPastTheFingerprint() async throws {
            let fixture = try await Fixture(captures: 1)
            defer { fixture.teardown() }
            fixture.query("no-match-filter")
            #expect(fixture.grid.numberOfItems(inSection: 0) == 0)
        }

        @MainActor @Test func clearingTheSearchForcesMembershipToReload() async throws {
            let fixture = try await Fixture(captures: 1)
            defer { fixture.teardown() }
            fixture.query("no-match-filter")
            fixture.query("")
            #expect(fixture.grid.numberOfItems(inSection: 0) == 1)
        }

        @MainActor @Test func theSearchFieldsClearButtonRestoresTheFullGrid() async throws {
            let fixture = try await Fixture(captures: 1, regularHeader: false)
            defer { fixture.teardown() }
            fixture.query("no-match-filter")
            fixture.search.stringValue = ""
            fixture.view.searchFieldDidEndSearching(try #require(fixture.search as? NSSearchField))
            #expect(fixture.grid.numberOfItems(inSection: 0) == 1)
        }

        @MainActor @Test func endingASearchThatIsAlreadyAppliedLeavesTheGridAlone() async throws {
            let fixture = try await Fixture(captures: 1, regularHeader: false)
            defer { fixture.teardown() }
            fixture.view.searchFieldDidEndSearching(try #require(fixture.search as? NSSearchField))
            #expect(fixture.grid.numberOfItems(inSection: 0) == 1)
        }

        @MainActor @Test func anUnavailableFolderShowsTheBottomStatusLineAndShortensTheGrid() async throws {
            let fixture = try await Fixture(files: 2, missingFolder: true, regularHeader: true, width: 400)
            defer { fixture.teardown() }
            let scroll = try #require(fixture.grid.enclosingScrollView)
            #expect(fixture.status == "1 folder needs access. Right-click empty space to fix.")
            #expect(scroll.frame.height == fixture.view.bounds.height - scroll.frame.minY - 28)
        }

        @MainActor @Test func aSingleAvailableFolderStartsWithNoStatusLine() async throws {
            let fixture = try await Fixture(files: 1, width: 400)
            defer { fixture.teardown() }
            #expect(fixture.status == nil)
        }

        @MainActor @Test func aLoadFailureStillRendersTheMediaItem() async throws {
            let fixture = try await Fixture(files: 1, corrupt: true, width: 400)
            defer { fixture.teardown() }
            #expect(fixture.catalog.loadError != nil && fixture.grid.numberOfItems(inSection: 0) == 1)
        }
    }
}
