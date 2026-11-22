import AppKit
import ParcCore

@MainActor
enum EaselShapeRendering {
    static func bezierPath(_ path: EaselPath) -> NSBezierPath {
        let result = NSBezierPath()
        func point(_ p: EaselPoint) -> NSPoint { NSPoint(x: p.x, y: p.y) }
        for element in path.elements {
            switch element {
            case .move(let p): result.move(to: point(p))
            case .line(let p): result.line(to: point(p))
            case .quad(let c, let p):
                let end = point(p), control = point(c)
                let start = result.isEmpty ? end : result.currentPoint
                result.curve(to: end,
                             controlPoint1: NSPoint(x: start.x + (control.x - start.x) * 2 / 3, y: start.y + (control.y - start.y) * 2 / 3),
                             controlPoint2: NSPoint(x: end.x + (control.x - end.x) * 2 / 3, y: end.y + (control.y - end.y) * 2 / 3))
            case .cubic(let c1, let c2, let p): result.curve(to: point(p), controlPoint1: point(c1), controlPoint2: point(c2))
            case .close: result.close()
            }
        }
        return result
    }

    static func outlinePath(for item: EaselItem) -> NSBezierPath? {
        guard let shape = item.resolvedShape else { return nil }
        let frame = NSRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height)
        if EaselShapeGeometry.usesOriginalLook(item) {
            return item.kind == .circle ? NSBezierPath(ovalIn: frame) : NSBezierPath(roundedRect: frame, xRadius: 5, yRadius: 5)
        }
        return bezierPath(EaselShapeGeometry.outline(shape, in: item.frame))
    }

    static func draw(_ item: EaselItem, adaptive: Bool) {
        guard let outline = outlinePath(for: item) else { return }
        let paint = EaselPaint(item, adaptive: adaptive)
        paint.fill(outline)
        paint.stroke(outline)
        if let shape = item.resolvedShape, case let details = EaselShapeGeometry.details(shape, in: item.frame), !details.isEmpty {
            let lines = bezierPath(details)
            lines.lineCapStyle = .round
            paint.stroke(lines)
        }
    }

    static func icon(_ shape: EaselShape, size: CGFloat, lineWidth: CGFloat = 1.25) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { bounds in
            let natural = EaselShapeGeometry.defaultSize(shape)
            let side = Double(bounds.width - 2 * (lineWidth + 0.5))
            let scale = side / max(natural.width, natural.height)
            let width = natural.width * scale, height = natural.height * scale
            let frame = EaselRect(x: (Double(bounds.width) - width) / 2, y: (Double(bounds.height) - height) / 2, width: width, height: height)
            let path = bezierPath(EaselShapeGeometry.outline(shape, in: frame))
            path.append(bezierPath(EaselShapeGeometry.details(shape, in: frame)))
            path.lineWidth = lineWidth; path.lineJoinStyle = .round; path.lineCapStyle = .round
            NSColor.black.setStroke(); path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = EaselShapeGeometry.displayName(shape)
        return image
    }

    static func drawOverflowMark(in box: NSRect, scale: CGFloat) {
        let unit = 1 / max(scale, 0.2), width = 10 * unit, height = 5 * unit
        let center = NSPoint(x: box.midX, y: box.maxY - 3 * unit)
        let mark = NSBezierPath()
        mark.move(to: NSPoint(x: center.x - width / 2, y: center.y - height))
        mark.line(to: center)
        mark.line(to: NSPoint(x: center.x + width / 2, y: center.y - height))
        mark.lineWidth = 2 * unit; mark.lineCapStyle = .round; mark.lineJoinStyle = .round
        EaselAppearance.selection.setStroke(); mark.stroke()
    }
}
