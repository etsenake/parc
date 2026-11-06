import AppKit

///
///
/// separator stroke clipped by the same shape (one point visible inside).
@MainActor
final class SettingsGroupView: LayoutView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quinaryLabelColor.withAlphaComponent(NSColor.quinaryLabelColor.alphaComponent * 0.3).cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    func separator(at y: CGFloat) {
        let line = NSBox(frame: NSRect(x: 10, y: y, width: max(0, bounds.width - 20), height: 1))
        line.boxType = .separator; line.autoresizingMask = [.width]; addSubview(line)
    }
}

/// Passive glyph; the original native control retains input and accessibility.
@MainActor
final class SettingsSymbolBadge: NSView {
    let symbol: String
    let color: NSColor
    private let glyph: NSImageView
    init(symbol: String, color: NSColor, size: CGFloat = 20) {
        self.symbol = symbol; self.color = color
        glyph = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true; layer?.cornerRadius = 4; layer?.cornerCurve = .continuous
        glyph.symbolConfiguration = .init(pointSize: size == 24 ? 14 : 12, weight: .regular)
        glyph.contentTintColor = .white
        glyph.imageScaling = .scaleProportionallyDown
        glyph.setAccessibilityElement(false); setAccessibilityElement(false)
        addSubview(glyph); updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() { super.layout(); glyph.frame = bounds.insetBy(dx: 3, dy: 3) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = color.cgColor }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
}

///
/// glyph, native label and accent arrow, padded by five points on all sides.
@MainActor
final class SettingsCommandButton: SettingsHoverButton {
    private let badge: SettingsSymbolBadge
    private let label = NSTextField(labelWithString: "")
    private let arrow = NSImageView(image: NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil) ?? NSImage())
    private let hoverLayer = CALayer()
    var actionBlock: (() -> Void)?
    init(title: String, symbol: String, color: NSColor, action: (() -> Void)? = nil) {
        badge = SettingsSymbolBadge(symbol: symbol, color: color, size: 24)
        super.init(frame: .zero)
        self.title = title; label.stringValue = title
        actionBlock = action; target = self; self.action = #selector(invoke)
        focusRingType = .exterior
        setButtonType(.momentaryPushIn); isBordered = false
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        arrow.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        arrow.contentTintColor = .controlAccentColor
        wantsLayer = true
        hoverLayer.cornerRadius = 8; hoverLayer.cornerCurve = .continuous
        layer?.addSublayer(hoverLayer)
        [badge, label, arrow].forEach { $0.setAccessibilityElement(false); addSubview($0) }
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func invoke() { actionBlock?() }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        hoverLayer.frame = bounds
        CATransaction.commit()
        badge.frame = NSRect(x: 5, y: (bounds.height - 24) / 2, width: 24, height: 24)
        label.frame = NSRect(x: 37, y: (bounds.height - 18) / 2, width: max(0, bounds.width - 66), height: 18)
        arrow.frame = NSRect(x: max(0, bounds.width - 22), y: (bounds.height - 16) / 2, width: 16, height: 16)
    }
    override func draw(_ dirtyRect: NSRect) {
        // Native NSButton continues to track accepted clicks/keys. The original
        // onTapGesture has no separately invented pressed color or animation.
        CATransaction.begin(); CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            hoverLayer.backgroundColor = (isEnabled && isHovered ? NSColor.controlAccentColor.withAlphaComponent(0.15) : .clear).cgColor
        }
        CATransaction.commit()
        label.textColor = isEnabled ? .labelColor : .disabledControlTextColor
        [badge, label, arrow].forEach { $0.alphaValue = isEnabled ? 1 : 0.25 }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point) == nil ? nil : self
    }
    override func accessibilityChildren() -> [Any]? { [] }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill() }
    override var focusRingMaskBounds: NSRect { bounds }
}

@MainActor
final class SettingsProfileCell: NSTableCellView {
    let name = NSTextField(labelWithString: "")
    let count = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        name.font = .systemFont(ofSize: 13); name.lineBreakMode = .byTruncatingTail
        count.font = .systemFont(ofSize: 11); count.textColor = .secondaryLabelColor; count.alignment = .right
        addSubview(name); addSubview(count); textField = name
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        name.frame = NSRect(x: 14, y: (bounds.height - 18) / 2, width: max(0, bounds.width - 84), height: 18)
        count.frame = NSRect(x: max(14, bounds.width - 70), y: (bounds.height - 16) / 2, width: 56, height: 16)
    }
}

///
///
/// not the bright source-list selection.
@MainActor
final class SettingsProfileRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 4), xRadius: 8, yRadius: 8).fill()
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

///
/// fill (black 15% light, near-white 7% dark), 6-point corners and the
/// PreferencesButtonForegroundColor title.
@MainActor
final class SettingsPillButton: NSButton {
    /// PreferencesLoadableButtonBackgroundColor (white; white 15% dark), used
    /// on the default-browser banner.
    private let loadable: Bool
    init(title: String, symbol: String? = nil, loadable: Bool = false) {
        self.loadable = loadable
        super.init(frame: .zero)
        self.title = title; isBordered = false; focusRingType = .exterior
        setButtonType(.momentaryPushIn)
        font = .systemFont(ofSize: 13)
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            imagePosition = .imageLeading; imageHugsTitle = true
        }
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    var fittingWidth: CGFloat { ceil(attributedTitle.size().width) + (image == nil ? 20 : 37) }
    override var isEnabled: Bool { didSet { updateColors() } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    private func updateColors() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let ink = dark ? NSColor(srgbRed: 0.878, green: 0.875, blue: 0.878, alpha: 1)
            : NSColor(srgbRed: 0.373, green: 0.373, blue: 0.373, alpha: 1)
        contentTintColor = ink.withAlphaComponent(isEnabled ? 1 : 0.4)
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: font ?? .systemFont(ofSize: 13), .foregroundColor: ink.withAlphaComponent(isEnabled ? 1 : 0.4)])
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        var fill = loadable ? NSColor(white: 1, alpha: dark ? 0.15 : 1)
            : dark ? NSColor(srgbRed: 0.878, green: 0.875, blue: 0.878, alpha: 0.07) : NSColor(white: 0, alpha: 0.15)
        if cell?.isHighlighted == true { fill = fill.withAlphaComponent(fill.alphaComponent * 2) }
        fill.setFill()
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        shape.fill()
        // White on the white banner needs an edge to read as a button.
        if loadable && !dark { NSColor.separatorColor.setStroke(); shape.stroke() }
        super.draw(dirtyRect)
    }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill() }
    override var focusRingMaskBounds: NSRect { bounds }
}
