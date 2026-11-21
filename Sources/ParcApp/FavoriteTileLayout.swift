import AppKit
import ParcCore
import QuartzCore
import SwiftUI

enum FavoriteTileMetrics {
    static let inset: CGFloat = 8
    static let spacing: CGFloat = 8
    static let minimumWidth: CGFloat = 47
    static let height: CGFloat = 47
    static let maximumColumns = 4
    static let cornerRadius: CGFloat = 12
    static let childGap: CGFloat = 2
    static let outlineWidth: CGFloat = 2
    static let highlightRingWidth: CGFloat = 2
    static let highlightRingInset: CGFloat = 1
    static let iconSide: CGFloat = 16
    static let childIconSide: CGFloat = 12
    static let hoverDuration: CFTimeInterval = 0.12
    static let washRefreshInterval: CFTimeInterval = 0.25
}

struct FavoriteSelectedStyle: Equatable {
    let fillAlpha: CGFloat
    let washOpacity: Float
    let shadowOpacity: Float
    let outlineShowsWash: Bool
    let outlineFillAlpha: CGFloat?
    let washAnimates: Bool

    init(dark: Bool, hovered: Bool, dimmed: Bool) {
        fillAlpha = (dark ? 0.45 : 0.8) * (dimmed ? 0.5 : 1)
        washOpacity = dimmed ? 0 : dark ? (hovered ? 0.3 : 0.2) : (hovered ? 0.1 : 0)
        shadowOpacity = dimmed ? 0 : 0.1
        outlineShowsWash = !dimmed
        outlineFillAlpha = dimmed ? 0.2 : nil
        washAnimates = !dimmed
    }
}

enum FavoriteGridLayout {
    static func frames(count: Int, width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        guard count > 0 else { return ([], 0) }
        let m = FavoriteTileMetrics.self
        let available = max(0, width - 2 * m.inset)
        let fit = Int(((available + m.spacing) / (m.minimumWidth + m.spacing)).rounded(.down))
        let fitted = max(min(m.maximumColumns, count, fit), 1)
        let rows = max((count + fitted - 1) / fitted, 1)
        let columns = max((count + rows - 1) / rows, 1)
        let tileWidth = (available - m.spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let frames = (0..<count).map { index in
            CGRect(x: m.inset + CGFloat(index % columns) * (tileWidth + m.spacing),
                   y: m.inset + CGFloat(index / columns) * (m.height + m.spacing),
                   width: tileWidth, height: m.height)
        }
        return (frames, m.inset + CGFloat(rows) * (m.height + m.spacing))
    }
}

struct FavoriteChildLayout: Equatable {
    let rect: CGRect
    let corners: CACornerMask
}

enum FavoriteChildLayouts {
    static func layouts(count: Int, size: CGSize, gap: CGFloat,
                        orientation: SplitOrientation, slotSizes: [Int]? = nil) -> [FavoriteChildLayout] {
        guard count > 0, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return [] }
        guard count > 1 else { return [cell(CGRect(origin: .zero, size: size), in: size, gap: gap)] }
        if let slotSizes, slotSizes.count > 1, slotSizes.allSatisfy({ $0 > 0 }),
           slotSizes.contains(where: { $0 > 1 }), slotSizes.reduce(0, +) == count {
            return stacked(slotSizes, size: size, orientation: orientation).map { cell($0, in: size, gap: gap) }
        }
        var cells: [CGRect] = []
        switch orientation {
        case .horizontal:
            let columns = max(1, min(count, Int((size.width / (size.height * 0.5)).rounded(.down))))
            let rows = (count + columns - 1) / columns
            let width = size.width / CGFloat(columns)
            var remaining = count
            for column in 0..<columns where remaining > 0 {
                let inColumn = remaining == columns - column ? 1 : min(rows, remaining)
                let height = size.height / CGFloat(inColumn)
                for row in 0..<inColumn {
                    cells.append(CGRect(x: CGFloat(column) * width, y: CGFloat(row) * height,
                                        width: width, height: height))
                }
                remaining -= inColumn
            }
        case .vertical:
            let slices = (count + 1) / 2
            let width = size.width / CGFloat(slices)
            let height = size.height * 0.5
            for row in 0..<2 {
                let start = row * slices, end = min(count, start + slices)
                guard start < end else { continue }
                for index in start..<end {
                    let span = end - start == 1 ? size.width : width
                    cells.append(CGRect(x: CGFloat(index - start) * width, y: CGFloat(row) * height,
                                        width: span, height: height))
                }
            }
        }
        return cells.map { cell($0, in: size, gap: gap) }
    }

    private static func stacked(_ slotSizes: [Int], size: CGSize, orientation: SplitOrientation) -> [CGRect] {
        let horizontal = orientation == .horizontal
        let slotLength = (horizontal ? size.width : size.height) / CGFloat(slotSizes.count)
        return slotSizes.enumerated().flatMap { slot, panes in
            let paneLength = (horizontal ? size.height : size.width) / CGFloat(panes)
            return (0..<panes).map { pane in
                horizontal
                    ? CGRect(x: CGFloat(slot) * slotLength, y: CGFloat(pane) * paneLength, width: slotLength, height: paneLength)
                    : CGRect(x: CGFloat(pane) * paneLength, y: CGFloat(slot) * slotLength, width: paneLength, height: slotLength)
            }
        }
    }

    private static func cell(_ raw: CGRect, in size: CGSize, gap: CGFloat) -> FavoriteChildLayout {
        let tolerance: CGFloat = 0.001
        let left = raw.minX <= tolerance, top = raw.minY <= tolerance
        let right = raw.maxX >= size.width - tolerance, bottom = raw.maxY >= size.height - tolerance
        let half = gap / 2
        let rect = CGRect(x: raw.minX + (left ? 0 : half), y: raw.minY + (top ? 0 : half),
                          width: raw.width - (left ? 0 : half) - (right ? 0 : half),
                          height: raw.height - (top ? 0 : half) - (bottom ? 0 : half))
        var corners: CACornerMask = []
        if left && top { corners.insert(.layerMinXMinYCorner) }
        if right && top { corners.insert(.layerMaxXMinYCorner) }
        if left && bottom { corners.insert(.layerMinXMaxYCorner) }
        if right && bottom { corners.insert(.layerMaxXMaxYCorner) }
        return FavoriteChildLayout(rect: rect, corners: corners)
    }
}

enum FavoriteTileLayerLayoutSkip {
    struct CellGeometry: Equatable {
        var fillFrame: CGRect
        var corners: CACornerMask
        var iconFrame: CGRect
        var glyphFrame: CGRect
        var glyphFontSize: CGFloat
    }

    static func shouldSkip(
        bounds: CGRect,
        shadowFrame: CGRect,
        shadowPath: CGPath?,
        expectedShadowPath: CGPath,
        selectionFrame: CGRect,
        washFrame: CGRect,
        outlineFrame: CGRect,
        outlineMaskFrame: CGRect,
        outlineImageFrame: CGRect,
        outlineMaskPath: CGPath?,
        expectedOutlinePath: CGPath,
        cells: [CellGeometry],
        expectedCells: [CellGeometry]
    ) -> Bool {
        let local = CGRect(origin: .zero, size: bounds.size)
        return shadowFrame == bounds
            && shadowPath == expectedShadowPath
            && selectionFrame == bounds
            && washFrame == local
            && outlineFrame == bounds
            && outlineMaskFrame == local
            && outlineImageFrame == local
            && outlineMaskPath == expectedOutlinePath
            && cells == expectedCells
    }

    static func glyphGeometry(in size: CGSize, single: Bool) -> (frame: CGRect, fontSize: CGFloat) {
        let font = NSFont.systemFont(ofSize: single ? 15 : 11, weight: .semibold)
        let height = ceil(font.ascender - font.descender)
        let frame = CGRect(x: 0, y: ((size.height - height) / 2).rounded(),
                           width: size.width, height: height)
        return (frame, font.pointSize)
    }
}

enum FavoriteTilePaths {
    static func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
        Path(roundedRect: rect, cornerRadius: radius, style: .continuous).cgPath
    }

    static func highlightRing(bounds: CGRect) -> CGPath {
        let m = FavoriteTileMetrics.self
        return roundedRect(bounds.insetBy(dx: m.highlightRingInset, dy: m.highlightRingInset),
                           radius: m.cornerRadius - m.highlightRingInset)
    }

    static func selectionRing(bounds: CGRect, count: Int, orientation: SplitOrientation, slotSizes: [Int]? = nil) -> CGPath {
        let m = FavoriteTileMetrics.self
        let path = CGMutablePath()
        path.addPath(roundedRect(bounds, radius: m.cornerRadius))
        let inner = bounds.insetBy(dx: m.outlineWidth, dy: m.outlineWidth)
        let radius = m.cornerRadius - m.outlineWidth
        let holes = FavoriteChildLayouts.layouts(count: count, size: inner.size, gap: m.outlineWidth,
                                                 orientation: orientation, slotSizes: slotSizes)
        for hole in holes {
            let rect = hole.rect.offsetBy(dx: inner.minX, dy: inner.minY)
            if hole.corners == [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner] {
                path.addPath(roundedRect(rect, radius: radius))
            } else {
                path.addPath(partiallyRounded(rect, radius: radius, corners: hole.corners))
            }
        }
        return path
    }

    private static func partiallyRounded(_ rect: CGRect, radius: CGFloat, corners: CACornerMask) -> CGPath {
        let r = min(radius, rect.width / 2, rect.height / 2)
        func corner(_ mask: CACornerMask) -> CGFloat { corners.contains(mask) ? r : 0 }
        let path = CGMutablePath()
        let topLeft = corner(.layerMinXMinYCorner), topRight = corner(.layerMaxXMinYCorner)
        let bottomLeft = corner(.layerMinXMaxYCorner), bottomRight = corner(.layerMaxXMaxYCorner)
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topRight), radius: topRight)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY), radius: bottomRight)
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft), radius: bottomLeft)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.minX + topLeft, y: rect.minY), radius: topLeft)
        path.closeSubpath()
        return path
    }
}
