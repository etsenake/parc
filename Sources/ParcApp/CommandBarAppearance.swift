import AppKit
import SwiftUI

/// The command bar's colours, shared by `CommandBar`, `CommandResultRowView`
///
/// theme's semantic palette and every other colour from the CommandBar asset
///
/// resolves light or dark by the drawing appearance.
struct CommandBarPalette {
    ///
    /// inline bar with no query or results. The centred bar, and any bar with
    ///
    ///
    static func panelAppearance(inlineEmpty: Bool, space: NSAppearance?, window: NSAppearance?) -> NSAppearance? {
        inlineEmpty ? space ?? window : window
    }
    /// `CommandBarSuggestionRowView.Theme.selectedColor`: the window theme's
    ///
    ///
    ///
    let selected: NSColor
    /// The field's icon tint: the palette's `maxContrastColor`
    ///
    let inputIcon: NSColor
    /// `CustomSelectionColorTextField.selectionColor`, the background of
    ///
    let inputSelection: NSColor
    /// The field's text keeps the PopoverInputText asset it starts with
    ///
    var inputText: NSColor { Self.popoverInputText }
    ///
    /// colour replaces it.
    var scopePill: NSColor { selected }

    init(theme: SpaceTheme) {
        let theme = theme.isValid && theme.primaryColor != nil ? theme : Self.neutralTheme
        let light = ThemeChromePalette(theme: theme, isDark: false)
        let dark = ThemeChromePalette(theme: theme, isDark: true)
        selected = Self.either(light.focus, dark.focus)
        inputIcon = Self.either(light.maxContrastColor, dark.maxContrastColor)
        inputSelection = Self.either(light.subtitle, dark.subtitle)
    }

    ///
    /// without a colour was not recovered. Parc's colourless palette is a
    /// system fallback whose focus is the accent; instead, a Space without a
    ///
    /// selected rows stay grey with readable white text (inferred).
    static let neutralTheme = SpaceTheme.singleColor(ThemeColor(red: 0.2, green: 0.2, blue: 0.2, colorSpace: .sRGB)!)
    static let colourless = CommandBarPalette(theme: SpaceTheme())

    static func either(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
    }
    private static func ink(_ alpha: CGFloat, dark darkAlpha: CGFloat? = nil) -> NSColor {
        either(NSColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha),
               NSColor(srgbRed: 1, green: 1, blue: 1, alpha: darkAlpha ?? alpha))
    }
    ///
    static let popoverInputText = either(NSColor(displayP3Red: 0.055, green: 0.059, blue: 0.063, alpha: 0.8),
                                         NSColor(displayP3Red: 0.98, green: 0.984, blue: 1, alpha: 0.9))
    /// `CommandBarSuggestionRowView.Theme.hoveredColor`.
    static let rowHover = ink(0.05)
    static let textPrimary = ink(0.8)
    static let textSecondary = ink(0.33)
    static let accessoryBackground = ink(0.05)
    static let accessoryForeground = ink(0.5, dark: 0.66)
    /// CommandBarHairlineDividerColor.
    static let hairline = ink(0.1)
    ///
    ///
    /// subtitle white at 0.5, and its icon tile and keycap white with the
    /// glyph in the selected colour.
    static let selectedText = NSColor.white
    static let selectedSecondaryText = NSColor.white.withAlphaComponent(0.5)
    static let selectedTile = NSColor.white
}

/// The command bar's type. Everything but the centred field is FontSet
///
///
///
enum CommandBarTypography {
    ///
    static let field = NSFont.systemFont(ofSize: 18, weight: .medium)
    ///
    static let label = NSFont.systemFont(ofSize: 13, weight: .medium)
}

extension NSTextField {
    /// The label's single-line width, its 2-point text padding included, which
    /// its intrinsic (alignment) width leaves out; independent of its frame.
    var singleLineWidth: CGFloat {
        cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: 20)).width.rounded(.up) ?? 0
    }
}

///
///
/// CommandBarHairlineDividerColor, shown in the empty state too.
final class CommandBarHairline: NSView {
    override var wantsUpdateLayer: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    static func height(in window: NSWindow?) -> CGFloat { 1 / max(1, window?.backingScaleFactor ?? 1) }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = CommandBarPalette.hairline.cgColor
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
}

///
///
/// bar. It ignores the mouse, so presses around the bar land on the page. It
/// is masked to outside the bar so the bar's material doesn't blur its own
/// shadow.
final class CommandBarShadowView: NSView {
    /// Room for the blur to fade out around the bar: measured offscreen, it
    /// still darkens a white page by 3–6 levels at 72 points; the 24-point
    /// offset adds to the bottom.
    static let margins = NSEdgeInsets(top: 96, left: 96, bottom: 120, right: 96)
    let shadowLayer = CALayer()
    private let outsideBar = CAShapeLayer()
    var cornerRadius: CGFloat = 12 { didSet { needsLayout = true } }
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = 0.5
        shadowLayer.shadowRadius = 48
        shadowLayer.shadowOffset = CGSize(width: 0, height: 24)
        outsideBar.fillRule = .evenOdd
        shadowLayer.mask = outsideBar
        layer?.addSublayer(shadowLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var barFrame: NSRect {
        let m = Self.margins
        return NSRect(x: m.left, y: m.top, width: max(0, bounds.width - m.left - m.right),
                      height: max(0, bounds.height - m.top - m.bottom))
    }
    var barPath: CGPath {
        CGPath(roundedRect: barFrame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        // A flipped view's layer is y-down, so a positive offset falls below.
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = barPath
        outsideBar.frame = bounds
        let path = CGMutablePath()
        path.addRect(bounds); path.addPath(barPath)
        outsideBar.path = path
        CATransaction.commit()
    }
    /// The bar's centre relative to `shadowLayer`'s anchor, its own centre.
    var barCentreOffset: CGPoint { CGPoint(x: barFrame.midX - bounds.midX, y: barFrame.midY - bounds.midY) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

///
///
///
/// its settling duration.
enum CommandBarBounce {
    static let key = "arc_commandBarBounce"
    static let scale: CGFloat = 0.95
    static let dampingRatio: CGFloat = 0.9
    static let response: CGFloat = 0.7

    /// `centre` is the point to scale about, relative to the layer's anchor
    ///
    /// middle instead, which AppKit's own layers don't allow, so the from-value
    /// carries the matching translation.
    static func animation(about centre: CGPoint) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: "transform")
        animation.mass = 1
        animation.stiffness = pow(2 * .pi / response, 2)
        animation.damping = 4 * .pi * dampingRatio / response
        animation.duration = animation.settlingDuration
        let from = CATransform3DScale(CATransform3DMakeTranslation((1 - scale) * centre.x, (1 - scale) * centre.y, 0),
                                      scale, scale, 1)
        animation.fromValue = NSValue(caTransform3D: from)
        animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        return animation
    }
    static func play(on layer: CALayer?, about centre: CGPoint? = nil) {
        guard let layer else { return }
        let bounds = layer.bounds, anchor = layer.anchorPoint
        let point = centre ?? CGPoint(x: (0.5 - anchor.x) * bounds.width, y: (0.5 - anchor.y) * bounds.height)
        layer.removeAnimation(forKey: key)
        layer.add(animation(about: point), forKey: key)
    }
}

///
/// the scope's colour in the bar's continuous rounded rectangle, blurred and
/// faded together. On appear its blur radius goes from 0 to 150 and its opacity
///
/// under the bar view; Parc's sits under the bar's shadow with `padding` for
/// its blur: two blur radii, past which it has faded to nothing.
struct CommandBarSplashView: View {
    static let blurRadius: CGFloat = 150
    static let padding = 2 * blurRadius
    static let duration: TimeInterval = 1.2
    let color: NSColor
    let cornerRadius: CGFloat
    let margin: CGFloat
    @State private var blurRadius: CGFloat = 0
    @State private var opacity: Double = 1

    var body: some View {
        Color(nsColor: color)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .blur(radius: blurRadius)
            .opacity(opacity)
            .animation(.easeOut(duration: Self.duration), value: opacity)
            .onAppear { blurRadius = Self.blurRadius; opacity = 0 }
            .padding(margin)
    }
}
