import AppKit
import ParcCore
import QuartzCore
import ParcKit

@MainActor
final class SidebarFolderIconView: NSView {
    package enum State: Equatable { case collapsed, expanded, peekedOpen, peekedClosed }

    private(set) var state: State = .collapsed
    var strokeColor: NSColor = .labelColor { didSet { if strokeColor != oldValue { applyColors() } } }
    var backFillColor: NSColor = .clear { didSet { if backFillColor != oldValue { applyColors() } } }
    var frontFillColor: NSColor = .clear { didSet { if frontFillColor != oldValue { applyColors() } } }

    private let root = CALayer()
    private let back = CAShapeLayer()
    private let backShading = CAGradientLayer()
    private let backShadingMask = CAShapeLayer()
    private let front = CALayer()
    private let frontPath = CAShapeLayer()
    private let frontShading = CAGradientLayer()
    private let frontShadingMask = CAShapeLayer()
    private let ellipsis = CALayer()
    private let ellipsisMask = CALayer()
    private let custom = CALayer()
    private let customMask = CALayer()
    var customIcon: SidebarGroupIcon? { didSet { if customIcon != oldValue { laidOutSize = nil; needsLayout = true } } }
    private var laidOutSize: NSSize?
    private var laidOutScale: CGFloat?

    static let perspective: CGFloat = -0.0029129464302474974

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        root.masksToBounds = false
        layer?.addSublayer(root)
        root.addSublayer(back)
        back.addSublayer(backShading)
        backShading.mask = backShadingMask
        root.addSublayer(front)
        front.addSublayer(frontPath)
        frontPath.addSublayer(frontShading)
        frontShading.mask = frontShadingMask
        front.addSublayer(custom)
        front.addSublayer(ellipsis)
        ellipsisMask.contentsGravity = .center
        customMask.contentsGravity = .resizeAspect
        ellipsis.mask = ellipsisMask
        ellipsis.opacity = 0
        frontShading.masksToBounds = true
        frontShading.colors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(0.15).cgColor]
        frontShading.startPoint = CGPoint(x: 0.1, y: 0); frontShading.endPoint = CGPoint(x: 0.9, y: 1)
        frontShading.locations = [0, 1]
        backShading.colors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(0.36).cgColor]
        backShading.startPoint = .zero; backShading.endPoint = CGPoint(x: 0.6, y: 1)
        backShading.locations = [0, 1]
        for mask in [backShadingMask, frontShadingMask] { mask.fillColor = NSColor.white.cgColor }
        for shape in [back, frontPath] { shape.lineJoin = .round }
        setAccessibilityElement(false)
        applyColors()
        applyState(animated: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setState(_ next: State, animated: Bool) {
        guard next != state else { return }
        state = next
        let animate = animated && window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        applyState(animated: animate)
    }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard laidOutSize != bounds.size || laidOutScale != scale else { return }
        laidOutSize = bounds.size; laidOutScale = scale
        layoutLayers(scale: scale)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        laidOutScale = nil; needsLayout = true
    }

    private func layoutLayers(scale: CGFloat) {
        guard let host = layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        root.frame = host.bounds
        let w = bounds.width, h = bounds.height
        func pixel(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let radius = (w / 7).rounded()
        let lineWidth = (1.25 * scale).rounded() / scale
        let tab = pixel((0.25 * h).rounded())
        let drop = (tab / 1.5).rounded(.down)
        let tabEnd = pixel(0.42 * w), slopeEnd = pixel(0.58 * w)

        func pin(_ layer: CALayer, frame: CGRect) {
            layer.transform = CATransform3DIdentity
            layer.anchorPoint = CGPoint(x: 0, y: 1)
            layer.bounds = CGRect(origin: .zero, size: frame.size)
            layer.position = CGPoint(x: frame.minX, y: frame.maxY)
        }
        let backPath = CGMutablePath()
        backPath.move(to: CGPoint(x: radius, y: 0))
        backPath.addLine(to: CGPoint(x: tabEnd, y: 0))
        backPath.addLine(to: CGPoint(x: slopeEnd, y: drop))
        backPath.addLine(to: CGPoint(x: w - radius, y: drop))
        backPath.addArc(center: CGPoint(x: w - radius, y: radius + drop), radius: radius,
                        startAngle: 1.5 * .pi, endAngle: 0, clockwise: false)
        backPath.addLine(to: CGPoint(x: w, y: h - radius))
        backPath.addArc(center: CGPoint(x: w - radius, y: h - radius), radius: radius,
                        startAngle: 0, endAngle: 0.5 * .pi, clockwise: false)
        backPath.addLine(to: CGPoint(x: radius, y: h))
        backPath.addArc(center: CGPoint(x: radius, y: h - radius), radius: radius,
                        startAngle: 0.5 * .pi, endAngle: .pi, clockwise: false)
        backPath.addLine(to: CGPoint(x: 0, y: radius))
        backPath.addArc(center: CGPoint(x: radius, y: radius), radius: radius,
                        startAngle: .pi, endAngle: 1.5 * .pi, clockwise: false)
        backPath.closeSubpath()
        pin(back, frame: CGRect(x: 0, y: 0, width: w, height: h))
        back.path = backPath; back.lineWidth = lineWidth
        backShading.frame = back.bounds
        backShadingMask.frame = backShading.bounds; backShadingMask.path = backPath

        let flap = CGRect(x: 0, y: tab, width: w, height: max(0, h - tab))
        pin(front, frame: flap)
        let flapPath = CGPath(roundedRect: CGRect(origin: .zero, size: flap.size),
                              cornerWidth: min(radius, flap.width / 2), cornerHeight: min(radius, flap.height / 2), transform: nil)
        frontPath.frame = front.bounds
        frontPath.path = flapPath; frontPath.lineWidth = lineWidth
        frontShading.frame = frontPath.bounds
        frontShadingMask.frame = frontShading.bounds; frontShadingMask.path = flapPath
        let side = min(flap.width, flap.height)
        ellipsis.frame = CGRect(x: (flap.width - side) / 2, y: (flap.height - side) / 2, width: side, height: side)
        ellipsisMask.frame = ellipsis.bounds
        ellipsisMask.contentsScale = scale
        ellipsisMask.contents = Self.ellipsisImage?.layerContents(forContentsScale: scale)
        let iconSide = max(0, min(flap.width, flap.height) - 2.5)
        custom.frame = CGRect(x: (flap.width - iconSide) / 2, y: (flap.height - iconSide) / 2, width: iconSide, height: iconSide)
        customMask.frame = custom.bounds
        let image = customIcon?.image(size: iconSide)
        if case .emoji = customIcon {
            custom.mask = nil; custom.backgroundColor = nil
            custom.contentsGravity = .resizeAspect; custom.contentsScale = scale
            custom.contents = image?.layerContents(forContentsScale: scale)
        } else {
            custom.contents = nil; custom.mask = image == nil ? nil : customMask
            custom.backgroundColor = image == nil ? nil : strokeColor.cgColor(in: effectiveAppearance)
            customMask.contentsScale = scale
            customMask.contents = image?.layerContents(forContentsScale: scale)
        }
        applyState(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); applyColors() }

    private func applyColors() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        back.strokeColor = strokeColor.cgColor(in: effectiveAppearance); back.fillColor = backFillColor.cgColor(in: effectiveAppearance)
        frontPath.strokeColor = strokeColor.cgColor(in: effectiveAppearance); frontPath.fillColor = frontFillColor.cgColor(in: effectiveAppearance)
        ellipsis.backgroundColor = strokeColor.cgColor(in: effectiveAppearance)
        if custom.mask != nil { custom.backgroundColor = strokeColor.cgColor(in: effectiveAppearance) }
    }

    private static let ellipsisImage = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 10, weight: .heavy, scale: .small))

    private func applyState(animated: Bool) {
        let (shift, turn, backTip, frontTip): (CGFloat, CGFloat, CGFloat, CGFloat) = {
            switch state {
            case .collapsed, .peekedClosed: return (0, 0, 0, 0)
            case .expanded: return (3, 32, 28, -30)
            case .peekedOpen: return (1.5, 16, 14, -15)
            }
        }()
        func degrees(_ value: CGFloat) -> CGFloat { value * .pi / 180 }
        var base = CATransform3DIdentity
        base.m34 = Self.perspective
        let turned = CATransform3DRotate(CATransform3DTranslate(base, shift, 0, 0), degrees(turn), 0, 1, 0)
        let open = state == .expanded || state == .peekedOpen
        CATransaction.begin(); CATransaction.setDisableActions(!animated)
        defer { CATransaction.commit() }
        back.transform = CATransform3DRotate(turned, degrees(backTip), 1, 0, 0)
        front.transform = CATransform3DRotate(turned, degrees(frontTip), 1, 0, 0)
        frontShading.opacity = open ? 1 : 0
        backShading.opacity = open ? 1 : 0.2
        let peeked = state == .peekedOpen || state == .peekedClosed
        ellipsis.opacity = peeked ? 1 : 0
        custom.opacity = peeked ? 0 : 1
    }
}
