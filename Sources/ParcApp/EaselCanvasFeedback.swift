import AppKit
import QuartzCore
import ParcCore

enum EaselConnectorPop: Equatable {
    case created
    case end(EaselArrowEndpoint)
}

struct EaselMagnetSnapKey: Hashable {
    let target: UUID
    let place: String
}

@MainActor
final class EaselCanvasFeedbackState {
    struct Reveal {
        var start: TimeInterval
        var drawsLine: Bool
        var startHead: Bool
        var endHead: Bool
        var reduced: Bool
    }

    struct Tray {
        var start: TimeInterval
        var from: Double
        var rising: Bool
    }

    struct Fold {
        var item: EaselItem
        var offset: EaselPoint
        var start: TimeInterval
        var reduced: Bool
    }

    struct Growth {
        var from: Double
        var to: Double
        var start: TimeInterval
        var result: EaselItem
    }

    var guideTicker = EaselSnapTicker<EaselGuideSnapKey>()
    var rotationTicker = EaselSnapTicker<Int>()
    var magnetTicker = EaselSnapTicker<EaselMagnetSnapKey>()
    var guideStarts: [EaselGuideSnapKey: TimeInterval] = [:]
    var guideEngaged: Set<EaselGuideSnapKey> = []
    var sizeLines: [EaselAlignmentGuides.Line] = []
    var guideReduced = false
    var reveals: [UUID: Reveal] = [:]
    var handDrawn: EaselConnectorPop?
    var revealsNew = false
    var movingMagnet: EaselConnectorCanvasState.Magnet?
    var glow: (target: UUID, start: TimeInterval)?
    var dot: (target: UUID, side: EaselConnection.Side, start: TimeInterval, from: Double)?
    var trayTarget: UUID?
    var trays: [UUID: Tray] = [:]
    var flashes: [UUID: TimeInterval] = [:]
    var folds: [Fold] = []
    var growths: [UUID: Growth] = [:]
    var tables: [UUID: EaselTableSlide] = [:]
    var paintsLive = 0
    var driver: EaselCanvasFrameDriver?
    var envelope = NSRect.null
    var pageOverlay: EaselCanvasPageFlipOverlay?
    var extendedSurfaces: Set<UUID> = []

    var animating: Bool {
        let now = CACurrentMediaTime()
        let highlighting = [glow?.start, dot?.start].contains { $0.map { now - $0 < EaselFeedbackCurve.highlight } == true }
        return !guideStarts.isEmpty || !reveals.isEmpty || highlighting || !trays.isEmpty || !flashes.isEmpty
            || !folds.isEmpty || !growths.isEmpty || !tables.isEmpty
    }
}

@MainActor
final class EaselCanvasPageFlipOverlay: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension EaselCanvasView {
    var feedbackReducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var paintsLiveFeedback: Bool { canvasFeedback.paintsLive > 0 }

    func paintingLive(_ body: () -> Void) {
        canvasFeedback.paintsLive += 1
        defer { canvasFeedback.paintsLive -= 1 }
        body()
    }

    func startCanvasFeedback() {
        guard canvasFeedback.animating else { return }
        if canvasFeedback.driver == nil {
            canvasFeedback.driver = EaselCanvasFrameDriver { [weak self] in self?.canvasFeedbackFrame() ?? false }
        }
        canvasFeedback.driver?.start(in: self)
        canvasFeedbackFrame()
    }

    @discardableResult
    func canvasFeedbackFrame() -> Bool {
        let now = CACurrentMediaTime()
        pruneCanvasFeedback(at: now)
        refreshFeedbackSurfaces()
        updateStickyEditorMask()
        let current = canvasFeedbackEnvelope()
        presentCanvasFeedbackDirty(canvasFeedback.envelope.union(current))
        canvasFeedback.envelope = current
        let active = canvasFeedback.animating
        if !active { canvasFeedback.envelope = .null }
        return active
    }

    func settleCanvasFeedback() {
        let dirty = canvasFeedback.envelope.union(canvasFeedbackEnvelope())
        canvasFeedback.guideStarts.removeAll()
        canvasFeedback.reveals.removeAll()
        canvasFeedback.glow = nil
        canvasFeedback.dot = nil
        canvasFeedback.trays.removeAll()
        canvasFeedback.flashes.removeAll()
        canvasFeedback.folds.removeAll()
        canvasFeedback.growths.removeAll()
        canvasFeedback.tables.removeAll()
        refreshFeedbackSurfaces()
        updateStickyEditorMask()
        canvasFeedback.driver?.stop()
        canvasFeedback.driver = nil
        canvasFeedback.envelope = .null
        settlePageFlip()
        presentCanvasFeedbackDirty(dirty)
    }

    func resetSnapFeedback() {
        canvasFeedback.guideTicker.reset()
        canvasFeedback.rotationTicker.reset()
        canvasFeedback.magnetTicker.reset()
        canvasFeedback.movingMagnet = nil
        canvasFeedback.glow = nil
        canvasFeedback.dot = nil
        canvasFeedback.guideStarts.removeAll()
        canvasFeedback.guideEngaged.removeAll()
        canvasFeedback.sizeLines.removeAll()
        endSectionCarry()
    }

    private func pruneCanvasFeedback(at now: TimeInterval) {
        let state = canvasFeedback
        let guideSpan = state.guideReduced ? EaselFeedbackCurve.guideFade : max(EaselFeedbackCurve.guideFade, EaselFeedbackCurve.markPop)
        if state.guideStarts.values.allSatisfy({ now - $0 >= guideSpan }) { state.guideStarts.removeAll() }
        state.reveals = state.reveals.filter { _, reveal in
            !EaselFeedbackCurve.revealFinished(now - reveal.start, reduced: reveal.reduced, drawsLine: reveal.drawsLine)
        }
        state.trays = state.trays.filter { now - $0.value.start < EaselFeedbackCurve.tray }
        state.flashes = state.flashes.filter { now - $0.value < EaselFeedbackCurve.flash }
        state.folds.removeAll { now - $0.start >= ($0.reduced ? EaselFeedbackCurve.reducedFade : EaselFeedbackCurve.fold) }
        state.growths = state.growths.filter { now - $0.value.start < EaselFeedbackCurve.grow }
        state.tables = state.tables.filter { now - $0.value.start < EaselFeedbackCurve.tableSlide }
    }

    func feedbackSurfaceExtent(_ item: EaselItem) -> NSRect {
        var extent = NSRect.null
        if let slide = canvasFeedback.tables[item.id] { extent = extent.union(slide.previousBounds) }
        if item.kind == .section, canvasFeedback.trayTarget == item.id || canvasFeedback.trays[item.id] != nil
            || canvasFeedback.flashes[item.id] != nil {
            extent = extent.union(rect(item).insetBy(dx: -6, dy: -6))
        }
        if let growth = canvasFeedback.growths[item.id] {
            var box = displayBounds(of: item)
            let tallest = max(growth.from, growth.to) * 1.02 + 2
            box.size.height += CGFloat(max(0, tallest - item.frame.height))
            extent = extent.union(box)
        }
        return extent
    }

    private func refreshFeedbackSurfaces() {
        let ids = Set(canvasFeedback.growths.keys).union(canvasFeedback.tables.keys)
        guard ids != canvasFeedback.extendedSurfaces else { return }
        let changed = ids.symmetricDifference(canvasFeedback.extendedSurfaces)
        canvasFeedback.extendedSurfaces = ids
        guard usesObjectSurfaces else { return }
        needsLayout = true
        for id in changed { artwork[id]?.needsDisplay = true }
    }

    private var feedbackObjectIDs: Set<UUID> {
        let state = canvasFeedback
        var ids = Set(state.reveals.keys).union(state.flashes.keys).union(state.growths.keys).union(state.tables.keys)
        ids.formUnion(state.trays.keys)
        return ids
    }

    private func canvasFeedbackEnvelope() -> NSRect {
        var dirty = NSRect.null
        let ids = feedbackObjectIDs
        if !ids.isEmpty {
            for item in session.document.items where ids.contains(item.id) {
                dirty = dirty.union(displayBounds(of: item)).union(feedbackSurfaceExtent(item))
            }
        }
        for fold in canvasFeedback.folds {
            let box = displayBounds(of: fold.item)
            dirty = dirty.union(box).union(box.offsetBy(dx: fold.offset.x, dy: fold.offset.y))
        }
        if !canvasFeedback.guideStarts.isEmpty { dirty = dirty.union(guideFeedbackBounds()) }
        if canvasFeedback.glow != nil || canvasFeedback.dot != nil { dirty = dirty.union(connectorChromeBounds()) }
        return dirty
    }

    private func presentCanvasFeedbackDirty(_ rect: NSRect) {
        if usesObjectSurfaces {
            for id in feedbackObjectIDs { artwork[id]?.needsDisplay = true }
        }
        guard !rect.isNull, rect.width.isFinite, rect.height.isFinite else { return }
        if usesObjectSurfaces { decoration.setNeedsDisplay(rect) } else { setNeedsDisplay(rect) }
    }

    func noteCanvasFeedback(from before: EaselDocument, to after: EaselDocument) {
        guard before.id == after.id else { return }
        noteNewConnectors(from: before, to: after)
        noteStickyGrowth(from: before, to: after)
        settleStaleFeedback(in: after)
    }

    func settleStaleFeedback(in document: EaselDocument? = nil) {
        guard !canvasFeedback.tables.isEmpty || !canvasFeedback.growths.isEmpty else { return }
        let current = Dictionary((document ?? session.document).items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let staleTables = canvasFeedback.tables.filter { current[$0.key] != $0.value.result }.map(\.key)
        let staleGrowths = canvasFeedback.growths.filter { current[$0.key]?.frame != $0.value.result.frame }.map(\.key)
        guard !staleTables.isEmpty || !staleGrowths.isEmpty else { return }
        var dirty = NSRect.null
        for id in staleTables {
            if let item = current[id] { dirty = dirty.union(displayBounds(of: item)).union(feedbackSurfaceExtent(item)) }
            if let slide = canvasFeedback.tables.removeValue(forKey: id) { dirty = dirty.union(slide.previousBounds) }
        }
        for id in staleGrowths {
            if let item = current[id] { dirty = dirty.union(feedbackSurfaceExtent(item)) }
            canvasFeedback.growths.removeValue(forKey: id)
        }
        refreshFeedbackSurfaces()
        updateStickyEditorMask()
        presentCanvasFeedbackDirty(dirty)
    }

    func noteGuideFeedback(_ lines: [EaselAlignmentGuides.Line]) {
        let keys = Set(lines.map(EaselGuideSnapKey.init))
        canvasFeedback.guideTicker.update(keys)
        let now = CACurrentMediaTime()
        var started = false
        for key in keys.subtracting(canvasFeedback.guideEngaged) {
            canvasFeedback.guideStarts[key] = now; started = true
        }
        canvasFeedback.guideEngaged = keys
        for key in Array(canvasFeedback.guideStarts.keys) where !keys.contains(key) { canvasFeedback.guideStarts.removeValue(forKey: key) }
        guard started else { return }
        canvasFeedback.guideReduced = feedbackReducesMotion
        startCanvasFeedback()
    }

    func equalSizeSnap(_ proposal: [EaselItem]?, edit: EaselGeometryEdit, handle: EaselResizeHandle?, centered: Bool,
                       enabled: Bool) -> [EaselItem]? {
        canvasFeedback.sizeLines = []
        guard enabled, fixedCanvasSize == nil, let handle, var result = proposal, result.count == 1, let item = result.first,
              EaselEqualSize.resizes(item.kind), !EaselRotation.isRotated(item), !edit.resizesRotated else { return proposal }
        let engaged = currentGuideLines
        let lockedX = engaged.contains { $0.anchor.horizontal }, lockedY = engaged.contains { !$0.anchor.horizontal }
        let v = visibleRect
        let viewport = EaselRect(x: v.minX, y: v.minY, width: v.width, height: v.height)
        let others = EaselEqualSize.candidates(items, excluding: item.id, viewport: viewport)
        guard !others.isEmpty else { return proposal }
        let snapped = EaselEqualSize.snap(item, handle: handle, centered: centered, candidates: others, scale: canvasScale,
                                          lockedX: lockedX, lockedY: lockedY)
        result[0] = snapped.item
        canvasFeedback.sizeLines = EaselEqualSize.lines(snapped.item, matches: snapped.matches, in: others, scale: canvasScale)
        return result
    }

    func noteRotationSnap(_ degrees: Double?) {
        canvasFeedback.rotationTicker.update(Set([degrees.flatMap(EaselRotationSnap.step)].compactMap { $0 }))
    }

    func primeRotationSnap(_ degrees: Double) {
        canvasFeedback.rotationTicker.prime(Set([EaselRotationSnap.step(degrees)].compactMap { $0 }))
    }

    private func guideFeedbackBounds() -> NSRect {
        var dirty = NSRect.null
        let pad = 6 / max(canvasScale, 0.2)
        for line in currentGuideLines {
            for segment in line.targetSegments + line.anchorSegments {
                let length = hypot(segment.end.x - segment.start.x, segment.end.y - segment.start.y)
                let grow = CGFloat(length * 0.12) + pad
                let box = NSRect(x: min(segment.start.x, segment.end.x), y: min(segment.start.y, segment.end.y),
                                 width: abs(segment.end.x - segment.start.x), height: abs(segment.end.y - segment.start.y))
                dirty = dirty.union(box.insetBy(dx: -grow, dy: -grow))
            }
        }
        return dirty
    }

    func drawGuideLines(_ lines: [EaselAlignmentGuides.Line]) {
        let now = CACurrentMediaTime()
        let reduced = canvasFeedback.guideReduced
        for line in lines {
            let started = canvasFeedback.guideStarts[EaselGuideSnapKey(line)]
            let elapsed = started.map { now - $0 } ?? .infinity
            let opacity = CGFloat(EaselFeedbackCurve.guideOpacity(elapsed))
            let mark = CGFloat(EaselFeedbackCurve.markScale(elapsed, reduced: reduced))
            guard opacity > 0 else { continue }
            let target = NSBezierPath(), anchor = NSBezierPath()
            for path in [target, anchor] {
                path.lineWidth = 2.5 / canvasScale; path.lineCapStyle = .round; path.lineJoinStyle = .round
            }
            for segment in line.targetSegments {
                target.move(to: NSPoint(x: segment.start.x, y: segment.start.y))
                target.line(to: NSPoint(x: segment.end.x, y: segment.end.y))
            }
            for segment in line.anchorSegments {
                let mid = NSPoint(x: (segment.start.x + segment.end.x) / 2, y: (segment.start.y + segment.end.y) / 2)
                anchor.move(to: NSPoint(x: mid.x + (segment.start.x - mid.x) * mark, y: mid.y + (segment.start.y - mid.y) * mark))
                anchor.line(to: NSPoint(x: mid.x + (segment.end.x - mid.x) * mark, y: mid.y + (segment.end.y - mid.y) * mark))
            }
            EaselAppearance.guide.withAlphaComponent(EaselAppearance.guide.alphaComponent * opacity).setStroke(); target.stroke()
            EaselAppearance.selection.withAlphaComponent(EaselAppearance.selection.alphaComponent * opacity).setStroke(); anchor.stroke()
        }
    }

    func withPresentation(_ presentation: EaselObjectPresentation, around center: NSPoint, _ body: () -> Void) {
        guard !presentation.isIdentity, let context = NSGraphicsContext.current?.cgContext else { body(); return }
        context.saveGState()
        context.setAlpha(CGFloat(max(0, min(1, presentation.opacity))))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.translateBy(x: center.x + CGFloat(presentation.offset.x), y: center.y + CGFloat(presentation.offset.y))
        context.scaleBy(x: CGFloat(presentation.scale), y: CGFloat(presentation.scale))
        context.translateBy(x: -center.x, y: -center.y)
        body()
        context.endTransparencyLayer()
        context.restoreGState()
    }
}
