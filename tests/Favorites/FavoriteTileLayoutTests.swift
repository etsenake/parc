import AppKit

@main struct FavoriteTileLayoutTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        func columns(_ frames: [CGRect]) -> [Int] {
            Dictionary(grouping: frames, by: \.minY).keys.sorted().map { y in frames.filter { $0.minY == y }.count }
        }

        let one = FavoriteGridLayout.frames(count: 1, width: 260)
        check(one.frames == [CGRect(x: 8, y: 8, width: 244, height: 47)], "A lone Favorite spans the tray")
        check(one.height == 63, "One row is 8 + 55")
        let five = FavoriteGridLayout.frames(count: 5, width: 260)
        check(columns(five.frames) == [3, 2], "Five Favorites balance as 3 + 2")
        check(five.height == 118, "Two rows are 8 + 2 × 55")
        check(five.frames[3].minX == 8 && five.frames[3].width == five.frames[0].width, "Short rows stay left aligned")
        check(abs(five.frames[1].minX - five.frames[0].maxX - 8) < 0.001, "Eight-point column gap")
        check(five.frames[3].minY - five.frames[0].minY == 55, "55-point row pitch")
        check(columns(FavoriteGridLayout.frames(count: 7, width: 260).frames) == [4, 3], "Seven balance as 4 + 3")
        check(columns(FavoriteGridLayout.frames(count: 9, width: 260).frames) == [3, 3, 3], "Nine balance as 3 × 3")
        check(columns(FavoriteGridLayout.frames(count: 10, width: 260).frames) == [4, 4, 2], "Ten balance as 4 + 4 + 2")
        check(columns(FavoriteGridLayout.frames(count: 4, width: 228).frames) == [4], "Four fit from 228 points")
        check(columns(FavoriteGridLayout.frames(count: 4, width: 227).frames) == [2, 2], "Below 228 the grid rebalances")
        check(columns(FavoriteGridLayout.frames(count: 3, width: 40).frames) == [1, 1, 1], "Narrow trays keep one column")
        check(FavoriteGridLayout.frames(count: 0, width: 260).frames.isEmpty, "No Favorites, no tiles")

        let pair = FavoriteChildLayouts.layouts(count: 2, size: CGSize(width: 55, height: 47), gap: 2, orientation: .horizontal)
        check(pair.map(\.rect) == [CGRect(x: 0, y: 0, width: 26.5, height: 47), CGRect(x: 28.5, y: 0, width: 26.5, height: 47)],
              "Recovered two-page split cells")
        check(pair[0].corners.rawValue == 5 && pair[1].corners.rawValue == 10, "Recovered corner masks 5 and 10")
        let single = FavoriteChildLayouts.layouts(count: 1, size: CGSize(width: 55, height: 47), gap: 2, orientation: .horizontal)
        check(single.count == 1 && single[0].corners.rawValue == 15, "A single page keeps every corner")
        let three = FavoriteChildLayouts.layouts(count: 3, size: CGSize(width: 55, height: 47), gap: 2, orientation: .horizontal)
        check(three.count == 3 && three[0].rect.height == 22.5 && three[2].rect.height == 47,
              "Column-major fill; the last remaining page takes the full height")
        check(three[0].corners == .layerMinXMinYCorner && three[1].corners == .layerMinXMaxYCorner,
              "Stacked pages keep only their outer corners")
        let stacked = FavoriteChildLayouts.layouts(count: 2, size: CGSize(width: 55, height: 47), gap: 2, orientation: .vertical)
        check(stacked.map(\.rect) == [CGRect(x: 0, y: 0, width: 55, height: 22.5), CGRect(x: 0, y: 24.5, width: 55, height: 22.5)],
              "Vertical splits stack into two rows")
        check(FavoriteChildLayouts.layouts(count: 2, size: .zero, gap: 2, orientation: .horizontal).isEmpty, "Empty size has no cells")

        let ring = FavoriteTilePaths.selectionRing(bounds: CGRect(x: 0, y: 0, width: 55, height: 47), count: 1, orientation: .horizontal)
        check(ring.contains(CGPoint(x: 27, y: 1), using: .evenOdd), "Ring covers the outer two points")
        check(!ring.contains(CGPoint(x: 27, y: 23), using: .evenOdd), "Ring leaves the tile interior open")
        let splitRing = FavoriteTilePaths.selectionRing(bounds: CGRect(x: 0, y: 0, width: 55, height: 47), count: 2, orientation: .horizontal)
        check(splitRing.contains(CGPoint(x: 27.5, y: 23), using: .evenOdd), "Split ring carves a divider")

        let tile = CGRect(x: 0, y: 0, width: 55, height: 47)
        let highlight = FavoriteTilePaths.highlightRing(bounds: tile)
        check(FavoriteTileMetrics.highlightRingWidth == 2 && FavoriteTileMetrics.highlightRingInset == 1,
              "Recovered ring width 2 and inset 1")
        check(highlight.boundingBox == CGRect(x: 1, y: 1, width: 53, height: 45), "Ring path is the bounds inset 1")
        check(highlight == FavoriteTilePaths.roundedRect(CGRect(x: 1, y: 1, width: 53, height: 45), radius: 11),
              "Ring corners are 12 − 1 continuous")
        let stroke = highlight.copy(strokingWithWidth: 2, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        check(stroke.boundingBox.insetBy(dx: -0.01, dy: -0.01).contains(tile)
              && tile.insetBy(dx: -0.01, dy: -0.01).contains(stroke.boundingBox),
              "The 2-point stroke is flush with the tile edge")
        check(stroke.contains(CGPoint(x: 27, y: 0.5)) && !stroke.contains(CGPoint(x: 27, y: 2.5)),
              "Stroke covers only the outer two points")

        func style(dark: Bool, hovered: Bool, dimmed: Bool) -> FavoriteSelectedStyle {
            FavoriteSelectedStyle(dark: dark, hovered: hovered, dimmed: dimmed)
        }
        let light = style(dark: false, hovered: false, dimmed: false)
        check(light.fillAlpha == 0.8 && light.washOpacity == 0 && light.shadowOpacity == 0.1
              && light.outlineShowsWash && light.outlineFillAlpha == nil && light.washAnimates, "Light selected tile")
        check(style(dark: false, hovered: true, dimmed: false).washOpacity == 0.1, "Light hovered wash .1")
        let dark = style(dark: true, hovered: false, dimmed: false)
        check(dark.fillAlpha == 0.45 && dark.washOpacity == 0.2 && dark.shadowOpacity == 0.1, "Dark selected tile")
        check(style(dark: true, hovered: true, dimmed: false).washOpacity == 0.3, "Dark hovered wash .3")
        for dark in [false, true] {
            for hovered in [false, true] {
                let dimmed = style(dark: dark, hovered: hovered, dimmed: true)
                let base = style(dark: dark, hovered: hovered, dimmed: false)
                check(dimmed.fillAlpha == base.fillAlpha * 0.5, "Dimmed fill is halved (dark \(dark), hovered \(hovered))")
                check(dimmed.washOpacity == 0 && dimmed.shadowOpacity == 0, "Dimmed wash and shadow are 0")
                check(!dimmed.outlineShowsWash && dimmed.outlineFillAlpha == 0.2, "Dimmed outline is mutedColor at .2")
                check(!dimmed.washAnimates, "A dimmed tile's hover change does not animate")
            }
        }

        typealias LayerSkip = FavoriteTileLayerLayoutSkip
        let tileBounds = CGRect(x: 0, y: 0, width: 60, height: 47)
        let local = CGRect(origin: .zero, size: tileBounds.size)
        let shadowPath = FavoriteTilePaths.roundedRect(tileBounds, radius: FavoriteTileMetrics.cornerRadius)
        let outlinePath = FavoriteTilePaths.selectionRing(bounds: local, count: 1, orientation: .horizontal)
        let glyph = LayerSkip.glyphGeometry(in: tileBounds.size, single: true)
        let cell = LayerSkip.CellGeometry(
            fillFrame: tileBounds,
            corners: [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner],
            iconFrame: CGRect(x: 22, y: 15.5, width: 16, height: 16),
            glyphFrame: glyph.frame,
            glyphFontSize: glyph.fontSize
        )
        check(LayerSkip.shouldSkip(
            bounds: tileBounds,
            shadowFrame: tileBounds, shadowPath: shadowPath, expectedShadowPath: shadowPath,
            selectionFrame: tileBounds, washFrame: local,
            outlineFrame: tileBounds, outlineMaskFrame: local, outlineImageFrame: local,
            outlineMaskPath: outlinePath, expectedOutlinePath: outlinePath,
            cells: [cell], expectedCells: [cell]
        ), "Matching tile frames/paths/cells skip")
        check(!LayerSkip.shouldSkip(
            bounds: tileBounds,
            shadowFrame: .zero, shadowPath: shadowPath, expectedShadowPath: shadowPath,
            selectionFrame: tileBounds, washFrame: local,
            outlineFrame: tileBounds, outlineMaskFrame: local, outlineImageFrame: local,
            outlineMaskPath: outlinePath, expectedOutlinePath: outlinePath,
            cells: [cell], expectedCells: [cell]
        ), "Mismatched shadow frame does not skip")
        check(!LayerSkip.shouldSkip(
            bounds: tileBounds,
            shadowFrame: tileBounds, shadowPath: nil, expectedShadowPath: shadowPath,
            selectionFrame: tileBounds, washFrame: local,
            outlineFrame: tileBounds, outlineMaskFrame: local, outlineImageFrame: local,
            outlineMaskPath: outlinePath, expectedOutlinePath: outlinePath,
            cells: [cell], expectedCells: [cell]
        ), "Missing shadow path does not skip")
        let splitOutline = FavoriteTilePaths.selectionRing(bounds: local, count: 2, orientation: .horizontal)
        check(!LayerSkip.shouldSkip(
            bounds: tileBounds,
            shadowFrame: tileBounds, shadowPath: shadowPath, expectedShadowPath: shadowPath,
            selectionFrame: tileBounds, washFrame: local,
            outlineFrame: tileBounds, outlineMaskFrame: local, outlineImageFrame: local,
            outlineMaskPath: outlinePath, expectedOutlinePath: splitOutline,
            cells: [cell], expectedCells: [cell]
        ), "Orientation/cell-count outline change does not skip")
        var moved = cell
        moved.fillFrame = tileBounds.offsetBy(dx: 1, dy: 0)
        check(!LayerSkip.shouldSkip(
            bounds: tileBounds,
            shadowFrame: tileBounds, shadowPath: shadowPath, expectedShadowPath: shadowPath,
            selectionFrame: tileBounds, washFrame: local,
            outlineFrame: tileBounds, outlineMaskFrame: local, outlineImageFrame: local,
            outlineMaskPath: outlinePath, expectedOutlinePath: outlinePath,
            cells: [moved], expectedCells: [cell]
        ), "Mismatched child fill frame does not skip")
        check(glyph.fontSize == 15, "Single-page monogram uses 15-point semibold")
        let splitGlyph = LayerSkip.glyphGeometry(in: CGSize(width: 26.5, height: 47), single: false)
        check(splitGlyph.fontSize == 11, "Split monogram uses 11-point semibold")

        print("\(checks) Favorite tile geometry assertions passed (no browser)")
    }
}
