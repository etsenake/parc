import AppKit
import QuartzCore

enum ExtensionControlStyle {
    case sidebar, toolbar
    var surfaceSize: NSSize {
        self == .sidebar ? NSSize(width: 28, height: 28) : NSSize(width: 32, height: 24)
    }
    var cornerRadius: CGFloat { self == .sidebar ? 9 : 6 }
    static let iconSize: CGFloat = 16
    static let iconCanvas: CGFloat = 32
}

private final class ExtensionActionButtonCell: NSButtonCell {
    override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {
        super.highlight(flag, withFrame: cellFrame, in: controlView)
        (controlView as? ExtensionActionButton)?.nativeHighlight(flag)
    }
    override func imageRect(forBounds rect: NSRect) -> NSRect {
        let canvas = ExtensionControlStyle.iconCanvas
        let side = image?.size == NSSize(width: canvas, height: canvas) ? canvas
            : min(ExtensionControlStyle.iconSize, max(0, min(rect.width, rect.height)))
        return NSRect(x: (rect.midX - side / 2).rounded(.down), y: (rect.midY - side / 2).rounded(.down),
                      width: side, height: side)
    }
}

@MainActor
struct ExtensionControlItem {
    let identifier: String
    let name: String
    let tooltip: String
    let accessibilityLabel: String
    let image: NSImage?
    let pinnedIndex: Int?
    let canChangePin: Bool
    let execute: () -> Void
    let showContextMenu: (_ control: NSView) -> Void
    let setPinned: (Bool) -> Void
    var pinnedArtwork: ExtensionPinnedArtwork? = nil
    var badgeText = ""
}

struct ExtensionActionBadge: Equatable {
    let text: String
    let textColor: NSColor
    let backgroundColor: NSColor
}

struct ExtensionPinnedArtwork {
    let image: NSImage
    let badge: ExtensionActionBadge?

    init?(unbadged: NSImage?, badgeText: String, textColor: NSColor?, backgroundColor: NSColor?) {
        guard let unbadged else { return nil }
        if badgeText.isEmpty {
            badge = nil
        } else {
            guard let textColor, let backgroundColor else { return nil }
            badge = ExtensionActionBadge(text: badgeText, textColor: textColor, backgroundColor: backgroundColor)
        }
        image = unbadged
    }
}

enum ExtensionActionBadgeMetrics {
    static let height: CGFloat = 11
    static let overhang: CGFloat = 4
    static let horizontalPadding: CGFloat = 2.5
    static let maxWidth: CGFloat = 26
    static let font = NSFont.systemFont(ofSize: 8, weight: .bold)

    static func width(for text: String) -> CGFloat {
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        return min(maxWidth, max(height, (textWidth + horizontalPadding * 2).rounded(.up)))
    }
    static func frame(text: String, in bounds: NSRect) -> NSRect {
        let icon = ExtensionControlStyle.iconSize
        let iconMinY = (bounds.midY - icon / 2).rounded(.down)
        let iconMaxX = (bounds.midX - icon / 2).rounded(.down) + icon
        let width = width(for: text)
        return NSRect(x: iconMaxX + overhang - width, y: iconMinY - overhang, width: width, height: height)
    }
}

@MainActor final class ExtensionActionBadgeView: NSView {
    var badge: ExtensionActionBadge? {
        didSet { if badge != oldValue { needsDisplay = true }; isHidden = badge == nil }
    }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        guard let badge else { return }
        let radius = bounds.height / 2
        badge.backgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        let font = ExtensionActionBadgeMetrics.font
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: badge.textColor]
        let text = badge.text as NSString
        let width = text.size(withAttributes: attributes).width
        let baseline = ((bounds.height + font.capHeight) / 2).rounded()
        NSGraphicsContext.saveGraphicsState()
        bounds.insetBy(dx: ExtensionActionBadgeMetrics.horizontalPadding / 2, dy: 0).clip()
        text.draw(at: NSPoint(x: max(ExtensionActionBadgeMetrics.horizontalPadding, (bounds.width - width) / 2),
                              y: baseline - font.ascender), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }
}

@MainActor
final class ExtensionActionButton: PointingHandButton {
    let style: ExtensionControlStyle
    private var invokeAction: (() -> Void)?
    private var contextAction: ((NSView) -> Void)?
    private var mouseDownAction: (() -> Void)?
    private var trackingMouseDown = false
    private var trackingArea: NSTrackingArea?
    private var hovered = false
    private var pressed = false
    private var keyObserver: NSObjectProtocol?
    private let badgeView = ExtensionActionBadgeView()
    var badgeFrame: NSRect? { badgeView.isHidden ? nil : badgeView.frame }

    init(item: ExtensionControlItem, style: ExtensionControlStyle = .sidebar) {
        self.style = style
        super.init(frame: .zero)
        cell = ExtensionActionButtonCell()
        (cell as? NSButtonCell)?.highlightsBy = []
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        target = self
        action = #selector(invoke)
        wantsLayer = true
        layer?.cornerRadius = style.cornerRadius
        clipsToBounds = false
        focusRingType = .exterior
        addSubview(badgeView)
        update(item)
    }
    override func layout() {
        super.layout()
        if let badge = badgeView.badge {
            var frame = ExtensionActionBadgeMetrics.frame(text: badge.text, in: bounds)
            if !isFlipped { frame.origin.y = bounds.height - frame.maxY }
            badgeView.frame = frame
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) } }

    func update(_ item: ExtensionControlItem) {
        title = item.name
        LiveShortcutToolTip.set(self, item.tooltip.isEmpty ? item.name : item.tooltip)
        image = item.pinnedArtwork?.image ?? item.image
            ?? NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil)
        imagePosition = .imageOnly
        badgeView.badge = item.pinnedArtwork?.badge
        needsLayout = true
        invokeAction = item.execute
        contextAction = item.showContextMenu
        isEnabled = true
        setAccessibilityLabel(item.accessibilityLabel.isEmpty ? item.name : item.accessibilityLabel)
        setAccessibilityValue(item.badgeText.isEmpty ? nil : item.badgeText)
        setAccessibilityIdentifier("extension-action-" + item.identifier)
        updateHighlight()
    }

    func invalidate() {
        invokeAction = nil
        mouseDownAction = nil
        contextAction = nil
        isEnabled = false
        cancelInteraction()
    }

    private var available: Bool { isEnabled && invokeAction != nil && window != nil && !isHiddenOrHasHiddenAncestor }

    @objc private func invoke() {
        guard available else { return }
        let perform = trackingMouseDown ? mouseDownAction : invokeAction
        perform?()
    }
    override func accessibilityPerformPress() -> Bool {
        guard available else { return false }
        invoke()
        return true
    }
    override func accessibilityPerformShowMenu() -> Bool {
        guard available, let perform = contextAction else { return false }
        cancelInteraction()
        perform(self)
        return true
    }
    override func isAccessibilityEnabled() -> Bool { available }
    override func rightMouseDown(with event: NSEvent) {
        guard available else { return }
        cancelInteraction()
        let perform = contextAction
        perform?(self)
    }
    override func mouseDown(with event: NSEvent) {
        guard available else { return }
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
        } else {
            mouseDownAction = invokeAction
            trackingMouseDown = true
            defer { trackingMouseDown = false; mouseDownAction = nil; setPressed(false) }
            super.mouseDown(with: event)
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
        hovered = available && window?.isKeyWindow == true && window.map {
            let point = $0.mouseLocationOutsideOfEventStream
            return bounds.contains(convert(point, from: nil)) && isTopmost(atWindowPoint: point)
        } == true
        updateHighlight()
    }
    override func mouseEntered(with event: NSEvent) { hovered = isTopmost(atWindowPoint: event.locationInWindow); updateHighlight() }
    override func mouseMoved(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { super.mouseMoved(with: event); return }
        let value = isTopmost(atWindowPoint: event.locationInWindow)
        guard value != hovered else { return }
        hovered = value; updateHighlight()
    }
    override func mouseExited(with event: NSEvent) { hovered = false; updateHighlight() }
    fileprivate func nativeHighlight(_ flag: Bool) {
        setPressed(style == .sidebar && flag && available && window?.isKeyWindow == true)
    }
    override var isHidden: Bool { didSet { if isHidden { cancelInteraction() } } }
    override var isEnabled: Bool { didSet { if !isEnabled { cancelInteraction() } } }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        cancelInteraction()
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = newWindow.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.cancelInteraction() }
                }
        }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateHighlight()
    }
    private func cancelInteraction() {
        mouseDownAction = nil
        hovered = false; pressed = false
        layer?.removeAnimation(forKey: "extensionPress")
        layer?.transform = CATransform3DIdentity
        updateHighlight()
    }
    private func updateHighlight() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fill = dark ? NSColor(white: 1, alpha: pressed ? 0.103 : 0.077)
                        : NSColor(white: 0, alpha: pressed ? 0.09 : 0.071)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.backgroundColor = (available && (hovered || pressed) ? fill : .clear).cgColor
        CATransaction.commit()
    }
    private func setPressed(_ value: Bool) {
        guard value != pressed, let layer else { return }
        pressed = value; updateHighlight()
        let next = value ? CATransform3DMakeScale(0.95, 0.95, 1) : CATransform3DIdentity
        let previous = layer.presentation()?.transform ?? layer.transform
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) {
            let frame = layer.frame; layer.anchorPoint = CGPoint(x: 0.5, y: 0.5); layer.frame = frame
        }
        layer.transform = next; CATransaction.commit()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, window != nil else {
            layer.removeAnimation(forKey: "extensionPress"); return
        }
        let spring = CASpringAnimation(keyPath: "transform")
        spring.mass = 1; spring.stiffness = pow(2 * Double.pi / 0.3, 2)
        spring.damping = 4 * Double.pi * 0.6 / 0.3
        spring.fromValue = NSValue(caTransform3D: previous); spring.toValue = NSValue(caTransform3D: next)
        spring.duration = spring.settlingDuration; layer.add(spring, forKey: "extensionPress")
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        let radius = style.cornerRadius
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }
}

@MainActor
final class ExtensionToolbarView: NSView {
    let style: ExtensionControlStyle
    private var buttons: [String: ExtensionActionButton] = [:]
    private var orderedIDs: [String] = []
    var onWidthChange: (() -> Void)?
    var onButtonsChange: (() -> Void)?
    private(set) var desiredWidth: CGFloat = 0
    var orderedButtons: [NSView] { orderedIDs.compactMap { buttons[$0] } }
    override var isFlipped: Bool { true }
    var hitTestsWhenTransparent = true
    override func hitTest(_ point: NSPoint) -> NSView? {
        if !hitTestsWhenTransparent, alphaValue < 0.01 { return nil }
        return super.hitTest(point)
    }

    init(frame: NSRect = .zero, style: ExtensionControlStyle = .sidebar) {
        self.style = style
        super.init(frame: frame)
        clipsToBounds = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(_ items: [ExtensionControlItem]) {
        let pinned = items.filter { $0.pinnedIndex != nil }.sorted {
            $0.pinnedIndex! < $1.pinnedIndex!
        }
        let wanted = Set(pinned.map(\.identifier))
        for id in Array(buttons.keys) where !wanted.contains(id) {
            buttons[id]?.invalidate()
            buttons.removeValue(forKey: id)?.removeFromSuperview()
        }
        for item in pinned {
            if let button = buttons[item.identifier] { button.update(item) }
            else {
                let button = ExtensionActionButton(item: item, style: style)
                buttons[item.identifier] = button
                addSubview(button)
            }
        }
        let ordered = pinned.map(\.identifier), reordered = ordered != orderedIDs
        orderedIDs = ordered
        let width = CGFloat(orderedIDs.count) * style.surfaceSize.width
        let changed = desiredWidth != width
        desiredWidth = width
        needsLayout = true
        if changed { onWidthChange?() }
        if reordered { onButtonsChange?() }
    }

    override func layout() {
        super.layout()
        let visibleCount = max(0, Int(max(0, bounds.width) / style.surfaceSize.width))
        for (index, id) in orderedIDs.enumerated() {
            guard let button = buttons[id] else { continue }
            button.isHidden = index >= visibleCount
            let size = style.surfaceSize
            button.frame = NSRect(x: CGFloat(index) * size.width, y: max(0, (bounds.height - size.height) / 2), width: size.width, height: size.height)
        }
    }
}
