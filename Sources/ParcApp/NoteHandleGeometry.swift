import CoreGraphics
import Foundation

struct NoteHandleTarget: Hashable {
    var id: NoteBlockID
    var frame: CGRect
    var depth: Int
    var anchorY: CGFloat
}

struct NoteHandleRects: Hashable {
    var plus: CGRect
    var grip: CGRect
    var union: CGRect { plus.union(grip) }
}

enum NoteHandleGeometry {
    static let buttonSize = CGSize(width: 20, height: 24)
    static let buttonGap: CGFloat = 1
    static let contentGap: CGFloat = 4
    static let gutterReach: CGFloat = 52
    static let verticalSlop: CGFloat = 2
    static let trailingReach: CGFloat = 12

    static var barWidth: CGFloat { buttonSize.width * 2 + buttonGap }

    static func rects(blockFrame: CGRect, anchorY: CGFloat, minimumX: CGFloat = 0) -> NoteHandleRects {
        let height = buttonSize.height
        let centerY = blockFrame.minY + anchorY
        let gripX = max(minimumX + buttonSize.width + buttonGap, blockFrame.minX - contentGap - buttonSize.width)
        let y = (centerY - height / 2).rounded()
        let grip = CGRect(x: gripX.rounded(), y: y, width: buttonSize.width, height: height)
        let plus = CGRect(x: grip.minX - buttonGap - buttonSize.width, y: y, width: buttonSize.width, height: height)
        return NoteHandleRects(plus: plus, grip: grip)
    }

    static func hoverZone(for frame: CGRect) -> CGRect {
        CGRect(x: frame.minX - gutterReach, y: frame.minY - verticalSlop,
               width: frame.width + gutterReach + trailingReach, height: frame.height + verticalSlop * 2)
    }

    static func target(at point: CGPoint, in candidates: [NoteHandleTarget]) -> NoteHandleTarget? {
        var best: NoteHandleTarget?
        for candidate in candidates where hoverZone(for: candidate.frame).contains(point) {
            guard let current = best else { best = candidate; continue }
            if isBetter(candidate, than: current, at: point) { best = candidate }
        }
        return best
    }

    private static func isBetter(_ candidate: NoteHandleTarget, than current: NoteHandleTarget, at point: CGPoint) -> Bool {
        let candidateRow = inRow(point, candidate.frame), currentRow = inRow(point, current.frame)
        if candidateRow != currentRow { return candidateRow }
        if candidate.depth != current.depth { return candidate.depth > current.depth }
        return distance(from: point, to: candidate.frame) < distance(from: point, to: current.frame)
    }

    private static func inRow(_ point: CGPoint, _ frame: CGRect) -> Bool {
        point.y >= frame.minY && point.y < frame.maxY
    }

    private static func distance(from point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return dx * dx + dy * dy
    }
}

enum NoteAutoscroll {
    static let edgeZone: CGFloat = 64
    static let overshoot: CGFloat = 96
    static let minimumSpeed: CGFloat = 60
    static let maximumSpeed: CGFloat = 1800

    static func velocity(pointerY: CGFloat, visibleMinY: CGFloat, visibleMaxY: CGFloat) -> CGFloat {
        let height = visibleMaxY - visibleMinY
        guard height > 0 else { return 0 }
        let zone = min(edgeZone, height / 3)
        let topDepth = visibleMinY + zone - pointerY
        let bottomDepth = pointerY - (visibleMaxY - zone)
        if topDepth > 0 { return -speed(depth: topDepth, zone: zone) }
        if bottomDepth > 0 { return speed(depth: bottomDepth, zone: zone) }
        return 0
    }

    static func step(velocity: CGFloat, elapsed: TimeInterval) -> CGFloat {
        velocity * CGFloat(min(max(elapsed, 0), 0.05))
    }

    private static func speed(depth: CGFloat, zone: CGFloat) -> CGFloat {
        let reach = zone + overshoot
        let progress = min(depth, reach) / reach
        return minimumSpeed + (maximumSpeed - minimumSpeed) * progress * progress
    }
}

enum NoteDragPlan {
    static let threshold: CGFloat = 4
    static let maximumColumns = 5
    static let toggleExpandDelay: TimeInterval = 0.6

    static func crossesThreshold(from start: CGPoint, to point: CGPoint) -> Bool {
        let dx = point.x - start.x, dy = point.y - start.y
        return dx * dx + dy * dy >= threshold * threshold
    }

    static func draggedBlocks(grabbing grabbed: NoteBlockID, selection: NotePageSelection, page: NotePage) -> [NoteBlockID] {
        guard page.block(grabbed) != nil else { return [] }
        if case .blocks(let ids) = selection {
            let selected = page.topLevelSelection(ids).filter { page.block($0)?.kind != .column }
            if selected.contains(grabbed) || selected.contains(where: { page.isAncestor($0, of: grabbed) }) { return selected }
        }
        return page.block(grabbed)?.kind == .column ? [] : [grabbed]
    }

    static func affectedBlocks(_ dragged: [NoteBlockID], page: NotePage) -> [NoteBlockID] {
        let roots = Set(dragged)
        return page.documentOrder(includingCollapsed: false).filter { id in
            roots.contains(id) || roots.contains { page.isAncestor($0, of: id) }
        }
    }

    static func canDrop(_ dragged: [NoteBlockID], onto target: NoteBlockID, page: NotePage) -> Bool {
        !dragged.contains(target) && !dragged.contains { page.isAncestor($0, of: target) }
    }

    static func shouldExpand(_ block: NoteBlock?, hoveredSince start: TimeInterval?, now: TimeInterval) -> Bool {
        guard let block, block.isToggle, !block.props.expanded, let start else { return false }
        return now - start + 0.000_001 >= toggleExpandDelay
    }

    static func ghostOrigin(pointer: CGPoint, grabOffset: CGPoint) -> CGPoint {
        CGPoint(x: pointer.x - grabOffset.x, y: pointer.y - grabOffset.y)
    }

    static func copies(of ids: [NoteBlockID], in page: NotePage) -> [NoteBlock] {
        page.topLevelSelection(ids).compactMap { page.block($0)?.withFreshIDs() }
    }
}
