import AppKit

///
/// The small-screen fit is a Parc adaptation; ordinary dimensions are recovered.
enum OnboardingSetupLayout {
    static let size = NSSize(width: 967, height: 548)
    static let instructionWidth: CGFloat = 357
    static let padding: CGFloat = 50
    static let cornerRadius: CGFloat = 20
    static let borderWidth: CGFloat = 1
    /// CALayer borders paint inset from bounds, so expanding 1pt puts the 1pt
    /// stroke at −1…0 (centerline −0.5).
    static let outerStrokeInset: CGFloat = 1
    /// The theme texture's repeat, shared with the sidebar's theme renderer.
    static let grainTileSize = NSSize(width: ThemeTexturePitch.points, height: ThemeTexturePitch.points)
    /// `StrokeStyle` lineWidth 1, lineCap butt, lineJoin miter, miterLimit 10.
    static let strokeMiterLimit: CGFloat = 10
    /// Horizontal margin kept when the window is smaller than the 967-point card.
    static let horizontalInset: CGFloat = 24
    /// Vertical margin kept when the window is smaller than the 548-point card.
    static let verticalInset: CGFloat = 48

    static func frame(in bounds: NSRect) -> NSRect {
        let scale = min(1, max(0, bounds.width - 2 * horizontalInset) / size.width,
                        max(0, bounds.height - 2 * verticalInset) / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }
}

///
///
/// `NSColor.colorNamed:bundle:` once and store CardBackground, CardInnerBorder
/// and CardOuterBorder in `__common`. Parc registers the recovered names with
/// the unthemed catalog values rather than loading that bundle. A chosen Space
/// supplies the card's semantic background instead of CardBackground.
enum OnboardingSetupPalette {
    static let cardBackgroundName: NSColor.Name = "CardBackground"
    static let innerBorderName: NSColor.Name = "CardInnerBorder"
    static let outerBorderName: NSColor.Name = "CardOuterBorder"

    static let card = NSColor(name: cardBackgroundName) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 140 / 255, green: 141 / 255, blue: 171 / 255, alpha: 1)
            : NSColor(srgbRed: 230 / 255, green: 231 / 255, blue: 1, alpha: 1)
    }
    static let title = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white : .black
    }
    static let message = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .white : NSColor(srgbRed: 118 / 255, green: 118 / 255, blue: 118 / 255, alpha: 1)
    }
    static let action = NSColor(srgbRed: 49 / 255, green: 57 / 255, blue: 251 / 255, alpha: 1)
    /// CardInnerBorder: light white/0, dark white/0.2.
    static let innerBorder = NSColor(name: innerBorderName) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.2)
            : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)
    }
    /// CardOuterBorder: light black/0, dark black/0.61.
    static let outerBorder = NSColor(name: outerBorderName) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.61)
            : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
    }
}

/// A persistent setup card. Only its content changes when the reducer advances;
/// the owning window and animated background remain in place.
final class OnboardingSetupCard: NSView {
    final class Column: NSView {
        override var isFlipped: Bool { true }
        var onLayout: (() -> Void)?
        override func layout() { super.layout(); onLayout?() }
    }

    /// Clipped grain fill. AuthFeature.Card overlays tiled grain on the
    /// background shape; clicks fall through to the card and its controls.
    final class Chrome: NSView {
        let grain = TiledGrainLayer()
        override var isFlipped: Bool { true }
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.cornerRadius = OnboardingSetupLayout.cornerRadius
            layer?.cornerCurve = .continuous
            layer?.masksToBounds = true
            grain.anchorPoint = .zero
            grain.contentsGravity = .resize
            grain.needsDisplayOnBoundsChange = true
            layer?.addSublayer(grain)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func layout() {
            super.layout()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            grain.frame = bounds
            CATransaction.commit()
        }
    }

    /// Inner and outer 1pt continuous strokes sit above the content column so
    /// full-bleed steps cannot cover CardInnerBorder. Inner uses the full
    /// bounds: a 1pt inside border has centerline 0.5 and occupies 0…1, so it
    /// does not need the grain clip. Outer is expanded 1pt so its inset ink
    /// occupies −1…0. Shadow lives on the unclipped card layer.
    final class Borders: NSView {
        let inner = CardStrokeLayer()
        let outer = CardStrokeLayer()
        override var isFlipped: Bool { true }
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = false
            inner.anchorPoint = .zero
            outer.anchorPoint = .zero
            outer.masksToBounds = false
            layer?.addSublayer(inner)
            layer?.addSublayer(outer)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func layout() {
            super.layout()
            let outside = OnboardingSetupLayout.outerStrokeInset
            CATransaction.begin(); CATransaction.setDisableActions(true)
            inner.frame = bounds
            inner.cornerRadius = OnboardingSetupLayout.cornerRadius
            outer.frame = bounds.insetBy(dx: -outside, dy: -outside)
            outer.cornerRadius = OnboardingSetupLayout.cornerRadius + outside
            CATransaction.commit()
        }
    }

    /// Recovered `StrokeStyle`: lineWidth 1, lineCap butt, lineJoin miter,
    /// miterLimit 10. Visible ink is the continuous CALayer border so the
    /// stroke follows the fill's `cornerCurve` rather than a circular path.
    final class CardStrokeLayer: CAShapeLayer {
        override init() {
            super.init()
            lineWidth = OnboardingSetupLayout.borderWidth
            miterLimit = OnboardingSetupLayout.strokeMiterLimit
            lineCap = .butt
            lineJoin = .miter
            fillColor = nil
            strokeColor = nil
            borderWidth = OnboardingSetupLayout.borderWidth
            cornerCurve = .continuous
        }
        override init(layer: Any) {
            super.init(layer: layer)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    }

    final class TiledGrainLayer: CALayer {
        var tile: CGImage?
        var tileSize = OnboardingSetupLayout.grainTileSize
        override func draw(in ctx: CGContext) {
            guard let tile, tileSize.width > 0, tileSize.height > 0 else { return }
            // Bilinear, as the theme renderer's linear sampler.
            ctx.interpolationQuality = .low
            var y: CGFloat = 0
            while y < bounds.height {
                var x: CGFloat = 0
                while x < bounds.width {
                    ctx.draw(tile, in: CGRect(x: x, y: y, width: tileSize.width, height: tileSize.height))
                    x += tileSize.width
                }
                y += tileSize.height
            }
        }
    }

    let instructions = Column()
    let content = Column()
    let chrome = Chrome()
    let borders = Borders()
    let heading = NSTextField(wrappingLabelWithString: "")
    let message = NSTextField(wrappingLabelWithString: "")
    /// The browser-choice step's backdrop; text takes its dominant theme's
    /// content appearance, as content over a Space theme does.
    let backdrop = BrowserImportBackdrop()
    var onBackdropChange: (() -> Void)?
    /// Ink over the backdrop. A theme's tinted ink loses contrast over a vivid
    /// wash, so its content appearance picks black or white; the sunset is
    /// white over its colour, and the page's own grey below it.
    private var backdropInk: NSColor?
    private var backdropFillsPage = false
    var titleColor: NSColor { backdropInk ?? OnboardingSetupPalette.title }
    var messageColor: NSColor { backdropInk?.withAlphaComponent(0.75) ?? OnboardingSetupPalette.message }
    /// Skip, Back and the step count sit low on the card, below the sunset.
    var chromeColor: NSColor { backdropFillsPage ? messageColor : OnboardingSetupPalette.message }
    var themeBackground: NSColor? { didSet { updateColors() } }
    /// The chosen Space theme's texture, drawn as the sidebar's theme renderer
    /// draws it. No theme, or one without colour, draws none.
    var grainTheme: SpaceTheme? { didSet { if grainTheme != oldValue { updateColors() } } }
    /// The sidebar's `ThemeWindowActivity` state; inactive draws a quarter.
    var grainIsActive = true { didSet { if grainIsActive != oldValue { updateColors() } } }
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        content.wantsLayer = true
        heading.wantsLayer = true
        message.wantsLayer = true
        setAccessibilityRole(.group)
        layer?.cornerRadius = OnboardingSetupLayout.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 17
        layer?.shadowOffset = CGSize(width: 0, height: 14)
        layer?.backgroundColor = nil
        chrome.addSubview(backdrop)
        backdrop.onDominantChange = { [weak self] in self?.applyBackdrop($0) }
        addSubview(chrome)
        addSubview(instructions)
        addSubview(content)
        addSubview(borders)
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
        if backdropInk != nil { applyBackdrop(backdrop.dominant) }
    }

    private func applyBackdrop(_ page: BrowserImportBackdrop.Page?) {
        switch page {
        case .theme(let theme)? where theme.primaryColor != nil:
            let dark = ThemeChromePalette(theme: theme, appearance: effectiveAppearance).isDark
            backdropInk = dark ? .white : .black; backdropFillsPage = true
        case .sunset?: backdropInk = .white; backdropFillsPage = false
        default: backdropInk = nil; backdropFillsPage = false
        }
        heading.textColor = titleColor; message.textColor = messageColor
        onBackdropChange?()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        chrome.grain.contentsScale = scale
        chrome.grain.setNeedsDisplay()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            chrome.layer?.backgroundColor = (themeBackground ?? OnboardingSetupPalette.card).cgColor
            borders.inner.borderColor = OnboardingSetupPalette.innerBorder.cgColor
            borders.outer.borderColor = OnboardingSetupPalette.outerBorder.cgColor
        }
        // On an opaque fill, multiply is the theme renderer's themeComposite
        // and layer opacity is its strength scale of the premultiplied texture.
        let theme = grainTheme.flatMap { $0.isValid && $0.primaryColor != nil ? $0 : nil }
        let strength = theme?.textureStrength(isActive: grainIsActive) ?? 0
        // The card fill changes at once, like the sidebar's; so does the grain.
        CATransaction.begin(); CATransaction.setDisableActions(true)
        chrome.grain.compositingFilter = "multiplyBlendMode"
        chrome.grain.opacity = Float(strength)
        chrome.grain.tile = strength > 0 ? theme.flatMap { Self.grainTile($0.texture) } : nil
        chrome.grain.tileSize = OnboardingSetupLayout.grainTileSize
        chrome.grain.isHidden = chrome.grain.tile == nil
        chrome.grain.setNeedsDisplay()
        CATransaction.commit()
    }

    func configure(title: String, subtitle: String, font: NSFont,
                   back: NSView, next: NSView, skip: NSView, progress: NSView,
                   accessory: NSView?, accessoryHeight: CGFloat = 30) {
        let controls = [heading, message, back, next, skip, progress] + (accessory.map { [$0] } ?? [])
        // Access refreshes update this card once a second. Keep existing native
        // controls attached so a refresh cannot discard keyboard focus/hover.
        instructions.subviews.filter { view in !controls.contains { $0 === view } }
            .forEach { $0.removeFromSuperview() }
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 36
        paragraph.maximumLineHeight = 36
        paragraph.lineBreakMode = .byWordWrapping
        heading.attributedStringValue = NSAttributedString(string: title, attributes: [
            .font: font, .foregroundColor: titleColor,
            .kern: -1.3, .paragraphStyle: paragraph
        ])
        heading.setAccessibilityRole(NSAccessibility.Role(rawValue: "AXHeading"))
        heading.setAccessibilityLabel(title)
        message.stringValue = subtitle
        message.setAccessibilityRole(.staticText)
        progress.setAccessibilityRole(.staticText)
        setAccessibilityLabel(title)
        message.font = .systemFont(ofSize: 14)
        message.textColor = messageColor
        for view in controls where view.superview !== instructions { instructions.addSubview(view) }
        instructions.onLayout = { [weak self, weak back, weak next, weak skip, weak progress, weak accessory] in
            guard let self else { return }
            let bounds = self.instructions.bounds
            let titleHeight = self.heading.sizeThatFits(NSSize(width: bounds.width, height: 200)).height
            self.heading.frame = NSRect(x: 0, y: back?.isHidden == true ? 0 : 40,
                width: bounds.width, height: titleHeight)
            let detailY = self.heading.frame.maxY + 20
            let detailHeight = self.message.sizeThatFits(NSSize(width: bounds.width, height: 160)).height
            self.message.frame = NSRect(x: 0, y: detailY, width: bounds.width, height: detailHeight)
            back?.frame = NSRect(x: -6, y: -5, width: 64, height: 25)
            accessory?.frame = NSRect(x: 0, y: detailY + detailHeight + 24,
                width: bounds.width, height: accessoryHeight)
            next?.frame = NSRect(x: 0, y: bounds.height - 40, width: bounds.width, height: 40)
            skip?.frame = NSRect(x: 0, y: bounds.height - 76, width: bounds.width, height: 26)
            progress?.frame = NSRect(x: 0, y: bounds.height + 14, width: bounds.width, height: 18)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        chrome.frame = bounds
        backdrop.frame = bounds
        borders.frame = bounds
        chrome.needsLayout = true
        borders.needsLayout = true
        let padding = OnboardingSetupLayout.padding
        instructions.frame = NSRect(x: padding, y: padding,
            width: OnboardingSetupLayout.instructionWidth - 2 * padding,
            height: bounds.height - 2 * padding)
        content.frame = NSRect(x: OnboardingSetupLayout.instructionWidth, y: 0,
            width: bounds.width - OnboardingSetupLayout.instructionWidth, height: bounds.height)
        instructions.needsLayout = true
        content.needsLayout = true
    }

    /// The same bundled `ThemeTextures` file the theme renderer samples.
    static func grainTile(_ texture: SpaceTheme.Texture) -> CGImage? {
        if let cached = grainTiles[texture] { return cached }
        let tile = Bundle.main.url(forResource: texture.rawValue, withExtension: "png", subdirectory: "ThemeTextures")
            .flatMap(NSImage.init(contentsOf:))?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        grainTiles[texture] = tile
        return tile
    }
    private static var grainTiles: [SpaceTheme.Texture: CGImage] = [:]
}
