import AppKit
import QuartzCore

enum SidebarPreviewMetrics {
    static let width: CGFloat = 240, maximumHeight: CGFloat = 320, header: CGFloat = 48
    static let windowInset: CGFloat = 18, gap: CGFloat = 4, hoverExtension: CGFloat = 40
    static let cornerRadius: CGFloat = 12, scale: CGFloat = 0.8
    static let duration: CFTimeInterval = 0.1
}

enum SidebarPreviewLocation { case right, diagonal }

struct SidebarPreviewPlacement: Equatable {
    var row: NSRect
    var location: SidebarPreviewLocation

    func frame(height: CGFloat, hostHeight: CGFloat) -> NSRect {
        let inset = SidebarPreviewMetrics.windowInset, gap = SidebarPreviewMetrics.gap
        let height = min(height, SidebarPreviewMetrics.maximumHeight, max(0, hostHeight - 2 * inset))
        let x = location == .right ? row.maxX + gap : row.maxX - gap
        let y = location == .right ? row.midY - height / 2 : row.maxY - gap
        return NSRect(x: x, y: min(max(inset, y), max(inset, hostHeight - inset - height)),
                      width: SidebarPreviewMetrics.width, height: height)
    }
    var anchor: NSPoint { NSPoint(x: row.maxX, y: location == .right ? row.midY : row.maxY) }
}

enum SidebarPreviewAim {
    static let reach: CGFloat = 478
    static func keepsCurrent(from last: NSPoint, to point: NSPoint, location: SidebarPreviewLocation) -> Bool {
        switch location {
        case .right:
            guard last.x < point.x else { return false }
            if point.y == last.y { return true }
            return abs(Float(point.y - last.y) / Float(point.x - last.x)) <= 3 && point.x < reach
        case .diagonal:
            return last.x <= point.x && last.y >= point.y && point.x < reach
        }
    }
}

enum SidebarPreviewHighlight {
    static func opacity(hovered: Bool, focused: Bool) -> CGFloat {
        hovered && focused ? 0.16 : hovered != focused ? 0.08 : 0
    }
}

@MainActor
class SidebarPreviewSurface: NSView {
    var placement = SidebarPreviewPlacement(row: .zero, location: .right)
    var onHover: ((Bool) -> Void)?
    var fill: NSColor? { didSet { updateColors() } }
    let content: NSView = SidebarPreviewClipView()
    private(set) var isRetired = false
    private let popover = PopoverBackgroundView(blending: .withinWindow)
    private let background = NSView()
    private var hoverArea: NSTrackingArea?
    private var motionAnchor: NSPoint?
    override var isFlipped: Bool { true }
    var preferredHeight: CGFloat { SidebarPreviewMetrics.maximumHeight }
    var hoverFrame: NSRect {
        NSRect(x: frame.minX - SidebarPreviewMetrics.hoverExtension, y: frame.minY,
               width: frame.width + SidebarPreviewMetrics.hoverExtension, height: frame.height)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.4); shadow.shadowBlurRadius = 16
        shadow.shadowOffset = NSSize(width: 0, height: 5)
        self.shadow = shadow
        content.wantsLayer = true
        content.layer?.cornerRadius = SidebarPreviewMetrics.cornerRadius; content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true
        popover.cornerRadius = SidebarPreviewMetrics.cornerRadius
        background.wantsLayer = true
        content.addSubview(popover); popover.addSubview(background, positioned: .above, relativeTo: popover.wash)
        addSubview(content)
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        content.frame = bounds; popover.frame = content.bounds; background.frame = popover.bounds
        let radius = SidebarPreviewMetrics.cornerRadius
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            background.layer?.backgroundColor = fill?.cgColor
        }
    }
    func place() {
        guard let host = superview else { return }
        frame = placement.frame(height: preferredHeight, hostHeight: host.bounds.height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        hoverArea = nil
        guard !isRetired else { return }
        let rect = NSRect(x: -SidebarPreviewMetrics.hoverExtension, y: 0,
                          width: bounds.width + SidebarPreviewMetrics.hoverExtension, height: bounds.height)
        let area = NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea === hoverArea { onHover?(true) } else { super.mouseEntered(with: event) }
    }
    override func mouseExited(with event: NSEvent) {
        if event.trackingArea === hoverArea { onHover?(false) } else { super.mouseExited(with: event) }
    }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func hitTest(_ point: NSPoint) -> NSView? { isRetired ? nil : super.hitTest(point) }

    func retire() {
        isRetired = true; onHover = nil
        if let hoverArea { removeTrackingArea(hoverArea) }
        hoverArea = nil
    }

    func animateIn(from anchor: NSPoint, duration: CFTimeInterval = SidebarPreviewMetrics.duration) {
        motionAnchor = anchor
        guard let layer else { return }
        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: scaled(about: anchor))
        transform.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0; opacity.toValue = 1
        for animation in [transform, opacity] {
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: animation.keyPath)
        }
    }

    func animateOut(duration: CFTimeInterval = SidebarPreviewMetrics.duration, completion: @escaping @MainActor () -> Void) {
        let presented = layer?.presentation()
        let opacity = presented?.opacity ?? layer?.opacity ?? 0
        guard let layer, opacity > 0 else { removeFromSuperview(); completion(); return }
        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: presented?.transform ?? layer.transform)
        transform.toValue = NSValue(caTransform3D: scaled(about: motionAnchor ?? NSPoint(x: 0, y: bounds.height / 2)))
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacity; fade.toValue = 0
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated { self?.removeFromSuperview(); completion() }
        }
        for animation in [transform, fade] {
            animation.duration = duration * CFTimeInterval(opacity)
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.fillMode = .forwards; animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: animation.keyPath)
        }
        CATransaction.commit()
    }

    private func scaled(about point: NSPoint) -> CATransform3D {
        guard let layer else { return CATransform3DIdentity }
        let x = point.x - layer.anchorPoint.x * bounds.width, y = point.y - layer.anchorPoint.y * bounds.height
        let scale = SidebarPreviewMetrics.scale
        return CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(x, y, 0), scale, scale, 1), -x, -y, 0)
    }
}

private final class SidebarPreviewClipView: NSView {
    override var isFlipped: Bool { true }
}

final class SidebarPreviewItemView: NSTableCellView {
    static let titleFont = NSFont.systemFont(ofSize: 13), subtitleFont = NSFont.systemFont(ofSize: 11)
    static let iconSize: CGFloat = 16
    static let height = 5 + line(titleFont) + line(subtitleFont) + 7
    private static func line(_ font: NSFont) -> CGFloat { ceil(NSLayoutManager().defaultLineHeight(for: font)) }
    private let icon = NSImageView()
    private let hasIcon: Bool
    let titleLabel = NSTextField(labelWithString: "")
    let subtitle = NSTextField(labelWithString: "")
    var image: NSImage? { didSet { icon.image = image ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil) } }
    override var isFlipped: Bool { true }

    init(row: SidebarPreviewRow, title: NSColor, secondary: NSColor, now: Date = Date()) {
        hasIcon = row.hasIcon
        super.init(frame: .zero)
        titleLabel.stringValue = row.title.isEmpty ? row.url.absoluteString : row.title
        titleLabel.font = Self.titleFont; titleLabel.textColor = title
        let detail = row.subtitle(now: now)
        subtitle.stringValue = detail.isEmpty ? row.url.host ?? row.url.absoluteString : detail
        subtitle.font = row.isBadged ? .boldSystemFont(ofSize: 11) : Self.subtitleFont; subtitle.textColor = secondary
        for label in [titleLabel, subtitle] { label.lineBreakMode = .byTruncatingTail; label.maximumNumberOfLines = 1; addSubview(label) }
        icon.imageScaling = .scaleProportionallyUpOrDown; icon.contentTintColor = secondary
        if hasIcon { addSubview(icon); image = nil }
        setAccessibilityElement(true); setAccessibilityRole(.staticText)
        setAccessibilityLabel(titleLabel.stringValue + ", " + subtitle.stringValue)
        toolTip = row.url.absoluteString
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        let titleHeight = Self.line(Self.titleFont), text = hasIcon ? 8 + Self.iconSize + 8 : 8
        let width = max(0, bounds.width - text - 8)
        icon.frame = NSRect(x: 8, y: 5 + (bounds.height - 12 - Self.iconSize) / 2, width: Self.iconSize, height: Self.iconSize)
        titleLabel.frame = NSRect(x: text, y: 5, width: width, height: titleHeight)
        subtitle.frame = NSRect(x: text, y: 5 + titleHeight, width: width, height: Self.line(Self.subtitleFont))
    }
}

final class SidebarPreviewRowView: NSTableRowView {
    var highlight: NSColor = .labelColor { didSet { needsDisplay = true } }
    var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
    var isFocused = false { didSet { if isFocused != oldValue { needsDisplay = true } } }
    var highlightOpacity: CGFloat { SidebarPreviewHighlight.opacity(hovered: isHovered, focused: isFocused) }
    override var isFlipped: Bool { true }
    override func drawSelection(in dirtyRect: NSRect) {}
    override func drawBackground(in dirtyRect: NSRect) {
        guard highlightOpacity > 0 else { return }
        highlight.withAlphaComponent(highlightOpacity).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 0.5), xRadius: 4, yRadius: 4).fill()
    }
}
