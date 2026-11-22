import AppKit
import QuartzCore

@MainActor
final class BrowserToolbarView: NSView {
    enum Action { case address, copy, siteInfo, siteInsecure, pageMenu, split, closeSplit, sidebar, blocked }
    static let height = PaneTopBarLayout.height
    var onAction: ((Action, NSView) -> Void)?
    var onNavigation: ((NavigationControlKind) -> NavigationControlInteraction?)?
    var onEscape: (() -> Void)?
    var reducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private(set) var pageColor: NSColor?
    var themeBackground: NSColor? { didSet { if themeBackground != oldValue { applyColors(animated: false) } } }
    let extensionToolbar = ExtensionToolbarView(style: .toolbar)
    private let back = NavigationControlButton("Go back", symbol: "arrow.left", history: true, commandID: "goBack:")
    private let forward = NavigationControlButton("Go forward", symbol: "arrow.right", history: true, commandID: "goForward:")
    private let reload = NavigationControlButton("Reload this page", symbol: "arrow.clockwise", commandID: "reload:")
    private let address = PaneTitleControl(frame: .zero)
    private let copy = BrowserToolbarActionButton("Copy Current URL", symbol: "link")
    private let siteInfo = BrowserToolbarActionButton("Site Control Center", symbol: "slider.horizontal.3")
    private let blocked = BrowserToolbarActionButton("Blocked", symbol: "nosign")
    private var blockedContent: BlockedPageContent?
    private let split = SplitPaneControl(.menu)
    private let closeSplit = SplitPaneControl(.close)
    private let insecure = SplitPaneControl(.insecure)
    private let sidebar = BrowserToolbarActionButton("Show sidebar", symbol: "sidebar.left")
    private(set) var controlsRevealed = true
    var onTitleMenu: (() -> NSMenu?)? { get { address.menuProvider } set { address.menuProvider = newValue } }
    private(set) var obstructedByModal = false
    private var actionsEnabled = false
    private var showsClose = false
    private var showsSidebar = false
    private var showsInsecure = false
    private var copyAvailable = false
    private var showsSiteControls = true
    private var extensionsAlpha: CGFloat = 1
    var ownsFocus: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder === self || responder.isDescendant(of: self)
    }
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        SidebarMotionController.pinDrawnContent(self, to: .scaleAxesIndependently)
        setAccessibilityRole(.toolbar); setAccessibilityLabel("Toolbar")
        for (button, action, id) in [(copy, Action.copy, "copyCurrentURL:"), (siteInfo, .siteInfo, nil), (sidebar, .sidebar, "toggleSidebar:")] {
            LiveShortcutToolTip.set(button, button.title, commandID: id); button.setAccessibilityLabel(button.title)
            button.focusRingType = .exterior
            button.actionBlock = { [weak self, weak button] in guard let self, let button else { return }; self.onAction?(action, button) }
            addSubview(button)
        }
        if let glyph = SiteControlCenterArtwork.controlCenter { siteInfo.image = glyph }
        siteInfo.secondaryActionBlock = { [weak self] in
            guard let self else { return }; self.onAction?(.pageMenu, self.siteInfo)
        }
        for (button, action) in [(split, Action.split), (closeSplit, .closeSplit)] {
            button.actionBlock = { [weak self, weak button] in
                guard let self, let button else { return }; self.onAction?(action, button)
            }
            addSubview(button)
        }
        insecure.actionBlock = { [weak self] in
            guard let self else { return }; self.onAction?(.siteInsecure, self.siteInfo)
        }
        addSubview(insecure)
        insecure.isHidden = true
        blocked.focusRingType = .exterior
        blocked.actionBlock = { [weak self] in
            guard let self else { return }; self.onAction?(.blocked, self.blocked)
        }
        blocked.isHidden = true
        addSubview(blocked)
        for button in [back, forward, reload] { addSubview(button) }
        back.prepareInteraction = { [weak self] in self?.onNavigation?(.back) }
        forward.prepareInteraction = { [weak self] in self?.onNavigation?(.forward) }
        reload.prepareInteraction = { [weak self] in self?.onNavigation?(.reload) }
        address.actionBlock = { [weak self] in
            guard let self else { return }; self.onAction?(.address, self.address)
        }
        addSubview(address)
        address.setAccessibilityHelp("Edit the current tab’s address.")
        extensionToolbar.onWidthChange = { [weak self] in self?.needsLayout = true }
        addSubview(extensionToolbar); applyColors(animated: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { if let sampledColorObserver { NotificationCenter.default.removeObserver(sampledColorObserver.token) } }
    private weak var sampledPage: AnyObject?
    private var sampledColorRefresh: (@MainActor (AnyObject) -> Void)?
    private var sampledColorObserver: (name: Notification.Name, token: NSObjectProtocol)?
    func followSampledColor(of page: AnyObject?, changes name: Notification.Name,
                            refresh: @escaping @MainActor (AnyObject) -> Void) {
        sampledPage = page
        sampledColorRefresh = page == nil ? nil : refresh
        if let observer = sampledColorObserver, observer.name != name {
            NotificationCenter.default.removeObserver(observer.token)
            sampledColorObserver = nil
        }
        guard page != nil, sampledColorObserver == nil else { return }
        let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let object = note.object.map({ $0 as AnyObject }), object === self.sampledPage,
                      !self.isHidden else { return }
                self.sampledColorRefresh?(object)
            }
        }
        sampledColorObserver = (name, token)
    }
    func update(url: URL?, documentTitle: String? = nil, fullURL: Bool, enabled: Bool, canBack: Bool, canForward: Bool,
                loading: Bool, canReload: Bool, canCopy: Bool, canShowSiteInfo: Bool,
                canSplit: Bool, close: Bool, showSidebar: Bool, insecure isInsecure: Bool = false,
                siteControls: Bool = true, extensionItems: [ExtensionControlItem]) {
        actionsEnabled = enabled
        if let documentTitle { address.updateTitle(documentTitle) }
        else { address.update(BrowserToolbarAddress(url: url, full: fullURL)) }
        address.isEnabled = enabled
        back.isEnabled = enabled && canBack; forward.isEnabled = enabled && canForward
        reload.setLoading(loading, enabled: enabled && canReload)
        copy.isEnabled = enabled && canCopy; siteInfo.isEnabled = enabled && canShowSiteInfo
        split.isEnabled = enabled && canSplit
        closeSplit.isEnabled = enabled && close; sidebar.isEnabled = enabled
        insecure.isEnabled = enabled
        showsClose = close; showsSidebar = showSidebar; showsInsecure = isInsecure; copyAvailable = canCopy
        showsSiteControls = siteControls
        extensionToolbar.update(enabled && siteControls ? extensionItems : [])
        if controlsRevealed, extensionsTarget != extensionsAlpha {
            PaneTopBarFade.set([extensionToolbar], alpha: extensionsTarget, duration: nil)
        }
        extensionsAlpha = extensionsTarget
        needsLayout = true
    }
    private var extensionsTarget: CGFloat { controlsRevealed ? (actionsEnabled ? 1 : 0.5) : 0 }
    func updateExtensionItems(_ items: [ExtensionControlItem]) {
        extensionToolbar.update(actionsEnabled && showsSiteControls ? items : [])
    }
    var siteControlCenterAnchor: NSView? { siteInfo.isHidden || siteInfo.isHiddenOrHasHiddenAncestor ? nil : siteInfo }
    func updateBlockedContent(_ content: BlockedPageContent?) {
        guard content != blockedContent else { return }
        let appearing = blockedContent == nil && content != nil
        if let content {
            if content.glyphName != blockedContent?.glyphName { blocked.image = SiteControlCenterArtwork.image(content.glyphName) }
            LiveShortcutToolTip.set(blocked, content.summary)
            blocked.setAccessibilityLabel(content.summary)
            blocked.setAccessibilityHelp(BlockedContentSign.help)
        }
        blockedContent = content
        if appearing { BlockedContentSign.reveal(blocked, animated: true, alpha: 1) }
        needsLayout = true
    }
    func setObstructedByModal(_ obstructed: Bool, animated: Bool) {
        guard obstructed != obstructedByModal else { return }
        obstructedByModal = obstructed
        PaneTopBarFade.set([back, forward], alpha: obstructed ? 0 : 1,
                           duration: animated ? PaneTopBarFade.obstruction : nil)
    }
    func setControlsRevealed(_ revealed: Bool, duration: TimeInterval? = nil) {
        controlsRevealed = revealed
        PaneTopBarFade.set([split, reload, siteInfo], alpha: revealed ? 1 : 0, duration: duration)
        extensionsAlpha = extensionsTarget
        PaneTopBarFade.set([extensionToolbar], alpha: extensionsAlpha, duration: duration)
    }
    override func layout() {
        super.layout()
        let width = max(0, bounds.width), unit: CGFloat = 28
        var left = PaneTopBarLayout.horizontalInset
        sidebar.isHidden = !showsSidebar
        if showsSidebar { sidebar.frame = PaneTopBarLayout.frame(x: left, width: unit, height: 28); left += unit }
        back.isHidden = false; forward.isHidden = false
        back.frame = PaneTopBarLayout.frame(x: left, width: unit, height: 28); left += unit
        forward.frame = PaneTopBarLayout.frame(x: left, width: unit, height: 28); left += unit
        reload.isHidden = false
        reload.frame = PaneTopBarLayout.frame(x: left, width: unit, height: 28); left += unit
        var right = width - PaneTopBarLayout.horizontalInset
        closeSplit.isHidden = !showsClose
        let splitSize = SplitPaneControl.surfaceSize
        if showsClose { right -= splitSize.width; closeSplit.frame = PaneTopBarLayout.frame(x: right, width: splitSize.width, height: splitSize.height) }
        for button in (showsSiteControls ? [split, siteInfo] : [split]) as [NSButton] {
            button.isHidden = false
            let size = button === split ? splitSize : NSSize(width: unit, height: 28)
            right -= size.width; button.frame = PaneTopBarLayout.frame(x: right, width: size.width, height: size.height)
        }
        var showsBlocked = showsSiteControls && blockedContent != nil
        var collapsesSiteInfo = false
        if showsBlocked {
            let bar = PaneTopBarLayout.frame(x: 0, width: width, height: 28)
            let closeEdge = showsClose ? closeSplit.frame.minX : width - PaneTopBarLayout.horizontalInset
            let titleWidth = { (edge: CGFloat) -> CGFloat in
                let leading = min(closeEdge, self.split.frame.minX, edge)
                return PaneTitleLayout.slot(in: bar, leftEssential: left, rightEssential: leading,
                    requiredLeft: self.forward.frame.maxX + 2, requiredRight: leading - 2,
                    balancesCopy: true, balancesInsecure: self.showsInsecure).width
            }
            if titleWidth(right - unit) >= BlockedContentSign.toolbarTitleRoom {
                right -= unit; blocked.frame = PaneTopBarLayout.frame(x: right, width: unit, height: 28)
            } else if titleWidth(siteInfo.frame.minX) >= BlockedContentSign.toolbarTitleRoom {
                collapsesSiteInfo = true; blocked.frame = siteInfo.frame
            } else { showsBlocked = false }
        }
        blocked.isHidden = !showsBlocked
        let rightEssential = showsClose ? closeSplit.frame.minX : width - PaneTopBarLayout.horizontalInset
        let splitLeading = min(rightEssential, split.frame.minX, showsBlocked ? blocked.frame.minX : .greatestFiniteMagnitude)
        let requiredLeft = forward.frame.maxX
        let slot = PaneTitleLayout.slot(in: PaneTopBarLayout.frame(x: 0, width: width, height: 28),
            leftEssential: left, rightEssential: splitLeading,
            requiredLeft: requiredLeft + 2, requiredRight: splitLeading - 2,
            balancesCopy: true, balancesInsecure: showsInsecure)
        address.place(in: slot)
        let lockWidth = showsInsecure ? PaneTitleLayout.balanceWidth : 0
        insecure.frame = PaneTopBarLayout.frame(x: address.frame.minX - PaneTitleLayout.balanceWidth,
            width: SplitPaneControl.insecureSurfaceSize.width, height: SplitPaneControl.insecureSurfaceSize.height)
        insecure.isHidden = !showsInsecure || !(requiredLeft < insecure.frame.minX)
        copy.frame = PaneTopBarLayout.frame(x: address.frame.minX - lockWidth - PaneTitleLayout.balanceWidth,
                                            width: PaneTitleLayout.balanceWidth, height: 24)
        copy.isHidden = !copyAvailable || !(requiredLeft < copy.frame.minX) || !bounds.contains(copy.frame)
        let centerStart = !copy.isHidden ? copy.frame.minX : !insecure.isHidden ? insecure.frame.minX : address.frame.minX
        reload.isHidden = reload.frame.maxX >= centerStart
        siteInfo.isHidden = !showsSiteControls || collapsesSiteInfo || address.frame.maxX >= siteInfo.frame.minX
        let pinSize = extensionToolbar.style.surfaceSize
        let pins = min(extensionToolbar.desiredWidth, max(0, floor((right - address.frame.maxX) / pinSize.width) * pinSize.width))
        extensionToolbar.frame = PaneTopBarLayout.frame(x: right - pins, width: pins, height: pinSize.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        (inkDark ? NSColor.white : .black).withAlphaComponent(0.10).setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }
    private var inkDark = false
    private weak var pageColorOwner: AnyObject?
    func setPageColor(_ color: NSColor?, for owner: AnyObject?, holdingWhileUnknown: Bool = false, animated: Bool? = nil) {
        let fill = PaneTopBarColor.fill(from: color)
        let sameOwner = owner != nil && owner === pageColorOwner
        pageColorOwner = owner
        if fill == nil, holdingWhileUnknown, sameOwner { return }
        guard fill != pageColor else { return }
        pageColor = fill
        applyColors(animated: sameOwner && (animated ?? true))
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); applyColors(animated: false) }
    private func applyColors(animated: Bool) {
        let windowDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        var theme: NSColor?, fill: CGColor = NSColor.clear.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            theme = themeBackground?.usingColorSpace(.deviceRGB)
            fill = (pageColor ?? PaneTopBarColor.backing).cgColor
        }
        let dark = pageColor.flatMap(PaneTopBarColor.usesDarkScheme(on:))
            ?? theme.flatMap { PaneTopBarColor.usesDarkScheme(backingOver: $0, windowDark: windowDark) }
        let scheme = dark.flatMap { NSAppearance(named: $0 ? .darkAqua : .aqua) }
        for view in subviews where view.appearance?.name != scheme?.name { view.appearance = scheme }
        inkDark = dark ?? windowDark
        if let layer, layer.backgroundColor != fill {
            let from = layer.presentation()?.backgroundColor ?? layer.backgroundColor
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer.removeAnimation(forKey: "page-color"); layer.backgroundColor = fill
            CATransaction.commit()
            if animated, window != nil, !reducesMotion() {
                let fade = CABasicAnimation(keyPath: "backgroundColor")
                fade.fromValue = from; fade.toValue = fill; fade.duration = PaneTopBarColor.crossfadeDuration
                fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(fade, forKey: "page-color")
            }
        }
        for button in [back, forward, reload] as [NSButton] {
            button.contentTintColor = PaneTopBarColor.glyph(dark: inkDark)
        }
        needsDisplay = true
    }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    func invalidate() { onAction = nil; onNavigation = nil; onEscape = nil; onTitleMenu = nil; extensionToolbar.update([]); updateBlockedContent(nil) }
}

enum BrowserToolbarActionSurfaceLayoutSkip {
    static func shouldSkip(current: CGRect, next: CGRect) -> Bool { current == next }
}

@MainActor final class BrowserToolbarActionButton: PointingHandButton {
    var actionBlock: (() -> Void)?
    var reducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private let surface = CALayer()
    private var area: NSTrackingArea?
    private var observers: [NSObjectProtocol] = []
    private var optionsObserver: NSObjectProtocol?
    private(set) var isHovered = false
    private(set) var isPressed = false
    var activityFill: CGFloat = 0 { didSet { if activityFill != oldValue { refresh(animated: false) } } }
    var glyphLift: CGFloat = 0 { didSet { if glyphLift != oldValue { needsDisplay = true } } }
    override var isEnabled: Bool {
        didSet { guard oldValue != isEnabled else { return }; if isEnabled { sampleHover() } else { clearInteraction() } }
    }

    init(_ title: String, symbol: String) {
        super.init(frame: .zero)
        let nativeCell = BrowserToolbarActionCell(); cell = nativeCell
        setButtonType(.momentaryPushIn)
        nativeCell.highlightsBy = []; nativeCell.showsStateBy = []
        nativeCell.imageDimsWhenDisabled = false
        isBordered = false; bezelStyle = .regularSquare
        self.title = title
        font = .systemFont(ofSize: 12, weight: .medium)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        imagePosition = .imageOnly
        target = self; action = #selector(invoke)
        setAccessibilityLabel(title)
        wantsLayer = true; surface.cornerRadius = 6; surface.cornerCurve = .continuous
        layer?.addSublayer(surface)
        optionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh(animated: false, resetsMotion: true) } }
        refresh(animated: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        MainActor.assumeIsolated {
            observers.forEach(NotificationCenter.default.removeObserver)
            if let optionsObserver { NSWorkspace.shared.notificationCenter.removeObserver(optionsObserver) }
        }
    }
    private var surfaceFrame: NSRect {
        let height = min(bounds.height, 24)
        return NSRect(x: bounds.minX, y: bounds.midY - height / 2, width: bounds.width, height: height)
    }
    override func layout() {
        super.layout()
        let next = surfaceFrame
        guard !BrowserToolbarActionSurfaceLayoutSkip.shouldSkip(current: surface.frame, next: next) else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        surface.frame = next
        CATransaction.commit()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refresh(animated: false) }
    override func draw(_ dirtyRect: NSRect) {
        guard glyphLift != 0, let context = NSGraphicsContext.current?.cgContext else { super.draw(dirtyRect); return }
        context.saveGState()
        context.translateBy(x: 0, y: isFlipped ? -glyphLift : glyphLift)
        super.draw(dirtyRect)
        context.restoreGState()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }; area = nil
        guard window != nil, !isHiddenOrHasHiddenAncestor, !bounds.isEmpty else { clearInteraction(); return }
        let next = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow], owner: self)
        area = next; addTrackingArea(next)
        sampleHover()
    }
    private func sampleHover() {
        guard let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor, isEnabled else {
            isHovered = false; refresh(animated: false); return
        }
        let point = window.mouseLocationOutsideOfEventStream
        isHovered = bounds.contains(convert(point, from: nil)) && isTopmost(atWindowPoint: point)
        refresh(animated: false)
    }
    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea === area, area != nil, window?.isKeyWindow == true,
              !isHiddenOrHasHiddenAncestor, isEnabled else { return }
        isHovered = isTopmost(atWindowPoint: event.locationInWindow); refresh(animated: true)
    }
    override func mouseMoved(with event: NSEvent) {
        guard area != nil, bounds.contains(convert(event.locationInWindow, from: nil)) else { super.mouseMoved(with: event); return }
        let value = window?.isKeyWindow == true && !isHiddenOrHasHiddenAncestor && isEnabled
            && isTopmost(atWindowPoint: event.locationInWindow)
        guard value != isHovered else { return }
        isHovered = value; refresh(animated: true)
    }
    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea === area, area != nil else { return }
        isHovered = false; refresh(animated: true)
    }
    fileprivate func nativeHighlight(_ highlighted: Bool) {
        isPressed = highlighted && isEnabled && window?.isKeyWindow == true && !isHiddenOrHasHiddenAncestor
        refresh(animated: true, pressed: true)
    }
    private func refresh(animated: Bool, pressed: Bool = false, resetsMotion: Bool = false) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let ink: NSColor = dark ? .white : .black
        contentTintColor = ink.withAlphaComponent(isEnabled ? (dark ? 0.675 : 0.55) : 0.25)
        let pressedOpacity: Float = dark ? 0.13 : 0.09
        let interaction: Float = isPressed ? pressedOpacity : isHovered ? (dark ? 0.09 : 0.05) : 0
        let opacity: Float = isEnabled ? max(interaction, pressedOpacity * Float(activityFill)) : 0
        let old = surface.presentation()?.opacity ?? surface.opacity
        CATransaction.begin(); CATransaction.setDisableActions(true)
        surface.backgroundColor = ink.cgColor
        guard resetsMotion || opacity != surface.opacity else { CATransaction.commit(); return }
        surface.removeAnimation(forKey: "toolbar-action-opacity"); surface.opacity = opacity
        CATransaction.commit()
        guard animated, old != opacity, window?.isKeyWindow == true, !isHiddenOrHasHiddenAncestor,
              !reducesMotion() else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = old; animation.toValue = opacity; animation.duration = pressed ? 0.16 : 0.18
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        surface.add(animation, forKey: "toolbar-action-opacity")
    }
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
                        if name == NSWindow.didBecomeKeyNotification { self.sampleHover() } else { self.clearInteraction() }
                    }
                })
            }
        }
    }
    @objc private func invoke() { guard isEnabled else { return }; actionBlock?() }
    var secondaryActionBlock: (() -> Void)?
    override func rightMouseDown(with event: NSEvent) {
        guard let secondaryActionBlock, isEnabled else { super.rightMouseDown(with: event); return }
        secondaryActionBlock()
    }
    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.control), let secondaryActionBlock, isEnabled else {
            super.mouseDown(with: event); return
        }
        secondaryActionBlock()
    }
    override func accessibilityPerformShowMenu() -> Bool {
        guard let secondaryActionBlock, isEnabled else { return super.accessibilityPerformShowMenu() }
        secondaryActionBlock(); return true
    }
}

@MainActor private final class BrowserToolbarActionCell: NSButtonCell {
    override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {
        super.highlight(flag, withFrame: cellFrame, in: controlView)
        (controlView as? BrowserToolbarActionButton)?.nativeHighlight(flag)
    }
}
