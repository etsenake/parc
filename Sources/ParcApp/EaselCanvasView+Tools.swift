import AppKit
import QuartzCore

@MainActor
final class EaselCanvasToolState {
    struct Creation {
        let tool: EaselTool
        let start: NSPoint
        var end: NSPoint
        var flags: NSEvent.ModifierFlags
        var dragged = false
        let id = UUID()
    }

    var spaceHeld = false
    var pan: (window: NSPoint, origin: NSPoint)?
    var creation: Creation?
    var shape: EaselShape = .rectangle
    var previewPoint: NSPoint?
    var previewTool: EaselTool?
    var previewView: EaselToolPreviewView?
    let previewID = UUID()
    var zoomDriver: EaselCanvasFrameDriver?
    var zoomTarget: (magnification: Double, centre: NSPoint)?
    var openFitDone = false
    var coveredBottom: CGFloat = 0
    var onQuickActions: (() -> Void)?
}

extension EaselKeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var value: EaselKeyModifiers = []
        if flags.contains(.shift) { value.insert(.shift) }
        if flags.contains(.control) { value.insert(.control) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.command) { value.insert(.command) }
        self = value
    }
}

private extension EaselPoint {
    init(_ point: NSPoint) { self.init(x: Double(point.x), y: Double(point.y)) }
}

extension EaselCanvasView {
    var toolOwnsPointer: Bool { tool != .select || toolState.spaceHeld || toolState.pan != nil }

    var toolCursor: NSCursor {
        if toolState.pan != nil { return .closedHand }
        if toolState.spaceHeld { return .openHand }
        switch tool {
        case .select: return .arrow
        case .hand: return .openHand
        case .marker, .highlighter, .washi, .eraser: return brushCursor(for: tool)
        case .stamp: return stampCursor
        default: return .crosshair
        }
    }

    func activateTool(_ next: EaselTool, from control: NSView? = nil) {
        guard next.isAvailable, !session.isClosed else { return }
        tool = next
        toolActivated(next, from: control)
    }

    func toolActivated(_ tool: EaselTool, from control: NSView?) {
        switch tool {
        case .stamp: stampToolActivated(from: control)
        default: break
        }
    }

    func armShape(_ shape: EaselShape) {
        toolState.shape = shape == .ellipse ? toolState.shape : shape
        activateTool(shape == .ellipse ? .ellipse : .rectangle)
        refreshPlacementPreview()
    }

    func toolDidChange() {
        cancelToolGesture()
        if tool != .stamp { dismissStampPanels() }
        hoveredObjectID = nil
        needsDisplay = true
        decoration.needsDisplay = true
        refreshPlacementPreview()
        refreshToolCursor()
    }

    func cancelToolGesture() {
        cancelStampPress()
        if toolState.creation?.tool == .table { cancelTablePlacement() }
        toolState.creation = nil
        cancelConnectorGesture()
        guard toolState.pan != nil else { return }
        toolState.pan = nil
        refreshToolCursor()
    }

    func refreshToolCursor() {
        window?.invalidateCursorRects(for: self)
        guard let window, window.isKeyWindow, isTopmost(atWindowPoint: window.mouseLocationOutsideOfEventStream) else { return }
        toolCursor.set()
    }

    func keyCommand(for event: NSEvent) -> EaselKeyCommand? {
        EaselKeyCommands.command(characters: event.charactersIgnoringModifiers, keyCode: event.keyCode,
                                 modifiers: EaselKeyModifiers(event.modifierFlags))
    }

    func handleToolKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        if event.keyCode == EaselKeyCommands.spaceKeyCode {
            guard flags.isDisjoint(with: [.command, .control, .option]) else { return false }
            if !event.isARepeat { holdTemporaryHand() }
            return true
        }
        if [UInt16(36), UInt16(76)].contains(event.keyCode), flags.isDisjoint(with: [.command, .control, .option, .shift]),
           start == nil, tool.createsObjects, !tool.draws {
            placeAtVisibleCentre()
            return true
        }
        guard !flags.contains(.command), let command = keyCommand(for: event) else { return false }
        guard start == nil, toolState.pan == nil else { return true }
        switch command {
        case .tool(let next):
            guard next.isAvailable, fixedCanvasSize == nil else { return false }
            if next == .rectangle { toolState.shape = .rectangle }
            activateTool(next)
            NSAccessibility.post(element: self, notification: .announcementRequested,
                                 userInfo: [.announcement: next.title, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            return true
        case .zoom(let zoom):
            guard enclosingScrollView?.allowsMagnification == true else { return false }
            self.zoom(zoom)
            return true
        case .flip(let horizontal): flipSelection(horizontal: horizontal); return true
        case .layer: return false
        }
    }

    func performZoomKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        if event.charactersIgnoringModifiers == "/", event.modifierFlags.isDisjoint(with: [.control, .option]),
           let onQuickActions = toolState.onQuickActions {
            onQuickActions()
            return true
        }
        guard case .zoom(let command)? = keyCommand(for: event), enclosingScrollView?.allowsMagnification == true else { return false }
        zoom(command)
        return true
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == EaselKeyCommands.spaceKeyCode, toolState.spaceHeld { releaseTemporaryHand(); return }
        super.keyUp(with: event)
    }

    func holdTemporaryHand() {
        guard !toolState.spaceHeld else { return }
        toolState.spaceHeld = true
        hoveredObjectID = nil
        invalidateIncrementalDisplay()
        refreshPlacementPreview()
        refreshToolCursor()
    }

    func releaseTemporaryHand() {
        guard toolState.spaceHeld else { return }
        toolState.spaceHeld = false
        refreshPlacementPreview()
        refreshToolCursor()
    }

    func beginNavigationGesture(_ event: NSEvent) -> Bool {
        stopZoomAnimation()
        guard tool == .hand || toolState.spaceHeld, let clip = enclosingScrollView?.contentView else { return false }
        toolState.pan = (event.locationInWindow, clip.bounds.origin)
        hidePlacementPreview()
        refreshToolCursor()
        return true
    }

    func continueNavigationGesture(_ event: NSEvent) -> Bool {
        guard let pan = toolState.pan else { return false }
        guard let scroll = enclosingScrollView else { toolState.pan = nil; return true }
        let scale = max(scroll.magnification, 0.01)
        panCanvas(toVisibleOrigin: NSPoint(x: pan.origin.x - (event.locationInWindow.x - pan.window.x) / scale,
                                           y: pan.origin.y + (event.locationInWindow.y - pan.window.y) / scale))
        NSCursor.closedHand.set()
        return true
    }

    func finishNavigationGesture(_ event: NSEvent) -> Bool {
        guard toolState.pan != nil else { return false }
        toolState.pan = nil
        refreshPlacementPreview()
        refreshToolCursor()
        return true
    }

    func panCanvas(toVisibleOrigin origin: NSPoint) {
        guard let scroll = enclosingScrollView else { return }
        let clip = scroll.contentView
        let target = clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin
        guard target != clip.bounds.origin else { return }
        clip.scroll(to: target)
        scroll.reflectScrolledClipView(clip)
    }

    func panByKeyboard(dx: Double, dy: Double, fast: Bool) {
        guard let scroll = enclosingScrollView else { return }
        let distance = (fast ? 240.0 : 48.0) / max(Double(scroll.magnification), 0.01)
        let origin = scroll.contentView.bounds.origin
        panCanvas(toVisibleOrigin: NSPoint(x: origin.x + CGFloat(dx.sign == .minus ? -distance : dx == 0 ? 0 : distance),
                                           y: origin.y + CGFloat(dy.sign == .minus ? -distance : dy == 0 ? 0 : distance)))
    }

    func beginToolGesture(at point: NSPoint, event: NSEvent) -> Bool {
        if tool == .stamp { return beginStampPress(at: point, event: event) }
        guard tool.createsObjects, !tool.draws, tool.isAvailable else { return false }
        toolState.creation = EaselCanvasToolState.Creation(tool: tool, start: point, end: point, flags: event.modifierFlags)
        selection.removeAll()
        hidePlacementPreview()
        if tool.drawsConnector { beginConnectorCreation(tool.routing == .straight ? nil : tool.routing, at: point, flags: event.modifierFlags) }
        return true
    }

    func continueToolGesture(at point: NSPoint, event: NSEvent) -> Bool {
        if moveStampPress(to: point) { return true }
        guard let creation = toolState.creation else { return false }
        toolState.creation?.end = point
        if creation.tool.drawsConnector { updateConnectorCreation(to: point, event: event); return true }
        toolState.creation?.flags = event.modifierFlags
        if creation.tool == .table { tablePlacementMoved(from: creation.start, to: point); return true }
        refreshCreationDraft()
        autoscroll(with: event)
        return true
    }

    func refreshToolGesture(flags: NSEvent.ModifierFlags) {
        guard let creation = toolState.creation else { return }
        toolState.creation?.flags = flags
        if creation.tool.drawsConnector {
            guard connectors.travelled, case .create? = connectors.gesture else { return }
            let previousChrome = connectorChromeBounds()
            updateConnectorCreationPreview(to: creation.end, flags: flags)
            refreshConnectorChrome(from: previousChrome)
            invalidateIncrementalDisplay(layout: true)
            return
        }
        guard start != nil else { return }
        refreshCreationDraft()
    }

    func finishToolGesture(at point: NSPoint, event: NSEvent) -> Bool {
        if finishStampPress(at: point) { return true }
        guard var creation = toolState.creation else { return false }
        toolState.creation = nil
        creation.end = point
        creation.flags = event.modifierFlags
        if !creation.dragged, Self.travel(creation) * canvasScale > EaselToolGeometry.dragThreshold { creation.dragged = true }
        if creation.tool.drawsConnector { _ = finishConnectorCreation(at: point, event: event); return true }
        if !creation.dragged { objectMotion.intent = .appear }
        defer { objectMotion.intent = nil }
        let frame = creation.dragged && creation.tool != .sticky
            ? EaselToolGeometry.draggedFrame(from: EaselPoint(creation.start), to: EaselPoint(creation.end),
                                             square: creation.flags.contains(.shift), centered: creation.flags.contains(.option))
            : EaselToolGeometry.placedFrame(creation.tool, at: EaselPoint(creation.dragged ? creation.end : creation.start))
        if placeWithOwner(creation.tool, from: creation.start, to: creation.end, frame: frame, dragged: creation.dragged) != nil { return true }
        guard let item = createdItem(for: creation) else { return true }
        placeCreatedItem(item, tool: creation.tool)
        return true
    }

    func ownerPlacement(_ placing: EaselTool, from start: NSPoint, to end: NSPoint, frame: EaselRect, dragged: Bool) -> Bool? {
        switch placing {
        case .sticky: return insertSticky(at: dragged ? end : start)
        case .section:
            return dragged ? insertSection(frame: NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)) : insertSection(at: dragged ? end : start)
        case .rectangle: return nil
        case .ellipse: return nil
        case .text: return dragged ? insertText(at: NSPoint(x: frame.x, y: frame.y), width: frame.width) : insertText(at: dragged ? end : start)
        case .table: return placeTable(from: start, to: dragged ? end : nil)
        case .codeBlock: return placeCodeBlock(in: frame)
        case .stamp: return placeStamp(at: end)
        default: return nil
        }
    }

    private func placeWithOwner(_ placing: EaselTool, from start: NSPoint, to end: NSPoint, frame: EaselRect, dragged: Bool) -> Bool? {
        let returning = placing.returnsToSelect && tool == placing
        guard let placed = ownerPlacement(placing, from: start, to: end, frame: frame, dragged: dragged) else { return nil }
        if placed, returning, tool == placing { tool = .select }
        return placed
    }

    private static func travel(_ creation: EaselCanvasToolState.Creation) -> Double {
        Double(hypot(creation.end.x - creation.start.x, creation.end.y - creation.start.y))
    }

    private func refreshCreationDraft() {
        guard let creation = toolState.creation else { return }
        if !creation.dragged {
            guard Self.travel(creation) * canvasScale > EaselToolGeometry.dragThreshold else { return }
            toolState.creation?.dragged = true
        }
        guard let current = toolState.creation else { return }
        draft = createdItem(for: current).map { [$0] }
        invalidateIncrementalDisplay(layout: true)
    }

    func createdItem(for creation: EaselCanvasToolState.Creation) -> EaselItem? {
        let tool = creation.tool
        if tool.drawsConnector {
            let end = creation.flags.contains(.shift)
                ? EaselToolGeometry.snappedLineEnd(from: EaselPoint(creation.start), to: EaselPoint(creation.end))
                : EaselPoint(creation.end)
            return connectorItem(tool, from: creation.start, to: NSPoint(x: end.x, y: end.y), id: creation.id)
        }
        guard creation.dragged, tool != .sticky else {
            return placedItem(tool, frame: EaselToolGeometry.placedFrame(tool, at: EaselPoint(creation.dragged ? creation.end : creation.start)),
                              id: creation.id)
        }
        var frame = EaselToolGeometry.draggedFrame(from: EaselPoint(creation.start), to: EaselPoint(creation.end),
                                                   square: creation.flags.contains(.shift), centered: creation.flags.contains(.option))
        if tool == .text { frame.width = max(40, frame.width); frame.height = tool.defaultSize.height }
        return placedItem(tool, frame: frame, id: creation.id)
    }

    func placedItem(_ tool: EaselTool, frame proposed: EaselRect, id: UUID) -> EaselItem? {
        switch tool {
        case .table: return nil
        case .stamp: return nil
        case .codeBlock: return codeBlockItem(frame: proposed, id: id)
        default: break
        }
        guard let kind = tool.kind, tool.placesObjects else { return nil }
        let highest = session.document.items.map(\.zIndex).max() ?? 0
        var item = EaselItem(id: id, kind: kind, frame: constrainedToCanvas(proposed), zIndex: highest < Int.max ? highest + 1 : highest,
                             color: insertionColor)
        if tool == .text { item.text = EaselTextEditing.defaultText }
        if tool == .rectangle, toolState.shape != .rectangle { item.shape = toolState.shape }
        return item
    }

    func connectorItem(_ tool: EaselTool, from start: NSPoint, to end: NSPoint, id: UUID) -> EaselItem {
        let first = snappedConnectorEnd(constrainedToCanvas(start), flags: [], other: nil, excluding: nil)
        let last = snappedConnectorEnd(constrainedToCanvas(end), flags: [], other: first.point, excluding: first.connection?.itemID)
        connectors.magnet = nil
        let highest = session.document.items.map(\.zIndex).max() ?? 0
        let lookup = connectorLookup()
        var item = EaselConnectorRouter.make(from: first.point, to: last.point, style: Self.connectorStyle(for: session.document.id),
                                             routing: tool.routing == .straight ? nil : tool.routing,
                                             startConnection: first.connection, endConnection: last.connection,
                                             zIndex: highest < Int.max ? highest + 1 : highest) { lookup[$0] }
        item.id = id
        stampNewConnectorStyle(on: &item)
        return item
    }

    private func constrainedToCanvas(_ frame: EaselRect) -> EaselRect {
        if let size = fixedCanvasSize {
            return EaselToolGeometry.constrained(frame, to: EaselRect(x: 0, y: 0, width: Double(size.width), height: Double(size.height)))
        }
        return EaselRect(x: max(0, frame.x), y: max(0, frame.y), width: max(1, frame.width), height: max(1, frame.height))
    }

    private func constrainedToCanvas(_ point: NSPoint) -> NSPoint {
        if let size = fixedCanvasSize {
            let clamped = EaselToolGeometry.clamped(EaselPoint(point), to: EaselRect(x: 0, y: 0, width: Double(size.width), height: Double(size.height)))
            return NSPoint(x: clamped.x, y: clamped.y)
        }
        return NSPoint(x: max(0, point.x), y: max(0, point.y))
    }

    private func placementName(_ placing: EaselTool, item: EaselItem) -> String {
        if placing == .rectangle, let shape = item.shape { return EaselShapeGeometry.displayName(shape).lowercased() }
        return placing.title.lowercased()
    }

    @discardableResult
    func placeCreatedItem(_ item: EaselItem, tool placing: EaselTool) -> Bool {
        let name = placementName(placing, item: item)
        guard commit("Add \(name)", { $0.items.append(item) }) else { return false }
        if placing.returnsToSelect, tool == placing { tool = .select }
        selection = [item.id]
        window?.makeFirstResponder(self)
        if item.kind == .text, let saved = session.document.items.first(where: { $0.id == item.id }) { beginEditing(saved) }
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: "Added \(name)", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        return true
    }

    @discardableResult
    func place(_ placing: EaselTool, at point: NSPoint) -> Bool {
        guard placing.isAvailable, placing.createsObjects, !placing.draws, !session.isClosed else { return false }
        cancelPointerInteraction()
        guard finishEditing() else { return false }
        objectMotion.intent = .appear
        defer { objectMotion.intent = nil }
        if let placed = placeWithOwner(placing, from: point, to: point,
                                       frame: EaselToolGeometry.placedFrame(placing, at: EaselPoint(point)), dragged: false) {
            return placed
        }
        if placing.drawsConnector {
            let half = CGFloat(placing.defaultSize.width / 2)
            return placeCreatedItem(connectorItem(placing, from: NSPoint(x: point.x - half, y: point.y),
                                                  to: NSPoint(x: point.x + half, y: point.y), id: UUID()), tool: placing)
        }
        guard let item = placedItem(placing, frame: EaselToolGeometry.placedFrame(placing, at: EaselPoint(point)), id: UUID()) else { return false }
        return placeCreatedItem(item, tool: placing)
    }

    func placeAtVisibleCentre() {
        let visible = uncoveredVisibleRect
        place(tool, at: NSPoint(x: visible.midX, y: visible.midY))
    }

    var uncoveredVisibleRect: NSRect {
        let visible = visibleRect.isEmpty ? bounds : visibleRect
        let shown = EaselFloatingBar.uncovered(EaselRect(x: Double(visible.minX), y: Double(visible.minY), width: Double(visible.width),
                                                         height: Double(visible.height)),
                                               coveredBottom: Double(toolState.coveredBottom), magnification: magnification)
        return NSRect(x: shown.x, y: shown.y, width: shown.width, height: shown.height)
    }

    func setCoveredBottom(_ value: CGFloat) {
        guard fixedCanvasSize == nil, value != toolState.coveredBottom else { return }
        toolState.coveredBottom = value
    }

    func previewPlacement(_ dragged: EaselTool?, atWindowPoint point: NSPoint?) {
        toolState.previewTool = dragged
        toolState.previewPoint = point.map { convert($0, from: nil) }
        refreshPlacementPreview()
    }

    @discardableResult
    func placeTool(_ placing: EaselTool, atWindowPoint point: NSPoint) -> Bool {
        toolState.previewTool = nil
        let local = convert(point, from: nil)
        guard uncoveredVisibleRect.contains(local) else { refreshPlacementPreview(); return false }
        return place(placing, at: local)
    }

    func updatePlacementPreview(at point: NSPoint?) {
        toolState.previewPoint = point
        refreshPlacementPreview()
        connectorToolHover(at: tool.drawsConnector && start == nil ? point : nil)
    }

    func hidePlacementPreview() {
        guard let view = toolState.previewView, !view.isHidden else { return }
        view.isHidden = true
    }

    func refreshPlacementPreview() {
        let previewing = toolState.previewTool ?? tool
        let armed = toolState.previewTool != nil || (start == nil && toolState.pan == nil && !toolState.spaceHeld)
        guard armed, previewing.placesObjects, previewing != .text, previewing.isAvailable, let point = toolState.previewPoint,
              let item = placedItem(previewing, frame: EaselToolGeometry.placedFrame(previewing, at: EaselPoint(point)), id: toolState.previewID)
        else { hidePlacementPreview(); return }
        let view: EaselToolPreviewView
        if let existing = toolState.previewView { view = existing } else {
            view = EaselToolPreviewView(frame: .zero)
            toolState.previewView = view
        }
        if view.superview !== self { addSubview(view, positioned: .above, relativeTo: nil) }
        let scale = CGFloat(canvasScale)
        let pad = 3 / scale
        view.configure(item: item, scale: scale)
        view.frame = NSRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height).insetBy(dx: -pad, dy: -pad)
        if view.isHidden {
            view.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
            view.isHidden = false
            if view.alphaValue == 0 {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.12
                    view.animator().alphaValue = 1
                }
            }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command), event.modifierFlags.isDisjoint(with: [.control, .option]),
              let scroll = enclosingScrollView, scroll.allowsMagnification, !motion.isInteracting else {
            super.scrollWheel(with: event)
            return
        }
        let raw = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        let factor = EaselZoom.wheelFactor(deviceDelta: Double(raw), precise: event.hasPreciseScrollingDeltas)
        guard factor != 1 else { return }
        stopZoomAnimation()
        applyZoom(Double(scroll.magnification) * factor, anchor: convert(event.locationInWindow, from: nil))
    }

    var magnification: Double { Double(enclosingScrollView?.magnification ?? 1) }

    func zoomMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] {
        guard enclosingScrollView?.allowsMagnification == true else { return [] }
        switch context.target {
        case .canvas:
            return [EaselMenuRow(id: "zoom-fit", title: EaselZoomCommand.fit.title, symbol: "viewfinder",
                                 shortcut: EaselZoomCommand.fit.shortcut, isEnabled: !session.document.items.isEmpty,
                                 perform: guardedMenuAction { $0.zoom(.fit) })]
        case .object, .objects:
            return [EaselMenuRow(id: "zoom-selection", title: EaselZoomCommand.selection.title, symbol: "scope",
                                 shortcut: EaselZoomCommand.selection.shortcut, perform: guardedMenuAction { $0.zoom(.selection) })]
        }
    }

    var canZoomToSelection: Bool { !selection.isEmpty }

    func zoom(_ command: EaselZoomCommand) {
        guard let scroll = enclosingScrollView, scroll.allowsMagnification, !motion.isInteracting, !session.isClosed else { return }
        let visible = scroll.contentView.bounds
        let centre = toolState.zoomTarget?.centre ?? NSPoint(x: visible.midX, y: visible.midY)
        let current = toolState.zoomTarget?.magnification ?? Double(scroll.magnification)
        switch command {
        case .zoomIn, .zoomOut:
            animateZoom(to: EaselZoom.stepped(from: current, zoomingIn: command == .zoomIn,
                                              minimum: Double(scroll.minMagnification), maximum: Double(scroll.maxMagnification)), centre: centre)
        case .actualSize:
            animateZoom(to: 1, centre: centre)
        case .fit:
            zoomToFit()
        case .selection:
            zoomToContent(selectedOnly: true, maximum: nil, animated: true)
        }
    }

    func zoom(toMagnification value: Double) {
        guard let scroll = enclosingScrollView, scroll.allowsMagnification, value.isFinite, value > 0 else { return }
        let visible = scroll.contentView.bounds
        animateZoom(to: value, centre: toolState.zoomTarget?.centre ?? NSPoint(x: visible.midX, y: visible.midY))
    }

    func zoomToFit(maximum: Double? = nil, animated: Bool = true) {
        guard !zoomToContent(selectedOnly: false, maximum: maximum, animated: animated), let scroll = enclosingScrollView else { return }
        animateZoom(to: 1, centre: NSPoint(x: scroll.contentSize.width / 2, y: scroll.contentSize.height / 2), animated: animated)
    }

    @discardableResult
    func zoomToContent(selectedOnly: Bool, maximum: Double?, animated: Bool) -> Bool {
        guard let scroll = enclosingScrollView else { return false }
        let frames = session.document.items.filter { !selectedOnly || selection.contains($0.id) }.map(\.frame)
        let covered = Double(toolState.coveredBottom), height = Double(scroll.contentSize.height)
        guard let bounds = EaselZoom.bounds(of: frames),
              let value = EaselZoom.fitting(bounds, viewport: EaselFloatingBar.viewport(width: Double(scroll.contentSize.width),
                                                                                       height: height, coveredBottom: covered),
                                            minimum: Double(scroll.minMagnification),
                                            maximum: min(Double(scroll.maxMagnification), maximum ?? .greatestFiniteMagnitude))
        else { return false }
        let target = EaselZoom.clamped(value, minimum: Double(scroll.minMagnification), maximum: Double(scroll.maxMagnification))
        let centre = EaselFloatingBar.clipCentre(showing: EaselPoint(x: bounds.x + bounds.width / 2, y: bounds.y + bounds.height / 2),
                                                 coveredBottom: covered, viewportHeight: height, magnification: target)
        animateZoom(to: value, centre: NSPoint(x: centre.x, y: centre.y), animated: animated)
        return true
    }

    var contentIsOutOfView: Bool {
        guard let scroll = enclosingScrollView, let bounds = EaselZoom.bounds(of: session.document.items.map(\.frame)) else { return false }
        let clip = scroll.contentView.bounds
        let shown = EaselFloatingBar.uncovered(EaselRect(x: Double(clip.minX), y: Double(clip.minY), width: Double(clip.width),
                                                         height: Double(clip.height)),
                                               coveredBottom: Double(toolState.coveredBottom), magnification: Double(scroll.magnification))
        let visible = NSRect(x: shown.x, y: shown.y, width: shown.width, height: shown.height)
        let margin = 0.5 * min(visible.width, visible.height)
        return !visible.insetBy(dx: -margin, dy: -margin).intersects(NSRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height))
    }

    func fitOnOpenIfNeeded() {
        guard !toolState.openFitDone, fixedCanvasSize == nil, let scroll = enclosingScrollView else { return }
        let viewport = scroll.contentSize
        guard viewport.width > 80, viewport.height > 80 else { return }
        toolState.openFitDone = true
        let room = EaselFloatingBar.viewport(width: Double(viewport.width), height: Double(viewport.height),
                                             coveredBottom: Double(toolState.coveredBottom))
        guard let bounds = EaselZoom.bounds(of: session.document.items.map(\.frame)),
              bounds.x + bounds.width > room.width || bounds.y + bounds.height > room.height else { return }
        zoomToContent(selectedOnly: false, maximum: 1, animated: false)
    }

    func animateZoom(to value: Double, centre: NSPoint, animated: Bool = true) {
        guard let scroll = enclosingScrollView else { return }
        let target = EaselZoom.clamped(value, minimum: Double(scroll.minMagnification), maximum: Double(scroll.maxMagnification))
        let visible = scroll.contentView.bounds
        let from = (magnification: Double(scroll.magnification), centre: NSPoint(x: visible.midX, y: visible.midY))
        stopZoomAnimation()
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, window != nil, !isHiddenOrHasHiddenAncestor else {
            applyZoom(target, centre: centre)
            return
        }
        toolState.zoomTarget = (target, centre)
        let started = CACurrentMediaTime()
        let driver = EaselCanvasFrameDriver { [weak self, weak scroll] in
            guard let self, let scroll, self.enclosingScrollView === scroll, self.window != nil, !self.motion.isInteracting else {
                self?.toolState.zoomTarget = nil
                return false
            }
            let progress = min(1, (CACurrentMediaTime() - started) / EaselZoom.animationDuration)
            let eased = EaselZoom.eased(progress)
            let value = EaselZoom.interpolated(from: from.magnification, to: target, progress: eased)
            let point = NSPoint(x: from.centre.x + (centre.x - from.centre.x) * eased, y: from.centre.y + (centre.y - from.centre.y) * eased)
            self.applyZoom(value, centre: point)
            if progress >= 1 { self.toolState.zoomTarget = nil; return false }
            return true
        }
        toolState.zoomDriver = driver
        driver.start(in: self)
    }

    func stopZoomAnimation() {
        toolState.zoomDriver?.stop()
        toolState.zoomDriver = nil
        toolState.zoomTarget = nil
    }

    func applyZoom(_ value: Double, centre: NSPoint) {
        guard let scroll = enclosingScrollView else { return }
        let next = CGFloat(EaselZoom.clamped(value, minimum: Double(scroll.minMagnification), maximum: Double(scroll.maxMagnification)))
        if abs(scroll.magnification - next) > 0.0001 { scroll.magnification = next }
        resizeCanvas(viewport: scroll.contentSize)
        let size = scroll.contentView.bounds.size
        panCanvas(toVisibleOrigin: NSPoint(x: centre.x - size.width / 2, y: centre.y - size.height / 2))
        zoomDidChange()
    }

    func applyZoom(_ value: Double, anchor: NSPoint) {
        guard let scroll = enclosingScrollView else { return }
        let clip = scroll.contentView
        let before = scroll.magnification
        let origin = clip.bounds.origin
        let next = CGFloat(EaselZoom.clamped(value, minimum: Double(scroll.minMagnification), maximum: Double(scroll.maxMagnification)))
        if abs(before - next) > 0.0001 { scroll.magnification = next }
        resizeCanvas(viewport: scroll.contentSize)
        let target = EaselZoom.anchoredOrigin(anchor: EaselPoint(anchor), visibleOrigin: EaselPoint(origin), before: Double(before), after: Double(next))
        panCanvas(toVisibleOrigin: NSPoint(x: target.x, y: target.y))
        zoomDidChange()
    }

    private func zoomDidChange() {
        refreshTextControls()
        invalidateIncrementalDisplay(layout: true)
        refreshPlacementPreview()
        window?.invalidateCursorRects(for: self)
        imageZoomChanged()
    }
}

@MainActor
final class EaselCanvasFrameDriver: NSObject {
    private let onFrame: () -> Bool
    private var link: AnyObject?
    private var timer: Timer?

    init(onFrame: @escaping () -> Bool) {
        self.onFrame = onFrame
        super.init()
    }

    func start(in view: NSView) {
        guard link == nil, timer == nil else { return }
        if #available(macOS 14.0, *) {
            let link = view.displayLink(target: self, selector: #selector(displayFrame(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        } else {
            let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.frame() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func stop() {
        if #available(macOS 14.0, *) { (link as? CADisplayLink)?.invalidate() }
        link = nil
        timer?.invalidate()
        timer = nil
    }

    @available(macOS 14.0, *)
    @objc private func displayFrame(_ link: CADisplayLink) { frame() }

    private func frame() {
        if !onFrame() { stop() }
    }
}

@MainActor
final class EaselToolPreviewView: NSView {
    private var item: EaselItem?
    private var scale: CGFloat = 1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(item: EaselItem, scale: CGFloat) {
        guard self.item != item || self.scale != scale else { return }
        self.item = item
        self.scale = max(scale, 0.01)
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let item else { return }
        let line = 1.5 / scale
        let shape = NSRect(x: 3 / scale, y: 3 / scale, width: max(1, bounds.width - 6 / scale), height: max(1, bounds.height - 6 / scale))
        let path: NSBezierPath
        switch item.kind {
        case .circle: path = NSBezierPath(ovalIn: shape)
        case .sticky: path = NSBezierPath(roundedRect: shape, xRadius: 4, yRadius: 4)
        case .section: path = NSBezierPath(roundedRect: shape, xRadius: 12, yRadius: 12)
        default: path = NSBezierPath(roundedRect: shape, xRadius: 5, yRadius: 5)
        }
        EaselAppearance.selection.withAlphaComponent(0.1).setFill()
        path.fill()
        EaselAppearance.selection.withAlphaComponent(0.7).setStroke()
        path.lineWidth = line
        path.setLineDash([6 / scale, 4 / scale], count: 2, phase: 0)
        path.stroke()
    }
}

@MainActor
enum EaselToolCursors {
    static let pen: NSCursor = {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let symbol = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 16, weight: .semibold)) else { return false }
            let glyph = symbol.size
            let box = NSRect(x: 1.5, y: 1.5, width: glyph.width, height: glyph.height)
            func tinted(_ color: NSColor) -> NSImage {
                NSImage(size: glyph, flipped: false) { rect in
                    symbol.draw(in: rect)
                    color.setFill()
                    rect.fill(using: .sourceAtop)
                    return true
                }
            }
            let halo = tinted(.white), ink = tinted(.black)
            for (dx, dy) in [(-1.0, 0.0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)] {
                halo.draw(in: box.offsetBy(dx: dx, dy: dy))
            }
            ink.draw(in: box)
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 2, y: 22))
    }()
}
