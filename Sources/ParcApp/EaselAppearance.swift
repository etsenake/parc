import AppKit

/// Static EaselUI 1.122 contracts. Colors are the retained ARC_EaselUI catalog
/// values; native controls retain their existing action, focus and undo owners.
@MainActor
enum EaselAppearance {
    static let selection = NSColor(srgbRed: 108 / 255, green: 186 / 255, blue: 217 / 255, alpha: 1)
    static let surface = NSColor(name: "ParcEaselFloatingElementBackground") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .black : .white
    }
    static let text = NSColor(name: "ParcEaselTextColor") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white : .black
    }
    static let outline = NSColor(name: "ParcEaselModalOutline") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.99, green: 1, blue: 1, alpha: 0.1)
            : NSColor(srgbRed: 0.071, green: 0.059, blue: 0.180, alpha: 0.03)
    }
    static let error = NSColor(name: "ParcEaselErrorBorder") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(displayP3Red: 0.818, green: 0.535, blue: 0.507, alpha: 1)
            : NSColor(displayP3Red: 0.818, green: 0.230, blue: 0.138, alpha: 1)
    }
    static let toolbarInk = NSColor(name: "ParcEaselToolbarIcon") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(displayP3Red: 0.522, green: 0.529, blue: 0.557, alpha: 1)
            : NSColor(srgbRed: 0.373, green: 0.345, blue: 0.502, alpha: 1)
    }
    ///
    static let toolbarFill = NSColor(srgbRed: 0.086, green: 0.106, blue: 0.129, alpha: 1)
    static let toolbarSelected = NSColor(srgbRed: 0.290, green: 0.435, blue: 0.533, alpha: 1)
    static let toolbarGlyph = NSColor(srgbRed: 0.820, green: 0.898, blue: 0.945, alpha: 1)
    static let toolbarHeight: CGFloat = 44
    static let toolbarButton: CGFloat = 32
    static let toolbarRadius: CGFloat = 12
    static let toolbarSelectedRadius: CGFloat = 8
    static func configureToolbarScroll(_ scroll: NSScrollView) {
        scroll.drawsBackground = false; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        // Reserve the full36pt control +8pt inset height even under the system's
        // always-visible/legacy preference. This strip deliberately overlays.
        scroll.scrollerStyle = .overlay
    }
    static func drawHandle(at point: NSPoint, scale: CGFloat) {
        let mark = NSRect(x: point.x - 4 / scale, y: point.y - 4 / scale, width: 8 / scale, height: 8 / scale)
        selection.setFill(); NSBezierPath(ovalIn: mark).fill()
        surface.setFill(); NSBezierPath(ovalIn: mark.insetBy(dx: 2.5 / scale, dy: 2.5 / scale)).fill()
    }
    static func configureSurface(_ layer: CALayer?) {
        layer?.backgroundColor = surface.cgColor
        layer?.cornerRadius = 8; layer?.cornerCurve = .continuous
        layer?.borderWidth = 1; layer?.borderColor = outline.cgColor
    }
}

///
/// Native pressed, checked and keyboard-ring feedback are explicit AppKit
/// adaptations; drawing never changes the button's logical state or action.
@MainActor
final class EaselPaletteButton: NSButton {
    var usesToolbarInk = false
    var caption: String?
    private var pointerInside = false
    private var hoverTracking: NSTrackingArea?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false; focusRingType = .exterior; font = .systemFont(ofSize: 13)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking); hoverTracking = tracking
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { pointerInside = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { pointerInside = false; needsDisplay = true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); pointerInside = false; needsDisplay = true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override var state: NSControl.StateValue { didSet { needsDisplay = true } }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override func highlight(_ flag: Bool) { super.highlight(flag); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if usesToolbarInk {
            drawTool()
            return
        }
        let ink = EaselAppearance.text
        let alpha: CGFloat = !isEnabled ? 0 : isHighlighted ? 0.12 : state != .off ? 0.08 : pointerInside ? 0.03 : 0
        EaselAppearance.surface.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        if alpha > 0 {
            ink.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
        drawContent(foreground: ink.withAlphaComponent(isEnabled ? 1 : 0.35))
    }
    private func drawTool() {
        let radius = EaselAppearance.toolbarSelectedRadius
        if state != .off {
            EaselAppearance.toolbarSelected.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: radius, yRadius: radius).fill()
        } else if isEnabled, isHighlighted || pointerInside {
            EaselAppearance.toolbarGlyph.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: radius, yRadius: radius).fill()
        }
        drawContent(foreground: EaselAppearance.toolbarGlyph.withAlphaComponent(isEnabled ? 1 : 0.35), maximum: 18)
    }
    private func drawContent(foreground: NSColor, maximum: CGFloat? = nil) {
        if let image, imagePosition != .noImage {
            let size = image.size
            let cap: CGFloat = maximum ?? (caption == nil ? 20 : 24)
            let factor = min(1, cap / max(1, size.width), cap / max(1, size.height))
            let rect = NSRect(x: (bounds.width - size.width * factor) / 2, y: caption == nil ? (bounds.height - size.height * factor) / 2 : 11 + (24 - size.height * factor) / 2,
                              width: size.width * factor, height: size.height * factor)
            let tinted = NSImage(size: rect.size, flipped: false) { rect in
                image.draw(in: rect); foreground.setFill(); rect.fill(using: .sourceAtop); return true
            }
            tinted.draw(in: rect)
            if let caption {
                let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
                (caption as NSString).draw(in: NSRect(x: 0, y: 0, width: bounds.width, height: 11),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: foreground, .paragraphStyle: paragraph])
            }
        } else {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: foreground, .paragraphStyle: paragraph]
            let height = (title as NSString).size(withAttributes: attributes).height
            (title as NSString).draw(in: NSRect(x: 4, y: (bounds.height - height) / 2, width: max(0, bounds.width - 8), height: height), withAttributes: attributes)
        }
        if state == .mixed {
            foreground.setFill(); NSRect(x: bounds.midX - 3, y: 2, width: 6, height: 1).fill()
        }
    }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill() }
    override var focusRingMaskBounds: NSRect { bounds }
}

///
/// icon-only tools.
@MainActor
final class EaselToolbarPill: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = EaselAppearance.toolbarFill.cgColor
        layer?.cornerRadius = EaselAppearance.toolbarRadius
        layer?.cornerCurve = .continuous
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = EaselAppearance.toolbarFill.cgColor }
}

@MainActor
final class EaselSurfaceView: NSView {
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { effectiveAppearance.performAsCurrentDrawingAppearance { EaselAppearance.configureSurface(layer) } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

@MainActor
final class EaselDocumentView: NSView {
    var onLayout: (() -> Void)?
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = EaselAppearance.surface.cgColor } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func layout() { super.layout(); onLayout?() }

    /// Apply the enclosing Space's content-over-background appearance. Passing
    /// nil restores inherited window appearance, matching Optional.none at
    ///
    func inheritSpaceContentAppearance(_ appearance: NSAppearance?) {
        guard self.appearance != appearance else { return }
        self.appearance = appearance
        needsDisplay = true
    }
}
