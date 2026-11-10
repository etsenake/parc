import AppKit
import QuartzCore

/// True no-op gate for SplitPaneControl layout. Identical centered surface
/// frames skip the CATransaction rewrite; identical glyph frames skip the
/// view-frame write. Hover/press/refresh remain ungated.
enum SplitPaneControlLayoutSkip {
    static func surfaceFrame(bounds: NSRect, surfaceSize: NSSize) -> NSRect {
        NSRect(x: bounds.midX - surfaceSize.width / 2, y: bounds.midY - surfaceSize.height / 2,
               width: surfaceSize.width, height: surfaceSize.height)
    }

    static func shouldSkipSurface(current: CGRect, bounds: NSRect, surfaceSize: NSSize) -> Bool {
        current == surfaceFrame(bounds: bounds, surfaceSize: surfaceSize)
    }

    static func shouldSkipGlyph(current: NSRect, bounds: NSRect) -> Bool {
        current == bounds
    }
}

/// TopBarPanelView's symbol controls. NSButton retains native input, focus
/// and AX; the original page/menu callback remains the action authority.
///
/// slot, red `lock.slash.fill` at 11-point semibold, and the same hover/press
///
@MainActor final class SplitPaneControl: PointingHandButton {
    enum Kind { case menu, close, insecure }
    static let surfaceSize = NSSize(width: 32, height: 24)
    ///
    ///
    static let insecureSurfaceSize = NSSize(width: 24, height: 24)
    let kind: Kind
    var surfaceSize: NSSize { kind == .insecure ? Self.insecureSurfaceSize : Self.surfaceSize }
    var actionBlock: (() -> Void)?
    private let glyph = SplitControlGlyph()
    private let surface = CALayer()
    private var hoverArea: NSTrackingArea?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private(set) var isHovered = false
    private(set) var isPressed = false

    init(_ kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        let nativeCell = SplitControlCell()
        cell = nativeCell
        setButtonType(.momentaryPushIn)
        nativeCell.highlightsBy = []; nativeCell.showsStateBy = []
        isBordered = false; title = ""; focusRingType = .exterior
        target = self; action = #selector(invoke)
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityChildren([])
        switch kind {
        //
        //
        //
        case .menu: LiveShortcutToolTip.set(self, "Split View Options"); setAccessibilityLabel("Split View Menu")
        case .close: LiveShortcutToolTip.set(self, "Remove Tab from Split View"); setAccessibilityLabel("Close Split View Pane")
        //
        case .insecure: LiveShortcutToolTip.set(self, "Site is not secure"); setAccessibilityLabel("Site is not secure")
        }
        wantsLayer = true
        surface.cornerRadius = 6; surface.cornerCurve = .continuous
        layer?.addSublayer(surface)
        let symbol: (String, CGFloat, NSFont.Weight) = switch kind {
        case .menu: ("square.split.2x1", 15.5, .medium)
        case .close: ("xmark", 15, .medium)
        case .insecure: ("lock.slash.fill", 11, .semibold)
        }
        glyph.image = NSImage(systemSymbolName: symbol.0, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: symbol.1, weight: symbol.2))
        glyph.imageScaling = .scaleNone
        glyph.setAccessibilityElement(false)
        addSubview(glyph)
        refresh(animated: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { for (center, observer) in observers { center.removeObserver(observer) } }
    override var intrinsicContentSize: NSSize { surfaceSize }
    override var isEnabled: Bool { didSet { if !isEnabled { isHovered = false; isPressed = false }; refresh(animated: false) } }
    override func layout() {
        super.layout()
        let nextSurface = SplitPaneControlLayoutSkip.surfaceFrame(bounds: bounds, surfaceSize: surfaceSize)
        // Chrome re-layout can dirty the control without moving its centered
        // 32×24 (or 24×24 insecure) surface. Skip the CATransaction when the
        // frame already matches; hover/press/refresh stay ungated.
        if surface.frame != nextSurface {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            surface.frame = nextSurface
            CATransaction.commit()
        }
        if glyph.frame != bounds {
            glyph.frame = bounds
        }
    }
    override var focusRingMaskBounds: NSRect { surface.frame }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: surface.frame, xRadius: 6, yRadius: 6).fill()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refresh(animated: false) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .inVisibleRect, .activeInKeyWindow], owner: self, userInfo: nil)
        hoverArea = area; addTrackingArea(area)
    }
    override func mouseEntered(with event: NSEvent) {
        guard let hoverArea, event.trackingArea === hoverArea, window?.isKeyWindow == true,
              !isHiddenOrHasHiddenAncestor, isEnabled else { return }
        isHovered = true; refresh(animated: true)
    }
    override func mouseExited(with event: NSEvent) {
        guard let hoverArea, event.trackingArea === hoverArea else { return }
        isHovered = false; refresh(animated: true)
    }
    fileprivate func nativeHighlight(_ highlighted: Bool) {
        isPressed = highlighted && isEnabled && window?.isKeyWindow == true && !isHiddenOrHasHiddenAncestor
        refresh(animated: true, pressed: true)
    }
    private func refresh(animated: Bool, pressed: Bool = false) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // FullOpacityForegroundPrimary (black/white), not the Space accent.
        let ink = dark ? NSColor.white : NSColor.black
        //
        glyph.contentTintColor = kind == .insecure ? .systemRed
            : ink.withAlphaComponent(isEnabled ? (dark ? 0.675 : 0.55) : 0.25)
        let opacity: Float = !isEnabled ? 0 : isPressed ? (dark ? 0.13 : 0.09) : isHovered ? (dark ? 0.09 : 0.05) : 0
        let old = surface.presentation()?.opacity ?? surface.opacity
        CATransaction.begin(); CATransaction.setDisableActions(true)
        surface.backgroundColor = ink.cgColor; surface.opacity = opacity
        surface.removeAnimation(forKey: "split-control-opacity")
        CATransaction.commit()
        guard animated, window?.isKeyWindow == true, !isHiddenOrHasHiddenAncestor,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, old != opacity else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = old; animation.toValue = opacity
        animation.duration = pressed ? 0.16 : 0.18
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        surface.add(animation, forKey: "split-control-opacity")
    }
    private func clearInteraction() { isHovered = false; isPressed = false; refresh(animated: false) }
    override func viewDidHide() { super.viewDidHide(); clearInteraction() }
    override func viewWillMove(toSuperview newSuperview: NSView?) { super.viewWillMove(toSuperview: newSuperview); clearInteraction() }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow); clearInteraction()
        if let hoverArea { removeTrackingArea(hoverArea) }; hoverArea = nil
        for (center, observer) in observers { center.removeObserver(observer) }; observers.removeAll()
        if let newWindow {
            observers.append((NotificationCenter.default, NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: newWindow, queue: .main) { [weak self, weak newWindow] _ in
                MainActor.assumeIsolated { guard let self, let newWindow, self.window === newWindow else { return }; self.clearInteraction() }
            }))
            observers.append((NSWorkspace.shared.notificationCenter, NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self, weak newWindow] _ in
                MainActor.assumeIsolated { guard let self, let newWindow, self.window === newWindow else { return }; self.refresh(animated: false) }
            }))
        }
    }
    @objc private func invoke() {
        guard isEnabled, !isHiddenOrHasHiddenAncestor, window?.isKeyWindow == true else { return }
        actionBlock?()
    }
}

@MainActor private final class SplitControlGlyph: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor private final class SplitControlCell: NSButtonCell {
    override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {
        super.highlight(flag, withFrame: cellFrame, in: controlView)
        (controlView as? SplitPaneControl)?.nativeHighlight(flag)
    }
}

//
// The parent does not derive its content inset from the symbol's 24-point hit
// surface. Developer Mode and Peek's outer card retain their separate owners.
enum PaneTopBarLayout {
    static let height: CGFloat = 32
    static let horizontalInset: CGFloat = 5

    static func frame(x: CGFloat, width: CGFloat, height controlHeight: CGFloat) -> NSRect {
        NSRect(x: x, y: (height - controlHeight) / 2, width: width, height: controlHeight)
    }
}

///
/// menu item for the recovered `show-toolbar-in-split-view-enabled` string;
/// gating on it (or on the separate Show Toolbar preference) hid the chrome.
enum PaneTopBarAdmission {
    static func displayed(toolbarVisible: Bool, inSplit: Bool, isPopup: Bool = false,
                          hasLibrary: Bool = false, tabFullscreen: Bool = false) -> Bool {
        !isPopup && !hasLibrary && !tabFullscreen && (toolbarVisible || inSplit)
    }
    /// Peek's own bar still follows Show Toolbar. Split admission must not
    /// leak onto it: Peek is never a split pane.
    static func peekDisplayed(toolbarVisible: Bool, isActivePeek: Bool,
                              developerToolbarHidden: Bool) -> Bool {
        toolbarVisible && isActivePeek && developerToolbarHidden
    }
    /// The sidebar URL bar (`WindowViewController.ViewState
    ///
    ///
    /// keeps it beside split panes' bars, showing the focused pane, so only
    /// the Toolbar preference hides it here.
    static func sidebarAddressBarShown(focusedHasTopBar: Bool, toolbarVisible: Bool) -> Bool {
        !(focusedHasTopBar && toolbarVisible)
    }
}

/// The pane chrome X closes that pane's original page, matching the sidebar
///
/// for Peek and for a single displayed page.
enum SplitPaneCloseAdmission {
    static func accepts(tabID: UUID, selected: [UUID], isPeek: Bool = false) -> Bool {
        !isPeek && selected.count > 1 && selected.contains(tabID)
    }
}

/// Opacity changes of top-bar controls. TopBarPanelView's body animates hover
/// changes with 0.18-second and modal-obstruction changes with 0.17-second
///
@MainActor enum PaneTopBarFade {
    static let hover: TimeInterval = 0.18
    static let obstruction: TimeInterval = 0.17
    static func set(_ views: [NSView], alpha: CGFloat, duration: TimeInterval?) {
        let animated = duration != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && views.contains { $0.window != nil && !$0.isHiddenOrHasHiddenAncestor }
        guard animated, let duration else {
            for view in views { view.layer?.removeAnimation(forKey: "opacity"); view.alphaValue = alpha }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for view in views { view.animator().alphaValue = alpha }
        }
    }
}

/// TopBarPanelViewModel's ordinary-pane essential-control rule. Tracking is
///
/// extends beyond the bar; this owner never receives clicks or changes focus.
/// The menu shows for `!isObstructedByModal && (!onlyShowEssentialControls ||
///
/// onlyShowEssentialControls and `obstructed` is isObstructedByModal.
@MainActor final class PaneControlVisibility: NSResponder {
    /// The new reveal and the original transition duration, nil for immediate.
    var onChange: ((Bool, TimeInterval?) -> Void)?
    private weak var host: NSView?
    private weak var trackingView: NSView?
    private weak var originalWindow: NSWindow?
    private var area: NSTrackingArea?
    private var observers: [NSObjectProtocol] = []
    private var topBar = NSRect.zero
    private var focused = true
    private var obstructed = false
    private var publishedHover = false
    private var publishedObstruction = false
    private var menuDepth = 0
    private let applicationIsActive: @MainActor () -> Bool

    init(applicationIsActive: @escaping @MainActor () -> Bool = { NSApp.isActive }) {
        self.applicationIsActive = applicationIsActive
        super.init()
    }
    required init?(coder: NSCoder) { nil }
    private(set) var isHovered = false
    private(set) var isRevealed = true

    static func hoverRegion(for bar: NSRect) -> NSRect {
        NSRect(x: bar.minX, y: bar.minY - 40, width: bar.width, height: bar.height + 40 + (60 - PaneTopBarLayout.height))
    }
    func update(host: NSView, bar: NSRect?, focused: Bool, obstructed: Bool = false) {
        self.focused = focused; self.obstructed = obstructed
        guard let bar, !bar.isEmpty, let window = host.window, let root = window.contentView,
              !host.isHiddenOrHasHiddenAncestor, host.visibleRect.intersects(bar) else {
            retireTracking(); publish(); return
        }
        let rect = root.convert(Self.hoverRegion(for: bar), from: host).intersection(root.bounds)
        guard !rect.isEmpty else { retireTracking(); publish(); return }
        if self.host !== host || originalWindow !== window || trackingView !== root || area?.rect != rect {
            retireTracking()
            self.host = host; originalWindow = window; trackingView = root; topBar = bar
            let next = NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow], owner: self, userInfo: nil)
            area = next; root.addTrackingArea(next)
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                    MainActor.assumeIsolated {
                        guard let self, let window, self.originalWindow === window else { return }
                        self.isHovered = false; self.publish()
                    }
                })
            }
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window, self.originalWindow === window else { return }
                    self.isHovered = false; self.publish()
                }
            })
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window, self.originalWindow === window else { return }
                    self.samplePointer()
                }
            })
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window, self.originalWindow === window else { return }
                    self.samplePointer()
                }
            })
        }
        topBar = bar; samplePointer()
    }
    override func mouseEntered(with event: NSEvent) {
        guard let area, event.trackingArea === area else { return }; samplePointer()
    }
    override func mouseExited(with event: NSEvent) {
        guard let area, event.trackingArea === area else { return }; samplePointer()
    }
    override func mouseMoved(with event: NSEvent) {
        guard event.window === originalWindow else { return }
        // Tracking delivers moved only while the pointer stays inside the
        // installed hover-region area. When already hovered and live window/
        // key/active/host gates still admit hover — or still refuse while not
        // hovered — the hover bit cannot flip without mouseExited, resign-key/
        // active, or update rebuilding geometry. Skip convert/contains/publish.
        // Enter/exit/key/active/focus/obstruction/menuDepth still sample.
        if isHovered == hoverGatesOpen { return }
        samplePointer()
    }
    /// Window/key/active/host visibility that admit a hover bit of true.
    private var hoverGatesOpen: Bool {
        guard let host, let window = originalWindow, host.window === window, window.isKeyWindow,
              applicationIsActive(), !host.isHiddenOrHasHiddenAncestor, host.visibleRect.intersects(topBar) else {
            return false
        }
        return true
    }
    private func samplePointer() {
        if hoverGatesOpen, let host, let window = originalWindow {
            isHovered = Self.hoverRegion(for: topBar).contains(host.convert(window.mouseLocationOutsideOfEventStream, from: nil))
        } else { isHovered = false }
        publish()
    }
    func trackMenu(_ body: () -> Void) {
        // AppKit's synchronous menu tracking substitutes for the original
        // retained popover state. It cannot extend the original action lease.
        menuDepth += 1; publish()
        defer { menuDepth -= 1; samplePointer() }
        body()
    }
    private func publish() {
        let value = !obstructed && (focused || isHovered || menuDepth > 0)
        // The hover animation modifier is nearer the content than the modal
        // one, so it wins when both change in one update.
        let duration: TimeInterval? = isHovered != publishedHover ? PaneTopBarFade.hover
            : obstructed != publishedObstruction ? PaneTopBarFade.obstruction : nil
        publishedHover = isHovered; publishedObstruction = obstructed
        guard value != isRevealed else { return }
        isRevealed = value; onChange?(value, duration)
    }
    func invalidate() { retireTracking(); publish() }
    private func retireTracking() {
        let oldView = trackingView, oldArea = area
        host = nil; trackingView = nil; originalWindow = nil; area = nil; isHovered = false
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        if let oldView, let oldArea { oldView.removeTrackingArea(oldArea) }
    }
    deinit {
        // All owners are native views; their teardown stays on the main thread.
        MainActor.assumeIsolated { retireTracking() }
    }
}
