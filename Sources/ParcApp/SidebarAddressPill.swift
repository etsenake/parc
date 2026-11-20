import AppKit
import QuartzCore

@MainActor final class SidebarAddressPillView: NSView {
    static let cornerRadius: CGFloat = 12
    static let hoverDuration: CFTimeInterval = 0.12

    static func fill(dark: Bool, hovered: Bool) -> NSColor {
        dark ? NSColor(displayP3Red: 0.98, green: 0.984, blue: 1, alpha: hovered ? 0.15 : 0.1)
             : NSColor(displayP3Red: 0.055, green: 0.059, blue: 0.063, alpha: hovered ? 0.1 : 0.05)
    }
    static let incognitoFill = NSColor(displayP3Red: 1, green: 1, blue: 1, alpha: 0.15)
    static func fill(dark: Bool, hovered: Bool, incognito: Bool) -> NSColor {
        incognito && !hovered ? incognitoFill : fill(dark: dark, hovered: hovered)
    }

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
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { setHovered((superview ?? self).isTopmost(atWindowPoint: event.locationInWindow)) }
    override func mouseMoved(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { super.mouseMoved(with: event); return }
        setHovered((superview ?? self).isTopmost(atWindowPoint: event.locationInWindow))
    }
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

@MainActor final class SidebarAddressSearchIcon: NSImageView {
    static let placeholder = SidebarAddressText.placeholder
    static func host(of url: URL) -> String? { SidebarAddressText.host(of: url) }
    static let centerX: CGFloat = 16
    static let textIndent: CGFloat = 32
    static let side: CGFloat = 14
    static let glyph = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        image = Self.glyph
        imageScaling = .scaleNone
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor final class AddressPopoverRevealHold {
    private var observers: [NSObjectProtocol] = []
    private var popover: NSPopover?
    private weak var window: NSWindow?
    private var isOpen: ((NSWindow) -> Bool)?
    private var onEnd: (() -> Void)?

    init(window: NSWindow, isOpen: @escaping (NSWindow) -> Bool, onEnd: @escaping () -> Void) {
        self.window = window
        self.isOpen = isOpen
        self.onEnd = onEnd
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.end() }
        })
        observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.endIfWindowClosed() }
        })
    }

    func endIfWindowClosed() {
        guard let isOpen else { return }
        if window.map(isOpen) != true { end() }
    }

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
        window = nil
        isOpen = nil
        let onEnd = onEnd
        self.onEnd = nil
        onEnd?()
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }
}

enum SidebarAddressButtonsReveal {
    static let fadeDuration: CFTimeInterval = 0.15

    static func revealed(sidebarHovered: Bool, showingMenu: Bool, anchored: Bool, voiceOverRunning: Bool) -> Bool {
        sidebarHovered || showingMenu || !anchored || voiceOverRunning
    }
    static func showsSiteControlCenter(revealed: Bool, copyQuoteLink: Bool) -> Bool { revealed || copyQuoteLink }
    @MainActor static func holdsExtensionPopup(_ popup: NSWindow, of window: NSWindow, showsPage: Bool, atSidebar: Bool) -> Bool {
        popup.parent === window && showsPage && atSidebar
    }
    @MainActor static func extensionPopupOpen(_ popup: NSWindow, of window: NSWindow?) -> Bool {
        window.map { popup.parent === $0 } == true
    }
    static func extensionPopupLoading(attached: Bool, visible: Bool, showsPage: Bool) -> Bool {
        showsPage && !attached && !visible
    }

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
