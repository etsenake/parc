import AppKit
import Testing
@testable import Parc
@testable import ParcSidebar

struct FavoriteTileLayoutTests {
    private func rowCounts(_ frames: [CGRect]) -> [Int] {
        Dictionary(grouping: frames, by: \.minY).keys.sorted().map { y in frames.filter { $0.minY == y }.count }
    }

    private let tileSize = CGSize(width: 55, height: 47)

    @Test func aLoneFavoriteSpansTheTray() {
        let layout = FavoriteGridLayout.frames(count: 1, width: 260)
        #expect(layout.frames == [CGRect(x: 8, y: 8, width: 244, height: 47)])
        #expect(layout.height == 63)
    }

    @Test func fiveFavoritesBalanceAsThreeAndTwo() {
        let layout = FavoriteGridLayout.frames(count: 5, width: 260)
        #expect(rowCounts(layout.frames) == [3, 2])
        #expect(layout.height == 118)
    }

    @Test func shortRowsStayLeftAligned() {
        let frames = FavoriteGridLayout.frames(count: 5, width: 260).frames
        #expect(frames[3].minX == 8)
        #expect(frames[3].width == frames[0].width)
    }

    @Test func columnsAreEightPointsApart() {
        let frames = FavoriteGridLayout.frames(count: 5, width: 260).frames
        #expect(abs(frames[1].minX - frames[0].maxX - 8) < 0.001)
    }

    @Test func rowsAreFiftyFivePointsApart() {
        let frames = FavoriteGridLayout.frames(count: 5, width: 260).frames
        #expect(frames[3].minY - frames[0].minY == 55)
    }

    @Test(arguments: [(7, 260.0, [4, 3]), (9, 260.0, [3, 3, 3]), (10, 260.0, [4, 4, 2]),
                      (4, 228.0, [4]), (4, 227.0, [2, 2]), (3, 40.0, [1, 1, 1])])
    func favoritesBalanceAcrossRowsByTrayWidth(count: Int, width: Double, expected: [Int]) {
        #expect(rowCounts(FavoriteGridLayout.frames(count: count, width: width).frames) == expected)
    }

    @Test func noFavoritesMeansNoTiles() {
        #expect(FavoriteGridLayout.frames(count: 0, width: 260).frames.isEmpty)
    }

    @Test func aTwoPageSplitHasTwoCellsSideBySide() {
        let pair = FavoriteChildLayouts.layouts(count: 2, size: tileSize, gap: 2, orientation: .horizontal)
        #expect(pair.map(\.rect) == [CGRect(x: 0, y: 0, width: 26.5, height: 47), CGRect(x: 28.5, y: 0, width: 26.5, height: 47)])
    }

    @Test func aTwoPageSplitKeepsOnlyItsOuterCorners() {
        let pair = FavoriteChildLayouts.layouts(count: 2, size: tileSize, gap: 2, orientation: .horizontal)
        #expect(pair[0].corners.rawValue == 5)
        #expect(pair[1].corners.rawValue == 10)
    }

    @Test func aSinglePageKeepsEveryCorner() {
        let single = FavoriteChildLayouts.layouts(count: 1, size: tileSize, gap: 2, orientation: .horizontal)
        #expect(single.count == 1)
        #expect(single[0].corners.rawValue == 15)
    }

    @Test func threePagesFillColumnMajorAndTheLastTakesTheFullHeight() {
        let three = FavoriteChildLayouts.layouts(count: 3, size: tileSize, gap: 2, orientation: .horizontal)
        #expect(three.count == 3)
        #expect(three[0].rect.height == 22.5)
        #expect(three[2].rect.height == 47)
    }

    @Test func stackedPagesKeepOnlyTheirOuterCorners() {
        let three = FavoriteChildLayouts.layouts(count: 3, size: tileSize, gap: 2, orientation: .horizontal)
        #expect(three[0].corners == .layerMinXMinYCorner)
        #expect(three[1].corners == .layerMinXMaxYCorner)
    }

    @Test func aVerticalSplitStacksIntoTwoRows() {
        let stacked = FavoriteChildLayouts.layouts(count: 2, size: tileSize, gap: 2, orientation: .vertical)
        #expect(stacked.map(\.rect) == [CGRect(x: 0, y: 0, width: 55, height: 22.5), CGRect(x: 0, y: 24.5, width: 55, height: 22.5)])
    }

    @Test func anEmptySizeHasNoCells() {
        #expect(FavoriteChildLayouts.layouts(count: 2, size: .zero, gap: 2, orientation: .horizontal).isEmpty)
    }

    @Test func aStackedRightColumnDrawsAFullHeightPaneBesideTwoStackedPanes() {
        let layouts = FavoriteChildLayouts.layouts(count: 3, size: tileSize, gap: 2, orientation: .horizontal, slotSizes: [1, 2])
        #expect(layouts.map(\.rect) == [CGRect(x: 0, y: 0, width: 26.5, height: 47), CGRect(x: 28.5, y: 0, width: 26.5, height: 22.5),
                                        CGRect(x: 28.5, y: 24.5, width: 26.5, height: 22.5)])
        #expect(layouts.map(\.corners.rawValue) == [5, 2, 8])
    }

    @Test func aDividedLowerRowDrawsAFullWidthPaneAboveTwoSideBySidePanes() {
        let layouts = FavoriteChildLayouts.layouts(count: 3, size: tileSize, gap: 2, orientation: .vertical, slotSizes: [1, 2])
        #expect(layouts.map(\.rect) == [CGRect(x: 0, y: 0, width: 55, height: 22.5), CGRect(x: 0, y: 24.5, width: 26.5, height: 22.5),
                                        CGRect(x: 28.5, y: 24.5, width: 26.5, height: 22.5)])
        #expect(layouts.map(\.corners.rawValue) == [3, 4, 8])
    }

    @Test(arguments: [[1, 1], [1, 1, 1]])
    func aShapeThatDoesNotMatchThePagesDrawsTheFlatIcon(slotSizes: [Int]) {
        let flat = FavoriteChildLayouts.layouts(count: 3, size: tileSize, gap: 2, orientation: .horizontal)
        #expect(FavoriteChildLayouts.layouts(count: 3, size: tileSize, gap: 2, orientation: .horizontal, slotSizes: slotSizes) == flat)
    }

    @Test func theSelectionRingCarvesTheStackedColumnsOwnDivider() {
        let bounds = CGRect(origin: .zero, size: tileSize)
        let stacked = FavoriteTilePaths.selectionRing(bounds: bounds, count: 3, orientation: .horizontal, slotSizes: [1, 2])
        let flat = FavoriteTilePaths.selectionRing(bounds: bounds, count: 3, orientation: .horizontal)
        #expect(stacked.contains(CGPoint(x: 40, y: 23.5), using: .evenOdd))
        #expect(!flat.contains(CGPoint(x: 40, y: 23.5), using: .evenOdd))
    }

    @Test func theSelectionRingCoversTheOuterTwoPoints() {
        let ring = FavoriteTilePaths.selectionRing(bounds: CGRect(origin: .zero, size: tileSize), count: 1, orientation: .horizontal)
        #expect(ring.contains(CGPoint(x: 27, y: 1), using: .evenOdd))
    }

    @Test func theSelectionRingLeavesTheTileInteriorOpen() {
        let ring = FavoriteTilePaths.selectionRing(bounds: CGRect(origin: .zero, size: tileSize), count: 1, orientation: .horizontal)
        #expect(!ring.contains(CGPoint(x: 27, y: 23), using: .evenOdd))
    }

    @Test func aSplitSelectionRingCarvesADivider() {
        let ring = FavoriteTilePaths.selectionRing(bounds: CGRect(origin: .zero, size: tileSize), count: 2, orientation: .horizontal)
        #expect(ring.contains(CGPoint(x: 27.5, y: 23), using: .evenOdd))
    }

    private var tile: CGRect { CGRect(x: 0, y: 0, width: 55, height: 47) }

    @Test func theHighlightRingIsTwoPointsWideAndInsetOne() {
        #expect(FavoriteTileMetrics.highlightRingWidth == 2)
        #expect(FavoriteTileMetrics.highlightRingInset == 1)
    }

    @Test func theHighlightRingPathIsTheBoundsInsetOne() {
        #expect(FavoriteTilePaths.highlightRing(bounds: tile).boundingBox == CGRect(x: 1, y: 1, width: 53, height: 45))
    }

    @Test func theHighlightRingCornersAreTwelveMinusOneContinuous() {
        #expect(FavoriteTilePaths.highlightRing(bounds: tile)
                == FavoriteTilePaths.roundedRect(CGRect(x: 1, y: 1, width: 53, height: 45), radius: 11))
    }

    @Test func theTwoPointStrokeIsFlushWithTheTileEdge() {
        let stroke = FavoriteTilePaths.highlightRing(bounds: tile).copy(strokingWithWidth: 2, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        #expect(stroke.boundingBox.insetBy(dx: -0.01, dy: -0.01).contains(tile))
        #expect(tile.insetBy(dx: -0.01, dy: -0.01).contains(stroke.boundingBox))
    }

    @Test func theStrokeCoversOnlyTheOuterTwoPoints() {
        let stroke = FavoriteTilePaths.highlightRing(bounds: tile).copy(strokingWithWidth: 2, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        #expect(stroke.contains(CGPoint(x: 27, y: 0.5)))
        #expect(!stroke.contains(CGPoint(x: 27, y: 2.5)))
    }

    private func style(dark: Bool, hovered: Bool, dimmed: Bool) -> FavoriteSelectedStyle {
        FavoriteSelectedStyle(dark: dark, hovered: hovered, dimmed: dimmed)
    }

    @Test func aLightSelectedTileFillsAtPointEightWithAFaintShadow() {
        let light = style(dark: false, hovered: false, dimmed: false)
        #expect(light.fillAlpha == 0.8)
        #expect(light.washOpacity == 0)
        #expect(light.shadowOpacity == 0.1)
        #expect(light.outlineShowsWash)
        #expect(light.outlineFillAlpha == nil)
        #expect(light.washAnimates)
    }

    @Test func aLightHoveredTileWashesAtPointOne() {
        #expect(style(dark: false, hovered: true, dimmed: false).washOpacity == 0.1)
    }

    @Test func aDarkSelectedTileFillsAtPointFortyFive() {
        let dark = style(dark: true, hovered: false, dimmed: false)
        #expect(dark.fillAlpha == 0.45)
        #expect(dark.washOpacity == 0.2)
        #expect(dark.shadowOpacity == 0.1)
    }

    @Test func aDarkHoveredTileWashesAtPointThree() {
        #expect(style(dark: true, hovered: true, dimmed: false).washOpacity == 0.3)
    }

    @Test(arguments: [(false, false), (false, true), (true, false), (true, true)])
    func aDimmedTileHalvesItsFill(dark: Bool, hovered: Bool) {
        #expect(style(dark: dark, hovered: hovered, dimmed: true).fillAlpha == style(dark: dark, hovered: hovered, dimmed: false).fillAlpha * 0.5)
    }

    @Test(arguments: [(false, false), (false, true), (true, false), (true, true)])
    func aDimmedTileDropsItsWashAndShadow(dark: Bool, hovered: Bool) {
        let dimmed = style(dark: dark, hovered: hovered, dimmed: true)
        #expect(dimmed.washOpacity == 0)
        #expect(dimmed.shadowOpacity == 0)
    }

    @Test(arguments: [(false, false), (false, true), (true, false), (true, true)])
    func aDimmedTilesOutlineIsTheMutedColorAtPointTwo(dark: Bool, hovered: Bool) {
        let dimmed = style(dark: dark, hovered: hovered, dimmed: true)
        #expect(!dimmed.outlineShowsWash)
        #expect(dimmed.outlineFillAlpha == 0.2)
    }

    @Test(arguments: [(false, false), (false, true), (true, false), (true, true)])
    func aDimmedTilesHoverChangeDoesNotAnimate(dark: Bool, hovered: Bool) {
        #expect(!style(dark: dark, hovered: hovered, dimmed: true).washAnimates)
    }

    typealias LayerSkip = FavoriteTileLayerLayoutSkip

    private struct LayerGeometry {
        let bounds = CGRect(x: 0, y: 0, width: 60, height: 47)
        let local = CGRect(x: 0, y: 0, width: 60, height: 47)
        let shadowPath: CGPath
        let outlinePath: CGPath
        let cell: LayerSkip.CellGeometry
        var shadowFrame: CGRect
        var liveShadowPath: CGPath?
        var expectedOutlinePath: CGPath
        var liveCells: [LayerSkip.CellGeometry]

        init() {
            shadowPath = FavoriteTilePaths.roundedRect(bounds, radius: FavoriteTileMetrics.cornerRadius)
            outlinePath = FavoriteTilePaths.selectionRing(bounds: local, count: 1, orientation: .horizontal)
            let glyph = LayerSkip.glyphGeometry(in: bounds.size, single: true)
            cell = LayerSkip.CellGeometry(
                fillFrame: bounds,
                corners: [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner],
                iconFrame: CGRect(x: 22, y: 15.5, width: 16, height: 16),
                glyphFrame: glyph.frame,
                glyphFontSize: glyph.fontSize
            )
            shadowFrame = bounds
            liveShadowPath = shadowPath
            expectedOutlinePath = outlinePath
            liveCells = [cell]
        }

        var skips: Bool {
            LayerSkip.shouldSkip(
                bounds: bounds,
                shadowFrame: shadowFrame, shadowPath: liveShadowPath, expectedShadowPath: shadowPath,
                selectionFrame: bounds, washFrame: local,
                outlineFrame: bounds, outlineMaskFrame: local, outlineImageFrame: local,
                outlineMaskPath: outlinePath, expectedOutlinePath: expectedOutlinePath,
                cells: liveCells, expectedCells: [cell]
            )
        }
    }

    @Test func matchingTileFramesPathsAndCellsSkipTheLayerLayout() {
        #expect(LayerGeometry().skips)
    }

    @Test func aMismatchedShadowFrameDoesNotSkip() {
        var geometry = LayerGeometry()
        geometry.shadowFrame = .zero
        #expect(!geometry.skips)
    }

    @Test func aMissingShadowPathDoesNotSkip() {
        var geometry = LayerGeometry()
        geometry.liveShadowPath = nil
        #expect(!geometry.skips)
    }

    @Test func anOrientationOrCellCountOutlineChangeDoesNotSkip() {
        var geometry = LayerGeometry()
        geometry.expectedOutlinePath = FavoriteTilePaths.selectionRing(bounds: geometry.local, count: 2, orientation: .horizontal)
        #expect(!geometry.skips)
    }

    @Test func aMismatchedChildFillFrameDoesNotSkip() {
        var geometry = LayerGeometry()
        var moved = geometry.cell
        moved.fillFrame = geometry.bounds.offsetBy(dx: 1, dy: 0)
        geometry.liveCells = [moved]
        #expect(!geometry.skips)
    }

    @Test func aSinglePageMonogramUsesFifteenPointSemibold() {
        #expect(LayerSkip.glyphGeometry(in: CGSize(width: 60, height: 47), single: true).fontSize == 15)
    }

    @Test func aSplitMonogramUsesElevenPointSemibold() {
        #expect(LayerSkip.glyphGeometry(in: CGSize(width: 26.5, height: 47), single: false).fontSize == 11)
    }
}
