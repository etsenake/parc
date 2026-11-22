import AppKit
import QuartzCore
import ParcKit

enum SidebarPreviewMetrics {
    static let width: CGFloat = 288, minimumWidth: CGFloat = 240, maximumHeight: CGFloat = 384, header: CGFloat = 56
    static let windowInset: CGFloat = 18, gap: CGFloat = 4, hoverExtension: CGFloat = 40
    static let cornerRadius: CGFloat = 14, pictureInset: CGFloat = 10, listInset: CGFloat = 5, scale: CGFloat = 0.8
    static let duration: CFTimeInterval = 0.1
}

enum SidebarPreviewLocation { case right, diagonal }

struct SidebarPreviewPlacement: Equatable {
    var row: NSRect
    var location: SidebarPreviewLocation

    private var x: CGFloat { location == .right ? row.maxX + SidebarPreviewMetrics.gap : row.maxX - SidebarPreviewMetrics.gap }
    func width(hostWidth: CGFloat) -> CGFloat {
        max(SidebarPreviewMetrics.minimumWidth, min(SidebarPreviewMetrics.width, hostWidth - SidebarPreviewMetrics.windowInset - x))
    }
    func frame(width: CGFloat, height: CGFloat, hostHeight: CGFloat) -> NSRect {
        let inset = SidebarPreviewMetrics.windowInset
        let height = min(height, SidebarPreviewMetrics.maximumHeight, max(0, hostHeight - 2 * inset))
        let y = location == .right ? row.midY - height / 2 : row.maxY - SidebarPreviewMetrics.gap
        return NSRect(x: x, y: min(max(inset, y), max(inset, hostHeight - inset - height)), width: width, height: height)
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
public class SidebarPreviewSurface: NSView, Sendable {
    var placement = SidebarPreviewPlacement(row: .zero, location: .right)
    var onHover: ((Bool) -> Void)?
    var fill: NSColor? { didSet { updateColors() } }
    let content: NSView = SidebarPreviewClipView()
    private(set) var isRetired = false
    private let popover = PopoverBackgroundView(blending: .withinWindow)
    private let background = NSView()
    private var hoverArea: NSTrackingArea?
    private var motionAnchor: NSPoint?
    var reducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var commitsExit: (_ animations: () -> Void, _ completion: @escaping @Sendable () -> Void) -> Void = { animations, completion in
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        animations()
        CATransaction.commit()
    }
    public override var isFlipped: Bool { true }
    func preferredHeight(width: CGFloat) -> CGFloat { SidebarPreviewMetrics.maximumHeight }
    var hoverFrame: NSRect {
        NSRect(x: frame.minX - SidebarPreviewMetrics.hoverExtension, y: frame.minY,
               width: frame.width + SidebarPreviewMetrics.hoverExtension, height: frame.height)
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.4); shadow.shadowBlurRadius = 19
        shadow.shadowOffset = NSSize(width: 0, height: 6)
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
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func layout() {
        super.layout()
        content.frame = bounds; popover.frame = content.bounds; background.frame = popover.bounds
        let radius = SidebarPreviewMetrics.cornerRadius
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
    public override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            background.layer?.backgroundColor = fill?.cgColor
        }
    }
    func place() {
        guard let host = superview else { return }
        let width = placement.width(hostWidth: host.bounds.width)
        frame = placement.frame(width: width, height: preferredHeight(width: width), hostHeight: host.bounds.height)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        hoverArea = nil
        guard !isRetired else { return }
        let rect = NSRect(x: -SidebarPreviewMetrics.hoverExtension, y: 0,
                          width: bounds.width + SidebarPreviewMetrics.hoverExtension, height: bounds.height)
        let area = NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    public override func mouseEntered(with event: NSEvent) {
        if event.trackingArea === hoverArea { onHover?(true) } else { super.mouseEntered(with: event) }
    }
    public override func mouseExited(with event: NSEvent) {
        if event.trackingArea === hoverArea { onHover?(false) } else { super.mouseExited(with: event) }
    }
    public override func mouseDown(with event: NSEvent) {}
    public override func rightMouseDown(with event: NSEvent) {}
    public override func hitTest(_ point: NSPoint) -> NSView? { isRetired ? nil : super.hitTest(point) }

    func retire() {
        isRetired = true; onHover = nil
        if let hoverArea { removeTrackingArea(hoverArea) }
        hoverArea = nil
    }

    func animateIn(from anchor: NSPoint, duration: CFTimeInterval = SidebarPreviewMetrics.duration) {
        motionAnchor = anchor
        guard let layer else { return }
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0; opacity.toValue = 1
        var animations = [opacity]
        if !reducesMotion() {
            let transform = CABasicAnimation(keyPath: "transform")
            transform.fromValue = NSValue(caTransform3D: scaled(about: anchor))
            transform.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            animations.append(transform)
        }
        for animation in animations {
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: animation.keyPath)
        }
    }

    func animateOut(duration: CFTimeInterval = SidebarPreviewMetrics.duration, completion: @escaping @MainActor () -> Void) {
        let presented = layer?.presentation()
        let opacity = presented?.opacity ?? layer?.opacity ?? 0
        guard let layer, opacity > 0 else { removeFromSuperview(); completion(); return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacity; fade.toValue = 0
        var animations = [fade]
        if !reducesMotion() {
            let transform = CABasicAnimation(keyPath: "transform")
            transform.fromValue = NSValue(caTransform3D: presented?.transform ?? layer.transform)
            transform.toValue = NSValue(caTransform3D: scaled(about: motionAnchor ?? NSPoint(x: 0, y: bounds.height / 2)))
            animations.append(transform)
        }
        commitsExit({
            for animation in animations {
                animation.duration = duration * CFTimeInterval(opacity)
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animation.fillMode = .forwards; animation.isRemovedOnCompletion = false
                layer.add(animation, forKey: animation.keyPath)
            }
        }, { [weak self] in
            MainActor.assumeIsolated { self?.removeFromSuperview(); completion() }
        })
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
    static let iconSize: CGFloat = 16, top: CGFloat = 6, bottom: CGFloat = 8, leading: CGFloat = 10, trailing: CGFloat = 8
    static let height = top + line(titleFont) + line(subtitleFont) + bottom
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
        let titleHeight = Self.line(Self.titleFont), text = hasIcon ? Self.leading + Self.iconSize + 8 : Self.leading
        let width = max(0, bounds.width - text - Self.trailing)
        icon.frame = NSRect(x: Self.leading, y: Self.top + (bounds.height - Self.top - Self.bottom - Self.iconSize) / 2,
                            width: Self.iconSize, height: Self.iconSize)
        titleLabel.frame = NSRect(x: text, y: Self.top, width: width, height: titleHeight)
        subtitle.frame = NSRect(x: text, y: Self.top + titleHeight, width: width, height: Self.line(Self.subtitleFont))
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
