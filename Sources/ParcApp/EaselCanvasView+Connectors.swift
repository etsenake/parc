import AppKit
import ParcCore

@MainActor
struct EaselConnectorCanvasState {
    enum Gesture {
        case endpoint(id: UUID, end: EaselArrowEndpoint, original: EaselItem)
        case segment(id: UUID, index: Int, original: EaselItem, vertices: [EaselPoint], origin: NSPoint)
        case curve(id: UUID, handle: EaselConnectorPath.CurveHandle, original: EaselItem)
        case label(id: UUID, original: EaselItem, origin: NSPoint)
        case inert(id: UUID, wasSelected: Bool, origin: NSPoint)
        case create(routing: EaselConnectorRouting?, origin: NSPoint, start: EaselConnection?, startPoint: EaselPoint)
        case quickCreate(source: EaselItem, side: EaselConnection.Side, origin: NSPoint)
    }

    enum Chrome {
        case endpoint(EaselItem, EaselArrowEndpoint)
        case segment(EaselItem, index: Int, vertices: [EaselPoint])
        case curve(EaselItem, EaselConnectorPath.CurveHandle)
        case label(EaselItem)
        case quickCreate(EaselItem, EaselConnection.Side)
    }

    struct RouteKey: Equatable {
        var item: EaselItem
        var start: EaselItem?
        var end: EaselItem?
        var editing: Bool
        var label: NSSize?
    }

    struct Magnet: Equatable {
        var target: UUID
        var side: EaselConnection.Side?
        var pinned: EaselPoint?
    }

    struct LabelKey: Equatable {
        var text: String
        var rich: EaselRichText?
        var style: EaselTextStyle?
        var color: String
        var background: Bool
    }

    var gesture: Gesture?
    var travelled = false
    var preview: [EaselItem] = []
    var magnet: Magnet?
    var quickHover: (id: UUID, side: EaselConnection.Side)?
    var quickCreateHover: UUID?
    var toolHover: UUID?
    var pendingLabel: (id: UUID, position: Double, original: Double?)?
    var routes: [UUID: (key: RouteKey, drawing: EaselConnectorDrawing)] = [:]
    var labels: [UUID: (key: LabelKey, layout: EaselConnectorLabelLayout)] = [:]
    var draftGeneration = 0
    var settledPreview: (generation: Int, modified: Date, document: UUID, items: [EaselItem])?
    var settleContext: (modified: Date, document: UUID, context: EaselSettleContext)?
    static var styles: [UUID: EaselConnectorStyle] = [:]
}

@MainActor
final class EaselConnectorLabelLayout {
    let storage: NSTextStorage
    let manager: NSLayoutManager = EaselChecklistLayoutManager()
    let container: NSTextContainer

    init(_ value: NSAttributedString) {
        storage = NSTextStorage(attributedString: value)
        container = NSTextContainer(size: NSSize(width: EaselConnectorLabel.maximumWidth, height: 100_000))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
    }

    var used: NSRect {
        var rect = manager.usedRect(for: container)
        if storage.length == 0 || rect.isEmpty {
            let font = storage.length > 0 ? storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil
            let height = manager.defaultLineHeight(for: font ?? NSFont.systemFont(ofSize: 15))
            rect = NSRect(x: EaselConnectorLabel.maximumWidth / 2, y: 0, width: 1, height: height)
        }
        return rect
    }

    var size: NSSize { NSSize(width: ceil(used.width), height: ceil(used.height)) }

    func draw(in rect: NSRect) {
        let used = self.used
        let origin = NSPoint(x: rect.minX + CGFloat(EaselConnectorLabel.paddingX) - used.minX,
                             y: rect.minY + CGFloat(EaselConnectorLabel.paddingY) - used.minY)
        let glyphs = manager.glyphRange(for: container)
        manager.drawBackground(forGlyphRange: glyphs, at: origin)
        manager.drawGlyphs(forGlyphRange: glyphs, at: origin)
    }
}

extension EaselCanvasView {
    static func connectorStyle(for document: UUID) -> EaselConnectorStyle {
        EaselConnectorCanvasState.styles[document] ?? EaselConnectorStyle()
    }

    func rememberConnectorStyle(_ item: EaselItem) {
        guard item.kind == .arrow else { return }
        EaselConnectorCanvasState.styles[session.document.id] = EaselConnectorStyle(item)
    }

    func connectorLookup() -> [UUID: EaselItem] {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    func connectorTargets(_ item: EaselItem) -> [UUID: EaselItem] {
        let ids = [item.startConnection?.itemID, item.endConnection?.itemID].compactMap { $0 }
        guard !ids.isEmpty else { return [:] }
        let source = hidesPassiveAnnotations || !connectors.preview.isEmpty ? items : session.document.items
        var table: [UUID: EaselItem] = [:]
        for candidate in source where ids.contains(candidate.id) { table[candidate.id] = candidate }
        return table
    }

    func connectorDrawing(for source: EaselItem, lookup: [UUID: EaselItem]? = nil) -> EaselConnectorDrawing? {
        guard source.kind == .arrow else { return nil }
        let item = positioningPendingLabel(source)
        let table = lookup ?? connectorTargets(item)
        let labelSize = connectorLabelSize(item)
        let key = EaselConnectorCanvasState.RouteKey(item: item, start: item.startConnection.flatMap { table[$0.itemID] },
                                                     end: item.endConnection.flatMap { table[$0.itemID] }, editing: editingID == item.id,
                                                     label: labelSize)
        if let cached = connectors.routes[item.id], cached.key == key { return cached.drawing }
        guard let route = EaselConnectorRouter.route(for: item, lookup: { table[$0] }) else { return nil }
        let drawing = EaselConnectorDrawing(route: route, item: item,
                                            labelSize: labelSize.map { (width: Double($0.width), height: Double($0.height)) })
        if connectors.routes.count > max(64, session.document.items.count * 2) { connectors.routes.removeAll() }
        connectors.routes[item.id] = (key, drawing)
        return drawing
    }

    func connectorLabelText(_ item: EaselItem, background: NSColor?) -> NSAttributedString {
        let value = NSMutableAttributedString(attributedString: displayedText(item))
        let range = NSRange(location: 0, length: value.length)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        value.addAttribute(.paragraphStyle, value: paragraph, range: range)
        if let background { value.addAttribute(.foregroundColor, value: contrastingInk(on: background), range: range) }
        return value
    }

    func contrastingInk(on color: NSColor) -> NSColor {
        let onLight = EaselInk.fixed(EaselPalette.inkLight), onDark = EaselInk.fixed(EaselPalette.neutralLight)
        return NSColor(name: nil) { appearance in
            var luminance: CGFloat = 0
            appearance.performAsCurrentDrawingAppearance {
                guard let rgb = color.usingColorSpace(.sRGB) else { return }
                luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
            }
            return luminance > 0.6 ? onLight : onDark
        }
    }

    func connectorLabelLayout(_ item: EaselItem) -> EaselConnectorLabelLayout {
        let key = EaselConnectorCanvasState.LabelKey(text: item.text, rich: item.richText, style: item.textStyle,
                                                     color: item.color, background: item.labelBackground == true)
        if let cached = connectors.labels[item.id], cached.key == key { return cached.layout }
        let background = item.labelBackground == true ? EaselPaint(item, adaptive: adaptsInk).inkColor : nil
        let layout = EaselConnectorLabelLayout(connectorLabelText(item, background: background))
        if connectors.labels.count > max(64, session.document.items.count * 2) { connectors.labels.removeAll() }
        connectors.labels[item.id] = (key, layout)
        return layout
    }

    func connectorLabelSize(_ item: EaselItem) -> NSSize? {
        let editing = editingID == item.id
        guard editing || !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let size = connectorLabelLayout(item).size
        return NSSize(width: max(editing ? 12 : 1, size.width), height: max(1, size.height))
    }

    func positioningPendingLabel(_ item: EaselItem) -> EaselItem {
        guard let pending = connectors.pendingLabel, pending.id == item.id, editingID == item.id else { return item }
        var moved = item
        moved.labelPosition = pending.position
        return moved
    }

    func connectorLabelRect(_ item: EaselItem) -> NSRect? {
        guard let rect = connectorDrawing(for: item)?.label else { return nil }
        return NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    func connectorEditingFrame(_ item: EaselItem) -> NSRect {
        let size = connectorLabelSize(item) ?? NSSize(width: 12, height: 18)
        guard let route = connectorDrawing(for: item)?.route else { return rect(item) }
        let measured = (width: Double(size.width), height: Double(size.height))
        let position = positioningPendingLabel(item).resolvedLabelPosition
        let anchor = route.location(atFraction: EaselConnectorLabel.clampedPosition(position, on: route, size: measured)).point
        let width = CGFloat(EaselConnectorLabel.maximumWidth + 2 * EaselConnectorLabel.paddingX)
        let height = size.height + CGFloat(2 * EaselConnectorLabel.paddingY)
        return NSRect(x: CGFloat(anchor.x) - width / 2, y: CGFloat(anchor.y) - height / 2, width: width, height: height)
    }

    func configureConnectorLabelEditor(_ text: EaselStyledTextView) {
        text.textContainerInset = NSSize(width: EaselConnectorLabel.paddingX, height: EaselConnectorLabel.paddingY)
        text.textContainer?.lineFragmentPadding = 0
        text.alignment = .center
        text.usesEaselObjectLayout = false
        text.setAccessibilityLabel("Connector label")
    }

    func appendConnectorPath(_ pieces: [[EaselConnectorRoute.Segment]], to path: NSBezierPath) {
        for piece in pieces {
            guard let first = piece.first else { continue }
            path.move(to: NSPoint(x: first.start.x, y: first.start.y))
            for segment in piece {
                switch segment {
                case .line(_, let b): path.line(to: NSPoint(x: b.x, y: b.y))
                case .cubic(_, let c1, let c2, let b):
                    path.curve(to: NSPoint(x: b.x, y: b.y), controlPoint1: NSPoint(x: c1.x, y: c1.y), controlPoint2: NSPoint(x: c2.x, y: c2.y))
                }
            }
        }
    }

    func drawConnector(_ item: EaselItem) {
        guard let drawing = connectorDrawing(for: item) else { return }
        let reveal = paintsLiveFeedback ? presentedReveal(item.id) : nil
        guard let reveal, let context = NSGraphicsContext.current?.cgContext else { drawConnector(item, drawing: drawing); return }
        context.saveGState()
        if reveal.opacity < 1 { context.setAlpha(reveal.opacity); context.beginTransparencyLayer(auxiliaryInfo: nil) }
        drawConnector(item, drawing: drawing, reveal: reveal)
        if reveal.opacity < 1 { context.endTransparencyLayer() }
        context.restoreGState()
    }

    private func drawConnector(_ item: EaselItem, drawing: EaselConnectorDrawing, reveal: EaselConnectorRevealFrame? = nil) {
        let paint = EaselPaint(item, adaptive: adaptsInk)
        let pieces = reveal.map { EaselConnectorReveal.trimmed(drawing.pieces, fraction: $0.fraction) } ?? drawing.pieces
        if !pieces.isEmpty {
            let line = NSBezierPath()
            appendConnectorPath(pieces, to: line)
            line.lineCapStyle = .round; line.lineJoinStyle = .round
            paint.stroke(line)
        }
        withHeadPop(reveal?.startHead, tip: drawing.route.start) { drawConnectorHead(drawing.startHead, paint: paint) }
        withHeadPop(reveal?.endHead, tip: drawing.route.end) { drawConnectorHead(drawing.endHead, paint: paint) }
        if let label = drawing.label {
            let box = NSRect(x: label.x, y: label.y, width: label.width, height: label.height)
            withHeadPop(reveal?.label, tip: NSPoint(x: box.midX, y: box.midY).easelPoint) {
                if item.labelBackground == true {
                    paint.inkColor.setFill()
                    let radius = min(8, box.height / 2)
                    NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius).fill()
                }
                if editingID != item.id { connectorLabelLayout(item).draw(in: box) }
            }
        }
    }

    private func withHeadPop(_ pop: (scale: CGFloat, opacity: CGFloat)?, tip: EaselPoint, _ body: () -> Void) {
        guard let pop, pop.scale != 1 || pop.opacity != 1 else { body(); return }
        guard pop.scale > 0.001, pop.opacity > 0.001, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setAlpha(pop.opacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.translateBy(x: tip.x, y: tip.y)
        context.scaleBy(x: pop.scale, y: pop.scale)
        context.translateBy(x: -tip.x, y: -tip.y)
        body()
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private func drawConnectorHead(_ head: EaselArrowHeadGeometry, paint: EaselPaint) {
        for stroke in head.strokes {
            guard let first = stroke.points.first else { continue }
            let path = NSBezierPath()
            path.move(to: NSPoint(x: first.x, y: first.y))
            for point in stroke.points.dropFirst() { path.line(to: NSPoint(x: point.x, y: point.y)) }
            if stroke.closed { path.close() }
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            if stroke.filled { paint.inkColor.setFill(); path.fill() }
            paint.stroke(path, dashed: false)
        }
        for dot in head.dots {
            let path = NSBezierPath(ovalIn: NSRect(x: dot.center.x - dot.radius, y: dot.center.y - dot.radius,
                                                   width: dot.radius * 2, height: dot.radius * 2))
            if dot.filled { paint.inkColor.setFill(); path.fill() }
            paint.stroke(path, dashed: false)
        }
    }

    func drawConnectorOutline(_ item: EaselItem, exclusive: Bool) {
        guard let drawing = connectorDrawing(for: item) else { return }
        let path = NSBezierPath()
        appendConnectorPath([drawing.route.segments], to: path)
        path.lineCapStyle = .round; path.lineJoinStyle = .round
        path.lineWidth = max(CGFloat(EaselPaintRules.strokeWidth(item)) + 5 / canvasScale, 6 / canvasScale)
        EaselAppearance.selection.withAlphaComponent(exclusive ? 0.42 : 0.28).setStroke()
        path.stroke()
        if let label = drawing.label {
            let box = NSRect(x: label.x, y: label.y, width: label.width, height: label.height)
            let radius = min(8, box.height / 2)
            let outline = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
            outline.lineWidth = 1.5 / canvasScale
            EaselAppearance.selection.setStroke(); outline.stroke()
        }
    }

    var selectedConnector: EaselItem? {
        guard !drawing, editor == nil, marqueeRect == nil, displayedSelection.count == 1, !motion.isInteracting,
              let item = items.first(where: { displayedSelection.contains($0.id) }), item.kind == .arrow, item.points.count >= 2,
              !item.isLocked else { return nil }
        return item
    }

    func connectorChromeItems() -> [(chrome: EaselConnectorCanvasState.Chrome, point: NSPoint, radius: CGFloat)] {
        var result: [(chrome: EaselConnectorCanvasState.Chrome, point: NSPoint, radius: CGFloat)] = []
        let scale = CGFloat(canvasScale)
        if let item = selectedConnector, let drawing = connectorDrawing(for: item) {
            let busy = connectors.gesture != nil
            var draggingEnd = false
            if case .endpoint? = connectors.gesture { draggingEnd = true }
            if !busy || draggingEnd {
                result.append((.endpoint(item, .start), NSPoint(x: drawing.route.start.x, y: drawing.route.start.y), 10 / scale))
                result.append((.endpoint(item, .end), NSPoint(x: drawing.route.end.x, y: drawing.route.end.y), 10 / scale))
            }
            if !busy, fixedCanvasSize == nil {
                switch drawing.route.routing {
                case .elbow:
                    for handle in EaselConnectorPath.elbowHandles(drawing.route, scale: canvasScale,
                                                                  attachedStart: item.startConnection != nil, attachedEnd: item.endConnection != nil) {
                        result.append((.segment(item, index: handle.index, vertices: drawing.route.vertices), NSPoint(x: handle.point.x, y: handle.point.y), 8 / scale))
                    }
                case .curved:
                    for handle in EaselConnectorPath.curveHandles(drawing.route, waypoints: item.waypoints ?? [])
                    where drawing.route.length * canvasScale >= 48 {
                        result.append((.curve(item, handle), NSPoint(x: handle.point.x, y: handle.point.y), 8 / scale))
                    }
                case .straight: break
                }
            }
        }
        if connectors.gesture == nil {
            for source in quickCreateSources {
                for side in EaselConnection.Side.allCases {
                    result.append((.quickCreate(source, side), quickCreateDot(for: source, side: side), 11 / scale))
                }
            }
        }
        return result
    }

    func connectorChrome(at point: NSPoint) -> EaselConnectorCanvasState.Chrome? {
        let chrome = connectorChromeItems()
        if let hit = chrome.first(where: { hypot($0.point.x - point.x, $0.point.y - point.y) <= $0.radius }) { return hit.chrome }
        if let item = selectedConnector, let label = connectorLabelRect(item), label.contains(point) { return .label(item) }
        return nil
    }

    func connectorContains(_ point: NSPoint, item: EaselItem) -> Bool {
        let reach = CGFloat(EaselConnectorHit.reach(for: item, scale: canvasScale))
        guard connectorOverhang(item).insetBy(dx: -reach, dy: -reach).contains(point),
              let drawing = connectorDrawing(for: item) else { return false }
        return EaselConnectorHit.contains(EaselPoint(x: point.x, y: point.y), drawing: drawing, item: item, scale: canvasScale)
    }

    func drawConnectorChrome(in dirtyRect: NSRect) {
        let scale = CGFloat(canvasScale)
        if let magnet = connectors.magnet, let target = items.first(where: { $0.id == magnet.target }) {
            drawMagnets(on: target, magnet: magnet, scale: scale)
        } else if let id = connectors.toolHover, let target = items.first(where: { $0.id == id }) {
            drawMagnets(on: target, magnet: nil, scale: scale)
        }
        for entry in connectorChromeItems() {
            switch entry.chrome {
            case .endpoint(let item, let end):
                let attached = (end == .start ? item.startConnection : item.endConnection) != nil
                drawConnectorHandle(at: entry.point, filled: attached, scale: scale)
            case .segment(_, let index, let vertices):
                guard vertices.indices.contains(index + 1) else { continue }
                let a = vertices[index], b = vertices[index + 1]
                let horizontal = abs(a.y - b.y) <= abs(a.x - b.x)
                let size = NSSize(width: (horizontal ? 14 : 6) / scale, height: (horizontal ? 6 : 14) / scale)
                let pill = NSRect(x: entry.point.x - size.width / 2, y: entry.point.y - size.height / 2, width: size.width, height: size.height)
                EaselAppearance.surface.setFill(); EaselAppearance.selection.setStroke()
                let path = NSBezierPath(roundedRect: pill, xRadius: 3 / scale, yRadius: 3 / scale)
                path.lineWidth = 1.5 / scale; path.fill(); path.stroke()
            case .curve(_, let handle):
                let radius = (handle.waypoint == nil ? 3.5 : 4.5) / scale
                let dot = NSBezierPath(ovalIn: NSRect(x: entry.point.x - radius, y: entry.point.y - radius, width: radius * 2, height: radius * 2))
                dot.lineWidth = 1.5 / scale
                (handle.waypoint == nil ? EaselAppearance.surface : EaselAppearance.selection).setFill(); dot.fill()
                EaselAppearance.selection.setStroke(); dot.stroke()
            case .quickCreate(let item, let side):
                let hovered = connectors.quickHover.map { $0.id == item.id && $0.side == side } == true
                drawQuickCreateDot(at: entry.point, hovered: hovered, scale: scale)
            case .label:
                break
            }
        }
    }

    private func drawConnectorHandle(at point: NSPoint, filled: Bool, scale: CGFloat) {
        guard filled else { EaselAppearance.drawHandle(at: point, scale: scale); return }
        let mark = NSRect(x: point.x - 5 / scale, y: point.y - 5 / scale, width: 10 / scale, height: 10 / scale)
        EaselAppearance.surface.setFill(); NSBezierPath(ovalIn: mark).fill()
        EaselAppearance.selection.setFill(); NSBezierPath(ovalIn: mark.insetBy(dx: 2 / scale, dy: 2 / scale)).fill()
    }

    private func drawMagnets(on target: EaselItem, magnet: EaselConnectorCanvasState.Magnet?, scale: CGFloat) {
        let outline = EaselShapeGeometry.outline(for: target).map(NSBezierPath.init(connectorOutline:))
            ?? NSBezierPath(roundedRect: rect(target).insetBy(dx: -3 / scale, dy: -3 / scale), xRadius: 6 / scale, yRadius: 6 / scale)
        if magnet != nil, let glow = connectorGlowLevel(target.id), glow > 0 {
            outline.lineJoinStyle = .round
            for (width, alpha) in [(CGFloat(12), CGFloat(0.1)), (7, 0.16), (3.5, 0.22)] {
                outline.lineWidth = width / scale
                EaselAppearance.selection.withAlphaComponent(alpha * glow).setStroke(); outline.stroke()
            }
        }
        if let magnet, magnet.side == nil, magnet.pinned == nil {
            outline.lineWidth = 2 / scale
            EaselAppearance.selection.setStroke(); outline.stroke()
        }
        for (side, point) in EaselConnectorAttachment.magnets(on: target) {
            let active = magnet?.side == side && magnet?.pinned == nil
            let radius = connectorDotRadius(target: target.id, side: side, active: active) / scale
            let dot = NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            dot.lineWidth = 1.5 / scale
            (active ? EaselAppearance.selection : EaselAppearance.surface).setFill(); dot.fill()
            EaselAppearance.selection.setStroke(); dot.stroke()
        }
        if let pinned = magnet?.pinned {
            let radius = 4 / scale
            let dot = NSBezierPath(ovalIn: NSRect(x: pinned.x - radius, y: pinned.y - radius, width: radius * 2, height: radius * 2))
            EaselAppearance.selection.setFill(); dot.fill()
        }
    }

    func connectorChromeBounds() -> NSRect {
        var dirty = NSRect.null
        let pad = 24 / max(CGFloat(canvasScale), 0.2)
        for entry in connectorChromeItems() {
            dirty = dirty.union(NSRect(x: entry.point.x - pad, y: entry.point.y - pad, width: pad * 2, height: pad * 2))
        }
        for id in [connectors.magnet?.target, connectors.toolHover].compactMap({ $0 }) {
            if let target = items.first(where: { $0.id == id }) { dirty = dirty.union(rect(target).insetBy(dx: -pad, dy: -pad)) }
        }
        return dirty
    }

    func refreshConnectorChrome(from previous: NSRect) {
        let next = connectorChromeBounds()
        let dirty = previous.union(next)
        guard !dirty.isNull else { return }
        if usesObjectSurfaces { refreshDecorations() } else { setNeedsDisplay(dirty) }
    }

    func addConnectorCursorRects() {
        for entry in connectorChromeItems() {
            addCursorRect(NSRect(x: entry.point.x - entry.radius, y: entry.point.y - entry.radius, width: entry.radius * 2, height: entry.radius * 2),
                          cursor: .pointingHand)
        }
        if let item = selectedConnector, let label = connectorLabelRect(item) {
            addCursorRect(label, cursor: .openHand)
        }
    }

    func updateConnectorHover(at point: NSPoint) {
        let previous = connectorChromeBounds()
        let previousSource = connectors.quickCreateHover
        connectors.quickCreateHover = quickCreateHoverTarget(at: point)
        var next: (id: UUID, side: EaselConnection.Side)?
        if connectors.gesture == nil, case .quickCreate(let item, let side)? = connectorChrome(at: point) { next = (item.id, side) }
        let sourceChanged = previousSource != connectors.quickCreateHover
        let changed = sourceChanged || next?.id != connectors.quickHover?.id || next?.side != connectors.quickHover?.side
        connectors.quickHover = next
        if changed { refreshConnectorChrome(from: previous) }
        if sourceChanged { window?.invalidateCursorRects(for: self) }
    }

    func connectorTarget(at point: NSPoint, excluding id: UUID?, also others: Set<UUID> = []) -> EaselItem? {
        guard fixedCanvasSize == nil else { return nil }
        let reach = CGFloat(EaselConnectorAttachment.magnetReach / canvasScale)
        let local = EaselPoint(x: point.x, y: point.y)
        return items.reversed().first { item in
            guard item.id != id, !others.contains(item.id), EaselConnectorAttachment.canAttach(to: item) else { return false }
            let bounds = EaselShapeGeometry.visualBounds(of: item)
            let grown = NSRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height).insetBy(dx: -reach, dy: -reach)
            guard grown.contains(point) else { return false }
            if NSRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height).contains(point) { return true }
            return EaselConnectorAttachment.magnets(on: item).contains { hypot($0.point.x - local.x, $0.point.y - local.y) <= Double(reach) }
        }
    }

    func snappedConnectorEnd(_ point: NSPoint, flags: NSEvent.ModifierFlags, other: EaselPoint?, excluding id: UUID?,
                             also others: Set<UUID> = [], feedback: Bool = true) -> (connection: EaselConnection?, point: EaselPoint) {
        var location = EaselPoint(x: point.x, y: point.y)
        let target = connectorTarget(at: point, excluding: id, also: others)
        defer { if feedback { noteConnectorMagnet() } }
        if let target {
            let snap = EaselConnectorAttachment.snap(location, to: target, pin: flags.contains(.command), scale: canvasScale)
            if feedback {
                connectors.magnet = snap.connection.map { EaselConnectorCanvasState.Magnet(target: $0.itemID, side: $0.side, pinned: $0.anchor == nil ? nil : snap.point) }
            }
            return snap
        }
        if feedback { connectors.magnet = nil }
        if flags.contains(.shift), let other { location = EaselToolGeometry.snappedLineEnd(from: other, to: location) }
        location = EaselPoint(x: max(0, location.x), y: max(0, location.y))
        return (nil, location)
    }

    func beginConnectorGesture(at point: NSPoint, event: NSEvent) -> Bool {
        connectors.travelled = false
        let pressed = connectorChrome(at: point)
        if case .quickCreate? = pressed {} else { clearQuickCreateHover() }
        if let chrome = pressed {
            switch chrome {
            case .endpoint(let item, let end):
                connectors.gesture = .endpoint(id: item.id, end: end, original: item)
                primeConnectorMagnet(attachedMagnet(item, end: end))
            case .segment(let item, let index, let vertices):
                connectors.gesture = .segment(id: item.id, index: index, original: item, vertices: vertices, origin: point)
            case .curve(let item, let handle):
                connectors.gesture = .curve(id: item.id, handle: handle, original: item)
            case .label(let item):
                if event.clickCount >= 2 { cancelPointerInteraction(); beginConnectorLabelEditing(item, at: point); return true }
                connectors.gesture = .label(id: item.id, original: item, origin: point)
            case .quickCreate(let item, let side):
                connectors.gesture = .quickCreate(source: item, side: side, origin: point)
                primeConnectorMagnet(nil)
            }
            invalidateIncrementalDisplay(layout: true)
            return true
        }
        guard let hit = object(at: point), hit.kind == .arrow else { return false }
        if event.clickCount >= 2, !hit.isLocked, fixedCanvasSize == nil {
            selection = [hit.id]
            cancelPointerInteraction()
            beginConnectorLabelEditing(hit, at: point)
            return true
        }
        let lookup = connectorLookup()
        let attached = [hit.startConnection, hit.endConnection].allSatisfy { connection in
            connection.flatMap { lookup[$0.itemID] }.map(EaselConnectorAttachment.resolves) == true
        }
        guard attached, !event.modifierFlags.contains(.shift), !(selection.contains(hit.id) && selection.count > 1) else { return false }
        let wasSelected = selection == [hit.id]
        selection = [hit.id]
        connectors.gesture = .inert(id: hit.id, wasSelected: wasSelected, origin: point)
        invalidateIncrementalDisplay(layout: true)
        return true
    }

    func continueConnectorGesture(to point: NSPoint, event: NSEvent) -> Bool {
        guard let gesture = connectors.gesture else { return false }
        let previousChrome = connectorChromeBounds()
        defer { refreshConnectorChrome(from: previousChrome); autoscroll(with: event); invalidateIncrementalDisplay(layout: true) }
        let lookup = Dictionary(session.document.items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        switch gesture {
        case .endpoint(_, let end, let original):
            let other = end == .start ? EaselConnectorRouter.absolutePoints(original).last : EaselConnectorRouter.absolutePoints(original).first
            let snap = snappedConnectorEnd(point, flags: event.modifierFlags, other: other, excluding: original.id)
            connectors.travelled = true
            connectors.preview = [EaselConnectorRouter.connecting(original, end: end, to: snap.connection, at: snap.point) { lookup[$0] }]
        case .segment(_, let index, let original, let vertices, let origin):
            guard vertices.indices.contains(index + 1) else { return true }
            let a = vertices[index], b = vertices[index + 1]
            let horizontal = abs(a.y - b.y) <= abs(a.x - b.x)
            let offset = Double(horizontal ? point.y - origin.y : point.x - origin.x)
            guard connectors.travelled || abs(offset) * canvasScale > EaselToolGeometry.dragThreshold else { return true }
            connectors.travelled = true
            guard let corners = EaselConnectorPath.movingElbowSegment(vertices, index: index, by: offset) else { return true }
            var next = original
            next.waypoints = corners.isEmpty ? nil : corners
            connectors.preview = [EaselConnectorRouter.settled(next) { lookup[$0] }]
        case .curve(_, let handle, let original):
            connectors.travelled = true
            var waypoints = original.waypoints ?? []
            let location = EaselPoint(x: max(0, point.x), y: max(0, point.y))
            if let index = handle.waypoint, waypoints.indices.contains(index) { waypoints[index] = location }
            else { waypoints.insert(location, at: min(max(0, handle.insertion), waypoints.count)) }
            guard waypoints.count <= 64 else { return true }
            var next = original
            next.waypoints = waypoints
            connectors.preview = [EaselConnectorRouter.settled(next) { lookup[$0] }]
        case .label(_, let original, let origin):
            guard connectors.travelled || hypot(point.x - origin.x, point.y - origin.y) * canvasScale > EaselToolGeometry.dragThreshold,
                  let route = connectorDrawing(for: original)?.route, let size = connectorLabelSize(original) else { return true }
            let measured = (width: Double(size.width), height: Double(size.height))
            guard EaselConnectorLabel.canSlide(on: route, size: measured) else { return true }
            connectors.travelled = true
            var next = original
            next.labelPosition = EaselConnectorLabel.position(nearest: EaselPoint(x: point.x, y: point.y), on: route, size: measured)
            connectors.preview = [next]
        case .inert(_, _, let origin):
            if hypot(point.x - origin.x, point.y - origin.y) * canvasScale > EaselToolGeometry.dragThreshold { connectors.travelled = true }
        case .create(_, let origin, _, _):
            guard connectors.travelled || hypot(point.x - origin.x, point.y - origin.y) * canvasScale > EaselToolGeometry.dragThreshold else { return true }
            connectors.travelled = true
            updateConnectorCreationPreview(to: point, flags: event.modifierFlags)
        case .quickCreate(let source, let side, let origin):
            guard connectors.travelled || hypot(point.x - origin.x, point.y - origin.y) * canvasScale > EaselToolGeometry.dragThreshold else { return true }
            connectors.travelled = true
            connectors.preview = quickCreatePreview(from: source, side: side, toward: point, flags: event.modifierFlags)
        }
        return true
    }

    func endConnectorGesture(at point: NSPoint, event: NSEvent) -> Bool {
        guard let gesture = connectors.gesture else { return false }
        let preview = connectors.preview, travelled = connectors.travelled
        let previousChrome = connectorChromeBounds()
        connectors.gesture = nil; connectors.preview = []; connectors.magnet = nil; connectors.travelled = false
        defer { refreshConnectorChrome(from: previousChrome); invalidateIncrementalDisplay(layout: true); window?.invalidateCursorRects(for: self) }
        switch gesture {
        case .endpoint(_, _, let original), .segment(_, _, let original, _, _), .curve(_, _, let original):
            guard travelled, let next = preview.first else { return true }
            let name: String
            if case .endpoint = gesture { name = "Move connector end" } else { name = "Bend connector" }
            if case .endpoint(_, let end, _) = gesture, (end == .start ? next.startConnection : next.endConnection) != nil {
                poppingConnectorHead(.end(end)) { replaceConnector(original, with: next, name: name) }
            } else {
                replaceConnector(original, with: next, name: name)
            }
        case .label(_, let original, _):
            if travelled, let next = preview.first { replaceConnector(original, with: next, name: "Move label") }
            else { cancelPointerInteraction(); beginConnectorLabelEditing(original, at: nil) }
        case .inert(let id, let wasSelected, _):
            guard wasSelected, !travelled, let item = session.document.items.first(where: { $0.id == id }) else { return true }
            cancelPointerInteraction()
            beginConnectorLabelEditing(item, at: point)
        case .create:
            guard travelled, let item = preview.first else { return true }
            if poppingConnectorHead(.created, { commit("Add connector", { $0.items.append(item) }) }) { selection = [item.id]; rememberConnectorStyle(item) }
        case .quickCreate(let source, let side, _):
            connectors.quickCreateHover = nil; connectors.quickHover = nil
            if travelled { poppingConnectorHead(.created) { finishQuickCreateDrag(from: source, side: side, preview: preview) } }
            else { quickCreate(from: source, side: side) }
        }
        return true
    }

    func cancelConnectorGesture() {
        guard connectors.gesture != nil || !connectors.preview.isEmpty || connectors.magnet != nil else { return }
        let previousChrome = connectorChromeBounds()
        if case .quickCreate? = connectors.gesture { connectors.quickCreateHover = nil; connectors.quickHover = nil }
        connectors.gesture = nil; connectors.preview = []; connectors.magnet = nil; connectors.travelled = false
        refreshConnectorChrome(from: previousChrome)
    }

    @discardableResult
    func replaceConnector(_ original: EaselItem, with next: EaselItem, name: String) -> Bool {
        guard session.document.items.contains(where: { $0 == original }) else { return false }
        let saved = commit(name) { document in
            guard let index = document.items.firstIndex(where: { $0 == original }) else { return }
            document.items[index] = next
        }
        if saved { rememberConnectorStyle(next) }
        return saved
    }

    func mergingConnectorPreview(_ displayed: [EaselItem]) -> [EaselItem] {
        guard !connectors.preview.isEmpty else { return displayed }
        let replacements = Dictionary(connectors.preview.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var seen = Set<UUID>()
        var result = displayed.map { item -> EaselItem in
            guard let replacement = replacements[item.id] else { return item }
            seen.insert(item.id)
            return replacement
        }
        result += connectors.preview.filter { !seen.contains($0.id) }
        return result
    }

    func settledDragPreview(_ preview: EaselDocument, previous: EaselDocument, moved: Set<UUID>) -> [EaselItem] {
        if let cached = connectors.settledPreview, cached.generation == connectors.draftGeneration,
           cached.modified == previous.modifiedAt, cached.document == previous.id {
            return cached.items
        }
        let context: EaselSettleContext
        if let cached = connectors.settleContext, cached.modified == previous.modifiedAt, cached.document == previous.id {
            context = cached.context
        } else {
            context = EaselSettleContext(previous: previous)
            connectors.settleContext = (previous.modifiedAt, previous.id, context)
        }
        let items = EaselDependents.settle(preview, context: context, moved: moved, tidy: false).items
        connectors.settledPreview = (connectors.draftGeneration, previous.modifiedAt, previous.id, items)
        return items
    }

    func beginConnectorCreation(_ routing: EaselConnectorRouting?, at point: NSPoint, flags: NSEvent.ModifierFlags) {
        let snap = snappedConnectorEnd(point, flags: flags.subtracting(.shift), other: nil, excluding: nil)
        primeConnectorMagnet(connectors.magnet)
        connectors.travelled = false
        connectors.gesture = .create(routing: routing, origin: point, start: snap.connection, startPoint: snap.point)
        invalidateIncrementalDisplay(layout: true)
    }

    func updateConnectorCreationPreview(to point: NSPoint, flags: NSEvent.ModifierFlags) {
        guard case .create(let routing, _, let start, let startPoint)? = connectors.gesture else { return }
        let lookup = Dictionary(session.document.items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let snap = snappedConnectorEnd(point, flags: flags, other: startPoint, excluding: start?.itemID)
        var created = EaselConnectorRouter.make(from: startPoint, to: snap.point, style: Self.connectorStyle(for: session.document.id),
                                                routing: routing, startConnection: start, endConnection: snap.connection,
                                                zIndex: (session.document.items.map(\.zIndex).max() ?? 0) + 1) { lookup[$0] }
        if let previous = connectors.preview.first { created.id = previous.id }
        stampNewConnectorStyle(on: &created)
        connectors.preview = [created]
    }

    func updateConnectorCreation(to point: NSPoint, event: NSEvent) {
        _ = continueConnectorGesture(to: point, event: event)
    }

    @discardableResult
    func finishConnectorCreation(at point: NSPoint, event: NSEvent) -> Bool {
        guard case .create? = connectors.gesture else { return false }
        _ = continueConnectorGesture(to: point, event: event)
        return endConnectorGesture(at: point, event: event)
    }

    func connectorToolHover(at point: NSPoint?) {
        let previous = connectorChromeBounds()
        let next = point.flatMap { connectorTarget(at: $0, excluding: nil)?.id }
        guard next != connectors.toolHover else { return }
        connectors.toolHover = next
        refreshConnectorChrome(from: previous)
    }

    func beginConnectorLabelEditing(_ item: EaselItem, at point: NSPoint?) {
        guard item.kind == .arrow, !item.isLocked, fixedCanvasSize == nil,
              let current = session.document.items.first(where: { $0.id == item.id }) else { return }
        selection = [current.id]
        var pending: (id: UUID, position: Double, original: Double?)?
        if let point, current.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let route = connectorDrawing(for: current)?.route, route.length > 0 {
            let position = route.nearest(to: EaselPoint(x: point.x, y: point.y)).arc / route.length
            if abs(position - current.resolvedLabelPosition) > 0.01 { pending = (current.id, min(1, max(0, position)), current.labelPosition) }
        }
        beginEditing(current, at: nil)
        guard editingID == current.id else { return }
        connectors.pendingLabel = pending
        if pending != nil, let text = editor { placeEditor(text, for: current); invalidateIncrementalDisplay(layout: true) }
    }

    func editConnectorLabel() {
        guard let item = selectedConnector else { return }
        beginConnectorLabelEditing(item, at: nil)
    }

    private func selectedConnectors() -> [EaselItem] {
        session.document.items.filter { selection.contains($0.id) && $0.kind == .arrow }
    }

    @discardableResult
    func updateSelectedConnectors(_ name: String, _ change: (inout EaselItem) -> Void) -> Bool {
        cancelPointerInteraction(); guard finishEditing() else { return false }
        let ids = Set(selectedConnectors().filter { !$0.isLocked }.map(\.id))
        guard !ids.isEmpty else { return false }
        var last: EaselItem?
        let saved = withObjectMotion(.restyle) { commit(name) { document in
            for index in document.items.indices where ids.contains(document.items[index].id) {
                change(&document.items[index])
                last = document.items[index]
            }
        } }
        if saved, let id = last?.id, let stored = session.document.items.first(where: { $0.id == id }) { rememberConnectorStyle(stored) }
        return saved
    }

    @discardableResult
    func setArrowHeads(start: EaselArrowHead? = nil, end: EaselArrowHead? = nil) -> Bool {
        guard start != nil || end != nil else { return false }
        return updateSelectedConnectors("Change arrowheads") { item in
            if let start { item.startHead = start == .none ? nil : start }
            if let end { item.endHead = end == .arrow ? nil : end }
        }
    }

    @discardableResult
    func swapArrowHeads() -> Bool {
        updateSelectedConnectors("Swap arrowheads") { item in
            let start = item.resolvedStartHead, end = item.resolvedEndHead
            item.startHead = end == .none ? nil : end
            item.endHead = start == .arrow ? nil : start
        }
    }

    @discardableResult
    func setConnectorRouting(_ routing: EaselConnectorRouting) -> Bool {
        updateSelectedConnectors("Change connector type") { item in
            item.routing = routing == .straight ? nil : routing
            item.waypoints = nil
        }
    }

    @discardableResult
    func setConnectorLabelBackground(_ enabled: Bool) -> Bool {
        guard !connectorSelection.isEmpty else { return false }
        return applyStyle(.labelBackground(enabled))
    }

    @discardableResult
    func resetConnectorPath() -> Bool {
        updateSelectedConnectors("Reset connector path") { item in item.waypoints = nil }
    }

    var connectorSelection: [EaselItem] { selectedConnectors() }
}

extension NSBezierPath {
    convenience init(connectorOutline easelPath: EaselPath) {
        self.init()
        for subpath in easelPath.subpaths(tolerance: 0.25) {
            guard let first = subpath.points.first else { continue }
            move(to: NSPoint(x: first.x, y: first.y))
            for point in subpath.points.dropFirst() { line(to: NSPoint(x: point.x, y: point.y)) }
            if subpath.closed { close() }
        }
    }
}

@MainActor
final class EaselMenuAction: NSObject {
    private let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func perform(_ sender: Any?) { run() }
}

extension EaselCanvasView {
    static func headTitle(_ head: EaselArrowHead) -> String {
        switch head {
        case .none: return "None"
        case .arrow: return "Line Arrow"
        case .solidArrow: return "Solid Arrow"
        case .triangle: return "Triangle"
        case .diamond: return "Diamond"
        case .circle: return "Circle"
        case .bar: return "Bar"
        case .erdOne: return "One"
        case .erdMany: return "Many"
        case .erdExactlyOne: return "Exactly One"
        case .erdZeroOrOne: return "Zero or One"
        case .erdOneOrMore: return "One or More"
        case .erdZeroOrMore: return "Zero or More"
        }
    }

    static func routingTitle(_ routing: EaselConnectorRouting) -> String {
        switch routing {
        case .straight: return "Straight"
        case .elbow: return "Elbow"
        case .curved: return "Curved"
        }
    }

    static let headGroups: [[EaselArrowHead]] = [[.none, .arrow, .solidArrow, .triangle, .diamond, .circle, .bar],
                                                 [.erdOne, .erdMany, .erdExactlyOne, .erdZeroOrOne, .erdOneOrMore, .erdZeroOrMore]]

    func editingFrame(for item: EaselItem) -> NSRect { item.kind == .arrow ? connectorEditingFrame(item) : rect(item) }

    var editingLabel: Bool {
        guard let id = editingID else { return false }
        return session.document.items.first(where: { $0.id == id })?.kind == .arrow
    }

    func accessibleConnectorControls(owner: NSWindow) -> [NSAccessibilityElement] {
        guard let item = selectedConnector, !item.isLocked, let drawing = connectorDrawing(for: item) else { return [] }
        return EaselArrowEndpoint.allCases.map { end in
            let point = end == .start ? drawing.route.start : drawing.route.end
            let radius = 10 / canvasScale
            let node = NSAccessibilityElement()
            node.setAccessibilityRole(.handle)
            node.setAccessibilityLabel(end == .start ? "Connector start" : "Connector end")
            node.setAccessibilityParent(self)
            node.setAccessibilityFrame(owner.convertToScreen(convert(NSRect(x: point.x - radius, y: point.y - radius,
                                                                            width: radius * 2, height: radius * 2), to: nil)))
            let moves: [(String, Double, Double)] = [("Move left", -1, 0), ("Move right", 1, 0), ("Move up", 0, -1), ("Move down", 0, 1)]
            node.setAccessibilityCustomActions(moves.map { name, dx, dy in
                NSAccessibilityCustomAction(name: name) { [weak self, weak owner] in
                    guard let self, let owner, self.window === owner,
                          let current = self.selectedConnector, current.id == item.id else { return false }
                    return self.moveConnectorEnd(end, of: current, dx: dx, dy: dy)
                }
            })
            return node
        }
    }

    @discardableResult
    func moveConnectorEnd(_ end: EaselArrowEndpoint, of item: EaselItem, dx: Double, dy: Double) -> Bool {
        guard !item.isLocked, let drawing = connectorDrawing(for: item) else { return false }
        let point = end == .start ? drawing.route.start : drawing.route.end
        let target = EaselPoint(x: max(0, point.x + dx), y: max(0, point.y + dy))
        let lookup = Dictionary(session.document.items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let next = EaselConnectorRouter.connecting(item, end: end, to: nil, at: target) { lookup[$0] }
        let saved = replaceConnector(item, with: next, name: "Move connector end")
        if saved { NSAccessibility.post(element: self, notification: .layoutChanged) }
        return saved
    }

    func makeConnectorMenu() -> NSMenuItem? {
        let chosen = connectorSelection.filter { !$0.isLocked }
        guard !chosen.isEmpty, fixedCanvasSize == nil else { return nil }
        let owner = window, expected = selection
        func add(_ title: String, to menu: NSMenu, checked: Bool = false, _ run: @escaping (EaselCanvasView) -> Void) {
            let action = EaselMenuAction { [weak self, weak owner] in
                guard let self, let owner, self.window === owner, self.selection == expected else { return }
                run(self)
            }
            let row = NSMenuItem(title: title, action: #selector(EaselMenuAction.perform(_:)), keyEquivalent: "")
            row.target = action; row.representedObject = action; row.state = checked ? .on : .off
            menu.addItem(row)
        }
        func submenu(_ title: String, in menu: NSMenu) -> NSMenu {
            let child = NSMenu(title: title)
            let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            row.submenu = child; menu.addItem(row)
            return child
        }
        let menu = NSMenu(title: "Connector")
        if chosen.count == 1, let only = chosen.first {
            add(only.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add Label" : "Edit Label", to: menu) { $0.editConnectorLabel() }
            menu.addItem(.separator())
        }
        let type = submenu("Type", in: menu)
        for routing in EaselConnectorRouting.allCases {
            add(Self.routingTitle(routing), to: type, checked: chosen.allSatisfy { $0.resolvedRouting == routing }) { _ = $0.setConnectorRouting(routing) }
        }
        for (title, isStart) in [("Start", true), ("End", false)] {
            let heads = submenu(title, in: menu)
            for (index, group) in Self.headGroups.enumerated() {
                if index > 0 { heads.addItem(.separator()) }
                for head in group {
                    let checked = chosen.allSatisfy { (isStart ? $0.resolvedStartHead : $0.resolvedEndHead) == head }
                    add(Self.headTitle(head), to: heads, checked: checked) { canvas in
                        _ = isStart ? canvas.setArrowHeads(start: head) : canvas.setArrowHeads(end: head)
                    }
                }
            }
        }
        add("Swap Ends", to: menu) { _ = $0.swapArrowHeads() }
        if chosen.contains(where: { $0.waypoints != nil }) {
            menu.addItem(.separator())
            add("Reset Path", to: menu) { _ = $0.resetConnectorPath() }
        }
        let row = NSMenuItem(title: "Connector", action: nil, keyEquivalent: "")
        row.submenu = menu
        return row
    }

    func connectorToolbarSupports(_ control: EaselToolbarControl, selected: [EaselItem]) -> Bool? {
        guard !selected.isEmpty, selected.allSatisfy({ $0.kind == .arrow }) else { return nil }
        switch control {
        case .connectorLabel: return selected.count == 1 && editor == nil
        case .startHead, .endHead, .routing: return editor == nil
        default: return nil
        }
    }

    func connectorToolbarButton(_ control: EaselToolbarControl, selected: [EaselItem]) -> EaselToolbarButtonModel? {
        guard !selected.isEmpty, selected.allSatisfy({ $0.kind == .arrow }) else { return nil }
        let unlocked = selected.allSatisfy { !$0.isLocked }
        switch control {
        case .connectorLabel:
            let empty = selected.first?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            return .init(control: control, face: .symbol("text.bubble"), name: empty ? "Add a label" : "Edit label", shortcut: "↩",
                         isEnabled: unlocked)
        case .startHead:
            return .init(control: control, face: .symbol("arrow.left"), name: "Start", isEnabled: unlocked, opens: .menu, showsDisclosure: true)
        case .endHead:
            return .init(control: control, face: .symbol("arrow.right"), name: "End", isEnabled: unlocked, opens: .menu, showsDisclosure: true)
        case .routing:
            let routing = Set(selected.map(\.resolvedRouting))
            let symbol: String
            switch routing.count == 1 ? routing.first : nil {
            case .elbow?: symbol = "arrow.turn.down.right"
            case .curved?: symbol = "point.topleft.down.curvedto.point.bottomright.up"
            default: symbol = "line.diagonal"
            }
            return .init(control: control, face: .symbol(symbol), name: "Connector type", isEnabled: unlocked, opens: .menu, showsDisclosure: true)
        default:
            return nil
        }
    }

    func connectorToolbarMenu(for control: EaselToolbarControl) -> [EaselToolbarMenuEntry]? {
        let chosen = connectorSelection
        guard !chosen.isEmpty else { return nil }
        switch control {
        case .startHead, .endHead:
            let start = control == .startHead
            var entries: [EaselToolbarMenuEntry] = []
            for (index, group) in Self.headGroups.enumerated() {
                for (offset, head) in group.enumerated() {
                    let checked = chosen.allSatisfy { (start ? $0.resolvedStartHead : $0.resolvedEndHead) == head }
                    entries.append(EaselToolbarMenuEntry(id: head.rawValue, title: Self.headTitle(head), isChecked: checked,
                                                         separatorBefore: index > 0 && offset == 0))
                }
            }
            entries.append(EaselToolbarMenuEntry(id: "swap", title: "Swap Ends", symbol: "arrow.left.arrow.right", separatorBefore: true))
            return entries
        case .routing:
            var entries = EaselConnectorRouting.allCases.map { routing in
                EaselToolbarMenuEntry(id: routing.rawValue, title: Self.routingTitle(routing),
                                      isChecked: chosen.allSatisfy { $0.resolvedRouting == routing })
            }
            if chosen.contains(where: { $0.waypoints != nil }) {
                entries.append(EaselToolbarMenuEntry(id: "reset", title: "Reset Path", symbol: "arrow.uturn.backward", separatorBefore: true))
            }
            return entries
        default:
            return nil
        }
    }

    func performConnectorToolbar(_ control: EaselToolbarControl) -> Bool? {
        guard control == .connectorLabel else { return nil }
        guard let item = selectedConnector else { return false }
        beginConnectorLabelEditing(item, at: nil)
        return editingID == item.id
    }

    func performConnectorToolbarMenu(_ control: EaselToolbarControl, entry id: String) -> Bool? {
        switch control {
        case .startHead, .endHead:
            if id == "swap" { return swapArrowHeads() }
            guard let head = EaselArrowHead(rawValue: id) else { return false }
            return control == .startHead ? setArrowHeads(start: head) : setArrowHeads(end: head)
        case .routing:
            if id == "reset" { return resetConnectorPath() }
            guard let routing = EaselConnectorRouting(rawValue: id) else { return false }
            return setConnectorRouting(routing)
        default:
            return nil
        }
    }
}

extension EaselCanvasView {
    static let centeredParagraph: NSParagraphStyle = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return paragraph
    }()

    func editorText(for item: EaselItem) -> NSAttributedString {
        guard item.kind == .arrow else { return displayedText(item) }
        let value = NSMutableAttributedString(attributedString: displayedText(item))
        value.addAttribute(.paragraphStyle, value: Self.centeredParagraph, range: NSRange(location: 0, length: value.length))
        return value
    }
}

extension EaselCanvasView {
    func connectorOverhang(_ item: EaselItem) -> NSRect {
        guard item.kind == .arrow else { return .null }
        let width = CGFloat(EaselPaintRules.strokeWidth(item))
        let reach = CGFloat(EaselPaintRules.arrowHeadLength(width: Double(width))) * 1.4 + width
        var bounds = rect(item).insetBy(dx: -reach, dy: -reach)
        if editingID == item.id || !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let label = connectors.routes[item.id]?.drawing.label {
                bounds = bounds.union(NSRect(x: label.x, y: label.y, width: label.width, height: label.height))
            }
            let spread = CGFloat(EaselConnectorLabel.maximumWidth / 2 + EaselConnectorLabel.paddingX + 2)
            bounds = bounds.union(rect(item).insetBy(dx: -spread, dy: -spread))
        }
        return bounds
    }
}

extension EaselCanvasView {
    func noteConnectorStyleChanges(from before: EaselDocument, to after: EaselDocument) {
        noteCanvasFeedback(from: before, to: after)
        guard before.id == after.id, after.items.contains(where: { $0.kind == .arrow }) else { return }
        let previous = Dictionary(before.items.filter { $0.kind == .arrow }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var latest: EaselConnectorStyle?
        for item in after.items where item.kind == .arrow {
            guard let old = previous[item.id] else { continue }
            let style = EaselConnectorStyle(item)
            if EaselConnectorStyle(old) != style { latest = style }
        }
        if let latest { EaselConnectorCanvasState.styles[after.id] = latest }
    }
}

struct EaselConnectorRevealFrame {
    var fraction: Double
    var opacity: CGFloat
    var startHead: (scale: CGFloat, opacity: CGFloat)?
    var endHead: (scale: CGFloat, opacity: CGFloat)?
    var label: (scale: CGFloat, opacity: CGFloat)?
}

private extension NSPoint {
    var easelPoint: EaselPoint { EaselPoint(x: x, y: y) }
}

extension EaselCanvasView {
    static let revealCrowd = 40

    @discardableResult
    func poppingConnectorHead<T>(_ pop: EaselConnectorPop, _ body: () -> T) -> T {
        let previous = canvasFeedback.handDrawn
        canvasFeedback.handDrawn = pop
        defer { canvasFeedback.handDrawn = previous }
        return body()
    }

    @discardableResult
    func revealingConnectors<T>(_ body: () -> T) -> T {
        let previous = canvasFeedback.revealsNew
        canvasFeedback.revealsNew = true
        defer { canvasFeedback.revealsNew = previous }
        return body()
    }

    func revealConnectors(_ ids: some Sequence<UUID>) {
        let wanted = Set(ids)
        let fresh = session.document.items.filter { wanted.contains($0.id) && $0.kind == .arrow }
        startConnectorReveal(fresh, drawsLine: true, startHead: true, endHead: true)
    }

    func noteNewConnectors(from before: EaselDocument, to after: EaselDocument) {
        let old = Set(before.items.lazy.filter { $0.kind == .arrow }.map(\.id))
        let fresh = after.items.filter { $0.kind == .arrow && !old.contains($0.id) }
        switch canvasFeedback.handDrawn {
        case .created?:
            startConnectorReveal(fresh, drawsLine: false, startHead: false, endHead: true)
        case .end(let end)?:
            let previous = Dictionary(before.items.filter { $0.kind == .arrow }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let moved = after.items.filter { item in
                guard item.kind == .arrow, let was = previous[item.id] else { return false }
                return end == .start ? was.startConnection != item.startConnection : was.endConnection != item.endConnection
            }
            startConnectorReveal(moved, drawsLine: false, startHead: end == .start, endHead: end == .end)
        case nil:
            guard !fresh.isEmpty else { return }
            var copies = Set<UUID>()
            switch objectMotion.intent {
            case .appear?: break
            case .copies(_, let made)?: copies = Set(made)
            default: guard canvasFeedback.revealsNew else { return }
            }
            startConnectorReveal(fresh.filter { !copies.contains($0.id) }, drawsLine: true, startHead: true, endHead: true)
        }
    }

    private func startConnectorReveal(_ connectors: [EaselItem], drawsLine: Bool, startHead: Bool, endHead: Bool) {
        guard !connectors.isEmpty, canAnimateObjects else { return }
        let reduced = feedbackReducesMotion
        let visible = visibleRect.isEmpty ? bounds : visibleRect
        var chosen = connectors
        if chosen.count > Self.revealCrowd {
            guard !reduced else { return }
            chosen = chosen.filter { displayBounds(of: $0).intersects(visible) }
        }
        if reduced, !drawsLine { return }
        let now = CACurrentMediaTime()
        for item in chosen {
            canvasFeedback.reveals[item.id] = .init(start: now, drawsLine: drawsLine, startHead: startHead, endHead: endHead, reduced: reduced)
        }
        startCanvasFeedback()
    }

    func presentedReveal(_ id: UUID) -> EaselConnectorRevealFrame? {
        guard let reveal = canvasFeedback.reveals[id] else { return nil }
        let elapsed = CACurrentMediaTime() - reveal.start
        if reveal.reduced {
            return EaselConnectorRevealFrame(fraction: 1, opacity: CGFloat(EaselFeedbackCurve.revealOpacity(elapsed, reduced: true)))
        }
        let line = reveal.drawsLine ? EaselFeedbackCurve.reveal : 0
        let head = elapsed - line
        let pop = (scale: CGFloat(EaselFeedbackCurve.headScale(head, reduced: false)),
                   opacity: CGFloat(head > 0 ? EaselFeedbackCurve.headOpacity(head, reduced: false) : 0))
        let lead = (scale: CGFloat(EaselFeedbackCurve.headScale(elapsed + 0.08, reduced: false)),
                    opacity: CGFloat(EaselFeedbackCurve.headOpacity(elapsed + 0.04, reduced: false)))
        return EaselConnectorRevealFrame(
            fraction: reveal.drawsLine ? EaselFeedbackCurve.revealFraction(elapsed, reduced: false) : 1,
            opacity: reveal.drawsLine ? CGFloat(EaselFeedbackCurve.revealOpacity(elapsed, reduced: false)) : 1,
            startHead: reveal.startHead ? (reveal.drawsLine ? lead : pop) : nil,
            endHead: reveal.endHead ? pop : nil,
            label: reveal.drawsLine ? pop : nil)
    }

    func magnetKey(_ magnet: EaselConnectorCanvasState.Magnet) -> EaselMagnetSnapKey {
        EaselMagnetSnapKey(target: magnet.target, place: magnet.pinned != nil ? "pin" : magnet.side?.rawValue ?? "outline")
    }

    func attachedMagnet(_ item: EaselItem, end: EaselArrowEndpoint) -> EaselConnectorCanvasState.Magnet? {
        guard let connection = end == .start ? item.startConnection : item.endConnection else { return nil }
        let points = EaselConnectorRouter.absolutePoints(item)
        let tip = (end == .start ? points.first : points.last) ?? EaselPoint(x: 0, y: 0)
        return EaselConnectorCanvasState.Magnet(target: connection.itemID, side: connection.side, pinned: connection.anchor == nil ? nil : tip)
    }

    func primeConnectorMagnet(_ magnet: EaselConnectorCanvasState.Magnet?) {
        canvasFeedback.magnetTicker.prime(Set([magnet.map(magnetKey)].compactMap { $0 }))
        canvasFeedback.movingMagnet = magnet
        canvasFeedback.glow = magnet.map { ($0.target, -.infinity) }
        if let magnet, magnet.pinned == nil, let side = magnet.side {
            canvasFeedback.dot = (magnet.target, side, -.infinity, 6)
        } else {
            canvasFeedback.dot = nil
        }
    }

    func noteConnectorMagnet() {
        let magnet = connectors.magnet, previous = canvasFeedback.movingMagnet
        canvasFeedback.movingMagnet = magnet
        canvasFeedback.magnetTicker.update(Set([magnet.map(magnetKey)].compactMap { $0 }))
        let now = CACurrentMediaTime()
        var animate = false
        if magnet?.target != previous?.target {
            canvasFeedback.glow = magnet.map { ($0.target, now) }
            animate = magnet != nil
        }
        let side = magnet?.pinned == nil ? magnet?.side : nil
        let oldSide = previous?.pinned == nil ? previous?.side : nil
        if let magnet, let side, side != oldSide || magnet.target != previous?.target {
            canvasFeedback.dot = (magnet.target, side, now, 4)
            animate = true
        } else if side == nil {
            canvasFeedback.dot = nil
        }
        if animate, !feedbackReducesMotion { startCanvasFeedback() }
    }

    func connectorGlowLevel(_ target: UUID) -> CGFloat? {
        guard let glow = canvasFeedback.glow, glow.target == target else { return nil }
        if feedbackReducesMotion { return 1 }
        return CGFloat(EaselFeedbackCurve.highlighted(CACurrentMediaTime() - glow.start, from: 0, to: 1))
    }

    func connectorDotRadius(target: UUID, side: EaselConnection.Side, active: Bool) -> CGFloat {
        guard active else { return 4 }
        guard let dot = canvasFeedback.dot, dot.target == target, dot.side == side, !feedbackReducesMotion else { return 6 }
        return CGFloat(EaselFeedbackCurve.highlighted(CACurrentMediaTime() - dot.start, from: dot.from, to: 6))
    }
}
