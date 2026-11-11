import AppKit

enum OnboardingSetupLayout {
    static let size = NSSize(width: 967, height: 548)
    static let instructionWidth: CGFloat = 357
    static let padding: CGFloat = 50
    static let cornerRadius: CGFloat = 20
    static let borderWidth: CGFloat = 1
    static let outerStrokeInset: CGFloat = 1
    static let grainTileSize = NSSize(width: ThemeTexturePitch.points, height: ThemeTexturePitch.points)
    static let strokeMiterLimit: CGFloat = 10
    static let horizontalInset: CGFloat = 24
    static let verticalInset: CGFloat = 48

    static func frame(in bounds: NSRect) -> NSRect {
        let scale = min(1, max(0, bounds.width - 2 * horizontalInset) / size.width,
                        max(0, bounds.height - 2 * verticalInset) / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }
}

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
    static let innerBorder = NSColor(name: innerBorderName) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.2)
            : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)
    }
    static let outerBorder = NSColor(name: outerBorderName) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.61)
            : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
    }
}

final class OnboardingSetupCard: NSView {
    final class Column: NSView {
        override var isFlipped: Bool { true }
        var onLayout: (() -> Void)?
        override func layout() { super.layout(); onLayout?() }
    }

    final class Chrome: NSView {
        let grain = TiledGrainLayer()
        var themeSurface: NSView? {
            didSet {
                oldValue?.removeFromSuperview()
                if let themeSurface { addSubview(themeSurface, positioned: .below, relativeTo: subviews.first) }
                needsLayout = true
            }
        }
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
            themeSurface?.frame = bounds
            CATransaction.commit()
        }
    }

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

    final class OutgoingText: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private final class TextTrail: NSView {
        let image: CGImage
        init(image: CGImage, frame: NSRect) {
            self.image = image
            super.init(frame: frame)
            wantsLayer = true
            layerContentsRedrawPolicy = .onSetNeedsDisplay
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override var wantsUpdateLayer: Bool { true }
        override func updateLayer() { layer?.contents = image; layer?.contentsGravity = .resize }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    struct TextSnapshot {
        fileprivate let heading: (image: CGImage, frame: NSRect, offset: Double)?
        fileprivate let message: (image: CGImage, frame: NSRect, offset: Double)?
    }

    let instructions = Column()
    let outgoingText = OutgoingText()
    let content = Column()
    let chrome = Chrome()
    let borders = Borders()
    let heading = NSTextField(wrappingLabelWithString: "")
    let message = NSTextField(wrappingLabelWithString: "")
    let backdrop = BrowserImportBackdrop()
    var themeTextColor: NSColor? {
        didSet {
            heading.textColor = titleColor
            let title = NSMutableAttributedString(attributedString: heading.attributedStringValue)
            title.addAttribute(.foregroundColor, value: titleColor, range: NSRange(location: 0, length: title.length))
            heading.attributedStringValue = title
            styleMessage()
            updateColors()
        }
    }
    var titleColor: NSColor { themeTextColor ?? OnboardingSetupPalette.title }
    var importInk = false { didSet { if importInk != oldValue { styleMessage() } } }
    private var messageText = ""
    var textSpansCard = false { didSet { if textSpansCard != oldValue { updateColors() } } }
    var messageColor: NSColor { themeTextColor ?? (importInk ? titleColor : OnboardingSetupPalette.message) }
    var fill: NSColor { themeBackground ?? OnboardingSetupPalette.card }
    var chromeColor: NSColor { themeTextColor ?? (importInk ? titleColor : OnboardingSetupPalette.message) }
    var themeBackground: NSColor? { didSet { updateColors() } }
    var grainTheme: SpaceTheme? { didSet { if grainTheme != oldValue { updateColors() } } }
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
        addSubview(chrome)
        addSubview(instructions)
        addSubview(outgoingText)
        addSubview(content)
        addSubview(borders)
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        chrome.grain.contentsScale = scale
        chrome.grain.setNeedsDisplay()
    }

    private func updateColors() {
        let width = OnboardingSetupLayout.size.width, padding = OnboardingSetupLayout.padding
        backdrop.setPage(fill: fill, ink: titleColor,
                         text: textSpansCard ? 0...1 : padding / width...(OnboardingSetupLayout.instructionWidth - padding) / width)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            chrome.layer?.backgroundColor = (themeBackground ?? OnboardingSetupPalette.card).cgColor
            borders.inner.borderColor = OnboardingSetupPalette.innerBorder.cgColor
            borders.outer.borderColor = OnboardingSetupPalette.outerBorder.cgColor
        }
        let theme = grainTheme.flatMap { $0.isValid && $0.primaryColor != nil ? $0 : nil }
        let strength = theme?.textureStrength(isActive: grainIsActive) ?? 0
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
        messageText = subtitle
        styleMessage()
        message.setAccessibilityRole(.staticText)
        progress.setAccessibilityRole(.staticText)
        setAccessibilityLabel(title)
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

    private func styleMessage() {
        let font = NSFont.systemFont(ofSize: 15, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = max(0, 21 - (font.ascender - font.descender + font.leading))
        paragraph.lineBreakMode = .byWordWrapping
        message.font = font
        message.attributedStringValue = NSAttributedString(string: messageText, attributes: [
            .font: font, .foregroundColor: messageColor, .kern: -0.3, .paragraphStyle: paragraph
        ])
        message.textColor = messageColor
    }

    func captureText() -> TextSnapshot? {
        guard !isHiddenOrHasHiddenAncestor, window != nil else { return nil }
        func capture(_ field: NSTextField) -> (image: CGImage, frame: NSRect, offset: Double)? {
            guard !field.isHidden, !field.stringValue.isEmpty, field.bounds.width > 0, field.bounds.height > 0,
                  let rep = field.bitmapImageRepForCachingDisplay(in: field.bounds) else { return nil }
            field.effectiveAppearance.performAsCurrentDrawingAppearance {
                field.cacheDisplay(in: field.bounds, to: rep)
            }
            let offset = field.layer?.presentation()?.value(forKeyPath: "transform.translation.x") as? Double ?? 0
            return rep.cgImage.map { ($0, field.frame, offset) }
        }
        let snapshot = TextSnapshot(heading: capture(heading), message: capture(message))
        return snapshot.heading == nil && snapshot.message == nil ? nil : snapshot
    }

    func animateStepChange(from outgoing: TextSnapshot?, direction: OnboardingTransitionDirection,
                           slides: Bool, fades: Bool) {
        typealias Motion = OnboardingStepMotion
        if fades {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = Motion.contentFadeDuration
            let curve = Motion.contentFadeCurve
            fade.timingFunction = CAMediaTimingFunction(controlPoints: curve.0, curve.1, curve.2, curve.3)
            content.layer?.add(fade, forKey: "step")
        }
        guard slides else { return }
        let (insertion, removal) = Motion.offsets(direction)
        for (field, spring, old) in [(heading, Motion.titleSpring, outgoing?.heading),
                                     (message, Motion.messageSpring, outgoing?.message)] {
            field.layer?.add(Self.slide(from: insertion, to: 0, spring: spring), forKey: "step")
            guard let old else { continue }
            let trail = TextTrail(image: old.image, frame: old.frame)
            outgoingText.addSubview(trail)
            trail.displayIfNeeded()
            let away = Self.slide(from: old.offset, to: removal, spring: spring)
            away.fillMode = .forwards
            away.isRemovedOnCompletion = false
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak trail] in trail?.removeFromSuperview() }
            trail.layer?.add(away, forKey: "step")
            CATransaction.commit()
        }
    }

    private static func slide(from: Double, to: Double, spring: OnboardingStepMotion.Spring) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: "transform.translation.x")
        animation.mass = 1
        animation.stiffness = spring.stiffness
        animation.damping = spring.damping
        animation.fromValue = from
        animation.toValue = to
        animation.duration = animation.settlingDuration
        return animation
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
        outgoingText.frame = instructions.frame
        content.frame = NSRect(x: OnboardingSetupLayout.instructionWidth, y: 0,
            width: bounds.width - OnboardingSetupLayout.instructionWidth, height: bounds.height)
        instructions.needsLayout = true
        content.needsLayout = true
    }

    static func grainTile(_ texture: SpaceTheme.Texture) -> CGImage? {
        if let cached = grainTiles[texture] { return cached }
        let tile = Bundle.main.url(forResource: texture.rawValue, withExtension: "png", subdirectory: "ThemeTextures")
            .flatMap(NSImage.init(contentsOf:))?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        grainTiles[texture] = tile
        return tile
    }
    private static var grainTiles: [SpaceTheme.Texture: CGImage] = [:]
}
