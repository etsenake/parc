import AppKit
import ParcCore

@MainActor
enum EaselCanvasRotation {
    private static var cursors: [Int: NSCursor] = [:]

    static func bounds(_ item: EaselItem) -> NSRect {
        let box = EaselRotation.bounds(of: item)
        return NSRect(x: box.x, y: box.y, width: box.width, height: box.height)
    }

    static func affine(_ transform: EaselTransform) -> NSAffineTransform {
        let value = NSAffineTransform()
        value.transformStruct = NSAffineTransformStruct(m11: transform.a, m12: transform.b, m21: transform.c,
                                                        m22: transform.d, tX: transform.tx, tY: transform.ty)
        return value
    }

    static func begin(_ item: EaselItem, straight: Bool) -> Bool {
        let transform = straight ? EaselTransform.mirror(horizontally: EaselRotation.mirrorsHorizontally(item),
            vertically: EaselRotation.mirrorsVertically(item), around: EaselRotation.center(of: item.frame)) : EaselRotation.transform(for: item)
        guard !transform.isIdentity else { return false }
        NSGraphicsContext.saveGraphicsState()
        affine(transform).concat()
        return true
    }

    static func polygonPath(_ points: [EaselPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: NSPoint(x: first.x, y: first.y))
        for point in points.dropFirst() { path.line(to: NSPoint(x: point.x, y: point.y)) }
        path.close()
        return path
    }

    static func cursor(toward direction: EaselPoint) -> NSCursor {
        let degrees = atan2(direction.y, direction.x) * 180 / .pi + 90
        let step = Int((EaselRotation.normalized(degrees) / 45).rounded()) * 45
        let key = (step % 360 + 360) % 360
        if let cached = cursors[key] { return cached }
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size, flipped: true) { _ in
            let turn = NSAffineTransform()
            turn.translateX(by: 12, yBy: 12); turn.rotate(byDegrees: CGFloat(key)); turn.translateX(by: -12, yBy: -12)
            turn.concat()
            let center = NSPoint(x: 12, y: 15), radius: CGFloat = 7
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: 212, endAngle: 328, clockwise: false)
            var heads: [NSBezierPath] = []
            for angle in [CGFloat(212), 328] {
                let radians = angle * .pi / 180
                let end = NSPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
                let sign: CGFloat = angle < 270 ? 1 : -1
                let along = NSPoint(x: sign * sin(radians), y: -sign * cos(radians))
                let across = NSPoint(x: -along.y, y: along.x)
                let head = NSBezierPath()
                head.move(to: NSPoint(x: end.x + along.x * 3.6, y: end.y + along.y * 3.6))
                head.line(to: NSPoint(x: end.x + across.x * 3.2 - along.x * 0.6, y: end.y + across.y * 3.2 - along.y * 0.6))
                head.line(to: NSPoint(x: end.x - across.x * 3.2 - along.x * 0.6, y: end.y - across.y * 3.2 - along.y * 0.6))
                head.close()
                heads.append(head)
            }
            arc.lineCapStyle = .round
            NSColor.white.setStroke(); NSColor.white.setFill()
            arc.lineWidth = 4.2; arc.stroke()
            for head in heads { head.lineWidth = 2.6; head.lineJoinStyle = .round; head.stroke(); head.fill() }
            NSColor.black.setStroke(); NSColor.black.setFill()
            arc.lineWidth = 1.7; arc.stroke()
            for head in heads { head.fill() }
            return true
        }
        let cursor = NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
        cursors[key] = cursor
        return cursor
    }

    static func badgeRect(at point: NSPoint, scale: CGFloat) -> NSRect {
        let scale = max(scale, 0.05)
        let widest = ("\u{2212}188.8°" as NSString).size(withAttributes: [.font: NoteTheme.chromeFont(11)])
        return NSRect(x: point.x + 14 / scale, y: point.y + 16 / scale, width: (ceil(widest.width) + 18) / scale, height: 22 / scale)
    }

    static func drawBadge(_ label: String, at point: NSPoint, scale: CGFloat) {
        EaselTextLayout.drawSizeBadge(label, in: badgeRect(at: point, scale: scale), scale: scale)
    }
}

extension EaselCanvasView {
    func transformMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] {
        let flips = EaselRotation.canFlip(context.items), turns = EaselRotation.canRotate(context.items)
        guard flips || turns else { return [] }
        return [
            EaselMenuRow(id: "flip-horizontal", title: "Flip Horizontal", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                         shortcut: "⇧H", isEnabled: flips, perform: guardedMenuAction { _ = $0.flipSelection(horizontal: true) }),
            EaselMenuRow(id: "flip-vertical", title: "Flip Vertical", symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down",
                         shortcut: "⇧V", isEnabled: flips, perform: guardedMenuAction { _ = $0.flipSelection(horizontal: false) }),
            EaselMenuRow(id: "rotate-left", title: "Rotate 90° Left", symbol: "rotate.left",
                         isEnabled: turns, perform: guardedMenuAction { _ = $0.rotateSelection(by: -90) }),
            EaselMenuRow(id: "rotate-right", title: "Rotate 90° Right", symbol: "rotate.right",
                         isEnabled: turns, perform: guardedMenuAction { _ = $0.rotateSelection(by: 90) })
        ]
    }
}
