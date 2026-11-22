import AppKit
import ParcCore

@MainActor
enum EaselControlSurface {
    nonisolated static let scaleKey = NoteAnimation.keyPrefix + "easel.control.scale"
    nonisolated static let shadowKey = NoteAnimation.keyPrefix + "easel.control.shadow"
    nonisolated static let radiusKey = NoteAnimation.keyPrefix + "easel.control.radius"
    nonisolated static let shakeKey = NoteAnimation.keyPrefix + "easel.control.shake"
    nonisolated static let glowKey = NoteAnimation.keyPrefix + "easel.control.glow"
    nonisolated static let morphKey = NoteAnimation.keyPrefix + "easel.control.morph"
    nonisolated static let blinkKey = NoteAnimation.keyPrefix + "easel.control.blink"
    nonisolated static let glowName = "parc.easel.control.glow"
    nonisolated static let restingShadowRadius: CGFloat = 2
    nonisolated static let liftedShadowRadius: CGFloat = 8

    static func apply(_ view: NSView, hovered: Bool, pressed: Bool, released: Bool = false,
                      hover: Double = EaselControlMotion.hoverScale, press: Double = EaselControlMotion.pressedScale,
                      casts: Bool = true, shadowPath: CGPath? = nil) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let scale = NoteAnimation.reduceMotion ? 1 : CGFloat(EaselControlMotion.scale(hovered: hovered, pressed: pressed,
                                                                                    hover: hover, press: press))
        let centre = NoteAnimation.layerPoint(NSPoint(x: view.bounds.midX, y: view.bounds.midY), in: view)
        let target = scale == 1 ? CATransform3DIdentity : NoteAnimation.scaleTransform(scale, about: centre)
        NoteAnimation.spring(layer, "transform", to: NSValue(caTransform3D: target), spring: pressed || released ? .press : .highlight,
                             key: scaleKey)
        NoteAnimation.withoutAnimation { layer.zPosition = hovered || pressed ? 2 : 0 }
        guard casts else { return }
        let dark = NoteTheme.isDark(view.effectiveAppearance)
        NoteAnimation.withoutAnimation {
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOffset = CGSize(width: 0, height: view.isFlipped ? 2.5 : -2.5)
            if let shadowPath { layer.shadowPath = shadowPath }
        }
        let lifted = EaselControlMotion.shadowOpacity(hovered: hovered, pressed: pressed, dark: dark)
        animate(layer, "shadowOpacity", to: Float(lifted), key: shadowKey)
        animate(layer, "shadowRadius", to: lifted > 0 ? liftedShadowRadius : restingShadowRadius, key: radiusKey)
    }

    static func rest(_ view: NSView) {
        NoteAnimation.settle(view)
        guard let layer = view.layer else { return }
        NoteAnimation.withoutAnimation {
            layer.transform = CATransform3DIdentity
            layer.shadowOpacity = 0
        }
    }

    private static func animate<Value: BinaryFloatingPoint>(_ layer: CALayer, _ keyPath: String, to value: Value, key: String) {
        let from = (layer.presentation()?.value(forKeyPath: keyPath) as? NSNumber)?.floatValue
            ?? (layer.value(forKeyPath: keyPath) as? NSNumber)?.floatValue ?? 0
        let target = Float(value)
        NoteAnimation.withoutAnimation { layer.setValue(target, forKeyPath: keyPath) }
        guard from != target, layer.superlayer != nil else {
            NoteAnimation.settle(layer, keys: [key])
            return
        }
        let animation = NoteAnimation.reduceMotion
            ? NoteAnimation.basic(keyPath, from: from, to: target, duration: NoteAnimation.reducedFadeDuration)
            : NoteAnimation.spring(keyPath, .highlight, from: from, to: target)
        _ = NoteAnimation.run(animation, on: layer, key: key)
    }

    static func makePill() -> CALayer {
        let pill = CALayer()
        pill.cornerRadius = NoteTheme.controlRadius
        pill.cornerCurve = .continuous
        pill.opacity = 0
        return pill
    }

    static func recolor(_ pill: CALayer, in view: NSView) {
        NoteAnimation.withoutAnimation { pill.backgroundColor = NoteTheme.resolved(NoteTheme.checkedFill, in: view) }
    }

    static func movePill(_ pill: CALayer, to frame: CGRect?, animated: Bool) {
        guard let frame else {
            if animated, pill.opacity > 0 {
                NoteAnimation.fade(pill, to: 0, duration: NoteAnimation.hoverDuration)
            } else {
                NoteAnimation.settle(pill, keys: [NoteAnimation.fadeKey, NoteAnimation.positionKey, NoteAnimation.boundsKey])
                NoteAnimation.withoutAnimation { pill.opacity = 0 }
            }
            return
        }
        if animated, pill.opacity > 0 {
            NoteAnimation.slideLayer(pill, to: frame, spring: .pill)
            return
        }
        NoteAnimation.settle(pill, keys: [NoteAnimation.positionKey, NoteAnimation.boundsKey])
        NoteAnimation.withoutAnimation { pill.frame = frame }
        guard animated else {
            NoteAnimation.settle(pill, keys: [NoteAnimation.fadeKey])
            NoteAnimation.withoutAnimation { pill.opacity = 1 }
            return
        }
        NoteAnimation.fade(pill, to: 1, duration: NoteAnimation.hoverDuration)
        NoteAnimation.pop(pill, from: 0.85, spring: .pill)
    }

    static func makeRing(radius: CGFloat = 8) -> CALayer {
        let ring = CALayer()
        ring.cornerRadius = radius
        ring.cornerCurve = .continuous
        ring.borderWidth = 1.5
        ring.opacity = 0
        return ring
    }

    static func setRing(_ ring: CALayer, in view: NSView, shown: Bool, animated: Bool) {
        NoteAnimation.withoutAnimation {
            ring.frame = view.bounds.insetBy(dx: 0.75, dy: 0.75)
            ring.borderColor = NoteTheme.resolved(NoteTheme.checkedInk, in: view)
        }
        guard animated, view.window != nil else {
            NoteAnimation.settle(ring, keys: [NoteAnimation.fadeKey, NoteAnimation.popKey])
            NoteAnimation.withoutAnimation { ring.opacity = shown ? 1 : 0 }
            return
        }
        if shown {
            NoteAnimation.fade(ring, to: 1, duration: NoteAnimation.hoverDuration)
            NoteAnimation.pop(ring, from: CGFloat(EaselControlMotion.ringHiddenScale), spring: .check)
        } else {
            NoteAnimation.fade(ring, to: 0, duration: NoteAnimation.hoverDuration)
        }
    }

    static func crossfade(_ view: NSView, duration: CFTimeInterval = 0.15, pops: CGFloat? = 0.94) {
        guard let layer = view.layer, view.window != nil else { return }
        let transition = CATransition()
        transition.type = .fade
        transition.duration = duration
        transition.timingFunction = NoteCurve.easeOut
        layer.add(transition, forKey: morphKey)
        guard let pops, !NoteAnimation.reduceMotion else { return }
        NoteAnimation.pop(layer, from: pops, spring: .pill, about: CGPoint(x: view.bounds.midX, y: view.bounds.midY))
    }

    static func morph(_ view: NSView, pops: CGFloat? = 0.94, _ change: () -> Void) {
        change()
        crossfade(view, pops: pops)
    }

    static func shake(_ layer: CALayer, distance: CGFloat = 5, key: String = shakeKey) {
        guard !NoteAnimation.reduceMotion else { return }
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -1, 1, -0.8, 0.8, -0.4, 0.4, 0].map { $0 * distance }
        shake.keyTimes = [0, 0.14, 0.28, 0.42, 0.56, 0.7, 0.85, 1]
        shake.duration = 0.5
        shake.timingFunction = NoteCurve.easeOut
        layer.add(shake, forKey: key)
    }

    static func blink(_ layer: CALayer, resting: Float = 1, key: String = blinkKey) {
        NoteAnimation.withoutAnimation { layer.opacity = resting }
        NoteAnimation.settle(layer, keys: [key])
        guard !NoteAnimation.reduceMotion else { return }
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1, 0.2, 1, 0.2, resting].map { NSNumber(value: $0) }
        blink.keyTimes = [0, 0.2, 0.45, 0.7, 1].map { NSNumber(value: $0) }
        blink.duration = 0.55
        blink.timingFunction = NoteCurve.easeInOut
        _ = NoteAnimation.run(blink, on: layer, key: key)
    }

    static func glow(_ view: NSView, color: NSColor, radius: CGFloat = NoteTheme.controlRadius, around: NSRect? = nil) {
        view.wantsLayer = true
        guard let host = view.layer, view.window != nil else { return }
        let glow = host.sublayers?.first { $0.name == glowName } ?? CALayer()
        glow.name = glowName
        NoteAnimation.withoutAnimation {
            glow.frame = around ?? host.bounds
            glow.cornerRadius = radius
            glow.cornerCurve = .continuous
            glow.backgroundColor = NoteTheme.resolved(color.withAlphaComponent(0.28), in: view)
            glow.shadowColor = NoteTheme.resolved(color, in: view)
            glow.shadowRadius = 9
            glow.shadowOffset = .zero
            glow.shadowOpacity = 0.8
            glow.opacity = 0
            if glow.superlayer == nil { host.insertSublayer(glow, at: 0) }
        }
        let animation: CAAnimation
        if NoteAnimation.reduceMotion {
            let fade = NoteAnimation.basic("opacity", from: 0, to: EaselPulseTrain.peak, duration: NoteAnimation.reducedFadeDuration)
            fade.autoreverses = true
            animation = fade
        } else {
            let pulses = CAKeyframeAnimation(keyPath: "opacity")
            pulses.keyTimes = EaselPulseTrain.keyTimes.map { NSNumber(value: $0) }
            pulses.values = EaselPulseTrain.values.map { NSNumber(value: $0) }
            pulses.duration = EaselPulseTrain.duration
            pulses.timingFunction = NoteCurve.easeInOut
            animation = pulses
        }
        _ = NoteAnimation.run(animation, on: glow, key: glowKey) { [weak glow] _ in glow?.removeFromSuperlayer() }
    }

    static func clearFinish(_ view: NSView, shaking layer: CALayer?) {
        clearGlow(view)
        layer?.removeAnimation(forKey: shakeKey)
    }

    static func clearGlow(_ view: NSView) {
        view.layer?.sublayers?.filter { $0.name == glowName }.forEach { $0.removeAllAnimations(); $0.removeFromSuperlayer() }
    }
}

@MainActor
final class EaselRollingText: NSView {
    private final class Glyph: NSView {
        var character: Character
        var font: NSFont { didSet { if font != oldValue { needsDisplay = true } } }
        var color: NSColor { didSet { if color != oldValue { needsDisplay = true } } }

        init(_ character: Character, font: NSFont, color: NSColor) {
            self.character = character
            self.font = font
            self.color = color
            super.init(frame: .zero)
            wantsLayer = true
            layerContentsRedrawPolicy = .onSetNeedsDisplay
            setAccessibilityElement(false)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

        override func draw(_ dirtyRect: NSRect) {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let text = String(character) as NSString
            let height = text.size(withAttributes: attributes).height
            text.draw(at: NSPoint(x: 0, y: ((bounds.height - height) / 2).rounded()), withAttributes: attributes)
        }
    }

    static let rollKey = NoteAnimation.keyPrefix + "easel.roll"
    static let fadeLength: CFTimeInterval = 0.12

    var alignment: NSTextAlignment = .center { didSet { if alignment != oldValue { needsLayout = true } } }
    var clips = false { didSet { layer?.masksToBounds = clips } }
    private(set) var text = ""
    private var font = NSFont.systemFont(ofSize: 13)
    private var color = NSColor.labelColor
    private var columns: [Glyph] = []
    private var leaving: [(glyph: Glyph, index: Int)] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
        NoteAnimation.observeReduceMotion(self) { [weak self] in self?.settle() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var lineHeight: CGFloat { ceil(font.ascender - font.descender) }

    private func width(of character: Character) -> CGFloat {
        ceil((String(character) as NSString).size(withAttributes: [.font: font]).width)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: text.reduce(0) { $0 + width(of: $1) }, height: lineHeight)
    }

    func update(text next: String, font nextFont: NSFont, color nextColor: NSColor, animated: Bool) {
        let fontChanged = nextFont != font
        font = nextFont
        color = nextColor
        for glyph in columns + leaving.map(\.glyph) { glyph.color = nextColor; glyph.font = nextFont }
        let old = text
        guard next != old || columns.count != next.count else { needsLayout = true; return }
        text = next
        let characters = Array(next)
        guard animated, !fontChanged, window != nil, characters.count == columns.count, !columns.isEmpty else {
            rebuild(characters)
            return
        }
        let direction = EaselDigitRoll.direction(from: old, to: next)
        for index in EaselDigitRoll.changedColumns(from: old, to: next) where columns.indices.contains(index) {
            let outgoing = columns[index]
            let incoming = Glyph(characters[index], font: font, color: color)
            columns[index] = incoming
            addSubview(incoming)
            leaving.append((outgoing, index))
            place(incoming, at: index)
            roll(incoming, direction: direction, entering: true)
            roll(outgoing, direction: direction, entering: false) { [weak self, weak outgoing] in
                guard let self, let outgoing else { return }
                outgoing.removeFromSuperview()
                self.leaving.removeAll { $0.glyph === outgoing }
            }
        }
        needsLayout = true
    }

    private func rebuild(_ characters: [Character]) {
        settle()
        columns.forEach { $0.removeFromSuperview() }
        columns = characters.map { Glyph($0, font: font, color: color) }
        columns.forEach(addSubview)
        needsLayout = true
    }

    func settle() {
        for entry in leaving { entry.glyph.layer.map { NoteAnimation.settle($0) }; entry.glyph.removeFromSuperview() }
        leaving.removeAll()
        for glyph in columns { glyph.layer.map { NoteAnimation.settle($0) } }
    }

    private func roll(_ glyph: Glyph, direction: EaselDigitRoll.Direction, entering: Bool, completion: (() -> Void)? = nil) {
        guard let layer = glyph.layer else { completion?(); return }
        let length = NoteAnimation.reduceMotion ? NoteAnimation.reducedFadeDuration : Self.fadeLength
        let live = layer.animation(forKey: NoteAnimation.fadeKey) != nil || layer.animation(forKey: Self.rollKey) != nil
        let presented = live ? layer.presentation() : nil
        let fromOpacity = presented?.opacity ?? (entering ? 0 : 1)
        let fromShift = presented.flatMap { ($0.value(forKeyPath: "transform.translation.y") as? NSNumber).map { CGFloat($0.floatValue) } }
        NoteAnimation.withoutAnimation { layer.opacity = entering ? 1 : 0 }
        let fade = NoteAnimation.basic("opacity", from: fromOpacity, to: entering ? 1 : 0, duration: length)
        _ = NoteAnimation.run(fade, on: layer, key: NoteAnimation.fadeKey) { _ in completion?() }
        guard !NoteAnimation.reduceMotion else { return }
        let travel = CGFloat(EaselDigitRoll.offsetBelowIsPositive(of: direction, height: Double(lineHeight), entering: entering))
        let roll = entering
            ? NoteAnimation.spring("transform.translation.y", .settle, from: fromShift ?? travel, to: 0)
            : NoteAnimation.basic("transform.translation.y", from: fromShift ?? 0, to: travel, duration: length, curve: NoteCurve.easeOut)
        _ = NoteAnimation.run(roll, on: layer, key: Self.rollKey)
    }

    private func place(_ glyph: Glyph, at index: Int) {
        let widths = text.map(width(of:))
        let total = widths.reduce(0, +)
        var x: CGFloat
        switch alignment {
        case .left, .natural, .justified: x = 0
        case .right: x = bounds.width - total
        default: x = ((bounds.width - total) / 2).rounded()
        }
        for offset in 0..<min(index, widths.count) { x += widths[offset] }
        let width = index < widths.count ? widths[index] : self.width(of: glyph.character)
        glyph.frame = NSRect(x: x, y: ((bounds.height - lineHeight) / 2).rounded(), width: width, height: lineHeight)
    }

    override func layout() {
        super.layout()
        NoteAnimation.withoutAnimation {
            for (index, glyph) in columns.enumerated() { place(glyph, at: index) }
            for entry in leaving { place(entry.glyph, at: entry.index) }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        for glyph in columns { glyph.needsDisplay = true }
    }
}
