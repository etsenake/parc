import AppKit
import SwiftUI

///
///
/// pressed, then hovered. The entry is never disabled.
struct TranslucentButtonColors: Equatable {
    var background: NSColor
    var hoveredBackground: NSColor
    var pressedBackground: NSColor
    var foreground: NSColor
    var pressedForeground: NSColor
    var disabledBackground: NSColor
    var disabledForeground: NSColor

    ///
    /// GrayA4, GrayA5, GrayA11, GrayA12, clear, GrayA8. The named colours are
    ///
    /// alphas in Aqua, white in Dark Aqua. Not the window theme palette.
    static func standard(dark: Bool) -> TranslucentButtonColors {
        func gray(_ aqua: CGFloat, _ darkAqua: CGFloat) -> NSColor {
            dark ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: darkAqua) : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: aqua)
        }
        return TranslucentButtonColors(background: .clear, hoveredBackground: gray(0.071, 0.077),
                                       pressedBackground: gray(0.090, 0.103), foreground: gray(0.565, 0.592),
                                       pressedForeground: gray(0.910, 0.923), disabledBackground: .clear,
                                       disabledForeground: gray(0.220, 0.249))
    }

    ///
    /// backgrounds and the palette's maxContrastColor for every foreground.
    static func bin(maxContrast: NSColor) -> TranslucentButtonColors {
        TranslucentButtonColors(background: .clear, hoveredBackground: .clear, pressedBackground: .clear,
                                foreground: maxContrast, pressedForeground: maxContrast,
                                disabledBackground: .clear, disabledForeground: maxContrast)
    }

    func background(hovered: Bool, pressed: Bool, enabled: Bool) -> NSColor {
        !enabled ? disabledBackground : pressed ? pressedBackground : hovered ? hoveredBackground : background
    }
    func foreground(pressed: Bool, enabled: Bool) -> NSColor {
        !enabled ? disabledForeground : pressed ? pressedForeground : foreground
    }
}

///
/// TranslucentButtons, drawn by their AppKit owner: the default properties
/// (`TranslucentButtonColors.standard`, resolved by the view's appearance), a
/// background over the whole frame clipped to 6-point corners, and
/// `.scaleEffect(isPressed ? 0.95 : 1)`. Press changes ride
/// spring(response: 0.3, dampingFraction: 0.6) and hover changes
/// easeIn(duration: 0.1). The style also publishes `isPressed` to the label
///
/// spring, to the arrow and reload glyphs.
@MainActor final class TranslucentButtonFace {
    static let cornerRadius: CGFloat = 6
    static let pressedScale: CGFloat = 0.95
    static let pressResponse = 0.3, pressDamping = 0.6
    static let hoverDuration: CFTimeInterval = 0.1

    private weak var view: NSView?
    private let frames = ViewDisplayFrameDriver()
    private var hovered = false
    private var pressed = false
    /// 0 at rest, 1 hovered.
    private var hoverProgress: CGFloat = 0
    /// 0 released, 1 pressed; the spring may overshoot either end.
    private(set) var pressProgress: CGFloat = 0
    private var hoverFrom: CGFloat = 0, hoverStart: CFTimeInterval = 0
    private var pressFrom: CGFloat = 0, pressStart: CFTimeInterval = 0

    init(view: NSView) { self.view = view }

    func setHovered(_ hovered: Bool, animated: Bool = true) {
        guard hovered != self.hovered else { return }
        self.hovered = hovered
        hoverFrom = hoverProgress; hoverStart = CACurrentMediaTime()
        if !animate(animated) { hoverProgress = hovered ? 1 : 0 }
        view?.needsDisplay = true
    }

    func setPressed(_ pressed: Bool, animated: Bool = true) {
        guard pressed != self.pressed else { return }
        self.pressed = pressed
        pressFrom = pressProgress; pressStart = CACurrentMediaTime()
        if !animate(animated) { pressProgress = pressed ? 1 : 0 }
        view?.needsDisplay = true
    }

    func stop() {
        frames.stop()
        hoverProgress = hovered ? 1 : 0; pressProgress = pressed ? 1 : 0
    }

    func colors(for view: NSView) -> TranslucentButtonColors {
        .standard(dark: view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }

    /// The pressed foreground blends in on the press spring; disabled wins.
    func foreground(enabled: Bool, in view: NSView) -> NSColor {
        let colors = colors(for: view)
        guard enabled else { return colors.disabledForeground }
        return Self.blend(colors.foreground, colors.pressedForeground, pressProgress)
    }

    private var plate: (bounds: NSRect, path: CGPath)?
    /// `clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))`.
    private func platePath(_ bounds: NSRect) -> CGPath {
        if let plate, plate.bounds == bounds { return plate.path }
        let path = Path(roundedRect: bounds, cornerRadius: Self.cornerRadius, style: .continuous).cgPath
        plate = (bounds, path)
        return path
    }

    /// Fills the background, then draws the glyph inside the press scale.
    func draw(in bounds: NSRect, enabled: Bool, view: NSView, glyph: (NSColor) -> Void) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let colors = colors(for: view)
        NSGraphicsContext.saveGraphicsState()
        let scale = 1 - (1 - Self.pressedScale) * pressProgress
        if abs(scale - 1) > 0.0001 {
            let transform = NSAffineTransform()
            transform.translateX(by: bounds.midX, yBy: bounds.midY)
            transform.scale(by: scale)
            transform.translateX(by: -bounds.midX, yBy: -bounds.midY)
            transform.concat()
        }
        let shape = platePath(bounds)
        if enabled {
            let hoveredFill = Self.blend(colors.background, colors.hoveredBackground, hoverProgress)
            let fill = Self.blend(hoveredFill, colors.pressedBackground, pressProgress)
            if fill.alphaComponent > 0.001 { fill.setFill(); context.addPath(shape); context.fillPath() }
        }
        context.addPath(shape); context.clip()
        glyph(foreground(enabled: enabled, in: view))
        NSGraphicsContext.restoreGraphicsState()
    }

    private var tintedGlyph: (image: NSImage, color: NSColor, result: NSImage)?
    /// A template glyph centred in the bounds, shifted horizontally by `shiftX`.
    /// The palette's states differ only in alpha, so the cached image holds the
    /// opaque tint and the alpha is applied as the drawing fraction.
    func drawGlyph(_ image: NSImage, tint: NSColor, in bounds: NSRect, shiftX: CGFloat = 0, view: NSView) {
        let opaque = tint.withAlphaComponent(1)
        if tintedGlyph?.image !== image || tintedGlyph?.color != opaque {
            tintedGlyph = (image, opaque, Self.tinted(image, opaque))
        }
        guard let tinted = tintedGlyph?.result else { return }
        let rect = NSRect(x: bounds.midX - image.size.width / 2, y: bounds.midY - image.size.height / 2,
                          width: image.size.width, height: image.size.height)
        tinted.draw(in: view.backingAlignedRect(rect, options: .alignAllEdgesNearest).offsetBy(dx: shiftX, dy: 0),
                    from: .zero, operation: .sourceOver, fraction: tint.alphaComponent, respectFlipped: true, hints: nil)
    }

    static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect); color.set(); rect.fill(using: .sourceIn); return true
        }
    }

    /// Unclamped as SwiftUI's spring is, with the alpha kept in range.
    static func blend(_ from: NSColor, _ to: NSColor, _ progress: CGFloat) -> NSColor {
        guard let a = from.usingColorSpace(.sRGB), let b = to.usingColorSpace(.sRGB) else { return progress < 0.5 ? from : to }
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * progress }
        let alpha = min(1, max(0, mix(a.alphaComponent, b.alphaComponent)))
        // A clear end takes the other end's colour, as premultiplied interpolation does.
        let red = a.alphaComponent == 0 ? b.redComponent : b.alphaComponent == 0 ? a.redComponent : mix(a.redComponent, b.redComponent)
        let green = a.alphaComponent == 0 ? b.greenComponent : b.alphaComponent == 0 ? a.greenComponent : mix(a.greenComponent, b.greenComponent)
        let blue = a.alphaComponent == 0 ? b.blueComponent : b.alphaComponent == 0 ? a.blueComponent : mix(a.blueComponent, b.blueComponent)
        return NSColor(srgbRed: min(1, max(0, red)), green: min(1, max(0, green)), blue: min(1, max(0, blue)), alpha: alpha)
    }

    /// CAMediaTimingFunction(name: .easeIn): cubic Bézier (0.42, 0) (1, 1).
    static func easeIn(_ x: Double) -> CGFloat {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        func bezier(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
            3 * (1 - t) * (1 - t) * t * p1 + 3 * (1 - t) * t * t * p2 + t * t * t
        }
        var low = 0.0, high = 1.0, t = x
        for _ in 0..<40 {
            t = (low + high) / 2
            if bezier(t, 0.42, 1) < x { low = t } else { high = t }
        }
        return CGFloat(bezier(t, 0, 1))
    }

    private func animate(_ animated: Bool) -> Bool {
        guard animated, let view, view.window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return false }
        frames.start(in: view) { [weak self] in self?.tick() ?? false }
        return true
    }

    private func tick() -> Bool {
        let now = CACurrentMediaTime()
        var keep = false
        let hoverTarget: CGFloat = hovered ? 1 : 0
        if hoverProgress != hoverTarget {
            let t = (now - hoverStart) / Self.hoverDuration
            if t >= 1 { hoverProgress = hoverTarget } else {
                hoverProgress = hoverFrom + (hoverTarget - hoverFrom) * Self.easeIn(t); keep = true
            }
        }
        let pressTarget: CGFloat = pressed ? 1 : 0
        if pressProgress != pressTarget {
            let elapsed = now - pressStart
            if elapsed >= ReloadGlyph.settlingDuration(response: Self.pressResponse, damping: Self.pressDamping) {
                pressProgress = pressTarget
            } else {
                let unit = ReloadGlyph.unitSpring(elapsed, response: Self.pressResponse, damping: Self.pressDamping)
                pressProgress = pressFrom + (pressTarget - pressFrom) * unit; keep = true
            }
        }
        view?.needsDisplay = true
        return keep
    }
}
