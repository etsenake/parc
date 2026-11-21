import AppKit

@MainActor
final class NoteButtonPillView: NSView {
    static let horizontalPadding: CGFloat = 12
    static let iconSide: CGFloat = 18
    static let iconGap: CGFloat = 7

    var label = "" { didSet { if label != oldValue { needsDisplay = true; refreshAccessibility() } } }
    var icon: String? { didSet { if icon != oldValue { needsDisplay = true } } }
    var isPlaceholder = false { didSet { if isPlaceholder != oldValue { needsDisplay = true } } }
    var color: NoteColorStyle? { didSet { if color != oldValue { needsDisplay = true } } }
    var font = NoteTheme.nunitoBold(15) { didSet { needsDisplay = true } }
    var isActive = false { didSet { if isActive != oldValue { needsDisplay = true } } }
    var isSelected = false { didSet { if isSelected != oldValue { needsDisplay = true } } }
    var onPress: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private(set) var isHovered = false
    private var isPressed = false
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityHelp("Press to run its actions")
        NoteAnimation.observeReduceMotion(self) { [weak self] in
            guard let layer = self?.layer else { return }
            NoteAnimation.settle(layer)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func naturalWidth() -> CGFloat {
        let text = ceil(NSAttributedString(string: label, attributes: [.font: font]).size().width)
        let iconWidth = icon == nil ? 0 : Self.iconSide + Self.iconGap
        return Self.horizontalPadding * 2 + iconWidth + text
    }

    private var ink: NSColor {
        if isPlaceholder { return NoteTheme.tertiaryInk }
        if let color, !color.isBackground { return NoteTheme.color(color) }
        return NoteTheme.ink
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = NoteTheme.controlRadius + 2
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        if let color, color.isBackground { NoteTheme.color(color).setFill() } else { NoteTheme.menuFill.setFill() }
        shape.fill()
        if isPressed {
            NoteTheme.pressedFill.setFill()
            shape.fill()
        } else if isHovered || isActive {
            NoteTheme.hoverFill.setFill()
            shape.fill()
        }
        (isSelected ? NoteTheme.accent : NoteTheme.menuHairline).setStroke()
        shape.lineWidth = isSelected ? 1.5 : 1
        shape.stroke()
        var x = Self.horizontalPadding
        if let icon {
            NoteIconRenderer.draw(.emoji(icon), in: NSRect(x: x, y: ((bounds.height - Self.iconSide) / 2).rounded(), width: Self.iconSide,
                                                          height: Self.iconSide), tint: ink, pointSize: (font.pointSize * 0.95).rounded())
            x += Self.iconSide + Self.iconGap
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let height = ceil(font.ascender - font.descender)
        NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph])
            .draw(with: NSRect(x: x, y: ((bounds.height - height) / 2).rounded(), width: max(0, bounds.width - x - Self.horizontalPadding + 2),
                               height: height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)) }
    override func mouseMoved(with event: NSEvent) { setHovered(NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ value: Bool) {
        guard value != isHovered else { return }
        isHovered = value
        needsDisplay = true
        onHover?(value)
    }

    override func cursorUpdate(with event: NSEvent) {
        if !applyNoteCursor(.pointingHand, for: event) { super.cursorUpdate(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.shift, .command]).isEmpty else {
            superview?.mouseDown(with: event)
            return
        }
        setPressed(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isPressed || bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        setPressed(bounds.contains(convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        let fire = isPressed && inside
        setPressed(false)
        if fire { onPress?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }

    func celebrate() {
        guard let layer else { return }
        NoteAnimation.pop(layer, from: 0.94, spring: .pill, about: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    func refuse() {
        guard let layer else { return }
        NoteAnimation.pop(layer, from: 0.97, spring: .bounce, about: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    private func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        needsDisplay = true
        guard let layer else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let target = pressed ? NoteAnimation.scaleTransform(NoteAnimation.pressedScale, about: center) : CATransform3DIdentity
        if NoteAnimation.reduceMotion {
            NoteAnimation.withoutAnimation { layer.transform = CATransform3DIdentity }
            return
        }
        NoteAnimation.spring(layer, "transform", to: NSValue(caTransform3D: target), spring: .press, key: NoteAnimation.keyPrefix + "button.press")
    }

    private func refreshAccessibility() {
        setAccessibilityLabel(label)
    }
}

@MainActor
final class NoteButtonBlockView: NoteBlockView {
    nonisolated static let verticalPadding: CGFloat = NoteButtonMetrics.verticalPadding
    static let gearGap: CGFloat = 4

    nonisolated static func pillHeight(scale: CGFloat) -> CGFloat { NoteButtonMetrics.pillHeight(scale: scale) }
    nonisolated static func height(scale: CGFloat) -> CGFloat { NoteButtonMetrics.height(scale: scale) }

    let pill = NoteButtonPillView()
    private let gear = NoteToolbarButton(icon: .symbol("gearshape"), label: "Edit button")
    private var isHovered = false
    private var press: NoteButtonPress?
    private var tracking: NSTrackingArea?
    private var panel: NoteFloatingPanel?
    private var editorView: NoteButtonEditorView?
    private var outsideMonitor: Any?

    override init(block: NoteBlock, editor: NotePageEditor?) {
        super.init(block: block, editor: editor)
        pill.onPress = { [weak self] in self?.pressButton() }
        pill.onHover = { [weak self] _ in self?.refreshGear(animated: true) }
        gear.onPress = { [weak self] in self?.openEditor() }
        gear.iconPointSize = 13
        gear.alphaValue = 0
        addSubview(pill)
        addSubview(gear)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var isEditing: Bool { panel != nil }

    private var pageSettings: NotePageSettings { editor?.session.page.settings ?? NotePageSettings() }
    private var scale: CGFloat { pageSettings.smallText ? NoteTheme.smallBodySize / NoteTheme.bodySize : 1 }
    private var canEdit: Bool { !isReadOnly && editor?.isReadOnly != true }

    override func update(_ block: NoteBlock) {
        super.update(block)
        refresh()
    }

    override func readOnlyDidChange() {
        if isReadOnly { closeEditor(reselect: false, animated: true) }
        refreshGear(animated: false)
    }

    override func themeDidChange() {
        super.themeDidChange()
        pill.needsDisplay = true
    }

    func refresh() {
        let button = block.buttonValue
        let name = button.name.trimmingCharacters(in: .whitespacesAndNewlines)
        pill.label = name.isEmpty ? NoteButton.placeholderName : name
        pill.isPlaceholder = name.isEmpty
        pill.icon = block.props.icon.flatMap { $0.isEmpty ? nil : $0 }
        pill.color = block.color
        pill.font = NoteTheme.nunitoBold((15 * scale).rounded())
        pill.setAccessibilityHelp(button.summary)
        setAccessibilityLabel("Button: " + pill.label)
        needsLayout = true
    }

    override func measureHeight(width: CGFloat) -> CGFloat { Self.height(scale: scale) }
    override var handleAnchorY: CGFloat { Self.height(scale: scale) / 2 }

    override func layout() {
        super.layout()
        let height = Self.pillHeight(scale: scale)
        let gearSide = NoteTheme.toolbarButtonSize.width
        let width = min(max(height * 2.5, pill.naturalWidth()), max(height, bounds.width - gearSide - Self.gearGap))
        NoteAnimation.withoutAnimation {
            pill.frame = NSRect(x: 0, y: Self.verticalPadding, width: width.rounded(.up), height: height)
            gear.frame = NSRect(x: pill.frame.maxX + Self.gearGap, y: pill.frame.midY - gearSide / 2, width: gearSide, height: gearSide)
        }
        repositionPanel()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        repositionPanel()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { closeEditor(reselect: false, animated: false) }
    }

    override func setBlockSelected(_ selected: Bool, animated: Bool) {
        super.setBlockSelected(selected, animated: animated)
        pill.isSelected = selected
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)) }

    override func mouseMoved(with event: NSEvent) { setHovered(NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)) }

    private func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        refreshGear(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refreshGear(animated: true)
    }

    func refreshGear(animated: Bool) {
        let visible = canEdit && (isHovered || pill.isHovered || isEditing)
        gear.isEnabled = canEdit
        let target: CGFloat = visible ? 1 : 0
        guard gear.alphaValue != target else { return }
        guard animated, !NoteAnimation.reduceMotion, window != nil else {
            gear.alphaValue = target
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NoteAnimation.hoverDuration
            context.timingFunction = NoteCurve.hover
            gear.animator().alphaValue = target
        }
    }

    override func mouseDown(with event: NSEvent) {
        NoteBlockPointer.selectBlock(self, with: event)
    }

    override func accessibilityPerformPress() -> Bool {
        pressButton()
        return true
    }

    override func focus(at offset: Int?, field: NoteTextField = .body) -> Bool {
        guard canEdit else { return false }
        openEditor()
        return true
    }

    func openEditor() {
        guard canEdit, panel == nil, let editor, window != nil, editor.session.page.contains(blockID) else { return }
        let content = NoteButtonEditorView(block: block, editor: editor)
        content.frame.size = content.fittingSize
        content.onClose = { [weak self] in self?.closeEditor(reselect: true, animated: true) }
        let floating = NoteFloatingPanel(content: content)
        floating.alignment = .leading
        floating.onDismiss = { [weak self, weak floating] in
            guard let self, let floating, self.panel === floating else { return }
            self.finishEditing()
        }
        panel = floating
        editorView = content
        let host = editor.canvas.overlayView
        floating.present(in: host, anchor: anchorRect(in: host), edge: .below)
        content.didPresent()
        pill.isActive = true
        refreshGear(animated: true)
        outsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let content = self.editorView, let window = self.window, event.window === window else { return }
                if self.pill.bounds.contains(self.pill.convert(event.locationInWindow, from: nil)) { return }
                let root = window.contentView?.superview ?? window.contentView
                guard let hit = root?.hitTest(event.locationInWindow) else { return }
                if !content.contains(hit) && hit !== self.gear { self.closeEditor(reselect: false, animated: true) }
            }
            return event
        }
    }

    func closeEditor(reselect: Bool, animated: Bool) {
        guard let floating = panel else { return }
        let hadFocus = editorView?.hasFocus ?? false
        finishEditing()
        floating.dismiss(animated: animated)
        guard let editor, reselect || hadFocus, window != nil, editor.session.page.contains(blockID) else { return }
        window?.makeFirstResponder(editor.canvas)
        editor.session.setSelection(.blocks([blockID]))
        editor.restoreFocus()
    }

    private func finishEditing() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
        editorView?.tearDown()
        editorView = nil
        panel = nil
        pill.isActive = false
        refreshGear(animated: true)
    }

    private func anchorRect(in host: NSView) -> NSRect {
        host.convert(pill.frame, from: self)
    }

    private func repositionPanel() {
        guard let panel, let host = panel.superview else { return }
        panel.reposition(anchor: anchorRect(in: host), edge: panel.resolvedEdge, animated: false)
        editorView?.syncOverlays()
    }

    func pressButton() {
        guard press == nil, !isEditing, let editor else { return }
        let button = block.buttonValue
        if button.actions.isEmpty {
            if canEdit { openEditor() } else { pill.refuse() }
            return
        }
        if editor.isReadOnly, button.actions.contains(where: { $0.kind == .insert }) {
            pill.refuse()
            let locked = editor.session.page.settings.locked
            editor.formatBar.showToast(.standard(locked ? "Unlock the note to press this button." : "This note is read-only, so the button can’t add anything.",
                                                 icon: "lock"))
            return
        }
        let run = NoteButtonPress(session: editor.session, button: blockID, confirm: { [weak self] message, decide in
            guard let window = self?.window ?? editor.canvas.window else { decide(false); return }
            let title = message.trimmingCharacters(in: .whitespacesAndNewlines)
            ParcDialog.confirm(in: window, title: title.isEmpty ? "Are you sure?" : title, message: nil, confirm: "Continue") { proceed in
                decide(proceed)
            }
        }, open: { [weak editor] target in
            editor?.formatBar.open(target)
        })
        guard let run else { return }
        press = run
        run.onFinish = { [weak self] finished in self?.pressDidFinish(finished) }
        run.start()
    }

    private func pressDidFinish(_ finished: NoteButtonPress) {
        press = nil
        guard let editor, !finished.inserted.isEmpty else { return }
        pill.celebrate()
        editor.canvas.layoutSubtreeIfNeeded()
        let live = finished.inserted.filter { editor.session.page.contains($0) }
        if let first = live.first, let frame = editor.canvas.frame(of: first), !editor.canvas.visibleRect.intersects(frame) {
            editor.canvas.scrollBlockToVisible(first)
            editor.canvas.layoutSubtreeIfNeeded()
        }
        for id in live {
            if let view = editor.canvas.existingBlockView(for: id) { NoteBlockWash.flash(view) }
        }
    }
}
