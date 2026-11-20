import AppKit
import Combine

@MainActor
final class NoteHandleButton: NSView {
    enum Role { case add, grip }

    static let idleOpacity: Float = 0.33
    static let pressedScale: CGFloat = 0.95

    let role: Role
    var onPress: ((NSEvent) -> Void)?
    var onActivate: ((NSEvent.ModifierFlags) -> Void)?
    var isPinned = false { didSet { if oldValue != isPinned { refresh() } } }
    private let face = CALayer()
    private let plate = CALayer()
    private let glyph = CAShapeLayer()
    private var trackingArea: NSTrackingArea?
    private(set) var isHovered = false
    private(set) var isPressed = false

    init(role: Role) {
        self.role = role
        super.init(frame: NSRect(origin: .zero, size: NoteHandleGeometry.buttonSize))
        wantsLayer = true
        layer?.masksToBounds = false
        face.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        plate.cornerRadius = 4
        plate.cornerCurve = .continuous
        plate.opacity = 0
        face.addSublayer(plate)
        face.addSublayer(glyph)
        layer?.addSublayer(face)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        switch role {
        case .add:
            setAccessibilityLabel("Add Block")
            parcTooltip = TooltipConfiguration(NoteBlockHandleController.addTooltip)
            setAccessibilityHelp(NoteBlockHandleController.addTooltip)
        case .grip:
            setAccessibilityLabel("Block Options")
            parcTooltip = TooltipConfiguration(NoteBlockHandleController.gripTooltip)
            setAccessibilityHelp(NoteBlockHandleController.gripTooltip)
        }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        face.bounds = bounds
        face.position = CGPoint(x: bounds.midX, y: bounds.midY)
        plate.frame = bounds
        glyph.frame = bounds
        glyph.path = Self.glyphPath(role, in: bounds)
        CATransaction.commit()
    }

    static func glyphPath(_ role: Role, in bounds: CGRect) -> CGPath {
        let path = CGMutablePath()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        switch role {
        case .add:
            let arm: CGFloat = 5.5, thickness: CGFloat = 1.6
            path.addRoundedRect(in: CGRect(x: center.x - arm, y: center.y - thickness / 2, width: arm * 2, height: thickness),
                                cornerWidth: thickness / 2, cornerHeight: thickness / 2)
            path.addRoundedRect(in: CGRect(x: center.x - thickness / 2, y: center.y - arm, width: thickness, height: arm * 2),
                                cornerWidth: thickness / 2, cornerHeight: thickness / 2)
        case .grip:
            let dot: CGFloat = 2.6, columnGap: CGFloat = 5, rowGap: CGFloat = 5
            for column in 0..<2 {
                for row in 0..<3 {
                    let x = center.x + (CGFloat(column) - 0.5) * columnGap - dot / 2
                    let y = center.y + CGFloat(row - 1) * rowGap - dot / 2
                    path.addEllipse(in: CGRect(x: x, y: y, width: dot, height: dot))
                }
            }
        }
        return path
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }

    override func mouseExited(with event: NSEvent) { setHovered(false) }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        setPressed(true)
        if let onPress {
            onPress(event)
            setPressed(false)
            return
        }
        var inside = true
        window?.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking) { tracked, stop in
            guard let tracked else { stop.pointee = true; return }
            inside = bounds.contains(convert(tracked.locationInWindow, from: nil))
            setPressed(inside)
            if tracked.type == .leftMouseUp { stop.pointee = true }
        }
        setPressed(false)
        if inside { onActivate?(event.modifierFlags) }
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?([])
        return true
    }

    func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        refresh()
    }

    func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        refresh()
        let scale = pressed && !NoteAnimation.reduceMotion ? Self.pressedScale : 1
        NoteAnimation.animate(face, "transform.scale", to: scale, spring: .press, key: "note.handle.press")
    }

    var isLit: Bool { isHovered || isPressed || isPinned }

    private func refresh() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            glyph.fillColor = NoteTheme.secondaryInk.cgColor
            plate.backgroundColor = (isPressed ? NoteTheme.pressedFill : NoteTheme.hoverFill).cgColor
        }
        glyph.opacity = isLit ? 1 : Self.idleOpacity
        plate.opacity = isLit ? 1 : 0
        CATransaction.commit()
    }
}

@MainActor
final class NoteHandleBar: NSView {
    let plus = NoteHandleButton(role: .add)
    let grip = NoteHandleButton(role: .grip)
    private(set) var isShown = false
    private var generation = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.opacity = 0
        isHidden = true
        addSubview(plus)
        addSubview(grip)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func place(_ rects: NoteHandleRects) {
        let union = rects.union
        frame = union
        plus.frame = rects.plus.offsetBy(dx: -union.minX, dy: -union.minY)
        grip.frame = rects.grip.offsetBy(dx: -union.minX, dy: -union.minY)
    }

    func setShown(_ shown: Bool, animated: Bool = true) {
        guard shown != isShown else { return }
        isShown = shown
        generation += 1
        let token = generation
        if shown { isHidden = false }
        if !shown {
            plus.setHovered(false)
            grip.setHovered(false)
        }
        NoteAnimation.fade(self, visible: shown, duration: animated ? 0.1 : 0) { [weak self] in
            guard let self, self.generation == token, !self.isShown else { return }
            self.isHidden = true
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isShown ? super.hitTest(point) : nil
    }
}

@MainActor
final class NoteBlockHandleController {
    static let addTooltip = "Click to add below, ⌥-click to add above"
    static let gripTooltip = "Drag to move, click for options"

    unowned let editor: NotePageEditor
    let bar = NoteHandleBar()
    private(set) var hoveredBlock: NoteBlockID?
    private(set) var pinnedBlock: NoteBlockID?
    private var hiddenForTyping = false
    private var typingMouseLocation: NSPoint?
    private var cachedTargets: [NoteHandleTarget]?
    private var repositionScheduled = false
    private var subscription: AnyCancellable?

    init(editor: NotePageEditor) {
        self.editor = editor
        bar.plus.onActivate = { [weak self] modifiers in self?.addBlock(above: modifiers.contains(.option)) }
        bar.grip.onPress = { [weak self] event in self?.gripPressed(event) }
        bar.grip.onActivate = { [weak self] _ in self?.gripClicked() }
        subscription = editor.session.changes.sink { [weak self] change in self?.sessionDidChange(change) }
    }

    var activeBlock: NoteBlockID? { pinnedBlock ?? hoveredBlock }

    func pointerMoved(to point: NSPoint) {
        if hiddenForTyping {
            let location = NSEvent.mouseLocation
            if let start = typingMouseLocation, hypot(location.x - start.x, location.y - start.y) < 3 { return }
            hiddenForTyping = false
            typingMouseLocation = nil
        }
        guard pinnedBlock == nil else { return }
        guard !editor.isReadOnly, let target = target(at: point) else {
            if bar.isShown, bar.frame.contains(editor.canvas.overlayView.convert(point, from: editor.canvas)) { return }
            hide()
            return
        }
        show(target)
    }

    func pointerExited() {
        guard pinnedBlock == nil else { return }
        hide()
    }

    func layoutDidChange() {
        cachedTargets = nil
        guard bar.isShown, !repositionScheduled else { return }
        repositionScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.repositionScheduled = false
            self.reposition()
        }
    }

    func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) || modifiers.contains(.control) { return false }
        if let characters = event.characters, !characters.isEmpty { hideForTyping() }
        return false
    }

    func pin(_ id: NoteBlockID?) {
        pinnedBlock = id
        bar.grip.isPinned = id != nil
        if let id, let target = targets().first(where: { $0.id == id }) { show(target) }
        else if id == nil, hoveredBlock == nil { hide() }
    }

    func handleRects(for id: NoteBlockID) -> NoteHandleRects? {
        guard let target = targets().first(where: { $0.id == id }) ?? fallbackTarget(id) else { return nil }
        return rects(for: target)
    }

    func hide(animated: Bool = true) {
        hoveredBlock = nil
        bar.setShown(false, animated: animated)
    }

    private func hideForTyping() {
        guard pinnedBlock == nil else { return }
        hiddenForTyping = true
        typingMouseLocation = NSEvent.mouseLocation
        hide()
    }

    private func sessionDidChange(_ change: NotePageChange) {
        if change.kind == .text, change.origin != nil, !change.isUndoRedo { hideForTyping() }
        if let id = activeBlock, editor.session.page.block(id) == nil {
            if pinnedBlock == id { pinnedBlock = nil; bar.grip.isPinned = false }
            hide()
        }
        if editor.isReadOnly { hide(animated: false) }
    }

    private func show(_ target: NoteHandleTarget) {
        let overlay = editor.canvas.overlayView
        if bar.superview !== overlay { overlay.addSubview(bar) }
        hoveredBlock = target.id
        bar.place(rects(for: target))
        bar.setShown(true)
    }

    private func reposition() {
        guard let id = activeBlock else { return }
        guard let target = targets().first(where: { $0.id == id }) else { hide(); return }
        bar.place(rects(for: target))
    }

    private func rects(for target: NoteHandleTarget) -> NoteHandleRects {
        let canvas = editor.canvas!
        let local = NoteHandleGeometry.rects(blockFrame: target.frame, anchorY: target.anchorY, minimumX: canvas.bounds.minX)
        let overlay = canvas.overlayView
        return NoteHandleRects(plus: overlay.convert(local.plus, from: canvas), grip: overlay.convert(local.grip, from: canvas))
    }

    private func target(at point: NSPoint) -> NoteHandleTarget? {
        NoteHandleGeometry.target(at: point, in: targets())
    }

    private func fallbackTarget(_ id: NoteBlockID) -> NoteHandleTarget? {
        guard let frame = editor.canvas.frame(of: id) else { return nil }
        let depth = editor.session.page.path(of: id).map { $0.count - 1 } ?? 0
        return NoteHandleTarget(id: id, frame: frame, depth: depth, anchorY: editor.canvas.blockView(for: id)?.handleAnchorY ?? 14)
    }

    func targets() -> [NoteHandleTarget] {
        if let cachedTargets { return cachedTargets }
        let canvas = editor.canvas!
        var result: [NoteHandleTarget] = []
        func walk(_ blocks: [NoteBlock], depth: Int) {
            for block in blocks {
                if block.kind != .columns && block.kind != .column, let frame = canvas.frame(of: block.id) {
                    result.append(NoteHandleTarget(id: block.id, frame: frame, depth: depth,
                                                   anchorY: canvas.blockView(for: block.id)?.handleAnchorY ?? 14))
                }
                if block.showsChildren { walk(block.children, depth: depth + 1) }
            }
        }
        walk(editor.session.page.blocks, depth: 0)
        cachedTargets = result
        return result
    }

    private func addBlock(above: Bool) {
        guard !editor.isReadOnly, let id = activeBlock, let block = editor.session.page.block(id) else { return }
        let empty = block.kind == .paragraph && block.text.isEmpty && block.children.isEmpty
        let target: NoteBlockID
        if empty {
            target = id
            editor.session.setSelection(.caret(NotePosition(id, 0)))
        } else {
            let inserted = NoteBlock.paragraph()
            let position: NoteInsertion
            if above { position = .before(id) }
            else if block.acceptsChildren && block.showsChildren && !block.children.isEmpty { position = .firstChild(of: id) }
            else { position = .after(id) }
            editor.session.insertBlocks([inserted], position, select: .caret(NotePosition(inserted.id, 0)))
            target = inserted.id
        }
        hide(animated: false)
        editor.canvas.layoutSubtreeIfNeeded()
        editor.focus(NotePosition(target, 0))
        editor.slashMenu.open(.plus(after: target))
    }

    private func gripPressed(_ event: NSEvent) {
        guard !editor.isReadOnly, let id = activeBlock else { return }
        var moved = false
        let start = event.locationInWindow
        editor.canvas.window?.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking) { tracked, stop in
            guard let tracked else { stop.pointee = true; return }
            if tracked.type == .leftMouseUp { stop.pointee = true; return }
            if NoteDragPlan.crossesThreshold(from: start, to: tracked.locationInWindow) {
                moved = true
                stop.pointee = true
            }
        }
        if !moved { gripClicked(id) }
    }

    private func gripClicked(_ id: NoteBlockID? = nil) {
        guard let id = id ?? activeBlock, editor.session.page.block(id) != nil else { return }
        let ids = NoteDragPlan.draggedBlocks(grabbing: id, selection: editor.session.selection, page: editor.session.page)
        editor.session.setSelection(.blocks(ids.isEmpty ? [id] : ids))
    }
}
