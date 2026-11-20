import AppKit

@MainActor
final class NoteImageContentView: NoteMediaContentView {
    private let picture = CALayer()
    private let ring = CALayer()
    private let shimmer = NoteMediaShimmer()
    private let leadingHandle = NoteMediaResizeHandle(edge: .leading)
    private let trailingHandle = NoteMediaResizeHandle(edge: .trailing)
    private let toolbar = NoteMediaToolbar()
    private let alignChip = NoteToolbarButton(icon: .symbol("text.aligncenter"), label: "Alignment")
    private let captionChip = NoteToolbarButton(icon: .symbol("text.below.photo"), label: "Caption")
    private let replaceChip = NoteToolbarButton(icon: .symbol("arrow.triangle.2.circlepath"), label: "Replace")
    private let downloadChip = NoteToolbarButton(icon: .symbol("arrow.down.to.line"), label: "Download")
    private let openChip = NoteToolbarButton(icon: .symbol("eye"), label: "Open in Quick Look")
    private let deleteChip = NoteToolbarButton(icon: .symbol("trash"), label: "Delete")
    private var source: NoteMediaSource = .empty
    private var props = NoteBlockProps()
    private var natural: CGSize?
    private var image: NoteMediaImage?
    private var requestedPixels = 0
    private var liveWidth: CGFloat?
    private var resizeStart: (width: CGFloat, column: CGFloat)?
    private var settleScale: CGFloat?
    private var hovered = false
    private var alignmentMenu: NoteFloatingPanel?
    private var menuMonitor: Any?
    private var observer: NSObjectProtocol?

    override init(host: NoteMediaBlockView) {
        super.init(host: host)
        picture.contentsGravity = .resizeAspectFill
        picture.masksToBounds = true
        picture.cornerRadius = NoteMediaStyle.imageRadius
        picture.cornerCurve = .continuous
        picture.minificationFilter = .trilinear
        picture.opacity = 0
        ring.cornerRadius = NoteMediaStyle.imageRadius + 2
        ring.cornerCurve = .continuous
        ring.borderWidth = 2
        ring.isHidden = true
        layer?.addSublayer(picture)
        layer?.addSublayer(ring)
        addSubview(shimmer)
        for handle in [leadingHandle, trailingHandle] {
            handle.owner = self
            handle.isHidden = true
            handle.alphaValue = 0
            addSubview(handle)
        }
        alignChip.onPress = { [weak self] in self?.toggleAlignmentMenu() }
        captionChip.onPress = { [weak self] in self?.host?.revealCaption() }
        replaceChip.onPress = { [weak self] in self?.host?.replace() }
        downloadChip.onPress = { [weak self] in self?.host?.download() }
        openChip.onPress = { [weak self] in
            guard let self else { return }
            self.host?.quickLook(from: self.imageRect, in: self)
        }
        deleteChip.onPress = { [weak self] in self?.host?.deleteBlock() }
        addSubview(toolbar)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reduceMotionChanged() }
        }
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let menuMonitor { NSEvent.removeMonitor(menuMonitor) }
    }

    override func update(block: NoteBlock, source: NoteMediaSource) {
        let changed = source != self.source
        self.source = source
        props = block.props
        if changed {
            image = nil
            requestedPixels = 0
            NoteMediaMotion.instant { picture.contents = nil; picture.opacity = 0 }
            picture.removeAllAnimations()
            natural = source.url.flatMap { NoteMediaImageLoader.shared.naturalSize(of: $0) }
            if let url = source.url, let cached = NoteMediaImageLoader.shared.bestCached(url) {
                natural = cached.pointSize
                show(cached, animated: false)
            }
        }
        configureToolbar()
        needsLayout = true
    }

    private var editable: Bool { host?.canEdit == true }

    private func displayWidth(for column: CGFloat) -> CGFloat {
        if let liveWidth { return liveWidth }
        return NoteMediaLayout.displayWidth(fraction: props.width, natural: natural, columnWidth: column)
    }

    private func rect(for column: CGFloat) -> NSRect {
        let width = displayWidth(for: column)
        let height = NoteMediaLayout.displayHeight(width: width, natural: natural)
        let x = NoteMediaLayout.originX(width: width, alignment: props.alignment, columnWidth: column)
        return NSRect(x: x, y: 0, width: width, height: max(1, height))
    }

    var imageRect: NSRect { rect(for: bounds.width) }

    override func measureHeight(width: CGFloat) -> CGFloat { rect(for: width).height }
    override var handleAnchorY: CGFloat { 14 }

    override func captionSpan(width: CGFloat) -> (x: CGFloat, width: CGFloat) {
        let frame = rect(for: width)
        let span = max(frame.width, min(width, 220))
        let x = min(max(0, frame.midX - span / 2), width - span)
        return props.alignment == .left ? (frame.minX, span) : props.alignment == .right ? (frame.maxX - span, span) : (x, span)
    }

    override func layout() {
        super.layout()
        let frame = imageRect
        let anchorX: CGFloat = props.alignment == .left ? 0 : props.alignment == .right ? 1 : 0.5
        NoteMediaMotion.instant {
            picture.anchorPoint = CGPoint(x: anchorX, y: 0)
            picture.bounds = CGRect(origin: .zero, size: frame.size)
            picture.position = CGPoint(x: frame.minX + anchorX * frame.width, y: frame.minY)
            picture.contentsScale = window?.backingScaleFactor ?? 2
            ring.frame = frame.insetBy(dx: -3, dy: -3)
            ring.borderColor = NoteMediaStyle.cg(NoteTheme.accent, in: self)
        }
        shimmer.frame = frame
        shimmer.isHidden = image != nil
        let handleHeight = min(48, max(24, frame.height * 0.3))
        leadingHandle.frame = NSRect(x: frame.minX + 4, y: frame.midY - handleHeight / 2, width: 14, height: handleHeight)
        trailingHandle.frame = NSRect(x: frame.maxX - 18, y: frame.midY - handleHeight / 2, width: 14, height: handleHeight)
        let toolbarWidth = toolbar.fittingWidth
        let toolbarX = min(max(0, frame.maxX - 8 - toolbarWidth), max(0, bounds.width - toolbarWidth))
        toolbar.frame = NSRect(x: toolbarX, y: frame.minY + 8, width: toolbarWidth, height: NoteMediaToolbar.height)
        if let settleScale {
            self.settleScale = nil
            settle(from: settleScale)
        }
        requestIfNeeded()
    }

    private func requestIfNeeded() {
        guard let url = source.url, bounds.width > 0 else { return }
        let frame = imageRect
        let scale = window?.backingScaleFactor ?? 2
        let pixels = NoteMediaImageLoader.pixels(for: frame.size, scale: scale)
        let bucket = NoteMediaImageLoader.bucket(for: pixels)
        if let image, image.decodedPixels >= min(bucket, maxNaturalPixels) { return }
        guard bucket > requestedPixels else { return }
        requestedPixels = bucket
        let expected = source
        NoteMediaImageLoader.shared.load(url, pixels: pixels) { [weak self] result in
            guard let self, self.source == expected else { return }
            switch result {
            case .success(let loaded):
                let first = self.image == nil
                let aspectChanged = self.natural.map { abs(NoteMediaLayout.aspect(of: $0) - NoteMediaLayout.aspect(of: loaded.pointSize)) > 0.001 } ?? true
                self.natural = loaded.pointSize
                self.show(loaded, animated: first && self.window != nil)
                if aspectChanged { self.host?.invalidateMeasuredHeight() }
                self.needsLayout = true
            case .failure(let error):
                guard self.image == nil else { return }
                self.host?.contentDidFail(NoteMediaBlockView.problem(for: error))
            }
        }
    }

    private var maxNaturalPixels: Int {
        guard let natural else { return .max }
        return NoteMediaImageLoader.bucket(for: Int(max(natural.width, natural.height) * 2))
    }

    private func show(_ loaded: NoteMediaImage, animated: Bool) {
        image = loaded
        NoteMediaMotion.instant { picture.contents = loaded.first }
        shimmer.isHidden = true
        if animated {
            NoteMediaMotion.fadeIn(picture, duration: 0.2)
        } else {
            NoteMediaMotion.instant { picture.opacity = 1 }
        }
        refreshAnimation()
    }

    private func refreshAnimation() {
        guard let image, image.isAnimated else { picture.removeAnimation(forKey: "media.frames"); return }
        let shouldPlay = host?.isOnScreen == true && !NoteAnimation.reduceMotion
        let playing = picture.animation(forKey: "media.frames") != nil
        if shouldPlay && !playing {
            picture.add(NoteImageFrames.animation(for: image), forKey: "media.frames")
        } else if !shouldPlay && playing {
            picture.removeAnimation(forKey: "media.frames")
        }
    }

    override func visibilityDidChange() {
        refreshAnimation()
        if host?.isOnScreen == true { requestIfNeeded() }
    }

    private func reduceMotionChanged() {
        if NoteAnimation.reduceMotion {
            picture.removeAnimation(forKey: "media.settle")
            picture.removeAnimation(forKey: "media.fadeIn")
            NoteMediaMotion.instant { picture.transform = CATransform3DIdentity }
            toolbar.layer?.removeAllAnimations()
        }
        refreshAnimation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { dismissMenu() }
        refreshAnimation()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    override func setSelected(_ selected: Bool) {
        NoteMediaMotion.instant { ring.isHidden = !selected }
    }

    override func readOnlyDidChange() {
        configureToolbar()
        setHovered(hovered)
    }

    private func configureToolbar() {
        let column = bounds.width > 0 ? bounds.width : 10_000
        let fullWidth = displayWidth(for: column) >= column - 1
        alignChip.content = .icon(.symbol(Self.alignmentSymbol(props.alignment)))
        var chips: [NoteControlButton] = []
        if editable {
            if !fullWidth { chips.append(alignChip) }
            if host?.captionVisible != true { chips.append(captionChip) }
            chips.append(replaceChip)
        }
        chips.append(downloadChip)
        chips.append(openChip)
        if editable { chips.append(deleteChip) }
        toolbar.setButtons(chips)
        needsLayout = true
    }

    static func alignmentSymbol(_ alignment: NoteAlignment) -> String {
        switch alignment {
        case .left: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        }
    }

    override func setHovered(_ hovered: Bool) {
        self.hovered = hovered
        let visible = (hovered || resizeStart != nil || alignmentMenu != nil) && image != nil
        if visible {
            configureToolbar()
            layoutSubtreeIfNeeded()
            toolbar.show()
        } else {
            toolbar.hide()
        }
        let showsHandles = visible && editable && imageRect.height >= 36
        for handle in [leadingHandle, trailingHandle] { handle.setRevealed(showsHandles) }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard imageRect.contains(point) else { super.mouseDown(with: event); return }
        if event.clickCount >= 2, let image {
            host?.zoom(image: image, from: imageRect, in: self)
            return
        }
        if host?.selectBlock(with: event) == true { return }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        if image != nil { addCursorRect(imageRect, cursor: .pointingHand) }
    }

    func beginResize() {
        guard editable else { return }
        resizeStart = (imageRect.width, bounds.width)
        dismissMenu()
    }

    func updateResize(edge: NoteMediaEdge, delta: CGFloat) {
        guard let start = resizeStart else { return }
        let raw = NoteMediaLayout.rawResize(start: start.width, dragDelta: delta, edge: edge, alignment: props.alignment)
        liveWidth = NoteMediaLayout.rubberBanded(raw, columnWidth: start.column).rounded()
        needsLayout = true
        host?.invalidateMeasuredHeight()
    }

    func endResize() {
        guard let start = resizeStart else { return }
        resizeStart = nil
        let live = liveWidth ?? start.width
        let fraction = NoteMediaLayout.storedFraction(width: live, columnWidth: start.column)
        let settled = NoteMediaLayout.displayWidth(fraction: fraction, natural: natural, columnWidth: start.column)
        liveWidth = nil
        if settled > 0, abs(live - settled) > 0.5 { settleScale = live / settled }
        if props.width != fraction { host?.commitWidth(fraction) }
        needsLayout = true
        host?.invalidateMeasuredHeight()
        setHovered(hovered)
    }

    private func settle(from scale: CGFloat) {
        guard !NoteAnimation.reduceMotion else { return }
        let from = CATransform3DMakeScale(scale, scale, 1)
        NoteMediaMotion.instant { picture.transform = CATransform3DIdentity }
        picture.add(NoteAnimation.spring("transform", .settle, from: NSValue(caTransform3D: from), to: NSValue(caTransform3D: CATransform3DIdentity)),
                    forKey: "media.settle")
    }

    private func toggleAlignmentMenu() {
        if menu != nil { dismissMenu(); return }
        guard let overlay = host?.editor?.canvas.overlayView else { return }
        let list = NoteMenuList()
        list.items = NoteAlignment.allCases.map { alignment in
            NoteMenuList.Item(id: alignment.rawValue, title: Self.alignmentTitle(alignment),
                              icon: .symbol(Self.alignmentSymbol(alignment)), isChecked: alignment == props.alignment)
        }
        list.onActivate = { [weak self] item in
            guard let self, let alignment = NoteAlignment(rawValue: item.id) else { return }
            self.dismissMenu()
            self.host?.setAlignment(alignment)
        }
        let panel = NoteFloatingPanel(content: list)
        panel.onDismiss = { [weak self] in self?.menuDidClose() }
        let anchor = overlay.convert(alignChip.bounds, from: alignChip)
        panel.present(in: overlay, anchor: anchor, edge: .below)
        alignmentMenu = panel
        menuMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let isKey = event.type == .keyDown, keyCode = event.keyCode
            let location = event.locationInWindow, windowNumber = event.windowNumber
            let consumed = MainActor.assumeIsolated {
                self?.menuEvent(isKey: isKey, keyCode: keyCode, location: location, windowNumber: windowNumber) ?? false
            }
            return consumed ? nil : event
        }
    }

    private func menuEvent(isKey: Bool, keyCode: UInt16, location: NSPoint, windowNumber: Int) -> Bool {
        guard let panel = alignmentMenu else { return false }
        if isKey {
            guard keyCode == 53 else { return false }
            dismissMenu()
            return true
        }
        guard windowNumber == window?.windowNumber else { dismissMenu(); return false }
        if panel.bounds.contains(panel.convert(location, from: nil)) { return false }
        if alignChip.bounds.contains(alignChip.convert(location, from: nil)) { return false }
        dismissMenu()
        return false
    }

    static func alignmentTitle(_ alignment: NoteAlignment) -> String {
        switch alignment {
        case .left: return "Align Left"
        case .center: return "Center"
        case .right: return "Align Right"
        }
    }

    private func dismissMenu() {
        guard let panel = alignmentMenu else { return }
        alignmentMenu = nil
        panel.dismiss(animated: true)
    }

    private func menuDidClose() {
        alignmentMenu = nil
        if let menuMonitor { NSEvent.removeMonitor(menuMonitor) }
        menuMonitor = nil
        setHovered(hovered)
    }
}

@MainActor
final class NoteMediaResizeHandle: NSView, ResizeHandleView {
    let edge: NoteMediaEdge
    weak var owner: NoteImageContentView?
    private let pill = CALayer()
    private var startX: CGFloat = 0
    private var dragging = false
    private var revealed = false

    init(edge: NoteMediaEdge) {
        self.edge = edge
        super.init(frame: .zero)
        wantsLayer = true
        pill.cornerRadius = 3
        pill.cornerCurve = .continuous
        pill.borderWidth = 0.5
        pill.shadowOpacity = 0.25
        pill.shadowRadius = 3
        pill.shadowOffset = CGSize(width: 0, height: -1)
        pill.shadowColor = NSColor.black.cgColor
        layer?.addSublayer(pill)
        setAccessibilityElement(true)
        setAccessibilityRole(.handle)
        setAccessibilityLabel(edge == .leading ? "Resize from the left" : "Resize from the right")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        NoteMediaMotion.instant {
            pill.frame = NSRect(x: (bounds.width - 6) / 2, y: 0, width: 6, height: bounds.height)
            pill.backgroundColor = NoteMediaStyle.cg(NoteMediaStyle.handleFill, in: self)
            pill.borderColor = NoteMediaStyle.cg(NoteMediaStyle.handleStroke, in: self)
            pill.shadowPath = CGPath(roundedRect: pill.bounds, cornerWidth: 3, cornerHeight: 3, transform: nil)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    func setRevealed(_ value: Bool) {
        guard value != revealed || dragging else { return }
        revealed = value || dragging
        if revealed { isHidden = false }
        NoteAnimation.fade(self, visible: revealed, duration: 0.1) { [weak self] in
            guard let self, !self.revealed else { return }
            self.isHidden = true
        }
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        if revealed { addCursorRect(bounds, cursor: .resizeLeftRight) }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard revealed else { return }
        startX = event.locationInWindow.x
        dragging = true
        owner?.beginResize()
        NSCursor.resizeLeftRight.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        owner?.updateResize(edge: edge, delta: event.locationInWindow.x - startX)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        NSCursor.pop()
        owner?.endResize()
    }

    override func accessibilityPerformIncrement() -> Bool { nudge(by: 24) }
    override func accessibilityPerformDecrement() -> Bool { nudge(by: -24) }

    private func nudge(by amount: CGFloat) -> Bool {
        guard let owner else { return false }
        owner.beginResize()
        owner.updateResize(edge: .trailing, delta: amount / 2)
        owner.endResize()
        return true
    }
}
