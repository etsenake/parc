import AppKit

// Native popup chrome uses the same controls and theme as the regular shell.
// Chromium owns the destination type; this view has no page or navigation copy.
final class PopupChromeView: NSView {
    var onNavigation: ((NavigationControlKind) -> NavigationControlInteraction?)?
    var onAddress: (() -> Void)? { didSet { address.actionBlock = onAddress } }
    var prepareCopy: (() -> (() -> Bool)?)? { didSet { copy.prepareAction = prepareCopy } }
    var prepareExtensions: (() -> (() -> Bool)?)? { didSet { extensions.prepareAction = prepareExtensions } }
    var onPageMenu: (() -> Void)? { didSet { address.secondaryActionBlock = onPageMenu } }
    var prepareSiteControls: (() -> (() -> Bool)?)? {
        didSet {
            address.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Site Control Center") { [weak self] in
                self?.prepareSiteControls?()?() == true
            }])
        }
    }
    var palette: ThemeChromePalette? { didSet { applyPalette() } }
    var pageControlsAnchor: NSView { extensions.isHidden ? address : extensions }
    var addressAnchor: NSView { address }
    private let back = NavigationControlButton("Back", symbol: "arrow.left", history: true, commandID: "goBack:")
    private let address = ActionButton("Address")
    private let addressLabel = PopupAddressLabel(labelWithString: "")
    private let addressBackground = PopupAddressBackground()
    private let copy = SidebarRowActionButton("Copy URL")
    private let extensions = SidebarRowActionButton("Extensions")
    private var addressTracking: NSTrackingArea?
    private var addressHovered = false { didSet { updateAddressBackground() } }
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        back.prepareInteraction = { [weak self] in self?.onNavigation?(.back) }
        // LittleBrowser's Back label renders Feather U+E92F at 16 points
        //
        back.image = SidebarIconCatalog.featherImage(0xE92F, size: 16)
        addSubview(addressBackground)
        for button in [back, address, extensions, copy] as [NSButton] { addSubview(button) }
        addSubview(addressLabel, positioned: .above, relativeTo: address)
        back.imagePosition = .imageOnly
        address.title = ""
        addressLabel.alignment = .center
        addressLabel.lineBreakMode = .byTruncatingMiddle
        addressLabel.font = .systemFont(ofSize: 13)
        addressLabel.setAccessibilityElement(false)
        copy.symbol = SidebarIconCatalog.featherImage(0xE98A, size: 16)
        copy.isHidden = true
        extensions.symbol = NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .medium))
        extensions.isHidden = true
        //
        LiveShortcutToolTip.set(extensions, "Extensions", anchor: .bottom)
        updateCopyTooltip()
        applyPalette()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        // Leave the standard macOS close/minimize/zoom controls unobstructed.
        let start: CGFloat = 70
        back.frame = NSRect(x: start, y: 8, width: 31, height: 31)
        let next = start + (back.isHidden ? 0 : 32)
        let field = NSRect(x: next + 3, y: 8, width: max(0, bounds.width - next - 7), height: 31)
        address.frame = field
        addressBackground.frame = field
        let labelInset: CGFloat = (copy.isHidden ? 0 : 31) + (extensions.isHidden ? 0 : 31)
        let labelHeight = min(field.height, addressLabel.intrinsicContentSize.height)
        addressLabel.frame = NSRect(x: field.minX + min(labelInset, field.width / 2),
                                    y: field.midY - labelHeight / 2,
                                    width: max(0, field.width - 2 * labelInset), height: labelHeight)
        copy.frame = NSRect(x: field.maxX - 27, y: field.minY + 4, width: 23, height: 23)
        extensions.frame = NSRect(x: field.maxX - (copy.isHidden ? 27 : 58), y: field.minY + 4, width: 23, height: 23)
        updateTrackingAreas()
    }
    func update(url: URL?, canGoBack: Bool, loading: Bool) {
        back.isEnabled = canGoBack
        // LittleBrowserToolbar builds this button only for an item that can
        //
        if back.isHidden == canGoBack { back.isHidden = !canGoBack; needsLayout = true }
        let hideCopy = url == nil
        if copy.isHidden != hideCopy { copy.isHidden = hideCopy; needsLayout = true }
        copy.refreshAvailability()
        //
        //
        let fontSize: CGFloat = loading ? 11 : 13
        if addressLabel.font?.pointSize != fontSize {
            addressLabel.font = .systemFont(ofSize: fontSize); needsLayout = true
        }
        // Read the current engine URL; a requested destination or an opener
        // cannot supply the popup's displayed origin.
        addressLabel.stringValue = url?.host ?? url?.absoluteString ?? "Loading…"
        address.toolTip = url?.absoluteString
        address.setAccessibilityLabel(url.map { "Address: " + $0.absoluteString } ?? "Address")
    }
    func updateExtensions(available: Bool) {
        if extensions.isHidden == available { extensions.isHidden = !available; needsLayout = true }
        extensions.refreshAvailability()
    }
    private func applyPalette() {
        appearance = palette?.contentAppearance
        for button in [back, address] as [NSButton] {
            button.contentTintColor = palette?.title ?? .labelColor
        }
        addressLabel.textColor = palette?.title ?? .labelColor
        copy.dark = palette?.isDark ?? (effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        extensions.dark = copy.dark
        updateAddressBackground()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let addressTracking { removeTrackingArea(addressTracking) }
        let point = window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
        reconcileAddressHover(pointer: point, active: window?.isKeyWindow == true, visible: !isHiddenOrHasHiddenAncestor)
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow]
        if addressHovered { options.insert(.assumeInside) }
        let tracking = NSTrackingArea(rect: address.frame, options: options, owner: self)
        addTrackingArea(tracking); addressTracking = tracking
    }
    func reconcileAddressHover(pointer: NSPoint?, active: Bool, visible: Bool) {
        addressHovered = active && visible && pointer.map { address.frame.contains($0) } == true
    }
    override func mouseEntered(with event: NSEvent) { addressHovered = true }
    override func mouseExited(with event: NSEvent) { addressHovered = false }
    override func viewDidHide() { super.viewDidHide(); addressHovered = false }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
        }
        addressHovered = false
        super.viewWillMove(toWindow: newWindow)
        if let newWindow {
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidResignKey), name: NSWindow.didResignKeyNotification, object: newWindow)
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey), name: NSWindow.didBecomeKeyNotification, object: newWindow)
        }
    }
    @objc private func windowDidResignKey(_ notification: Notification) { addressHovered = false }
    @objc private func windowDidBecomeKey(_ notification: Notification) { updateTrackingAreas() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateAddressBackground() }
    private func updateAddressBackground() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        addressBackground.update(dark: dark, hovered: addressHovered)
    }
    func updateCopyTooltip() { LiveShortcutToolTip.set(copy, "Copy URL", commandID: "copyCurrentURL:", anchor: .bottom) }
}

/// The address button remains the input/AX owner while its centered label
/// yields equal space around the trailing Copy control.
final class PopupAddressLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

///
final class PopupAddressBackground: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 5; layer?.cornerCurve = .continuous
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func update(dark: Bool, hovered: Bool) {
        let color = dark
            ? NSColor(displayP3Red: 0.98, green: 0.984, blue: 1, alpha: hovered ? 0.15 : 0.10)
            : NSColor(displayP3Red: 0.055, green: 0.059, blue: 0.063, alpha: hovered ? 0.10 : 0.06)
        layer?.backgroundColor = color.cgColor
    }
}
