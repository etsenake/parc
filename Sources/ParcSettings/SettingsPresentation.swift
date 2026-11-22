import AppKit
import ParcKit

enum SettingsLayout {
    static let sidebarWidth: CGFloat = 196
    static let sidebarRowHeight: CGFloat = 28
    static let sidebarMemberRowHeight: CGFloat = 40
    static let sidebarFontSize: CGFloat = 14
    static let margin: CGFloat = 20
    static let groupWidth: CGFloat = 556
    static let contentWidth: CGFloat = groupWidth + margin * 2
    static let contentHeight: CGFloat = 562
    static let rowHeight: CGFloat = 42
    static let noteRowHeight: CGFloat = 56
    static let rowInset: CGFloat = 12
    static let groupRadius: CGFloat = 12
    static let groupSpacing: CGFloat = 16
    static let headingSpacing: CGFloat = 50
    static let headingHeight: CGFloat = 17
    static let headingGap: CGFloat = 7
    static let buttonHeight: CGFloat = 24
}

@MainActor
final class SettingsGroupView: LayoutView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = SettingsLayout.groupRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(dark ? 0.045 : 0.032).cgColor
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    func separator(at y: CGFloat) {
        let inset = SettingsLayout.rowInset
        let line = NSBox(frame: NSRect(x: inset, y: y, width: max(0, bounds.width - inset * 2), height: 1))
        line.boxType = .separator; line.autoresizingMask = [.width]; addSubview(line)
    }
}

@MainActor
final class SettingsSectionHeading: NSTextField {
    convenience init(title: String) {
        self.init(labelWithString: title)
        font = .systemFont(ofSize: 13, weight: .semibold)
        textColor = .labelColor
        lineBreakMode = .byTruncatingTail
        setAccessibilityRole(.staticText)
    }
}

@MainActor
final class SettingsSymbolBadge: NSView {
    let symbol: String
    let color: NSColor
    private let glyph: NSImageView
    init(symbol: String, color: NSColor, size: CGFloat = 20) {
        self.symbol = symbol; self.color = color
        glyph = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true; layer?.cornerRadius = (size * 0.26).rounded(); layer?.cornerCurve = .continuous
        glyph.symbolConfiguration = .init(pointSize: (size * 0.58).rounded(), weight: .medium)
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

@MainActor
class SettingsRowButton: SettingsHoverButton {
    private let pressLayer = CALayer()
    var actionBlock: (() -> Void)?
    init(title: String, action: (() -> Void)?) {
        super.init(frame: .zero)
        self.title = title
        actionBlock = action; target = self; self.action = #selector(invoke)
        focusRingType = .exterior
        setButtonType(.momentaryPushIn); isBordered = false
        wantsLayer = true
        pressLayer.cornerRadius = 8; pressLayer.cornerCurve = .continuous
        layer?.addSublayer(pressLayer)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func invoke() { actionBlock?() }
    var passiveViews: [NSView] { [] }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        pressLayer.frame = bounds.insetBy(dx: 4, dy: 3)
        CATransaction.commit()
    }
    override func draw(_ dirtyRect: NSRect) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            pressLayer.backgroundColor = (isEnabled && cell?.isHighlighted == true ? NSColor.labelColor.withAlphaComponent(0.06) : .clear).cgColor
        }
        CATransaction.commit()
        passiveViews.forEach { $0.alphaValue = isEnabled ? 1 : 0.25 }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point) == nil ? nil : self
    }
    override func accessibilityChildren() -> [Any]? { [] }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 3), xRadius: 8, yRadius: 8).fill() }
    override var focusRingMaskBounds: NSRect { bounds }
}

@MainActor
final class SettingsCommandButton: SettingsRowButton {
    private let badge: SettingsSymbolBadge
    private let label = NSTextField(labelWithString: "")
    private let arrow = NSImageView(image: NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: nil) ?? NSImage())
    init(title: String, symbol: String, color: NSColor, action: (() -> Void)? = nil) {
        badge = SettingsSymbolBadge(symbol: symbol, color: color)
        super.init(title: title, action: action)
        label.stringValue = title
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        arrow.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        arrow.contentTintColor = .secondaryLabelColor
        [badge, label, arrow].forEach { $0.setAccessibilityElement(false); addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var passiveViews: [NSView] { [badge, label, arrow] }
    override func layout() {
        super.layout()
        let inset = SettingsLayout.rowInset
        badge.frame = NSRect(x: inset, y: (bounds.height - 20) / 2, width: 20, height: 20)
        label.frame = NSRect(x: inset + 30, y: (bounds.height - 17) / 2, width: max(0, bounds.width - inset * 2 - 56), height: 17)
        arrow.frame = NSRect(x: max(0, bounds.width - inset - 14), y: (bounds.height - 14) / 2, width: 14, height: 14)
    }
    override func draw(_ dirtyRect: NSRect) {
        label.textColor = isEnabled ? .labelColor : .disabledControlTextColor
        super.draw(dirtyRect)
    }
}

@MainActor
final class SettingsSpaceButton: SettingsRowButton {
    let name = NSTextField(labelWithString: "")
    let detail = NSTextField(labelWithString: "")
    let iconImage = NSImageView()
    let iconEmoji = NSTextField(labelWithString: "")
    private let chevron = NSImageView(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage())
    init(action: (() -> Void)? = nil) {
        super.init(title: "", action: action)
        name.font = .systemFont(ofSize: 13); name.lineBreakMode = .byTruncatingTail
        detail.font = .systemFont(ofSize: 13); detail.textColor = .secondaryLabelColor
        detail.alignment = .right; detail.lineBreakMode = .byTruncatingTail
        iconImage.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        iconImage.contentTintColor = .secondaryLabelColor
        iconEmoji.font = .systemFont(ofSize: 14); iconEmoji.alignment = .center
        chevron.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        chevron.contentTintColor = .tertiaryLabelColor
        [iconImage, iconEmoji, name, detail, chevron].forEach { $0.setAccessibilityElement(false); addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var passiveViews: [NSView] { [iconImage, iconEmoji, name, detail, chevron] }
    func update(name value: String, detail note: String, image: NSImage? = nil, emoji: String? = nil) {
        name.stringValue = value; detail.stringValue = note
        iconEmoji.stringValue = emoji ?? ""
        iconEmoji.isHidden = emoji == nil
        iconImage.image = emoji == nil ? image : nil
        iconImage.isHidden = iconImage.image == nil
        title = value
        setAccessibilityLabel(note.isEmpty ? value : value + ", " + note)
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let inset = SettingsLayout.rowInset
        let hasIcon = !iconImage.isHidden || !iconEmoji.isHidden
        let iconSlot = NSRect(x: inset, y: (bounds.height - 20) / 2, width: 20, height: 20)
        iconImage.frame = iconSlot
        iconEmoji.frame = NSRect(x: iconSlot.minX, y: (bounds.height - 18) / 2, width: 20, height: 18)
        let nameX = hasIcon ? iconSlot.maxX + 8 : inset
        let chevronX = max(0, bounds.width - inset - 10)
        let detailWidth = detail.stringValue.isEmpty ? 0 : min(ceil(detail.intrinsicContentSize.width) + 6, 160)
        let detailX = max(nameX, chevronX - 10 - detailWidth)
        chevron.frame = NSRect(x: chevronX, y: (bounds.height - 14) / 2, width: 10, height: 14)
        detail.frame = NSRect(x: detailX, y: (bounds.height - 17) / 2, width: detailWidth, height: 17)
        name.frame = NSRect(x: nameX, y: (bounds.height - 17) / 2, width: max(0, detailX - nameX - 12), height: 17)
    }
    override func draw(_ dirtyRect: NSRect) {
        name.textColor = isEnabled ? .labelColor : .disabledControlTextColor
        super.draw(dirtyRect)
    }
}

@MainActor
final class SettingsPillButton: PointingHandButton {
    private let loadable: Bool
    var destructive = false { didSet { updateColors() } }
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
    var fittingWidth: CGFloat { ceil(attributedTitle.size().width) + (image == nil ? 24 : 41) }
    func setLabel(_ value: String) {
        guard value != title else { return }
        title = value; updateColors()
    }
    override var isEnabled: Bool { didSet { updateColors() } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    private func updateColors() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let base = destructive ? NSColor.systemRed : dark ? NSColor(srgbRed: 0.878, green: 0.875, blue: 0.878, alpha: 1)
            : NSColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        let ink = base.withAlphaComponent(isEnabled ? 1 : 0.4)
        contentTintColor = ink
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: font ?? .systemFont(ofSize: 13), .foregroundColor: ink])
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        var fill = loadable ? NSColor(white: 1, alpha: dark ? 0.15 : 1)
            : dark ? NSColor(white: 1, alpha: 0.09) : NSColor(white: 0, alpha: 0.06)
        if cell?.isHighlighted == true { fill = fill.withAlphaComponent(fill.alphaComponent * 2) }
        fill.setFill()
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        shape.fill()
        if loadable && !dark { NSColor.separatorColor.setStroke(); shape.stroke() }
        super.draw(dirtyRect)
    }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill() }
    override var focusRingMaskBounds: NSRect { bounds }
}
