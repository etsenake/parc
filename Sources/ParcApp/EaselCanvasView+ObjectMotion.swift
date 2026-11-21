import AppKit
import QuartzCore

enum EaselObjectMotionIntent {
    case appear
    case vanish
    case copies(sources: [UUID], copies: [UUID])
    case arrange
    case layer(forward: Bool, ids: Set<UUID>)
    case restyle
    case history
}

@MainActor
final class EaselCanvasObjectMotionState {
    static let chromeDuration: TimeInterval = 0.1
    static let handleGrowth: CGFloat = 1.35
    static let crowd = 40
    var timeline = EaselObjectMotion()
    var intent: EaselObjectMotionIntent?
    var pendingSurfaces: Set<UUID> = []
    var chromeSelection = Set<UUID>()
    var chromeFading = Set<UUID>()
    var chromeStart: TimeInterval?
    var hoverID: UUID?
    var hoverStart: TimeInterval?
    var hoveredHandle: EaselResizeHandle?
    var handleGrowth: [EaselResizeHandle: (from: CGFloat, to: CGFloat, start: TimeInterval)] = [:]
    var driver: EaselCanvasFrameDriver?
    var envelope = NSRect.null
    var retiring: [UUID: NSView] = [:]
    var burst: EaselCanvasBurst?
    var carriedSurfaces: Set<UUID> = []
    var lockedPress: UUID?
    var refusedThisGesture = false

    var animatesChrome: Bool { chromeStart != nil || hoverStart != nil || !handleGrowth.isEmpty }
}

extension EaselCanvasView {
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var canAnimateObjects: Bool {
        window != nil && !isHiddenOrHasHiddenAncestor && canPresentMotion && !motion.isInteracting
    }

    @discardableResult
    func withObjectMotion<T>(_ intent: EaselObjectMotionIntent, _ body: () -> T) -> T {
        let previous = objectMotion.intent
        objectMotion.intent = intent
        defer { objectMotion.intent = previous }
        return body()
    }

    func recordObjectMotion(from before: EaselDocument, to after: EaselDocument) {
        guard let intent = objectMotion.intent else { return }
        objectMotion.intent = nil
        guard canAnimateObjects else { return }
        let now = CACurrentMediaTime(), reduced = reduceMotion
        var frames: [UUID: EaselItem] = [:]
        for item in before.items { frames[item.id] = item }
        for item in after.items { frames[item.id] = item }
        let visible = visibleRect.isEmpty ? bounds : visibleRect
        func onScreen(_ id: UUID) -> Bool { frames[id].map { displayBounds(of: $0).intersects(visible) } ?? false }
        func admitted(_ ids: [UUID]) -> Set<UUID> {
            let candidates = ids.filter { frames[$0]?.ownsEmbeddedPage == false }
            guard candidates.count > EaselCanvasObjectMotionState.crowd else { return Set(candidates) }
            guard !reduced else { return [] }
            return Set(candidates.filter(onScreen))
        }
        func cascade(_ ids: some Collection<UUID>) -> [UUID: TimeInterval] {
            guard ids.count > 1 else { return [:] }
            var boxes: [UUID: EaselRect] = [:]
            for id in ids { if let item = frames[id] { boxes[id] = item.frame } }
            return EaselObjectMotion.cascade(boxes)
        }
        var touched = Set<UUID>()
        switch intent {
        case .appear:
            let ordered = EaselObjectMotion.added(from: before, to: after)
            let added = admitted(ordered)
            var entrances: [UUID: EaselObjectEntrance] = [:]
            for id in added { if let item = frames[id] { entrances[id] = EaselObjectEntrance.of(item) } }
            let delays = cascade(added)
            objectMotion.timeline.appear(entrances, delays: delays, at: now, reduced: reduced)
            touched.formUnion(added)
            let stamps = ordered.filter { added.contains($0) && frames[$0]?.kind == .stamp && onScreen($0) }
            for id in stamps.prefix(EaselBurstPlan.perCommand) {
                guard let item = frames[id] else { continue }
                splashStamp(item, delay: delays[id] ?? 0)
            }
        case .vanish:
            let removed = EaselObjectMotion.removed(from: before, to: after)
            let leaving = admitted(removed.map(\.id))
            let ghosts = removed.filter { leaving.contains($0.id) }
            objectMotion.timeline.vanish(ghosts, at: now, reduced: reduced)
            touched.formUnion(leaving)
            for item in ghosts.filter({ onScreen($0.id) }).prefix(EaselBurstPlan.perCommand) {
                playCanvasBurst(.puff, around: EaselCanvasRotation.bounds(item), tint: color(item.color))
            }
        case .copies(let sources, let copies):
            let all = EaselObjectMotion.copyOffsets(sources: sources, copies: copies, before: before, after: after)
            let added = EaselObjectMotion.added(from: before, to: after)
            let chosen = admitted(added)
            let offsets = all.filter { chosen.contains($0.key) }
            let delays = cascade(offsets.keys)
            objectMotion.timeline.glide(offsets, fades: true, lands: true, delays: delays, at: now, reduced: reduced)
            let rest = added.filter { offsets[$0] == nil && chosen.contains($0) }
            objectMotion.timeline.appear(rest, at: now, reduced: reduced)
            touched.formUnion(offsets.keys); touched.formUnion(rest)
        case .arrange:
            let all = EaselObjectMotion.moves(from: before, to: after)
            let chosen = admitted(Array(all.keys))
            let offsets = all.filter { chosen.contains($0.key) }
            objectMotion.timeline.glide(offsets, fades: false, at: now, reduced: reduced)
            touched.formUnion(offsets.keys)
        case .layer(let forward, let ids):
            let moved = admitted(Array(ids))
            objectMotion.timeline.lift(moved, from: forward ? 1.03 : 0.97, at: now, reduced: reduced)
            touched.formUnion(moved)
        case .restyle:
            let previous = EaselObjectMotion.restyled(from: before, to: after)
            let chosen = admitted(previous.map(\.id))
            objectMotion.timeline.restyle(previous.filter { chosen.contains($0.id) }, at: now, reduced: reduced)
            touched.formUnion(chosen)
        case .history:
            let change = EaselObjectMotion.history(from: before, to: after)
            guard !change.isEmpty else { return }
            let added = admitted(change.added)
            var entrances: [UUID: EaselObjectEntrance] = [:]
            for id in added { entrances[id] = .quick }
            objectMotion.timeline.appear(entrances, at: now, reduced: reduced)
            let leaving = admitted(change.removed.map(\.id))
            objectMotion.timeline.vanish(change.removed.filter { leaving.contains($0.id) }, at: now, reduced: reduced)
            let moving = admitted(Array(Set(change.offsets.keys).union(change.stretches.keys).union(change.turns.keys)))
            objectMotion.timeline.glide(change.offsets.filter { moving.contains($0.key) }, fades: false,
                                        stretches: change.stretches.filter { moving.contains($0.key) },
                                        turns: change.turns.filter { moving.contains($0.key) }, at: now, reduced: reduced)
            let restyled = admitted(change.restyled.map(\.id))
            objectMotion.timeline.restyle(change.restyled.filter { restyled.contains($0.id) }, at: now, reduced: reduced)
            touched = added.union(leaving).union(moving).union(restyled)
        }
        guard !touched.isEmpty else { return }
        objectMotion.pendingSurfaces.formUnion(touched)
        startObjectMotionDriver()
        objectMotionFrame()
    }

    func applyHistory(_ step: () throws -> Void) throws {
        let before = session.document
        try step()
        guard before != session.document else { return }
        withObjectMotion(.history) { recordObjectMotion(from: before, to: session.document) }
    }

    func pulseObjects(_ ids: Set<UUID>) {
        guard canAnimateObjects else { return }
        let shown = items.filter { ids.contains($0.id) }
        guard !shown.isEmpty else { return }
        let visible = visibleRect.isEmpty ? bounds : visibleRect
        let chosen = shown.count > EaselCanvasObjectMotionState.crowd ? shown.filter { displayBounds(of: $0).intersects(visible) } : shown
        let reduced = reduceMotion
        let movable = chosen.filter { !$0.ownsEmbeddedPage }.map(\.id)
        objectMotion.timeline.pulse(movable, at: CACurrentMediaTime(), reduced: reduced)
        for item in chosen.prefix(EaselBurstPlan.perCommand) {
            playCanvasBurst(.glow, around: EaselCanvasRotation.bounds(item), tint: EaselAppearance.selection)
        }
        guard !reduced, !movable.isEmpty else { return }
        objectMotion.pendingSurfaces.formUnion(movable)
        startObjectMotionDriver()
        needsLayout = true
        objectMotionFrame()
    }

    func shakeObjects(_ ids: Set<UUID>) {
        guard canAnimateObjects, !reduceMotion else { return }
        let shaken = items.filter { ids.contains($0.id) && !$0.ownsEmbeddedPage }.map(\.id)
        guard !shaken.isEmpty else { return }
        objectMotion.timeline.shake(shaken, at: CACurrentMediaTime(), reduced: false)
        objectMotion.pendingSurfaces.formUnion(shaken)
        startObjectMotionDriver()
        needsLayout = true
        objectMotionFrame()
    }

    func refuseLocked(_ ids: Set<UUID>) {
        let locked = Set(session.document.items.filter { ids.contains($0.id) && $0.isLocked }.map(\.id))
        guard !locked.isEmpty else { return }
        shakeObjects(locked)
        if let event = NSApp.currentEvent, [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseUp].contains(event.type) {
            EaselCanvasHaptics.refuse()
        }
    }

    func noteLockedPress(at point: NSPoint) {
        objectMotion.refusedThisGesture = false
        objectMotion.lockedPress = nil
        guard let hit = object(at: point, includingLocked: true), hit.isLocked, selection.contains(hit.id) else { return }
        objectMotion.lockedPress = hit.id
    }

    func refuseLockedDrag(to point: NSPoint) {
        guard !objectMotion.refusedThisGesture, let start, hypot(point.x - start.x, point.y - start.y) > 4 else { return }
        let locked = Set(session.document.items.filter { selection.contains($0.id) && $0.isLocked }.map(\.id))
        guard !locked.isEmpty, objectMotion.lockedPress != nil || (draft != nil && marqueeRect == nil && !resizing) else { return }
        objectMotion.refusedThisGesture = true
        refuseLocked(locked)
    }

    func playCanvasBurst(_ style: EaselCanvasBurst.Style, around rect: NSRect, tint: NSColor?, delay: TimeInterval = 0) {
        guard canAnimateObjects, rect.width.isFinite, rect.height.isFinite, !rect.isNull else { return }
        let reduced = reduceMotion
        guard !reduced || style == .glow else { return }
        let seed = UInt64(truncatingIfNeeded: Int(rect.midX * 31 + rect.midY * 17)) &+ UInt64(truncatingIfNeeded: Int(CACurrentMediaTime() * 1000))
        burstSurface().play(style, around: rect, tint: tint ?? EaselAppearance.selection, scale: CGFloat(canvasScale), reduced: reduced,
                            seed: seed, delay: reduced ? 0 : delay)
    }

    func flashCopiedSelection(_ ids: Set<UUID>) {
        guard canAnimateObjects else { return }
        let chosen = items.filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return }
        var rects = chosen.prefix(EaselBurstPlan.perCommand).map { EaselCanvasRotation.bounds($0) }
        if chosen.count > 1, let group = EaselGeometryEdit.bounds(of: chosen) {
            rects = [NSRect(x: group.x, y: group.y, width: group.width, height: group.height)]
        }
        burstSurface().sweep(rects, tint: EaselAppearance.selection, scale: CGFloat(canvasScale), reduced: reduceMotion)
    }

    var burstOverlay: NSView? {
        guard let burst = objectMotion.burst, burst.superview === self else { return nil }
        return burst
    }

    private func burstSurface() -> EaselCanvasBurst {
        let host = objectMotion.burst ?? EaselCanvasBurst(frame: bounds)
        if objectMotion.burst == nil {
            host.onIdle = { [weak self, weak host] in
                guard let host, self?.objectMotion.burst === host else { return }
                host.removeFromSuperview()
            }
            objectMotion.burst = host
        }
        if host.frame != bounds { host.frame = bounds }
        if host.superview !== self || subviews.last !== host { addSubview(host, positioned: .above, relativeTo: nil) }
        return host
    }

    private func splashStamp(_ item: EaselItem, delay: TimeInterval) {
        let box = EaselCanvasRotation.bounds(item), tint = color(item.color), impact = delay + 0.07
        playCanvasBurst(.ripple, around: box, tint: tint, delay: impact)
        playCanvasBurst(.confetti, around: box, tint: tint, delay: impact)
    }

    func settleObjectMotion() {
        dismissQuickCreateHint()
        let wasActive = !objectMotion.timeline.isEmpty || objectMotion.animatesChrome
        let envelope = objectMotion.envelope.union(objectMotionEnvelope())
        objectMotion.timeline.cancelAll()
        objectMotion.pendingSurfaces.removeAll()
        objectMotion.chromeStart = nil; objectMotion.chromeFading.removeAll()
        objectMotion.hoverStart = nil
        objectMotion.handleGrowth.removeAll()
        objectMotion.envelope = .null
        objectMotion.driver?.stop()
        objectMotion.driver = nil
        editor?.alphaValue = 1
        for view in artwork.values { if let layer = view.layer { Self.settleSurface(layer) } }
        objectMotion.carriedSurfaces.removeAll()
        for view in objectMotion.retiring.values { view.layer?.removeAllAnimations(); view.removeFromSuperview() }
        objectMotion.retiring.removeAll()
        if let burst = objectMotion.burst { burst.settle(); burst.removeFromSuperview() }
        guard wasActive else { return }
        presentObjectMotionDirty(envelope)
    }

    private func startObjectMotionDriver() {
        if objectMotion.driver == nil {
            objectMotion.driver = EaselCanvasFrameDriver { [weak self] in self?.objectMotionFrame() ?? false }
        }
        objectMotion.driver?.start(in: self)
    }

    @discardableResult
    func objectMotionFrame() -> Bool {
        let now = CACurrentMediaTime()
        objectMotion.timeline.forget(missing: Set(session.document.items.map(\.id)))
        objectMotion.timeline.carry?.advance(to: now)
        let current = objectMotionEnvelope()
        presentObjectMotionDirty(objectMotion.envelope.union(current))
        objectMotion.envelope = current
        updateEditorPresentation(at: now)
        presentCarriedSurfaces(at: now)
        objectMotion.timeline.prune(at: now)
        if let start = objectMotion.chromeStart, now - start >= EaselCanvasObjectMotionState.chromeDuration {
            objectMotion.chromeStart = nil; objectMotion.chromeFading.removeAll()
        }
        if let start = objectMotion.hoverStart, now - start >= EaselCanvasObjectMotionState.chromeDuration { objectMotion.hoverStart = nil }
        for (handle, growth) in objectMotion.handleGrowth where now - growth.start >= 0.3 {
            objectMotion.handleGrowth.removeValue(forKey: handle)
        }
        let active = !objectMotion.timeline.isEmpty || objectMotion.animatesChrome
        if !active {
            editor?.alphaValue = 1
            if !objectMotion.envelope.isNull { presentObjectMotionDirty(objectMotion.envelope) }
            objectMotion.envelope = .null
        }
        return active
    }

    private func presentObjectMotionDirty(_ rect: NSRect) {
        guard !rect.isNull, rect.width.isFinite, rect.height.isFinite else { return }
        if usesObjectSurfaces { decoration.setNeedsDisplay(rect) } else { setNeedsDisplay(rect) }
    }

    private func objectMotionEnvelope() -> NSRect {
        var dirty = NSRect.null
        if !usesObjectSurfaces, !objectMotion.timeline.isEmpty {
            var lookup: [UUID: EaselItem] = [:]
            for ghost in objectMotion.timeline.ghosts { lookup[ghost.id] = ghost }
            for item in items { lookup[item.id] = item }
            let now = CACurrentMediaTime()
            for id in objectMotion.timeline.ids {
                guard let item = lookup[id] else { continue }
                var box = displayBounds(of: item)
                if let transition = objectMotion.timeline.transition(for: id), objectMotion.timeline.carry?.ids.contains(id) != true {
                    switch transition.effect {
                    case .glide(let from, _, let stretch, let turn, _) where !transition.reduced:
                        let reach = max(abs(from.x), abs(from.y)) * 0.1 + 4
                        let grow = max(0, max(stretch.x, stretch.y) - 1) * max(box.width, box.height) / 2 + abs(turn) / 90 * max(box.width, box.height) / 2
                        box = box.union(box.offsetBy(dx: from.x, dy: from.y)).insetBy(dx: -reach - grow, dy: -reach - grow)
                    case .appear(.slam):
                        let grow = (EaselObjectTransition.slamScale - 1) * max(box.width, box.height) / 2 + 8
                        box = box.insetBy(dx: -grow, dy: -grow)
                    default:
                        box = box.union(presentedBounds(of: item, objectMotion.timeline.presentation(for: id, at: now)))
                        let pad = max(box.width, box.height) * 0.06 + 4
                        box = box.insetBy(dx: -pad, dy: -pad)
                    }
                } else {
                    box = box.union(presentedBounds(of: item, objectMotion.timeline.presentation(for: id, at: now)))
                }
                dirty = dirty.union(box)
            }
        }
        if objectMotion.animatesChrome {
            var ids = objectMotion.chromeFading
            if let hover = objectMotion.hoverID { ids.insert(hover) }
            if !objectMotion.handleGrowth.isEmpty { ids.formUnion(displayedSelection) }
            let chosen = items.filter { ids.contains($0.id) }
            for item in chosen { dirty = dirty.union(displayBounds(of: item)) }
            if let bounds = EaselGeometryEdit.bounds(of: chosen) {
                let pad = 16 / max(canvasScale, 0.2) + 16
                dirty = dirty.union(NSRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height).insetBy(dx: -pad, dy: -pad))
            }
        }
        return dirty
    }

    private func updateEditorPresentation(at now: TimeInterval) {
        guard let editor else { return }
        guard let id = editingID, let transition = objectMotion.timeline.transition(for: id) else {
            if editor.alphaValue != 1 { editor.alphaValue = 1 }
            return
        }
        let shown = transition.presentation(at: now)
        var opacity = shown.opacity
        if case .glide(let from, _, _, _, _) = transition.effect {
            let travel = max(abs(from.x), abs(from.y))
            if travel > 0 { opacity *= max(0, 1 - max(abs(shown.offset.x), abs(shown.offset.y)) / travel) }
        }
        if case .restyle = transition.effect { opacity = 1 }
        editor.alphaValue = CGFloat(min(1, max(0, opacity)))
    }

    func drawPresentedObjects(in dirtyRect: NSRect) {
        let shown = items
        guard !objectMotion.timeline.isEmpty else {
            for item in shown where displayBounds(of: item).intersects(dirtyRect) { drawObject(item) }
            return
        }
        let now = CACurrentMediaTime()
        var ordered = shown
        for ghost in objectMotion.timeline.ghosts where !shown.contains(where: { $0.id == ghost.id }) {
            let slot = ordered.firstIndex { $0.zIndex > ghost.zIndex } ?? ordered.endIndex
            ordered.insert(ghost, at: slot)
        }
        for item in ordered {
            let presentation = objectMotion.timeline.presentation(for: item.id, at: now)
            guard presentedBounds(of: item, presentation).intersects(dirtyRect) else { continue }
            if let previous = objectMotion.timeline.previousLook(for: item.id) {
                var faded = presentation
                faded.opacity = 1 - presentation.opacity
                drawPresented(previous, faded)
            }
            drawPresented(item, presentation)
        }
    }

    private func presentedBounds(of item: EaselItem, _ presentation: EaselObjectPresentation) -> NSRect {
        var box = displayBounds(of: item)
        let grow = max(presentation.scaleX, presentation.scaleY) - 1
        if grow > 0 { box = box.insetBy(dx: -box.width * grow / 2, dy: -box.height * grow / 2) }
        if presentation.rotation != 0 {
            let radians = abs(presentation.rotation) * Double.pi / 180
            let width = box.width * cos(radians) + box.height * sin(radians)
            let height = box.width * sin(radians) + box.height * cos(radians)
            box = NSRect(x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height)
        }
        if presentation.shadow > 0 {
            let pad = Self.shadowReach(presentation.shadow) / max(canvasScale, 0.2)
            box = NSRect(x: box.minX - pad, y: box.minY - pad, width: box.width + pad * 2, height: box.height + pad * 3)
        }
        return box.offsetBy(dx: presentation.offset.x, dy: presentation.offset.y)
    }

    private static func shadowReach(_ amount: Double) -> CGFloat { CGFloat(6 + 22 * min(1, amount)) }

    private func shadowColor(_ amount: Double) -> NSColor {
        let dark = NoteTheme.isDark(effectiveAppearance)
        return NSColor.black.withAlphaComponent(CGFloat(min(1, amount) * (dark ? 0.5 : 0.24)))
    }

    private func drawPresented(_ item: EaselItem, _ presentation: EaselObjectPresentation) {
        guard !presentation.isIdentity, let context = NSGraphicsContext.current?.cgContext else { drawObject(item); return }
        guard presentation.opacity > 0.001 else { return }
        context.saveGState(); defer { context.restoreGState() }
        context.translateBy(x: presentation.offset.x, y: presentation.offset.y)
        if presentation.scaleX != 1 || presentation.scaleY != 1 || presentation.rotation != 0 {
            let box = EaselCanvasRotation.bounds(item)
            context.translateBy(x: box.midX, y: box.midY)
            if presentation.rotation != 0 { context.rotate(by: CGFloat(presentation.rotation * Double.pi / 180)) }
            context.scaleBy(x: presentation.scaleX, y: presentation.scaleY)
            context.translateBy(x: -box.midX, y: -box.midY)
        }
        let shadowed = presentation.shadow > 0.01
        if shadowed {
            let amount = min(1, presentation.shadow)
            let zoom = CGFloat(max(canvasScale, 0.2)) * (window?.backingScaleFactor ?? 2) / 2
            context.setShadow(offset: CGSize(width: 0, height: -CGFloat(2 + 8 * amount) * zoom), blur: CGFloat(4 + 16 * amount) * zoom,
                              color: shadowColor(amount).cgColor)
        }
        let faded = presentation.opacity < 0.999
        if faded { context.setAlpha(presentation.opacity) }
        let layered = faded || shadowed
        if layered { context.beginTransparencyLayer(auxiliaryInfo: nil) }
        drawObject(item)
        if layered { context.endTransparencyLayer() }
    }

    private static let surfaceKey = "parc.easel.motion."

    private static func settleSurface(_ layer: CALayer) {
        for key in layer.animationKeys() ?? [] where key.hasPrefix(surfaceKey) { layer.removeAnimation(forKey: key) }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if !CATransform3DIsIdentity(layer.transform) { layer.transform = CATransform3DIdentity }
        if layer.shadowOpacity != 0 { layer.shadowOpacity = 0 }
        CATransaction.commit()
    }

    private struct SurfaceFrame {
        let centre: CGPoint
        let flip: CGFloat
        let unit: CGPoint
    }

    private func surfaceFrame(for item: EaselItem, layer: CALayer) -> SurfaceFrame? {
        guard let canvasLayer = self.layer, layer.superlayer != nil else { return nil }
        let box = EaselCanvasRotation.bounds(item)
        let middle = convertToLayer(NSPoint(x: box.midX, y: box.midY))
        let below = convertToLayer(NSPoint(x: box.midX, y: box.midY + 1))
        let local = layer.convert(middle, from: canvasLayer), localBelow = layer.convert(below, from: canvasLayer)
        let anchor = CGPoint(x: layer.bounds.minX + layer.anchorPoint.x * layer.bounds.width,
                             y: layer.bounds.minY + layer.anchorPoint.y * layer.bounds.height)
        let superMiddle = canvasLayer.convert(middle, to: layer.superlayer), superBelow = canvasLayer.convert(below, to: layer.superlayer)
        return SurfaceFrame(centre: CGPoint(x: local.x - anchor.x, y: local.y - anchor.y), flip: localBelow.y >= local.y ? 1 : -1,
                            unit: CGPoint(x: superBelow.x - superMiddle.x, y: superBelow.y - superMiddle.y))
    }

    private static func surfaceTransform(_ presentation: EaselObjectPresentation, _ frame: SurfaceFrame) -> CATransform3D {
        var transform = CATransform3DMakeTranslation(frame.centre.x, frame.centre.y, 0)
        if presentation.rotation != 0 {
            transform = CATransform3DRotate(transform, frame.flip * CGFloat(presentation.rotation * Double.pi / 180), 0, 0, 1)
        }
        transform = CATransform3DScale(transform, CGFloat(presentation.scaleX), CGFloat(presentation.scaleY), 1)
        return CATransform3DTranslate(transform, -frame.centre.x, -frame.centre.y, 0)
    }

    private func surfaceOffset(_ offset: EaselPoint, _ frame: SurfaceFrame) -> CGPoint {
        let vertical = frame.unit.y >= 0 ? 1.0 : -1.0
        return CGPoint(x: offset.x, y: offset.y * vertical)
    }

    private func styleSurfaceShadow(_ layer: CALayer, _ frame: SurfaceFrame) {
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 6 * frame.flip)
        layer.shadowPath = nil
    }

    private func surfaceAnimations(_ transition: EaselObjectTransition, item: EaselItem, layer: CALayer, frame: SurfaceFrame,
                                   now: TimeInterval, keepsEnd: Bool = false) -> [String: CAAnimation] {
        let elapsed = max(0, now - transition.start), delay = max(0, transition.start - now)
        let remaining = transition.duration - elapsed
        guard remaining > 0.01 else { return [:] }
        let count = max(2, Int(remaining * 60) + 1)
        var transforms: [Any] = [], offsets: [Any] = [], opacities: [Any] = [], shadows: [Any] = [], radii: [Any] = []
        var moves = false, fades = false, turns = false, shades = false
        let dark = NoteTheme.isDark(effectiveAppearance)
        for index in 0..<count {
            let time = transition.start + elapsed + remaining * Double(index) / Double(count - 1)
            let shown = transition.presentation(at: index == count - 1 ? transition.start + transition.duration : time)
            transforms.append(NSValue(caTransform3D: Self.surfaceTransform(shown, frame)))
            offsets.append(NSValue(point: surfaceOffset(shown.offset, frame)))
            opacities.append(shown.opacity)
            shadows.append(min(1, shown.shadow) * (dark ? 0.5 : 0.24))
            radii.append(Double(Self.shadowReach(shown.shadow)) / 2)
            if shown.scaleX != 1 || shown.scaleY != 1 || shown.rotation != 0 { turns = true }
            if shown.offset.x != 0 || shown.offset.y != 0 { moves = true }
            if shown.opacity < 0.999 { fades = true }
            if shown.shadow > 0.001 { shades = true }
        }
        let begin = delay > 0 ? layer.convertTime(CACurrentMediaTime(), from: nil) + delay : 0
        func keyframes(_ path: String, _ values: [Any], additive: Bool = false) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: path)
            animation.values = values
            animation.duration = remaining
            animation.calculationMode = .linear
            animation.isAdditive = additive
            animation.beginTime = begin
            animation.fillMode = keepsEnd ? .both : .backwards
            animation.isRemovedOnCompletion = !keepsEnd
            return animation
        }
        var result: [String: CAAnimation] = [:]
        if turns { result["transform"] = keyframes("transform", transforms) }
        if moves { result["position"] = keyframes("position", offsets, additive: true) }
        if fades || keepsEnd { result["opacity"] = keyframes("opacity", opacities) }
        if shades {
            styleSurfaceShadow(layer, frame)
            result["shadowOpacity"] = keyframes("shadowOpacity", shadows)
            result["shadowRadius"] = keyframes("shadowRadius", radii)
        }
        return result
    }

    func applySurfaceObjectMotion() {
        for (id, view) in objectMotion.retiring where artwork[id] != nil && artwork[id] !== view {
            view.layer?.removeAllAnimations(); view.removeFromSuperview()
            objectMotion.retiring.removeValue(forKey: id)
        }
        guard usesObjectSurfaces, !objectMotion.pendingSurfaces.isEmpty else { return }
        let now = CACurrentMediaTime(), key = Self.surfaceKey
        var lookup: [UUID: EaselItem] = [:]
        for item in items { lookup[item.id] = item }
        for id in objectMotion.pendingSurfaces {
            guard let transition = objectMotion.timeline.transition(for: id), let view = artwork[id], let item = lookup[id],
                  objectMotion.timeline.ghosts.contains(where: { $0.id == id }) == false else { continue }
            view.wantsLayer = true
            guard let layer = view.layer else { continue }
            if case .restyle = transition.effect {
                let fade = CATransition()
                fade.type = .fade
                fade.duration = max(0.01, transition.duration - max(0, now - transition.start))
                fade.timingFunction = NoteCurve.easeInOut
                layer.add(fade, forKey: key + "restyle")
                continue
            }
            guard let frame = surfaceFrame(for: item, layer: layer) else { continue }
            for (path, animation) in surfaceAnimations(transition, item: item, layer: layer, frame: frame, now: now) {
                layer.add(animation, forKey: key + path)
            }
        }
        objectMotion.pendingSurfaces.removeAll()
    }

    func retireArtwork(_ view: NSView?, id: UUID) {
        guard let view else { return }
        guard let ghost = objectMotion.timeline.ghosts.first(where: { $0.id == id }), let transition = objectMotion.timeline.transition(for: id),
              canAnimateObjects else { view.removeFromSuperview(); return }
        view.wantsLayer = true
        guard let layer = view.layer else { view.removeFromSuperview(); return }
        objectMotion.retiring[id]?.removeFromSuperview()
        objectMotion.retiring[id] = view
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak view] in
            MainActor.assumeIsolated {
                guard let view else { return }
                view.removeFromSuperview()
                if let self, self.objectMotion.retiring[id] === view { self.objectMotion.retiring.removeValue(forKey: id) }
            }
        }
        let now = CACurrentMediaTime()
        var animations = surfaceFrame(for: ghost, layer: layer).map {
            surfaceAnimations(transition, item: ghost, layer: layer, frame: $0, now: now, keepsEnd: true)
        } ?? [:]
        if animations.isEmpty {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = layer.presentation()?.opacity ?? 1; fade.toValue = 0
            fade.duration = EaselObjectTransition.vanishDuration
            fade.fillMode = .forwards; fade.isRemovedOnCompletion = false
            animations["opacity"] = fade
        }
        for (path, animation) in animations { layer.add(animation, forKey: Self.surfaceKey + "vanish." + path) }
        CATransaction.commit()
    }

    func carryDraggedObjects(rotating: Bool, velocity: EaselPoint) {
        let now = CACurrentMediaTime()
        if objectMotion.timeline.carry != nil {
            objectMotion.timeline.carry?.pointer(speed: velocity.x * canvasScale, at: now)
            return
        }
        guard !rotating, !resizing, dragDistance > 3, draft != nil, canAnimateObjects, !reduceMotion else { return }
        let carried = movableSelection
        guard !carried.isEmpty else { return }
        let lifted = session.document.items.filter { carried.contains($0.id) }
        let tilting = Set(lifted.filter { $0.kind == .sticky || $0.kind == .stamp }.map(\.id))
        let pages = Set(lifted.filter(\.ownsEmbeddedPage).map(\.id))
        objectMotion.timeline.pickUp(carried, tilting: tilting, shadowOnly: pages, at: now, reduced: false)
        objectMotion.timeline.carry?.pointer(speed: velocity.x * canvasScale, at: now)
        startObjectMotionDriver()
    }

    func dropCarriedObjects() {
        objectMotion.lockedPress = nil
        guard objectMotion.timeline.carry != nil else { return }
        let landed = objectMotion.timeline.drop(at: CACurrentMediaTime())
        for id in objectMotion.carriedSurfaces { if let layer = artwork[id]?.layer { Self.settleSurface(layer) } }
        objectMotion.carriedSurfaces.removeAll()
        objectMotion.pendingSurfaces.formUnion(landed)
        needsLayout = true
        startObjectMotionDriver()
    }

    private func presentCarriedSurfaces(at now: TimeInterval) {
        guard usesObjectSurfaces, let carry = objectMotion.timeline.carry else { return }
        var lookup: [UUID: EaselItem] = [:]
        for item in items where carry.ids.contains(item.id) { lookup[item.id] = item }
        let dark = NoteTheme.isDark(effectiveAppearance)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for id in carry.ids {
            guard let item = lookup[id], let view = artwork[id] else { continue }
            view.wantsLayer = true
            guard let layer = view.layer, let frame = surfaceFrame(for: item, layer: layer) else { continue }
            let shown = carry.presentation(for: id, at: now)
            if !item.ownsEmbeddedPage { layer.transform = Self.surfaceTransform(shown, frame) }
            if !layer.masksToBounds {
                styleSurfaceShadow(layer, frame)
                layer.shadowOpacity = Float(min(1, shown.shadow) * (dark ? 0.5 : 0.24))
                layer.shadowRadius = Self.shadowReach(shown.shadow) / 2
            }
            objectMotion.carriedSurfaces.insert(id)
        }
        CATransaction.commit()
    }

    func noteObjectChrome() {
        let now = CACurrentMediaTime()
        let shown = displayedSelection
        if shown != objectMotion.chromeSelection {
            let fresh = shown.subtracting(objectMotion.chromeSelection)
            objectMotion.chromeSelection = shown
            if !fresh.isEmpty, marqueeRect == nil, canAnimateObjects, !reduceMotion {
                objectMotion.chromeFading = fresh
                objectMotion.chromeStart = now
                startObjectMotionDriver()
            } else if fresh.isEmpty {
                objectMotion.chromeFading.formIntersection(shown)
            }
        }
        if hoveredObjectID != objectMotion.hoverID {
            objectMotion.hoverID = hoveredObjectID
            if hoveredObjectID != nil, canAnimateObjects, !reduceMotion {
                objectMotion.hoverStart = now
                startObjectMotionDriver()
            } else {
                objectMotion.hoverStart = nil
            }
        }
    }

    func objectChromeOpacity(for id: UUID) -> CGFloat {
        let now = CACurrentMediaTime()
        if displayedSelection.contains(id) {
            guard objectMotion.chromeFading.contains(id), let start = objectMotion.chromeStart else { return 1 }
            return CGFloat(EaselObjectTransition.easeOut((now - start) / EaselCanvasObjectMotionState.chromeDuration))
        }
        guard id == objectMotion.hoverID, let start = objectMotion.hoverStart else { return 1 }
        return CGFloat(EaselObjectTransition.easeOut((now - start) / EaselCanvasObjectMotionState.chromeDuration))
    }

    var handleChromeOpacity: CGFloat {
        guard let start = objectMotion.chromeStart, !objectMotion.chromeFading.isDisjoint(with: displayedSelection) else { return 1 }
        return CGFloat(EaselObjectTransition.easeOut((CACurrentMediaTime() - start) / EaselCanvasObjectMotionState.chromeDuration))
    }

    func withObjectChrome(opacity: CGFloat, _ body: () -> Void) {
        guard opacity < 0.999, let context = NSGraphicsContext.current?.cgContext else { body(); return }
        guard opacity > 0.001 else { return }
        context.saveGState(); defer { context.restoreGState() }
        context.setAlpha(opacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        context.endTransparencyLayer()
    }

    func updateHandleHover(_ handle: EaselResizeHandle?) {
        guard handle != objectMotion.hoveredHandle else { return }
        let now = CACurrentMediaTime()
        let previous = objectMotion.hoveredHandle
        objectMotion.hoveredHandle = handle
        guard canAnimateObjects, !reduceMotion else {
            objectMotion.handleGrowth.removeAll()
            presentObjectMotionDirty(objectMotionEnvelope().union(handleDirty()))
            return
        }
        if let previous { objectMotion.handleGrowth[previous] = (handleScale(previous, at: now), 1, now) }
        if let handle { objectMotion.handleGrowth[handle] = (handleScale(handle, at: now), EaselCanvasObjectMotionState.handleGrowth, now) }
        startObjectMotionDriver()
        presentObjectMotionDirty(handleDirty())
    }

    private func handleDirty() -> NSRect {
        let chosen = items.filter { displayedSelection.contains($0.id) }
        guard let bounds = EaselGeometryEdit.bounds(of: chosen) else { return .null }
        let pad = 16 / max(canvasScale, 0.2) + 16
        return NSRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height).insetBy(dx: -pad, dy: -pad)
    }

    func handleScale(_ handle: EaselResizeHandle, at now: TimeInterval = CACurrentMediaTime()) -> CGFloat {
        if let growth = objectMotion.handleGrowth[handle] {
            let progress = CGFloat(EaselObjectSpring.hover.progress(at: now - growth.start))
            return growth.from + (growth.to - growth.from) * progress
        }
        return handle == objectMotion.hoveredHandle && !reduceMotion ? EaselCanvasObjectMotionState.handleGrowth : 1
    }
}
