import AppKit
import Combine

@MainActor
final class NoteHandleButton: NSView {
    enum Role { case add, grip }

    static let idleOpacity = Float(NoteTheme.idleHandleOpacity)
    static let pressedScale = NoteAnimation.pressedScale

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
            glyph.fillColor = (isHovered || isPressed ? NoteTheme.secondaryInk : NoteTheme.handleInk).cgColor
            plate.backgroundColor = (isPressed ? NoteTheme.pressedFill : NoteTheme.hoverFill).cgColor
        }
        glyph.opacity = isLit ? 1 : Self.idleOpacity
        plate.opacity = isHovered || isPressed ? 1 : 0
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
        NoteAnimation.observeReduceMotion(self) { [weak self] in
            guard let self else { return }
            NoteAnimation.settle(self)
        }
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
        NoteAnimation.fade(self, visible: shown, duration: animated ? NoteAnimation.hoverDuration : 0) { [weak self] in
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
    static let addTooltip = "Click to add below, Option-click to add above"
    static let gripTooltip = "Drag to move, click for options"

    unowned let editor: NotePageEditor
    let bar = NoteHandleBar()
    var presentToast: ((ParcToastContent) -> Void)?
    var downloadFolder: (@MainActor () async -> URL?)?
    private(set) lazy var menu: NoteBlockMenuController = {
        let controller = NoteBlockMenuController(editor: editor)
        controller.onClose = { [weak self] in self?.menuDidClose() }
        return controller
    }()
    private(set) lazy var drag: NoteDragController = {
        let controller = NoteDragController(editor: editor)
        controller.onFinish = { [weak self] in self?.refreshFromPointer() }
        return controller
    }()
    private(set) var hoveredBlock: NoteBlockID?
    private(set) var pinnedBlock: NoteBlockID?
    private var hiddenForTyping = false
    private var typingMouseLocation: NSPoint?
    private var cachedTargets: [NoteHandleTarget]?
    private var lastMenuTarget: [NoteBlockID] = []
    private var lastMenuCloseEvent: TimeInterval?
    private var subscriptions: Set<AnyCancellable> = []

    init(editor: NotePageEditor) {
        self.editor = editor
        bar.plus.onActivate = { [weak self] modifiers in self?.addBlock(above: modifiers.contains(.option)) }
        bar.grip.onPress = { [weak self] event in self?.gripPressed(event) }
        bar.grip.onActivate = { [weak self] _ in self?.gripClicked(event: nil) }
        editor.session.changes.sink { [weak self] change in self?.sessionDidChange(change) }.store(in: &subscriptions)
        editor.canvas.layoutDidChange.sink { [weak self] in self?.canvasDidLayout() }.store(in: &subscriptions)
    }

    var activeBlock: NoteBlockID? { pinnedBlock ?? hoveredBlock }

    func pointerMoved(to point: NSPoint) {
        if hiddenForTyping {
            let location = NSEvent.mouseLocation
            if let start = typingMouseLocation, hypot(location.x - start.x, location.y - start.y) < 3 { return }
            hiddenForTyping = false
            typingMouseLocation = nil
        }
        guard pinnedBlock == nil, !drag.isDragging else { return }
        guard !editor.isReadOnly, let target = target(at: point) else {
            if bar.isShown, bar.frame.contains(editor.canvas.overlayView.convert(point, from: editor.canvas)) { return }
            hide()
            return
        }
        show(target)
    }

    func pointerExited() {
        guard pinnedBlock == nil, !drag.isDragging else { return }
        hide()
    }

    func layoutDidChange() {
        cachedTargets = nil
    }

    private func canvasDidLayout() {
        cachedTargets = nil
        if bar.isShown { reposition() }
    }

    private func refreshFromPointer() {
        guard let window = editor.canvas.window else { return }
        let point = editor.canvas.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if editor.canvas.visibleRect.contains(point) { pointerMoved(to: point) } else { hide() }
    }

    func handleKey(_ event: NSEvent) -> Bool {
        if menu.isOpen, menu.handleKey(event) { return true }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == .command, key == "/" { return openBlockActions() }
        if modifiers == [.command, .shift], key == "p" { return openBlockActions(startInMoveTo: true) }
        if modifiers == [.command, .control], event.keyCode == 37 { return copyLinkToSelectedBlock() }
        if modifiers.contains(.command) || modifiers.contains(.control) { return false }
        if let characters = event.characters, !characters.isEmpty { hideForTyping() }
        return false
    }

    @discardableResult
    func openBlockActions(startInMoveTo: Bool = false) -> Bool {
        let selection = editor.session.selection
        let ids = blocksForMenu(selection)
        guard let first = ids.first, !menu.isOpen else { return menu.isOpen }
        editor.session.setSelection(.blocks(ids))
        editor.canvas.layoutSubtreeIfNeeded()
        editor.canvas.scrollBlockToVisible(first)
        pin(first)
        let anchor = handleRects(for: first)?.grip ?? editor.canvas.overlayView.convert(editor.canvas.frame(of: first) ?? .zero, from: editor.canvas)
        lastMenuTarget = ids
        menu.open(for: ids, anchor: anchor, keyboard: true, previousSelection: selection, startInMoveTo: startInMoveTo)
        if !menu.isOpen { pin(nil) }
        return true
    }

    @discardableResult
    func copyLinkToSelectedBlock() -> Bool {
        let ids = blocksForMenu(editor.session.selection)
        guard ids.count == 1, editor.canLinkBlocks else { return false }
        return editor.copyLink(toBlock: ids[0])
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

    private func blocksForMenu(_ selection: NotePageSelection) -> [NoteBlockID] {
        let page = editor.session.page
        switch selection {
        case .none: return []
        case .blocks(let ids): return page.topLevelSelection(ids).filter { page.block($0)?.kind != .column }
        case .cells(let table, _, _): return page.block(table) == nil ? [] : [table]
        case .text(let anchor, let head):
            if anchor == head { return page.block(head.block) == nil ? [] : [head.block] }
            let touched = editor.session.textSegments(of: selection).map(\.position.block)
            return page.topLevelSelection(touched.isEmpty ? [head.block] : touched)
        }
    }

    private func menuDidClose() {
        lastMenuCloseEvent = NSApp.currentEvent?.timestamp
        pin(nil)
        refreshFromPointer()
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
        let canvas = editor.canvas!
        canvas.updateLayoutIfNeeded()
        guard let entry = canvas.canvasLayout.entry(id) else { return nil }
        return Self.target(for: entry, canvas: canvas)
    }

    private static func target(for entry: NoteCanvasEntry, canvas: NotePageCanvasView) -> NoteHandleTarget {
        let leading = entry.kind == .callout ? min(entry.outerFrame.minX, entry.frame.minX) : entry.frame.minX
        let frame = CGRect(x: leading, y: entry.frame.minY, width: max(0, entry.frame.maxX - leading), height: entry.frame.height)
        return NoteHandleTarget(id: entry.id, frame: frame, depth: entry.depth, anchorY: canvas.handleAnchorY(for: entry.id))
    }

    func targets() -> [NoteHandleTarget] {
        if let cachedTargets { return cachedTargets }
        let canvas = editor.canvas!
        canvas.updateLayoutIfNeeded()
        let result = canvas.canvasLayout.entries.compactMap { entry -> NoteHandleTarget? in
            guard entry.isRow, entry.kind != .columns, entry.kind != .column,
                  entry.frame.width > 0, entry.frame.height > 0 else { return nil }
            return Self.target(for: entry, canvas: canvas)
        }
        cachedTargets = result
        return result
    }

    private func addBlock(above: Bool) {
        guard !editor.isReadOnly, let id = activeBlock, let block = editor.session.page.block(id) else { return }
        let empty = block.kind == .paragraph && block.text.isEmpty && block.children.isEmpty
        let target: NoteBlockID
        if empty && !above {
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
        guard let id = activeBlock else { return }
        if editor.isReadOnly { gripClicked(event: event); return }
        var dragEvent: NSEvent?
        let start = event.locationInWindow
        editor.canvas.window?.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking) { tracked, stop in
            guard let tracked else { stop.pointee = true; return }
            if tracked.type == .leftMouseUp { stop.pointee = true; return }
            if NoteDragPlan.crossesThreshold(from: start, to: tracked.locationInWindow) {
                dragEvent = tracked
                stop.pointee = true
            }
        }
        guard let dragEvent else { gripClicked(event: event, block: id); return }
        bar.grip.setPressed(false)
        hide(animated: true)
        drag.run(grabbing: id, mouseDown: event, current: dragEvent)
    }

    private func gripClicked(event: NSEvent?, block: NoteBlockID? = nil) {
        guard let id = block ?? activeBlock, editor.session.page.block(id) != nil else { return }
        let previous = editor.session.selection
        let dragged = NoteDragPlan.draggedBlocks(grabbing: id, selection: previous, page: editor.session.page)
        let ids = dragged.isEmpty ? [id] : dragged
        if let event, let closed = lastMenuCloseEvent, closed == event.timestamp, lastMenuTarget == ids { return }
        editor.session.setSelection(.blocks(ids))
        pin(id)
        guard let anchor = handleRects(for: id)?.grip else { pin(nil); return }
        lastMenuTarget = ids
        menu.open(for: ids, anchor: anchor, keyboard: event == nil, previousSelection: previous)
        if !menu.isOpen { pin(nil) }
    }

    func move(_ ids: [NoteBlockID], to url: URL, title: String?) {
        let session = editor.session
        guard !session.page.topLevelSelection(ids).isEmpty else { return }
        let name = title ?? url.deletingPathExtension().lastPathComponent
        let file: NoteFileSession
        do { file = try NoteFileSession.open(url) } catch {
            presentToast?(.standard("Couldn’t open “\(name)”. Your blocks stayed put."))
            return
        }
        guard file.page !== session else { return }
        file.retain()
        defer { file.release() }
        guard !file.page.isReadOnly, !file.page.page.settings.locked else {
            presentToast?(.standard("“\(name)” is locked or read-only, so your blocks stayed put."))
            return
        }
        let home = NoteFileSession.openSessions.first { $0.page === session }
        guard NoteCrossNoteMove.perform(ids, from: session, name: "Move to “\(name)”", target: Self.access(file),
                                        source: home.map(Self.access)) != nil else {
            presentToast?(.standard("Couldn’t move those blocks. They stayed put."))
            return
        }
        presentToast?(.undoable("Moved to “\(name)”"))
        if let caret = session.selection.caret { editor.focus(caret) }
    }

    private static func access(_ file: NoteFileSession) -> NoteCrossNoteMove.Access {
        var current = file
        return { body in
            guard let live = try? NoteFileSession.open(current.url) else { return false }
            current = live
            live.retain()
            defer { live.release() }
            guard !live.page.isReadOnly else { return false }
            body(live.page)
            return true
        }
    }

    func download(_ source: String) {
        guard let url = editor.environment.resolve(source) else { return }
        let chosenFolder = downloadFolder
        Task { @MainActor [weak self] in
            let folder = await chosenFolder?() ?? Self.fallbackDownloadFolder
            if url.isFileURL {
                do {
                    let saved = try Self.copy(url, into: folder, suggestedName: url.lastPathComponent)
                    self?.announceDownload(saved, in: folder)
                } catch {
                    self?.presentToast?(.standard("Couldn’t save that file. Maybe try again?"))
                }
                return
            }
            do {
                let (temporary, response) = try await URLSession.shared.download(from: url)
                defer { try? FileManager.default.removeItem(at: temporary) }
                let name = response.suggestedFilename ?? url.lastPathComponent
                let saved = try Self.copy(temporary, into: folder, suggestedName: name.isEmpty ? "Download" : name)
                self?.announceDownload(saved, in: folder)
            } catch {
                self?.presentToast?(.standard("Couldn’t download that. Maybe try again?"))
            }
        }
    }

    static var fallbackDownloadFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }

    static func downloadToastTitle(for folder: URL) -> String {
        "Saved to \(FileManager.default.displayName(atPath: folder.path))"
    }

    private func announceDownload(_ saved: URL, in folder: URL) {
        presentToast?(.standard(Self.downloadToastTitle(for: folder), icon: "arrow.down.circle.fill", subLabel: saved.lastPathComponent))
    }

    private static func copy(_ source: URL, into folder: URL, suggestedName: String) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = (suggestedName as NSString).deletingPathExtension
        let ext = (suggestedName as NSString).pathExtension
        var candidate = folder.appendingPathComponent(suggestedName)
        var counter = 2
        while manager.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = folder.appendingPathComponent(name)
            counter += 1
        }
        try manager.copyItem(at: source, to: candidate)
        return candidate
    }
}
