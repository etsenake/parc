import AppKit
import Combine
import ParcCore

package final class ActionButton: PointingHandButton {
    package var actionBlock: (() -> Void)?
    package var onHover: ((Bool) -> Void)?
    package var showsHoverFill = false
    package var showsSelectedFill = false {
        didSet { if showsSelectedFill != oldValue { needsDisplay = true } }
    }
    package var contentAlpha: CGFloat = 1 {
        didSet { if contentAlpha != oldValue { needsDisplay = true } }
    }
    package var activityFill: CGFloat = 0 { didSet { if activityFill != oldValue { needsDisplay = true } } }
    package var glyphLift: CGFloat = 0 { didSet { if glyphLift != oldValue { needsDisplay = true } } }
    private var hoverTracking: NSTrackingArea?
    package private(set) var hovered = false {
        didSet {
            guard hovered != oldValue else { return }
            if showsHoverFill { needsDisplay = true }
            translucentFace?.setHovered(hovered)
            onHover?(hovered)
        }
    }
    package var secondaryActionBlock: (() -> Void)?
    package var focusRingCornerRadius: CGFloat? {
        didSet {
            guard focusRingCornerRadius != oldValue else { return }
            focusRingType = focusRingCornerRadius == nil ? .none : .exterior; noteFocusRingMaskChanged()
        }
    }
    package init(_ title: String = "", symbol: String? = nil, action: (() -> Void)? = nil) {
        super.init(frame: .zero)
        self.title = title
        self.actionBlock = action
        self.target = self
        self.action = #selector(invoke)
        isBordered = false
        bezelStyle = .regularSquare
        font = .systemFont(ofSize: 12, weight: .medium)
        contentTintColor = .parcInk
        focusRingType = .none
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); imagePosition = title.isEmpty ? .imageOnly : .imageLeading }
        setAccessibilityLabel(title)
    }
    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func invoke() { actionBlock?() }
    package var hitTestsWhenTransparent = true
    package override func hitTest(_ point: NSPoint) -> NSView? {
        if !hitTestsWhenTransparent, alphaValue < 0.01 { return nil }
        return super.hitTest(point)
    }
    package override func rightMouseDown(with event: NSEvent) {
        guard let secondaryActionBlock, isEnabled else { super.rightMouseDown(with: event); return }
        secondaryActionBlock()
    }
    package override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.control), let secondaryActionBlock, isEnabled else {
            super.mouseDown(with: event); return
        }
        secondaryActionBlock()
    }
    package override func accessibilityPerformShowMenu() -> Bool {
        guard let secondaryActionBlock, isEnabled else { return super.accessibilityPerformShowMenu() }
        secondaryActionBlock(); return true
    }
    package override var focusRingMaskBounds: NSRect { focusRingCornerRadius == nil ? super.focusRingMaskBounds : bounds }
    package override func drawFocusRingMask() {
        guard let radius = focusRingCornerRadius else { super.drawFocusRingMask(); return }
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }
    package var translucentFace: TranslucentButtonFace? {
        didSet { translucentFace?.setHovered(hovered, animated: false); updateTrackingAreas(); needsDisplay = true }
    }
    private var tracksHover: Bool { showsHoverFill || onHover != nil || translucentFace != nil }
    package override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking); self.hoverTracking = nil }
        if tracksHover {
            hoverTracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                           owner: self, userInfo: nil)
            addTrackingArea(hoverTracking!)
        }
        super.updateTrackingAreas()
    }
    package var isAvailable: (() -> Bool)?
    package override func mouseEntered(with event: NSEvent) {
        if let available = isAvailable?(), isEnabled != available { isEnabled = available }
        if tracksHover { hovered = isEnabled && isTopmost(atWindowPoint: event.locationInWindow) }
        super.mouseEntered(with: event)
    }
    package override func mouseExited(with event: NSEvent) {
        if tracksHover { hovered = false }
        super.mouseExited(with: event)
    }
    package override func mouseMoved(with event: NSEvent) {
        if tracksHover, bounds.contains(convert(event.locationInWindow, from: nil)) { hovered = isEnabled && isTopmost(atWindowPoint: event.locationInWindow) }
    }
    package override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { hovered = false; translucentFace?.stop() }
        super.viewWillMove(toWindow: newWindow)
    }
    package func refreshHover() {
        guard let window, isEnabled, window.applicationIsActive, !isHiddenOrHasHiddenAncestor else { hovered = false; return }
        let point = window.mouseLocationOutsideOfEventStream
        hovered = bounds.contains(convert(point, from: nil)) && isTopmost(atWindowPoint: point)
    }
    package var onHighlight: ((Bool) -> Void)?
    package override func highlight(_ flag: Bool) {
        super.highlight(flag)
        if tracksHover { refreshHover() }
        onHighlight?(flag)
    }
    package override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if translucentFace != nil { needsDisplay = true }
    }
    package override func draw(_ dirtyRect: NSRect) {
        if let face = translucentFace {
            face.setPressed(isHighlighted && isEnabled)
            face.draw(in: bounds, enabled: isEnabled, view: self) { tint in
                if let image { face.drawGlyph(image, tint: tint, in: bounds, view: self) }
            }
            return
        }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let pressedAlpha: CGFloat = dark ? 0.103 : 0.09
        var fill: CGFloat = 0
        if showsHoverFill, isEnabled, showsSelectedFill || hovered || isHighlighted {
            fill = isHighlighted && !showsSelectedFill ? pressedAlpha : dark ? 0.077 : 0.071
        }
        if isEnabled { fill = max(fill, pressedAlpha * activityFill) }
        if fill > 0 {
            NSColor(white: dark ? 1 : 0, alpha: fill).setFill()
            let side = min(24, bounds.width, bounds.height)
            let plate = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
            NSBezierPath(roundedRect: plate, xRadius: 5, yRadius: 5).fill()
        }
        guard contentAlpha < 1 || glyphLift != 0, let context = NSGraphicsContext.current?.cgContext else {
            super.draw(dirtyRect); return
        }
        context.saveGState()
        if contentAlpha < 1 { context.setAlpha(contentAlpha) }
        context.translateBy(x: 0, y: isFlipped ? -glyphLift : glyphLift)
        super.draw(dirtyRect)
        context.restoreGState()
    }
}
