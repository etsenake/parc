import AppKit
import QuartzCore

enum EaselObjectMotionIntent {
    case appear
    case vanish
    case copies(sources: [UUID], copies: [UUID])
    case arrange
    case layer(forward: Bool, ids: Set<UUID>)
}

@MainActor
final class EaselCanvasObjectMotionState {
    static let chromeDuration: TimeInterval = 0.1
    static let handleGrowth: CGFloat = 1.35
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
        let live = Set(after.items.filter(\.ownsEmbeddedPage).map(\.id))
        var touched = Set<UUID>()
        switch intent {
        case .appear:
            let added = EaselObjectMotion.added(from: before, to: after).filter { !live.contains($0) }
            objectMotion.timeline.appear(added, at: now, reduced: reduced)
            touched.formUnion(added)
        case .vanish:
            let leaving = EaselObjectMotion.removed(from: before, to: after).filter { !$0.ownsEmbeddedPage }
            objectMotion.timeline.vanish(leaving, at: now, reduced: reduced)
            touched.formUnion(leaving.map(\.id))
        case .copies(let sources, let copies):
            let offsets = EaselObjectMotion.copyOffsets(sources: sources, copies: copies, before: before, after: after)
                .filter { !live.contains($0.key) }
            objectMotion.timeline.glide(offsets, fades: true, at: now, reduced: reduced)
            let rest = EaselObjectMotion.added(from: before, to: after).filter { offsets[$0] == nil && !live.contains($0) }
            objectMotion.timeline.appear(rest, at: now, reduced: reduced)
            touched.formUnion(offsets.keys); touched.formUnion(rest)
        case .arrange:
            let offsets = EaselObjectMotion.moves(from: before, to: after).filter { !live.contains($0.key) }
            objectMotion.timeline.glide(offsets, fades: false, at: now, reduced: reduced)
            touched.formUnion(offsets.keys)
        case .layer(let forward, let ids):
            let moved = ids.subtracting(live)
            objectMotion.timeline.lift(moved, from: forward ? 1.03 : 0.97, at: now, reduced: reduced)
            touched.formUnion(moved)
        }
        guard !touched.isEmpty else { return }
        objectMotion.pendingSurfaces.formUnion(touched)
        startObjectMotionDriver()
        objectMotionFrame()
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
        editor?.alphaValue = 1
        for view in artwork.values { if let layer = view.layer { Self.settleSurface(layer) } }
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
        let current = objectMotionEnvelope()
        presentObjectMotionDirty(objectMotion.envelope.union(current))
        objectMotion.envelope = current
        updateEditorPresentation(at: now)
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
        if !usesObjectSurfaces {
            let shown = items
            for (id, transition) in objectMotion.timeline.transitions {
                guard let item = shown.first(where: { $0.id == id }) ?? objectMotion.timeline.ghosts.first(where: { $0.id == id }) else { continue }
                var box = displayBounds(of: item)
                if case .lift(let from) = transition.effect, from > 1 {
                    box = box.insetBy(dx: -box.width * (from - 1), dy: -box.height * (from - 1))
                }
                if case .glide(let from, _) = transition.effect, !transition.reduced {
                    let overshoot = max(abs(from.x), abs(from.y)) * 0.1 + 4
                    box = box.union(box.offsetBy(dx: from.x, dy: from.y)).insetBy(dx: -overshoot, dy: -overshoot)
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
        if case .glide(let from, _) = transition.effect {
            let travel = max(abs(from.x), abs(from.y))
            if travel > 0 { opacity *= max(0, 1 - max(abs(shown.offset.x), abs(shown.offset.y)) / travel) }
        }
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
            drawPresented(item, presentation)
        }
    }

    private func presentedBounds(of item: EaselItem, _ presentation: EaselObjectPresentation) -> NSRect {
        var box = displayBounds(of: item)
        if presentation.scale > 1 {
            let grow = presentation.scale - 1
            box = box.insetBy(dx: -box.width * grow / 2, dy: -box.height * grow / 2)
        }
        return box.offsetBy(dx: presentation.offset.x, dy: presentation.offset.y)
    }

    private func drawPresented(_ item: EaselItem, _ presentation: EaselObjectPresentation) {
        guard !presentation.isIdentity, let context = NSGraphicsContext.current?.cgContext else { drawObject(item); return }
        guard presentation.opacity > 0.001 else { return }
        context.saveGState(); defer { context.restoreGState() }
        context.translateBy(x: presentation.offset.x, y: presentation.offset.y)
        if presentation.scale != 1 {
            let box = EaselCanvasRotation.bounds(item)
            context.translateBy(x: box.midX, y: box.midY)
            context.scaleBy(x: presentation.scale, y: presentation.scale)
            context.translateBy(x: -box.midX, y: -box.midY)
        }
        let faded = presentation.opacity < 0.999
        if faded { context.setAlpha(presentation.opacity); context.beginTransparencyLayer(auxiliaryInfo: nil) }
        drawObject(item)
        if faded { context.endTransparencyLayer() }
    }

    private static let surfaceKey = "parc.easel.motion."

    private static func basic(_ keyPath: String, from: Any, to: Any, duration: TimeInterval,
                              curve: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeOut)) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from; animation.toValue = to
        animation.duration = duration; animation.timingFunction = curve
        return animation
    }

    private static func scaled(_ scale: Double, in layer: CALayer) -> NSValue {
        let x = layer.bounds.width * (0.5 - layer.anchorPoint.x), y = layer.bounds.height * (0.5 - layer.anchorPoint.y)
        var transform = CATransform3DMakeTranslation(x, y, 0)
        transform = CATransform3DScale(transform, CGFloat(scale), CGFloat(scale), 1)
        return NSValue(caTransform3D: CATransform3DTranslate(transform, -x, -y, 0))
    }

    private static func settleSurface(_ layer: CALayer) {
        for key in layer.animationKeys() ?? [] where key.hasPrefix(surfaceKey) { layer.removeAnimation(forKey: key) }
    }

    func applySurfaceObjectMotion() {
        guard usesObjectSurfaces, !objectMotion.pendingSurfaces.isEmpty else { return }
        let now = CACurrentMediaTime(), reduced = reduceMotion, key = Self.surfaceKey
        let identity = NSValue(caTransform3D: CATransform3DIdentity)
        for id in objectMotion.pendingSurfaces {
            guard let transition = objectMotion.timeline.transition(for: id), let view = artwork[id],
                  objectMotion.timeline.ghosts.contains(where: { $0.id == id }) == false else { continue }
            view.wantsLayer = true
            guard let layer = view.layer else { continue }
            let remaining = max(0.01, transition.duration - (now - transition.start))
            switch transition.effect {
            case .appear:
                let fade = Self.basic("opacity", from: 0, to: 1, duration: reduced ? remaining : min(remaining, EaselObjectTransition.appearFade))
                fade.fillMode = .backwards
                layer.add(fade, forKey: key + "appear")
                if !reduced {
                    layer.add(Self.basic("transform", from: Self.scaled(EaselObjectTransition.hiddenScale, in: layer), to: identity, duration: remaining,
                                         curve: CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1)), forKey: key + "pop")
                }
            case .glide(let from, let fades):
                if reduced {
                    let fade = Self.basic("opacity", from: fades ? 0 : 0.4, to: 1, duration: remaining)
                    fade.fillMode = .backwards
                    layer.add(fade, forKey: key + "fade")
                } else {
                    let spring = CASpringAnimation(keyPath: "position")
                    let omega = 2 * Double.pi / EaselObjectSpring.glide.response
                    spring.mass = 1; spring.stiffness = omega * omega; spring.damping = 2 * EaselObjectSpring.glide.damping * omega
                    spring.fromValue = NSValue(point: NSPoint(x: from.x, y: from.y)); spring.toValue = NSValue(point: .zero)
                    spring.isAdditive = true; spring.duration = remaining
                    layer.add(spring, forKey: key + "glide")
                }
            case .lift(let scale):
                layer.add(Self.basic("transform", from: Self.scaled(scale, in: layer), to: identity, duration: remaining), forKey: key + "lift")
            case .vanish:
                break
            }
        }
        objectMotion.pendingSurfaces.removeAll()
    }

    func retireArtwork(_ view: NSView?, id: UUID) {
        guard let view else { return }
        guard objectMotion.timeline.ghosts.contains(where: { $0.id == id }), canAnimateObjects else { view.removeFromSuperview(); return }
        view.wantsLayer = true
        guard let layer = view.layer else { view.removeFromSuperview(); return }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak view] in MainActor.assumeIsolated { view?.removeFromSuperview() } }
        let fade = Self.basic("opacity", from: layer.presentation()?.opacity ?? 1, to: 0, duration: EaselObjectTransition.vanishDuration)
        fade.fillMode = .forwards; fade.isRemovedOnCompletion = false
        layer.add(fade, forKey: Self.surfaceKey + "vanish")
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
