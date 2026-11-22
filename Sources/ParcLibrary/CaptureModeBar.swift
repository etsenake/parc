import AppKit
import ParcCore
import ParcKit
import ParcNotes

@MainActor
final class CaptureModeButton: NoteControlButton {
    let item: CaptureModeItem
    var density = CaptureModeBarLayout.Density.full {
        didSet { if density != oldValue { invalidateIntrinsicContentSize(); setFrameSize(intrinsicContentSize); needsDisplay = true } }
    }
    var onMoveFocus: ((CaptureModeButton, Int) -> Void)?

    static let iconSide: CGFloat = 16
    static var titleFont: NSFont { NoteTheme.chromeFont(13) }

    init(_ item: CaptureModeItem) {
        self.item = item
        super.init(frame: NSRect(origin: .zero, size: NoteTheme.toolbarButtonSize))
        refusesFirstResponder = false
        focusRingType = .exterior
        setAccessibilityRole(item.mode == nil ? .button : .radioButton)
        setAccessibilityLabel(item.title)
        setToolTip(item.title, shortcut: item.key, anchor: .top)
        setAccessibilityHelp(item.toolTip + ". Shortcut: " + NoteKeycapLabel.spoken(item.key))
        setFrameSize(intrinsicContentSize)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var showsTitle: Bool { item != .cancel && density != .icons }
    private var showsKey: Bool { density == .full }

    private var titleWidth: CGFloat {
        ceil(NSAttributedString(string: item.title, attributes: [.font: Self.titleFont]).size().width)
    }

    func width(for density: CaptureModeBarLayout.Density) -> CGFloat {
        let titled = item != .cancel && density != .icons
        guard titled || density == .full else { return NoteTheme.toolbarButtonSize.width }
        var width = 7 + Self.iconSide + 5
        if titled { width += titleWidth + (density == .full ? 7 : 4) }
        if density == .full { width += NoteKeycapRenderer.size(for: item.key, style: .caps).width }
        return ceil(width + 5)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: width(for: density), height: NoteTheme.toolbarButtonSize.height)
    }

    override var acceptsFirstResponder: Bool { isEnabled && NSApp.isFullKeyboardAccessEnabled }

    override func accessibilityValue() -> Any? {
        item.mode == nil ? nil : NSNumber(value: isChecked)
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == 48, modifiers == .shift { window?.selectKeyView(preceding: self); return }
        if modifiers.isEmpty {
            switch event.keyCode {
            case 48: window?.selectKeyView(following: self); return
            case 123: onMoveFocus?(self, -1); return
            case 124: onMoveFocus?(self, 1); return
            case 36, 76, 49: performClick(nil); return
            default: break
            }
        }
        super.keyDown(with: event)
    }

    override func drawContent(in bounds: NSRect, ink: NSColor) {
        let iconX = showsTitle || showsKey ? bounds.minX + 7 : bounds.midX - Self.iconSide / 2
        let icon = NSRect(x: iconX, y: bounds.midY - Self.iconSide / 2, width: Self.iconSide, height: Self.iconSide)
        NoteIconRenderer.draw(.symbol(item.symbol), in: icon, tint: ink, pointSize: 13, weight: .semibold)
        var x = icon.maxX + 5
        if showsTitle {
            let font = Self.titleFont
            let height = ceil(font.ascender - font.descender)
            NSAttributedString(string: item.title, attributes: [.font: font, .foregroundColor: ink])
                .draw(with: NSRect(x: x, y: (bounds.midY - height / 2).rounded(), width: titleWidth, height: height),
                      options: [.usesLineFragmentOrigin])
            x += titleWidth + 7
        }
        if showsKey {
            let key = NoteKeycapRenderer.size(for: item.key, style: .caps)
            NoteKeycapRenderer.draw(item.key, style: .caps, in: NSRect(x: x, y: bounds.minY, width: key.width, height: bounds.height))
        }
    }
}

@MainActor
package final class CaptureModeBar: NSView, NoteFloatingPanelContent {
    package var preferredSizeDidChange: (() -> Void)?
    package var onItem: ((CaptureModeItem) -> Void)?
    private(set) var buttons: [CaptureModeButton] = []
    private var dividers: [NSView] = []
    private(set) var mode = CaptureSelectionMode.element
    private(set) var density = CaptureModeBarLayout.Density.full

    static let padding: CGFloat = 4
    static let spacing: CGFloat = 2
    static let dividerSlot: CGFloat = 9

    package override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Capture")
        var previous: Int?
        for item in CaptureModeItem.allCases {
            if let previous, previous != item.group {
                let divider = CaptureModeDivider()
                dividers.append(divider)
                addSubview(divider)
            }
            let button = CaptureModeButton(item)
            button.onPress = { [weak self] in self?.onItem?(item) }
            button.onMoveFocus = { [weak self] button, delta in self?.moveFocus(from: button, by: delta) }
            buttons.append(button)
            addSubview(button)
            previous = item.group
        }
        setMode(.element)
        relayout()
    }

    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    package override var isFlipped: Bool { true }
    package override var mouseDownCanMoveWindow: Bool { false }
    package override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    package override func mouseDown(with event: NSEvent) {}
    package override func mouseDragged(with event: NSEvent) {}
    package override func mouseUp(with event: NSEvent) {}

    func button(for item: CaptureModeItem) -> CaptureModeButton? { buttons.first { $0.item == item } }

    package var keyViews: [NSView] { buttons.filter(\.isEnabled) }

    package func setMode(_ mode: CaptureSelectionMode) {
        self.mode = mode
        for button in buttons where button.item.mode != nil {
            let checked = button.item.mode == mode
            guard button.isChecked != checked else { continue }
            button.isChecked = checked
            NSAccessibility.post(element: button, notification: .valueChanged)
        }
        setAccessibilityValue(mode == .element ? "Element mode" : "Region mode")
    }

    func setBusy(_ busy: Bool) {
        for button in buttons where button.item != .cancel { button.isEnabled = !busy }
    }

    func fit(width available: CGFloat) {
        let next = CaptureModeBarLayout.density(available: available, full: width(for: .full), labels: width(for: .labels))
        guard next != density else { return }
        density = next
        for button in buttons { button.density = next }
        relayout()
    }

    func width(for density: CaptureModeBarLayout.Density) -> CGFloat {
        var width = Self.padding * 2
        var previous: Int?
        for button in buttons {
            if let previous { width += previous == button.item.group ? Self.spacing : Self.dividerSlot }
            width += button.width(for: density)
            previous = button.item.group
        }
        return ceil(width)
    }

    package override var intrinsicContentSize: NSSize { NSSize(width: width(for: density), height: NoteTheme.toolbarHeight) }
    package override var fittingSize: NSSize { intrinsicContentSize }

    private func relayout() {
        let before = frame.size
        let height = NoteTheme.toolbarHeight
        var x = Self.padding
        var previous: Int?
        var dividerIndex = 0
        NoteAnimation.withoutAnimation {
            for button in buttons {
                if let previous {
                    if previous == button.item.group {
                        x += Self.spacing
                    } else {
                        dividers[dividerIndex].frame = NSRect(x: x + (Self.dividerSlot - 1) / 2, y: (height - 18) / 2, width: 1, height: 18)
                        dividerIndex += 1
                        x += Self.dividerSlot
                    }
                }
                let size = button.intrinsicContentSize
                button.frame = NSRect(x: x, y: ((height - size.height) / 2).rounded(), width: size.width, height: size.height)
                x += size.width
                previous = button.item.group
            }
        }
        invalidateIntrinsicContentSize()
        if intrinsicContentSize != before {
            setFrameSize(intrinsicContentSize)
            preferredSizeDidChange?()
        }
    }

    private func moveFocus(from button: CaptureModeButton, by delta: Int) {
        let focusable = buttons.filter(\.acceptsFirstResponder)
        guard let index = focusable.firstIndex(where: { $0 === button }), focusable.count > 1 else { return }
        window?.makeFirstResponder(focusable[(index + delta + focusable.count) % focusable.count])
    }
}

@MainActor
private final class CaptureModeDivider: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuSeparator, in: self) }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

@MainActor
package final class CaptureHintCard: NSView {
    package var stringValue = "" {
        didSet {
            guard stringValue != oldValue else { return }
            needsDisplay = true
            superview?.needsLayout = true
            setAccessibilityValue(stringValue)
            if window != nil, !isHidden, !NoteAnimation.reduceMotion {
                let transition = CATransition()
                transition.type = .fade
                transition.duration = 0.2
                transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer?.add(transition, forKey: "captureHintText")
            }
        }
    }
    private var tracking: NSTrackingArea?
    private var retired = false

    static let horizontalPadding: CGFloat = 13
    static let verticalPadding: CGFloat = 7
    static var font: NSFont { NoteTheme.chromeFont(12.5) }

    package override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        refreshShadow()
    }

    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    package override var isFlipped: Bool { true }
    package override var mouseDownCanMoveWindow: Bool { false }
    package override func hitTest(_ point: NSPoint) -> NSView? { nil }
    package override func accessibilityLabel() -> String? { stringValue }

    private var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        return [.font: Self.font, .foregroundColor: NoteTheme.menuSecondaryInk, .paragraphStyle: paragraph]
    }

    func fittingWidth(maximum: CGFloat) -> CGFloat {
        let text = ceil((stringValue as NSString).size(withAttributes: attributes).width)
        return min(max(1, maximum), text + 2 * Self.horizontalPadding)
    }

    func height(for width: CGFloat) -> CGFloat {
        let text = (stringValue as NSString).boundingRect(with: NSSize(width: max(1, width - 2 * Self.horizontalPadding), height: 400),
                                                           options: [.usesLineFragmentOrigin], attributes: attributes)
        return ceil(text.height) + 2 * Self.verticalPadding
    }

    package override func layout() {
        super.layout()
        refreshShadow()
    }

    package override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshShadow()
        needsDisplay = true
    }

    private var radius: CGFloat { min(NoteTheme.menuRadius, bounds.height / 2) }

    private func refreshShadow() {
        guard let layer else { return }
        NoteAnimation.withoutAnimation {
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = NoteTheme.isDark(effectiveAppearance) ? 0.32 : 0.12
            layer.shadowRadius = 7
            layer.shadowOffset = CGSize(width: 0, height: -2)
            layer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
    }

    package override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
        NoteTheme.menuFill.setFill()
        card.fill()
        NoteTheme.menuHairline.setStroke()
        card.lineWidth = 0.5
        card.stroke()
        (stringValue as NSString).draw(with: bounds.insetBy(dx: Self.horizontalPadding, dy: Self.verticalPadding),
                                       options: [.usesLineFragmentOrigin], attributes: attributes)
    }

    package override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = nil
        guard !retired else { super.updateTrackingAreas(); return }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        tracking = area
        addTrackingArea(area)
        super.updateTrackingAreas()
    }

    package override func mouseEntered(with event: NSEvent) { setHovered(true) }
    package override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ hovered: Bool) {
        guard !retired, let layer else { return }
        NoteAnimation.fade(layer, to: hovered ? 0.1 : 1, duration: 0.2, curve: NoteCurve.easeInOut, key: "captureHintHover")
    }

    package func settleMotion() {
        layer?.removeAllAnimations()
        NoteAnimation.withoutAnimation { layer?.opacity = 1 }
    }

    package func retire() {
        retired = true
        if let tracking { removeTrackingArea(tracking) }
        tracking = nil
        settleMotion()
    }
}

@MainActor
package final class CaptureSizeReadoutView: NSView {
    private(set) var text = ""
    static var font: NSFont { .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold) }

    package override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        isHidden = true
        setAccessibilityElement(false)
    }

    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    package override var isFlipped: Bool { true }
    package override func hitTest(_ point: NSPoint) -> NSView? { nil }

    package func show(_ size: CGSize, around frame: NSRect, in bounds: NSRect, avoiding obstacle: NSRect?) {
        let next = CaptureSizeReadout.text(size)
        if next != text { text = next; needsDisplay = true }
        let width = ceil(NSAttributedString(string: text, attributes: [.font: Self.font]).size().width) + 14
        let placed = CaptureSizeReadout.placement(for: frame, size: CGSize(width: width, height: 20), in: bounds, avoiding: obstacle)
        NoteAnimation.withoutAnimation { self.frame = placed.integral }
        isHidden = false
    }

    package func hide() { isHidden = true }

    package override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    package override func draw(_ dirtyRect: NSRect) {
        NoteTheme.accent.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: NoteTheme.menuFill]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: (bounds.midX - size.width / 2).rounded(), y: (bounds.midY - size.height / 2).rounded()),
                                withAttributes: attributes)
    }
}

@MainActor
package final class CaptureModeChrome {
    package let bar = CaptureModeBar()
    package let hint = CaptureHintCard()
    package let readout = CaptureSizeReadoutView()
    let panel: NoteFloatingPanel
    package private(set) var isShown = false
    private(set) var isDragging = false
    private weak var host: NSView?

    package init() {
        panel = NoteFloatingPanel(content: bar)
        panel.alignment = .center
        panel.gap = 0
    }

    package func install(in host: NSView) {
        self.host = host
        host.addSubview(hint)
        host.addSubview(readout)
    }

    package var barFrame: NSRect { isShown && panel.superview === host ? panel.frame : .zero }

    package var readoutObstacle: NSRect? {
        let rects = [barFrame, hint.isHidden ? .zero : hint.frame].filter { !$0.isEmpty }
        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }

    package func blocks(_ point: NSPoint) -> Bool {
        isShown && !isDragging && panel.frame.contains(point)
    }

    package func show(in bounds: NSRect) {
        guard let host else { return }
        setDragging(false)
        bar.setBusy(false)
        bar.fit(width: bounds.width - 2 * CaptureModeBarLayout.margin)
        let anchor = anchorRect(in: bounds)
        if isShown, panel.isPresented, panel.superview === host {
            panel.reposition(anchor: anchor, edge: .above, animated: false)
        } else {
            isShown = true
            panel.present(in: host, anchor: anchor, edge: .above, animated: true)
        }
    }

    package func hide(animated: Bool) {
        readout.hide()
        guard isShown else { return }
        isShown = false
        isDragging = false
        panel.dismiss(animated: animated)
    }

    package func setBusy(_ busy: Bool) {
        readout.hide()
        bar.setBusy(busy)
        if busy, isDragging { hide(animated: false) }
    }

    package func setDragging(_ dragging: Bool) {
        guard dragging != isDragging else { return }
        isDragging = dragging
        guard isShown, let layer = panel.layer else { return }
        NoteAnimation.fade(layer, to: dragging ? 0 : 1, duration: 0.15, key: "captureModeDrag")
    }

    package func layout(in bounds: NSRect, hintVisible: Bool) {
        if isShown, panel.isPresented, panel.superview === host {
            bar.fit(width: bounds.width - 2 * CaptureModeBarLayout.margin)
            panel.reposition(anchor: anchorRect(in: bounds), edge: .above, animated: false)
        }
        guard hintVisible else { return }
        let maximum = max(1, bounds.width - 2 * CaptureModeBarLayout.margin)
        let width = hint.fittingWidth(maximum: min(maximum, 460))
        let size = CGSize(width: width, height: hint.height(for: width))
        let bar = barFrame.isEmpty
            ? NSRect(x: bounds.midX, y: bounds.maxY - CaptureModeBarLayout.margin + CaptureModeBarLayout.hintGap, width: 0, height: 0)
            : barFrame
        NoteAnimation.withoutAnimation { hint.frame = CaptureModeBarLayout.hintFrame(size: size, above: bar, in: bounds) }
    }

    package func retire(fading: Bool) {
        readout.hide()
        let presented = isShown
        isShown = false
        isDragging = false
        guard presented, fading, let host, let destination = host.superview, panel.superview === host else {
            if panel.isPresented { panel.dismiss(animated: false) }
            return
        }
        let anchor = destination.convert(panel.anchor, from: host)
        destination.addSubview(panel, positioned: .above, relativeTo: nil)
        panel.margin = 0
        panel.reposition(anchor: anchor, edge: .above, animated: false)
        panel.margin = NoteTheme.menuScreenMargin
        panel.dismiss(animated: true)
    }

    private func anchorRect(in bounds: NSRect) -> NSRect {
        let frame = CaptureModeBarLayout.frame(size: panel.preferredSize, in: bounds)
        return NSRect(x: frame.minX, y: frame.maxY, width: frame.width, height: 0)
    }
}

@MainActor
package enum CaptureModeMotion {
    static let enterDuration: CFTimeInterval = 0.2
    static let exitDuration: CFTimeInterval = 0.18

    package static func enter(_ view: NSView) {
        guard let layer = view.layer else { return }
        NoteAnimation.withoutAnimation { layer.opacity = 1 }
        let duration = NoteAnimation.reduceMotion ? NoteAnimation.reducedFadeDuration : enterDuration
        layer.add(NoteAnimation.basic("opacity", from: 0, to: 1, duration: duration, curve: NoteCurve.hud), forKey: "captureModeEnter")
    }

    package static func fadeAway(_ view: NSView, from host: NSView) {
        guard let destination = host.superview, view.superview != nil, !view.isHidden else { view.removeFromSuperview(); return }
        let frame = destination.convert(view.frame, from: view.superview)
        destination.addSubview(view, positioned: .above, relativeTo: nil)
        NoteAnimation.withoutAnimation { view.frame = frame }
        guard let layer = view.layer else { view.removeFromSuperview(); return }
        NoteAnimation.fade(layer, to: 0, duration: exitDuration, curve: NoteCurve.easeOut, key: "captureModeExit") { [weak view] in
            view?.removeFromSuperview()
        }
    }
}
