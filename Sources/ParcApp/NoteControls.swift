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

    static func resolvedStyle(_ style: Style, for shortcut: String) -> Style {
        guard style == .automatic else { return style }
        return hasModifiers(shortcut) ? .caps : .text
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
