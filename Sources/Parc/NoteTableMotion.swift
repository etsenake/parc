import AppKit

@MainActor
enum NoteTableMotion {
    static let slideKey = "parc.note.table.slide"
    static let sizeKey = "parc.note.table.size"
    static let fadeKey = "parc.note.table.fade"
    static let pressKey = "parc.note.table.press"
    static let liftKey = "parc.note.table.lift"
    static let insertFadeDuration: CFTimeInterval = 0.2
    static let removeFadeDuration: CFTimeInterval = 0.15
    static let reducedFadeDuration: CFTimeInterval = 0.15

    static var reduceMotion: Bool { NoteAnimation.reduceMotion }

    static func scaleTransform(_ scale: CGFloat, for layer: CALayer) -> CATransform3D {
        let center = CGPoint(x: layer.bounds.midX - layer.anchorPoint.x * layer.bounds.width,
                             y: layer.bounds.midY - layer.anchorPoint.y * layer.bounds.height)
        var transform = CATransform3DMakeTranslation(center.x, center.y, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -center.x, -center.y, 0)
    }

    static func press(_ view: NSView, pressed: Bool, scale: CGFloat = 0.95) {
        guard let layer = view.layer else { return }
        let target = pressed && !reduceMotion ? scaleTransform(scale, for: layer) : CATransform3DIdentity
        NoteAnimation.animate(layer, "transform", to: NSValue(caTransform3D: target), spring: .press, key: pressKey)
    }

    static func presentedOffset(_ view: NSView) -> CGSize {
        guard let layer = view.layer, layer.animation(forKey: slideKey) != nil, let presented = layer.presentation() else { return .zero }
        return CGSize(width: presented.position.x - layer.position.x, height: presented.position.y - layer.position.y)
    }

    static func slide(_ view: NSView, from old: NSRect, offset: CGSize = .zero, spring: NoteSpring = .reorder) {
        guard let layer = view.layer else { return }
        let new = view.frame
        let delta = CGPoint(x: old.minX - new.minX + offset.width, y: old.minY - new.minY + offset.height)
        guard !reduceMotion, abs(delta.x) > 0.25 || abs(delta.y) > 0.25 else { layer.removeAnimation(forKey: slideKey); return }
        let animation = NoteAnimation.spring("position", spring, from: NSValue(point: delta), to: NSValue(point: .zero))
        animation.isAdditive = true
        layer.add(animation, forKey: slideKey)
    }

    static func resize(_ view: NSView, from old: NSSize, spring: NoteSpring = .reorder) {
        guard let layer = view.layer else { return }
        let new = view.frame.size
        let delta = NSRect(x: 0, y: 0, width: old.width - new.width, height: old.height - new.height)
        guard !reduceMotion, abs(delta.width) > 0.25 || abs(delta.height) > 0.25 else { layer.removeAnimation(forKey: sizeKey); return }
        let animation = NoteAnimation.spring("bounds", spring, from: NSValue(rect: delta), to: NSValue(rect: .zero))
        animation.isAdditive = true
        layer.add(animation, forKey: sizeKey)
    }

    static func fadeIn(_ view: NSView, delay: CFTimeInterval = 0) {
        guard let layer = view.layer else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = reduceMotion ? reducedFadeDuration : insertFadeDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        if delay > 0, !reduceMotion {
            animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
            animation.fillMode = .backwards
        }
        layer.add(animation, forKey: fadeKey)
    }

    static func fadeOutAndRemove(_ view: NSView) {
        guard let layer = view.layer else { view.removeFromSuperview(); return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0
        animation.duration = reduceMotion ? reducedFadeDuration : removeFadeDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak view] in MainActor.assumeIsolated { view?.removeFromSuperview() } }
        layer.add(animation, forKey: fadeKey)
        CATransaction.commit()
    }

    static func settle(_ view: NSView) {
        guard let layer = view.layer else { return }
        for key in [slideKey, sizeKey, fadeKey, liftKey] { layer.removeAnimation(forKey: key) }
        for subview in view.subviews { settle(subview) }
    }

    static func snapshot(of view: NSView, rect: NSRect) -> NSImage? {
        let bounded = rect.intersection(view.bounds)
        guard !bounded.isEmpty, let rep = view.bitmapImageRepForCachingDisplay(in: bounded) else { return nil }
        view.cacheDisplay(in: bounded, to: rep)
        let image = NSImage(size: bounded.size)
        image.addRepresentation(rep)
        return image
    }
}

@MainActor
final class NoteTableSnapshotView: NSView {
    init(image: NSImage, frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class NoteTableGhostView: NSView {
    private let image: NoteTableSnapshotView

    init(image snapshot: NSImage, frame: NSRect) {
        image = NoteTableSnapshotView(image: snapshot, frame: NSRect(origin: .zero, size: frame.size))
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.cornerCurve = .continuous
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        image.layer?.cornerRadius = 4
        image.layer?.masksToBounds = true
        addSubview(image)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        image.frame = bounds
    }

    override func updateLayer() {
        var fill = NoteTableStyle.ghostFill.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { fill = NoteTableStyle.ghostFill.cgColor }
        layer?.backgroundColor = fill
    }

    override var wantsUpdateLayer: Bool { true }

    func lift(_ lifted: Bool) {
        guard let layer else { return }
        let scale: CGFloat = lifted && !NoteTableMotion.reduceMotion ? 1.02 : 1
        NoteAnimation.animate(layer, "transform", to: NSValue(caTransform3D: NoteTableMotion.scaleTransform(scale, for: layer)),
                              spring: .reorder, key: NoteTableMotion.liftKey)
        NoteAnimation.animate(layer, "shadowOpacity", to: Float(lifted ? 0.16 : 0), spring: .reorder, key: NoteTableMotion.liftKey + ".shadow")
    }
}
