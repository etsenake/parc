import AppKit
import ParcCore
import QuartzCore
import ParcKit

struct PeekControlColors: Equatable {
    let fill: NSColor
    let accent: NSColor

    static let confirmation = PeekControlColors(
        fill: NSColor(srgbRed: 0.961, green: 0.216, blue: 0.078, alpha: 1), accent: .white)

    init(fill: NSColor, accent: NSColor) { self.fill = fill; self.accent = accent }

    init(palette: ThemeChromePalette) {
        let appearance = palette.contentAppearance ?? NSAppearance.currentDrawing()
        var fill = palette.backgroundExtra, accent = palette.foregroundPrimary
        appearance.performAsCurrentDrawingAppearance {
            fill = palette.backgroundExtra.usingColorSpace(.sRGB) ?? palette.backgroundExtra
            accent = palette.foregroundPrimary.usingColorSpace(.sRGB) ?? palette.foregroundPrimary
        }
        let light = appearance.bestMatch(from: [.aqua, .darkAqua]) != .darkAqua
        self.init(fill: fill, accent: light ? Self.darkened(accent, toLuminance: 0.4) : accent)
    }

    static func darkened(_ color: NSColor, toLuminance maximum: Double) -> NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return color }
        func unit(_ value: CGFloat) -> Double { min(1, max(0, Double(value))) }
        guard let base = ThemeColor(red: unit(rgb.redComponent), green: unit(rgb.greenComponent),
                                    blue: unit(rgb.blueComponent)) else { return rgb }
        func linear(_ value: Double) -> Double { value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(base.red) + 0.7152 * linear(base.green) + 0.0722 * linear(base.blue)
        guard luminance > maximum else { return rgb }
        let hsl = base.hsl
        guard let shifted = ThemeColor.hsl(hue: hsl.hue, saturation: hsl.saturation,
                                           lightness: max(0, hsl.lightness - (luminance - maximum))) else { return rgb }
        return NSColor(srgbRed: shifted.red, green: shifted.green, blue: shifted.blue, alpha: rgb.alphaComponent)
    }
}

enum PeekCardAppearance {
    static func cardFill(dark: Bool) -> NSColor {
        let white: CGFloat = dark ? 0.085 : 0.99
        return NSColor(srgbRed: white, green: white, blue: white, alpha: 1)
    }
    static let borderColor = NSColor.black.withAlphaComponent(0.25)
    static let borderWidth: CGFloat = 2
    static let shadowOpacity: Float = 0.3
    static let shadowRadius: CGFloat = 4
    static let backdropOpacity: CGFloat = 0.7
    static let cornerRadius: CGFloat = 8
    static let shadowOffsetY: CGFloat = 1
}

@MainActor
final class PeekControlButton: PointingHandButton {
    static let diameter: CGFloat = 32
    private static let glyphBox: CGFloat = 14
    private static let leadingInset: CGFloat = 9
    private static let labelSpacing: CGFloat = 7
    private static let trailingInset: CGFloat = 8
    private static let labelFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    var actionBlock: (() -> Void)?
    private let face = CALayer()
    private let clip = CALayer()
    private let glyph = CALayer()
    private let label = CATextLayer()
    private var symbol: String
    private var text: String?
    private var colors = PeekControlColors(fill: .controlBackgroundColor, accent: .labelColor)
    private var hoverTracking: NSTrackingArea?
    private var hovered = false
    private var pressed = false
    private var animatesNextResize = false

    init(symbol: String) {
        self.symbol = symbol
        super.init(frame: NSRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter))
        title = ""; image = nil; isBordered = false
        bezelStyle = .regularSquare; focusRingType = .default
        target = self; action = #selector(invoke)
        wantsLayer = true
        layer?.masksToBounds = false
        face.masksToBounds = false
        face.anchorPoint = CGPoint(x: 0, y: 0.5)
        face.shadowColor = NSColor.black.cgColor
        clip.masksToBounds = true
        clip.anchorPoint = CGPoint(x: 0, y: 0.5)
        clip.addSublayer(glyph)
        label.alignmentMode = .left
        label.truncationMode = .end
        label.opacity = 0
        clip.addSublayer(label)
        face.addSublayer(clip)
        layer?.addSublayer(face)
        refreshContent()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var isEnabled: Bool { didSet { if isEnabled != oldValue { refreshFace(animated: false) } } }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        let radius = bounds.height / 2
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }

    @objc private func invoke() { actionBlock?() }

    var preferredWidth: CGFloat {
        guard let text, !text.isEmpty else { return Self.diameter }
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: Self.labelFont]).width)
        return Self.leadingInset + Self.glyphBox + 1 + Self.labelSpacing + textWidth + Self.trailingInset
    }

    func setContent(symbol: String, text: String?, colors: PeekControlColors) {
        let expanding = (self.text == nil) != (text == nil)
        guard symbol != self.symbol || text != self.text || colors != self.colors else { return }
        self.symbol = symbol; self.text = text; self.colors = colors
        refreshContent()
        needsLayout = true
        guard expanding else { return }
        animatesNextResize = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animatesNextResize else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = text == nil ? 1 : 0; fade.toValue = text == nil ? 0 : 1; fade.duration = 0.2
        label.add(fade, forKey: "parc.peek.control.label")
    }

    func settleMotion() {
        animatesNextResize = false
        face.removeAllAnimations(); clip.removeAllAnimations(); label.removeAllAnimations()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshFace(animated: false)
    }

    override func layout() {
        super.layout()
        let previous = face.presentation()?.bounds ?? face.bounds
        CATransaction.begin(); CATransaction.setDisableActions(true)
        face.bounds = CGRect(origin: .zero, size: bounds.size)
        face.position = CGPoint(x: 0, y: bounds.midY)
        face.cornerRadius = bounds.height / 2
        clip.bounds = face.bounds
        clip.position = CGPoint(x: 0, y: bounds.height / 2)
        clip.cornerRadius = face.cornerRadius
        let glyphCenterX = bounds.width <= Self.diameter ? bounds.width / 2 : Self.leadingInset + Self.glyphBox / 2
        glyph.position = CGPoint(x: glyphCenterX, y: bounds.height / 2)
        let labelX = Self.leadingInset + Self.glyphBox + 1 + Self.labelSpacing
        let labelHeight = ceil(Self.labelFont.ascender - Self.labelFont.descender + Self.labelFont.leading)
        label.frame = CGRect(x: labelX, y: ((bounds.height - labelHeight) / 2).rounded(),
                             width: max(0, bounds.width - labelX - Self.trailingInset), height: labelHeight)
        CATransaction.commit()
        guard animatesNextResize, previous.size != face.bounds.size else { return }
        animatesNextResize = false
        let spring = Self.spring(keyPath: "bounds", response: 0.25, damping: 0.8)
        spring.fromValue = NSValue(rect: previous); spring.toValue = NSValue(rect: face.bounds)
        face.add(spring, forKey: "parc.peek.control.width")
        clip.add(spring, forKey: "parc.peek.control.width")
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        refreshContent()
    }

    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                      owner: self, userInfo: nil)
        addTrackingArea(tracking); hoverTracking = tracking
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) {
        setHovered(isEnabled && isTopmost(atWindowPoint: event.locationInWindow)); super.mouseEntered(with: event)
    }
    override func mouseMoved(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { super.mouseMoved(with: event); return }
        setHovered(isEnabled && isTopmost(atWindowPoint: event.locationInWindow))
    }
    override func mouseExited(with event: NSEvent) { setHovered(false); super.mouseExited(with: event) }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { hovered = false; pressed = false; settleMotion() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        guard pressed != flag else { return }
        pressed = flag
        refreshFace(animated: true, response: 0.28, damping: 0.63)
    }

    private func setHovered(_ value: Bool) {
        guard hovered != value else { return }
        hovered = value
        refreshFace(animated: true, response: 0.15, damping: 0.95)
    }

    private func refreshContent() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        CATransaction.begin(); CATransaction.setDisableActions(true)
        face.backgroundColor = colors.fill.cgColor
        if let image = Self.glyphImage(symbol, color: colors.accent) {
            glyph.contents = image.layerContents(forContentsScale: scale)
            glyph.contentsScale = image.recommendedLayerContentsScale(scale)
            glyph.bounds = CGRect(origin: .zero, size: image.size)
        } else {
            glyph.contents = nil
        }
        label.contentsScale = scale
        if let text {
            label.string = NSAttributedString(string: text, attributes: [.font: Self.labelFont, .foregroundColor: colors.accent])
        }
        label.opacity = text == nil ? 0 : 1
        CATransaction.commit()
    }

    private func refreshFace(animated: Bool, response: CGFloat = 0.15, damping: CGFloat = 0.95) {
        let up: CGFloat = face.contentsAreFlipped() ? -1 : 1
        let lift = hovered ? up : 0
        var transform = CATransform3DMakeTranslation(pressed ? bounds.width * 0.025 : 0, lift, 0)
        if pressed { transform = CATransform3DScale(transform, 0.95, 0.95, 1) }
        let previous = face.presentation()?.transform ?? face.transform
        CATransaction.begin(); CATransaction.setDisableActions(true)
        face.opacity = isEnabled ? 1 : 0.45
        face.shadowOpacity = hovered ? 0.3 : 0.2
        face.shadowRadius = hovered && !pressed ? 6 : 4
        face.shadowOffset = CGSize(width: 0, height: -up)
        face.transform = transform
        CATransaction.commit()
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              !CATransform3DEqualToTransform(previous, transform) else {
            face.removeAnimation(forKey: "parc.peek.control.motion"); return
        }
        let spring = Self.spring(keyPath: "transform", response: response, damping: damping)
        spring.fromValue = NSValue(caTransform3D: previous); spring.toValue = NSValue(caTransform3D: transform)
        face.add(spring, forKey: "parc.peek.control.motion")
    }

    private static func spring(keyPath: String, response: CGFloat, damping: CGFloat) -> CASpringAnimation {
        let spring = CASpringAnimation(keyPath: keyPath)
        let frequency = 2 * Double.pi / Double(response)
        spring.mass = 1; spring.stiffness = frequency * frequency
        spring.damping = 2 * Double(damping) * frequency
        spring.duration = spring.settlingDuration
        return spring
    }

    private static func glyphImage(_ symbol: String, color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        guard let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        return NSImage(size: symbolImage.size, flipped: false) { rect in
            symbolImage.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
