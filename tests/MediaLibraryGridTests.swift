import AppKit

@main struct MediaLibraryGridTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        gridFollowsItsWidth()
        thumbnailsSurviveSectionSwitches()
    }
}

private final class GridSource: NSObject, NSCollectionViewDataSource {
    var count = 12
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        collectionView.makeItem(withIdentifier: .init("tile"), for: indexPath)
    }
}

private final class GridTile: NSCollectionViewItem {
    override func loadView() { view = NSView() }
}

@MainActor private func gridFollowsItsWidth() {
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700)); host.wantsLayer = true
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 0, height: 600))
    scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay
    host.addSubview(scroll)
    let layout = MediaLibraryGridLayout()
    layout.minimumInteritemSpacing = 10; layout.minimumLineSpacing = 10
    layout.sectionInset = NSEdgeInsets(top: 12, left: 10, bottom: 10, right: 10)
    let grid = NSCollectionView()
    grid.collectionViewLayout = layout
    grid.register(GridTile.self, forItemWithIdentifier: .init("tile"))
    let source = GridSource(); grid.dataSource = source
    scroll.documentView = grid
    grid.reloadData(); host.layoutSubtreeIfNeeded()
    func frames() -> (NSRect, NSRect, NSRect) {
        func frame(_ index: Int) -> NSRect { layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame ?? .zero }
        return (frame(0), frame(1), frame(2))
    }
    func expectTwoColumns(_ width: CGFloat, _ message: String) {
        scroll.frame.size.width = width
        host.layoutSubtreeIfNeeded()
        let (first, second, third) = frames()
        let side = (width - 30) / 2
        precondition(first.size == NSSize(width: side, height: side) && second.size == first.size,
                     "\(message): tiles are \(first.size) instead of \(side) square at width \(width)")
        precondition(first.minY == second.minY && second.minX > first.maxX && third.minY > first.maxY && third.minX == first.minX,
                     "\(message): the grid lost its two columns at width \(width): \(first) \(second) \(third)")
        precondition(second.maxX <= width - 10, "\(message): the second column overflows the grid at width \(width)")
    }
    expectTwoColumns(305, "Opening Media lays out two columns at the Library width")
    expectTwoColumns(632, "Showing the grid at the wide Spaces width keeps two columns")
    expectTwoColumns(305, "Narrowing back from the Spaces width resizes the tiles instead of stacking one tall column")
    expectTwoColumns(290, "A narrower Library resizes the tiles to the narrower grid")
    expectTwoColumns(305, "Widening again grows the tiles back")
    source.count = 13; grid.reloadData()
    expectTwoColumns(305, "Reloading the grid keeps the tiles sized for its width")
    let settled = layout.itemSize
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 200)); host.layoutSubtreeIfNeeded()
    precondition(layout.itemSize == settled, "Scrolling never resizes the tiles")
    let bar = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    let reserved = (305 - bar - 30) / 2
    func settle(_ style: NSScroller.Style, count: Int) {
        scroll.scrollerStyle = style; source.count = count; grid.reloadData()
        for width: CGFloat in [310, 305] { scroll.frame.size.width = width; host.layoutSubtreeIfNeeded() }
    }
    settle(.legacy, count: 4)
    precondition(layout.itemSize == settled, "A short grid with legacy scroll bars keeps full-width tiles, since no bar appears")
    settle(.legacy, count: 8)
    precondition(layout.itemSize == NSSize(width: reserved, height: reserved) && scroll.contentView.bounds.width == 305,
                 "A grid too tall at full width but short enough once the bar's width is reserved keeps the reserved tiles with the bar hidden: \(layout.itemSize)")
    host.layoutSubtreeIfNeeded(); grid.layoutSubtreeIfNeeded()
    precondition(layout.itemSize == NSSize(width: reserved, height: reserved), "That borderline grid stays put on the next pass instead of flip-flopping")
    scroll.scrollerStyle = .overlay
    NotificationCenter.default.post(name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)); grid.layoutSubtreeIfNeeded()
    precondition(layout.itemSize == settled, "Switching to overlay scroll bars gives the tiles the full width back without a resize: \(layout.itemSize)")
    scroll.scrollerStyle = .legacy
    NotificationCenter.default.post(name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)); grid.layoutSubtreeIfNeeded()
    precondition(layout.itemSize == NSSize(width: reserved, height: reserved), "Switching back to legacy scroll bars reserves the bar's width again")
    settle(.legacy, count: 40)
    precondition(layout.itemSize == NSSize(width: reserved, height: reserved),
                 "A grid taller than the page reserves the scroll bar's width, so tiles never jump as the bar appears: \(layout.itemSize)")
    func expectColumnsFit(_ message: String) {
        let (first, second, third) = frames()
        precondition(first.minY == second.minY && third.minX == first.minX && second.maxX <= scroll.contentView.bounds.width - 10,
                     "\(message): \(first) \(second) \(third) in a \(scroll.contentView.bounds.width)-point grid")
    }
    expectColumnsFit("Two columns fit beside a reserved scroll bar")
    grid.performBatchUpdates({ source.count = 4; grid.deleteItems(at: Set((4..<40).map { IndexPath(item: $0, section: 0) })) })
    precondition(grid.numberOfItems(inSection: 0) == source.count); grid.layoutSubtreeIfNeeded()
    precondition(layout.itemSize == settled, "Removing items until the grid fits gives the tiles the full width back: \(layout.itemSize)")
    expectColumnsFit("A grid that fits keeps two columns")
    grid.performBatchUpdates({ source.count = 40; grid.insertItems(at: Set((4..<40).map { IndexPath(item: $0, section: 0) })) })
    precondition(grid.numberOfItems(inSection: 0) == source.count); grid.layoutSubtreeIfNeeded()
    precondition(layout.itemSize == NSSize(width: reserved, height: reserved), "Files arriving past the page height reserve the scroll bar's width")
    expectColumnsFit("Files arriving past the page height keep two columns")
    scroll.autohidesScrollers = false
    settle(.legacy, count: 4)
    precondition(scroll.contentView.bounds.width < 305 && layout.itemSize == NSSize(width: reserved, height: reserved),
                 "A scroll bar that never hides always keeps its width reserved: \(layout.itemSize) in \(scroll.contentView.bounds.width)")
    expectColumnsFit("Even a short grid keeps two columns beside a scroll bar that never hides")
    grid.performBatchUpdates({ source.count = 2; grid.deleteItems(at: [IndexPath(item: 2, section: 0), IndexPath(item: 3, section: 0)]) })
    precondition(grid.numberOfItems(inSection: 0) == source.count); grid.layoutSubtreeIfNeeded()
    let (left, right, _) = frames()
    precondition(left.minY == right.minY && right.maxX <= scroll.contentView.bounds.width - 10, "Removing files beside a shown scroll bar never stacks one column")
    scroll.autohidesScrollers = true
    settle(.overlay, count: 40)
    precondition(layout.itemSize == settled, "Overlay scroll bars always give the tiles the full width")
    precondition(MediaLibraryGridLayout.side(width: 0, insets: 20, spacing: 10) == 1, "An unsized grid never produces an empty tile size")
    withExtendedLifetime(source) {}
}

@MainActor private func thumbnailsSurviveSectionSwitches() {
    typealias Fill = MediaLibraryThumbnails<String, Int>.Fill
    func loadTicket(_ fill: Fill?) -> UInt64? { if case .load(let ticket)? = fill { return ticket }; return nil }
    func shown(_ fill: Fill?) -> Int? { if case .show(let image)? = fill { return image }; return nil }
    var thumbnails = MediaLibraryThumbnails<String, Int>(capacity: 3)

    precondition(thumbnails.fill("hidden", live: false) == nil, "A tile filled while its section is hidden waits instead of loading")
    let hiddenTicket = loadTicket(thumbnails.fill("hidden", live: true))
    precondition(hiddenTicket != nil, "That waiting tile starts its load as soon as the section shows again")
    precondition(thumbnails.fill("hidden", live: true) == nil, "A tile already loading never starts a second load")
    precondition(thumbnails.finish("hidden", ticket: hiddenTicket!, image: 1), "The load lands in the cache")
    precondition(shown(thumbnails.fill("hidden", live: false)) == 1, "A cached thumbnail shows at once, even while hidden")

    let cancelled = loadTicket(thumbnails.fill("cancelled", live: true))!
    thumbnails.abandon("cancelled", ticket: cancelled)
    let retried = loadTicket(thumbnails.fill("cancelled", live: true))
    precondition(retried != nil && retried != cancelled, "A load cut short is retried the next time its tile needs it")
    precondition(!thumbnails.finish("cancelled", ticket: cancelled, image: 9), "A cut-short load that answers late cannot land")
    precondition(thumbnails.finish("cancelled", ticket: retried!, image: 2), "The retried load lands")

    let retiring = loadTicket(thumbnails.fill("retiring", live: true))!
    thumbnails.reset()
    precondition(thumbnails.count == 0 && !thumbnails.isLoading("retiring"), "Closing the Library drops cached thumbnails and loads")
    precondition(!thumbnails.finish("retiring", ticket: retiring, image: 3), "A load that answers after the Library closed cannot land")
    precondition(thumbnails.fill("retiring", live: false) == nil, "Nothing from before closing comes back")

    for (key, image) in [("a", 1), ("b", 2), ("c", 3)] {
        let ticket = loadTicket(thumbnails.fill(key, live: true))!
        precondition(thumbnails.finish(key, ticket: ticket, image: image))
    }
    precondition(shown(thumbnails.fill("a", live: true)) == 1, "Showing a thumbnail marks it recently used")
    let newest = loadTicket(thumbnails.fill("d", live: true))!
    precondition(thumbnails.finish("d", ticket: newest, image: 4))
    precondition(thumbnails.count == 3 && thumbnails.peek("b") == nil && thumbnails.peek("a") == 1,
                 "A full cache lets go of the least recently shown thumbnail, not the one just on screen")
    thumbnails.forget(["a", "missing"])
    precondition(thumbnails.peek("a") == nil && thumbnails.peek("c") == 3, "Forgetting removed files drops only their thumbnails")
}
