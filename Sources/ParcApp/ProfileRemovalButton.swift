import AppKit

/// Draw-only adaptation of DialogButtonStyleView. NSButton continues to own
/// mouse tracking, keyboard activation, enabled state and accessibility.
@MainActor
final class ProfileRemovalButton: SettingsHoverButton {
    let destructive: Bool
    init(_ title: String, destructive: Bool = false) {
        self.destructive = destructive
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryPushIn)
        font = .systemFont(ofSize: 13)
        focusRingType = .exterior
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    var preferredWidth: CGFloat { ceil((title as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 13)]).width) + 24 }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill() }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let pressed = cell?.isHighlighted == true
        let face: NSColor, foreground: NSColor, border: NSColor, shadow: NSColor
        if destructive {
            if isEnabled {
                face = pressed ? Self.color(0.816, 0.184, 0.067) : isHovered ? Self.color(0.867, 0.192, 0.071) : Self.color(0.961, 0.216, 0.078)
                foreground = .white
                shadow = Self.color(0.706, 0.145, 0.039, 0.3)
            } else {
                face = dark ? Self.color(0.404, 0.196, 0.161) : Self.color(1, 0.780, 0.741)
                foreground = dark ? .white.withAlphaComponent(0.172) : Self.color(0.961, 0.216, 0.078, 0.3)
                shadow = dark ? Self.color(0.706, 0.145, 0.039, 0.3) : Self.color(0.863, 0.165, 0.035, 0.3)
            }
            border = .clear
        } else {
            if dark {
                face = pressed ? Self.color(0.169, 0.165, 0.349) : isHovered ? Self.color(0.271, 0.267, 0.451) : Self.color(0.188, 0.184, 0.388)
                foreground = .white.withAlphaComponent(0.9)
                border = Self.color(0.388, 0.384, 0.682); shadow = .clear
            } else {
                face = pressed ? .init(white: 0.898, alpha: 1) : isHovered ? .init(white: 0.949, alpha: 1) : .white
                foreground = .init(white: 0.09, alpha: 1)
                border = .init(white: 0.859, alpha: 1); shadow = .init(white: 0.886, alpha: 1)
            }
        }
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState()
        let drop = NSShadow(); drop.shadowColor = shadow; drop.shadowBlurRadius = 2; drop.shadowOffset = .zero
        drop.set(); face.setFill(); shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        border.setStroke(); shape.lineWidth = 1; shape.stroke()
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: foreground]
        let text = title as NSString, size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
    private static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
