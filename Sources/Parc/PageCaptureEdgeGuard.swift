import AppKit

enum PageCaptureEdgeReach {
    static let reach: CGFloat = 24

    static func guardFrame(source: NSRect, host: NSRect) -> NSRect {
        guard source.width > 0, source.height > 0, host.intersects(source) else { return .zero }
        let minX = source.minX - host.minX <= reach ? host.minX : source.minX
        let minY = source.minY - host.minY <= reach ? host.minY : source.minY
        let maxX = host.maxX - source.maxX <= reach ? host.maxX : source.maxX
        let maxY = host.maxY - source.maxY <= reach ? host.maxY : source.maxY
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).intersection(host)
    }
}

@MainActor
final class PageCaptureEdgeGuard: NSView {
    private weak var overlay: NSView?
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    init(overlay: NSView) {
        self.overlay = overlay
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func install(in host: NSView, below overlay: NSView) {
        frame = PageCaptureEdgeReach.guardFrame(source: overlay.frame, host: host.bounds)
        host.addSubview(self, positioned: .below, relativeTo: overlay)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        overlay == nil ? nil : super.hitTest(point)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { overlay?.mouseDown(with: event) }
    override func mouseDragged(with event: NSEvent) { overlay?.mouseDragged(with: event) }
    override func mouseUp(with event: NSEvent) { overlay?.mouseUp(with: event) }
}
