import AppKit

@MainActor
private final class EaselToolGlyphView: NSView {
    var paint: ((NSRect) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { paint?(bounds) }
}

@MainActor
final class EaselToolButton: NoteControlButton {
    var content: NoteToolbarButton.Content { didSet { invalidateIntrinsicContentSize(); redrawFace() } }
    var showsDisclosure = false { didSet { invalidateIntrinsicContentSize(); layoutGlyph(); redrawFace() } }
    var iconPointSize: CGFloat = 14 { didSet { redrawFace() } }
    var isCurrent = false {
        didSet {
            guard isCurrent != oldValue else { return }
            refreshFace(animated: true)
            setAccessibilityValue(isCurrent || isChecked ? "on" : nil)
        }
    }
    override var isChecked: Bool { didSet { if isCurrent, !isChecked { setAccessibilityValue("on") } } }
    private let lift = EaselToolGlyphView()
    private let glyph = EaselToolGlyphView()
    private var lifted = false
    private static let liftKey = NoteAnimation.keyPrefix + "easel.tool.lift"
    private static let flourishKey = NoteAnimation.keyPrefix + "easel.tool.flourish"
    var onDragMoved: ((NSPoint) -> Void)?
    var onDragEnded: ((NSPoint?) -> Void)?
    var onShowMenu: (() -> Void)?
    private(set) var pressedDisclosure = false
    private(set) var pressedWithPointer = false
    private var downPoint: NSPoint?
    private var dragging = false
    private var dragCancelled = false
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    init(_ content: NoteToolbarButton.Content, label: String) {
        self.content = content
        super.init(frame: NSRect(origin: .zero, size: NoteTheme.toolbarButtonSize))
        lift.addSubview(glyph)
        addSubview(lift)
        glyph.paint = { [weak self] rect in self?.drawGlyph(in: rect) }
        setAccessibilityLabel(label)
        setFrameSize(intrinsicContentSize)
        NoteAnimation.observeReduceMotion(self) { [weak self] in self?.settleGlyph() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var textFont: NSFont { NoteTheme.chromeFont(13.5) }

    override var intrinsicContentSize: NSSize {
        let height = NoteTheme.toolbarButtonSize.height
        let disclosure: CGFloat = showsDisclosure ? 12 : 0
        switch content {
        case .icon: return NSSize(width: NoteTheme.toolbarButtonSize.width + disclosure, height: height)
        case .text(let text): return NSSize(width: ceil(textWidth(text)) + 16 + disclosure, height: height)
        case .iconAndText(_, let text): return NSSize(width: ceil(textWidth(text)) + 36 + disclosure, height: height)
        }
    }

    private func textWidth(_ text: String) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: textFont]).size().width
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutGlyph()
    }

    private func layoutGlyph() {
        let area = NSRect(x: 0, y: 0, width: max(0, bounds.width - (showsDisclosure ? 12 : 0)), height: bounds.height)
        guard lift.frame != area else { return }
        NoteAnimation.withoutAnimation {
            lift.frame = area
            glyph.frame = lift.bounds
        }
        glyph.needsDisplay = true
    }

    private func redrawFace() {
        needsDisplay = true
        glyph.needsDisplay = true
    }

    override func fill(hovered: Bool, pressed: Bool, checked: Bool) -> NSColor? {
        isCurrent ? nil : super.fill(hovered: hovered, pressed: pressed, checked: checked)
    }

    override func ink(hovered: Bool, pressed: Bool, checked: Bool) -> NSColor {
        super.ink(hovered: hovered, pressed: pressed, checked: checked || isCurrent)
    }

    override func refreshFace(animated: Bool) {
        super.refreshFace(animated: animated)
        glyph.needsDisplay = true
        let wantsLift = isHovered && isEnabled && window != nil
        guard wantsLift != lifted else { return }
        lifted = wantsLift
        guard let layer = lift.layer else { return }
        let rise = wantsLift && !NoteAnimation.reduceMotion ? -CGFloat(EaselFloatingBar.hoverLift) : 0
        NoteAnimation.spring(layer, "transform", to: NSValue(caTransform3D: CATransform3DMakeTranslation(0, rise, 0)),
                             spring: .highlight, key: Self.liftKey)
    }

    func playFlourish(_ flourish: EaselToolFlourish) {
        guard window != nil, !isHiddenOrHasHiddenAncestor, !NoteAnimation.reduceMotion, let layer = glyph.layer else { return }
        let centre = NoteAnimation.layerCenter(layer)
        let values = flourish.frames().map { frame -> NSValue in
            var transform = CATransform3DMakeTranslation(centre.x + CGFloat(frame.dx), centre.y + CGFloat(frame.dy), 0)
            transform = CATransform3DRotate(transform, CGFloat(frame.rotation) * .pi / 180, 0, 0, 1)
            transform = CATransform3DScale(transform, CGFloat(frame.scaleX), CGFloat(frame.scaleY), 1)
            return NSValue(caTransform3D: CATransform3DTranslate(transform, -centre.x, -centre.y, 0))
        }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = values
        animation.duration = flourish.duration
        animation.calculationMode = .linear
        NoteAnimation.withoutAnimation { layer.transform = CATransform3DIdentity }
        _ = NoteAnimation.run(animation, on: layer, key: Self.flourishKey)
    }

    private func settleGlyph() {
        lifted = false
        for view in [lift, glyph] {
            guard let layer = view.layer else { continue }
            NoteAnimation.settle(layer, keys: [Self.liftKey, Self.flourishKey])
            NoteAnimation.withoutAnimation { layer.transform = CATransform3DIdentity }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { settleGlyph() }
    }

    override func drawContent(in bounds: NSRect, ink: NSColor) {
        guard showsDisclosure else { return }
        let chevronBox = NSRect(x: bounds.maxX - 16, y: bounds.minY, width: 10, height: bounds.height)
        if let chevron = NoteIconRenderer.symbol("chevron.down", pointSize: 8, weight: .bold) {
            NoteIconRenderer.drawTemplate(chevron, centeredIn: chevronBox, tint: NoteTheme.menuTertiaryInk)
        }
    }

    private func drawGlyph(in area: NSRect) {
        let ink = currentInk
        switch content {
        case .icon(let icon):
            NoteIconRenderer.draw(icon, in: NSRect(x: area.midX - 10, y: area.midY - 10, width: 20, height: 20), tint: ink,
                                  pointSize: iconPointSize, weight: .semibold, decoration: [])
        case .text(let text):
            drawTitle(text, in: NSRect(x: area.minX + 8, y: area.minY, width: area.width - 16, height: area.height), ink: ink)
        case .iconAndText(let icon, let text):
            let box = NSRect(x: area.minX + 6, y: area.midY - 9, width: 18, height: 18)
            NoteIconRenderer.draw(icon, in: box, tint: ink, pointSize: iconPointSize - 1, weight: .semibold, decoration: [])
            drawTitle(text, in: NSRect(x: box.maxX + 4, y: area.minY, width: area.maxX - box.maxX - 12, height: area.height), ink: ink)
        }
    }

    private func drawTitle(_ text: String, in rect: NSRect, ink: NSColor) {
        let font = textFont
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .center
        let height = ceil(font.ascender - font.descender)
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph])
            .draw(with: NSRect(x: rect.minX, y: (rect.midY - height / 2).rounded(), width: rect.width, height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    override var acceptsFirstResponder: Bool { isEnabled && NSApplication.shared.isFullKeyboardAccessEnabled }
    override var canBecomeKeyView: Bool { acceptsFirstResponder && !isHiddenOrHasHiddenAncestor }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: NoteTheme.controlRadius, yRadius: NoteTheme.controlRadius).fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pressedDisclosure = showsDisclosure && point.x >= bounds.maxX - 14
        pressedWithPointer = true
        downPoint = event.locationInWindow
        dragging = false
        dragCancelled = false
        super.mouseDown(with: event)
    }

    private func watchDrag() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let cancelled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.dragging else { return false }
                self.cancelDrag()
                return true
            }
            return cancelled ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelDrag() }
        }
    }

    private func unwatchDrag() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        keyMonitor = nil
        resignObserver = nil
    }

    private func cancelDrag() {
        guard dragging else { return }
        dragging = false
        dragCancelled = true
        downPoint = nil
        unwatchDrag()
        setPressed(false)
        onDragEnded?(nil)
        NSCursor.arrow.set()
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        guard !dragCancelled, let start = downPoint, let onDragMoved else { return }
        if !dragging, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 6 {
            dragging = true
            watchDrag()
        }
        if dragging {
            onDragMoved(event.locationInWindow)
            NSCursor.closedHand.set()
        }
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = dragging
        let cancelled = dragCancelled
        dragging = false
        dragCancelled = false
        downPoint = nil
        unwatchDrag()
        if cancelled { setPressed(false); return }
        if wasDragging {
            let inside = bounds.contains(convert(event.locationInWindow, from: nil))
            onDragEnded?(inside ? nil : event.locationInWindow)
        }
        super.mouseUp(with: event)
    }

    override func performClick(_ sender: Any?) {
        pressedDisclosure = false
        pressedWithPointer = false
        super.performClick(sender)
    }

    override func accessibilityPerformPress() -> Bool {
        pressedDisclosure = false
        pressedWithPointer = false
        return super.accessibilityPerformPress()
    }

    override func accessibilityPerformShowMenu() -> Bool {
        guard let onShowMenu else { return false }
        pressedWithPointer = false
        onShowMenu()
        return true
    }
}

@MainActor
private final class EaselPaletteDivider: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuSeparator, in: self) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

@MainActor
private final class EaselPaletteStrip: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class EaselToolCurrentPill: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = NoteTheme.controlRadius
        layer?.cornerCurve = .continuous
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateLayer() { layer?.backgroundColor = NoteTheme.resolved(NoteTheme.checkedFill, in: self) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

@MainActor
private final class EaselPaletteScroller: NSScrollView {
    var passthrough: (() -> NSView?)?
    private var routesOut = false

    override func scrollWheel(with event: NSEvent) {
        let overflows = (documentView?.frame.width ?? 0) > contentView.bounds.width + 0.5
        if event.phase == .began || (event.phase.isEmpty && event.momentumPhase.isEmpty) {
            routesOut = !overflows || abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX)
        }
        if routesOut, let target = passthrough?() {
            target.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }
}

@MainActor
final class EaselFieldMenuView: NSView, NoteFloatingPanelContent {
    var preferredSizeDidChange: (() -> Void)?
    let field = NoteSearchField(placeholder: "100%")
    let list = NoteMenuList()
    private let noticeLabel = NSTextField(labelWithString: "")
    var notice: String? {
        didSet {
            noticeLabel.stringValue = notice ?? ""
            noticeLabel.isHidden = notice == nil
            invalidateIntrinsicContentSize()
            needsLayout = true
            preferredSizeDidChange?()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        field.showsIcon = false
        field.textField.setAccessibilityLabel("Zoom percentage")
        list.minimumWidth = 236
        list.preferredSizeDidChange = { [weak self] in self?.preferredSizeDidChange?() }
        noticeLabel.font = NoteTheme.captionFont()
        noticeLabel.textColor = NoteTheme.destructiveInk
        noticeLabel.isHidden = true
        addSubview(field)
        addSubview(noticeLabel)
        addSubview(list)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private var noticeHeight: CGFloat { notice == nil ? 0 : 20 }

    override var intrinsicContentSize: NSSize {
        let menu = list.intrinsicContentSize
        return NSSize(width: max(236, menu.width), height: NoteTheme.menuInset * 2 + NoteTheme.fieldHeight + noticeHeight + menu.height)
    }

    override var fittingSize: NSSize { intrinsicContentSize }

    override func layout() {
        super.layout()
        let inset = NoteTheme.menuInset
        field.frame = NSRect(x: inset * 2, y: inset * 2, width: max(0, bounds.width - inset * 4), height: NoteTheme.fieldHeight)
        noticeLabel.frame = NSRect(x: inset * 2 + 4, y: field.frame.maxY + 2, width: max(0, bounds.width - inset * 4 - 8), height: 16)
        let top = field.frame.maxY + noticeHeight
        list.frame = NSRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
    }
}

@MainActor
final class EaselToolPalette: NSView {
    enum Insert: String { case mermaid, templates }
    enum Menu {
        case shapes, connectors, draw, media, web, code

        var group: EaselInsertKind.Group? {
            switch self {
            case .media: return .media
            case .web: return .web
            case .code: return .code
            case .shapes, .connectors, .draw: return nil
            }
        }
    }

    private enum Entry: Hashable {
        case tool(EaselTool)
        case menu(Menu)
        case insert(Insert)
        case zoom
    }

    private struct Placed {
        let entry: Entry
        let group: Int
        let button: EaselToolButton
    }

    static let shapeTools: [EaselShape] = [.rectangle, .ellipse]
    static let connectorTools: [EaselTool] = [.elbowConnector, .curvedConnector, .straightConnector]
    static let drawTools: [EaselTool] = [.marker, .highlighter, .washi, .eraser]

    var onTool: ((EaselTool, NSView?) -> Void)?
    var onShape: ((EaselShape) -> Void)?
    var onMindMap: (() -> Void)?
    static let mindMapSymbol = "point.3.connected.trianglepath.dotted"
    var onInsert: ((Insert, NSButton) -> Void)?
    var onInsertKind: ((EaselInsertKind) -> Void)?
    var canInsert: (EaselInsertKind) -> Bool = { _ in true }
    var onZoom: ((EaselZoomCommand) -> Void)?
    var onZoomTo: ((Double) -> Void)?
    var onDrag: ((EaselTool, NSPoint?, Bool) -> Void)?
    var onMenuClose: (() -> Void)?
    var onPreferredSizeChange: (() -> Void)?
    var canZoomToSelection: () -> Bool = { false }
    var shapePicker: ((@escaping (EaselShape) -> Void) -> NSView)?
    var shapePickerKeepsOpen = false { didSet { if shapePickerKeepsOpen { exemptPinnedViews() } } }
    var keepOpenViews: () -> [NSView] = { [] }
    var scrollPassthrough: (() -> NSView?)? {
        get { scroller.passthrough }
        set { scroller.passthrough = newValue }
    }
    var showsTemplates = false { didSet { if showsTemplates != oldValue { rebuild() } } }
    var showsMermaid = false { didSet { if showsMermaid != oldValue { rebuild() } } }

    private(set) var tool: EaselTool = .select
    private var shape: EaselShape = .rectangle
    private var connector: EaselTool = .elbowConnector
    private var brush: EaselTool = .marker
    private var lastKind: [EaselInsertKind.Group: EaselInsertKind] = [.media: .image, .web: .embed, .code: .codeBlock]
    private var zoomPercent = 100
    private let pill = EaselToolbarPill(frame: .zero)
    private let scroller = EaselPaletteScroller()
    private let strip = EaselPaletteStrip()
    private let current = EaselToolCurrentPill(frame: .zero)
    private var dimTracking: NSTrackingArea?
    private var dimMonitor: Any?
    private var dimmed = false
    private var draggingTool = false
    private var tracksTool = false
    private static let dimKey = NoteAnimation.keyPrefix + "easel.bar.dim"
    private static let entranceFadeKey = NoteAnimation.keyPrefix + "easel.bar.entrance.fade"
    private static let entranceRiseKey = NoteAnimation.keyPrefix + "easel.bar.entrance.rise"
    private static let currentFadeKey = NoteAnimation.keyPrefix + "easel.bar.current.fade"
    private var placed: [Placed] = []
    private var dividers: [NSView] = []
    private var popover: NotePagePopover?
    private var openEntry: Entry?

    static let padding = EaselAppearance.toolbarInset
    static let spacing: CGFloat = 2
    static let dividerSlot: CGFloat = 9

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        EaselAppearance.configureToolbarScroll(scroller)
        scroller.documentView = strip
        current.isHidden = true
        strip.addSubview(current)
        pill.addSubview(scroller)
        addSubview(pill)
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Easel tools")
        rebuild()
        NoteAnimation.observeReduceMotion(self) { [weak self] in
            guard let self, let layer = self.layer else { return }
            NoteAnimation.settle(layer, keys: [Self.entranceFadeKey, Self.entranceRiseKey])
            NoteAnimation.withoutAnimation { layer.opacity = 1; layer.transform = CATransform3DIdentity }
            if let marker = self.current.layer { NoteAnimation.settle(marker, keys: [NoteAnimation.positionKey, NoteAnimation.boundsKey, Self.currentFadeKey]) }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private(set) var preferredWidth: CGFloat = 0

    func button(for insert: Insert) -> NSButton? { placed.first { $0.entry == .insert(insert) }?.button }

    func update(tool: EaselTool, shape: EaselShape) {
        let changed = tracksTool && tool != self.tool
        tracksTool = true
        self.tool = tool
        if tool == .rectangle { self.shape = shape }
        if tool == .ellipse { self.shape = .ellipse }
        if tool.drawsConnector { connector = tool }
        if Self.drawTools.contains(tool) { brush = tool }
        refreshStates()
        placeCurrent(animated: changed)
        guard changed, let button = currentButton else { return }
        strip.scrollToVisible(button.frame.insetBy(dx: -Self.padding, dy: 0))
        if let flourish = EaselToolFlourish.flourish(for: tool) { button.playFlourish(flourish) }
    }

    private var currentButton: EaselToolButton? { placed.first { $0.button.isCurrent }?.button }

    private func placeCurrent(animated: Bool) {
        guard let button = currentButton else {
            if !current.isHidden { NoteAnimation.fade(current, visible: false) { [weak self] in self?.current.isHidden = true } }
            return
        }
        let frame = button.frame
        let box = EaselFloatingBar.pillFrame(button: EaselRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height))
        let target = NSRect(x: box.x, y: box.y, width: box.width, height: box.height)
        let appearing = current.isHidden || current.alphaValue < 1
        current.isHidden = false
        if appearing {
            jumpCurrent(to: target)
            if animated, window != nil { NoteAnimation.fade(current, visible: true); return }
            if let layer = current.layer { NoteAnimation.settle(layer, keys: [NoteAnimation.fadeKey]) }
            NoteAnimation.withoutAnimation { current.alphaValue = 1; current.layer?.opacity = 1 }
            return
        }
        guard current.frame != target else { return }
        guard animated, window != nil else { jumpCurrent(to: target); return }
        NoteAnimation.slide(current, to: target, spring: .pill)
        if NoteAnimation.reduceMotion, let layer = current.layer {
            _ = NoteAnimation.run(NoteAnimation.basic("opacity", from: 0, to: 1, duration: NoteAnimation.reducedFadeDuration),
                                  on: layer, key: Self.currentFadeKey)
        }
    }

    private func jumpCurrent(to target: NSRect) {
        NoteAnimation.withoutAnimation { current.frame = target }
        if let layer = current.layer { NoteAnimation.settle(layer, keys: [NoteAnimation.positionKey, NoteAnimation.boundsKey]) }
    }

    func playEntrance() {
        guard let layer, window != nil else { return }
        let reduced = NoteAnimation.reduceMotion
        NoteAnimation.withoutAnimation { layer.opacity = 1; layer.transform = CATransform3DIdentity }
        _ = NoteAnimation.run(NoteAnimation.basic("opacity", from: 0, to: 1,
                                                  duration: reduced ? NoteAnimation.reducedFadeDuration : NoteAnimation.insertDuration),
                              on: layer, key: Self.entranceFadeKey)
        guard !reduced else { return }
        let rise = NoteAnimation.spring("transform", .open,
                                        from: NSValue(caTransform3D: CATransform3DMakeTranslation(0, CGFloat(EaselFloatingBar.entranceRise), 0)),
                                        to: NSValue(caTransform3D: CATransform3DIdentity))
        _ = NoteAnimation.run(rise, on: layer, key: Self.entranceRiseKey)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let dimTracking { removeTrackingArea(dimTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .enabledDuringMouseDrag, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        dimTracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea === dimTracking else { super.mouseEntered(with: event); return }
        setDimmed(NSEvent.pressedMouseButtons & 1 != 0 && !draggingTool && popover?.isOpen != true)
    }

    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea === dimTracking else { super.mouseExited(with: event); return }
        setDimmed(false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { setDimmed(false) }
    }

    private func setDimmed(_ value: Bool) {
        guard value != dimmed else { return }
        dimmed = value
        if value, dimMonitor == nil {
            dimMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .leftMouseDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.setDimmed(false) }
                return event
            }
        } else if !value, let dimMonitor {
            NSEvent.removeMonitor(dimMonitor)
            self.dimMonitor = nil
        }
        guard let layer = pill.layer else { return }
        let target = Float(value ? EaselFloatingBar.dimmedOpacity : 1)
        if window == nil { NoteAnimation.settle(layer, keys: [Self.dimKey]); NoteAnimation.withoutAnimation { layer.opacity = target }; return }
        NoteAnimation.fade(layer, to: target, duration: NoteAnimation.reducedFadeDuration, key: Self.dimKey)
    }

    func setZoom(percent: Int) {
        guard percent != zoomPercent else { return }
        zoomPercent = percent
        refreshZoomButton()
        relayout()
    }

    func refreshAvailability() { rebuild() }

    func closeMenu(animated: Bool = true) {
        popover?.close(animated: animated)
    }

    override func layout() {
        super.layout()
        pill.frame = bounds
        scroller.frame = pill.bounds
        strip.frame = NSRect(x: 0, y: 0, width: max(preferredWidth, bounds.width), height: EaselAppearance.toolbarHeight)
        placeCurrent(animated: false)
    }

    private func wantedEntries() -> [(Entry, Int)] {
        var result: [(Entry, Int)] = []
        for tool in [EaselTool.select, .hand] where tool.isAvailable { result.append((.tool(tool), 0)) }
        if EaselTool.sticky.isAvailable { result.append((.tool(.sticky), 1)) }
        result.append((.menu(.shapes), 1))
        result.append((.menu(.connectors), 1))
        for tool in [EaselTool.text, .section, .table] where tool.isAvailable { result.append((.tool(tool), 1)) }
        if Self.drawTools.contains(where: \.isAvailable) { result.append((.menu(.draw), 2)) }
        if EaselTool.stamp.isAvailable { result.append((.tool(.stamp), 2)) }
        result.append((.menu(.media), 3))
        result.append((.menu(.web), 3))
        result.append((.menu(.code), 3))
        if showsMermaid { result.append((.insert(.mermaid), 3)) }
        if showsTemplates { result.append((.insert(.templates), 3)) }
        result.append((.zoom, 4))
        return result
    }

    private func rebuild() {
        let wanted = wantedEntries()
        let existing = Dictionary(placed.map { ($0.entry, $0.button) }, uniquingKeysWith: { first, _ in first })
        for item in placed where !wanted.contains(where: { $0.0 == item.entry }) { item.button.removeFromSuperview() }
        placed = wanted.map { entry, group in
            let button = existing[entry] ?? makeButton(entry)
            if button.superview !== strip { strip.addSubview(button) }
            return Placed(entry: entry, group: group, button: button)
        }
        let needed = max(0, Set(wanted.map(\.1)).count - 1)
        while dividers.count > needed { dividers.removeLast().removeFromSuperview() }
        while dividers.count < needed {
            let divider = EaselPaletteDivider(frame: .zero)
            strip.addSubview(divider)
            dividers.append(divider)
        }
        refreshStates()
        refreshZoomButton()
        relayout()
    }

    private func makeButton(_ entry: Entry) -> EaselToolButton {
        let button = EaselToolButton(.icon(.symbol("circle")), label: "")
        button.refusesFirstResponder = false
        button.focusRingType = .exterior
        button.iconPointSize = 14.5
        switch entry {
        case .tool(let tool):
            if tool.placesObjects { attachDrag(to: button) { tool } }
        case .menu(let menu):
            button.showsDisclosure = true
            button.onShowMenu = { [weak self, weak button] in
                guard let self, let button else { return }
                self.toggle(.menu(menu), from: button)
            }
            if menu == .shapes { attachDrag(to: button) { [weak self] in self?.shape == .ellipse ? .ellipse : .rectangle } }
            if menu == .code { attachDrag(to: button) { [weak self] in self?.lastKind[.code] == .codeBlock ? .codeBlock : nil } }
        case .insert:
            break
        case .zoom:
            button.content = .text("100%")
            button.showsDisclosure = true
            button.setAccessibilityRole(.menuButton)
            button.onShowMenu = { [weak self, weak button] in
                guard let self, let button else { return }
                self.toggle(.zoom, from: button)
            }
        }
        button.onPress = { [weak self, weak button] in
            guard let self, let button else { return }
            self.press(entry, button: button)
        }
        return button
    }

    private func attachDrag(to button: EaselToolButton, tool: @escaping () -> EaselTool?) {
        button.onDragMoved = { [weak self] point in
            guard let self, let dragged = tool() else { return }
            self.draggingTool = true
            self.setDimmed(false)
            self.closeMenu()
            self.onDrag?(dragged, point, false)
        }
        button.onDragEnded = { [weak self] point in
            guard let self else { return }
            self.draggingTool = false
            guard let dragged = tool() else { return }
            self.onDrag?(dragged, point, true)
        }
    }

    private func press(_ entry: Entry, button: EaselToolButton) {
        switch entry {
        case .tool(let tool):
            closeMenu()
            onTool?(tool, button)
        case .menu(let menu):
            if button.pressedDisclosure || isActive(menu) {
                toggle(entry, from: button)
                return
            }
            closeMenu()
            switch menu {
            case .shapes: onShape?(shape)
            case .connectors: onTool?(connector, button)
            case .draw: onTool?(brush.isAvailable ? brush : .marker, button)
            case .media, .web, .code:
                if let group = menu.group, let kind = lastKind[group] { perform(kind, from: button) }
            }
        case .insert(let insert):
            closeMenu()
            onInsert?(insert, button)
        case .zoom:
            toggle(entry, from: button)
        }
    }

    private func perform(_ kind: EaselInsertKind, from button: NSButton?) {
        if kind == .codeBlock { onTool?(.codeBlock, button) } else { onInsertKind?(kind) }
    }

    private func isActive(_ menu: Menu) -> Bool {
        switch menu {
        case .media, .web: return false
        case .code: return tool == .codeBlock
        case .shapes: return tool == .rectangle || tool == .ellipse
        case .connectors: return tool.drawsConnector
        case .draw: return Self.drawTools.contains(tool)
        }
    }

    private func refreshStates() {
        for item in placed {
            let button = item.button
            switch item.entry {
            case .tool(let tool):
                button.content = .icon(Self.icon(for: tool))
                button.setAccessibilityLabel(tool.title)
                button.setToolTip(tool.title, shortcut: tool.key?.label, anchor: .top)
                button.isChecked = false
                button.isCurrent = self.tool == tool
            case .menu(let menu) where menu.group != nil:
                guard let group = menu.group else { continue }
                let last = lastKind[group] ?? group.firstKind
                button.content = .icon(group.icon)
                button.setAccessibilityLabel(group.title)
                button.setToolTip("Add " + last.title, shortcut: last == .codeBlock ? EaselTool.codeBlock.key?.label : nil, anchor: .top)
                button.isChecked = openEntry == item.entry
                button.isCurrent = isActive(menu)
            case .menu(let menu):
                let variant: EaselTool
                switch menu {
                case .shapes: variant = shape == .ellipse ? .ellipse : .rectangle
                case .connectors: variant = connector
                case .draw, .media, .web, .code: variant = brush
                }
                let title: String
                switch menu {
                case .shapes: title = shape == .ellipse ? EaselTool.ellipse.title : Self.shapeTitle(shape)
                case .connectors, .draw, .media, .web, .code: title = variant.title
                }
                button.content = .icon(menu == .shapes ? Self.icon(for: shape) : Self.icon(for: variant))
                button.setAccessibilityLabel(title)
                button.setToolTip(title, shortcut: variant.key?.label, anchor: .top)
                button.isChecked = openEntry == item.entry
                button.isCurrent = isActive(menu)
            case .insert(let insert):
                button.content = .icon(Self.icon(for: insert))
                button.setAccessibilityLabel(Self.title(for: insert))
                button.setToolTip(Self.title(for: insert), anchor: .top)
                button.isChecked = false
                button.isCurrent = false
            case .zoom:
                button.isChecked = openEntry == .zoom
                button.setAccessibilityValue("\(zoomPercent)%")
            }
        }
    }

    private func refreshZoomButton() {
        guard let button = placed.first(where: { $0.entry == .zoom })?.button else { return }
        button.content = .text("\(zoomPercent)%")
        button.setAccessibilityLabel("Zoom")
        button.setAccessibilityValue("\(zoomPercent)%")
        button.setToolTip("Zoom", anchor: .top)
    }

    private func relayout() {
        let height = EaselAppearance.toolbarHeight
        var x = Self.padding
        var previous: Int?
        var dividerIndex = 0
        for item in placed {
            if let previous {
                if previous == item.group {
                    x += Self.spacing
                } else if dividerIndex < dividers.count {
                    dividers[dividerIndex].frame = NSRect(x: x + (Self.dividerSlot - 1) / 2, y: (height - 18) / 2, width: 1, height: 18)
                    dividerIndex += 1
                    x += Self.dividerSlot
                }
            }
            let size = item.button.intrinsicContentSize
            item.button.frame = NSRect(x: x, y: ((height - size.height) / 2).rounded(), width: size.width, height: size.height)
            x += size.width
            previous = item.group
        }
        let width = ceil(x + Self.padding)
        let changed = width != preferredWidth
        preferredWidth = width
        needsLayout = true
        if changed { onPreferredSizeChange?() }
    }

    private func toggle(_ entry: Entry, from button: EaselToolButton) {
        if openEntry == entry, popover?.isOpen == true { closeMenu(); return }
        closeMenu(animated: false)
        guard let host = superview else { return }
        let keyboard = !button.pressedWithPointer
        let content: NSView
        var list: NoteMenuList?
        var field: NoteSearchField?
        switch entry {
        case .menu(.shapes) where shapePicker != nil:
            guard let picker = shapePicker?({ [weak self] shape in
                guard let self else { return }
                if !self.shapePickerKeepsOpen { self.closeMenu() }
                self.onShape?(shape)
            }) else { return }
            content = picker
        case .menu(let menu):
            let menuList = NoteMenuList()
            menuList.items = menuItems(menu)
            if menu.group != nil { menuList.rowStyle = .detailed }
            menuList.onActivate = { [weak self] item in self?.activate(menu: menu, item: item) }
            menuList.onCancel = { [weak self] in self?.closeMenu() }
            content = menuList
            list = menuList
        case .zoom:
            let zoom = EaselFieldMenuView(frame: .zero)
            zoom.field.placeholder = "\(zoomPercent)%"
            zoom.field.textField.setAccessibilityLabel("Zoom percentage")
            zoom.list.items = zoomItems()
            zoom.list.onActivate = { [weak self] item in self?.activateZoom(item) }
            zoom.list.onCancel = { [weak self] in self?.closeMenu() }
            zoom.field.onSubmit = { [weak self] text in self?.applyTypedZoom(text) }
            zoom.field.onCommand = { [weak self, weak zoom] selector in
                guard let self, let zoom else { return false }
                switch selector {
                case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)):
                    return zoom.list.handle(command: selector)
                case #selector(NSResponder.insertNewline(_:)):
                    return zoom.field.text.trimmingCharacters(in: .whitespaces).isEmpty && zoom.list.activateHighlighted()
                case #selector(NSResponder.cancelOperation(_:)):
                    self.closeMenu()
                    return true
                default:
                    return false
                }
            }
            content = zoom
            list = zoom.list
            field = zoom.field
        case .tool, .insert:
            return
        }
        let next = NotePagePopover(content: content)
        next.exempt(button)
        if let list {
            let typed = field
            next.onKeyDown = { event in
                if let typed, [UInt16(36), UInt16(76)].contains(event.keyCode),
                   !typed.text.trimmingCharacters(in: .whitespaces).isEmpty { return false }
                return list.handleKeyDown(event)
            }
        }
        next.onClose = { [weak self, weak next] in
            guard let self, self.popover === next else { return }
            self.popover = nil
            self.openEntry = nil
            self.refreshStates()
            self.onMenuClose?()
        }
        popover = next
        openEntry = entry
        if entry == .menu(.shapes) { exemptPinnedViews() }
        next.present(in: host, anchor: host.convert(button.bounds, from: button), edge: .above)
        list?.prepare(origin: keyboard ? .keyboard : .pointer)
        field?.focus()
        refreshStates()
    }

    private func exemptPinnedViews() {
        guard shapePickerKeepsOpen, shapePicker != nil, openEntry == .menu(.shapes), let popover else { return }
        for view in keepOpenViews() { popover.exempt(view) }
    }

    private func menuItems(_ menu: Menu) -> [NoteMenuList.Item] {
        switch menu {
        case .shapes:
            let shapes = Self.shapeTools.map { shape in
                let tool: EaselTool = shape == .ellipse ? .ellipse : .rectangle
                return NoteMenuList.Item(id: shape.rawValue, title: shape == .ellipse ? tool.title : Self.shapeTitle(shape),
                                         icon: Self.icon(for: shape), shortcut: tool.key?.label,
                                         isChecked: self.shape == shape && isActive(.shapes))
            }
            guard onMindMap != nil else { return shapes }
            return shapes + [NoteMenuList.Item(id: "mind-map", title: "Mind map", icon: .symbol(Self.mindMapSymbol), separatorBefore: true)]
        case .media, .web, .code:
            guard let group = menu.group else { return [] }
            return group.kinds.map { kind in
                NoteMenuList.Item(id: kind.rawValue, title: kind.title, subtitle: kind.summary, icon: kind.icon,
                                  shortcut: kind == .codeBlock ? EaselTool.codeBlock.key?.label : nil,
                                  isChecked: lastKind[group] == kind, isEnabled: canInsert(kind))
            }
        case .connectors:
            return Self.connectorTools.map { tool in
                NoteMenuList.Item(id: tool.rawValue, title: tool.title, icon: Self.icon(for: tool), shortcut: tool.key?.label,
                                  isChecked: self.tool == tool)
            }
        case .draw:
            return Self.drawTools.filter(\.isAvailable).map { tool in
                NoteMenuList.Item(id: tool.rawValue, title: tool.title, icon: Self.icon(for: tool), shortcut: tool.key?.label,
                                  isChecked: self.tool == tool)
            }
        }
    }

    private func activate(menu: Menu, item: NoteMenuList.Item) {
        closeMenu()
        switch menu {
        case .shapes:
            if item.id == "mind-map" { onMindMap?() }
            else if let shape = EaselShape(rawValue: item.id) { onShape?(shape) }
        case .connectors, .draw:
            if let tool = EaselTool(rawValue: item.id) { onTool?(tool, nil) }
        case .media, .web, .code:
            guard let group = menu.group, let kind = EaselInsertKind(rawValue: item.id), canInsert(kind) else { return }
            lastKind[group] = kind
            refreshStates()
            perform(kind, from: nil)
        }
    }

    private func zoomItems() -> [NoteMenuList.Item] {
        var items = [EaselZoomCommand.zoomIn, .zoomOut, .fit, .selection].map { command in
            NoteMenuList.Item(id: command.rawValue, title: command.title, shortcut: command.shortcut,
                              isEnabled: command != .selection || canZoomToSelection())
        }
        for preset in EaselZoom.presets {
            let percent = EaselZoom.percent(preset)
            items.append(NoteMenuList.Item(id: "preset-\(percent)", title: "Zoom to \(percent)%",
                                           shortcut: preset == 1 ? EaselZoomCommand.actualSize.shortcut : nil,
                                           isChecked: percent == zoomPercent, separatorBefore: preset == EaselZoom.presets.first))
        }
        return items
    }

    private func activateZoom(_ item: NoteMenuList.Item) {
        closeMenu()
        if let command = EaselZoomCommand(rawValue: item.id) { onZoom?(command); return }
        guard item.id.hasPrefix("preset-"), let percent = Double(item.id.dropFirst("preset-".count)) else { return }
        if percent == 100 { onZoom?(.actualSize) } else { onZoomTo?(percent / 100) }
    }

    private func applyTypedZoom(_ text: String) {
        let digits = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
        guard let percent = Double(digits), percent.isFinite, percent > 0 else { NSSound.beep(); return }
        closeMenu()
        onZoomTo?(percent / 100)
    }

    static func icon(for tool: EaselTool) -> NoteIcon {
        switch tool {
        case .select: return .symbol("cursorarrow")
        case .hand: return .symbol("hand.raised")
        case .sticky: return .symbol("note.text")
        case .rectangle: return .symbol("square")
        case .ellipse: return .symbol("circle")
        case .elbowConnector: return .symbol("arrow.turn.down.right")
        case .curvedConnector: return .symbol("point.topleft.down.curvedto.point.bottomright.up")
        case .straightConnector: return .symbol("arrow.up.right")
        case .text: return .glyph("T")
        case .section: return .symbol("rectangle.dashed")
        case .table: return .symbol("tablecells")
        case .marker: return .symbol("scribble.variable")
        case .highlighter: return .symbol("highlighter")
        case .washi: return .symbol("bandage")
        case .eraser: return .symbol("eraser")
        case .stamp: return .symbol("face.smiling")
        case .codeBlock: return .symbol("chevron.left.forwardslash.chevron.right")
        }
    }

    static func icon(for shape: EaselShape) -> NoteIcon {
        switch shape {
        case .rectangle: return .symbol("square")
        case .roundedRectangle: return .symbol("app")
        case .ellipse: return .symbol("circle")
        case .diamond: return .symbol("diamond")
        case .triangle: return .symbol("triangle")
        case .star: return .symbol("star")
        case .hexagon: return .symbol("hexagon")
        case .pentagon: return .symbol("pentagon")
        case .octagon: return .symbol("octagon")
        default: return .symbol("square.on.circle")
        }
    }

    static func shapeTitle(_ shape: EaselShape) -> String {
        if shape == .rectangle { return EaselTool.rectangle.title }
        let words = shape.rawValue.reduce(into: "") { text, character in
            if character.isUppercase { text += " " + character.lowercased() } else { text.append(character) }
        }
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    static func icon(for insert: Insert) -> NoteIcon {
        switch insert {
        case .mermaid: return .symbol("flowchart")
        case .templates: return .symbol("square.grid.2x2")
        }
    }

    static func title(for insert: Insert) -> String {
        switch insert {
        case .mermaid: return "Add Mermaid diagram"
        case .templates: return "Templates"
        }
    }
}
