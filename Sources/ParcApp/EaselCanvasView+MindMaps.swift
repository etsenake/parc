import AppKit

enum EaselMindMapControl: Equatable {
    case add(EaselMindMapLink.Side)
    case collapse
    case expand
}

@MainActor
final class EaselMindMapCanvasState {
    var hover: (id: UUID, control: EaselMindMapControl)?
    var hoverNode: UUID?
    var drop: (id: UUID, drop: EaselMindMapDrop)?
    var dropRect = NSRect.null
}

extension EaselCanvasView {
    static let mindMapButtonOffset: CGFloat = 18

    func isMindMapNode(_ id: UUID) -> Bool {
        session.document.items.contains { $0.id == id && EaselMindMap.isNode($0) }
    }

    private var mindMapsWritable: Bool { fixedCanvasSize == nil && !session.isClosed && !session.isDeleted }

    private func mindMapText(_ text: String, size: EaselTextStyle.Size, zIndex: Int) -> EaselItem {
        var item = EaselItem(kind: .text, frame: EaselRect(x: 0, y: 0, width: 280, height: 28), zIndex: zIndex, text: text, color: insertionColor)
        item.textStyle = EaselTextStyle(size: size, autoWidth: true)
        item.frame = fittedTextFrame(item)
        return item
    }

    private func focusMindMapNode(_ id: UUID, editing: Bool) {
        selection = [id]
        window?.makeFirstResponder(self)
        guard let stored = session.document.items.first(where: { $0.id == id }) else { return }
        scrollToVisible(rect(stored))
        if editing { beginEditing(stored) }
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    @discardableResult
    func insertMindMap(at point: NSPoint? = nil) -> Bool {
        guard mindMapsWritable else { return false }
        cancelPointerInteraction(); guard finishEditing() else { return false }; drawing = false
        let top = session.document.items.map(\.zIndex).max() ?? 0
        guard top < Int.max - 8 else { return false }
        var root = mindMapText(EaselMindMap.rootText, size: .h2, zIndex: top + 1)
        if let point {
            root.frame.x = max(0, Double(point.x) - root.frame.width / 2)
            root.frame.y = max(0, Double(point.y) - root.frame.height / 2)
        } else {
            root.frame.x = max(30, (Double(visibleRect.midX) - root.frame.width - EaselMindMap.rootGap).rounded())
            root.frame.y = max(30, (Double(visibleRect.midY) - root.frame.height / 2).rounded())
        }
        let kids = EaselMindMap.starterTexts.enumerated().map { mindMapText($1, size: .body, zIndex: top + 2 + $0) }
        guard let next = EaselMindMap.creatingMap(root: root, children: kids, in: session.document),
              growingMindMap(from: kids.map { _ in root.id }, kids.map(\.id), { commit("Add mind map", { $0 = next }) }) else { return false }
        focusMindMapNode(root.id, editing: true)
        return true
    }

    @discardableResult
    func startMindMap(from id: UUID) -> Bool {
        guard mindMapsWritable, let source = session.document.items.first(where: { $0.id == id }), EaselMindMap.canStart(from: source) else { return false }
        cancelPointerInteraction(); guard finishEditing(removingEmpty: false) else { return false }
        guard let root = session.document.items.first(where: { $0.id == id }), EaselMindMap.canStart(from: root) else { return false }
        let top = session.document.items.map(\.zIndex).max() ?? 0
        guard top < Int.max - 8 else { return false }
        let kids = EaselMindMap.starterTexts.enumerated().map { mindMapText($1, size: .body, zIndex: top + 1 + $0) }
        guard let next = EaselMindMap.creatingMap(root: root, children: kids, in: session.document),
              growingMindMap(from: kids.map { _ in root.id }, kids.map(\.id), { commit("Make mind map", { $0 = next }) }) else { return false }
        focusMindMapNode(kids[0].id, editing: true)
        return true
    }

    @discardableResult
    func addMindMapNode(to id: UUID, side: EaselMindMapLink.Side? = nil, sibling: Bool = false) -> Bool {
        guard mindMapsWritable, editor?.hasMarkedText() != true else { return false }
        let before = EaselMindMap.tree(of: session.document.items)
        guard let node = before.nodes[id], !sibling || node.parent != nil else { return false }
        let slot = node.parent.flatMap { parent in
            before.children(of: parent, side: node.side).firstIndex(of: id).map { (parent: parent, index: $0) }
        }
        cancelPointerInteraction(); guard finishEditing() else { return false }
        let document = session.document
        let present = document.items.contains { $0.id == id }
        let parentID: UUID
        let index: Int?
        if present, !sibling {
            parentID = id
            index = nil
        } else if let slot {
            parentID = slot.parent
            index = present ? slot.index + 1 : slot.index
        } else { return false }
        let wantedSide = parentID == id ? side : node.side
        let top = document.items.map(\.zIndex).max() ?? 0
        guard top < Int.max - 4, var template = EaselMindMap.template(forChildOf: parentID, side: wantedSide, in: document) else { return false }
        template.zIndex = top + 1
        if template.kind == .text { template.frame = fittedTextFrame(template) }
        if template.kind == .sticky { template.frame.height = min(template.frame.height, EaselBoardObjects.stickyMinimumHeight(template)) }
        guard let next = EaselMindMap.adding(template, to: parentID, side: wantedSide, at: index, in: document),
              growingMindMap(from: [parentID], [template.id], { commit(sibling ? "Add sibling" : "Add child", { $0 = next }) }) else { return false }
        focusMindMapNode(template.id, editing: true)
        return true
    }

    @discardableResult
    func reparentMindMapNode(_ id: UUID, outdent: Bool) -> Bool {
        guard mindMapsWritable, isMindMapNode(id), editor?.hasMarkedText() != true else { return false }
        let editing = editingID == id
        let caret = editing ? editor?.selectedRange() : nil
        guard (outdent ? EaselMindMap.outdenting(id, in: session.document) : EaselMindMap.indenting(id, in: session.document)) != nil else { return false }
        cancelPointerInteraction(); guard finishEditing(removingEmpty: false) else { return false }
        let document = session.document
        guard let next = outdent ? EaselMindMap.outdenting(id, in: document) : EaselMindMap.indenting(id, in: document),
              commit(outdent ? "Move topic out" : "Move topic in", { $0 = next }) else { return false }
        focusMindMapNode(id, editing: editing)
        if let caret, let text = editor, editingID == id {
            let length = (text.string as NSString).length, start = min(caret.location, length)
            text.setSelectedRange(NSRange(location: start, length: min(caret.length, length - start)))
        }
        return true
    }

    @discardableResult
    func setMindMapCollapsed(_ collapsed: Bool, ids: Set<UUID>) -> Bool {
        guard mindMapsWritable else { return false }
        cancelPointerInteraction(); guard finishEditing() else { return false }
        let before = session.document
        guard let next = EaselMindMap.settingCollapsed(collapsed, ids, in: session.document),
              commit(collapsed ? "Collapse branch" : "Expand branch", { $0 = next }) else { return false }
        foldMindMap(from: before, toward: ids)
        if collapsed { selection.subtract(EaselBoardObjects.hiddenIDs(in: session.document.items)) }
        NSAccessibility.post(element: self, notification: .layoutChanged)
        return true
    }

    var mindMapKeyTarget: UUID? {
        let id = editingID ?? (selection.count == 1 ? selection.first : nil)
        guard let id, let item = session.document.items.first(where: { $0.id == id }), EaselMindMap.isNode(item), !item.isLocked else { return nil }
        return id
    }

    func performMindMapChord(_ command: EaselChordCommand) -> Bool {
        guard window?.isKeyWindow == true, start == nil, editor?.hasMarkedText() != true, let id = mindMapKeyTarget else { return false }
        switch command {
        case .quickCreate: _ = addMindMapNode(to: id)
        case .mindMapSibling:
            guard EaselMindMap.tree(of: session.document.items).nodes[id]?.parent != nil else { _ = addMindMapNode(to: id); return true }
            _ = addMindMapNode(to: id, sibling: true)
        default: return false
        }
        return true
    }

    func performMindMapTab(backward: Bool) -> Bool {
        guard start == nil, let id = mindMapKeyTarget else { return false }
        if !reparentMindMapNode(id, outdent: backward) { NSSound.beep() }
        return true
    }

    func mindMapTextCommand(_ textView: NSTextView, _ selector: Selector) -> Bool {
        guard textView === editor, let id = editingID, isMindMapNode(id) else { return false }
        switch selector {
        case #selector(NSResponder.insertTab(_:)): return performMindMapTab(backward: false)
        case #selector(NSResponder.insertBacktab(_:)): return performMindMapTab(backward: true)
        default: return false
        }
    }

    func mindMapControls(pressing: Bool = false) -> [(id: UUID, control: EaselMindMapControl, point: NSPoint)] {
        guard fixedCanvasSize == nil, !drawing, marqueeRect == nil, !hidesPassiveAnnotations, start == nil || pressing,
              connectors.gesture == nil, tool == .select else { return [] }
        let shown = items
        guard shown.contains(where: { $0.mindMap != nil }) else { return [] }
        let tree = EaselMindMap.tree(of: session.document.items)
        var result: [(id: UUID, control: EaselMindMapControl, point: NSPoint)] = []
        let step = 24 / CGFloat(canvasScale)
        for item in shown {
            guard let node = tree.nodes[item.id] else { continue }
            if node.collapsed {
                result.append((item.id, .expand, mindMapButtonPoint(for: item, side: node.side)))
                continue
            }
            guard editor == nil, displayedSelection == [item.id] || (item.id == mindMaps.hoverNode && !toolOwnsPointer),
                  !item.isLocked else { continue }
            for side in EaselMindMap.childSides(of: item.id, in: tree) {
                let point = mindMapButtonPoint(for: item, side: side)
                result.append((item.id, .add(side), point))
                if EaselMindMap.canCollapse(item.id, in: tree), side == node.side {
                    result.append((item.id, .collapse, NSPoint(x: point.x, y: point.y + step)))
                }
            }
        }
        return result
    }

    private func mindMapButtonPoint(for item: EaselItem, side: EaselMindMapLink.Side) -> NSPoint {
        let bounds = EaselShapeGeometry.visualBounds(of: item)
        let offset = Self.mindMapButtonOffset / CGFloat(canvasScale)
        let y = CGFloat(bounds.y + bounds.height / 2)
        return side == .right ? NSPoint(x: CGFloat(bounds.x + bounds.width) + offset, y: y) : NSPoint(x: CGFloat(bounds.x) - offset, y: y)
    }

    private func mindMapControlRadius(_ control: EaselMindMapControl) -> CGFloat {
        (control == .expand ? 13 : 11) / CGFloat(canvasScale)
    }

    func mindMapControl(at point: NSPoint, pressing: Bool = false) -> (id: UUID, control: EaselMindMapControl)? {
        mindMapControl(at: point, in: mindMapControls(pressing: pressing))
    }

    private func mindMapControl(at point: NSPoint, in controls: [(id: UUID, control: EaselMindMapControl, point: NSPoint)])
        -> (id: UUID, control: EaselMindMapControl)? {
        controls.last { hypot($0.point.x - point.x, $0.point.y - point.y) <= mindMapControlRadius($0.control) }.map { ($0.id, $0.control) }
    }

    func mindMapControlPress(at point: NSPoint) -> Bool {
        guard let hit = mindMapControl(at: point, pressing: true) else { clearMindMapHover(); return false }
        mindMaps.hover = nil
        switch hit.control {
        case .add(let side): addMindMapNode(to: hit.id, side: side)
        case .collapse: setMindMapCollapsed(true, ids: [hit.id])
        case .expand: setMindMapCollapsed(false, ids: [hit.id])
        }
        return true
    }

    func mindMapChromeBounds(pressing: Bool = false) -> NSRect {
        mindMapChromeBounds(of: mindMapControls(pressing: pressing))
    }

    private func mindMapChromeBounds(of controls: [(id: UUID, control: EaselMindMapControl, point: NSPoint)]) -> NSRect {
        let pad = 26 / max(CGFloat(canvasScale), 0.2)
        return controls.reduce(NSRect.null) { $0.union(NSRect(x: $1.point.x - pad, y: $1.point.y - pad, width: pad * 2, height: pad * 2)) }
    }

    private func mindMapHoverTarget(at point: NSPoint, controls: [(id: UUID, control: EaselMindMapControl, point: NSPoint)]) -> UUID? {
        guard !toolOwnsPointer, start == nil, editor == nil, !session.isClosed, connectors.gesture == nil,
              objectMotion.hoveredHandle == nil else { return nil }
        if let hit = mindMapControl(at: point, in: controls), hit.control != .expand { return hit.id }
        if let id = hoveredObjectID { return isMindMapNode(id) ? id : nil }
        guard let current = mindMaps.hoverNode, let item = items.first(where: { $0.id == current }) else { return nil }
        let reach = (Self.mindMapButtonOffset + 12) / CGFloat(canvasScale)
        let bounds = EaselShapeGeometry.visualBounds(of: item)
        return NSRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height).insetBy(dx: -reach, dy: -reach).contains(point) ? current : nil
    }

    func updateMindMapHover(at point: NSPoint) {
        let controls = mindMapControls()
        let node = mindMapHoverTarget(at: point, controls: controls)
        let nodeChanged = node != mindMaps.hoverNode
        let previous = nodeChanged ? mindMapChromeBounds(of: controls) : .null
        mindMaps.hoverNode = node
        let next = start == nil && editor == nil ? mindMapControl(at: point, in: nodeChanged ? mindMapControls() : controls) : nil
        guard nodeChanged || next?.id != mindMaps.hover?.id || next?.control != mindMaps.hover?.control else { return }
        mindMaps.hover = next
        refreshMindMapChrome(from: previous)
        if nodeChanged { window?.invalidateCursorRects(for: self) }
    }

    func clearMindMapHover() {
        guard mindMaps.hoverNode != nil || mindMaps.hover != nil else { return }
        let previous = mindMapChromeBounds(pressing: true)
        mindMaps.hoverNode = nil
        mindMaps.hover = nil
        refreshMindMapChrome(from: previous)
        window?.invalidateCursorRects(for: self)
    }

    func refreshMindMapChrome(from previous: NSRect = .null) {
        let dirty = mindMapChromeBounds().union(previous)
        guard !dirty.isNull else { return }
        if usesObjectSurfaces { refreshDecorations() } else { setNeedsDisplay(dirty) }
    }

    func addMindMapCursorRects() {
        for entry in mindMapControls() {
            let radius = mindMapControlRadius(entry.control)
            addCursorRect(NSRect(x: entry.point.x - radius, y: entry.point.y - radius, width: radius * 2, height: radius * 2), cursor: .pointingHand)
        }
    }

    func drawMindMapChrome(in dirtyRect: NSRect) {
        drawMindMapFolds(in: dirtyRect)
        let scale = CGFloat(canvasScale)
        drawMindMapDrop(scale: scale)
        let controls = mindMapControls()
        guard !controls.isEmpty else { return }
        let tree = EaselMindMap.tree(of: session.document.items)
        for entry in controls {
            let reach = 30 / scale
            guard NSRect(x: entry.point.x - reach, y: entry.point.y - reach, width: reach * 2, height: reach * 2).intersects(dirtyRect) else { continue }
            let hovered = mindMaps.hover.map { $0.id == entry.id && $0.control == entry.control } == true
            switch entry.control {
            case .add: drawQuickCreateDot(at: entry.point, hovered: hovered, scale: scale)
            case .collapse: drawMindMapCollapseDot(at: entry.point, hovered: hovered, scale: scale)
            case .expand: drawMindMapCountChip(EaselMindMap.hiddenCount(of: entry.id, in: tree), at: entry.point, hovered: hovered, scale: scale)
            }
        }
    }

    private func drawMindMapCollapseDot(at point: NSPoint, hovered: Bool, scale: CGFloat) {
        let radius = (hovered ? 8 : 6) / scale
        let disc = NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        disc.lineWidth = 1.5 / scale
        (hovered ? EaselAppearance.selection : EaselAppearance.surface).setFill(); disc.fill()
        EaselAppearance.selection.setStroke(); disc.stroke()
        let arm = (hovered ? 3.5 : 2.5) / scale
        let bar = NSBezierPath()
        bar.move(to: NSPoint(x: point.x - arm, y: point.y)); bar.line(to: NSPoint(x: point.x + arm, y: point.y))
        bar.lineWidth = 1.5 / scale; bar.lineCapStyle = .round
        (hovered ? EaselAppearance.surface : EaselAppearance.selection).setStroke(); bar.stroke()
    }

    private func drawMindMapCountChip(_ count: Int, at point: NSPoint, hovered: Bool, scale: CGFloat) {
        let label = NSAttributedString(string: count > 99 ? "99+" : "\(count)", attributes: [
            .font: NoteTheme.nunitoBold(11 / scale), .foregroundColor: hovered ? EaselAppearance.surface : EaselAppearance.selection,
        ])
        let size = label.size()
        let height = 18 / scale, width = max(height, size.width + 10 / scale)
        let chip = NSRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
        let path = NSBezierPath(roundedRect: chip, xRadius: height / 2, yRadius: height / 2)
        path.lineWidth = 1.5 / scale
        (hovered ? EaselAppearance.selection : EaselAppearance.surface).setFill(); path.fill()
        EaselAppearance.selection.setStroke(); path.stroke()
        label.draw(at: NSPoint(x: chip.midX - size.width / 2, y: chip.midY - size.height / 2))
    }

    func refreshMindMapDrop(id: UUID?, frame: EaselRect?, pointer: NSPoint?) {
        var next: (id: UUID, drop: EaselMindMapDrop)?
        if let id, let frame, let pointer, mindMapsWritable, arrangeState.duplicateDrag == nil, dragDistance > 3,
           let item = session.document.items.first(where: { $0.id == id }), EaselMindMap.isNodeKind(item.kind), !item.isLocked,
           let drop = EaselMindMap.drop(for: id, frame: frame, pointer: EaselPoint(x: pointer.x, y: pointer.y), in: session.document) {
            next = (id, drop)
        }
        guard next?.id != mindMaps.drop?.id || next?.drop != mindMaps.drop?.drop else { return }
        let previous = mindMaps.dropRect
        mindMaps.drop = next
        mindMaps.dropRect = mindMapDropRect()
        let dirty = previous.union(mindMaps.dropRect)
        guard !dirty.isNull else { return }
        if usesObjectSurfaces { refreshDecorations() } else { setNeedsDisplay(dirty) }
    }

    func clearMindMapDrop() {
        guard mindMaps.drop != nil else { return }
        let dirty = mindMaps.dropRect
        mindMaps.drop = nil
        mindMaps.dropRect = .null
        if dirty.isNull { return }
        if usesObjectSurfaces { refreshDecorations() } else { setNeedsDisplay(dirty) }
    }

    func commitMindMapDrop() -> Bool {
        guard let pending = mindMaps.drop else { return false }
        clearMindMapDrop()
        let attaching = !isMindMapNode(pending.id)
        guard let next = EaselMindMap.moving(pending.id, to: pending.drop, in: session.document) else { return false }
        guard revealingConnectors({ commit(attaching ? "Attach to mind map" : "Move topic", { $0 = next }) }) else { return false }
        selection = [pending.id]
        NSAccessibility.post(element: self, notification: .layoutChanged)
        return true
    }

    private func mindMapDropTarget() -> (rect: NSRect, drop: EaselMindMapDrop)? {
        guard let pending = mindMaps.drop, let parent = session.document.items.first(where: { $0.id == pending.drop.parent }) else { return nil }
        let bounds = EaselShapeGeometry.visualBounds(of: parent)
        return (NSRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height), pending.drop)
    }

    private func mindMapDropRect() -> NSRect {
        guard let target = mindMapDropTarget() else { return .null }
        let pad = 12 / max(CGFloat(canvasScale), 0.2)
        let slot = NSRect(x: target.drop.slot.x - 40, y: target.drop.slot.y - 8, width: 80, height: 16)
        return target.rect.union(slot).insetBy(dx: -pad, dy: -pad)
    }

    private func drawMindMapDrop(scale: CGFloat) {
        guard let target = mindMapDropTarget() else { return }
        EaselAppearance.selection.setStroke()
        if target.drop.onto {
            let ring = NSBezierPath(roundedRect: target.rect.insetBy(dx: -5 / scale, dy: -5 / scale), xRadius: 6 / scale, yRadius: 6 / scale)
            ring.lineWidth = 2 / scale
            ring.stroke()
            return
        }
        let right = target.drop.side == .right
        let from = NSPoint(x: right ? target.rect.maxX : target.rect.minX, y: target.rect.midY)
        let to = NSPoint(x: target.drop.slot.x, y: target.drop.slot.y)
        let line = NSBezierPath()
        line.move(to: from)
        let bend = (to.x - from.x) / 2
        line.curve(to: to, controlPoint1: NSPoint(x: from.x + bend, y: from.y), controlPoint2: NSPoint(x: to.x - bend, y: to.y))
        line.lineWidth = 2 / scale
        line.setLineDash([4 / scale, 4 / scale], count: 2, phase: 0)
        line.lineCapStyle = .round
        line.stroke()
        let bar = NSBezierPath()
        bar.move(to: to)
        bar.line(to: NSPoint(x: to.x + (right ? 28 : -28) / scale, y: to.y))
        bar.lineWidth = 3 / scale
        bar.lineCapStyle = .round
        bar.stroke()
        let radius = 4 / scale
        EaselAppearance.selection.setFill()
        NSBezierPath(ovalIn: NSRect(x: to.x - radius, y: to.y - radius, width: radius * 2, height: radius * 2)).fill()
    }

    func mindMapMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] {
        guard mindMapsWritable else { return [] }
        func row(_ id: String, _ title: String, _ symbol: String, _ shortcut: String? = nil, _ action: @escaping (EaselCanvasView) -> Void) -> EaselMenuRow {
            EaselMenuRow(id: id, title: title, symbol: symbol, shortcut: shortcut, perform: guardedMenuAction(action))
        }
        if context.target == .canvas {
            let point = NSPoint(x: context.point.x, y: context.point.y)
            return [row("mind-map-add", "Add Mind Map Here", "point.3.connected.trianglepath.dotted") { $0.insertMindMap(at: point) }]
        }
        guard context.target == .object, let item = context.items.first, !item.isLocked else { return [] }
        if EaselMindMap.canStart(from: item) {
            return [row("mind-map-start", "Make Mind Map", "point.3.connected.trianglepath.dotted") { $0.startMindMap(from: item.id) }]
        }
        let tree = EaselMindMap.tree(of: session.document.items)
        guard let node = tree.nodes[item.id] else { return [] }
        var rows = [row("mind-map-child", "Add Child", "arrow.turn.down.right", "⌘↩") { $0.addMindMapNode(to: item.id) }]
        if node.parent != nil {
            rows.append(row("mind-map-sibling", "Add Sibling", "arrow.down", "⇧⌘↩") { $0.addMindMapNode(to: item.id, sibling: true) })
        }
        if EaselMindMap.indenting(item.id, in: session.document) != nil {
            rows.append(row("mind-map-indent", "Move In", "increase.indent", "⇥") { $0.reparentMindMapNode(item.id, outdent: false) })
        }
        if EaselMindMap.outdenting(item.id, in: session.document) != nil {
            rows.append(row("mind-map-outdent", "Move Out", "decrease.indent", "⇧⇥") { $0.reparentMindMapNode(item.id, outdent: true) })
        }
        if EaselMindMap.canCollapse(item.id, in: tree) {
            let collapsed = node.collapsed
            rows.append(row("mind-map-collapse", collapsed ? "Expand Branch" : "Collapse Branch",
                            collapsed ? "chevron.down.circle" : "chevron.up.circle") { $0.setMindMapCollapsed(!collapsed, ids: [item.id]) })
        }
        return rows
    }

    func mindMapActionNames(_ item: EaselItem) -> [String] {
        guard mindMapsWritable, !item.isLocked else { return [] }
        if EaselMindMap.canStart(from: item) { return ["Make mind map"] }
        let tree = EaselMindMap.tree(of: session.document.items)
        guard let node = tree.nodes[item.id] else { return [] }
        var names = ["Add child"]
        if node.parent != nil { names.append("Add sibling") }
        if EaselMindMap.indenting(item.id, in: session.document) != nil { names.append("Move in") }
        if EaselMindMap.outdenting(item.id, in: session.document) != nil { names.append("Move out") }
        if EaselMindMap.canCollapse(item.id, in: tree) { names.append(node.collapsed ? "Expand branch" : "Collapse branch") }
        return names
    }

    func performMindMapAction(_ name: String, item: EaselItem) -> Bool {
        guard selection == [item.id] else { return false }
        switch name {
        case "Make mind map": return startMindMap(from: item.id)
        case "Add child": return addMindMapNode(to: item.id)
        case "Add sibling": return addMindMapNode(to: item.id, sibling: true)
        case "Move in": return reparentMindMapNode(item.id, outdent: false)
        case "Move out": return reparentMindMapNode(item.id, outdent: true)
        case "Collapse branch": return setMindMapCollapsed(true, ids: [item.id])
        case "Expand branch": return setMindMapCollapsed(false, ids: [item.id])
        default: return false
        }
    }
}

extension EaselCanvasView {
    func growingMindMap(from parents: [UUID], _ children: [UUID], _ body: () -> Bool) -> Bool {
        let before = session.document
        let saved = withObjectMotion(.copies(sources: parents, copies: children)) { revealingConnectors(body) }
        guard saved else { return false }
        withObjectMotion(.arrange) { recordObjectMotion(from: before, to: session.document) }
        return true
    }

    func foldMindMap(from before: EaselDocument, toward ids: Set<UUID>) {
        guard canAnimateObjects else { return }
        let after = session.document
        let wasHidden = EaselBoardObjects.hiddenIDs(in: before.items), nowHidden = EaselBoardObjects.hiddenIDs(in: after.items)
        let folding = nowHidden.subtracting(wasHidden), unfolding = wasHidden.subtracting(nowHidden)
        let anchors = after.items.filter { ids.contains($0.id) }
        guard !anchors.isEmpty else { return }
        func center(_ item: EaselItem) -> EaselPoint { EaselPoint(x: item.frame.x + item.frame.width / 2, y: item.frame.y + item.frame.height / 2) }
        let lineage = EaselMindMap.tree(of: after.items)
        let anchorByID = Dictionary(anchors.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func anchor(for item: EaselItem) -> EaselItem? {
            let node = item.kind == .arrow ? item.endConnection?.itemID ?? item.id : item.id
            if let found = lineage.foldAnchor(of: node, among: ids), let match = anchorByID[found] { return match }
            let c = center(item)
            return anchors.min { hypot(center($0).x - c.x, center($0).y - c.y) < hypot(center($1).x - c.x, center($1).y - c.y) }
        }
        let reduced = feedbackReducesMotion, now = CACurrentMediaTime()
        let visible = visibleRect.isEmpty ? bounds : visibleRect
        func admitted(_ items: [EaselItem]) -> [EaselItem] {
            let live = items.filter { !$0.ownsEmbeddedPage }
            guard live.count > EaselCanvasObjectMotionState.crowd else { return live }
            return reduced ? [] : live.filter { displayBounds(of: $0).intersects(visible) }
        }
        let folded = admitted(before.items.filter { folding.contains($0.id) })
        for item in folded {
            guard let target = anchor(for: item) else { continue }
            let from = center(item), to = center(target)
            canvasFeedback.folds.append(.init(item: item, offset: EaselPoint(x: to.x - from.x, y: to.y - from.y), start: now, reduced: reduced))
        }
        if !folded.isEmpty { startCanvasFeedback() }
        let opened = admitted(after.items.filter { unfolding.contains($0.id) })
        guard !opened.isEmpty else { return }
        let nodes = opened.filter { $0.kind != .arrow }, branches = opened.filter { $0.kind == .arrow }
        var staged = before
        let leaving = Set(nodes.map(\.id))
        staged.items.removeAll { leaving.contains($0.id) }
        let tree = lineage
        func depth(_ id: UUID) -> Int {
            var steps = 0, current = id
            while let parent = tree.nodes[current]?.parent, steps <= tree.nodes.count {
                if ids.contains(current) { break }
                current = parent; steps += 1
            }
            return steps
        }
        let parents = nodes.compactMap { anchor(for: $0)?.id }
        if parents.count == nodes.count {
            let offsets = EaselObjectMotion.copyOffsets(sources: parents, copies: nodes.map(\.id), before: staged, after: after)
            let stagger = EaselFeedbackCurve.unfoldDelays(depths: nodes.map { depth($0.id) })
            glideObjects(offsets, delays: Dictionary(zip(nodes.map(\.id), stagger), uniquingKeysWith: { first, _ in first }), fades: true)
        }
        let depths = branches.map { branch in branch.endConnection.map { depth($0.itemID) } ?? 0 }
        let delays = EaselFeedbackCurve.unfoldDelays(depths: depths)
        revealConnectors(branches.map(\.id))
        for (branch, delay) in zip(branches, delays) where delay > 0 {
            canvasFeedback.reveals[branch.id]?.start += delay
        }
    }

    func drawMindMapFolds(in dirtyRect: NSRect) {
        guard !canvasFeedback.folds.isEmpty else { return }
        let now = CACurrentMediaTime()
        for fold in canvasFeedback.folds {
            let box = displayBounds(of: fold.item)
            guard box.union(box.offsetBy(dx: fold.offset.x, dy: fold.offset.y)).intersects(dirtyRect) else { continue }
            let shown = EaselFeedbackCurve.foldPresentation(now - fold.start, toward: fold.offset, reduced: fold.reduced)
            let frame = rect(fold.item)
            withPresentation(shown, around: NSPoint(x: frame.midX, y: frame.midY)) { drawObject(fold.item, showsEditor: false) }
        }
    }
}
