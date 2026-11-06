import AppKit
import SwiftUI

///
///
/// the tooltip window; the tooltip sits `margin(scale:)` inside so its
/// shadows are not clipped.
@MainActor final class TooltipView: NSView {
    struct Content: Equatable {
        var label: String
        var keycaps: [TooltipKeycap]
        var corners: TooltipCorners
        var palette: TooltipColorPalette
        var maxWidth: CGFloat
        var style: TooltipConfiguration.Style = .standard
    }
    /// Frames relative to the tooltip's own origin. `size` is the frame placed
    /// against the anchor; a wrapped label's `pill` can be narrower, leading.
    struct Layout: Equatable {
        var size: CGSize
        var pill: CGRect
        var label: CGRect
        var keycaps: [CGRect]
        /// The `.label` style's subtitle, below the label.
        var subtitle: CGRect? = nil
        /// The `.dockItem` style's Profile capsule, after the label.
        var profile: CGRect? = nil
    }

    ///
    static let labelFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    ///
    static let glyphFont = NSFont.systemFont(ofSize: 10, weight: .bold)
    static let minHeight: CGFloat = 28
    static let horizontalPadding: CGFloat = 10
    static let shortcutSpacing: CGFloat = 6
    /// A taller tooltip's background reaches this far above and below it.
    static let backgroundOverhang: CGFloat = 7
    static let borderWidth: CGFloat = 1
    static let darkBorder = NSColor.white.withAlphaComponent(0.1)

    ///
    /// spacing (0 between these texts) of the label, `lineLimit(4)`, over the
    ///
    ///
    /// descent: 15 and 14 points.
    enum Label {
        static let subtitleFont = NSFont.systemFont(ofSize: 11)
        static let lineLimit = 4
        static let subtitleOpacity: CGFloat = 0.66
        static func lineHeight(_ font: NSFont) -> CGFloat { ceil(font.ascender) + ceil(-font.descender) }
    }

    ///
    ///
    /// with the Space header's full-size geometry: 5 points leading, 6
    /// trailing and 4 above and below, a 20-point icon slot, 2 points, then
    /// the name in 11-point medium, in a capsule. The face colour fills it and
    ///
    /// pressed colours never apply under a tooltip, which takes no mouse.
    ///
    /// Like the header's indicator, the capsule is capped (at half the row's
    /// room) and a longer name truncates at its tail, so the title keeps room.
    enum Profile {
        static let spacing: CGFloat = 6
        static let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        static let leading: CGFloat = 5
        static let trailing: CGFloat = 6
        static let vertical: CGFloat = 4
        static let iconSlot: CGFloat = 20
        static let iconSpacing: CGFloat = 2
        static var icon: NSImage? {
            NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        }
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
            contentLayout = Self.layout(for: content, scale: backingScale)
            pressProgress = content.keycaps.map { _ in 0 }; pressTargets = pressProgress; frames.stop()
            needsDisplay = true
        }
    }
    /// The scale the layout is aligned to: the destination screen's before the
    /// window moves there, then the window's own.
    var backingScale: CGFloat = 2 {
        didSet {
            guard backingScale != oldValue else { return }
            contentLayout = Self.layout(for: content, scale: backingScale); needsDisplay = true
        }
    }
    /// `TooltipShadow.windowMargin` on a device pixel, so the pill's edges and
    /// text land on whole pixels at every scale.
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

    /// The shown keycaps follow the keys held while the tooltip is up; a face
    /// drops to its pressed inset on `.easeOut(duration: 0.12)`.
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

    /// CAMediaTimingFunction(name: .easeOut): cubic Bézier (0, 0) (0.58, 1).
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
    /// A `.label` style text on SwiftUI's line height.
    static func lineString(_ text: String, font: NSFont, color: NSColor = .black) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.minimumLineHeight = Label.lineHeight(font); paragraph.maximumLineHeight = Label.lineHeight(font)
        return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    /// `HStack(alignment: .center, spacing: 6) { label.frame(minHeight: 28); keycaps }`,
    /// padded 10 points either side, vertically fixed and at most `maxWidth`
    /// wide; the label wraps rather than exceed it.
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
        /// The text's size within `available` less `reserved`, and whether it wraps.
        func measure(_ text: NSAttributedString, lines: CGFloat? = nil, reserved: CGFloat = 0) -> (size: CGSize, wraps: Bool) {
            let room = max(0, available - reserved)
            let natural = text.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude), options: options).size
            let wraps = pixel(natural.width) > room
            let measured = wraps ? text.boundingRect(with: CGSize(width: room, height: .greatestFiniteMagnitude), options: options).size : natural
            return (CGSize(width: min(room, pixel(measured.width)), height: pixel(min(measured.height, lines ?? .greatestFiniteMagnitude))), wraps)
        }
        let label: CGSize, subtitle: CGSize?, wraps: Bool
        var profile: CGSize?
        switch content.style {
        case .standard:
            (label, wraps) = measure(labelString(content.label))
            subtitle = nil
        case .label(let text):
            let title = measure(lineString(content.label, font: labelFont), lines: CGFloat(Label.lineLimit) * Label.lineHeight(labelFont))
            let below = text.map { measure(lineString($0, font: Label.subtitleFont)) }
            label = title.size; subtitle = below?.size
            wraps = title.wraps || below?.wraps == true
        case .dockItem(let name):
            profile = name.map {
                let chrome = Profile.leading + Profile.iconSlot + Profile.iconSpacing + Profile.trailing
                let limit = floor((available - Profile.spacing) / 2 * scale) / scale
                return CGSize(width: max(chrome, min(chrome + pixel(profileString($0).size().width), limit)),
                              height: Label.lineHeight(Profile.font) + 2 * Profile.vertical)
            }
            (label, wraps) = measure(labelString(content.label), reserved: profile.map { Profile.spacing + $0.width } ?? 0)
            subtitle = nil
        }
        let textWidth = max(label.width, subtitle?.width ?? 0), textHeight = label.height + (subtitle?.height ?? 0)
        let profileWidth = profile.map { Profile.spacing + $0.width } ?? 0
        let height = max(minHeight, textHeight, profile?.height ?? 0, widths.isEmpty ? 0 : Keycap.minSide)
        let pillWidth = 2 * horizontalPadding + textWidth + profileWidth + shortcutWidth
        var x = horizontalPadding + textWidth + profileWidth + shortcutSpacing
        let keycaps = widths.map { width -> CGRect in
            defer { x += width + Keycap.spacing }
            return CGRect(x: x, y: aligned((height - Keycap.minSide) / 2), width: width, height: Keycap.minSide)
        }
        let top = aligned((height - textHeight) / 2)
        return Layout(size: CGSize(width: wraps ? content.maxWidth : pillWidth, height: height),
                      pill: CGRect(x: 0, y: 0, width: pillWidth, height: height),
                      label: CGRect(x: horizontalPadding, y: top, width: label.width, height: label.height),
                      keycaps: keycaps,
                      subtitle: subtitle.map { CGRect(x: horizontalPadding, y: top + label.height, width: $0.width, height: $0.height) },
                      profile: profile.map {
                          CGRect(x: horizontalPadding + textWidth + Profile.spacing, y: aligned((height - $0.height) / 2),
                                 width: $0.width, height: $0.height)
                      })
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let palette = content.palette, layout = contentLayout
        let margin = Self.margin(scale: backingScale)
        var background = layout.pill.offsetBy(dx: margin, dy: margin)
        if background.height > Self.minHeight { background = background.insetBy(dx: 0, dy: -Self.backgroundOverhang) }
        let shape = content.corners.path(in: background)

        // CGContext shadows ignore the CTM, so map SwiftUI's y-down offset and
        // radius (the blur's standard deviation; CG's blur is twice it) to
        // device space.
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
        case .dockItem(let profile):
            Self.labelString(content.label, color: title)
                .draw(with: layout.label.offsetBy(dx: origin.x, dy: origin.y), options: [.usesLineFragmentOrigin, .usesFontLeading])
            if let profile, let frame = layout.profile {
                drawProfile(profile, in: frame.offsetBy(dx: origin.x, dy: origin.y), palette: palette, dark: dark, context: context)
            }
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

    private func drawProfile(_ name: String, in frame: CGRect, palette: TooltipColorPalette, dark: Bool, context: CGContext) {
        func aligned(_ value: CGFloat) -> CGFloat { (value * backingScale).rounded() / backingScale }
        let ink = palette.keyTitle.resolved(dark: dark)
        context.addPath(CGPath(roundedRect: frame, cornerWidth: frame.height / 2, cornerHeight: frame.height / 2, transform: nil))
        context.setFillColor(palette.keyForeground.resolved(dark: dark).cgColor)
        context.fillPath()
        if let icon = Profile.icon {
            let slot = CGRect(x: frame.minX + Profile.leading, y: frame.minY + Profile.vertical,
                              width: Profile.iconSlot, height: frame.height - 2 * Profile.vertical)
            let rect = CGRect(x: aligned(slot.midX - icon.size.width / 2), y: aligned(slot.midY - icon.size.height / 2),
                              width: icon.size.width, height: icon.size.height)
            context.saveGState()
            context.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            context.setBlendMode(.sourceIn)
            context.setFillColor(ink.cgColor)
            context.fill(rect)
            context.endTransparencyLayer()
            context.restoreGState()
        }
        let x = frame.minX + Profile.leading + Profile.iconSlot + Profile.iconSpacing
        Self.profileString(name, color: ink)
            .draw(with: CGRect(x: x, y: frame.minY + Profile.vertical, width: frame.maxX - Profile.trailing - x,
                               height: Label.lineHeight(Profile.font)),
                  options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
    }

    /// The Profile name on its one line, tail-truncated as the Space header's is.
    static func profileString(_ name: String, color: NSColor = .black) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.minimumLineHeight = Label.lineHeight(Profile.font); paragraph.maximumLineHeight = Label.lineHeight(Profile.font)
        return NSAttributedString(string: name, attributes: [.font: Profile.font, .foregroundColor: color, .paragraphStyle: paragraph])
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
