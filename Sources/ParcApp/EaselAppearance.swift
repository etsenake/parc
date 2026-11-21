import AppKit

@MainActor
enum EaselInk {
    static let automatic = "#252525"
    static let adaptiveName = NSColor.Name("Parc.Easel.Ink")
    static let adaptive: NSColor = {
        let ink = NoteTheme.ink
        return NSColor(name: adaptiveName) { appearance in
            var resolved = ink
            appearance.performAsCurrentDrawingAppearance { resolved = ink.usingColorSpace(.sRGB) ?? ink }
            return resolved
        }
    }()

    private static let paletteNamePrefix = "Parc.Easel.Palette."
    private static var paletteColors: [NSColor.Name: NSColor] = [:]

    static func isAutomatic(_ hex: String) -> Bool {
        let value = hex.uppercased()
        return value == automatic || value == automatic + "FF"
    }

    static func isAdaptive(_ color: NSColor) -> Bool { canonicalHex(of: color) != nil }

    static func canonicalHex(of color: NSColor) -> String? {
        guard color.type == .catalog else { return nil }
        let name = color.colorNameComponent
        if name == adaptiveName { return automatic }
        guard name.hasPrefix(paletteNamePrefix), let hex = name.split(separator: ".").last else { return nil }
        return EaselPalette.normalized(String(hex))
    }

    static func storedInk(_ color: NSColor) -> String? { canonicalHex(of: color).map { $0 + "FF" } }

    static func color(_ hex: String, adaptive adapts: Bool, role: EaselColorRole = .ink) -> NSColor {
        if adapts {
            if role == .ink, isAutomatic(hex) { return adaptive }
            if let variants = EaselPalette.variants(hex, role: role), variants.adapts { return paletteColor(variants, role: role) }
        }
        return fixed(hex)
    }

    static func fixed(_ hex: String) -> NSColor {
        let value = UInt32(hex.dropFirst().prefix(6), radix: 16) ?? 0x252525
        return NSColor(srgbRed: Double(value >> 16 & 255) / 255, green: Double(value >> 8 & 255) / 255,
                       blue: Double(value & 255) / 255, alpha: 1)
    }

    private static func paletteColor(_ variants: EaselColorVariants, role: EaselColorRole) -> NSColor {
        let name = NSColor.Name(paletteNamePrefix + role.rawValue + "." + variants.canonical)
        if let cached = paletteColors[name] { return cached }
        let light = fixed(variants.light), dark = fixed(variants.dark)
        let made = NSColor(name: name) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
        paletteColors[name] = made
        return made
    }

    static func adapting(_ value: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: value)
        value.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: value.length)) { color, range, _ in
            guard let color = color as? NSColor, color.type != .catalog, let rgb = color.usingColorSpace(.sRGB) else { return }
            let hex = String(format: "#%02X%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                             Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()),
                             Int((rgb.alphaComponent * 255).rounded()))
            let shown = self.color(hex, adaptive: true)
            guard isAdaptive(shown) else { return }
            result.addAttribute(.foregroundColor, value: shown, range: range)
        }
        return result
    }
}

@MainActor
struct EaselPaint {
    let inkColor: NSColor
    let fillColor: NSColor?
    let lineWidth: CGFloat
    let dash: [CGFloat]

    init(_ item: EaselItem, adaptive: Bool) {
        let source = EaselPaintRules.ink(item), opacity = EaselPaintRules.strokeOpacity(item)
        let ink = EaselInk.color(source.hex, adaptive: adaptive, role: source.role)
        let width = EaselPaintRules.strokeWidth(item)
        inkColor = opacity < 1 ? ink.withAlphaComponent(CGFloat(opacity)) : ink
        lineWidth = CGFloat(width)
        dash = EaselPaintRules.dashPattern(item.strokeDash, width: width).map { CGFloat($0) }
        switch EaselPaintRules.fill(item) {
        case .none: fillColor = nil
        case .wash(let opacity): fillColor = ink.withAlphaComponent(CGFloat(opacity))
        case .color(let hex, let role, let opacity):
            fillColor = EaselInk.color(hex, adaptive: adaptive, role: role).withAlphaComponent(CGFloat(opacity))
        }
    }

    var arrowHeadLength: CGFloat { CGFloat(EaselPaintRules.arrowHeadLength(width: Double(lineWidth))) }

    func fill(_ path: NSBezierPath) {
        guard let fillColor else { return }
        fillColor.setFill(); path.fill()
    }

    func stroke(_ path: NSBezierPath, dashed: Bool = true) {
        guard lineWidth > 0 else { return }
        path.lineWidth = lineWidth
        if dashed, !dash.isEmpty {
            path.lineCapStyle = .round
            path.setLineDash(dash, count: dash.count, phase: 0)
        }
        inkColor.setStroke(); path.stroke()
    }
}

@MainActor
enum EaselAppearance {
    static let selection = NoteTheme.accent
    static let surface = NoteTheme.menuFill
    static let paper = NoteTheme.paper
    static let text = NoteTheme.menuInk
    static let secondaryText = NoteTheme.secondaryInk
    static let outline = NoteTheme.menuHairline
    static let guide = NoteTheme.tertiaryInk
    static let cardFill = NoteTheme.panelFill
    static let cardStroke = NoteTheme.panelStroke
    static let error = NoteTheme.destructiveInk
    static let toolbarInk = NoteTheme.menuSecondaryInk
    static let toolbarFill = NoteTheme.menuFill
    static let toolbarHeight: CGFloat = NoteTheme.toolbarHeight
    static let toolbarButton: CGFloat = NoteTheme.toolbarButtonSize.width
    static let toolbarRadius: CGFloat = NoteTheme.menuRadius
    static let toolbarSelectedRadius: CGFloat = NoteTheme.controlRadius
    static let toolbarInset: CGFloat = (NoteTheme.toolbarHeight - NoteTheme.toolbarButtonSize.height) / 2
    static func configureToolbarScroll(_ scroll: NSScrollView) {
        scroll.drawsBackground = false; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
    }
    static func drawHandle(at point: NSPoint, scale: CGFloat, grow: CGFloat = 1) {
        let radius = 4 * grow / scale
        let mark = NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        selection.setFill(); NSBezierPath(ovalIn: mark).fill()
        surface.setFill(); NSBezierPath(ovalIn: mark.insetBy(dx: 2.5 / scale, dy: 2.5 / scale)).fill()
    }
    static func configureSurface(_ layer: CALayer?) {
        layer?.backgroundColor = surface.cgColor
        layer?.cornerRadius = NoteTheme.menuRadius; layer?.cornerCurve = .continuous
        layer?.borderWidth = 1; layer?.borderColor = outline.cgColor
    }
    static func configureFloatingShadow(_ layer: CALayer?, dark: Bool) {
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = dark ? 0.32 : 0.12
        layer?.shadowRadius = 7
        layer?.shadowOffset = CGSize(width: 0, height: -2)
    }
}

@MainActor
final class EaselPaletteButton: PointingHandButton {
    var usesToolbarInk = false
    var caption: String?
    private var pointerInside = false
    private var hoverTracking: NSTrackingArea?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false; focusRingType = .exterior; font = NoteTheme.chromeFont(13)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking); hoverTracking = tracking
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { pointerInside = isTopmost(atWindowPoint: event.locationInWindow); needsDisplay = true }
    override func mouseMoved(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { super.mouseMoved(with: event); return }
        let value = isTopmost(atWindowPoint: event.locationInWindow)
        guard value != pointerInside else { return }
        pointerInside = value; needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) { pointerInside = false; needsDisplay = true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); pointerInside = false; needsDisplay = true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override var state: NSControl.StateValue { didSet { needsDisplay = true } }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override func highlight(_ flag: Bool) { super.highlight(flag); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let radius = NoteTheme.controlRadius, plate = bounds
        let fill: NSColor? = !isEnabled ? nil : state != .off ? NoteTheme.checkedFill
            : isHighlighted ? NoteTheme.pressedFill : pointerInside ? NoteTheme.hoverFill : nil
        if let fill {
            fill.setFill()
            NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius).fill()
        }
        let ink = state != .off ? NoteTheme.checkedInk : isHighlighted || pointerInside ? NoteTheme.menuInk : NoteTheme.menuSecondaryInk
        drawContent(foreground: ink.withAlphaComponent(isEnabled ? 1 : NoteTheme.disabledOpacity), maximum: usesToolbarInk ? 18 : nil)
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
                    withAttributes: [.font: NoteTheme.nunitoBold(9), .foregroundColor: foreground, .paragraphStyle: paragraph])
            }
        } else {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NoteTheme.chromeFont(13), .foregroundColor: foreground, .paragraphStyle: paragraph]
            let height = (title as NSString).size(withAttributes: attributes).height
            (title as NSString).draw(in: NSRect(x: 4, y: (bounds.height - height) / 2, width: max(0, bounds.width - 8), height: height), withAttributes: attributes)
        }
        if state == .mixed {
            foreground.setFill(); NSRect(x: bounds.midX - 3, y: 2, width: 6, height: 1).fill()
        }
    }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: NoteTheme.controlRadius, yRadius: NoteTheme.controlRadius).fill() }
    override var focusRingMaskBounds: NSRect { bounds }
}

@MainActor
final class EaselToolbarPill: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = EaselAppearance.toolbarRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = EaselAppearance.toolbarFill.cgColor
            layer?.borderColor = EaselAppearance.outline.cgColor
        }
        EaselAppearance.configureFloatingShadow(layer, dark: NoteTheme.isDark(effectiveAppearance))
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: EaselAppearance.toolbarRadius,
                                   cornerHeight: EaselAppearance.toolbarRadius, transform: nil)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); needsDisplay = true }
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
    override func updateLayer() { effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = EaselAppearance.paper.cgColor } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func layout() { super.layout(); onLayout?() }

    func inheritSpaceContentAppearance(_ appearance: NSAppearance?) {
        guard self.appearance != appearance else { return }
        self.appearance = appearance
        needsDisplay = true
    }
}
