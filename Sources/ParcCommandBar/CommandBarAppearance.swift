import AppKit
import ParcCore
import SwiftUI
import ParcKit

struct CommandBarPalette {
    static func panelAppearance(inlineEmpty: Bool, resident: Bool = false, space: NSAppearance?, window: NSAppearance?) -> NSAppearance? {
        inlineEmpty || resident ? space ?? window : window
    }
    let selected: NSColor
    let inputIcon: NSColor
    let inputSelection: NSColor
    var inputText: NSColor { Self.popoverInputText }
    var scopePill: NSColor { selected }

    init(theme: SpaceTheme) {
        let theme = theme.isValid && theme.primaryColor != nil ? theme : Self.neutralTheme
        let light = ThemeChromePalette(theme: theme, isDark: false)
        let dark = ThemeChromePalette(theme: theme, isDark: true)
        selected = Self.either(light.focus, dark.focus)
        inputIcon = Self.either(light.maxContrastColor, dark.maxContrastColor)
        inputSelection = Self.either(light.subtitle, dark.subtitle)
    }

    static let neutralTheme = SpaceTheme.singleColor(ThemeColor(red: 0.2, green: 0.2, blue: 0.2, colorSpace: .sRGB)!)
    static let colourless = CommandBarPalette(theme: SpaceTheme())

    static func either(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
    }
    private static func ink(_ alpha: CGFloat, dark darkAlpha: CGFloat? = nil) -> NSColor {
        either(NSColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha),
               NSColor(srgbRed: 1, green: 1, blue: 1, alpha: darkAlpha ?? alpha))
    }
    static let popoverInputText = either(NSColor(displayP3Red: 0.055, green: 0.059, blue: 0.063, alpha: 0.8),
                                         NSColor(displayP3Red: 0.98, green: 0.984, blue: 1, alpha: 0.9))
    static let rowHover = ink(0.05)
    static let textPrimary = ink(0.8)
    static let textSecondary = ink(0.33)
    static let textPrimaryMatch = ink(1)
    static let textSecondaryMatch = ink(0.6)
    static let accessoryBackground = ink(0.05)
    static let accessoryForeground = ink(0.5, dark: 0.66)
    static let hairline = ink(0.1)
    static let selectedText = NSColor.white
    static let selectedSecondaryText = NSColor.white.withAlphaComponent(0.5)
    static let selectedSecondaryMatchText = NSColor.white.withAlphaComponent(0.8)
    static let selectedTile = NSColor.white
}

enum CommandBarTypography {
    static let field = NSFont.systemFont(ofSize: 18, weight: .medium)
    static let label = NSFont.systemFont(ofSize: 13, weight: .medium)
}

extension NSTextField {
    var singleLineWidth: CGFloat {
        cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: 20)).width.rounded(.up) ?? 0
    }
}

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

final class CommandBarShadowView: NSView {
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
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = barPath
        outsideBar.frame = bounds
        let path = CGMutablePath()
        path.addRect(bounds); path.addPath(barPath)
        outsideBar.path = path
        CATransaction.commit()
    }
    var barCentreOffset: CGPoint { CGPoint(x: barFrame.midX - bounds.midX, y: barFrame.midY - bounds.midY) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

enum CommandBarBounce {
    static let key = "parc.commandBarBounce"
    static let scale: CGFloat = 0.95
    static let dampingRatio: CGFloat = 0.9
    static let response: CGFloat = 0.7

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
