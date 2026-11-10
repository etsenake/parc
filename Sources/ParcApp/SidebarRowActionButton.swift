import AppKit
import QuartzCore

/// A row action retains its original owner's one-use command from press until
/// release. Native NSButton tracking, keyboard activation and cancellation stay
/// authoritative; a disappearing/replaced row cannot dispatch a fresh command.
final class SidebarRowActionButton: PointingHandButton {
    var prepareAction: (() -> (() -> Bool)?)?
    /// A cheap stand-in for `prepareAction() != nil` when preparing the action
    /// is costly; the action itself is then prepared only on press.
    var isAvailable: (() -> Bool)?
    var makeMenu: (() -> NSMenu?)?
    /// A SidebarCellButtonSystemImageContentView glyph in place of Close's bars.
    var symbol: NSImage? { didSet { needsDisplay = true } }
    /// Decorative content can persist across row reconstruction; input remains
    /// owned by this button and its original action lease.
    var decoration: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let decoration {
                if let previous = decoration.superview as? SidebarRowActionButton, previous !== self {
                    previous.decoration = nil
                }
                addSubview(decoration); decoration.frame = bounds
                decoration.autoresizingMask = [.width, .height]
                decoration.alphaValue = isEnabled ? 1 : 0.35
            }
            needsDisplay = true
        }
    }
    var dark = false { didSet { if dark != oldValue { needsDisplay = true } } }
    private var hovering = false
    private var pressed = false
    private var trackingPress = false
    private var pendingAction: (() -> Bool)?
    private var trackingArea: NSTrackingArea?
    private var windowObserver: NSObjectProtocol?

    init(_ title: String) {
        super.init(frame: .zero)
        self.title = ""; isBordered = false; bezelStyle = .regularSquare
        wantsLayer = true; focusRingType = .exterior
        setAccessibilityLabel(title); LiveShortcutToolTip.set(self, title)
        target = self; action = #selector(invoke)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) } }

    func refreshAvailability() {
        // A hidden button refreshes when it is shown again.
        guard !isHidden else { return }
        isEnabled = window != nil && available
    }
    private var available: Bool { isAvailable?() ?? (prepareAction?() != nil) }
    @objc private func invoke() {
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return }
        if trackingPress {
            let action = pendingAction; pendingAction = nil
            _ = action?()
        } else { _ = prepareAction?()?() }
    }
    override func accessibilityPerformPress() -> Bool {
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return false }
        return prepareAction?()?() == true
    }
    override func isAccessibilityEnabled() -> Bool {
        window != nil && !isHiddenOrHasHiddenAncestor && available
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        refreshAvailability()
        guard isEnabled, let action = prepareAction?() else { return }
        trackingPress = true; pendingAction = action
        defer { trackingPress = false; pendingAction = nil; setPressed(false) }
        super.mouseDown(with: event)
    }
    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        setPressed(flag && isEnabled && window?.isKeyWindow == true)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return nil }
        return makeMenu?()
    }
    override func rightMouseDown(with event: NSEvent) {
        cancelInteraction()
        if let menu = menu(for: event) { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
    override func accessibilityPerformShowMenu() -> Bool {
        guard window != nil, !isHiddenOrHasHiddenAncestor, let menu = makeMenu?() else { return false }
        cancelInteraction(); menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY), in: self)
        return true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect], owner: self)
        addTrackingArea(area); trackingArea = area
        hovering = window.map { window in
            let point = window.mouseLocationOutsideOfEventStream
            return window.isKeyWindow && !isHiddenOrHasHiddenAncestor && bounds.contains(convert(point, from: nil))
                && isTopmost(atWindowPoint: point)
        } == true
        refreshAvailability(); needsDisplay = true
    }
    override func mouseEntered(with event: NSEvent) {
        hovering = isTopmost(atWindowPoint: event.locationInWindow); refreshAvailability(); needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    /// Sliding out from under something drawn over the row, such as the
    /// command bar, hovers the button; sliding back under doesn't.
    override func mouseMoved(with event: NSEvent) {
        let value = isTopmost(atWindowPoint: event.locationInWindow)
        guard value != hovering else { return }
        hovering = value; refreshAvailability(); needsDisplay = true
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        cancelInteraction()
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
        if let newWindow {
            windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                object: newWindow, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.cancelInteraction() }
                }
        }
        super.viewWillMove(toWindow: newWindow)
    }
    override var isHidden: Bool { didSet { if isHidden { cancelInteraction() } else if oldValue { refreshAvailability() } } }
    override var isEnabled: Bool { didSet { if !isEnabled { cancelInteraction() }; decoration?.alphaValue = isEnabled ? 1 : 0.35; needsDisplay = true } }
    func cancelInteraction() {
        pendingAction = nil; hovering = false; pressed = false
        layer?.removeAnimation(forKey: "rowActionPress"); layer?.transform = CATransform3DIdentity
        needsDisplay = true
    }
    private func setPressed(_ value: Bool) {
        guard value != pressed, let layer else { return }
        pressed = value; needsDisplay = true
        let next = value ? CATransform3DMakeScale(0.95, 0.95, 1) : CATransform3DIdentity
        let previous = layer.presentation()?.transform ?? layer.transform
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) {
            let frame = layer.frame; layer.anchorPoint = CGPoint(x: 0.5, y: 0.5); layer.frame = frame
        }
        layer.transform = next; CATransaction.commit()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, window != nil else {
            layer.removeAnimation(forKey: "rowActionPress"); return
        }
        //
        // ratio and .3 response. Reversals use the current presentation value.
        let spring = CASpringAnimation(keyPath: "transform")
        spring.mass = 1; spring.stiffness = pow(2 * Double.pi / 0.3, 2)
        spring.damping = 4 * Double.pi * 0.6 / 0.3
        spring.fromValue = NSValue(caTransform3D: previous); spring.toValue = NSValue(caTransform3D: next)
        spring.duration = spring.settlingDuration; layer.add(spring, forKey: "rowActionPress")
    }
    override func draw(_ dirtyRect: NSRect) {
        //
        // 24-point square; the 5-point corners remain Parc's placement.
        if (hovering || pressed) && isEnabled {
            SidebarRowAppearance.controlFill(pressed: pressed, dark: dark).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
        if decoration != nil { return }
        if let symbol {
            //
            let tint = dark ? NSColor(white: 1, alpha: 0.592) : NSColor(white: 0, alpha: 0.565)
            let image = NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect); tint.set(); rect.fill(using: .sourceAtop); return true
            }
            let size = symbol.size
            image.draw(in: NSRect(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded(),
                                  width: size.width, height: size.height),
                       from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.35, respectFlipped: true, hints: nil)
            return
        }
        // SidebarCellButtonCloseContentView: two 14×2 rounded bars at ±π/4,
        //
        //
        // One path keeps the crossing no darker than the bars.
        let alpha: CGFloat = (dark ? 0.592 : 0.565) * (isEnabled ? 1 : 0.35)
        let cross = NSBezierPath()
        for angle: CGFloat in [-45, 45] {
            let bar = NSBezierPath(roundedRect: NSRect(x: -7, y: -1, width: 14, height: 2), xRadius: 1, yRadius: 1)
            var transform = AffineTransform(rotationByDegrees: angle)
            transform.append(AffineTransform(translationByX: bounds.midX, byY: bounds.midY))
            bar.transform(using: transform)
            cross.append(bar)
        }
        (dark ? NSColor.white : NSColor.black).withAlphaComponent(alpha).setFill()
        cross.windingRule = .nonZero
        cross.fill()
    }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 1, dy: 1) }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 5, yRadius: 5).fill()
    }
}

///
/// lifts as one layer and leaves pointer input to the row.
final class SidebarRowTitleStack: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

///
/// from (1, 1) to (width − 1, height − 1). Decorative only.
final class SidebarRowSlashView: NSView {
    var color = SidebarRowAppearance.slashColor(dark: false) { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 1, y: 1)); path.line(to: NSPoint(x: bounds.width - 1, y: bounds.height - 1))
        path.lineWidth = SidebarRowAppearance.slashLineWidth; path.lineCapStyle = .round
        color.setStroke(); path.stroke()
    }
}

///
/// with per-region corners (TabCellRegionalBackgroundButton.updateLayer
///
class SidebarRowRegionView: PointingHandButton {
    var dark = false { didSet { if dark != oldValue { refreshFill() } } }
    var corners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner] {
        didSet { if corners != oldValue { refreshFill() } }
    }
    var hovered = false { didSet { if hovered != oldValue { refreshFill() } } }
    fileprivate(set) var pressed = false { didSet { if pressed != oldValue { refreshFill() } } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""; isBordered = false; bezelStyle = .regularSquare; wantsLayer = true
        layer?.allowsGroupOpacity = false
        refreshFill()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func refreshFill() {
        guard let layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.backgroundColor = pressed || hovered ? SidebarRowAppearance.regionFill(pressed: pressed, dark: dark).cgColor : nil
        // The region radius follows the row's 12-point continuous background.
        layer.cornerRadius = SidebarRowAppearance.cornerRadius; layer.cornerCurve = .continuous
        layer.maskedCorners = corners
        CATransaction.commit()
    }
}

/// The non-interactive body region of a resettable row.
final class SidebarRowBodyRegionView: SidebarRowRegionView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
}

///
/// hovered on a resettable row, and Command picks the separate variant
///
enum SidebarRowHoverSubtitle: Equatable {
    case reset, resetAndSeparate

    var text: String {
        self == .reset ? SidebarRowAppearance.resetSubtitle : SidebarRowAppearance.separateSubtitle
    }
}

///
///
///
///
/// so a Command-click separates the live page instead of resetting it. Like
/// the row's other controls it holds the original owner's one-use command from
/// press to release; a drag that starts on it moves the row instead.
final class SidebarRowResetRegion: SidebarRowRegionView {
    var prepareAction: (() -> (() -> Bool)?)?
    /// Separate From Pinned Tab, available whenever reset is.
    var prepareSeparate: (() -> (() -> Bool)?)?
    var makeMenu: (() -> NSMenu?)?
    /// Called when the region's hover or its hover subtitle state changes.
    var onHoverChange: (() -> Void)?
    private(set) var hoverSubtitle: SidebarRowHoverSubtitle?
    private var pendingAction: (() -> Bool)?
    private var downEvent: NSEvent?
    private var trackingArea: NSTrackingArea?
    private var flagsMonitor: Any?
    private var windowObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .exterior
        setAccessibilityLabel("Reset Tab to Original URL")
        target = self; action = #selector(invoke)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
    }

    func refreshAvailability() {
        isEnabled = window != nil && prepareAction?() != nil
    }
    /// Keyboard activation (Full Keyboard Access) takes a fresh command.
    @objc private func invoke() {
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return }
        _ = prepareAction?()?()
    }
    override func accessibilityPerformPress() -> Bool {
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return false }
        return prepareAction?()?() == true
    }
    override func isAccessibilityEnabled() -> Bool {
        window != nil && !isHiddenOrHasHiddenAncestor && prepareAction?() != nil
    }
    /// The one-use command a click with these modifiers takes.
    func lease(_ flags: NSEvent.ModifierFlags) -> (() -> Bool)? {
        flags.contains(.command) ? prepareSeparate?() : prepareAction?()
    }
    /// A region without a current command for the held modifiers (the page is
    /// held by another window or a Peek, a sheet is open) leaves the click to
    /// the row's own selection and activation owners.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point), window != nil, lease(NSEvent.modifierFlags) != nil else { return nil }
        return hit
    }
    /// Like the row around it, a background window's first click only
    /// activates the window; it never resets the page.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        refreshAvailability()
        guard isEnabled, window?.isKeyWindow == true, let action = lease(event.modifierFlags) else { return }
        pendingAction = action; downEvent = event; pressed = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let down = downEvent, pendingAction != nil else { return }
        let start = convert(down.locationInWindow, from: nil), point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) <= 4 else {
            // A drag from the icon moves the row, as from anywhere else on it.
            pendingAction = nil; downEvent = nil; pressed = false
            superview?.mouseDown(with: down); superview?.mouseDragged(with: event)
            return
        }
        pressed = bounds.contains(point)
    }
    override func mouseUp(with event: NSEvent) {
        let action = pendingAction
        pendingAction = nil; downEvent = nil; pressed = false
        guard action != nil, window != nil, !isHiddenOrHasHiddenAncestor,
              bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        _ = action?()
    }
    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        pressed = flag && isEnabled && window?.isKeyWindow == true
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return nil }
        return makeMenu?()
    }
    override func rightMouseDown(with event: NSEvent) {
        cancelInteraction()
        if let menu = menu(for: event) { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
    override func accessibilityPerformShowMenu() -> Bool {
        guard window != nil, !isHiddenOrHasHiddenAncestor, let menu = makeMenu?() else { return false }
        cancelInteraction(); menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY), in: self)
        return true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect], owner: self)
        addTrackingArea(area); trackingArea = area
        // A row rebuilt under a stationary pointer reconciles its actual hover.
        setPointerInside(window.map { window in
            let point = window.mouseLocationOutsideOfEventStream
            return window.isKeyWindow && !isHiddenOrHasHiddenAncestor && bounds.contains(convert(point, from: nil))
                && isTopmost(atWindowPoint: point)
        } == true)
    }
    // Under something drawn over the row, such as the command bar, the
    // pointer isn't on the button; moves re-read it as it slides out.
    override func mouseEntered(with event: NSEvent) { setPointerInside(isTopmost(atWindowPoint: event.locationInWindow)) }
    override func mouseMoved(with event: NSEvent) { setPointerInside(isTopmost(atWindowPoint: event.locationInWindow)) }
    override func mouseExited(with event: NSEvent) { setPointerInside(false) }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        cancelInteraction()
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
        if let newWindow {
            windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                object: newWindow, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.cancelInteraction() }
                }
        }
        super.viewWillMove(toWindow: newWindow)
    }
    override var isHidden: Bool { didSet { if isHidden { cancelInteraction() } } }
    override var isEnabled: Bool { didSet { if !isEnabled { cancelInteraction() } } }
    func cancelInteraction() {
        pendingAction = nil; downEvent = nil; pressed = false
        setPointerInside(false)
    }

    private func setPointerInside(_ inside: Bool) {
        let wasHovered = hovered
        hovered = inside && isEnabled
        //
        // `monitor`), so Command can switch the hover without pointer motion.
        if hovered, flagsMonitor == nil {
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                MainActor.assumeIsolated { _ = self?.updateHoverSubtitle(event.modifierFlags) }
                return event
            }
        } else if !hovered, let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor); self.flagsMonitor = nil
        }
        if !updateHoverSubtitle(NSEvent.modifierFlags), wasHovered != hovered { onHoverChange?() }
    }
    /// Re-derives the hover subtitle state for the held modifiers.
    @discardableResult func updateHoverSubtitle(_ flags: NSEvent.ModifierFlags) -> Bool {
        let next: SidebarRowHoverSubtitle? = hovered ? (flags.contains(.command) ? .resetAndSeparate : .reset) : nil
        guard next != hoverSubtitle else { return false }
        hoverSubtitle = next
        onHoverChange?()
        return true
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: SidebarRowAppearance.cornerRadius, yRadius: SidebarRowAppearance.cornerRadius).fill()
    }
}
