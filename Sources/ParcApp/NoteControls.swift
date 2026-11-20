import AppKit
import CoreText

struct NoteIconDecoration: OptionSet, Hashable {
    let rawValue: Int
    static let italic = NoteIconDecoration(rawValue: 1)
    static let underline = NoteIconDecoration(rawValue: 2)
    static let strikethrough = NoteIconDecoration(rawValue: 4)
    static let regularWeight = NoteIconDecoration(rawValue: 8)
}

@MainActor
enum NoteIconRenderer {
    private static var symbolCache: [String: NSImage] = [:]
    private static var featherDescriptor: CTFontDescriptor?
    private static var featherLoaded = false

    static func symbolWeight(for font: NSFont) -> NSFont.Weight {
        let name = font.fontName.lowercased()
        if name.contains("extrabold") || name.contains("black") { return .heavy }
        if name.contains("bold") { return .semibold }
        return .medium
    }

    static func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
        let key = "\(name)|\(pointSize)|\(weight.rawValue)"
        if let cached = symbolCache[key] { return cached }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
            ?? NSImage(named: name)
        if let image { symbolCache[key] = image }
        return image
    }

    static func featherFont(size: CGFloat) -> NSFont? {
        if !featherLoaded {
            featherLoaded = true
            if let url = Bundle.main.resourceURL?.appendingPathComponent("CustomInfoPicker/feather.ttf"),
               let found = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] {
                featherDescriptor = found.first
            }
        }
        guard let featherDescriptor else { return nil }
        return CTFontCreateWithFontDescriptor(featherDescriptor, size, nil) as NSFont
    }

    static func isPrivateUse(_ text: String) -> Bool {
        guard let scalar = text.unicodeScalars.first, text.unicodeScalars.count == 1 else { return false }
        return (0xE000...0xF8FF).contains(scalar.value)
    }

    static func glyphFont(for text: String, pointSize: CGFloat, decoration: NoteIconDecoration) -> NSFont {
        if isPrivateUse(text), let feather = featherFont(size: pointSize * 1.15) { return feather }
        let scale: CGFloat = text.count > 2 ? 0.78 : text.count == 2 ? 0.92 : 1.08
        let size = (pointSize * scale).rounded(.toNearestOrAwayFromZero)
        if decoration.contains(.italic) {
            return decoration.contains(.regularWeight) ? NoteTheme.nunitoItalic(size) : NSFont(name: "Nunito-BoldItalic", size: size) ?? NoteTheme.nunitoItalic(size)
        }
        return decoration.contains(.regularWeight) ? NoteTheme.nunitoBold(size) : NoteTheme.nunitoExtraBold(size)
    }

    static func draw(_ icon: NoteIcon, in rect: NSRect, tint: NSColor, pointSize: CGFloat,
                     weight: NSFont.Weight = .semibold, decoration: NoteIconDecoration = []) {
        switch icon {
        case .symbol(let name):
            guard let image = symbol(name, pointSize: pointSize, weight: weight) else {
                drawText(String(name.prefix(1)).uppercased(), font: glyphFont(for: "A", pointSize: pointSize, decoration: decoration),
                         in: rect, color: tint, decoration: [])
                return
            }
            drawTemplate(image, centeredIn: rect, tint: tint)
        case .glyph(let text):
            drawText(text, font: glyphFont(for: text, pointSize: pointSize, decoration: decoration), in: rect, color: tint,
                     decoration: decoration)
        case .emoji(let text):
            drawText(text, font: NSFont.systemFont(ofSize: pointSize * 1.12), in: rect, color: nil, decoration: [])
        }
    }

    static func drawTemplate(_ image: NSImage, centeredIn rect: NSRect, tint: NSColor) {
        let size = image.size
        let target = NSRect(x: (rect.midX - size.width / 2).rounded(), y: (rect.midY - size.height / 2).rounded(),
                            width: size.width, height: size.height)
        let tinted = NSImage(size: size, flipped: false) { bounds in
            image.draw(in: bounds)
            tint.withAlphaComponent(1).set()
            bounds.fill(using: .sourceIn)
            return true
        }
        tinted.draw(in: target, from: .zero, operation: .sourceOver, fraction: tint.alphaComponent,
                    respectFlipped: true, hints: nil)
    }

    static func drawText(_ text: String, font: NSFont, in rect: NSRect, color: NSColor?, decoration: NoteIconDecoration) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if color != nil { attributes[NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String)] = true }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let flipped = NSGraphicsContext.current?.isFlipped ?? false
        let x = (rect.midX - ink.midX).rounded(.toNearestOrAwayFromZero)
        let opticalLift: CGFloat = isPrivateUse(text) ? 0 : 0.25
        let baseline = flipped ? rect.midY + ink.midY + opticalLift : rect.midY - ink.midY - opticalLift
        context.saveGState()
        if let color {
            context.setFillColor(color.cgColor)
            context.setStrokeColor(color.cgColor)
        }
        context.textMatrix = flipped ? CGAffineTransform(scaleX: 1, y: -1) : .identity
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, context)
        let thickness = max(1, (font.pointSize / 14).rounded())
        if decoration.contains(.underline) {
            let y = flipped ? baseline + thickness + 1 : baseline - thickness - 1
            context.fill(CGRect(x: x + ink.minX, y: y - thickness / 2, width: ink.width, height: thickness))
        }
        if decoration.contains(.strikethrough) {
            let middle = font.xHeight * 0.55
            let y = flipped ? baseline - middle : baseline + middle
            context.fill(CGRect(x: x + ink.minX - 1, y: y - thickness / 2, width: ink.width + 2, height: thickness))
        }
        context.restoreGState()
    }
}

@MainActor
final class NoteIconView: NSView {
    var icon: NoteIcon? { didSet { if icon != oldValue { needsDisplay = true; updateAccessibility() } } }
    var tint: NSColor = NoteTheme.menuSecondaryInk { didSet { needsDisplay = true } }
    var pointSize: CGFloat = 15 { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }
    var weight: NSFont.Weight = .semibold { didSet { needsDisplay = true } }
    var decoration: NoteIconDecoration = [] { didSet { needsDisplay = true } }
    var tileFill: NSColor? { didSet { needsDisplay = true } }
    var tileRadius: CGFloat = 5 { didSet { needsDisplay = true } }

    init(icon: NoteIcon? = nil, pointSize: CGFloat = 15) {
        self.icon = icon
        self.pointSize = pointSize
        super.init(frame: NSRect(x: 0, y: 0, width: pointSize + 6, height: pointSize + 6))
        updateAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: pointSize + 6, height: pointSize + 6) }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if let tileFill {
            tileFill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: tileRadius, yRadius: tileRadius).fill()
        }
        guard let icon else { return }
        NoteIconRenderer.draw(icon, in: bounds, tint: tint, pointSize: pointSize, weight: weight, decoration: decoration)
    }

    private func updateAccessibility() {
        setAccessibilityElement(false)
    }
}

@MainActor
enum NoteKeycapRenderer {
    enum Style { case automatic, caps, text }

    static let minimumSide: CGFloat = 19
    static let spacing: CGFloat = 3
    static let glyphPadding: CGFloat = 2
    static let baseRadius: CGFloat = 4
    static let faceRadius: CGFloat = 3
    static let faceInset: CGFloat = 1
    static let faceBottomInset: CGFloat = 2.5
    static let shade = NSColor.black.withAlphaComponent(0.1)
    static var glyphFont: NSFont { .systemFont(ofSize: 10, weight: .bold) }
    static var hintFont: NSFont { NoteTheme.codeFont(size: 11.5) }

    private static let modifierOrder: [Character] = ["⌃", "⌥", "⇧", "⌘"]
    private static let named: [String: String] = [
        "space": "⎵", "return": "↩", "enter": "↩", "tab": "TAB", "esc": "ESC", "escape": "ESC",
        "delete": "⌫", "backspace": "⌫", "up": "↑", "down": "↓", "left": "←", "right": "→",
        "cmd": "⌘", "command": "⌘", "shift": "⇧", "option": "⌥", "alt": "⌥", "ctrl": "⌃", "control": "⌃",
    ]

    static func keys(in shortcut: String) -> [String] {
        let words = shortcut.split(whereSeparator: { $0 == "+" || $0 == " " }).map(String.init)
        var modifiers: Set<Character> = []
        var rest = ""
        for word in words {
            if let mapped = named[word.lowercased()] {
                if mapped.count == 1, let character = mapped.first, modifierOrder.contains(character) {
                    modifiers.insert(character)
                } else {
                    rest += mapped
                }
                continue
            }
            for character in word {
                if modifierOrder.contains(character) { modifiers.insert(character) } else { rest.append(character) }
            }
        }
        var result = modifierOrder.filter(modifiers.contains).map(String.init)
        if !rest.isEmpty {
            if rest.count == 1 || named.values.contains(rest) {
                result.append(rest.count == 1 ? rest.uppercased() : rest)
            } else {
                result.append(contentsOf: rest.map { String($0).uppercased() })
            }
        }
        return result
    }

    static func hasModifiers(_ shortcut: String) -> Bool {
        keys(in: shortcut).contains { $0.count == 1 && modifierOrder.contains($0.first!) }
    }

    static func isNamedKey(_ shortcut: String) -> Bool {
        named[shortcut.lowercased()] != nil
    }

    static func resolvedStyle(_ style: Style, for shortcut: String) -> Style {
        guard style == .automatic else { return style }
        return hasModifiers(shortcut) || isNamedKey(shortcut) ? .caps : .text
    }

    private static func glyph(_ text: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: glyphFont, .foregroundColor: color])
    }

    static func capWidths(_ keys: [String]) -> [CGFloat] {
        keys.map { max(minimumSide, ceil(glyph($0, color: .black).size().width) + 2 * (glyphPadding + faceInset)) }
    }

    static func size(for shortcut: String, style: Style = .automatic) -> NSSize {
        guard !shortcut.isEmpty else { return .zero }
        if resolvedStyle(style, for: shortcut) == .text {
            let size = NSAttributedString(string: shortcut, attributes: [.font: hintFont]).size()
            return NSSize(width: ceil(size.width), height: minimumSide)
        }
        let widths = capWidths(keys(in: shortcut))
        return NSSize(width: widths.reduce(0, +) + spacing * CGFloat(max(0, widths.count - 1)), height: minimumSide)
    }

    static func draw(_ shortcut: String, style: Style = .automatic, in rect: NSRect, textInk: NSColor? = nil,
                     face: NSColor? = nil, base: NSColor? = nil, ink: NSColor? = nil) {
        guard !shortcut.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
        let textInk = textInk ?? NoteTheme.menuTertiaryInk
        let face = face ?? NoteTheme.keycapFace
        let base = base ?? NoteTheme.keycapBase
        let ink = ink ?? NoteTheme.keycapInk
        let flipped = NSGraphicsContext.current?.isFlipped ?? false
        if resolvedStyle(style, for: shortcut) == .text {
            let text = NSAttributedString(string: shortcut, attributes: [.font: hintFont, .foregroundColor: textInk])
            let size = text.size()
            text.draw(at: NSPoint(x: rect.maxX - ceil(size.width), y: rect.midY - size.height / 2))
            return
        }
        let keys = keys(in: shortcut)
        let widths = capWidths(keys)
        let total = widths.reduce(0, +) + spacing * CGFloat(max(0, widths.count - 1))
        var x = rect.maxX - total
        let y = (rect.midY - minimumSide / 2).rounded()
        for (index, key) in keys.enumerated() {
            let frame = CGRect(x: x, y: y, width: widths[index], height: minimumSide)
            context.saveGState()
            let basePath = CGPath(roundedRect: frame, cornerWidth: baseRadius, cornerHeight: baseRadius, transform: nil)
            context.addPath(basePath)
            context.clip()
            context.setFillColor(base.cgColor)
            context.fill(frame)
            if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                         colors: [NSColor.clear.cgColor, shade.cgColor] as CFArray, locations: [0, 1]) {
                let top = flipped ? frame.minY : frame.maxY
                let bottom = flipped ? frame.maxY : frame.minY
                context.drawLinearGradient(gradient, start: CGPoint(x: frame.midX, y: top), end: CGPoint(x: frame.midX, y: bottom), options: [])
            }
            context.restoreGState()
            let faceRect = CGRect(x: frame.minX + faceInset, y: flipped ? frame.minY + faceInset : frame.minY + faceBottomInset,
                                  width: frame.width - 2 * faceInset, height: frame.height - faceInset - faceBottomInset)
            context.addPath(CGPath(roundedRect: faceRect, cornerWidth: faceRadius, cornerHeight: faceRadius, transform: nil))
            context.setFillColor(face.cgColor)
            context.fillPath()
            let text = glyph(key, color: ink)
            let size = text.size()
            text.draw(at: NSPoint(x: (faceRect.midX - size.width / 2).rounded(), y: faceRect.midY - size.height / 2))
            x += widths[index] + spacing
        }
    }
}

@MainActor
final class NoteKeycapLabel: NSView {
    typealias Style = NoteKeycapRenderer.Style

    var shortcut: String { didSet { if shortcut != oldValue { invalidateIntrinsicContentSize(); needsDisplay = true; updateAccessibility() } } }
    var style: Style { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var textInk: NSColor = NoteTheme.menuTertiaryInk { didSet { needsDisplay = true } }

    init(_ shortcut: String = "", style: Style = .automatic) {
        self.shortcut = shortcut
        self.style = style
        super.init(frame: NSRect(origin: .zero, size: NoteKeycapRenderer.size(for: shortcut, style: style)))
        updateAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NoteKeycapRenderer.size(for: shortcut, style: style) }
    override var fittingSize: NSSize { intrinsicContentSize }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NoteKeycapRenderer.draw(shortcut, style: style, in: bounds, textInk: textInk)
    }

    private func updateAccessibility() {
        setAccessibilityElement(!shortcut.isEmpty)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(NoteKeycapLabel.spoken(shortcut))
    }

    static func spoken(_ shortcut: String) -> String {
        let names: [String: String] = ["⌃": "Control", "⌥": "Option", "⇧": "Shift", "⌘": "Command", "↩": "Return",
                                       "⎵": "Space", "⌫": "Delete", "↑": "Up Arrow", "↓": "Down Arrow",
                                       "←": "Left Arrow", "→": "Right Arrow", "TAB": "Tab", "ESC": "Escape"]
        guard NoteKeycapRenderer.hasModifiers(shortcut) else { return shortcut }
        return NoteKeycapRenderer.keys(in: shortcut).map { names[$0] ?? $0 }.joined(separator: "-")
    }
}

@MainActor
class NoteControlButton: PointingHandButton {
    private(set) var isHovered = false
    private(set) var isPressed = false
    var isChecked = false { didSet { if isChecked != oldValue { refreshFace(animated: true); setAccessibilityValue(isChecked ? "on" : nil) } } }
    var onPress: (() -> Void)?
    var cornerRadius: CGFloat = NoteTheme.controlRadius { didSet { layer?.cornerRadius = cornerRadius } }
    var pressedScale: CGFloat = NoteAnimation.pressedScale
    private var hoverArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        title = ""
        image = nil
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none
        refusesFirstResponder = true
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        NoteAnimation.observeReduceMotion(self) { [weak self] in
            guard let self, let layer = self.layer else { return }
            NoteAnimation.settle(layer)
        }
        refreshFace(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        refreshFace(animated: false)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled { isHovered = false; isPressed = false }
            alphaValue = isEnabled ? 1 : NoteTheme.disabledOpacity
            refreshFace(animated: false)
        }
    }

    func fill(hovered: Bool, pressed: Bool, checked: Bool) -> NSColor? {
        if checked { return NoteTheme.checkedFill }
        if pressed { return NoteTheme.pressedFill }
        if hovered { return NoteTheme.hoverFill }
        return nil
    }

    func ink(hovered: Bool, pressed: Bool, checked: Bool) -> NSColor {
        if checked { return NoteTheme.checkedInk }
        return hovered || pressed ? NoteTheme.menuInk : NoteTheme.menuSecondaryInk
    }

    var currentInk: NSColor { ink(hovered: isHovered, pressed: isPressed, checked: isChecked) }

    func drawContent(in bounds: NSRect, ink: NSColor) {}

    override func draw(_ dirtyRect: NSRect) {
        drawContent(in: bounds, ink: currentInk)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshFace(animated: false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshFace(animated: false)
    }

    func refreshFace(animated: Bool) {
        needsDisplay = true
        guard let layer else { return }
        let target = fill(hovered: isHovered, pressed: isPressed, checked: isChecked).map { NoteTheme.resolved($0, in: self) }
            ?? NSColor.clear.cgColor
        let from = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        NoteAnimation.withoutAnimation { layer.backgroundColor = target }
        if animated, !NoteAnimation.reduceMotion, window != nil, let from {
            let fade = NoteAnimation.basic("backgroundColor", from: from, to: target, duration: NoteAnimation.hoverDuration,
                                           curve: NoteCurve.hover)
            _ = NoteAnimation.run(fade, on: layer, key: NoteAnimation.keyPrefix + "hover")
        } else {
            NoteAnimation.settle(layer, keys: [NoteAnimation.keyPrefix + "hover"])
        }
    }

    private func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        refreshFace(animated: false)
        guard let layer else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let target = pressed ? NoteAnimation.scaleTransform(pressedScale, about: center) : CATransform3DIdentity
        NoteAnimation.spring(layer, "transform", to: NSValue(caTransform3D: target), spring: .press,
                             key: NoteAnimation.keyPrefix + "press")
    }

    private func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        refreshFace(animated: true)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea === hoverArea else { super.mouseEntered(with: event); return }
        setHovered(isEnabled && NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow))
    }

    override func mouseMoved(with event: NSEvent) {
        setHovered(isEnabled && NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow))
    }

    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea === hoverArea else { super.mouseExited(with: event); return }
        setHovered(false)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        setPressed(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        setPressed(bounds.contains(convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        let wasPressed = isPressed
        setPressed(false)
        if isEnabled && inside && wasPressed { activate() }
    }

    override func performClick(_ sender: Any?) {
        guard isEnabled else { return }
        activate()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        activate()
        return true
    }

    func activate() {
        onPress?()
        if let action { sendAction(action, to: target) }
    }

    func setToolTip(_ title: String, shortcut: String? = nil, commandID: String? = nil,
                    anchor: TooltipConfiguration.Anchor = .bottom) {
        if let commandID {
            LiveShortcutToolTip.set(self, title, commandID: commandID, anchor: anchor)
            return
        }
        let fixed = shortcut.flatMap(Self.keyboardShortcut(from:))
        parcTooltip = TooltipConfiguration(title, shortcut: fixed.map { .fixed($0) }, anchor: anchor)
        setAccessibilityHelp(shortcut.map { "\(title), \(NoteKeycapLabel.spoken($0))" } ?? title)
    }

    static func keyboardShortcut(from text: String) -> KeyboardShortcut? {
        let keys = NoteKeycapRenderer.keys(in: text)
        var flags: NSEvent.ModifierFlags = []
        var key: String?
        for part in keys {
            switch part {
            case "⌃": flags.insert(.control)
            case "⌥": flags.insert(.option)
            case "⇧": flags.insert(.shift)
            case "⌘": flags.insert(.command)
            case "↩": key = "\r"
            case "⎵": key = " "
            case "⌫": key = "\u{8}"
            case "TAB": key = "\t"
            case "ESC": key = "\u{1b}"
            default: key = part.lowercased()
            }
        }
        guard let key else { return nil }
        return KeyboardShortcut(key: key, flags: flags)
    }
}

@MainActor
final class NoteToolbarButton: NoteControlButton {
    enum Content: Hashable {
        case icon(NoteIcon)
        case text(String)
        case iconAndText(NoteIcon, String)
    }

    var content: Content { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var showsDisclosure = false { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var decoration: NoteIconDecoration = [] { didSet { needsDisplay = true } }
    var iconTint: NSColor? { didSet { needsDisplay = true } }
    var iconFill: NSColor? { didSet { needsDisplay = true } }
    var iconPointSize: CGFloat = 14 { didSet { needsDisplay = true } }

    init(_ content: Content, label: String, shortcut: String? = nil) {
        self.content = content
        super.init(frame: NSRect(origin: .zero, size: NoteTheme.toolbarButtonSize))
        setAccessibilityLabel(label)
        setToolTip(label, shortcut: shortcut)
        setFrameSize(intrinsicContentSize)
    }

    convenience init(icon: NoteIcon, label: String, shortcut: String? = nil) {
        self.init(.icon(icon), label: label, shortcut: shortcut)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var textFont: NSFont { NoteTheme.chromeFont(13.5) }

    override var intrinsicContentSize: NSSize {
        let height = NoteTheme.toolbarButtonSize.height
        let disclosure: CGFloat = showsDisclosure ? 12 : 0
        switch content {
        case .icon:
            return NSSize(width: NoteTheme.toolbarButtonSize.width + disclosure, height: height)
        case .text(let text):
            return NSSize(width: ceil(textWidth(text)) + 16 + disclosure, height: height)
        case .iconAndText(_, let text):
            return NSSize(width: ceil(textWidth(text)) + 16 + 20 + disclosure, height: height)
        }
    }

    private func textWidth(_ text: String) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: textFont]).size().width
    }

    override func drawContent(in bounds: NSRect, ink: NSColor) {
        var area = bounds
        if showsDisclosure {
            let chevronBox = NSRect(x: bounds.maxX - 16, y: bounds.minY, width: 10, height: bounds.height)
            if let chevron = NoteIconRenderer.symbol("chevron.down", pointSize: 8, weight: .bold) {
                NoteIconRenderer.drawTemplate(chevron, centeredIn: chevronBox, tint: NoteTheme.menuTertiaryInk)
            }
            area.size.width -= 12
        }
        let iconInk = isChecked ? ink : (iconTint ?? ink)
        switch content {
        case .icon(let icon):
            let box = NSRect(x: area.midX - 10, y: area.midY - 10, width: 20, height: 20)
            if let iconFill {
                iconFill.setFill()
                NSBezierPath(roundedRect: box.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
            }
            NoteIconRenderer.draw(icon, in: box, tint: iconInk, pointSize: iconPointSize, weight: .semibold, decoration: decoration)
        case .text(let text):
            drawTitle(text, in: NSRect(x: area.minX + 8, y: area.minY, width: area.width - 16, height: area.height), ink: ink)
        case .iconAndText(let icon, let text):
            let box = NSRect(x: area.minX + 6, y: area.midY - 9, width: 18, height: 18)
            NoteIconRenderer.draw(icon, in: box, tint: iconInk, pointSize: iconPointSize - 1, weight: .semibold, decoration: decoration)
            drawTitle(text, in: NSRect(x: box.maxX + 4, y: area.minY, width: area.maxX - box.maxX - 12, height: area.height), ink: ink)
        }
    }

    private func drawTitle(_ text: String, in rect: NSRect, ink: NSColor) {
        let font = textFont
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let height = ceil(font.ascender - font.descender)
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph])
            .draw(with: NSRect(x: rect.minX, y: (rect.midY - height / 2).rounded(), width: rect.width, height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

@MainActor
final class NoteChip: NoteControlButton {
    enum Style { case ghost, filled }

    var chipTitle: String { didSet { if !isFlashing { shownTitle = chipTitle } } }
    var icon: NoteIcon? { didSet { if !isFlashing { shownIcon = icon } } }
    var style: Style { didSet { refreshFace(animated: false) } }
    private var shownTitle: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true; setAccessibilityLabel(shownTitle) } }
    private var shownIcon: NoteIcon? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    private var isFlashing = false
    private var flashGeneration = 0

    init(_ title: String, icon: NoteIcon? = nil, style: Style = .ghost) {
        chipTitle = title
        self.icon = icon
        self.style = style
        shownTitle = title
        shownIcon = icon
        super.init(frame: NSRect(x: 0, y: 0, width: 80, height: NoteTheme.chipHeight))
        setAccessibilityLabel(title)
        setFrameSize(intrinsicContentSize)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var chipFont: NSFont { NoteTheme.chromeFont(12.5) }

    override var intrinsicContentSize: NSSize {
        let text = ceil(NSAttributedString(string: shownTitle, attributes: [.font: chipFont]).size().width)
        let iconWidth: CGFloat = shownIcon == nil ? 0 : 18
        return NSSize(width: text + iconWidth + 20, height: NoteTheme.chipHeight)
    }

    override func fill(hovered: Bool, pressed: Bool, checked: Bool) -> NSColor? {
        switch style {
        case .ghost: return super.fill(hovered: hovered, pressed: pressed, checked: checked)
        case .filled: return pressed ? NoteTheme.pressedFill : hovered ? NoteTheme.pressedFill : NoteTheme.chipFill
        }
    }

    override func drawContent(in bounds: NSRect, ink: NSColor) {
        var x = bounds.minX + 10
        if let shownIcon {
            NoteIconRenderer.draw(shownIcon, in: NSRect(x: x - 1, y: bounds.midY - 8, width: 16, height: 16), tint: ink,
                                  pointSize: 12, weight: .semibold)
            x += 18
        }
        let height = ceil(chipFont.ascender - chipFont.descender)
        NSAttributedString(string: shownTitle, attributes: [.font: chipFont, .foregroundColor: ink])
            .draw(with: NSRect(x: x, y: (bounds.midY - height / 2).rounded(), width: bounds.maxX - x - 8, height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    func flash(_ title: String, icon: NoteIcon? = .symbol("checkmark"), duration: TimeInterval = 1.4) {
        flashGeneration += 1
        let generation = flashGeneration
        isFlashing = true
        crossfade { self.shownTitle = title; self.shownIcon = icon }
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: title, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.flashGeneration == generation else { return }
            self.isFlashing = false
            self.crossfade { self.shownTitle = self.chipTitle; self.shownIcon = self.icon }
        }
    }

    private func crossfade(_ change: () -> Void) {
        change()
        guard let layer, !NoteAnimation.reduceMotion, window != nil else { return }
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.15
        transition.timingFunction = NoteCurve.easeOut
        layer.add(transition, forKey: NoteAnimation.keyPrefix + "flash")
        NoteAnimation.pop(layer, from: 0.96, spring: .pill, about: CGPoint(x: bounds.midX, y: bounds.midY))
    }
}

@MainActor
final class NoteSearchField: NSView {
    let textField = NSTextField()
    var onChange: ((String) -> Void)?
    var onCommand: ((Selector) -> Bool)?
    var onSubmit: ((String) -> Void)?
    var placeholder: String { didSet { refreshPlaceholder() } }
    var text: String {
        get { textField.stringValue }
        set { textField.stringValue = newValue; refreshClear() }
    }
    var showsIcon = true { didSet { needsLayout = true; icon.isHidden = !showsIcon } }

    private let icon = NoteIconView(icon: .symbol("magnifyingglass"), pointSize: 12)
    private let clear = NoteToolbarButton(icon: .symbol("xmark.circle.fill"), label: "Clear")
    private let relay = NoteSearchFieldRelay()

    init(placeholder: String = "Search…") {
        self.placeholder = placeholder
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: NoteTheme.fieldHeight))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NoteTheme.nunitoRegular(13.5)
        textField.textColor = NoteTheme.menuInk
        textField.lineBreakMode = .byTruncatingTail
        textField.usesSingleLineMode = true
        textField.cell?.isScrollable = true
        textField.cell?.wraps = false
        relay.field = self
        textField.delegate = relay
        icon.tint = NoteTheme.menuTertiaryInk
        clear.iconPointSize = 12
        clear.isHidden = true
        clear.onPress = { [weak self] in
            guard let self else { return }
            self.text = ""
            self.onChange?("")
            self.focus()
        }
        addSubview(icon)
        addSubview(textField)
        addSubview(clear)
        setAccessibilityElement(false)
        textField.setAccessibilityLabel(placeholder)
        refreshPlaceholder()
        refreshFill()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NoteTheme.fieldHeight) }

    func focus() {
        window?.makeFirstResponder(textField)
    }

    func bind(to list: NoteMenuList) {
        onChange = { [weak list] text in list?.filterText = text }
        onCommand = { [weak list] selector in list?.handle(command: selector) ?? false }
    }

    override func layout() {
        super.layout()
        let left: CGFloat = showsIcon ? 30 : 10
        icon.frame = NSRect(x: 8, y: (bounds.midY - 9).rounded(), width: 18, height: 18)
        clear.frame = NSRect(x: bounds.maxX - 28, y: (bounds.midY - 12).rounded(), width: 24, height: 24)
        let font = textField.font ?? NoteTheme.nunitoRegular(13.5)
        let height = ceil(font.ascender - font.descender) + 2
        textField.frame = NSRect(x: left, y: (bounds.midY - height / 2).rounded(), width: bounds.width - left - (clear.isHidden ? 10 : 30),
                                 height: height)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshFill()
    }

    override func mouseDown(with event: NSEvent) { focus() }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .iBeam) }

    private func refreshFill() {
        NoteAnimation.withoutAnimation { layer?.backgroundColor = NoteTheme.resolved(NoteTheme.fieldFill, in: self) }
    }

    private func refreshPlaceholder() {
        textField.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .font: textField.font ?? NoteTheme.nunitoRegular(13.5), .foregroundColor: NoteTheme.menuTertiaryInk,
        ])
        textField.setAccessibilityLabel(placeholder)
    }

    fileprivate func refreshClear() {
        let hidden = text.isEmpty
        guard clear.isHidden != hidden else { return }
        clear.isHidden = hidden
        needsLayout = true
    }

    fileprivate func editingBegan(_ editor: NSTextView?) {
        editor?.insertionPointColor = NoteTheme.caret
        editor?.selectedTextAttributes = [.backgroundColor: NoteTheme.selection]
    }

    fileprivate func textChanged() {
        refreshClear()
        onChange?(text)
    }

    fileprivate func command(_ selector: Selector) -> Bool {
        if onCommand?(selector) == true { return true }
        if selector == #selector(NSResponder.insertNewline(_:)), let onSubmit {
            onSubmit(text)
            return true
        }
        return false
    }
}

@MainActor
private final class NoteSearchFieldRelay: NSObject, NSTextFieldDelegate {
    weak var field: NoteSearchField?

    func controlTextDidBeginEditing(_ notification: Notification) {
        field?.editingBegan(notification.userInfo?["NSFieldEditor"] as? NSTextView)
    }

    func controlTextDidChange(_ notification: Notification) {
        field?.textChanged()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        field?.command(commandSelector) ?? false
    }
}
