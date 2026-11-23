import AppKit

@MainActor
package final class CapturePictureView: NSView {
    package var image: CGImage? {
        didSet { if image !== oldValue { needsDisplay = true } }
    }
    package var onPixelSizeChange: ((CGSize) -> Void)? {
        didSet { reportedPixels = .zero; reportPixelSize() }
    }
    package var keepsRendering = false {
        didSet { if oldValue && !keepsRendering { needsDisplay = true; reportPixelSize() } }
    }
    private var reportedPixels = CGSize.zero
    private var renderedImage: CGImage?

    package override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(true); setAccessibilityRole(.image)
    }
    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    package override var wantsUpdateLayer: Bool { true }
    package override var isOpaque: Bool { false }
    package override func hitTest(_ point: NSPoint) -> NSView? { nil }

    package var pixelSize: CGSize {
        let size = convertToBacking(bounds).size
        return CGSize(width: size.width.rounded(), height: size.height.rounded())
    }

    package override func setFrameSize(_ newSize: NSSize) {
        let before = pixelSize
        super.setFrameSize(newSize)
        if pixelSize != before { needsDisplay = true; reportPixelSize() }
    }

    package override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true; reportPixelSize()
    }

    package override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        needsDisplay = true; reportPixelSize()
    }

    package override func updateLayer() {
        guard let layer else { return }
        layer.contentsGravity = .resize
        if inLiveResize || keepsRendering, layer.contents != nil, let image, renderedImage === image { return }
        renderedImage = image
        layer.contents = image.flatMap { Self.displayed($0, pixels: pixelSize) }
    }

    private func reportPixelSize() {
        let pixels = pixelSize
        guard let onPixelSizeChange, !inLiveResize, !keepsRendering, pixels.width >= 1, pixels.height >= 1, pixels != reportedPixels else { return }
        reportedPixels = pixels
        onPixelSizeChange(pixels)
    }

    package static func displayed(_ image: CGImage, pixels: CGSize) -> CGImage? {
        let width = Int(pixels.width.rounded()), height = Int(pixels.height.rounded())
        guard width > 0, height > 0 else { return nil }
        if image.width == width && image.height == height { return image }
        let space = image.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: image.bitsPerComponent > 8 ? 16 : 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        let native = abs(image.width - width) <= 2 && abs(image.height - height) <= 2
        let fit = min(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
        var drawn = CGSize(width: (CGFloat(image.width) * fit).rounded(), height: (CGFloat(image.height) * fit).rounded())
        if native { drawn = CGSize(width: image.width, height: image.height) }
        else if abs(drawn.width - CGFloat(width)) <= 2 && abs(drawn.height - CGFloat(height)) <= 2 {
            drawn = CGSize(width: width, height: height)
        }
        context.interpolationQuality = native ? .none : .high
        context.draw(image, in: CGRect(x: ((CGFloat(width) - drawn.width) / 2).rounded(.down),
                                       y: ((CGFloat(height) - drawn.height) / 2).rounded(.down),
                                       width: drawn.width, height: drawn.height))
        return context.makeImage() ?? image
    }
}
