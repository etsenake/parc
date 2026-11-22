import AppKit
import ParcCore

extension NoteSelectionController {
    static let dragThreshold: CGFloat = 3
    static let columnEscape: CGFloat = 36

    private static func modifiers(_ event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection([.command, .shift, .option, .control])
    }

    func textViewMouseDown(_ view: NoteTextView, with event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown, !isTracking, let host = view.host, let window = view.window,
              !view.hasMarkedText() else { return false }
        let flags = Self.modifiers(event)
        if flags.contains(.control) { return false }
        let blocksSelected = session.selection.selectedBlocks != nil
        if flags.contains(.command) {
            guard flags.contains(.shift) || blocksSelected else { return false }
            toggleBlock(host.blockID)
            return true
        }
        if flags.contains(.option) || host.field != .body { return false }
        if flags.contains(.shift) {
            if blocksSelected {
                extendBlocks(to: host.blockID)
                return true
            }
            guard case .text(let anchor, _) = currentSelection(), anchor.field == .body else { return false }
            trackText(event, anchor: anchor.block, range: anchor.offset..<anchor.offset, granularity: .character, immediate: true)
            return true
        }
        let point = canvas.convert(event.locationInWindow, from: nil)
        let offset = layout.offset(in: host.blockID, at: point) ?? 0
        if event.clickCount >= 3 {
            trackText(event, anchor: host.blockID, range: 0..<layout.length(of: NotePosition(host.blockID, 0)),
                      granularity: .paragraph, immediate: true)
            return true
        }
        if event.clickCount == 1, window.firstResponder === view {
            let current = view.selectedOffsets
            if !current.isEmpty && current.contains(offset) { return false }
        }
        guard waitForDrag(after: event, in: window) else { return false }
        let position = NotePosition(host.blockID, offset)
        let word = event.clickCount == 2
        trackText(event, anchor: host.blockID, range: word ? layout.wordRange(at: position) : offset..<offset,
                  granularity: word ? .word : .character, immediate: false)
        return true
    }

    func canvasMouseDown(_ event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown, !isTracking, let window = canvas.window else { return false }
        let flags = Self.modifiers(event)
        guard !flags.contains(.control) else { return false }
        let point = canvas.convert(event.locationInWindow, from: nil)
        let nav = navigator()
        let column = canvas.contentRect
        let inColumn = point.x >= column.minX && point.x <= column.maxX
        let frames = nav.items.filter { $0.role.isSteppable && !$0.frame.isEmpty }.map(\.frame)
        let below = point.y > (frames.map(\.maxY).max() ?? 0)
        let above = point.y < (frames.map(\.minY).min() ?? 0) - NoteTheme.blockSpacing
        let item = below || above ? nil : pointerItem(at: point, nav: nav)
        if inColumn, let item {
            return rowMouseDown(item, event: event, point: point, flags: flags, window: window)
        }
        let dragged = waitForDrag(after: event, in: window)
        guard dragged else {
            if (below || above) && inColumn { return false }
            if let item, flags.contains(.shift) {
                extendBlocks(to: item.id)
                return true
            }
            if let item, flags.contains(.command) {
                toggleBlock(item.id)
                return true
            }
            if session.selection.selectedBlocks != nil {
                blockRange = nil
                select(.none)
                return true
            }
            return false
        }
        var base: [NoteBlockID] = []
        if !flags.intersection([.shift, .command]).isEmpty, let ids = session.selection.selectedBlocks { base = ids }
        trackMarquee(event, base: base)
        return true
    }

    func blockMouseDown(_ view: NoteBlockView, with event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown, !isTracking, let window = canvas.window else { return false }
        let flags = Self.modifiers(event)
        guard !flags.contains(.control), let item = navigator().item(view.blockID), item.role.isSteppable else { return false }
        return rowMouseDown(item, event: event, point: canvas.convert(event.locationInWindow, from: nil), flags: flags, window: window)
    }

    private func rowMouseDown(_ item: NoteSelectionItem, event: NSEvent, point: NSPoint, flags: NSEvent.ModifierFlags, window: NSWindow) -> Bool {
        if flags.contains(.command) {
            toggleBlock(item.id)
            return true
        }
        if flags.contains(.shift) {
            if item.role == .text, case .text(let anchor, _) = currentSelection(), anchor.field == .body {
                trackText(event, anchor: anchor.block, range: anchor.offset..<anchor.offset, granularity: .character, immediate: true)
            } else {
                extendBlocks(to: item.id)
            }
            return true
        }
        guard item.role == .text else {
            guard waitForDrag(after: event, in: window) else {
                goal.reset()
                blockRange = NoteBlockRange(anchor: item.id, head: item.id)
                select(.blocks([item.id]))
                return true
            }
            trackBlocks(event, anchor: item.id)
            return true
        }
        let length = layout.length(of: NotePosition(item.id, 0))
        if event.clickCount >= 3 {
            trackText(event, anchor: item.id, range: 0..<length, granularity: .paragraph, immediate: true)
            return true
        }
        let offset = layout.offset(in: item.id, at: point) ?? (point.y < item.frame.midY ? 0 : length)
        let position = NotePosition(item.id, offset)
        let word = event.clickCount == 2
        let range = word ? layout.wordRange(at: position) : offset..<offset
        guard waitForDrag(after: event, in: window) else {
            goal.reset()
            select(.text(anchor: NotePosition(item.id, range.lowerBound), head: NotePosition(item.id, range.upperBound)))
            return true
        }
        trackText(event, anchor: item.id, range: range, granularity: word ? .word : .character, immediate: false)
        return true
    }

    func extendBlocks(to id: NoteBlockID) {
        let nav = navigator()
        let anchor: NoteBlockID
        switch currentSelection() {
        case .blocks(let ids): anchor = blockRange?.anchor ?? ids.first ?? id
        case .text(let current, _): anchor = current.block
        case .cells(let table, _, _): anchor = table
        case .none: anchor = id
        }
        goal.reset()
        blockRange = NoteBlockRange(anchor: anchor, head: id)
        select(.blocks(nav.blocks(from: anchor, to: id)))
    }

    func toggleBlock(_ id: NoteBlockID) {
        let nav = navigator()
        let next = nav.toggling(id, in: session.selection.selectedBlocks ?? [])
        goal.reset()
        blockRange = next.last.map { NoteBlockRange(anchor: $0, head: $0) }
        select(next.isEmpty ? .none : .blocks(next))
    }

    func pointerItem(at point: NSPoint, nav: NoteSelectionNavigator) -> NoteSelectionItem? {
        if let id = canvas.blockID(at: point), let item = nav.item(id), item.role.isSteppable { return item }
        return nav.nearestItem(to: point)
    }

    func waitForDrag(after event: NSEvent, in window: NSWindow) -> Bool {
        let start = event.locationInWindow
        while true {
            guard let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged], until: .distantFuture,
                                              inMode: .eventTracking, dequeue: false) else { return false }
            if next.type == .leftMouseUp { return false }
            if hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y) >= Self.dragThreshold { return true }
            _ = window.nextEvent(matching: [.leftMouseDragged], until: .distantFuture, inMode: .eventTracking, dequeue: true)
        }
    }

    private func runDragLoop(from event: NSEvent, in window: NSWindow) {
        trackingEvent = event
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoscrollTick() }
        }
        RunLoop.current.add(timer, forMode: .eventTracking)
        defer { timer.invalidate() }
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged], until: .distantFuture,
                                          inMode: .eventTracking, dequeue: true) {
            trackingEvent = next
            if next.type == .leftMouseDragged, canvas.autoscroll(with: next) { refreshTrackingLayout() }
            trackingUpdate?(next.locationInWindow)
            if next.type == .leftMouseUp { break }
        }
    }

    private func autoscrollTick() {
        guard isTracking, let event = trackingEvent, event.type == .leftMouseDragged, let window = canvas.window else { return }
        guard canvas.autoscroll(with: event) else { return }
        refreshTrackingLayout()
        trackingUpdate?(window.mouseLocationOutsideOfEventStream)
    }

    private func refreshTrackingLayout() {
        canvas.layoutSubtreeIfNeeded()
        trackingNavigator = nil
        trackingNavigator = navigator()
    }

    private func trackText(_ event: NSEvent, anchor: NoteBlockID, range: Range<Int>, granularity: NoteSelectionGranularity, immediate: Bool) {
        guard let window = canvas.window else { return }
        goal.reset()
        beginTracking()
        let column = canvas.contentRect
        var result = NotePageSelection.text(anchor: NotePosition(anchor, range.lowerBound), head: NotePosition(anchor, range.upperBound))
        let text = { [unowned self] (head: NotePosition) -> NotePageSelection in
            let nav = navigator()
            let headRange = nav.granularRange(at: head, granularity: granularity, layout: layout)
            let ends = nav.span(anchor: anchor, anchorRange: range, head: head.block, headRange: headRange)
            return .text(anchor: ends.anchor, head: ends.head)
        }
        trackingUpdate = { [unowned self] windowPoint in
            let nav = navigator()
            let point = canvas.convert(windowPoint, from: nil)
            let outside = point.x < column.minX - Self.columnEscape || point.x > column.maxX + Self.columnEscape
            let pointer = pointerItem(at: point, nav: nav)
            switch nav.dragTarget(anchor: anchor, pointer: pointer, outsideColumn: outside, layout: layout) {
            case .blocks(let ids):
                blockRange = NoteBlockRange(anchor: anchor, head: pointer?.id ?? anchor)
                result = .blocks(ids)
            case .position(let position):
                result = text(position)
            case .text(let id):
                result = text(NotePosition(id, textOffset(in: id, at: point, nav: nav)))
            }
            preview(result)
        }
        if immediate { trackingUpdate?(event.locationInWindow) } else { preview(result) }
        runDragLoop(from: event, in: window)
        endTracking(with: result)
    }

    private func textOffset(in id: NoteBlockID, at point: NSPoint, nav: NoteSelectionNavigator) -> Int {
        let length = layout.length(of: NotePosition(id, 0))
        let steppable = nav.items.filter { $0.role.isSteppable && !$0.frame.isEmpty }
        if let first = steppable.first, first.id == id, point.y < first.frame.minY { return 0 }
        if let last = steppable.last, last.id == id, point.y > last.frame.maxY { return length }
        if let offset = layout.offset(in: id, at: point) { return offset }
        let frame = nav.item(id)?.frame ?? .zero
        return point.y < frame.midY ? 0 : length
    }

    private func trackBlocks(_ event: NSEvent, anchor: NoteBlockID) {
        guard let window = canvas.window else { return }
        goal.reset()
        beginTracking()
        var result = NotePageSelection.blocks([anchor])
        blockRange = NoteBlockRange(anchor: anchor, head: anchor)
        trackingUpdate = { [unowned self] windowPoint in
            let nav = navigator()
            let point = canvas.convert(windowPoint, from: nil)
            let head = pointerItem(at: point, nav: nav)?.id ?? anchor
            blockRange = NoteBlockRange(anchor: anchor, head: head)
            result = .blocks(nav.blocks(from: anchor, to: head))
            preview(result)
        }
        preview(result)
        runDragLoop(from: event, in: window)
        endTracking(with: result)
    }

    private func trackMarquee(_ event: NSEvent, base: [NoteBlockID]) {
        guard let window = canvas.window else { return }
        goal.reset()
        beginTracking()
        let start = canvas.convert(event.locationInWindow, from: nil)
        let column = canvas.contentRect
        let marquee = NoteSelectionMarqueeView(frame: NSRect(origin: start, size: .zero))
        canvas.overlayView.addSubview(marquee)
        var result: NotePageSelection = base.isEmpty ? .none : .blocks(base)
        trackingUpdate = { [unowned self] windowPoint in
            let point = canvas.convert(windowPoint, from: nil)
            let rect = NSRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
            marquee.frame = canvas.overlayView.convert(rect, from: canvas)
            let nav = navigator()
            let hit = nav.marquee(rect, column: column.minX...max(column.minX, column.maxX))
            let ids = base.isEmpty ? hit : nav.normalized(Set(base).union(hit))
            if let first = ids.first { blockRange = NoteBlockRange(anchor: first, head: ids.last ?? first) }
            result = ids.isEmpty ? .none : .blocks(ids)
            preview(result)
        }
        trackingUpdate?(event.locationInWindow)
        runDragLoop(from: event, in: window)
        NoteAnimation.fade(marquee, visible: false, duration: 0.12) { marquee.removeFromSuperview() }
        endTracking(with: result)
    }
}

@MainActor
final class NoteSelectionMarqueeView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = NoteTheme.accent.usingColorSpace(.sRGB) ?? NoteTheme.accent
            layer?.backgroundColor = accent.withAlphaComponent(0.08).cgColor
            layer?.borderColor = accent.withAlphaComponent(0.28).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
