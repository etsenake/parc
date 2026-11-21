import AppKit

@MainActor
final class EaselCanvasBrushes {
    static var washiPattern = EaselWashi.defaultPattern
    var brush: EaselBrush = .marker
    var draftID = UUID()
    var erasing: Set<UUID> = []
    var lastEraserPoint: EaselPoint?
    var trail: [(point: EaselPoint, time: TimeInterval)] = []
    var trailTimer: Timer?
    var trailBounds = NSRect.null
}

@MainActor
enum EaselBrushArt {
    static let trailLife: TimeInterval = 0.32
    static let fadedOpacity: CGFloat = 0.2

    static func path(_ item: EaselItem) -> NSBezierPath {
        let origin = NSPoint(x: item.frame.x, y: item.frame.y), path = NSBezierPath()
        var current = origin
        func point(_ p: EaselPoint) -> NSPoint { NSPoint(x: origin.x + p.x, y: origin.y + p.y) }
        for element in EaselDrawing.smoothPath(item.points) {
            switch element {
            case .move(let p): current = point(p); path.move(to: current)
            case .line(let p): current = point(p); path.line(to: current)
            case .quad(let p, let control):
                let end = point(p), c = point(control)
                path.curve(to: end, controlPoint1: NSPoint(x: current.x + (c.x - current.x) * 2 / 3, y: current.y + (c.y - current.y) * 2 / 3),
                           controlPoint2: NSPoint(x: end.x + (c.x - end.x) * 2 / 3, y: end.y + (c.y - end.y) * 2 / 3))
                current = end
            }
        }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return path
    }

    static func cgPath(_ item: EaselItem) -> CGPath {
        let path = CGMutablePath()
        func point(_ p: EaselPoint) -> CGPoint { CGPoint(x: item.frame.x + p.x, y: item.frame.y + p.y) }
        for element in EaselDrawing.smoothPath(item.points) {
            switch element {
            case .move(let p): path.move(to: point(p))
            case .line(let p): path.addLine(to: point(p))
            case .quad(let p, let control): path.addQuadCurve(to: point(p), control: point(control))
            }
        }
        return path
    }

    static func draw(_ item: EaselItem, adaptive: Bool, dark: Bool, faded: Bool) {
        guard let context = NSGraphicsContext.current?.cgContext, !item.points.isEmpty else { return }
        context.saveGState(); defer { context.restoreGState() }
        if faded { context.setAlpha(fadedOpacity); context.beginTransparencyLayer(auxiliaryInfo: nil) }
        switch item.resolvedBrush {
        case .marker:
            EaselPaint(item, adaptive: adaptive).stroke(path(item))
        case .highlighter:
            context.setBlendMode(dark ? .normal : .multiply)
            EaselPaint(item, adaptive: adaptive).stroke(path(item), dashed: false)
        case .washi:
            if let placement = EaselWashi.placement(item) {
                drawTape(placement, pattern: EaselWashi.pattern(item), color: item.color, seed: EaselWashi.seed(item.id), in: context)
            }
        }
        if faded { context.endTransparencyLayer() }
    }

    static func drawTape(_ placement: EaselWashiPlacement, pattern: EaselWashiPattern, color: String, seed: UInt64, in context: CGContext) {
        let tile = EaselWashi.tile(pattern, color: color), half = EaselWashi.width / 2, length = placement.length
        let outline = EaselWashi.outline(length: length, seed: seed)
        context.saveGState(); defer { context.restoreGState() }
        context.translateBy(x: placement.origin.x, y: placement.origin.y)
        context.rotate(by: placement.angle)
        let shape = CGMutablePath()
        shape.addLines(between: outline.map { CGPoint(x: $0.x, y: $0.y) })
        shape.closeSubpath()
        context.setShadow(offset: .zero, blur: 1.6, color: NSColor.black.withAlphaComponent(0.16).cgColor)
        context.setAlpha(EaselWashi.opacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.addPath(shape)
        context.clip()
        let reach = EaselWashi.tooth * 2
        context.setFillColor(EaselInk.fixed(tile.base).cgColor)
        context.fill(CGRect(x: -reach, y: -half, width: length + 2 * reach, height: EaselWashi.width))
        var x = -tile.width
        while x < length + tile.width {
            drawTile(tile, at: CGPoint(x: x, y: -half), in: context)
            x += tile.width
        }
        context.setFillColor(EaselInk.fixed(EaselPalette.neutralLight).withAlphaComponent(0.3).cgColor)
        context.fill(CGRect(x: -reach, y: -half, width: length + 2 * reach, height: 1))
        context.setFillColor(EaselInk.fixed(EaselPalette.automaticInk).withAlphaComponent(0.08).cgColor)
        context.fill(CGRect(x: -reach, y: half - 1, width: length + 2 * reach, height: 1))
        context.endTransparencyLayer()
    }

    static func drawTile(_ tile: EaselWashiTile, at origin: CGPoint, in context: CGContext) {
        for mark in tile.marks {
            context.setFillColor(EaselInk.fixed(mark.color).withAlphaComponent(CGFloat(mark.opacity)).cgColor)
            switch mark.shape {
            case .rect(let r):
                context.fill(CGRect(x: origin.x + r.x, y: origin.y + r.y, width: r.width, height: r.height))
            case .circle(let center, let radius):
                context.fillEllipse(in: CGRect(x: origin.x + center.x - radius, y: origin.y + center.y - radius, width: radius * 2, height: radius * 2))
            case .polygon(let points):
                let path = CGMutablePath()
                path.addLines(between: points.map { CGPoint(x: origin.x + $0.x, y: origin.y + $0.y) })
                path.closeSubpath()
                context.addPath(path)
                context.fillPath()
            }
        }
    }

    static func swatch(_ pattern: EaselWashiPattern, color: String, size: NSSize) -> NSImage {
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let inset = EaselWashi.tooth + 2, scale = min(1, rect.height / (EaselWashi.width + 4))
            context.translateBy(x: rect.midX, y: rect.midY)
            context.scaleBy(x: scale, y: scale)
            context.rotate(by: -0.12)
            let length = rect.width / scale - inset * 2
            drawTape(EaselWashiPlacement(origin: EaselPoint(x: -length / 2, y: 0), angle: 0, length: length),
                     pattern: pattern, color: color, seed: UInt64(pattern.rawValue.utf8.count * 7919), in: context)
            return true
        }
        image.isTemplate = false
        return image
    }

    static let eraserCursor: NSCursor = {
        let diameter = EaselDrawing.eraserRadius * 2, side = diameter + 6
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let disc = NSRect(x: 3, y: 3, width: diameter, height: diameter)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = NSSize(width: 0, height: -0.5)
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.set()
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(ovalIn: disc).fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.withAlphaComponent(0.42).setStroke()
            let ring = NSBezierPath(ovalIn: disc.insetBy(dx: 0.5, dy: 0.5))
            ring.lineWidth = 1
            ring.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: side / 2, y: side / 2))
    }()
}

extension EaselCanvasView {
    func drawDrawing(_ item: EaselItem) {
        EaselBrushArt.draw(item, adaptive: adaptsInk, dark: NoteTheme.isDark(effectiveAppearance), faded: brushes.erasing.contains(item.id))
    }

    func drawBrushSelection(_ item: EaselItem) -> Bool {
        guard item.kind == .freehand, !item.points.isEmpty else { return false }
        let outline: CGPath
        let pad = CGFloat(3 / max(canvasScale, 0.2)), reach = CGFloat(EaselDrawing.reach(of: item)) + pad
        if item.resolvedBrush == .washi, let placement = EaselWashi.placement(item) {
            let shape = CGMutablePath(), overhang = CGFloat(EaselWashi.tooth) + pad
            shape.addRect(CGRect(x: -overhang, y: -reach, width: CGFloat(placement.length) + 2 * overhang, height: reach * 2),
                          transform: CGAffineTransform(translationX: placement.origin.x, y: placement.origin.y).rotated(by: placement.angle))
            outline = shape
        } else {
            outline = EaselBrushArt.cgPath(item).copy(strokingWithWidth: reach * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
        }
        guard let context = NSGraphicsContext.current?.cgContext else { return true }
        context.saveGState(); defer { context.restoreGState() }
        context.addPath(outline)
        context.setStrokeColor(EaselAppearance.selection.cgColor)
        context.setLineWidth(2 / canvasScale)
        context.strokePath()
        return true
    }

    func beginBrushStroke(_ brush: EaselBrush, at point: NSPoint, flags: NSEvent.ModifierFlags) {
        brushes.brush = brush
        brushes.draftID = UUID()
        stroke = [point]
        selection.removeAll()
        updateBrushDraft(flags: flags)
    }

    func dragBrushStroke(to point: NSPoint, flags: NSEvent.ModifierFlags) {
        guard let last = stroke.last, point.x.isFinite, point.y.isFinite else { return }
        let travel = hypot(point.x - last.x, point.y - last.y)
        if travel >= 1 / EaselDrawing.safeScale(canvasScale), stroke.count < EaselDrawing.maximumPoints {
            stroke.append(point)
        } else if stroke.count > 1, flags.contains(.shift) || brushes.brush.alwaysStraight {
            stroke[stroke.count - 1] = point
        }
        updateBrushDraft(flags: flags)
    }

    func refreshBrushStroke(flags: NSEvent.ModifierFlags) {
        guard drawing, start != nil, !stroke.isEmpty else { return }
        updateBrushDraft(flags: flags)
    }

    func endBrushStroke(flags: NSEvent.ModifierFlags) {
        updateBrushDraft(flags: flags, finishing: true)
        guard var item = draft?.first else { return }
        if item.resolvedBrush.sticksToObjects {
            item.attachedTo = EaselDrawing.attachmentTarget(for: EaselDrawing.visualPoints(item), in: session.document.items)
        }
        let name: String
        switch item.resolvedBrush {
        case .marker: name = "Draw"
        case .highlighter: name = "Highlight"
        case .washi: name = "Washi Tape"
        }
        if commit(name, { $0.items.append(item) }) { selectionBeforeGesture = [] }
    }

    func cancelBrushStroke() {
        brushes.lastEraserPoint = nil
        guard !brushes.erasing.isEmpty else { return }
        let faded = brushes.erasing
        brushes.erasing = []
        repaintDrawings(faded)
    }

    private func updateBrushDraft(flags: NSEvent.ModifierFlags, finishing: Bool = false) {
        guard let first = stroke.first, let last = stroke.last else { draft = nil; return }
        let brush = brushes.brush
        let start = EaselPoint(x: first.x, y: first.y)
        let absolute: [EaselPoint]
        if brush.alwaysStraight || flags.contains(.shift) {
            let end = EaselDrawing.straightEnd(from: start, to: EaselPoint(x: last.x, y: last.y), strict: brush.alwaysStraight && flags.contains(.shift))
            if brush == .washi && hypot(end.x - start.x, end.y - start.y) < 4 { draft = nil; invalidateIncrementalDisplay(); return }
            absolute = [start, end]
        } else {
            let raw = stroke.map { EaselPoint(x: $0.x, y: $0.y) }
            absolute = finishing ? EaselDrawing.finished(raw, scale: canvasScale) : (raw.count == 1 ? [start, start] : raw)
        }
        guard let placed = EaselDrawing.geometry(absolute) else { draft = nil; invalidateIncrementalDisplay(); return }
        var item = EaselItem(kind: .freehand, frame: placed.frame, zIndex: (original.map(\.zIndex).max() ?? 0) + 1,
                             color: insertionColor, points: placed.points)
        item.id = brushes.draftID
        item.brush = brush == .marker ? nil : brush
        item.pattern = brush == .washi ? EaselWashi.storedName(EaselCanvasBrushes.washiPattern) : nil
        draft = [item]
        invalidateIncrementalDisplay()
    }

    func beginErasing(at point: NSPoint) {
        selection.removeAll()
        brushes.erasing = []
        draft = []
        let location = EaselPoint(x: point.x, y: point.y)
        brushes.lastEraserPoint = location
        erase(from: location, to: location)
        extendEraserTrail(to: location)
    }

    func continueErasing(to point: NSPoint) {
        let location = EaselPoint(x: point.x, y: point.y)
        erase(from: brushes.lastEraserPoint ?? location, to: location)
        brushes.lastEraserPoint = location
        extendEraserTrail(to: location)
    }

    func endErasing() {
        let ids = brushes.erasing.intersection(session.document.items.map(\.id))
        brushes.erasing = []
        brushes.lastEraserPoint = nil
        guard !ids.isEmpty else { repaintDrawings(ids); return }
        if !commit("Erase", { $0 = EaselDependents.removing(ids, from: $0) }) { repaintDrawings(ids) }
    }

    func setWashiPattern(_ pattern: EaselWashiPattern) {
        EaselCanvasBrushes.washiPattern = pattern
        let ids = Set(session.document.items.filter {
            selection.contains($0.id) && $0.kind == .freehand && $0.resolvedBrush == .washi && !$0.isLocked
        }.map(\.id))
        guard !ids.isEmpty, finishImageEditing() else { return }
        commit("Change Tape") { document in
            for index in document.items.indices where ids.contains(document.items[index].id) {
                document.items[index].pattern = EaselWashi.storedName(pattern)
            }
        }
    }

    var selectedWashiPattern: EaselWashiPattern? {
        let patterns = Set(session.document.items.filter {
            selection.contains($0.id) && $0.kind == .freehand && $0.resolvedBrush == .washi
        }.map(EaselWashi.pattern))
        return patterns.count == 1 ? patterns.first : nil
    }

    func drawBrushOverlay(in dirtyRect: NSRect) {
        let now = ProcessInfo.processInfo.systemUptime
        let live = brushes.trail.filter { now - $0.time < EaselBrushArt.trailLife }
        guard live.count > 1, brushes.trailBounds.intersects(dirtyRect), let context = NSGraphicsContext.current?.cgContext else { return }
        let radius = CGFloat(EaselDrawing.eraserRadius(scale: canvasScale))
        context.saveGState(); defer { context.restoreGState() }
        context.setAlpha(0.3)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setStrokeColor(EaselAppearance.guide.cgColor)
        context.setLineCap(.round)
        for (from, to) in zip(live, live.dropFirst()) {
            let freshness = CGFloat(max(0, 1 - (now - to.time) / EaselBrushArt.trailLife))
            context.setLineWidth(radius * 2 * (0.25 + 0.75 * freshness))
            context.move(to: CGPoint(x: from.point.x, y: from.point.y))
            context.addLine(to: CGPoint(x: to.point.x, y: to.point.y))
            context.strokePath()
        }
        context.endTransparencyLayer()
    }

    private func erase(from a: EaselPoint, to b: EaselPoint) {
        let candidates = session.document.items.filter { !brushes.erasing.contains($0.id) }
        let hits = EaselDrawing.erased(candidates, from: a, to: b, scale: canvasScale)
        guard !hits.isEmpty else { return }
        brushes.erasing.formUnion(hits)
        repaintDrawings(hits)
    }

    private func repaintDrawings(_ ids: Set<UUID>) {
        for item in session.document.items where ids.contains(item.id) {
            setNeedsDisplay(displayBounds(of: item))
            artwork[item.id]?.needsDisplay = true
        }
    }

    private func extendEraserTrail(to point: EaselPoint) {
        guard !NoteTheme.reduceMotion else { return }
        brushes.trail.append((point, ProcessInfo.processInfo.systemUptime))
        refreshEraserTrail()
        guard brushes.trailTimer == nil else { return }
        brushes.trailTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshEraserTrail() }
        }
    }

    private func refreshEraserTrail() {
        let now = ProcessInfo.processInfo.systemUptime
        brushes.trail.removeAll { now - $0.time >= EaselBrushArt.trailLife }
        let previous = brushes.trailBounds
        var next = NSRect.null
        let pad = CGFloat(EaselDrawing.eraserRadius(scale: canvasScale)) + 2
        for entry in brushes.trail {
            next = next.union(NSRect(x: entry.point.x - pad, y: entry.point.y - pad, width: pad * 2, height: pad * 2))
        }
        brushes.trailBounds = next
        let dirty = previous.union(next)
        if !dirty.isNull {
            setNeedsDisplay(dirty)
            decoration.setNeedsDisplay(dirty)
        }
        if brushes.trail.isEmpty || window == nil {
            brushes.trailTimer?.invalidate()
            brushes.trailTimer = nil
            if window == nil { brushes.trail = []; brushes.trailBounds = .null }
        }
    }
}
