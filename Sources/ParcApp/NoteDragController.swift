import AppKit
import ParcCore

@MainActor
final class NoteDragGhostImageView: NSView {
    let image: NSImage

    init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

@MainActor
final class NoteDragGhostView: NSView {
    static let opacity: CGFloat = 0.9
    let content: NoteDragGhostImageView

    init(image: NSImage, frame: NSRect) {
        content = NoteDragGhostImageView(image: image)
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        if let layer = content.layer {
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0
            layer.shadowRadius = 12
            layer.shadowOffset = CGSize(width: 0, height: -6)
        }
        NoteAnimation.withoutAnimation { content.alphaValue = 0 }
        addSubview(content)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func lift() {
        guard let layer = content.layer else { return }
        NoteAnimation.fade(layer, to: Float(Self.opacity), duration: NoteAnimation.hoverDuration)
        NoteAnimation.withoutAnimation { content.alphaValue = Self.opacity }
        guard !NoteAnimation.reduceMotion else { return }
        NoteAnimation.lift(layer, lifted: true)
    }

    func drop() {
        guard let layer = content.layer else { return }
        NoteAnimation.lift(layer, lifted: false)
    }

    func land(completion: @escaping () -> Void) {
        guard let layer = content.layer else { completion(); return }
        let duration = NoteAnimation.reduceMotion ? NoteAnimation.reducedFadeDuration : 0.18
        NoteAnimation.fade(layer, to: 0, duration: duration, completion: completion)
        NoteAnimation.withoutAnimation { content.alphaValue = 0 }
    }
}

@MainActor
final class NoteDragController: NSObject, NSDraggingSource {
    private enum Outcome { case drop, cancel, dragOut(NSEvent) }

    static let markdownType = NSPasteboard.PasteboardType("net.daringfireball.markdown")

    unowned let editor: NotePageEditor
    private(set) var isDragging = false
    private var dragged: [NoteBlockID] = []
    private var ghost: NoteDragGhostView?
    private var ghostHome: NSRect = .zero
    private var grabOffset: CGPoint = .zero
    private var leadingOffset: CGFloat = 0
    private var target: NoteCanvasDropTarget?
    private var copying = false
    private var hovered: (id: NoteBlockID, since: TimeInterval)?
    private var lastTick: TimeInterval?
    private var pointer: NSPoint = .zero
    var onFinish: (() -> Void)?

    init(editor: NotePageEditor) {
        self.editor = editor
    }

    func run(grabbing id: NoteBlockID, mouseDown: NSEvent, current: NSEvent) {
        guard !isDragging, !editor.isReadOnly, let canvas = editor.canvas, let window = canvas.window else { return }
        let page = editor.session.page
        let ids = NoteDragPlan.draggedBlocks(grabbing: id, selection: editor.session.selection, page: page)
        guard !ids.isEmpty else { return }
        isDragging = true
        dragged = ids
        copying = current.modifierFlags.contains(.option)
        let start = canvas.convert(mouseDown.locationInWindow, from: nil)
        let affected = NoteDragPlan.affectedBlocks(ids, page: page)
        let snapshot = makeSnapshot(of: affected, around: start)
        ghostHome = snapshot?.frame ?? NSRect(origin: start, size: .zero)
        grabOffset = CGPoint(x: start.x - ghostHome.minX, y: start.y - ghostHome.minY)
        leadingOffset = (canvas.frame(of: ids[0])?.minX ?? ghostHome.minX) - ghostHome.minX
        if let snapshot {
            let view = NoteDragGhostView(image: snapshot.image, frame: canvas.overlayView.convert(snapshot.frame, from: canvas))
            canvas.overlayView.addSubview(view)
            view.lift()
            ghost = view
        }
        canvas.setDragSources(ids)
        pointer = canvas.convert(current.locationInWindow, from: nil)
        update()
        NSCursor.closedHand.push()
        let outcome = track(in: window)
        NSCursor.pop()
        finish(outcome)
    }

    private func track(in window: NSWindow) -> Outcome {
        var outcome = Outcome.cancel
        NSEvent.startPeriodicEvents(afterDelay: 0, withPeriod: 1.0 / 60)
        defer { NSEvent.stopPeriodicEvents() }
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp, .keyDown, .flagsChanged, .periodic],
                           timeout: .infinity, mode: .eventTracking) { event, stop in
            guard let event else { stop.pointee = true; return }
            switch event.type {
            case .leftMouseDragged:
                if self.leftWindow(event, window: window) {
                    outcome = .dragOut(event)
                    stop.pointee = true
                    return
                }
                self.pointer = self.editor.canvas.convert(event.locationInWindow, from: nil)
                self.copying = event.modifierFlags.contains(.option)
                self.update()
            case .periodic:
                self.tick(at: event.timestamp, window: window)
            case .flagsChanged:
                self.copying = event.modifierFlags.contains(.option)
            case .keyDown:
                if event.keyCode == 53 {
                    outcome = .cancel
                    stop.pointee = true
                }
            case .leftMouseUp:
                outcome = .drop
                stop.pointee = true
            default:
                break
            }
        }
        return outcome
    }

    private func leftWindow(_ event: NSEvent, window: NSWindow) -> Bool {
        guard let content = window.contentView else { return false }
        return !content.bounds.contains(content.convert(event.locationInWindow, from: nil))
    }

    private func tick(at time: TimeInterval, window: NSWindow) {
        let elapsed = lastTick.map { time - $0 } ?? 1.0 / 60
        lastTick = time
        let canvas = editor.canvas!
        pointer = canvas.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if let clip = canvas.enclosingScrollView?.contentView {
            let visible = canvas.visibleRect
            let velocity = NoteAutoscroll.velocity(pointerY: pointer.y, visibleMinY: visible.minY, visibleMaxY: visible.maxY)
            let step = NoteAutoscroll.step(velocity: velocity, elapsed: elapsed)
            if step != 0 {
                let limit = max(0, canvas.bounds.height - clip.bounds.height)
                var origin = clip.bounds.origin
                let next = min(max(0, origin.y + step), limit)
                if next != origin.y {
                    origin.y = next
                    clip.scroll(to: origin)
                    canvas.enclosingScrollView?.reflectScrolledClipView(clip)
                    pointer = canvas.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                }
            }
        }
        update()
        expandHoveredToggle(now: time)
    }

    private func update() {
        let canvas = editor.canvas!
        let origin = NoteDragPlan.ghostOrigin(pointer: pointer, grabOffset: grabOffset)
        if let ghost {
            let frame = canvas.overlayView.convert(NSRect(origin: origin, size: ghostHome.size), from: canvas)
            NoteAnimation.withoutAnimation { ghost.frame = frame }
        }
        let next = canvas.dropTarget(at: pointer, dragging: dragged, leadingX: origin.x + leadingOffset)
        if next != target {
            target = next
            canvas.showDropIndicator(next)
        }
    }

    private func expandHoveredToggle(now: TimeInterval) {
        let canvas = editor.canvas!
        guard let id = canvas.blockID(at: pointer), let block = editor.session.page.block(id),
              block.isToggle, !block.props.expanded, NoteDragPlan.canDrop(dragged, onto: id, page: editor.session.page) else {
            hovered = nil
            return
        }
        guard let current = hovered, current.id == id else {
            hovered = (id, now)
            return
        }
        guard NoteDragPlan.shouldExpand(block, hoveredSince: current.since, now: now) else { return }
        hovered = nil
        editor.session.toggleExpanded(id)
        canvas.updateLayoutIfNeeded()
        update()
    }

    private func finish(_ outcome: Outcome) {
        let canvas = editor.canvas!
        canvas.showDropIndicator(nil)
        let ids = dragged
        let chosen = target
        target = nil
        hovered = nil
        lastTick = nil
        switch outcome {
        case .drop where chosen != nil:
            drop(ids, on: chosen!)
        case .drop, .cancel:
            springHome()
        case .dragOut(let event):
            canvas.setDragSources([])
            let image = ghost?.content.image
            removeGhost()
            beginExternalDrag(ids, image: image, event: event)
        }
        isDragging = false
        dragged = []
        onFinish?()
    }

    private func drop(_ ids: [NoteBlockID], on target: NoteCanvasDropTarget) {
        let canvas = editor.canvas!
        let session = editor.session
        let origin = ghost.map { canvas.convert($0.frame, from: canvas.overlayView).origin } ?? pointer
        if copying {
            let copies = NoteDragPlan.copies(of: ids, in: session.page)
            canvas.prepareDropSettle(copies.map(\.id), ghostOrigin: origin)
            copy(copies, to: target)
        } else {
            canvas.prepareDropSettle(ids, ghostOrigin: origin)
            target.perform(moving: ids, in: session)
        }
        canvas.setDragSources([])
        removeGhost()
    }

    private func copy(_ copies: [NoteBlock], to target: NoteCanvasDropTarget) {
        let session = editor.session
        let selection = NotePageSelection.blocks(copies.map(\.id))
        switch target.action {
        case .move(let insertion):
            session.insertBlocks(copies, insertion, select: selection)
        case .placeBeside(let anchor, let side):
            session.edit("Duplicate", selection: selection) { page in
                page.place(copies, beside: anchor, side: side)
            }
        }
    }

    private func springHome() {
        let canvas = editor.canvas!
        guard let ghost else { canvas.setDragSources([]); return }
        self.ghost = nil
        let home = canvas.overlayView.convert(ghostHome, from: canvas)
        if NoteAnimation.reduceMotion {
            NoteAnimation.withoutAnimation { ghost.frame = home }
            canvas.setDragSources([])
            ghost.land { ghost.removeFromSuperview() }
            return
        }
        ghost.drop()
        _ = NoteAnimation.slide(ghost, to: home, spring: .settle) {
            canvas.setDragSources([])
            ghost.land { ghost.removeFromSuperview() }
        }
    }

    private func removeGhost() {
        ghost?.removeFromSuperview()
        ghost = nil
    }

    private func makeSnapshot(of ids: [NoteBlockID], around point: NSPoint) -> (image: NSImage, frame: NSRect)? {
        let canvas = editor.canvas!
        var union: NSRect?
        var pieces: [NoteDragGhostRenderer.Piece] = []
        for id in ids {
            guard let frame = canvas.frame(of: id) else { continue }
            let outer = canvas.outerFrame(of: id) ?? frame
            union = union.map { $0.union(outer) } ?? outer
            if let view = canvas.existingBlockView(for: id), !view.isHidden { pieces.append(.init(view: view, frame: view.frame)) }
        }
        let decorations = canvas.decorations(of: ids)
        for decoration in decorations { union = union.map { $0.union(decoration.rect) } ?? decoration.rect }
        guard var rect = union?.integral, rect.width >= 1, rect.height >= 1 else { return nil }
        let reach: CGFloat = 360
        rect = rect.intersection(NSRect(x: rect.minX, y: point.y - reach, width: rect.width, height: reach * 2))
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        let scale = canvas.window?.backingScaleFactor ?? 2
        guard let image = NoteDragGhostRenderer.render(pieces, decorations: decorations, clip: rect, in: canvas, scale: scale) else { return nil }
        return (image, rect)
    }

    private func beginExternalDrag(_ ids: [NoteBlockID], image: NSImage?, event: NSEvent) {
        let canvas = editor.canvas!
        let blocks = editor.session.fragment(of: .blocks(ids))
        guard !blocks.isEmpty else { return }
        let fragment = NotePage(blocks: blocks)
        let item = NSPasteboardItem()
        item.setString(NoteMarkdown.serialize(fragment), forType: NoteDragController.markdownType)
        item.setString(fragment.plainText, forType: .string)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        let size = image?.size ?? NSSize(width: 240, height: 28)
        let location = canvas.convert(event.locationInWindow, from: nil)
        let frame = NSRect(x: location.x - grabOffset.x, y: location.y - grabOffset.y, width: size.width, height: size.height)
        dragging.setDraggingFrame(frame, contents: image)
        let session = canvas.beginDraggingSession(with: [dragging], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

@MainActor
enum NoteDragGhostRenderer {
    struct Piece {
        var view: NSView
        var frame: NSRect
    }

    static func render(_ pieces: [Piece], decorations: [NoteCanvasDecoration], clip rect: NSRect, in container: NSView,
                       scale: CGFloat) -> NSImage? {
        guard rect.width >= 1, rect.height >= 1,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(rect.width * scale)),
                                         pixelsHigh: Int(ceil(rect.height * scale)), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let bitmap = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = rect.size
        let context = bitmap.cgContext
        context.translateBy(x: 0, y: CGFloat(rep.pixelsHigh))
        context.scaleBy(x: CGFloat(rep.pixelsWide) / rect.width, y: -CGFloat(rep.pixelsHigh) / rect.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        container.effectiveAppearance.performAsCurrentDrawingAppearance {
            for decoration in decorations {
                NoteCanvasDecorationView.draw(decoration.style, in: decoration.rect.offsetBy(dx: -rect.minX, dy: -rect.minY))
            }
        }
        for piece in pieces {
            let visible = piece.frame.intersection(rect)
            guard visible.width >= 1, visible.height >= 1 else { continue }
            let local = piece.view.convert(visible, from: piece.view.superview ?? container)
            guard let capture = piece.view.bitmapImageRepForCachingDisplay(in: local) else { continue }
            piece.view.cacheDisplay(in: local, to: capture)
            capture.draw(in: visible.offsetBy(dx: -rect.minX, dy: -rect.minY), from: .zero, operation: .sourceOver,
                         fraction: 1, respectFlipped: true, hints: nil)
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rect.size)
        image.addRepresentation(rep)
        return image
    }
}
