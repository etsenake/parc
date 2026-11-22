import AppKit

@MainActor
enum NoteCanvasMotion {
    static let slideKey = NoteAnimation.keyPrefix + "canvas.slide."
    static let appearKey = NoteAnimation.keyPrefix + "canvas.appear"
    static let riseKey = NoteAnimation.keyPrefix + "canvas.rise"
    static let settleScaleKey = NoteAnimation.keyPrefix + "canvas.settle.scale"
    static let revealOpacityKey = NoteAnimation.keyPrefix + "canvas.reveal.opacity"
    static let revealMaskKey = NoteAnimation.keyPrefix + "canvas.reveal.mask"
    private static var slideCounter = 0

    static func slide(_ view: NSView, by delta: CGVector, spring: NoteSpring) {
        guard let layer = view.layer, !NoteAnimation.reduceMotion, abs(delta.dx) > 0.5 || abs(delta.dy) > 0.5 else { return }
        let animation = NoteAnimation.spring("position", spring, from: NSValue(point: NSPoint(x: delta.dx, y: delta.dy)),
                                             to: NSValue(point: .zero))
        animation.isAdditive = true
        slideCounter &+= 1
        layer.add(animation, forKey: slideKey + String(slideCounter))
    }

    static func settle(_ view: NSView, by delta: CGVector) {
        slide(view, by: delta, spring: .settle)
        guard let layer = view.layer, !NoteAnimation.reduceMotion else { return }
        layer.add(NoteAnimation.spring("transform.scale", .settle, from: NoteAnimation.liftScale, to: 1), forKey: settleScaleKey)
    }

    static func appear(_ view: NSView) {
        guard let layer = view.layer else { return }
        let reduced = NoteAnimation.reduceMotion
        let fade = NoteAnimation.basic("opacity", from: 0, to: 1,
                                       duration: reduced ? NoteAnimation.reducedFadeDuration : NoteAnimation.insertDuration)
        fade.fillMode = .backwards
        layer.add(fade, forKey: appearKey)
        guard !reduced else { return }
        let rise = NoteAnimation.basic("position", from: NSValue(point: NSPoint(x: 0, y: NoteAnimation.insertRise)),
                                       to: NSValue(point: .zero), duration: NoteAnimation.insertDuration)
        rise.isAdditive = true
        layer.add(rise, forKey: riseKey)
    }

    static func vanish(_ view: NSView, completion: @escaping () -> Void) {
        guard let layer = view.layer else { completion(); return }
        NoteAnimation.fade(layer, to: 0, duration: NoteAnimation.removeDuration, completion: completion)
    }

    static func reveal(_ view: NSView, edge: CGFloat, height: CGFloat, expanding: Bool, completion: (() -> Void)? = nil) {
        guard let layer = view.layer else { completion?(); return }
        let reduced = NoteAnimation.reduceMotion
        let duration = reduced ? NoteAnimation.reducedFadeDuration : NoteAnimation.revealDuration
        let fade = NoteAnimation.basic("opacity", from: expanding ? 0 : 1, to: expanding ? 1 : 0, duration: duration)
        if expanding {
            fade.fillMode = .backwards
        } else {
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
        }
        guard !reduced, height > 0.5 else {
            _ = NoteAnimation.run(fade, on: layer, key: revealOpacityKey) { _ in completion?() }
            return
        }
        _ = NoteAnimation.run(fade, on: layer, key: revealOpacityKey)
        let offset = view.frame.minY - edge
        let width = max(view.bounds.width, 1)
        let mask = CALayer()
        mask.backgroundColor = NSColor.black.cgColor
        mask.anchorPoint = .zero
        let shown = CGPoint(x: -width, y: -offset - 8)
        let hidden = CGPoint(x: -width, y: shown.y - height)
        NoteAnimation.withoutAnimation {
            mask.bounds = CGRect(x: 0, y: 0, width: width * 3, height: height + 8)
            mask.position = expanding ? shown : hidden
        }
        layer.mask = mask
        let motion = NoteAnimation.spring("position", .reorder, from: NSValue(point: expanding ? hidden : shown),
                                          to: NSValue(point: expanding ? shown : hidden))
        _ = NoteAnimation.run(motion, on: mask, key: revealMaskKey) { [weak layer, weak mask] _ in
            if let layer, let mask, layer.mask === mask, expanding { layer.mask = nil }
            completion?()
        }
    }

    static func settleAll(_ view: NSView) {
        guard let layer = view.layer else { return }
        for key in layer.animationKeys() ?? [] where key.hasPrefix(NoteAnimation.keyPrefix + "canvas.") {
            layer.removeAnimation(forKey: key)
        }
        if let mask = layer.mask, mask.animation(forKey: revealMaskKey) != nil { layer.mask = nil }
    }
}
