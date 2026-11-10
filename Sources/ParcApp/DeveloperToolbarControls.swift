import AppKit
import QuartzCore

///
/// buttons: clear at rest, GrayA4 while hovered, GrayA5 while pressed, radius
/// 5, no scale and no fill fade. Distinct from ordinary toolbar
/// `TopBarButtonStyle`. Disabled and non-key windows keep a clear surface.
@MainActor final class DeveloperToolbarButton: PointingHandButton {
    var actionBlock: (() -> Void)?
    private var hoverTrackingArea: NSTrackingArea?
    private var resignationObserver: NSObjectProtocol?
    private(set) var isHovered = false
    private(set) var isPressed = false

    init(symbol: String, title: String) {
        super.init(frame: .zero)
        let nativeCell = DeveloperToolbarButtonCell()
        cell = nativeCell
        setButtonType(.momentaryPushIn)
        nativeCell.highlightsBy = []
        nativeCell.showsStateBy = []
        isBordered = false
        bezelStyle = .regularSquare
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        imagePosition = .imageOnly
        target = self
        action = #selector(invoke)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        wantsLayer = true
        focusRingType = .exterior
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        if let resignationObserver { NotificationCenter.default.removeObserver(resignationObserver) }
    }

    override var isEnabled: Bool {
        didSet { if !isEnabled { setHovered(false); setPressed(false) }; needsDisplay = true }
    }
    override var wantsUpdateLayer: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: DeveloperToolbarButton.cornerRadius,
                     yRadius: DeveloperToolbarButton.cornerRadius).fill()
    }
    override func updateLayer() {
        super.updateLayer()
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fillColor(dark: effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua).cgColor
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil)
        hoverTrackingArea = area
        addTrackingArea(area)
    }
    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea === hoverTrackingArea else { super.mouseEntered(with: event); return }
        refreshHover()
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event); refreshHover()
    }
    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea === hoverTrackingArea else { super.mouseExited(with: event); return }
        setHovered(false)
    }
    fileprivate func nativeHighlight(_ highlighted: Bool) {
        setPressed(highlighted && isEnabled && window?.isKeyWindow == true && !isHiddenOrHasHiddenAncestor)
    }
    override func viewDidHide() {
        super.viewDidHide(); setHovered(false); setPressed(false)
    }
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview); setHovered(false); setPressed(false)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        setHovered(false); setPressed(false)
        if let resignationObserver { NotificationCenter.default.removeObserver(resignationObserver) }
        resignationObserver = nil
        if let newWindow {
            resignationObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: newWindow, queue: .main
            ) { [weak self, weak newWindow] _ in
                MainActor.assumeIsolated {
                    guard let self, let newWindow, self.window === newWindow else { return }
                    self.setHovered(false); self.setPressed(false)
                }
            }
        }
    }
    @objc private func invoke() { guard isEnabled else { return }; actionBlock?() }

    func setTrailingHidden(_ hidden: Bool) {
        isHidden = hidden
        setAccessibilityHidden(hidden)
    }

    static let cornerRadius: CGFloat = 5
    static func grayA4(dark: Bool) -> NSColor {
        NSColor(srgbRed: dark ? 1 : 0, green: dark ? 1 : 0, blue: dark ? 1 : 0, alpha: dark ? 0.077 : 0.071)
    }
    static func grayA5(dark: Bool) -> NSColor {
        NSColor(srgbRed: dark ? 1 : 0, green: dark ? 1 : 0, blue: dark ? 1 : 0, alpha: dark ? 0.103 : 0.090)
    }

    private func fillColor(dark: Bool) -> NSColor {
        guard isEnabled else { return .clear }
        if isPressed { return Self.grayA5(dark: dark) }
        if isHovered { return Self.grayA4(dark: dark) }
        return .clear
    }
    private func refreshHover() {
        guard isEnabled, let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor,
              let content = window.contentView else { setHovered(false); return }
        let location = content.superview?.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            ?? window.mouseLocationOutsideOfEventStream
        let hit = content.hitTest(location)
        setHovered(hit === self || hit?.isDescendant(of: self) == true)
    }
    private func setHovered(_ value: Bool) {
        guard isHovered != value else { return }
        isHovered = value; needsDisplay = true
    }
    private func setPressed(_ value: Bool) {
        guard isPressed != value else { return }
        isPressed = value; needsDisplay = true
    }
}

@MainActor private final class DeveloperToolbarButtonCell: NSButtonCell {
    override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {
        super.highlight(flag, withFrame: cellFrame, in: controlView)
        (controlView as? DeveloperToolbarButton)?.nativeHighlight(flag)
    }
}

///
///
/// replaces that spring with response 0.3 / damping 0.4 for offset −5, then
///
///
///
@MainActor
enum DeveloperToolbarSpring {
    static let restResponse: CGFloat = 0.2
    static let restDampingRatio: CGFloat = 0.6
    static let shakeResponse: CGFloat = 0.3
    static let shakeDampingRatio: CGFloat = 0.4
    static let shakeOffset: CGFloat = -5
    static let resetDelay: TimeInterval = 0.1
    static let animationKey = "parc.developer-toolbar.offset"

    private static var generations: [ObjectIdentifier: UInt] = [:]

    static func shake(_ view: NSView, reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        bump(view)
        let id = ObjectIdentifier(view)
        let generation = generations[id] ?? 0
        guard !reduceMotion else {
            generations.removeValue(forKey: id)
            return
        }
        animate(view, to: shakeOffset)
        DispatchQueue.main.asyncAfter(deadline: .now() + resetDelay) { [weak view] in
            MainActor.assumeIsolated {
                guard let view, generations[ObjectIdentifier(view)] == generation else { return }
                resetToRest(view)
                generations.removeValue(forKey: ObjectIdentifier(view))
            }
        }
    }

    static func spring(response: CGFloat, dampingRatio: CGFloat) -> CASpringAnimation {
        let omega = 2 * Double.pi / Double(response)
        let animation = CASpringAnimation(keyPath: "transform.translation.x")
        animation.mass = 1
        animation.stiffness = omega * omega
        animation.damping = 2 * Double(dampingRatio) * omega
        return animation
    }

    /// Offset returns to 0 on the shake spring; init rest 0.2/0.6 is not
    ///
    static func resetToRest(_ view: NSView) {
        animate(view, to: 0)
    }

    static func currentOffset(_ view: NSView) -> CGFloat {
        let layer = view.layer
        if let presented = layer?.presentation()?.value(forKeyPath: "transform.translation.x") as? CGFloat {
            return presented
        }
        return (layer?.value(forKeyPath: "transform.translation.x") as? CGFloat) ?? 0
    }

    private static func animate(_ view: NSView, to offset: CGFloat) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let from = currentOffset(view)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(offset, forKeyPath: "transform.translation.x")
        CATransaction.commit()
        let animation = spring(response: shakeResponse, dampingRatio: shakeDampingRatio)
        animation.fromValue = from
        animation.toValue = offset
        animation.duration = animation.settlingDuration
        layer.add(animation, forKey: animationKey)
    }

    private static func bump(_ view: NSView) {
        let id = ObjectIdentifier(view)
        generations[id, default: 0] &+= 1
    }
}

/// First-edit `selectAll:` plus ContentPanel shake, invoked from
/// `DeveloperAddressField.becomeFirstResponder`.
@MainActor
enum DeveloperToolbarFirstEdit {
    static func apply(_ field: NSTextField, reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        DeveloperToolbarLayout.scheduleFirstEditSelection(field)
        DeveloperToolbarSpring.shake(field, reduceMotion: reduceMotion)
    }
}

///
/// `validateMenuItem` falls through to `return true`; original-page/window
/// ownership still gates dispatch (`changeZoom` requires a tab identity).
enum PageZoomAvailability {
    static func canChange(windowReady: Bool, closing: Bool, hasOriginalPage: Bool) -> Bool {
        windowReady && !closing && hasOriginalPage
    }
}
