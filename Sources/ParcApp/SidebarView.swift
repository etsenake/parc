import AppKit

/// Immutable original-page lease and its sampled audio flags.
struct SidebarTabAudio {
    let lease: NSObject
    let audible: Bool
    let muted: Bool
}

/// Favicon arming identity for a reused Favorite tile.
///
/// Behavior lock: skip re-arm only when this page-URL list and orientation
/// match the last arm *and* the tile already shows settled non-nil page
/// favicons. Image-byte updates keep using `reloadFavicon(for:)`. Orientation
/// belongs here because `setPages` rebuilds cells when it changes.
private struct FavoriteFaviconIdentity: Equatable {
    var pageURLs: [String]
    var orientation: SplitOrientation
}

/// Favicon arming identity for a sidebar tab row across outline rebuilds.
///
/// Behavior lock: skip re-arm only when page URL and reset destination match
/// the last arm *and* settled non-nil art is available to adopt onto the new
/// row instance. Image-byte updates keep using `reloadFavicon(for:)`.
private struct TabRowFaviconIdentity: Equatable {
    var pageURL: String
    var resetDestination: URL?
}

/// Settled page (+ optional reset) art carried across outline rebuilds when
/// `makeRow` replaces the row instance but page identity is unchanged.
private struct TabRowSettledFaviconArt {
    var page: NSImage
    var reset: NSImage?
}

extension NSColor {
    convenience init(parcHex: String) {
        let raw = parcHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(raw, radix: 16) ?? 0xCAD5E2
        self.init(srgbRed: CGFloat((value >> 16) & 255) / 255,
                  green: CGFloat((value >> 8) & 255) / 255,
                  blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    static let parcInk = NSColor(srgbRed: 0.16, green: 0.20, blue: 0.28, alpha: 1)
}

final class ActionButton: NSButton {
    var actionBlock: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var showsHoverFill = false
    /// HoverableButtonStyle's `alwaysSelected` status: the hover fill stays on.
    var showsSelectedFill = false {
        didSet { if showsSelectedFill != oldValue { needsDisplay = true } }
    }
    /// The cell's image and title only; the hover fill and focus ring keep full strength.
    var contentAlpha: CGFloat = 1 {
        didSet { if contentAlpha != oldValue { needsDisplay = true } }
    }
    private var hoverTracking: NSTrackingArea?
    private(set) var hovered = false {
        didSet {
            guard hovered != oldValue else { return }
            if showsHoverFill { needsDisplay = true }
            translucentFace?.setHovered(hovered)
            onHover?(hovered)
        }
    }
    /// A secondary click, Control-click or VoiceOver's Show Menu; nil keeps
    /// NSButton's own handling.
    var secondaryActionBlock: (() -> Void)?
    /// Opt-in keyboard focus ring in HoverableButton's mask shape: its bounds
    ///
    ///
    ///
    ///
    var focusRingCornerRadius: CGFloat? {
        didSet {
            guard focusRingCornerRadius != oldValue else { return }
            focusRingType = focusRingCornerRadius == nil ? .none : .exterior; noteFocusRingMaskChanged()
        }
    }
    init(_ title: String = "", symbol: String? = nil, action: (() -> Void)? = nil) {
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
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func invoke() { actionBlock?() }
    /// False makes a fully transparent button pass clicks through; keyboard
    /// and accessibility access stay.
    var hitTestsWhenTransparent = true
    override func hitTest(_ point: NSPoint) -> NSView? {
        if !hitTestsWhenTransparent, alphaValue < 0.01 { return nil }
        return super.hitTest(point)
    }
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
    override var focusRingMaskBounds: NSRect { focusRingCornerRadius == nil ? super.focusRingMaskBounds : bounds }
    override func drawFocusRingMask() {
        guard let radius = focusRingCornerRadius else { super.drawFocusRingMask(); return }
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }
    ///
    var translucentFace: TranslucentButtonFace? {
        didSet { translucentFace?.setHovered(hovered, animated: false); updateTrackingAreas(); needsDisplay = true }
    }
    private var tracksHover: Bool { showsHoverFill || onHover != nil || translucentFace != nil }
    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking); self.hoverTracking = nil }
        if tracksHover {
            hoverTracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
            addTrackingArea(hoverTracking!)
        }
        super.updateTrackingAreas()
    }
    /// Availability that changes without a render, re-read as the pointer
    /// enters, before the hover reads `isEnabled`.
    var isAvailable: (() -> Bool)?
    override func mouseEntered(with event: NSEvent) {
        if let available = isAvailable?(), isEnabled != available { isEnabled = available }
        if tracksHover { hovered = isEnabled }
        super.mouseEntered(with: event)
    }
    override func mouseExited(with event: NSEvent) {
        if tracksHover { hovered = false }
        super.mouseExited(with: event)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { hovered = false; translucentFace?.stop() }
        super.viewWillMove(toWindow: newWindow)
    }
    /// Re-reads the pointer after the window's key state changed under it,
    /// when `.activeInKeyWindow` tracking sent no exit. Nothing is hovered
    /// while the app is inactive or the button hidden. The app, not the
    /// window, is checked: a press on the button closes a key child window
    /// before this window takes key.
    func refreshHover() {
        hovered = isEnabled && NSApp.isActive && !isHiddenOrHasHiddenAncestor
            && window.map { bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } == true
    }
    /// NSButton's press highlight: on while the pointer is down inside.
    var onHighlight: ((Bool) -> Void)?
    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        // NSButton's press tracking holds back the tracking area's exit and
        // entry, so a press dragged off or back on re-reads the pointer, as
        //
        if tracksHover { refreshHover() }
        onHighlight?(flag)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if translucentFace != nil { needsDisplay = true }
    }
    override func draw(_ dirtyRect: NSRect) {
        if let face = translucentFace {
            // The cell redraws whenever its tracking highlight changes.
            face.setPressed(isHighlighted && isEnabled)
            face.draw(in: bounds, enabled: isEnabled, view: self) { tint in
                if let image { face.drawGlyph(image, tint: tint, in: bounds, view: self) }
            }
            return
        }
        if showsHoverFill, isEnabled, showsSelectedFill || hovered || isHighlighted {
            //
            //
            // always-selected, GrayA5 pressed unless always-selected.
            let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let pressed = isHighlighted && !showsSelectedFill
            NSColor(white: dark ? 1 : 0, alpha: dark ? (pressed ? 0.103 : 0.077) : (pressed ? 0.09 : 0.071)).setFill()
            let side = min(24, bounds.width, bounds.height)
            let plate = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
            NSBezierPath(roundedRect: plate, xRadius: 5, yRadius: 5).fill()
        }
        guard contentAlpha < 1, let context = NSGraphicsContext.current?.cgContext else { super.draw(dirtyRect); return }
        context.saveGState(); context.setAlpha(contentAlpha)
        super.draw(dirtyRect)
        context.restoreGState()
    }
}

///
///
///
enum SidebarNewTabAppearance {
    static let title = "New Tab"
    static func titleColor(dark: Bool) -> NSColor {
        (dark ? NSColor.white : NSColor.black).withAlphaComponent(dark ? 0.45 : 0.30)
    }
    static func plusColor(dark: Bool) -> NSColor {
        (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.5)
    }
    static let plus = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 16, weight: .medium))
}

///
///
/// semibold as measured from the reference. The button colours itself the
/// same in the window sidebar and in Library cards: ForegroundTertiary
/// (BaseAssets black/white at 0.3) while shown but not under the pointer
///
///
/// sidebar is hovered. Theme `subtitle` is a washed fill that disappears on
/// a coloured Space.
enum SidebarClearAppearance {
    static let title = "Clear"
    ///
    static let revealDuration: CFTimeInterval = 0.1
    /// Installed 1.170 BaseAssets: ForegroundPrimary is white 0.8 or P3
    /// (0.0549, 0.0588, 0.0627) at 0.9, ForegroundTertiary white or black at 0.3.
    static func color(dark: Bool, hovered: Bool = false) -> NSColor {
        switch (hovered, dark) {
        case (true, true): NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.8)
        case (true, false): NSColor(displayP3Red: 0.0549, green: 0.0588, blue: 0.0627, alpha: 0.9)
        case (false, _): (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.3)
        }
    }
    private static let arrow = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 10, weight: .bold))
    static func apply(to button: NSButton, dark: Bool, hovered: Bool = false) {
        let color = color(dark: dark, hovered: hovered)
        button.font = .systemFont(ofSize: 10, weight: .semibold)
        button.contentTintColor = color
        button.image = arrow
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: button.font ?? NSFont.systemFont(ofSize: 10), .foregroundColor: color
        ])
    }
}

final class MenuAction: NSObject {
    let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    @objc func invoke() { block() }
    ///
    ///
    /// image are nil at every such call site). Parc's counterparts of the few
    ///
    static func item(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
        let holder = MenuAction(action)
        let item = NSMenuItem(title: title, action: #selector(invoke), keyEquivalent: "")
        item.target = holder
        item.representedObject = holder
        return item
    }
}

class LayoutView: NSView {
    var onLayout: (() -> Void)?
    override var isFlipped: Bool { true }
    override func layout() { super.layout(); onLayout?() }
}

/// The divider cell's border in SidebarSeparator (installed BaseAssets: black
/// or white at 0.15), independent of window appearance (updateLayer
///
final class SidebarHairline: NSView {
    var dark = false { didSet { if dark != oldValue { needsDisplay = true } } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        superview?.needsLayout = true
    }
    override func draw(_ dirtyRect: NSRect) {
        (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.15).setFill()
        bounds.fill(using: .sourceOver)
    }
}

/// The sidebar list's flipped document view; it holds the shown Space's outline.
final class SidebarListHost: NSView {
    override var isFlipped: Bool { true }
}

final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

/// Tab titles over the Space material paint `SemanticColorPalette.title`
/// without AppKit vibrancy sampling the window appearance. Mini player
/// chrome already uses that same explicit title color.
final class SidebarChromeLabel: NSTextField {
    override var allowsVibrancy: Bool { false }
}

///
///
/// SidebarCellImageContainerView and the title with the tab cell's insets
///
/// and "New Tab" at the title inset in the cell's 14-point label. While
/// hovered, the cell's CellSelectionStateView fills the visible row with
///
final class SidebarNewTabRow: NSView {
    let button = ActionButton()
    private let background = SidebarRowBackgroundView()
    private let icon = NSImageView()
    private let titleLabel = SidebarChromeLabel(labelWithString: SidebarNewTabAppearance.title)
    var dark = false { didSet { if dark != oldValue { applyColors() } } }
    var paletteTitle: NSColor = .parcInk { didSet { if paletteTitle != oldValue { applyColors() } } }
    /// NewTabCellState.isCurrentItem is the window's
    ///
    /// current fill and shadow over its hover colour, and its sink
    ///
    ///
    var current = false { didSet { if current != oldValue { applyColors() } } }
    override var isFlipped: Bool { true }
    private var keyObservers: [NSObjectProtocol] = []
    private var hoverStale = false
    deinit { keyObservers.forEach(NotificationCenter.default.removeObserver) }

    /// SidebarBouncyClickCell.performBounceAnimation(isPressedIn:)
    ///
    /// centre and holds it there (fill-forwards, kept on completion); the
    /// release springs it back to identity from the presented transform.
    /// The spring has damping ratio 0.5 and response 0.2, giving stiffness
    /// (2π / response)² and damping 4π × ratio / response at unit mass, and
    ///
    static let pressScale: CGFloat = 0.992
    static let bounceKey = "press_bounce"
    ///
    /// scales about the centre.
    static func pressedTransform(in bounds: NSRect) -> CATransform3D {
        CATransform3DTranslate(
            CATransform3DScale(CATransform3DMakeTranslation(bounds.midX, bounds.midY, 0), pressScale, pressScale, 1),
            -bounds.midX, -bounds.midY, 0)
    }
    static func bounce(pressed: Bool, bounds: NSRect, from presented: CATransform3D) -> CASpringAnimation {
        let response: CGFloat = 0.2, dampingRatio: CGFloat = 0.5
        let spring = CASpringAnimation(keyPath: "transform")
        spring.mass = 1
        spring.stiffness = pow(2 * .pi / response, 2)
        spring.damping = 4 * .pi * dampingRatio / response
        spring.duration = spring.settlingDuration
        spring.fromValue = NSValue(caTransform3D: presented)
        spring.toValue = NSValue(caTransform3D: pressed ? pressedTransform(in: bounds) : CATransform3DIdentity)
        spring.isRemovedOnCompletion = !pressed
        spring.fillMode = .forwards
        return spring
    }

    init(dark: Bool, action: @escaping () -> Void) {
        self.dark = dark
        super.init(frame: .zero)
        wantsLayer = true
        button.actionBlock = { [weak self] in
            self?.springPress(false)
            action()
        }
        button.setAccessibilityLabel(SidebarNewTabAppearance.title)
        button.onHover = { [weak self] _ in self?.refreshPlate() }
        //
        // released off the row stays at 0.992 until the next completed click,
        // and dragging back on during the press changes nothing.
        button.onHighlight = { [weak self] pressed in
            guard pressed, let self, !self.holdsPress else { return }
            self.springPress(true)
        }
        icon.image = SidebarNewTabAppearance.plus
        icon.imageScaling = .scaleNone
        titleLabel.font = .systemFont(ofSize: SidebarRowAppearance.titleFontSize)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        for view in [icon, titleLabel] as [NSView] { view.setAccessibilityElement(false) }
        addSubview(background); addSubview(icon); addSubview(titleLabel); addSubview(button)
        applyColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var holdsPress: Bool { layer?.animation(forKey: Self.bounceKey)?.isRemovedOnCompletion == false }
    private var pressedSize: NSSize?
    private func springPress(_ pressed: Bool) {
        guard let layer else { return }
        let presented = layer.presentation()?.transform ?? layer.transform
        layer.add(Self.bounce(pressed: pressed, bounds: bounds, from: presented), forKey: Self.bounceKey)
        pressedSize = pressed ? bounds.size : nil
    }
    ///
    /// every Space, so another Space shows it unpressed.
    func dropHeldPress() {
        guard holdsPress else { return }
        layer?.removeAnimation(forKey: Self.bounceKey)
        pressedSize = nil
    }

    private func applyColors() {
        background.dark = dark
        background.appearanceState.current = current
        icon.contentTintColor = current ? paletteTitle : SidebarNewTabAppearance.plusColor(dark: dark)
        titleLabel.textColor = current ? paletteTitle : SidebarNewTabAppearance.titleColor(dark: dark)
    }

    /// The button's `.activeInKeyWindow` tracking sends no exit when the
    /// window resigns key, as it does for New Tab's own command bar, so the
    /// plate also needs the key window and the pointer is re-read when the
    /// window takes key again.
    private func refreshPlate() { background.appearanceState.hovered = button.hovered && window?.isKeyWindow == true }
    /// AppKit sends no entry for a row that appears or moves under a still
    /// pointer, so the next layout, once the row is in its place, re-reads it.
    func invalidateHover() { hoverStale = true; needsLayout = true }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        keyObservers.forEach(NotificationCenter.default.removeObserver)
        keyObservers = []
        guard let newWindow else { return }
        keyObservers = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: newWindow, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if note.name == NSWindow.didBecomeKeyNotification { self.button.refreshHover() }
                    self.refreshPlate()
                }
            }
        }
        invalidateHover()
    }

    override func layout() {
        super.layout()
        background.frame = bounds
        button.frame = bounds
        let slot = SidebarRowAppearance.iconSlotFrame(in: bounds)
        let size = icon.image?.size ?? .zero
        icon.frame = NSRect(x: slot.midX - size.width / 2, y: slot.midY - size.height / 2, width: size.width, height: size.height)
        let (titleX, width) = SidebarRowAppearance.titleLabelSpan(
            resettable: false, trailing: SidebarRowAppearance.titleTrailingEdge(in: bounds, closeVisible: false))
        titleLabel.frame = NSRect(x: titleX, y: ((bounds.height - 18) / 2).rounded(.down), width: width, height: 18)
        if hoverStale, window != nil { hoverStale = false; button.refreshHover() }
        // A held press keeps scaling about the row's centre as the sidebar resizes.
        if holdsPress, let pressedSize, pressedSize != bounds.size, let layer {
            let held = Self.pressedTransform(in: bounds)
            layer.add(Self.bounce(pressed: true, bounds: bounds, from: held), forKey: Self.bounceKey)
            self.pressedSize = bounds.size
        }
    }
}

final class SidebarTabRow: NSView, NSDraggingSource, SidebarItemDragSource, SidebarDeferredAccessibilityActions {
    static let pasteboardType = NSPasteboard.PasteboardType("org.parc.sidebar-tab")
    let tabID: UUID
    private let titleLabel = SidebarChromeLabel(labelWithString: "")
    /// Built for the first rename; most rows are never renamed, and every
    /// rarely shown part built up front cost a long list most of its memory.
    private var titleFieldStore: SidebarTitleField?
    private var titleField: SidebarTitleField {
        if let titleFieldStore { return titleFieldStore }
        let field = SidebarTitleField()
        addSubview(field, positioned: .above, relativeTo: titleStack)
        titleFieldStore = field
        needsLayout = true
        return field
    }
    private var editingTitle: Bool { titleFieldStore?.editingTitle == true }
    private let background = SidebarRowBackgroundView()
    private let icon = SidebarFaviconView()
    private let closeButton = SidebarRowActionButton("Close Tab")
    ///
    /// with a 14-point semibold rectangle.inset.filled.and.person.filled,
    /// shown only while the row is hovered without its reset subtitle and the
    ///
    private var shareButtonStore: SidebarRowActionButton?
    private var shareButton: SidebarRowActionButton {
        if let shareButtonStore { return shareButtonStore }
        let button = SidebarRowActionButton("Share this tab instead")
        button.symbol = Self.shareSymbol
        button.setAccessibilityIdentifier("shareTabButton")
        button.isHidden = true
        button.prepareAction = prepareShare
        addSubview(button, positioned: .below, relativeTo: closeButton)
        shareButtonStore = button
        updateColor()
        onControlsChanged?()
        return button
    }
    var shareable = false { didSet { if shareable != oldValue { updateActions(); needsLayout = true } } }
    var prepareShare: (() -> (() -> Bool)?)? { didSet { shareButtonStore?.prepareAction = prepareShare } }
    ///
    /// region (TabCellRegionalBackgroundView), the slash between icon and
    /// title, and the hover subtitle carried by the lifted title stack. Built
    /// once the row's tab first has a reset destination.
    private struct ResetParts {
        let region: SidebarRowResetRegion
        let body: SidebarRowBodyRegionView
        let slash: SidebarRowSlashView
        let icon: SidebarFaviconView
        let subtitle: SidebarChromeLabel
    }
    private var resetParts: ResetParts?
    private var resetAction: () -> (() -> Bool)? = { nil }
    private var separateAction: () -> (() -> Bool)? = { nil }
    @discardableResult private func makeResetParts() -> ResetParts {
        if let resetParts { return resetParts }
        let parts = ResetParts(region: SidebarRowResetRegion(), body: SidebarRowBodyRegionView(), slash: SidebarRowSlashView(),
                               icon: SidebarFaviconView(), subtitle: SidebarChromeLabel(labelWithString: SidebarRowAppearance.resetSubtitle))
        parts.region.prepareAction = resetAction; parts.region.prepareSeparate = separateAction
        parts.region.onHoverChange = { [weak self] in self?.resetHoverChanged() }
        parts.region.makeMenu = { [weak self] in self?.context?() }
        parts.icon.isHidden = true
        parts.subtitle.font = .systemFont(ofSize: SidebarRowAppearance.subtitleFontSize)
        parts.subtitle.lineBreakMode = .byTruncatingTail
        parts.subtitle.maximumNumberOfLines = 1
        parts.subtitle.setAccessibilityElement(false)
        parts.subtitle.wantsLayer = true; parts.subtitle.alphaValue = 0
        addSubview(parts.body, positioned: .above, relativeTo: background)
        addSubview(parts.region, positioned: .above, relativeTo: parts.body)
        addSubview(parts.icon, positioned: .above, relativeTo: icon)
        addSubview(parts.slash, positioned: .above, relativeTo: parts.icon)
        titleStack.addSubview(parts.subtitle)
        resetParts = parts
        LiveShortcutToolTip.set(parts.region, "Reset Tab", commandID: "resetTab:", requiresBinding: true)
        updateColor()
        needsLayout = true
        return parts
    }
    /// The hover subtitle's line height, for rows that have none yet.
    private static let subtitleHeight: CGFloat = {
        let label = SidebarChromeLabel(labelWithString: SidebarRowAppearance.resetSubtitle)
        label.font = .systemFont(ofSize: SidebarRowAppearance.subtitleFontSize)
        return ceil(label.intrinsicContentSize.height)
    }()
    private let titleStack = SidebarRowTitleStack()
    private var shownSubtitle: SidebarRowHoverSubtitle?
    private var resetIconGeneration: UInt64 = 0
    private var hasReset = false
    private var allowsFavicon = false
    private var shownURL = ""
    ///
    var keyboardHighlighted = false { didSet { updateColor() } }
    /// Tab-into-list focus uses the same HighlightRingView as the keyboard
    /// cursor. Drawing it on the row's own layer (the old 1-point accent
    /// border) rounded and clipped the current-item shadow.
    var listFocusRing = false { didSet { if listFocusRing != oldValue { updateColor() } } }
    private var dimmed = false
    /// Built while the tab first records.
    private var captureButtonStore: ActionButton?
    private var captureButton: ActionButton {
        if let captureButtonStore { return captureButtonStore }
        let capture = ActionButton("Active capture", symbol: "mic.fill")
        capture.isHidden = true
        capture.imagePosition = .imageOnly
        capture.actionBlock = { [weak self, weak capture] in
            guard let self, let capture else { return }
            self.showCapture?(capture)
        }
        addSubview(capture, positioned: .above, relativeTo: closeButton)
        captureButtonStore = capture
        updateColor()
        onControlsChanged?()
        return capture
    }
    /// Built once the tab plays or is muted.
    private var muteButtonStore: SidebarRowActionButton?
    private var muteButton: SidebarRowActionButton {
        if let muteButtonStore { return muteButtonStore }
        let button = SidebarRowActionButton("Mute this tab")
        button.decoration = builtSpeaker
        button.setAccessibilityIdentifier("sidebarTabCellMuteButton")
        button.isHidden = true
        button.makeMenu = { [weak self] in self?.context?() }
        button.prepareAction = prepareMute
        addSubview(button, positioned: .above, relativeTo: captureButtonStore ?? closeButton)
        muteButtonStore = button
        applyAudioLabel(speaker: audio != nil)
        updateColor()
        onControlsChanged?()
        return button
    }
    private var hasAudio: Bool { audio?.audible == true || audio?.muted == true }
    var audio: SidebarTabAudio? {
        didSet {
            // Every live-metadata pass sets each row's audio; only a change
            // rebuilds its tooltip and layout.
            guard audio?.audible != oldValue?.audible || audio?.muted != oldValue?.muted else { return }
            if hasAudio { _ = muteButton }
            applyAudioLabel(speaker: true)
            needsLayout = true
        }
    }
    private func applyAudioLabel(speaker: Bool) {
        let muted = audio?.muted == true
        if let muteButtonStore {
            let label = muted ? "Unmute this tab" : "Mute this tab"
            LiveShortcutToolTip.set(muteButtonStore, label); muteButtonStore.setAccessibilityLabel(label)
        }
        if speaker, let speakerHost, speakerHost.model.muted != muted { speakerHost.model.muted = muted }
    }
    /// A share, capture or mute button joined the row: the sidebar's Tab
    /// order takes it.
    var onControlsChanged: (() -> Void)?
    var prepareMute: (() -> (() -> Bool)?)? {
        didSet { muteButtonStore?.prepareAction = prepareMute; muteButtonStore?.refreshAvailability() }
    }
    var showCapture: ((NSView) -> Void)?
    var capture: CaptureIndicatorPresentation? {
        didSet {
            guard capture != oldValue, capture != nil || captureButtonStore != nil else { return }
            captureButton.isHidden = capture == nil
            captureButton.image = capture.flatMap { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: nil) }
            //
            LiveShortcutToolTip.set(captureButton, "This tab is using your camera or microphone")
            captureButton.setAccessibilityLabel(capture?.summary ?? "Active capture")
            needsLayout = true
        }
    }
    var beginSidebarMove: (() -> SidebarMoveSession?)?
    private(set) var sidebarDrag: SidebarMoveSession?
    var beginSplitDrag: (() -> SidebarSplitDrag?)?
    private(set) var splitDrag: SidebarSplitDrag?
    ///
    var splitDropCardContent: (icon: NSImage?, title: String) { (icon.image, titleLabel.stringValue) }
    /// This drag's own image, which the split overlay puts back on exit.
    private(set) var splitDragImage: NSImage?
    var privateBrowsing = false {
        didSet {
            guard privateBrowsing else { return }
            bindCloseButton(tooltip: "Close Tab", label: "Close Tab")
        }
    }
    /// The close button's tooltip and label as last bound. Live page updates
    /// rebind every row, and each repeat re-registered the shortcut help.
    private var boundCloseButton: String?
    private func bindCloseButton(tooltip: String, label: String) {
        let key = tooltip + "\u{0}" + label
        guard boundCloseButton != key else { return }
        boundCloseButton = key
        LiveShortcutToolTip.set(closeButton, tooltip, commandID: "closeTab:"); closeButton.setAccessibilityLabel(label)
    }
    var compactSplitChild = false { didSet { updateActions(); updateColor(); updateRowTooltip(); needsLayout = true } }
    ///
    var splitGroupSelected = false { didSet { updateColor() } }
    /// The split's hover, which shows a child's Close (ChildItemState's
    ///
    private var groupHover = false
    private var groupTracking: (area: NSTrackingArea, view: NSView)?
    /// `ChildItemState.closeButtonConfiguration`: the split cell gives its
    /// children a Close only while it shows none of its own
    /// (`SidebarSplitCellLayout.childCloseAvailable`).
    var splitChildCloseAvailable = true { didSet { if splitChildCloseAvailable != oldValue { updateActions(); needsLayout = true } } }
    /// A split child's press belongs to its split's one outline row: a drag
    /// that starts on it moves the whole split (the press and drag events).
    var beginGroupDrag: ((NSEvent, NSEvent) -> Void)?
    /// The row a sidebar drag started from is the drag's key item. The sidebar
    ///
    var keyDragged = false { didSet { if keyDragged != oldValue { updateColor() } } }
    var onKeyDrag: ((Bool) -> Void)?
    var prepareActivation: (() -> (() -> Bool)?)?
    var makeAccessibilityActions: (() -> [NSAccessibilityCustomAction])?
    private var pendingActivation: (() -> Bool)?
    private var windowObservers: [NSObjectProtocol] = []
    var selectionClick: ((NSEvent) -> Bool)?
    /// Starts this row's title editing; nil where the row cannot be renamed.
    var beginRename: (() -> Bool)? { didSet { if (beginRename == nil) != (oldValue == nil) { updateRowTooltip() } } }
    private var tooltipTab: BrowserTab
    var context: (() -> NSMenu)?
    var selected = false { didSet { updateColor() } }
    ///
    /// than the current-item fill.
    var multiSelected = false { didSet { updateColor() } }
    var palette: ThemeChromePalette? { didSet { updateColor() } }
    private var hover = false
    private var mouseStart: NSPoint?
    private var selectionEvent: NSEvent?
    private var tracking: NSTrackingArea?
    /// The window the row last refreshed its controls in.
    private weak var trackedWindow: NSWindow?
    override var isFlipped: Bool { true }

    init(tab: BrowserTab, selected: Bool, speaker: SidebarSpeakerHost?, close: @escaping () -> (() -> Bool)?,
         reset: @escaping () -> (() -> Bool)?, separate: @escaping () -> (() -> Bool)?) {
        tabID = tab.id; tooltipTab = tab
        built = (tab.kind, tab.resetDestination != nil, InternalPage(urlString: tab.url))
        super.init(frame: .zero)
        // Rounding lives on CellSelectionStateView, not this row. A 12-point
        //
        //
        wantsLayer = true
        clipsToBounds = false
        layer?.masksToBounds = false
        layer?.allowsGroupOpacity = false
        titleLabel.stringValue = SidebarTabTitle.display(tab)
        //
        titleLabel.font = .systemFont(ofSize: SidebarRowAppearance.titleFontSize)
        titleLabel.textColor = .parcInk
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        //
        // its page image and the fallback stays a still glyph. EaselCellView
        // and Notes use typed FaviconType glyphs (easel / arcDocument), not a
        // page favicon; the still fallback is that typed SF template, tinted
        // with SemanticColorPalette.title like mini player and the row title.
        icon.image = Self.fallbackSymbol(tab)
        icon.fallbackTintColor = .parcInk
        allowsFavicon = InternalPage(urlString: tab.url) == nil
        closeButton.prepareAction = close
        closeButton.imagePosition = .imageOnly
        let closeTitle = tab.kind == .today ? "Archive Tab" : "Close Tab"
        //
        bindCloseButton(tooltip: Self.closeTooltip(tab), label: closeTitle)
        closeButton.isHidden = true
        //
        //
        //
        hasReset = tab.resetDestination != nil
        resetAction = reset; separateAction = separate
        titleStack.wantsLayer = true
        closeButton.focusRingType = .exterior
        builtSpeaker = speaker
        addSubview(background); addSubview(icon)
        titleStack.addSubview(titleLabel)
        addSubview(titleStack); addSubview(closeButton)
        if hasReset { makeResetParts() }
        if speaker != nil { _ = muteButton }
        self.selected = selected
        updateColor()
        updateRowTooltip(); shownURL = tab.url
        //
        //
        // button description, which document rows share here.
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        if InternalPage(urlString: tab.url) == nil { setAccessibilityRoleDescription("Tab") }
        setAccessibilityHelp(WhatsNewPage.presented(tab.url))
        closeButton.makeMenu = { [weak self] in self?.context?() }
    }
    /// Every row shows one of a few symbols; looking each up again per row was
    /// a third of building a long list's rows.
    private static var fallbackSymbols: [String: NSImage] = [:]
    private static func fallbackSymbol(_ tab: BrowserTab) -> NSImage? {
        let name = InternalPage.sidebarFallbackSymbol(urlString: tab.url)
        if let image = fallbackSymbols[name] { return image }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        fallbackSymbols[name] = image
        return image
    }
    private static let shareSymbol = NSImage(systemSymbolName: "rectangle.inset.filled.and.person.filled", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
    func loadFavicon(_ request: (@escaping (NSImage?) -> Void) -> Void) {
        guard allowsFavicon else { return }
        icon.load(request)
    }
    /// TabCellState.resetTabIcon is the saved destination's stored icon
    ///
    func loadResetIcon(_ request: (@escaping (NSImage?) -> Void) -> Void) {
        guard hasReset, allowsFavicon else { return }
        resetIconGeneration &+= 1
        let generation = resetIconGeneration
        request { [weak self] image in
            guard let self, self.resetIconGeneration == generation else { return }
            self.makeResetParts().icon.image = image
            self.updateResetIcon()
        }
    }
    /// Settled page art, and reset art when the row shows a reset target.
    /// Nil while still on the themed fallback or waiting on a lookup so a
    /// later same-URL history hit is not dropped by a skip.
    fileprivate func settledFaviconArt() -> TabRowSettledFaviconArt? {
        guard allowsFavicon, icon.hasSettledFavicon, let page = icon.image else { return nil }
        if hasReset {
            guard let reset = resetParts?.icon.image else { return nil }
            return TabRowSettledFaviconArt(page: page, reset: reset)
        }
        return TabRowSettledFaviconArt(page: page, reset: nil)
    }
    /// Adopt prior settled art onto a replacement row without re-arming loads.
    fileprivate func adoptSettledFaviconArt(_ art: TabRowSettledFaviconArt) {
        guard allowsFavicon else { return }
        icon.adoptSettled(art.page)
        if hasReset {
            resetIconGeneration &+= 1
            makeResetParts().icon.image = art.reset
            updateResetIcon()
        }
    }
    ///
    /// carries `titleSourceInfo` and `icon` on the existing row; it does not
    /// rebuild the outline for a metadata tick.
    @discardableResult
    func applyLivePage(_ tab: BrowserTab) -> Bool {
        let title = SidebarTabTitle.display(tab)
        if titleLabel.stringValue != title {
            titleLabel.stringValue = title
            needsLayout = true
        }
        tooltipTab = tab; updateRowTooltip()
        let urlChanged = shownURL != tab.url
        if urlChanged {
            shownURL = tab.url
            setAccessibilityHelp(WhatsNewPage.presented(tab.url))
            let allows = InternalPage(urlString: tab.url) == nil
            if allows != allowsFavicon {
                allowsFavicon = allows
                icon.image = Self.fallbackSymbol(tab)
            }
        }
        let reset = tab.resetDestination != nil
        if reset != hasReset {
            hasReset = reset
            if hasReset { makeResetParts() }
            resetParts?.slash.isHidden = !hasReset
            if !hasReset {
                resetParts?.icon.image = nil
                updateResetIcon()
            }
            updateActions()
            needsLayout = true
        }
        return urlChanged
    }
    /// Close/reset leases capture a `BrowserTab` snapshot. Rebind after a
    /// title/URL tick so `Equatable` membership checks still see this row.
    func bindLiveActions(tab: BrowserTab, close: @escaping () -> (() -> Bool)?,
                         reset: @escaping () -> (() -> Bool)?,
                         separate: @escaping () -> (() -> Bool)?) {
        closeButton.prepareAction = close
        resetAction = reset; separateAction = separate
        resetParts?.region.prepareAction = reset
        resetParts?.region.prepareSeparate = separate
        // The region stays shown; scrolling no longer re-reads its availability.
        resetParts?.region.refreshAvailability()
        guard !privateBrowsing else { return }
        bindCloseButton(tooltip: Self.closeTooltip(tab), label: tab.kind == .today ? "Archive Tab" : "Close Tab")
    }
    ///
    ///
    ///
    static func closeTooltip(_ tab: BrowserTab) -> String {
        tab.kind == .today ? "Archive this tab" : "Close and Keep Pinned"
    }
    static let renameHint = "Double-click to rename"
    ///
    ///
    /// over "Double-click to rename" while the tab has no custom title, as an
    ///
    /// appears only where a double-click renames this row.
    static func rowTooltip(_ tab: BrowserTab, renameable: Bool) -> TooltipConfiguration {
        let hint = renameable && tab.customTitle == nil ? renameHint : nil
        return TooltipConfiguration(SidebarTabTitle.display(tab), style: .label(subtitle: hint), anchor: .cursor,
                                    behavior: .onMouseIdle(delay: 1.5))
    }
    /// A split child (SplitViewCellState.ChildItemState) has no tooltip.
    private func updateRowTooltip() {
        parcTooltip = compactSplitChild ? nil : Self.rowTooltip(tooltipTab, renameable: beginRename != nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @discardableResult func beginTitleEditing(_ title: String, finished: @escaping (String?) -> Void) -> Bool {
        cancelInteraction()
        titleField.font = titleLabel.font; titleField.textColor = titleLabel.textColor
        titleField.onFinish = { [weak self] value in
            self?.titleLabel.isHidden = false; self?.needsLayout = true
            finished(value)
        }
        layoutSubtreeIfNeeded()
        guard titleField.begin(title: title) else { titleField.onFinish = nil; return false }
        titleLabel.isHidden = true; needsLayout = true
        return true
    }
    func cancelTitleEditing() { titleFieldStore?.cancel() }

    override func layout() {
        super.layout()
        defer {
            let titleFrame = NSRect(x: titleStack.frame.minX, y: titleStack.frame.minY,
                                    width: titleLabel.frame.width, height: titleLabel.frame.height)
            if editingTitle {
                titleLabel.isHidden = true
                titleField.frame = NSRect(x: titleFrame.minX, y: titleFrame.minY,
                    width: max(0, bounds.width - titleFrame.minX - 8), height: titleFrame.height)
                closeButton.isHidden = true; resetParts?.region.isHidden = true; resetParts?.body.isHidden = true
                captureButtonStore?.isHidden = true; shareButtonStore?.isHidden = true; muteButtonStore?.isHidden = true
            } else { titleFieldStore?.frame = titleFrame }
        }
        background.frame = bounds
        updateActions()
        let mute = muteButtonStore.flatMap { $0.isHidden ? nil : $0 }
        if compactSplitChild {
            //
            // slash or hover subtitle; Parc's capture button takes the
            // recording indicator's place before the icon.
            let titleHeight = ceil(titleLabel.intrinsicContentSize.height)
            let layout = SidebarRowAppearance.splitChildLayout(in: bounds, titleHeight: titleHeight,
                recording: capture != nil, closeAvailable: !editingTitle && splitChildCloseAvailable,
                groupHovered: groupHover)
            background.frame = layout.cell
            if let indicator = layout.indicator { captureButton.isHidden = false; captureButton.frame = indicator }
            else { captureButtonStore?.isHidden = true }
            icon.isHidden = false
            let slot = layout.iconSlot
            icon.frame = NSRect(x: slot.midX - SidebarRowAppearance.iconSize / 2, y: slot.midY - SidebarRowAppearance.iconSize / 2,
                                width: SidebarRowAppearance.iconSize, height: SidebarRowAppearance.iconSize).integral
            resetParts?.icon.frame = icon.frame
            closeButton.frame = layout.close
            if let mute {
                let right = layout.showsClose ? layout.close.minX - 2 : bounds.maxX - 4
                let frame = NSRect(x: right - 24, y: layout.close.minY, width: 24, height: layout.close.height)
                if frame.minX < slot.maxX { mute.isHidden = true }
                else { mute.frame = frame }
            }
            closeButton.isHidden = !layout.showsClose
            resetParts?.slash.isHidden = true
            titleLabel.isHidden = layout.title == nil
            let title = layout.title ?? NSRect(x: slot.maxX, y: 0, width: 0, height: titleHeight)
            let shownMute = mute.flatMap { $0.isHidden ? nil : $0 }
            let titleWidth = shownMute.map { max(0, min(title.width, $0.frame.minX - title.minX)) } ?? title.width
            titleStack.frame = NSRect(x: title.minX, y: title.minY, width: titleWidth, height: title.height)
            titleLabel.frame = NSRect(x: 0, y: 0, width: titleWidth, height: title.height)
            resetParts?.subtitle.frame = NSRect(x: 0, y: title.height, width: title.width, height: 0)
            return
        }
        titleLabel.isHidden = false; icon.isHidden = false
        icon.frame = SidebarRowAppearance.iconFrame(in: bounds)
        titleLabel.font = .systemFont(ofSize: SidebarRowAppearance.titleFontSize)
        if let parts = resetParts {
            parts.icon.frame = icon.frame
            parts.slash.isHidden = !hasReset
            parts.slash.frame = SidebarRowAppearance.slashFrame(in: bounds)
            parts.region.frame = SidebarRowAppearance.resetRegionFrame(in: bounds)
            parts.body.frame = NSRect(x: parts.region.frame.maxX, y: 0,
                                      width: max(0, bounds.width - parts.region.frame.maxX), height: bounds.height)
        }
        closeButton.frame = SidebarRowAppearance.closeFrame(in: bounds)
        var trailing = SidebarRowAppearance.titleTrailingEdge(in: bounds, closeVisible: !closeButton.isHidden)
        if let share = shareButtonStore, !share.isHidden {
            //
            let close = closeButton.frame
            share.frame = NSRect(x: close.minX - 2 - close.width, y: close.minY, width: close.width, height: close.height)
            trailing = share.frame.minX - SidebarRowAppearance.titleCloseSpacing
        }
        if let mute {
            mute.frame = NSRect(x: trailing - 24, y: ((bounds.height - 24) / 2).rounded(.down), width: 24, height: 24)
            trailing = mute.frame.minX
        }
        // Shown again after a title edit (the defer above hides it while editing).
        if capture != nil {
            // Parc's capture indicator sits in the body stack before Close.
            captureButton.isHidden = false
            captureButton.frame = NSRect(x: trailing - 23, y: ((bounds.height - 25) / 2).rounded(.down), width: 23, height: 25)
            trailing = captureButton.frame.minX
        } else { captureButtonStore?.isHidden = true }
        let (titleX, width) = SidebarRowAppearance.titleLabelSpan(resettable: hasReset, trailing: trailing)
        //
        let subtitleHeight = resetParts.map { ceil($0.subtitle.intrinsicContentSize.height) } ?? Self.subtitleHeight
        titleStack.frame = NSRect(x: titleX, y: ((bounds.height - 18) / 2).rounded(.down), width: width, height: 18 + subtitleHeight)
        titleLabel.frame = NSRect(x: 0, y: 0, width: width, height: 18)
        resetParts?.subtitle.frame = NSRect(x: 0, y: 18, width: width, height: subtitleHeight)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
        // A row can be rebuilt under a stationary pointer after navigation.
        // Reconcile its actual hover instead of waiting for another enter event.
        let wasHover = hover, wasGroupHover = groupHover
        hover = pointerIsInside(self)
        updateGroupTracking()
        // Every row of the list is in the window, and AppKit asks them all
        // again as the list scrolls or resizes: refresh a row's controls, fill
        // and layout only when it entered a window or its hover changed.
        guard window !== trackedWindow || hover != wasHover || groupHover != wasGroupHover else { return }
        trackedWindow = window
        updateActions(); updateColor(); needsLayout = true
    }
    private func pointerIsInside(_ view: NSView) -> Bool {
        window?.isKeyWindow == true && window.map {
            view.bounds.contains(view.convert($0.mouseLocationOutsideOfEventStream, from: nil))
        } == true && mouseStart == nil
    }
    /// A split child follows its whole split's hover with a tracking area on
    ///
    /// isGroupHovered.
    private func updateGroupTracking() {
        guard compactSplitChild, window != nil, let group = superview else {
            if let groupTracking { groupTracking.view.removeTrackingArea(groupTracking.area); self.groupTracking = nil }
            groupHover = false; return
        }
        // An in-visible-rect area follows the split's bounds by itself.
        if groupTracking?.view !== group {
            if let groupTracking { groupTracking.view.removeTrackingArea(groupTracking.area) }
            let area = NSTrackingArea(rect: group.bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
                                      owner: self, userInfo: nil)
            group.addTrackingArea(area); groupTracking = (area, group)
        }
        groupHover = pointerIsInside(group)
    }
    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea === groupTracking?.area {
            guard !groupHover else { return }
            groupHover = true
        } else {
            guard !hover else { return }
            hover = true
        }
        updateActions(); updateColor(); needsLayout = true
    }
    override func mouseExited(with event: NSEvent) {
        if event.trackingArea === groupTracking?.area {
            guard groupHover else { return }
            groupHover = false
        } else {
            guard hover else { return }
            hover = false
        }
        updateActions(); updateColor(); needsLayout = true
    }
    private func updateActions() {
        closeButton.refreshAvailability(); resetParts?.region.refreshAvailability()
        // Hidden pointer controls keep their context-menu and accessibility
        // actions. A split child shows Close while its split is hovered (its
        // layout also needs room) and has no reset target.
        closeButton.isHidden = editingTitle || !(compactSplitChild ? groupHover && splitChildCloseAvailable : hover)
        let muteHidden = editingTitle || !hasAudio
        if !muteHidden || muteButtonStore != nil {
            muteButton.isHidden = muteHidden
            muteButton.refreshAvailability()
        }
        let shareHidden = editingTitle || compactSplitChild || !shareable || !hover || shownSubtitle != nil
        if !shareHidden || shareButtonStore != nil {
            shareButton.refreshAvailability()
            shareButton.isHidden = shareHidden
        }
        resetParts?.region.isHidden = editingTitle || !hasReset || compactSplitChild
        resetParts?.body.isHidden = resetParts?.region.isHidden ?? true
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        cancelInteraction()
        trackedWindow = nil
        if let groupTracking { groupTracking.view.removeTrackingArea(groupTracking.area); self.groupTracking = nil }
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers = []
        if let newWindow {
            let center = NotificationCenter.default
            windowObservers.append(center.addObserver(forName: NSWindow.didResignKeyNotification,
                object: newWindow, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.cancelInteraction(); self?.updateDim() }
                })
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification] {
                windowObservers.append(center.addObserver(forName: name, object: newWindow, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateDim() }
                })
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateDim() }
    deinit {
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        // The split container keeps the tracking area; native views tear down
        // on the main thread.
        MainActor.assumeIsolated { if let groupTracking { groupTracking.view.removeTrackingArea(groupTracking.area) } }
    }
    override var isHidden: Bool { didSet { if isHidden { cancelInteraction() } } }
    private func cancelInteraction() {
        titleFieldStore?.cancel()
        hover = false; groupHover = false; mouseStart = nil; selectionEvent = nil; pendingActivation = nil
        setResetSubtitle(nil, animated: false)
        closeButton.cancelInteraction(); resetParts?.region.cancelInteraction()
        shareButtonStore?.cancelInteraction(); muteButtonStore?.cancelInteraction()
        closeButton.isHidden = true; shareButtonStore?.isHidden = true
        updateColor()
    }
    ///
    /// the row's TabCellState.shouldDim takes the same window state here.
    private func updateDim() {
        dimmed = window.map { !$0.isKeyWindow && !$0.isMainWindow } ?? false
        // Muting needs the key window: the speaker's dimming follows it.
        muteButtonStore?.refreshAvailability()
        updateColor()
    }
    private func updateColor() {
        let dark = palette?.isDark ?? (effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        let title = palette?.title ?? .parcInk
        titleLabel.textColor = title
        resetParts?.subtitle.textColor = title.withAlphaComponent(SidebarRowAppearance.subtitleTextAlpha)
        icon.fallbackTintColor = title
        resetParts?.icon.fallbackTintColor = title
        closeButton.dark = dark; shareButtonStore?.dark = dark; muteButtonStore?.dark = dark
        speakerHost?.model.color = dark
            ? NSColor(white: 1, alpha: 0.592) : NSColor(white: 0, alpha: 0.565)
        captureButtonStore?.contentTintColor = title
        // Fill changes apply on the next layer update, without a transition,
        //
        // resettable row's hover belongs to its regions, not the row fill. A
        // split child leaves selection, hover and the ring to its split.
        let state = compactSplitChild
            ? SidebarRowAppearance(splitChild: true, splitGroupSelected: splitGroupSelected)
            : SidebarRowAppearance(current: selected, multiSelected: multiSelected, hovered: hover && !hasReset,
                                   highlighted: keyboardHighlighted || listFocusRing, dimmed: dimmed, keyDragged: keyDragged)
        background.dark = dark
        background.ringColor = palette?.maxContrastColor ?? .labelColor
        background.appearanceState = state
        guard let parts = resetParts else { return }
        parts.region.dark = dark; parts.body.dark = dark
        parts.region.corners = state.resetRegionCorners
        parts.body.hovered = hover && !parts.region.hovered && state.splitsResetRegions
        //
        parts.slash.color = SidebarRowAppearance.slashColor(dark: dark)
        parts.slash.alphaValue = parts.region.hovered || parts.body.hovered ? 0 : 1
    }
    private func resetHoverChanged() {
        updateColor()
        setResetSubtitle(compactSplitChild || editingTitle ? nil : resetParts?.region.hoverSubtitle, animated: true)
    }
    /// The hover subtitle fades in below the title while the title stack lifts
    ///
    /// flipped title stack moves the same 7 points up with −7. Switching
    /// between the two subtitles changes only the text.
    private func setResetSubtitle(_ subtitle: SidebarRowHoverSubtitle?, animated: Bool) {
        guard subtitle != shownSubtitle else { return }
        let wasVisible = shownSubtitle != nil, visible = subtitle != nil
        shownSubtitle = subtitle
        if let subtitle { resetParts?.subtitle.stringValue = subtitle.text }
        updateResetIcon()
        if shareable && visible != wasVisible { updateActions(); needsLayout = true }
        guard visible != wasVisible, let stack = titleStack.layer, let subtitleLabel = resetParts?.subtitle, let label = subtitleLabel.layer else { return }
        let lift = visible ? CATransform3DMakeTranslation(0, -SidebarRowAppearance.subtitleLift, 0) : CATransform3DIdentity
        let opacity: Float = visible ? 1 : 0
        let fromLift = stack.presentation()?.sublayerTransform ?? stack.sublayerTransform
        let fromOpacity = label.presentation()?.opacity ?? label.opacity
        CATransaction.begin(); CATransaction.setDisableActions(true)
        stack.sublayerTransform = lift; subtitleLabel.alphaValue = CGFloat(opacity)
        CATransaction.commit()
        stack.removeAnimation(forKey: "transform_animation"); label.removeAnimation(forKey: "opacity_animation")
        // Settled Reduce Motion is an adaptation shared with the row controls.
        guard animated, window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fromOpacity; fade.toValue = opacity
        let move = CABasicAnimation(keyPath: "sublayerTransform")
        move.fromValue = NSValue(caTransform3D: fromLift); move.toValue = NSValue(caTransform3D: lift)
        for animation in [fade, move] {
            animation.duration = SidebarRowAppearance.subtitleDuration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }
        label.add(fade, forKey: "opacity_animation"); stack.add(move, forKey: "transform_animation")
    }
    /// While the reset subtitle shows, the icon view shows resetTabIcon in
    ///
    /// subtitle keeps the page image.
    private func updateResetIcon() {
        let swap = shownSubtitle == .reset && resetParts?.icon.image != nil
        resetParts?.icon.isHidden = !swap
        icon.alphaValue = swap ? 0 : 1
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        guard window != nil, !isHiddenOrHasHiddenAncestor, !editingTitle else { return }
        mouseStart = convert(event.locationInWindow, from: nil); selectionEvent = event
        pendingActivation = prepareActivation?()
    }
    override func mouseUp(with event: NSEvent) {
        let beganHere = mouseStart != nil, originalEvent = selectionEvent ?? event
        let action = pendingActivation
        mouseStart = nil; selectionEvent = nil; pendingActivation = nil
        if beganHere && window != nil && !isHiddenOrHasHiddenAncestor
            && bounds.contains(convert(event.locationInWindow, from: nil)) {
            if Self.isRenameClick(originalEvent), beginRename?() == true { return }
            if selectionClick?(originalEvent) != true { _ = action?() }
        }
    }
    ///
    /// count to the window; the second click of a plain double-click on the
    ///
    /// buttons and reset region take their own presses, and a press that
    /// became a drag never reaches here.
    static func isRenameClick(_ press: NSEvent) -> Bool {
        press.clickCount == 2 && press.modifierFlags.isDisjoint(with: [.command, .shift, .option, .control])
    }
    ///
    override func accessibilityTitle() -> String? { titleLabel.stringValue }
    ///
    ///
    /// original activation lease here.
    override func accessibilityPerformPress() -> Bool {
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return false }
        return prepareActivation?()?() == true
    }
    var storedAccessibilityActions: [NSAccessibilityCustomAction] {
        super.accessibilityCustomActions() ?? []
    }
    var deferredAccessibilityActions: (index: Int, make: () -> [NSAccessibilityCustomAction])?
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return [] }
        return mergedAccessibilityActions + (makeAccessibilityActions?() ?? [])
    }
    /// The Mini Player speaker host this row was built with, while its mute
    /// button still shows it (another row can take the host over).
    private var builtSpeaker: SidebarSpeakerHost?
    var speakerHost: SidebarSpeakerHost? { muteButtonStore?.decoration as? SidebarSpeakerHost }
    /// Whether another render can reuse this row for `tab`: what only `init`
    /// sets (the close action's kind, the page type's glyph and role, the
    /// reset regions) still holds.
    func canShow(_ tab: BrowserTab) -> Bool {
        tab.id == tabID && tab.kind == built.kind && (tab.resetDestination != nil) == built.reset
            && InternalPage(urlString: tab.url) == built.page
    }
    private let built: (kind: TabKind, reset: Bool, page: InternalPage?)
    /// A kept page's outline hides, or leaves the screen, with its rows under
    /// the pointer. Rows with nothing to cancel stay as they are, so the
    /// outline has no layout left for when it shows again.
    override func viewDidHide() { super.viewDidHide(); resetPointer() }
    func resetPointer() {
        if hover || groupHover || mouseStart != nil || pendingActivation != nil { cancelInteraction() }
    }
    override func isAccessibilityEnabled() -> Bool {
        window != nil && !isHiddenOrHasHiddenAncestor && prepareActivation?() != nil
    }
    override func isAccessibilitySelected() -> Bool { selected || super.isAccessibilitySelected() }
    override func rightMouseDown(with event: NSEvent) {
        cancelInteraction()
        if let menu = menu(for: event) { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
    ///
    /// sends the cell's middle-click action on a middle-button press
    ///
    /// Compact split children keep the split cell's separate handler.
    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2, !compactSplitChild, window != nil, !isHiddenOrHasHiddenAncestor,
              !editingTitle, let close = closeButton.prepareAction?() else {
            super.otherMouseDown(with: event); return
        }
        cancelInteraction(); _ = close()
    }
    override func accessibilityPerformShowMenu() -> Bool {
        guard window != nil, !isHiddenOrHasHiddenAncestor, let menu = context?() else { return false }
        cancelInteraction(); menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY), in: self)
        return true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
        let press = selectionEvent
        mouseStart = nil; selectionEvent = nil; pendingActivation = nil; hover = false; updateActions()
        if compactSplitChild {
            //
            if let press { beginGroupDrag?(press, event) }
            return
        }
        sidebarDrag = beginSidebarMove?()
        splitDrag = beginSplitDrag?()
        let snapshot: NSImage
        if let sidebarDrag, sidebarDrag.items.count > 1 {
            snapshot = NSImage(size: bounds.size)
            snapshot.lockFocus(); NSColor.white.withAlphaComponent(0.7).setFill(); NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
            ("\(sidebarDrag.items.count) Items" as NSString).draw(at: NSPoint(x: 12, y: 9), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor])
            snapshot.unlockFocus()
        } else {
            snapshot = dragImage()
        }
        keyDragged = sidebarDrag != nil || splitDrag != nil
        if keyDragged { onKeyDrag?(true) }
        let item = NSPasteboardItem(); item.setString(tabID.uuidString, forType: Self.pasteboardType)
        if let sidebarDrag { item.setString(sidebarDrag.identifier.uuidString, forType: SidebarMoveSession.pasteboardType) }
        if let splitDrag { item.setString(splitDrag.identifier.uuidString, forType: SidebarSplitDrag.pasteboardType) }
        let drag = NSDraggingItem(pasteboardWriter: item)
        splitDragImage = snapshot
        drag.setDraggingFrame(bounds, contents: snapshot)
        beginDraggingSession(with: [drag], event: event, source: self)
    }
    ///
    ///
    /// before the row takes the key-dragged state. The row's frame is the
    /// cell's visible background, as for the split cell's drag image.
    private func dragImage() -> NSImage {
        // A drag from the reset icon would otherwise keep its hover fill and subtitle.
        resetParts?.region.cancelInteraction(); setResetSubtitle(nil, animated: false)
        updateColor(); layoutSubtreeIfNeeded()
        let image = NSImage(size: bounds.size)
        if let bitmap = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: bitmap); image.addRepresentation(bitmap)
        }
        return image
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .withinApplication ? .move : [] }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        sidebarDrag?.end(); sidebarDrag = nil
        splitDrag?.end(); splitDrag = nil
        splitDragImage = nil
        if keyDragged { keyDragged = false; onKeyDrag?(false) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return nil }
        return context?()
    }
}

enum SidebarSelectionCommandKind { case copyLinks, copyMarkdown, close, newFolder }

/// A main-menu opening owns one selection. Expiry consumes that intent instead
/// of falling through to a newly selected page or a different browser window.
@MainActor final class SidebarSelectionCommandTarget {
    let kind: SidebarSelectionCommandKind
    let title: String
    private let validate: () -> Bool
    private let execute: () -> Bool
    init(kind: SidebarSelectionCommandKind, title: String,
         validate: @escaping () -> Bool, execute: @escaping () -> Bool) {
        self.kind = kind; self.title = title; self.validate = validate; self.execute = execute
    }
    var isValid: Bool { validate() }
    @discardableResult func perform() -> Bool { validate() && execute() }
}

///
/// active Space's Space menu (SidebarSpaceMenuSurface), over any part of the
/// sidebar whose view has none.
final class SidebarView: SidebarSpaceMenuSurface, NSMenuItemValidation, OffscreenPresenting {
    var isPrivateBrowsing = false { didSet { addressBackground.incognito = isPrivateBrowsing } }
    var prepareWindowDrop: ((SidebarMoveSession, SidebarContainerLocation, SidebarItemReference?) -> (() -> Bool)?)?
    /// This window's copy of a session's items at a drop location.
    var prepareCopyDrop: ((SidebarMoveSession, [SidebarItemReference], SidebarContainerLocation, SidebarItemReference?) -> (() -> Bool)?)?
    /// This window's move of a session's items onto a dock Space's list.
    var prepareDockDrop: ((SidebarMoveSession, [SidebarItemReference], SidebarContainerLocation, SidebarItemReference?) -> (() -> Bool)?)?
    var prepareSidebarMoves: (([SidebarItemReference]) -> SidebarMoveSession?)?
    var prepareSidebarCopy: (([SidebarItemReference], FolderLinkFormat) -> (() -> Bool)?)?
    var canSelectItems: (() -> Bool)?
    private var onManagementCancel: (() -> Void)?
    /// All manager row activation, including the list responder and modifier
    /// selection, uses the same original-tab transaction as a plain click.
    func configureManagementInteraction(ownerValid: @escaping () -> Bool, onCancel: @escaping () -> Void) {
        canSelectItems = ownerValid
        onManagementCancel = onCancel
        onSelectTab = { [weak self] id in
            guard let self, ownerValid(), let state = self.hierarchyState,
                  let tab = state.tabs.first(where: { $0.id == id && $0.spaceID == self.activeSpaceID && $0.archivedAt == nil }),
                  let activate = self.prepareTabActivation?(tab) else { return }
            _ = activate()
        }
    }
    var prepareSidebarDeletion: (([SidebarItemReference]) -> (() -> Bool)?)?
    var prepareSidebarClose: (([SidebarItemReference]) -> (() -> Bool)?)?
    private var selectionRevision: UInt64 = 0
    private var selectionSheetCommand: UUID?
    private var itemSelection = SidebarItemSelection() {
        didSet { if itemSelection != oldValue { selectionRevision &+= 1 } }
    }
    private var selectionContext: SidebarHierarchySnapshot?
    /// `selectionContext` with every folder expanded; a change clears the selection (render).
    private var selectionStructure: SidebarHierarchySnapshot?
    private var selectionActive: SidebarItemReference?
    private var selectionWindowObserver: NSObjectProtocol?
    private var clearKeyObserver: NSObjectProtocol?
    override var acceptsFirstResponder: Bool { true }
    /// The sidebar is the list's keyboard stop (arrows, Shift, Delete, Escape),
    /// between Favorites and the list's controls; with no item, or while Space
    /// creation replaces the list, there is nothing to navigate, so Tab passes on.
    /// A hidden sidebar is no stop: Tab passes through it (isPresented).
    override var canBecomeKeyView: Bool {
        super.canBecomeKeyView && isPresented && !contentSurface.isHidden && !selectionOrder.isEmpty
    }
    /// Where the window owner's key-view loop enters the sidebar's Tab chain: a
    /// gate that never takes focus and leads to the first header control, or,
    /// while hidden, past the sidebar. A relink moves an outside link into the
    /// sidebar or any other member there (SidebarAccessibility.link).
    var keyViewEntry: NSView { keyViewGate }
    private let keyViewGate = NSView()
    /// The window owner's first key view after the sidebar. Nil keeps the window
    /// loop's own link out (SidebarAccessibility.link).
    weak var keyViewExit: NSView? { didSet { if keyViewExit !== oldValue { setNeedsKeyViewLinking() } } }
    deinit {
        if let selectionWindowObserver { NotificationCenter.default.removeObserver(selectionWindowObserver) }
        if let clearKeyObserver { NotificationCenter.default.removeObserver(clearKeyObserver) }
    }
    var onPreview: ((SidebarPreviewTarget) -> Void)?
    var onPreviewPreferencesChanged: (() -> Void)?
    /// Favorites' preview anchors; the shown page holds its rows'.
    private var favoriteAnchors: [SidebarPreviewTarget: NSView] = [:]
    private var previewAnchors: [SidebarPreviewTarget: NSView] {
        favoriteAnchors.merging(shownPage.previewAnchors) { _, row in row }
    }
    var onAddress: (() -> Void)?
    var onNewTab: (() -> Void)?
    var onNavigation: ((NavigationControlKind) -> NavigationControlInteraction?)?
    var onSettings: (() -> Void)?
    ///
    var onLibrary: ((LibraryEntryPage?) -> Void)?
    /// A Library flyout row's action through the window's download and capture
    /// routes; the window's file URL for a download row.
    var onLibraryItem: ((LibraryFlyoutAction) -> Bool)? {
        get { libraryEntry.onItemAction }
        set { libraryEntry.onItemAction = newValue }
    }
    var libraryDownloadFileURL: ((BrowserDownload) -> URL?)? {
        get { libraryEntry.downloadFileURL }
        set { libraryEntry.downloadFileURL = newValue }
    }
    var onToggle: (() -> Void)?
    var onNewSpace: (() -> Void)?
    var onNewFolder: (() -> Void)?
    var onNewEasel: (() -> Void)?
    var onNewNote: (() -> Void)?
    var onNewSplit: (() -> Void)?
    var plusMenuCanCreateEasel: () -> Bool = { false }
    var plusMenuCanCreateNote: () -> Bool = { false }
    var plusMenuCanSplit: () -> Bool = { false }
    var plusMenuTheme: SpaceTheme {
        get { plusMenu.theme }
        set { plusMenu.theme = newValue }
    }
    var onSelectTab: ((UUID) -> Void)?
    var onCloseTab: ((UUID) -> Void)?
    // Each prepared action captures the original native page identity.
    var prepareResetTab: ((BrowserTab) -> (() -> Bool)?)?
    /// A resettable row's icon region: reset, or separate with Command, then
    ///
    var prepareIconReset: ((BrowserTab, Bool) -> (() -> Bool)?)?
    var requestTabFavicon: ((BrowserTab, @escaping (NSImage?) -> Void) -> Void)?
    ///
    var requestSavedFavicon: ((BrowserTab, @escaping (NSImage?) -> Void) -> Void)?
    var prepareTabMute: ((BrowserTab, SidebarTabAudio) -> (() -> Bool)?)?
    var prepareTabActivation: ((BrowserTab) -> (() -> Bool)?)?
    var prepareTabClose: ((BrowserTab) -> (() -> Bool)?)?
    var prepareFavoritePointerAction: ((BrowserTab, FavoritePointerAction) -> (() -> Bool)?)?
    var prepareFavoriteActivation: ((BrowserTab) -> (() -> Bool)?)?
    var prepareFavoriteRename: ((BrowserTab) -> (() -> Bool)?)?
    var prepareFavoriteClose: ((BrowserTab) -> (() -> Bool)?)?
    var onArchiveTabs: ((BrowserTab, [UUID], Set<UUID>) -> Void)?
    private var todayOrder: [UUID] = []
    var onSplitTab: ((UUID) -> Void)?
    var prepareSidebarSpaceMove: (([SidebarItemReference], UUID) -> (() -> Bool)?)?
    var prepareSidebarNewSpace: (([SidebarItemReference]) -> (() -> Bool)?)?
    /// Turn “name” into Space for the original folder.
    var prepareTurnFolderIntoSpace: ((UUID) -> (() -> Bool)?)?
    var prepareSidebarMove: ((SidebarItemReference) -> SidebarMoveSession?)?
    var prepareSeparateSplitTab: ((UUID) -> (() -> Bool)?)?
    ///
    /// at that moment; `canCloseSplit` is its availability check.
    var prepareSplitClose: ((UUID) -> (() -> Bool)?)?
    /// The split cell menu's window-owned actions (SidebarSplitCellMenu) and
    /// its Archive Item (true) and Close (false).
    var prepareSplitCellCommand: ((UUID, SplitCellMenuCommand) -> (() -> Bool)?)?
    var prepareSplitCellClose: ((UUID, Bool) -> (() -> Bool)?)?
    var canCloseSplit: ((UUID) -> Bool)?
    /// Whether an original tab has a live page or local document editor in
    ///
    var hasPresentedContent: ((UUID) -> Bool)?
    var onBeginSplitDrag: ((UUID) -> SidebarSplitDrag?)?
    var canSelectSpace: ((UUID, UUID) -> Bool)?
    var onSelectSpace: ((UUID, UUID) -> Void)?
    var onToggleFolder: ((UUID) -> Void)?
    var onCopyFolderLinks: ((FolderLinkTarget, FolderLinkFormat) -> Void)?
    var prepareTabRename: ((BrowserTab) -> ((String) -> Bool)?)?
    var prepareFavoriteSplitRename: ((SidebarSplitTitleEdit) -> (() -> Bool)?)?
    var prepareSplitAppearance: ((SidebarSplitTitleEdit, Bool) -> (() -> Bool)?)?
    var prepareSplitRename: ((SidebarSplitTitleEdit) -> ((String) -> Bool)?)?
    var onTitleEditFinished: (() -> Void)?
    /// Reveals the sidebar before a rename, as the window's Rename does. A
    /// hidden sidebar waits unhidden off-screen, where its rename field would
    /// take focus [C], so a row's Rename (menu or accessibility action) has the
    /// owner float it in and settle any motion (a hide in motion still reports
    /// presented), and edits only once it is presented.
    var revealForEditing: (() -> Void)?
    private var titleEdit: (tab: BrowserTab, row: SidebarTabRow, selected: [UUID], focused: UUID?)?
    private var splitTitleEdit: (target: SidebarSplitTitleEdit, row: SidebarSplitGroupView, selected: [UUID], focused: UUID?)?
    private var latestFocusedTabID: UUID?

    var isEditingTitle: Bool { titleEdit != nil || splitTitleEdit != nil || folderTitleEdit != nil }

    private var folderTitleEdit: (folder: BrowserFolder, row: SidebarFolderRow)?
    /// Prepares an inline rename of the original folder: commits a name, or
    /// nil when the folder cannot be renamed here.
    var prepareFolderRename: ((BrowserFolder) -> ((String) -> Bool)?)?
    /// New Folder with the selected items, editing its name in its row.
    var prepareFolderFromSelection: (([SidebarItemReference]) -> (() -> Bool)?)?
    /// Change Icon… for the original folder.
    var prepareFolderIcon: ((BrowserFolder) -> (() -> Bool)?)?
    /// The folder row and its icon's rect, where Change Icon… anchors.
    func folderIconAnchor(_ id: UUID) -> (view: NSView, rect: NSRect)? {
        guard let row = shownPage.folderRow(id, building: true), row.window != nil else { return nil }
        return (row, row.iconFrame)
    }
    ///
    /// collapsed folder still shows under it, in the order they were peeked.
    /// The active item is peeked through every collapsed folder on its path
    /// when it becomes active or one of those folders collapses, so it stays
    /// in view. Expanding the folder, the folder's Close This Folder button
    ///
    private var folderPeeks: [UUID: [SidebarItemReference]] = [:] {
        didSet { if folderPeeks != oldValue { onFolderPeeksChange?(folderPeeks) } }
    }
    var peekedItems: [UUID: [SidebarItemReference]] { folderPeeks }
    ///
    var onFolderPeeksChange: (([UUID: [SidebarItemReference]]) -> Void)?
    private var peekedActiveItem: SidebarItemReference?
    /// Rows must be rebuilt although the state is unchanged.
    private var outlineInvalidated = false
    /// Asks the owner for a render after a sidebar-only change.
    var onOutlineInvalidated: (() -> Void)?

    /// While the new-tab placeholder stands in for the active item, peeks
    /// keep their last active item (`keepActive`).
    private func updateFolderPeeks(state: BrowserState, active: SidebarItemReference?, keepActive: Bool = false) {
        guard !isSpaceManagement else { folderPeeks = [:]; peekedActiveItem = nil; return }
        let folders = Dictionary(state.folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var next: [UUID: [SidebarItemReference]] = [:]
        for (id, items) in folderPeeks {
            guard let folder = folders[id], !folder.isExpanded else { continue }
            let children = SidebarHierarchy.children(in: .init(spaceID: folder.spaceID, folderID: id, section: .pinned), state: state)
            let kept = items.filter(children.contains)
            if !kept.isEmpty { next[id] = kept }
        }
        if let active, !keepActive {
            let previous = shownPage.spaceID == state.activeSpaceID ? shownPage.renderedDisclosure?.expanded : nil
            var child = active
            var location = SidebarHierarchy.location(of: child, state: state, spaceID: state.activeSpaceID)
            while let folderID = location?.folderID, let folder = folders[folderID] {
                let collapsedNow = !folder.isExpanded && previous?[folderID] == true
                if !folder.isExpanded, active != peekedActiveItem || collapsedNow, !(next[folderID]?.contains(child) ?? false) {
                    next[folderID, default: []].append(child)
                }
                child = .folder(folderID)
                location = SidebarHierarchy.location(of: child, state: state, spaceID: state.activeSpaceID)
            }
        }
        // A peeked folder row that is itself collapsed shows only its own
        // peeks; once it has none, its parent stops listing it.
        var pruned = true
        while pruned {
            pruned = false
            for (id, items) in next {
                let kept = items.filter { item in
                    guard case .folder(let child) = item, folders[child]?.isExpanded == false else { return true }
                    return !(next[child]?.isEmpty ?? true)
                }
                guard kept.count != items.count else { continue }
                next[id] = kept.isEmpty ? nil : kept; pruned = true
            }
        }
        if !keepActive { peekedActiveItem = active }
        folderPeeks = next
    }

    /// A restored window's saved peeks; the first render drops any whose
    /// folder has since opened or lost the item.
    func restoreFolderPeeks(_ peeks: [UUID: [SidebarItemReference]]) {
        folderPeeks = peeks
    }

    private func removePeek(_ item: SidebarItemReference) {
        for (id, items) in folderPeeks where items.contains(item) {
            let kept = items.filter { $0 != item }
            folderPeeks[id] = kept.isEmpty ? nil : kept
            outlineInvalidated = true
        }
    }

    private func closeFolderPeek(_ id: UUID) {
        guard folderPeeks.removeValue(forKey: id) != nil else { return }
        outlineInvalidated = true
        onOutlineInvalidated?()
    }

    /// Runs an item's Close after taking it out of any peek.
    private func closingPeek(_ item: SidebarItemReference, _ action: (() -> Bool)?) -> (() -> Bool)? {
        guard let action else { return nil }
        return { [weak self] in
            self?.removePeek(item)
            let done = action()
            if self?.outlineInvalidated == true { self?.onOutlineInvalidated?() }
            return done
        }
    }

    ///
    /// whose placeholder is "Folder Title"; an emptied name leaves the folder
    ///
    /// folder is untitled, so its field starts empty (`untitled`).
    @discardableResult func beginFolderTitleEditing(_ id: UUID, untitled: Bool = false) -> Bool {
        guard !isEditingTitle, !isSpaceManagement, let state = hierarchyState,
              let folder = state.folders.first(where: { $0.id == id }),
              let row = shownPage.folderRow(id, building: true), row.window != nil,
              let commit = prepareFolderRename?(folder), presentsForEditing(reveal: revealForEditing) else { return false }
        folderTitleEdit = (folder, row)
        list.scrollRowToVisible(SidebarItemReference.folder(id), inset: 3)
        let initial = folder.name
        let began = row.beginTitleEditing(untitled ? "" : initial) { [weak self, weak row] value in
            guard let self, let row, self.folderTitleEdit?.row === row else { return }
            self.folderTitleEdit = nil
            if let value {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = trimmed.isEmpty ? SidebarFolderRow.untitled : trimmed
                if name != initial { _ = commit(name) }
            }
            self.onTitleEditFinished?()
        }
        if !began { folderTitleEdit = nil }
        return began
    }

    @discardableResult func beginTitleEditing(_ tab: BrowserTab) -> Bool {
        guard !isEditingTitle, let state = hierarchyState,
              let row = shownPage.tabRow(tab.id, building: true),
              let commit = prepareTabRename?(tab), presentsForEditing(reveal: revealForEditing) else { return false }
        titleEdit = (tab, row, state.selectedTabIDs, latestFocusedTabID)
        list.scrollRowToVisible(shownPage.item(showing: tab.id), inset: 3)
        let initial = SidebarTabTitle.display(tab)
        let began = row.beginTitleEditing(initial) { [weak self, weak row] value in
            guard let self, let row, self.titleEdit?.row === row else { return }
            self.titleEdit = nil
            if let value, value != initial { _ = commit(value) }
            self.onTitleEditFinished?()
        }
        if !began { titleEdit = nil }
        return began
    }

    func appearanceAnchor(for group: BrowserSplitLayout) -> NSView? {
        if let anchor = group.sidebarAnchorID, let tile = favoriteTiles[anchor] { return tile }
        return shownPage.splitRow(group.id, building: true)
    }

    ///
    /// prepares its action from current state when the menu opens.
    private func splitCellMenu(_ group: BrowserSplitLayout, state: BrowserState) -> NSMenu {
        var menu = SidebarSplitCellMenu(orientation: group.orientation)
        menu.bindShortcut = { item, id in KeyboardShortcuts.shared.showBinding(on: item, for: id) }
        menu.separateAll = prepareSplitCellCommand?(group.id, .separateAll)
        menu.addTab = prepareSplitCellCommand?(group.id, .addTab)
        menu.convert = prepareSplitCellCommand?(group.id, .convertOrientation)
        menu.children = group.tabIDs.compactMap { id in
            guard let tab = state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }) else { return nil }
            let submenu = SidebarSplitCellMenu.childSubmenu(separate: prepareSeparateSplitTab?(id),
                tabMenu: tabMenu(tab, allowsRename: false), replacing: ["Separate Tab from Split View", "Open in Split View"])
            return (SidebarTabTitle.display(tab), submenu)
        }
        if let profileID = state.spaces.first(where: { $0.id == group.spaceID })?.profileID,
           let target = SidebarSplitTitleEdit(group: group, profileID: profileID, state: state) {
            menu.reset = prepareSplitAppearance?(target, true)
            menu.changeIcon = prepareSplitAppearance?(target, false)
            if prepareSplitRename?(target) != nil { menu.rename = { [weak self] in self?.beginTitleEditing(target) == true } }
        }
        menu.duplicate = prepareSidebarDuplicate?([.split(group.id)])
        let moves = moveMenu(for: .split(group.id), state: state)
        menu.moves = moves.items
        moves.removeAllItems()
        menu.showsNewFolder = !isPrivateBrowsing
        menu.newFolder = isPrivateBrowsing ? nil : prepareSplitCellCommand?(group.id, .newFolder)
        // Private windows never archive; like the tab menu, they offer Close.
        menu.showsArchive = !isPrivateBrowsing
        menu.archive = isPrivateBrowsing ? nil : prepareSplitCellClose?(group.id, true)
        if SidebarHierarchy.location(of: .split(group.id), state: state, spaceID: state.activeSpaceID)?.section == .today,
           let anchorID = group.sidebarAnchorID ?? group.tabIDs.first,
           let anchor = state.tabs.first(where: { $0.id == anchorID && $0.archivedAt == nil }),
           let sets = SidebarSplitCellMenu.archiveGroupIDs(order: todayOrder, children: Set(group.tabIDs)) {
            let order = todayOrder
            // A private window closes, as the tab menu's group says.
            menu.archiveGroup = zip(SidebarSplitCellMenu.archiveGroupTitles, sets).map { title, ids in
                (isPrivateBrowsing ? title.replacingOccurrences(of: "Archive", with: "Close") : title,
                 ids.isEmpty ? nil : { [weak self] in self?.onArchiveTabs?(anchor, order, ids); return self != nil })
            }
        }
        menu.close = prepareSplitCellClose?(group.id, false)
        return menu.makeMenu()
    }

    private func appendSplitAppearance(to menu: NSMenu, target: SidebarSplitTitleEdit) {
        let choose = prepareSplitAppearance?(target, false)
        let icon = MenuAction.item("Change Icon…") { _ = choose?() }; icon.isEnabled = choose != nil
        menu.addItem(icon)
        if target.group.customTitle != nil || target.group.customIcon != nil {
            let restore = prepareSplitAppearance?(target, true)
            let reset = MenuAction.item("Reset Name and Icon") { _ = restore?() }; reset.isEnabled = restore != nil
            menu.addItem(reset)
        }
    }

    private func splitAppearanceActions(_ target: SidebarSplitTitleEdit) -> [NSAccessibilityCustomAction] {
        var actions: [NSAccessibilityCustomAction] = []
        if let choose = prepareSplitAppearance?(target, false) { actions.append(.init(name: "Change Split View Icon", handler: choose)) }
        if let reset = prepareSplitAppearance?(target, true) { actions.append(.init(name: "Reset Name and Icon", handler: reset)) }
        return actions
    }

    @discardableResult func beginTitleEditing(_ target: SidebarSplitTitleEdit) -> Bool {
        guard !isEditingTitle, let state = hierarchyState, target.matches(state),
              let row = shownPage.splitRow(target.group.id, building: true),
              let commit = prepareSplitRename?(target), presentsForEditing(reveal: revealForEditing) else { return false }
        splitTitleEdit = (target, row, state.selectedTabIDs, latestFocusedTabID)
        list.scrollRowToVisible(SidebarItemReference.split(target.group.id), inset: 3)
        let initial = target.group.customTitle ?? ""
        let began = row.beginTitleEditing(initial) { [weak self, weak row] value in
            guard let self, let row, self.splitTitleEdit?.row === row else { return }
            self.splitTitleEdit = nil
            if let value, value != initial { _ = commit(value) }
            self.onTitleEditFinished?()
        }
        if !began { splitTitleEdit = nil }
        return began
    }

    var onRenameFolder: ((UUID) -> Void)?
    var prepareFolderDeletion: ((UUID) -> (() -> Bool)?)?
    var prepareFolderDuplicate: ((UUID) -> (() -> Bool)?)?
    var prepareSidebarDuplicate: (([SidebarItemReference]) -> (() -> Bool)?)?
    var onNewSubfolder: ((UUID) -> Void)?
    /// Library cards reuse the real Space header/list, without the window's
    /// address bar, Profile-wide App Tray or dock. Actions retain their card ID.
    var isSpaceManagement = false
    var managementItemMenu: ((SidebarItemReference) -> NSMenu?)?
    var onRenameSpace: ((UUID) -> Void)?
    var makeSpaceManagementMenu: ((UUID) -> SidebarSpaceMenu?)?
    var onChangeSpaceIcon: ((UUID) -> Void)?
    private var editingSpace: BrowserSpace?
    /// The last render's header visibility rule, without the editing session.
    private var spaceHeaderContentShown: Bool {
        get { shownPage.headerContentShown } set { shownPage.headerContentShown = newValue }
    }
    var isEditingSpaceName: Bool { editingSpace != nil }
    func spaceAppearanceAnchor(_ id: UUID) -> NSView? {
        if id == activeSpaceID, !spaceHeader.isHidden { return spaceHeader }
        if let button = spaceButtonsByID[id], button.window != nil { return button }
        return self
    }
    @discardableResult func beginSpaceNameEditing(_ expected: BrowserSpace, finished: @escaping (String?) -> Void) -> Bool {
        guard expected.id == activeSpaceID, editingSpace == nil else { return false }
        editingSpace = expected; spaceHeader.isHidden = false
        needsLayout = true; layoutSubtreeIfNeeded()
        let began = spaceHeader.beginNameEditing(title: expected.title) { [weak self] value in
            guard let self else { finished(value); return }
            self.editingSpace = nil
            // A Library card's unchanged catalog skips its next render, so the
            // session's header hides here when the rule does not show it.
            if !self.spaceHeaderContentShown { self.spaceHeader.isHidden = true; self.needsLayout = true }
            finished(value)
        }
        if !began {
            editingSpace = nil
            if !spaceHeaderContentShown { spaceHeader.isHidden = true; needsLayout = true }
        }
        return began
    }
    func cancelSpaceNameEditing() { spaceHeader.cancelNameEditing(); editingSpace = nil }
    var onEditTheme: (() -> Void)?
    var onClearToday: (() -> Void)?
    /// Whether Clear has a Today tab it may archive; nil allows every one.
    var canClearToday: (() -> Bool)?
    /// The address pill's Site Control Center entry (WEB14); a secondary
    /// click opens Parc's page menu.
    var onPageMenu: (() -> Void)?
    var onPageActionsMenu: (() -> Void)?
    var onPaymentMenu: ((NSView) -> Void)?
    var onCaptureMenu: ((UUID, NSView) -> Void)?
    /// Live: whether this tab's page is capturing now, read when a menu opens.
    var captureIsActive: ((UUID) -> Bool)?
    ///
    var prepareShareThisTab: ((UUID) -> (() -> Bool)?)?
    let extensionToolbar = ExtensionToolbarView()
    /// The URL bar gives way to the Toolbar (`PaneTopBarAdmission
    /// .sidebarAddressBarShown`); Back, Forward and Reload go with it.
    private var hiddenAddressHeight: CGFloat {
        SidebarChromeLayout.hiddenAddressHeight(toolbar: usesContentToolbar,
            hasPrompt: paymentWidth > 0, keyboardSearch: keyboardSearchActive)
    }
    var addressEditorAnchor: NSView { addressButton }
    var usesContentToolbar = false {
        didSet {
            guard oldValue != usesContentToolbar else { return }
            for view in [addressBackground, addressButton, pageActions, extensionToolbar] as [NSView] {
                view.isHidden = usesContentToolbar
            }
            updateSharedQuoteVisibility()
            // Payment/popup prompts retain their genuine sidebar entry. The
            // existing address-region keyboard session keeps its stable anchor.
            needsLayout = true
        }
    }
    /// The focused pane's own top bar carries Back, Forward and Reload, so the
    /// header keeps only the sidebar button. A split pane's bar does this while
    /// the URL bar stays.
    var navigationInContentToolbar = false {
        didSet { if oldValue != navigationInContentToolbar { needsLayout = true } }
    }
    private let miniPlayers = MiniPlayerDeck()
    private let archiveEducation = AutoArchiveEducationView(frame: .zero)
    private lazy var archiveEducationHost = SidebarBannerHost(card: archiveEducation)
    var onDismissAutoArchiveEducation: (() -> Void)?
    var onAutoArchiveEducationSettings: (() -> Void)?
    var onBannerRelinquishFocus: (() -> Void)?

    func showAutoArchiveEducation(_ visible: Bool) {
        archiveEducationHost.show(visible)
        archiveEducationHost.setInteractionAllowed(isPresented && creationView == nil)
    }
    func resetAutoArchiveEducation() { archiveEducationHost.reset() }
    // Update Complete shares the education card's slot; one shows at a time.
    private let updateComplete = UpdateCompleteCard(frame: .zero)
    private lazy var updateCompleteHost = SidebarBannerHost(card: updateComplete)
    var onSeeWhatsNew: (() -> Void)?
    var onShareParc: (() -> Void)?
    var onDismissUpdateComplete: (() -> Void)?
    func showUpdateComplete(_ visible: Bool) {
        updateCompleteHost.show(visible)
        updateCompleteHost.setInteractionAllowed(isPresented && creationView == nil)
    }
    func resetUpdateComplete() { updateCompleteHost.reset() }
    private let updateReady = UpdateReadyCard(frame: .zero)
    private lazy var updateReadyHost = SidebarBannerHost(card: updateReady)
    var onRestartAndUpdate: (() -> Void)?
    var onToggleAutomaticUpdates: (() -> Void)?
    /// `automaticUpdates` is nil while the card isn't shown, so a leaving card keeps its state.
    func showUpdateReady(_ visible: Bool, automaticUpdates: Bool?) {
        if let automaticUpdates { updateReady.setAutomaticUpdates(automaticUpdates) }
        if visible && !updateReadyHost.isShowing { updateReady.collapse() }
        updateReadyHost.show(visible)
        updateReadyHost.setInteractionAllowed(isPresented && creationView == nil)
    }
    func resetUpdateReady() { updateReadyHost.reset() }
    private var miniPlayerIDs: [String] = []
    func updateMiniPlayers(_ items: [MiniPlayerItem]) {
        miniPlayers.update(items)
        // New rows' controls join the Tab chain; metadata updates do not relink.
        let ids = items.map(\.id)
        if ids != miniPlayerIDs { miniPlayerIDs = ids; setNeedsKeyViewLinking() }
    }
    private var tabAudio: [UUID: SidebarTabAudio] = [:]
    private var favoriteOverlays: [UUID: FavoriteTileOverlayState] = [:]
    /// TAB16 overlay producer input, keyed by the tile's tab. Tiles compare with
    /// their current overlays, so repeated renders never restart motion.
    func updateFavoriteOverlays(_ overlays: [UUID: FavoriteTileOverlayState]) {
        favoriteOverlays = overlays
        for (id, tile) in favoriteTiles { tile.setOverlays(overlays[id] ?? .none) }
    }
    var pageControlsAnchor: NSView { pageActions }
    var keyboardSearchAnchor: NSView { addressButton }
    private var keyboardHighlightedItem: SidebarItemReference?
    private let keyboardHighlight = SidebarKeyboardHighlightView()
    private weak var keyboardHighlightedRow: SidebarTabRow?
    private var keyboardSearchActive = false

    func setKeyboardSearchActive(_ active: Bool) {
        keyboardSearchActive = active
        updateSharedQuoteVisibility()
        // The child command field owns this exact address region while open.
        for view in [addressBackground, addressButton, pageActions, paymentAction, extensionToolbar] as [NSView] {
            view.alphaValue = active ? 0 : 1
        }
        if !active { updateAddressButtonsReveal(animated: false) }
    }

    private var addressText = ""
    private func applyAddressPillStyle() {
        addressBackground.style = .urlBar
        addressButton.focusRingCornerRadius = SidebarAddressPillView.cornerRadius
        shareQuote.contentTintColor = palette?.maxContrastColor ?? .labelColor
        copyQuote.contentTintColor = palette?.maxContrastColor ?? .labelColor
    }
    /// The URL bar's text for the focused tab. What's New shows its title,
    ///
    private static func address(of tab: BrowserTab?) -> String {
        guard let tab else { return SidebarAddressSearchIcon.placeholder }
        if InternalPage(urlString: tab.url) != nil { return "Easel" }
        if WhatsNewPage.matches(tab.url) { return tab.title }
        guard let url = URL(string: tab.url) else { return SidebarAddressSearchIcon.placeholder }
        return url.isFileURL ? url.lastPathComponent : SidebarAddressSearchIcon.host(of: url) ?? SidebarAddressSearchIcon.placeholder
    }
    /// CommandBarPlaceholderTextView's host text: system 13 regular
    ///
    ///
    private func setAddressTitle(_ address: String) {
        addressText = address
        let empty = address == SidebarAddressSearchIcon.placeholder
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = empty ? SidebarAddressSearchIcon.textIndent : SidebarChromeLayout.addressTextIndent
        paragraph.lineBreakMode = .byTruncatingTail
        let color = (palette?.isDark == true ? NSColor.white : NSColor.black).withAlphaComponent(0.6)
        addressSearchIcon.isHidden = !empty; addressSearchIcon.contentTintColor = color
        addressButton.attributedTitle = NSAttributedString(string: address, attributes: [
            .font: NSFont.systemFont(ofSize: SidebarChromeLayout.addressFontSize), .foregroundColor: color, .paragraphStyle: paragraph,
        ])
        addressButton.setAccessibilityLabel(address)
    }

    // MARK: URL bar buttons (SidebarAddressButtonsReveal)

    private var toggleGlyphPointSize = SidebarChromeLayout.navigationGlyphPointSize
    private var revealTracking: NSTrackingArea?
    ///
    private var pointerInSidebar = false {
        didSet { if pointerInSidebar != oldValue { updateAddressButtonsReveal(); updateClearReveal() } }
    }
    ///
    private var sidebarFloating = false
    ///
    private var showingAddressMenu = false
    ///
    ///
    /// Parc's owners are the Site Control Center popover and permission
    /// prompts anchored to the pill.
    private var addressPopovers = Set<ObjectIdentifier>()
    func setAddressPopover(_ owner: AnyObject, open: Bool) {
        let id = ObjectIdentifier(owner)
        guard open ? addressPopovers.insert(id).inserted : addressPopovers.remove(id) != nil else { return }
        updateAddressButtonsReveal()
    }
    private var firstResponderObservation: NSKeyValueObservation?
    /// Parc adaptation: keyboard focus on the address button, Site Control
    /// Center or a pinned extension reveals the buttons.
    private var addressControlFocused: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder === addressButton || responder === pageActions || responder.isDescendant(of: extensionToolbar)
    }
    private func observeFirstResponder() {
        firstResponderObservation = window?.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateAddressButtonsReveal() }
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let revealTracking { removeTrackingArea(revealTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area); revealTracking = area
    }
    override func mouseEntered(with event: NSEvent) {
        guard let revealTracking, event.trackingArea === revealTracking else { super.mouseEntered(with: event); return }
        pointerInSidebar = isPresented
        refreshClearAvailability()
    }
    /// Another window's page ownership changes without a render, so Clear
    /// re-reads `canClearToday` as the pointer enters the sidebar or Clear and
    /// as the window becomes key.
    private var clearAvailable: Bool { todayHasTabs && onClearToday != nil && canClearToday?() != false }
    ///
    /// Library card (SpaceContainerType home) and otherwise while the
    ///
    /// divider cell, and so Clear, exists only with Today items.
    private var clearShown: Bool { isSpaceManagement || pointerInSidebar }
    /// Clear is unhidden before its fade-in and hidden in its fade-out's
    ///
    /// clicks, key focus or accessibility. Until then it holds its place in
    /// the divider's row and the border ends 8 points before it; NSStackView
    /// lays out only unhidden views.
    private var clearRevealed: Bool { get { shownPage.clearRevealed } set { shownPage.clearRevealed = newValue } }
    /// Only the latest fade's completion may hide Clear.
    private var clearRevealGeneration = 0
    private func updateClearReveal() {
        guard let clearButton else { return }
        let shown = clearShown
        guard shown != clearRevealed else { return }
        clearRevealed = shown
        clearRevealGeneration += 1
        let generation = clearRevealGeneration
        if shown { clearButton.isHidden = false; clearButton.refreshHover(); clearButton.superview?.needsLayout = true }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = SidebarClearAppearance.revealDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            clearButton.animator().alphaValue = shown ? 1 : 0
        }, completionHandler: { [weak self, weak clearButton] in
            MainActor.assumeIsolated {
                guard let self, let clearButton, clearButton === self.clearButton,
                      generation == self.clearRevealGeneration, !self.clearRevealed else { return }
                clearButton.isHidden = true
                clearButton.refreshHover()
                clearButton.superview?.needsLayout = true
            }
        })
    }
    private func refreshClearAvailability() {
        let available = clearAvailable
        guard let clearButton, clearButton.isEnabled != available else { return }
        clearButton.isEnabled = available
        clearButton.refreshHover()
    }
    override func mouseExited(with event: NSEvent) {
        guard let revealTracking, event.trackingArea === revealTracking else { super.mouseExited(with: event); return }
        pointerInSidebar = false
    }
    private func retestPointerInSidebar() {
        guard let window, isPresented else { pointerInSidebar = false; return }
        pointerInSidebar = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
    private func updateAddressButtonsReveal(animated: Bool = true) {
        guard !keyboardSearchActive else { return }
        let revealed = SidebarAddressButtonsReveal.revealed(sidebarHovered: pointerInSidebar || addressControlFocused,
                                                            showingMenu: showingAddressMenu || !addressPopovers.isEmpty,
                                                            anchored: !sidebarFloating)
        SidebarAddressButtonsReveal.apply(SidebarAddressButtonsReveal.showsSiteControlCenter(revealed: revealed, copyQuoteLink: showsSharedQuote),
                                          to: pageActions, animated: animated)
        SidebarAddressButtonsReveal.apply(revealed, to: extensionToolbar, animated: animated)
    }

    func highlightItemForKeyboard(_ item: SidebarItemReference?, scrollToHighlight: Bool) {
        keyboardHighlightedItem = item
        keyboardHighlight.removeFromSuperview()
        keyboardHighlightedRow?.keyboardHighlighted = false; keyboardHighlightedRow = nil
        keyboardHighlightedGroup?.keyboardHighlighted = false; keyboardHighlightedGroup = nil
        keyboardHighlightedFolder?.keyboardHighlighted = false; keyboardHighlightedFolder = nil
        // A highlighted Favorite (single or split) shows its own App Tray ring,
        //
        let favorite = item.flatMap { favoriteItems.firstIndex(of: $0) }.map { favorites[$0] }
        for tile in favoriteTiles.values { tile.setKeyboardHighlighted(tile === favorite) }
        let row: NSView?
        if let favorite { row = favorite }
        else if let item, let view = shownPage.rowView(for: item, building: scrollToHighlight) { row = view }
        else if case .tab(let id) = item { row = shownPage.tabRow(id, building: scrollToHighlight) ?? previewAnchors[.tab(id)] }
        else { row = nil }
        guard let row else { return }
        markKeyboardHighlight(row, favorite: favorite != nil)
        if scrollToHighlight {
            if favorite != nil { row.scrollToVisible(row.bounds.insetBy(dx: 0, dy: -3)) }
            else if let item { list.scrollRowToVisible(shownPage.item(showing: item), inset: 3) }
        }
    }

    /// The keyboard cursor on `row`, drawn by the row itself where it can.
    private func markKeyboardHighlight(_ row: NSView, favorite: Bool) {
        if let tabRow = row as? SidebarTabRow {
            //
            tabRow.keyboardHighlighted = true; keyboardHighlightedRow = tabRow
        } else if let group = row as? SidebarSplitGroupView {
            // So does the split cell's CellSelectionStateView.
            group.keyboardHighlighted = true; keyboardHighlightedGroup = group
        } else if let folder = row as? SidebarFolderRow {
            // And the folder cell's.
            folder.keyboardHighlighted = true; keyboardHighlightedFolder = folder
        } else if !favorite {
            keyboardHighlight.frame = row.bounds
            keyboardHighlight.autoresizingMask = [.width, .height]
            row.addSubview(keyboardHighlight)
        }
    }

    private var spaces: [BrowserSpace] = []
    private var folders: [BrowserFolder] = []
    private var activeSpaceID: UUID?
    /// Scroll/attention is intentionally separate from item activation and from
    /// multi-selection. A reveal cannot load or take ownership of a live page.
    ///
    func revealItem(_ item: SidebarItemReference) {
        layoutSubtreeIfNeeded()
        guard let row = shownPage.rowView(for: item, building: true) else { return }
        // The row keeps its view while the scroll brings it in.
        revealedItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated { if self?.revealedItem == item { self?.revealedItem = nil } }
        }
        list.scrollRowToVisible(item, inset: 4)
        NSAccessibility.post(element: row, notification: .layoutChanged)
        SidebarAttentionShake.play(on: row)
    }
    private var revealedItem: SidebarItemReference?

    ///
    /// row into view without the reveal's attention shake.
    func scrollItemToVisible(_ item: SidebarItemReference) {
        layoutSubtreeIfNeeded()
        guard shownPage.items.contains(item) else { return }
        list.scrollRowToVisible(item, inset: 4)
    }

    ///
    /// off-screen ones (`spaceViewControllerCache`, an NSCache whose count
    ///
    ///
    private var pages: [UUID: SidebarSpacePage] = [:]
    /// The kept pages' Spaces, the most recently shown last.
    private var pageOrder: [UUID] = []
    private static let keptPages = 10
    /// The page on screen; before the first render, one no Space owns yet.
    private lazy var shownPage: SidebarSpacePage = {
        let page = makePage()
        page.list.preparesRowsInLayout = true
        return page
    }()
    ///
    /// and the Space header above it (SidebarSpaceHeader.swift), the shown page's.
    private var scroll: SidebarPagingScrollView { shownPage.scroll }
    private var list: SidebarOutlineView { shownPage.list }
    private var spaceHeader: SidebarSpaceHeaderView { shownPage.header }
    /// Outlines of pages let go, taken apart a row at a time while idle.
    private var retiredLists: [SidebarOutlineView] = []
    private let favoritesHost = NSView()
    ///
    /// the tray until its profile dismisses it.
    private let favoritesEmptyState = FavoritesEmptyStateView()
    /// Records the Dismiss button's or Hide item's profile in the store.
    var dismissFavoritesEmptyState: ((UUID) -> Void)?
    /// Flips the app-wide showSpaceHeaderOnSingleUnnamedSpaces in the store
    /// (the header menu's Show/Hide Space Header).
    var toggleSpaceHeaderOnSingleUnnamedSpaces: (() -> Void)?
    ///
    private let spacesHost = SidebarDockStrip()
    private let contentSurface = LayoutView()
    private let creationScroll = NSScrollView()
    private var creationView: SpaceCreationView?
    private let creationSpaceButton = ActionButton("Create a Space", symbol: "plus")
    private let addressBackground = SidebarAddressPillView()
    private let addressButton = ActionButton()
    private let addressSearchIcon = SidebarAddressSearchIcon()
    private let shareQuote = ActionButton("Share Quote")
    private let copyQuote = ActionButton("Copy Current URL as Quote", symbol: "quote.bubble")
    private var sharedQuoteAction: (() -> Void)?
    private var showsSharedQuote: Bool { sharedQuoteAction != nil && !usesContentToolbar && !keyboardSearchActive }
    func updateSharedQuote(action: (() -> Void)?) {
        sharedQuoteAction = action
        shareQuote.actionBlock = action; copyQuote.actionBlock = action
        updateSharedQuoteVisibility()
    }
    private func updateSharedQuoteVisibility() {
        shareQuote.isHidden = !showsSharedQuote; copyQuote.isHidden = !showsSharedQuote
        updateAddressButtonsReveal()
        needsLayout = true
    }
    private let back = NavigationControlButton(SidebarAccessibility.goBack, symbol: "arrow.left", history: true, commandID: "goBack:",
                                               glyphPointSize: SidebarChromeLayout.navigationGlyphPointSize)
    private let forward = NavigationControlButton(SidebarAccessibility.goForward, symbol: "arrow.right", history: true, commandID: "goForward:",
                                                  glyphPointSize: SidebarChromeLayout.navigationGlyphPointSize)
    private let reload = NavigationControlButton(SidebarAccessibility.reload, symbol: "arrow.clockwise", commandID: "reload:",
                                                 glyphPointSize: SidebarChromeLayout.navigationGlyphPointSize)
    ///
    /// `chevron.down`); the window owner presents the menu (ReloadOptionsMenu).
    private let reloadOptions = NavigationControlButton("Reload options", symbol: "chevron.down")
    var onReloadOptions: ((NSView) -> Void)?
    private var developerReload = false
    private var developerForceReload = false
    private let footerMore = ActionButton("New Tab, Folder, or Space")
    private let plusMenu = SidebarPlusMenuController()
    private let plusButton = SidebarPlusButtonState()
    ///
    ///
    /// BoxOfThingsIcon button, "View Library", labelled "Home", no keyboard stop,
    /// with download progress in a badge cell above it (SidebarLibraryEntry.swift).
    private let libraryEntry = SidebarLibraryEntry()
    private let toggle = ActionButton(SidebarAccessibility.hideSidebar, symbol: "sidebar.left")
    private let windowButtons = WindowStandardButtons()
    private let pageActions = ActionButton("Site Control Center", symbol: "slider.horizontal.3")
    private let paymentAction = ActionButton("Payment methods", symbol: "creditcard")
    private var paymentWidth: CGFloat = 0
    /// Last payment-entry inputs applied to the control. Live chrome ticks that
    /// republish the same title/symbol/enabled/savedLabel skip sidebar layout.
    private var paymentEntryTitle: String?
    private var paymentEntrySymbol = "creditcard"
    private var paymentEntryEnabled = false
    private var paymentEntrySavedLabel = ""
    private var favorites: [FavoriteTile] = []
    private var favoriteItems: [SidebarItemReference] = []
    private var favoriteTiles: [UUID: FavoriteTile] = [:]
    /// Page URLs and split orientation last armed on each Favorite tile. Full
    /// `render` skips `loadFavicon` when membership rebuilds keep this identity.
    private var favoriteFaviconArms: [UUID: FavoriteFaviconIdentity] = [:]
    /// Page URL and reset destination last armed on each tab row. Full `render`
    /// / `makeRow` skips `loadFavicon` / `loadResetIcon` when identity matches
    /// and settled art can be adopted onto the replacement row.
    private var tabFaviconArms: [UUID: TabRowFaviconIdentity] = [:]
    private var spaceButtons: [ActionButton] = []
    /// The dock's Space buttons by Space ID. Renders update them in place, as
    ///
    /// button's accessibility element survive store updates.
    private var spaceButtonsByID: [UUID: ActionButton] = [:]
    /// Each dock Space button's Space menu by Space ID (SidebarDockItemMenu).
    private var spaceMenusByID: [UUID: SidebarDockItemMenu] = [:]
    /// The shown page's built tab rows.
    private var tabRows: [SidebarTabRow] { shownPage.tabRows }
    ///
    private var keyDraggedTabID: UUID?
    /// The split whose cell is the key item of an in-progress drag.
    private var keyDraggedSplitID: UUID?
    private weak var keyboardHighlightedGroup: SidebarSplitGroupView?
    private weak var keyboardHighlightedFolder: SidebarFolderRow?
    private var hierarchyState: BrowserState?
    /// The shown page's item rows in outline order.
    private var hierarchyRows: [(SidebarItemReference, NSView)] { shownPage.hierarchyRows }
    private let dropFeedback = SidebarDropFeedbackView()
    private var dropProposal: (SidebarMoveSession, SidebarContainerLocation, SidebarItemReference?)?
    private var windowDropAction: (() -> Bool)?
    private var copyDropAction: (() -> Bool)?
    private var dockDropAction: (() -> Bool)?
    private var pinnedEnd: NSView? { shownPage.pinnedEnd }
    private var todayStart: NSView? { shownPage.todayStart }
    /// Each page keeps one New Tab row across renders, so a render keeps its
    /// hover plate and lets a release bounce finish.
    private var newTabRow: SidebarNewTabRow { shownPage.newTabRow }
    private func makePage() -> SidebarSpacePage {
        let row = SidebarNewTabRow(dark: false) { [weak self] in self?.onNewTab?() }
        row.button.focusRingCornerRadius = SidebarRowAppearance.cornerRadius // a Parc ring in the hover plate's shape
        //
        // the state has no tooltip, so only the help carries it.
        LiveShortcutToolTip.help(row.button, "New tab", commandID: "newTab:")
        let page = SidebarSpacePage(newTabRow: row)
        configureHeader(page.header)
        page.scroll.offerScroll = { [weak self] event in self?.spacePager.scrollWheel(event) ?? false }
        page.list.focusOwner = self
        page.list.preparesRowsInLayout = false
        page.list.releaseContent = { [weak self, weak page] key, view in
            guard let self, let page, let item = key.base as? SidebarItemReference else { return }
            for row in page.remove(item, view) {
                guard let art = row.settledFaviconArt(), let arm = self.tabFaviconArms[row.tabID] else { continue }
                page.releasedFavicons[row.tabID] = (arm, art)
            }
        }
        page.list.contentLeftWindow = { view in
            (view as? SidebarTabRow)?.resetPointer()
            (view as? SidebarFolderRow)?.resetPointer()
            (view as? SidebarSplitGroupView)?.resetPointer()
        }
        page.list.keepsContent = { [weak self] key in
            guard let self, let item = key.base as? SidebarItemReference else { return false }
            return self.keepsRowView(item)
        }
        page.view.passesThrough = true
        // Built pages wait out of the strip's reach rather than hidden:
        // showing a long page again cost a frame.
        page.view.frame = NSRect(x: 3 * bounds.width, y: 0, width: bounds.width, height: bounds.height)
        pageStrip.addSubview(page.view)
        return page
    }
    ///
    /// is then the only current item: the tab and split cell builders report
    ///
    /// clears a split's child plates. The next render rebuilds the rows with
    /// it; until then the live-metadata path refuses. Favorites tiles do not
    /// read it.
    var newTabPlaceholderActive = false { didSet { newTabRow.current = newTabPlaceholderActive } }
    private var renderedNewTabPlaceholder = false
    private var clearButton: ActionButton? { shownPage.clearButton }
    private var todayHasTabs: Bool { shownPage.todayHasTabs }
    private var sectionLine: SidebarHairline? { shownPage.sectionLine }
    private var privateUnpinnedHeader: SidebarSpaceHeaderView? { shownPage.privateUnpinnedHeader }
    var showsPrivateProfileIndicator = false {
        didSet {
            guard showsPrivateProfileIndicator != oldValue else { return }
            privateUnpinnedHeader?.updateIncognitoIndicator(shown: showsPrivateProfileIndicator)
        }
    }
    var palette: ThemeChromePalette? { didSet { applyPalette() } }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([SidebarMoveSession.pasteboardType])
        addSubview(spaceCreationFeedback)
        addSubview(contentSurface)
        for view in [favoritesHost, addressBackground, addressButton, shareQuote, copyQuote, pageActions, paymentAction, extensionToolbar, pageStrip, miniPlayers] { contentSurface.addSubview(view) }
        contentSurface.addSubview(archiveEducationHost)
        archiveEducation.setInteractionEnabled(false)
        archiveEducation.onDismiss = { [weak self] in self?.onDismissAutoArchiveEducation?() }
        archiveEducation.onSettings = { [weak self] in self?.onAutoArchiveEducationSettings?() }
        archiveEducationHost.onLayoutChanged = { [weak self] in self?.setNeedsKeyViewLinking() }
        archiveEducationHost.onInteractionChanged = { [weak self] enabled in
            self?.archiveEducation.setInteractionEnabled(enabled)
            self?.setNeedsKeyViewLinking()
        }
        archiveEducationHost.onRelinquishFocus = { [weak self] in self?.onBannerRelinquishFocus?() }
        contentSurface.addSubview(updateCompleteHost)
        updateComplete.onSeeWhatsNew = { [weak self] in self?.onSeeWhatsNew?() }
        updateComplete.onShare = { [weak self] in self?.onShareParc?() }
        updateComplete.onDismiss = { [weak self] in self?.onDismissUpdateComplete?() }
        updateCompleteHost.onLayoutChanged = { [weak self] in self?.setNeedsKeyViewLinking() }
        updateCompleteHost.onInteractionChanged = { [weak self] enabled in
            self?.updateComplete.setInteractionEnabled(enabled)
            self?.setNeedsKeyViewLinking()
        }
        updateCompleteHost.onRelinquishFocus = { [weak self] in self?.onBannerRelinquishFocus?() }
        contentSurface.addSubview(updateReadyHost)
        updateReady.onRestart = { [weak self] in self?.onRestartAndUpdate?() }
        updateReady.onToggleAutomaticUpdates = { [weak self] in self?.onToggleAutomaticUpdates?() }
        // Opening or closing it also changes its key stops.
        updateReady.onHeightChange = { [weak self] in self?.setNeedsKeyViewLinking() }
        updateReadyHost.onLayoutChanged = { [weak self] in self?.setNeedsKeyViewLinking() }
        updateReadyHost.onInteractionChanged = { [weak self] enabled in
            self?.updateReady.setInteractionEnabled(enabled)
            self?.setNeedsKeyViewLinking()
        }
        updateReadyHost.onRelinquishFocus = { [weak self] in self?.onBannerRelinquishFocus?() }
        // The list's empty area and any other view without a menu of its own.
        spaceMenu = { [weak self] in self?.sidebarSpaceMenu() }
        for view in [keyViewGate, windowButtons, spacesHost, back, forward, reload, reloadOptions, footerMore, libraryEntry, toggle] { addSubview(view) }
        favoritesHost.addSubview(favoritesEmptyState)
        creationScroll.drawsBackground = false
        creationScroll.hasVerticalScroller = true; creationScroll.autohidesScrollers = true
        creationScroll.scrollerStyle = .overlay; creationScroll.isHidden = true
        addSubview(creationScroll)
        creationSpaceButton.title = ""; creationSpaceButton.imagePosition = .imageOnly
        //
        creationSpaceButton.parcTooltip = TooltipConfiguration("Create Space", anchor: .top)
        creationSpaceButton.isHidden = true
        creationSpaceButton.actionBlock = { [weak self] in self?.creationView?.focusName() }
        addSubview(dropFeedback)
        miniPlayers.onHeightChanged = { [weak self] in
            guard let self else { return }
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
        }
        miniPlayers.motionCompanion = { [weak self] in self?.scroll }
        miniPlayers.onKeyViewsChanged = { [weak self] in self?.setNeedsKeyViewLinking() }
        back.prepareInteraction = { [weak self] in self?.onNavigation?(.back) }
        forward.prepareInteraction = { [weak self] in self?.onNavigation?(.forward) }
        reload.prepareInteraction = { [weak self] in self?.onNavigation?(.reload) }
        reloadOptions.prepareInteraction = { [weak self] in
            guard let self, self.developerReload else { return nil }
            return NavigationControlInteraction(activate: { [weak self] _ in
                guard let self, self.developerReload, !self.reloadOptions.isHidden else { return }
                self.onReloadOptions?(self.reloadOptions)
            })
        }
        reloadOptions.isHidden = true
        reloadOptions.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Refresh options button")
        reloadOptions.windowControlStyle = true
        shareQuote.isHidden = true; copyQuote.isHidden = true
        // Clicking the affordance must preserve the original renderer selection.
        // Keyboard access remains the actual Copy URL as Quote menu command.
        shareQuote.refusesFirstResponder = true; copyQuote.refusesFirstResponder = true
        shareQuote.alignment = .left; shareQuote.font = .systemFont(ofSize: 13, weight: .semibold)
        shareQuote.contentTintColor = .linkColor
        shareQuote.setAccessibilityLabel("Share Quote")
        //
        // Quote as URL" with the binding's keycaps, the standard row. Its
        //
        // service, so it is not shown.
        LiveShortcutToolTip.set(shareQuote, "Copy Quote as URL", commandID: "copyCurrentURLAsQuote:")
        copyQuote.imagePosition = .imageOnly
        LiveShortcutToolTip.set(copyQuote, "Copy Quote as URL", commandID: "copyCurrentURLAsQuote:")
        copyQuote.setAccessibilityLabel("Copy Current URL as Quote")
        addressButton.actionBlock = { [weak self] in self?.onAddress?() }
        addressButton.alignment = .left
        addressButton.font = .systemFont(ofSize: SidebarChromeLayout.addressFontSize)
        addressSearchIcon.isHidden = true; addressButton.addSubview(addressSearchIcon)
        //
        LiveShortcutToolTip.help(addressButton, "Search or enter a URL", commandID: "focusAddress:")
        libraryEntry.onOpen = { [weak self] page in self?.onLibrary?(page) }
        libraryEntry.onFlyoutExpansion = { [weak self] expanded, count in self?.updateLibraryFlyoutMask(expanded, count: count) }
        toggle.actionBlock = { [weak self] in self?.onToggle?() }
        footerMore.actionBlock = { [weak self] in self?.showPlusMenu() }
        // The face draws the glyph; AppKit would draw the title.
        footerMore.title = ""
        plusButton.install(in: footerMore)
        footerMore.onHover = { [weak self] hovered in self?.plusButton.hovered = hovered }
        footerMore.onHighlight = { [weak self] pressed in self?.plusButton.pressed = pressed }
        plusMenu.onVisibilityChange = { [weak self] shown in
            guard let self else { return }
            self.plusButton.open = shown
            // The HUD takes key while open, so the hover may have gone stale.
            if !shown { self.footerMore.refreshHover() }
        }
        extensionToolbar.onWidthChange = { [weak self] in self?.needsLayout = true }
        pageActions.actionBlock = { [weak self] in self?.onPageMenu?() }
        pageActions.secondaryActionBlock = { [weak self] in
            guard let self else { return }
            // The page menu tracks synchronously; the pill's buttons stay revealed meanwhile.
            self.showingAddressMenu = true; self.updateAddressButtonsReveal()
            self.onPageActionsMenu?()
            self.showingAddressMenu = false; self.retestPointerInSidebar(); self.updateAddressButtonsReveal()
        }
        pageActions.hitTestsWhenTransparent = false
        extensionToolbar.hitTestsWhenTransparent = false
        LiveShortcutToolTip.set(pageActions, "Site Control Center")
        //
        if let glyph = SiteControlCenterArtwork.controlCenter { pageActions.image = glyph }
        paymentAction.isHidden = true
        paymentAction.imagePosition = .imageOnly
        paymentAction.font = .systemFont(ofSize: 11, weight: .medium)
        paymentAction.actionBlock = { [weak self] in
            guard let self else { return }
            self.onPaymentMenu?(self.paymentAction)
        }
        for button in [back, forward, reload, reloadOptions, toggle, pageActions] as [NSButton] { button.imagePosition = .imageOnly }
        toggle.image = NavigationControlArtwork.symbol("sidebar.left", pointSize: SidebarChromeLayout.navigationGlyphPointSize) ?? toggle.image
        toggle.translucentFace = TranslucentButtonFace(view: toggle)
        updateAddressButtonsReveal(animated: false)
        //
        //
        //
        // an NSView with no focus override hosting a SwiftUI button whose focus
        // effect is SwiftUI's own (inferred). Parc gives all five one rounded
        // ring over their bounds.
        toggle.focusRingCornerRadius = 5; footerMore.focusRingCornerRadius = 5
        for button in [back, forward, reload, reloadOptions] { button.focusRingCornerRadius = 5 }
        // The URL pill's surface is a HoverableView (no key view); its icon and
        // status buttons are HoverableButtons. Parc's one address button keeps
        // that rounded mask at the pill's radius.
        addressButton.focusRingCornerRadius = SidebarAddressPillView.cornerRadius
        //
        // a Parc ring so Full Keyboard Access shows its stop. The Library entry
        //
        for button in [pageActions, paymentAction] { button.focusRingCornerRadius = 5 }
        //
        // "Create Space" [O]; like the Space buttons it is no keyboard stop.
        creationSpaceButton.setAccessibilityLabel("Create Space")
        SidebarAccessibility.configureSpace(creationSpaceButton, name: "Create Space")
        extensionToolbar.onButtonsChange = { [weak self] in self?.setNeedsKeyViewLinking() }
        configureSpacePaging()
        shownPage.view.isHidden = false; shownPage.view.passesThrough = false
        SidebarInputClock.start()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Every page's Space header offers the shown Space's actions; only the
    /// shown page's takes input.
    private func configureHeader(_ header: SidebarSpaceHeaderView) {
        // The header's menu offers the Space actions Parc already has.
        header.isHidden = true
        header.managementMenu = { [weak self] in
            guard let self, let id = self.activeSpaceID else { return nil }
            return self.makeSpaceManagementMenu?(id)
        }
        header.onChangeIcon = { [weak self] in
            guard let self, let id = self.activeSpaceID else { return }
            self.onChangeSpaceIcon?(id)
        }
        header.onRenameSpace = { [weak self] in
            guard let self, let id = self.activeSpaceID else { return }
            self.onRenameSpace?(id)
        }
        header.onEditTheme = { [weak self] in self?.onEditTheme?() }
        header.onNewFolder = { [weak self] in self?.onNewFolder?() }
        header.onToggleHeader = { [weak self] in self?.toggleSpaceHeaderOnSingleUnnamedSpaces?() }
        //
        // header can show its edit button; Parc has no `.home` one [I].
        header.canShowHeaderButtonsIfPossible = true
    }

    // MARK: Mouse and trackpad navigation (docs/navigation.md)

    ///
    /// window's Spaces in dock order, each Space's header and tablist its own
    /// page view (SidebarSpacePage) in `pageStrip`, which clips to the sidebar
    ///
    ///
    /// either side of the shown one wait beside it, outside the strip, so a
    /// swipe only moves the strip. The themes of the pages either side of the
    ///
    /// window's background and the floating container's theme view
    ///
    private let spacePager = SidebarSpacePager()
    private let pageStrip = SidebarPageStripView()
    /// The Space a switch made elsewhere left, shown beside the strip and
    /// blended from while it slides in, even when it isn't the adjacent page.
    private var pagingSourceID: UUID?
    /// Set when the creation page closes, so its new Space doesn't slide in
    /// from the Space it was created from.
    private var creationEnded = false
    ///
    private let spaceCreationFeedback = SidebarSpaceCreationFeedbackView()
    private var spaceCreationGesture = SidebarSpaceCreationGesture()
    /// The themes either side of the strip's position and the progress
    /// between them, which the window's theme surfaces draw; nil at rest.
    var onPagingTheme: ((ThemePagingTransition?) -> Void)?
    /// The latest render's captures and share offers, for pages built between renders.
    private var renderedCaptures: [UUID: CaptureIndicatorPresentation] = [:]
    private var renderedShareable: Set<UUID> = []
    /// Counts the states renders show; a page checks itself once against each.
    private var stateGeneration = 0
    /// The page a swipe or slide shows beside the strip.
    private var revealedPageID: UUID?
    private func configureSpacePaging() {
        pageStrip.wantsLayer = true; pageStrip.layer?.masksToBounds = true
        spacePager.pages = { [weak self] in
            self?.spaces.map { SidebarSpacePager.Page(id: $0.id, profileID: $0.profileID) } ?? []
        }
        spacePager.selectedID = { [weak self] in self?.activeSpaceID }
        spacePager.pageWidth = { [weak self] in self?.bounds.width ?? 0 }
        spacePager.canBegin = { [weak self] in
            guard let self else { return false }
            return self.window != nil && self.isPresented && self.creationView == nil && !self.isEditingTitle
                && !self.contentSurface.isHidden && self.hierarchyState != nil
        }
        spacePager.canSelect = { [weak self] page in self?.canSelectSpace?(page.id, page.profileID) ?? false }
        spacePager.select = { [weak self] page in self?.onSelectSpace?(page.id, page.profileID) }
        spacePager.setOffset = { [weak self] offset in self?.showPageStrip(at: offset) }
        spacePager.trackingEnded = { [weak self] in
            guard let self, self.spaceCreationGesture.release(now: CACurrentMediaTime()) else { return }
            self.onNewSpace?()
        }
        //
        // takes a horizontal gesture over the sidebar before the list
        //
        // can't use, so they never reached the sidebar.
        let offer: (NSEvent) -> Bool = { [weak self] event in self?.spacePager.scrollWheel(event) ?? false }
        spacesHost.offerScroll = offer
        miniPlayers.offerScroll = offer
    }

    ///
    /// trailing edge in and fills its ring; filling or emptying it plays a
    /// haptic. Only a window that can create Spaces shows it.
    private func updateSpaceCreationFeedback(offset: CGFloat) {
        let index = spaces.firstIndex { $0.id == activeSpaceID }
        let overscroll = index.map {
            SidebarSpaceCreationGesture.overscroll(selected: $0, offset: offset, width: bounds.width, count: spaces.count)
        } ?? 0
        let shown = !isPrivateBrowsing && onNewSpace != nil
        let progress = shown ? SidebarSpaceCreationGesture.progress(overscroll) : 0
        spaceCreationFeedback.presentation = shown ? SidebarSpaceCreationGesture.presentation(overscroll) : 0
        spaceCreationFeedback.progress = progress
        if spaceCreationGesture.update(progress: progress, now: CACurrentMediaTime()) {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        spaceCreationFeedback.isActivated = spaceCreationGesture.isActivated
    }

    private func showPageStrip(at offset: CGFloat) {
        let width = bounds.width
        updateSpaceCreationFeedback(offset: offset)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        pageStrip.layer?.sublayerTransform = CATransform3DMakeTranslation(offset, 0, 0)
        CATransaction.commit()
        let index = spaces.firstIndex { $0.id == activeSpaceID }
        if spacePager.isTracking { pagingSourceID = nil }
        let source = pagingSourceID.flatMap { id in spaces.firstIndex { $0.id == id } }
        let neighborIndex = source ?? index.map { offset < 0 ? $0 + 1 : $0 - 1 }
        guard offset != 0, width > 0, let index, let neighborIndex, spaces.indices.contains(neighborIndex),
              hierarchyState != nil,
              let pages = SidebarSpacePagingModel.themePages(selected: index, offset: offset, width: width, count: spaces.count) else {
            pagingSourceID = nil
            // A page the strip revealed but didn't land on lets go of the pointer.
            if let revealed = revealedPageID, revealed != activeSpaceID { self.pages[revealed]?.resetPointer() }
            revealedPageID = nil
            placePages(side: nil)
            onPagingTheme?(nil)
            return
        }
        if let revealed = revealedPageID, revealed != spaces[neighborIndex].id { self.pages[revealed]?.resetPointer() }
        revealedPageID = spaces[neighborIndex].id
        placePages(side: (spaces[neighborIndex].id, offset < 0 ? 1 : -1))
        if let source {
            // The source sits on the side the strip slides in from.
            let fraction = min(1, max(0, abs(offset) / width))
            onPagingTheme?(offset > 0
                ? ThemePagingTransition(from: spaces[source].theme, theme: spaces[index].theme, progress: 1 - fraction)
                : ThemePagingTransition(from: spaces[index].theme, theme: spaces[source].theme, progress: fraction))
        } else {
            onPagingTheme?(ThemePagingTransition(from: spaces[pages.left].theme, theme: spaces[pages.left + 1].theme,
                                                 progress: pages.progress))
        }
    }

    /// Places the pages beside the shown one, outside the strip's bounds:
    /// `side`'s page, which a swipe or slide reveals, on its side (built now
    /// if it isn't yet), and the built pages of the Spaces either side.
    /// Every other page is hidden.
    private func placePages(side: (id: UUID, direction: Int)?) {
        guard !isSpaceManagement, let state = hierarchyState else { return }
        var beside: [UUID: Int] = [:]
        if let index = spaces.firstIndex(where: { $0.id == activeSpaceID }) {
            for direction in [-1, 1] where spaces.indices.contains(index + direction) { beside[spaces[index + direction].id] = direction }
        }
        if let side {
            for (id, direction) in beside where direction == side.direction { beside[id] = nil }
            beside[side.id] = side.direction
            if pages[side.id] == nil, spaces.contains(where: { $0.id == side.id }) { keep(side.id, page: makePage()) }
        }
        for (id, page) in pages where page !== shownPage {
            guard let direction = beside[id], id == side?.id || page.key != nil else {
                let away = NSRect(x: 3 * bounds.width, y: 0, width: bounds.width, height: bounds.height)
                if page.view.frame != away { page.view.frame = away }
                continue
            }
            if id == side?.id, page.checkedGeneration != stateGeneration || page.pendingBuild != nil { refresh(page, spaceID: id, state: state) }
            let frame = NSRect(x: CGFloat(direction) * bounds.width, y: 0, width: bounds.width, height: bounds.height)
            if page.view.frame != frame { page.view.frame = frame }
            if !page.laidOut || !isFramed(page) { layoutPage(page) }
            // The page coming into view has every row it shows.
            if id == side?.id, page.list.hasUnbuiltRows {
                page.list.prepareRows(budget: .max)
                page.list.layoutSubtreeIfNeeded()
                page.laidOut = true
            }
        }
    }

    /// The state `id`'s page shows: this one with that Space active and its
    /// own remembered selection, as selecting the Space restores it.
    private func pageState(_ id: UUID, from state: BrowserState) -> BrowserState {
        guard id != state.activeSpaceID else { return state }
        var next = state
        next.activeSpaceID = id
        next.selectedTabIDs = state.selectionBySpace[id.uuidString] ?? []
        return next
    }

    /// Brings a page that isn't shown up to `state`: its rows take live title
    /// and address changes in place, and a changed Space rebuilds it, until
    /// `deadline` if there is one. Answers whether the page is up to date.
    @discardableResult
    private func refresh(_ page: SidebarSpacePage, spaceID: UUID, state: BrowserState, until deadline: CFTimeInterval? = nil) -> Bool {
        let shown = pageState(spaceID, from: state)
        let focused = shown.selectedTabIDs.first
        let key = pageKey(shown, focused: focused, placeholder: false)
        if page.key == key, page.pendingBuild == nil {
            page.checkedGeneration = stateGeneration
            patchLive(page, state: shown, focusedTabID: focused)
        } else {
            if page.pendingBuild?.key != key {
                page.pendingBuild = (key, startBuild(page, state: shown, focusedTabID: focused, placeholder: false, key: key))
                // Starting a build ahead takes a share of its own.
                if let deadline, CACurrentMediaTime() >= deadline { return false }
            }
            guard page.pendingBuild?.run(deadline) ?? true else { return false }
            patchLive(page, state: shown, focusedTabID: focused)
        }
        applyPagePalette(page, paletteForPage(spaceID))
        return true
    }

    /// A page beside the shown one takes its own Space's palette, from the
    /// window's appearance rather than the shown Space's contrasting one.
    private func paletteForPage(_ spaceID: UUID) -> ThemeChromePalette? {
        guard let space = spaces.first(where: { $0.id == spaceID }) else { return palette }
        return ThemeChromePalette(theme: space.theme, appearance: window?.effectiveAppearance ?? effectiveAppearance)
    }

    /// Keeps `page` as `id`'s and lets go of the pages farthest from the
    ///
    /// reversed; the shown page and those beside it stay. A page holds views
    /// only for the rows near its visible area, so the cap needs no row budget.
    private func keep(_ id: UUID, page: SidebarSpacePage) {
        page.spaceID = id
        pages[id] = page
        pageOrder.removeAll { $0 == id }
        pageOrder.append(id)
        let pinned = pinnedPages
        let index = spaces.firstIndex { $0.id == activeSpaceID } ?? 0
        let distance: (UUID) -> Int = { [spaces] id in spaces.firstIndex { $0.id == id }.map { abs($0 - index) } ?? .max }
        let farthest = pageOrder.filter { !pinned.contains($0) && $0 != id }.sorted { distance($0) > distance($1) }
        for old in farthest.prefix(max(0, pages.count - (Self.keptPages + pinned.count))) { retirePage(old) }
    }
    /// The shown Space and the Spaces either side.
    /// The shown Space, the Spaces either side and the Space a slide comes from.
    private var pinnedPages: Set<UUID> {
        let source = Set(pagingSourceID.map { [$0] } ?? [])
        guard let index = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return source.union(activeSpaceID.map { [$0] } ?? []) }
        return source.union([index - 1, index, index + 1].filter(spaces.indices.contains).map { spaces[$0].id })
    }
    /// Lets go of `id`'s page: it leaves view now and its rows leave the
    /// window a few at a time while idle.
    private func retirePage(_ id: UUID) {
        guard let page = pages[id], page !== shownPage else { return }
        pages.removeValue(forKey: id)
        pageOrder.removeAll { $0 == id }
        page.view.frame.origin.x = 3 * bounds.width
        page.pendingBuild = nil
        retiredLists.append(page.list)
        retiredPageViews.append(page.view)
        scheduleNeighborPreparation()
    }
    private var retiredPageViews: [NSView] = []
    /// Lets go of the pages of Spaces that no longer exist.
    private func retirePages(notIn spaces: [BrowserSpace]) {
        for id in pages.keys where !spaces.contains(where: { $0.id == id }) && pages[id] !== shownPage { retirePage(id) }
    }

    /// Under memory pressure the off-screen pages go, except the ones beside
    ///
    private var memoryPressure: DispatchSourceMemoryPressure?
    /// Watches memory pressure while the sidebar is in a window.
    private func watchMemoryPressure(_ watching: Bool) {
        guard watching != (memoryPressure != nil) else { return }
        guard watching else { memoryPressure?.cancel(); memoryPressure = nil; return }
        // A new source reports only changes from here on.
        underMemoryPressure = false
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            MainActor.assumeIsolated {
                guard let self, let source else { return }
                if source.data.contains(.normal) { self.memoryPressureEnded() } else { self.releaseOffscreenPages() }
            }
        }
        source.activate()
        memoryPressure = source
    }
    private var underMemoryPressure = false
    func releaseOffscreenPages() {
        underMemoryPressure = true
        let pinned = pinnedPages
        for id in pageOrder where !pinned.contains(id) { retirePage(id) }
        if hierarchyState != nil { prepareNeighborPages() }
    }
    private func memoryPressureEnded() {
        guard underMemoryPressure else { return }
        underMemoryPressure = false
        if isPresented && !isSpaceManagement && hierarchyState != nil { prepareNeighborPages() }
    }

    ///
    /// While this sidebar is idle it prepares, a few milliseconds per turn,
    /// every Space's page up to the ten it keeps, the Spaces either side
    /// first and then the nearest: the page, then the views of the rows near
    /// its visible area a few at a time, then their layout. A swipe, a click
    /// on a Space or a shortcut to one then only shows a page.
    private enum PreparationStep {
        /// Builds the page, then its rows' views and layout a few at a time.
        case page(UUID)
        case layout(UUID, Int)
    }
    private var neighborPreparation: Timer?
    private var pendingPreparation: [PreparationStep] = []
    /// One turn's share, well inside a 120 Hz frame.
    private static let preparationSlice: CFTimeInterval = 0.003
    /// Rows that join or leave the window in one turn. The window's layout
    /// engine takes them after the turn, about half a millisecond each on
    /// top of the half a millisecond a tab row takes to build.
    private static let rowsPerTurn = 5
    /// Preparation waits for this long after Parc's own keyboard, pointer or trackpad input.
    private static let preparationQuiet: CFTimeInterval = 0.3
    private func scheduleNeighborPreparation(after delay: TimeInterval = 0.25) {
        neighborPreparation?.invalidate(); neighborPreparation = nil
        guard window != nil, !pendingPreparation.isEmpty || !retiredLists.isEmpty || !retiredPageViews.isEmpty else { return }
        let timer = Timer(timeInterval: max(delay, Self.preparationQuiet - SidebarInputClock.secondsSinceInput), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.prepareNeighborPage() }
        }
        // Not in event tracking: a drag or a menu waits for it.
        RunLoop.main.add(timer, forMode: .default)
        neighborPreparation = timer
    }
    /// Input arrived recently: preparation steps aside.
    private var inputRecent: Bool { SidebarInputClock.secondsSinceInput < Self.preparationQuiet }
    private func prepareNeighborPage() {
        neighborPreparation = nil
        guard window != nil else { pendingPreparation = []; return }
        let canBuild = isPresented && !isSpaceManagement && creationView == nil && !contentSurface.isHidden && hierarchyState != nil
        // A waiting event is peeked once: the peek runs the run loop.
        guard !spacePager.isTracking, !spacePager.isAnimating, !inputRecent,
              NSApp.nextEvent(matching: .any, until: nil, inMode: .default, dequeue: false) == nil else {
            scheduleNeighborPreparation(); return
        }
        let deadline = CACurrentMediaTime() + Self.preparationSlice
        // Let-go pages leave the window first.
        if !retireLists(until: deadline) { scheduleNeighborPreparation(after: 0.008); return }
        var built = 0
        turn: while CACurrentMediaTime() < deadline, !inputRecent, let step = pendingPreparation.first {
            // Rows built this turn join the layout engine after it; the next
            // page's build waits for a turn of its own.
            if built > 0, case .page = step { break }
            switch step {
            case .page(let id):
                guard canBuild, let state = hierarchyState else { return }
                guard state.spaces.contains(where: { $0.id == id }) else { pendingPreparation.removeFirst(); continue }
                let page = pages[id] ?? { let page = makePage(); keep(id, page: page); return page }()
                guard page !== shownPage else { pendingPreparation.removeFirst(); continue }
                if page.checkedGeneration != stateGeneration || page.pendingBuild != nil {
                    guard refresh(page, spaceID: id, state: state, until: deadline) else { continue }
                }
                pendingPreparation.removeFirst()
                guard !page.laidOut || !isFramed(page) else { continue }
                if page.view.frame.size != bounds.size { page.view.frame = NSRect(origin: page.view.frame.origin, size: bounds.size) }
                layoutPage(page, flush: false)
                pendingPreparation.insert(.layout(id, 0), at: 0)
            case .layout(let id, let from):
                guard canBuild else { return }
                guard let page = pages[id], page !== shownPage else { pendingPreparation.removeFirst(); continue }
                // The views a turn builds join the window's layout engine after it.
                let before = page.list.builtViews
                let ready = page.list.prepareRows(budget: Self.rowsPerTurn - built)
                built += page.list.builtViews - before
                guard ready else { break turn }
                if let next = layoutRows(page, from: from, until: deadline) {
                    pendingPreparation[0] = .layout(id, next)
                } else { pendingPreparation.removeFirst() }
            }
        }
        // A gap between turns keeps frames and typing free.
        scheduleNeighborPreparation(after: 0.008)
    }
    /// Queues every Space's page the sidebar doesn't hold up to date, the
    /// Spaces either side first, then the nearest, up to the ten it keeps;
    /// after memory pressure only the pages beside the shown one.
    private func prepareNeighborPages() {
        retirePages(notIn: spaces)
        guard let index = spaces.firstIndex(where: { $0.id == activeSpaceID }), spaces.count > 1, !isSpaceManagement else {
            pendingPreparation = []; scheduleNeighborPreparation(); return
        }
        let pinned = pinnedPages
        let byDistance = spaces.indices.filter { $0 != index }
            .sorted { abs($0 - index) != abs($1 - index) ? abs($0 - index) < abs($1 - index) : $0 > $1 }
            .prefix(Self.keptPages).map { spaces[$0].id }
            .filter { pinned.contains($0) || !underMemoryPressure }
        pendingPreparation = byDistance.flatMap { id -> [PreparationStep] in
            guard let page = pages[id], page.key != nil else { return [.page(id)] }
            return page.checkedGeneration == stateGeneration && page.laidOut && page.pendingBuild == nil ? [] : [.page(id)]
        }
        scheduleNeighborPreparation()
    }
    /// Takes let-go outlines apart a row at a time, so each row leaves the
    /// window and is freed in its own share of a turn; true once none are left.
    private func retireLists(until deadline: CFTimeInterval) -> Bool {
        var removed = 0
        while let retired = retiredLists.last, CACurrentMediaTime() < deadline, removed < Self.rowsPerTurn {
            if retired.removeLastRow() { removed += 1 } else { retiredLists.removeLast() }
        }
        guard retiredLists.isEmpty else { return false }
        for view in retiredPageViews { view.removeFromSuperview() }
        retiredPageViews.removeAll()
        return true
    }
    /// Lays out a page's rows from `index` until `deadline`; nil once all are.
    private func layoutRows(_ page: SidebarSpacePage, from index: Int, until deadline: CFTimeInterval) -> Int? {
        // The outline places its rows first; then each row lays out its own views.
        if index == 0, page.list.needsLayout { page.list.layout() }
        let rows = page.list.subviews
        var next = index
        while next < rows.count, CACurrentMediaTime() < deadline {
            let row = rows[next]; next += 1
            guard row.needsLayout || row.subviews.contains(where: { $0.needsLayout || $0.subviews.contains(where: \.needsLayout) }) else { continue }
            row.layoutSubtreeIfNeeded()
        }
        guard next >= rows.count else { return next }
        page.laidOut = true
        return nil
    }

    /// Horizontal scrolls the tablist does not use (its horizontal elasticity
    ///
    ///
    override func scrollWheel(with event: NSEvent) {
        if !spacePager.scrollWheel(event) { super.scrollWheel(with: event) }
    }

    ///
    override func swipe(with event: NSEvent) {
        if !spacePager.swipe(event) { super.swipe(with: event) }
    }

    ///
    /// events, mouse button 4 navigates Back and button 5 Forward through the
    /// window's ordinary navigation action. Rows and controls pass these
    /// buttons up to the sidebar.
    override func otherMouseUp(with event: NSEvent) {
        let kind: NavigationControlKind? = event.buttonNumber == 3 ? .back : event.buttonNumber == 4 ? .forward : nil
        guard let kind, window != nil, isPresented else { super.otherMouseUp(with: event); return }
        onNavigation?(kind)?.activate(false)
    }

    var isPaymentEntryVisible: Bool {
        // An off-screen hidden sidebar is unhidden and its visibleRect is not
        // empty (sidebar-accessibility.md), so only a presented one counts.
        guard isPresented, let window = paymentAction.window else { return false }
        return window.isVisible && !window.isMiniaturized &&
            !paymentAction.isHiddenOrHasHiddenAncestor && !paymentAction.visibleRect.isEmpty
    }

    /// - Returns: `true` when a visible field changed and layout is required.
    @discardableResult
    func updatePaymentEntry(title: String?, symbol: String, enabled: Bool, savedLabel: String) -> Bool {
        guard title != paymentEntryTitle || symbol != paymentEntrySymbol
                || enabled != paymentEntryEnabled || savedLabel != paymentEntrySavedLabel else {
            return false
        }
        paymentEntryTitle = title
        paymentEntrySymbol = symbol
        paymentEntryEnabled = enabled
        paymentEntrySavedLabel = savedLabel
        paymentAction.isHidden = title == nil
        paymentAction.isEnabled = enabled
        paymentAction.title = savedLabel
        if let tooltip = savedLabel.isEmpty ? title : savedLabel {
            LiveShortcutToolTip.set(paymentAction, tooltip)
        } else {
            paymentAction.parcTooltip = nil
        }
        paymentAction.setAccessibilityLabel(savedLabel.isEmpty ? title : savedLabel)
        paymentAction.imagePosition = savedLabel.isEmpty ? .imageOnly : .imageLeading
        paymentAction.image = NSImage(systemSymbolName: savedLabel.isEmpty ? symbol : "checkmark.circle.fill", accessibilityDescription: nil)
        paymentWidth = title == nil ? 0 : (savedLabel.isEmpty ? 28 : min(122, max(70, paymentAction.intrinsicContentSize.width + 8)))
        needsLayout = true
        return true
    }

    func setFloating(_ floating: Bool) {
        //
        // its tooltip). Which state picks Hide is unrecovered: locked → Hide
        // rests on the 1.170 locked observation; floating → Lock, and hidden →
        //
        // container), are inferred.
        if sidebarFloating != floating { sidebarFloating = floating; updateAddressButtonsReveal() }
        let label = floating ? SidebarAccessibility.lockSidebar : SidebarAccessibility.hideSidebar
        // BrowserNavigationButtonState's toggle carries Show/Hide Sidebar's live
        //
        LiveShortcutToolTip.set(toggle, label, commandID: "toggleSidebar:")
        SidebarAccessibility.label(toggle, label)
    }
    ///
    /// exiting it (WindowFullscreenPhase); the window controller sets this
    /// before any ⌘S group, which carries the lights as sidebar content.
    var showsWindowButtons = true {
        didSet { if showsWindowButtons != oldValue { needsLayout = true } }
    }
    ///
    ///
    /// leaves in the accessibility tree [C], so no hide or unhide reaches the
    /// header lights and the dock: they drop and re-test the pointer here.
    /// Parc's adaptation: Tab passes the hidden chain (linkKeyViews).
    var isPresented = true {
        didSet {
            guard isPresented != oldValue else { return }
            if !isPresented { spacePager.cancel() }
            archiveEducationHost.setInteractionAllowed(isPresented && creationView == nil)
            updateCompleteHost.setInteractionAllowed(isPresented && creationView == nil)
            updateReadyHost.setInteractionAllowed(isPresented && creationView == nil)
            retestPointer(); setNeedsKeyViewLinking()
            // Bypassed at once, not at the next layout, so no Tab enters the
            // settled hidden sidebar in between.
            if !isPresented { keyViewsNeedLinking = false; linkKeyViews() }
        }
    }
    /// Drops the lights' and the dock's hover, or re-tests it where the
    /// presented sidebar now lies.
    func retestPointer() {
        windowButtons.setPresented(isPresented); spacesHost.setPresented(isPresented)
        retestPointerInSidebar()
    }
    ///
    /// Forward and Reload, then the address and the list. The header controls
    /// stay above `contentSurface` for drawing and hit testing.
    override func accessibilityChildren() -> [Any]? {
        super.accessibilityChildren().map { SidebarAccessibility.headerFirst($0, header: [windowButtons] + headerControls) }
    }
    /// While the sidebar is the list's keyboard stop, the outline it stands for
    /// is the focused element.
    override var accessibilityFocusedUIElement: Any? {
        list.isAccessibilityFocused() ? list : super.accessibilityFocusedUIElement
    }
    /// The visible toggle and navigation buttons in their laid-out order: below
    ///
    /// (SidebarChromeLayout.toolbar), so the order follows the frames.
    private var headerControls: [NSView] {
        SidebarAccessibility.laidOut([toggle, back, forward, reload, reloadOptions])
    }


    ///
    /// `isInDeveloperMode`); `forceReload` its stored reload default. Nil
    /// keeps the last owner-supplied values (title-edit refreshes).
    func updateNavigation(canBack: Bool, canForward: Bool, loading: Bool, enabled: Bool,
                          developerReload: Bool? = nil, forceReload: Bool? = nil) {
        back.isEnabled = canBack; forward.isEnabled = canForward
        let developerReload = developerReload ?? self.developerReload
        if let forceReload { developerForceReload = forceReload }
        let force = developerReload && developerForceReload
        let idleLabel = force ? "Force Refresh the Page" : SidebarAccessibility.reload
        reload.setLoading(loading, enabled: enabled, idleLabel: idleLabel, forceReload: force)
        SidebarAccessibility.label(reload, loading ? "Stop Loading" : idleLabel)
        reloadOptions.isEnabled = enabled
        if developerReload != self.developerReload {
            self.developerReload = developerReload
            needsLayout = true
        }
    }

    /// A plain tab-to-tab switch changes only the two rows' fills
    /// (`SidebarRowAppearance.current`), so it updates them in place instead
    /// of rebuilding every row, which made each switch cost tens of ms.
    /// Favorites, split groups, multi-selection, the new-tab placeholder and
    /// rows not in the list still rebuild. Only `render` asks for this: the
    /// window's metadata refresh still falls back to its full render, which
    /// attaches the newly selected page.
    private func canApplySelectionOnly(state: BrowserState, previous: BrowserState, focusedTabID: UUID?) -> Bool {
        var reselected = previous
        reselected.selectedTabIDs = state.selectedTabIDs
        reselected.selectionBySpace = state.selectionBySpace
        guard !renderedNewTabPlaceholder, state.preservesSidebarOutline(relativeTo: reselected),
              state.selectedTabIDs.count <= 1, previous.selectedTabIDs.count <= 1 else { return false }
        let involved = Set(state.selectedTabIDs + previous.selectedTabIDs + [focusedTabID, latestFocusedTabID].compactMap { $0 })
        let splitGroups = SidebarSplitItems.groups(in: state, spaceID: state.activeSpaceID)
        return involved.allSatisfy { id in
            state.tabs.first(where: { $0.id == id })?.kind != .favorite
                && !splitGroups.contains(where: { $0.tabIDs.contains(id) })
                && shownPage.contains(.tab(id))
        }
    }
    private func applySelection(state: BrowserState, focusedTabID: UUID?) {
        for row in tabRows where !row.compactSplitChild {
            let current = state.selectedTabIDs.contains(row.tabID)
            if row.selected != current { row.selected = current }
        }
        let activeItem = (focusedTabID ?? state.selectedTabIDs.first).map { SidebarItemReference.tab($0) }
        if activeItem != selectionActive { itemSelection.clear() }
        selectionActive = activeItem
        // The new active row is already in view, so no folder needs to peek it.
        peekedActiveItem = activeItem
        refreshItemSelection()
    }

    /// Title/URL/loading/favicon ticks update existing cells. Do not rebuild
    ///
    /// its instance and applies TabCellState in place.
    /// Returns false when the existing cells cannot present the change.
    @discardableResult
    func applyLivePageMetadata(state: BrowserState, focusedTabID: UUID?, loading: Set<UUID>, canBack: Bool, canForward: Bool, captures: [UUID: CaptureIndicatorPresentation] = [:],
                               shareable: Set<UUID> = [], audio: [UUID: SidebarTabAudio] = [:],
                               applyShareableAudio: Bool = true, allowSelectionChange: Bool = false) -> Bool {
        guard let previous = hierarchyState else {
            render(state: state, focusedTabID: focusedTabID, loading: loading, canBack: canBack, canForward: canForward,
                   captures: captures, shareable: shareable, audio: audio)
            return true
        }
        // Identical chrome ticks keep the last applied shareable/audio maps;
        // only real membership or audible/mute flips republish them.
        if applyShareableAudio { tabAudio = audio }
        if let edit = titleEdit {
            let current = state.tabs.first { $0.id == edit.tab.id }
            let sameGroup = state.splitLayouts.first { $0.tabIDs.contains(edit.tab.id) }
                == previous.splitLayouts.first { $0.tabIDs.contains(edit.tab.id) }
            if state.activeSpaceID == activeSpaceID, state.selectedTabIDs == edit.selected,
               focusedTabID == edit.focused, let current,
               SidebarTabTitle.sameItemForEditing(current, edit.tab), sameGroup {
                updateNavigation(canBack: canBack, canForward: canForward,
                    loading: focusedTabID.map { loading.contains($0) } ?? false, enabled: true)
                // Preserve the field editor, but still hand off shareable/audio
                // so a mute/shareable flip during rename is not absorbed.
                if applyShareableAudio {
                    renderedShareable = shareable
                    for row in tabRows {
                        row.shareable = shareable.contains(row.tabID)
                        row.audio = tabAudio[row.tabID]
                    }
                }
                return true
            }
            return false
        }
        if let edit = folderTitleEdit {
            // The cached row keeps its field editor across this render while
            // its folder keeps the name and Space the edit began with.
            let current = state.folders.first { $0.id == edit.folder.id }
            if state.activeSpaceID != activeSpaceID || current?.name != edit.folder.name || current?.spaceID != edit.folder.spaceID
                || current?.parentID != edit.folder.parentID {
                folderTitleEdit = nil; edit.row.cancelTitleEditing()
            }
        }
        if let edit = splitTitleEdit {
            if state.activeSpaceID == activeSpaceID, state.selectedTabIDs == edit.selected,
               focusedTabID == edit.focused, edit.target.matches(state) {
                updateNavigation(canBack: canBack, canForward: canForward,
                    loading: focusedTabID.map { loading.contains($0) } ?? false, enabled: true)
                if applyShareableAudio {
                    renderedShareable = shareable
                    for row in tabRows {
                        row.shareable = shareable.contains(row.tabID)
                        row.audio = tabAudio[row.tabID]
                    }
                }
                return true
            }
            return false
        }
        // Row selection/Favorite highlight and outline membership are fixed at
        // `render`. Refuse when focus, selection, folder expansion or sidebar
        // chrome structure moved — callers reconstruct — except a plain
        // tab-to-tab switch that `render` itself allows. Title/URL/customTitle,
        // loading and download ticks remain allowed on matching membership.
        if newTabPlaceholderActive != renderedNewTabPlaceholder || outlineInvalidated { return false }
        let selectionChanged = focusedTabID != latestFocusedTabID || !state.preservesSidebarOutline(relativeTo: previous)
        if selectionChanged,
           !allowSelectionChange || !canApplySelectionOnly(state: state, previous: previous, focusedTabID: focusedTabID) {
            return false
        }
        let visible = state.tabs.filter { $0.archivedAt == nil }
        let splitGroups = SidebarSplitItems.groups(in: state, spaceID: state.activeSpaceID)
        // A custom-named split cell shows its tabs' captures, and a speaker
        // joins or leaves a row only in a rebuild: both are part of the page.
        for group in splitGroups where SidebarSplitCellLayout.usesCustomInfo(
            title: group.customTitle, hasIcon: group.customIcon != nil, editing: false) {
            for id in group.tabIDs where renderedCaptures[id] != captures[id] { return false }
        }
        let effectiveAudio = applyShareableAudio ? audio : tabAudio
        var speakers = Set<UUID>()
        for tab in state.tabs where tab.spaceID == state.activeSpaceID {
            if let next = effectiveAudio[tab.id], next.audible || next.muted { speakers.insert(tab.id) }
        }
        if let built = shownPage.key, built.speakers != speakers { return false }
        if selectionChanged { applySelection(state: state, focusedTabID: focusedTabID) }
        latestFocusedTabID = focusedTabID
        hierarchyState = state
        // Rows built later show these too.
        renderedCaptures = captures
        if applyShareableAudio { renderedShareable = shareable }
        stateGeneration += 1
        shownPage.renderedState = state; shownPage.checkedGeneration = stateGeneration
        if selectionChanged { shownPage.key?.selected = state.selectedTabIDs; shownPage.key?.focused = focusedTabID }
        updateNavigation(canBack: canBack, canForward: canForward,
            loading: focusedTabID.map { loading.contains($0) } ?? false, enabled: true)
        let address = Self.address(of: state.tabs.first { $0.id == (focusedTabID ?? state.selectedTabIDs.first) })
        if addressText != address { setAddressTitle(address) }
        for row in tabRows {
            guard let tab = visible.first(where: { $0.id == row.tabID }) else { continue }
            let urlChanged = row.applyLivePage(tab)
            let inGroup = splitGroups.contains { $0.tabIDs.contains(tab.id) }
            bindLiveRow(row, tab: tab, inGroup: inGroup)
            row.capture = captures[tab.id]
            if applyShareableAudio {
                row.shareable = shareable.contains(tab.id)
                row.audio = tabAudio[tab.id]
            }
            if urlChanged {
                refreshPreviewAction(row, tab: tab)
                tabFaviconArms[tab.id] = TabRowFaviconIdentity(
                    pageURL: tab.url, resetDestination: tab.resetDestination)
                row.loadFavicon { [weak self, weak row] completion in
                    self?.requestTabFavicon?(tab) { [weak self, weak row] image in
                        guard let self, let row, self.tabRows.contains(where: { $0 === row }) else { return }
                        completion(image)
                    }
                }
                row.loadResetIcon { [weak self, weak row] completion in
                    self?.requestSavedFavicon?(tab) { [weak self, weak row] image in
                        guard let self, let row, self.tabRows.contains(where: { $0 === row }) else { return }
                        completion(image)
                    }
                }
            }
        }
        for (id, button) in favoriteTiles {
            guard let tab = visible.first(where: { $0.id == id }) else { continue }
            let group = splitGroups.first { $0.sidebarAnchorID == tab.id || $0.tabIDs.contains(tab.id) }
            let spokenTitle = FavoriteAccessibilityTitle.text(group.map { split in
                split.customTitle.map { [$0] } ?? split.tabIDs.compactMap { id in visible.first { $0.id == id }.map(SidebarTabTitle.display) }
            } ?? [SidebarTabTitle.display(tab)])
            func monogram(_ page: BrowserTab) -> String {
                let host = URL(string: page.url)?.host?.replacingOccurrences(of: "www.", with: "") ?? "New tab"
                return String(host.prefix(1)).uppercased()
            }
            let pages = group.map { $0.tabIDs.compactMap { id in visible.first { $0.id == id } } } ?? [tab]
            let previousPages = group.map { $0.tabIDs.compactMap { id in previous.tabs.first { $0.id == id } } }
                ?? previous.tabs.first { $0.id == id }.map { [$0] } ?? []
            let urlsChanged = !pages.elementsEqual(previousPages) { $0.url == $1.url }
            button.update(title: spokenTitle, monogram: monogram(tab), url: WhatsNewPage.presented(tab.url),
                owner: .init(tabID: tab.id, profileID: tab.profileID,
                             spaceID: state.activeSpaceID, createdAt: tab.createdAt))
            let item: SidebarItemReference = group.map { .split($0.id) } ?? .tab(tab.id)
            bindFavoriteTile(button, tab: tab, group: group, item: item, state: state)
            if let icon = group?.customIcon {
                button.setCustomGlyph(image: icon.image, text: icon.emoji)
                favoriteFaviconArms.removeValue(forKey: id)
            } else {
                let orientation = group?.orientation ?? .horizontal
                let arm = FavoriteFaviconIdentity(pageURLs: pages.map(\.url), orientation: orientation)
                button.setPages(pages.map(monogram), orientation: orientation)
                let skipArm = !urlsChanged
                    && favoriteFaviconArms[id] == arm
                    && button.hasSettledPageFavicons(count: pages.count)
                if !skipArm {
                    favoriteFaviconArms[id] = arm
                    for (index, page) in pages.enumerated() {
                        button.loadFavicon(page: index) { [weak self, weak button] completion in
                            self?.requestTabFavicon?(page) { [weak self, weak button] image in
                                guard let self, let button, self.favoriteTiles[id] === button else { return }
                                completion(image)
                            }
                        }
                    }
                }
            }
        }
        return true
    }

    /// Rebind row actions to the live `BrowserTab`. Title/URL ticks must not
    /// leave Close/Mute/Select holding a snapshot `Equatable` no longer finds.
    private func bindLiveRow(_ row: SidebarTabRow, tab: BrowserTab, inGroup: Bool) {
        row.bindLiveActions(
            tab: tab,
            close: { [weak self] in self?.prepareTabClose?(tab) },
            reset: { [weak self] in inGroup ? nil : self?.prepareIconReset?(tab, false) },
            separate: { [weak self] in inGroup ? nil : self?.prepareIconReset?(tab, true) })
        row.prepareMute = { [weak self] in
            guard let self, let audio = self.tabAudio[tab.id] else { return nil }
            return self.prepareTabMute?(tab, audio)
        }
        row.prepareActivation = { [weak self] in
            guard let self, let action = self.prepareTabActivation?(tab) else { return nil }
            return { [weak self] in
                guard action() else { return false }
                self?.clearItemSelection(); return true
            }
        }
        if !inGroup {
            let selectionItem = SidebarItemReference.tab(tab.id)
            row.context = { [weak self] in
                guard let self else { return NSMenu() }
                if self.isSpaceManagement { return self.managementItemMenu?(selectionItem) ?? NSMenu() }
                return self.selectedItemsMenu(for: selectionItem) ?? self.tabMenu(tab)
            }
        }
        row.makeAccessibilityActions = { [weak self] in
            self?.isSpaceManagement == true ? [] : self?.tabAccessibilityActions(tab) ?? []
        }
        //
        row.beginRename = inGroup || isSpaceManagement || !SidebarTabTitle.isRenameable(tab) ? nil : { [weak self] in
            self?.beginTitleEditing(tab) == true
        }
    }

    private func bindFavoriteTile(_ button: FavoriteTile, tab: BrowserTab, group: BrowserSplitLayout?,
                                  item: SidebarItemReference, state: BrowserState) {
        button.preparePointerAction = { [weak self] intent in
            guard let self, let action = self.prepareFavoritePointerAction?(tab, intent) else { return nil }
            return { [weak self] in
                guard action() else { return false }
                self?.clearItemSelection(); return true
            }
        }
        button.beginMove = { [weak self] in self?.prepareSidebarMove?(item) }
        button.canActivate = { [weak self] in self?.prepareFavoriteActivation?(tab) != nil }
        button.activate = { [weak self] in
            guard let self, let action = self.prepareFavoriteActivation?(tab) else { return false }
            self.clearItemSelection(); return action()
        }
        button.makeMenu = { [weak self, weak button] in
            guard let self, self.currentFavorite(tab) != nil else { return nil }
            let menu = self.tabMenu(tab)
            // A Favorite has no row badge; its capture's Stop controls live here.
            if self.captureIsActive?(tab.id) == true {
                menu.insertItem(.separator(), at: 0)
                menu.insertItem(MenuAction.item("Camera, Microphone and Sharing…") { [weak self, weak button] in
                    guard let self, let button else { return }
                    self.onCaptureMenu?(tab.id, button)
                }, at: 0)
            }
            return menu
        }
        button.makeAccessibilityActions = { [weak self] in
            guard let self, self.currentFavorite(tab) != nil else { return [] }
            var actions: [NSAccessibilityCustomAction] = []
            if let group, let target = SidebarSplitTitleEdit(group: group, profileID: tab.profileID, state: state) {
                if let rename = self.prepareFavoriteSplitRename?(target) { actions.append(.init(name: "Rename Split View", handler: rename)) }
                actions += self.splitAppearanceActions(target)
            } else if let rename = self.prepareFavoriteRename?(tab) {
                actions.append(NSAccessibilityCustomAction(name: "Rename Tab", handler: rename))
            }
            if let url = URL(string: tab.url), SidebarRecentDomain.matching(url) != nil,
               SidebarPreviewPreference.recentPages.isEnabled {
                actions.append(NSAccessibilityCustomAction(name: "Preview recent pages") { [weak self] in
                    guard let self, self.currentFavorite(tab) != nil else { return false }
                    self.onPreview?(.tab(tab.id)); return true
                })
            }
            if let audio = self.tabAudio[tab.id], let mute = self.prepareTabMute?(tab, audio) {
                actions.append(NSAccessibilityCustomAction(name: audio.muted ? "Unmute" : "Mute", handler: mute))
            }
            if let reset = self.prepareResetTab?(tab) {
                actions.append(NSAccessibilityCustomAction(name: "Reset Tab to Original URL", handler: reset))
            }
            if let close = self.prepareFavoriteClose?(tab) {
                actions.append(NSAccessibilityCustomAction(name: "Close Tab", handler: close))
            }
            actions += self.moveAccessibilityActions(item: item)
            return actions
        }
    }

    func reloadFavicon(for id: UUID) {
        // A kept page off screen holds its rows too; a page being built re-arms.
        tabFaviconArms.removeValue(forKey: id)
        if let tab = hierarchyState?.tabs.first(where: { $0.id == id }) {
            for page in pages.values {
                page.releasedFavicons.removeValue(forKey: id)
                guard let row = page.tabRow(id) else { continue }
                row.loadFavicon { [weak self, weak row, weak page] completion in
                    self?.requestTabFavicon?(tab) { [weak row, weak page] image in
                        guard let row, page?.holds(row) == true else { return }
                        completion(image)
                    }
                }
            }
        }
        let visible = hierarchyState?.tabs.filter { $0.archivedAt == nil } ?? []
        let groups = hierarchyState.map { SidebarSplitItems.groups(in: $0, spaceID: $0.activeSpaceID) } ?? []
        for (tileID, button) in favoriteTiles {
            let group = groups.first { $0.sidebarAnchorID == tileID || $0.tabIDs.contains(tileID) }
            if let group, let index = group.tabIDs.firstIndex(of: id),
               let tab = visible.first(where: { $0.id == id }) {
                // Genuine favicon bytes changed; keep the armed URL identity.
                button.loadFavicon(page: index) { [weak self, weak button] completion in
                    self?.requestTabFavicon?(tab) { [weak self, weak button] image in
                        guard let self, let button, self.favoriteTiles[tileID] === button else { return }
                        completion(image)
                    }
                }
            } else if tileID == id, let tab = visible.first(where: { $0.id == id }) {
                button.loadFavicon(page: 0) { [weak self, weak button] completion in
                    self?.requestTabFavicon?(tab) { [weak self, weak button] image in
                        guard let self, let button, self.favoriteTiles[tileID] === button else { return }
                        completion(image)
                    }
                }
            }
        }
    }

    func render(state: BrowserState, focusedTabID: UUID?, loading: Set<UUID>, canBack: Bool, canForward: Bool, captures: [UUID: CaptureIndicatorPresentation] = [:],
                shareable: Set<UUID> = [], audio: [UUID: SidebarTabAudio] = [:]) {
        tabAudio = audio
        if let edit = titleEdit {
            let current = state.tabs.first { $0.id == edit.tab.id }
            let sameGroup = state.splitLayouts.first { $0.tabIDs.contains(edit.tab.id) }
                == hierarchyState?.splitLayouts.first { $0.tabIDs.contains(edit.tab.id) }
            if state.activeSpaceID == activeSpaceID, state.selectedTabIDs == edit.selected,
               focusedTabID == edit.focused, let current,
               SidebarTabTitle.sameItemForEditing(current, edit.tab), sameGroup {
                // Preserve the original AppKit field editor and any marked text.
                // The window/page continues updating; row reconstruction resumes
                // from the owner's latest state when this short edit completes.
                updateNavigation(canBack: canBack, canForward: canForward,
                    loading: focusedTabID.map { loading.contains($0) } ?? false, enabled: true)
                return
            }
            titleEdit = nil; edit.row.cancelTitleEditing()
        }
        if let edit = folderTitleEdit {
            // The cached row keeps its field editor across this render while
            // its folder keeps the name and Space the edit began with.
            let current = state.folders.first { $0.id == edit.folder.id }
            if state.activeSpaceID != activeSpaceID || current?.name != edit.folder.name || current?.spaceID != edit.folder.spaceID
                || current?.parentID != edit.folder.parentID {
                folderTitleEdit = nil; edit.row.cancelTitleEditing()
            }
        }
        if let edit = splitTitleEdit {
            if state.activeSpaceID == activeSpaceID, state.selectedTabIDs == edit.selected,
               focusedTabID == edit.focused, edit.target.matches(state) {
                updateNavigation(canBack: canBack, canForward: canForward,
                    loading: focusedTabID.map { loading.contains($0) } ?? false, enabled: true)
                return
            }
            splitTitleEdit = nil; edit.row.cancelTitleEditing()
        }
        // True no-op of outline rebuild when membership/selection/folder
        // expansion already match: patch cells via the live path and skip
        // row allocation plus forced layoutSubtreeIfNeeded. First paint and
        // membership moves still fall through.
        if hierarchyState != nil,
           applyLivePageMetadata(state: state, focusedTabID: focusedTabID, loading: loading,
                                 canBack: canBack, canForward: canForward, captures: captures,
                                 shareable: shareable, audio: audio, allowSelectionChange: true) {
            return
        }
        latestFocusedTabID = focusedTabID
        renderedNewTabPlaceholder = newTabPlaceholderActive
        let context = state.spaces.first { $0.id == state.activeSpaceID }.flatMap {
            SidebarHierarchySnapshot(state: state, spaceID: $0.id, profileID: $0.profileID)
        }
        let splitGroups = SidebarSplitItems.groups(in: state, spaceID: state.activeSpaceID)
        let activeID = focusedTabID ?? state.selectedTabIDs.first
        let activeItem = activeID.map { id in
            splitGroups.first { $0.tabIDs.contains(id) }
                .map { SidebarItemReference.split($0.id) } ?? .tab(id)
        }
        // Folder disclosure alone keeps the selection, as AppKit's outline keeps
        // its selected rows across expand and collapse (a folder row's
        // AXDisclosing); reconcile below drops the rows a collapse hides.
        var disclosed = state
        for index in disclosed.folders.indices { disclosed.folders[index].isExpanded = true }
        let structure = context.flatMap { SidebarHierarchySnapshot(state: disclosed, spaceID: $0.spaceID, profileID: $0.profileID) }
        if structure != selectionStructure || activeItem != selectionActive { itemSelection.clear() }
        selectionContext = context; selectionStructure = structure; selectionActive = activeItem
        favoriteAnchors.removeAll()
        if state.activeSpaceID != activeSpaceID { newTabRow.dropHeldPress() }
        let departing = activeSpaceID, afterCreation = creationEnded
        creationEnded = false
        spaces = state.spaces; activeSpaceID = state.activeSpaceID
        spacesHost.isHidden = isPrivateBrowsing
        favoritesHost.isHidden = isPrivateBrowsing
        libraryEntry.isHidden = false
        folders = state.folders.filter { $0.spaceID == state.activeSpaceID }
        outlineInvalidated = false
        updateFolderPeeks(state: state, active: activeItem, keepActive: renderedNewTabPlaceholder)
        let space = spaces.first { $0.id == state.activeSpaceID }
        layer?.backgroundColor = NSColor.clear.cgColor
        back.isEnabled = canBack; forward.isEnabled = canForward
        setAddressTitle(Self.address(of: state.tabs.first { $0.id == (focusedTabID ?? state.selectedTabIDs.first) }))
        favorites.removeAll(); favoriteItems.removeAll()
        var retainedFavoriteIDs = Set<UUID>()
        let visible = state.tabs.filter { $0.archivedAt == nil }
        todayOrder = SidebarTodayArchive.order(in: state, spaceID: state.activeSpaceID)
        let tray = SidebarContainerLocation(spaceID: state.activeSpaceID, folderID: nil, section: .favorite, profileID: space?.profileID)
        for item in SidebarHierarchy.children(in: tray, state: state) {
            let group: BrowserSplitLayout? = { if case .split(let id) = item { return splitGroups.first { $0.id == id } }; return nil }()
            let id: UUID? = { if case .tab(let id) = item { return id }; return group?.sidebarAnchorID }()
            guard let id, let tab = visible.first(where: { $0.id == id }) else { continue }
            //
            let spokenTitle = FavoriteAccessibilityTitle.text(group.map { split in
                split.customTitle.map { [$0] } ?? split.tabIDs.compactMap { id in visible.first { $0.id == id }.map(SidebarTabTitle.display) }
            } ?? [SidebarTabTitle.display(tab)])
            func monogram(_ page: BrowserTab) -> String {
                let host = URL(string: page.url)?.host?.replacingOccurrences(of: "www.", with: "") ?? "New tab"
                return String(host.prefix(1)).uppercased()
            }
            let button = favoriteTiles[tab.id] ?? FavoriteTile(title: spokenTitle, monogram: monogram(tab), url: WhatsNewPage.presented(tab.url))
            favoriteTiles[tab.id] = button; retainedFavoriteIDs.insert(tab.id)
            button.update(title: spokenTitle, monogram: monogram(tab), url: WhatsNewPage.presented(tab.url),
                owner: .init(tabID: tab.id, profileID: tab.profileID,
                             spaceID: state.activeSpaceID, createdAt: tab.createdAt))
            bindFavoriteTile(button, tab: tab, group: group, item: item, state: state)
            if let icon = group?.customIcon {
                button.setCustomGlyph(image: icon.image, text: icon.emoji)
                favoriteFaviconArms.removeValue(forKey: tab.id)
            } else {
                let pages = group.map { $0.tabIDs.compactMap { id in visible.first { $0.id == id } } } ?? [tab]
                let orientation = group?.orientation ?? .horizontal
                let arm = FavoriteFaviconIdentity(pageURLs: pages.map(\.url), orientation: orientation)
                button.setPages(pages.map(monogram), orientation: orientation)
                // True no-op only when this reused tile already shows settled
                // favicons for the same page URLs + orientation. Monogram-only
                // / in-flight tiles keep loading so a later same-URL history
                // hit is not dropped; `reloadFavicon(for:)` still forces load.
                let skipArm = favoriteFaviconArms[tab.id] == arm
                    && button.hasSettledPageFavicons(count: pages.count)
                if !skipArm {
                    favoriteFaviconArms[tab.id] = arm
                    for (index, page) in pages.enumerated() {
                        button.loadFavicon(page: index) { [weak self, weak button] completion in
                            self?.requestTabFavicon?(page) { [weak self, weak button] image in
                                guard let self, let button, self.favoriteTiles[tab.id] === button else { return }
                                completion(image)
                            }
                        }
                    }
                }
            }
            //
            button.selected = activeID.map { group?.tabIDs.contains($0) ?? ($0 == tab.id) } ?? false
            if button.superview !== favoritesHost { favoritesHost.addSubview(button) }
            favorites.append(button); favoriteItems.append(item)
            favoriteAnchors[.tab(tab.id)] = button
            //
            // row, so the window capture strip is their only Stop entry.
            button.setOverlays(favoriteOverlays[tab.id] ?? .none)
        }
        for id in Set(favoriteTiles.keys).subtracting(retainedFavoriteIDs) {
            favoriteTiles.removeValue(forKey: id)?.removeFromSuperview()
            favoriteFaviconArms.removeValue(forKey: id)
        }
        //
        // dismisses it.
        favoritesEmptyState.update(favorites: favorites.count, profileID: space?.profileID, settings: state.settings,
                                   privateWindow: isPrivateBrowsing) { [weak self] in self?.dismissFavoritesEmptyState?($0) }
        if let editingSpace, space?.id != editingSpace.id || space?.profileID != editingSpace.profileID || space?.title != editingSpace.title {
            cancelSpaceNameEditing()
        }
        stateGeneration += 1
        hierarchyState = state
        renderedCaptures = captures; renderedShareable = shareable
        // The Space's own page: kept, or the one no Space owns yet, or new.
        let page = pages[state.activeSpaceID] ?? (shownPage.spaceID == nil ? shownPage : makePage())
        let swapsPage = page !== shownPage
        let origin = scroll.contentView.bounds.origin
        if swapsPage { show(page) }
        keep(state.activeSpaceID, page: page)
        // A new Space arrives from its own creation page, not the one it left.
        if let departing, departing != state.activeSpaceID, !afterCreation, window != nil, isPresented,
           creationView == nil, !contentSurface.isHidden,
           let from = spaces.firstIndex(where: { $0.id == departing }),
           let to = spaces.firstIndex(where: { $0.id == state.activeSpaceID }) {
            pagingSourceID = departing
            if !spacePager.slideIn(from: from, to: to) { pagingSourceID = nil }
        }
        dropProposal = nil; dropFeedback.targetRect = nil
        //
        // (TablistViewController's SidebarSnapshotViewState view store): a
        // page whose Space is unchanged patches live fields, a selection
        // change moves the current row, and only a changed Space rebuilds.
        let key = pageKey(state, focused: focusedTabID, placeholder: renderedNewTabPlaceholder)
        if page.key == key, page.pendingBuild == nil {
            patchLive(page, state: state, focusedTabID: focusedTabID)
        } else if page.pendingBuild == nil, let built = page.key, built.matchesApartFromSelection(key),
                  patchSelection(page, state: state, focusedTabID: focusedTabID) {
            page.key = key
            patchLive(page, state: state, focusedTabID: focusedTabID)
        } else if let pending = page.pendingBuild, pending.key == key {
            // A build begun ahead finishes, then takes what changed since it began.
            _ = pending.run(nil)
            patchLive(page, state: state, focusedTabID: focusedTabID)
        } else {
            buildPage(page, state: state, focusedTabID: focusedTabID, placeholder: renderedNewTabPlaceholder, key: key, animated: !swapsPage)
        }
        page.checkedGeneration = stateGeneration
        if swapsPage {
            // Another Space's page took the list's place.
            NSAccessibility.post(element: list, notification: .rowCountChanged)
            NSAccessibility.post(element: list, notification: .selectedRowsChanged)
        }
        itemSelection.reconcile(order: selectionOrder)
        refreshItemSelection()
        let previousSpaceButtons = spaceButtonsByID, previousSpaceMenus = spaceMenusByID
        spaceButtonsByID = [:]; spaceMenusByID = [:]
        spaceButtons = spaces.enumerated().map { offset, space in
            let button = previousSpaceButtons[space.id] ?? ActionButton()
            spaceButtonsByID[space.id] = button
            let spaceID = space.id
            let dockMenu = previousSpaceMenus[spaceID] ?? SidebarDockItemMenu { [weak self] in self?.dockSpaceMenu(spaceID) }
            spaceMenusByID[spaceID] = dockMenu
            dockMenu.install(on: button)
            button.actionBlock = { [weak self] in self?.onSelectSpace?(space.id, space.profileID) }
            if let icon = space.customIcon {
                button.image = icon.image; button.font = .systemFont(ofSize: 18)
            } else {
                button.image = NSImage(systemSymbolName: space.symbol, accessibilityDescription: space.name)
                button.font = .systemFont(ofSize: 12, weight: .medium)
            }
            button.title = space.customIcon?.emoji ?? ""
            button.imagePosition = space.customIcon?.emoji == nil ? .imageOnly : .noImage
            //
            // its Profile while there is more than one, and the Space's
            // numbered binding, above.
            let profileName = state.profiles.count > 1 ? state.profiles.first(where: { $0.id == space.profileID })?.name : nil
            button.parcTooltip = TooltipConfiguration(space.name.isEmpty ? "Untitled Space" : space.name,
                                                      style: .dockItem(profileName: profileName),
                                                      shortcut: .command(NumberedTarget.spaceBindingID(offset + 1)), anchor: .top)
            button.setAccessibilityLabel(space.name)
            SidebarAccessibility.configureSpace(button, name: space.name)
            let selected = creationView == nil && space.id == state.activeSpaceID
            button.tag = selected ? 1 : 0
            button.state = selected ? .on : .off
            button.isEnabled = canSelectSpace?(space.id, space.profileID) ?? false
            return button
        }
        updateDockItems()
        applyPalette()
        highlightItemForKeyboard(keyboardHighlightedItem, scrollToHighlight: false)
        setKeyboardSearchActive(keyboardSearchActive)
        keyViewsNeedLinking = true
        let retainedTabIDs = Set(pages.values.flatMap { $0.tabRows.map(\.tabID) + $0.keptTabRows.keys })
        for id in Set(tabFaviconArms.keys).subtracting(retainedTabIDs) {
            tabFaviconArms.removeValue(forKey: id)
        }
        needsLayout = true; layoutSubtreeIfNeeded()
        //
        if !swapsPage {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: min(origin.y, max(0, list.frame.height - scroll.contentView.bounds.height))))
        }
        if spacePager.offset == 0 { placePages(side: nil) } else { showPageStrip(at: spacePager.offset) }
        if isPresented && !isSpaceManagement { prepareNeighborPages() }
    }

    /// Builds `page` for `state`, whose active Space is the page's: its
    /// header, rows and outline, reusing the rows it kept. It writes only into
    /// the page, so a page beside the shown one builds the same way.
    private func buildPage(_ page: SidebarSpacePage, state: BrowserState, focusedTabID: UUID?, placeholder: Bool,
                           key: SidebarSpacePageKey, animated: Bool = false) {
        page.pendingBuild = nil
        _ = startBuild(page, state: state, focusedTabID: focusedTabID, placeholder: placeholder, key: key, animated: animated)(nil)
    }

    /// A page's build, run until a deadline or, without one, to the end; it
    /// answers whether it finished. Idle preparation resumes it a slice at a time.
    private func startBuild(_ page: SidebarSpacePage, state: BrowserState, focusedTabID: UUID?, placeholder: Bool,
                            key: SidebarSpacePageKey, animated: Bool = false) -> (CFTimeInterval?) -> Bool {
        page.checkedGeneration = stateGeneration
        // Its rows are let go below; until the build ends the page matches no key.
        page.key = nil; page.laidOut = false
        let pagePalette = page === shownPage ? palette : paletteForPage(state.activeSpaceID)
        let space = state.spaces.first { $0.id == state.activeSpaceID }
        let visible = state.tabs.filter { $0.archivedAt == nil }
        let splitGroups = SidebarSplitItems.groups(in: state, spaceID: state.activeSpaceID)
        let pageFolders = state.folders.filter { $0.spaceID == state.activeSpaceID }
        //
        // and menu toggle (SidebarChromeLayout.SpaceHeader.content).
        let headerContent = SidebarChromeLayout.SpaceHeader.content(
            spaces: state.spaces, activeSpaceID: state.activeSpaceID, privateWindow: isPrivateBrowsing,
            showOnSingleUnnamedSpace: state.settings.showSpaceHeaderOnSingleUnnamedSpaces ?? false)
        page.header.canShowHeaderButtonsIfPossible = !isSpaceManagement
        page.headerContentShown = headerContent.isShown
        page.header.isHidden = !headerContent.isShown && !page.header.isEditing
        page.header.update(headerContent, symbol: space?.customIcon?.image, emoji: space?.customIcon?.emoji)
        let profileName = state.profiles.count > 1 && !isPrivateBrowsing
            ? state.profiles.first(where: { $0.id == space?.profileID })?.name : nil
        page.header.updateProfile(name: profileName, menu: { [weak self] in
            guard let self, let id = self.activeSpaceID else { return nil }
            return self.makeSpaceManagementMenu?(id)?.profileMenu()
        })
        // Capture settled art before teardown so replacement rows for the same
        // page identity can adopt it and skip a true no-op re-arm.
        var priorTabFaviconArt: [UUID: TabRowSettledFaviconArt] = [:]
        for row in page.tabRows {
            if let art = row.settledFaviconArt() {
                priorTabFaviconArt[row.tabID] = art
            }
        }
        page.beginBuild()
        typealias Chrome = SidebarChromeLayout
        // Item rows in the order they are listed; Chrome.tablistSlots places
        // them in the list. Each builds its view when it nears the visible area.
        var itemRows: [SidebarOutlineEntry] = []
        let tabs = visible.filter { $0.spaceID == state.activeSpaceID }
        let activeAudioIDs = Set(tabs.compactMap { tab -> UUID? in
            guard let audio = tabAudio[tab.id], audio.audible || audio.muted else { return nil }
            return tab.id
        })
        page.speakerHosts = page.speakerHosts.filter { activeAudioIDs.contains($0.key) }
        let spaceTabIDs = Set(tabs.map(\.id))
        page.releasedFavicons = page.releasedFavicons.filter { spaceTabIDs.contains($0.key) }
        // Folder containers are pinned, so every container the walk lists is here.
        let containers = SidebarHierarchy.childrenByContainer(spaceID: state.activeSpaceID, state: state)
        let tabsByID = Dictionary(tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let visibleByID = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let foldersByID = Dictionary(pageFolders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let build = RowBuild(state: state, focusedTabID: focusedTabID, placeholder: placeholder, animated: animated,
                             visible: visibleByID, splitGroups: splitGroups, activeAudioIDs: activeAudioIDs,
                             pagePalette: pagePalette, priorFavicons: priorTabFaviconArt)
        func entry(_ item: SidebarItemReference, depth: Int, folder: UUID?) -> SidebarOutlineEntry {
            .item(item, depth: depth, in: folder) { [weak self, weak page] in
                guard let self, let page else { return NSView() }
                return self.buildRowView(item, page: page, build: build)
            }
        }
        var emittedGroups = Set<UUID>()
        func addTab(_ tab: BrowserTab, depth: Int = 0, folder: UUID? = nil) {
            let item: SidebarItemReference
            if let group = splitGroups.first(where: { $0.tabIDs.contains(tab.id) }) {
                guard group.sidebarAnchorID == tab.id, emittedGroups.insert(group.id).inserted else { return }
                item = .split(group.id)
                page.addItem(item, tabs: group.tabIDs)
            } else {
                item = .tab(tab.id)
                page.addItem(item)
            }
            itemRows.append(entry(item, depth: depth, folder: folder))
        }
        var visitedFolders = Set<UUID>()
        /// The walk's remaining work, the next last: a container lists its
        /// items in place, and a folder's children follow its row, in the
        /// order a recursive walk visits them.
        enum Work {
            case container(UUID?, TabKind, Int, [SidebarItemReference]?)
            case item(SidebarItemReference, UUID?, Int)
            case today
        }
        var work: [Work] = isPrivateBrowsing ? [.today] : [.today, .container(nil, .pinned, 0, nil)]
        var pinnedRows: [SidebarOutlineEntry] = []
        func process(_ next: Work) {
            switch next {
            case .today:
                pinnedRows = itemRows; itemRows.removeAll()
                work.append(.container(nil, .today, 0, nil))
            case .container(let parentID, let section, let depth, let only):
                let location = SidebarContainerLocation(spaceID: state.activeSpaceID, folderID: parentID, section: section)
                let items = (containers[location.key] ?? []).filter { only?.contains($0) ?? true }
                work.append(contentsOf: items.reversed().map { .item($0, parentID, depth) })
            case .item(let item, let parentID, let depth):
                addItem(item, parentID: parentID, depth: depth)
            }
        }
        func addItem(_ item: SidebarItemReference, parentID: UUID?, depth: Int) {
                switch item {
                case .tab(let id):
                    if let tab = tabsByID[id] { addTab(tab, depth: depth, folder: parentID) }
                    return
                case .split(let id):
                    if let group = splitGroups.first(where: { $0.id == id }), let anchor = group.sidebarAnchorID, let tab = visibleByID[anchor] { addTab(tab, depth: depth, folder: parentID) }
                    return
                case .folder: break
                }
                guard case .folder(let id) = item, visitedFolders.insert(id).inserted,
                      let folder = foldersByID[id] else { return }
                let peeks = folder.isExpanded ? [] : folderPeeks[folder.id] ?? []
                page.addItem(item)
                // The folder's row discloses its children's rows. Its AXDisclosing
                // toggles the folder without the click's selection reset.
                itemRows.append(.folder(folder.id, depth: depth, in: parentID, expanded: folder.isExpanded,
                                        toggle: { [weak self] in self?.onToggleFolder?(folder.id) }) { [weak self, weak page] in
                    guard let self, let page else { return NSView() }
                    return self.buildFolderRow(folder, peeks: peeks, page: page, build: build)
                })
                if folder.isExpanded {
                    work.append(.container(folder.id, .pinned, depth + 1, nil))
                } else if !peeks.isEmpty {
                    work.append(.container(folder.id, .pinned, depth + 1, peeks))
                }
        }
        let today = tabs.filter { $0.kind == .today && $0.folderID == nil }
        func makeSectionDivider() -> NSView {
            //
            //
            // spans the cell's insets while Clear is out of the row and ends
            //
            // (buttons .tidyAndClear) is never shown.
            let section = LayoutView()
            //
            //
            page.pinnedEnd = section
            let clear = ActionButton(SidebarClearAppearance.title) { [weak self] in self?.onClearToday?() }
            clear.identifier = NSUserInterfaceItemIdentifier("sidebarClear")
            SidebarClearAppearance.apply(to: clear, dark: pagePalette?.isDark ?? false)
            clear.onHover = { [weak self, weak clear] hovered in
                guard let self, let clear else { return }
                SidebarClearAppearance.apply(to: clear, dark: self.palette?.isDark ?? false, hovered: hovered)
            }
            clear.alignment = .right
            //
            // Today keeps its keyboard command, and VoiceOver can still press it.
            clear.refusesFirstResponder = true
            //
            //
            LiveShortcutToolTip.set(clear, "Clear Today tabs", commandID: "clearToday:")
            page.clearButton = clear
            page.todayHasTabs = !today.isEmpty
            clear.isAvailable = { [weak self] in self?.clearAvailable ?? false }
            clear.hitTestsWhenTransparent = false
            page.clearRevealed = clearShown
            clear.isHidden = !page.clearRevealed; clear.alphaValue = page.clearRevealed ? 1 : 0
            let line = SidebarHairline(); line.dark = pagePalette?.isDark ?? false
            page.sectionLine = line
            section.addSubview(line); section.addSubview(clear)
            section.onLayout = { [weak section, weak line, weak clear] in
                guard let section, let clear else { return }
                let inset = Chrome.sectionDividerInset, bounds = section.bounds
                let width = ceil(clear.intrinsicContentSize.width)
                clear.frame = NSRect(x: max(0, bounds.width - inset - width), y: (bounds.height - 20) / 2, width: width, height: 20)
                //
                let pad = clear.cell?.imageRect(forBounds: clear.bounds).minX ?? 0
                clear.frame = NSRect(x: clear.frame.minX + pad, y: clear.frame.minY, width: width - pad, height: 20)
                let scale = section.window?.backingScaleFactor ?? 1
                let thickness = Chrome.sectionDividerThickness(scale: scale)
                let end = clear.isHidden ? bounds.width - inset : clear.frame.minX - Chrome.sectionDividerSpacing
                line?.frame = NSRect(x: inset, y: (((bounds.height - thickness) / 2) * scale).rounded(.down) / scale,
                                     width: max(0, end - inset), height: thickness)
            }
            return section
        }
        func makePrivateHeading() -> NSView {
            //
            //
            //
            let heading = SidebarSpaceHeaderView()
            heading.update(.init(isShown: true, title: "Incognito Tabs", placeholder: nil, toggleTitle: nil),
                           symbol: nil, emoji: nil)
            heading.applyStyle(dark: pagePalette?.isDark ?? true, tint: nil)
            heading.updateIncognitoIndicator(shown: showsPrivateProfileIndicator)
            page.privateUnpinnedHeader = heading
            return heading
        }
        func makeNewTabRow() -> NSView {
            page.newTabRow.dark = pagePalette?.isDark ?? (effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            page.newTabRow.paletteTitle = pagePalette?.title ?? .parcInk
            page.newTabRow.invalidateHover()
            page.todayStart = page.newTabRow
            return page.newTabRow
        }
        var phase = 0, prepared = 0
        var outline: [SidebarOutlineEntry] = [], previousFrames: [AnyHashable: NSRect] = [:], disclosureChanged = false
        return { [self] deadline in
            func expired() -> Bool { deadline.map { CACurrentMediaTime() >= $0 } ?? false }
            if phase == 0 {
                while let next = work.popLast() {
                    process(next)
                    if !work.isEmpty, expired() { return false }
                }
                page.pinnedEnd = nil; page.clearButton = nil; page.sectionLine = nil; page.clearRevealed = false; page.todayHasTabs = false
                var pinnedEntries = pinnedRows.makeIterator(), todayEntries = itemRows.makeIterator()
                // Each visible list entry, in outline order, becomes one outline row.
                for slot in Chrome.tablistSlots(pinnedItems: pinnedRows.count, todayItems: itemRows.count,
                                                isPrivate: isPrivateBrowsing) {
                    switch slot {
                    case .pinnedHeader: outline.append(.pinnedHeader(SidebarListRow.pinnedHeader))
                    case .pinnedItem: if let entry = pinnedEntries.next() { outline.append(entry) }
                    case .todayItem: if let entry = todayEntries.next() { outline.append(entry) }
                    case .sectionDivider: outline.append(.init(key: SidebarListRow.divider, content: makeSectionDivider(), row: slot.row))
                    case .privateHeading: outline.append(.init(key: SidebarListRow.heading, content: makePrivateHeading(), row: slot.row))
                    case .newTab:
                        // Library cards have no New Tab cell; Today begins below the
                        // divider, or below the last row without one.
                        if isSpaceManagement { page.todayStart = page.pinnedEnd; continue }
                        outline.append(.init(key: SidebarListRow.newTab, content: makeNewTabRow(), row: slot.row))
                        // Without a divider the pinned section ends at New Tab's row.
                        if page.pinnedEnd == nil, !isPrivateBrowsing { page.pinnedEnd = page.todayStart }
                    }
                }
                // A folder's disclosure or peek change in this Space animates the outline.
                let disclosure = Dictionary(pageFolders.map { ($0.id, $0.isExpanded) }, uniquingKeysWith: { first, _ in first })
                let visiblePeeks = folderPeeks.filter { disclosure[$0.key] != nil }
                disclosureChanged = page.renderedDisclosure.map { previous in
                    animated && (previous.peeks != visiblePeeks
                        || disclosure.contains { id, expanded in previous.expanded[id].map { $0 != expanded } ?? false })
                } ?? false
                page.renderedDisclosure = (disclosure, visiblePeeks)
                previousFrames = disclosureChanged ? page.list.rowFrames() : [:]
                phase = 1
                if expired() { return false }
            }
            if deadline != nil {
                while prepared < outline.count {
                    let next = min(outline.count, prepared + 50)
                    page.list.prepareReload(outline[prepared..<next])
                    prepared = next
                    if expired() { return false }
                }
            }
            // Built ahead, the page's rows build their views a few per turn
            // afterwards (prepareNeighborPage); shown, the rows in view build now.
            page.list.reload(outline, budget: deadline == nil ? .max : 0)
            page.endBuild()
            if disclosureChanged { page.list.animateDisclosure(from: previousFrames) }
            page.key = key; page.renderedState = state; page.laidOut = false; page.framed = nil
            page.palette = nil
            applyPagePalette(page, pagePalette)
            if page === shownPage { refreshClearAvailability() }
            page.pendingBuild = nil
            return true
        }
    }

    /// What a page's build knows when one of its rows builds its view, which
    /// may be long after the build; a row built later then takes what changed
    /// since (refreshBuiltRow).
    private struct RowBuild {
        let state: BrowserState
        let focusedTabID: UUID?
        let placeholder: Bool
        let animated: Bool
        let visible: [UUID: BrowserTab]
        let splitGroups: [BrowserSplitLayout]
        let activeAudioIDs: Set<UUID>
        let pagePalette: ThemeChromePalette?
        let priorFavicons: [UUID: TabRowSettledFaviconArt]
    }

    /// A built page's current copy of a tab, for a row built after the
    /// build: its live title and address, so its favicon matches.
    private func currentTab(_ id: UUID, page: SidebarSpacePage) -> BrowserTab? {
        guard page.key != nil else { return nil }
        return page.renderedState?.tabs.first { $0.id == id && $0.archivedAt == nil }
    }

    /// Builds the view of a tab's or Split View's row.
    private func buildRowView(_ item: SidebarItemReference, page: SidebarSpacePage, build: RowBuild) -> NSView {
        let view: NSView
        switch item {
        case .split(let id):
            guard let group = build.splitGroups.first(where: { $0.id == id }) else { return NSView() }
            view = makeSplitRow(group, page: page, build: build)
        case .tab(let id):
            guard let tab = currentTab(id, page: page) ?? build.visible[id] else { return NSView() }
            view = makeTabRow(tab, page: page, build: build)
        case .folder: return NSView()
        }
        finishRow(item, view, page: page, build: build)
        return view
    }

    private func makeTabRow(_ tab: BrowserTab, inGroup: Bool = false, page: SidebarSpacePage, build: RowBuild) -> SidebarTabRow {
        let state = build.state
        let current = inGroup ? build.focusedTabID == tab.id
            : !build.placeholder && state.selectedTabIDs.contains(tab.id)
        //
        //
        let speaker: SidebarSpeakerHost?
        if build.activeAudioIDs.contains(tab.id) {
            speaker = page.speakerHosts[tab.id] ?? SidebarSpeakerHost(muted: tabAudio[tab.id]?.muted == true)
            page.speakerHosts[tab.id] = speaker
        } else { speaker = nil }
        // A split's children move into a new split cell each render; a
        // standalone row is reused from its Space's page, as the live
        // path patches it, while it keeps its speaker.
        let reused = inGroup ? nil : page.keptTabRows[tab.id].flatMap { $0.speakerHost === speaker && $0.canShow(tab) ? $0 : nil }
        let row = reused ?? SidebarTabRow(tab: tab, selected: current, speaker: speaker,
            close: { [weak self] in self?.closingPeek(.tab(tab.id), self?.prepareTabClose?(tab)) },
            reset: { [weak self] in inGroup ? nil : self?.prepareIconReset?(tab, false) },
            separate: { [weak self] in inGroup ? nil : self?.prepareIconReset?(tab, true) })
        if let reused { reused.applyLivePage(tab); reused.selected = current }
        row.audio = tabAudio[tab.id]
        row.onControlsChanged = { [weak self] in self?.rowControlsBuilt = true; self?.setNeedsKeyViewLinking() }
        bindLiveRow(row, tab: tab, inGroup: inGroup)
        row.capture = renderedCaptures[tab.id]
        row.showCapture = { [weak self] anchor in self?.onCaptureMenu?(tab.id, anchor) }
        row.shareable = renderedShareable.contains(tab.id)
        row.prepareShare = { [weak self] in self?.prepareShareThisTab?(tab.id) }
        let selectionItem = inGroup ? build.splitGroups.first { $0.tabIDs.contains(tab.id) }.map { SidebarItemReference.split($0.id) } ?? .tab(tab.id) : .tab(tab.id)
        row.selectionClick = { [weak self] event in self?.selectItem(selectionItem, event: event) ?? false }
        // A split child has no drag of its own: its split cell moves the
        //
        if !inGroup {
            row.beginSidebarMove = { [weak self] in self?.beginSelectedMove(.tab(tab.id)) }
            row.beginSplitDrag = { [weak self] in guard let self, self.itemSelection.items.isEmpty else { return nil }; return self.onBeginSplitDrag?(tab.id) }
        }
        // A rebuild during the drag keeps the key item's fill; the drag's
        // source row reports its end even after it leaves the sidebar.
        row.keyDragged = !inGroup && keyDraggedTabID == tab.id
        row.onKeyDrag = { [weak self] dragging in
            guard let self else { return }
            if dragging { self.keyDraggedTabID = tab.id } else if self.keyDraggedTabID == tab.id { self.keyDraggedTabID = nil }
            for other in self.tabRows where other.tabID == tab.id && !other.compactSplitChild { other.keyDragged = dragging }
        }
        if !isSpaceManagement, let url = URL(string: tab.url), SidebarRecentDomain.matching(url) != nil, SidebarPreviewPreference.recentPages.isEnabled {
            row.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Preview recent pages", handler: { [weak self] in
                self?.onPreview?(.tab(tab.id)); return true
            })])
        } else { row.setAccessibilityCustomActions([]) }
        if !inGroup {
            addMoveAccessibility(to: row, item: .tab(tab.id))
            // A row built after the page's build is reused by the next one too.
            page.keptTabRows[tab.id] = row
        }
        page.tabRows.append(row)
        // True no-op only when page URL + reset destination match the last
        // arm and settled art can be adopted onto this replacement row.
        // Fallback / in-flight rows keep loading so a later same-URL
        // history hit is not dropped; `reloadFavicon(for:)` still forces
        // load. Favorite tiles above keep their own settled skip. A row
        // built again after the list let it go adopts the art it showed.
        let arm = TabRowFaviconIdentity(pageURL: tab.url, resetDestination: tab.resetDestination)
        let released = page.releasedFavicons.removeValue(forKey: tab.id)
        let releasedArt = released?.arm == arm ? released?.art : nil
        let priorArt = releasedArt ?? build.priorFavicons[tab.id] ?? reused?.settledFaviconArt()
        let skipArm = (tabFaviconArms[tab.id] == arm || releasedArt != nil) && priorArt != nil
        if let art = priorArt, skipArm {
            row.adoptSettledFaviconArt(art)
        } else {
            tabFaviconArms[tab.id] = arm
            row.loadFavicon { [weak self, weak row, weak page] completion in
                self?.requestTabFavicon?(tab) { [weak self, weak row, weak page] image in
                    guard self != nil, let row, page?.holds(row) == true else { return }
                    completion(image)
                }
            }
            row.loadResetIcon { [weak self, weak row, weak page] completion in
                self?.requestSavedFavicon?(tab) { [weak self, weak row, weak page] image in
                    guard self != nil, let row, page?.holds(row) == true else { return }
                    completion(image)
                }
            }
        }
        page.previewAnchors[.tab(tab.id)] = row
        return row
    }

    private func makeSplitRow(_ group: BrowserSplitLayout, page: SidebarSpacePage, build: RowBuild) -> SidebarSplitGroupView {
        let state = build.state
        let children = group.tabIDs.compactMap { currentTab($0, page: page) ?? build.visible[$0] }.map { makeTabRow($0, inGroup: true, page: page, build: build) }
        // ChildItemState.isGroupSelected: every child of the selected
        //
        let groupSelected = !build.placeholder && group.tabIDs == state.selectedTabIDs
        children.forEach { $0.splitGroupSelected = groupSelected }
        //
        //
        // closes; a pinned split deselects while a child is presented.
        let today = SidebarHierarchy.location(of: .split(group.id), state: state, spaceID: state.activeSpaceID)?.section == .today
        let presented = group.tabIDs.contains { hasPresentedContent?($0) == true }
        let closeAction = SidebarSplitCellLayout.closeAction(today: today, anyChildPresented: presented)
        let groupView = SidebarSplitGroupView(group: group, rows: children, selected: groupSelected, today: today,
            closeAction: closeAction, privateWindow: isPrivateBrowsing)
        groupView.beginMove = { [weak self] in self?.beginSelectedMove(.split(group.id)) }
        groupView.keyDragged = keyDraggedSplitID == group.id
        groupView.onKeyDrag = { [weak self] dragging in self?.setKeyDraggedSplit(group.id, dragging) }
        groupView.closeAvailable = { [weak self] in self?.canCloseSplit?(group.id) == true }
        groupView.prepareClose = { [weak self] in self?.closingPeek(.split(group.id), self?.prepareSplitClose?(group.id)) }
        //
        // Close is reached only as the visible SidebarCellButton.
        groupView.setAccessibilityCustomActions([])
        if !isSpaceManagement, let profileID = state.spaces.first(where: { $0.id == group.spaceID })?.profileID,
           let target = SidebarSplitTitleEdit(group: group, profileID: profileID, state: state) {
            groupView.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Rename Split View") { [weak self] in
                self?.beginTitleEditing(target) == true
            }] + splitAppearanceActions(target))
        }
        //
        // opens. A child passes its secondary click to the split's one
        //
        let cellMenu: () -> NSMenu = { [weak self] in
            guard let self else { return NSMenu() }
            if self.isSpaceManagement { return self.managementItemMenu?(.split(group.id)) ?? NSMenu() }
            guard let current = self.hierarchyState else { return NSMenu() }
            return self.splitCellMenu(group, state: current)
        }
        for row in children {
            row.context = { [weak self] in self?.selectedItemsMenu(for: .split(group.id)) ?? cellMenu() }
        }
        groupView.prepareActivation = { [weak self, weak groupView] in
            guard let self, let groupView else { return nil }
            let id = self.latestFocusedTabID.flatMap { group.tabIDs.contains($0) ? $0 : nil } ?? group.tabIDs.first
            return groupView.rows.first(where: { $0.tabID == id })?.prepareActivation?()
        }
        groupView.selectionClick = { [weak self] event in self?.selectItem(.split(group.id), event: event) ?? false }
        groupView.selectionContext = { [weak self] in self?.selectedItemsMenu(for: .split(group.id)) ?? cellMenu() }
        addMoveAccessibility(to: groupView, item: .split(group.id))
        if let pagePalette = build.pagePalette { groupView.applyPalette(pagePalette) }
        return groupView
    }

    /// Builds the view of a folder's row; `peeks` are the items the
    /// collapsed folder shows under it.
    private func buildFolderRow(_ folder: BrowserFolder, peeks: [SidebarItemReference], page: SidebarSpacePage, build: RowBuild) -> NSView {
        // The row outlives renders so its icon animates a disclosure change.
        let button = page.folderRows[folder.id] ?? SidebarFolderRow(folder: folder)
        page.folderRows[folder.id] = button
        button.update(folder, animated: build.animated)
        button.closePeek = peeks.isEmpty ? nil : { [weak self] in self?.closeFolderPeek(folder.id) }
        button.peeked = !peeks.isEmpty
        button.setAccessibilityCustomActions([])
        button.activate = { [weak self] in self?.clearItemSelection(); self?.onToggleFolder?(folder.id) }
        button.doubleClick = isSpaceManagement ? nil : { [weak self] _ in self?.beginFolderTitleEditing(folder.id) ?? false }
        button.selectionClick = { [weak self] event in self?.selectItem(.folder(folder.id), event: event) ?? false }
        button.selectionContext = { [weak self] in self?.selectedItemsMenu(for: .folder(folder.id)) }
        button.beginMove = { [weak self] in self?.beginSelectedMove(.folder(folder.id)) }
        if SidebarPreviewPreference.folders.isEnabled {
            button.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Preview folder", handler: { [weak self] in
                self?.onPreview?(.folder(folder.id)); return true
            })])
        }
        page.previewAnchors[.folder(folder.id)] = button
        button.makeMenu = { [weak self, id = folder.id] in
            guard let self else { return nil }
            return self.isSpaceManagement ? self.managementItemMenu?(.folder(id)) : self.folderMenu(id)
        }
        button.menu = nil
        if isSpaceManagement { button.setAccessibilityCustomActions([]) }
        button.deferAccessibilityActions { [weak self, id = folder.id] in
            guard let self else { return [] }
            return self.folderAccessibilityActions(id) + self.moveAccessibilityActions(item: .folder(id))
        }
        if button.palette != build.pagePalette { button.palette = build.pagePalette }
        finishRow(.folder(folder.id), button, page: page, build: build)
        return button
    }

    /// Registers a built row with its page and gives it the selection
    /// actions every item row offers, then what changed since its build.
    private func finishRow(_ item: SidebarItemReference, _ view: NSView, page: SidebarSpacePage, build: RowBuild) {
        page.add(item, view)
        let select = NSAccessibilityCustomAction(name: "Add or Remove from Selection") { [weak self] in
            guard let self, self.window?.isKeyWindow == true, self.canSelectItems?() == true else { return false }
            self.itemSelection.select(item, order: self.selectionOrder, active: self.selectionActive, extending: false, toggling: true)
            if self.activateSingleSelection() { return true }
            self.focusSelectionList(); return true
        }
        let actions = (view as? SidebarDeferredAccessibilityActions)?.storedAccessibilityActions
            ?? view.accessibilityCustomActions() ?? []
        let close = NSAccessibilityCustomAction(name: "Close Tabs in Selection") { [weak self] in
            guard let self, self.itemSelection.items.contains(item), let action = self.prepareSidebarClose?(self.itemSelection.items) else { return false }
            return action()
        }
        let clear = NSAccessibilityCustomAction(name: "Clear Selection") { [weak self] in self?.clearItemSelection(); return true }
        let duplicate = NSAccessibilityCustomAction(name: "Duplicate Selection") { [weak self] in
            guard let self, self.itemSelection.items.contains(item),
                  let action = self.prepareSidebarDuplicate?(self.itemSelection.items) else { return false }
            return action()
        }
        let remove = NSAccessibilityCustomAction(name: "Delete or Archive Selection") { [weak self] in
            guard let self, self.itemSelection.items.contains(item),
                  let action = self.prepareSidebarDeletion?(self.itemSelection.items) else { return false }
            return action()
        }
        var selectionActions: [NSAccessibilityCustomAction] = []
        if canSelectItems != nil { selectionActions += [select, clear] }
        if prepareSidebarDuplicate != nil { selectionActions.append(duplicate) }
        if prepareSidebarClose != nil { selectionActions.append(close) }
        if prepareSidebarDeletion != nil { selectionActions.append(remove) }
        view.setAccessibilityCustomActions(actions + selectionActions)
        refreshBuiltRow(item, view, page: page, builtFrom: build.state)
    }

    /// Shows `page` in the strip's place. The page shown until now keeps its
    /// views and stays beside it while the strip moves.
    private func show(_ page: SidebarSpacePage) {
        let previous = shownPage
        previous.view.passesThrough = true
        for (_, view) in previous.hierarchyRows {
            if let row = view as? SidebarTabRow { if row.multiSelected { row.multiSelected = false }; if row.listFocusRing { row.listFocusRing = false } }
            else if let group = view as? SidebarSplitGroupView { group.multiSelected = false; group.listFocusRing = false }
            else if let folder = view as? SidebarFolderRow { folder.multiSelected = false; folder.listFocusRing = false }
        }
        previous.resetPointer()
        previous.newTabRow.current = false
        previous.list.preparesRowsInLayout = false
        shownPage = page
        page.list.preparesRowsInLayout = true
        page.view.passesThrough = false
        page.view.frame = pageStrip.bounds
        page.view.isHidden = false
        newTabRow.current = newTabPlaceholderActive
        // A page built while the pointer was elsewhere takes Clear's current reveal.
        if let clearButton {
            clearRevealed = clearShown
            clearButton.isHidden = !clearRevealed; clearButton.alphaValue = clearRevealed ? 1 : 0
        }
        refreshClearAvailability()
        layoutPage(page)
        // A page shown before idle preparation built its rows builds them now.
        if page.list.hasUnbuiltRows {
            page.list.prepareRows(budget: .max)
            page.list.layoutSubtreeIfNeeded()
            page.laidOut = true
        }
        setNeedsKeyViewLinking()
    }

    /// The key of `state`'s active Space's page (SidebarSpacePageKey).
    private func pageKey(_ state: BrowserState, focused: UUID?, placeholder: Bool) -> SidebarSpacePageKey {
        let id = state.activeSpaceID
        var speakers = Set<UUID>()
        for tab in state.tabs where tab.spaceID == id {
            if let audio = tabAudio[tab.id], audio.audible || audio.muted { speakers.insert(tab.id) }
        }
        let splits = state.splitLayouts.filter { $0.spaceID == id }
        let presented = Set(splits.flatMap(\.tabIDs).filter { hasPresentedContent?($0) == true })
        var splitCaptures: [UUID: CaptureIndicatorPresentation] = [:]
        for split in splits where SidebarSplitCellLayout.usesCustomInfo(title: split.customTitle, hasIcon: split.customIcon != nil, editing: false) {
            for tab in split.tabIDs { splitCaptures[tab] = renderedCaptures[tab] }
        }
        // The drag's key item only shapes its own Space's page.
        let dragged = [keyDraggedTabID.flatMap { tab in state.tabs.contains { $0.id == tab && $0.spaceID == id } ? tab : nil },
                       keyDraggedSplitID.flatMap { split in splits.contains { $0.id == split } ? split : nil }]
        return SidebarSpacePageKey(state: state, spaceID: id, focused: focused, placeholder: placeholder, peeks: folderPeeks,
            speakers: speakers, presented: presented, splitCaptures: splitCaptures, keyDragged: dragged,
            flags: [isPrivateBrowsing, isSpaceManagement, showsPrivateProfileIndicator,
                    SidebarPreviewPreference.recentPages.isEnabled, SidebarPreviewPreference.folders.isEnabled,
                    canSelectItems != nil, prepareSidebarDuplicate != nil, prepareSidebarClose != nil,
                    prepareSidebarDeletion != nil, prepareFolderDeletion != nil])
    }

    /// The live path's patch on a page whose Space is otherwise unchanged:
    /// titles, addresses and favicons, captures, share offers and audio.
    private func patchLive(_ page: SidebarSpacePage, state: BrowserState, focusedTabID: UUID?) {
        let rendered = page.renderedState
        page.renderedState = state
        let id = state.activeSpaceID
        var current: [UUID: BrowserTab] = [:], before: [UUID: BrowserTab] = [:]
        for tab in state.tabs where tab.spaceID == id && tab.archivedAt == nil { current[tab.id] = tab }
        for tab in rendered?.tabs ?? [] where tab.spaceID == id { before[tab.id] = tab }
        let splitTabs = Set(SidebarSplitItems.groups(in: state, spaceID: id).flatMap(\.tabIDs))
        for row in page.tabRows {
            guard let tab = current[row.tabID] else { continue }
            patchLiveRow(row, tab: tab, before: before[row.tabID], inGroup: splitTabs.contains(tab.id), page: page)
        }
    }

    /// One row's live patch: `tab`'s title, address and favicon when they
    /// changed since `before`, and its capture, share offer and audio.
    private func patchLiveRow(_ row: SidebarTabRow, tab: BrowserTab, before: BrowserTab?, inGroup: Bool, page: SidebarSpacePage) {
        if before != tab {
            let urlChanged = row.applyLivePage(tab)
            bindLiveRow(row, tab: tab, inGroup: inGroup)
            if urlChanged {
                refreshPreviewAction(row, tab: tab)
                tabFaviconArms[tab.id] = TabRowFaviconIdentity(pageURL: tab.url, resetDestination: tab.resetDestination)
                row.loadFavicon { [weak self, weak row, weak page] completion in
                    self?.requestTabFavicon?(tab) { [weak row, weak page] image in
                        guard let row, page?.holds(row) == true else { return }
                        completion(image)
                    }
                }
                row.loadResetIcon { [weak self, weak row, weak page] completion in
                    self?.requestSavedFavicon?(tab) { [weak row, weak page] image in
                        guard let row, page?.holds(row) == true else { return }
                        completion(image)
                    }
                }
            }
        }
        row.capture = renderedCaptures[tab.id]
        row.shareable = renderedShareable.contains(tab.id)
        row.audio = tabAudio[tab.id]
    }

    /// A row built after its page's build, as it nears the visible area,
    /// shows what the page shows now: the live fields and selection that
    /// changed since the build, the sidebar's marks and the page's palette.
    private func refreshBuiltRow(_ item: SidebarItemReference, _ view: NSView, page: SidebarSpacePage, builtFrom state: BrowserState) {
        guard let key = page.key, let current = page.renderedState else { return }
        let standalone = view as? SidebarTabRow
        for row in standalone.map({ [$0] }) ?? (view as? SidebarSplitGroupView)?.rows ?? [] {
            guard let tab = current.tabs.first(where: { $0.id == row.tabID && $0.archivedAt == nil }) else { continue }
            patchLiveRow(row, tab: tab, before: state.tabs.first { $0.id == row.tabID }, inGroup: standalone == nil, page: page)
            if standalone != nil {
                let selected = !key.placeholder && key.selected.contains(tab.id)
                if row.selected != selected { row.selected = selected }
            }
        }
        if let palette = page.palette { applyPalette(palette, toRow: view) }
        guard page === shownPage else { return }
        applySelectionMarks(item, view, listFocused: window?.firstResponder === self)
        if let highlighted = keyboardHighlightedItem {
            if highlighted == item { markKeyboardHighlight(view, favorite: false) }
            else if case .tab(let id) = highlighted, let child = (view as? SidebarSplitGroupView)?.rows.first(where: { $0.tabID == id }) {
                markKeyboardHighlight(child, favorite: false)
            }
        }
        if case .folder(let id) = item, springFolder?.id == id { (view as? SidebarFolderRow)?.dropTarget = true }
        setNeedsKeyViewLinking()
    }

    /// A kept row's Preview recent pages action follows its page, as a
    /// rebuild makes it: first among the row's actions, before its moves.
    private func refreshPreviewAction(_ row: SidebarTabRow, tab: BrowserTab) {
        let stored = row.storedAccessibilityActions
        let had = stored.first?.name == "Preview recent pages"
        let wants = !isSpaceManagement && URL(string: tab.url).flatMap(SidebarRecentDomain.matching) != nil
            && SidebarPreviewPreference.recentPages.isEnabled
        guard had != wants else { return }
        var actions = had ? Array(stored.dropFirst()) : stored
        if wants {
            actions.insert(NSAccessibilityCustomAction(name: "Preview recent pages") { [weak self] in
                self?.onPreview?(.tab(tab.id)); return true
            }, at: 0)
        }
        row.setAccessibilityCustomActions(actions)
        if var deferred = row.deferredAccessibilityActions {
            deferred.index = max(0, deferred.index + (wants ? 1 : -1))
            row.deferredAccessibilityActions = deferred
        }
    }

    /// Moves the current row on a page whose Space changed only its
    /// selection between plain tabs (or a Favorite, which has no row), as
    /// `applySelection` does for a tab-to-tab switch; false when the rows
    /// can't show it.
    private func patchSelection(_ page: SidebarSpacePage, state: BrowserState, focusedTabID: UUID?) -> Bool {
        guard let built = page.key, !renderedNewTabPlaceholder, !built.placeholder,
              state.selectedTabIDs.count <= 1, built.selected.count <= 1 else { return false }
        let involved = Set(state.selectedTabIDs + built.selected + [focusedTabID, built.focused].compactMap { $0 })
        let splitTabs = Set(state.splitLayouts.filter { $0.spaceID == state.activeSpaceID }.flatMap(\.tabIDs))
        let favorites = Set(state.tabs.filter { $0.kind == .favorite }.map(\.id))
        guard involved.allSatisfy({ !splitTabs.contains($0) && (page.contains(.tab($0)) || favorites.contains($0)) }) else { return false }
        for id in involved {
            let selected = state.selectedTabIDs.contains(id)
            if let row = page.tabRow(id), row.selected != selected { row.selected = selected }
        }
        return true
    }

    /// The pages' shared geometry, from the sidebar's layout: the App Tray's
    /// height and the bottom of the tablist above the Mini Players.
    private struct PageGeometry: Equatable {
        var hiddenAddressHeight: CGFloat = 0
        var trayHeight: CGFloat = 0
        var hasFavorites = false
        var bottom: CGFloat = 0
    }
    private var pageGeometry = PageGeometry()
    /// Lays out `page`'s header and tablist at the sidebar's geometry; its
    /// rows too unless `flush` is false (idle preparation lays them out a few
    /// at a time).
    private func isFramed(_ page: SidebarSpacePage) -> Bool {
        guard let framed = page.framed else { return false }
        return framed.size == bounds.size && framed.hiddenAddressHeight == pageGeometry.hiddenAddressHeight
            && framed.trayHeight == pageGeometry.trayHeight
            && framed.hasFavorites == pageGeometry.hasFavorites && framed.bottom == pageGeometry.bottom
            && page.headerFramedShown == !page.header.isHidden
    }
    private func layoutPage(_ page: SidebarSpacePage, flush: Bool = true) {
        typealias Chrome = SidebarChromeLayout
        let width = bounds.width, geometry = pageGeometry
        page.framed = (bounds.size, geometry.hiddenAddressHeight, geometry.trayHeight, geometry.hasFavorites, geometry.bottom)
        page.headerFramedShown = !page.header.isHidden
        if isSpaceManagement {
            // The card's page has no App Tray: a shown header sits its
            // padding below the top and the list follows it, else the list
            // starts at the top (SidebarChromeLayout.SpaceHeader).
            page.header.frame = NSRect(x: 0, y: Chrome.SpaceHeader.topPadding, width: width, height: Chrome.SpaceHeader.height)
            let listTop = page.header.isHidden ? 0 : page.header.frame.maxY
            page.scroll.frame = NSRect(x: 8, y: listTop, width: max(0, width - 16), height: max(0, bounds.height - listTop))
        } else {
            // A shown Space header drops the header's 5-point inset, sits 8 below
            // the page's top while the profile has no Favorites, and the list
            // follows its bottom (SidebarChromeLayout.SpaceHeader).
            page.header.frame = NSRect(x: 0, y: Chrome.SpaceHeader.top(trayHeight: geometry.trayHeight, hasFavorites: geometry.hasFavorites) - geometry.hiddenAddressHeight,
                                       width: width, height: Chrome.SpaceHeader.height)
            let listY = Chrome.tablistTop(trayHeight: geometry.trayHeight, spaceHeader: !page.header.isHidden, hasFavorites: geometry.hasFavorites) - geometry.hiddenAddressHeight
            page.scroll.frame = NSRect(x: 8, y: listY, width: width - 16, height: max(0, geometry.bottom - listY))
        }
        // Membership rebuilds / disclosure / size changes dirty outline rows
        // or move this frame and still flush. Identical geometry with a clean
        // outline is a true no-op after the row-fill paint skip.
        let listFrame = NSRect(x: 0, y: 0, width: page.scroll.contentSize.width, height: max(0, page.list.contentHeight))
        let listFrameChanged = page.list.frame != listFrame
        if listFrameChanged { page.list.frame = listFrame }
        if page.listHost.frame != listFrame { page.listHost.frame = listFrame }
        guard flush else { return }
        if SidebarOutlineLayoutFlushSkip.shouldFlush(
            frameChanged: listFrameChanged,
            needsLayout: page.list.needsLayout,
            subtreeNeedsLayout: page.list.subviews.contains(where: \.needsLayout)
        ) {
            page.list.layoutSubtreeIfNeeded()
        }
        page.laidOut = !page.list.hasUnbuiltRows
    }

    /// The palette's colours on one item's row: a tab, a folder, or a split
    /// cell and its tabs.
    private func applyPalette(_ palette: ThemeChromePalette, toRow view: NSView) {
        if let folder = view as? SidebarFolderRow, folder.palette != palette { folder.palette = palette }
        let group = view as? SidebarSplitGroupView
        group?.applyPalette(palette)
        for row in (view as? SidebarTabRow).map({ [$0] }) ?? group?.rows ?? [] {
            if row.palette != palette { row.palette = palette }
            if isPrivateBrowsing { row.privateBrowsing = true }
        }
    }

    /// The palette's colours on a page's rows, headings and header; a page
    /// already showing `palette` is left alone.
    private func applyPagePalette(_ page: SidebarSpacePage, _ palette: ThemeChromePalette?) {
        guard let palette, page.palette != palette else { return }
        page.palette = palette
        for (_, view) in page.hierarchyRows { applyPalette(palette, toRow: view) }
        for view in page.list.contents {
            if let row = view as? SidebarNewTabRow {
                row.dark = palette.isDark; row.paletteTitle = palette.title
            } else if let heading = view as? SidebarSpaceHeaderView {
                heading.applyStyle(dark: palette.isDark, tint: nil)
            }
        }
        if let clearButton = page.clearButton { SidebarClearAppearance.apply(to: clearButton, dark: palette.isDark, hovered: clearButton.hovered) }
        page.sectionLine?.dark = palette.isDark
        // The Space header's icon takes ViewState headerTintColor, the
        // window's theme palette at +0x70 while that theme belongs to this
        //
        // live. As in the dock, +0x70 is read as maxContrastColor and a Space
        // stored without a theme colour keeps ForegroundTertiary [I].
        let themed = spaces.first { $0.id == page.spaceID }.map { $0.theme.primaryColor != nil && $0.theme.isValid } ?? false
        page.header.applyStyle(dark: palette.isDark, tint: themed ? palette.maxContrastColor : nil)
    }

    func updateSpaceAvailability() {
        for (space, button) in zip(spaces, spaceButtons) {
            button.isEnabled = canSelectSpace?(space.id, space.profileID) ?? false
        }
    }

    /// Creation replaces the sidebar content while retaining its native toolbar
    /// and Space footer. The document scrolls on short windows; controls never
    /// become inaccessible below the window edge.
    func setSpaceCreationView(_ view: SpaceCreationView?) {
        guard creationView !== view else { return }
        if view == nil {
            // Only the selection made as creation ends, in this same turn,
            // skips the slide; a later switch slides as usual.
            creationEnded = true
            DispatchQueue.main.async { [weak self] in self?.creationEnded = false }
        }
        creationView = view; creationScroll.documentView = view
        view?.palette = palette
        if view != nil { spacePager.cancel() }
        creationScroll.isHidden = view == nil; contentSurface.isHidden = view != nil
        creationSpaceButton.isHidden = view == nil
        creationSpaceButton.state = view == nil ? .off : .on
        if view != nil { clearItemSelection(); clearDrop() }
        archiveEducationHost.setInteractionAllowed(isPresented && view == nil)
        updateCompleteHost.setInteractionAllowed(isPresented && view == nil)
        updateReadyHost.setInteractionAllowed(isPresented && view == nil)
        for (space, button) in zip(spaces, spaceButtons) {
            let selected = view == nil && space.id == activeSpaceID
            button.tag = selected ? 1 : 0; button.state = selected ? .on : .off
            //
            spaceMenusByID[space.id]?.install(on: button)
        }
        updateDockItems(); updateSpaceAvailability(); setNeedsKeyViewLinking()
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    ///
    /// canBecomeKeyView or key-view-loop selector. Its sidebar therefore keeps
    /// AppKit's default loop, inferred to follow its structure: header buttons,
    /// the URL pill (SidebarHeaderView's buttons, then commandBarPlaceholderView),
    ///
    /// rows and buttons after a window's one-time loop, so it links that order,
    /// with the sidebar itself as a list stop for its arrow keys (adaptation).
    /// Spaces and the quote affordances refuse focus; the resize strip and
    /// keyboard highlight are no responders.
    private var keyViewsNeedLinking = true
    func setNeedsKeyViewLinking() { keyViewsNeedLinking = true; needsLayout = true }
    /// The shown page's outline, laid out by `layout` just before it links,
    /// unless a row has since built a control the chain must place.
    private var listLaidOut: (NSView) -> Bool {
        let built = rowControlsBuilt
        return { [list] in $0 === list && !list.needsLayout && !built }
    }
    private var rowControlsBuilt = false
    private func linkKeyViews() {
        defer { rowControlsBuilt = false }
        if isSpaceManagement {
            let chain = SidebarAccessibility.keyViewChain(leading: [], favorites: favoritesHost, list: self,
                regions: [list], trailing: [], space: self, beforeList: [spaceHeader], laidOut: listLaidOut)
            SidebarAccessibility.link(chain, within: self, exit: keyViewExit, bypassed: !isPresented,
                                     skipping: { ($0 as? SidebarPageStripView)?.passesThrough == true })
            return
        }
        let leading: [NSView] = [keyViewGate] + headerControls + [addressButton] + extensionToolbar.orderedButtons
            + [paymentAction, pageActions]
        var regions: [NSView] = [list, miniPlayers]
        if archiveEducationHost.isInteractive { regions += archiveEducation.keyViewControls }
        if updateCompleteHost.isInteractive { regions += updateComplete.keyViewControls }
        if updateReadyHost.isInteractive { regions += updateReady.keyViewControls }
        if let creationView { regions.append(creationView) }
        let chain = SidebarAccessibility.keyViewChain(leading: leading, favorites: favoritesHost, list: self, regions: regions,
                                                      trailing: [footerMore], space: self, beforeList: [spaceHeader], laidOut: listLaidOut)
        SidebarAccessibility.link(chain, within: self, exit: keyViewExit, bypassed: !isPresented,
                                     skipping: { ($0 as? SidebarPageStripView)?.passesThrough == true })
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        typealias Chrome = SidebarChromeLayout
        if isSpaceManagement {
            let shown: [NSView] = [contentSurface, pageStrip, scroll, dropFeedback]
            for child in subviews where child !== spaceHeader { child.isHidden = !shown.contains { $0 === child } }
            for child in contentSurface.subviews { child.isHidden = child !== pageStrip }
            contentSurface.frame = bounds; pageStrip.frame = bounds; dropFeedback.frame = bounds
            shownPage.view.frame = pageStrip.bounds
            layoutPage(shownPage)
            if keyViewsNeedLinking { keyViewsNeedLinking = false; linkKeyViews() }
            return
        }
        contentSurface.frame = bounds
        pageStrip.frame = bounds
        spaceCreationFeedback.frame = NSRect(x: width - SidebarSpaceCreationFeedbackView.width, y: 0,
                                             width: SidebarSpaceCreationFeedbackView.width, height: bounds.height)
        let creationTop = Chrome.headerTop + Chrome.navigationRowHeight
        creationScroll.frame = NSRect(x: 0, y: creationTop, width: width, height: max(0, bounds.height - creationTop - Chrome.dockHeight))
        creationView?.frame = NSRect(x: 0, y: 0, width: creationScroll.contentSize.width,
                                    height: max(436, creationScroll.contentSize.height))
        dropFeedback.frame = bounds
        let bar = Chrome.toolbar(width: width, windowButtons: showsWindowButtons ? WindowStandardButtons.stackSize : nil,
                                 showsNavigation: !usesContentToolbar && !navigationInContentToolbar,
                                 developerReload: developerReload)
        windowButtons.isHidden = bar.windowButtons == nil
        if let frame = bar.windowButtons { windowButtons.frame = frame }
        for (button, frame) in [(toggle, bar.toggle), (back, bar.back), (forward, bar.forward), (reload, bar.reload),
                                (reloadOptions, bar.reloadOptions)] as [(NSButton, CGRect?)] {
            button.isHidden = frame == nil
            if let frame { button.frame = frame }
        }
        let glyph = Chrome.navigationGlyphPointSize(buttonSide: (bar.back ?? bar.toggle)?.height ?? Chrome.dockButtonSide)
        for button in [back, forward, reload] { button.glyphPointSize = glyph }
        if toggleGlyphPointSize != glyph {
            toggleGlyphPointSize = glyph
            toggle.image = NavigationControlArtwork.symbol("sidebar.left", pointSize: glyph) ?? toggle.image
        }
        let field = NSRect(x: Chrome.fieldInset, y: Chrome.fieldTop, width: max(0, width - 2 * Chrome.fieldInset), height: Chrome.fieldHeight)
        addressBackground.frame = field
        // The URL button anchors the sidebar command field, which is its
        // superview's width − 18 wide (CommandBar.position); starting 1 point
        // inside the pill keeps that field at 9…width − 9.
        addressButton.frame = field.insetBy(dx: 1, dy: 0)
        pageActions.frame = NSRect(x: width - 38, y: 50, width: 25, height: 28)
        let quoteWidth: CGFloat = showsSharedQuote ? 28 : 0
        let extensionWidth = min(extensionToolbar.desiredWidth, max(0, floor((width - 138 - quoteWidth - paymentWidth) / 28) * 28))
        copyQuote.frame = NSRect(x: width - 66, y: 50, width: 25, height: 28)
        paymentAction.frame = NSRect(x: width - 42 - quoteWidth - paymentWidth, y: 50, width: paymentWidth, height: 28)
        extensionToolbar.frame = NSRect(x: width - 42 - quoteWidth - paymentWidth - extensionWidth, y: 50, width: extensionWidth, height: 28)
        // The field spans the container; the URL button must not cover native action hit targets.
        addressButton.frame.size.width = max(0, width - 54 - quoteWidth - paymentWidth - extensionWidth)
        applyAddressPillStyle()
        if showsSharedQuote {
            //
            addressButton.frame.size.height = 18
        }
        shareQuote.frame = NSRect(x: field.minX + 13.5, y: field.minY + 18, width: max(0, addressButton.frame.width - 14), height: 16)
        let iconSide = SidebarAddressSearchIcon.side
        addressSearchIcon.frame = NSRect(x: SidebarAddressSearchIcon.centerX - 1 - iconSide / 2,
                                         y: (addressButton.bounds.height - iconSide) / 2, width: iconSide, height: iconSide)
        addressButton.contentTintColor = palette?.title ?? .parcInk.withAlphaComponent(0.8)
        // The App Tray spans the sidebar below the header with its own 8-point
        // insets, or its empty state fills it, and the list follows it
        // (SidebarChromeLayout.appTrayHeight and tablistTop).
        let grid = FavoriteGridLayout.frames(count: favorites.count, width: width)
        let favoritesHeight = isPrivateBrowsing ? 0 : favoritesEmptyState.trayHeight(gridHeight: grid.height, width: width)
        favoritesHost.frame = NSRect(x: 0, y: Chrome.headerBottom - hiddenAddressHeight, width: width, height: favoritesHeight)
        favoritesEmptyState.frame = favoritesHost.bounds
        for (button, frame) in zip(favorites, grid.frames) {
            // The host is unflipped; the recovered grid is top-left based.
            button.frame = NSRect(x: frame.minX, y: favoritesHeight - frame.maxY, width: frame.width, height: frame.height)
        }
        let showsSpaceHeader = !spaceHeader.isHidden
        let listY = Chrome.tablistTop(trayHeight: favoritesHeight, spaceHeader: showsSpaceHeader, hasFavorites: !favorites.isEmpty) - hiddenAddressHeight
        let dockTop = bounds.height - Chrome.dockHeight
        let bannerWidth = max(0, width - 16)
        // The card coming in sizes the slot while another is still leaving.
        let banners: [(host: SidebarBannerHost, height: (CGFloat) -> CGFloat)] = [
            (updateReadyHost, updateReady.preferredHeight), (updateCompleteHost, updateComplete.preferredHeight),
            (archiveEducationHost, archiveEducation.preferredHeight)]
        let banner = banners.first { $0.host.isShowing } ?? banners.first { $0.host.occupiesSpace }
        let bannerHeight = banner?.height(bannerWidth) ?? 0
        let bannerSpacing: CGFloat = bannerHeight > 0 ? 8 : 0
        archiveEducationHost.frame = NSRect(x: 8, y: dockTop - bannerHeight, width: bannerWidth, height: bannerHeight)
        updateCompleteHost.frame = archiveEducationHost.frame
        updateReadyHost.frame = archiveEducationHost.frame
        let playerBottom = dockTop - bannerHeight - bannerSpacing
        let playerHeight = min(miniPlayers.desiredHeight, max(0, playerBottom - listY))
        let playerSpacing: CGFloat = playerHeight > 0 ? 8 : 0
        miniPlayers.frame = NSRect(x: 8, y: playerBottom - playerHeight, width: width - 16, height: playerHeight)
        let geometry = PageGeometry(hiddenAddressHeight: hiddenAddressHeight, trayHeight: favoritesHeight, hasFavorites: !favorites.isEmpty,
                                    bottom: playerBottom - playerHeight - playerSpacing)
        let geometryChanged = geometry != pageGeometry
        pageGeometry = geometry
        if shownPage.view.frame != pageStrip.bounds { shownPage.view.frame = pageStrip.bounds }
        layoutPage(shownPage)
        // The other pages follow a changed size or tray while idle, or when
        // a swipe reveals them.
        if geometryChanged {
            for page in pages.values where page !== shownPage {
                let slot = page.view.frame.width > 0 ? (page.view.frame.minX / page.view.frame.width).rounded() : 3
                page.view.frame = NSRect(x: slot * width, y: 0, width: width, height: bounds.height)
                page.laidOut = false
            }
            if isPresented && !isSpaceManagement && !pages.isEmpty { prepareNeighborPages() }
        }
        //
        // button, 32 × 32 and 8 from the edges, with the Space strip between
        // them at 40…width − 40.
        footerMore.frame = Chrome.dockTrailingButton(width: width, height: bounds.height)
        libraryEntry.containerWidth = width
        libraryEntry.place(button: Chrome.dockLeadingButton(height: bounds.height))
        libraryFlyoutMask.resize()
        spacesHost.frame = Chrome.dockStrip(width: width, height: bounds.height)
        if keyViewsNeedLinking { keyViewsNeedLinking = false; linkKeyViews() }
    }

    /// The selected Space, or the creation button while creating, is the
    ///
    ///
    /// appears in the traced item-view paths (inferred). A lone iconless Space
    ///
    private func updateDockItems() {
        let creating = !creationSpaceButton.isHidden
        let shown = SidebarChromeLayout.dockShowsSpaces(
            count: spaces.count, anyCustomIcon: spaces.contains { $0.customIcon != nil }, creating: creating)
        spacesHost.iconlessButtons = Set(zip(spaces, spaceButtons).compactMap { space, button in
            SidebarChromeLayout.dockIconless(hasCustomIcon: space.customIcon != nil, symbol: space.symbol) ? ObjectIdentifier(button) : nil
        })
        spacesHost.items = shown ? spaceButtons + (creating ? [creationSpaceButton] : []) : []
        spacesHost.selectedIndex = shown ? (creating ? spaceButtons.count : spaceButtons.firstIndex { $0.tag == 1 }) : nil
    }

    ///
    /// with the header's actions.
    private func dockSpaceMenu(_ id: UUID) -> SidebarSpaceMenu? {
        if let makeSpaceManagementMenu { return creationView == nil ? makeSpaceManagementMenu(id) : nil }
        return SidebarSpaceMenu.dock(spaces: spaces, spaceID: id, activeSpaceID: activeSpaceID, creatingSpace: creationView != nil,
                              showOnSingleUnnamedSpace: hierarchyState?.settings.showSpaceHeaderOnSingleUnnamedSpaces ?? false,
                              rename: { [weak self] id in self?.onRenameSpace?(id) },
                              editTheme: { [weak self] in self?.onEditTheme?() },
                              newFolder: { [weak self] in self?.onNewFolder?() },
                              toggleHeader: { [weak self] in self?.toggleSpaceHeaderOnSingleUnnamedSpaces?() })
    }

    ///
    /// active Space's, with the header's actions.
    private func sidebarSpaceMenu() -> SidebarSpaceMenu? {
        if let makeSpaceManagementMenu {
            guard !isPrivateBrowsing, creationView == nil, let id = activeSpaceID else { return nil }
            return makeSpaceManagementMenu(id)
        }
        return SidebarSpaceMenu.sidebar(spaces: spaces, activeSpaceID: activeSpaceID, creatingSpace: creationView != nil,
                                 privateWindow: isPrivateBrowsing,
                                 showOnSingleUnnamedSpace: hierarchyState?.settings.showSpaceHeaderOnSingleUnnamedSpaces ?? false,
                                 rename: { [weak self] id in self?.onRenameSpace?(id) },
                                 editTheme: { [weak self] in self?.onEditTheme?() },
                                 newFolder: { [weak self] in self?.onNewFolder?() },
                                 toggleHeader: { [weak self] in self?.toggleSpaceHeaderOnSingleUnnamedSpaces?() })
    }

    private func currentFavorite(_ expected: BrowserTab) -> BrowserTab? {
        guard let state = hierarchyState, let profile = state.spaces.first(where: { $0.id == activeSpaceID })?.profileID,
              profile == expected.profileID else { return nil }
        return state.tabs.first { $0 == expected && $0.kind == .favorite && $0.archivedAt == nil }
    }

    private func tabAccessibilityActions(_ tab: BrowserTab) -> [NSAccessibilityCustomAction] {
        var actions: [NSAccessibilityCustomAction] = []
        if let audio = tabAudio[tab.id], let mute = prepareTabMute?(tab, audio) {
            actions.append(NSAccessibilityCustomAction(name: audio.muted ? "Unmute" : "Mute", handler: mute))
        }
        if prepareTabRename?(tab) != nil {
            actions.append(NSAccessibilityCustomAction(name: "Rename Tab", handler: { [weak self] in
                self?.beginTitleEditing(tab) == true
            }))
        }
        if let reset = prepareResetTab?(tab) {
            actions.append(NSAccessibilityCustomAction(name: "Reset Tab to Original URL", handler: reset))
        }
        if let close = prepareTabClose?(tab) {
            let title = tab.kind == .today && !isPrivateBrowsing ? "Archive Tab" : "Close Tab"
            actions.append(NSAccessibilityCustomAction(name: title, handler: close))
        }
        if let separate = prepareSeparateSplitTab?(tab.id) {
            actions.append(NSAccessibilityCustomAction(name: "Separate Page from Split View", handler: separate))
        }
        return actions
    }

    private func tabMenu(_ tab: BrowserTab, allowsRename: Bool = true) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        if allowsRename, tab.kind == .favorite {
            let target = hierarchyState.flatMap { state in
                activeSpaceID.flatMap { space in SidebarSplitItems.groups(in: state, spaceID: space)
                    .first { $0.tabIDs.contains(tab.id) }.flatMap { SidebarSplitTitleEdit(group: $0, profileID: tab.profileID, state: state) } }
            }
            let action = target.map { prepareFavoriteSplitRename?($0) } ?? prepareFavoriteRename?(tab)
            let rename = MenuAction.item("Rename…") { _ = action?() }
            KeyboardShortcuts.shared.showBinding(on: rename, for: "renameCurrentItem:")
            rename.isEnabled = action != nil; menu.addItem(rename)
            if let target { appendSplitAppearance(to: menu, target: target) }
        }
        if allowsRename, SidebarTabTitle.isRenameable(tab) {
            let rename = MenuAction.item("Rename…") { [weak self] in _ = self?.beginTitleEditing(tab) }
            // The tab context menu's Rename and Copy Link carry rename's and
            //
            KeyboardShortcuts.shared.showBinding(on: rename, for: "renameCurrentItem:")
            rename.isEnabled = prepareTabRename?(tab) != nil
            menu.addItem(rename)
        }
        if !isPrivateBrowsing, let url = URL(string: tab.url), SidebarRecentDomain.matching(url) != nil {
            let previewItem = MenuAction.item("Preview recent pages") { [weak self] in self?.onPreview?(.tab(tab.id)) }
            previewItem.isEnabled = SidebarPreviewPreference.recentPages.isEnabled
            menu.addItem(previewItem)
            menu.addItem(.separator())
        }
        if let separate = prepareSeparateSplitTab?(tab.id) {
            menu.addItem(MenuAction.item("Separate Tab from Split View") { _ = separate() })
        } else {
            menu.addItem(MenuAction.item("Open in Split View") { [weak self] in self?.onSplitTab?(tab.id) })
        }
        if !isPrivateBrowsing {
        let group = hierarchyState.flatMap { state in activeSpaceID.flatMap { SidebarSplitItems.groups(in: state, spaceID: $0).first { $0.tabIDs.contains(tab.id) } } }
        let source = group.map { SidebarItemReference.split($0.id) } ?? .tab(tab.id)
        if let state = hierarchyState, let spaceID = activeSpaceID {
            let session = prepareSidebarMove?(source)
            var toggled: [SidebarContainerLocation] = []
            for (title, kind) in [(tab.kind == .pinned ? "Unpin tab" : "Pin tab", tab.kind == .pinned ? TabKind.today : .pinned),
                                  (tab.kind == .favorite ? "Remove from Favorites" : "Add to Favorites", tab.kind == .favorite ? TabKind.today : .favorite)] {
                let target = SidebarContainerLocation(spaceID: spaceID, folderID: nil, section: kind, profileID: kind == .favorite ? tab.profileID : nil)
                let row = MenuAction.item(title) { _ = session?.move(to: target, before: nil) }
                row.isEnabled = session?.canMove(to: target, before: nil) == true; menu.addItem(row)
                toggled.append(target)
            }
            // The rows above already make these moves; listing them again as
            // Move to Pinned Tabs, Today or Favorites doubled them up.
            let moves = moveMenu(for: source, state: state, excluding: toggled)
            for item in moves.items { moves.removeItem(item); menu.addItem(item) }
        }
        }
        if let audio = tabAudio[tab.id] {
            let action = prepareTabMute?(tab, audio)
            let mute = MenuAction.item(audio.muted ? "Unmute" : "Mute") { _ = action?() }
            mute.isEnabled = action != nil; menu.addItem(mute)
        }
        menu.addItem(.separator())
        let copyURL = MenuAction.item("Copy Link") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(tab.url, forType: .string) }
        KeyboardShortcuts.shared.showBinding(on: copyURL, for: "copyCurrentURL:")
        copyURL.isEnabled = !WhatsNewPage.matches(tab.url)
        menu.addItem(copyURL)
        if tab.kind != .today && !InternalPage.isInternal(tab.savedURL) {
            let action = prepareResetTab?(tab)
            let reset = MenuAction.item("Reset Tab to Original URL") { _ = action?() }
            reset.isEnabled = action != nil
            menu.addItem(reset)
        }
        if tab.kind == .favorite {
            let close = prepareFavoriteClose?(tab)
            let item = MenuAction.item("Close Tab") { _ = close?() }
            item.isEnabled = close != nil; menu.addItem(item)
        } else {
            let action = prepareTabClose?(tab)
            let close = MenuAction.item(tab.kind == .today && !isPrivateBrowsing ? "Archive Tab" : "Close Tab") { _ = action?() }
            close.isEnabled = action != nil; menu.addItem(close)
        }
        if tab.kind == .today, let index = todayOrder.firstIndex(of: tab.id) {
            let order = todayOrder
            let groups: [(String, Set<UUID>)] = [
                ("Archive Other Tabs", Set(order.filter { $0 != tab.id })),
                ("Archive Tabs Below", Set(order.dropFirst(index + 1))),
                ("Archive Tabs Above", Set(order.prefix(index)))
            ]
            for (title, ids) in groups {
                let action = MenuAction.item(isPrivateBrowsing ? title.replacingOccurrences(of: "Archive", with: "Close") : title) { [weak self] in self?.onArchiveTabs?(tab, order, ids) }
                action.isEnabled = !ids.isEmpty; menu.addItem(action)
            }
        }
        return menu
    }
    func previewAnchor(for target: SidebarPreviewTarget) -> NSView? { previewAnchors[target] }

    func previewTarget(atWindowPoint point: NSPoint) -> SidebarPreviewTarget? {
        guard !isHiddenOrHasHiddenAncestor, window != nil else { return nil }
        // Use the actual hit target: close/capture buttons must not inherit a
        // containing row's preview just because their rectangles overlap.
        let local = convert(point, from: nil)
        let hitPoint = superview?.convert(point, from: nil) ?? local
        guard bounds.contains(local), let hit = hitTest(hitPoint) else { return nil }
        for (target, view) in previewAnchors {
            if hit === view || (hit.isDescendant(of: view) && !(hit is NSButton)) {
                return view.visibleRect.contains(view.convert(point, from: nil)) ? target : nil
            }
        }
        return nil
    }

    ///
    /// (SidebarTablistBackground): a press drags the window and a double-click
    /// below the last row opens the new-tab command bar through the New Tab
    ///
    /// point shares with its New Tab button.
    override func mouseDown(with event: NSEvent) {
        guard let window, isTablistBackground(event) else { super.mouseDown(with: event); return }
        switch SidebarTablistBackground.press(clickCount: event.clickCount, modifiers: event.modifierFlags) {
        case .passThrough: super.mouseDown(with: event)
        case .waitForRelease: break
        case .dragWindow:
            NotificationCenter.default.post(name: NSWindow.willMoveNotification, object: window)
            window.performDrag(with: event)
        }
    }
    override func mouseUp(with event: NSEvent) {
        if isTablistBackground(event), SidebarTablistBackground.opensCommandBar(
            clickCount: event.clickCount, modifiers: event.modifierFlags,
            y: list.convert(event.locationInWindow, from: nil).y,
            lastRowMaxY: list.rows.last?.frame.maxY) {
            onNewTab?(); return
        }
        super.mouseUp(with: event)
    }
    private func isTablistBackground(_ event: NSEvent) -> Bool {
        guard window != nil, isPresented, !isSpaceManagement, !isHiddenOrHasHiddenAncestor,
              !contentSurface.isHidden, !scroll.isHidden,
              let hit = hitTest(superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow) else { return false }
        return hit === list || hit === scroll.contentView || hit === scroll
    }

    private func showPlusMenu() {
        let rows = SidebarPlusMenuModel.rows(
            privateBrowsing: isPrivateBrowsing,
            canCreateEasel: plusMenuCanCreateEasel(),
            canCreateNote: plusMenuCanCreateNote(),
            canSplit: plusMenuCanSplit()
        ) { KeyboardShortcuts.shared.activeShortcut(for: $0)?.display ?? "" }
        plusMenu.toggle(from: footerMore, rows: rows) { [weak self] action in
            guard let self else { return }
            switch action {
            case .space: self.onNewSpace?()
            case .folder: self.onNewFolder?()
            case .easel: self.onNewEasel?()
            case .note: self.onNewNote?()
            case .split: self.onNewSplit?()
            case .tab: self.onNewTab?()
            }
        }
    }

    func updateDownloadActivity(_ items: [BrowserDownload], profiles: Set<UUID>, enabled: Bool) {
        //
        // lists the downloads only where this window can (SidebarLibraryEntry.swift).
        libraryDownloadsEnabled = enabled
        libraryEntry.updateFlyoutDownloads(items, profiles: profiles, privateWindow: isPrivateBrowsing,
                                           badging: enabled && !libraryEntry.isHidden)
        updateLibraryEntryExpansion()
    }
    ///
    /// Library page, tab switcher or command bar over it (BrowserWindowController
    /// records the window-source Peek condition Parc has no counterpart for).
    var libraryEntryExpansionAllowed = true { didSet { updateLibraryEntryExpansion() } }
    private var libraryDownloadsEnabled = false
    private func updateLibraryEntryExpansion() {
        libraryEntry.canExpand = libraryDownloadsEnabled && !libraryEntry.isHidden && libraryEntryExpansionAllowed
    }
    /// The flyout's captures: the active profile's capture library (nil in a
    /// private window).
    func updateLibraryCaptures(_ store: CaptureLibraryStore?) { libraryEntry.captureStore = store }
    func updateLibraryFlyoutFiles(_ files: [LibraryFlyoutFile]) { libraryEntry.updateFlyoutFiles(files) }
    /// `onDidOpenArcHome`: any route opening the Library reads the entry's unread item.
    func libraryDidOpen() { libraryEntry.libraryDidOpen() }
    /// `onDidCloseArcHome` for the flyout's 100 ms hover guard.
    func libraryDidClose() { libraryEntry.libraryDidClose() }
    ///
    ///
    ///
    private let libraryFlyoutMask = LibraryFlyoutContentMask()
    private var libraryFlyoutMaskGeneration = 0
    private func updateLibraryFlyoutMask(_ expanded: Bool, count: Int) {
        libraryFlyoutMaskGeneration &+= 1
        let total = LibraryEntryLayout.totalHeight(count: count)
        if expanded {
            libraryFlyoutMask.expand(on: contentSurface, totalHeight: total, dockHeight: SidebarChromeLayout.dockHeight)
            return
        }
        let token = libraryFlyoutMaskGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + LibraryFlyoutContentMask.duration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.libraryFlyoutMaskGeneration == token else { return }
                self.libraryFlyoutMask.collapse(totalHeight: total, dockHeight: SidebarChromeLayout.dockHeight)
            }
        }
    }

    private func applyPalette() {
        // Theme content appearance also reaches native semantic text, fields
        // and control materials. The separate ThemeRendererView keeps the
        // backing material on the original window's appearance.
        appearance = palette?.contentAppearance
        libraryEntry.badge.colors = DownloadBadgeColors(foreground: palette?.foregroundPrimary ?? .labelColor,
            maxContrast: palette?.maxContrastColor ?? .labelColor, cutout: palette?.cutoutColor ?? .windowBackgroundColor)
        miniPlayers.palette = palette
        guard let palette else { return }
        archiveEducation.applyPalette(palette)
        updateComplete.applyPalette(palette)
        updateReady.applyPalette(palette)
        // Inferred: the dim alpha and overlay colour follow the theme's
        // darkness rather than the window's appearance.
        windowButtons.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
        // The entry's GrayA colours and Dark Aqua beam follow the same scheme (inferred).
        libraryEntry.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
        for button in [back, forward, reload, reloadOptions, toggle, pageActions, paymentAction, addressButton] as [NSButton] {
            button.contentTintColor = palette.title
        }
        let plusColors = TranslucentButtonColors.standard(dark: palette.isDark)
        if plusButton.colors != plusColors { plusButton.colors = plusColors }
        addressBackground.dark = palette.isDark
        applyAddressPillStyle()
        setAddressTitle(addressText)
        applyPagePalette(shownPage, palette)
        refreshItemSelection()
        keyboardHighlight.color = palette.maxContrastColor
        creationView?.palette = palette
        //
        //
        dropFeedback.tint = palette.maxContrastColor
        for button in favorites {
            button.applyPalette(isDark: palette.isDark, glyphColor: palette.title, highlightColor: palette.maxContrastColor)
        }
        favoritesEmptyState.applyPalette(isDark: palette.isDark, title: palette.title, maxContrast: palette.maxContrastColor,
                                         minContrast: palette.minContrastColor, backgroundExtra: palette.backgroundExtra)
        spacesHost.dark = palette.isDark
        //
        //
        // ForegroundSecondary without one. Reading +0x70 as maxContrastColor
        //
        spacesHost.activeTints = spaces.map { space in
            guard space.theme.primaryColor != nil, space.theme.isValid else { return nil }
            return ThemeChromePalette(theme: space.theme, appearance: window?.effectiveAppearance ?? effectiveAppearance).maxContrastColor
        }
    }
    private var selectionOrder: [SidebarItemReference] {
        guard let state = hierarchyState, let spaceID = activeSpaceID else { return [] }
        // Items still in the Space's hierarchy, found in one pass rather than
        // looking each one up.
        let present = Set(SidebarHierarchy.childrenByContainer(spaceID: spaceID, state: state).values.joined())
        return shownPage.items.filter(present.contains)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Out of a window, nothing is left to prepare for.
        if window == nil {
            neighborPreparation?.invalidate(); neighborPreparation = nil; pendingPreparation = []
            for page in pages.values where page.pendingBuild != nil {
                page.pendingBuild = nil; page.key = nil; page.laidOut = false; page.checkedGeneration = -1
            }
        }
        watchMemoryPressure(window != nil)
        needsLayout = true
        observeFirstResponder()
        if let selectionWindowObserver { NotificationCenter.default.removeObserver(selectionWindowObserver) }
        selectionWindowObserver = nil
        selectionSheetCommand = nil
        clearItemSelection()
        if let clearKeyObserver { NotificationCenter.default.removeObserver(clearKeyObserver) }
        clearKeyObserver = nil
        if let window {
            clearKeyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshClearAvailability() }
            }
            selectionWindowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // Only the exact admitted command may retain its original
                    // multi-set while its own sheet takes key focus.
                    if self.selectionSheetCommand != nil, self.window?.attachedSheet != nil { return }
                    self.clearItemSelection()
                }
            }
        }
    }
    private var ownsSelectionFocus: Bool {
        guard let window, window.isKeyWindow, window.firstResponder === self,
              isPresented, !isHiddenOrHasHiddenAncestor, window.attachedSheet == nil,
              let state = hierarchyState, let expected = selectionContext,
              SidebarHierarchySnapshot(state: state, spaceID: expected.spaceID, profileID: expected.profileID) == expected else { return false }
        return canSelectItems?() == true
    }
    /// A captured destructive command remains bound to the original multi-set
    /// even while its own confirmation or beforeunload sheet owns key focus.
    func hasItemSelection(_ items: [SidebarItemReference]) -> Bool {
        guard itemSelection.items == items, !items.isEmpty, let state = hierarchyState,
              let expected = selectionContext, window != nil else { return false }
        return SidebarHierarchySnapshot(state: state, spaceID: expected.spaceID, profileID: expected.profileID) == expected
    }

    func itemSelectionValidator(_ items: [SidebarItemReference]) -> (() -> Bool)? {
        guard hasItemSelection(items) else { return nil }
        let revision = selectionRevision
        return { [weak self] in
            guard let self else { return false }
            return self.selectionRevision == revision && self.hasItemSelection(items)
        }
    }
    func retainItemSelectionForSheet(_ items: [SidebarItemReference]) -> (() -> Void)? {
        guard selectionSheetCommand == nil, hasItemSelection(items) else { return nil }
        let token = UUID(); selectionSheetCommand = token
        return { [weak self] in
            guard self?.selectionSheetCommand == token else { return }
            self?.selectionSheetCommand = nil
        }
    }

    var hasCommandSelection: Bool { ownsSelectionFocus && itemSelection.items.count > 1 }

    /// Capture before a child command panel takes key focus and clears the
    /// sidebar's transient selection. Nil means use the active-item fallback;
    /// a nonempty unsupported collection must never become that fallback.
    func commandBarSelectionItems() -> [SidebarItemReference]? {
        guard ownsSelectionFocus, !itemSelection.items.isEmpty else { return nil }
        return itemSelection.items
    }


    func prepareSelectionCommand(_ kind: SidebarSelectionCommandKind) -> SidebarSelectionCommandTarget? {
        guard hasCommandSelection, let state = hierarchyState, let spaceID = activeSpaceID,
              let lease = prepareSidebarMoves?(itemSelection.items) else { return nil }
        let items = itemSelection.items, expected = selectionContext
        let action: (() -> Bool)?
        let title: String
        switch kind {
        case .copyLinks: title = "Copy URLs"; action = prepareSidebarCopy?(items, .plain)
        case .copyMarkdown: title = "Copy URLs as Markdown"; action = prepareSidebarCopy?(items, .markdown)
        case .close:
            let ids = Set(items.flatMap { SidebarHierarchy.tabIDs(in: $0, state: state, spaceID: spaceID) })
            title = !isPrivateBrowsing && !ids.isEmpty && state.tabs.filter { ids.contains($0.id) }.allSatisfy { $0.kind == .today }
                ? "Archive Tabs" : "Close Tabs"
            action = prepareSidebarClose?(items)
        case .newFolder:
            // The main menu's New Folder… reads "New Folder from Selection…"
            //
            title = "New Folder from Selection…"; action = prepareFolderFromSelection?(items)
        }
        guard let action else { return nil }
        return SidebarSelectionCommandTarget(kind: kind, title: title, validate: { [weak self] in
            guard let self else { return false }
            return self.hasCommandSelection && self.itemSelection.items == items && self.selectionContext == expected && lease.isValid
        }, execute: action)
    }
    @objc override func selectAll(_ sender: Any?) {
        guard ownsSelectionFocus else { return }
        itemSelection.selectAll(order: selectionOrder, active: selectionActive)
        if activateSingleSelection() { return }
        refreshItemSelection()
    }
    @objc func copy(_ sender: Any?) {
        _ = prepareSelectionCommand(.copyLinks)?.perform()
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(selectAll(_:)) { return ownsSelectionFocus && !selectionOrder.isEmpty }
        if item.action == #selector(delete(_:)) {
            if case .folder = itemSelection.singleItem { return ownsSelectionFocus && !isPrivateBrowsing }
            return false
        }
        if item.action == #selector(copy(_:)) {
            return prepareSelectionCommand(.copyLinks) != nil
        }
        return false
    }
    private func clearItemSelection() { itemSelection.clear(); refreshItemSelection() }
    /// A row being renamed, dragged or sprung open keeps its view while far
    /// from the visible area.
    private func keepsRowView(_ item: SidebarItemReference) -> Bool {
        if item == revealedItem { return true }
        switch item {
        case .tab(let id): return titleEdit?.tab.id == id || keyDraggedTabID == id
        case .split(let id):
            return splitTitleEdit?.target.group.id == id || keyDraggedSplitID == id
                || titleEdit.map { shownPage.item(showing: $0.tab.id) == item } == true
        case .folder(let id): return folderTitleEdit?.folder.id == id || springFolder?.id == id
        }
    }
    /// The split cell keeps its key-dragged fill across row rebuilds until its
    /// drag ends, as ordinary rows do (TAB19).
    private func setKeyDraggedSplit(_ id: UUID, _ dragging: Bool) {
        if dragging { keyDraggedSplitID = id } else if keyDraggedSplitID == id { keyDraggedSplitID = nil }
        shownPage.splitRow(id)?.keyDragged = dragging
    }
    /// `listFocused` is passed while first responder changes, before the window
    /// reports it.
    private func refreshItemSelection(listFocused: Bool? = nil) {
        let listFocused = listFocused ?? (window?.firstResponder === self)
        for (item, view) in hierarchyRows { applySelectionMarks(item, view, listFocused: listFocused) }
        list.select(itemSelection.items, single: itemSelection.singleItem, active: selectionActive)
    }
    /// One built row's multi-selection fill and list-stop focus ring.
    private func applySelectionMarks(_ item: SidebarItemReference, _ view: NSView, listFocused: Bool) {
        let selected = itemSelection.items.contains(item)
        view.setAccessibilitySelected(selected)
        let focused = listFocused && itemSelection.focus == item
        if let row = view as? SidebarTabRow {
            // Multi-selection is TabCellBackgroundMutiselected. List-stop
            // focus uses HighlightRingView; a 1-point accent border on this
            // layer rounded the row and clipped the current-item shadow.
            if row.multiSelected != selected { row.multiSelected = selected }
            if row.listFocusRing != focused { row.listFocusRing = focused }
            return
        }
        if let group = view as? SidebarSplitGroupView {
            group.multiSelected = selected
            group.listFocusRing = focused
            return
        }
        if let folder = view as? SidebarFolderRow {
            // A folder's ListHeaderCellView has the same CellSelectionStateView.
            folder.multiSelected = selected
            folder.listFocusRing = focused
            return
        }
        view.wantsLayer = true
        view.layer?.borderWidth = selected ? 2 : (focused ? 1 : 0)
        view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(selected ? 0.8 : 0.4).cgColor(in: view.effectiveAppearance)
        view.layer?.cornerRadius = 7
    }
    private func selectItem(_ item: SidebarItemReference, event: NSEvent) -> Bool {
        guard window?.isKeyWindow == true, selectionOrder.contains(item) else { return false }
        //
        // modifier that authorizes changing the ordered multi-selection.
        if event.modifierFlags.contains(.option) { return !itemSelection.items.isEmpty }
        let extend = event.modifierFlags.contains(.shift), toggle = event.modifierFlags.contains(.command)
        guard extend || toggle else { clearItemSelection(); return false }
        itemSelection.select(item, order: selectionOrder, active: selectionActive, extending: extend, toggling: toggle)
        if activateSingleSelection() { return true }
        focusSelectionList()
        return true
    }
    /// The list stop takes focus for its selection commands only while the
    /// sidebar is presented (`focusIfPresented`), so an accessibility action on
    /// an off-screen row changes only the selection.
    private func focusSelectionList() { focusIfPresented(); refreshItemSelection() }
    private func activateSingleSelection() -> Bool {
        //
        // normal activation, separately from the ordered multi-set.
        guard let single = itemSelection.singleItem, single != selectionActive else { return false }
        switch single {
        case .tab(let id): clearItemSelection(); onSelectTab?(id); return true
        case .split(let id):
            guard let first = hierarchyState?.splitLayouts.first(where: { $0.id == id })?.tabIDs.first else { return false }
            clearItemSelection(); onSelectTab?(first); return true
        case .folder: return false
        }
    }
    private func beginSelectedMove(_ item: SidebarItemReference) -> SidebarMoveSession? {
        if itemSelection.items.contains(item), itemSelection.items.count > 1 { return prepareSidebarMoves?(itemSelection.items) }
        clearItemSelection()
        return prepareSidebarMove?(item)
    }
    private func selectedItemsMenu(for item: SidebarItemReference) -> NSMenu? {
        guard itemSelection.items.contains(item), itemSelection.items.count > 1, let state = hierarchyState else { return nil }
        let items = itemSelection.items
        let menu = NSMenu(); menu.autoenablesItems = false
        let heading = NSMenuItem(title: "\(items.count) Selected Items", action: nil, keyEquivalent: "")
        heading.isEnabled = false; menu.addItem(heading)
        if let session = prepareSidebarMoves?(items) {
            let copy = prepareSelectionCommand(.copyLinks)
            let copyItem = MenuAction.item("Copy Links") { _ = copy?.perform() }
            copyItem.isEnabled = copy != nil; menu.addItem(copyItem)
            menu.addItem(.separator())
            var destinations = Set<String>()
            // This menu offers only Move to rows, so it keeps Move to Pinned Tabs.
            let options = items.flatMap { moveOptions(for: $0, state: state, keepsPinnedRoot: true) }.filter {
                $0.2 == nil && $0.0.hasPrefix("Move to ") && destinations.insert($0.1.key).inserted
            }
            for (title, destination, before) in options where session.canMove(to: destination, before: before) {
                menu.addItem(MenuAction.item(title) { [weak self] in
                    guard let self, self.itemSelection.items == items else { return }
                    if session.move(to: destination, before: before) { self.clearItemSelection() }
                })
            }
        }
        if let duplicate = prepareSidebarDuplicate?(items) {
            let duplicateItem = MenuAction.item("Duplicate") { [weak self] in
                guard self?.hasItemSelection(items) == true else { return }
                _ = duplicate()
            }
            KeyboardShortcuts.shared.showBinding(on: duplicateItem, for: "duplicateCurrentItem:")
            menu.addItem(duplicateItem)
        }
        appendSpaceMoves(to: menu, items: items)
        if let close = prepareSidebarClose?(items) {
            menu.addItem(.separator())
            menu.addItem(MenuAction.item("Close Tabs in Selection") { [weak self] in
                guard self?.itemSelection.items == items else { return }
                _ = close()
            })
        }
        if let remove = prepareSidebarDeletion?(items) {
            let hasFolder = items.contains { if case .folder = $0 { return true }; return false }
            menu.addItem(MenuAction.item(hasFolder ? "Delete" : "Archive Tabs") { [weak self] in
                guard self?.hasItemSelection(items) == true else { return }
                _ = remove()
            })
        }
        menu.addItem(.separator())
        menu.addItem(MenuAction.item("Clear Selection") { [weak self] in self?.clearItemSelection() })
        return menu
    }
    /// A hidden sidebar waits unhidden off-screen; its list takes no focus
    /// there, and the window keeps it instead [C].
    override func becomeFirstResponder() -> Bool {
        guard isPresented, super.becomeFirstResponder() else { return false }
        // Tab into the list stop: HighlightRingView marks the active item (or
        // the first), where the arrow keys continue.
        let order = selectionOrder
        if let event = window?.currentEvent, event.type == .keyDown, event.keyCode == 48, itemSelection.focus == nil,
           let item = selectionActive.flatMap({ order.contains($0) ? $0 : nil }) ?? order.first {
            itemSelection.select(item, order: order, active: selectionActive, extending: false, toggling: false)
        }
        refreshItemSelection(listFocused: true)
        return true
    }
    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        refreshItemSelection(listFocused: false)
        return true
    }
    override func cancelOperation(_ sender: Any?) {
        if isSpaceManagement, itemSelection.items.isEmpty, itemSelection.singleItem == nil, itemSelection.focus == nil { onManagementCancel?() }
        else { clearItemSelection() }
    }
    func performFolderDeletion(_ id: UUID, spaceID: UUID) -> Bool {
        guard !isPrivateBrowsing, activeSpaceID == spaceID,
              hierarchyState?.folders.contains(where: { $0.id == id && $0.spaceID == spaceID }) == true else { return false }
        return prepareFolderDeletion?(id)?() == true
    }

    @objc func delete(_ sender: Any?) {
        guard ownsSelectionFocus, case .folder(let id) = itemSelection.singleItem,
              let spaceID = activeSpaceID else { return }
        _ = performFolderDeletion(id, spaceID: spaceID)
    }

    @discardableResult
    func handleFolderDeletionKey(_ event: NSEvent) -> Bool {
        guard window?.isKeyWindow == true, window?.firstResponder === self, isPresented,
              event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty,
              [51, 117].contains(event.keyCode),
              case .folder(let id) = itemSelection.singleItem, let spaceID = activeSpaceID else { return false }
        _ = performFolderDeletion(id, spaceID: spaceID)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard window?.isKeyWindow == true, window?.firstResponder === self else { super.keyDown(with: event); return }
        let flags = event.modifierFlags.intersection([.shift, .control, .option, .command])
        if event.keyCode == 53 { cancelOperation(nil); return }
        // A hidden sidebar's list switches and closes nothing out of sight.
        if !isPresented, [51, 117, 125, 126].contains(event.keyCode) { super.keyDown(with: event); return }
        if flags.subtracting(.shift).isEmpty, [125, 126].contains(event.keyCode) {
            let order = selectionOrder
            guard !order.isEmpty else { return }
            let current = itemSelection.focus ?? selectionActive
            let index = current.flatMap { order.firstIndex(of: $0) } ?? 0
            let next = order[min(order.count - 1, max(0, index + (event.keyCode == 125 ? 1 : -1)))]
            if flags.contains(.shift) {
                itemSelection.select(next, order: order, active: selectionActive, extending: true, toggling: false)
                if activateSingleSelection() { return }
                refreshItemSelection()
            } else {
                clearItemSelection()
                switch next {
                case .tab(let id): onSelectTab?(id)
                case .split(let id): if let first = hierarchyState?.splitLayouts.first(where: { $0.id == id })?.tabIDs.first { onSelectTab?(first) }
                case .folder: itemSelection.select(next, order: order, active: nil, extending: false, toggling: false)
                }
                refreshItemSelection()
            }
            list.scrollRowToVisible(next)
            return
        }
        if flags.isEmpty, [51, 117].contains(event.keyCode) {
            if handleFolderDeletionKey(event) { return }
            if !itemSelection.items.isEmpty {
                _ = prepareSidebarClose?(itemSelection.items)?(); return
            }
        }
        super.keyDown(with: event)
    }

    private func moveOptions(for item: SidebarItemReference, state: BrowserState,
                             keepsPinnedRoot: Bool = false) -> [(String, SidebarContainerLocation, SidebarItemReference?)] {
        guard let spaceID = activeSpaceID,
              let current = SidebarHierarchy.location(of: item, state: state, spaceID: spaceID) else { return [] }
        var result: [(String, SidebarContainerLocation, SidebarItemReference?)] = []
        let siblings = SidebarHierarchy.children(in: current, state: state)
        if let index = siblings.firstIndex(of: item) {
            if index > 0 { result.append((current.section == .favorite ? "Move Earlier" : "Move Up", current, siblings[index - 1])) }
            if index + 1 < siblings.count { result.append((current.section == .favorite ? "Move Later" : "Move Down", current, index + 2 < siblings.count ? siblings[index + 2] : nil)) }
        }
        let outOfFolder = current.folderID.flatMap { parent in state.folders.first { $0.id == parent } }
            .map { SidebarContainerLocation(spaceID: spaceID, folderID: $0.parentID, section: .pinned) }
        if let outOfFolder { result.append(("Move Out of Folder", outOfFolder, nil)) }
        let pinnedRoot = SidebarContainerLocation(spaceID: spaceID, folderID: nil, section: .pinned)
        // Out of a top-level folder is already the pinned root.
        if (current.folderID != nil || current.section != .pinned) && (keepsPinnedRoot || outOfFolder != pinnedRoot) {
            result.append(("Move to Pinned Tabs", pinnedRoot, nil))
        }
        if case .folder = item {} else if current.folderID != nil || current.section != .today {
            result.append(("Move to Today", .init(spaceID: spaceID, folderID: nil, section: .today), nil))
        }
        if case .folder = item {} else if current.section != .favorite {
            let profileID = state.spaces.first { $0.id == spaceID }?.profileID
            result.append(("Move to Favorites", .init(spaceID: spaceID, folderID: nil, section: .favorite, profileID: profileID), nil))
        }
        for folder in state.folders where folder.spaceID == spaceID && folder.id != current.folderID {
            var names = [folder.name], parent = folder.parentID, seen: Set<UUID> = [folder.id]
            while let id = parent, seen.insert(id).inserted, let ancestor = state.folders.first(where: { $0.id == id && $0.spaceID == spaceID }) {
                names.insert(ancestor.name, at: 0); parent = ancestor.parentID
            }
            result.append(("Move to " + names.joined(separator: " / "), .init(spaceID: spaceID, folderID: folder.id, section: .pinned), nil))
        }
        return result
    }
    private func moveMenu(for item: SidebarItemReference, state: BrowserState,
                          excluding duplicates: [SidebarContainerLocation] = []) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        appendSpaceMoves(to: menu, items: [item])
        if let session = prepareSidebarMove?(item) {
            for (title, destination, before) in moveOptions(for: item, state: state)
            where session.canMove(to: destination, before: before) && !(before == nil && duplicates.contains(destination)) {
                menu.addItem(MenuAction.item(title) { _ = session.move(to: destination, before: before) })
            }
        }
        return menu
    }
    private func appendSpaceMoves(to menu: NSMenu, items: [SidebarItemReference]) {
        guard !isPrivateBrowsing, let state = hierarchyState, let sourceID = activeSpaceID,
              state.spaces.contains(where: { $0.id == sourceID }),
              SidebarHierarchy.roots(items, state: state, spaceID: sourceID) != nil else { return }
        let submenu = NSMenu(); submenu.autoenablesItems = false
        //
        for space in spaces {
            let action = prepareSidebarSpaceMove?(items, space.id)
            let row = MenuAction.item(space.name) { [weak self] in
                guard let self else { return }
                if items.count > 1 && self.itemSelection.items != items { return }
                if action?() == true { self.clearItemSelection() }
            }
            row.state = space.id == sourceID ? .on : .off
            row.isEnabled = space.id != sourceID && action != nil
            submenu.addItem(row)
        }
        submenu.addItem(.separator())
        let create = prepareSidebarNewSpace?(items)
        let newSpace = MenuAction.item("New Space…") { [weak self] in
            guard let self, items.count <= 1 || self.itemSelection.items == items else { return }
            if create?() == true { self.clearItemSelection() }
        }
        newSpace.isEnabled = create != nil; submenu.addItem(newSpace)
        let row = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
        row.submenu = submenu; menu.addItem(row)
    }

    /// A folder row's context menu, built when it opens from the current
    /// hierarchy.
    private func folderMenu(_ id: UUID) -> NSMenu? {
        guard let state = hierarchyState, let folder = state.folders.first(where: { $0.id == id && $0.spaceID == activeSpaceID }) else { return nil }
        //
        // Turn “name” into Space and Copy All Links, then Change Icon…
        // and Rename…, then Duplicate and the
        //
        // service) is excluded; Preview folder is Parc's keyboard entry
        // to the folder preview.
        let menu = NSMenu(); menu.autoenablesItems = false
        let previewItem = MenuAction.item("Preview folder") { [weak self] in self?.onPreview?(.folder(folder.id)) }
        previewItem.isEnabled = SidebarPreviewPreference.folders.isEnabled
        menu.addItem(previewItem)
        menu.addItem(.separator())
        let newSubfolder = MenuAction.item("New Nested Folder…") { [weak self] in self?.onNewSubfolder?(folder.id) }
        KeyboardShortcuts.shared.showBinding(on: newSubfolder, for: "createFolder:")
        menu.addItem(newSubfolder)
        //
        let turnIntoSpace = prepareTurnFolderIntoSpace?(folder.id)
        let folderName = folder.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : folder.name
        let spaceItem = MenuAction.item("Turn “\(folderName)” into Space") { if turnIntoSpace?() != true { NSSound.beep() } }
        spaceItem.isEnabled = turnIntoSpace != nil
        menu.addItem(spaceItem)
        if let space = state.spaces.first(where: { $0.id == folder.spaceID }) {
            let target = FolderLinkTarget(folderID: folder.id, spaceID: space.id, profileID: space.profileID)
            let hasLinks = !(FolderLinks.links(in: state, target: target)?.isEmpty ?? true)
            let copy = MenuAction.item("Copy All Links") { [weak self] in
                self?.onCopyFolderLinks?(target, .plain)
            }
            copy.isEnabled = hasLinks
            copy.keyEquivalentModifierMask = []
            menu.addItem(copy)
            //
            // action target and changes only the requested format.
            let markdown = MenuAction.item("Copy All Links as Markdown") { [weak self] in
                self?.onCopyFolderLinks?(target, .markdown)
            }
            markdown.isEnabled = hasLinks
            markdown.isAlternate = true
            markdown.keyEquivalentModifierMask = [.option]
            menu.addItem(markdown)
        }
        menu.addItem(.separator())
        let changeIcon = prepareFolderIcon?(folder)
        let icon = MenuAction.item("Change Icon…") { if changeIcon?() != true { NSSound.beep() } }
        icon.isEnabled = changeIcon != nil
        menu.addItem(icon)
        //
        let renameFolder = MenuAction.item("Rename…") { [weak self] in
            guard let self, !self.beginFolderTitleEditing(folder.id) else { return }
            self.onRenameFolder?(folder.id)
        }
        KeyboardShortcuts.shared.showBinding(on: renameFolder, for: "renameCurrentItem:")
        menu.addItem(renameFolder)
        menu.addItem(.separator())
        let duplicateFolder = prepareFolderDuplicate?(folder.id)
        let duplicate = MenuAction.item("Duplicate") {
            if duplicateFolder?() != true { NSSound.beep() }
        }
        KeyboardShortcuts.shared.showBinding(on: duplicate, for: "duplicateCurrentItem:")
        duplicate.isEnabled = duplicateFolder != nil
        menu.addItem(duplicate)
        let move = moveMenu(for: .folder(folder.id), state: state)
        for item in move.items { move.removeItem(item); menu.addItem(item) }
        menu.addItem(.separator())
        // Rows survive live metadata updates. Capture the folder identity,
        // then prepare consent/retirement against current owners on press.
        let deleteFolder: () -> Bool = { [weak self] in
            self?.performFolderDeletion(folder.id, spaceID: folder.spaceID) == true
        }
        let delete = MenuAction.item("Delete") {
            if !deleteFolder() { NSSound.beep() }
        }
        delete.isEnabled = !isPrivateBrowsing && prepareFolderDeletion != nil
        menu.addItem(delete)
        return menu
    }
    /// A folder row's Duplicate and Delete Folder actions, prepared when asked for.
    private func folderAccessibilityActions(_ id: UUID) -> [NSAccessibilityCustomAction] {
        guard !isSpaceManagement, let folder = hierarchyState?.folders.first(where: { $0.id == id && $0.spaceID == activeSpaceID }) else { return [] }
        var actions: [NSAccessibilityCustomAction] = []
        if let duplicateFolder = prepareFolderDuplicate?(id) {
            actions.append(NSAccessibilityCustomAction(name: "Duplicate") { duplicateFolder() })
        }
        if !isPrivateBrowsing && prepareFolderDeletion != nil {
            actions.append(NSAccessibilityCustomAction(name: "Delete Folder") { [weak self] in
                self?.performFolderDeletion(id, spaceID: folder.spaceID) == true
            })
        }
        return actions
    }
    private func addMoveAccessibility(to view: SidebarDeferredAccessibilityActions, item: SidebarItemReference) {
        // AX alternatives use the same original-item transaction. They do not
        // synthesize drag events or silently move an individual split child.
        view.deferAccessibilityActions { [weak self] in self?.moveAccessibilityActions(item: item) ?? [] }
    }
    private func moveAccessibilityActions(item: SidebarItemReference) -> [NSAccessibilityCustomAction] {
        guard let state = hierarchyState else { return [] }
        let actions = moveOptions(for: item, state: state).compactMap { title, destination, before -> NSAccessibilityCustomAction? in
            guard let session = prepareSidebarMove?(item), session.canMove(to: destination, before: before) else { return nil }
            return NSAccessibilityCustomAction(name: title) { session.move(to: destination, before: before) }
        }
        let spaceActions = spaces.compactMap { space -> NSAccessibilityCustomAction? in
            guard let action = prepareSidebarSpaceMove?([item], space.id) else { return nil }
            return NSAccessibilityCustomAction(name: "Move to " + space.name, handler: action)
        }
        let create = prepareSidebarNewSpace?([item]).map { action in
            NSAccessibilityCustomAction(name: "Move to New Space", handler: action)
        }
        return actions + spaceActions + (create.map { [$0] } ?? [])
    }

    private func dragSession(_ sender: NSDraggingInfo) -> SidebarMoveSession? {
        // A row rebuilt during the drag (a folder springing open) detaches
        // its source; the session it holds and the pasteboard identity stay
        // the drag's authority.
        guard let source = sender.draggingSource as? NSView,
              let authority = sender.draggingSource as? SidebarItemDragSource,
              let session = authority.sidebarDrag, session.window != nil,
              source.window.map({ $0 === session.window }) ?? true,
              sender.draggingPasteboard.string(forType: SidebarMoveSession.pasteboardType) == session.identifier.uuidString,
              (session.window === window ? session.isValid : session.isValidForWindowTransfer) else { return nil }
        return session
    }
    private let reorderFeedback = SidebarReorderingFeedback()
    /// An empty tray's drop target runs to the outline: its empty state, or
    /// once that is dismissed the header's 5-point bottom inset; the pinned
    /// header below it belongs to the pinned section. A shown Space header
    ///
    /// drop target (`headerOrDockDrop`).
    private var favoritesDropFrame: NSRect {
        // A Library Space card shows no Profile-wide Favorites tray.
        guard !isSpaceManagement else { return .zero }
        guard favorites.isEmpty else { return favoritesHost.frame }
        let top = favoritesHost.frame.minY
        let end = spaceHeader.isHidden ? scroll.frame.minY : spaceHeader.frame.minY
        return NSRect(x: 0, y: top, width: bounds.width, height: max(0, end - top))
    }
    private func clearDrop() {
        dropProposal = nil; windowDropAction = nil; copyDropAction = nil; dockDropAction = nil; dropFeedback.targetRect = nil
        favoritesEmptyState.showsDrop(false)
    }
    /// Admits a move, or with `copying` the destination window's prepared copy
    ///
    /// Option mask is that copy-only operation).
    private func admitDrop(_ session: SidebarMoveSession, to destination: SidebarContainerLocation,
                           before: SidebarItemReference?, copying: Bool) -> Bool {
        if copying {
            guard session.allowsCopy, let action = prepareCopyDrop?(session, session.items, destination, before) else { return false }
            copyDropAction = action
        } else if session.window === window {
            guard session.canMove(to: destination, before: before) else { return false }
        } else {
            guard let action = prepareWindowDrop?(session, destination, before) else { return false }
            windowDropAction = action
        }
        return true
    }
    /// The Space header and the dock's Space items take sidebar item drags as
    ///
    ///
    ///
    /// `pinnedTabsHeader` accessory, which resolves to index 0 of this Space's
    ///
    ///
    ///
    ///
    /// Pinned list when every item is pinned or a Favorite, otherwise its Today
    ///
    /// neither; [] refuses.
    private func headerOrDockDrop(_ session: SidebarMoveSession, at point: NSPoint, copying: Bool,
                                  state: BrowserState, spaceID: UUID) -> NSDragOperation? {
        if !spaceHeader.isHiddenOrHasHiddenAncestor {
            let header = convert(spaceHeader.bounds, from: spaceHeader)
            if header.contains(point) {
                guard !copying else { return [] }
                let pinned = SidebarContainerLocation(spaceID: spaceID, folderID: nil, section: .pinned)
                let before = SidebarHierarchy.children(in: pinned, state: state).first { !session.items.contains($0) }
                guard admitDrop(session, to: pinned, before: before, copying: false) else { return [] }
                dropProposal = (session, pinned, before)
                dropFeedback.isInsertion = false; dropFeedback.targetRect = header
                return .move
            }
        }
        guard !spacesHost.isHiddenOrHasHiddenAncestor,
              convert(spacesHost.bounds, from: spacesHost).contains(point) else { return nil }
        guard let (target, button) = spaceButtonsByID.first(where: { _, button in
            button.superview != nil && !button.isHidden && convert(button.bounds, from: button).contains(point)
        }) else { return [] }
        func kind(_ item: SidebarItemReference) -> TabKind? {
            switch item {
            case .folder: return .pinned
            case .tab(let id): return state.tabs.first { $0.id == id }?.kind
            case .split(let id):
                return state.splitLayouts.first { $0.id == id }?.tabIDs.first.flatMap { child in state.tabs.first { $0.id == child }?.kind }
            }
        }
        func space(of item: SidebarItemReference) -> UUID? {
            switch item {
            case .folder(let id): return state.folders.first { $0.id == id }?.spaceID
            case .tab(let id): return state.tabs.first { $0.id == id && $0.kind != .favorite }?.spaceID
            case .split(let id):
                return state.splitLayouts.first { $0.id == id }?.tabIDs.first.flatMap { child in
                    state.tabs.first { $0.id == child && $0.kind != .favorite }?.spaceID
                }
            }
        }
        let items = session.items.filter { space(of: $0) != target }
        guard !items.isEmpty else { return [] }
        let section: TabKind = items.allSatisfy { [.pinned, .favorite].contains(kind($0)) } ? .pinned : .today
        let destination = SidebarContainerLocation(spaceID: target, folderID: nil, section: section)
        let top = SidebarHierarchy.children(in: destination, state: state).first { !items.contains($0) }
        if copying {
            guard session.allowsCopy, let action = prepareCopyDrop?(session, items, destination, top) else { return [] }
            copyDropAction = action
        } else {
            guard let action = prepareDockDrop?(session, items, destination, top) else { return [] }
            dockDropAction = action
        }
        dropProposal = (session, destination, top)
        dropFeedback.isInsertion = false; dropFeedback.targetRect = convert(button.bounds, from: button)
        return copying ? .copy : .move
    }
    private func updateDrop(_ sender: NSDraggingInfo) -> NSDragOperation {
        springCandidate = nil
        let operation = proposeDrop(sender)
        updateSpringLoading(operation.isEmpty ? nil : springCandidate)
        return operation
    }
    /// The collapsed folder the current drop lands on.
    private var springCandidate: UUID?
    private var springFolder: (id: UUID, timer: Timer)?
    /// Folders this drag sprang open, in order.
    private var sprungFolders: [UUID] = []
    /// NSOutlineView springs a collapsed item open under a drag that rests on
    ///
    /// only `shouldCollapseAutoExpandedItemsForDeposited:`). The delay is the
    /// system spring-loading delay, 0.5 seconds unless the user changed it.
    ///
    /// folders open and a drag that leaves or ends without one closes them.
    private static var springLoadingDelay: TimeInterval {
        (UserDefaults.standard.object(forKey: "com.apple.springing.delay") as? NSNumber)?.doubleValue ?? 0.5
    }
    private func updateSpringLoading(_ id: UUID?) {
        guard springFolder?.id != id else { return }
        if let previous = springFolder { previous.timer.invalidate(); shownPage.folderRow(previous.id)?.dropTarget = false }
        springFolder = nil
        guard let id else { return }
        shownPage.folderRow(id)?.dropTarget = true
        let timer = Timer(timeInterval: Self.springLoadingDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.springFolder?.id == id else { return }
                self.springFolder = nil
                self.shownPage.folderRow(id)?.dropTarget = false
                guard self.hierarchyState?.folders.first(where: { $0.id == id })?.isExpanded == false else { return }
                self.onToggleFolder?(id)
                self.sprungFolders.append(id)
            }
        }
        // A drag runs the event-tracking run-loop mode.
        RunLoop.main.add(timer, forMode: .common)
        springFolder = (id, timer)
    }
    private func proposeDrop(_ sender: NSDraggingInfo) -> NSDragOperation {
        clearDrop()
        guard creationView == nil else { return [] }
        guard let session = dragSession(sender), let state = hierarchyState, let spaceID = activeSpaceID else { return [] }
        //
        //
        let mask = sender.draggingSourceOperationMask, option = NSEvent.modifierFlags.contains(.option)
        let copying = mask.contains(.copy) && option
        // Option never becomes a move: a move-only source (a single Favorite
        // whose tile ignores modifiers) is refused while Option is held.
        guard !option || copying else { return [] }
        let operation: NSDragOperation = copying ? .copy : .move
        let point = convert(sender.draggingLocation, from: nil)
        let tray = favoritesDropFrame
        if !isPrivateBrowsing, tray.contains(point),
           let profileID = state.spaces.first(where: { $0.id == spaceID })?.profileID {
            let destination = SidebarContainerLocation(spaceID: spaceID, folderID: nil, section: .favorite, profileID: profileID)
            var before: SidebarItemReference?
            var feedback = NSRect(x: tray.minX, y: tray.minY + 2, width: 2, height: max(14, tray.height - 4))
            for (index, tile) in favorites.enumerated() {
                let rect = convert(tile.bounds, from: tile)
                if point.y < rect.minY || (point.y <= rect.maxY && point.x < rect.midX) {
                    before = favoriteItems[index]
                    feedback = NSRect(x: rect.minX - 4, y: rect.minY, width: 2, height: rect.height); break
                }
                feedback = NSRect(x: rect.maxX + 4, y: rect.minY, width: 2, height: rect.height)
            }
            guard admitDrop(session, to: destination, before: before, copying: copying) else { return [] }
            dropProposal = (session, destination, before)
            // The outline's insertion-index haptic is not attributed to AppTray.
            // A shown empty state draws its dragging style in place of a cue.
            dropFeedback.isInsertion = true; dropFeedback.targetRect = favoritesEmptyState.showsDrop(true) ? nil : feedback
            return operation
        }
        if let target = headerOrDockDrop(session, at: point, copying: copying, state: state, spaceID: spaceID) {
            return target
        }
        guard scroll.frame.contains(point) else { return [] }
        let clip = scroll.contentView
        let offset: CGFloat = point.y < scroll.frame.minY + 20 ? -8 : (point.y > scroll.frame.maxY - 20 ? 8 : 0)
        if offset != 0 {
            let y = min(max(0, clip.bounds.origin.y + offset), max(0, list.bounds.height - clip.bounds.height))
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y)); scroll.reflectScrolledClipView(clip)
        }
        var destination: SidebarContainerLocation?
        var before: SidebarItemReference?
        var feedback: NSRect?
        var insertion = true
        var onCollapsedFolder: UUID?
        // A card that lists no divider has no row after its pinned items: the
        // sections meet at the boundary below its last row.
        let listEnd = isSpaceManagement && pinnedEnd == nil
            ? list.rows.last.map { convert($0.frame, from: list).maxY - SidebarChromeLayout.tablistIntercellSpacing / 2 } : nil
        let pinnedBottom = pinnedEnd.map { convert($0.bounds, from: $0).midY } ?? listEnd ?? scroll.frame.minY
        let todayTop = todayStart.map { convert($0.bounds, from: $0).midY } ?? listEnd ?? scroll.frame.maxY
        // Insertion cues sit on the outline's row boundary, in the intercell
        // gap between two visible rows, so each index has one position; the
        // pinned section ends at the boundary above the divider cell.
        let outset = SidebarChromeLayout.tablistRowBoundaryOutset
        let pinnedEndBoundary = pinnedEnd.map {
            convert($0.bounds, from: $0).minY - ($0 is SidebarNewTabRow ? outset : SidebarChromeLayout.tablistIntercellSpacing / 2)
        } ?? listEnd
        // Rows are placed by the list whether or not their views exist; only
        // rows reaching the pointer have their items looked up.
        let items = shownPage.items
        let listY = list.convert(point, from: self).y
        for (index, item) in items.enumerated() {
            guard let frame = list.itemFrame(for: item), listY <= frame.maxY else { continue }
            let rect = convert(frame, from: list)
            guard point.y <= rect.maxY, let location = SidebarHierarchy.location(of: item, state: state, spaceID: spaceID),
                  (point.y <= pinnedBottom ? location.section == .pinned : (point.y >= todayTop && location.section == .today)) else { continue }
            if point.y < rect.minY {
                destination = location; before = item
                feedback = NSRect(x: rect.minX, y: rect.minY - outset - 1, width: rect.width, height: 2)
                break
            }
            if case .folder(let id) = item, point.y > rect.minY + rect.height * 0.25, point.y < rect.maxY - rect.height * 0.25 {
                let folder = SidebarContainerLocation(spaceID: spaceID, folderID: id, section: .pinned)
                destination = folder
                //
                //
                before = SidebarHierarchy.children(in: folder, state: state).first { !session.items.contains($0) }
                feedback = rect; insertion = false
                if state.folders.first(where: { $0.id == id })?.isExpanded == false { onCollapsedFolder = id }
            } else {
                destination = location
                let preceding = point.y < rect.midY
                if preceding { before = item }
                else {
                    let siblings = SidebarHierarchy.children(in: location, state: state)
                    if let index = siblings.firstIndex(of: item), index + 1 < siblings.count { before = siblings[index + 1] }
                }
                var boundary = preceding ? rect.minY - outset : rect.maxY + outset
                if !preceding, case .folder(let folderID) = item {
                    // After a folder means after its whole visible subtree,
                    // the rows that follow it in the list. The insertion cue
                    // must not imply an insert into it.
                    subtree: for child in items[(index + 1)...] {
                        guard let childFrame = list.itemFrame(for: child) else { continue }
                        var ancestor = SidebarHierarchy.location(of: child, state: state, spaceID: spaceID)?.folderID
                        var seen = Set<UUID>()
                        while let id = ancestor, seen.insert(id).inserted {
                            if id == folderID { boundary = max(boundary, convert(childFrame, from: list).maxY + outset); continue subtree }
                            ancestor = state.folders.first { $0.id == id }?.parentID
                        }
                        break
                    }
                }
                feedback = NSRect(x: rect.minX, y: boundary - 1, width: rect.width, height: 2)
            }
            break
        }
        if destination == nil {
            if point.y <= pinnedBottom {
                destination = .init(spaceID: spaceID, folderID: nil, section: .pinned)
                feedback = NSRect(x: scroll.frame.minX + 5, y: pinnedEndBoundary.map { $0 - 1 } ?? min(point.y, pinnedBottom),
                                  width: scroll.frame.width - 10, height: 2)
            } else if point.y >= todayTop {
                destination = .init(spaceID: spaceID, folderID: nil, section: .today)
                feedback = NSRect(x: scroll.frame.minX + 5, y: point.y, width: scroll.frame.width - 10, height: 2)
            }
        }
        guard let destination, let feedback else { return [] }
        guard admitDrop(session, to: destination, before: before, copying: copying) else { return [] }
        dropProposal = (session, destination, before)
        // NSOutlineView reports a child index, with -1 for an on-item drop.
        // Feedback follows that index, not pointer position, row identity or
        // repeated drag-validation callbacks. Menus/AX moves do not emit it.
        let siblings = SidebarHierarchy.children(in: destination, state: state)
        let index = insertion ? before.flatMap { siblings.firstIndex(of: $0) } ?? siblings.count : -1
        reorderFeedback.propose(index: index)
        dropFeedback.isInsertion = insertion; dropFeedback.targetRect = feedback.intersection(scroll.frame)
        springCandidate = onCollapsedFolder
        return operation
    }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrop(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrop(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { clearDrop(); updateSpringLoading(nil); collapseSprungFolders() }
    override func draggingEnded(_ sender: NSDraggingInfo) { clearDrop(); updateSpringLoading(nil); collapseSprungFolders() }
    private func collapseSprungFolders() {
        let sprung = sprungFolders; sprungFolders = []
        for id in sprung.reversed() where hierarchyState?.folders.first(where: { $0.id == id })?.isExpanded == true {
            onToggleFolder?(id)
        }
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !updateDrop(sender).isEmpty }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !updateDrop(sender).isEmpty, let (session, destination, before) = dropProposal else { return false }
        let external = windowDropAction, copy = copyDropAction, dock = dockDropAction
        clearDrop(); updateSpringLoading(nil); sprungFolders = []
        if let copy { return session.copy(copy) }
        if let dock { return session.transferThenEnd(dock) }
        if let external { return session.moveToAnotherWindow(external) }
        return session.move(to: destination, before: before)
    }

}

/// Outline row keys of the list's own rows; items use their SidebarItemReference.
private enum SidebarListRow: Hashable { case pinnedHeader, divider, heading, newTab }

/// A keyboard cursor is neither native focus nor the sidebar's multi-selection.
/// Drawing above the original row avoids overwriting either owner's appearance.
///
/// function or notification, so the cursor posts nothing here either.
private final class SidebarKeyboardHighlightView: NSView {
    ///
    /// continuous 12-point corners in the palette's maxContrastColor, the ring
    /// tab rows draw for the same cursor (SidebarRowAppearance), not the
    /// system focus colour.
    var color: NSColor = .labelColor { didSet { needsDisplay = true } }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        guard let layer else { return }
        layer.borderWidth = SidebarRowAppearance.ringWidth
        layer.cornerRadius = SidebarRowAppearance.cornerRadius; layer.cornerCurve = .continuous
        layer.borderColor = color.cgColor
    }
}

/// The Space page container. It takes no hits of its own, so the App Tray,
/// address and header controls beneath it stay reachable; a neighbouring
/// page drawn for paging passes every hit and hides from accessibility.
/// The time since Parc's own last keyboard, pointer or trackpad input.
/// Input to other apps doesn't count, so work Parc does while idle goes on
/// while the user works elsewhere.
@MainActor enum SidebarInputClock {
    private static var lastInput: CFTimeInterval = 0
    private static var monitor: Any?
    static var secondsSinceInput: CFTimeInterval {
        start()
        return CACurrentMediaTime() - lastInput
    }
    /// Counts from now: input before the first sidebar isn't known.
    static func start() {
        if monitor == nil {
            lastInput = CACurrentMediaTime()
            let input: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .rightMouseDown,
                .rightMouseUp, .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                .mouseMoved, .scrollWheel, .gesture, .magnify, .swipe, .rotate, .beginGesture, .endGesture, .smartMagnify, .pressure]
            monitor = NSEvent.addLocalMonitorForEvents(matching: input) { event in
                lastInput = CACurrentMediaTime()
                return event
            }
        }
    }
}

/// One Space's sidebar page: its header and tablist, laid out in its own
///
/// per Space (`spaceViewControllerCache`, collectionView(_:willDisplay:…) at
///
/// views as they were, with their scroll position. Every lookup of a row's
/// view by item goes through this page.
@MainActor final class SidebarSpacePage {
    let view = SidebarPageStripView()
    let header = SidebarSpaceHeaderView()
    let scroll = SidebarPagingScrollView()
    /// The list's flipped document view.
    let listHost = SidebarListHost()
    let list = SidebarOutlineView()
    let newTabRow: SidebarNewTabRow
    var spaceID: UUID?
    /// Every built tab row, a split's children included.
    var tabRows: [SidebarTabRow] = []
    /// Standalone tab rows by tab, kept for the page's next build.
    var keptTabRows: [UUID: SidebarTabRow] = [:]
    /// Folder rows by folder, kept across builds so a disclosure change
    /// animates the row's icon and the row keeps its pointer state.
    var folderRows: [UUID: SidebarFolderRow] = [:]
    /// The items in outline order, whether or not their rows have views.
    private(set) var items: [SidebarItemReference] = []
    private var itemSet: Set<SidebarItemReference> = []
    /// Each Split View's tabs' split, for a child's row.
    private var splitOfTab: [UUID: UUID] = [:]
    private var rowsByItem: [SidebarItemReference: NSView] = [:]
    var previewAnchors: [SidebarPreviewTarget: NSView] = [:]
    /// Settled favicons of tab rows let go, with the page and reset
    /// addresses they showed, for the row built when it comes back.
    fileprivate var releasedFavicons: [UUID: (arm: TabRowFaviconIdentity, art: TabRowSettledFaviconArt)] = [:]
    var speakerHosts: [UUID: SidebarSpeakerHost] = [:]
    weak var pinnedEnd: NSView?
    weak var todayStart: NSView?
    weak var clearButton: ActionButton?
    weak var sectionLine: SidebarHairline?
    weak var privateUnpinnedHeader: SidebarSpaceHeaderView?
    var todayHasTabs = false
    var clearRevealed = false
    var headerContentShown = false
    var renderedDisclosure: (expanded: [UUID: Bool], peeks: [UUID: [SidebarItemReference]])?
    /// What the page was last built from; nil until built, or once it must rebuild.
    var key: SidebarSpacePageKey?
    /// The state the page's rows last showed.
    var renderedState: BrowserState?
    var palette: ThemeChromePalette?
    /// The sidebar's state generation this page was last brought up to.
    var checkedGeneration = -1
    /// Every row has been laid out since the last build.
    var laidOut = false
    /// The sidebar size and shared geometry the page was last framed for.
    var framed: (size: NSSize, hiddenAddressHeight: CGFloat, trayHeight: CGFloat, hasFavorites: Bool, bottom: CGFloat)?
    var headerFramedShown = false
    /// A build idle preparation has begun, for the key it builds.
    var pendingBuild: (key: SidebarSpacePageKey, run: (CFTimeInterval?) -> Bool)?

    init(newTabRow: SidebarNewTabRow) {
        self.newTabRow = newTabRow
        view.wantsLayer = true
        view.addSubview(header); view.addSubview(scroll)
        scroll.drawsBackground = false; scroll.adoptTablistScroller()
        scroll.horizontalScrollElasticity = .none
        scroll.documentView = listHost; listHost.addSubview(list)
    }

    /// The built view showing `item`'s row: its tab, Split View or folder row.
    func view(for item: SidebarItemReference) -> NSView? { rowsByItem[item] }
    /// `item`'s row view; with `building`, built now if it has none and placed
    /// in the window at its row.
    func rowView(for item: SidebarItemReference, building: Bool) -> NSView? {
        if building, rowsByItem[item] == nil, itemSet.contains(item) { _ = list.content(for: item, building: true) }
        return rowsByItem[item]
    }
    /// The row showing a tab: its own, or its split's child row.
    func tabRow(_ id: UUID, building: Bool = false) -> SidebarTabRow? {
        if let row = rowView(for: .tab(id), building: building) as? SidebarTabRow { return row }
        if let split = splitOfTab[id], let group = rowView(for: .split(split), building: building) as? SidebarSplitGroupView,
           let row = group.rows.first(where: { $0.tabID == id }) { return row }
        return tabRows.first { $0.tabID == id }
    }
    func folderRow(_ id: UUID, building: Bool = false) -> SidebarFolderRow? { rowView(for: .folder(id), building: building) as? SidebarFolderRow }
    func splitRow(_ id: UUID, building: Bool = false) -> SidebarSplitGroupView? { rowView(for: .split(id), building: building) as? SidebarSplitGroupView }
    /// Whether the page lists `item`, built or not.
    func contains(_ item: SidebarItemReference) -> Bool { itemSet.contains(item) }
    /// The item whose row shows `tabID`: its own, or its Split View's.
    func item(showing tabID: UUID) -> SidebarItemReference {
        itemSet.contains(.tab(tabID)) ? .tab(tabID) : splitOfTab[tabID].map { .split($0) } ?? .tab(tabID)
    }
    func item(showing item: SidebarItemReference) -> SidebarItemReference {
        if case .tab(let id) = item { return self.item(showing: id) }
        return item
    }
    /// The built rows in outline order.
    var hierarchyRows: [(SidebarItemReference, NSView)] { items.compactMap { item in rowsByItem[item].map { (item, $0) } } }
    /// Whether `row` still belongs to this page's last build.
    func holds(_ row: SidebarTabRow) -> Bool { tabRows.contains { $0 === row } }
    /// The page left the screen: rows under the pointer let go of it.
    func resetPointer() {
        header.clearHover()
        newTabRow.invalidateHover()
        for row in tabRows { row.resetPointer() }
        for (_, view) in rowsByItem {
            (view as? SidebarFolderRow)?.resetPointer()
            (view as? SidebarSplitGroupView)?.resetPointer()
        }
    }

    func beginBuild() {
        tabRows.removeAll(); items.removeAll(); itemSet.removeAll(); splitOfTab.removeAll()
        rowsByItem.removeAll(); previewAnchors.removeAll()
    }
    /// Lists `item` in outline order; a Split View with its tabs.
    func addItem(_ item: SidebarItemReference, tabs: [UUID] = []) {
        items.append(item); itemSet.insert(item)
        if case .split(let id) = item { for tab in tabs { splitOfTab[tab] = id } }
    }
    func add(_ item: SidebarItemReference, _ view: NSView) { rowsByItem[item] = view }
    /// The list let go of `item`'s view; answers the tab rows that went with it.
    func remove(_ item: SidebarItemReference, _ view: NSView) -> [SidebarTabRow] {
        if rowsByItem[item] === view { rowsByItem.removeValue(forKey: item) }
        let rows = (view as? SidebarTabRow).map { [$0] } ?? (view as? SidebarSplitGroupView)?.rows ?? []
        let gone = Set(([view] + rows).map(ObjectIdentifier.init))
        tabRows.removeAll { gone.contains(ObjectIdentifier($0)) }
        previewAnchors = previewAnchors.filter { !gone.contains(ObjectIdentifier($0.value)) }
        keptTabRows = keptTabRows.filter { !gone.contains(ObjectIdentifier($0.value)) }
        folderRows = folderRows.filter { !gone.contains(ObjectIdentifier($0.value)) }
        return rows
    }
    /// Rows kept for reuse: those the build showed.
    func endBuild() {
        keptTabRows = Dictionary(tabRows.filter { !$0.compactSplitChild }.map { ($0.tabID, $0) }, uniquingKeysWith: { first, _ in first })
        folderRows = folderRows.filter { rowsByItem[.folder($0.key)] != nil }
    }
}

/// What a Space's page shows, apart from the live title, address, loading
/// and favicon fields the live path patches in place: the Space's own items,
/// order, folders, disclosure and selection, and the sidebar chrome that
/// shapes its rows. A page whose key still matches needs no rebuild.
struct SidebarSpacePageKey: Equatable {
    struct Tab: Equatable {
        let id: UUID, profileID: UUID, kind: TabKind, folderID: UUID?, archived: Bool
        let page: InternalPage?, blank: Bool, reset: Bool
    }
    var spaceID: UUID
    var profiles: [BrowserProfile]
    var spaces: [BrowserSpace]
    var settings: BrowserSettings
    var tabs: [Tab]
    var folders: [BrowserFolder]
    var splits: [BrowserSplitLayout]
    var order: [String: [SidebarItemReference]]
    var selected: [UUID]
    var focused: UUID?
    var placeholder: Bool
    var peeks: [UUID: [SidebarItemReference]]
    var speakers: Set<UUID>
    var presented: Set<UUID>
    /// Captures of custom-named Split Views' tabs, which their split cell shows.
    var splitCaptures: [UUID: CaptureIndicatorPresentation]
    var keyDragged: [UUID?]
    var flags: [Bool]

    init(state: BrowserState, spaceID: UUID, focused: UUID?, placeholder: Bool, peeks: [UUID: [SidebarItemReference]],
         speakers: Set<UUID>, presented: Set<UUID>, splitCaptures: [UUID: CaptureIndicatorPresentation],
         keyDragged: [UUID?], flags: [Bool]) {
        self.spaceID = spaceID
        profiles = state.profiles; spaces = state.spaces; settings = state.settings
        tabs = state.tabs.filter { $0.spaceID == spaceID }.map {
            Tab(id: $0.id, profileID: $0.profileID, kind: $0.kind, folderID: $0.folderID, archived: $0.archivedAt != nil,
                page: InternalPage(urlString: $0.url), blank: BrowserState.isBlankPage($0.url), reset: $0.resetDestination != nil)
        }
        folders = state.folders.filter { $0.spaceID == spaceID }
        splits = state.splitLayouts.filter { $0.spaceID == spaceID }
        let space = spaceID.uuidString
        order = state.sidebarItemOrder.filter { $0.key.hasPrefix(space) }
        selected = state.selectedTabIDs; self.focused = focused; self.placeholder = placeholder
        let shown = Set(folders.map(\.id))
        self.peeks = peeks.filter { shown.contains($0.key) }
        self.speakers = speakers; self.presented = presented; self.splitCaptures = splitCaptures
        self.keyDragged = keyDragged; self.flags = flags
    }

    /// The same page apart from its selection.
    func matchesApartFromSelection(_ other: Self) -> Bool {
        var other = other
        other.selected = selected; other.focused = focused
        return other == self
    }
}

final class SidebarPageStripView: NSView {
    var passesThrough = false
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !passesThrough, let hit = super.hitTest(point), hit !== self else { return nil }
        return hit
    }
    override func accessibilityChildren() -> [Any]? { passesThrough ? [] : super.accessibilityChildren() }
    override func isAccessibilityElement() -> Bool { false }
}
