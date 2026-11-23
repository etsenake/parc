import AppKit

@MainActor
enum EaselScreenChrome {
    static func place(_ view: NSView, boardFrame: NSRect, scale: CGFloat) {
        let zoom = scale.isFinite && scale > 0 ? scale : 1
        let drawn = NSRect(x: 0, y: 0, width: boardFrame.width * zoom, height: boardFrame.height * zoom)
        if view.frame != boardFrame { view.frame = boardFrame }
        if view.bounds != drawn { view.bounds = drawn; view.needsLayout = true }
    }
}
