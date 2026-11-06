import AppKit

///
/// card's six-point continuous corner, shared by the page host, divided panes
/// and their shadows.
enum PageCard {
    static let cornerRadius: CGFloat = 6
}

///
///
/// down, outside the rounded card only. Parc draws it once as a stretchable
/// image with the interior cleared, so a resize never re-rasterizes a blur.
enum ContentShadowImage {
    static let outset: CGFloat = 10
    /// Straight edge kept beside each corner so the stretched middle carries
    /// a long edge's full blur.
    static let straight: CGFloat = 9
    static var size: CGFloat { 2 * (outset + PageCard.cornerRadius + straight) + 1 }
    static var stretchableCenter: CGRect {
        let edge = (outset + PageCard.cornerRadius + straight) / size
        return CGRect(x: edge, y: edge, width: 1 / size, height: 1 / size)
    }
    static func frame(around card: CGRect) -> CGRect { card.insetBy(dx: -outset, dy: -outset) }

    static func image(scale: CGFloat) -> CGImage? {
        let pixels = Int((size * scale).rounded(.up))
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let interior = cardMask(pixels: pixels, scale: scale) else { return nil }
        context.scaleBy(x: scale, y: scale)
        let canvas = CGRect(x: 0, y: 0, width: size, height: size)
        let card = canvas.insetBy(dx: outset, dy: outset)
        let radius = PageCard.cornerRadius
        // The shape sits one canvas to the left, so only its shadow lands here.
        // Shadow geometry is in device pixels and unflipped (negative falls
        // downward); Core Animation's radius 3 is a Core Graphics blur of 6.
        context.setShadow(offset: CGSize(width: size * scale, height: -scale), blur: 6 * scale,
                          color: NSColor.black.withAlphaComponent(0.25).cgColor)
        context.addPath(CGPath(roundedRect: card.offsetBy(dx: -size, dy: 0), cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.clip(to: canvas, mask: interior)
        context.clear(canvas)
        return context.makeImage()
    }

    /// The card's own continuous-corner shape, drawn by Core Animation.
    private static func cardMask(pixels: Int, scale: CGFloat) -> CGImage? {
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: outset, y: outset)
        let shape = CALayer()
        shape.bounds = CGRect(x: 0, y: 0, width: size - 2 * outset, height: size - 2 * outset)
        shape.backgroundColor = CGColor(gray: 1, alpha: 1)
        shape.cornerRadius = PageCard.cornerRadius
        shape.cornerCurve = .continuous
        shape.render(in: context)
        return context.makeImage()
    }

    @MainActor private static var images: [CGFloat: CGImage] = [:]
    @MainActor static func apply(to layer: CALayer, scale: CGFloat) {
        let image = images[scale] ?? image(scale: scale)
        images[scale] = image
        layer.contents = image
        layer.contentsScale = scale
        layer.contentsCenter = stretchableCenter
    }
}

/// The shadow of the window's lone page card. The page host clips that card
/// and its edge moves with the host inside ⌘S, so the shadow is the host's
/// sibling below it and takes the same frame motion. It has no input and no
/// accessibility.
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
    override func updateLayer() {
        guard let layer else { return }
        ContentShadowImage.apply(to: layer, scale: window?.backingScaleFactor ?? 2)
    }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); needsDisplay = true }
    func place(around card: NSRect) { frame = ContentShadowImage.frame(around: card) }
}
