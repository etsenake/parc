import AppKit
import ParcCore

enum PageCard {
    nonisolated(unsafe) private(set) static var cornerRadius: CGFloat = 6

    @discardableResult @MainActor static func follow(thickness: CGFloat) -> Bool {
        let next = (WindowFrameThickness.cornerRadius(for: thickness) * 2).rounded() / 2
        guard next != cornerRadius else { return false }
        cornerRadius = next
        return true
    }
}

enum ContentShadowImage {
    static let outset: CGFloat = 10
    static let straight: CGFloat = 9
    static var size: CGFloat { size(radius: PageCard.cornerRadius) }
    static var stretchableCenter: CGRect { stretchableCenter(radius: PageCard.cornerRadius) }
    static func size(radius: CGFloat) -> CGFloat { 2 * (outset + radius + straight) + 1 }
    static func stretchableCenter(radius: CGFloat) -> CGRect {
        let total = size(radius: radius)
        let edge = (outset + radius + straight) / total
        return CGRect(x: edge, y: edge, width: 1 / total, height: 1 / total)
    }
    static func frame(around card: CGRect) -> CGRect { card.insetBy(dx: -outset, dy: -outset) }

    static func image(scale: CGFloat, radius: CGFloat = PageCard.cornerRadius) -> CGImage? {
        let side = Self.size(radius: radius)
        let pixels = Int((side * scale).rounded(.up))
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let interior = cardMask(pixels: pixels, scale: scale, radius: radius) else { return nil }
        context.scaleBy(x: scale, y: scale)
        let canvas = CGRect(x: 0, y: 0, width: side, height: side)
        let card = canvas.insetBy(dx: outset, dy: outset)
        context.setShadow(offset: CGSize(width: side * scale, height: -scale), blur: 6 * scale,
                          color: NSColor.black.withAlphaComponent(0.25).cgColor)
        context.addPath(CGPath(roundedRect: card.offsetBy(dx: -side, dy: 0), cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.clip(to: canvas, mask: interior)
        context.clear(canvas)
        return context.makeImage()
    }

    private static func cardMask(pixels: Int, scale: CGFloat, radius: CGFloat) -> CGImage? {
        let side = Self.size(radius: radius)
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: outset, y: outset)
        let shape = CALayer()
        shape.bounds = CGRect(x: 0, y: 0, width: side - 2 * outset, height: side - 2 * outset)
        shape.backgroundColor = CGColor(gray: 1, alpha: 1)
        shape.cornerRadius = radius
        shape.cornerCurve = .continuous
        shape.render(in: context)
        return context.makeImage()
    }

    private struct Key: Hashable { let scale: CGFloat; let radius: CGFloat }
    private static let radiusKey = "parcCardRadius"
    @MainActor private static var images: [Key: CGImage] = [:]
    @MainActor static func apply(to layer: CALayer, scale: CGFloat, radius: CGFloat = PageCard.cornerRadius) {
        let key = Key(scale: scale, radius: radius)
        if images[key] == nil, images.count >= 24 { images.removeAll() }
        let image = images[key] ?? image(scale: scale, radius: radius)
        images[key] = image
        layer.contents = image
        layer.contentsScale = scale
        layer.contentsCenter = stretchableCenter(radius: radius)
        layer.setValue(radius, forKey: radiusKey)
    }
    @MainActor static func isCurrent(_ layer: CALayer, scale: CGFloat, radius: CGFloat = PageCard.cornerRadius) -> Bool {
        layer.contents != nil && layer.contentsScale == scale && layer.value(forKey: radiusKey) as? CGFloat == radius
    }
}

final class PageCardShadowView: NSView {
    override var wantsUpdateLayer: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    var cornerRadius: CGFloat? { didSet { if cornerRadius != oldValue { needsDisplay = true } } }
    override func updateLayer() {
        guard let layer else { return }
        ContentShadowImage.apply(to: layer, scale: window?.backingScaleFactor ?? 2, radius: cornerRadius ?? PageCard.cornerRadius)
    }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); needsDisplay = true }
    func place(around card: NSRect) { frame = ContentShadowImage.frame(around: card) }
}
