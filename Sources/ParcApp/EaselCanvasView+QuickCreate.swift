import AppKit

extension EaselCanvasView {
    static let quickCreateGap = 40.0
    static let quickCreateDotOffset: CGFloat = 18

    func quickCreates(_ item: EaselItem) -> Bool {
        (item.kind == .sticky || item.kind == .rectangle || item.kind == .circle) && !item.isLocked
    }

    var quickCreateSource: EaselItem? {
        guard fixedCanvasSize == nil, !drawing, editor == nil, marqueeRect == nil, !hidesPassiveAnnotations,
              connectors.gesture == nil, displayedSelection.count == 1,
              let item = items.first(where: { displayedSelection.contains($0.id) }), quickCreates(item) else { return nil }
        return item
    }

    func quickCreateDot(for item: EaselItem, side: EaselConnection.Side) -> NSPoint {
        let bounds = EaselShapeGeometry.visualBounds(of: item)
        let offset = Self.quickCreateDotOffset / CGFloat(canvasScale)
        let midX = CGFloat(bounds.x + bounds.width / 2), midY = CGFloat(bounds.y + bounds.height / 2)
        switch side {
        case .top: return NSPoint(x: midX, y: CGFloat(bounds.y) - offset)
        case .right: return NSPoint(x: CGFloat(bounds.x + bounds.width) + offset, y: midY)
        case .bottom: return NSPoint(x: midX, y: CGFloat(bounds.y + bounds.height) + offset)
        case .left: return NSPoint(x: CGFloat(bounds.x) - offset, y: midY)
        }
    }

    func drawQuickCreateDot(at point: NSPoint, hovered: Bool, scale: CGFloat) {
        if hovered {
            let radius = 10 / scale
            let disc = NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            EaselAppearance.selection.setFill(); disc.fill()
            let arm = 4.5 / scale
            let plus = NSBezierPath()
            plus.move(to: NSPoint(x: point.x - arm, y: point.y)); plus.line(to: NSPoint(x: point.x + arm, y: point.y))
            plus.move(to: NSPoint(x: point.x, y: point.y - arm)); plus.line(to: NSPoint(x: point.x, y: point.y + arm))
            plus.lineWidth = 2 / scale; plus.lineCapStyle = .round
            EaselAppearance.surface.setStroke(); plus.stroke()
            return
        }
        let radius = 4.5 / scale
        let dot = NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        dot.lineWidth = 1.5 / scale
        EaselAppearance.selection.setFill(); dot.fill()
        EaselAppearance.surface.setStroke(); dot.stroke()
    }

    func quickCreateCopy(of source: EaselItem, origin: EaselPoint, id: UUID = UUID(), zIndex: Int) -> EaselItem {
        var height = source.frame.height
        if source.kind == .sticky { height = min(height, EaselBoardObjects.stickyMinimumHeight(source)) }
        var item = EaselItem(id: id, kind: source.kind,
                             frame: EaselRect(x: max(0, origin.x), y: max(0, origin.y), width: source.frame.width, height: max(1, height)),
                             zIndex: zIndex, color: source.color)
        item.textStyle = source.textStyle
        item.shape = source.shape
        item.fill = source.fill
        item.fillOpacity = source.fillOpacity
        item.strokeWidth = source.strokeWidth
        item.strokeDash = source.strokeDash
        return item
    }

    func quickCreateSlot(from source: EaselItem, side: EaselConnection.Side, in document: EaselDocument) -> EaselPoint {
        let gap = Self.quickCreateGap
        let size = (width: source.frame.width, height: source.kind == .sticky
                    ? min(source.frame.height, EaselBoardObjects.stickyMinimumHeight(source)) : source.frame.height)
        let bounds = EaselShapeGeometry.visualBounds(of: source)
        let base: EaselPoint
        switch side {
        case .right: base = EaselPoint(x: bounds.x + bounds.width + gap, y: bounds.y + bounds.height / 2 - size.height / 2)
        case .left: base = EaselPoint(x: bounds.x - gap - size.width, y: bounds.y + bounds.height / 2 - size.height / 2)
        case .bottom: base = EaselPoint(x: bounds.x + bounds.width / 2 - size.width / 2, y: bounds.y + bounds.height + gap)
        case .top: base = EaselPoint(x: bounds.x + bounds.width / 2 - size.width / 2, y: bounds.y - gap - size.height)
        }
        let blockers = document.items.filter { $0.id != source.id && ![.arrow, .freehand, .section].contains($0.kind) }
            .map(EaselShapeGeometry.visualBounds(of:))
        let step = side == .left || side == .right ? size.height + gap : size.width + gap
        for attempt in 0..<16 {
            let lane = attempt == 0 ? 0 : (attempt % 2 == 1 ? (attempt + 1) / 2 : -(attempt / 2))
            let offset = Double(lane) * step
            let candidate = side == .left || side == .right ? EaselPoint(x: base.x, y: base.y + offset) : EaselPoint(x: base.x + offset, y: base.y)
            guard candidate.x >= 0, candidate.y >= 0 else { continue }
            let slot = EaselRect(x: candidate.x + 1, y: candidate.y + 1, width: max(1, size.width - 2), height: max(1, size.height - 2))
            if !blockers.contains(where: { EaselContentHitTest.intersects($0, slot) }) { return candidate }
        }
        return EaselPoint(x: max(0, base.x), y: max(0, base.y))
    }

    func quickCreateConnector(from source: EaselItem, side: EaselConnection.Side, to target: EaselItem, targetSide: EaselConnection.Side?,
                              id: UUID = UUID(), zIndex: Int, in document: EaselDocument) -> EaselItem {
        var lookup = Dictionary(document.items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        lookup[target.id] = target
        let style = Self.connectorStyle(for: session.document.id)
        var connector = EaselConnectorRouter.make(from: EaselConnectorAttachment.magnet(side, on: source),
                                                  to: EaselConnectorAttachment.magnet(targetSide ?? side, on: target), style: style,
                                                  routing: style.routing, startConnection: EaselConnection(itemID: source.id, side: side),
                                                  endConnection: EaselConnection(itemID: target.id, side: targetSide),
                                                  zIndex: zIndex) { lookup[$0] }
        connector.id = id
        connector.zIndex = zIndex
        return connector
    }

    static func opposite(_ side: EaselConnection.Side) -> EaselConnection.Side {
        switch side {
        case .top: return .bottom
        case .bottom: return .top
        case .left: return .right
        case .right: return .left
        }
    }

    @discardableResult
    func quickCreate(from source: EaselItem, side: EaselConnection.Side, connected: Bool? = nil) -> Bool {
        guard quickCreates(source), fixedCanvasSize == nil, let current = session.document.items.first(where: { $0 == source }) else { return false }
        let document = session.document
        let top = document.items.map(\.zIndex).max() ?? 0
        let origin = quickCreateSlot(from: current, side: side, in: document)
        let created = quickCreateCopy(of: current, origin: origin, zIndex: top + 1)
        let link = connected ?? (current.kind != .sticky)
        let connector = link ? quickCreateConnector(from: current, side: side, to: created, targetSide: Self.opposite(side),
                                                    zIndex: top + 2, in: document) : nil
        return commitQuickCreate(created, connector: connector)
    }

    func quickCreatePreview(from source: EaselItem, side: EaselConnection.Side, toward point: NSPoint) -> [EaselItem] {
        let document = session.document
        let top = document.items.map(\.zIndex).max() ?? 0
        let ids = connectors.preview.count == 2 ? (connectors.preview[0].id, connectors.preview[1].id) : (UUID(), UUID())
        let width = source.frame.width
        let height = source.kind == .sticky ? min(source.frame.height, EaselBoardObjects.stickyMinimumHeight(source)) : source.frame.height
        let origin = EaselPoint(x: max(0, Double(point.x) - width / 2), y: max(0, Double(point.y) - height / 2))
        let created = quickCreateCopy(of: source, origin: origin, id: ids.0, zIndex: top + 1)
        let connector = quickCreateConnector(from: source, side: side, to: created, targetSide: nil, id: ids.1, zIndex: top + 2, in: document)
        return [created, connector]
    }

    func finishQuickCreateDrag(from source: EaselItem, side: EaselConnection.Side, preview: [EaselItem]) {
        guard preview.count == 2, session.document.items.contains(where: { $0 == source }) else { return }
        commitQuickCreate(preview[0], connector: preview[1])
    }

    @discardableResult
    func commitQuickCreate(_ created: EaselItem, connector: EaselItem?) -> Bool {
        guard commit(connector == nil ? "Quick create" : "Quick create with connector", { document in
            document.items.append(created)
            if let connector { document.items.append(connector) }
        }) else { return false }
        if let connector, let stored = session.document.items.first(where: { $0.id == connector.id }) { rememberConnectorStyle(stored) }
        selection = [created.id]
        window?.makeFirstResponder(self)
        if let stored = session.document.items.first(where: { $0.id == created.id }) {
            scrollToVisible(rect(stored))
            beginEditing(stored)
        }
        return true
    }

    func performQuickCreateKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, [UInt16(36), UInt16(76)].contains(event.keyCode),
              event.modifierFlags.intersection([.command, .shift, .option, .control]) == [.command],
              window?.isKeyWindow == true, canvasOwnsKeyFocus || textEditorOwnsKeyFocus, start == nil, fixedCanvasSize == nil,
              !session.isClosed, !session.isDeleted else { return false }
        let id = editingID ?? (selection.count == 1 ? selection.first : nil)
        guard let id, let source = session.document.items.first(where: { $0.id == id }) else { return false }
        if source.kind == .code, editor == nil, !source.isLocked { return insertCodeBlockBelow(source.id) }
        guard quickCreates(source) else { return false }
        if editor != nil { guard finishEditing() else { return true } }
        guard let settled = session.document.items.first(where: { $0.id == id }) else { return true }
        quickCreate(from: settled, side: .right)
        return true
    }
}
