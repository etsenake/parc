import Foundation

package enum EaselTextPlacement {
    package static func box(for item: EaselItem) -> EaselRect {
        switch item.kind {
        case .rectangle, .circle: return item.resolvedShape.map { EaselShapeGeometry.textRect($0, in: item.frame) } ?? item.frame
        case .sticky: return EaselBoardObjects.stickyTextBox(item)
        default: return item.frame
        }
    }

    package static func canvasBox(for item: EaselItem) -> EaselRect {
        let flip = EaselShapeGeometry.flipTransform(for: item)
        return flip.isIdentity ? box(for: item) : flip.bounds(of: box(for: item))
    }

    package static func alignment(for item: EaselItem) -> EaselTextStyle.Alignment? {
        switch item.kind {
        case .rectangle, .circle: return item.textStyle?.alignment ?? .center
        default: return item.textStyle?.alignment
        }
    }

    package static func centresVertically(_ item: EaselItem) -> Bool {
        item.kind == .rectangle || item.kind == .circle
    }

    package static func clipsOverflow(_ item: EaselItem) -> Bool {
        item.kind == .rectangle || item.kind == .circle
    }

    package static func retiresWhenEmpty(_ item: EaselItem) -> Bool { item.kind == .text }

    package static func fittedFrameHeight(_ item: EaselItem, textHeight: @autoclosure () -> Double) -> Double? {
        switch item.kind {
        case .text:
            let height = textHeight()
            return height.isFinite ? max(item.frame.height, height) : nil
        case .sticky:
            return EaselBoardObjects.stickyHeight(item, textHeight: textHeight())
        default:
            return nil
        }
    }

    package static func origin(for item: EaselItem, textHeight: Double, overflowing: Bool) -> EaselPoint {
        let box = box(for: item)
        guard centresVertically(item), !overflowing, textHeight.isFinite, textHeight < box.height else {
            return EaselPoint(x: box.x, y: box.y)
        }
        return EaselPoint(x: box.x, y: box.y + ((box.height - textHeight) / 2).rounded(.down))
    }
}
