import AppKit

extension SidebarTabRow: SplitDropCardSource {}

///
/// `SplitViewCellState`): one outline row whose `CellSelectionStateView`
/// draws the current, key-dragged, multi-selected, hovered (always
///
/// `SplitViewCellChildrenContainerView` lays the children out with separator
/// layers, or whose `SplitViewCellCustomInfoView` replaces them; and whose own
/// Close shows while it is hovered. Geometry and producers are in
/// `SidebarSplitCellLayout`. The container keeps each original child's AX,
/// close/capture controls and authenticated drag source.
@MainActor
final class SidebarSplitGroupView: NSView, SidebarDeferredAccessibilityActions {
    var deferredAccessibilityActions: (index: Int, make: () -> [NSAccessibilityCustomAction])?
    var storedAccessibilityActions: [NSAccessibilityCustomAction] { super.accessibilityCustomActions() ?? [] }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        window != nil && !isHiddenOrHasHiddenAncestor ? mergedAccessibilityActions : []
    }
    let groupID: UUID
    let rows: [SidebarTabRow]
    private let background = SidebarRowBackgroundView()
    private let moveSurface = SidebarSplitMoveSurface()
    private let closeButton: SidebarRowActionButton
    private var separators: [CALayer] = []
    private let titleView: SidebarSplitTitleView
    private let hasCustomTitle: Bool
    private var captureButtons: [ActionButton] = []
    /// Whether the cell has its own close configuration (its children carry
    ///
    let hasClose: Bool
    let closeAction: SidebarSplitCellLayout.CloseAction
    /// `isCurrentItem` / `ChildrenContainerView.ViewState.isGroupSelected`.
    let selected: Bool
    private var hover = false
    private var dimmed = false
    private var tracking: NSTrackingArea?
    private var windowObservers: [NSObjectProtocol] = []
    private var palette: ThemeChromePalette?
    var multiSelected = false { didSet { if multiSelected != oldValue { updateAppearance() } } }
    ///
    var keyboardHighlighted = false { didSet { if keyboardHighlighted != oldValue { updateAppearance() } } }
    /// Tab-into-list focus uses the split's HighlightRingView, not a clipped
    /// 1-point accent border on this cell's layer.
    var listFocusRing = false { didSet { if listFocusRing != oldValue { updateAppearance() } } }
    /// The split is the key item of an in-progress sidebar drag.
    var keyDragged = false { didSet { if keyDragged != oldValue { updateAppearance() } } }
    var onKeyDrag: ((Bool) -> Void)? { didSet { moveSurface.onKeyDrag = onKeyDrag } }
    var prepareActivation: (() -> (() -> Bool)?)? {
        didSet { titleView.prepareActivation = prepareActivation; moveSurface.prepareActivation = prepareActivation }
    }
    var beginMove: (() -> SidebarMoveSession?)? { didSet { moveSurface.beginMove = beginMove } }
    var selectionClick: ((NSEvent) -> Bool)? { didSet { moveSurface.selectionClick = selectionClick; titleView.selectionClick = selectionClick } }
    var selectionContext: (() -> NSMenu?)? { didSet { moveSurface.selectionContext = selectionContext } }
    ///
    /// action is prepared only when pressed; `closeAvailable` is the cheap
    /// check that enables the button.
    var prepareClose: (() -> (() -> Bool)?)? { didSet { closeButton.prepareAction = prepareClose; closeButton.refreshAvailability() } }
    var closeAvailable: (() -> Bool)? { didSet { closeButton.isAvailable = closeAvailable; closeButton.refreshAvailability() } }
    override func menu(for event: NSEvent) -> NSMenu? { selectionContext?() ?? super.menu(for: event) }
    /// The split menu is built when it opens, so VoiceOver's Show Menu asks for it too.
    override func accessibilityPerformShowMenu() -> Bool {
        guard window != nil, !isHiddenOrHasHiddenAncestor, let menu = selectionContext?() ?? menu else { return false }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY), in: self)
        return true
    }
    override var isFlipped: Bool { true }
    init(group: BrowserSplitLayout, rows: [SidebarTabRow], selected: Bool, today: Bool,
         closeAction: SidebarSplitCellLayout.CloseAction, privateWindow: Bool) {
        groupID = group.id; self.rows = rows; self.selected = selected
        hasCustomTitle = SidebarSplitCellLayout.usesCustomInfo(title: group.customTitle, hasIcon: group.customIcon != nil, editing: false)
        hasClose = SidebarSplitCellLayout.splitHasClose(today: today, current: selected, customInfo: hasCustomTitle)
        self.closeAction = closeAction
        let name = group.customTitle.flatMap { $0.isEmpty ? nil : $0 }
        titleView = SidebarSplitTitleView(title: name ?? SidebarSplitCellLayout.defaultTitle(count: rows.count),
                                          count: rows.count, named: name != nil)
        closeButton = SidebarRowActionButton(SidebarSplitCellLayout.closeTitle(closeAction, privateWindow: privateWindow))
        super.init(frame: .zero)
        // Separator sublayers need a host layer; rounding and the selected
        // shadow belong to CellSelectionStateView. Clipping here swallowed
        // TabCellShadowSelected and the children's TabCellChildBackground pills.
        wantsLayer = true
        clipsToBounds = false
        layer?.masksToBounds = false
        layer?.allowsGroupOpacity = false
        addSubview(background)
        moveSurface.setAccessibilityElement(false)
        addSubview(moveSurface)
        let childClose = SidebarSplitCellLayout.childCloseAvailable(today: today, current: selected, customInfo: hasCustomTitle)
        rows.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = true; $0.compactSplitChild = true
            $0.splitChildCloseAvailable = childClose; addSubview($0)
            // A child's press belongs to the split's one outline row: its drag
            //
            $0.beginGroupDrag = { [weak self] press, drag in self?.moveSurface.beginDrag(from: press, with: drag) }
        }
        addSubview(titleView)
        for row in rows {
            guard let capture = row.capture else { continue }
            let button = ActionButton("Active capture", symbol: capture.symbol)
            button.imagePosition = .imageOnly
            //
            LiveShortcutToolTip.set(button, "This tab is using your camera or microphone"); button.setAccessibilityLabel(capture.summary)
            button.actionBlock = { [weak row, weak button] in
                guard let row, let button else { return }
                row.showCapture?(button)
            }
            captureButtons.append(button); addSubview(button)
        }
        //
        // is one of the split's accessibility children.
        closeButton.imagePosition = .imageOnly
        closeButton.isHidden = true
        //
        LiveShortcutToolTip.set(closeButton, SidebarSplitCellLayout.closeTitle(closeAction, privateWindow: privateWindow),
                                commandID: "closeTab:")
        addSubview(closeButton)
        for _ in rows.dropLast() {
            let separator = CALayer()
            separator.actions = ["position": NSNull(), "bounds": NSNull(), "hidden": NSNull(), "backgroundColor": NSNull()]
            separators.append(separator)
        }
        titleView.setIcon(group.customIcon)
        titleView.makeMenu = { [weak self] in self?.selectionContext?() ?? self?.menu }
        closeButton.makeMenu = { [weak self] in self?.selectionContext?() ?? self?.menu }
        titleView.beginMoveDrag = { [weak self] press, drag in self?.moveSurface.beginDrag(from: press, with: drag) }
        moveSurface.dragPreview = self
        moveSurface.makeDragImage = { [weak self] in self?.dragImage() }
        updateTitlePresentation()
        setAccessibilityElement(true); setAccessibilityRole(.group)
        setAccessibilityLabel(group.customTitle.map { "\($0), Split View, \(rows.count) tabs" } ?? "Split View, \(rows.count) tabs")
        updateAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { for observer in windowObservers { NotificationCenter.default.removeObserver(observer) } }
    ///
    ///
    var appearanceAnchorRect: NSRect { convert(titleView.iconContainerFrame, from: titleView) }
    func applyPalette(_ palette: ThemeChromePalette) {
        self.palette = palette
        titleView.applyColors(title: palette.title, secondary: palette.subtitle, countText: palette.maxContrastColor,
                              countBackground: palette.cutoutColor, dark: palette.isDark)
        captureButtons.forEach { $0.contentTintColor = palette.title }
        updateAppearance()
    }
    private var dark: Bool {
        palette?.isDark ?? (effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }
    /// The cell's `CellSelectionStateView` and the container's separators
    ///
    private func updateAppearance() {
        background.dark = dark
        background.ringColor = palette?.maxContrastColor ?? .labelColor
        background.appearanceState = SidebarRowAppearance(current: selected, multiSelected: multiSelected, hovered: hover,
                                                          highlighted: keyboardHighlighted || listFocusRing, dimmed: dimmed,
                                                          keyDragged: keyDragged)
        closeButton.dark = dark
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let color = SidebarSplitCellLayout.separatorColor(dark: dark).cgColor
        for separator in separators {
            separator.backgroundColor = color
            separator.isHidden = selected || hasCustomTitle || titleView.editingTitle
        }
        CATransaction.commit()
    }
    private var customInfoShown: Bool { hasCustomTitle || titleView.editingTitle }
    /// Close shows while the cell is hovered and has a close configuration
    ///
    private var closeShown: Bool { hover && hasClose && !titleView.editingTitle }
    private func updateTitlePresentation() {
        let custom = customInfoShown
        rows.forEach { $0.isHidden = custom }
        titleView.isHidden = !custom
        captureButtons.forEach { $0.isHidden = !custom || titleView.editingTitle }
        titleView.trailingControlWidth = titleView.editingTitle ? 0 : CGFloat(captureButtons.count) * 23
        updateAccessibilityChildren()
        updateAppearance()
        needsLayout = true
    }
    private func updateAccessibilityChildren() {
        let close: [NSView] = closeButton.isHidden ? [] : [closeButton]
        setAccessibilityChildren((customInfoShown ? [titleView] + captureButtons.filter { !$0.isHidden } : rows) + close)
    }
    @discardableResult func beginTitleEditing(_ title: String, finished: @escaping (String?) -> Void) -> Bool {
        titleView.isHidden = false; layoutSubtreeIfNeeded()
        let began = titleView.begin(title: title) { [weak self] value in
            self?.updateTitlePresentation(); finished(value)
        }
        updateTitlePresentation()
        return began
    }
    func cancelTitleEditing() { titleView.cancel() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
        // A rebuilt row under a stationary pointer reconciles its hover.
        setHover(window.map { $0.isKeyWindow && bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false)
    }
    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea === tracking { setHover(true) } else { super.mouseEntered(with: event) }
    }
    override func mouseExited(with event: NSEvent) {
        if event.trackingArea === tracking { setHover(false) } else { super.mouseExited(with: event) }
    }
    /// The split's page left the screen with the pointer over it.
    func resetPointer() { setHover(false) }
    private func setHover(_ value: Bool) {
        guard hover != value else { return }
        hover = value
        closeButton.refreshAvailability()
        updateAppearance(); needsLayout = true
    }
    ///
    ///
    /// the outline's width and the 40-point row and cached as a bitmap
    ///
    /// the split's selection state without the hover fill or the cell's Close.
    /// Parc's row is the cell's visible background, so its own bounds frame the
    ///
    func dragImage() -> NSImage {
        let wasHovered = hover
        setHover(false); layoutSubtreeIfNeeded()
        let image = NSImage(size: bounds.size)
        if let bitmap = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: bitmap); image.addRepresentation(bitmap)
        }
        setHover(wasHovered); layoutSubtreeIfNeeded()
        return image
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers = []
        if let newWindow {
            let center = NotificationCenter.default
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                         NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification] {
                windowObservers.append(center.addObserver(forName: name, object: newWindow, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated {
                        if note.name == NSWindow.didResignKeyNotification { self?.setHover(false) }
                        self?.updateDim()
                    }
                })
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateDim() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateAppearance() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); needsLayout = true }
    /// `SplitViewCellState.shouldDim` from the window's key/main state, as
    /// ordinary rows take it (TAB19).
    private func updateDim() {
        let value = window.map { !$0.isKeyWindow && !$0.isMainWindow } ?? false
        guard dimmed != value else { return }
        dimmed = value; updateAppearance()
    }
    override func layout() {
        super.layout()
        background.frame = bounds
        moveSurface.frame = bounds
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let layout = SidebarSplitCellLayout.layout(in: bounds, childCount: rows.count, showsClose: closeShown, pixel: 1 / scale)
        func aligned(_ rect: NSRect) -> NSRect { window == nil ? rect : backingAlignedRect(rect, options: .alignAllEdgesNearest) }
        for (row, frame) in zip(rows, layout.children) { row.frame = aligned(frame) }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if let host = layer {
            for (separator, frame) in zip(separators, layout.separators) {
                if separator.superlayer !== host { host.addSublayer(separator) }
                separator.frame = aligned(frame)
            }
        }
        CATransaction.commit()
        if closeButton.isHidden == closeShown { closeButton.isHidden = !closeShown; updateAccessibilityChildren() }
        if let close = layout.close { closeButton.frame = close }
        titleView.frame = bounds
        titleView.titleTrailing = layout.infoTitleTrailing
        for (index, button) in captureButtons.enumerated() {
            // Parc's active-capture controls sit before the title's trailing edge.
            button.frame = NSRect(x: max(SidebarSplitCellLayout.infoTitleInset, layout.infoTitleTrailing - CGFloat(index + 1) * 23),
                                  y: ((bounds.height - 25) / 2).rounded(.down), width: 23, height: 25)
        }
        updateAppearance()
    }
}

///
///
///
/// separate handle. A press in the cell (outside a child) activates the split.
@MainActor
final class SidebarSplitMoveSurface: SidebarMoveHandle {
    var prepareActivation: (() -> (() -> Bool)?)?
    var onKeyDrag: ((Bool) -> Void)?
    private var pendingActivation: (() -> Bool)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        activate = { [weak self] in
            let action = self?.pendingActivation; self?.pendingActivation = nil
            _ = action?()
        }
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        pendingActivation = window?.isKeyWindow == true && window?.attachedSheet == nil ? prepareActivation?() : nil
        super.mouseDown(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        pendingActivation = nil
    }
    override func mouseDragged(with event: NSEvent) {
        let dragging = sidebarDrag != nil
        super.mouseDragged(with: event)
        if !dragging, sidebarDrag != nil { pendingActivation = nil; onKeyDrag?(true) }
    }
    /// A drag that starts on the custom-info cell.
    func beginDrag(from press: NSEvent, with drag: NSEvent) {
        super.mouseDown(with: press)
        pendingActivation = nil
        mouseDragged(with: drag)
    }
    override func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let dragging = sidebarDrag != nil
        super.draggingSession(session, endedAt: screenPoint, operation: operation)
        if dragging { onKeyDrag?(false) }
    }
    ///
    ///
    ///
    ///
    /// page or editor accepts the split. A cancelled or refused drag slides
    ///
    override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        guard context == .withinApplication else { return .copy }
        return sidebarDrag?.allowsCopy == true ? [.move, .copy] : .move
    }
    override func accessibilityPerformPress() -> Bool { false }
}
