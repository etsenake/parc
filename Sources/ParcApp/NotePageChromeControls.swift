import AppKit

@MainActor
enum NotePageChrome {
    static let chipFill = NoteTheme.adaptive("Chrome.ChipFill", light: NoteTheme.rgb(0xFFFFFF, 0.86), dark: NoteTheme.rgb(0x1B1830, 0.82))
    static let chipHover = NoteTheme.adaptive("Chrome.ChipHover", light: NoteTheme.rgb(0xFFFFFF, 0.97), dark: NoteTheme.rgb(0x2A2645, 0.92))
    static let chipInk = NoteTheme.adaptive("Chrome.ChipInk", light: NoteTheme.rgb(0x1F1B2E, 0.78), dark: NoteTheme.rgb(0xEDEBFA, 0.86))
    static let fieldFill = NoteTheme.adaptive("Chrome.FieldFill", light: NoteTheme.rgb(0x060E2B, 0.06), dark: NoteTheme.rgb(0xEEEEF6, 0.10))
    static let checkedFill = NoteTheme.adaptive("Chrome.CheckedFill", light: NoteTheme.rgb(0x2702C2, 0.12), dark: NoteTheme.rgb(0x9380E0, 0.26))
    static let ghostInk = NoteTheme.adaptive("Chrome.GhostInk", light: NoteTheme.rgb(0x1F1B2E, 0.45), dark: NoteTheme.rgb(0xEDEBFA, 0.5))

    static func font(_ size: CGFloat, bold: Bool = false) -> NSFont {
        let base = NoteTheme.bodyFont(.standard, bold: bold)
        return NSFont(descriptor: base.fontDescriptor, size: size) ?? base
    }

    static func labelFont(_ size: CGFloat = 12, weight: NSFont.Weight = .medium) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .semibold) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
    }

    static func cgColor(_ color: NSColor, in view: NSView) -> CGColor {
        var result = color.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    static func isDark(_ view: NSView) -> Bool {
        view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    static func centeredScale(_ scale: CGFloat, size: NSSize) -> CATransform3D {
        var transform = CATransform3DMakeTranslation(size.width / 2, size.height / 2, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -size.width / 2, -size.height / 2, 0)
    }

    static func press(_ view: NSView, down: Bool, scale: CGFloat = 0.95) {
        guard let layer = view.layer else { return }
        let target = down ? centeredScale(scale, size: view.bounds.size) : CATransform3DIdentity
        guard !NoteTheme.reduceMotion else {
            withoutAnimation { layer.transform = CATransform3DIdentity }
            return
        }
        NoteAnimation.animate(layer, "transform", to: NSValue(caTransform3D: target), spring: .press, key: "note.chrome.press")
    }

    static func fade(_ view: NSView, to alpha: CGFloat, duration: CFTimeInterval = 0.12) {
        guard let layer = view.layer else { view.alphaValue = alpha; return }
        let from = layer.presentation()?.opacity ?? layer.opacity
        withoutAnimation { layer.opacity = Float(alpha) }
        guard abs(from - Float(alpha)) > 0.001 else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = Float(alpha)
        animation.duration = NoteTheme.reduceMotion ? min(duration, 0.15) : duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "note.chrome.fade")
    }

    static func presentHUD(_ view: NSView, from offset: CGFloat = -6) {
        guard let layer = view.layer else { return }
        layer.removeAnimation(forKey: "note.chrome.hud")
        withoutAnimation { layer.opacity = 1; layer.transform = CATransform3DIdentity }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = NoteTheme.reduceMotion ? 0.15 : 0.05
        guard !NoteTheme.reduceMotion else { layer.add(fade, forKey: "note.chrome.hud"); return }
        let grow = CABasicAnimation(keyPath: "transform")
        var start = centeredScale(0.95, size: view.bounds.size)
        start = CATransform3DConcat(start, CATransform3DMakeTranslation(0, offset, 0))
        grow.fromValue = NSValue(caTransform3D: start)
        grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        grow.duration = 0.1
        grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1)
        let group = CAAnimationGroup()
        group.animations = [fade, grow]
        group.duration = 0.1
        layer.add(group, forKey: "note.chrome.hud")
    }

    static func dismissHUD(_ view: NSView, completion: @escaping () -> Void) {
        guard let layer = view.layer, view.window != nil || view.superview != nil else { completion(); return }
        let from = layer.presentation()?.opacity ?? layer.opacity
        withoutAnimation { layer.opacity = 0 }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = 0
        fade.duration = NoteTheme.reduceMotion ? 0.12 : 0.07
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1)
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        layer.add(fade, forKey: "note.chrome.hud")
        CATransaction.commit()
    }
}

@MainActor
class NotePageChromeButton: PointingHandButton {
    enum Style { case icon, chip, ghost, menuRow }

    let style: Style
    var symbolName: String? { didSet { refreshContent() } }
    var label: String { didSet { refreshContent() } }
    var symbolSize: CGFloat = 13 { didSet { refreshContent() } }
    var isChecked = false { didSet { if isChecked != oldValue { needsDisplay = true; updateAccessibilityValue() } } }
    var isKeyboardFocused = false { didSet { if isKeyboardFocused != oldValue { needsDisplay = true } } }
    var tint: NSColor? { didSet { needsDisplay = true } }
    var fillColor: NSColor? { didSet { needsDisplay = true } }
    var hoverFillColor: NSColor? { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = NoteTheme.controlRadius { didSet { needsDisplay = true } }
    var onPress: (() -> Void)?
    var showsTitle: Bool { style != .icon }
    private(set) var isHovered = false
    private var hoverArea: NSTrackingArea?

    init(_ label: String, symbol: String? = nil, style: Style = .chip) {
        self.label = label
        self.style = style
        symbolName = symbol
        super.init(frame: .zero)
        wantsLayer = true
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        imagePosition = .noImage
        title = ""
        focusRingType = .none
        target = self
        action = #selector(pressed)
        setAccessibilityLabel(label)
        refreshContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var allowsVibrancy: Bool { false }

    var titleFont: NSFont {
        switch style {
        case .menuRow: return NotePageChrome.font(14)
        case .chip, .ghost: return NotePageChrome.labelFont(12, weight: .medium)
        case .icon: return NotePageChrome.labelFont(12)
        }
    }

    override var intrinsicContentSize: NSSize {
        let height: CGFloat = style == .menuRow ? 32 : 28
        guard showsTitle else { return NSSize(width: 28, height: height) }
        let text = (label as NSString).size(withAttributes: [.font: titleFont]).width
        let icon: CGFloat = symbolName == nil ? 0 : symbolSize + 6
        return NSSize(width: ceil(text + icon + (style == .menuRow ? 20 : 18)), height: height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        NotePageChrome.press(self, down: true, scale: style == .menuRow ? 0.992 : 0.95)
        super.mouseDown(with: event)
        NotePageChrome.press(self, down: false)
    }

    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1 : 0.25
            if !isEnabled { isHovered = false }
            needsDisplay = true
        }
    }

    @objc private func pressed() { onPress?() }

    private func refreshContent() {
        setAccessibilityLabel(label)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    private func updateAccessibilityValue() {
        setAccessibilityValue(isChecked ? "On" : nil)
    }

    var currentFill: NSColor? {
        if isHighlighted { return hoverFillColor ?? NoteTheme.pressedFill }
        if isChecked { return NotePageChrome.checkedFill }
        if isHovered || isKeyboardFocused { return hoverFillColor ?? NoteTheme.hoverFill }
        return fillColor
    }

    var currentInk: NSColor {
        if let tint { return tint }
        if isChecked { return NoteTheme.accent }
        switch style {
        case .ghost: return isHovered ? NoteTheme.secondaryInk : NotePageChrome.ghostInk
        case .chip: return NotePageChrome.chipInk
        case .icon: return NoteTheme.secondaryInk
        case .menuRow: return NoteTheme.ink
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if let fill = currentFill {
            fill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }
        if isKeyboardFocused && style != .menuRow {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: cornerRadius - 1, yRadius: cornerRadius - 1)
            ring.lineWidth = 2
            ring.stroke()
        }
        let ink = currentInk
        let image = symbolName.flatMap { NotePageChrome.symbol($0, pointSize: symbolSize) }
        guard showsTitle else {
            if let image { drawTemplate(image, in: bounds, ink: ink) }
            return
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: ink]
        let text = label as NSString
        let textSize = text.size(withAttributes: attributes)
        let iconWidth: CGFloat = image == nil ? 0 : symbolSize + 6
        var x = style == .menuRow ? 10 : (bounds.width - textSize.width - iconWidth) / 2
        if let image {
            drawTemplate(image, in: NSRect(x: x, y: 0, width: symbolSize + 2, height: bounds.height), ink: ink)
            x += iconWidth
        }
        text.draw(at: NSPoint(x: x, y: (bounds.height - textSize.height) / 2), withAttributes: attributes)
    }

    private func drawTemplate(_ image: NSImage, in rect: NSRect, ink: NSColor) {
        let size = image.size
        let target = NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height).integral
        let tinted = NSImage(size: size, flipped: false) { bounds in
            image.draw(in: bounds)
            ink.set()
            bounds.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

@MainActor
final class NotePageTextField: NSTextField {
    var onCommand: ((Selector) -> Bool)?

    convenience init(placeholder: String, size: CGFloat = 14) {
        self.init(frame: .zero)
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        usesSingleLineMode = true
        lineBreakMode = .byTruncatingTail
        cell?.isScrollable = true
        cell?.wraps = false
        font = NotePageChrome.font(size)
        textColor = NoteTheme.ink
        placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .font: NotePageChrome.font(size), .foregroundColor: NoteTheme.tertiaryInk])
        setAccessibilityPlaceholderValue(placeholder)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = NoteTheme.caret
            editor.selectedTextAttributes = [.backgroundColor: NoteTheme.selection]
        }
        return accepted
    }
}

@MainActor
final class NotePageFieldBox: NSView {
    let field: NotePageTextField
    var symbolName: String? { didSet { needsLayout = true; needsDisplay = true } }
    var trailingAccessory: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let trailingAccessory { addSubview(trailingAccessory) }
            needsLayout = true
        }
    }

    init(placeholder: String, symbol: String? = nil, size: CGFloat = 14) {
        field = NotePageTextField(placeholder: placeholder, size: size)
        symbolName = symbol
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(field)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let leading: CGFloat = symbolName == nil ? 10 : 30
        var trailing: CGFloat = 8
        if let accessory = trailingAccessory {
            let size = accessory.fittingSize
            accessory.frame = NSRect(x: bounds.width - size.width - 8, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
            trailing += size.width + 6
        }
        let height = ceil(field.intrinsicContentSize.height)
        field.frame = NSRect(x: leading, y: (bounds.height - height) / 2, width: max(0, bounds.width - leading - trailing), height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        NotePageChrome.fieldFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        guard let symbolName, let image = NotePageChrome.symbol(symbolName, pointSize: 12, weight: .semibold) else { return }
        let size = image.size
        let rect = NSRect(x: 10, y: (bounds.height - size.height) / 2, width: size.width, height: size.height).integral
        let tinted = NSImage(size: size, flipped: false) { bounds in
            image.draw(in: bounds)
            NoteTheme.tertiaryInk.set()
            bounds.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(field)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .iBeam)
    }
}
