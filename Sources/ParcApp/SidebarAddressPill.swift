import AppKit
import QuartzCore

///
///
///
///
/// SidebarItemBackground, and SidebarItemHoveredBackground while the pointer is
///
/// In an incognito window (WindowStyle standard, sidebar context incognito)
/// the scheme's resting fill is CommandBarPlaceholderIncognitoBackground
///
@MainActor final class SidebarAddressPillView: NSView {
    static let cornerRadius: CGFloat = 12
    static let hoverDuration: CFTimeInterval = 0.12

    /// SidebarItemBackground / SidebarItemHoveredBackground (Display P3).
    static func fill(dark: Bool, hovered: Bool) -> NSColor {
        dark ? NSColor(displayP3Red: 0.98, green: 0.984, blue: 1, alpha: hovered ? 0.15 : 0.1)
             : NSColor(displayP3Red: 0.055, green: 0.059, blue: 0.063, alpha: hovered ? 0.1 : 0.05)
    }
    /// BaseAssets CommandBarPlaceholderIncognitoBackground: Display P3 white
    /// at 0.15 in every appearance.
    static let incognitoFill = NSColor(displayP3Red: 1, green: 1, blue: 1, alpha: 0.15)
    static func fill(dark: Bool, hovered: Bool, incognito: Bool) -> NSColor {
        incognito && !hovered ? incognitoFill : fill(dark: dark, hovered: hovered)
    }

    /// Parc's shared-quote mode shrinks the pill to the URL line with the quote
    /// below it, Parc's earlier surface: 7-point corners in the theme's hover
    ///
    /// (`CommandBarPlaceholderButtonState.StaticButtonState.copyQuoteLink`),
    /// whose presentation was not recovered.
    enum Style: Equatable { case urlBar, sharedQuote(fill: NSColor) }
    static let sharedQuoteCornerRadius: CGFloat = 7

    var dark = false { didSet { if dark != oldValue { applyFill(animated: false) } } }
    var incognito = false { didSet { if incognito != oldValue { applyFill(animated: false) } } }
    var style: Style = .urlBar {
        didSet {
            guard style != oldValue else { return }
            applyShape(); applyFill(animated: false)
        }
    }
    private var hovered = false
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        applyShape(); applyFill(animated: false)
    }
    private func applyShape() {
        switch style {
        case .urlBar: layer?.cornerRadius = Self.cornerRadius; layer?.cornerCurve = .continuous
        case .sharedQuote: layer?.cornerRadius = Self.sharedQuoteCornerRadius; layer?.cornerCurve = .circular
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { setHovered(false, animated: false) }
        super.viewWillMove(toWindow: newWindow)
    }

    func setHovered(_ hovered: Bool, animated: Bool = true) {
        guard hovered != self.hovered else { return }
        self.hovered = hovered
        applyFill(animated: animated)
    }

    /// A theme-free shared-quote fill is a system colour that equals itself
    /// across appearances, so `style` alone never re-resolves it.
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); applyFill(animated: false) }

    private func applyFill(animated: Bool) {
        guard let layer else { return }
        let color: CGColor
        switch style {
        case .urlBar: color = Self.fill(dark: dark, hovered: hovered, incognito: incognito).cgColor
        case .sharedQuote(let fill): color = fill.cgColor(in: effectiveAppearance)
        }
        guard layer.backgroundColor != color else { return }
        if animated, style == .urlBar, window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = CABasicAnimation(keyPath: "backgroundColor")
            animation.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
            animation.toValue = color
            animation.duration = Self.hoverDuration
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "backgroundColor")
        } else {
            layer.removeAnimation(forKey: "backgroundColor")
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.backgroundColor = color
        CATransaction.commit()
    }
}

/// The empty URL bar's `CommandBarPlaceholderView.iconView`, a
/// `CommandBarIconView` whose `IconType` has `searchOutline`, beside
///
///
/// glyph's centre, its 11-point ink and the text's start are measured on
///
@MainActor final class SidebarAddressSearchIcon: NSImageView {
    static let placeholder = "Search or Enter URL…"
    /// The URL bar reads the page's host without one leading "www.": the
    ///
    ///
    static func host(of url: URL) -> String? {
        guard let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
    static let centerX: CGFloat = 16
    static let textIndent: CGFloat = 32
    static let side: CGFloat = 14

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        imageScaling = .scaleNone
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

///
///
/// its anchor and then shows its popover from it at once, so this hold
/// follows the next popover shown and ends when that popover closes, or on
/// the next turn of the run loop if none was shown.
@MainActor final class AddressPopoverRevealHold {
    private var observers: [NSObjectProtocol] = []
    private var popover: NSPopover?
    private var onEnd: (() -> Void)?

    init(onEnd: @escaping () -> Void) {
        self.onEnd = onEnd
        observers.append(NotificationCenter.default.addObserver(forName: NSPopover.willShowNotification, object: nil,
                                                                queue: nil) { [weak self] notification in
            MainActor.assumeIsolated { self?.follow(notification.object as? NSPopover) }
        })
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { if self?.popover == nil { self?.end() } }
        }
    }

    private func follow(_ shown: NSPopover?) {
        guard popover == nil, onEnd != nil, let shown else { return }
        popover = shown
        removeObservers()
        observers.append(NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: shown,
                                                                queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.end() }
        })
    }

    func end() {
        removeObservers()
        popover = nil
        let onEnd = onEnd
        self.onEnd = nil
        onEnd?()
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }
}

///
/// pinned extensions are revealed by the view state's computed predicate
///
///
///
/// change from the presentation opacity over 0.15 s ease-out.
enum SidebarAddressButtonsReveal {
    static let fadeDuration: CFTimeInterval = 0.15

    static func revealed(sidebarHovered: Bool, showingMenu: Bool, anchored: Bool) -> Bool {
        sidebarHovered || showingMenu || !anchored
    }
    static func showsSiteControlCenter(revealed: Bool, copyQuoteLink: Bool) -> Bool { revealed || copyQuoteLink }

    /// Parc adaptation: a hidden button stays in the key-view loop and the
    ///
    /// also reveals while one of the pill's controls has keyboard focus.
    @MainActor static func apply(_ shown: Bool, to view: NSView, animated: Bool) {
        let alpha: CGFloat = shown ? 1 : 0
        guard view.alphaValue != alpha else { return }
        guard animated, view.window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            view.alphaValue = alpha; return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.animator().alphaValue = alpha
        }
    }
}
