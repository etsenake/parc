import AppKit
import QuartzCore

@MainActor final class PaneTitleControl: PointingHandButton {
    var actionBlock: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?
    private let label = PaneTitleLabel(labelWithString: "")
    private let surface = CALayer()
    private var primary = ""
    private var suffix: String?
    private var webURL = false
    private var allocatedTitleWidth: CGFloat?
    private var area: NSTrackingArea?
    private var observers: [NSObjectProtocol] = []
    private var appearanceObserver: NSObjectProtocol?
    private(set) var isHovered = false
    private(set) var isPressed = false
    var standingHighlight = false { didSet { refresh(animated: false) } }
    override var isFlipped: Bool { true }
    override var isEnabled: Bool { didSet { if !isEnabled { clearInteraction() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        let nativeCell = PaneTitleCell(); cell = nativeCell
        setButtonType(.momentaryPushIn)
        nativeCell.highlightsBy = []; nativeCell.showsStateBy = []
        isBordered = false; title = ""; focusRingType = .exterior
        target = self; action = #selector(invoke)
        wantsLayer = true; surface.cornerRadius = 6; surface.cornerCurve = .continuous
        layer?.addSublayer(surface)
        label.isSelectable = false; label.maximumNumberOfLines = 1
        label.cell?.usesSingleLineMode = true; label.alignment = .center
        label.setAccessibilityElement(false); addSubview(label)
        SidebarMotionController.pinDrawnContent(label, to: .center)
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityChildren([])
        appearanceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh(animated: false) } }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func update(_ value: BrowserToolbarAddress) {
        primary = value.primary; suffix = value.suffix; webURL = value.isWebURL
        toolTip = value.fullURL
        setAccessibilityLabel(value.fullURL.isEmpty ? "Address" : "Address: " + value.fullURL)
        refresh(animated: false); needsLayout = true; superview?.needsLayout = true
    }
    func updateTitle(_ title: String) {
        primary = title; suffix = nil; webURL = false
        toolTip = title; setAccessibilityLabel(title)
        refresh(animated: false); needsLayout = true; superview?.needsLayout = true
    }
    func place(in slot: NSRect) {
        allocatedTitleWidth = max(0, slot.width)
        refreshText()
        let textSize = label.attributedStringValue.size()
        let width = min(max(0, slot.width), ceil(textSize.width) + 12)
        let height = min(max(0, slot.height), ceil(textSize.height) + 8)
        frame = NSRect(x: slot.midX - width / 2, y: slot.midY - height / 2, width: width, height: height)
        needsLayout = true
    }
    @objc private func invoke() { guard isEnabled else { return }; actionBlock?() }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(!NSAnimationContext.current.allowsImplicitAnimation)
        surface.frame = bounds
        CATransaction.commit()
        refreshText()
        let textSize = label.attributedStringValue.size()
        let height = min(max(0, bounds.height - 8), ceil(textSize.height))
        let cellInset = max(0, ((label.cell?.cellSize.width ?? textSize.width) - textSize.width) / 2)
        let inset = max(0, 6 - cellInset)
        label.frame = NSRect(x: inset, y: (bounds.height - height) / 2,
                             width: max(0, bounds.width - inset * 2), height: height)
    }
    private func refreshText() {
        let complete = displayText(includingSuffix: true)
        let available = allocatedTitleWidth ?? bounds.width
        let fits = complete.size().width + 16 + 10 <= available
        label.attributedStringValue = displayText(includingSuffix: fits)
        label.lineBreakMode = webURL && (!fits || suffix == nil) ? .byTruncatingHead : .byTruncatingTail
    }
    private func displayText(includingSuffix: Bool) -> NSAttributedString {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let ink = dark ? NSColor.white : .black
        let alpha: CGFloat = dark ? 0.75 : 0.6
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let visibleSuffix = includingSuffix ? suffix : nil
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        paragraph.lineBreakMode = webURL && visibleSuffix == nil ? .byTruncatingHead : .byTruncatingTail
        let text = NSMutableAttributedString(string: primary, attributes: [
            .font: font, .foregroundColor: ink.withAlphaComponent(alpha), .paragraphStyle: paragraph])
        if let visibleSuffix {
            text.append(NSAttributedString(string: visibleSuffix, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: ink.withAlphaComponent(alpha * 5 / 6), .paragraphStyle: paragraph]))
        }
        return text
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refresh(animated: false) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }; area = nil
        guard window != nil, !isHiddenOrHasHiddenAncestor, !bounds.isEmpty else { clearInteraction(); return }
        let next = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        area = next; addTrackingArea(next)
        sampleHover()
    }
    private func sampleHover() {
        guard let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor, isEnabled else {
            isHovered = false; refresh(animated: false); return
        }
        isHovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        refresh(animated: false)
    }
    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea === area, area != nil, window?.isKeyWindow == true,
              !isHiddenOrHasHiddenAncestor, isEnabled else { return }
        isHovered = true; refresh(animated: true)
    }
    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea === area, area != nil else { return }
        isHovered = false; refresh(animated: true)
    }
    fileprivate func nativeHighlight(_ highlighted: Bool) {
        isPressed = highlighted && isEnabled && window?.isKeyWindow == true && !isHiddenOrHasHiddenAncestor
        refresh(animated: true, pressed: true)
    }
    private func refresh(animated: Bool, pressed: Bool = false) {
        refreshText()
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let opacity: Float = isPressed ? (dark ? 0.15 : 0.11) : isHovered ? (dark ? 0.11 : 0.07)
            : standingHighlight ? (dark ? 0.09 : 0.05) : 0
        let old = surface.presentation()?.opacity ?? surface.opacity
        CATransaction.begin(); CATransaction.setDisableActions(true)
        surface.backgroundColor = (dark ? NSColor.white : .black).cgColor
        surface.removeAnimation(forKey: "pane-title-opacity"); surface.opacity = opacity
        CATransaction.commit()
        guard animated, old != opacity, window?.isKeyWindow == true, !isHiddenOrHasHiddenAncestor,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = old; animation.toValue = opacity; animation.duration = pressed ? 0.16 : 0.18
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        surface.add(animation, forKey: "pane-title-opacity")
    }
    func titleMenu() -> NSMenu? {
        guard isEnabled, !isHiddenOrHasHiddenAncestor, window?.isKeyWindow == true else { return nil }
        return menuProvider?()
    }
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = titleMenu() else { super.rightMouseDown(with: event); return }
        clearInteraction()
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    override func accessibilityPerformShowMenu() -> Bool {
        guard let menu = titleMenu() else { return false }
        return menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY), in: self)
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill() }
    private func clearInteraction() { isHovered = false; isPressed = false; refresh(animated: false) }
    override func viewDidHide() { super.viewDidHide(); clearInteraction() }
    override func viewWillMove(toSuperview newSuperview: NSView?) { super.viewWillMove(toSuperview: newSuperview); clearInteraction() }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let area { removeTrackingArea(area) }; area = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        clearInteraction(); super.viewWillMove(toWindow: newWindow)
        if let newWindow {
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSWindow.didBecomeKeyNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: newWindow, queue: .main) { [weak self, weak newWindow] _ in
                    MainActor.assumeIsolated {
                        guard let self, let newWindow, self.window === newWindow else { return }
                        if name == NSWindow.didBecomeKeyNotification { self.sampleHover() }
                        else { self.clearInteraction() }
                    }
                })
            }
        }
    }
    deinit {
        MainActor.assumeIsolated {
            observers.forEach(NotificationCenter.default.removeObserver)
            if let appearanceObserver { NSWorkspace.shared.notificationCenter.removeObserver(appearanceObserver) }
        }
    }
}

@MainActor private final class PaneTitleLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
@MainActor private final class PaneTitleCell: NSButtonCell {
    override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {
        super.highlight(flag, withFrame: cellFrame, in: controlView)
        (controlView as? PaneTitleControl)?.nativeHighlight(flag)
    }
}

struct PaneTitleLayout {
    static let balanceWidth: CGFloat = 19
    static func slot(in bounds: NSRect, leftEssential: CGFloat, rightEssential: CGFloat,
                     requiredLeft: CGFloat, requiredRight: CGFloat,
                     balancesCopy: Bool, balancesInsecure: Bool = false) -> NSRect {
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.minX.isFinite,
              bounds.minY.isFinite, leftEssential.isFinite, rightEssential.isFinite,
              requiredLeft.isFinite, requiredRight.isFinite else { return .zero }
        let side = (balancesCopy ? balanceWidth : 0) + (balancesInsecure ? balanceWidth : 0)
        let left = max(0, leftEssential - bounds.minX)
        let right = max(0, bounds.maxX - rightEssential)
        let stack = max(150, bounds.width - 2 * max(left, right) - 4)
        let room = max(0, 2 * min(bounds.midX - requiredLeft, requiredRight - bounds.midX))
        let width = min(room, max(0, stack - 2 * side))
        return NSRect(x: bounds.midX - width / 2, y: bounds.minY,
                      width: width, height: max(0, bounds.height))
    }
}

@MainActor enum PaneShareMenu {
    static func item(for url: URL?, services: @MainActor ([URL]) -> [NSSharingService] = sharingServices(for:)) -> NSMenuItem {
        let item = NSMenuItem(title: "Share", action: nil, keyEquivalent: "")
        guard let url, let submenu = menu(for: [url], services: services) else { item.isEnabled = false; return item }
        item.submenu = submenu
        return item
    }
    static func menu(for urls: [URL], services: @MainActor ([URL]) -> [NSSharingService] = sharingServices(for:)) -> NSMenu? {
        guard !urls.isEmpty else { return nil }
        let available = services(urls)
        guard !available.isEmpty else { return nil }
        let menu = NSMenu(); menu.autoenablesItems = false
        for service in available {
            let entry = NSMenuItem(title: service.menuItemTitle, action: #selector(ShareAction.share), keyEquivalent: "")
            let action = ShareAction(service: service, urls: urls)
            entry.target = action; entry.representedObject = action; entry.showImage(service.image)
            menu.addItem(entry)
        }
        return menu
    }
    static func popUp(for urls: [URL], at location: NSPoint? = nil) {
        menu(for: urls)?.popUp(positioning: nil, at: location ?? NSEvent.mouseLocation, in: nil)
    }
    static func sharingServices(for urls: [URL]) -> [NSSharingService] {
        let selector = NSSelectorFromString("sharingServicesForItems:")
        let owner: AnyObject = NSSharingService.self
        guard owner.responds(to: selector) else { return [] }
        return owner.perform(selector, with: urls)?.takeUnretainedValue() as? [NSSharingService] ?? []
    }
    @MainActor final class ShareAction: NSObject {
        let service: NSSharingService
        let urls: [URL]
        init(service: NSSharingService, urls: [URL]) { self.service = service; self.urls = urls }
        @objc func share() { service.perform(withItems: urls) }
    }
}

enum PaneMenuContent: Equatable {
    case web, document, none
    init(livePage: Bool, tabURL: String?, localDocument: Bool) {
        if livePage { self = .web; return }
        guard let tabURL, !tabURL.isEmpty, tabURL != "about:blank" else { self = .none; return }
        self = localDocument ? .document : .web
    }
}

enum PaneSurface: Equatable {
    case page, failure, local
    func usesPageBar(pageLive: Bool) -> Bool { pageLive && self != .local }
}
