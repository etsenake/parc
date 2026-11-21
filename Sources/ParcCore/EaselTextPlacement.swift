import Foundation

enum EaselTextPlacement {
    static func box(for item: EaselItem) -> EaselRect {
        switch item.kind {
        case .rectangle, .circle: return item.resolvedShape.map { EaselShapeGeometry.textRect($0, in: item.frame) } ?? item.frame
        default: return item.frame
        }
    }

    static func canvasBox(for item: EaselItem) -> EaselRect {
        let flip = EaselShapeGeometry.flipTransform(for: item)
        return flip.isIdentity ? box(for: item) : flip.bounds(of: box(for: item))
    }

    static func alignment(for item: EaselItem) -> EaselTextStyle.Alignment? {
        switch item.kind {
        case .rectangle, .circle: return item.textStyle?.alignment ?? .center
        default: return item.textStyle?.alignment
        }
    }

    static func centresVertically(_ item: EaselItem) -> Bool {
        item.kind == .rectangle || item.kind == .circle
    }

    static func clipsOverflow(_ item: EaselItem) -> Bool {
        item.kind == .rectangle || item.kind == .circle
    }

    static func retiresWhenEmpty(_ item: EaselItem) -> Bool { item.kind == .text }

    static func fittedFrameHeight(_ item: EaselItem, textHeight: @autoclosure () -> Double) -> Double? {
        switch item.kind {
        case .text:
            let height = textHeight()
            return height.isFinite ? max(item.frame.height, height) : nil
        default:
            return nil
        }
    }

    static func origin(for item: EaselItem, textHeight: Double, overflowing: Bool) -> EaselPoint {
        let box = box(for: item)
        guard centresVertically(item), !overflowing, textHeight.isFinite, textHeight < box.height else {
            return EaselPoint(x: box.x, y: box.y)
        }
        return EaselPoint(x: box.x, y: box.y + ((box.height - textHeight) / 2).rounded(.down))
    }
}
