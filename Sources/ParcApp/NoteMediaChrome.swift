import AppKit

@MainActor
enum NoteMediaStyle {
    static let cardFill = NoteTheme.adaptive("Media.CardFill", light: NoteTheme.rgb(0x1F1B2E, 0.035), dark: NoteTheme.rgb(0xFFFFFF, 0.05))
    static let cardHover = NoteTheme.adaptive("Media.CardHover", light: NoteTheme.rgb(0x1F1B2E, 0.065), dark: NoteTheme.rgb(0xFFFFFF, 0.085))
    static let cardStroke = NoteTheme.adaptive("Media.CardStroke", light: NoteTheme.rgb(0x1F1B2E, 0.11), dark: NoteTheme.rgb(0xFFFFFF, 0.11))
    static let shimmerGlow = NoteTheme.adaptive("Media.ShimmerGlow", light: NoteTheme.rgb(0x1F1B2E, 0.095), dark: NoteTheme.rgb(0xFFFFFF, 0.12))
    static let dropFill = NoteTheme.adaptive("Media.DropFill", light: NoteTheme.rgb(0x2702C2, 0.08), dark: NoteTheme.rgb(0x9380E0, 0.16))
    static let handleFill = NoteTheme.adaptive("Media.HandleFill", light: NoteTheme.rgb(0xFFFFFF, 0.96), dark: NoteTheme.rgb(0x2A2733, 0.96))
    static let handleStroke = NoteTheme.adaptive("Media.HandleStroke", light: NoteTheme.rgb(0x1F1B2E, 0.28), dark: NoteTheme.rgb(0xFFFFFF, 0.3))
    static let fieldFill = NoteTheme.adaptive("Media.FieldFill", light: NoteTheme.rgb(0x060E2B, 0.06), dark: NoteTheme.rgb(0xEEEEF6, 0.09))
    static let warningInk = NoteTheme.adaptive("Media.WarningInk", light: NoteTheme.rgb(0xC2410C), dark: NoteTheme.rgb(0xFB923C))
    static let backdrop = NoteTheme.adaptive("Media.Backdrop", light: NoteTheme.rgb(0xF7F7FB, 0.94), dark: NoteTheme.rgb(0x07060D, 0.9))

    static let cardRadius: CGFloat = 8
    static let imageRadius: CGFloat = 4
    static let verticalInset: CGFloat = 6
    static let captionGap: CGFloat = 6

    static func nunito(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        switch weight {
        case .heavy, .black: return NoteTheme.nunitoExtraBold(size)
        case .bold, .semibold: return NoteTheme.nunitoBold(size)
        default: return NoteTheme.nunitoRegular(size)
        }
    }

    static var titleFont: NSFont { nunito(15, weight: .bold) }
    static var detailFont: NSFont { nunito(13) }
    static var smallFont: NSFont { nunito(12) }

    static func cg(_ color: NSColor, in view: NSView) -> CGColor {
        var resolved = color.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { resolved = color.cgColor }
        return resolved
    }

    static func symbol(_ name: String, size: CGFloat = 13, weight: NSFont.Weight = .semibold) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: weight))
    }

    static func tinted(_ image: NSImage, _ color: NSColor, in view: NSView) -> NSImage {
        var ink = color
        view.effectiveAppearance.performAsCurrentDrawingAppearance { ink = NSColor(cgColor: color.cgColor) ?? color }
        let result = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            ink.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        result.isTemplate = false
        return result
    }

    static func textWidth(_ field: NSTextField) -> CGFloat {
        guard !field.stringValue.isEmpty else { return 0 }
        let font = field.font ?? NoteTheme.nunitoRegular(13)
        return ceil((field.stringValue as NSString).size(withAttributes: [.font: font]).width) + 6
    }

    static func label(_ text: String, font: NSFont, color: NSColor, lines: Int = 1) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = lines
        field.cell?.truncatesLastVisibleLine = true
        field.allowsDefaultTighteningForTruncation = false
        field.isSelectable = false
        return field
    }
}

@MainActor
enum NoteMediaMotion {
    static let hudCurve = CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1)

    static func instant(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    static func scaleTransform(_ scale: CGFloat, anchor: CGPoint, in view: NSView) -> CATransform3D {
        let size = view.bounds.size
        let flipped = view.superview?.isFlipped ?? true
        let x = anchor.x * size.width, y = (flipped ? anchor.y : 1 - anchor.y) * size.height
        var transform = CATransform3DMakeTranslation(x, y, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -x, -y, 0)
    }

    static func present(_ view: NSView, anchor: CGPoint) {
        view.wantsLayer = true
        view.isHidden = false
        guard let layer = view.layer else { return }
        let fromOpacity = layer.presentation()?.opacity ?? 0
        NoteMediaMotion.instant {
            layer.opacity = 1
            layer.transform = CATransform3DIdentity
        }
        layer.removeAnimation(forKey: "media.hud.transform")
        if NoteAnimation.reduceMotion {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = fromOpacity
            fade.toValue = 1
            fade.duration = 0.12
            layer.add(fade, forKey: "media.hud.opacity")
            return
        }
        let scale = CABasicAnimation(keyPath: "transform")
        scale.fromValue = NSValue(caTransform3D: scaleTransform(0.95, anchor: anchor, in: view))
        scale.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        scale.duration = 0.1
        scale.timingFunction = hudCurve
        layer.add(scale, forKey: "media.hud.transform")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fromOpacity
        fade.toValue = 1
        fade.duration = 0.05
        layer.add(fade, forKey: "media.hud.opacity")
    }

    static func dismiss(_ view: NSView, anchor: CGPoint, completion: (() -> Void)? = nil) {
        guard let layer = view.layer, !view.isHidden else { completion?(); return }
        let fromOpacity = layer.presentation()?.opacity ?? layer.opacity
        NoteMediaMotion.instant { layer.opacity = 0 }
        let generation = (layer.value(forKey: "media.hud.generation") as? Int ?? 0) + 1
        layer.setValue(generation, forKey: "media.hud.generation")
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated {
                guard layer.value(forKey: "media.hud.generation") as? Int == generation, layer.opacity == 0 else { return }
                view.isHidden = true
                completion?()
            }
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fromOpacity
        fade.toValue = 0
        fade.duration = NoteAnimation.reduceMotion ? 0.1 : 0.07
        fade.timingFunction = hudCurve
        layer.add(fade, forKey: "media.hud.opacity")
        if !NoteAnimation.reduceMotion {
            let scale = CABasicAnimation(keyPath: "transform")
            scale.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
            scale.toValue = NSValue(caTransform3D: scaleTransform(0.95, anchor: anchor, in: view))
            scale.duration = 0.07
            scale.timingFunction = hudCurve
            layer.add(scale, forKey: "media.hud.transform")
        }
        CATransaction.commit()
    }

    static func fadeIn(_ layer: CALayer, duration: CFTimeInterval = 0.2) {
        NoteMediaMotion.instant { layer.opacity = 1 }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = NoteAnimation.reduceMotion ? min(duration, 0.15) : duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "media.fadeIn")
    }

    static func press(_ layer: CALayer, pressed: Bool, in view: NSView, scale: CGFloat = 0.95) {
        let target = pressed ? scaleTransform(scale, anchor: CGPoint(x: 0.5, y: 0.5), in: view) : CATransform3DIdentity
        if NoteAnimation.reduceMotion {
            NoteMediaMotion.instant { layer.transform = target }
            return
        }
        let from = layer.presentation()?.transform ?? layer.transform
        NoteMediaMotion.instant { layer.transform = target }
        layer.add(NoteAnimation.spring("transform", .press, from: NSValue(caTransform3D: from), to: NSValue(caTransform3D: target)),
                  forKey: "media.press")
    }
}

@MainActor
class NoteMediaControl: NSView {
    var onPress: (() -> Void)?
    var isEnabled = true { didSet { if oldValue != isEnabled { refresh(); refreshCursorIfPointerOwned() } } }
    private(set) var isHovered = false
    private(set) var isPressed = false
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        addCursorUpdateArea()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func cursorUpdate(with event: NSEvent) {
        if isEnabled, applyNoteCursor(.pointingHand, for: event) { return }
        super.cursorUpdate(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        guard isTopmost(atWindowPoint: event.locationInWindow) else { return }
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) { setHovered(false) }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        setPressed(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        setPressed(bounds.contains(convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        setPressed(false)
        if inside { onPress?() }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onPress?()
        return true
    }

    override func isAccessibilityEnabled() -> Bool { isEnabled }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { isHovered = false; isPressed = false; refresh() }
    }

    func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        hoverDidChange()
        refresh()
    }

    private func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        pressDidChange()
        refresh()
    }

    func hoverDidChange() {}
    func pressDidChange() {}
    func refresh() {}
}

@MainActor
final class NoteMediaToolbar: NSView {
    private let card = CALayer()
    private(set) var buttons: [NoteControlButton] = []
    var anchor = CGPoint(x: 1, y: 0)
    static let padding: CGFloat = 3
    static let spacing: CGFloat = 2
    static let height: CGFloat = NoteTheme.toolbarButtonSize.height + padding * 2

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        card.cornerRadius = 9
        card.cornerCurve = .continuous
        card.borderWidth = 0.5
        card.shadowOpacity = 1
        card.shadowRadius = 7
        card.shadowOffset = CGSize(width: 0, height: -2)
        layer?.addSublayer(card)
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        isHidden = true
        layer?.opacity = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func setButtons(_ value: [NoteControlButton]) {
        for button in buttons where !value.contains(where: { $0 === button }) { button.removeFromSuperview() }
        buttons = value
        for button in value where button.superview !== self { addSubview(button) }
        needsLayout = true
    }

    var fittingWidth: CGFloat {
        guard !buttons.isEmpty else { return 0 }
        return buttons.reduce(0) { $0 + $1.intrinsicContentSize.width } + CGFloat(buttons.count - 1) * Self.spacing + Self.padding * 2
    }

    override func layout() {
        super.layout()
        NoteMediaMotion.instant {
            card.frame = bounds
            card.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 9, cornerHeight: 9, transform: nil)
        }
        var x = Self.padding
        for button in buttons {
            let size = button.intrinsicContentSize
            button.frame = NSRect(x: x, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
            x += size.width + Self.spacing
        }
        refreshColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    private func refreshColors() {
        NoteMediaMotion.instant {
            card.backgroundColor = NoteMediaStyle.cg(NoteTheme.menuFill, in: self)
            card.borderColor = NoteMediaStyle.cg(NoteTheme.menuHairline, in: self)
            card.shadowColor = NoteTheme.menuShadow.cgColor
        }
    }

    var isShown: Bool { !isHidden && (layer?.opacity ?? 0) > 0 }

    func show() {
        guard !isShown else { return }
        NoteMediaMotion.present(self, anchor: anchor)
    }

    func hide() {
        guard isShown else { return }
        NoteMediaMotion.dismiss(self, anchor: anchor)
    }

    func hideImmediately() {
        layer?.removeAllAnimations()
        NoteMediaMotion.instant { layer?.opacity = 0 }
        isHidden = true
    }
}

@MainActor
final class NoteMediaShimmer: NSView {
    private let gradient = CAGradientLayer()
    private var observer: NSObjectProtocol?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = NoteMediaStyle.imageRadius
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.locations = [0, 0.5, 1]
        layer?.addSublayer(gradient)
        setAccessibilityElement(true)
        setAccessibilityRole(.progressIndicator)
        setAccessibilityLabel("Loading")
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restart() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    var cornerRadius: CGFloat = NoteMediaStyle.imageRadius { didSet { layer?.cornerRadius = cornerRadius } }

    override func layout() {
        super.layout()
        NoteMediaMotion.instant {
            gradient.frame = NSRect(x: -bounds.width, y: 0, width: bounds.width * 3, height: bounds.height)
        }
        restart()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restart()
    }

    override func viewDidHide() {
        super.viewDidHide()
        gradient.removeAllAnimations()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        restart()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        restart()
    }

    private func restart() {
        let base = NoteMediaStyle.cg(NoteTheme.mediaPlaceholderFill, in: self)
        let glow = NoteMediaStyle.cg(NoteMediaStyle.shimmerGlow, in: self)
        NoteMediaMotion.instant {
            layer?.backgroundColor = NoteMediaStyle.cg(NoteTheme.mediaPlaceholderFill, in: self)
            gradient.colors = [base, glow, base]
            gradient.locations = [0.3, 0.5, 0.7]
        }
        gradient.removeAnimation(forKey: "media.shimmer")
        guard window != nil, !isHiddenOrHasHiddenAncestor, !NoteAnimation.reduceMotion, bounds.width > 0 else {
            NoteMediaMotion.instant { gradient.colors = [base, base, base] }
            return
        }
        let sweep = CABasicAnimation(keyPath: "position.x")
        let start = gradient.position.x - bounds.width
        sweep.fromValue = start
        sweep.toValue = start + bounds.width * 2
        sweep.duration = 1.5
        sweep.repeatCount = .infinity
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradient.add(sweep, forKey: "media.shimmer")
    }
}

@MainActor
final class NoteMediaCaption: NSView, NoteTextHost {
    let blockID: NoteBlockID
    let field: NoteTextField = .caption
    let textView = NoteTextView()
    var onFocusChange: ((Bool) -> Void)? {
        get { textView.onFocusChange }
        set { textView.onFocusChange = newValue }
    }
    var onHeightChange: (() -> Void)? {
        get { textView.onContentHeightChange }
        set { textView.onContentHeightChange = newValue }
    }

    init(blockID: NoteBlockID, editor: NotePageEditor?) {
        self.blockID = blockID
        super.init(frame: .zero)
        textView.host = self
        textView.editor = editor
        textView.placeholder = NoteTheme.captionPlaceholder
        textView.inputRulesEnabled = false
        textView.setAccessibilityLabel("Caption")
        addSubview(textView)
        refreshPresentation()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func refreshPresentation() {
        let settings = textView.editor?.session.page.settings ?? NotePageSettings()
        textView.presentation = NoteTextPresentation(role: .caption, pageFont: settings.font, small: settings.smallText)
    }

    var isFocused: Bool { textView.isFocused }

    func show(_ text: NoteText, editable: Bool) {
        textView.isEditable = editable
        textView.isSelectable = true
        refreshPresentation()
        guard text != textView.noteText else { return }
        textView.apply(text, selection: isFocused ? textView.selectedOffsets : nil)
        needsLayout = true
    }

    func height(for width: CGFloat) -> CGFloat {
        let target = max(1, width)
        if abs(textView.frame.width - target) > 0.5 {
            textView.setFrameSize(NSSize(width: target, height: max(textView.frame.height, 1)))
        }
        return ceil(textView.contentHeight())
    }

    override func layout() {
        super.layout()
        let height = self.height(for: bounds.width)
        textView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(height, bounds.height))
    }

    func focusAtEnd() {
        guard let window = textView.window else { return }
        let end = textView.noteText.length
        if window.makeFirstResponder(textView) { textView.selectedOffsets = end..<end }
    }
}

@MainActor
extension NoteBlockView {
    func invalidateMeasuredHeight() {
        needsLayout = true
        editor?.canvas.blockHeightDidChange(blockID)
    }

    func reportMediaError(_ error: Error) {
        editor?.onError?(error)
    }
}

@MainActor
class NoteCaptionedBlockView: NoteBlockView {
    let caption: NoteMediaCaption
    private(set) var captionRevealed = false

    override init(block: NoteBlock, editor: NotePageEditor?) {
        caption = NoteMediaCaption(blockID: block.id, editor: editor)
        super.init(block: block, editor: editor)
        caption.onFocusChange = { [weak self] focused in self?.captionFocusChanged(focused) }
        caption.onHeightChange = { [weak self] in self?.invalidateMeasuredHeight() }
        caption.isHidden = true
        addSubview(caption)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var canEdit: Bool { !isReadOnly && editor?.isReadOnly != true }

    override func themeDidChange() {
        super.themeDidChange()
        caption.refreshPresentation()
    }

    var allowsCaption: Bool { true }

    var captionVisible: Bool { allowsCaption && (!block.props.caption.isEmpty || captionRevealed) }

    override var textHosts: [NoteTextHost] { captionVisible ? [caption] : [] }

    func refreshCaption() {
        caption.show(block.props.caption, editable: canEdit)
        caption.isHidden = !captionVisible
    }

    func captionHeight(width: CGFloat) -> CGFloat {
        captionVisible ? NoteMediaStyle.captionGap + caption.height(for: width) : 0
    }

    func layoutCaption(top: CGFloat, x: CGFloat, width: CGFloat) {
        guard captionVisible else { return }
        caption.frame = NSRect(x: x, y: top + NoteMediaStyle.captionGap, width: width, height: caption.height(for: width))
    }

    func revealCaption() {
        guard canEdit, allowsCaption else { return }
        captionRevealed = true
        caption.isHidden = false
        invalidateMeasuredHeight()
        editor?.canvas.layoutSubtreeIfNeeded()
        layoutSubtreeIfNeeded()
        caption.focusAtEnd()
        captionRevealDidChange()
    }

    func captionRevealDidChange() {}

    private func captionFocusChanged(_ focused: Bool) {
        guard !focused, block.props.caption.isEmpty, captionRevealed else { return }
        captionRevealed = false
        caption.isHidden = true
        invalidateMeasuredHeight()
        captionRevealDidChange()
    }
}
