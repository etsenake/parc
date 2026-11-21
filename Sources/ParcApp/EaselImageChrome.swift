import AppKit

@MainActor
final class EaselImageChrome: EaselImageChromeHosting {
    private weak var canvas: EaselCanvasView?
    private var overlay: EaselImageChromeOverlay?
    private var bar: EaselImageCropBar?
    private var popover: NotePagePopover?
    private weak var observedClip: NSClipView?
    private var scrollObserver: NSObjectProtocol?

    func showCropBar(on canvas: EaselCanvasView, draft: EaselImageCropDraft) {
        guard let overlay = overlay(for: canvas) else { return }
        let bar: EaselImageCropBar
        if let existing = self.bar, existing.superview === overlay {
            bar = existing
        } else {
            self.bar?.removeFromSuperview()
            bar = EaselImageCropBar(canvas: canvas, chrome: self)
            overlay.addSubview(bar)
            self.bar = bar
            bar.update(draft)
            position(bar, for: draft)
            bar.appear()
            return
        }
        bar.update(draft)
        position(bar, for: draft)
    }

    func hideCropBar(on canvas: EaselCanvasView) {
        popover?.close(animated: false)
        bar?.disappear()
        bar = nil
        retireOverlayIfIdle()
    }

    func editAltText(on canvas: EaselCanvasView, text: String, anchor: NSRect, commit: @escaping (String) -> Void) {
        guard let overlay = overlay(for: canvas) else { return }
        popover?.close(animated: false)
        let editor = NoteMediaAltTextEditor(text: text)
        let popover = NotePagePopover(content: editor)
        editor.onCommit = { [weak popover] value in
            popover?.close()
            commit(value)
        }
        popover.onKeyDown = { [weak editor, weak popover] event in
            guard event.keyCode == 53 else { return false }
            editor?.cancel()
            popover?.close()
            return true
        }
        popover.onClose = { [weak self, weak popover, weak editor] in
            editor?.commitIfPending()
            guard let self, self.popover === popover else { return }
            self.popover = nil
            self.retireOverlayIfIdle()
        }
        self.popover = popover
        popover.present(in: overlay, anchor: overlay.convert(anchor, from: canvas), edge: .below, alignment: .leading)
        editor.focus()
    }

    func pickMask(on canvas: EaselCanvasView, current: EaselImageMask?, preview: CGImage?, anchor: NSRect,
                  pick: @escaping (EaselImageMask?) -> Void) {
        guard let overlay = overlay(for: canvas) else { return }
        popover?.close(animated: false)
        let picker = NoteImageMaskPicker(image: preview, crop: .full, current: current?.noteMask)
        let popover = NotePagePopover(content: picker)
        picker.onPick = { [weak popover] mask in
            popover?.close()
            pick(mask.flatMap { EaselImageMask(rawValue: $0.rawValue) })
        }
        popover.onKeyDown = { [weak picker] event in picker?.handleKeyDown(event) ?? false }
        popover.onClose = { [weak self, weak popover] in
            guard let self, self.popover === popover else { return }
            self.popover = nil
            self.retireOverlayIfIdle()
        }
        if let bar { popover.exempt(bar) }
        self.popover = popover
        popover.present(in: overlay, anchor: overlay.convert(anchor, from: canvas), edge: .below, alignment: .leading)
    }

    fileprivate func presentAspectMenu(from button: NSView, draft: EaselImageCropDraft) {
        guard let canvas, let overlay else { return }
        if popover?.isOpen == true { popover?.close(); return }
        let locked = draft.mask?.isSquare == true && draft.mask != .circle
        var items = NoteImageCropAspect.allCases.map { option in
            NoteMenuList.Item(id: option.id, title: option.title, isChecked: option == draft.aspect && draft.mask != .circle,
                              isEnabled: !locked || option == .square)
        }
        items.append(NoteMenuList.Item(id: "circle", title: "Circle", isChecked: draft.mask == .circle, separatorBefore: true))
        let list = NoteMenuList(items: items)
        list.minimumWidth = 160
        let menu = NotePagePopover(content: list)
        menu.exempt(button)
        list.onActivate = { [weak canvas, weak menu] item in
            menu?.close()
            guard let canvas else { return }
            if item.id == "circle" { canvas.setCropMask(.circle); return }
            guard let option = NoteImageCropAspect.allCases.first(where: { $0.id == item.id }) else { return }
            if canvas.imageCropDraft?.mask == .circle { canvas.setCropMask(nil) }
            canvas.setCropAspect(option)
        }
        list.onCancel = { [weak menu] in menu?.close() }
        menu.onKeyDown = { [weak list] event in list?.handleKeyDown(event) ?? false }
        menu.onClose = { [weak self, weak menu] in
            guard let self, self.popover === menu else { return }
            self.popover = nil
        }
        popover = menu
        menu.present(in: overlay, anchor: overlay.convert(button.bounds, from: button), edge: .below, alignment: .leading)
        if NSApp.currentEvent?.type == .keyDown { list.prepare(origin: .keyboard); _ = list.moveHighlight(by: 1) }
    }

    private func overlay(for canvas: EaselCanvasView) -> EaselImageChromeOverlay? {
        guard let scroll = canvas.enclosingScrollView, let host = scroll.superview else { return nil }
        if self.canvas !== canvas { hideCropBar(on: canvas); overlay?.removeFromSuperview(); overlay = nil }
        self.canvas = canvas
        let overlay = self.overlay ?? EaselImageChromeOverlay()
        if overlay.superview !== host { host.addSubview(overlay, positioned: .above, relativeTo: scroll) }
        if overlay.frame != scroll.frame { overlay.frame = scroll.frame }
        self.overlay = overlay
        observeScroll(scroll.contentView)
        return overlay
    }

    private func observeScroll(_ clip: NSClipView) {
        guard observedClip !== clip || scrollObserver == nil else { return }
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        observedClip = clip
        clip.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scrolled() }
        }
    }

    private func scrolled() {
        guard let canvas, let bar, let draft = canvas.imageCropDraft else { return }
        if let scroll = canvas.enclosingScrollView, let overlay, overlay.frame != scroll.frame { overlay.frame = scroll.frame }
        position(bar, for: draft)
    }

    private func position(_ bar: EaselImageCropBar, for draft: EaselImageCropDraft) {
        guard let canvas, let overlay else { return }
        let frame = overlay.convert(draft.frame, from: canvas)
        let size = bar.fittingSize, area = overlay.bounds.insetBy(dx: 8, dy: 8), gap: CGFloat = 12
        var y = frame.maxY + gap
        if y + size.height > area.maxY { y = frame.minY - gap - size.height }
        y = min(max(area.minY, y), area.maxY - size.height)
        let x = min(max(area.minX, frame.midX - size.width / 2), max(area.minX, area.maxX - size.width))
        bar.frame = NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    private func retireOverlayIfIdle() {
        guard bar == nil, popover?.isOpen != true else { return }
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        scrollObserver = nil
        observedClip = nil
        let retiring = overlay
        overlay = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak retiring] in
            MainActor.assumeIsolated {
                guard let retiring, retiring.subviews.allSatisfy({ $0.isHidden }) else { return }
                retiring.removeFromSuperview()
            }
        }
    }
}

@MainActor
private final class EaselImageChromeOverlay: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

@MainActor
private final class EaselImageCropCard: NSView {
    private let card = CALayer()
    var items: [NSView] = [] {
        didSet {
            for view in oldValue where !items.contains(where: { $0 === view }) { view.removeFromSuperview() }
            for view in items where view.superview !== self { addSubview(view) }
            needsLayout = true
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        card.cornerRadius = 9
        card.cornerCurve = .continuous
        card.borderWidth = 0.5
        card.shadowOpacity = 1
        card.shadowRadius = 7
        card.shadowOffset = CGSize(width: 0, height: -2)
        layer?.addSublayer(card)
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    var fittingWidth: CGFloat {
        guard !items.isEmpty else { return 0 }
        return items.reduce(0) { $0 + $1.intrinsicContentSize.width } + CGFloat(items.count - 1) * NoteMediaToolbar.spacing
            + NoteMediaToolbar.padding * 2
    }

    override func layout() {
        super.layout()
        NoteMediaMotion.instant {
            card.frame = bounds
            card.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 9, cornerHeight: 9, transform: nil)
        }
        var x = NoteMediaToolbar.padding
        for view in items {
            let size = view.intrinsicContentSize
            view.frame = NSRect(x: x, y: ((bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height)
            x += size.width + NoteMediaToolbar.spacing
        }
        refreshColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    private func refreshColors() {
        NoteMediaMotion.instant {
            card.backgroundColor = NoteMediaStyle.cg(NoteTheme.menuFill, in: self)
            card.borderColor = NoteMediaStyle.cg(NoteTheme.menuHairline, in: self)
            card.shadowColor = NoteTheme.menuShadow.cgColor
        }
    }
}

@MainActor
private final class EaselImageCropBar: NSView {
    private weak var canvas: EaselCanvasView?
    private weak var chrome: EaselImageChrome?
    private var draft: EaselImageCropDraft?
    private let tools = EaselImageCropCard()
    private let actions = EaselImageCropCard()
    private let ratioButton = NoteToolbarButton(.iconAndText(.symbol("aspectratio"), "Freeform"), label: "Aspect ratio")
    private let maskButton = NoteToolbarButton(icon: .symbol("square.on.circle"), label: "Mask")
    private let rotateButton = NoteToolbarButton(icon: .symbol("rotate.right"), label: "Rotate 90°")
    private let zoomOutButton = NoteToolbarButton(icon: .symbol("minus.magnifyingglass"), label: "Zoom out", shortcut: "-")
    private let zoomSlider = EaselCropZoomSlider()
    private let zoomInButton = NoteToolbarButton(icon: .symbol("plus.magnifyingglass"), label: "Zoom in", shortcut: "=")
    private let resetChip = NoteChip("Reset", icon: .symbol("arrow.counterclockwise"))
    private let cancelChip = NoteChip("Cancel")
    private let saveChip = NoteChip("Save", icon: .symbol("checkmark"), style: .filled)

    init(canvas: EaselCanvasView, chrome: EaselImageChrome) {
        self.canvas = canvas
        self.chrome = chrome
        super.init(frame: .zero)
        wantsLayer = true
        isHidden = true
        layer?.opacity = 0
        ratioButton.showsDisclosure = true
        maskButton.showsDisclosure = true
        ratioButton.onPress = { [weak self] in
            guard let self, let draft = self.draft else { return }
            self.chrome?.presentAspectMenu(from: self.ratioButton, draft: draft)
        }
        maskButton.onPress = { [weak self] in
            guard let self, let canvas = self.canvas else { return }
            canvas.presentCropMaskPicker(anchor: canvas.convert(self.maskButton.bounds, from: self.maskButton))
        }
        rotateButton.onPress = { [weak self] in self?.canvas?.rotateImageCrop() }
        zoomOutButton.onPress = { [weak self] in self?.canvas?.zoomImageCrop(by: 0.8) }
        zoomInButton.onPress = { [weak self] in self?.canvas?.zoomImageCrop(by: 1.25) }
        zoomSlider.onChange = { [weak self] value in self?.canvas?.setCropZoom(value) }
        resetChip.setToolTip("Show the whole picture")
        cancelChip.setToolTip("Cancel", shortcut: "ESC")
        saveChip.setToolTip("Save", shortcut: "↩")
        resetChip.onPress = { [weak self] in self?.canvas?.resetImageCrop() }
        cancelChip.onPress = { [weak self] in self?.canvas?.finishImageCrop(save: false) }
        saveChip.onPress = { [weak self] in self?.canvas?.finishImageCrop(save: true) }
        tools.items = [ratioButton, maskButton, rotateButton, zoomOutButton, zoomSlider, zoomInButton]
        actions.items = [resetChip, cancelChip, saveChip]
        addSubview(tools)
        addSubview(actions)
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Crop image")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override var fittingSize: NSSize {
        NSSize(width: tools.fittingWidth + 8 + actions.fittingWidth, height: NoteMediaToolbar.height)
    }

    override func layout() {
        super.layout()
        tools.frame = NSRect(x: 0, y: 0, width: tools.fittingWidth, height: NoteMediaToolbar.height)
        actions.frame = NSRect(x: bounds.width - actions.fittingWidth, y: 0, width: actions.fittingWidth, height: NoteMediaToolbar.height)
    }

    func update(_ draft: EaselImageCropDraft) {
        self.draft = draft
        let title = draft.mask == .circle ? "Circle" : draft.aspect.title
        let ratio = NoteToolbarButton.Content.iconAndText(.symbol("aspectratio"), title)
        if ratioButton.content != ratio {
            ratioButton.content = ratio
            EaselControlSurface.crossfade(ratioButton, duration: NoteAnimation.hoverDuration, pops: nil)
        }
        ratioButton.setAccessibilityValue(title)
        maskButton.setAccessibilityValue(draft.mask?.title ?? NoteImageMask.noneTitle)
        zoomSlider.limit = draft.zoomLimit
        zoomSlider.value = draft.zoom
        zoomOutButton.isEnabled = draft.zoom > 1.001
        zoomInButton.isEnabled = draft.zoom < draft.zoomLimit - 0.001
        resetChip.isEnabled = !(draft.isWhole && draft.turns == 0 && draft.zoom <= 1.001)
        needsLayout = true
        if frame.size != fittingSize { setFrameSize(fittingSize) }
    }

    func appear() {
        layoutSubtreeIfNeeded()
        NoteMediaMotion.present(self, anchor: CGPoint(x: 0.5, y: 0))
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    func disappear() {
        NoteMediaMotion.dismiss(self, anchor: CGPoint(x: 0.5, y: 0)) { [weak self] in self?.removeFromSuperview() }
    }
}

@MainActor
private final class EaselCropZoomSlider: NSView {
    var value: CGFloat = 1 {
        didSet {
            guard value != oldValue else { return }
            needsDisplay = true
            placeKnob()
            setAccessibilityValue(Self.label(value))
        }
    }
    var limit: CGFloat = EaselImageCropDraft.maximumZoom { didSet { if limit != oldValue { needsDisplay = true; placeKnob() } } }
    private let knobLayer = CALayer()
    var onChange: ((CGFloat) -> Void)?
    private var tracking = false
    private static let knob: CGFloat = 12

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        knobLayer.bounds = CGRect(x: 0, y: 0, width: Self.knob, height: Self.knob)
        knobLayer.cornerRadius = Self.knob / 2
        knobLayer.borderWidth = 0.5
        knobLayer.shadowRadius = 3
        knobLayer.shadowOffset = CGSize(width: 0, height: 1)
        knobLayer.shadowOpacity = 1
        layer?.addSublayer(knobLayer)
        NoteAnimation.observeReduceMotion(self) { [weak self] in
            guard let self else { return }
            NoteAnimation.settle(self)
            NoteAnimation.withoutAnimation { self.knobLayer.transform = CATransform3DIdentity }
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Zoom")
        setAccessibilityValue(Self.label(value))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 104, height: NoteTheme.toolbarButtonSize.height) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private static func label(_ value: CGFloat) -> String { String(format: "%.1f×", Double(value)) }

    private var track: NSRect { NSRect(x: Self.knob / 2 + 4, y: bounds.midY - 1.5, width: max(0, bounds.width - Self.knob - 8), height: 3) }

    private var fraction: CGFloat {
        let span = log(max(1, limit))
        return span > 0 ? min(1, max(0, log(max(value, 1)) / span)) : 0
    }

    private func value(at fraction: CGFloat) -> CGFloat {
        pow(max(1, limit), min(1, max(0, fraction)))
    }

    private func placeKnob() {
        let bar = track
        NoteAnimation.withoutAnimation {
            knobLayer.position = CGPoint(x: bar.minX + bar.width * fraction, y: bounds.midY)
            knobLayer.backgroundColor = NoteTheme.resolved(NoteTheme.menuFill, in: self)
            knobLayer.borderColor = NoteTheme.resolved(NoteTheme.menuHairline, in: self)
            knobLayer.shadowColor = NoteTheme.menuShadow.cgColor
        }
    }

    private func grow(_ grown: Bool) {
        guard !NoteAnimation.reduceMotion else { return }
        NoteAnimation.springScale(knobLayer, to: grown ? 1.3 : 1, spring: grown ? .highlight : .press, key: NoteAnimation.keyPrefix + "easel.crop.knob")
        NoteAnimation.spring(knobLayer, "shadowRadius", to: CGFloat(grown ? 6 : 3), spring: .highlight, key: NoteAnimation.keyPrefix + "easel.crop.knob.shadow")
    }

    override func layout() {
        super.layout()
        placeKnob()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        placeKnob()
    }

    override func draw(_ dirtyRect: NSRect) {
        let bar = track
        NoteTheme.menuHairline.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
        let filled = NSRect(x: bar.minX, y: bar.minY, width: bar.width * fraction, height: bar.height)
        NoteTheme.menuSecondaryInk.setFill()
        NSBezierPath(roundedRect: filled, xRadius: 1.5, yRadius: 1.5).fill()
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func mouseDown(with event: NSEvent) {
        tracking = true
        grow(true)
        update(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard tracking else { return }
        update(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard tracking else { return }
        tracking = false
        grow(false)
        update(with: event)
    }

    private func update(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil), bar = track
        guard bar.width > 0 else { return }
        let next = value(at: (point.x - bar.minX) / bar.width)
        value = next
        onChange?(next)
    }

    override func accessibilityPerformIncrement() -> Bool {
        let next = value(at: fraction + 0.1)
        value = next
        onChange?(next)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        let next = value(at: fraction - 0.1)
        value = next
        onChange?(next)
        return true
    }
}
