import AppKit

@MainActor
final class NoteImageCropEditor: NSView {
    static let barGap: CGFloat = 10
    static let barHeight: CGFloat = NoteMediaToolbar.height
    static let minimumSide: CGFloat = 32
    static let handleReach: CGFloat = 12

    private enum Drag {
        case move(start: CGRect, origin: NSPoint)
        case resize(NoteImageCropHandle, start: CGRect, origin: NSPoint)
    }

    weak var owner: NoteImageContentView?
    let natural: CGSize
    private(set) var draftCrop: NoteImageCrop
    private(set) var mask: NoteImageMask?
    private var aspect: NoteImageCropAspect
    private var drag: Drag?
    private var popover: NotePagePopover?
    private var dismissing = false
    var imageRect: NSRect = .zero { didSet { if oldValue != imageRect { needsLayout = true } } }

    private let dim = CAShapeLayer()
    private let outline = CAShapeLayer()
    private let shapeOutline = CAShapeLayer()
    private let grid = CAShapeLayer()
    private let handles = CAShapeLayer()
    private let leftCard = NoteMediaToolbar()
    private let rightCard = NoteMediaToolbar()
    private let shapeButton = NoteToolbarButton(icon: .symbol("square.on.circle"), label: "Shape")
    private let ratioButton = NoteToolbarButton(.iconAndText(.symbol("aspectratio"), "Freeform"), label: "Aspect ratio")
    private let resetChip = NoteChip("Reset", icon: .symbol("arrow.counterclockwise"))
    private let cancelChip = NoteChip("Cancel")
    private let saveChip = NoteChip("Save", icon: .symbol("checkmark"), style: .filled)
    private let resetIcon = NoteToolbarButton(icon: .symbol("arrow.counterclockwise"), label: "Reset")
    private let cancelIcon = NoteToolbarButton(icon: .symbol("xmark"), label: "Cancel", shortcut: "ESC")
    private let saveIcon = NoteToolbarButton(icon: .symbol("checkmark"), label: "Save", shortcut: "↩")

    init(owner: NoteImageContentView, crop: NoteImageCrop, mask: NoteImageMask?, natural: CGSize) {
        self.owner = owner
        self.natural = natural
        draftCrop = crop
        self.mask = mask
        aspect = mask?.isSquare == true ? .square : .free
        super.init(frame: .zero)
        wantsLayer = true
        alphaValue = 0
        dim.fillRule = .evenOdd
        dim.fillColor = NSColor.black.withAlphaComponent(0.5).cgColor
        outline.fillColor = nil
        outline.lineWidth = 1
        shapeOutline.fillColor = nil
        shapeOutline.lineWidth = 1.5
        shapeOutline.lineDashPattern = [5, 4]
        grid.fillColor = nil
        grid.lineWidth = 0.5
        grid.opacity = 0
        handles.fillColor = nil
        handles.lineWidth = 3
        handles.lineCap = .round
        handles.lineJoin = .round
        handles.shadowColor = NSColor.black.cgColor
        handles.shadowOpacity = 0.35
        handles.shadowRadius = 2
        handles.shadowOffset = .zero
        for shape in [dim, grid, outline, shapeOutline, handles] {
            shape.strokeColor = NSColor.white.cgColor
            layer?.addSublayer(shape)
        }
        outline.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        grid.strokeColor = NSColor.white.withAlphaComponent(0.55).cgColor
        shapeButton.showsDisclosure = true
        ratioButton.showsDisclosure = true
        shapeButton.onPress = { [weak self] in self?.toggleShapes() }
        ratioButton.onPress = { [weak self] in self?.toggleRatios() }
        resetChip.setToolTip("Show the whole picture")
        cancelChip.setToolTip("Cancel", shortcut: "ESC")
        saveChip.setToolTip("Save", shortcut: "↩")
        for reset in [resetChip, resetIcon] as [NoteControlButton] { reset.onPress = { [weak self] in self?.reset() } }
        for cancel in [cancelChip, cancelIcon] as [NoteControlButton] { cancel.onPress = { [weak self] in self?.owner?.finishCrop(save: false) } }
        for save in [saveChip, saveIcon] as [NoteControlButton] { save.onPress = { [weak self] in self?.owner?.finishCrop(save: true) } }
        leftCard.anchor = CGPoint(x: 0, y: 0)
        rightCard.anchor = CGPoint(x: 1, y: 0)
        leftCard.setButtons([shapeButton, ratioButton])
        addSubview(leftCard)
        addSubview(rightCard)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Crop image")
        setAccessibilityHelp("Drag the frame or its handles. Arrow keys nudge it, Return saves and Escape cancels.")
        setAccessibilityCustomActions(accessibilityActions())
        refreshControls()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var result: (crop: NoteImageCrop?, mask: NoteImageMask?) {
        let crop = draftCrop.normalized
        return (crop.isFull ? nil : crop, mask)
    }

    var cropRect: CGRect { draftCrop.rect(in: imageRect) }

    private var ratio: CGFloat? { aspect.ratio(natural: natural) }

    func appear() {
        layoutSubtreeIfNeeded()
        NoteAnimation.fade(self, visible: true, duration: 0.18)
        leftCard.show()
        rightCard.show()
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    func disappear() {
        dismissing = true
        popover?.close(animated: false)
        leftCard.hide()
        rightCard.hide()
        NoteAnimation.fade(self, visible: false, duration: 0.12) { [weak self] in self?.removeFromSuperview() }
    }

    func imageDidLoad() { needsLayout = true }

    override func layout() {
        super.layout()
        refreshShapes(animated: false)
        layoutBar()
    }

    private func layoutBar() {
        let y = imageRect.maxY + Self.barGap
        let compact = leftCard.fittingWidth + chipWidth(full: true) + 8 > bounds.width
        rightCard.setButtons(compact ? [resetIcon, cancelIcon, saveIcon] : [resetChip, cancelChip, saveChip])
        let leftWidth = leftCard.fittingWidth, rightWidth = rightCard.fittingWidth
        let leftX = max(0, min(imageRect.minX, bounds.width - leftWidth - rightWidth - 8))
        let rightX = min(bounds.width - rightWidth, max(leftX + leftWidth + 8, imageRect.maxX - rightWidth))
        leftCard.frame = NSRect(x: leftX, y: y, width: leftWidth, height: Self.barHeight)
        rightCard.frame = NSRect(x: max(leftX + leftWidth + 8, rightX), y: y, width: rightWidth, height: Self.barHeight)
    }

    private func chipWidth(full: Bool) -> CGFloat {
        let buttons: [NoteControlButton] = full ? [resetChip, cancelChip, saveChip] : [resetIcon, cancelIcon, saveIcon]
        return buttons.reduce(0) { $0 + $1.intrinsicContentSize.width } + CGFloat(buttons.count - 1) * NoteMediaToolbar.spacing
            + NoteMediaToolbar.padding * 2
    }

    private func refreshShapes(animated: Bool) {
        let rect = cropRect
        let dimPath = CGMutablePath()
        dimPath.addRect(imageRect)
        dimPath.addPath(mask?.path(in: rect) ?? CGPath(rect: rect, transform: nil))
        let outlinePath = CGPath(rect: rect.insetBy(dx: 0.5, dy: 0.5), transform: nil)
        let shapePath = mask?.path(in: rect) ?? CGMutablePath()
        let gridPath = CGMutablePath()
        for step in 1...2 {
            let x = rect.minX + rect.width * CGFloat(step) / 3, y = rect.minY + rect.height * CGFloat(step) / 3
            gridPath.move(to: CGPoint(x: x, y: rect.minY))
            gridPath.addLine(to: CGPoint(x: x, y: rect.maxY))
            gridPath.move(to: CGPoint(x: rect.minX, y: y))
            gridPath.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        let handlePath = Self.handlePath(for: rect)
        let paths: [(CAShapeLayer, CGPath)] = [(dim, dimPath), (outline, outlinePath), (shapeOutline, shapePath), (grid, gridPath), (handles, handlePath)]
        for (layer, path) in paths {
            if animated, layer.path != nil, layer !== shapeOutline || mask != nil {
                NoteAnimation.spring(layer, "path", to: path, spring: .glide)
            } else {
                NoteAnimation.withoutAnimation { layer.path = path }
            }
        }
        NoteAnimation.withoutAnimation {
            for layer in [dim, outline, shapeOutline, grid, handles] { layer.frame = bounds }
            outline.opacity = mask == nil ? 1 : 0.45
            shapeOutline.isHidden = mask == nil
        }
        window?.invalidateCursorRects(for: self)
    }

    private static func handlePath(for rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let arm = min(16, rect.width / 3, rect.height / 3)
        let corners: [(CGPoint, CGFloat, CGFloat)] = [(CGPoint(x: rect.minX, y: rect.minY), 1, 1), (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
                                                      (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1), (CGPoint(x: rect.minX, y: rect.maxY), 1, -1)]
        for (corner, dx, dy) in corners {
            path.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        }
        let bar = min(18, rect.width / 4, rect.height / 4)
        if rect.width > 3 * arm + bar {
            for y in [rect.minY, rect.maxY] {
                path.move(to: CGPoint(x: rect.midX - bar / 2, y: y))
                path.addLine(to: CGPoint(x: rect.midX + bar / 2, y: y))
            }
        }
        if rect.height > 3 * arm + bar {
            for x in [rect.minX, rect.maxX] {
                path.move(to: CGPoint(x: x, y: rect.midY - bar / 2))
                path.addLine(to: CGPoint(x: x, y: rect.midY + bar / 2))
            }
        }
        return path
    }

    private static func point(of handle: NoteImageCropHandle, in rect: CGRect) -> CGPoint {
        let x = handle.movesLeft ? rect.minX : handle.movesRight ? rect.maxX : rect.midX
        let y = handle.movesTop ? rect.minY : handle.movesBottom ? rect.maxY : rect.midY
        return CGPoint(x: x, y: y)
    }

    private func hitRect(of handle: NoteImageCropHandle, in rect: CGRect) -> CGRect {
        let center = Self.point(of: handle, in: rect)
        let reach = Self.handleReach
        if handle.isCorner { return CGRect(x: center.x - reach, y: center.y - reach, width: reach * 2, height: reach * 2) }
        if handle.movesLeft || handle.movesRight {
            return CGRect(x: center.x - reach, y: rect.minY + reach, width: reach * 2, height: max(0, rect.height - reach * 2))
        }
        return CGRect(x: rect.minX + reach, y: center.y - reach, width: max(0, rect.width - reach * 2), height: reach * 2)
    }

    private func handle(at point: NSPoint) -> NoteImageCropHandle? {
        let rect = cropRect
        for handle in NoteImageCropHandle.allCases where handle.isCorner && hitRect(of: handle, in: rect).contains(point) { return handle }
        for handle in NoteImageCropHandle.allCases where !handle.isCorner && hitRect(of: handle, in: rect).contains(point) { return handle }
        return nil
    }

    private static func cursor(for handle: NoteImageCropHandle) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch handle {
            case .topLeft: position = .topLeft
            case .top: position = .top
            case .topRight: position = .topRight
            case .right: position = .right
            case .bottomRight: position = .bottomRight
            case .bottom: position = .bottom
            case .bottomLeft: position = .bottomLeft
            case .left: position = .left
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        if handle.isCorner { return .crosshair }
        return handle.movesTop || handle.movesBottom ? .resizeUpDown : .resizeLeftRight
    }

    override func resetCursorRects() {
        guard !dismissing else { return }
        let rect = cropRect
        addCursorRect(rect.insetBy(dx: Self.handleReach, dy: Self.handleReach), cursor: drag == nil ? .openHand : .closedHand)
        for handle in NoteImageCropHandle.allCases.reversed() {
            addCursorRect(hitRect(of: handle, in: rect), cursor: Self.cursor(for: handle))
        }
        for card in [leftCard, rightCard] { addCursorRect(card.frame, cursor: .arrow) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !dismissing else { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)
        let rect = cropRect
        if let handle = handle(at: point) {
            drag = .resize(handle, start: rect, origin: point)
            Self.cursor(for: handle).push()
        } else if rect.contains(point) {
            drag = .move(start: rect, origin: point)
            NSCursor.closedHand.push()
        } else {
            return
        }
        NoteAnimation.fade(grid, to: 1, duration: 0.12)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let point = convert(event.locationInWindow, from: nil)
        switch drag {
        case .move(let start, let origin):
            let moved = NoteImageCropGeometry.move(start, by: CGSize(width: point.x - origin.x, height: point.y - origin.y), within: imageRect)
            setDraft(moved)
        case .resize(let handle, let start, let origin):
            let lock = ratio ?? (event.modifierFlags.contains(.shift) && start.height > 0 ? start.width / start.height : nil)
            let resized = NoteImageCropGeometry.resize(start, handle: handle, by: CGSize(width: point.x - origin.x, height: point.y - origin.y),
                                                       within: imageRect, minimum: Self.minimumSide, aspect: lock)
            setDraft(resized)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard drag != nil else { return }
        NSCursor.pop()
        drag = nil
        NoteAnimation.fade(grid, to: 0, duration: 0.2)
        refreshControls()
        window?.invalidateCursorRects(for: self)
    }

    private func setDraft(_ rect: CGRect, animated: Bool = false) {
        draftCrop = NoteImageCrop(rect, in: imageRect)
        refreshShapes(animated: animated)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 36 where modifiers.isEmpty, 76 where modifiers.isEmpty: owner?.finishCrop(save: true)
        case 53: owner?.finishCrop(save: false)
        case 123 where modifiers.isEmpty: nudge(dx: -step, dy: 0)
        case 124 where modifiers.isEmpty: nudge(dx: step, dy: 0)
        case 125 where modifiers.isEmpty: nudge(dx: 0, dy: step)
        case 126 where modifiers.isEmpty: nudge(dx: 0, dy: -step)
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { owner?.finishCrop(save: false) }

    private func nudge(dx: CGFloat, dy: CGFloat) {
        setDraft(NoteImageCropGeometry.move(cropRect, by: CGSize(width: dx, height: dy), within: imageRect))
        refreshControls()
    }

    private func scale(by factor: CGFloat) {
        let rect = cropRect
        let width = rect.width * factor, height = rect.height * factor
        let grown = CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
        let resized = NoteImageCropGeometry.resize(grown, handle: .bottomRight, by: .zero, within: imageRect, minimum: Self.minimumSide,
                                                   aspect: ratio ?? (rect.height > 0 ? rect.width / rect.height : nil))
        setDraft(NoteImageCropGeometry.move(resized, by: .zero, within: imageRect), animated: true)
        refreshControls()
    }

    private func reset() {
        let whole = imageRect
        if let ratio {
            setDraft(NoteImageCropGeometry.fitted(aspect: ratio, around: whole, within: whole), animated: true)
        } else {
            setDraft(whole, animated: true)
        }
        refreshControls()
    }

    func setMask(_ next: NoteImageMask?) {
        let previous = mask
        mask = next
        if next?.isSquare == true {
            aspect = .square
            setDraft(NoteImageCropGeometry.fitted(aspect: 1, around: cropRect, within: imageRect), animated: previous == next)
        } else {
            if previous?.isSquare == true, aspect == .square { aspect = .free }
            refreshShapes(animated: false)
        }
        refreshControls()
    }

    private func setAspect(_ next: NoteImageCropAspect) {
        aspect = next
        if let ratio { setDraft(NoteImageCropGeometry.fitted(aspect: ratio, around: cropRect, within: imageRect), animated: true) }
        refreshControls()
    }

    private func refreshControls() {
        ratioButton.content = .iconAndText(.symbol("aspectratio"), aspect.title)
        let whole = draftCrop.normalized.isFull
        resetChip.isEnabled = !whole
        resetIcon.isEnabled = !whole
        shapeButton.setAccessibilityValue(mask?.title ?? NoteImageMask.noneTitle)
        ratioButton.setAccessibilityValue(aspect.title)
        needsLayout = true
    }

    private func anchorRect(of view: NSView) -> NSRect? {
        guard let overlay = owner?.host?.editor?.canvas.overlayView else { return nil }
        return overlay.convert(view.bounds, from: view)
    }

    private func toggleShapes() {
        if popover?.isOpen == true { popover?.close(); return }
        guard let owner, let anchor = anchorRect(of: shapeButton) else { return }
        popover = owner.presentMaskPicker(anchor: anchor, edge: .below, parent: nil, current: mask) { [weak self] mask in
            self?.setMask(mask)
        }
        popover?.exempt(shapeButton)
    }

    private func toggleRatios() {
        if popover?.isOpen == true { popover?.close(); return }
        guard let overlay = owner?.host?.editor?.canvas.overlayView, let anchor = anchorRect(of: ratioButton) else { return }
        let locked = mask?.isSquare == true
        let list = NoteMenuList(items: NoteImageCropAspect.allCases.map { option in
            NoteMenuList.Item(id: option.id, title: option.title, isChecked: option == aspect,
                              isEnabled: !locked || option == .square)
        })
        list.minimumWidth = 160
        let menu = NotePagePopover(content: list)
        menu.exempt(ratioButton)
        list.onActivate = { [weak self, weak menu] item in
            menu?.close()
            guard let self, let option = NoteImageCropAspect.allCases.first(where: { $0.id == item.id }) else { return }
            self.setAspect(option)
        }
        list.onCancel = { [weak menu] in menu?.close() }
        menu.onKeyDown = { [weak list] event in list?.handleKeyDown(event) ?? false }
        popover = menu
        menu.present(in: overlay, anchor: anchor, edge: .below, alignment: .leading)
        if NSApp.currentEvent?.type == .keyDown { list.prepare(origin: .keyboard); _ = list.moveHighlight(by: 1) }
    }

    private func accessibilityActions() -> [NSAccessibilityCustomAction] {
        let actions: [(String, (NoteImageCropEditor) -> Void)] = [
            ("Move crop left", { $0.nudge(dx: -10, dy: 0) }), ("Move crop right", { $0.nudge(dx: 10, dy: 0) }),
            ("Move crop up", { $0.nudge(dx: 0, dy: -10) }), ("Move crop down", { $0.nudge(dx: 0, dy: 10) }),
            ("Grow crop", { $0.scale(by: 1.1) }), ("Shrink crop", { $0.scale(by: 1 / 1.1) }),
            ("Reset crop", { $0.reset() }), ("Save crop", { $0.owner?.finishCrop(save: true) }),
        ]
        return actions.map { name, perform in
            NSAccessibilityCustomAction(name: name) { [weak self] in
                guard let self else { return false }
                perform(self)
                return true
            }
        }
    }

    override func accessibilityPerformCancel() -> Bool {
        owner?.finishCrop(save: false)
        return true
    }
}
