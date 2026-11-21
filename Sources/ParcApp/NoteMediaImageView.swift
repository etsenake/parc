import AppKit
import ParcCore

@MainActor
protocol NoteMediaResizing: AnyObject {
    func beginResize()
    func updateResize(edge: NoteMediaEdge, delta: CGFloat)
    func endResize()
}

@MainActor
final class NoteImageContentView: NoteMediaContentView, NoteMediaResizing {
    private let frameLayer = CALayer()
    private let picture = CALayer()
    private let maskLayer = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let shimmer = NoteMediaShimmer()
    private let leadingHandle = NoteMediaResizeHandle(edge: .leading)
    private let trailingHandle = NoteMediaResizeHandle(edge: .trailing)
    private let toolbar = NoteMediaToolbar()
    private let altBadge = NoteMediaAltBadge()
    private let alignChip = NoteToolbarButton(icon: .symbol("text.aligncenter"), label: "Alignment")
    private let captionChip = NoteToolbarButton(icon: .symbol("text.below.photo"), label: "Caption")
    private let replaceChip = NoteToolbarButton(icon: .symbol("arrow.triangle.2.circlepath"), label: "Replace")
    private let downloadChip = NoteToolbarButton(icon: .symbol("arrow.down.to.line"), label: "Download")
    private let openChip = NoteToolbarButton(icon: .symbol("eye"), label: "Open in Quick Look")
    private let moreChip = NoteToolbarButton(icon: .symbol("ellipsis"), label: "More")
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
    private var morePopover: NotePagePopover?
    private var framingPopover: NotePagePopover?
    private(set) var cropEditor: NoteImageCropEditor?
    private var animatesNextLayout = false
    private var imageZone = NoteZoneCursor()
    private var clickAwayMonitor: Any?
    private weak var responderBeforeCrop: NSResponder?
    static let cropMaximumHeight: CGFloat = 560

    override init(host: NoteMediaHost) {
        super.init(host: host)
        addCursorZoneArea()
        frameLayer.masksToBounds = true
        frameLayer.cornerRadius = NoteMediaStyle.imageRadius
        frameLayer.cornerCurve = .continuous
        picture.contentsGravity = .resizeAspectFill
        picture.anchorPoint = .zero
        picture.minificationFilter = .trilinear
        picture.opacity = 0
        maskLayer.fillColor = NSColor.black.cgColor
        maskLayer.anchorPoint = .zero
        ring.fillColor = nil
        ring.lineWidth = 2
        ring.isHidden = true
        frameLayer.addSublayer(picture)
        layer?.addSublayer(frameLayer)
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
        replaceChip.onPress = { [weak self] in
            guard let self else { return }
            self.host?.presentReplaceMenu(from: self.replaceChip)
        }
        downloadChip.onPress = { [weak self] in self?.host?.download() }
        openChip.onPress = { [weak self] in
            guard let self else { return }
            self.host?.quickLook(from: self.imageRect, in: self)
        }
        moreChip.onPress = { [weak self] in self?.toggleMoreMenu() }
        altBadge.onPress = { [weak self] in self?.editAltText() }
        addSubview(toolbar)
        addSubview(altBadge)
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
        if let clickAwayMonitor { NSEvent.removeMonitor(clickAwayMonitor) }
    }

    override func update(block: NoteBlock, source: NoteMediaSource) {
        let changed = source != self.source
        let framingChanged = block.props.crop != props.crop || block.props.mask != props.mask
        self.source = source
        props = block.props
        if changed {
            if cropEditor != nil { finishCrop(save: false) }
            image = nil
            requestedPixels = 0
            NoteMediaMotion.instant { picture.contents = nil; picture.opacity = 0 }
            picture.removeAllAnimations()
            natural = source.url.flatMap { NoteMediaImageLoader.shared.naturalSize(of: $0) }
            if let url = source.url, let cached = NoteMediaImageLoader.shared.bestCached(url) {
                natural = cached.pointSize
                show(cached, animated: false)
            }
        } else if framingChanged, window != nil, image != nil {
            animatesNextLayout = true
        }
        configureToolbar()
        refreshBadge()
        needsLayout = true
    }

    override func rebind(to source: NoteMediaSource) {
        guard image != nil else { return }
        self.source = source
    }

    private var editable: Bool { host?.canEdit == true }

    private var altText: String { props.alt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }

    private var shownCrop: NoteImageCrop { cropEditor == nil ? (props.crop ?? .full) : .full }

    private var framedNatural: CGSize? { natural.map { (props.crop ?? .full).croppedSize(of: $0) } }

    private func displayWidth(for column: CGFloat) -> CGFloat {
        if let liveWidth { return liveWidth }
        return NoteMediaLayout.displayWidth(fraction: props.width, natural: framedNatural, columnWidth: column)
    }

    private func frameRect(for column: CGFloat) -> NSRect {
        let width = displayWidth(for: column)
        let natural = framedNatural ?? props.crop.map { crop in
            CGSize(width: CGFloat(crop.width), height: CGFloat(crop.height) * NoteMediaLayout.fallbackAspect)
        }
        let height = NoteMediaLayout.displayHeight(width: width, natural: natural)
        let x = NoteMediaLayout.originX(width: width, alignment: props.alignment, columnWidth: column)
        return NSRect(x: x, y: 0, width: width, height: max(1, height))
    }

    private func cropRect(for column: CGFloat) -> NSRect {
        let frame = frameRect(for: column)
        let crop = props.crop ?? .full
        let aspect = NoteMediaLayout.aspect(of: natural)
        var width = min(column, max(frame.width, frame.width / CGFloat(crop.width)))
        if width * aspect > Self.cropMaximumHeight { width = max(min(column, NoteMediaLayout.minimumWidth), Self.cropMaximumHeight / aspect) }
        width = width.rounded()
        let x = NoteMediaLayout.originX(width: width, alignment: props.alignment, columnWidth: column)
        return NSRect(x: x, y: 0, width: width, height: max(1, (width * aspect).rounded()))
    }

    private func rect(for column: CGFloat) -> NSRect {
        cropEditor == nil ? frameRect(for: column) : cropRect(for: column)
    }

    var imageRect: NSRect { rect(for: bounds.width) }

    override func measureHeight(width: CGFloat) -> CGFloat {
        let height = rect(for: width).height
        return cropEditor == nil ? height : height + NoteImageCropEditor.barGap + NoteImageCropEditor.barHeight
    }

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
        let local = CGRect(origin: .zero, size: frame.size)
        let pictureRect = shownCrop.fullRect(forFrame: local)
        let mask = cropEditor == nil ? props.mask : nil
        let animated = animatesNextLayout && window != nil && !NoteAnimation.reduceMotion
        animatesNextLayout = false
        applyGeometry(frame: frame, anchorX: anchorX, picture: pictureRect, maskPath: mask?.path(in: local), animated: animated)
        NoteMediaMotion.instant {
            picture.contentsScale = window?.backingScaleFactor ?? 2
            ring.path = Self.ringPath(frame: frame, mask: mask)
            ring.strokeColor = NoteMediaStyle.cg(NoteTheme.accent, in: self)
        }
        shimmer.frame = frame
        shimmer.isHidden = image != nil
        let handleHeight = min(48, max(24, frame.height * 0.3))
        leadingHandle.frame = NSRect(x: frame.minX + 4, y: frame.midY - handleHeight / 2, width: 14, height: handleHeight)
        trailingHandle.frame = NSRect(x: frame.maxX - 18, y: frame.midY - handleHeight / 2, width: 14, height: handleHeight)
        let toolbarWidth = toolbar.fittingWidth
        let toolbarX = min(max(0, frame.maxX - 8 - toolbarWidth), max(0, bounds.width - toolbarWidth))
        toolbar.frame = NSRect(x: toolbarX, y: frame.minY + 8, width: toolbarWidth, height: NoteMediaToolbar.height)
        let badgeSize = altBadge.intrinsicContentSize
        let badgeInset: CGFloat = mask == nil ? 8 : max(8, min(frame.width, frame.height) * 0.16)
        altBadge.frame = NSRect(x: frame.minX + badgeInset, y: frame.maxY - badgeInset - badgeSize.height,
                                width: badgeSize.width, height: badgeSize.height)
        if let cropEditor {
            cropEditor.frame = bounds
            cropEditor.imageRect = frame
        }
        if let settleScale {
            self.settleScale = nil
            settle(from: settleScale)
        }
        requestIfNeeded()
    }

    private static func ringPath(frame: NSRect, mask: NoteImageMask?) -> CGPath {
        let outset = frame.insetBy(dx: -3, dy: -3)
        if let mask { return mask.path(in: outset) }
        let radius = NoteMediaStyle.imageRadius + 2
        return CGPath(roundedRect: outset, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private func applyGeometry(frame: NSRect, anchorX: CGFloat, picture pictureRect: CGRect, maskPath: CGPath?, animated: Bool) {
        let fromBounds = frameLayer.presentation()?.bounds ?? frameLayer.bounds
        let fromPosition = frameLayer.presentation()?.position ?? frameLayer.position
        let fromPictureBounds = picture.presentation()?.bounds ?? picture.bounds
        let fromPicturePosition = picture.presentation()?.position ?? picture.position
        let fromPath = frameLayer.mask === maskLayer ? (maskLayer.presentation()?.path ?? maskLayer.path) : nil
        let toBounds = CGRect(origin: .zero, size: frame.size)
        let toPosition = CGPoint(x: frame.minX + anchorX * frame.width, y: frame.minY)
        let toPictureBounds = CGRect(origin: .zero, size: pictureRect.size)
        NoteMediaMotion.instant {
            frameLayer.anchorPoint = CGPoint(x: anchorX, y: 0)
            frameLayer.bounds = toBounds
            frameLayer.position = toPosition
            picture.bounds = toPictureBounds
            picture.position = pictureRect.origin
            if let maskPath {
                maskLayer.frame = toBounds
                maskLayer.path = maskPath
                frameLayer.mask = maskLayer
                frameLayer.cornerRadius = 0
            } else {
                frameLayer.mask = nil
                frameLayer.cornerRadius = NoteMediaStyle.imageRadius
            }
        }
        guard animated else { return }
        func spring(_ layer: CALayer, _ keyPath: String, _ from: Any, _ to: Any) {
            layer.add(NoteAnimation.spring(keyPath, .settle, from: from, to: to), forKey: "media.frame." + keyPath)
        }
        if fromBounds != toBounds { spring(frameLayer, "bounds", NSValue(rect: fromBounds), NSValue(rect: toBounds)) }
        if fromPosition != toPosition { spring(frameLayer, "position", NSValue(point: fromPosition), NSValue(point: toPosition)) }
        if fromPictureBounds != toPictureBounds { spring(picture, "bounds", NSValue(rect: fromPictureBounds), NSValue(rect: toPictureBounds)) }
        if fromPicturePosition != pictureRect.origin {
            spring(picture, "position", NSValue(point: fromPicturePosition), NSValue(point: pictureRect.origin))
        }
        if let fromPath, let maskPath { spring(maskLayer, "path", fromPath, maskPath) }
    }

    private func requestIfNeeded() {
        guard let url = source.url, bounds.width > 0 else { return }
        let full = shownCrop.fullRect(forFrame: imageRect)
        let scale = window?.backingScaleFactor ?? 2
        let pixels = NoteMediaImageLoader.pixels(for: full.size, scale: scale)
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
        cropEditor?.imageDidLoad()
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
            for layer in [frameLayer, picture, maskLayer] as [CALayer] { layer.removeAllAnimations() }
            NoteMediaMotion.instant { frameLayer.transform = CATransform3DIdentity; picture.opacity = image == nil ? 0 : 1 }
            toolbar.layer?.removeAllAnimations()
        }
        refreshAnimation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            dismissMenu()
            morePopover?.close(animated: false)
            framingPopover?.close(animated: false)
            if cropEditor != nil { finishCrop(save: false) }
        }
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
        NoteMediaMotion.instant { ring.isHidden = !selected || cropEditor != nil }
    }

    override func readOnlyDidChange() {
        if !editable, cropEditor != nil { finishCrop(save: false) }
        if !editable { framingPopover?.close(animated: false) }
        configureToolbar()
        refreshBadge()
        setHovered(hovered)
    }

    private func configureToolbar() {
        let column = bounds.width > 0 ? bounds.width : 10_000
        let fullWidth = displayWidth(for: column) >= column - 1
        alignChip.content = .icon(.symbol(Self.alignmentSymbol(props.alignment)))
        var chips: [NoteControlButton] = []
        if editable {
            if !fullWidth { chips.append(alignChip) }
            if host?.offersCaption == true { chips.append(captionChip) }
            chips.append(replaceChip)
        }
        chips.append(downloadChip)
        chips.append(openChip)
        chips.append(moreChip)
        toolbar.setButtons(chips)
        needsLayout = true
    }

    private func refreshBadge() {
        altBadge.text = altText
        altBadge.isEditable = editable
        setHovered(hovered)
    }

    static func alignmentSymbol(_ alignment: NoteAlignment) -> String {
        switch alignment {
        case .left: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        }
    }

    private var menusOpen: Bool {
        alignmentMenu != nil || morePopover?.isOpen == true || framingPopover?.isOpen == true
    }

    override func setHovered(_ hovered: Bool) {
        self.hovered = hovered
        let visible = (hovered || resizeStart != nil || menusOpen) && image != nil && cropEditor == nil
        if visible {
            configureToolbar()
            layoutSubtreeIfNeeded()
            toolbar.show()
        } else {
            toolbar.hide()
        }
        let showsHandles = visible && editable && imageRect.height >= 36
        for handle in [leadingHandle, trailingHandle] { handle.setRevealed(showsHandles) }
        let fitsBadge = imageRect.width >= 64 && imageRect.height >= 40
        altBadge.setRevealed(visible && !altText.isEmpty && fitsBadge)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard cropEditor == nil, imageRect.contains(point) else { super.mouseDown(with: event); return }
        if event.clickCount >= 2, image != nil {
            _ = presentZoom()
            return
        }
        if host?.selectBlock(with: event) == true { return }
        super.mouseDown(with: event)
    }

    private func imageCursor(for event: NSEvent) -> NSCursor? {
        guard image != nil, cropEditor == nil, imageRect.contains(convert(event.locationInWindow, from: nil)) else { return nil }
        return .pointingHand
    }

    override func cursorUpdate(with event: NSEvent) {
        if !imageZone.cursorUpdate(imageCursor(for: event), in: self, event: event) { super.cursorUpdate(with: event) }
    }

    override func mouseMoved(with event: NSEvent) {
        imageZone.moved(imageCursor(for: event), in: self, event: event)
    }

    override func mouseExited(with event: NSEvent) { imageZone.exited() }

    func presentZoom() -> Bool {
        guard let image, let host, cropEditor == nil else { return false }
        host.zoom(image: image, from: imageRect, in: self, crop: props.crop, mask: props.mask)
        return true
    }

    func beginResize() {
        guard editable, cropEditor == nil else { return }
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
        let settled = NoteMediaLayout.displayWidth(fraction: fraction, natural: framedNatural, columnWidth: start.column)
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
        NoteMediaMotion.instant { frameLayer.transform = CATransform3DIdentity }
        frameLayer.add(NoteAnimation.spring("transform", .settle, from: NSValue(caTransform3D: from), to: NSValue(caTransform3D: CATransform3DIdentity)),
                       forKey: "media.settle")
    }

    private var overlay: NSView? { host?.mediaOverlay }

    private func toggleMoreMenu() {
        if morePopover?.isOpen == true { morePopover?.close(); return }
        guard let overlay else { return }
        dismissMenu()
        framingPopover?.close(animated: false)
        let editable = self.editable
        var items: [NoteMenuList.Item] = []
        if editable {
            items.append(NoteMenuList.Item(id: "crop", title: "Crop Image", icon: .symbol("crop"), isEnabled: image != nil && natural != nil))
            items.append(NoteMenuList.Item(id: "mask", title: "Mask", subtitle: props.mask?.title ?? NoteImageMask.noneTitle,
                                           icon: .symbol("square.on.circle"), hasSubmenu: true))
            items.append(NoteMenuList.Item(id: "alt", title: "Alt Text", subtitle: altText.isEmpty ? nil : altText, icon: .symbol("text.bubble")))
        }
        items.append(NoteMenuList.Item(id: "fullScreen", title: "Full Screen", icon: .symbol("arrow.up.left.and.arrow.down.right"),
                                       shortcut: "⌘↩", isEnabled: image != nil, separatorBefore: editable))
        if source.url != nil {
            items.append(NoteMenuList.Item(id: "original", title: "View Original", icon: .symbol("arrow.up.forward.square")))
        }
        if editable {
            items.append(NoteMenuList.Item(id: "delete", title: "Delete", icon: .symbol("trash"), isDestructive: true, separatorBefore: true))
        }
        let list = NoteMenuList(items: items)
        list.minimumWidth = 200
        let popover = NotePagePopover(content: list)
        popover.exempt(moreChip)
        list.onActivate = { [weak self, weak popover, weak list] item in
            guard let self else { return }
            if item.id == "mask" {
                guard let popover, let list, let row = list.rowFrame(forItemID: "mask") else { return }
                self.presentMaskPicker(anchor: overlay.convert(row, from: list), edge: .trailing, parent: popover,
                                       current: self.props.mask) { [weak self] mask in self?.applyMask(mask) }
                return
            }
            popover?.close(animated: false)
            self.performMoreItem(item.id)
        }
        list.onCancel = { [weak popover] in popover?.close() }
        popover.onKeyDown = { [weak list] event in list?.handleKeyDown(event) ?? false }
        popover.onClose = { [weak self, weak popover] in
            guard let self, self.morePopover === popover else { return }
            self.morePopover = nil
            self.setHovered(self.hovered)
        }
        morePopover = popover
        popover.present(in: overlay, anchor: overlay.convert(moreChip.bounds, from: moreChip), edge: .below, alignment: .trailing)
        if NSApp.currentEvent?.type == .keyDown { list.prepare(origin: .keyboard); _ = list.moveHighlight(by: 1) }
    }

    private func performMoreItem(_ id: String) {
        switch id {
        case "crop": beginCrop()
        case "alt": editAltText()
        case "fullScreen": _ = presentZoom()
        case "original": if let url = source.url { host?.open(url) }
        case "delete": host?.deleteBlock()
        default: break
        }
    }

    func applyMask(_ mask: NoteImageMask?) {
        guard editable, let host else { return }
        let next = NoteImageFraming.applying(mask, to: props, natural: natural)
        host.commitFraming(crop: next.crop, mask: next.mask, name: mask == nil ? "Remove Mask" : "Mask Image")
    }

    @discardableResult
    func presentMaskPicker(anchor: NSRect, edge: NoteFloatingPanel.Edge, parent: NotePagePopover?, current: NoteImageMask?,
                           onPick: @escaping (NoteImageMask?) -> Void) -> NotePagePopover? {
        guard let overlay else { return nil }
        let thumbnailCrop = cropEditor?.draftCrop ?? props.crop ?? .full
        let picker = NoteImageMaskPicker(image: image?.first, crop: thumbnailCrop, current: current)
        let popover = NotePagePopover(content: picker, parent: parent)
        picker.onPick = { [weak popover] mask in
            popover?.close()
            parent?.close()
            onPick(mask)
        }
        popover.onKeyDown = { [weak picker] event in picker?.handleKeyDown(event) ?? false }
        popover.onClose = { [weak self, weak popover] in
            guard let self, self.framingPopover === popover else { return }
            self.framingPopover = nil
            self.setHovered(self.hovered)
        }
        framingPopover = popover
        popover.present(in: overlay, anchor: anchor, edge: edge, alignment: .leading)
        return popover
    }

    func showMaskPicker() {
        guard editable, overlay != nil else { return }
        layoutSubtreeIfNeeded()
        let anchor = overlayRect(of: NSRect(x: imageRect.minX, y: imageRect.minY + 8, width: imageRect.width, height: NoteMediaToolbar.height))
        presentMaskPicker(anchor: anchor, edge: .below, parent: nil, current: props.mask) { [weak self] mask in self?.applyMask(mask) }
    }

    private func overlayRect(of rect: NSRect) -> NSRect {
        guard let overlay else { return rect }
        return overlay.convert(rect, from: self)
    }

    func editAltText() {
        guard editable, let overlay else { return }
        morePopover?.close(animated: false)
        framingPopover?.close(animated: false)
        layoutSubtreeIfNeeded()
        let editor = NoteMediaAltTextEditor(text: props.alt ?? "")
        let popover = NotePagePopover(content: editor)
        editor.onCommit = { [weak self, weak popover] text in
            popover?.close()
            self?.host?.setAltText(text)
        }
        popover.onKeyDown = { [weak editor, weak popover] event in
            guard event.keyCode == 53 else { return false }
            editor?.cancel()
            popover?.close()
            return true
        }
        popover.onClose = { [weak self, weak popover, weak editor] in
            editor?.commitIfPending()
            guard let self, self.framingPopover === popover else { return }
            self.framingPopover = nil
            self.setHovered(self.hovered)
        }
        framingPopover = popover
        let anchorRect = toolbar.isShown ? toolbar.frame : NSRect(x: imageRect.maxX - 1, y: imageRect.minY + 8, width: 1, height: NoteMediaToolbar.height)
        popover.present(in: overlay, anchor: overlayRect(of: anchorRect), edge: .below, alignment: .trailing)
        editor.focus()
    }

    func beginCrop() {
        guard editable, cropEditor == nil, image != nil, let natural, let host else { return }
        dismissMenu()
        morePopover?.close(animated: false)
        framingPopover?.close(animated: false)
        toolbar.hideImmediately()
        for handle in [leadingHandle, trailingHandle] { handle.setRevealed(false) }
        altBadge.setRevealed(false)
        let editor = NoteImageCropEditor(owner: self, crop: props.crop ?? .full, mask: props.mask, natural: natural)
        responderBeforeCrop = window?.firstResponder
        cropEditor = editor
        addSubview(editor, positioned: .above, relativeTo: shimmer)
        NoteMediaMotion.instant { ring.isHidden = true }
        animatesNextLayout = window != nil
        host.invalidateMeasuredHeight()
        needsLayout = true
        host.mediaCanvas?.layoutSubtreeIfNeeded()
        layoutSubtreeIfNeeded()
        editor.appear()
        window?.makeFirstResponder(editor)
        refreshCursorIfPointerOwned()
        installClickAwayMonitor()
    }

    func finishCrop(save: Bool) {
        guard let editor = cropEditor else { return }
        let result = editor.result
        removeClickAwayMonitor()
        let ownedFocus = window?.firstResponder === editor
        cropEditor = nil
        animatesNextLayout = window != nil
        editor.disappear()
        if save { host?.commitFraming(crop: result.crop, mask: result.mask, name: "Crop Image") }
        host?.invalidateMeasuredHeight()
        needsLayout = true
        if ownedFocus, let window {
            if let responder = responderBeforeCrop, (responder as? NSView)?.window === window { window.makeFirstResponder(responder) }
            else if let host { window.makeFirstResponder(host) }
        }
        responderBeforeCrop = nil
        refreshCursorIfPointerOwned()
        setSelected(host?.isBlockSelected == true)
        setHovered(hovered)
    }

    private func installClickAwayMonitor() {
        removeClickAwayMonitor()
        clickAwayMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let location = event.locationInWindow, windowNumber = event.windowNumber
            MainActor.assumeIsolated { self?.clickAway(at: location, windowNumber: windowNumber) }
            return event
        }
    }

    private func removeClickAwayMonitor() {
        if let clickAwayMonitor { NSEvent.removeMonitor(clickAwayMonitor) }
        clickAwayMonitor = nil
    }

    private func clickAway(at location: NSPoint, windowNumber: Int) {
        guard cropEditor != nil, let window, windowNumber == window.windowNumber else { return }
        if bounds.contains(convert(location, from: nil)) { return }
        if let topmost = NotePagePopover.topmost, topmost.contains(windowPoint: location, in: window) { return }
        finishCrop(save: true)
    }

    private func toggleAlignmentMenu() {
        if alignmentMenu != nil { dismissMenu(); return }
        guard let overlay = host?.mediaOverlay else { return }
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
        panel.onDismiss = { [weak self, weak panel] in self?.menuDidClose(panel) }
        let anchor = overlay.convert(alignChip.bounds, from: alignChip)
        panel.present(in: overlay, anchor: anchor, edge: .below)
        alignmentMenu = panel
        removeMenuMonitor()
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
        removeMenuMonitor()
        panel.dismiss(animated: true)
    }

    private func menuDidClose(_ panel: NoteFloatingPanel?) {
        guard alignmentMenu == nil || alignmentMenu === panel else { return }
        alignmentMenu = nil
        removeMenuMonitor()
        setHovered(hovered)
    }

    private func removeMenuMonitor() {
        if let menuMonitor { NSEvent.removeMonitor(menuMonitor) }
        menuMonitor = nil
    }
}

@MainActor
final class NoteMediaResizeHandle: NSView, ResizeHandleView {
    let edge: NoteMediaEdge
    weak var owner: NoteMediaResizing?
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
        addCursorUpdateArea()
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
        refreshCursorIfPointerOwned()
    }

    override func cursorUpdate(with event: NSEvent) {
        if revealed, applyNoteCursor(.resizeLeftRight, for: event) { return }
        super.cursorUpdate(with: event)
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
