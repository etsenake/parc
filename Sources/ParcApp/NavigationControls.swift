import AppKit

enum NavigationControlKind { case back, forward, reload }

final class NavigationControlButton: PointingHandButton, NSGestureRecognizerDelegate {
    var prepareInteraction: (() -> NavigationControlInteraction?)?
    private var press: NavigationControlPress?
    private var trackingArea: NSTrackingArea?
    private var hovering = false { didSet { translucentFace?.setHovered(hovering); needsDisplay = true } }
    var showingHistory = false { didSet { needsDisplay = true } }
    private let hold = NSPressGestureRecognizer()
    private let symbol: String
    var glyphPointSize: CGFloat? {
        didSet {
            guard glyphPointSize != oldValue, let glyphPointSize else { return }
            if let reloadGlyph { reloadGlyph.pointSize = glyphPointSize }
            else { image = NavigationControlArtwork.symbol(symbol, pointSize: glyphPointSize) ?? image }
            needsDisplay = true
        }
    }
    private var translucentFace: TranslucentButtonFace?
    var windowControlStyle = false { didSet { needsDisplay = true } }
    private var pressedArrowShift: CGFloat { symbol == "arrow.left" ? -3 : symbol == "arrow.right" ? 3 : 0 }

    init(_ title: String, symbol: String, history: Bool = false, commandID: String? = nil, glyphPointSize: CGFloat? = nil) {
        self.symbol = symbol
        self.glyphPointSize = glyphPointSize
        super.init(frame: .zero)
        if glyphPointSize != nil { translucentFace = TranslucentButtonFace(view: self) }
        self.title = title; setAccessibilityLabel(title)
        LiveShortcutToolTip.set(self, title, commandID: commandID)
        image = glyphPointSize.flatMap { NavigationControlArtwork.symbol(symbol, pointSize: $0) }
            ?? NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        imagePosition = .imageOnly; isBordered = false; bezelStyle = .regularSquare
        font = .systemFont(ofSize: 12, weight: .medium)
        focusRingType = .exterior
        target = self; action = #selector(invoke)
        if history {
            hold.target = self; hold.action = #selector(held(_:)); hold.delegate = self
            hold.buttonMask = 1
            hold.minimumPressDuration = NavigationControlPress.historyHoldDuration
            hold.delaysPrimaryMouseButtonEvents = false
            addGestureRecognizer(hold)
            setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Show history") { [weak self] in
                guard let self, self.isEnabled,
                      let action = self.prepareInteraction?()?.showHistory else { return false }
                action(self); return true
            }])
        }
        if commandID == "reload:" || commandID == "forceReload:" {
            setLoading(false, enabled: true)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    var focusRingCornerRadius: CGFloat? { didSet { noteFocusRingMaskChanged() } }
    override var focusRingMaskBounds: NSRect { focusRingCornerRadius == nil ? super.focusRingMaskBounds : bounds }
    override func drawFocusRingMask() {
        guard let radius = focusRingCornerRadius else { super.drawFocusRingMask(); return }
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); trackingArea = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = isTopmost(atWindowPoint: event.locationInWindow) }
    override func mouseMoved(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { super.mouseMoved(with: event); return }
        let value = isTopmost(atWindowPoint: event.locationInWindow)
        if value != hovering { hovering = value }
    }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func draw(_ dirtyRect: NSRect) {
        if let face = translucentFace {
            face.setPressed(isHighlighted && isEnabled)
            face.draw(in: bounds, enabled: isEnabled, view: self) { tint in
                if let reloadGlyph {
                    reloadGlyph.draw(in: bounds, tint: tint, press: face.pressProgress, in: self)
                } else if let image {
                    face.drawGlyph(image, tint: tint, in: bounds, shiftX: pressedArrowShift * face.pressProgress, view: self)
                }
            }
            return
        }
        if windowControlStyle {
            let colors = TranslucentButtonColors.standard(dark: effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            if isEnabled && hovering {
                colors.hoveredBackground.setFill()
                NSBezierPath(roundedRect: bounds, xRadius: TranslucentButtonFace.cornerRadius, yRadius: TranslucentButtonFace.cornerRadius).fill()
            }
            if let image { drawWindowControlImage(image, tint: isHighlighted ? colors.pressedForeground : colors.foreground) }
            return
        }
        if isEnabled && (hovering || isHighlighted || showingHistory) {
            (contentTintColor ?? .labelColor).withAlphaComponent(isHighlighted || showingHistory ? 0.16 : 0.08).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
        super.draw(dirtyRect)
        if let reloadGlyph {
            let tint = contentTintColor ?? .secondaryLabelColor
            reloadGlyph.draw(in: bounds, tint: isEnabled ? tint : tint.withAlphaComponent(tint.alphaComponent * 0.5), in: self)
        }
    }
    private func drawWindowControlImage(_ image: NSImage, tint: NSColor) {
        let frame = bounds.insetBy(dx: 1.5, dy: 1.5)
        let scale = min(1, frame.width / max(image.size.width, 1), frame.height / max(image.size.height, 1))
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = backingAlignedRect(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                             width: size.width, height: size.height), options: .alignAllEdgesNearest)
        TranslucentButtonFace.tinted(image, tint.withAlphaComponent(1))
            .draw(in: rect, from: .zero, operation: .sourceOver, fraction: tint.alphaComponent, respectFlipped: true, hints: nil)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if translucentFace != nil || windowControlStyle { needsDisplay = true }
    }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        if event.modifierFlags.contains(.control), let history = prepareInteraction?()?.showHistory {
            press?.cancel(); press = nil; history(self); return
        }
        beginPress(event)
        defer { press?.cancel(); press = nil }
        super.mouseDown(with: event)
    }
    override func rightMouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        press?.cancel(); press = nil
        prepareInteraction?()?.showHistory?(self)
    }
    override func otherMouseDown(with event: NSEvent) {
        guard isEnabled, event.buttonNumber == 2 else { super.otherMouseDown(with: event); return }
        beginPress(event)
    }
    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else { super.otherMouseUp(with: event); return }
        defer { press?.cancel(); press = nil }
        if isEnabled && bounds.contains(convert(event.locationInWindow, from: nil)) {
            if press?.finished != true { playReloadAction() }
            press?.activate()
        }
    }
    private func beginPress(_ event: NSEvent) {
        if press?.eventNumber == event.eventNumber { return }
        press?.cancel()
        press = prepareInteraction?().map { NavigationControlPress(event: event, interaction: $0) }
    }
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        guard isEnabled, event.type == .leftMouseDown else { return false }
        beginPress(event)
        return press?.hasHistory == true
    }
    @objc private func held(_ recognizer: NSPressGestureRecognizer) {
        if recognizer.state == .cancelled { press?.cancel(); return }
        guard recognizer.state == .began, isEnabled else { return }
        press?.showHistory(from: self)
    }
    @objc private func invoke() {
        guard isEnabled else { return }
        if let press {
            if !press.finished { playReloadAction() }
            press.activate()
        } else {
            playReloadAction()
            prepareInteraction?()?.activate(false)
        }
    }
    private func playReloadAction() {
        reloadGlyph?.playActionSpin(animated: window != nil && !isHiddenOrHasHiddenAncestor)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow { press?.cancel(); hovering = false }
        super.viewWillMove(toWindow: newWindow)
    }
    func setLoading(_ loading: Bool, enabled: Bool, idleLabel: String = "Reload this page", forceReload: Bool = false) {
        let label = loading ? "Stop Loading" : idleLabel
        title = ""; setAccessibilityLabel(label)
        LiveShortcutToolTip.set(self, label, commandID: loading ? "stopLoading:" : forceReload ? "forceReload:" : "reload:")
        let glyph = reloadGlyph ?? ReloadGlyph(view: self, pointSize: glyphPointSize ?? ReloadGlyph.toolbarPointSize,
                                               rasterized: glyphPointSize != nil)
        if reloadGlyph == nil { reloadGlyph = glyph }
        image = nil
        imagePosition = .imageOnly
        glyph.update(loading: loading, forceReload: forceReload, animated: window != nil && !isHiddenOrHasHiddenAncestor)
        isEnabled = enabled
        needsDisplay = true
    }
    private var reloadGlyph: ReloadGlyph?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { reloadGlyph?.stop(); translucentFace?.stop() }
    }
}

enum NavigationHistoryMenuMetrics {
    static let width: CGFloat = 220
    static let edgeInset: CGFloat = 8
    static let rowHeight: CGFloat = 40
    static let rowHorizontalInset: CGFloat = 8
    static let imageSpacing: CGFloat = 6
    static let imageDimension: CGFloat = 16
    static let rowCornerRadius: CGFloat = 8
    static let cardCornerRadius: CGFloat = 12
    static let anchorGap: CGFloat = 4
    static let shadowOpacity: Float = 0.2
    static let shadowRadius: CGFloat = 3
    static let shadowOffset = CGSize(width: 0, height: -1)
    static let shadowMargin: CGFloat = 8
    static let hiddenScale: CGFloat = 0.95
    static let openTransformDuration: CFTimeInterval = 0.1
    static let openOpacityDuration: CFTimeInterval = 0.05
    static let closeDuration: CFTimeInterval = 0.07
    static var timing: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1) }
    static var font: NSFont { .systemFont(ofSize: 13, weight: .medium) }

    static func cardHeight(rows: Int) -> CGFloat { CGFloat(rows) * rowHeight + 2 * edgeInset }
    static func cardFrame(anchor: NSRect, parent: NSRect, screen: NSRect?, rows: Int) -> NSRect {
        var height = cardHeight(rows: rows)
        if let screen {
            let available = anchor.minY - anchorGap - shadowMargin - screen.minY
            height = min(height, max(available, cardHeight(rows: 1)))
        }
        var x = max(anchor.midX - width / 2, parent.minX)
        if parent.maxX - width < x { x = parent.maxX - width }
        return NSRect(x: x, y: anchor.minY - anchorGap - height, width: width, height: height)
    }
}

private final class NavigationHistoryMenuWindow: NSWindow {
    var onResignKey: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func resignKey() { super.resignKey(); onResignKey?() }
}

private final class NavigationHistoryRowView: NSTableRowView {
    var hoverColor: NSColor = .clear
    var focused = false { didSet { if focused != oldValue { needsDisplay = true } } }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = NavigationHistoryMenuMetrics.rowCornerRadius
        layer?.cornerCurve = .continuous; layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = (focused ? hoverColor : .clear).cgColor }
    override func drawSelection(in dirtyRect: NSRect) {}
}

private final class NavigationHistoryCellView: NSTableCellView {
    var onPress: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { onPress?(); return onPress != nil }
}

private final class NavigationHistoryTable: NSTableView {
    var activate: ((Int, Bool) -> Void)?
    var cancel: (() -> Void)?
    var focus: ((Int?) -> Void)?
    var move: ((Int) -> Void)?
    var focusedRow: () -> Int? = { nil }
    private var hoverArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    private func pointerRow(_ event: NSEvent) -> Int? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        return row >= 0 ? row : nil
    }
    override func mouseMoved(with event: NSEvent) { focus?(pointerRow(event)) }
    override func mouseEntered(with event: NSEvent) { focus?(pointerRow(event)) }
    override func mouseExited(with event: NSEvent) { focus?(nil) }
    override func mouseDown(with event: NSEvent) { focus?(pointerRow(event)) }
    override func mouseUp(with event: NSEvent) {
        if let row = pointerRow(event) { activate?(row, event.modifierFlags.contains(.command)) }
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: if let row = focusedRow() { activate?(row, event.modifierFlags.contains(.command)) }
        case 53: cancel?()
        case 125: move?(1)
        case 126: move?(-1)
        default: super.keyDown(with: event)
        }
    }
    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2, let row = pointerRow(event) { activate?(row, true) }
        else { super.otherMouseUp(with: event) }
    }
}

private final class NavigationHistoryFill: NSView {
    private let color: NSColor
    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = color.cgColor }
}

private final class NavigationHistoryCardView: NSView {
    let clip = NSView()
    private let base: NavigationHistoryFill
    private let tint: NavigationHistoryFill
    init(frame: NSRect, colors: ParcMenuColors) {
        base = NavigationHistoryFill(color: colors.base)
        tint = NavigationHistoryFill(color: colors.background)
        super.init(frame: frame)
        wantsLayer = true
        let m = NavigationHistoryMenuMetrics.self
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOpacity = m.shadowOpacity
        layer?.shadowRadius = m.shadowRadius; layer?.shadowOffset = m.shadowOffset
        clip.frame = bounds.insetBy(dx: m.shadowMargin, dy: m.shadowMargin)
        clip.autoresizingMask = [.width, .height]; clip.wantsLayer = true
        clip.layer?.cornerRadius = m.cardCornerRadius; clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        for view in [base, tint] {
            view.frame = clip.bounds; view.autoresizingMask = [.width, .height]
            clip.addSubview(view)
        }
        addSubview(clip)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        let m = NavigationHistoryMenuMetrics.self
        layer?.shadowPath = CGPath(roundedRect: clip.frame, cornerWidth: m.cardCornerRadius,
                                   cornerHeight: m.cardCornerRadius, transform: nil)
    }
}

struct NavigationHistoryStepRow {
    var title: String
    var icon: NSImage?
    var url: URL?
    var choose: (Bool) -> Void
}

final class NavigationHistoryController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let page: PCNativePage?
    private let snapshot: PCNativeNavigationHistory?
    private let leading: NavigationHistoryStepRow?
    private var rowCount: Int { (leading == nil ? 0 : 1) + (snapshot?.entries.count ?? 0) }
    private var isValid: Bool { snapshot?.isValid ?? true }
    var beforeEntry: ((Bool) -> Bool)?
    private let colors: ParcMenuColors
    private weak var parent: NSWindow?
    private weak var oldResponder: NSResponder?
    private weak var anchor: NavigationControlButton?
    private let menuWindow: NavigationHistoryMenuWindow
    private let card: NavigationHistoryCardView
    private let table = NavigationHistoryTable()
    private var observers: [NSObjectProtocol] = []
    private var finished = false
    private var focused: Int? = 0
    private var anchorOffset: CGFloat = NavigationHistoryMenuMetrics.width / 2
    var stillSelected: (() -> Bool)?
    var onClose: (() -> Void)?
    var onNavigate: (() -> Void)?
    var address: (URL) -> String? = { $0.absoluteString }

    init(page: PCNativePage?, snapshot: PCNativeNavigationHistory?, leading: NavigationHistoryStepRow? = nil,
         window: NSWindow, theme: SpaceTheme) {
        self.page = page; self.snapshot = snapshot; self.leading = leading; colors = ParcMenuColors(theme: theme)
        let rowCount = (leading == nil ? 0 : 1) + (snapshot?.entries.count ?? 0)
        parent = window; oldResponder = window.firstResponder
        let m = NavigationHistoryMenuMetrics.self
        let size = NSSize(width: m.width + 2 * m.shadowMargin,
                          height: m.cardHeight(rows: rowCount) + 2 * m.shadowMargin)
        menuWindow = NavigationHistoryMenuWindow(contentRect: NSRect(origin: .zero, size: size),
                                                 styleMask: .borderless, backing: .buffered, defer: true)
        card = NavigationHistoryCardView(frame: NSRect(origin: .zero, size: size), colors: colors)
        super.init()
        menuWindow.isOpaque = false; menuWindow.backgroundColor = .clear; menuWindow.hasShadow = false
        menuWindow.isReleasedWhenClosed = false
        menuWindow.setAccessibilityLabel("Page navigation history")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history"))
        let rowWidth = m.width - 2 * m.edgeInset
        column.width = rowWidth; table.addTableColumn(column)
        table.headerView = nil; table.rowHeight = m.rowHeight; table.intercellSpacing = .zero
        table.style = .plain; table.backgroundColor = .clear; table.focusRingType = .none
        table.selectionHighlightStyle = .none; table.allowsEmptySelection = true
        table.dataSource = self; table.delegate = self
        table.target = self; table.action = #selector(pressed)
        table.setAccessibilityLabel("Page navigation history")
        table.activate = { [weak self] row, alternate in self?.choose(row, alternate: alternate) }
        table.cancel = { [weak self] in self?.dismiss(restoreFocus: true) }
        table.focus = { [weak self] row in self?.setFocus(row) }
        table.move = { [weak self] delta in self?.moveFocus(delta) }
        table.focusedRow = { [weak self] in self?.focused }
        let rows = CGFloat(rowCount) * m.rowHeight
        let scroll = NSScrollView(frame: card.clip.bounds.insetBy(dx: m.edgeInset, dy: m.edgeInset))
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay; scroll.autohidesScrollers = true
        scroll.autoresizingMask = [.width, .height]
        scroll.horizontalScrollElasticity = .none; scroll.verticalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false; scroll.documentView = table
        table.frame = NSRect(x: 0, y: 0, width: rowWidth, height: rows)
        card.clip.addSubview(scroll)
        menuWindow.contentView = card
        menuWindow.onResignKey = { [weak self] in
            guard let self, !self.finished else { return }
            self.dismiss()
        }
    }
    func show(from view: NSView) {
        guard isValid, stillSelected?() == true, let parent,
              view.window === parent, rowCount > 0 else { dismiss(); return }
        anchor = view as? NavigationControlButton; anchor?.showingHistory = true
        let m = NavigationHistoryMenuMetrics.self
        let anchorRect = parent.convertToScreen(view.convert(view.bounds, to: nil))
        let frame = m.cardFrame(anchor: anchorRect, parent: parent.frame,
                                screen: (parent.screen ?? NSScreen.main)?.visibleFrame, rows: rowCount)
        anchorOffset = min(max(anchorRect.midX - frame.minX, 0), m.width)
        menuWindow.setFrame(frame.insetBy(dx: -m.shadowMargin, dy: -m.shadowMargin), display: false)
        card.layoutSubtreeIfNeeded()
        table.scrollRowToVisible(0)
        parent.addChildWindow(menuWindow, ordered: .above)
        menuWindow.makeKeyAndOrderFront(nil)
        menuWindow.makeFirstResponder(table)
        setFocus(0)
        animateIn()
        let center = NotificationCenter.default
        for name in [NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification,
                     NSWindow.willBeginSheetNotification] {
            observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish(selection: nil, restoreFocus: false, animated: false) }
            })
        }
        observers.append(center.addObserver(forName: Notification.Name("PCNativeWindowSecurityStateChanged"), object: parent, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        })
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        })
        trackOpeningPress()
    }
    private func trackOpeningPress() {
        let pressed = NSEvent.pressedMouseButtons
        guard pressed & 0b11 != 0 else { return }
        var mask: NSEvent.EventTypeMask = []
        if pressed & 1 != 0 { mask.formUnion([.leftMouseDragged, .leftMouseUp]) }
        if pressed & 2 != 0 { mask.formUnion([.rightMouseDragged, .rightMouseUp]) }
        let start = ProcessInfo.processInfo.systemUptime
        let freshPress = NSApp.currentEvent.map {
            [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains($0.type) && start - $0.timestamp <= 0.1
        } ?? false
        while !finished {
            guard let event = NSApp.nextEvent(matching: mask, until: Date(timeIntervalSinceNow: 0.25),
                                              inMode: .eventTracking, dequeue: true) else {
                if NSEvent.pressedMouseButtons & 0b11 == 0 { break }
                continue
            }
            let point = menuWindow.convertPoint(fromScreen: event.window.map { $0.convertPoint(toScreen: event.locationInWindow) }
                                                    ?? event.locationInWindow)
            let tablePoint = table.convert(point, from: nil)
            let row = table.visibleRect.contains(tablePoint) ? table.row(at: tablePoint) : -1
            switch event.type {
            case .leftMouseDragged, .rightMouseDragged:
                setFocus(row >= 0 ? row : nil)
                continue
            default: break
            }
            if row >= 0 { choose(row, alternate: event.modifierFlags.contains(.command)) }
            else if freshPress, ProcessInfo.processInfo.systemUptime - start > 0.35 { dismiss() }
            if event.type == .leftMouseUp { NSApp.postEvent(event, atStart: true) }
            break
        }
    }
    func ownsKeyWindow(in window: NSWindow) -> Bool {
        !finished && parent === window && menuWindow.isKeyWindow && isValid && stillSelected?() == true
    }

    func validate() {
        if !isValid || stillSelected?() != true { dismiss() }
    }
    func dismiss(restoreFocus: Bool = false) {
        finish(selection: nil, restoreFocus: restoreFocus)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rowCount }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = NavigationHistoryRowView()
        view.hoverColor = colors.hover; view.focused = row == focused
        return view
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard (0..<rowCount).contains(row) else { return nil }
        let m = NavigationHistoryMenuMetrics.self
        let shown = shownRow(row)
        let width = m.width - 2 * m.edgeInset
        let cell = NavigationHistoryCellView(frame: NSRect(x: 0, y: 0, width: width, height: m.rowHeight))
        cell.onPress = { [weak self] in self?.choose(row, alternate: false) }
        let primary = colors.title
        let side = m.imageDimension
        let icon = NSImageView(frame: NSRect(x: m.rowHorizontalInset, y: (m.rowHeight - side) / 2, width: side, height: side))
        icon.image = shown.icon ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        icon.imageScaling = .scaleProportionallyUpOrDown; icon.contentTintColor = primary
        cell.addSubview(icon); cell.imageView = icon
        let label = NSTextField(labelWithString: shown.title.isEmpty ? shown.url.flatMap(address) ?? "Untitled" : shown.title)
        label.font = m.font; label.textColor = primary
        label.lineBreakMode = .byTruncatingTail; label.maximumNumberOfLines = 1
        let x = m.rowHorizontalInset + side + m.imageSpacing
        let height = ceil(label.intrinsicContentSize.height)
        label.frame = NSRect(x: x, y: (m.rowHeight - height) / 2, width: width - x - m.rowHorizontalInset, height: height)
        cell.addSubview(label); cell.textField = label; cell.toolTip = shown.url.flatMap(address)
        cell.setAccessibilityLabel(label.stringValue)
        return cell
    }
    private func shownRow(_ row: Int) -> (title: String, icon: NSImage?, url: URL?) {
        if let leading, row == 0 { return (leading.title, leading.icon, leading.url) }
        guard let entry = entry(at: row) else { return ("", nil, nil) }
        return (entry.title, entry.favicon, entry.url)
    }
    private func entry(at row: Int) -> PCNativeNavigationEntry? {
        let index = row - (leading == nil ? 0 : 1)
        guard let snapshot, snapshot.entries.indices.contains(index) else { return nil }
        return snapshot.entries[index]
    }
    private func setFocus(_ row: Int?) {
        let row = row.flatMap { (0..<rowCount).contains($0) ? $0 : nil }
        guard row != focused else { return }
        let old = focused; focused = row
        for index in [old, row].compactMap({ $0 }) {
            (table.rowView(atRow: index, makeIfNecessary: false) as? NavigationHistoryRowView)?.focused = index == row
        }
        if let row {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        } else {
            table.deselectAll(nil)
        }
    }
    @objc private func pressed() {
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        if row >= 0 { choose(row, alternate: false) }
    }
    private func moveFocus(_ delta: Int) {
        let count = rowCount
        guard count > 0 else { return }
        guard let focused else { setFocus(delta > 0 ? 0 : count - 1); return }
        setFocus(((focused + delta) % count + count) % count)
    }
    private func choose(_ row: Int, alternate: Bool) {
        guard !finished, (0..<rowCount).contains(row), isValid,
              stillSelected?() == true else { dismiss(); return }
        if let leading, row == 0 {
            finish(selection: nil, restoreFocus: false)
            DispatchQueue.main.async { leading.choose(alternate) }
            return
        }
        guard let entry = entry(at: row) else { dismiss(); return }
        finish(selection: (entry, alternate), restoreFocus: false)
    }
    private func finish(selection: (PCNativeNavigationEntry, Bool)?, restoreFocus: Bool, animated: Bool = true) {
        guard !finished else { return }; finished = true
        anchor?.showingHistory = false
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        let validOwner = stillSelected?() == true
        if let parent, menuWindow.isKeyWindow, parent.isVisible, NSApp.isActive { parent.makeKey() }
        animateOut(animated: animated)
        if let selection, validOwner, let snapshot {
            let stillSelected = stillSelected, onNavigate = onNavigate, beforeEntry = beforeEntry
            DispatchQueue.main.async {
                if stillSelected?() == true, beforeEntry?(selection.1) ?? true,
                   snapshot.navigate(to: selection.0, inNewTab: selection.1), !selection.1 { onNavigate?() }
                snapshot.invalidate()
            }
        } else {
            snapshot?.invalidate()
            if restoreFocus, validOwner {
                let stillSelected = stillSelected
                DispatchQueue.main.async { [weak parent, weak oldResponder] in
                    if stillSelected?() == true, let parent, parent.isKeyWindow, let oldResponder,
                       (oldResponder as? NSView).map({ SavedFocus.mayReturn(to: $0, in: parent) }) ?? true {
                        parent.makeFirstResponder(oldResponder)
                    }
                }
            }
        }
        onClose?()
    }
    private func scaled(_ scale: CGFloat) -> CATransform3D {
        let m = NavigationHistoryMenuMetrics.self
        let x = m.shadowMargin + anchorOffset, y = card.bounds.height - m.shadowMargin
        var t = CATransform3DMakeTranslation(x, y, 0)
        t = CATransform3DScale(t, scale, scale, 1)
        return CATransform3DTranslate(t, -x, -y, 0)
    }
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private func animateIn() {
        guard let layer = card.layer, !reduceMotion else { return }
        let m = NavigationHistoryMenuMetrics.self
        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: scaled(m.hiddenScale))
        transform.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        transform.duration = m.openTransformDuration; transform.timingFunction = m.timing
        layer.add(transform, forKey: "transform_animation")
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0; opacity.toValue = 1
        opacity.duration = m.openOpacityDuration; opacity.timingFunction = m.timing
        layer.add(opacity, forKey: "opacity_animation")
    }
    private func animateOut(animated: Bool) {
        let window = menuWindow
        let close = { [weak parent] in
            parent?.removeChildWindow(window); window.orderOut(nil); window.close()
        }
        guard animated, let layer = card.layer, !reduceMotion, window.isVisible else { close(); return }
        let m = NavigationHistoryMenuMetrics.self
        window.ignoresMouseEvents = true
        let current = layer.presentation()
        CATransaction.begin()
        CATransaction.setCompletionBlock(close)
        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: current?.transform ?? CATransform3DIdentity)
        transform.toValue = NSValue(caTransform3D: scaled(m.hiddenScale))
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = current?.opacity ?? 1; opacity.toValue = 0
        for animation in [transform, opacity] {
            animation.duration = m.closeDuration; animation.timingFunction = m.timing
            animation.fillMode = .forwards; animation.isRemovedOnCompletion = false
        }
        layer.add(transform, forKey: "transform_animation")
        layer.add(opacity, forKey: "opacity_animation")
        CATransaction.commit()
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
