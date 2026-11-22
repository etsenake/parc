import AppKit
import Testing
@testable import Parc
@testable import ParcLibrary

struct MediaLibraryGridTests {
    @MainActor private final class Tile: NSCollectionViewItem {
        override func loadView() { view = NSView() }
    }

    @MainActor private final class Source: NSObject, NSCollectionViewDataSource {
        var count: Int
        init(count: Int) { self.count = count }
        func collectionView(_ view: NSCollectionView, numberOfItemsInSection section: Int) -> Int { count }
        func collectionView(_ view: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            view.makeItem(withIdentifier: .init("tile"), for: indexPath)
        }
    }

    @MainActor private struct Fixture {
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 900, height: 700))
        let scroll: NSScrollView
        let grid = NSCollectionView()
        let layout = MediaLibraryGridLayout()
        let source: Source

        init(width: CGFloat = 305, count: Int = 12, style: NSScroller.Style = .overlay, autohides: Bool = true) {
            source = Source(count: count)
            scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: width, height: 600))
            host.addSubview(scroll)
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = autohides
            scroll.scrollerStyle = style
            layout.minimumInteritemSpacing = 10
            layout.minimumLineSpacing = 10
            layout.sectionInset = NSEdgeInsets(top: 12, left: 10, bottom: 10, right: 10)
            grid.collectionViewLayout = layout
            grid.register(Tile.self, forItemWithIdentifier: .init("tile"))
            grid.dataSource = source
            scroll.documentView = grid
            grid.reloadData()
            renderLayout()
        }

        func renderLayout() {
            host.layoutSubtreeIfNeeded()
            layout.remeasure()
            grid.layoutSubtreeIfNeeded()
        }

        func frame(_ index: Int) throws -> NSRect {
            try #require(layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))).frame
        }
    }

    @MainActor @Test(arguments: [CGFloat(290), 305, 632])
    func theMediaGridUsesTwoSquareColumnsAtEachWidth(_ width: CGFloat) throws {
        let fixture = Fixture(width: width)
        let first = try fixture.frame(0), second = try fixture.frame(1), third = try fixture.frame(2)
        let side = (width - 30) / 2
        #expect(first.size == CGSize(width: side, height: side) && second.size == first.size)
        #expect(first.minY == second.minY && second.minX > first.maxX)
        #expect(third.minY > first.maxY && third.minX == first.minX && second.maxX <= width - 10)
    }

    @MainActor @Test func narrowingAfterTheWideSpacesLayoutKeepsTwoColumns() throws {
        let fixture = Fixture(width: 632)
        fixture.scroll.frame.size.width = 305
        fixture.renderLayout()
        let first = try fixture.frame(0), second = try fixture.frame(1)
        #expect(first.minY == second.minY && fixture.layout.itemSize.width == 137.5)
    }

    @MainActor @Test func scrollingNeverResizesTiles() {
        let fixture = Fixture()
        let original = fixture.layout.itemSize
        fixture.scroll.contentView.scroll(to: CGPoint(x: 0, y: 200))
        fixture.renderLayout()
        #expect(fixture.layout.itemSize == original)
    }

    @MainActor @Test(arguments: [(4, true, false), (8, true, true), (40, true, true), (4, false, true)])
    func legacyScrollersReserveSpaceOnlyWhenNeeded(_ count: Int, _ autohides: Bool, _ reservesSpace: Bool) {
        let fixture = Fixture(count: count, style: .legacy, autohides: autohides)
        let bar = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        let side = (305 - 30 - (reservesSpace ? bar : 0)) / 2
        #expect(fixture.layout.itemSize == CGSize(width: side, height: side))
    }

    @MainActor @Test func changingToOverlayScrollersReclaimsTheReservedWidth() {
        let fixture = Fixture(count: 8, style: .legacy)
        fixture.scroll.scrollerStyle = .overlay
        fixture.renderLayout()
        #expect(fixture.layout.itemSize.width == 137.5)
    }

    @MainActor @Test func removingRowsThatNoLongerNeedAScrollerWidensTheTiles() {
        let fixture = Fixture(count: 40, style: .legacy)
        let narrow = fixture.layout.itemSize.width
        fixture.grid.performBatchUpdates {
            fixture.source.count = 4
            fixture.grid.deleteItems(at: Set((4..<40).map { IndexPath(item: $0, section: 0) }))
        }
        fixture.renderLayout()
        #expect(fixture.layout.itemSize.width > narrow)
    }

    @MainActor @Test func newlyArrivingRowsReserveTheScrollbarWidth() {
        let fixture = Fixture(count: 4, style: .legacy)
        let wide = fixture.layout.itemSize.width
        fixture.grid.performBatchUpdates {
            fixture.source.count = 8
            fixture.grid.insertItems(at: Set((4..<8).map { IndexPath(item: $0, section: 0) }))
        }
        fixture.renderLayout()
        #expect(fixture.layout.itemSize.width < wide)
    }

    @Test func anUnsizedGridStillHasPositiveTileGeometry() {
        #expect(MediaLibraryGridLayout.side(width: 0, insets: 20, spacing: 10) == 1)
    }
}

struct MediaLibraryThumbnailsTests {
    private typealias Cache = MediaLibraryThumbnails<String, Int>

    private func load(_ key: String, in cache: inout Cache) throws -> UInt64 {
        let fill = cache.fill(key, live: true)
        guard case .load(let ticket) = try #require(fill) else {
            Issue.record("Expected to start loading \(key)")
            throw CancellationError()
        }
        return ticket
    }

    private func save(_ image: Int, as key: String, in cache: inout Cache) throws {
        let ticket = try load(key, in: &cache)
        let saved = cache.finish(key, ticket: ticket, image: image)
        try #require(saved)
    }

    @Test func aHiddenTileWaitsForItsSectionToOpen() throws {
        var cache = Cache(capacity: 2)
        let hidden = cache.fill("shot", live: false)
        #expect(hidden == nil)
        _ = try load("shot", in: &cache)
        #expect(cache.isLoading("shot"))
    }

    @Test func aLoadingTileDoesNotStartAgain() throws {
        var cache = Cache(capacity: 2)
        _ = try load("shot", in: &cache)
        let duplicate = cache.fill("shot", live: true)
        #expect(duplicate == nil)
    }

    @Test func cachedThumbnailsAreAvailableEvenInAHiddenSection() throws {
        var cache = Cache(capacity: 2)
        try save(42, as: "shot", in: &cache)
        guard case .show(let image) = cache.fill("shot", live: false) else { Issue.record("Expected the cached image"); return }
        #expect(image == 42)
    }

    @Test func anAbandonedTicketCannotPopulateTheRetriedTile() throws {
        var cache = Cache(capacity: 2)
        let original = try load("shot", in: &cache)
        cache.abandon("shot", ticket: original)
        let fresh = try load("shot", in: &cache)
        let late = cache.finish("shot", ticket: original, image: 1)
        let accepted = cache.finish("shot", ticket: fresh, image: 2)
        #expect(!late && accepted)
    }

    @Test func closingTheLibraryRetiresBothCachedAndPendingThumbnails() throws {
        var cache = Cache(capacity: 2)
        try save(42, as: "existing", in: &cache)
        let ticket = try load("pending", in: &cache)
        cache.reset()
        #expect(cache.count == 0 && !cache.isLoading("pending"))
        let accepted = cache.finish("pending", ticket: ticket, image: 1)
        #expect(!accepted)
    }

    @Test func aFullCacheDropsTheLeastRecentlyShownThumbnail() throws {
        var cache = Cache(capacity: 2)
        try save(1, as: "a", in: &cache)
        try save(2, as: "b", in: &cache)
        _ = cache.fill("a", live: true)
        try save(3, as: "c", in: &cache)
        #expect(cache.peek("a") == 1 && cache.peek("b") == nil && cache.peek("c") == 3)
    }

    @Test func removingFilesForgetsOnlyTheirThumbnails() throws {
        var cache = Cache(capacity: 2)
        try save(1, as: "a", in: &cache)
        try save(2, as: "b", in: &cache)
        cache.forget(["a", "missing"])
        #expect(cache.peek("a") == nil && cache.peek("b") == 2)
    }
}
