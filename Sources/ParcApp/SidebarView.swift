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

final class SidebarTabRow: NSView, NSDraggingSource, SidebarItemDragSource {
    static let pasteboardType = NSPasteboard.PasteboardType("org.parc.sidebar-tab")
    let tabID: UUID
    private let titleLabel = SidebarChromeLabel(labelWithString: "")
    private let titleField = SidebarTitleField()
    private let background = SidebarRowBackgroundView()
    private let icon = SidebarFaviconView()
    private let closeButton = SidebarRowActionButton("Close Tab")
    ///
    /// with a 14-point semibold rectangle.inset.filled.and.person.filled,
    /// shown only while the row is hovered without its reset subtitle and the
    ///
    private let shareButton = SidebarRowActionButton("Share this tab instead")
    var shareable = false { didSet { if shareable != oldValue { updateActions(); needsLayout = true } } }
    var prepareShare: (() -> (() -> Bool)?)? { didSet { shareButton.prepareAction = prepareShare } }
    ///
    /// region (TabCellRegionalBackgroundView), the slash between icon and
    /// title, and the hover subtitle carried by the lifted title stack.
    private let resetRegion = SidebarRowResetRegion()
    private let bodyRegion = SidebarRowBodyRegionView()
    private let slash = SidebarRowSlashView()
    private let resetIcon = SidebarFaviconView()
    private let titleStack = SidebarRowTitleStack()
    private let hoverSubtitle = SidebarChromeLabel(labelWithString: SidebarRowAppearance.resetSubtitle)
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
    private let captureButton = ActionButton("Active capture", symbol: "mic.fill")
    private let muteButton = SidebarRowActionButton("Mute this tab")
    var audio: SidebarTabAudio? {
        didSet {
            // Every live-metadata pass sets each row's audio; only a change
            // rebuilds its tooltip and layout.
            guard audio?.audible != oldValue?.audible || audio?.muted != oldValue?.muted else { return }
            let muted = audio?.muted == true
            let label = muted ? "Unmute this tab" : "Mute this tab"
            LiveShortcutToolTip.set(muteButton, label); muteButton.setAccessibilityLabel(label)
            if let speaker = muteButton.decoration as? SidebarSpeakerHost, speaker.model.muted != muted {
                speaker.model.muted = muted
            }
            needsLayout = true
        }
    }
    var prepareMute: (() -> (() -> Bool)?)? {
        didSet { muteButton.prepareAction = prepareMute; muteButton.refreshAvailability() }
    }
    var showCapture: ((NSView) -> Void)?
    var capture: CaptureIndicatorPresentation? {
        didSet {
            guard capture != oldValue else { return }
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
        icon.image = NSImage(systemSymbolName: InternalPage.sidebarFallbackSymbol(urlString: tab.url),
                             accessibilityDescription: nil)
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
        resetRegion.prepareAction = reset; resetRegion.prepareSeparate = separate
        resetRegion.isHidden = !hasReset; bodyRegion.isHidden = !hasReset; slash.isHidden = !hasReset
        resetRegion.onHoverChange = { [weak self] in self?.resetHoverChanged() }
        resetIcon.isHidden = true
        hoverSubtitle.font = .systemFont(ofSize: SidebarRowAppearance.subtitleFontSize)
        hoverSubtitle.lineBreakMode = .byTruncatingTail
        hoverSubtitle.maximumNumberOfLines = 1
        hoverSubtitle.setAccessibilityElement(false)
        hoverSubtitle.wantsLayer = true; hoverSubtitle.alphaValue = 0
        titleStack.wantsLayer = true
        closeButton.focusRingType = .exterior
        shareButton.symbol = NSImage(systemSymbolName: "rectangle.inset.filled.and.person.filled", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
        shareButton.setAccessibilityIdentifier("shareTabButton")
        shareButton.isHidden = true
        muteButton.decoration = speaker
        muteButton.setAccessibilityIdentifier("sidebarTabCellMuteButton")
        muteButton.isHidden = true
        captureButton.isHidden = true
        captureButton.imagePosition = .imageOnly
        captureButton.actionBlock = { [weak self] in
            guard let self else { return }
            self.showCapture?(self.captureButton)
        }
        addSubview(background); addSubview(bodyRegion); addSubview(resetRegion)
        addSubview(icon); addSubview(resetIcon); addSubview(slash)
        titleStack.addSubview(titleLabel); titleStack.addSubview(hoverSubtitle)
        addSubview(titleStack); addSubview(titleField); addSubview(shareButton); addSubview(closeButton); addSubview(captureButton); addSubview(muteButton)
        updateResetTooltip()
        self.selected = selected
        updateColor()
        updateRowTooltip(); shownURL = tab.url
        //
        //
        // button description, which document rows share here.
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        if InternalPage(urlString: tab.url) == nil { setAccessibilityRoleDescription("Tab") }
        setAccessibilityHelp(tab.url)
        closeButton.makeMenu = { [weak self] in self?.context?() }
        resetRegion.makeMenu = { [weak self] in self?.context?() }
        muteButton.makeMenu = { [weak self] in self?.context?() }
    }
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
            self.resetIcon.image = image
            self.updateResetIcon()
        }
    }
    /// Settled page art, and reset art when the row shows a reset target.
    /// Nil while still on the themed fallback or waiting on a lookup so a
    /// later same-URL history hit is not dropped by a skip.
    fileprivate func settledFaviconArt() -> TabRowSettledFaviconArt? {
        guard allowsFavicon, icon.hasSettledFavicon, let page = icon.image else { return nil }
        if hasReset {
            guard let reset = resetIcon.image else { return nil }
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
            resetIcon.image = art.reset
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
            setAccessibilityHelp(tab.url)
            let allows = InternalPage(urlString: tab.url) == nil
            if allows != allowsFavicon {
                allowsFavicon = allows
                icon.image = NSImage(systemSymbolName: InternalPage.sidebarFallbackSymbol(urlString: tab.url),
                                     accessibilityDescription: nil)
            }
        }
        let reset = tab.resetDestination != nil
        if reset != hasReset {
            hasReset = reset
            slash.isHidden = !hasReset
            if !hasReset {
                resetIcon.image = nil
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
        resetRegion.prepareAction = reset
        resetRegion.prepareSeparate = separate
        // The region stays shown; scrolling no longer re-reads its availability.
        resetRegion.refreshAvailability()
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
    func cancelTitleEditing() { titleField.cancel() }

    override func layout() {
        super.layout()
        defer {
            let titleFrame = NSRect(x: titleStack.frame.minX, y: titleStack.frame.minY,
                                    width: titleLabel.frame.width, height: titleLabel.frame.height)
            if titleField.editingTitle {
                titleLabel.isHidden = true
                titleField.frame = NSRect(x: titleFrame.minX, y: titleFrame.minY,
                    width: max(0, bounds.width - titleFrame.minX - 8), height: titleFrame.height)
                closeButton.isHidden = true; resetRegion.isHidden = true; bodyRegion.isHidden = true
                captureButton.isHidden = true; shareButton.isHidden = true; muteButton.isHidden = true
            } else { titleField.frame = titleFrame }
        }
        background.frame = bounds
        updateActions()
        if compactSplitChild {
            //
            // slash or hover subtitle; Parc's capture button takes the
            // recording indicator's place before the icon.
            let titleHeight = ceil(titleLabel.intrinsicContentSize.height)
            let layout = SidebarRowAppearance.splitChildLayout(in: bounds, titleHeight: titleHeight,
                recording: capture != nil, closeAvailable: !titleField.editingTitle && splitChildCloseAvailable,
                groupHovered: groupHover)
            background.frame = layout.cell
            captureButton.isHidden = layout.indicator == nil
            if let indicator = layout.indicator { captureButton.frame = indicator }
            icon.isHidden = false
            let slot = layout.iconSlot
            icon.frame = NSRect(x: slot.midX - SidebarRowAppearance.iconSize / 2, y: slot.midY - SidebarRowAppearance.iconSize / 2,
                                width: SidebarRowAppearance.iconSize, height: SidebarRowAppearance.iconSize).integral
            resetIcon.frame = icon.frame
            closeButton.frame = layout.close
            if !muteButton.isHidden {
                let right = layout.showsClose ? layout.close.minX - 2 : bounds.maxX - 4
                let frame = NSRect(x: right - 24, y: layout.close.minY, width: 24, height: layout.close.height)
                if frame.minX < slot.maxX { muteButton.isHidden = true }
                else { muteButton.frame = frame }
            }
            closeButton.isHidden = !layout.showsClose
            slash.isHidden = true
            titleLabel.isHidden = layout.title == nil
            let title = layout.title ?? NSRect(x: slot.maxX, y: 0, width: 0, height: titleHeight)
            let titleWidth = muteButton.isHidden ? title.width : max(0, min(title.width, muteButton.frame.minX - title.minX))
            titleStack.frame = NSRect(x: title.minX, y: title.minY, width: titleWidth, height: title.height)
            titleLabel.frame = NSRect(x: 0, y: 0, width: titleWidth, height: title.height)
            hoverSubtitle.frame = NSRect(x: 0, y: title.height, width: title.width, height: 0)
            return
        }
        titleLabel.isHidden = false; icon.isHidden = false
        icon.frame = SidebarRowAppearance.iconFrame(in: bounds); resetIcon.frame = icon.frame
        titleLabel.font = .systemFont(ofSize: SidebarRowAppearance.titleFontSize)
        slash.isHidden = !hasReset
        slash.frame = SidebarRowAppearance.slashFrame(in: bounds)
        resetRegion.frame = SidebarRowAppearance.resetRegionFrame(in: bounds)
        bodyRegion.frame = NSRect(x: resetRegion.frame.maxX, y: 0,
                                  width: max(0, bounds.width - resetRegion.frame.maxX), height: bounds.height)
        closeButton.frame = SidebarRowAppearance.closeFrame(in: bounds)
        var trailing = SidebarRowAppearance.titleTrailingEdge(in: bounds, closeVisible: !closeButton.isHidden)
        if !shareButton.isHidden {
            //
            let close = closeButton.frame
            shareButton.frame = NSRect(x: close.minX - 2 - close.width, y: close.minY, width: close.width, height: close.height)
            trailing = shareButton.frame.minX - SidebarRowAppearance.titleCloseSpacing
        }
        if !muteButton.isHidden {
            muteButton.frame = NSRect(x: trailing - 24, y: ((bounds.height - 24) / 2).rounded(.down), width: 24, height: 24)
            trailing = muteButton.frame.minX
        }
        // Shown again after a title edit (the defer above hides it while editing).
        captureButton.isHidden = capture == nil
        if capture != nil {
            // Parc's capture indicator sits in the body stack before Close.
            captureButton.frame = NSRect(x: trailing - 23, y: ((bounds.height - 25) / 2).rounded(.down), width: 23, height: 25)
            trailing = captureButton.frame.minX
        }
        let (titleX, width) = SidebarRowAppearance.titleLabelSpan(resettable: hasReset, trailing: trailing)
        //
        let subtitleHeight = ceil(hoverSubtitle.intrinsicContentSize.height)
        titleStack.frame = NSRect(x: titleX, y: ((bounds.height - 18) / 2).rounded(.down), width: width, height: 18 + subtitleHeight)
        titleLabel.frame = NSRect(x: 0, y: 0, width: width, height: 18)
        hoverSubtitle.frame = NSRect(x: 0, y: 18, width: width, height: subtitleHeight)
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
        closeButton.refreshAvailability(); resetRegion.refreshAvailability()
        // Hidden pointer controls keep their context-menu and accessibility
        // actions. A split child shows Close while its split is hovered (its
        // layout also needs room) and has no reset target.
        closeButton.isHidden = titleField.editingTitle || !(compactSplitChild ? groupHover && splitChildCloseAvailable : hover)
        muteButton.isHidden = titleField.editingTitle || !(audio?.audible == true || audio?.muted == true)
        muteButton.refreshAvailability()
        shareButton.refreshAvailability()
        shareButton.isHidden = titleField.editingTitle || compactSplitChild || !shareable || !hover || shownSubtitle != nil
        resetRegion.isHidden = titleField.editingTitle || !hasReset || compactSplitChild
        bodyRegion.isHidden = resetRegion.isHidden
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
        titleField.cancel()
        hover = false; groupHover = false; mouseStart = nil; selectionEvent = nil; pendingActivation = nil
        setResetSubtitle(nil, animated: false)
        closeButton.cancelInteraction(); resetRegion.cancelInteraction(); shareButton.cancelInteraction(); muteButton.cancelInteraction()
        closeButton.isHidden = true; shareButton.isHidden = true
        updateColor()
    }
    ///
    /// the row's TabCellState.shouldDim takes the same window state here.
    private func updateDim() {
        dimmed = window.map { !$0.isKeyWindow && !$0.isMainWindow } ?? false
        // Muting needs the key window: the speaker's dimming follows it.
        muteButton.refreshAvailability()
        updateColor()
    }
    private func updateColor() {
        let dark = palette?.isDark ?? (effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        let title = palette?.title ?? .parcInk
        titleLabel.textColor = title
        hoverSubtitle.textColor = title.withAlphaComponent(SidebarRowAppearance.subtitleTextAlpha)
        icon.fallbackTintColor = title
        resetIcon.fallbackTintColor = title
        closeButton.dark = dark; shareButton.dark = dark; muteButton.dark = dark
        (muteButton.decoration as? SidebarSpeakerHost)?.model.color = dark
            ? NSColor(white: 1, alpha: 0.592) : NSColor(white: 0, alpha: 0.565)
        captureButton.contentTintColor = title
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
        resetRegion.dark = dark; bodyRegion.dark = dark
        resetRegion.corners = state.resetRegionCorners
        bodyRegion.hovered = hover && !resetRegion.hovered && state.splitsResetRegions
        //
        slash.color = SidebarRowAppearance.slashColor(dark: dark)
        slash.alphaValue = resetRegion.hovered || bodyRegion.hovered ? 0 : 1
    }
    private func resetHoverChanged() {
        updateColor()
        setResetSubtitle(compactSplitChild || titleField.editingTitle ? nil : resetRegion.hoverSubtitle, animated: true)
    }
    /// The hover subtitle fades in below the title while the title stack lifts
    ///
    /// flipped title stack moves the same 7 points up with −7. Switching
    /// between the two subtitles changes only the text.
    private func setResetSubtitle(_ subtitle: SidebarRowHoverSubtitle?, animated: Bool) {
        guard subtitle != shownSubtitle else { return }
        let wasVisible = shownSubtitle != nil, visible = subtitle != nil
        shownSubtitle = subtitle
        if let subtitle { hoverSubtitle.stringValue = subtitle.text }
        updateResetIcon()
        if shareable && visible != wasVisible { updateActions(); needsLayout = true }
        guard visible != wasVisible, let stack = titleStack.layer, let label = hoverSubtitle.layer else { return }
        let lift = visible ? CATransform3DMakeTranslation(0, -SidebarRowAppearance.subtitleLift, 0) : CATransform3DIdentity
        let opacity: Float = visible ? 1 : 0
        let fromLift = stack.presentation()?.sublayerTransform ?? stack.sublayerTransform
        let fromOpacity = label.presentation()?.opacity ?? label.opacity
        CATransaction.begin(); CATransaction.setDisableActions(true)
        stack.sublayerTransform = lift; hoverSubtitle.alphaValue = CGFloat(opacity)
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
        let swap = shownSubtitle == .reset && resetIcon.image != nil
        resetIcon.isHidden = !swap
        icon.alphaValue = swap ? 0 : 1
    }
    /// "Reset Tab" with the reset shortcut, only while one is bound
    ///
    private func updateResetTooltip() {
        LiveShortcutToolTip.set(resetRegion, "Reset Tab", commandID: "resetTab:", requiresBinding: true)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        guard window != nil, !isHiddenOrHasHiddenAncestor, !titleField.editingTitle else { return }
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
    var supplementaryAccessibilityActions: [NSAccessibilityCustomAction] {
        super.accessibilityCustomActions() ?? []
    }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return [] }
        return supplementaryAccessibilityActions + (makeAccessibilityActions?() ?? [])
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
              !titleField.editingTitle, let close = closeButton.prepareAction?() else {
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
        resetRegion.cancelInteraction(); setResetSubtitle(nil, animated: false)
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
    private var previewAnchors: [SidebarPreviewTarget: NSView] = [:]
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

    /// Folder rows by folder, kept across renders so a disclosure change
    /// animates the row's icon and the row keeps its pointer state.
    private var folderRowCache: [UUID: SidebarFolderRow] = [:]
    private var renderedFolderRows: [UUID: SidebarFolderRow] = [:]
    private var folderTitleEdit: (folder: BrowserFolder, row: SidebarFolderRow)?
    /// The last rendered Space's folder disclosure.
    private var renderedDisclosure: (space: UUID, expanded: [UUID: Bool], peeks: [UUID: [SidebarItemReference]])?
    /// Prepares an inline rename of the original folder: commits a name, or
    /// nil when the folder cannot be renamed here.
    var prepareFolderRename: ((BrowserFolder) -> ((String) -> Bool)?)?
    /// New Folder with the selected items, editing its name in its row.
    var prepareFolderFromSelection: (([SidebarItemReference]) -> (() -> Bool)?)?
    /// Change Icon… for the original folder.
    var prepareFolderIcon: ((BrowserFolder) -> (() -> Bool)?)?
    /// The folder row and its icon's rect, where Change Icon… anchors.
    func folderIconAnchor(_ id: UUID) -> (view: NSView, rect: NSRect)? {
        guard let row = renderedFolderRows[id], row.window != nil else { return nil }
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
            let previous = renderedDisclosure?.space == state.activeSpaceID ? renderedDisclosure?.expanded : nil
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
              let row = renderedFolderRows[id], row.window != nil,
              let commit = prepareFolderRename?(folder), presentsForEditing(reveal: revealForEditing) else { return false }
        folderTitleEdit = (folder, row)
        row.scrollToVisible(row.bounds.insetBy(dx: 0, dy: -3))
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
              let row = tabRows.first(where: { $0.tabID == tab.id }),
              let commit = prepareTabRename?(tab), presentsForEditing(reveal: revealForEditing) else { return false }
        titleEdit = (tab, row, state.selectedTabIDs, latestFocusedTabID)
        row.scrollToVisible(row.bounds.insetBy(dx: 0, dy: -3))
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
        return hierarchyRows.first { $0.0 == .split(group.id) }?.1
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
              let row = hierarchyRows.first(where: { $0.0 == .split(target.group.id) })?.1 as? SidebarSplitGroupView,
              let commit = prepareSplitRename?(target), presentsForEditing(reveal: revealForEditing) else { return false }
        splitTitleEdit = (target, row, state.selectedTabIDs, latestFocusedTabID)
        row.scrollToVisible(row.bounds.insetBy(dx: 0, dy: -3))
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
    private var spaceHeaderContentShown = false
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
    private lazy var archiveEducationHost = AutoArchiveEducationHost(card: archiveEducation)
    var onDismissAutoArchiveEducation: (() -> Void)?
    var onAutoArchiveEducationSettings: (() -> Void)?
    var onAutoArchiveEducationRelinquishFocus: (() -> Void)?

    func showAutoArchiveEducation(_ visible: Bool) {
        archiveEducationHost.show(visible)
        archiveEducationHost.setInteractionAllowed(isPresented && creationView == nil)
    }
    func resetAutoArchiveEducation() { archiveEducationHost.reset() }
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
        addressBackground.style = showsSharedQuote
            ? .sharedQuote(fill: palette?.hover ?? NSColor.white.withAlphaComponent(0.32)) : .urlBar
        addressButton.focusRingCornerRadius = showsSharedQuote ? SidebarAddressPillView.sharedQuoteCornerRadius
            : SidebarAddressPillView.cornerRadius
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
    private var clearRevealed = false
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
        else if let item, let view = hierarchyRows.first(where: { $0.0 == item })?.1 { row = view }
        else if case .tab(let id) = item { row = previewAnchors[.tab(id)] }
        else { row = nil }
        guard let row else { return }
        if let tabRow = row as? SidebarTabRow {
            //
            tabRow.keyboardHighlighted = true; keyboardHighlightedRow = tabRow
        } else if let group = row as? SidebarSplitGroupView {
            // So does the split cell's CellSelectionStateView.
            group.keyboardHighlighted = true; keyboardHighlightedGroup = group
        } else if let folder = row as? SidebarFolderRow {
            // And the folder cell's.
            folder.keyboardHighlighted = true; keyboardHighlightedFolder = folder
        } else if favorite == nil {
            keyboardHighlight.frame = row.bounds
            keyboardHighlight.autoresizingMask = [.width, .height]
            row.addSubview(keyboardHighlight)
        }
        if scrollToHighlight {
            row.scrollToVisible(row.bounds.insetBy(dx: 0, dy: -3))
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
        guard let row = hierarchyRows.first(where: { $0.0 == item })?.1 else { return }
        row.scrollToVisible(row.bounds.insetBy(dx: 0, dy: -4))
        NSAccessibility.post(element: row, notification: .layoutChanged)
        SidebarAttentionShake.play(on: row)
    }

    ///
    /// row into view without the reveal's attention shake.
    func scrollItemToVisible(_ item: SidebarItemReference) {
        layoutSubtreeIfNeeded()
        guard let row = hierarchyRows.first(where: { $0.0 == item })?.1 else { return }
        row.scrollToVisible(row.bounds.insetBy(dx: 0, dy: -4))
    }

    private let scroll = SidebarPagingScrollView()
    ///
    private let list = SidebarOutlineView()
    private let favoritesHost = NSView()
    ///
    /// the tray until its profile dismisses it.
    private let favoritesEmptyState = FavoritesEmptyStateView()
    /// Records the Dismiss button's or Hide item's profile in the store.
    var dismissFavoritesEmptyState: ((UUID) -> Void)?
    ///
    /// SidebarChromeLayout.SpaceHeader.content.
    private let spaceHeader = SidebarSpaceHeaderView()
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
    private var tabRows: [SidebarTabRow] = []
    private var speakerHosts: [UUID: SidebarSpeakerHost] = [:]
    ///
    private var keyDraggedTabID: UUID?
    /// The split whose cell is the key item of an in-progress drag.
    private var keyDraggedSplitID: UUID?
    private weak var keyboardHighlightedGroup: SidebarSplitGroupView?
    private weak var keyboardHighlightedFolder: SidebarFolderRow?
    private var hierarchyState: BrowserState?
    private var hierarchyRows: [(SidebarItemReference, NSView)] = []
    private let dropFeedback = SidebarDropFeedbackView()
    private var dropProposal: (SidebarMoveSession, SidebarContainerLocation, SidebarItemReference?)?
    private var windowDropAction: (() -> Bool)?
    private var copyDropAction: (() -> Bool)?
    private var dockDropAction: (() -> Bool)?
    private weak var pinnedEnd: NSView?
    private weak var todayStart: NSView?
    /// One New Tab row across renders, so a render keeps its hover plate and
    /// lets a release bounce finish.
    private lazy var newTabRow: SidebarNewTabRow = {
        let row = SidebarNewTabRow(dark: false) { [weak self] in self?.onNewTab?() }
        row.button.focusRingCornerRadius = SidebarRowAppearance.cornerRadius // a Parc ring in the hover plate's shape
        //
        // the state has no tooltip, so only the help carries it.
        LiveShortcutToolTip.help(row.button, "New tab", commandID: "newTab:")
        return row
    }()
    ///
    /// is then the only current item: the tab and split cell builders report
    ///
    /// clears a split's child plates. The next render rebuilds the rows with
    /// it; until then the live-metadata path refuses. Favorites tiles do not
    /// read it.
    var newTabPlaceholderActive = false { didSet { newTabRow.current = newTabPlaceholderActive } }
    private var renderedNewTabPlaceholder = false
    private weak var clearButton: ActionButton?
    private var todayHasTabs = false
    private weak var sectionLine: SidebarHairline?
    private weak var privateUnpinnedHeader: SidebarSpaceHeaderView?
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
        pageStrip.addSubview(spaceHeader); pageStrip.addSubview(scroll)
        contentSurface.addSubview(archiveEducationHost)
        archiveEducation.setInteractionEnabled(false)
        archiveEducation.onDismiss = { [weak self] in self?.onDismissAutoArchiveEducation?() }
        archiveEducation.onSettings = { [weak self] in self?.onAutoArchiveEducationSettings?() }
        archiveEducationHost.onLayoutChanged = { [weak self] in self?.setNeedsKeyViewLinking() }
        archiveEducationHost.onInteractionChanged = { [weak self] enabled in
            self?.archiveEducation.setInteractionEnabled(enabled)
            self?.setNeedsKeyViewLinking()
        }
        archiveEducationHost.onRelinquishFocus = { [weak self] in self?.onAutoArchiveEducationRelinquishFocus?() }
        // The header's menu offers the Space actions Parc already has.
        spaceHeader.isHidden = true
        spaceHeader.managementMenu = { [weak self] in
            guard let self, let id = self.activeSpaceID else { return nil }
            return self.makeSpaceManagementMenu?(id)
        }
        spaceHeader.onChangeIcon = { [weak self] in
            guard let self, let id = self.activeSpaceID else { return }
            self.onChangeSpaceIcon?(id)
        }
        spaceHeader.onRenameSpace = { [weak self] in
            guard let self, let id = self.activeSpaceID else { return }
            self.onRenameSpace?(id)
        }
        spaceHeader.onEditTheme = { [weak self] in self?.onEditTheme?() }
        spaceHeader.onNewFolder = { [weak self] in self?.onNewFolder?() }
        spaceHeader.onToggleHeader = { [weak self] in self?.toggleSpaceHeaderOnSingleUnnamedSpaces?() }
        //
        // header can show its edit button; Parc has no `.home` one [I].
        spaceHeader.canShowHeaderButtonsIfPossible = true
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
        shareQuote.alignment = .left; shareQuote.font = .systemFont(ofSize: 10, weight: .medium)
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
        scroll.drawsBackground = false; scroll.adoptTablistScroller()
        scroll.horizontalScrollElasticity = .none
        list.focusOwner = self
        scroll.documentView = list
        configureSpacePaging()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Mouse and trackpad navigation (docs/navigation.md)

    ///
    /// window's Spaces in dock order. The Space header and tablist live in
    ///
    ///
    /// dock stay in place. While the strip is off rest, the neighbouring
    /// Space's page is drawn beside it by a non-interactive sidebar rendered
    /// for that Space, and the themes of the pages either side of the strip's
    ///
    /// background and the floating container's theme view
    ///
    private let spacePager = SidebarSpacePager()
    private let pageStrip = SidebarPageStripView()
    private let neighborPage = SidebarPageStripView()
    private var neighborSidebar: SidebarView?
    private var neighborSpaceID: UUID?
    /// The Space a switch made elsewhere left, shown beside the strip and
    /// blended from while it slides in, even when it isn't the adjacent page.
    private var pagingSourceID: UUID?
    /// Set when the creation page closes, so its new Space doesn't slide in
    /// from the Space it was created from.
    private var creationEnded = false
    private var neighborPaletteSource: (theme: SpaceTheme, appearance: NSAppearance.Name)?
    ///
    private let spaceCreationFeedback = SidebarSpaceCreationFeedbackView()
    private var spaceCreationGesture = SidebarSpaceCreationGesture()
    /// The themes either side of the strip's position and the progress
    /// between them, which the window's theme surfaces draw; nil at rest.
    var onPagingTheme: ((ThemePagingTransition?) -> Void)?
    private func configureSpacePaging() {
        pageStrip.wantsLayer = true; pageStrip.layer?.masksToBounds = true
        neighborPage.wantsLayer = true; neighborPage.layer?.masksToBounds = true
        neighborPage.isHidden = true
        neighborPage.passesThrough = true
        pageStrip.addSubview(neighborPage)
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
        scroll.offerScroll = { [weak self] event in self?.spacePager.scrollWheel(event) ?? false }
        spacesHost.offerScroll = scroll.offerScroll
        miniPlayers.offerScroll = scroll.offerScroll
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
              let state = hierarchyState,
              let pages = SidebarSpacePagingModel.themePages(selected: index, offset: offset, width: width, count: spaces.count) else {
            neighborPage.isHidden = true
            pagingSourceID = nil
            onPagingTheme?(nil)
            return
        }
        let space = spaces[neighborIndex]
        if neighborSpaceID != space.id { renderNeighbor(space, state: state) }
        let pageTop = spaceHeader.isHidden ? scroll.frame.minY : spaceHeader.frame.minY
        let pageRect = NSRect(x: offset < 0 ? width : -width, y: pageTop, width: width,
                              height: max(0, scroll.frame.maxY - pageTop))
        neighborPage.frame = pageRect
        neighborSidebar?.frame = NSRect(x: 0, y: -pageTop, width: width, height: bounds.height)
        neighborPage.isHidden = false
        updateNeighborPalette(space)
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

    /// The neighbouring page's text and fills, from the window's appearance
    /// rather than the current Space's contrasting one.
    private func updateNeighborPalette(_ space: BrowserSpace) {
        let appearance = window?.effectiveAppearance ?? effectiveAppearance
        guard neighborPaletteSource?.theme != space.theme || neighborPaletteSource?.appearance != appearance.name else { return }
        neighborSidebar?.palette = ThemeChromePalette(theme: space.theme, appearance: appearance)
        neighborPaletteSource = (space.theme, appearance.name)
    }

    /// Renders the neighbouring Space's page with its own palette from the
    /// same state; no callbacks are connected, so it cannot act.
    private func renderNeighbor(_ space: BrowserSpace, state: BrowserState) {
        let sidebar = neighborSidebar ?? SidebarView(frame: bounds)
        if neighborSidebar == nil {
            neighborSidebar = sidebar; neighborPage.addSubview(sidebar)
            sidebar.isPresented = false
        }
        sidebar.isPrivateBrowsing = isPrivateBrowsing
        sidebar.requestTabFavicon = requestTabFavicon
        sidebar.requestSavedFavicon = requestSavedFavicon
        updateNeighborPalette(space)
        var neighbor = state; neighbor.activeSpaceID = space.id
        sidebar.frame = bounds
        sidebar.render(state: neighbor, focusedTabID: nil, loading: [], canBack: false, canForward: false)
        neighborSpaceID = space.id
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
                && tabRows.contains(where: { $0.tabID == id && !$0.compactSplitChild })
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
        for group in splitGroups where SidebarSplitCellLayout.usesCustomInfo(
            title: group.customTitle, hasIcon: group.customIcon != nil, editing: false) {
            for id in group.tabIDs {
                let current = tabRows.first { $0.tabID == id }?.capture
                if current != captures[id] { return false }
            }
        }
        let effectiveAudio = applyShareableAudio ? audio : tabAudio
        for row in tabRows {
            let next = effectiveAudio[row.tabID]
            let needsSpeaker = next?.audible == true || next?.muted == true
            if needsSpeaker != (speakerHosts[row.tabID] != nil) { return false }
        }
        if selectionChanged { applySelection(state: state, focusedTabID: focusedTabID) }
        latestFocusedTabID = focusedTabID
        hierarchyState = state
        updateNavigation(canBack: canBack, canForward: canForward,
            loading: focusedTabID.map { loading.contains($0) } ?? false, enabled: true)
        let selected = state.tabs.first { $0.id == (focusedTabID ?? state.selectedTabIDs.first) }
        let selectedURL = selected.flatMap { URL(string: $0.url) }
        let isEasel = selected.flatMap { InternalPage(urlString: $0.url) } != nil
        let address = isEasel ? "Easel" : selectedURL?.isFileURL == true ? selectedURL!.lastPathComponent
            : selectedURL.flatMap(SidebarAddressSearchIcon.host(of:)) ?? SidebarAddressSearchIcon.placeholder
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
            button.update(title: spokenTitle, monogram: monogram(tab), url: tab.url,
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
            if let hierarchy = self.hierarchyState {
                actions += self.moveAccessibilityActions(item: item, state: hierarchy)
            }
            return actions
        }
    }

    func reloadFavicon(for id: UUID) {
        if let row = tabRows.first(where: { $0.tabID == id }),
           let tab = hierarchyState?.tabs.first(where: { $0.id == id }) {
            row.loadFavicon { [weak self, weak row] completion in
                self?.requestTabFavicon?(tab) { [weak self, weak row] image in
                    guard let self, let row, self.tabRows.contains(where: { $0 === row }) else { return }
                    completion(image)
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
        previewAnchors.removeAll()
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
        let selected = state.tabs.first { $0.id == (focusedTabID ?? state.selectedTabIDs.first) }
        let selectedURL = selected.flatMap { URL(string: $0.url) }
        let isEasel = selected.flatMap { InternalPage(urlString: $0.url) } != nil
        let address = isEasel ? "Easel" : selectedURL?.isFileURL == true ? selectedURL!.lastPathComponent
            : selectedURL.flatMap(SidebarAddressSearchIcon.host(of:)) ?? SidebarAddressSearchIcon.placeholder
        setAddressTitle(address)
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
            let button = favoriteTiles[tab.id] ?? FavoriteTile(title: spokenTitle, monogram: monogram(tab), url: tab.url)
            favoriteTiles[tab.id] = button; retainedFavoriteIDs.insert(tab.id)
            button.update(title: spokenTitle, monogram: monogram(tab), url: tab.url,
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
            previewAnchors[.tab(tab.id)] = button
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
        //
        // and menu toggle (SidebarChromeLayout.SpaceHeader.content).
        let headerContent = SidebarChromeLayout.SpaceHeader.content(
            spaces: state.spaces, activeSpaceID: state.activeSpaceID, privateWindow: isPrivateBrowsing,
            showOnSingleUnnamedSpace: state.settings.showSpaceHeaderOnSingleUnnamedSpaces ?? false)
        if let editingSpace, space?.id != editingSpace.id || space?.profileID != editingSpace.profileID || space?.title != editingSpace.title {
            cancelSpaceNameEditing()
        }
        spaceHeader.canShowHeaderButtonsIfPossible = !isSpaceManagement
        spaceHeaderContentShown = headerContent.isShown
        spaceHeader.isHidden = !headerContent.isShown && !spaceHeader.isEditing
        spaceHeader.update(headerContent, symbol: space?.customIcon?.image, emoji: space?.customIcon?.emoji)
        let profileName = state.profiles.count > 1 && !isPrivateBrowsing
            ? state.profiles.first(where: { $0.id == space?.profileID })?.name : nil
        spaceHeader.updateProfile(name: profileName, menu: { [weak self] in
            guard let self, let id = self.activeSpaceID else { return nil }
            return self.makeSpaceManagementMenu?(id)?.profileMenu()
        })
        let origin = scroll.contentView.bounds.origin
        // Capture settled art before teardown so replacement rows for the same
        // page identity can adopt it and skip a true no-op re-arm.
        var priorTabFaviconArt: [UUID: TabRowSettledFaviconArt] = [:]
        for row in tabRows {
            if let art = row.settledFaviconArt() {
                priorTabFaviconArt[row.tabID] = art
            }
        }
        tabRows.removeAll(); hierarchyRows.removeAll(); hierarchyState = state
        renderedFolderRows.removeAll()
        neighborSpaceID = nil
        // A new Space arrives from its own creation page, not the one it left.
        if let departing, departing != state.activeSpaceID, !afterCreation, window != nil, isPresented,
           creationView == nil, !contentSurface.isHidden,
           let from = spaces.firstIndex(where: { $0.id == departing }),
           let to = spaces.firstIndex(where: { $0.id == state.activeSpaceID }) {
            pagingSourceID = departing
            if !spacePager.slideIn(from: from, to: to) { pagingSourceID = nil }
        }
        dropProposal = nil; dropFeedback.targetRect = nil
        typealias Chrome = SidebarChromeLayout
        // Item rows in the order they are built; Chrome.tablistSlots places
        // them in the list.
        var itemRows: [SidebarOutlineEntry] = []
        let tabs = visible.filter { $0.spaceID == state.activeSpaceID }
        let activeAudioIDs = Set(tabs.compactMap { tab -> UUID? in
            guard let audio = tabAudio[tab.id], audio.audible || audio.muted else { return nil }
            return tab.id
        })
        speakerHosts = speakerHosts.filter { activeAudioIDs.contains($0.key) }
        func makeRow(_ tab: BrowserTab, inGroup: Bool = false) -> SidebarTabRow {
            let current = inGroup ? focusedTabID == tab.id
                : !renderedNewTabPlaceholder && state.selectedTabIDs.contains(tab.id)
            //
            //
            let speaker: SidebarSpeakerHost?
            if activeAudioIDs.contains(tab.id) {
                speaker = speakerHosts[tab.id] ?? SidebarSpeakerHost(muted: tabAudio[tab.id]?.muted == true)
                speakerHosts[tab.id] = speaker
            } else { speaker = nil }
            let row = SidebarTabRow(tab: tab, selected: current, speaker: speaker,
                close: { [weak self] in self?.closingPeek(.tab(tab.id), self?.prepareTabClose?(tab)) },
                reset: { [weak self] in inGroup ? nil : self?.prepareIconReset?(tab, false) },
                separate: { [weak self] in inGroup ? nil : self?.prepareIconReset?(tab, true) })
            row.audio = tabAudio[tab.id]
            bindLiveRow(row, tab: tab, inGroup: inGroup)
            row.capture = captures[tab.id]
            row.showCapture = { [weak self] anchor in self?.onCaptureMenu?(tab.id, anchor) }
            row.shareable = shareable.contains(tab.id)
            row.prepareShare = { [weak self] in self?.prepareShareThisTab?(tab.id) }
            let selectionItem = inGroup ? splitGroups.first { $0.tabIDs.contains(tab.id) }.map { SidebarItemReference.split($0.id) } ?? .tab(tab.id) : .tab(tab.id)
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
            }
            if !inGroup { addMoveAccessibility(to: row, item: .tab(tab.id), state: state) }
            tabRows.append(row)
            // True no-op only when page URL + reset destination match the last
            // arm and settled art can be adopted onto this replacement row.
            // Fallback / in-flight rows keep loading so a later same-URL
            // history hit is not dropped; `reloadFavicon(for:)` still forces
            // load. Favorite tiles above keep their own settled skip.
            let arm = TabRowFaviconIdentity(pageURL: tab.url, resetDestination: tab.resetDestination)
            let skipArm = tabFaviconArms[tab.id] == arm
                && priorTabFaviconArt[tab.id] != nil
            if let art = priorTabFaviconArt[tab.id], skipArm {
                row.adoptSettledFaviconArt(art)
            } else {
                tabFaviconArms[tab.id] = arm
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
            previewAnchors[.tab(tab.id)] = row
            return row
        }
        var emittedGroups = Set<UUID>()
        func addTab(_ tab: BrowserTab, depth: Int = 0, folder: UUID? = nil) {
            let content: NSView
            if let group = splitGroups.first(where: { $0.tabIDs.contains(tab.id) }) {
                guard group.sidebarAnchorID == tab.id, emittedGroups.insert(group.id).inserted else { return }
                let children = group.tabIDs.compactMap { id in visible.first { $0.id == id } }.map { makeRow($0, inGroup: true) }
                // ChildItemState.isGroupSelected: every child of the selected
                //
                let groupSelected = !renderedNewTabPlaceholder && group.tabIDs == state.selectedTabIDs
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
                addMoveAccessibility(to: groupView, item: .split(group.id), state: state)
                content = groupView
                hierarchyRows.append((.split(group.id), content))
            } else { content = makeRow(tab); hierarchyRows.append((.tab(tab.id), content)) }
            guard let item = hierarchyRows.last?.0 else { return }
            itemRows.append(.item(item, content: content, depth: depth, in: folder))
        }
        var visitedFolders = Set<UUID>()
        func addItems(parentID: UUID?, section: TabKind = .pinned, depth: Int = 0, only: [SidebarItemReference]? = nil) {
            let location = SidebarContainerLocation(spaceID: state.activeSpaceID, folderID: parentID, section: section)
            for item in SidebarHierarchy.children(in: location, state: state) where only?.contains(item) ?? true {
                switch item {
                case .tab(let id):
                    if let tab = tabs.first(where: { $0.id == id }) { addTab(tab, depth: depth, folder: parentID) }
                    continue
                case .split(let id):
                    if let group = splitGroups.first(where: { $0.id == id }), let tab = visible.first(where: { $0.id == group.sidebarAnchorID }) { addTab(tab, depth: depth, folder: parentID) }
                    continue
                case .folder: break
                }
                guard case .folder(let id) = item, visitedFolders.insert(id).inserted,
                      let folder = folders.first(where: { $0.id == id }) else { continue }
                // The row outlives renders so its icon animates a disclosure change.
                let button = folderRowCache[folder.id] ?? SidebarFolderRow(folder: folder)
                renderedFolderRows[folder.id] = button
                button.update(folder, animated: true)
                let peeks = folder.isExpanded ? [] : folderPeeks[folder.id] ?? []
                button.closePeek = peeks.isEmpty ? nil : { [weak self] in self?.closeFolderPeek(folder.id) }
                button.peeked = !peeks.isEmpty
                button.setAccessibilityCustomActions([])
                button.activate = { [weak self] in self?.clearItemSelection(); self?.onToggleFolder?(folder.id) }
                button.doubleClick = isSpaceManagement ? nil : { [weak self] _ in self?.beginFolderTitleEditing(folder.id) ?? false }
                button.selectionClick = { [weak self] event in self?.selectItem(.folder(folder.id), event: event) ?? false }
                button.selectionContext = { [weak self] in self?.selectedItemsMenu(for: .folder(folder.id)) }
                button.beginMove = { [weak self] in self?.beginSelectedMove(.folder(folder.id)) }
                hierarchyRows.append((.folder(folder.id), button))
                if SidebarPreviewPreference.folders.isEnabled {
                    button.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Preview folder", handler: { [weak self] in
                        self?.onPreview?(.folder(folder.id)); return true
                    })])
                }
                previewAnchors[.folder(folder.id)] = button
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
                if let duplicateFolder {
                    button.setAccessibilityCustomActions((button.accessibilityCustomActions() ?? []) + [
                        NSAccessibilityCustomAction(name: "Duplicate") { duplicateFolder() }
                    ])
                }
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
                if delete.isEnabled {
                    button.setAccessibilityCustomActions((button.accessibilityCustomActions() ?? []) + [
                        NSAccessibilityCustomAction(name: "Delete Folder") { deleteFolder() }
                    ])
                }
                button.menu = isSpaceManagement ? managementItemMenu?(.folder(folder.id)) : menu
                if isSpaceManagement { button.setAccessibilityCustomActions([]) }
                addMoveAccessibility(to: button, item: .folder(folder.id), state: state)
                button.palette = palette
                // The folder's row discloses its children's rows. Its AXDisclosing
                // toggles the folder without the click's selection reset.
                itemRows.append(.folder(folder.id, content: button, depth: depth, in: parentID, expanded: folder.isExpanded,
                                        toggle: { [weak self] in self?.onToggleFolder?(folder.id) }))
                if folder.isExpanded {
                    addItems(parentID: folder.id, depth: depth + 1)
                } else if !peeks.isEmpty {
                    addItems(parentID: folder.id, depth: depth + 1, only: peeks)
                }
            }
        }
        let today = tabs.filter { $0.kind == .today && $0.folderID == nil }
        if !isPrivateBrowsing { addItems(parentID: nil) }
        let pinnedRows = itemRows; itemRows.removeAll()
        addItems(parentID: nil, section: .today)
        func makeSectionDivider() -> NSView {
            //
            //
            // spans the cell's insets while Clear is out of the row and ends
            //
            // (buttons .tidyAndClear) is never shown.
            let section = LayoutView()
            //
            //
            pinnedEnd = section
            let clear = ActionButton(SidebarClearAppearance.title) { [weak self] in self?.onClearToday?() }
            clear.identifier = NSUserInterfaceItemIdentifier("sidebarClear")
            SidebarClearAppearance.apply(to: clear, dark: palette?.isDark ?? false)
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
            clearButton = clear
            todayHasTabs = !today.isEmpty
            clear.isAvailable = { [weak self] in self?.clearAvailable ?? false }
            refreshClearAvailability()
            clear.hitTestsWhenTransparent = false
            clearRevealed = clearShown
            clear.isHidden = !clearRevealed; clear.alphaValue = clearRevealed ? 1 : 0
            let line = SidebarHairline(); line.dark = palette?.isDark ?? false
            sectionLine = line
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
            heading.applyStyle(dark: palette?.isDark ?? true, tint: nil)
            heading.updateIncognitoIndicator(shown: showsPrivateProfileIndicator)
            privateUnpinnedHeader = heading
            return heading
        }
        func makeNewTabRow() -> NSView {
            newTabRow.dark = palette?.isDark ?? (effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            newTabRow.paletteTitle = palette?.title ?? .parcInk
            newTabRow.invalidateHover()
            todayStart = newTabRow
            return newTabRow
        }
        pinnedEnd = nil; clearButton = nil; sectionLine = nil; clearRevealed = false; todayHasTabs = false
        var pinnedEntries = pinnedRows.makeIterator(), todayEntries = itemRows.makeIterator()
        // Each visible list entry, in outline order, becomes one outline row.
        var outline: [SidebarOutlineEntry] = []
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
                if isSpaceManagement { todayStart = pinnedEnd; continue }
                outline.append(.init(key: SidebarListRow.newTab, content: makeNewTabRow(), row: slot.row))
                // Without a divider the pinned section ends at New Tab's row.
                if pinnedEnd == nil, !isPrivateBrowsing { pinnedEnd = todayStart }
            }
        }
        // A folder's disclosure or peek change in this Space animates the outline.
        let disclosure = Dictionary(folders.map { ($0.id, $0.isExpanded) }, uniquingKeysWith: { first, _ in first })
        let visiblePeeks = folderPeeks.filter { disclosure[$0.key] != nil }
        let disclosureChanged = renderedDisclosure.map { previous in
            previous.space == state.activeSpaceID && (previous.peeks != visiblePeeks
                || disclosure.contains { id, expanded in previous.expanded[id].map { $0 != expanded } ?? false })
        } ?? false
        renderedDisclosure = (state.activeSpaceID, disclosure, visiblePeeks)
        let previousFrames = disclosureChanged ? list.rowFrames() : [:]
        list.reload(outline)
        folderRowCache = renderedFolderRows
        if disclosureChanged { list.animateDisclosure(from: previousFrames) }
        itemSelection.reconcile(order: selectionOrder)
        for (item, view) in hierarchyRows {
            let select = NSAccessibilityCustomAction(name: "Add or Remove from Selection") { [weak self] in
                guard let self, self.window?.isKeyWindow == true, self.canSelectItems?() == true else { return false }
                self.itemSelection.select(item, order: self.selectionOrder, active: self.selectionActive, extending: false, toggling: true)
                if self.activateSingleSelection() { return true }
                self.focusSelectionList(); return true
            }
            let actions = view.accessibilityCustomActions() ?? []
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
        }
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
        let retainedTabIDs = Set(tabRows.map(\.tabID))
        for id in Set(tabFaviconArms.keys).subtracting(retainedTabIDs) {
            tabFaviconArms.removeValue(forKey: id)
        }
        needsLayout = true; layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(origin.y, max(0, list.frame.height - scroll.contentView.bounds.height))))
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
    private func linkKeyViews() {
        if isSpaceManagement {
            let chain = SidebarAccessibility.keyViewChain(leading: [], favorites: favoritesHost, list: self,
                regions: [list], trailing: [], space: self, beforeList: [spaceHeader])
            SidebarAccessibility.link(chain, within: self, exit: keyViewExit, bypassed: !isPresented)
            return
        }
        let leading: [NSView] = [keyViewGate] + headerControls + [addressButton] + extensionToolbar.orderedButtons
            + [paymentAction, pageActions]
        var regions: [NSView] = [list, miniPlayers]
        if archiveEducationHost.isInteractive { regions += archiveEducation.keyViewControls }
        if let creationView { regions.append(creationView) }
        let chain = SidebarAccessibility.keyViewChain(leading: leading, favorites: favoritesHost, list: self, regions: regions,
                                                      trailing: [footerMore], space: self, beforeList: [spaceHeader])
        SidebarAccessibility.link(chain, within: self, exit: keyViewExit, bypassed: !isPresented)
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
            // The card's page has no App Tray: a shown header sits its
            // padding below the top and the list follows it, else the list
            // starts at the top (SidebarChromeLayout.SpaceHeader).
            spaceHeader.frame = NSRect(x: 0, y: Chrome.SpaceHeader.topPadding, width: width, height: Chrome.SpaceHeader.height)
            let listTop = spaceHeader.isHidden ? 0 : spaceHeader.frame.maxY
            scroll.frame = NSRect(x: 8, y: listTop, width: max(0, width - 16), height: max(0, bounds.height - listTop))
            // Membership rebuilds / disclosure / size changes dirty outline rows
            // or move this frame and still flush. Identical geometry with a
            // clean outline is a true no-op after the row-fill paint skip.
            let listFrame = NSRect(x: 0, y: 0, width: scroll.contentSize.width,
                                   height: max(0, list.contentHeight))
            let listFrameChanged = list.frame != listFrame
            if listFrameChanged { list.frame = listFrame }
            if SidebarOutlineLayoutFlushSkip.shouldFlush(
                frameChanged: listFrameChanged,
                needsLayout: list.needsLayout,
                subtreeNeedsLayout: list.subviews.contains(where: \.needsLayout)
            ) {
                list.layoutSubtreeIfNeeded()
            }
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
            // Shared-quote mode keeps Parc's earlier pill: the URL line only, with the quote below it.
            addressButton.frame.size.height = 18
            addressBackground.frame = NSRect(x: field.minX, y: field.minY, width: max(0, addressButton.frame.maxX - field.minX), height: 18)
        }
        shareQuote.frame = NSRect(x: 16, y: field.minY + 18, width: max(0, addressButton.frame.width - 7), height: 15)
        let iconSide = SidebarAddressSearchIcon.side
        addressSearchIcon.frame = NSRect(x: SidebarAddressSearchIcon.centerX - 1 - iconSide / 2,
                                         y: (addressButton.bounds.height - iconSide) / 2, width: iconSide, height: iconSide)
        addressButton.contentTintColor = palette?.title ?? .parcInk.withAlphaComponent(0.8)
        // The App Tray spans the sidebar below the header with its own 8-point
        // insets, or its empty state fills it, and the list follows it
        // (SidebarChromeLayout.appTrayHeight and tablistTop).
        let grid = FavoriteGridLayout.frames(count: favorites.count, width: width)
        let favoritesHeight = isPrivateBrowsing ? 0 : favoritesEmptyState.trayHeight(gridHeight: grid.height, width: width)
        favoritesHost.frame = NSRect(x: 0, y: Chrome.headerBottom, width: width, height: favoritesHeight)
        favoritesEmptyState.frame = favoritesHost.bounds
        for (button, frame) in zip(favorites, grid.frames) {
            // The host is unflipped; the recovered grid is top-left based.
            button.frame = NSRect(x: frame.minX, y: favoritesHeight - frame.maxY, width: frame.width, height: frame.height)
        }
        // A shown Space header drops the header's 5-point inset, sits 8 below
        // the page's top while the profile has no Favorites, and the list
        // follows its bottom (SidebarChromeLayout.SpaceHeader).
        let showsSpaceHeader = !spaceHeader.isHidden
        spaceHeader.frame = NSRect(x: 0, y: Chrome.SpaceHeader.top(trayHeight: favoritesHeight, hasFavorites: !favorites.isEmpty),
                                   width: width, height: Chrome.SpaceHeader.height)
        let listY = Chrome.tablistTop(trayHeight: favoritesHeight, spaceHeader: showsSpaceHeader, hasFavorites: !favorites.isEmpty)
        let dockTop = bounds.height - Chrome.dockHeight
        let bannerWidth = max(0, width - 16)
        let bannerHeight = archiveEducationHost.occupiesSpace ? archiveEducation.preferredHeight(for: bannerWidth) : 0
        let bannerSpacing: CGFloat = bannerHeight > 0 ? 8 : 0
        archiveEducationHost.frame = NSRect(x: 8, y: dockTop - bannerHeight, width: bannerWidth, height: bannerHeight)
        let playerBottom = dockTop - bannerHeight - bannerSpacing
        let playerHeight = min(miniPlayers.desiredHeight, max(0, playerBottom - listY))
        let playerSpacing: CGFloat = playerHeight > 0 ? 8 : 0
        miniPlayers.frame = NSRect(x: 8, y: playerBottom - playerHeight, width: width - 16, height: playerHeight)
        scroll.frame = NSRect(x: 8, y: listY, width: width - 16,
                              height: max(0, playerBottom - listY - playerHeight - playerSpacing))
        // Membership rebuilds / disclosure / size changes dirty outline rows
        // or move this frame and still flush. Identical geometry with a clean
        // outline is a true no-op after the row-fill paint skip.
        let listFrame = NSRect(x: 0, y: 0, width: scroll.contentSize.width,
                               height: max(0, list.contentHeight))
        let listFrameChanged = list.frame != listFrame
        if listFrameChanged { list.frame = listFrame }
        if SidebarOutlineLayoutFlushSkip.shouldFlush(
            frameChanged: listFrameChanged,
            needsLayout: list.needsLayout,
            subtreeNeedsLayout: list.subviews.contains(where: \.needsLayout)
        ) {
            list.layoutSubtreeIfNeeded()
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
            lastRowMaxY: list.rows.last.map { list.convert($0.bounds, from: $0).maxY }) {
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
        for row in tabRows { row.palette = palette; row.privateBrowsing = isPrivateBrowsing }
        for (_, view) in hierarchyRows {
            (view as? SidebarFolderRow)?.palette = palette
            (view as? SidebarSplitGroupView)?.applyPalette(palette)
        }
        refreshItemSelection()
        keyboardHighlight.color = palette.maxContrastColor
        creationView?.palette = palette
        //
        //
        dropFeedback.tint = palette.maxContrastColor
        for view in list.contents {
            if let row = view as? SidebarNewTabRow {
                row.dark = palette.isDark; row.paletteTitle = palette.title
            } else if let heading = view as? SidebarSpaceHeaderView {
                heading.applyStyle(dark: palette.isDark, tint: nil)
            }
        }
        if let clearButton { SidebarClearAppearance.apply(to: clearButton, dark: palette.isDark, hovered: clearButton.hovered) }
        sectionLine?.dark = palette.isDark
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
        // The Space header's icon takes ViewState headerTintColor, the
        // window's theme palette at +0x70 while that theme belongs to this
        //
        // live. As in the dock, +0x70 is read as maxContrastColor and a Space
        // stored without a theme colour keeps ForegroundTertiary [I].
        let themed = spaces.first { $0.id == activeSpaceID }.map { $0.theme.primaryColor != nil && $0.theme.isValid } ?? false
        spaceHeader.applyStyle(dark: palette.isDark, tint: themed ? palette.maxContrastColor : nil)
    }
    private var selectionOrder: [SidebarItemReference] {
        guard let state = hierarchyState, let spaceID = activeSpaceID else { return [] }
        return hierarchyRows.map(\.0).filter { SidebarHierarchy.location(of: $0, state: state, spaceID: spaceID) != nil }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
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
    /// The split cell keeps its key-dragged fill across row rebuilds until its
    /// drag ends, as ordinary rows do (TAB19).
    private func setKeyDraggedSplit(_ id: UUID, _ dragging: Bool) {
        if dragging { keyDraggedSplitID = id } else if keyDraggedSplitID == id { keyDraggedSplitID = nil }
        for (item, view) in hierarchyRows where item == .split(id) { (view as? SidebarSplitGroupView)?.keyDragged = dragging }
    }
    /// `listFocused` is passed while first responder changes, before the window
    /// reports it.
    private func refreshItemSelection(listFocused: Bool? = nil) {
        let listFocused = listFocused ?? (window?.firstResponder === self)
        for (item, view) in hierarchyRows {
            let selected = itemSelection.items.contains(item)
            view.setAccessibilitySelected(selected)
            let focused = listFocused && itemSelection.focus == item
            if let row = view as? SidebarTabRow {
                // Multi-selection is TabCellBackgroundMutiselected. List-stop
                // focus uses HighlightRingView; a 1-point accent border on this
                // layer rounded the row and clipped the current-item shadow.
                row.multiSelected = selected
                row.listFocusRing = focused
                continue
            }
            if let group = view as? SidebarSplitGroupView {
                group.multiSelected = selected
                group.listFocusRing = focused
                continue
            }
            if let folder = view as? SidebarFolderRow {
                // A folder's ListHeaderCellView has the same CellSelectionStateView.
                folder.multiSelected = selected
                folder.listFocusRing = focused
                continue
            }
            view.wantsLayer = true
            view.layer?.borderWidth = selected ? 2 : (focused ? 1 : 0)
            view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(selected ? 0.8 : 0.4).cgColor(in: view.effectiveAppearance)
            view.layer?.cornerRadius = 7
        }
        list.select(itemSelection.items, single: itemSelection.singleItem, active: selectionActive)
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
            if let row = hierarchyRows.first(where: { $0.0 == next })?.1 { row.scrollToVisible(row.bounds) }
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

    private func addMoveAccessibility(to view: NSView, item: SidebarItemReference, state: BrowserState) {
        // AX alternatives use the same original-item transaction. They do not
        // synthesize drag events or silently move an individual split child.
        let actions = moveAccessibilityActions(item: item, state: state)
        // Rows are assembled before attachment; keep their stored Preview.
        let existing = (view as? SidebarTabRow)?.supplementaryAccessibilityActions
            ?? view.accessibilityCustomActions() ?? []
        view.setAccessibilityCustomActions(existing + actions)
    }
    private func moveAccessibilityActions(item: SidebarItemReference, state: BrowserState) -> [NSAccessibilityCustomAction] {
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
        if let previous = springFolder { previous.timer.invalidate(); renderedFolderRows[previous.id]?.dropTarget = false }
        springFolder = nil
        guard let id else { return }
        renderedFolderRows[id]?.dropTarget = true
        let timer = Timer(timeInterval: Self.springLoadingDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.springFolder?.id == id else { return }
                self.springFolder = nil
                self.renderedFolderRows[id]?.dropTarget = false
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
            ? list.rows.last.map { convert($0.bounds, from: $0).maxY - SidebarChromeLayout.tablistIntercellSpacing / 2 } : nil
        let pinnedBottom = pinnedEnd.map { convert($0.bounds, from: $0).midY } ?? listEnd ?? scroll.frame.minY
        let todayTop = todayStart.map { convert($0.bounds, from: $0).midY } ?? listEnd ?? scroll.frame.maxY
        // Insertion cues sit on the outline's row boundary, in the intercell
        // gap between two visible rows, so each index has one position; the
        // pinned section ends at the boundary above the divider cell.
        let outset = SidebarChromeLayout.tablistRowBoundaryOutset
        let pinnedEndBoundary = pinnedEnd.map {
            convert($0.bounds, from: $0).minY - ($0 is SidebarNewTabRow ? outset : SidebarChromeLayout.tablistIntercellSpacing / 2)
        } ?? listEnd
        for (item, row) in hierarchyRows {
            let rect = convert(row.bounds, from: row)
            guard let location = SidebarHierarchy.location(of: item, state: state, spaceID: spaceID),
                  point.y <= rect.maxY,
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
                    // After a folder means after its whole visible subtree.
                    // The insertion cue must not imply an insert into it.
                    for (child, view) in hierarchyRows {
                        var ancestor = SidebarHierarchy.location(of: child, state: state, spaceID: spaceID)?.folderID
                        var seen = Set<UUID>()
                        while let id = ancestor, seen.insert(id).inserted {
                            if id == folderID { boundary = max(boundary, convert(view.bounds, from: view).maxY + outset); break }
                            ancestor = state.folders.first { $0.id == id }?.parentID
                        }
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
