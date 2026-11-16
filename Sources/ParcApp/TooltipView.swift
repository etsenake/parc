import AppKit
import SwiftUI

@MainActor final class TooltipView: NSView {
    struct Content: Equatable {
        var label: String
        var keycaps: [TooltipKeycap]
        var corners: TooltipCorners
        var palette: TooltipColorPalette
        var maxWidth: CGFloat
        var style: TooltipConfiguration.Style = .standard
    }
    struct Layout: Equatable {
        var size: CGSize
        var pill: CGRect
        var label: CGRect
        var keycaps: [CGRect]
        var subtitle: CGRect? = nil
    }

    static let labelFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let glyphFont = NSFont.systemFont(ofSize: 10, weight: .bold)
    static let minHeight: CGFloat = 28
    static let horizontalPadding: CGFloat = 10
    static let shortcutSpacing: CGFloat = 6
    static let backgroundOverhang: CGFloat = 7
    static let borderWidth: CGFloat = 1
    static let darkBorder = NSColor.white.withAlphaComponent(0.1)

    enum Label {
        static let subtitleFont = NSFont.systemFont(ofSize: 11)
        static let lineLimit = 4
        static let subtitleOpacity: CGFloat = 0.66
        static func lineHeight(_ font: NSFont) -> CGFloat { ceil(font.ascender) + ceil(-font.descender) }
    }

    enum Keycap {
        static let spacing: CGFloat = 3
        static let minSide: CGFloat = 19
        static let glyphPadding: CGFloat = 2
        static let baseRadius: CGFloat = 4
        static let faceRadius: CGFloat = 3
        static let faceInset: CGFloat = 1
        static let faceBottomInset: CGFloat = 2.5
        static let pressedFaceBottomInset: CGFloat = 1
        static let pressDuration: CFTimeInterval = 0.12
        static let shade = NSColor.black.withAlphaComponent(0.1)
    }

    var content: Content {
        didSet {
            guard content != oldValue else { return }
            var repainted = oldValue
            repainted.palette = content.palette
            if repainted != content {
                contentLayout = Self.layout(for: content, scale: backingScale)
                pressProgress = content.keycaps.map { _ in 0 }; pressTargets = pressProgress; frames.stop()
            }
            needsDisplay = true
        }
    }
    var backingScale: CGFloat = 2 {
        didSet {
            guard backingScale != oldValue else { return }
            contentLayout = Self.layout(for: content, scale: backingScale); needsDisplay = true
        }
    }
    static func margin(scale: CGFloat) -> CGFloat { ceil(TooltipShadow.windowMargin * scale - 0.001) / scale }
    private(set) var contentLayout: Layout
    private var pressProgress: [CGFloat] = []
    private var pressTargets: [CGFloat] = []
    private var pressFrom: [CGFloat] = []
    private var pressStart: [CFTimeInterval] = []
    private let frames = ViewDisplayFrameDriver()

    init(content: Content) {
        self.content = content
        contentLayout = Self.layout(for: content, scale: 2)
        pressProgress = content.keycaps.map { _ in 0 }; pressTargets = pressProgress
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let scale = window?.backingScaleFactor { backingScale = scale }
    }

    func setPressed(modifiers: NSEvent.ModifierFlags, characters: String?) {
        let targets = content.keycaps.map { $0.isPressed(modifiers: modifiers, characters: characters) ? CGFloat(1) : 0 }
        guard targets != pressTargets else { return }
        let now = CACurrentMediaTime()
        pressFrom = pressProgress; pressStart = targets.map { _ in now }; pressTargets = targets
        guard window != nil else { pressProgress = targets; needsDisplay = true; return }
        frames.start(in: self) { [weak self] in self?.tick() ?? false }
    }

    private func tick() -> Bool {
        let now = CACurrentMediaTime()
        var running = false
        for index in pressProgress.indices where pressProgress[index] != pressTargets[index] {
            let t = (now - pressStart[index]) / Keycap.pressDuration
            if t >= 1 { pressProgress[index] = pressTargets[index]; continue }
            pressProgress[index] = pressFrom[index] + (pressTargets[index] - pressFrom[index]) * Self.easeOut(t)
            running = true
        }
        needsDisplay = true
        return running
    }

    static func easeOut(_ x: Double) -> CGFloat {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        func bezier(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
            3 * (1 - t) * (1 - t) * t * p1 + 3 * (1 - t) * t * t * p2 + t * t * t
        }
        var low = 0.0, high = 1.0, t = x
        for _ in 0..<40 {
            t = (low + high) / 2
            if bezier(t, 0, 0.58) < x { low = t } else { high = t }
        }
        return CGFloat(bezier(t, 0, 1))
    }

    static func labelString(_ label: String, color: NSColor = .black) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: label, attributes: [.font: labelFont, .foregroundColor: color, .paragraphStyle: paragraph])
    }
    static func glyphString(_ glyph: String, color: NSColor = .black) -> NSAttributedString {
        NSAttributedString(string: glyph, attributes: [.font: glyphFont, .foregroundColor: color])
    }
    static func lineString(_ text: String, font: NSFont, color: NSColor = .black) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.minimumLineHeight = Label.lineHeight(font); paragraph.maximumLineHeight = Label.lineHeight(font)
        return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    static func layout(for content: Content, scale: CGFloat) -> Layout {
        func pixel(_ value: CGFloat) -> CGFloat { ceil(value * scale - 0.001) / scale }
        func aligned(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let widths = content.keycaps.map {
            max(Keycap.minSide, pixel(glyphString($0.glyph).size().width) + 2 * (Keycap.glyphPadding + Keycap.faceInset))
        }
        let keycapsWidth = widths.reduce(0, +) + Keycap.spacing * CGFloat(max(0, widths.count - 1))
        let shortcutWidth = widths.isEmpty ? 0 : shortcutSpacing + keycapsWidth
        let available = max(0, content.maxWidth - 2 * horizontalPadding - shortcutWidth)
        func measure(_ text: NSAttributedString, lines: CGFloat? = nil, reserved: CGFloat = 0) -> (size: CGSize, wraps: Bool) {
            let room = max(0, available - reserved)
            let natural = text.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude), options: options).size
            let wraps = pixel(natural.width) > room
            let measured = wraps ? text.boundingRect(with: CGSize(width: room, height: .greatestFiniteMagnitude), options: options).size : natural
            return (CGSize(width: min(room, pixel(measured.width)), height: pixel(min(measured.height, lines ?? .greatestFiniteMagnitude))), wraps)
        }
        let label: CGSize, subtitle: CGSize?, wraps: Bool
        switch content.style {
        case .standard:
            (label, wraps) = measure(labelString(content.label))
            subtitle = nil
        case .label(let text):
            let title = measure(lineString(content.label, font: labelFont), lines: CGFloat(Label.lineLimit) * Label.lineHeight(labelFont))
            let below = text.map { measure(lineString($0, font: Label.subtitleFont)) }
            label = title.size; subtitle = below?.size
            wraps = title.wraps || below?.wraps == true
        }
        let textWidth = max(label.width, subtitle?.width ?? 0), textHeight = label.height + (subtitle?.height ?? 0)
        let height = max(minHeight, textHeight, widths.isEmpty ? 0 : Keycap.minSide)
        let pillWidth = 2 * horizontalPadding + textWidth + shortcutWidth
        var x = horizontalPadding + textWidth + shortcutSpacing
        let keycaps = widths.map { width -> CGRect in
            defer { x += width + Keycap.spacing }
            return CGRect(x: x, y: aligned((height - Keycap.minSide) / 2), width: width, height: Keycap.minSide)
        }
        let top = aligned((height - textHeight) / 2)
        return Layout(size: CGSize(width: wraps ? content.maxWidth : pillWidth, height: height),
                      pill: CGRect(x: 0, y: 0, width: pillWidth, height: height),
                      label: CGRect(x: horizontalPadding, y: top, width: label.width, height: label.height),
                      keycaps: keycaps,
                      subtitle: subtitle.map { CGRect(x: horizontalPadding, y: top + label.height, width: $0.width, height: $0.height) })
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let palette = content.palette, layout = contentLayout
        let margin = Self.margin(scale: backingScale)
        var background = layout.pill.offsetBy(dx: margin, dy: margin)
        if background.height > Self.minHeight { background = background.insetBy(dx: 0, dy: -Self.backgroundOverhang) }
        let shape = content.corners.path(in: background)

        let device = context.userSpaceToDeviceSpaceTransform
        let linear = CGAffineTransform(a: device.a, b: device.b, c: device.c, d: device.d, tx: 0, ty: 0)
        let scale = hypot(device.a, device.b)
        context.saveGState()
        for shadow in TooltipShadow.standard.reversed() {
            context.setShadow(offset: shadow.offset.applying(linear), blur: 2 * shadow.radius * scale,
                              color: NSColor.black.withAlphaComponent(shadow.opacity).cgColor)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        context.addPath(shape)
        context.setFillColor(palette.background.resolved(dark: dark).cgColor)
        context.fillPath()
        for _ in TooltipShadow.standard { context.endTransparencyLayer() }
        context.restoreGState()
        if dark {
            context.addPath(shape)
            context.setStrokeColor(Self.darkBorder.cgColor); context.setLineWidth(Self.borderWidth)
            context.strokePath()
        }

        let origin = CGPoint(x: margin, y: margin)
        let title = palette.title.resolved(dark: dark)
        switch content.style {
        case .standard:
            Self.labelString(content.label, color: title)
                .draw(with: layout.label.offsetBy(dx: origin.x, dy: origin.y), options: [.usesLineFragmentOrigin, .usesFontLeading])
        case .label(let subtitle):
            Self.lineString(content.label, font: Self.labelFont, color: title)
                .draw(with: layout.label.offsetBy(dx: origin.x, dy: origin.y),
                      options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
            if let subtitle, let frame = layout.subtitle {
                Self.lineString(subtitle, font: Label.subtitleFont, color: title.withAlphaComponent(title.alphaComponent * Label.subtitleOpacity))
                    .draw(with: frame.offsetBy(dx: origin.x, dy: origin.y), options: [.usesLineFragmentOrigin, .usesFontLeading])
            }
        }
        for (index, frame) in layout.keycaps.enumerated() {
            drawKeycap(content.keycaps[index], in: frame.offsetBy(dx: origin.x, dy: origin.y),
                       pressed: pressProgress.indices.contains(index) ? pressProgress[index] : 0,
                       palette: palette, dark: dark, context: context)
        }
    }

    private func drawKeycap(_ keycap: TooltipKeycap, in frame: CGRect, pressed: CGFloat,
                            palette: TooltipColorPalette, dark: Bool, context: CGContext) {
        context.saveGState()
        context.addPath(Path(roundedRect: frame, cornerRadius: Keycap.baseRadius, style: .continuous).cgPath)
        context.clip()
        context.setFillColor(palette.keyBackground.resolved(dark: dark).cgColor)
        context.fill(frame)
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                     colors: [NSColor.clear.cgColor, Keycap.shade.cgColor] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: frame.midX, y: frame.minY),
                                       end: CGPoint(x: frame.midX, y: frame.maxY), options: [])
        }
        context.restoreGState()

        let bottom = Keycap.faceBottomInset + (Keycap.pressedFaceBottomInset - Keycap.faceBottomInset) * pressed
        let face = CGRect(x: frame.minX + Keycap.faceInset, y: frame.minY + Keycap.faceInset,
                          width: frame.width - 2 * Keycap.faceInset, height: frame.height - Keycap.faceInset - bottom)
        context.addPath(Path(roundedRect: face, cornerRadius: Keycap.faceRadius, style: .continuous).cgPath)
        context.setFillColor(palette.keyForeground.resolved(dark: dark).cgColor)
        context.fillPath()

        let glyph = Self.glyphString(keycap.glyph, color: palette.keyTitle.resolved(dark: dark))
        let size = glyph.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                                      options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        func aligned(_ value: CGFloat) -> CGFloat { (value * backingScale).rounded() / backingScale }
        glyph.draw(with: CGRect(x: aligned(face.midX - size.width / 2), y: aligned(face.midY - size.height / 2),
                                width: size.width, height: size.height),
                   options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}
